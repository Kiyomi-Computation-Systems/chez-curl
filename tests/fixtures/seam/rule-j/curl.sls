#!r6rs
;;; Fixture for tests/test-check-seam.sps: rule (j), (curl) importing the
;;; hatch, which it could then re-export past rule (b).
(library (curl)
  (export)
  (import (rnrs) (only (curl unsupported))))
