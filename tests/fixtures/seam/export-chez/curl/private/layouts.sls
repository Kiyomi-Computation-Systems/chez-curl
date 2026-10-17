#!r6rs
;;; Fixture for tests/test-check-seam.sps: the listed library re-exports
;;; define-ftype, so a library that may not import it gets it from here.
(library (curl private layouts)
  (export point define-ftype)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) define-ftype))
  (define-ftype point (struct (x int) (y int))))
