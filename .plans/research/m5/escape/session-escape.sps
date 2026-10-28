;; A second escape landing in call-with-http-session's after thunk: is the
;; engine left running? Sweeps the second timer's ticks N.
(import (chezscheme) (curl) (http-client) (curl private counters))
(define (count-of kind) (cdr (assq kind (native-counts))))
(define (attempt n)
  (let* ((phase 'first)
         (result
          (call/cc
           (lambda (k2)
             (let ((how (call/cc
                         (lambda (k1)
                           (timer-interrupt-handler
                            (lambda ()
                              (case phase
                                ((first) (set! phase 'second) (set-timer n) (k1 'escaped))
                                ((second) (set! phase 'done) (k2 'escaped-twice))
                                (else #f))))
                           (call-with-http-session
                            (lambda (s) (set-timer 50) (let loop () (loop))))))))
               (set-timer 0)
               how)))))
    (set-timer 0)
    (set! phase 'done)
    (sleep (make-time 'time-duration 200000000 0))
    (list n result (count-of 'multi))))
(let loop ((n 1))
  (when (<= n 40)
    (let ((r (attempt n)))
      (write r) (newline) (flush-output-port)
      (loop (+ n 1)))))
