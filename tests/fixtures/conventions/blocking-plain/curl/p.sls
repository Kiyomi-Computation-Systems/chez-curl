#!r6rs
;; ADR-0013's rows, each broken: three calls that block bound plain, one
;; through the known wrapper, and memcpy, which cannot block, bound
;; __collect_safe. memcpy's u8* is the crossing its row marks, which clears
;; it as a crossing, but not its convention: a marked row is never
;; __collect_safe (ADR-0013's decision 4).
(library (curl p)
  (export curl-easy-perform curl-multi-poll curl-multi-perform memcpy)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-entry?))

  (define (required-entry name library) (foreign-entry? name))

  (define-syntax bind-required
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (required-entry entry library)
         (foreign-procedure entry (arg ...) result)))))

  (define curl-easy-perform (bind-required "curl_easy_perform" (uptr) int #f))

  (define curl-multi-poll (foreign-procedure "curl_multi_poll" (uptr uptr unsigned int uptr) int))

  (define curl-multi-perform (foreign-procedure "curl_multi_perform" (uptr uptr) int))

  (define memcpy (foreign-procedure __collect_safe "memcpy" (u8* uptr size_t) uptr)))
