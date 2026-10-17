#!r6rs
;; Plain macros whose transformers can take their operands apart, or build
;; syntax from data: syntax-case, with-syntax, and syntax->datum with
;; datum->syntax. Each name is named.
(library (curl t)
  (export)
  (import (rnrs))

  (define-syntax by-case
    (lambda (x)
      (syntax-case x ()
        ((_ e) #'e))))

  (define-syntax by-with
    (lambda (x)
      (with-syntax ((e #'0)) #'e)))

  (define-syntax by-datum
    (lambda (x)
      (datum->syntax x (cadr (syntax->datum x))))))
