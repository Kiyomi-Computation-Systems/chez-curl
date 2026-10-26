#!r6rs
;;; Fixture for tests/test-check-seam.sps: the rule holds in the other family
;;; too: a mutex taken by hand, which no library may, and a thread started
;;; outside (curl private engine).
(library (http-client h)
  (export take start)
  (import (curl)
          (rnrs)
          (only (chezscheme) mutex-acquire fork-thread))
  (define (take m) (mutex-acquire m))
  (define (start thunk) (fork-thread thunk)))
