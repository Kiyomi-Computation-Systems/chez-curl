#!r6rs
;;; Fixture for tests/test-check-seam.sps: (curl private memory), listed for
;;; foreign-alloc and foreign-free, which are not named, imports
;;; foreign-procedure, which only (curl private native) may.
(library (curl private memory)
  (export block free-block! labs)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) foreign-alloc foreign-free foreign-procedure))
  (define (block n) (foreign-alloc n))
  (define (free-block! address) (foreign-free address))
  (define labs (foreign-procedure "labs" (long) long)))
