#!r6rs
;;; Fixture for tests/test-check-seam.sps: a library waits on a condition,
;;; which no library may: a wait that held a mutex deadlocked with a
;;; collection, so condition-wait is in no list. And it holds interrupts
;;; off by hand, which only (curl private engine) may.
(library (curl x)
  (export wait)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) make-mutex with-mutex condition-wait disable-interrupts))
  (define (wait c m) (disable-interrupts) (with-mutex m (condition-wait c m))))
