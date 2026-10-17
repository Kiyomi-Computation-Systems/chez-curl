#!r6rs
;; Rows that name the one way their entry is bound. A binding made any other
;; way is the wrong binder, its conventions right or not:
;;   - curl_share_setopt, whose row names bind-variadic, bound through
;;     bind-varargs, a known wrapper for this tree whose template carries
;;     (__varargs_after 2) too, and directly with it;
;;   - fixture_direct, whose row names foreign-procedure, bound so, and
;;     through bind-required;
;;   - on-direct, a callable, whose row names foreign-procedure;
;;   - fixture_marked_bound, whose row is marked string-not-kept and names
;;     bind-required: the mark clears its string either way.
(library (curl w)
  (export share-setopt share-setopt-direct direct wrapped on-direct
          marked marked-direct)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-callable foreign-entry?))

  (define (required-entry name library) (foreign-entry? name))

  (define-syntax bind-required
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (required-entry entry library)
         (foreign-procedure entry (arg ...) result)))))

  (define-syntax bind-varargs
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (required-entry entry library)
         (foreign-procedure (__varargs_after 2) entry (arg ...) result)))))

  (define share-setopt (bind-varargs "curl_share_setopt" (uptr int long) int #f))

  (define share-setopt-direct
    (foreign-procedure (__varargs_after 2) "curl_share_setopt" (uptr int long) int))

  (define direct (foreign-procedure "fixture_direct" (uptr) int))

  (define wrapped (bind-required "fixture_direct" (uptr) int #f))

  (define on-direct (foreign-callable (lambda (n) n) (int) int))

  (define marked (bind-required "fixture_marked_bound" (uptr string) int #f))

  (define marked-direct (foreign-procedure "fixture_marked_bound" (uptr string) int)))
