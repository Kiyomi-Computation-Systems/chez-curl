#!r6rs
;; A known wrapper's name as an argument, where a macro can put it at a head
;; the reader never sees: each is stray. The other wrapper, a use nested in
;; a call, and an improper tail.
(library (curl g)
  (export getinfo init nothing)
  (import (rnrs))

  (define-syntax again
    (syntax-rules ()
      ((_ m . args) (m . args))))

  (define-syntax tail
    (syntax-rules ()
      ((_ . m) 0)))

  (define getinfo (again bind-variadic "curl_easy_getinfo" (uptr int uptr) int #f))

  (define init (list (again bind-required "curl_easy_init" () uptr #f)))

  (define nothing (tail . bind-required)))
