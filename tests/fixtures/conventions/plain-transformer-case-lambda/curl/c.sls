#!r6rs
;; Plain transformers that are procedures, but not a lambda of one
;; identifier: a case-lambda, and a lambda handed to
;; make-variable-transformer. Each is named.
(library (curl c)
  (export)
  (import (rnrs))

  (define-syntax by-cases
    (case-lambda
      ((x) (syntax-violation 'by-cases "refused" x))))

  (define-syntax by-variable
    (make-variable-transformer
      (lambda (x) (syntax-violation 'by-variable "refused" x)))))
