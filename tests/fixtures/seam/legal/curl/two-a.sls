#!r6rs
;;; Fixture for tests/test-check-seam.sps: one of two libraries, each in its
;;; own file at its name's path.
(library (curl two-a)
  (export a)
  (import (rnrs))
  (define a 1))
