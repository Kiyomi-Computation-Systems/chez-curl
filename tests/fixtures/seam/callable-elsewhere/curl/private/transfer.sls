#!r6rs
;;; Fixture for tests/test-check-seam.sps: (curl private transfer), listed for
;;; foreign-callable, which is not named, allocates for itself, which only
;;; (curl private memory) may.
(library (curl private transfer)
  (export on-write block)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) foreign-callable foreign-alloc))
  (define on-write
    (foreign-callable __collect_safe (lambda (data size n key) (* size n))
                      (uptr size_t size_t uptr) size_t))
  (define (block n) (foreign-alloc n)))
