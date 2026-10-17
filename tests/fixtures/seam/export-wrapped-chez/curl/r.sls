#!r6rs
;;; Fixture for tests/test-check-seam.sps: a rename over an only over
;;; (chezscheme), exporting the name the rename makes.
(library (curl r)
  (export fmt)
  (import (rnrs) (rename (only (chezscheme) format) (format fmt))))
