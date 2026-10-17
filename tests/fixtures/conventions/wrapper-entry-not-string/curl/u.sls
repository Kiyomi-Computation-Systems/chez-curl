#!r6rs
;; Uses of the known wrapper whose entry is no string literal: a variable, an
;; expression, and a use too short to hold one.
(library (curl u)
  (export a b c)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-entry?))

  (define (required-entry name library) (foreign-entry? name))

  (define-syntax bind-required
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (required-entry entry library)
         (foreign-procedure entry (arg ...) result)))))

  (define name "curl_easy_init")

  (define a (bind-required name () uptr #f))

  (define b (bind-required (string-append "curl_" "easy_init") () uptr #f))

  (define c (bind-required)))
