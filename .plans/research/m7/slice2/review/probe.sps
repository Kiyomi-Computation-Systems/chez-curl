#!r6rs
;;; Probes beside test-auth, against the test origin. From the repository's
;;; root, in the container or a Docker lane:
;;;   scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program build/m7s2-review/probe.sps' < /dev/null
(import (rnrs) (only (chezscheme) format) (curl-testing) (curl))

(define (latin-1 bytes) (list->string (map integer->char (bytevector->u8-list bytes))))

(define (face-url o face path)
  (let ((f (origin-face o face)))
    (string-append (if (memq face '(https h2 raw-tls)) "https://" "http://")
                   (car f) ":" (number->string (cdr f)) path)))

(define (outcome x)
  (cond ((curl-response? x) (list 'response (curl-response-status x) 'effective (curl-response-effective-url x)))
        ((curl-transfer-error? x) (list 'failed (curl-transfer-error-reason x) (curl-transfer-error-code x)))
        ((condition? x) (list 'raised (describe x)))
        (else x)))

(define (run e request)
  (let ((t (guard (c (#t (list 'refused (describe c)))) (curl-submit e request))))
    (if (curl-token? t)
        (if (curl-token-wait t 30000) (outcome (curl-token-outcome t)) (begin (curl-token-cancel t) 'hung))
        t)))

(define (log-of e o key)
  (let ((r (run e (make-curl-request (face-url o 'http (string-append "/auth-log?key=" key)) 'proxy #f))))
    r))

(define (log-text e o key)
  (let ((t (curl-submit e (make-curl-request (face-url o 'http (string-append "/auth-log?key=" key)) 'proxy #f))))
    (curl-token-wait t 10000)
    (let ((r (curl-token-outcome t)))
      (if (curl-response? r) (latin-1 (curl-response-body r)) r))))

(define (pattern n)
  (let ((bv (make-bytevector n)))
    (let loop ((i 0)) (when (< i n) (bytevector-u8-set! bv i (mod i 251)) (loop (+ i 1))))
    bv))

(display (format "libcurl ~a~%" (libcurl-info-version (loaded-libcurl))))
(call-with-origin
 (lambda (o)
   (let ((e (make-curl-engine)))
     (for-each
      (lambda (c)
        (let* ((key (car c)) (face (cadr c)) (path (caddr c)) (keys (cdddr c))
               (answer (run e (apply make-curl-request (face-url o face path) 'proxy #f 'timeout-ms 15000 keys))))
          (display (format "~a: ~s~%~a~%" key answer (log-text e o key)))))
      (list
       (list "eff-basic" 'http "/auth?key=eff-basic&ch=basic" 'credentials '(basic "user" "pass"))
       (list "pk-digest-get" 'h2c "/auth?key=pk-digest-get&ch=digest&qop=none&nonce=pkg" 'http-version 'http/2-prior-knowledge
             'credentials '(digest "user" "pass"))
       (list "pk-digest-post" 'h2c "/auth?key=pk-digest-post&ch=digest&qop=none&nonce=pkp" 'http-version 'http/2-prior-knowledge
             'method 'post 'body (pattern 1024) 'credentials '(digest "user" "pass"))
       (list "pk-basic-post" 'h2c "/auth?key=pk-basic-post&ch=basic" 'http-version 'http/2-prior-knowledge
             'method 'post 'body (pattern 1024) 'credentials '(basic "user" "pass"))
       (list "digest-put" 'http "/auth?key=digest-put&ch=open" 'method 'put 'body (pattern 1024)
             'credentials '(digest "user" "pass"))
       (list "digest-307-like-post-64k" 'http "/auth?key=digest-307-like-post-64k&ch=digest&qop=none&nonce=big"
             'method 'post 'body (pattern 65536) 'credentials '(digest "user" "pass"))))
     (curl-engine-stop e))))
