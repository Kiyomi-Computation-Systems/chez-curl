#!r6rs
;;; Fixture for tests/test-check-seam.sps: another (http-client ...)
;;; library makes a generator of its own, which only (http-client private
;;; call) may.
(library (http-client private drive)
  (export make)
  (import (rnrs)
          (only (chezscheme) make-pseudo-random-generator))
  (define (make) (make-pseudo-random-generator)))
