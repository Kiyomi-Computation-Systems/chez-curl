#!r6rs
;; A12: a plain transformer whose input goes nowhere, and whose output is
;; built by a procedure another library exports: measured, Chez binds what
;; it builds. The library imports more than whole (rnrs ...) libraries and
;; (only (chezscheme) ...): named.
(library (curl m)
  (export curl-easy-setopt-long)
  (import (rnrs) (curl b))

  (define-syntax m
    (lambda (x)
      (built)))

  (define curl-easy-setopt-long (m)))
