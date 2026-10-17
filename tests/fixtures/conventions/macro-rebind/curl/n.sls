#!r6rs
;; FPA4: rebind's syntax-case takes apart its own template, a
;; foreign-procedure form the reader reads as memcpy, plain, and binds
;; curl_easy_setopt with it, plain. An unused use of bind-variadic keeps
;; the count. rebind is on no row of the table: named.
(library (curl n)
  (export curl-easy-setopt-long)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-entry?))

  (define (required-entry name library) (foreign-entry? name))

  (define-syntax bind-variadic
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (required-entry entry library)
         (foreign-procedure (__varargs_after 2) entry (arg ...) result)))))

  (define-syntax rebind
    (lambda (x)
      (syntax-case #'(foreign-procedure "memcpy" (uptr int long) int) ()
        ((fp e . rest) #'(fp "curl_easy_setopt" . rest)))))

  (define curl-easy-setopt-long-unused
    (bind-variadic "curl_easy_setopt" (uptr int long) int #f))

  (define curl-easy-setopt-long (rebind)))
