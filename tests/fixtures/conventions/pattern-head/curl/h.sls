#!r6rs
;; Listed macros whose templates put a pattern variable at a form's head,
;; where a use can hand in any keyword: two binders and three plain macros,
;; by syntax-rules and identifier-syntax. Each is named. A binder's
;; parameter list in its foreign-procedure form is types, no form, so
;; bind-required's (arg ...) there is not; fine, with no such head, is not;
;; and any-head, a fixture's any, is held to no kind's rules.
(library (curl h)
  (export)
  (import (rnrs) (only (chezscheme) foreign-procedure))

  (define-syntax bind-required
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (library entry)
         (foreign-procedure entry (arg ...) result)))))

  (define-syntax bind-listed
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (arg ...)
         (foreign-procedure entry (arg ...) result)))))

  (define-syntax apply-head
    (syntax-rules ()
      ((_ k a) (k a))))

  (define-syntax spliced
    (syntax-rules ()
      ((_ k ...) (begin (k ...)))))

  (define-syntax setter
    (identifier-syntax
      (id 0)
      ((set! id e) (e))))

  (define-syntax fine
    (syntax-rules ()
      ((_ a) (list a))))

  (define-syntax any-head
    (syntax-rules ()
      ((_ k) (k)))))
