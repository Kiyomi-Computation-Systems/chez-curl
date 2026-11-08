#!r6rs
;;; probe-claims.sps: the Headers and JSON page's claims the builder's probe
;;; did not run. Run from the repository's root (or a copy's):
;;;   $CHEZ --libdirs src:tests:build/scheme-libs --program review-scripts/probe-claims.sps
(import (rnrs) (http-client) (curl) (curl-testing))

(define (show-echo label response)
  (display "== ") (display label) (display " -> ") (display (http-response-status response)) (newline)
  (display (http-response-text response))
  (newline))

(define (refusal thunk)
  (guard (e ((curl-request-error? e)
             (list 'refused (curl-request-error-field e) (curl-request-error-reason e)))
            ((http-request-error? e)
             (list 'http-refused (http-request-error-field e) (http-request-error-reason e)))
            ((assertion-violation? e) (list 'assertion (describe e)))
            (#t (list 'raised (describe e))))
    (thunk)
    'accepted))

(define (row label thunk)
  (write (list label (refusal thunk)))
  (newline))

(define (producer text)
  (let ((sent #f))
    (lambda () (if sent (eof-object) (begin (set! sent #t) (string->utf8 text))))))

(call-with-origin
 (lambda (o)
   (let* ((face (origin-face o 'http))
          (base (string-append "http://" (car face) ":" (number->string (cdr face))))
          (url (string-append base "/echo"))
          (h2 (origin-face o 'h2c))
          (h2-url (string-append "http://" (car h2) ":" (number->string (cdr h2)) "/echo")))
     ;; "A call cannot remove a session's header": a call's user-agent #f.
     (call-with-http-session 'timeout-ms 10000 'headers '(("User-Agent" . "sess-hdr/1") ("X-A" . "1"))
       (lambda (s)
         (show-echo "session User-Agent header; call user-agent #f" (http-get s url 'user-agent #f))))
     (call-with-http-session 'timeout-ms 10000 'user-agent "sess-agent/1"
       (lambda (s)
         (show-echo "session user-agent; call user-agent #f" (http-get s url 'user-agent #f))))
     ;; "A form sends application/x-www-form-urlencoded": beside a session's
     ;; Content-Type, and beside a call's.
     (call-with-http-session 'timeout-ms 10000 'headers '(("Content-Type" . "application/json"))
       (lambda (s)
         (show-echo "session Content-Type: application/json; call form" (http-post s url 'form '(("a" . "b"))))
         (show-echo "session Content-Type: application/json; a GET" (http-get s url))
         (show-echo "session Content-Type: application/json; call multipart"
                    (http-post s (string-append base "/parts?key=review-ct") 'multipart '(("a" "b"))))))
     ;; HTTP/2: an empty value, and two of one name.
     (call-with-http-session 'timeout-ms 10000 'http-version 'http/2-prior-knowledge
       (lambda (s)
         (show-echo "h2c, Accept empty" (http-get s h2-url 'headers '(("Accept" . ""))))
         (show-echo "h2c, two X-Two" (http-get s h2-url 'headers '(("X-Two" . "a") ("x-two" . "b"))))
         (show-echo "h2c, Host named" (http-get s h2-url 'headers '(("Host" . "example.test"))))))
     ;; A call's own user-agent beside its own User-Agent header.
     (call-with-http-session 'timeout-ms 10000
       (lambda (s)
         (row "call user-agent and User-Agent header"
              (lambda () (http-get s url 'user-agent "a" 'headers '(("User-Agent" . "b")))))
         (row "call user-agent \"\"" (lambda () (http-get s url 'user-agent "")))
         (row "call headers not string pairs" (lambda () (http-get s url 'headers '(("a" . 1)))))
         (row "high level producer beside Expect: 100-continue"
              (lambda () (http-post s url 'body (producer "abc") 'headers '(("Expect" . "100-continue")))))
         (row "high level bytes body beside Expect: 100-continue"
              (lambda () (http-post s url 'body "abc" 'headers '(("Expect" . "100-continue")))))))
     (row "session user-agent \"\"" (lambda () (call-with-http-session 'user-agent "" (lambda (s) #t))))
     (row "session headers not string pairs"
          (lambda () (call-with-http-session 'headers '(("a" . 1)) (lambda (s) #t))))
     (row "session two Host" (lambda () (call-with-http-session 'headers '(("Host" . "a") ("HOST" . "b")) (lambda (s) #t))))
     (row "session user-agent beside User-Agent header"
          (lambda () (call-with-http-session 'user-agent "a" 'headers '(("user-agent" . "b")) (lambda (s) #t))))
     ;; The low level: "a stream" an Expect that holds 100-continue.
     (row "low level body stream, no stream-buffer, Expect: 100-continue"
          (lambda () (make-curl-request url 'method 'post 'body 'stream 'headers '(("Expect" . "100-continue")))))
     (row "low level stream-buffer, Expect: 100-continue"
          (lambda () (make-curl-request url 'stream-buffer 65536 'headers '(("Expect" . "100-continue")))))
     (row "low level two Host, different case"
          (lambda () (make-curl-request url 'headers '(("Host" . "a") ("hOsT" . "b")))))
     (row "low level a name holding U+00E9"
          (lambda () (make-curl-request url 'headers '(("X\xe9;" . "a")))))
     (row "low level a name holding a colon"
          (lambda () (make-curl-request url 'headers '(("X:" . "a")))))
     (row "low level a value of a lone space"
          (lambda () (make-curl-request url 'headers '(("X" . " ")))))
     (row "low level a value with VT inside" (lambda () (make-curl-request url 'headers '(("X" . "a\x0b;b")))))
     (row "low level a value ending in FF" (lambda () (make-curl-request url 'headers '(("X" . "a\x0c;"))))))))
