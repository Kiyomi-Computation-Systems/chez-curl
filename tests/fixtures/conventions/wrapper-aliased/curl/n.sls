#!r6rs
;; The review's A2: identifier-syntax makes bind-plain another name for
;; bind-required, and bind-plain binds curl-easy-setopt-long. An unused use
;; of bind-variadic keeps the count. The name in the template is stray.
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

  (define-syntax bind-plain (identifier-syntax bind-required))

  (define curl-easy-setopt-long-unused
    (bind-variadic "curl_easy_setopt" (uptr int long) int #f))

  (define curl-easy-setopt-long
    (bind-plain "curl_easy_setopt" (uptr int long) int #f)))
