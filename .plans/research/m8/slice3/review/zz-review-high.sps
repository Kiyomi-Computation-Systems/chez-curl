#!r6rs
;; Review probe: a high-level multipart call whose file goes between its
;; transfers: a 307 hop, and a retry with and without the session's bound;
;; and a group's 307 hop. What each call raises.
(import (rnrs) (curl-testing) (curl) (http-client)
        (only (chezscheme) make-time sleep)
        (only (http-client private drive) drive-step-gate-set!))

(define dir (cadr (command-line)))

(define (url o path)
  (let ((f (origin-face o 'http)))
    (string-append "http://" (car f) ":" (number->string (cdr f)) path)))

(define (fresh name)
  (let ((p (string-append dir "/" name)))
    (call-with-port (open-file-output-port p (file-options no-fail))
      (lambda (port) (put-bytevector port (string->utf8 "file bytes"))))
    p))

(define (shown e)
  (cond ((http-request-error? e) (list 'http-request-error (condition-who e) (http-request-error-reason e)))
        ((curl-request-error? e)
         (list 'curl-request-error (and (who-condition? e) (condition-who e)) (curl-request-error-field e)
               (curl-request-error-value e) (curl-request-error-reason e)
               (if (http-exchange? e) 'with-exchange 'no-exchange)))
        ((curl-transfer-error? e) (list 'transfer (curl-transfer-error-reason e)))
        ((condition? e) (list 'other (describe e)))
        (else (list 'non-condition e))))

;; gone-at-step : String -> (Symbol -> Any)
;; A gate that removes PATH at the first step's start.
(define (gone-at-step path)
  (let ((done #f))
    (lambda (where)
      (when (and (eq? where 'start) (not done))
        (set! done #t)
        (delete-file path)))))

(define (run label thunk)
  (write (cons label (guard (e (#t (list 'raised (shown e))))
                       (let ((r (thunk)))
                         (list 'answered (http-response-status r))))))
  (newline)
  (drive-step-gate-set! #f))

(call-with-origin
 (lambda (o)
   (let ((p1 (fresh "hop.bin")))
     (drive-step-gate-set! (gone-at-step p1))
     (run "hop-307"
          (lambda ()
            (call-with-http-session 'proxy #f
              (lambda (s) (http-post s (url o "/redirect/307?to=%2Fparts%3Fkey%3Dz1") 'multipart (list (list "f" (list 'file p1)))))))))
   (let ((p2 (fresh "retry-bound.bin")))
     (drive-step-gate-set! (gone-at-step p2))
     (run "retry-with-bound"
          (lambda ()
            (call-with-http-session 'proxy #f 'timeout-ms 30000
              'retry (make-http-retry 'attempts 2 'backoff-ms 100 'jitter #f 'statuses '(503) 'methods '(post))
              (lambda (s) (http-post s (url o "/parts?key=z2&fail=1") 'multipart (list (list "f" (list 'file p2)))))))))
   (let ((p3 (fresh "retry-nobound.bin")))
     (drive-step-gate-set! (gone-at-step p3))
     (run "retry-without-bound"
          (lambda ()
            (call-with-http-session 'proxy #f
              'retry (make-http-retry 'attempts 2 'backoff-ms 100 'jitter #f 'statuses '(503) 'methods '(post))
              (lambda (s) (http-post s (url o "/parts?key=z3&fail=1") 'multipart (list (list "f" (list 'file p3)))))))))
   (let ((p4 (fresh "group.bin")))
     (drive-step-gate-set! (gone-at-step p4))
     (write (cons "group-307"
                  (guard (e (#t (list 'raised (shown e))))
                    (call-with-http-session 'proxy #f
                      (lambda (s)
                        (map (lambda (r) (if (http-response? r) (list 'answered (http-response-status r)) (shown r)))
                             (http-parallel s (list (list 'post (url o "/redirect/307?to=%2Fparts%3Fkey%3Dz4")
                                                          'multipart (list (list "f" (list 'file p4))))))))))))
     (newline)
     (drive-step-gate-set! #f))))
