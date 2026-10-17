#!r6rs
;;; Fixture for tests/test-check-seam.sps: two names imported from
;;; (chezscheme) exported, one plain and one through a rename spec, each named
;;; in export order. r, its own definition, is not named.
(library (curl r)
  (export r format (rename (getenv curl-getenv)))
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) format getenv))
  (define r 1))
