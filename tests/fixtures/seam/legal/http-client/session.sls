#!r6rs
;;; Fixture for tests/test-check-seam.sps: an (http-client ...) library
;;; importing the public (curl), plain and wrapped.
(library (http-client session)
  (export session)
  (import (rnrs)
          (curl)
          (only (curl) lib-version)
          (http-client other))
  (define session lib-version))
