#!r6rs
;; Plain transformers that hand their input to a procedure of the same
;; library: one defined in the library's body, one in the transformer's
;; own. Each call is named, whatever the procedure does.
(library (curl l)
  (export)
  (import (rnrs))

  (define (keep form) form)

  (define-syntax by-library
    (lambda (x)
      (keep x)))

  (define-syntax by-body
    (lambda (x)
      (define (hold form) form)
      (hold x))))
