#!r6rs
;;; Fixture for tests/test-check-seam.sps: a library that is not listed frees
;;; foreign memory, which only (curl private memory) may, and loads a shared
;;; object, which only (curl private native) may.
(library (curl x)
  (export free!)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) format foreign-free load-shared-object))
  (define (free! address) (foreign-free address))
  (define (load! path) (load-shared-object path)))
