#!r6rs
;;; Fixture for tests/test-check-seam.sps: rule (j). The hatch itself may
;;; import any (curl ...) library, (curl) among them.
(library (curl unsupported)
  (export)
  (import (rnrs) (curl)))
