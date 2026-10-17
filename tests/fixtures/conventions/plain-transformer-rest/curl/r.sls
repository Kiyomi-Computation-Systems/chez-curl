#!r6rs
;; Plain transformers whose parameters are not one identifier: a rest list,
;; an identifier and a rest, and two identifiers. Each is named.
(library (curl r)
  (export)
  (import (rnrs))

  (define-syntax all-rest
    (lambda args
      (syntax-violation 'all-rest "refused" (car args))))

  (define-syntax some-rest
    (lambda (x . more)
      (syntax-violation 'some-rest "refused" x)))

  (define-syntax two
    (lambda (x y)
      (syntax-violation 'two "refused" x))))
