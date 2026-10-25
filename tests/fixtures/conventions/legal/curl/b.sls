#!r6rs
;; A second file: a plain direct binding and a plain callable.
(library (curl b)
  (export curl-multi-wakeup on-plain)
  (import (rnrs)
          (only (chezscheme) foreign-procedure foreign-callable))

  (define curl-multi-wakeup (foreign-procedure "curl_multi_wakeup" (uptr) int))

  (define on-plain (foreign-callable (lambda (n) n) (int) int)))
