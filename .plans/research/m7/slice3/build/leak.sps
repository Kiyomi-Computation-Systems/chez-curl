#!r6rs
;;; M7 slice 3's leak probe, after slice 2's review's leak.sps: every exit a
;;; request with a proxy password in its proxy URL can take, and whether
;;; the password is in what write, display or display-condition print for
;;; it. Run from the repository's root, in the container or a Docker lane:
;;;   scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m7/slice3/build/leak.sps' < /dev/null
;;; Each line: LABEL: secret printed: YES or no, then the text, cut.
(import (rnrs) (only (chezscheme) display-condition format parameterize)
        (curl) (curl unsupported) (http-client) (curl-testing)
        (only (curl private transfer) prepare-transfer proxy-settings)
        (only (http-client private call) form-encode))

(define secret "Pr0xyS3cr3t")
(define encoded "Pr0xy%53%33cr3t")

;; holds? : String -> Boolean
(define (holds? text)
  (define (has part)
    (let ((n (string-length text)) (k (string-length part)))
      (let loop ((i 0))
        (and (<= (+ i k) n) (or (string=? (substring text i (+ i k)) part) (loop (+ i 1)))))))
  (or (has secret) (has "S3cr3t") (has "UHIweHlTM2NyM3Q") (has "%53%33")))

;; printed : Any -> String
(define (printed x)
  (call-with-string-output-port
   (lambda (p)
     (write x p) (newline p) (display x p) (newline p)
     (when (condition? x) (display-condition x p)))))

(define (line label text)
  (display (format "~a: secret printed: ~a~%  ~a~%" label (if (holds? text) "YES" "no")
                   (let ((one (list->string (map (lambda (c) (if (char=? c #\newline) #\space c)) (string->list text)))))
                     (if (> (string-length one) 300) (string-append (substring one 0 300) "...") one))))
  (flush-output-port (current-output-port)))

;; raised : (-> Any) -> Any
(define (raised thunk) (guard (e (#t e)) (thunk) 'no-raise))

(define pki (make-test-pki))
(define ca (string-append pki "/ca.pem"))

(define (hostport o face) (let ((f (origin-face o face))) (string-append (car f) ":" (number->string (cdr f)))))

(parameterize ((origin-pki pki))
  (call-with-origin
   (lambda (o)
     (let* ((http (hostport o 'http)) (https (hostport o 'https))
            (with (lambda (scheme host) (string-append scheme "://alice:" secret "@" host)))
            (nowhere "http://127.0.0.1:1/")
            (check-proxy (lambda (proxy . keys) (curl-request-check (apply make-curl-request nowhere 'proxy proxy keys)))))
       ;; refusals at construction, check and submit
       (for-each
        (lambda (c) (line (car c) (printed (raised (cadr c)))))
        (list (list "refusal proxy-url (no scheme)" (lambda () (check-proxy (string-append "alice:" secret "@h:1"))))
              (list "refusal proxy-url (a %)" (lambda () (check-proxy (string-append "http://u%zz:" secret "@h:1"))))
              (list "refusal proxy-url (raw control)" (lambda () (check-proxy (string-append "http://u:" secret "\x1;@h:1"))))
              (list "refusal proxy-url (not UTF-8 host)" (lambda () (check-proxy (string-append "http://u:" secret "@caf%E9.x:1"))))
              (list "refusal proxy-url (U+0000)" (lambda () (check-proxy (string-append "http://u:" secret "\x0;@h:1"))))
              (list "refusal proxy-scheme" (lambda () (check-proxy (with "socks5" "h:1"))))
              (list "refusal proxy-url-parts" (lambda () (check-proxy (string-append (with "http" "h:1") "/p?" secret))))
              (list "refusal credentials-bytes (user)" (lambda () (check-proxy (string-append "http://a%01:" secret "@h:1"))))
              (list "refusal credentials-bytes (password)" (lambda () (check-proxy (string-append "http://a:" encoded "%FF@h:1"))))
              (list "refusal credentials-empty" (lambda () (check-proxy "http://:@h:1")))
              (list "refusal proxy-tls-without-https-proxy" (lambda () (check-proxy (with "http" "h:1") 'proxy-verify #f)))
              (list "refusal prior-knowledge-through-proxy" (lambda () (check-proxy (with "http" "h:1") 'http-version 'http/2-prior-knowledge)))
              (list "refusal proxy-tls-in-tls (or none here)"
                    (lambda () (curl-request-check (make-curl-request "https://127.0.0.1:1/" 'proxy (with "https" "h:1")))))
              (list "refusal proxy-authorization-header"
                    (lambda () (make-curl-request nowhere 'headers (list (cons "Proxy-Authorization" (string-append "Basic " secret "\r\n"))))))
              (list "refusal a wrong-shaped proxy" (lambda () (make-curl-request nowhere 'proxy (list (with "http" "h:1")))))
              (list "refusal the hatch's PROXYUSERPWD"
                    (lambda () (curl-request-with-options (make-curl-request nowhere) (list (cons "PROXYUSERPWD" (string-append "u:" secret))))))
              (list "refusal the hatch's PROXY"
                    (lambda () (curl-request-with-options (make-curl-request nowhere) (list (cons "PROXY" (with "http" "h:1"))))))
              (list "refusal proxy-settings' wrong proxy" (lambda () (proxy-settings (list (with "http" "h:1")) #f #t)))
              (list "refusal a submit's proxy-url"
                    (lambda ()
                      (let* ((e (make-curl-engine))
                             (c (raised (lambda () (curl-submit e (make-curl-request nowhere 'proxy (string-append "alice:" secret "@h:1")))))))
                        (curl-engine-stop e)
                        (raise c))))
              (list "refusal a session's proxy-url at a call"
                    (lambda () (call-with-http-session 'proxy (string-append "u:" secret "@h:1") (lambda (s) (http-get s nowhere)))))
              (list "refusal call-with-http-session, its procedure missing, a proxy URL last"
                    (lambda () (call-with-http-session 'proxy (string-append "u:" secret "@h:1"))))))
       ;; the records
       (let ((r (make-curl-request nowhere 'proxy (with "http" "127.0.0.1:1"))))
         (line "the request" (printed r))
         (line "its plan" (printed (raised (lambda () (prepare-transfer r))))))
       ;; transfer failures, each with its token, and their error buffers
       (for-each
        (lambda (c)
          (let* ((e (make-curl-engine))
                 (t (curl-submit e (apply make-curl-request (cadr c) 'timeout-ms 10000 (cddr c)))))
            (curl-token-wait t 20000)
            (let ((outcome (curl-token-outcome t)))
              (line (string-append "failure " (car c)) (printed outcome))
              (line (string-append "  its error buffer: " (car c))
                    (if (curl-transfer-error? outcome) (or (curl-transfer-error-error-buffer outcome) "#f") "not a failure"))
              (line (string-append "  its token: " (car c)) (printed t))
              (line (string-append "  a stream operation on it: " (car c)) (printed (raised (lambda () (curl-token-next-piece t 10))))))
            (curl-engine-stop e)))
        (list (list "a CONNECT refused 407 for the password" (string-append "https://localhost:" (number->string (cdr (origin-face o 'https))) "/") 'proxy (with "http" http) 'ca-file ca)
              (list "a CONNECT refused 503" "https://refuse-503.invalid:443/" 'proxy (with "http" http))
              (list "a CONNECT the proxy closes" "https://close.invalid:443/" 'proxy (with "http" http))
              (list "a proxy whose port refuses" "http://127.0.0.1:2/" 'proxy (with "http" "127.0.0.1:1"))
              (list "a proxy whose leaf fails" (string-append "http://" http "/") 'proxy (with "https" (hostport o 'https-expired)) 'proxy-ca-file ca)
              (list "a proxy's leaf against another CA" (string-append "http://" http "/") 'proxy (with "https" https) 'proxy-ca-file (string-append pki "/other-ca.pem"))
              (list "the origin's TLS inside the tunnel" (string-append "https://" https "/") 'proxy (with "http" http) 'ca-file (string-append pki "/other-ca.pem"))
              (list "a timeout" "https://refuse-503.invalid:443/" 'proxy (with "http" "10.255.255.1:9") 'connect-timeout-ms 1)))
       ;; the fix round: a secret where another value belongs (the review's
       ;; keys-leak.sps, and the audit's)
       (let ((url (with "http" "127.0.0.1:3128")))
         (for-each
          (lambda (c) (line (car c) (printed (raised (cadr c)))))
          (list (list "misplaced: the proxy URL where a key belongs, make-curl-request" (lambda () (make-curl-request nowhere url)))
                (list "misplaced: after a key's value, make-curl-request" (lambda () (make-curl-request nowhere 'timeout-ms 5000 url 'x)))
                (list "misplaced: curl-request-with" (lambda () (curl-request-with (make-curl-request nowhere) url "x")))
                (list "misplaced: make-http-session" (lambda () (make-http-session url)))
                (list "misplaced: make-http-session, a value after it" (lambda () (make-http-session url 'x)))
                (list "misplaced: call-with-http-session" (lambda () (call-with-http-session url (lambda (s) 'ran))))
                (list "misplaced: http-get" (lambda () (let ((s (make-http-session)))
                                                         (dynamic-wind (lambda () #f) (lambda () (http-get s nowhere url))
                                                                       (lambda () (http-session-close s))))))
                (list "misplaced: credentials where a key belongs, make-curl-request" (lambda () (make-curl-request nowhere (list 'basic "alice" secret))))
                (list "misplaced: credentials where a key belongs, make-http-session" (lambda () (make-http-session (list 'basic "alice" secret))))
                (list "misplaced: headers of a wrong type holding an Authorization"
                      (lambda () (make-curl-request nowhere 'headers (list (cons "Authorization" (string-append "Bearer " secret)) (cons "X" 5)))))
                (list "misplaced: an Authorization value refused" (lambda () (make-curl-request nowhere 'headers (list (cons "Authorization" (string-append "Bearer " secret "\r\n"))))))
                (list "misplaced: a body of a wrong type" (lambda () (let ((s (make-http-session)))
                                                                      (dynamic-wind (lambda () #f) (lambda () (http-post s nowhere 'body (list secret)))
                                                                                    (lambda () (http-session-close s))))))
                (list "misplaced: a URL where a request belongs" (lambda () (let ((e (make-curl-engine)))
                                                                               (dynamic-wind (lambda () #f) (lambda () (curl-submit e url))
                                                                                             (lambda () (curl-engine-stop e))))))
                (list "misplaced: a URL where a session belongs" (lambda () (http-get url nowhere)))
                (list "misplaced: a URL where a token belongs" (lambda () (curl-token-wait url 10)))
                (list "misplaced: a hatch value of a wrong type" (lambda () (curl-request-with-options (make-curl-request nowhere) (list (cons "LOW_SPEED_TIME" secret)))))
                (list "misplaced: http-parallel's specs a string" (lambda () (let ((s (make-http-session)))
                                                                                (dynamic-wind (lambda () #f) (lambda () (http-parallel s url))
                                                                                              (lambda () (http-session-close s))))))
                (list "misplaced: form-encode given a string" (lambda () (form-encode url))))))
       ;; the second fix round: an accessor handed a string, and a refused URL
       (let ((url (with "http" "127.0.0.1:3128")))
         (for-each
          (lambda (c) (line (car c) (printed (raised (cadr c)))))
          (list (list "accessor: curl-request-url" (lambda () (curl-request-url url)))
                (list "accessor: curl-response-status" (lambda () (curl-response-status url)))
                (list "accessor: curl-head-headers" (lambda () (curl-head-headers url)))
                (list "accessor: http-response-status" (lambda () (http-response-status url)))
                (list "accessor: http-exchange-url" (lambda () (http-exchange-url url)))
                (list "accessor: curl-url-error-input" (lambda () (curl-url-error-input url)))
                (list "accessor: curl-transfer-error-error-buffer" (lambda () (curl-transfer-error-error-buffer url)))
                (list "accessor: http-request-error-value" (lambda () (http-request-error-value url)))
                (list "accessor: libcurl-info-path" (lambda () (libcurl-info-path url)))
                (list "URL: scheme-not-http at check" (lambda () (curl-request-check (make-curl-request (with "ftp" "h")))))
                (list "URL: scheme-not-http at submit"
                      (lambda () (let ((e (make-curl-engine)))
                                   (dynamic-wind (lambda () #f) (lambda () (curl-submit e (make-curl-request (with "ftp" "h"))))
                                                 (lambda () (curl-engine-stop e))))))
                (list "URL: a parse failure at check" (lambda () (curl-request-check (make-curl-request (string-append (with "http" "h") " /")))))
                (list "URL: embedded-nul at check" (lambda () (curl-request-check (make-curl-request (string-append (with "http" "h") "/\x0;")))))
                (list "URL: not-utf-8 at check" (lambda () (curl-request-check (make-curl-request (with "http" "caf%E9.example")))))
                (list "URL: curl-url-part" (lambda () (curl-url-part (string-append (with "http" "h") " /") 'host)))
                (list "URL: curl-url-resolve's base" (lambda () (curl-url-resolve (string-append (with "http" "h") " /") "x")))
                (list "URL: curl-url-resolve's reference" (lambda () (curl-url-resolve "http://h/" (string-append (with "http" "h") " /"))))
                (list "URL: curl-url-append-query" (lambda () (curl-url-append-query (string-append (with "http" "h") " /") "a=1")))
                (list "URL: curl-url-with-fragment" (lambda () (curl-url-with-fragment (string-append (with "http" "h") " /") "f")))
                (list "URL: a call's, passed through"
                      (lambda () (call-with-http-session (lambda (s) (http-get s (with "ftp" "h")))))))))
       ;; a response through the proxy, and the high level
       (let* ((e (make-curl-engine))
              (r (curl-token-await (curl-submit e (make-curl-request (string-append "http://" http "/echo") 'proxy (with "http" http))))))
         (line "a response, absolute form, its body the origin's echo of the request (the proxy's own headers, expected)"
               (printed (list (curl-response-status r) (curl-response-headers r))))
         (curl-engine-stop e))
       (let ((s (make-http-session 'proxy (with "http" http) 'timeout-ms 10000)))
         (line "a session" (printed s))
         (line "a call's failure through it" (printed (raised (lambda () (http-get s (string-append "https://localhost:" (number->string (cdr (origin-face o 'https))) "/") 'ca-file ca)))))
         (line "a call's response through it, without its body" (let ((r (http-get s (string-append "http://" http "/status/200")))) (printed (list r (http-response-status r) (http-response-headers r)))))
         (http-session-close s))
       'done))))
