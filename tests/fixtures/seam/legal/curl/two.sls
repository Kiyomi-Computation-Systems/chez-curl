#!r6rs
;;; Fixture for tests/test-check-seam.sps: two libraries in one file.
(library (curl two-a)
  (export a)
  (import (rnrs))
  (define a 1))
(library (curl two-b)
  (export b)
  (import (rnrs) (curl two-a))
  (define b a))
