;;; M6 slice 2, item 6 (2026-10-30): upload throughput, to set the suite's
;;; bounds (the M6 plan, section 5.2).
;;;
;;;   scheme --libdirs build/m6s2/src --program throughput.sps HTTP RAW HTTPS H2 CA RUNS
;;;
;;; Each run, on the http, https and h2 faces, sized and chunked, on an
;;; engine of its own: a streamed post of 64 MiB, byte i being i mod 251, to
;;; /sink?want=67108864, through curl-token-put-piece! in 64 KiB pieces,
;;; each with no bound, after room-wait's #t, then the end. Each piece is
;;; cut from one buffer of the pattern, so making it costs a copy. Each
;;; line: the wall time from the submit to the token's completion, by the
;;; engine's clock (done-ms) and the time the last put returned (puts-ms);
;;; the outcome; the read callable's calls, pauses and resumes; the puts
;;; that found the buffer full; the most it held; and the server's sink
;;; line, whose want_sha=ok says the body arrived whole, by SHA-256.
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

;; The pattern, 64 KiB and 251 bytes more, so each piece is one cut.
(define piece-size 65536)
(define big
  (let ((bv (make-bytevector (+ piece-size 251))))
    (do ((i 0 (+ i 1))) ((= i (bytevector-length bv)) bv) (bytevector-u8-set! bv i (mod i 251)))))
(define (piece-at at)
  (let ((bv (make-bytevector piece-size)))
    (bytevector-copy! big (mod at 251) bv 0 piece-size)
    bv))

;; one : Natural Symbol Symbol -> Void
(define (one r face framing)
  (let* ((n 67108864)
         (label (format "throughput run=~a face=~a framing=~a" r face framing))
         (tag (format "throughput.~a.~a.r~a" face framing r))
         (engine (make-curl-engine))
         (t0 (now-ns))
         (token (curl-submit engine (curl-request-with-body-stream
                                     (request face 'post (format "/sink?want=~a&arr=0" n) tag 900000)
                                     (if (eq? framing 'sized) n #f))))
         (asked (curl-token-room-wait token 30000)))
    (let loop ((at 0))
      (when (< at n)
        (when (eq? #t (curl-token-put-piece! token (piece-at at)))
          (loop (+ at piece-size)))))
    (let ((puts (now-ns)))
      (curl-token-end-body! token)
      (curl-token-wait token 900000)
      (let ((sink (find (lambda (line) (and (> (string-length line) 4) (string=? (substring line 0 4) "sink")))
                        (server-log tag)))
            (d (stat token 'done-ns)))
        (say "~a asked=~a done-ms=~a puts-ms=~a ~a committed=~a handed=~a reads=~a pauses=~a resumes=~a fulls=~a most=~a"
             label asked (and (> d 0) (ms (- d t0))) (ms (- puts t0)) (outcome-text (curl-token-outcome token))
             (stat token 'committed) (stat token 'handed) (stat token 'reads) (stat token 'pauses)
             (stat token 'resumes) (stat token 'fulls) (stat token 'most))
        (say "~a server: ~a" label (or sink "none"))))
    (curl-engine-stop engine)))

(say "libcurl ~a ~a" (libcurl-info-version (loaded-libcurl)) (libcurl-info-ssl-version (loaded-libcurl)))
(do ((r 1 (+ r 1))) ((> r runs))
  (for-each (lambda (face)
              (for-each (lambda (framing) (one r face framing)) '(sized chunked)))
            '(http https h2)))
(curl-engine-stop log-engine)
(say "throughput done")
