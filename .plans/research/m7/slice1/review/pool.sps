#!r6rs
;; Review probe: does a pooled connection carry one request's version to the
;; next on one engine? (a) prior knowledge to h2c, then #f to h2c; (b) #f to
;; the http face, then prior knowledge to it; each pair on its own engine,
;; with a fresh-engine control for the second request.
(import (rnrs) (curl) (curl-testing))

(define (url o face path)
  (let ((f (origin-face o face)))
    (string-append "http://" (car f) ":" (number->string (cdr f)) path)))

(define (outcome thunk)
  (guard (e ((curl-transfer-error? e) (list 'failed (curl-transfer-error-code e)))
            (#t (list 'raised (describe e))))
    (let ((r (thunk)))
      (list (curl-response-status r) (curl-response-http-version r)))))

(define (get engine u v)
  (outcome (lambda () (curl-token-await (curl-submit engine (make-curl-request u 'proxy #f 'timeout-ms 10000 'http-version v))))))

(define (pair o face v1 v2)
  (let* ((e (make-curl-engine))
         (first (get e (url o face "/echo") v1))
         (second (get e (url o face "/echo") v2)))
    (curl-engine-stop e)
    (let* ((f (make-curl-engine))
           (alone (get f (url o face "/echo") v2)))
      (curl-engine-stop f)
      (list face v1 '-> v2 'first first 'second second 'second-alone alone))))

(call-with-origin
 (lambda (o)
   (write (list 'version (libcurl-info-version (loaded-libcurl)))) (newline)
   (for-each (lambda (args) (write (apply pair o args)) (newline))
             '((h2c http/2-prior-knowledge #f)
               (h2c http/2-prior-knowledge http/2)
               (h2c http/2-prior-knowledge http/1.1)
               (http #f http/2-prior-knowledge)
               (http http/1.1 http/2-prior-knowledge)))))
(exit 0)
