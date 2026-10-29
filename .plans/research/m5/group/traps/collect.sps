;;; collect and collect-rendezvous while another thread sleeps inside a
;;; critical section, holding a mutex (as call-with-engine-held's thunk can).
(import (chezscheme))
(define (now-ms) (let ((t (current-time 'time-monotonic))) (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))
(define (holder)
  (let ((lock (make-mutex)) (flag #f))
    (fork-thread (lambda ()
                   (critical-section
                    (with-mutex lock (set! flag #t))
                    (sleep (make-time 'time-duration 0 2)))))
    (let loop () (unless (with-mutex lock flag) (sleep (make-time 'time-duration 1000000 0)) (loop)))))
(holder)
(printf "collect: ~a~%" (guard (e (#t (condition-message e))) (collect) 'returned))
(sleep (make-time 'time-duration 0 3))
(holder)
(let ((t0 (now-ms)))
  (printf "collect-rendezvous: ~a after ~a ms~%" (guard (e (#t (condition-message e))) (collect-rendezvous) 'returned) (- (now-ms) t0)))
