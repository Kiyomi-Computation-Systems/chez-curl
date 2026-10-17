#!r6rs
;;; Fixture for tests/test-check-seam.sps: define-ftype in (curl private
;;; layouts), the one library library-only-chez-names lists for it. A function
;;; ftype is what that rule closes elsewhere; here it is only a struct.
(library (curl private layouts)
  (export point)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) define-ftype format))
  (define-ftype point (struct (x int) (y int))))
