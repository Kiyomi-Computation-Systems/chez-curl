#!r6rs
;;; Fixture for tests/test-check-seam.sps: (curl private native), listed for
;;; foreign-procedure, makes a callable, which only (curl private transfer)
;;; may.
(library (curl private native)
  (export on-write)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) foreign-procedure foreign-callable))
  (define on-write
    (foreign-callable (lambda (data size n key) (* size n)) (uptr size_t size_t uptr) size_t)))
