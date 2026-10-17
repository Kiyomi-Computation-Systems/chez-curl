#!r6rs
;;; Fixture: a syntax violation from chez-curl at expansion, whose message is
;;; not the threads refusal's: the floor refusal's wording.
(library (curl private require-threaded)
  (export)
  (import (rnrs))
  (define-syntax refuse
    (lambda (x)
      (syntax-violation
       'chez-curl
       "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0"
       x)))
  (refuse))
