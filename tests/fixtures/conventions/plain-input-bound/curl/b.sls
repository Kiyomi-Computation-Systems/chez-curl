#!r6rs
;; Plain transformers whose input goes elsewhere than as syntax-violation's
;; last argument: bound to another name, by let, define and set!, then that
;; name handed on; handed as the message; quoted; and inside a quoted
;; syntax-violation form, which is data. Each place is named.
(library (curl b)
  (export)
  (import (rnrs))

  (define-syntax by-let
    (lambda (x)
      (let ((form x))
        (syntax-violation 'by-let "refused" form))))

  (define-syntax by-define
    (lambda (x)
      (define form x)
      (syntax-violation 'by-define "refused" form)))

  (define-syntax by-set
    (lambda (x)
      (let ((form #f))
        (set! form x)
        (syntax-violation 'by-set "refused" form))))

  (define-syntax by-message
    (lambda (x)
      (syntax-violation 'by-message x #f)))

  (define-syntax by-quote
    (lambda (x)
      (syntax-violation 'by-quote "refused" 'x)))

  (define-syntax by-data
    (lambda (x)
      (car '(syntax-violation by-data "refused" x)))))
