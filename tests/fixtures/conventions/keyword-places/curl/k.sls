#!r6rs
;; define-syntax, let-syntax and letrec-syntax anywhere but the head of a
;; form written in code: as an operand, in data, and at the head of a form
;; in a template. Each is stray; the template's is a nested definition too.
(library (curl k)
  (export a b c)
  (import (rnrs))

  (define-syntax step
    (syntax-rules ()
      ((_ e) e)))

  (define a (step define-syntax))

  (define b '(let-syntax ((m 0)) m))

  (define c (list letrec-syntax))

  (define-syntax maker
    (syntax-rules ()
      ((_ name) (define-syntax name (syntax-rules () ((_) 0)))))))
