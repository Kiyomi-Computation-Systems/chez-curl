#!r6rs
;;; Fixture for tests/test-check-seam.sps: (http-client private call), the
;;; listed library, imports both names, and is not named.
(library (http-client private call)
  (export make draw)
  (import (rnrs)
          (only (chezscheme) make-pseudo-random-generator pseudo-random-generator-next!))
  (define (make) (make-pseudo-random-generator))
  (define (draw g) (pseudo-random-generator-next! g)))
