#!r6rs
;; A second file: a plain direct binding and a plain callable.
(library (curl b)
  (export curl-multi-perform on-plain)
  (import (rnrs)
          (only (chezscheme) foreign-procedure foreign-callable))

  (define curl-multi-perform (foreign-procedure "curl_multi_perform" (uptr uptr) int))

  (define on-plain (foreign-callable (lambda (n) n) (int) int)))
