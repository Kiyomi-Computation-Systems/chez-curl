#!r6rs
(library (curl ok)
  (export curl-easy-init)
  (import (rnrs) (only (chezscheme) foreign-procedure))
  (define curl-easy-init (foreign-procedure "curl_easy_init" () uptr)))
