#!r6rs
;;; errors.sps: what a call answers, and what it raises: a status is data;
;;; a timeout, a body too large and a refused request are conditions.
;;; Run it from the repository's root, URL the test server's base URL with no
;;; trailing / (docs/README.md says how to start one):
;;;   scheme --libdirs src --program examples/errors.sps URL
(import (rnrs) (curl) (http-client))

(define base (cadr (command-line)))

(define (url path) (string-append base path))

(define (show x)
  (write x)
  (newline))

(call-with-http-session 'timeout-ms 10000
  (lambda (session)
    ;; A 404 is an answer, not an error.
    (show (http-response-status (http-get session (url "/status/404"))))
    ;; The call's timeout-ms passed: &http-timeout, with (curl)'s &curl-timeout.
    (show (guard (e ((http-timeout? e)
                     (list 'timeout (http-timeout-timeout-ms e) (curl-timeout? e))))
            (http-get session (url "/pattern/10?delay=2000") 'timeout-ms 200)))
    ;; A body past body-limit: &curl-too-large. This one's Content-Length
    ;; says so before any byte comes, so libcurl refuses it, perform-failed.
    (show (guard (e ((curl-too-large? e)
                     (list 'too-large (curl-transfer-error-reason e))))
            (http-get session (url "/pattern/100000") 'body-limit 1000)))
    ;; A request refused before anything is sent: &curl-request-error,
    ;; naming the field and the reason, never a secret.
    (show (guard (e ((curl-request-error? e)
                     (list (curl-request-error-field e) (curl-request-error-reason e))))
            (curl-request-check
             (make-curl-request "https://example.invalid/"
                                'http-version 'http/2-prior-knowledge))))
    ;; Every chez-curl condition is a &curl-error.
    (show (guard (e ((curl-error? e) 'curl-error))
            (http-get session (url "/status/200") 'body #vu8(1))))))
