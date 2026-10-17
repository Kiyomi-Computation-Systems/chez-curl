#!r6rs
;; A row marked string-not-kept clears its bindings' strings, direct,
;; through the known wrapper, and a callable's result. A mark that quotes
;; nothing clears none, and each mark clears its own kind alone: a string
;; under a bytevector-crossing mark, and a u8* under a string-not-kept
;; mark, each fail.
(library (curl m)
  (export by-name wrapped on-kept uncited as-bytes bytes-not-kept)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-callable foreign-entry?))

  (define (required-entry name library) (foreign-entry? name))

  (define-syntax bind-required
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (required-entry entry library)
         (foreign-procedure entry (arg ...) result)))))

  (define by-name (foreign-procedure "fixture_string_not_kept" (uptr string) int))

  (define wrapped (bind-required "fixture_string_not_kept" (string) uptr #f))

  (define on-kept (foreign-callable (lambda () "kept") () utf-8))

  (define uncited (foreign-procedure "fixture_string_uncited" (string) int))

  (define as-bytes (foreign-procedure "fixture_string_as_bytes" (string) int))

  (define bytes-not-kept (foreign-procedure "fixture_bytes_not_kept" (u8*) int)))
