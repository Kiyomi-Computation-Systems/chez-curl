#!r6rs
;;; Fixture for tests/test-check-seam.sps: the rule holds in the other family
;;; too: a callable made, and locked, outside (curl private transfer).
(library (http-client h)
  (export on-write)
  (import (curl)
          (rnrs)
          (only (chezscheme) foreign-callable lock-object))
  (define on-write
    (foreign-callable (lambda (n) n) (int) int))
  (define locked (begin (lock-object on-write) #t)))
