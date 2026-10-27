#!r6rs
;;; Fixture for tests/test-check-seam.sps: an (http-client ...) library
;;; importing the hatch, which rule (b) refuses, as any (curl ...) library
;;; but the public ones.
(library (http-client z)
  (export)
  (import (rnrs) (curl unsupported)))
