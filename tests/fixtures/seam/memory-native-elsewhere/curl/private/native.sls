#!r6rs
;;; Fixture for tests/test-check-seam.sps: (curl private native), listed for
;;; foreign-procedure, which is not named, allocates for itself, which only
;;; (curl private memory) may.
(library (curl private native)
  (export labs block)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) foreign-procedure foreign-alloc))
  (define labs (foreign-procedure "labs" (long) long))
  (define (block n) (foreign-alloc n)))
