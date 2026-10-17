#!r6rs
;; A use of the known wrapper, which no file in the tree defines.
(library (curl u)
  (export curl-easy-init)
  (import (rnrs))

  (define curl-easy-init (bind-required "curl_easy_init" () uptr #f)))
