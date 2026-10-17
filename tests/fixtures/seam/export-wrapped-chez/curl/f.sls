#!r6rs
;;; Fixture for tests/test-check-seam.sps: a for over an only over
;;; (chezscheme), exporting its name.
(library (curl f)
  (export format)
  (import (rnrs) (for (only (chezscheme) format) run)))
