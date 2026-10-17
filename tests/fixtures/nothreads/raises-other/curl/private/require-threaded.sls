#!r6rs
;;; Fixture: a (curl private require-threaded) that raises at expansion, but
;;; not the refusal: a plain error from who fixture.
(library (curl private require-threaded)
  (export)
  (import (rnrs))
  (define-syntax refuse
    (lambda (x)
      (error 'fixture "boom")))
  (refuse))
