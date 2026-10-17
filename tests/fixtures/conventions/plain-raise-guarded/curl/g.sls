#!r6rs
;; A9: plain transformers whose input goes only to syntax-violation, with a
;; handler around the call that takes the input back from the condition,
;; by syntax-violation-form, and hands it to rebuild: by guard, and by
;; with-exception-handler. Measured with guard, Chez binds the entry
;; rebuild chooses. Neither call is in tail position: named.
(library (curl g)
  (export)
  (import (rnrs) (curl h))

  (define-syntax by-guard
    (lambda (x)
      (guard (c (#t (rebuild (syntax-violation-form c))))
        (syntax-violation 'by-guard "never" x))))

  (define-syntax by-handler
    (lambda (x)
      (call/cc
        (lambda (k)
          (with-exception-handler
            (lambda (c) (k (rebuild (syntax-violation-form c))))
            (lambda () (syntax-violation 'by-handler "never" x))))))))
