#!r6rs
;; Occurrences that are neither imported, nor a form's head: each is named.
(library (curl s)
  (export fp)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-callable))

  (define fp foreign-procedure)

  (define (call-it) (let ((f foreign-callable)) f))

  ;; an improper tail: a rest argument named foreign-callable
  (define (rest . foreign-callable) 0)

  (define-syntax alias (identifier-syntax foreign-procedure)))
