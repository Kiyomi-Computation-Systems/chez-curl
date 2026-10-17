#!r6rs
;; The known wrapper, defined here and again in b.sls: a use cannot be read
;; against one of them.
(library (curl a)
  (export curl-easy-init)
  (import (rnrs) (only (chezscheme) foreign-procedure))

  (define-syntax bind-required
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (foreign-procedure entry (arg ...) result))))

  (define curl-easy-init (bind-required "curl_easy_init" () uptr #f)))
