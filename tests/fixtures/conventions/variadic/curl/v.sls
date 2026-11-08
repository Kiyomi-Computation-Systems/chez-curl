#!r6rs
;; ADR-0001's variadic entries. Through the known wrapper whose template
;; carries (__varargs_after 2), they hold to their rows. Each row names that
;; wrapper as the one way to bind its entry, so directly, even with the
;; convention, is the wrong binder. Through the plain known wrapper,
;; directly with no convention, with another count, and with __varargs
;; alone, they mismatch too.
(library (curl v)
  (export setopt-long getinfo setopt-plain multi-setopt share-setopt
          multi-setopt-one share-setopt-any formadd formadd-plain)
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

  (define setopt-long (bind-variadic "curl_easy_setopt" (uptr int long) int #f))

  (define getinfo (bind-variadic "curl_easy_getinfo" (uptr int uptr) int #f))

  (define setopt-plain (bind-required "curl_easy_setopt" (uptr int uptr) int #f))

  (define multi-setopt
    (foreign-procedure (__varargs_after 2) "curl_multi_setopt" (uptr int long) int))

  (define share-setopt (foreign-procedure "curl_share_setopt" (uptr int long) int))

  (define multi-setopt-one
    (foreign-procedure (__varargs_after 1) "curl_multi_setopt" (uptr int long) int))

  (define share-setopt-any
    (foreign-procedure __varargs "curl_share_setopt" (uptr int long) int))

  (define formadd (bind-variadic "curl_formadd" (uptr uptr int uptr int uptr int) int #f))

  (define formadd-plain (bind-required "curl_formadd" (uptr uptr int uptr int uptr int) int #f)))
