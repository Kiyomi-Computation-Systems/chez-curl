;;; M6 slice 2, item 4 (2026-10-30): the read callable's offers (the M6
;;; plan, sections 3.3 and 5.1): each call's offered size, libcurl's room,
;;; and what it gave.
;;;
;;;   scheme --libdirs build/m6s2/src --program offers.sps HTTP RAW HTTPS H2 CA RUNS
;;;
;;; Each case on an engine of its own: a streamed post of 1 MiB, byte i
;;; being i mod 251, to /sink?want=1048576, sized and chunked, on the http,
;;; raw, https and h2 faces, its pieces put as fast as the buffer takes them,
;;; 16 KiB (fast16k) or 64 KiB (fast64k) a put; and slow, 1 KiB every 2 ms,
;;; so the buffer is mostly empty and the read gives what one put left.
;;; Each line: the outcome, the server's bytes and hash, the calls, the
;;; distinct rooms offered, each with its count, the largest answer, and
;;; every call in order, (ROOM:ANSWER), runs of one collapsed as xN.
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
(define (sleep-ms n) (when (> n 0) (sleep (make-time 'time-duration (* (mod n 1000) 1000000) (div n 1000)))))

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

;; rle : (Listof String) -> String
(define (rle items)
  (let loop ((rest items) (acc '()))
    (if (null? rest)
        (apply string-append (map (lambda (s) (string-append s " ")) (reverse acc)))
        (let count ((k 1) (more (cdr rest)))
          (if (and (pair? more) (string=? (car more) (car rest)))
              (count (+ k 1) (cdr more))
              (loop more (cons (if (= k 1) (car rest) (format "~ax~a" (car rest) k)) acc)))))))

;; tally : (Listof Natural) -> (Listof (Pairof Natural Natural))
(define (tally xs)
  (let loop ((xs (list-sort < xs)) (acc '()))
    (cond ((null? xs) (reverse acc))
          ((and (pair? acc) (= (caar acc) (car xs))) (loop (cdr xs) (cons (cons (car xs) (+ 1 (cdar acc))) (cdr acc))))
          (else (loop (cdr xs) (cons (cons (car xs) 1) acc))))))

;; one : Natural Symbol Symbol Symbol -> Void
(define (one r face framing pace)
  (let* ((n 1048576)
         (label (format "offers run=~a face=~a framing=~a pace=~a" r face framing pace))
         (tag (format "offers.~a.~a.~a.r~a" face framing pace r))
         (engine (make-curl-engine))
         (token (curl-submit engine (curl-request-with-body-stream
                                     (request face 'post (format "/sink?want=~a&arr=0" n) tag 30000)
                                     (if (eq? framing 'sized) n #f))))
         (asked (curl-token-room-wait token 10000))
         (k (case pace ((fast16k) 16384) ((fast64k) 65536) (else 1024))))
    (let loop ((at 0))
      (when (< at n)
        (when (eq? #t (curl-token-put-piece! token (pattern-piece at k) 5000))
          (when (eq? pace 'slow) (sleep-ms 2))
          (loop (+ at k)))))
    (curl-token-end-body! token)
    (curl-token-wait token 30000)
    (let* ((reads (filter (lambda (e) (eq? (car e) 'read)) (curl-token-upload-events token)))
           (rooms (map caddr reads))
           (answers (map (lambda (e) (list-ref e 4)) reads))
           (gave (filter number? answers))
           (sink (find (lambda (line) (and (> (string-length line) 4) (string=? (substring line 0 4) "sink")))
                       (server-log tag))))
      (say "~a asked=~a ~a calls=~a gave-bytes=~a max-answer=~a pauses=~a rooms=~s"
           label asked (outcome-text (curl-token-outcome token)) (length reads) (apply + gave)
           (if (null? gave) 0 (apply max gave)) (stat token 'pauses) (tally rooms))
      (say "~a server: ~a" label sink)
      (say "~a calls: ~a" label
           (rle (map (lambda (e) (format "~a:~a" (caddr e) (list-ref e 4))) reads))))
    (curl-engine-stop engine)))

(say "libcurl ~a ~a" (libcurl-info-version (loaded-libcurl)) (libcurl-info-ssl-version (loaded-libcurl)))
(do ((r 1 (+ r 1))) ((> r runs))
  (for-each (lambda (face)
              (for-each (lambda (framing)
                          (for-each (lambda (pace) (one r face framing pace)) '(fast16k fast64k slow)))
                        '(sized chunked)))
            '(http raw https h2)))
(curl-engine-stop log-engine)
(say "offers done")
