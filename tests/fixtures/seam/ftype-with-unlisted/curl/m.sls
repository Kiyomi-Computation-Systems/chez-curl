#!r6rs
;;; Fixture for tests/test-check-seam.sps: one import set with define-ftype
;;; between two names allowed-chez-names does not list. Each is named, in the
;;; order the import set holds them.
(library (curl m)
  (export m)
  (import (rnrs) (only (chezscheme) eval define-ftype $primitive format))
  (define m 1))
