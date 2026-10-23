#!r6rs
;; Crossings through known wrappers: bind-required, as native.sls writes it,
;; whose uses pass their parameter list and their result, and bind-bytes,
;; whose template's own parameter list holds u8*. A use whose result is u8*
;; hands C nothing; one whose result is scheme-object is never allowed.
(library (curl w)
  (export copy-in copied bytes object-back)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-entry?))

  (define (required-entry name library) (foreign-entry? name))

  (define-syntax bind-required
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (required-entry entry library)
         (foreign-procedure entry (arg ...) result)))))

  (define-syntax bind-bytes
    (syntax-rules ()
      ((_ entry) (foreign-procedure entry (u8* uptr size_t) uptr))))

  (define copy-in (bind-required "fixture_copy" (u8* uptr size_t) uptr #f))

  (define copied (bind-required "fixture_result" (uptr) u8* #f))

  (define bytes (bind-bytes "fixture_bytes"))

  (define object-back (bind-required "fixture_object_result" (uptr) scheme-object #f)))
