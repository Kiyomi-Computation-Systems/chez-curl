;;; M6 slice 1, item 6 (2026-10-30): a stream's throughput (the M6 plan,
;;; section 4.1): 64 MiB through the write callable and a Scheme consumer
;;; of curl-token-next-piece.
;;;
;;;   scheme --libdirs build/m6s1/src --program throughput.sps HTTP RAW HTTPS H2 PROXY CA RUNS
;;;
;;; Each run, on the http, https and h2 faces, at stream-buffer 65,536 and
;;; 1,048,576, on an engine of its own: /body?n=67108864&chunk=65536, byte i
;;; being i mod 251; every piece taken by curl-token-next-piece, a bound of
;;; 60 s each, and every byte checked against its pattern, in order. Each
;;; line: the wall time from the submit to the end, by the monotonic clock,
;;; read where the end is first seen; the bytes, whole or not, the first bad
;;; offset or ok; the pieces; the write callable's pauses, the engine's
;;; resumes and those passed over; the most the token held; the engine's
;;; polls that began with a message queued, the longest, and those of 100 ms
;;; or more; and the outcome.
(import (chezscheme)
        (curl private engine)
        (curl private transfer)
        (curl private conditions)
        (curl private native)
        (curl private libcurl-info))

(define args (command-line-arguments))
(define faces (map cons '(http raw https h2 proxy) (list-head args 5)))
(define ca (list-ref args 5))
(define runs (string->number (list-ref args 6)))

(define (say fmt . xs) (apply printf fmt xs) (newline) (flush-output-port (current-output-port)))
(define (ns-of t) (+ (* (time-second t) 1000000000) (time-nanosecond t)))
(define (now-ns) (ns-of (current-time 'time-monotonic)))
(define (ms x) (/ (round (/ x 1000)) 1000.0))

(define (url face path)
  (string-append (if (memq face '(https h2)) "https://" "http://") (cdr (assq face faces)) path))

(define (request face path)
  (let ((r (make-curl-request (url face path) 'proxy #f 'timeout-ms 600000)))
    (if (memq face '(https h2)) (curl-request-with r 'ca-file ca) r)))

(define (bad-at piece at)
  (let ((n (bytevector-length piece)))
    (let loop ((i 0) (v (mod at 251)))
      (cond ((= i n) #f)
            ((fx= (bytevector-u8-ref piece i) v) (loop (fx+ i 1) (if (fx= v 250) 0 (fx+ v 1))))
            (else (+ at i))))))

(define (stat token key) (cdr (assq key (curl-token-stream-stats token))))
(define (probe engine key) (cdr (assq key (curl-engine-probe engine))))

(define (outcome-text token)
  (let ((o (curl-token-outcome token)))
    (cond ((curl-response? o) (format "status=~a version=~a" (curl-response-status o) (curl-response-http-version o)))
          ((curl-transfer-error? o)
           (format "failed reason=~a code=~a" (curl-transfer-error-reason o) (curl-transfer-error-code o)))
          (else (format "other ~s" o)))))

;; one : Natural Symbol Natural -> Void
(define (one r face size)
  (let* ((engine (make-curl-engine))
         (n 67108864)
         (t0 (now-ns))
         (token (curl-submit engine (curl-request-with-stream-buffer
                                     (request face (format "/body?n=~a&chunk=65536" n)) size))))
    (let loop ((at 0) (pieces 0) (bad #f))
      (let ((piece (curl-token-next-piece token 60000)))
        (if (bytevector? piece)
            (loop (+ at (bytevector-length piece)) (+ pieces 1) (or bad (bad-at piece at)))
            (let ((t1 (now-ns)))
              (curl-token-wait token 10000)
              (say "throughput run=~a face=~a stream-buffer=~a wall-ms=~a bytes=~a whole=~a pattern=~a end=~a pieces=~a pauses=~a resumes=~a passed-over=~a max-buffered=~a queued-polls=~a queued-poll-max-ms=~a queued-polls-100ms=~a ~a"
                   r face size (ms (- t1 t0)) at (= at n) (or bad "ok") (if (eof-object? piece) "eof" piece) pieces
                   (stat token 'pauses)
                   (length (filter (lambda (e) (eq? (car e) 'resume)) (probe engine 'events)))
                   (probe engine 'passed-over) (stat token 'max-buffered)
                   (probe engine 'queued-polls) (ms (probe engine 'queued-poll-max-ns))
                   (probe engine 'queued-polls-100ms) (outcome-text token))))))
    (curl-engine-stop engine)))

(say "libcurl ~a ~a" (libcurl-info-version (loaded-libcurl)) (libcurl-info-ssl-version (loaded-libcurl)))
(do ((r 1 (+ r 1))) ((> r runs))
  (for-each (lambda (face)
              (for-each (lambda (size) (one r face size)) '(65536 1048576)))
            '(http https h2)))
(say "throughput done")
