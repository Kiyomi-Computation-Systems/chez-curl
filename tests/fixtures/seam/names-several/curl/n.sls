#!r6rs
;;; Fixture for tests/test-check-seam.sps.
(library (curl n)
  (export n)
  (import (rnrs) (only (chezscheme) format eval $primitive threaded?))
  (define n 1))
