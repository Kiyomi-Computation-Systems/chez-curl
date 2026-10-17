#!r6rs
;; Bindings the table has no row for: an entry, a callable, and a callable
;; named memcpy, a symbol, where the table's row "memcpy" is a string.
(library (curl n)
  (export curl-easy-reset on-unlisted memcpy)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-callable))

  (define curl-easy-reset (foreign-procedure "curl_easy_reset" (uptr) void))

  (define on-unlisted (foreign-callable (lambda (n) n) (int) int))

  (define memcpy (foreign-callable (lambda (m) m) (int) int)))
