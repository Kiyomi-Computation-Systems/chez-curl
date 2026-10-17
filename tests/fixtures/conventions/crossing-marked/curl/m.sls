#!r6rs
;; A row marked as the reviewed crossing: its bindings may hand C a
;; bytevector's data, directly and through the known wrapper. A row whose
;; mark quotes no record marks nothing.
(library (curl m)
  (export to-foreign from-foreign uncited)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-entry?))

  (define (required-entry name library) (foreign-entry? name))

  (define-syntax bind-required
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (required-entry entry library)
         (foreign-procedure entry (arg ...) result)))))

  (define to-foreign (foreign-procedure "fixture_crossing" (uptr u8* size_t) uptr))

  (define from-foreign (bind-required "fixture_crossing" (u8* uptr size_t) uptr #f))

  (define uncited (foreign-procedure "fixture_crossing_uncited" (u8* size_t) void)))
