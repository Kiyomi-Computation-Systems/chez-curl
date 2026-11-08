;; kinds.sps: each export of the three public libraries, with its kind as
;; Chez sees it: procedure, value (its printed shape), or syntax (a name
;; that is no expression: a condition type's, or a macro's). Read-only.
(import (chezscheme))
(define (kind-of lib name)
  (let ((env (environment lib)))
    (guard (e (#t (list 'syntax)))
      (let ((v (eval name env)))
        (cond ((procedure? v) (list 'procedure))
              ((and (list? v) (for-all symbol? v)) (list 'value 'symbol-list (length v)))
              (else (list 'value 'other)))))))
(for-each
 (lambda (lib)
   (for-each (lambda (name) (write (cons* lib name (kind-of lib name))) (newline))
             (sort (lambda (a b) (string<? (symbol->string a) (symbol->string b)))
                   (library-exports lib))))
 (begin (eval '(import (curl) (curl unsupported) (http-client)))
        '((curl) (curl unsupported) (http-client))))
