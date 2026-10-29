#!r6rs
;;; Fixture for tests/test-check-seam.sps: another (http-client ...)
;;; library draws from a generator, which only (http-client private call)
;;; may.
(library (http-client private exchange)
  (export draw)
  (import (rnrs)
          (only (chezscheme) pseudo-random-generator-next!))
  (define (draw g) (pseudo-random-generator-next! g)))
