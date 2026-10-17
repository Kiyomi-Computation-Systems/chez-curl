#!r6rs
;;; Fixture for tests/test-check-seam.sps: a prefix over an only over
;;; (chezscheme), exporting the name the prefix makes.
(library (curl p)
  (export c:format)
  (import (rnrs) (prefix (only (chezscheme) format) c:)))
