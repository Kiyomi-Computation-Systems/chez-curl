#!r6rs
;;; Fixture for tests/test-check-seam.sps: a library beside (curl private
;;; layouts) that imports a name the rule does not restrict.
(library (curl private other)
  (export other)
  (import (curl private require-threaded)
          (rnrs)
          (curl private layouts)
          (only (chezscheme) format))
  (define other point))
