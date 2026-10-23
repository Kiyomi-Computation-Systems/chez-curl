#!r6rs
;;; Fixture for tests/test-check-seam.sps: a name that starts with the listed
;;; one, but is not it, allocates a block the counters would not see.
(library (curl private memory extra)
  (export block)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) foreign-alloc))
  (define (block n) (foreign-alloc n)))
