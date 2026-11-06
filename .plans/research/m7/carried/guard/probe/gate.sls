#!r6rs
;;; (curl private gate): the research seam, in copies alone, never in the
;;; tree. run-gate! calls the armed procedure, if any, with WHERE: enter and
;;; exit, the first and last forms of call-state's checks; parse and
;;; parse-end, the first and last forms of a URL parse's body, inside
;;; call-with-flagged-url's critical winds. The probe's procedure decides
;;; what each place does: block on a mutex, set a timer, or mark.
(library (curl private gate)
  (export gate-set! run-gate!)
  (import (rnrs))

  (define gate (vector #f))

  ;; gate-set! : (U (Symbol -> Any) #f) -> Void
  (define (gate-set! proc) (vector-set! gate 0 proc))

  ;; run-gate! : Symbol -> Void
  (define (run-gate! where)
    (let ((g (vector-ref gate 0)))
      (when g (g where)))))
