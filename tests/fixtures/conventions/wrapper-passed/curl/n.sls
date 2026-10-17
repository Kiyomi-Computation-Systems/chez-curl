#!r6rs
;; The review's A3: apply-binder is handed bind-required as an argument and
;; puts it at the head, so curl-easy-setopt-long is bound plain, and so is a
;; curl_easy_perform with an unmarked u8*. An unused use of bind-variadic
;; keeps the count. Each argument is stray.
(library (curl n)
  (export curl-easy-setopt-long curl-easy-perform-plain)
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

  (define-syntax apply-binder
    (syntax-rules ()
      ((_ binder . args) (binder . args))))

  (define curl-easy-setopt-long-unused
    (bind-variadic "curl_easy_setopt" (uptr int long) int #f))

  (define curl-easy-setopt-long
    (apply-binder bind-required "curl_easy_setopt" (uptr int long) int #f))

  (define curl-easy-perform-plain
    (apply-binder bind-required "curl_easy_perform" (u8*) int #f)))
