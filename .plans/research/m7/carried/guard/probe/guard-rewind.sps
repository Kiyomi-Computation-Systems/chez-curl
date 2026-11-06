;;; guard-rewind.sps: R6RS guard, with no clause that takes a raise,
;;; re-raises it by raise-continuable "in the dynamic environment of the
;;; original call to raise" (R6RS 7.1): back through every dynamic-wind
;;; between, each before thunk run again. A before thunk that refuses
;;; re-entry, as (curl private url)'s call-with-flagged-url's does once its
;;; handle is freed, then raises in place of the declined object.
;;; Prints (case WHAT-THE-OUTER-GUARD-SAW BEFORE-RUNS) for each case.
(import (chezscheme))

(define (run raised clause-takes?)
  (let ((before-runs 0))
    (let ((seen
           (guard (e (#t (list 'outer e)))
             (guard (e ((clause-takes? e) (list 'inner e)))
               (let ((freed #f))
                 (dynamic-wind
                   (lambda ()
                     (set! before-runs (+ before-runs 1))
                     (when freed (raise 'refused-re-entry)))
                   (lambda () (raise raised))
                   (lambda () (set! freed #t))))))))
      (list seen before-runs))))

(write (list 'condition-clause-takes-a-condition
             (run (make-message-condition "x") condition?)))
(newline)
(write (list 'condition-clause-declines-a-symbol (run 'tick condition?)))
(newline)
(write (list 'condition-clause-declines-false (run #f condition?)))
(newline)
;; With no wind between, the declined object comes back as it was.
(write (list 'no-wind
             (guard (e (#t (list 'outer e)))
               (guard (e ((condition? e) (list 'inner e)))
                 (raise 'tick)))))
(newline)
