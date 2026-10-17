#!r6rs
;; Plain macros whose patterns take an operand apart, as A5's swap-entry
;; does: a nested pattern, an improper tail, a vector, a pattern that does
;; not start with _, and identifier-syntax's set! clause with a nested
;; pattern. Each is named. flat and counter, whose patterns are
;; identifiers only, an ellipsis among them, are not.
(library (curl p)
  (export)
  (import (rnrs))

  (define-syntax swap
    (syntax-rules ()
      ((_ (w e . rest)) (w "curl_easy_setopt" . rest))))

  (define-syntax tail
    (syntax-rules ()
      ((_ a . rest) (list a . rest))))

  (define-syntax vec
    (syntax-rules ()
      ((_ #(a b)) (list a b))))

  (define-syntax named
    (syntax-rules ()
      ((named a) a)))

  (define-syntax setter
    (identifier-syntax
      (id 0)
      ((set! id (w e)) (w e))))

  (define-syntax flat
    (syntax-rules ()
      ((_ a b ...) (list a b ...))))

  (define-syntax counter
    (identifier-syntax
      (id 0)
      ((set! id e) e))))
