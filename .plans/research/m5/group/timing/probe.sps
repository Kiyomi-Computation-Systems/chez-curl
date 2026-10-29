;;; test-group's 20-call timing, printed: 20 calls of /raw/hold ms=500 in
;;; one group on one session, with no limit and at a limit of 2, RUNS
;;; times, through (http-client) as the suite makes them. Each line: the
;;; limit, the ms from before the first go to the group's return, the 200s,
;;; and the origin's most held at once.
;;;   scheme --libdirs src:tests:build/scheme-libs --program probe.sps RUNS
(import (chezscheme) (curl) (http-client) (curl-testing))
(define runs (string->number (car (command-line-arguments))))
(define (now-ms) (let ((t (current-time 'time-monotonic))) (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))
(call-with-origin
 (lambda (o)
   (define (raw path) (let ((f (origin-face o 'raw))) (string-append "http://" (car f) ":" (number->string (cdr f)) path)))
   (define (twenty key limit)
     (let ((s (make-http-session 'timeout-ms 30000)))
       (let* ((t0 (now-ms))
              (oks (apply call-with-request-group s
                          (append (if limit (list 'limit limit) '())
                                  (list (lambda (go)
                                          (let ((ps (let loop ((i 0) (made '()))
                                                      (if (= i 20) (reverse made)
                                                          (loop (+ i 1) (cons (go 'get (raw (string-append "/raw/hold?key=" key "&ms=500"))) made))))))
                                            (let loop ((ps ps) (n 0))
                                              (if (null? ps) n
                                                  (loop (cdr ps) (if (= 200 (http-response-status (http-await (car ps)))) (+ n 1) n))))))))))
              (took (- (now-ms) t0))
              (most (let ((m (make-http-session 'timeout-ms 5000)))
                      (let ((r (http-get m (raw (string-append "/raw/most?key=" key)))))
                        (http-session-close m)
                        (utf8->string (http-response-body r))))))
         (http-session-close s)
         (printf "limit=~a ms=~a ok=~a ~a" limit took oks most))))
   (do ((i 1 (+ i 1))) ((> i runs))
     (twenty (format "t~a-all" i) #f)
     (twenty (format "t~a-two" i) 2))))
