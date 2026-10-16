#!r6rs
;;; Fixture for tests/test-check-seam.sps: a legal library, so the file under test is the only fault.
(library (curl legal)
  (export legal)
  (import (rnrs))
  (define legal 1))
