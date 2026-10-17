#!r6rs
;; A library that defines both known wrappers, as native.sls does, and
;; exports them, once by name and once renamed. Each export is stray: no
;; other library may reach a wrapper, under any name.
(library (curl e)
  (export bind-required (rename (bind-variadic bind-v)))
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-entry?))

  (define (required-entry name library) (foreign-entry? name))

  (define-syntax bind-required
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (required-entry entry library)
         (foreign-procedure entry (arg ...) result)))))

  (define-syntax bind-variadic
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (required-entry entry library)
         (foreign-procedure (__varargs_after 2) entry (arg ...) result))))))
