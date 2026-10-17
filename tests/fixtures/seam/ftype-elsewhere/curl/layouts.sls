#!r6rs
;;; Fixture for tests/test-check-seam.sps: a name near the listed one, but not
;;; it: (curl layouts) is not (curl private layouts).
(library (curl layouts)
  (export point)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) define-ftype))
  (define-ftype point (struct (x int) (y int))))
