#!r6rs
;; Bindings that hand C a bytevector's data, with no row marking any of them
;; the reviewed crossing: a direct binding's u8* parameter, another's u16*
;; and u32* parameters, and a callable's u8* result. A procedure's u8* result
;; and a callable's u8* parameter copy C's bytes into a fresh bytevector, and
;; hand C none.
(library (curl c)
  (export copy-in wide copied on-bytes on-copy)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-callable))

  (define copy-in (foreign-procedure "fixture_copy" (u8* uptr size_t) uptr))

  (define wide (foreign-procedure "fixture_wide" (uptr u16* int u32*) int))

  (define copied (foreign-procedure "fixture_result" (uptr) u8*))

  (define on-bytes (foreign-callable (lambda () (make-bytevector 4 0)) () u8*))

  (define on-copy (foreign-callable (lambda (b) 0) (u8*) int)))
