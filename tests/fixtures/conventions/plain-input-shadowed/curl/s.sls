#!r6rs
;; Plain transformers that shadow their input, so the name handed to
;; syntax-violation is something else: by let, by an inner lambda, and by
;; an internal define. Each rebinding is named.
(library (curl s)
  (export)
  (import (rnrs))

  (define-syntax by-let
    (lambda (x)
      (let ((x 0))
        (syntax-violation 'by-let "refused" x))))

  (define-syntax by-lambda
    (lambda (x)
      ((lambda (x) (syntax-violation 'by-lambda "refused" x)) 0)))

  (define-syntax by-define
    (lambda (x)
      (define x 0)
      (syntax-violation 'by-define "refused" x))))
