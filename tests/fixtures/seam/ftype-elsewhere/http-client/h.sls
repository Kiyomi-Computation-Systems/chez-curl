#!r6rs
;;; Fixture for tests/test-check-seam.sps: the rule holds in the other family
;;; too.
(library (http-client h)
  (export h)
  (import (curl)
          (rnrs)
          (only (chezscheme) define-ftype))
  (define-ftype point (struct (x int) (y int)))
  (define h 1))
