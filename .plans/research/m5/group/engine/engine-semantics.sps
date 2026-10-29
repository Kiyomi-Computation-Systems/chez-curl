;;; Review 3 probe: Chez's engine semantics the round's fix rests on.
;;; 1. Does engine-block inside a critical-section block at once, or once the
;;;    section ends?  2. Does a dynamic-wind's after thunk run before the
;;;    expire procedure is called, and its before thunk again on resume?
;;; 3. Is the timer at 0 while the after thunks run during the expiry?
(import (chezscheme))
(define events '())
(define (note x) (set! events (cons x events)))
(define (run thunk)
  (set! events (quote ()))
  (let ((eng (make-engine thunk)))
    (eng 1000000
         (lambda (left v) (note (list 'complete v)))
         (lambda (next)
           (note 'expire-called)
           (next 1000000
                 (lambda (left v) (note (list 'complete v)))
                 (lambda (again) (note 'expired-twice))))))
  (reverse events))
;; 1
(write (list 'block-in-section
             (run (lambda ()
                    (critical-section
                     (engine-block)
                     (note 'in-section-after-block))
                    (note 'after-section)
                    'done))))
(newline)
;; 2 and 3
(write (list 'winds
             (run (lambda ()
                    (dynamic-wind
                      (lambda () (note 'before))
                      (lambda () (engine-block) (note 'body-resumed) 'body)
                      (lambda () (note (list 'after 'timer-left (let ((t (set-timer 0))) (set-timer t) t)))))))))
(newline)
;; critical winds as the group's inner wind
(write (list 'critical-winds
             (run (lambda ()
                    (dynamic-wind
                      (lambda () (note 'outer-before))
                      (lambda ()
                        (dynamic-wind #t
                          (lambda () (note 'inner-before))
                          (lambda () (engine-block) (note 'body-resumed) 'body)
                          (lambda () (note (list 'inner-after (let ((n (disable-interrupts))) (enable-interrupts) n))))))
                      (lambda () (note (list 'outer-after (let ((n (disable-interrupts))) (enable-interrupts) n)))))))))
(newline)
