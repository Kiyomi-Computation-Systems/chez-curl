#!r6rs
;;; Fixture for tests/test-check-seam.sps: foreign-alloc and foreign-free in
;;; (curl private memory), the one library library-only-chez-names lists for
;;; each. make-mutex and with-mutex beside them are allowed everywhere.
(library (curl private memory)
  (export block free-block!)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) foreign-alloc foreign-free make-mutex with-mutex))
  (define lock (make-mutex))
  (define (block n) (with-mutex lock (foreign-alloc n)))
  (define (free-block! address) (with-mutex lock (foreign-free address))))
