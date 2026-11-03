#!r6rs
;;; M7 slice 3's second fix round: every export of (curl), (curl unsupported)
;;; and (http-client) that is a procedure, called with a string holding a
;;; password as every argument, at each arity from 1 to 3 it takes: whether
;;; it raised, and whether what it raised prints the password. Arity 0, and
;;; anything that is not a procedure, is skipped and named so.
(import (chezscheme) (curl) (curl unsupported) (http-client))

(define secret "Pr0xyS3cr3t")
(define url (string-append "http://u:" secret "@h/"))

(define (contains? text part)
  (let ((n (string-length text)) (k (string-length part)))
    (let loop ((i 0))
      (and (<= (+ i k) n) (or (string=? (substring text i (+ i k)) part) (loop (+ i 1)))))))

(define (printed x)
  (call-with-string-output-port
   (lambda (p) (write x p) (newline p) (display x p) (newline p) (when (condition? x) (display-condition x p)))))

(define env (environment '(chezscheme) '(curl) '(curl unsupported) '(http-client)))

(for-each
 (lambda (lib)
   (for-each
    (lambda (name)
      (let ((v (guard (e (#t 'not-a-value)) (eval name env))))
        (if (not (procedure? v))
            (begin (display name) (display ": not a procedure") (newline))
            (let ((mask (procedure-arity-mask v)))
              (for-each
               (lambda (n)
                 (when (logbit? n mask)
                   (let* ((raised (call/cc (lambda (k)
                                             (with-exception-handler
                                              (lambda (e) (k (list 'raised e)))
                                              (lambda () (apply v (make-list n url)) 'no-raise)))))
                          (text (if (pair? raised) (printed (cadr raised)) "")))
                     (display name) (display "/") (display n) (display ": ")
                     (display (if (pair? raised) "raised" "no raise"))
                     (display (if (contains? text secret) "; secret printed: YES" "; secret printed: no"))
                     (when (contains? text secret)
                       (display "  ")
                       (write (substring text 0 (min 200 (string-length text)))))
                     (newline))))
               '(1 2 3))))))
    (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) (library-exports lib))))
 '((curl) (curl unsupported) (http-client)))
(exit 0)
