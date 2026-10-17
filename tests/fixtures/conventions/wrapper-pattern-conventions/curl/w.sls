#!r6rs
;; The known wrapper takes its conventions from a pattern variable, so no
;; reading of the template says what a use binds.
(library (curl w)
  (export curl-easy-init)
  (import (rnrs) (only (chezscheme) foreign-procedure))

  (define-syntax bind-required
    (syntax-rules ()
      ((_ conv entry (arg ...) result library)
       (foreign-procedure conv entry (arg ...) result))))

  (define curl-easy-init (bind-required __collect_safe "curl_easy_init" () uptr #f)))
