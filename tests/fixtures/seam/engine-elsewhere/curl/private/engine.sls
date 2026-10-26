#!r6rs
;;; Fixture for tests/test-check-seam.sps: (curl private engine), listed for
;;; fork-thread, which is not named, allocates for itself, which only
;;; (curl private memory) may.
(library (curl private engine)
  (export start block)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) fork-thread foreign-alloc))
  (define (start thunk) (fork-thread thunk))
  (define (block n) (foreign-alloc n)))
