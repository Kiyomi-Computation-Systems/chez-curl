#!r6rs
;; Review probe: a caller's timer handler raising inside make-curl-request or
;; curl-request-check of a multipart body with a file part. Each n arms the
;; timer at n ticks, with a handler that raises the symbol timer-fired, then
;; makes the request (and checks it). Tally what came out.
(import (rnrs) (only (chezscheme) set-timer timer-interrupt-handler) (curl))

(define path (let ((args (cdr (command-line)))) (car args)))
(define mode (let ((args (cdr (command-line)))) (cadr args)))

(define r0 (make-curl-request "http://127.0.0.1:9/" 'method 'post 'proxy #f
                              'body (list 'multipart (list "f" (list 'file path)))))

(define (one n)
  (guard (e ((eq? e 'timer-fired) 'sentinel)
            ((curl-request-error? e) (list 'refused (curl-request-error-reason e)))
            (#t (list 'other (if (condition? e) (condition-who e) e))))
    (timer-interrupt-handler (lambda () (raise 'timer-fired)))
    (set-timer n)
    (if (string=? mode "make")
        (make-curl-request "http://127.0.0.1:9/" 'method 'post 'proxy #f
                           'body (list 'multipart (list "f" (list 'file path))))
        (curl-request-check r0))
    (set-timer 0)
    'no-raise))

(define tally (make-hashtable equal-hash equal?))
(let loop ((n 1))
  (when (<= n 20000)
    (let ((r (one n)))
      (set-timer 0)
      (hashtable-update! tally r (lambda (c) (+ c 1)) 0) (when (and (pair? r) (eq? (car r) (quote refused))) (display n) (display " ")))
    (loop (+ n 1))))
(let-values (((keys vals) (hashtable-entries tally)))
  (vector-for-each (lambda (k v) (write (list k v)) (newline)) keys vals))
