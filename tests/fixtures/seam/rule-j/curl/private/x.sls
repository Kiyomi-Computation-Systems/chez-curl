#!r6rs
;;; Fixture for tests/test-check-seam.sps: rule (j), a private (curl ...)
;;; library importing the hatch through a wrapper.
(library (curl private x)
  (export)
  (import (rnrs) (prefix (curl unsupported) hatch:)))
