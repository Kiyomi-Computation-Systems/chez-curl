#!r6rs
;;; Fixture for tests/test-check-seam.sps: a name that starts with the listed
;;; one, but is not it, hands C a callable's entry point.
(library (curl private transfer extra)
  (export entry)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) foreign-callable-entry-point))
  (define (entry code) (foreign-callable-entry-point code)))
