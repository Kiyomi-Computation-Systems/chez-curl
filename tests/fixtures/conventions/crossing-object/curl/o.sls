#!r6rs
;; Bindings that hand C a Scheme object itself, or take one from C, which no
;; row may have, marked or not: a procedure's scheme-object parameter and
;; result, and a callable's scheme-object result and parameter, then a
;; scheme-object parameter under each mark. C would hold a pointer into
;; Chez's heap, where Valgrind sees nothing (ADR-0001, amended).
(library (curl o)
  (export peek on-object back on-handed marked not-kept)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-callable))

  (define peek (foreign-procedure "fixture_object" (scheme-object) int))

  (define on-object (foreign-callable (lambda () 'x) () scheme-object))

  (define back (foreign-procedure "fixture_object_result" (uptr) scheme-object))

  (define on-handed (foreign-callable (lambda (x) 0) (scheme-object) int))

  (define marked (foreign-procedure "fixture_object_marked" (scheme-object) int))

  (define not-kept (foreign-procedure "fixture_object_not_kept" (scheme-object) int)))
