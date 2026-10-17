#!r6rs
;; A foreign-callable that is not the whole right-hand side of
;; (define name ...): in a procedure body, an argument, a begin, a define
;; with an extra part, and a let.
(library (curl c)
  (export make pair wrapped both bound)
  (import (rnrs) (only (chezscheme) foreign-callable))

  (define (make) (foreign-callable (lambda (a) a) (int) int))

  (define pair (cons 1 (foreign-callable (lambda (b) b) (int) int)))

  (define wrapped (begin (foreign-callable (lambda (c) c) (int) int)))

  (define both (foreign-callable (lambda (d) d) (int) int) 'extra)

  (define bound (let ((cb (foreign-callable (lambda (e) e) (int) int))) cb)))
