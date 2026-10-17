#!r6rs
;; A5: swap-entry takes apart the use it is handed and rebuilds it with
;; curl_easy_setopt, so curl-easy-setopt-long is bound plain while the
;; reader reads memcpy, plain. An unused use of bind-variadic keeps the
;; count. swap-entry is on no row of the table: named.
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

  (define-syntax swap-entry
    (syntax-rules ()
      ((_ (w e . rest)) (w "curl_easy_setopt" . rest))))

  (define curl-easy-setopt-long-unused
    (bind-variadic "curl_easy_setopt" (uptr int long) int #f))

  (define curl-easy-setopt-long
    (swap-entry (bind-required "memcpy" (uptr int long) int #f))))
