#!r6rs
;;; Fixture for tests/test-check-seam.sps: the rule holds in the other family
;;; too.
(library (http-client h)
  (export h format)
  (import (curl)
          (rnrs)
          (only (chezscheme) format))
  (define h 1))
