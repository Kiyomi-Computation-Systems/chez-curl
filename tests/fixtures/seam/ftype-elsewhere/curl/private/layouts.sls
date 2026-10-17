#!r6rs
;;; Fixture for tests/test-check-seam.sps: the listed library, in the same tree
;;; as those that are not. It imports define-ftype and is not named.
(library (curl private layouts)
  (export point)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) define-ftype))
  (define-ftype point (struct (x int) (y int))))
