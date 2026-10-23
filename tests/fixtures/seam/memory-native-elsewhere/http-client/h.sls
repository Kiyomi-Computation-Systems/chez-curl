#!r6rs
;;; Fixture for tests/test-check-seam.sps: the rule holds in the other family
;;; too: a binding, and a shared object loaded, outside (curl private native).
(library (http-client h)
  (export labs load!)
  (import (curl)
          (rnrs)
          (only (chezscheme) foreign-procedure load-shared-object))
  (define labs (foreign-procedure "labs" (long) long))
  (define (load! path) (load-shared-object path)))
