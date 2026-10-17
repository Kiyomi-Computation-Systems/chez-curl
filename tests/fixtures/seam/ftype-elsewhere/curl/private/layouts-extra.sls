#!r6rs
;;; Fixture for tests/test-check-seam.sps: a name that starts with the listed
;;; one, but is not it.
(library (curl private layouts extra)
  (export point)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) define-ftype))
  (define-ftype point (struct (x int) (y int))))
