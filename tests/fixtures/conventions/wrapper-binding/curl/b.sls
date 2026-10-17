#!r6rs
;; A known wrapper's name bound as a variable, which shadows the wrapper:
;; by define, lambda, case-lambda, the let forms, do and guard. Each is
;; stray, and none is read as a use.
(library (curl b)
  (export)
  (import (rnrs))

  (define bind-required 0)

  (define (bind-variadic . args) args)

  (define (formal bind-required) 0)

  (define as-lambda (lambda (bind-required) 0))

  (define as-rest (lambda bind-variadic 0))

  (define as-case (case-lambda ((bind-required) 0) ((x . bind-variadic) 1)))

  (define as-let (let ((bind-required "curl_easy_setopt")) 0))

  (define as-let* (let* ((x 0) (bind-variadic x)) 0))

  (define as-letrec (letrec ((bind-required (lambda () 0))) 0))

  (define as-named-let (let bind-variadic ((i 0)) i))

  (define as-values (let-values (((bind-required) (values 0))) 0))

  (define as-do (do ((bind-variadic 0 1)) (#t 0)))

  (define as-guard (guard (bind-required (#t 0)) 0)))
