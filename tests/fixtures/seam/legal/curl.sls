#!r6rs
;;; Fixture for tests/test-check-seam.sps: a legal tree. Every import is on a list.
(library (curl)
  (export lib-version)
  (import (curl private require-threaded)
          (rnrs)
          (rnrs io ports)
          (only (chezscheme) format threaded?)
          (curl private thing))
  (define lib-version thing))
