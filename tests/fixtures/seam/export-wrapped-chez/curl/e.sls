#!r6rs
;;; Fixture for tests/test-check-seam.sps: an except over an only over
;;; (chezscheme), exporting the name it leaves. Rule (c) refuses the wrapper,
;;; so no wrapper can hide a name it imports from (chezscheme).
(library (curl e)
  (export format)
  (import (rnrs) (except (only (chezscheme) format getenv) getenv)))
