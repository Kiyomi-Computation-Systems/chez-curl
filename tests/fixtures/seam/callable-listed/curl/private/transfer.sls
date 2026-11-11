#!r6rs
;;; Fixture for tests/test-check-seam.sps: foreign-callable,
;;; foreign-callable-entry-point and lock-object in (curl private transfer), the
;;; one library library-only-chez-names lists for each. make-mutex and
;;; with-mutex beside them are allowed everywhere.
(library (curl private transfer)
  (export entry)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) foreign-callable foreign-callable-entry-point lock-object
                make-mutex with-mutex))
  (define lock (make-mutex))
  (define on-write
    (foreign-callable __collect_safe (lambda (data size n key) (with-mutex lock (* size n)))
                      (uptr size_t size_t uptr) size_t))
  (define locked (begin (lock-object on-write) #t))
  (define (entry) (foreign-callable-entry-point on-write)))
