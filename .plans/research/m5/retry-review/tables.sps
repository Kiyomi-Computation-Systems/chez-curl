#!r6rs
;; Review 3 probe, by tables: what a call raises when an earlier attempt
;; sent its request and a later one sent nothing, through ran-out and
;; through the last attempt; a post with methods (post) and a get.
(import (chezscheme)
        (curl)
        (http-client)
        (only (http-client private exchange) make-exchange exchange-submission exchange-step)
        (only (curl private conditions) make-classed-transfer-error))

(define url "http://h.example/r")
(define start 1000000000000)
(define (at ms) (+ start (* ms 1000000)))
(define U 1800000000)
(define (failure code size)
  (make-classed-transfer-error 'perform-failed code #f "a failure" #f #f size))
(define (state method policy)
  (make-exchange method url (make-curl-request url 'method method) 5000 start 20 #f policy))
(define (seen a)
  (case (car a)
    ((next) (list 'next (cadddr a)))
    ((fail) (let ((e (cadr a)))
              (list 'fail
                    (and (http-timeout? e) 'http-timeout)
                    (and (curl-transfer-error? e)
                         (list (curl-transfer-error-code e) (curl-transfer-error-request-size e)))
                    (and (http-exchange? e) (http-exchange-transfers e)))))
    ((done) (list 'done))
    (else a)))

(define (run method policy)
  (let* ((a1 (exchange-step (state method policy) (list 'failed (failure 52 85)) (at 100) U 0.0)))
    (if (not (eq? (car a1) 'next))
        (list 'first (seen a1))
        (let* ((a2 (exchange-step (cadr a1) (list 'failed (failure 7 0)) (at 300) U 0.0)))
          (list 'first (seen a1) 'second (seen a2)
                'at-deadline (if (eq? (car a2) 'next) (seen (exchange-submission (cadr a2) (at 5000))) 'n/a))))))

(printf "get, attempts 3: ~s~%" (run 'get (make-http-retry 'attempts 3 'backoff-ms 100 'jitter #f)))
(printf "get, attempts 2: ~s~%" (run 'get (make-http-retry 'attempts 2 'backoff-ms 100 'jitter #f)))
(printf "post, methods (post), attempts 3: ~s~%"
        (run 'post (make-http-retry 'attempts 3 'backoff-ms 100 'jitter #f 'methods '(post))))
(printf "post, default methods: ~s~%" (run 'post (make-http-retry 'attempts 3 'backoff-ms 100 'jitter #f)))
