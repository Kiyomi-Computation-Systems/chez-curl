#!r6rs
;; Imports (curl extra), which rule (h) finds defined: only rule (i) names
;; where it stands.
(library (curl x)
  (export x)
  (import (rnrs) (curl extra))
  (define x 1))
