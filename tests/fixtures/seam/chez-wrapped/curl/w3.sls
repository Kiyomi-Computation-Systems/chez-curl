#!r6rs
;;; Fixture for tests/test-check-seam.sps.
(library (curl w3)
  (export w3)
  (import (rnrs) (rename (chezscheme) (car kar)))
  (define w3 1))
