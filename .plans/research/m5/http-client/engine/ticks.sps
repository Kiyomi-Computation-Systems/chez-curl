;; ticks.sps: how many of a Chez engine's ticks a call spends. Prints (drip
;; MS ticks-used N) for a call on a drip pausing MS ms, three times each,
;; run with fuel enough to complete; then (fuel F (expired-at MS live L)):
;; with fuel F, how many ms into a 10 s drip the engine expires, and how
;; many transfers are live then.
(import (chezscheme) (curl-testing) (curl) (http-client) (curl private counters))
(define (show . xs) (write xs) (newline) (flush-output-port (current-output-port)))
(define (count-of k) (cdr (assq k (native-counts))))
(define (now-ms) (let ((t (current-time 'time-monotonic))) (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))
(call-with-origin
 (lambda (o)
   (define f (origin-face o 'raw))
   (define (drip ms) (string-append "http://" (car f) ":" (number->string (cdr f)) "/raw/pause-mid-body?ms=" (number->string ms)))
   (define big 1000000000)
   (for-each
    (lambda (ms)
      (let loop ((i 0))
        (when (< i 3)
          (let* ((own (make-http-session 'timeout-ms 30000))
                 (eng (make-engine (lambda () (http-get own (drip ms)) 'done)))
                 (left (eng big (lambda (ticks v) ticks) (lambda (next) 'expired))))
            (http-session-close own)
            (show 'drip ms 'ticks-used (- big left)))
          (loop (+ i 1)))))
    '(1 100 300 1000))
   ;; with fuel F, when does the expiry land, and is the transfer live then?
   (for-each
    (lambda (fuel)
      (let loop ((i 0))
        (when (< i 3)
          (let* ((own (make-http-session 'timeout-ms 30000))
                 (t0 (now-ms))
                 (eng (make-engine (lambda () (guard (e (#t 'raised)) (http-get own (drip 10000))) 'done)))
                 (r (eng fuel (lambda (ticks v) (list 'completed (- (now-ms) t0)))
                         (lambda (next) (list 'expired-at (- (now-ms) t0) 'live (count-of 'transfer))))))
            (http-session-close own)
            (show 'fuel fuel r))
          (loop (+ i 1)))))
    '(20000 50000 100000))))
