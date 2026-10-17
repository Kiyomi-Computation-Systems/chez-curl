#!r6rs
;; A second file: a use of the wrapper a.sls defines, a plain direct binding
;; and a plain callable.
(library (curl b)
  (export curl-global-init curl-multi-perform on-plain)
  (import (rnrs)
          (curl a)
          (only (chezscheme) foreign-procedure foreign-callable))

  (define curl-global-init (bind-required "curl_global_init" (long) int #f))

  (define curl-multi-perform (foreign-procedure "curl_multi_perform" (uptr uptr) int))

  (define on-plain (foreign-callable (lambda (n) n) (int) int)))
