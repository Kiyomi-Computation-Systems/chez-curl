#!r6rs
;;; Prints, for each export of (curl), (curl unsupported) and (http-client),
;;; a row: (NAME type) for what is no procedure, (NAME none) for a procedure
;;; that takes no argument, else (NAME ARITY ANSWER), ANSWER what calling it
;;; at its least arity of 1 or more, every argument the secret URL, raised.
(import (chezscheme) (curl) (curl unsupported) (http-client))
(define url "http://u:Pr0xyS3cr3t@h/")
(define env (environment '(chezscheme) '(curl) '(curl unsupported) '(http-client)))
(define (answer thunk)
  (call/cc
   (lambda (k)
     (with-exception-handler
      (lambda (e)
        (k (cond ((curl-request-error? e) (list 'curl-request-error (curl-request-error-field e) (curl-request-error-value e) (curl-request-error-reason e)))
                 ((http-request-error? e) (list 'http-request-error (http-request-error-field e) (http-request-error-value e) (http-request-error-reason e)))
                 ((curl-url-error? e) (list 'curl-url-error (curl-url-error-reason e)))
                 ((assertion-violation? e) (list 'assertion (and (who-condition? e) (condition-who e)) (and (irritants-condition? e) (condition-irritants e))))
                 (else (list 'other (and (who-condition? e) (condition-who e)))))))
      (lambda () (thunk) 'no-raise)))))
(for-each
 (lambda (lib)
   (for-each
    (lambda (name)
      (let ((v (guard (e (#t 'not-a-value)) (eval name env))))
        (if (eq? v 'not-a-value) (write (list name 'syntax))
        (cond ((not (procedure? v)) (write (list name 'value)))
              (else
               (let* ((mask (procedure-arity-mask v))
                      (n (let loop ((n 1)) (cond ((> n 4) #f) ((logbit? n mask) n) (else (loop (+ n 1)))))))
                 (if n
                     (write (list name n (answer (lambda () (apply v (make-list n url))))))
                     (write (list name 'none)))))))
        (newline)))
    (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) (library-exports lib))))
 '((curl) (curl unsupported) (http-client)))
