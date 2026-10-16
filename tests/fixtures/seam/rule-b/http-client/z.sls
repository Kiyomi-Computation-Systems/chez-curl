#!r6rs
;;; Fixture for tests/test-check-seam.sps: rule (b), an (http-client ...)
;;; library importing a (curl ...) library that is not public.
(library (http-client z)
  (export z)
  (import (rnrs) (curl) (curl private thing))
  (define z 1))
