#!r6rs
;;; Fixture for tests/test-check-seam.sps: export specs that are neither an
;;; identifier nor (rename (internal external) ...), each named in order. x
;;; is one, and is not named. y.sls holds a cyclic one: #!r6rs refuses #0=.
(library (curl x)
  (export x 42 "s" (car) (foo car) (rename car kar) (rename (car)) (rename (car kar kaar))
          (rename (car 1)))
  (import (curl private require-threaded)
          (rnrs))
  (define x 1))
