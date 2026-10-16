#!r6rs
;;; Fixture for tests/test-check-seam.sps.
(library (curl n)
  (export n)
  (import (rnrs) (only (chezscheme) import include include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile load-program))
  (define n 1))
