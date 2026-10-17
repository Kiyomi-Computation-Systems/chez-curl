#!r6rs
;; A6: a plain transformer that holds none of the names a plain macro may
;; not, and hands its input to rebuild, from (curl h). The reader reads
;; memcpy, plain; measured, Chez binds the entry rebuild chooses. Its input
;; goes somewhere other than syntax-violation: named.
(library (curl m)
  (export curl-easy-setopt-long)
  (import (rnrs) (only (chezscheme) foreign-procedure) (curl h))

  (define-syntax m
    (lambda (x) (rebuild x)))

  (define curl-easy-setopt-long (m (foreign-procedure "memcpy" (uptr int long) int))))
