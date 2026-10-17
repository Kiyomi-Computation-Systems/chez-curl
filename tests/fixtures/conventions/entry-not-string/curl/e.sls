#!r6rs
;; A foreign-procedure outside a known wrapper whose entry is no string
;; literal: a variable, an expression, and a pattern variable in a
;; define-syntax that is no known wrapper.
(library (curl e)
  (export f g)
  (import (rnrs) (only (chezscheme) foreign-procedure))

  (define entry "curl_easy_init")

  (define f (foreign-procedure entry () uptr))

  (define g (foreign-procedure (string-append "curl_" "easy_init") () uptr))

  (define-syntax bind
    (syntax-rules ()
      ((_ e) (foreign-procedure e () int)))))
