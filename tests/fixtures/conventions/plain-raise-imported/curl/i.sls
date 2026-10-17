#!r6rs
;; A10: a plain transformer in a library that takes syntax-violation from
;; another library, with (rnrs)'s excepted. Measured, Chez binds the entry
;; that library's procedure chooses. The library imports no (rnrs) whole:
;; named.
(library (curl i)
  (export)
  (import (except (rnrs) syntax-violation) (curl v))

  (define-syntax m
    (lambda (x)
      (syntax-violation 'm "never" x))))
