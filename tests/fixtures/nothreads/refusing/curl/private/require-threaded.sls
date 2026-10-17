#!r6rs
;;; Fixture: a (curl private require-threaded) that always refuses, by name, at
;;; expansion: a syntax violation from chez-curl whose message starts with the
;;; marker tests/check-nothreads.sps and tests/test-require-threaded.sps use.
(library (curl private require-threaded)
  (export)
  (import (rnrs))
  (define-syntax refuse
    (lambda (x)
      (syntax-violation
       'chez-curl
       "chez-curl needs a threaded Chez Scheme, and (threaded?) is #f in this one"
       x)))
  (refuse))
