#!r6rs
;; Types the reader cannot read, so cannot clear: a string among the
;; parameters, a list that is no (* name) or (& name), a callable's result
;; that is no type, and uses of the known wrapper whose parameter list is a
;; variable, an improper list, or missing. Then types on no allowlist: a
;; name that is no Chez type, void as a parameter, ptr and utf-16 (which
;; Chez takes, as scheme-object and a string), a procedure's result, a
;; callable's parameter, and a wrapper use's result.
(library (curl t)
  (export a b on-bytes c d e unknown void-parameter alias wide-string
          unknown-result on-unknown f)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-callable foreign-entry?))

  (define (required-entry name library) (foreign-entry? name))

  (define-syntax bind-required
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (required-entry entry library)
         (foreign-procedure entry (arg ...) result)))))

  (define a (foreign-procedure "fixture_wide" (uptr "u8*") int))

  (define b (foreign-procedure "fixture_wide" ((u8*)) int))

  (define on-bytes (foreign-callable (lambda () 0) () (u8*)))

  (define args '(u8* uptr size_t))

  (define c (bind-required "memcpy" args uptr #f))

  (define d (bind-required "memcpy" (uptr . u8*) uptr #f))

  (define e (bind-required "memcpy"))

  (define unknown (foreign-procedure "fixture_wide" (uint32_t) int))

  (define void-parameter (foreign-procedure "fixture_wide" (void) int))

  (define alias (foreign-procedure "fixture_wide" (ptr) int))

  (define wide-string (foreign-procedure "fixture_wide" (utf-16) int))

  (define unknown-result (foreign-procedure "fixture_result" (uptr) uint32_t))

  (define on-unknown (foreign-callable (lambda (n) 0) (uint32_t) int))

  (define f (bind-required "fixture_result" (uptr) ptr #f)))
