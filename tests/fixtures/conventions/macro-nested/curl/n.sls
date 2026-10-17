#!r6rs
;; define-syntax anywhere but a library body's top level: in a procedure's
;; body, in a begin at the top level, and in the template of a macro the
;; table lists. Each is named.
(library (curl n)
  (export f)
  (import (rnrs))

  (define (f)
    (define-syntax inner
      (syntax-rules ()
        ((_) 0)))
    (inner))

  (begin
    (define-syntax in-begin
      (syntax-rules ()
        ((_) 0))))

  (define-syntax maker
    (syntax-rules ()
      ((_ name) (define-syntax name (syntax-rules () ((_) 0)))))))
