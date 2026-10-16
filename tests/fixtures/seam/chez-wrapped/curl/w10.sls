#!r6rs
;;; Fixture for tests/test-check-seam.sps.
(library (curl w10)
  (export w10)
  (import (rnrs) (only (only (chezscheme) format car) format))
  (define w10 1))
