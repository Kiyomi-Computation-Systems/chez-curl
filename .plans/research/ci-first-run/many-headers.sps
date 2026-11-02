;;; The CI-fix PR (2026-11-01): how long a GET of /raw/many-headers takes,
;;; by count, on the libcurl loaded: the floor lane's 100,000 once outlasted
;;; test-transfer's await bound of 60,000 ms on the runner.
;;;   many-headers.sps RUNS COUNT...
(import (chezscheme) (curl) (curl-testing))

(define args (command-line-arguments))
(define runs (string->number (car args)))
(define counts (map string->number (cdr args)))

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))
(define (cpu-ms)
  (let ((t (current-time 'time-process)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

(define engine (make-curl-engine))
(printf "libcurl ~a~%" (libcurl-info-version (loaded-libcurl)))

(call-with-origin
 (lambda (o)
   (let ((f (origin-face o 'raw)))
     (for-each
      (lambda (count)
        (do ((i 0 (+ i 1))) ((= i runs))
          (let* ((url (format "http://~a:~a/raw/many-headers?count=~a" (car f) (cdr f) count))
                 (t0 (now-ms)) (c0 (cpu-ms))
                 (t (curl-submit engine (make-curl-request url 'proxy #f 'timeout-ms 120000))))
            (curl-token-wait t 130000)
            (let ((out (curl-token-outcome t)))
              (printf "count ~a run ~a ms ~a cpu-ms ~a outcome ~a~%" count i (- (now-ms) t0) (- (cpu-ms) c0)
                      (cond ((curl-response? out) (list 'response (curl-response-status out) (length (curl-response-headers out))))
                            ((curl-transfer-error? out) (list 'failed (curl-transfer-error-code out)))
                            (else out)))))))
      counts))))
(curl-engine-stop engine)
