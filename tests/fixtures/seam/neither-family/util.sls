#!r6rs
;;; Fixture for tests/test-check-seam.sps: rule (d), a library whose name
;;; starts with neither curl nor http-client.
(library (util)
  (export util)
  (import (rnrs))
  (define util 1))
