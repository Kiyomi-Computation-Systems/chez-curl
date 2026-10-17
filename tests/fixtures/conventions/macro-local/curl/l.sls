#!r6rs
;; Local macros, by let-syntax and letrec-syntax: no table can name them,
;; so each is named.
(library (curl l)
  (export a b)
  (import (rnrs))

  (define a
    (let-syntax ((m (syntax-rules () ((_) 0))))
      (m)))

  (define b
    (letrec-syntax ((m (syntax-rules () ((_) 0))))
      (m))))
