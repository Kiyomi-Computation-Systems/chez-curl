;; timing.sps: the timings tests/test-http-client.sps's comments cite, on a
;; fresh origin. Prints (bound WHICH (HTTP-TIMEOUT? CURL-TIMEOUT?) MS) for
;; each of the suite's three bound calls, timeout-ms 400 against a 3 s drip:
;; the call's, the session's, and the call's with connect-timeout-ms 100; MS
;; from before the call to after its raise. Then (escape escaped AT
;; ended-after MS): a call awaiting a 10 s drip escaped by a timer's handler
;; AT ms in, as the suite's escape-await does, and MS from the escape until
;; no transfer is live.
(import (chezscheme) (curl-testing) (curl) (http-client) (curl private counters))
(define (now-ms) (let ((t (current-time 'time-monotonic))) (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))
(define (count-of kind) (cdr (assq kind (native-counts))))
(call-with-origin
 (lambda (o)
   (define (url-of face path)
     (let ((f (origin-face o face))) (string-append "http://" (car f) ":" (number->string (cdr f)) path)))
   (define drip (url-of 'raw "/raw/pause-mid-body?ms=3000"))
   (for-each
    (lambda (where)
      (let ((own (apply make-http-session (cadr where))))
        (let* ((start (now-ms))
               (a (guard (e (#t (list (http-timeout? e) (curl-timeout? e)))) (apply http-get own drip (caddr where))))
               (took (- (now-ms) start)))
          (http-session-close own)
          (write (list 'bound (car where) a took)) (newline))))
    (list (list 'call '(timeout-ms 20000) '(timeout-ms 400))
          (list 'session '(timeout-ms 400) '())
          (list 'connect '(timeout-ms 20000) '(timeout-ms 400 connect-timeout-ms 100))))
   ;; escape to ended
   (let* ((own (make-http-session 'timeout-ms 30000))
          (t0 (now-ms))
          (escaped-at #f)
          (how (call/cc (lambda (k)
                 (timer-interrupt-handler (lambda () (if (and (>= (- (now-ms) t0) 200) (= (count-of 'transfer) 1)) (begin (set! escaped-at (now-ms)) (k 'escaped)) (set-timer 200))))
                 (set-timer 200)
                 (http-get own (url-of 'raw "/raw/pause-mid-body?ms=10000"))
                 'returned))))
     (set-timer 0)
     (let loop () (unless (= (count-of 'transfer) 0) (sleep (make-time 'time-duration 1000000 0)) (loop)))
     (write (list 'escape how (- escaped-at t0) 'ended-after (- (now-ms) escaped-at))) (newline)
     (http-session-close own))))
