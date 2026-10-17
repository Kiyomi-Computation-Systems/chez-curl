#!r6rs
;;; Fixture: an assertion violation at expansion, with who chez-curl and the
;;; threads refusal's message: not a syntax violation.
(library (curl private require-threaded)
  (export)
  (import (rnrs))
  (define-syntax refuse
    (lambda (x)
      (assertion-violation
       'chez-curl
       "chez-curl needs a threaded Chez Scheme, and (threaded?) is #f in this one")))
  (refuse))
