#!r6rs
;;; Fixture for tests/test-check-seam.sps.
(library (curl n)
  (export n)
  (import (rnrs) (only (chezscheme) 42))
  (define n 1))
