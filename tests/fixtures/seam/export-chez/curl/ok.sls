#!r6rs
;;; Fixture for tests/test-check-seam.sps: exports the rule passes. car comes
;;; from (rnrs), not (chezscheme). my-format is exported as format, a name
;;; (chezscheme) has but whose binding here is the library's own. getenv is
;;; defined here, and not imported. format is imported and not exported.
(library (curl ok)
  (export car (rename (my-format format)) getenv)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) format))
  (define (my-format x) (format "~a" x))
  (define getenv 1))
