#!r6rs
;; Bindings that hand C a string Chez copied into its own heap, with no row
;; marking any of them string-not-kept: a string parameter, a parameter of
;; each other string type, a string parameter through the known wrapper,
;; and a callable's utf-8 result. A procedure's utf-8 result and a
;; callable's string parameter copy C's bytes into a fresh Scheme string,
;; and hand C none.
(library (curl s)
  (export by-name every wrapped name-of on-name on-named)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-callable foreign-entry?))

  (define (required-entry name library) (foreign-entry? name))

  (define-syntax bind-required
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (required-entry entry library)
         (foreign-procedure entry (arg ...) result)))))

  (define by-name (foreign-procedure "fixture_string" (string) uptr))

  (define every
    (foreign-procedure "fixture_strings" (utf-8 utf-16le utf-16be utf-32le utf-32be wstring) int))

  (define wrapped (bind-required "fixture_string" (uptr string) int #f))

  (define name-of (foreign-procedure "fixture_string_result" (uptr) utf-8))

  (define on-name (foreign-callable (lambda () "name") () utf-8))

  (define on-named (foreign-callable (lambda (s) 0) (string) int)))
