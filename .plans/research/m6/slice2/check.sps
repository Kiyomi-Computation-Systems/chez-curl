;;; M6 slice 2, the prototype's check (2026-10-30): each method's framing,
;;; sized and chunked, the body whole by its hash at the server, over every
;;; face (the M6 plan, sections 3.3 and 5.2's first item).
;;;
;;;   scheme --libdirs build/m6s2/src --program check.sps HTTP RAW HTTPS H2 CA RUNS
;;;
;;; Each case on an engine of its own: post, put, patch and delete of
;;; 262,144 bytes, byte i being i mod 251, to /sink?want=262144, sized
;;; (body-length 262,144) and chunked (#f), on the http, raw, https and h2
;;; faces. The producer waits for room-wait's #t, then puts 16 KiB pieces,
;;; each waiting while the buffer is full, then ends the body. Each line:
;;; the outcome, the server's sink line (method, Content-Length,
;;; Transfer-Encoding, Expect, Content-Type, bytes, SHA-256 against
;;; want=262144, the pattern), the read callable's calls, pauses and
;;; resumes, and the prerequest and seek calls.
(import (chezscheme)
        (curl private engine)
        (curl private transfer)
        (curl private conditions)
        (curl private native)
        (curl private libcurl-info))

(define args (command-line-arguments))
(define faces (map cons '(http raw https h2) (list-head args 4)))
(define ca (list-ref args 4))
(define runs (string->number (list-ref args 5)))

(define (say fmt . xs) (apply printf fmt xs) (newline) (flush-output-port (current-output-port)))
(define (ns-of t) (+ (* (time-second t) 1000000000) (time-nanosecond t)))
(define (now-ns) (ns-of (current-time 'time-monotonic)))
(define (ms x) (/ (round (/ x 1000)) 1000.0))

(define (url face path tag)
  (string-append (if (memq face '(https h2)) "https://" "http://") (cdr (assq face faces)) path
                 (if (memv #\? (string->list path)) "&" "?") "tag=" tag))

(define (request face method path tag timeout)
  (let ((r (make-curl-request (url face path tag) 'method method 'proxy #f 'timeout-ms timeout)))
    (if (memq face '(https h2)) (curl-request-with r 'ca-file ca) r)))

(define (pattern-piece at n)
  (let ((bv (make-bytevector n)))
    (let loop ((i 0) (v (mod at 251)))
      (when (< i n) (bytevector-u8-set! bv i v) (loop (+ i 1) (if (= v 250) 0 (+ v 1)))))
    bv))

(define (split-lines s)
  (let loop ((cs (string->list s)) (cur '()) (acc '()))
    (cond ((null? cs) (reverse (if (null? cur) acc (cons (list->string (reverse cur)) acc))))
          ((char=? (car cs) #\newline) (loop (cdr cs) '() (cons (list->string (reverse cur)) acc)))
          (else (loop (cdr cs) (cons (car cs) cur) acc)))))

(define (outcome-text o)
  (cond ((curl-response? o) (format "status=~a version=~a" (curl-response-status o) (curl-response-http-version o)))
        ((curl-transfer-error? o)
         (format "failed reason=~a code=~a request-size=~a error=~s" (curl-transfer-error-reason o)
                 (curl-transfer-error-code o) (curl-transfer-error-request-size o)
                 (curl-transfer-error-error-buffer o)))
        ((curl-engine-error? o) (format "engine ~a" (curl-engine-error-reason o)))
        ((not o) "not-done")
        (else (format "other ~s" o))))

(define log-engine (make-curl-engine))
(define (server-log tag)
  (let* ((t (curl-submit log-engine
                         (make-curl-request (string-append "http://" (cdr (assq 'raw faces)) "/log?tag=" tag)
                                            'proxy #f 'timeout-ms 10000)))
         (o (begin (curl-token-wait t 15000) (curl-token-outcome t))))
    (if (curl-response? o)
        (split-lines (utf8->string (curl-response-body o)))
        (list (format "log fetch failed: ~a" (outcome-text o))))))

(define (stat token key) (cdr (assq key (curl-token-upload-stats token))))

;; one : Natural Symbol Symbol Symbol -> Void
(define (one r face method framing)
  (let* ((n 262144)
         (tag (format "check.~a.~a.~a.r~a" face method framing r))
         (engine (make-curl-engine))
         (t0 (now-ns))
         (token (curl-submit engine (curl-request-with-body-stream
                                     (request face method "/sink?want=262144&arr=0" tag 30000)
                                     (if (eq? framing 'sized) n #f))))
         (first (curl-token-room-wait token 10000)))
    (let loop ((at 0) (answers '()))
      (if (< at n)
          (let ((a (curl-token-put-piece! token (pattern-piece at 16384) 10000)))
            (if (eq? a #t) (loop (+ at 16384) answers) (loop n (cons a answers))))
          (begin
            (curl-token-end-body! token)
            (curl-token-wait token 30000)
            (let ((t1 (now-ns)) (o (curl-token-outcome token)))
              (say "check run=~a face=~a method=~a framing=~a room-wait=~a puts-refused=~a ms=~a ~a committed=~a handed=~a reads=~a pauses=~a resumes=~a attempts=~a seeks=~a reads-in-pause=~a"
                   r face method framing first answers (ms (- t1 t0)) (outcome-text o)
                   (stat token 'committed) (stat token 'handed) (stat token 'reads) (stat token 'pauses)
                   (stat token 'resumes) (stat token 'attempts) (stat token 'seeks) (stat token 'reads-in-pause))
              (for-each (lambda (line) (unless (string=? line "") (say "check run=~a face=~a method=~a framing=~a server: ~a" r face method framing line)))
                        (server-log tag))))))
    (curl-engine-stop engine)))

(say "libcurl ~a ~a" (libcurl-info-version (loaded-libcurl)) (libcurl-info-ssl-version (loaded-libcurl)))
(do ((r 1 (+ r 1))) ((> r runs))
  (for-each (lambda (face)
              (for-each (lambda (method)
                          (for-each (lambda (framing) (one r face method framing)) '(sized chunked)))
                        '(post put patch delete)))
            '(http raw https h2)))
(curl-engine-stop log-engine)
(say "check done")
