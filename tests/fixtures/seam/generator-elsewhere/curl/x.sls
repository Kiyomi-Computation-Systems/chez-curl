#!r6rs
;;; Fixture for tests/test-check-seam.sps: a (curl ...) library makes and
;;; draws from a generator, which only (http-client private call) may.
(library (curl x)
  (export draw)
  (import (rnrs)
          (only (chezscheme) make-pseudo-random-generator pseudo-random-generator-next!))
  (define (draw) (pseudo-random-generator-next! (make-pseudo-random-generator))))
