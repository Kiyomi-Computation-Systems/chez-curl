#!r6rs
;;; Fixture for tests/test-check-seam.sps: (http-client private call), the
;;; one library listed for make-pseudo-random-generator and
;;; pseudo-random-generator-next!, imports both, with the mutex beside them.
(library (http-client private call)
  (export draw)
  (import (rnrs)
          (only (chezscheme) critical-section make-mutex with-mutex make-pseudo-random-generator
                pseudo-random-generator-next!))
  (define generator (make-pseudo-random-generator))
  (define lock (make-mutex))
  (define (draw) (critical-section (with-mutex lock (pseudo-random-generator-next! generator)))))
