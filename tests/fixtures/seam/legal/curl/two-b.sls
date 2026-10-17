#!r6rs
;;; Fixture for tests/test-check-seam.sps: the second of two libraries, which
;;; imports the first.
(library (curl two-b)
  (export b)
  (import (rnrs) (curl two-a))
  (define b a))
