#!r6rs
;; The known wrapper with __collect_safe in its template: every use gets it,
;; so the use whose row is plain fails and the one whose row blocks passes.
(library (curl w)
  (export curl-easy-init curl-multi-poll)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-entry?))

  (define (required-entry name library) (foreign-entry? name))

  (define-syntax bind-required
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (required-entry entry library)
         (foreign-procedure __collect_safe entry (arg ...) result)))))

  (define curl-easy-init (bind-required "curl_easy_init" () uptr #f))

  (define curl-multi-poll (bind-required "curl_multi_poll" (uptr uptr unsigned int uptr) int #f)))
