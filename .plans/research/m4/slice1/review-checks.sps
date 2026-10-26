;; M4 slice 1, the review's checks, reproduced (2026-10-26). Run from the repository's
;; root, in the container:
;;   scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m4/slice1/review-checks.sps'
;; It prints: a GET with HEADER at 1 through the test seam, refused as owned since the review
;; (before, its body began with the response's head); the request size of a
;; POST of 5 bytes, then of 100,000, each timing out before any answer, on an engine of its
;; own; and the timings of two GETs over one https connection, the second reusing it.
(import (rnrs) (only (chezscheme) parameterize) (curl-testing) (curl) (curl private engine) (curl private transfer))
(define engine (make-curl-engine))
(define (url-of o face path)
  (let ((f (origin-face o face)))
    (string-append "http://" (car f) ":" (number->string (cdr f)) path)))
(define (run thunk)
  (guard (e ((curl-transfer-error? e) (list 'refused (curl-transfer-error-reason e) (curl-transfer-error-code e) (curl-transfer-error-request-size e)))
            (#t (list 'raised (describe e))))
    (thunk)))
(define (await t) (curl-token-await t))
(define pki (make-test-pki))
(parameterize ((origin-pki pki))
  (call-with-origin
   (lambda (o)
     ;; HEADER through the seam: does the response head land in the body?
     (display (run (lambda () (let ((r (await (curl-engine-submit-with engine (make-curl-request (url-of o 'http "/status/200")) '(("HEADER" . 1))))))
                                (utf8->string (curl-response-body r))))))
     (newline)
     ;; request size of a POST with a 5-byte body that times out before any answer, on a fresh engine
     (let ((e2 (make-curl-engine)))
       (display (run (lambda () (await (curl-engine-submit e2 (make-curl-request (url-of o 'raw "/raw/stall-before-head") 'method 'post 'body (string->utf8 "hello") 'timeout-ms 300))))))
       (newline)
       (display (run (lambda () (await (curl-engine-submit e2 (make-curl-request (url-of o 'raw "/raw/stall-before-head") 'method 'post 'body (make-bytevector 100000 65) 'timeout-ms 300))))))
       (newline)
       (curl-engine-stop e2))
     ;; timings on a reused https connection
     (let* ((f (origin-face o 'https))
            (u (string-append "https://" (car f) ":" (number->string (cdr f)) "/status/200"))
            (r1 (await (curl-engine-submit engine (make-curl-request u 'ca-file (string-append pki "/ca.pem")))))
            (r2 (await (curl-engine-submit engine (make-curl-request u 'ca-file (string-append pki "/ca.pem"))))))
       (write (list (curl-response-timings r1) (curl-response-timings r2))) (newline)))))
(curl-engine-stop engine)
