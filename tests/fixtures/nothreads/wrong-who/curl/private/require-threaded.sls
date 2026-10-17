#!r6rs
;;; Fixture: a syntax violation at expansion with the threads refusal's message,
;;; but from who someone-else, not chez-curl.
(library (curl private require-threaded)
  (export)
  (import (rnrs))
  (define-syntax refuse
    (lambda (x)
      (syntax-violation
       'someone-else
       "chez-curl needs a threaded Chez Scheme, and (threaded?) is #f in this one"
       x)))
  (refuse))
