#!r6rs
;; Pattern variables spelt as types or a convention, in macros that are no
;; known wrapper: each use hands Chez another type in their place (measured:
;; bind-memcpy's use binds memcpy with two u8* parameters). Each is
;; unreadable: syntax-rules, with-syntax, identifier-syntax's set! clause, a
;; callable's result, and a convention. The known wrapper's use in a
;; syntax-case template is stray, whatever its types. A macro whose pattern
;; binds no type stays readable.
(library (curl p)
  (export copy-in through with on-pattern perform poll)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-callable foreign-entry?))

  (define (required-entry name library) (foreign-entry? name))

  (define-syntax bind-required
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (required-entry entry library)
         (foreign-procedure entry (arg ...) result)))))

  (define-syntax bind-memcpy
    (syntax-rules ()
      ((_ uptr) (foreign-procedure "memcpy" (uptr uptr size_t) uptr))))
  (define copy-in (bind-memcpy u8*))

  (define-syntax bind-through
    (lambda (x)
      (syntax-case x ()
        ((_ size_t) #'(bind-required "memcpy" (size_t) uptr #f)))))
  (define through (bind-through u8*))

  (define-syntax bind-with
    (lambda (x)
      (syntax-case x ()
        ((_ t) (with-syntax ((int #'t))
                 #'(foreign-procedure "memcpy" (uptr uptr size_t) int))))))
  (define with (bind-with scheme-object))

  (define-syntax bind-on-set
    (identifier-syntax
      (id #f)
      ((set! id uptr) (foreign-procedure "memcpy" (uptr) int))))

  (define-syntax bind-callable
    (syntax-rules ()
      ((_ name int) (define name (foreign-callable (lambda () 0) () int)))))
  (bind-callable on-pattern scheme-object)

  (define-syntax bind-perform
    (syntax-rules ()
      ((_ __collect_safe) (foreign-procedure __collect_safe "curl_easy_perform" (uptr) int))))
  (define perform (bind-perform __atomic))

  (define-syntax bind-poll
    (syntax-rules ()
      ((_ ignored) (foreign-procedure __collect_safe "curl_multi_poll" (uptr uptr unsigned int uptr) int))))
  (define poll (bind-poll 0)))
