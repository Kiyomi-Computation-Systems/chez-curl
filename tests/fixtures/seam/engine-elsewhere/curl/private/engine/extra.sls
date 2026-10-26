#!r6rs
;;; Fixture for tests/test-check-seam.sps: a name that starts with the listed
;;; one, but is not it, starts a thread.
(library (curl private engine extra)
  (export start)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) fork-thread))
  (define (start thunk) (fork-thread thunk)))
