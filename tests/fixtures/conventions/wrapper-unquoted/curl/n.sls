#!r6rs
;; Case A1: the use that binds curl-easy-setopt-long sits under an
;; unquote, in a quasiquote, which the reader reads as data. An unused use
;; of bind-variadic keeps the count. The quasiquoted name is stray.
(library (curl n)
  (export curl-easy-setopt-long)
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
         (foreign-procedure (__varargs_after 2) entry (arg ...) result)))))

  (define curl-easy-setopt-long-unused
    (bind-variadic "curl_easy_setopt" (uptr int long) int #f))

  (define curl-easy-setopt-long
    (car `(,(bind-required "curl_easy_setopt" (uptr int long) int #f)))))
