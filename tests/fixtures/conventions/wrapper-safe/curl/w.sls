#!r6rs
;; The known wrapper with __collect_safe in its template: every use gets it,
;; so the use whose row is plain fails and the one whose row blocks passes.
(library (curl w)
  (export curl-easy-init curl-easy-perform)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-entry?))

  (define (required-entry name library) (foreign-entry? name))

  (define-syntax bind-required
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (required-entry entry library)
         (foreign-procedure __collect_safe entry (arg ...) result)))))

  (define curl-easy-init (bind-required "curl_easy_init" () uptr #f))

  (define curl-easy-perform (bind-required "curl_easy_perform" (uptr) int #f)))
