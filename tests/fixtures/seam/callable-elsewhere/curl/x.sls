#!r6rs
;;; Fixture for tests/test-check-seam.sps: a library that is not listed locks
;;; an object, which only (curl private transfer) may.
(library (curl x)
  (export pin!)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) make-mutex lock-object))
  (define (pin! x) (lock-object x)))
