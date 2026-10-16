#!r6rs
;;; Fixture for tests/test-check-seam.sps: a legal library, so the file under test is the only fault.
(library (curl real)
  (export real)
  (import (rnrs))
  (define real 1))
