;;; Does an engine's queued count still hold a token cancelled while queued?
;;; The engine is held while a request is submitted and cancelled, so the
;;; token is queued at its cancel; then the counts are read at once, and
;;; every 50 ms until the queued count reads 0.
(import (chezscheme) (curl)
        (only (curl private engine) call-with-engine-held curl-engine-queued-count curl-engine-live-count))
(define (now-ms) (let ((t (current-time 'time-monotonic))) (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))
(define e (make-curl-engine))
(sleep (make-time 'time-duration 0 1))
(define r (make-curl-request "http://127.0.0.1:1/x" 'proxy #f))
(define token
  (call-with-engine-held e
    (lambda ()
      (let ((t (curl-submit e r)))
        (curl-token-cancel t)
        t))))
(define t0 (now-ms))
(printf "done? ~a queued ~a live ~a~%" (curl-token-done? token) (curl-engine-queued-count e) (curl-engine-live-count e))
(let loop ()
  (let ((q (curl-engine-queued-count e)))
    (if (and (> q 0) (< (- (now-ms) t0) 3000))
        (begin (sleep (make-time 'time-duration 50000000 0)) (loop))
        (printf "queued ~a after ~a ms~%" q (- (now-ms) t0)))))
(curl-engine-stop e)
