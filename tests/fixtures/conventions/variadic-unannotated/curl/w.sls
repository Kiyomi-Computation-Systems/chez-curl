#!r6rs
;; make check-variadic's mutant, as a fixture: the known wrapper
;; bind-variadic with (__varargs_after 2) removed from its template. Every
;; use is then bound plain, and each mismatches its row.
(library (curl w)
  (export setopt-long setopt-pointer setopt-off-t getinfo)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-entry?))

  (define (required-entry name library) (foreign-entry? name))

  (define-syntax bind-variadic
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (required-entry entry library)
         (foreign-procedure entry (arg ...) result)))))

  (define setopt-long (bind-variadic "curl_easy_setopt" (uptr int long) int #f))

  (define setopt-pointer (bind-variadic "curl_easy_setopt" (uptr int uptr) int #f))

  (define setopt-off-t (bind-variadic "curl_easy_setopt" (uptr int integer-64) int #f))

  (define getinfo (bind-variadic "curl_easy_getinfo" (uptr int uptr) int #f)))
