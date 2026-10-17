#!r6rs
;; Forms the reader cannot read as (head convention ... entry (type ...) type).
(library (curl m)
  (export a b c d)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-callable))

  (define a (foreign-procedure "curl_easy_init"))

  (define b (foreign-procedure "curl_easy_init" uptr uptr))

  (define c (foreign-procedure . "curl_easy_init"))

  (define d (foreign-callable (lambda () 0))))
