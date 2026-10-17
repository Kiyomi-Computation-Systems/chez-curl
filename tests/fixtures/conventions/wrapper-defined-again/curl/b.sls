#!r6rs
;; The known wrapper's second definition, with __collect_safe.
(library (curl b)
  (export)
  (import (rnrs) (only (chezscheme) foreign-procedure))

  (define-syntax bind-required
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (foreign-procedure __collect_safe entry (arg ...) result)))))
