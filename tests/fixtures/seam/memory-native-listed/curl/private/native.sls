#!r6rs
;;; Fixture for tests/test-check-seam.sps: foreign-procedure in (curl private
;;; native), the one library library-only-chez-names lists for it, and
;;; load-shared-object, likewise, which takes its blocks from (curl private
;;; memory).
(library (curl private native)
  (export labs)
  (import (curl private require-threaded)
          (rnrs)
          (curl private memory)
          (only (chezscheme) foreign-procedure foreign-entry? load-shared-object))
  (define loaded (load-shared-object "libc.so.6"))
  (define labs (and (foreign-entry? "labs") (foreign-procedure "labs" (long) long))))
