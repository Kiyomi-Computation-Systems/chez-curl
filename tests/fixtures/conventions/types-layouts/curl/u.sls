#!r6rs
;; (* NAME) and (& NAME) types: read when NAME is an ftype this tree's
;; (curl private layouts) defines, as parameters, as a result and in a
;; callable; unreadable when NAME is an ftype defined anywhere else, a
;; variable of layouts, or defined nowhere.
(library (curl u)
  (export pointed by-value on-pointed elsewhere variable nowhere)
  (import (rnrs)
          (only (chezscheme) foreign-procedure foreign-callable define-ftype)
          (curl private layouts))

  (define-ftype other-struct (struct (a int)))

  (define pointed
    (foreign-procedure "fixture_layout" ((* fixture-struct) uptr) (* fixture-struct)))

  (define by-value (foreign-procedure "fixture_layout" ((& fixture-struct)) int))

  (define on-pointed (foreign-callable (lambda (p) 0) ((* fixture-struct)) int))

  (define elsewhere (foreign-procedure "fixture_layout" ((* other-struct)) int))

  (define variable (foreign-procedure "fixture_layout" ((* not-an-ftype)) int))

  (define nowhere (foreign-procedure "fixture_layout" (uptr) (& no-such-struct))))
