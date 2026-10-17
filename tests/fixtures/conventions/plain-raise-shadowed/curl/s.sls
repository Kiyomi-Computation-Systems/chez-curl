#!r6rs
;; A11: plain transformers that rebind syntax-violation, so the call their
;; input goes to is a procedure of their own: by let, and by an internal
;; define. Measured with let, Chez binds the entry the procedure chooses.
;; Each binding of the name is named.
(library (curl s)
  (export)
  (import (rnrs))

  (define-syntax by-let
    (lambda (x)
      (let ((syntax-violation (lambda (who message form) form)))
        (syntax-violation 'by-let "never" x))))

  (define-syntax by-define
    (lambda (x)
      (define (syntax-violation who message form) form)
      (syntax-violation 'by-define "never" x))))
