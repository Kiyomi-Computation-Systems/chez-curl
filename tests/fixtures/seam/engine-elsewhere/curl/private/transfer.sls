#!r6rs
;;; Fixture for tests/test-check-seam.sps: (curl private transfer), listed
;;; for foreign-callable, starts a thread, which only (curl private engine)
;;; may.
(library (curl private transfer)
  (export start)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) fork-thread))
  (define (start thunk) (fork-thread thunk)))
