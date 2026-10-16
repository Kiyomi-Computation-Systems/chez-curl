#!r6rs
;;; Fixture for tests/test-check-seam.sps: rule (a), a (curl ...) library
;;; importing an (http-client ...) library.
(library (curl x)
  (export x)
  (import (rnrs) (http-client y))
  (define x 1))
