#!r6rs
;;; The suite for a proxy given by URL (ADR-0037, amended twice; ADR-0026 and
;;; ADR-0034, amended; the M7 plan, sections 3.1, 3.2, 3.4, 3.6, 3.7 and
;;; 6.2), at both levels, against the test origin's proxy: its http face and
;;; its https faces, which take a CONNECT and a request in absolute form, and
;;; log each, the proxy's own record of what it got.
;;;
;;;   - the settings, as data: proxy-settings' answer written out whole for
;;;     every value; unshared-tunnel-settings' and tls-in-tls-stall?'s
;;;     answers, and their tables held to this suite's copies; the decoder
;;;     and the CONNECT status' reading; the URL a submit hands PROXY;
;;;   - the keys: proxy, a URL kept as a copy, proxy-ca-file and
;;;     proxy-verify, their defaults and wrong types, and every copy, the
;;;     caller's strings changed after the request was made;
;;;   - every refusal beside a neighbour that passes, with a sentinel of its
;;;     own for no raise: proxy-url, proxy-scheme against its whole
;;;     complement, proxy-url-parts, the decoded userinfo on each byte class
;;;     at the first, a middle and the last position of the user and the
;;;     password, a colon, bytes that are not UTF-8, an empty userinfo by
;;;     version; proxy-authorization-header at every position and in every
;;;     letter's case; proxy-tls-without-https-proxy;
;;;     prior-knowledge-through-proxy; proxy-tls-in-tls by version and
;;;     backend; their order; and no refusal holding the proxy's password;
;;;   - through the engine, each asserted by the proxy's log, whole, never by
;;;     a 200 alone: absolute form and CONNECT, an https:// proxy, the
;;;     credentials' bytes; the proxy's TLS, each leaf, kept apart from the
;;;     origin's; a refused CONNECT's code and status by version; the
;;;     unshared tunnel before 8.19.0, FRESH_CONNECT's and FORBID_REUSE's
;;;     effects apart; the TLS-in-TLS refusal, bounded;
;;;   - in a child, given the variables through its command: no_proxy,
;;;     NO_PROXY, *, and the proxy variables beside a named proxy; Guix's
;;;     SSL_CERT_FILE beside a proxy CA file;
;;;   - the high level: a session's proxy and its TLS keys, a call's proxy
;;;     dropping them, a redirect's hops, a Proxy-Authorization header
;;;     refused, and a refused CONNECT retried by its status;
;;;   - no exit printing the proxy's password: every refusal, every transfer
;;;     failure, its error buffer among it, the request, the token, the
;;;     session and the response.
;;;
;;; Every expected value is one the code under test cannot produce by
;;; failing: SRFI-64 makes #f of a raise in the actual expression, so none
;;; is #f. Each by-version table has a row for each of the five Linux
;;; libcurls, and fails by name, printing what it measured, on one with
;;; none (ADR-0017), Apple's 8.7.1 among them.
(import (rnrs)
        (rnrs mutable-pairs)
        (rnrs mutable-strings)
        (srfi :64)
        (only (chezscheme) fork-thread make-mutex with-mutex sleep make-time current-time
              time-second time-nanosecond getenv parameterize display-condition
              library-directories foreign-entry)
        (curl-testing)
        (curl)
        (curl unsupported)
        (http-client)
        (only (curl private transfer) proxy-settings unshared-tunnel-settings unshared-tunnel-floor
              tls-in-tls-stalls tls-in-tls-stall? percent-decoded connect-status check-proxy-url
              prepare-transfer plan-proxy plan-tunnel request-field-options stops-multiplexing?
              plan-unmultiplex https-proxy-supported? check-https-proxy)
        (only (curl private engine) curl-engine-multiplexing)
        (only (curl private native) loaded-tls-backend loaded-features loaded-libcurl-file loaded-libcurl-patched?)
        (curl private counters))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; written : Any -> String
(define (written x) (call-with-string-output-port (lambda (p) (write x p))))

;; shown : Any -> String
;; X written, cut to 4000 characters.
(define (shown x)
  (let ((text (written x)))
    (if (> (string-length text) 4000)
        (string-append (substring text 0 4000) "...")
        text)))

;; The simple runner names a failing test but not its values. Print both.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (display "  expected: ")
        (display (shown (test-result-ref r 'expected-value)))
        (newline)
        (display "  actual:   ")
        (display (shown (test-result-ref r 'actual-value)))
        (newline))
      ;; A suite killed at its bound never flushes: flush each verdict.
      (flush-output-port (current-output-port)))))

(test-begin "proxy")

;; --- helpers --------------------------------------------------------------------------

(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)))

;; The loaded libcurl's version, its version_num and the TLS backend its
;; init put in use, by name, read here, before any engine's thread is
;; forked.
(define version
  (guard (e (#t (list 'no-version (describe e))))
    (libcurl-info-version (loaded-libcurl))))
(define version-number
  (guard (e (#t #f))
    (libcurl-info-version-number (loaded-libcurl))))

;; nothing-sent : (U 0 #f)
;; The request size a transfer that sent nothing carries on this libcurl:
;; 0, but #f, unknown, on 8.7.0 and 8.7.1, which report 0 for every
;; transfer, so a failure there never claims that nothing was sent
;; (ADR-0022, amended 2026-10-27). Written out here, not read from the
;; library's own list.
(define nothing-sent (if (member version '("8.7.0" "8.7.1")) #f 0))

;; tls-failure : (List Symbol Symbol Integer Symbol (U 0 #f) #f)
;; outcome-of's answer for a TLS failure at the proxy, before any request:
;; 60, the tls class, nothing sent, no CONNECT status.
(define tls-failure (list 'failed 'perform-failed 60 'tls nothing-sent #f))

;; name-of : Any -> Any
;; A backend's NAME/VERSION cut at its /: GnuTLS for GnuTLS/3.8.3.
(define (name-of x)
  (if (string? x)
      (let loop ((i 0))
        (cond ((= i (string-length x)) x)
              ((char=? (string-ref x i) #\/) (substring x 0 i))
              (else (loop (+ i 1)))))
      x))

(define backend
  (guard (e (#t (list 'no-backend (describe e))))
    (name-of (loaded-tls-backend))))

;; lane : Any
;; The key of a table that varies by version and by backend: VERSION/NAME.
(define lane (if (and (string? version) (string? backend)) (string-append version "/" backend) version))

;; now-ms : -> Integer
(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

;; pause-ms : Natural -> Unit
(define (pause-ms ms)
  (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))

;; wait-for : (-> Any) Natural -> Any
;; THUNK's first true answer, read every 2 ms, or #f after MS ms.
(define (wait-for thunk ms)
  (let ((deadline (+ (now-ms) ms)))
    (let loop ()
      (or (thunk)
          (and (< (now-ms) deadline)
               (begin (pause-ms 2) (loop)))))))

;; hex2 : Natural -> String
;; %XX for B, upper case.
(define (hex2 b)
  (string #\% (string-ref "0123456789ABCDEF" (div b 16)) (string-ref "0123456789ABCDEF" (mod b 16))))

;; escaped : Bytevector -> String
;; BYTES as the proxy's log shows them, written apart from the origin's
;; escaped: printable ASCII as it is, but \ as \\; every other byte as
;; \xNN, lower case.
(define (escaped bytes)
  (apply string-append
         (map (lambda (b)
                (cond ((= b #x5c) "\\\\")
                      ((or (< b #x20) (> b #x7e))
                       (string #\\ #\x (string-ref "0123456789abcdef" (div b 16))
                               (string-ref "0123456789abcdef" (mod b 16))))
                      (else (string (integer->char b)))))
              (bytevector->u8-list bytes))))

;; octets : String -> Bytevector
;; Each char, all below 256, as its byte.
(define (octets s) (u8-list->bytevector (map char->integer (string->list s))))

;; bytes : Natural ... -> Bytevector
(define (bytes . xs) (u8-list->bytevector xs))

;; latin-1 : Bytevector -> String
;; BYTES as Latin-1, one char each.
(define (latin-1 bytes) (list->string (map integer->char (bytevector->u8-list bytes))))

;; contains? : String String -> Boolean
;; Whether TEXT holds PART at some position.
(define (contains? text part)
  (let ((n (string-length text)) (k (string-length part)))
    (let loop ((i 0))
      (and (<= (+ i k) n)
           (or (string=? (substring text i (+ i k)) part) (loop (+ i 1)))))))

;; class-of : Condition -> Symbol
(define (class-of e)
  (cond ((curl-timeout? e) 'timeout)
        ((curl-connect-error? e) 'connect)
        ((curl-send-receive-error? e) 'send-receive)
        ((curl-tls-error? e) 'tls)
        ((curl-protocol-error? e) 'protocol)
        ((curl-too-large? e) 'too-large)
        (else 'none)))

;; stop-bounded : Engine -> Symbol
;; ENGINE stopped on a thread of its own: stopped, once it has, or
;; never-stopped after 20 s.
(define (stop-bounded engine)
  (let ((mx (make-mutex)) (done #f))
    (fork-thread (lambda ()
                   (guard (e (#t #f)) (curl-engine-stop engine))
                   (with-mutex mx (set! done #t))))
    (if (wait-for (lambda () (with-mutex mx done)) 20000) 'stopped 'never-stopped)))

;; on-own-engine : (Engine -> Any) -> Any
;; PROC's answer, given an engine made for it and stopped once it returns;
;; (raised TEXT) for a raise.
(define (on-own-engine proc)
  (guard (e (#t (list 'raised (describe e))))
    (let* ((own (make-curl-engine))
           (answer (guard (e (#t (list 'raised (describe e)))) (proc own))))
      (stop-bounded own)
      answer)))

;; awaited : Token -> (U Response Condition 'hung)
;; TOKEN's outcome, as data, once it is done; hung, after cancelling it,
;; when it is not done within 30 s.
(define (awaited token)
  (if (curl-token-wait token 30000)
      (curl-token-outcome token)
      (begin (curl-token-cancel token) (curl-token-wait token 5000) 'hung)))

;; size-kind : (U Natural #f) -> Symbol
(define (size-kind size)
  (cond ((eqv? size 0) 'zero) ((not size) 'unknown) (else 'sent)))

;; outcome-of : (U Response Condition 'hung) -> Outcome
;; A transfer's outcome: (response STATUS), (failed REASON CODE CLASS SIZE
;; CONNECT-CODE), or (raised TEXT).
(define (outcome-of x)
  (cond ((curl-response? x) (list 'response (curl-response-status x)))
        ((curl-transfer-error? x)
         (list 'failed (curl-transfer-error-reason x) (curl-transfer-error-code x) (class-of x)
               (curl-transfer-error-request-size x) (curl-transfer-error-connect-code x)))
        ((curl-request-error? x) (refusal-of x))
        (else (list 'raised (if (condition? x) (describe x) x)))))

;; refusal-of : Condition -> (List 'refused Symbol Any Symbol (U Symbol #f))
;; A &curl-request-error's field, value, reason and who.
(define (refusal-of e)
  (list 'refused (curl-request-error-field e) (curl-request-error-value e)
        (curl-request-error-reason e) (and (who-condition? e) (condition-who e))))

;; checked : (-> Any) -> Any
;; What THUNK raised: refusal-of's answer for a &curl-request-error,
;; (url-refused REASON) for a &curl-url-error, (assertion WHO IRRITANTS) for
;; an assertion violation, (raised TEXT) for anything else; or no-raise, a
;; sentinel no refusal is, when it returned.
(define (checked thunk)
  (guard (e ((curl-request-error? e) (refusal-of e))
            ((curl-url-error? e) (list 'url-refused (curl-url-error-reason e)))
            ((assertion-violation? e)
             (list 'assertion (and (who-condition? e) (condition-who e))
                   (and (irritants-condition? e) (condition-irritants e))))
            (#t (list 'raised (describe e))))
    (thunk)
    'no-raise))

;; made : (-> Request) -> Any
;; checked's answer for making a request, and made, a sentinel of its own,
;; when THUNK answers a request.
(define (made thunk)
  (guard (e ((curl-request-error? e) (refusal-of e))
            ((assertion-violation? e)
             (list 'assertion (and (who-condition? e) (condition-who e))
                   (and (irritants-condition? e) (condition-irritants e))))
            (#t (list 'raised (describe e))))
    (if (curl-request? (thunk)) 'made 'not-a-request)))

;; The URL a check needs: parsed at curl-request-check, never fetched.
(define nowhere "http://127.0.0.1:1/")
(define nowhere-tls "https://127.0.0.1:1/")

;; check-of : String . Keys -> Any
;; checked's answer for curl-request-check of a request for URL with KEYS,
;; or the making's refusal.
(define (check-of url . keys)
  (checked (lambda () (curl-request-check (apply make-curl-request url keys)))))

;; submit-of : String . Keys -> Any
;; checked's answer for curl-submit of a request for URL with KEYS, on an
;; engine of its own; a submit that passes is cancelled at once, so nothing
;; is fetched but what the engine begins before the cancel lands.
(define (submit-of url . keys)
  (on-own-engine
   (lambda (e)
     (checked (lambda ()
                (let ((token (curl-submit e (apply make-curl-request url keys))))
                  (curl-token-cancel token)
                  (curl-token-wait token 10000)))))))

;; by-version : (Listof (Pairof Any Any)) String Any (-> Any) -> (List Any Any)
;; A per-version test's expected and actual values, from ROWS for KEY, the
;; loaded libcurl's version or lane, and MEASURE's answer: the row's value
;; and the measurement; with no row, (a-row-for KEY), which no measurement
;; gives, and (no-row-for KEY measured M), so the failure names the libcurl
;; and prints the row it lacks (ADR-0017; AGENTS.md's by-version trap). TAG
;; names the table, on stdout with the key and the measurement, as evidence
;; of what ran, and on the error port with the row a libcurl with none
;; would need.
(define (by-version rows tag key measure)
  (let ((row (assoc key rows))
        (measured (measure)))
    (display (string-append "test-proxy: " tag " on " (written key) " measured "
                            (written measured) "\n"))
    (unless row
      (display (string-append "test-proxy: no row of " tag " for this libcurl; measured, it would be:\n")
               (current-error-port))
      (write (cons key measured) (current-error-port))
      (newline (current-error-port)))
    (if row
        (list (cdr row) measured)
        (list (list 'a-row-for key) (list 'no-row-for key 'measured measured)))))

;; The run's PKI, for the TLS faces.
(define pki-made
  (guard (e (#t (list 'raised (describe e))))
    (list 'made (make-test-pki))))
(define pki (and (eq? (car pki-made) 'made) (cadr pki-made)))
(define ca (and pki (string-append pki "/ca.pem")))
(define other-ca (and pki (string-append pki "/other-ca.pem")))

(test-equal "the run's PKI is made"
  'made
  (car pki-made))

;; --- hermetic --------------------------------------------------------------------------

(define ambient-variables
  '("http_proxy" "HTTP_PROXY" "https_proxy" "HTTPS_PROXY" "all_proxy" "ALL_PROXY" "no_proxy"
    "NO_PROXY" "SSL_CERT_FILE" "SSL_CERT_DIR"))

(test-equal "hermetic: none of http_proxy, HTTP_PROXY, https_proxy, HTTPS_PROXY, all_proxy, ALL_PROXY, no_proxy, NO_PROXY, SSL_CERT_FILE and SSL_CERT_DIR is set: the children set them, each in its own command"
  '()
  (filter (lambda (name) (let ((v (getenv name))) (and v (not (string=? v "")))))
          ambient-variables))

;; --- the settings, as data -----------------------------------------------------------

(test-equal "request-field-options, the proxy's fields: proxy's PROXY, NOPROXY and FORBID_REUSE; proxy-ca-file's PROXY_CAINFO and PROXY_CAPATH; proxy-verify's PROXY_SSL_VERIFYPEER and PROXY_SSL_VERIFYHOST; and body's FRESH_CONNECT, which a tunnel's settings set too"
  '((proxy "PROXY" "NOPROXY" "FORBID_REUSE")
    (proxy-ca-file "PROXY_CAINFO" "PROXY_CAPATH")
    (proxy-verify "PROXY_SSL_VERIFYPEER" "PROXY_SSL_VERIFYHOST")
    "FRESH_CONNECT")
  (list (assq 'proxy request-field-options)
        (assq 'proxy-ca-file request-field-options)
        (assq 'proxy-verify request-field-options)
        (list-ref (assq 'body request-field-options) 9)))

(test-equal "proxy-settings, written out whole: environment sets nothing, whatever the TLS keys; #f, PROXY \"\"; a URL, PROXY at it and NOPROXY \"\", then the proxy's verification, 1 and 2, or 0 and 0, then, with a proxy CA file, PROXY_CAINFO at it and PROXY_CAPATH cleared, for an http:// URL as an https:// one"
  '(()
    ()
    (("PROXY" . ""))
    (("PROXY" . ""))
    (("PROXY" . "http://u:p@127.0.0.1:8080/") ("NOPROXY" . "") ("PROXY_SSL_VERIFYPEER" . 1)
     ("PROXY_SSL_VERIFYHOST" . 2))
    (("PROXY" . "https://127.0.0.1:443/") ("NOPROXY" . "") ("PROXY_SSL_VERIFYPEER" . 1)
     ("PROXY_SSL_VERIFYHOST" . 2))
    (("PROXY" . "https://127.0.0.1:443/") ("NOPROXY" . "") ("PROXY_SSL_VERIFYPEER" . 0)
     ("PROXY_SSL_VERIFYHOST" . 0))
    (("PROXY" . "https://127.0.0.1:443/") ("NOPROXY" . "") ("PROXY_SSL_VERIFYPEER" . 1)
     ("PROXY_SSL_VERIFYHOST" . 2) ("PROXY_CAINFO" . "/x/proxy-ca.pem") ("PROXY_CAPATH" . #f))
    (("PROXY" . "https://127.0.0.1:443/") ("NOPROXY" . "") ("PROXY_SSL_VERIFYPEER" . 0)
     ("PROXY_SSL_VERIFYHOST" . 0) ("PROXY_CAINFO" . "/x/proxy-ca.pem") ("PROXY_CAPATH" . #f))
    (("PROXY" . "http://127.0.0.1:80/") ("NOPROXY" . "") ("PROXY_SSL_VERIFYPEER" . 0)
     ("PROXY_SSL_VERIFYHOST" . 0) ("PROXY_CAINFO" . "/x/proxy-ca.pem") ("PROXY_CAPATH" . #f)))
  (list (proxy-settings 'environment #f #t)
        (proxy-settings 'environment "/x/proxy-ca.pem" #f)
        (proxy-settings #f #f #t)
        (proxy-settings #f "/x/proxy-ca.pem" #f)
        (proxy-settings "http://u:p@127.0.0.1:8080/" #f #t)
        (proxy-settings "https://127.0.0.1:443/" #f #t)
        (proxy-settings "https://127.0.0.1:443/" #f #f)
        (proxy-settings "https://127.0.0.1:443/" "/x/proxy-ca.pem" #t)
        (proxy-settings "https://127.0.0.1:443/" "/x/proxy-ca.pem" #f)
        (proxy-settings "http://127.0.0.1:80/" "/x/proxy-ca.pem" #f)))

(test-equal "proxy-settings refuses any other proxy, an assertion violation naming proxy alone, never the value: direct, 0, and a list holding a URL"
  '((assertion proxy-settings (proxy)) (assertion proxy-settings (proxy))
    (assertion proxy-settings (proxy)))
  (map (lambda (proxy) (checked (lambda () (proxy-settings proxy #f #t))))
       (list 'direct 0 (list "http://u:Pr0xyS3cr3t@h/"))))

(test-equal "unshared-tunnel-floor is 8.19.0's version_num, #x081300"
  #x081300
  unshared-tunnel-floor)

;; tunnel-matrix : (Listof (List Natural (U String #f) Boolean Boolean))
;; Each version_num, scheme, proxy URL and userinfo the matrix below
;; crosses: 7.85.0, 8.5.0, 8.7.1, 8.18.0, 8.19.0, 8.20.0 and 8.23.0.
(define tunnel-versions '(#x075500 #x080500 #x080701 #x081200 #x081300 #x081400 #x081700))
(define tunnel-matrix
  (apply append
         (map (lambda (v)
                (apply append
                       (map (lambda (scheme)
                              (apply append
                                     (map (lambda (url)
                                            (map (lambda (info) (list v scheme url info)) '(#t #f)))
                                          '(#t #f))))
                            '("https" "http"))))
              tunnel-versions)))

(test-equal "unshared-tunnel-settings, written out for every version, scheme, proxy URL and userinfo crossed: below 8.19.0, an https:// URL through a proxy URL sets FRESH_CONNECT, and FORBID_REUSE beside userinfo; an http:// URL, no proxy URL, and 8.19.0 and later set nothing"
  (map (lambda (row)
         (if (and (< (car row) #x081300) (string=? (cadr row) "https") (caddr row))
             (if (cadddr row) '(("FRESH_CONNECT" . 1) ("FORBID_REUSE" . 1)) '(("FRESH_CONNECT" . 1)))
             '()))
       tunnel-matrix)
  (map (lambda (row) (apply unshared-tunnel-settings row)) tunnel-matrix))

(test-equal "stops-multiplexing?, written out for every version, proxy URL and userinfo crossed: below 8.19.0, a proxy URL with userinfo stops the engine's multiplexing, 8.7.1's and 8.18.0's among them; a proxy URL without, userinfo with none, and every one from 8.19.0 never"
  '((#x075500 #t #f #f #f) (#x080500 #t #f #f #f) (#x080701 #t #f #f #f) (#x081200 #t #f #f #f)
    (#x081300 #f #f #f #f) (#x081400 #f #f #f #f) (#x081700 #f #f #f #f))
  (map (lambda (v)
         (cons v (map (lambda (cell) (stops-multiplexing? v (car cell) (cadr cell)))
                      '((#t #t) (#t #f) (#f #t) (#f #f)))))
       tunnel-versions))

(test-equal "https-proxy-supported?, written out on features words: CURL_VERSION_HTTPS_PROXY, (1<<21), alone, beside SSL, and with every other bit, holds; none, SSL alone, and every bit but it, the bits on either side of it among them, do not"
  '(#t #t #t #f #f #f #f #f)
  (map https-proxy-supported?
       (list #x00200000 #x00200004 #x7FFFFFFF 0 #x00000004 #x7FDFFFFF #x00100000 #x00400000)))

(test-equal "check-https-proxy refuses an https:// proxy URL beside features without CURL_VERSION_HTTPS_PROXY, as https-proxy-unsupported, field proxy, value proxy, never the URL: libcurl would write the URL whole into its error buffer; an https:// proxy beside the feature, and no https:// proxy beside none, pass"
  (list '(refused proxy proxy https-proxy-unsupported curl-submit) '(refused proxy proxy https-proxy-unsupported curl-submit)
        'no-raise 'no-raise 'no-raise)
  (list (checked (lambda () (check-https-proxy 'curl-submit #t 0)))
        (checked (lambda () (check-https-proxy 'curl-submit #t #x7FDFFFFF)))
        (checked (lambda () (check-https-proxy 'curl-submit #t #x00200000)))
        (checked (lambda () (check-https-proxy 'curl-submit #f 0)))
        (checked (lambda () (check-https-proxy 'curl-submit #f #x00200000)))))

;; The features word read after curl_global_init: Apple's MultiSSL 8.7.1
;; reports CURL_VERSION_HTTPS_PROXY clear before it, and every https://
;; proxy was refused there until the check read this word (the Mac's run).
(test-equal "the loaded libcurl speaks TLS to an https:// proxy, as every lane's and the Mac's does, by the features it reports after its init, so its submit passes an https:// proxy URL that check-https-proxy would refuse beside features without it"
  (list #t 'no-raise)
  (list (guard (e (#t (list 'raised (describe e)))) (https-proxy-supported? (loaded-features)))
        (check-of nowhere 'proxy "https://u:p@127.0.0.1:1")))

(test-equal "tls-in-tls-stalls, the library's table, is this suite's copy: 7.85.0 with any backend for #f and http/2; Ubuntu's 8.5.0 with GnuTLS for #f, http/1.1 and http/2"
  '(("7.85.0" #f (#f http/2)) ("8.5.0" "GnuTLS" (#f http/1.1 http/2)))
  tls-in-tls-stalls)

(test-equal "tls-in-tls-stall?, written out: 7.85.0 on any backend stalls for #f and http/2, never http/1.1; 8.5.0 with GnuTLS, or a backend that could not be read, for each; 8.5.0 with OpenSSL, 8.20.0 with GnuTLS, 8.23.0, 8.7.1 and 8.5.1 never; a backend named only like GnuTLS at its end does not match"
  '((#t #f #t) (#t #f #t) (#t #t #t) (#t #t #t) (#f #f #f) (#f #f #f) (#f #f #f) (#f #f #f) (#f #f #f)
    (#f #f #f))
  (map (lambda (row)
         (map (lambda (asked) (tls-in-tls-stall? (car row) (cadr row) asked)) '(#f http/1.1 http/2)))
       '(("7.85.0" "OpenSSL/3.0.13") ("7.85.0" "GnuTLS/3.8.3") ("8.5.0" "GnuTLS/3.8.3") ("8.5.0" #f)
         ("8.5.0" "OpenSSL/3.0.13") ("8.20.0" "GnuTLS/3.8.13") ("8.23.0" "OpenSSL/3.0.13")
         ("8.7.1" "LibreSSL/3.3.6") ("8.5.1" "GnuTLS/3.8.3") ("8.5.0" "notGnuTLS/1"))))

(test-equal "percent-decoded, written out: each %XX, either case, its byte; every other char its UTF-8 bytes, raw UTF-8 among them; #f for a % not followed by two hex digits, at the end, before one digit, or before a non-hex char"
  (list (bytes) (octets "abc") (octets "A") (bytes #x4a) (bytes #x4a)
        (bytes #x00) (bytes #xff) (bytes #xc3 #xa9) (bytes #xc3 #xa9)
        (octets "a b") (octets "%") (octets "a:b")
        #f #f #f #f #f #f #f)
  (map percent-decoded
       (list "" "abc" "%41" "%4a" "%4A" "%00" "%ff" "%C3%A9" "\xE9;" "a%20b" "%25" "a%3ab"
             "%" "a%" "%4" "a%4" "%zz" "%g0" "%0g")))

(test-equal "connect-status, written out: 0 and every 2xx are #f, no refusal; any other status is itself"
  '(#f #f #f #f 100 199 300 403 407 502 503 599)
  (map connect-status '(0 200 204 299 100 199 300 403 407 502 503 599)))

;; --- the URL a submit hands PROXY --------------------------------------------------------

;; handed : String -> Any
;; check-proxy-url's answer for PROXY, (URL SCHEME USERINFO), or what it
;; raised.
(define (handed proxy)
  (guard (e ((curl-request-error? e) (refusal-of e))
            (#t (list 'raised (describe e))))
    (check-proxy-url 'test proxy)))

(test-equal "check-proxy-url hands PROXY the URL libcurl gives back, a port its scheme's when it names none, 80 or 443, A to Z folded, its own kept; its scheme folded; and whether it holds userinfo; alike on every libcurl"
  '(("http://127.0.0.1:80/" "http" #f)
    ("https://127.0.0.1:443/" "https" #f)
    ("http://127.0.0.1:80/" "http" #f)
    ("https://127.0.0.1:443/" "https" #f)
    ("http://127.0.0.1:8080/" "http" #f)
    ("https://127.0.0.1:80/" "https" #f)
    ("http://127.0.0.1:443/" "http" #f)
    ("http://[::1]:80/" "http" #f)
    ("http://u:p@127.0.0.1:80/" "http" #t)
    ("http://u%41:p%3Aq@127.0.0.1:3128/" "http" #t)
    ("http://u@127.0.0.1:3128/" "http" #t)
    ("http://:p@127.0.0.1:3128/" "http" #t)
    ("http://localhost:80/" "http" #f))
  (map handed '("http://127.0.0.1" "https://127.0.0.1" "HTTP://127.0.0.1" "hTTps://127.0.0.1/"
                "http://127.0.0.1:8080" "https://127.0.0.1:80" "http://127.0.0.1:443"
                "http://[::1]" "http://u:p@127.0.0.1" "http://u%41:p%3Aq@127.0.0.1:3128"
                "http://u@127.0.0.1:3128" "http://:p@127.0.0.1:3128" "http://localhost")))

(test-equal "a submit's plan holds the URL check-proxy-url hands PROXY, and environment and #f as given"
  '("http://127.0.0.1:80/" "https://u:p@127.0.0.1:443/" environment #f)
  (map (lambda (proxy)
         (guard (e (#t (list 'raised (describe e))))
           (plan-proxy (prepare-transfer (make-curl-request nowhere 'proxy proxy)))))
       '("http://127.0.0.1" "https://u:p@127.0.0.1" environment #f)))

;; empty-userinfo : (Listof (Pairof String (Listof Any)))
;; What each empty userinfo answers at check-proxy-url, by version: @ and
;; :@, which 7.85.0 reports as no user and no password, so it holds no
;; userinfo and gives the URL back without them, where 8.5.0 and later
;; report "" and refuse both as credentials-empty; :p@ and u:@, which hold
;; one part beside the other, pass alike, as 8.5.0 and later give them back,
;; 7.85.0 dropping the empty password's colon. 8.7.1's row is the Mac's.
(define empty-userinfo-later
  '((refused proxy (proxy user) credentials-empty test)
    (refused proxy (proxy user) credentials-empty test)
    ("http://:p@127.0.0.1:3128/" "http" #t)
    ("http://u:@127.0.0.1:3128/" "http" #t)))
(define empty-userinfo
  (list (cons "7.85.0" '(("http://127.0.0.1:3128/" "http" #f) ("http://127.0.0.1:3128/" "http" #f)
                         ("http://:p@127.0.0.1:3128/" "http" #t) ("http://u@127.0.0.1:3128/" "http" #t)))
        (cons "8.5.0" empty-userinfo-later)
        (cons "8.20.0" empty-userinfo-later)
        (cons "8.23.0" empty-userinfo-later)
        (cons "8.7.1" empty-userinfo-later)))

(let ((pair (by-version empty-userinfo "empty-userinfo" version
                        (lambda () (map handed '("http://@127.0.0.1:3128" "http://:@127.0.0.1:3128"
                                                 "http://:p@127.0.0.1:3128" "http://u:@127.0.0.1:3128"))))))
  (test-equal "an empty userinfo, by version: @ and :@ hold none on 7.85.0, which reports no part, and are refused as credentials-empty from 8.5.0; :p@ and u:@ pass everywhere"
    (car pair)
    (cadr pair)))

;; --- the keys ------------------------------------------------------------------------

(test-equal "proxy: environment by default; #f and environment kept; a URL string kept as a copy, equal and no caller's object, a fresh one each read; curl-request-with replaces each, and keeps one not given"
  '(environment #f environment "http://u:p@127.0.0.1:1" (#f #f) "https://127.0.0.1:2" "http://127.0.0.1:3" #f)
  (let* ((given (string-copy "http://u:p@127.0.0.1:1"))
         (r (make-curl-request nowhere 'proxy given)))
    (list (curl-request-proxy (make-curl-request nowhere))
          (curl-request-proxy (make-curl-request nowhere 'proxy #f))
          (curl-request-proxy (make-curl-request nowhere 'proxy 'environment))
          (curl-request-proxy r)
          (list (eq? (curl-request-proxy r) given) (eq? (curl-request-proxy r) (curl-request-proxy r)))
          (curl-request-proxy (curl-request-with r 'proxy "https://127.0.0.1:2"))
          (curl-request-proxy (curl-request-with (make-curl-request nowhere 'proxy "http://127.0.0.1:3")
                                                 'verify #f))
          (curl-request-proxy (curl-request-with r 'proxy #f)))))

(test-equal "proxy: any value but environment, #f or a string is an assertion violation from make-curl-request or curl-request-with, its irritant proxy alone, so a URL given in a wrong shape is never handed on: #t, direct, (), 0, a symbol environment's case changed, and a list holding a URL"
  (append (map (lambda (v) '(assertion make-curl-request (proxy))) '(1 2 3 4 5 6))
          '((assertion curl-request-with (proxy))))
  (append (map (lambda (v) (made (lambda () (make-curl-request nowhere 'proxy v))))
               (list #t 'direct '() 0 'Environment (list "http://u:Pr0xyS3cr3t@h/")))
          (list (made (lambda () (curl-request-with (make-curl-request nowhere) 'proxy 'none))))))

(test-equal "proxy: a string is taken as the request is made, any string, its parse a submit's: \"\", a scheme libcurl does not know, and U+0000 among them"
  '(made made made made)
  (map (lambda (v) (made (lambda () (make-curl-request nowhere 'proxy v))))
       (list "" "foo://h:1" "http://h\x0;:1" "not a URL")))

(test-equal "proxy-ca-file: #f by default; a path kept as a copy, a fresh one each read; curl-request-with replaces and keeps it; proxy-verify: #t by default, #f kept"
  '(#f "/x/proxy-ca.pem" (#f #f) "/y/ca.pem" "/x/proxy-ca.pem" #t #f #f)
  (let* ((given (string-copy "/x/proxy-ca.pem"))
         (r (make-curl-request nowhere 'proxy-ca-file given)))
    (list (curl-request-proxy-ca-file (make-curl-request nowhere))
          (curl-request-proxy-ca-file r)
          (list (eq? (curl-request-proxy-ca-file r) given)
                (eq? (curl-request-proxy-ca-file r) (curl-request-proxy-ca-file r)))
          (curl-request-proxy-ca-file (curl-request-with r 'proxy-ca-file "/y/ca.pem"))
          (curl-request-proxy-ca-file (curl-request-with r 'verify #f))
          (curl-request-proxy-verify (make-curl-request nowhere))
          (curl-request-proxy-verify (make-curl-request nowhere 'proxy-verify #f))
          (curl-request-proxy-verify (curl-request-with (make-curl-request nowhere 'proxy-verify #f)
                                                        'timeout-ms 5)))))

(test-equal "proxy-ca-file's wrong types and proxy-verify's are assertion violations from make-curl-request, with the value, a string by its kind: \"\", 5 and #t; 0, on and ()"
  '((assertion make-curl-request ((kind string))) (assertion make-curl-request (5))
    (assertion make-curl-request (#t))
    (assertion make-curl-request (0)) (assertion make-curl-request (on))
    (assertion make-curl-request (())))
  (append (map (lambda (v) (made (lambda () (make-curl-request nowhere 'proxy-ca-file v)))) (list "" 5 #t))
          (map (lambda (v) (made (lambda () (make-curl-request nowhere 'proxy-verify v)))) (list 0 'on '()))))

(test-equal "proxy-ca-file is checked as ca-file is, as the request is made: U+0000 embedded-nul, and pkcs11: in any ASCII case pkcs11-url, field proxy-ca-file; ./pkcs11:x and p, U+212A, cs11: pass"
  '((refused proxy-ca-file "/x\x0;y" embedded-nul make-curl-request)
    (refused proxy-ca-file "pkcs11:x" pkcs11-url make-curl-request)
    (refused proxy-ca-file "PKCS11:x" pkcs11-url make-curl-request)
    made made)
  (map (lambda (v) (made (lambda () (make-curl-request nowhere 'proxy-ca-file v))))
       (list "/x\x0;y" "pkcs11:x" "PKCS11:x" "./pkcs11:x" "p\x212A;cs11:")))

(test-equal "the copies: a caller's proxy string and proxy CA file string changed after the request was made change nothing it holds, nor does a change to an accessor's answer"
  '("http://u:p@127.0.0.1:1" "/x/proxy-ca.pem" "http://u:p@127.0.0.1:1" "/x/proxy-ca.pem")
  (let* ((proxy (string-copy "http://u:p@127.0.0.1:1"))
         (path (string-copy "/x/proxy-ca.pem"))
         (r (make-curl-request nowhere 'proxy proxy 'proxy-ca-file path)))
    (string-set! proxy 9 #\X)
    (string-set! path 1 #\Z)
    (let ((a (curl-request-proxy r)) (b (curl-request-proxy-ca-file r)))
      (let ((first (list (string-copy a) (string-copy b))))
        (string-set! a 9 #\Y)
        (string-set! b 1 #\W)
        (append first (list (curl-request-proxy r) (curl-request-proxy-ca-file r)))))))

;; --- the refusals ---------------------------------------------------------------------

;; both-ways : String . Keys -> (List Any Any)
;; check-of's and submit-of's answers for URL with KEYS.
(define (both-ways url . keys)
  (list (apply check-of url keys) (apply submit-of url keys)))

;; refused-both : Symbol Any Symbol -> (List Any Any)
;; A refusal of FIELD, VALUE and REASON, as curl-request-check raises it,
;; then as curl-submit does.
(define (refused-both field value reason)
  (list (list 'refused field value reason 'curl-request-check)
        (list 'refused field value reason 'curl-submit)))

;; checked-refusal : Symbol Any Symbol -> Any
;; The refusal curl-request-check raises, of FIELD, VALUE and REASON.
(define (checked-refusal field value reason)
  (list 'refused field value reason 'curl-request-check))

;; proxy-check : String . Keys -> Any
;; check-of's answer for a request of nowhere through PROXY, with KEYS.
(define (proxy-check proxy . keys)
  (apply check-of nowhere 'proxy proxy keys))

;; unparsable : (Listof String)
;; Proxy URLs libcurl's URL API refuses, on every libcurl (the slice's
;; probe, build/m7s3b/): no scheme, an empty one, a port past 65535, an
;; unclosed IPv6 host; a raw control byte, space or 0x7F in the userinfo;
;; U+0000; a host whose %XX decodes to bytes that are not UTF-8; a scheme
;; holding U+017F LONG S or U+212A KELVIN SIGN, which Unicode folds make s
;; and k, refused before chez-curl compares it.
(define unparsable
  (list "" "127.0.0.1:3128" "localhost:3128" "localhost" "http://127.0.0.1:99999" "http://[::1"
        "http://u\x1;x:p@127.0.0.1:1" "http://u\x9;x:p@127.0.0.1:1" "http://u x:p@127.0.0.1:1"
        "http://u\x7F;x:p@127.0.0.1:1" "http://u:p\x1;x@127.0.0.1:1" "http://u:p x@127.0.0.1:1"
        "http://u\x0;x:p@127.0.0.1:1" "http://caf%E9.example:1" "http\x17F;://127.0.0.1:1"
        "\x212A;ttp://127.0.0.1:1"))

(test-equal "proxy-url: a proxy URL libcurl's URL API refuses is refused at curl-request-check and at a submit, field proxy, value proxy, never the URL, alike on every libcurl; never as the request is made"
  (map (lambda (u) (cons 'made (refused-both 'proxy 'proxy 'proxy-url))) unparsable)
  (map (lambda (u)
         (cons (made (lambda () (make-curl-request nowhere 'proxy u)))
               (both-ways nowhere 'proxy u)))
       unparsable))

;; at-each-position : String -> (Listof String)
;; FILL put at the first, a middle and the last position of "xy", two chars
;; no hex digit is: FILLxy, xFILLy and xyFILL.
(define (at-each-position fill)
  (list (string-append fill "xy") (string-append "x" fill "y") (string-append "xy" fill)))

;; user-url, password-url : String -> String
;; A proxy URL whose user, or password, is PART, the other part plain.
(define (user-url part) (string-append "http://" part ":pw@127.0.0.1:1"))
(define (password-url part) (string-append "http://user:" part "@127.0.0.1:1"))

(test-equal "proxy-url: a % not followed by two hex digits, in the user or the password, at the first, a middle and the last position, %zz, %, %4, %z and %g1, which every libcurl takes and would send on as written, is refused, field proxy, value proxy"
  (map (lambda (fill) (map (lambda (x) (checked-refusal 'proxy 'proxy 'proxy-url)) '(1 2 3 4 5 6)))
       '("%zz" "%" "%4" "%z" "%g1"))
  (map (lambda (fill)
         (append (map (lambda (part) (proxy-check (user-url part))) (at-each-position fill))
                 (map (lambda (part) (proxy-check (password-url part))) (at-each-position fill))))
       '("%zz" "%" "%4" "%z" "%g1")))

;; scheme-kept, scheme-refused : (Listof String)
;; The schemes a proxy URL may name, http and https in any ASCII case, and
;; their complement as far as libcurl parses one: every scheme it knows and
;; any it does not, each parsed with CURLU_NON_SUPPORT_SCHEME, so alike on
;; every libcurl where with no flags socks5 parses on 8.23.0 alone.
(define scheme-kept '("http" "https" "HTTP" "Https" "hTtP" "HTTPS"))
(define scheme-refused '("ftp" "FTP" "socks5" "socks4a" "socks5h" "socks4" "foo" "gopher" "ws" "httpx" "htt"))

(test-equal "proxy-scheme: a proxy URL's scheme is http or https, A to Z folded: each other scheme, socks5, socks4a, socks5h, ftp and foo among them, is refused at check and submit, field proxy, value proxy, on every libcurl; http, https, HTTP, Https, hTtP and HTTPS pass"
  (append (map (lambda (s) (refused-both 'proxy 'proxy 'proxy-scheme)) scheme-refused)
          (map (lambda (s) '(no-raise no-raise)) scheme-kept))
  (map (lambda (s) (both-ways nowhere 'proxy (string-append s "://127.0.0.1:1")))
       (append scheme-refused scheme-kept)))

(test-equal "proxy-url-parts: a path but /, a query or a fragment is refused, field proxy, value proxy; /, none, and an empty query or fragment, which 7.85.0 and 8.5.0 report as \"\" and later libcurls as none, pass alike"
  (append (map (lambda (s) (checked-refusal 'proxy 'proxy 'proxy-url-parts)) '(1 2 3 4 5 6 7 8))
          '(no-raise no-raise no-raise no-raise no-raise no-raise))
  (map (lambda (tail) (proxy-check (string-append "http://127.0.0.1:1" tail)))
       '("/a" "//" "/?q" "?q" "#f" "/#f" "/a?b#c" "/%2F" "/" "" "/?" "/#" "?" "#")))

;; control-bytes, passing-bytes : (Listof Natural)
;; The byte classes the userinfo rule refuses, decoded: NUL, SOH, HTAB, LF,
;; CR, US and DEL; and its neighbours that pass, a space and a tilde.
(define control-bytes '(#x00 #x01 #x09 #x0A #x0D #x1F #x7F))
(define passing-bytes '(#x20 #x7E))

(test-equal "credentials-bytes: a decoded control byte, each class, at the first, a middle and the last position of the user and of the password, encoded, is refused at check and submit, field proxy, value (proxy user) or (proxy password): decoded, 7.85.0 and 8.5.0 went around the proxy"
  (map (lambda (b)
         (append (map (lambda (x) (checked-refusal 'proxy '(proxy user) 'credentials-bytes)) '(1 2 3))
                 (map (lambda (x) (checked-refusal 'proxy '(proxy password) 'credentials-bytes)) '(1 2 3))))
       control-bytes)
  (map (lambda (b)
         (append (map (lambda (part) (proxy-check (user-url part))) (at-each-position (hex2 b)))
                 (map (lambda (part) (proxy-check (password-url part))) (at-each-position (hex2 b)))))
       control-bytes))

(test-equal "credentials-bytes at a submit too: an encoded LF in the user, a DEL in the password"
  (list (list 'refused 'proxy '(proxy user) 'credentials-bytes 'curl-submit)
        (list 'refused 'proxy '(proxy password) 'credentials-bytes 'curl-submit))
  (list (submit-of nowhere 'proxy (user-url "a%0Ab")) (submit-of nowhere 'proxy (password-url "a%7Fb"))))

(test-equal "the neighbours pass: a space and a tilde, encoded at each position of each part, and a tilde raw; and the raw forms of every control class, a space and DEL among them, are libcurl's parse's refusal, proxy-url, at each position"
  (list (map (lambda (b) (map (lambda (x) 'no-raise) '(1 2 3 4 5 6))) passing-bytes)
        (map (lambda (x) 'no-raise) '(1 2 3 4 5 6))
        (map (lambda (b) (map (lambda (x) (checked-refusal 'proxy 'proxy 'proxy-url)) '(1 2 3 4 5 6)))
             (append control-bytes '(#x20))))
  (list (map (lambda (b)
               (append (map (lambda (part) (proxy-check (user-url part))) (at-each-position (hex2 b)))
                       (map (lambda (part) (proxy-check (password-url part))) (at-each-position (hex2 b)))))
             passing-bytes)
        (append (map (lambda (part) (proxy-check (user-url part))) (at-each-position "~"))
                (map (lambda (part) (proxy-check (password-url part))) (at-each-position "~")))
        (map (lambda (b)
               (let ((raw (string (integer->char b))))
                 (append (map (lambda (part) (proxy-check (user-url part))) (at-each-position raw))
                         (map (lambda (part) (proxy-check (password-url part))) (at-each-position raw)))))
             (append control-bytes '(#x20)))))

(test-equal "credentials-bytes: a decoded colon at each position of the user, %3A and %3a, ends the user at the proxy and is refused, (proxy user); in the password, encoded at each position or raw, it passes"
  (list (map (lambda (x) (checked-refusal 'proxy '(proxy user) 'credentials-bytes)) '(1 2 3 4 5 6))
        (map (lambda (x) 'no-raise) '(1 2 3 4 5 6 7 8)))
  (list (map (lambda (part) (proxy-check (user-url part)))
             (append (at-each-position "%3A") (at-each-position "%3a")))
        (append (map (lambda (part) (proxy-check (password-url part)))
                     (append (at-each-position "%3A") (at-each-position "%3a")))
                (list (proxy-check "http://user:a:b@127.0.0.1:1") (proxy-check "http://user::@127.0.0.1:1")))))

;; not-utf-8, utf-8 : (Listof String)
;; Encoded byte runs that are not UTF-8: a byte that starts nothing, a lone
;; continuation byte, a lead cut short, an overlong NUL, a surrogate, and a
;; five-byte form; and UTF-8, encoded and raw.
(define not-utf-8 '("%FF" "%80" "%BF" "%C3" "%C0%80" "%ED%A0%80" "%F8%88%80%80%80"))
(define utf-8 '("%C3%A9" "\xE9;" "%E2%82%AC" "\x20AC;" "%F0%9F%98%80"))

(test-equal "credentials-bytes: decoded bytes that are not UTF-8, in the user or the password, are refused, (proxy PART); UTF-8, encoded or raw, passes in each"
  (list (map (lambda (x) (list (checked-refusal 'proxy '(proxy user) 'credentials-bytes)
                               (checked-refusal 'proxy '(proxy password) 'credentials-bytes)))
             not-utf-8)
        (map (lambda (x) '(no-raise no-raise)) utf-8))
  (list (map (lambda (bytes) (list (proxy-check (user-url bytes)) (proxy-check (password-url bytes))))
             not-utf-8)
        (map (lambda (bytes) (list (proxy-check (user-url bytes)) (proxy-check (password-url bytes))))
             utf-8)))

(test-equal "one empty part beside the other passes, alike on every libcurl, and so does an encoded space beside an empty part: credentials-empty, both empty, is the empty-userinfo table's, by version"
  '(no-raise no-raise no-raise no-raise)
  (map proxy-check '("http://u:@127.0.0.1:1" "http://:p@127.0.0.1:1"
                     "http://%20:@127.0.0.1:1" "http://:%20@127.0.0.1:1")))

;; the order of the proxy URL's refusals
(test-equal "the proxy URL's refusals come in order: libcurl's parse, then a malformed %, before the scheme; the scheme before the parts; the parts before the userinfo; the user before the password"
  (list (checked-refusal 'proxy 'proxy 'proxy-url)
        (checked-refusal 'proxy 'proxy 'proxy-url)
        (checked-refusal 'proxy 'proxy 'proxy-scheme)
        (checked-refusal 'proxy 'proxy 'proxy-scheme)
        (checked-refusal 'proxy 'proxy 'proxy-url-parts)
        (checked-refusal 'proxy '(proxy user) 'credentials-bytes)
        (checked-refusal 'proxy 'proxy 'proxy-url))
  (map proxy-check '("ftp://u%zz@127.0.0.1:1" "http://u%01:p%zz@127.0.0.1:1" "ftp://127.0.0.1:1/a"
                     "socks5://u%01@127.0.0.1:1" "http://u%01@127.0.0.1:1/a" "http://u%01:p%02@127.0.0.1:1"
                     "http://u%zz:p%01@127.0.0.1:1")))

;; --- a caller's Proxy-Authorization header (ADR-0037, decision 4) ---------------------

(define proxy-authorization "Proxy-Authorization")

;; case-flips : String -> (Listof String)
;; NAME with each letter's case changed in turn, A to Z alone: one name per
;; letter.
(define (case-flips name)
  (let loop ((i 0) (found '()))
    (if (= i (string-length name))
        (reverse found)
        (let ((c (string-ref name i)))
          (if (or (char<=? #\a c #\z) (char<=? #\A c #\Z))
              (let ((flipped (string-copy name)))
                (string-set! flipped i (integer->char (if (char<=? #\a c #\z) (- (char->integer c) 32)
                                                          (+ (char->integer c) 32))))
                (loop (+ i 1) (cons flipped found)))
              (loop (+ i 1) found))))))

(test-equal "case-flips, the helper: each of Proxy-Authorization's eighteen letters flipped alone, the dash kept"
  '(18 "proxy-Authorization" "Proxy-AuthorizatioN" "pROXY-AUTHORIZATION")
  (let ((flips (case-flips proxy-authorization)))
    (list (length flips) (car flips) (list-ref flips 17) (car (case-flips "PROXY-AUTHORIZATION")))))

;; header-list-at : String Natural -> (Listof (Pairof String String))
;; Four headers, the one named NAME at position AT, 0 to 3.
(define (header-list-at name at)
  (let loop ((i 0) (found '()))
    (if (= i 4)
        (reverse found)
        (loop (+ i 1) (cons (if (= i at) (cons name "Basic cHg6UHIweHlTM2NyM3Q=") (cons (string-append "X-H" (number->string i)) "v"))
                            found)))))

(test-equal "proxy-authorization-header: a Proxy-Authorization header is refused as the request is made, field header-name, its name as given, never its value, at every position of a list of four, in each letter's case, all upper and all lower, and whatever proxy the request names"
  (append (map (lambda (at) (list 'refused 'header-name proxy-authorization 'proxy-authorization-header 'make-curl-request))
               '(0 1 2 3))
          (map (lambda (name) (list 'refused 'header-name name 'proxy-authorization-header 'make-curl-request))
               (append (case-flips proxy-authorization) '("PROXY-AUTHORIZATION" "proxy-authorization")))
          (map (lambda (p) (list 'refused 'header-name proxy-authorization 'proxy-authorization-header 'make-curl-request))
               '(1 2 3)))
  (append (map (lambda (at) (made (lambda () (make-curl-request nowhere 'headers (header-list-at proxy-authorization at)))))
               '(0 1 2 3))
          (map (lambda (name) (made (lambda () (make-curl-request nowhere 'headers (list (cons name "x"))))))
               (append (case-flips proxy-authorization) '("PROXY-AUTHORIZATION" "proxy-authorization")))
          (map (lambda (p) (made (lambda () (make-curl-request nowhere 'proxy p 'headers (list (cons proxy-authorization "x"))))))
               (list #f "http://127.0.0.1:1" 'environment))))

(test-equal "proxy-authorization-header is refused by its name before its value is read: a value holding CR LF, or past U+00FF, refused for the header, not the value, so the refusal holds no secret"
  (list (list 'refused 'header-name proxy-authorization 'proxy-authorization-header 'make-curl-request)
        (list 'refused 'header-name proxy-authorization 'proxy-authorization-header 'make-curl-request))
  (list (made (lambda () (make-curl-request nowhere 'headers (list (cons proxy-authorization "Basic s3cret\r\nX: y")))))
        (made (lambda () (make-curl-request nowhere 'headers (list (cons proxy-authorization "\x2603;")))))))

(test-equal "its neighbours pass: Proxy-Authorizatio, Proxy-Authorizations, X-Proxy-Authorization, Proxy-Authenticate, ProxyAuthorization, Proxy_Authorization and Authorization"
  '(made made made made made made made)
  (map (lambda (name) (made (lambda () (make-curl-request nowhere 'headers (list (cons name "x"))))))
       '("Proxy-Authorizatio" "Proxy-Authorizations" "X-Proxy-Authorization" "Proxy-Authenticate"
         "ProxyAuthorization" "Proxy_Authorization" "Authorization")))

(test-equal "proxy-authorization-header again at curl-request-with, and at curl-request-check and a submit, on their own copies: a header renamed after the request was made is refused there, each as its who"
  (list (list 'refused 'header-name "proxy-authorization" 'proxy-authorization-header 'curl-request-with)
        (list 'refused 'header-name "pROXY-AUTHORIZATION" 'proxy-authorization-header 'curl-request-check)
        (list 'refused 'header-name "pROXY-AUTHORIZATION" 'proxy-authorization-header 'curl-submit))
  (let* ((headers (list (cons (string-copy "X-Proxy-Authorization") "x")))
         (r (make-curl-request nowhere 'headers headers)))
    (set-car! (car headers) "pROXY-AUTHORIZATION")
    (list (made (lambda () (curl-request-with (make-curl-request nowhere)
                                              'headers '(("proxy-authorization" . "x")))))
          (checked (lambda () (curl-request-check r)))
          (on-own-engine (lambda (e) (checked (lambda () (curl-submit e r))))))))

;; --- the proxy's TLS fields beside their proxy ----------------------------------------

(define proxy-ca-path "/x/proxy-ca.pem")

(test-equal "proxy-tls-without-https-proxy: a proxy-ca-file, or proxy-verify #f, beside environment, #f or an http:// proxy URL, in any case, is refused at check and submit, field proxy-ca-file and its path, or proxy-verify and #f, the CA file first; never as the request is made"
  (map (lambda (proxy)
         (list 'made
               (refused-both 'proxy-ca-file proxy-ca-path 'proxy-tls-without-https-proxy)
               (refused-both 'proxy-verify #f 'proxy-tls-without-https-proxy)
               (refused-both 'proxy-ca-file proxy-ca-path 'proxy-tls-without-https-proxy)))
       '(1 2 3 4))
  (map (lambda (proxy)
         (list (made (lambda () (make-curl-request nowhere 'proxy proxy 'proxy-ca-file proxy-ca-path 'proxy-verify #f)))
               (both-ways nowhere 'proxy proxy 'proxy-ca-file proxy-ca-path)
               (both-ways nowhere 'proxy proxy 'proxy-verify #f)
               (both-ways nowhere 'proxy proxy 'proxy-ca-file proxy-ca-path 'proxy-verify #f)))
       (list 'environment #f "http://127.0.0.1:1" "HTTP://127.0.0.1:1")))

(test-equal "the neighbours pass: each beside an https:// proxy URL, in any case; and proxy-verify #t, the default, beside any proxy"
  '((no-raise no-raise no-raise) (no-raise no-raise no-raise)
    no-raise no-raise no-raise no-raise)
  (append (map (lambda (proxy)
                 (list (proxy-check proxy 'proxy-ca-file proxy-ca-path)
                       (proxy-check proxy 'proxy-verify #f)
                       (proxy-check proxy 'proxy-ca-file proxy-ca-path 'proxy-verify #f)))
               '("https://127.0.0.1:1" "HTTPS://127.0.0.1:1"))
          (map (lambda (proxy) (proxy-check proxy 'proxy-verify #t))
               (list 'environment #f "http://127.0.0.1:1" "https://127.0.0.1:1"))))

;; --- prior knowledge beside a proxy URL (ADR-0034, amended) ----------------------------

(test-equal "prior-knowledge-through-proxy: http/2-prior-knowledge beside an http:// or https:// proxy URL is refused at check and submit, field http-version; beside environment and #f, and http/2, http/1.1 and none beside a proxy URL, pass; an https:// URL is prior-knowledge-over-https first; a proxy URL that does not parse is proxy-url first"
  (list (refused-both 'http-version 'http/2-prior-knowledge 'prior-knowledge-through-proxy)
        (refused-both 'http-version 'http/2-prior-knowledge 'prior-knowledge-through-proxy)
        '(no-raise no-raise) '(no-raise no-raise)
        'no-raise 'no-raise 'no-raise
        (checked-refusal 'http-version 'http/2-prior-knowledge 'prior-knowledge-over-https)
        (checked-refusal 'proxy 'proxy 'proxy-url))
  (list (both-ways nowhere 'proxy "http://127.0.0.1:1" 'http-version 'http/2-prior-knowledge)
        (both-ways nowhere 'proxy "https://127.0.0.1:1" 'http-version 'http/2-prior-knowledge)
        (both-ways nowhere 'proxy 'environment 'http-version 'http/2-prior-knowledge)
        (both-ways nowhere 'proxy #f 'http-version 'http/2-prior-knowledge)
        (proxy-check "http://127.0.0.1:1" 'http-version 'http/2)
        (proxy-check "http://127.0.0.1:1" 'http-version 'http/1.1)
        (proxy-check "http://127.0.0.1:1")
        (check-of nowhere-tls 'proxy "http://127.0.0.1:1" 'http-version 'http/2-prior-knowledge)
        (check-of nowhere 'proxy "127.0.0.1:1" 'http-version 'http/2-prior-knowledge)))

;; --- TLS inside TLS, by version and backend (ADR-0037, decisions 7 and 10) -------------

;; tls-in-tls-checks : (Listof (Pairof String (Listof Any)))
;; What curl-request-check answers an https:// URL through an https:// proxy
;; URL, asking #f, http/1.1 and http/2, then an http:// URL through it and
;; an https:// URL through an http:// proxy URL, by VERSION/BACKEND: 7.85.0
;; refuses unless http/1.1 is asked; Ubuntu's 8.5.0 with GnuTLS refuses
;; every one; with OpenSSL, 8.20.0 and 8.23.0 none; nor 8.7.1 with
;; SecureTransport, the Mac's.
(define tls-in-tls-refused
  '(refused proxy proxy proxy-tls-in-tls curl-request-check))
(define tls-in-tls-checks
  (list (cons "7.85.0/OpenSSL" (list tls-in-tls-refused 'no-raise tls-in-tls-refused 'no-raise 'no-raise))
        (cons "8.5.0/OpenSSL" '(no-raise no-raise no-raise no-raise no-raise))
        (cons "8.5.0/GnuTLS" (list tls-in-tls-refused tls-in-tls-refused tls-in-tls-refused 'no-raise 'no-raise))
        (cons "8.20.0/GnuTLS" '(no-raise no-raise no-raise no-raise no-raise))
        (cons "8.23.0/OpenSSL" '(no-raise no-raise no-raise no-raise no-raise))
        ;; The Mac's run, two passes alike: SecureTransport, with
        ;; CURL_SSL_BACKEND unset, refuses none, and through the engine an
        ;; https:// URL through an https:// proxy answered 200 for each
        ;; http-version asked.
        (cons "8.7.1/SecureTransport" '(no-raise no-raise no-raise no-raise no-raise))))

;; tls-in-tls-row : (U (Pairof String (Listof Any)) #f)
;; This lane's tls-in-tls-checks row, #f for none.
(define tls-in-tls-row (assoc lane tls-in-tls-checks))

;; tls-in-tls-verdict : Any Any -> Any
;; REFUSED where this lane's row refuses an https:// URL through an
;; https:// proxy asking nothing, PASSED where it passes; with no row,
;; (a-row-for LANE), which no measurement gives, so a lane with no row
;; fails by name, printing what it measured (AGENTS.md's by-version trap).
(define (tls-in-tls-verdict refused passed)
  (cond ((not tls-in-tls-row) (list 'a-row-for lane))
        ((equal? (list-ref (cdr tls-in-tls-row) 0) tls-in-tls-refused) refused)
        (else passed)))

(let ((pair (by-version tls-in-tls-checks "tls-in-tls-checks" lane
                        (lambda ()
                          (list (check-of nowhere-tls 'proxy "https://127.0.0.1:1")
                                (check-of nowhere-tls 'proxy "https://127.0.0.1:1" 'http-version 'http/1.1)
                                (check-of nowhere-tls 'proxy "https://127.0.0.1:1" 'http-version 'http/2)
                                (check-of nowhere 'proxy "https://127.0.0.1:1")
                                (check-of nowhere-tls 'proxy "http://127.0.0.1:1"))))))
  (test-equal "proxy-tls-in-tls, by version and backend: an https:// URL through an https:// proxy URL is refused where TLS inside TLS stalls, 7.85.0 unless http/1.1 is asked, Ubuntu's 8.5.0 with GnuTLS whatever is asked; an http:// URL through it, and an https:// URL through an http:// proxy, pass everywhere"
    (car pair)
    (cadr pair)))

(test-equal "proxy-tls-in-tls names the field and the libcurl, never the URL: its irritants are proxy, the version and the backend in use, where this lane's tls-in-tls-checks row refuses; elsewhere no raise; a lane with no row fails"
  (tls-in-tls-verdict (list 'proxy version (guard (e (#t (list 'no-backend (describe e)))) (loaded-tls-backend)))
                      'no-raise)
  (guard (e ((curl-request-error? e) (condition-irritants e)))
    (curl-request-check (make-curl-request nowhere-tls 'proxy "https://u:Pr0xyS3cr3t@127.0.0.1:1"))
    'no-raise))

;; --- no refusal holds the proxy's password -----------------------------------------------

(define secret "Pr0xyS3cr3t")

;; printed : Any -> String
;; X as write, display and display-condition print it, one after another.
(define (printed x)
  (call-with-string-output-port
   (lambda (p)
     (write x p) (newline p) (display x p) (newline p)
     (when (condition? x) (display-condition x p)))))

;; refusal-raised : (-> Any) -> Any
;; What THUNK raised, or no-raise.
(define (refusal-raised thunk)
  (guard (e (#t e)) (thunk) 'no-raise))

;; secret-requests : (Listof (List String (-> Any)))
;; Each refusal a request holding the proxy password meets, and the call
;; that meets it.
(define secret-cases
  (list (list "proxy-url" (lambda () (curl-request-check (make-curl-request nowhere 'proxy (string-append "u:" secret "@127.0.0.1:1")))))
        (list "proxy-url, a %" (lambda () (curl-request-check (make-curl-request nowhere 'proxy (string-append "http://u%zz:" secret "@127.0.0.1:1")))))
        (list "proxy-url, a raw control byte" (lambda () (curl-request-check (make-curl-request nowhere 'proxy (string-append "http://u:" secret "\x1;@127.0.0.1:1")))))
        (list "proxy-scheme" (lambda () (curl-request-check (make-curl-request nowhere 'proxy (string-append "socks5://u:" secret "@127.0.0.1:1")))))
        (list "proxy-url-parts" (lambda () (curl-request-check (make-curl-request nowhere 'proxy (string-append "http://u:" secret "@127.0.0.1:1/x")))))
        (list "credentials-bytes" (lambda () (curl-request-check (make-curl-request nowhere 'proxy (string-append "http://u%01:" secret "@127.0.0.1:1")))))
        (list "credentials-bytes, the password" (lambda () (curl-request-check (make-curl-request nowhere 'proxy (string-append "http://u:" secret "%7F@127.0.0.1:1")))))
        (list "proxy-tls-without-https-proxy" (lambda () (curl-request-check (make-curl-request nowhere 'proxy (string-append "http://u:" secret "@127.0.0.1:1") 'proxy-verify #f))))
        (list "prior-knowledge-through-proxy" (lambda () (curl-request-check (make-curl-request nowhere 'proxy (string-append "http://u:" secret "@127.0.0.1:1") 'http-version 'http/2-prior-knowledge))))
        (list "proxy-tls-in-tls, or none" (lambda () (curl-request-check (make-curl-request nowhere-tls 'proxy (string-append "https://u:" secret "@127.0.0.1:1")))))
        (list "proxy-authorization-header" (lambda () (make-curl-request nowhere 'headers (list (cons proxy-authorization (string-append "Basic " secret))))))
        (list "a wrong type, a list holding the URL" (lambda () (make-curl-request nowhere 'proxy (list (string-append "http://u:" secret "@h/")))))
        (list "proxy-settings' wrong proxy" (lambda () (proxy-settings (list secret) #f #t)))
        (list "call-with-http-session, its procedure missing, a proxy URL last"
              (lambda () (call-with-http-session 'proxy (string-append "http://u:" secret "@127.0.0.1:1"))))
        (list "a session's proxy-url, at a call"
              (lambda () (call-with-http-session 'proxy (string-append "u:" secret "@127.0.0.1:1")
                                                 (lambda (s) (http-get s nowhere)))))
        (list "a submit's proxy-url"
              (lambda ()
                (let* ((e (make-curl-engine))
                       (c (refusal-raised (lambda () (curl-submit e (make-curl-request nowhere 'proxy (string-append "u:" secret "@h:1")))))))
                  (stop-bounded e)
                  (if (condition? c) (raise c) c))))))

(test-equal "no refusal holds the proxy's password: each condition, as write, display and display-condition print it, never shows it; and each did refuse, but TLS inside TLS where this lane's tls-in-tls-checks row passes it, a lane with no row failing"
  (map (lambda (c)
         (list (car c)
               (if (string=? (car c) "proxy-tls-in-tls, or none")
                   (tls-in-tls-verdict 'refused 'no-raise)
                   'refused)
               'no-secret))
       secret-cases)
  (map (lambda (c)
         (let ((raised (refusal-raised (cadr c))))
           (list (car c)
                 (if (eq? raised 'no-raise) 'no-raise 'refused)
                 (if (contains? (printed raised) secret) 'printed-the-secret 'no-secret))))
       secret-cases))

;; --- a secret where another value belongs (M7 slice 3's review) ---

;; misplaced-url : String
;; A proxy URL holding the secret, handed where it does not belong.
(define misplaced-url (string-append "http://alice:" secret "@127.0.0.1:3128/"))

;; raised-as : (-> Any) -> Any
;; What THUNK raised, as data: (curl-request-error FIELD VALUE REASON WHO),
;; (http-request-error FIELD VALUE REASON WHO), (assertion WHO IRRITANTS),
;; (raised TEXT); or no-raise.
(define (raised-as thunk)
  (let ((c (refusal-raised thunk)))
    (cond ((eq? c 'no-raise) 'no-raise)
          ((curl-request-error? c)
           (list 'curl-request-error (curl-request-error-field c) (curl-request-error-value c)
                 (curl-request-error-reason c) (and (who-condition? c) (condition-who c))))
          ((http-request-error? c)
           (list 'http-request-error (http-request-error-field c) (http-request-error-value c)
                 (http-request-error-reason c) (and (who-condition? c) (condition-who c))))
          ((assertion-violation? c)
           (list 'assertion (and (who-condition? c) (condition-who c))
                 (and (irritants-condition? c) (condition-irritants c))))
          (else (list 'raised (describe c))))))

;; with-session : (Session -> Any) -> Any
;; PROC's answer on a session of its own, closed after.
(define (with-session proc)
  (let ((s (make-http-session)))
    (dynamic-wind (lambda () #f) (lambda () (proc s)) (lambda () (http-session-close s)))))

;; misplaced-cases : (Listof (List String Any (-> Any)))
;; The review's nine, a proxy URL holding the secret, and slice 2's
;; credentials list, where a key belongs, at both levels; then the audit's:
;; a number there, headers of a wrong type holding an Authorization, a
;; header value refused, a body of a wrong type, a URL where a request, a
;; session or a token belongs, a hatch value of a wrong type. Each with
;; the refusal it must raise, its value named by its kind or its field.
(define misplaced-cases
  (list (list "make-curl-request, the proxy URL with no key"
              '(curl-request-error key (kind string) unknown-key make-curl-request)
              (lambda () (make-curl-request nowhere misplaced-url)))
        (list "make-curl-request, a key, its value, then the proxy URL with no key"
              '(curl-request-error key (kind string) unknown-key make-curl-request)
              (lambda () (make-curl-request nowhere 'timeout-ms 5000 misplaced-url 'x)))
        (list "curl-request-with, the proxy URL with no key"
              '(curl-request-error key (kind string) unknown-key curl-request-with)
              (lambda () (curl-request-with (make-curl-request nowhere) misplaced-url "x")))
        (list "make-http-session, the proxy URL with no key"
              '(http-request-error key (kind string) unknown-key make-http-session)
              (lambda () (make-http-session misplaced-url)))
        (list "make-http-session, the proxy URL as a key, a value after it"
              '(http-request-error key (kind string) unknown-key make-http-session)
              (lambda () (make-http-session misplaced-url 'x)))
        (list "call-with-http-session, the proxy URL with no key, then a procedure"
              '(http-request-error key (kind string) unknown-key make-http-session)
              (lambda () (call-with-http-session misplaced-url (lambda (s) 'ran))))
        (list "http-get, the proxy URL with no key"
              '(http-request-error key (kind string) unknown-key http-request)
              (lambda () (with-session (lambda (s) (http-get s nowhere misplaced-url)))))
        (list "slice 2's credentials, a list with no key, at make-curl-request"
              '(curl-request-error key (kind list) unknown-key make-curl-request)
              (lambda () (make-curl-request nowhere (list 'basic "alice" secret))))
        (list "slice 2's credentials, a list with no key, at make-http-session"
              '(http-request-error key (kind list) unknown-key make-http-session)
              (lambda () (make-http-session (list 'basic "alice" secret))))
        (list "a number where a key belongs"
              '(curl-request-error key (kind number) unknown-key make-curl-request)
              (lambda () (make-curl-request nowhere 5 misplaced-url)))
        (list "headers of a wrong type, an Authorization among them"
              '(assertion make-curl-request ((kind list)))
              (lambda () (make-curl-request nowhere 'headers (list (cons "Authorization" (string-append "Bearer " secret))
                                                                   (cons "X-Count" 5)))))
        (list "an Authorization value with a line break, refused by its header's name"
              '(curl-request-error header-value "Authorization" line-break make-curl-request)
              (lambda () (make-curl-request nowhere 'headers (list (cons "Authorization" (string-append "Bearer " secret "\r\n"))))))
        (list "a body of a wrong type, a list holding the secret"
              '(http-request-error body (kind list) not-a-body http-request)
              (lambda () (with-session (lambda (s) (http-post s nowhere 'body (list secret))))))
        (list "a URL where a request belongs, at curl-submit"
              '(assertion curl-submit ((kind string)))
              (lambda () (on-own-engine-raising (lambda (e) (curl-submit e misplaced-url)))))
        (list "a URL where a session belongs"
              '(assertion http-request ((kind string)))
              (lambda () (http-get misplaced-url nowhere)))
        (list "a URL where a token belongs"
              '(assertion curl-token-wait ((kind string)))
              (lambda () (curl-token-wait misplaced-url 10)))
        (list "a hatch value of a wrong type, the secret where a long belongs"
              '(assertion curl-request-with-options (("LOW_SPEED_TIME" kind string)))
              (lambda () (curl-request-with-options (make-curl-request nowhere) (list (cons "LOW_SPEED_TIME" secret)))))
        (list "control: a symbol where a key belongs is named as given"
              '(curl-request-error key proxyy unknown-key make-curl-request)
              (lambda () (make-curl-request nowhere 'proxyy misplaced-url)))
        (list "control: proxy given twice is named by its key"
              '(curl-request-error key proxy repeated-key make-curl-request)
              (lambda () (make-curl-request nowhere 'proxy misplaced-url 'proxy misplaced-url)))))

;; on-own-engine-raising : (Engine -> Any) -> Any
;; PROC's answer on an engine made for it and stopped after, whatever PROC
;; raises, which passes on.
(define (on-own-engine-raising proc)
  (let ((e (make-curl-engine)))
    (dynamic-wind (lambda () #f) (lambda () (proc e)) (lambda () (stop-bounded e)))))

(test-equal "no value found where another belongs prints the secret: the review's nine, a proxy URL and a credentials list where a key belongs, at both levels, each named by its kind, and the audit's, each named by its kind or its field; a symbol where a key belongs, and a key given twice, named as given; each as write, display and display-condition print it"
  (map (lambda (c) (list (car c) (cadr c) 'no-secret)) misplaced-cases)
  (map (lambda (c)
         (list (car c) (raised-as (caddr c))
               (if (contains? (printed (refusal-raised (caddr c))) secret) 'printed-the-secret 'no-secret)))
       misplaced-cases))

(test-equal "a request, its plan and a token holding the proxy's password print their type alone: each opaque, as test-auth holds the credentials'"
  '(no-secret no-secret no-secret)
  (let* ((r (make-curl-request nowhere 'proxy (string-append "http://u:" secret "@127.0.0.1:1")))
         (plan (guard (e (#t e)) (prepare-transfer r))))
    (list (if (contains? (printed r) secret) 'printed-the-secret 'no-secret)
          (if (contains? (printed plan) secret) 'printed-the-secret 'no-secret)
          (on-own-engine
           (lambda (e)
             (let* ((token (curl-submit e r)) (text (printed token)))
               (curl-token-cancel token)
               (curl-token-wait token 10000)
               (if (contains? text secret) 'printed-the-secret 'no-secret)))))))

;; --- through the engine, against the origin's proxy -----------------------------------

;; The faces whose ports a log line may name, for normalized.
(define named-faces '(http raw h2c https https-expired https-wrong-host https-untrusted raw-tls h2))

;; hostport : Origin Symbol -> String
(define (hostport o face)
  (let ((f (origin-face o face))) (string-append (car f) ":" (number->string (cdr f)))))

;; port-of : Origin Symbol -> String
(define (port-of o face) (number->string (cdr (origin-face o face))))

;; face-url : Origin Symbol String -> String
(define (face-url o face path)
  (string-append (if (memq face '(https https-expired https-wrong-host https-untrusted h2 raw-tls)) "https://" "http://")
                 (hostport o face) path))

;; proxy-at : Origin Symbol [String] -> String
;; FACE's URL as a proxy's, with USERINFO when given.
(define (proxy-at o face . userinfo)
  (string-append (if (eq? face 'http) "http://" "https://")
                 (if (pair? userinfo) (string-append (car userinfo) "@") "")
                 (hostport o face)))

;; local-url : Origin Symbol String -> String
;; FACE's URL for PATH at localhost: through the proxy, a CONNECT to it
;; needs Basic for alice or bob, and the good leaf names localhost.
(define (local-url o face path)
  (string-append "https://localhost:" (port-of o face) path))

;; split-lines : String -> (Listof String)
(define (split-lines text)
  (let loop ((start 0) (i 0) (found '()))
    (cond ((= i (string-length text))
           (reverse (if (= start i) found (cons (substring text start i) found))))
          ((char=? (string-ref text i) #\newline)
           (loop (+ i 1) (+ i 1) (cons (substring text start i) found)))
          (else (loop start (+ i 1) found)))))

;; replace-all : String String String -> String
(define (replace-all text old new)
  (let ((k (string-length old)))
    (let loop ((i 0) (out '()))
      (cond ((> (+ i k) (string-length text)) (apply string-append (reverse (cons (substring text i (string-length text)) out))))
            ((string=? (substring text i (+ i k)) old) (loop (+ i k) (cons new out)))
            (else (loop (+ i 1) (cons (string (string-ref text i)) out)))))))

;; digits-end : String Natural -> Natural
;; The index past the run of decimal digits in TEXT from START.
(define (digits-end text start)
  (let loop ((i start))
    (if (and (< i (string-length text)) (char<=? #\0 (string-ref text i) #\9)) (loop (+ i 1)) i)))

;; with-ports-named : Origin String -> String
;; LINE with each :PORT of a face, its digits whole, written :<FACE>.
(define (with-ports-named o line)
  (let ((ports (map (lambda (face) (cons (port-of o face) (string-append ":<" (symbol->string face) ">")))
                    (filter (lambda (face) (guard (e (#t #f)) (origin-face o face))) named-faces))))
    (let loop ((i 0) (out '()))
      (cond ((= i (string-length line)) (apply string-append (reverse out)))
            ((char=? (string-ref line i) #\:)
             (let* ((end (digits-end line (+ i 1)))
                    (hit (and (> end (+ i 1)) (assoc (substring line (+ i 1) end) ports))))
               (if hit
                   (loop end (cons (cdr hit) out))
                   (loop (+ i 1) (cons ":" out)))))
            (else (loop (+ i 1) (cons (string (string-ref line i)) out)))))))

;; renumbered : (Listof String) -> (Listof String)
;; LINES with each conn=N and via=N renumbered from 1, in the order each N
;; is first seen across both: a case's lines read alike whatever came
;; before them on the origin.
(define (renumbered lines)
  (let ((seen '()))
    (define (number-of n)
      (let ((hit (assoc n seen)))
        (if hit
            (cdr hit)
            (let ((k (+ 1 (length seen))))
              (set! seen (cons (cons n k) seen))
              k))))
    ;; renumber : String -> String, its keys in the order they stand.
    (define (renumber line)
      (let loop ((i 0) (out '()))
        (let ((key (cond ((and (<= (+ i 6) (string-length line)) (string=? (substring line i (+ i 6)) " conn=")) " conn=")
                         ((and (<= (+ i 5) (string-length line)) (string=? (substring line i (+ i 5)) " via=")) " via=")
                         (else #f))))
          (cond ((= i (string-length line)) (apply string-append (reverse out)))
                (key
                 (let* ((start (+ i (string-length key))) (end (digits-end line start)))
                   (loop end (cons (string-append key (number->string (number-of (substring line start end)))) out))))
                (else (loop (+ i 1) (cons (string (string-ref line i)) out)))))))
    ;; In order, line by line: map's order is no order (traps.md).
    (let loop ((rest lines) (found '()))
      (if (null? rest) (reverse found) (loop (cdr rest) (cons (renumber (car rest)) found))))))

;; headless : String -> String
;; LINE with head=N written head=_.
(define (headless line)
  (let loop ((i 0) (out '()))
    (cond ((> (+ i 5) (string-length line)) (apply string-append (reverse (cons (substring line i (string-length line)) out))))
          ((string=? (substring line i (+ i 5)) "head=")
           (loop (digits-end line (+ i 5)) (cons "head=_" out)))
          (else (loop (+ i 1) (cons (string (string-ref line i)) out))))))

;; head-of : String -> (U Natural #f)
;; The head=N of LINE.
(define (head-of line)
  (let loop ((i 0))
    (cond ((> (+ i 5) (string-length line)) #f)
          ((string=? (substring line i (+ i 5)) "head=")
           (string->number (substring line (+ i 5) (digits-end line (+ i 5)))))
          (else (loop (+ i 1))))))

(define (scenarios o)
  ;; The log engine reads /proxy-log on the http face, direct, for the whole
  ;; run; each case's transfers run on an engine of their own.
  (define log-engine (make-curl-engine))

  ;; log-read : Natural -> (List Natural Natural (Listof String))
  ;; /proxy-log?from=FROM: the lines so far, the proxy's connections open,
  ;; and the lines from FROM.
  (define (log-read from)
    (let* ((t (curl-submit log-engine (make-curl-request (face-url o 'http (string-append "/proxy-log?from=" (number->string from)))
                                                         'proxy #f 'timeout-ms 10000)))
           (r (curl-token-await t))
           (lines (split-lines (utf8->string (curl-response-body r))))
           (words (let loop ((i 0) (start 0) (found '()))
                    (let ((head (car lines)))
                      (cond ((= i (string-length head)) (reverse (cons (substring head start i) found)))
                            ((char=? (string-ref head i) #\space) (loop (+ i 1) (+ i 1) (cons (substring head start i) found)))
                            (else (loop (+ i 1) start found)))))))
      (list (string->number (list-ref words 1)) (string->number (list-ref words 3)) (cdr lines))))

  ;; settled-lines : Natural -> (Listof String)
  ;; The lines from MARK once the proxy holds no connection open, waited for
  ;; up to 10 s; as they are then otherwise.
  (define (settled-lines mark)
    (let ((deadline (+ (now-ms) 10000)))
      (let loop ()
        (let ((now (log-read mark)))
          (if (or (= (cadr now) 0) (>= (now-ms) deadline))
              (caddr now)
              (begin (pause-ms 10) (loop)))))))

  ;; close-line? : String -> Boolean
  (define (close-line? l) (string=? (substring l 0 (min 6 (string-length l))) "close "))

  ;; proxied : (-> Any) -> (List Any (Listof String))
  ;; THUNK's answer, and the proxy's log lines it made, once settled, ports
  ;; named, connections renumbered, heads written head=_, and the closes
  ;; last, sorted: an engine's stop closes its pool in no fixed order. A
  ;; case whose close order matters reads its lines itself.
  (define (proxied thunk)
    (let* ((mark (car (log-read 0)))
           (answer (thunk))
           (lines (map headless (renumbered (map (lambda (l) (with-ports-named o l)) (settled-lines mark))))))
      (list answer (append (filter (lambda (l) (not (close-line? l))) lines)
                           (list-sort string<? (filter close-line? lines))))))

  ;; proxied-raw : (-> Any) -> (List Any (Listof String))
  ;; proxied's, the lines as they came but for their ports.
  (define (proxied-raw thunk)
    (let* ((mark (car (log-read 0)))
           (answer (thunk))
           (lines (settled-lines mark)))
      (list answer (map (lambda (l) (with-ports-named o l)) lines))))

  ;; fetch : String . Keys -> Outcome
  ;; A GET of URL with a 10 s timeout and KEYS, on an engine of its own:
  ;; its outcome, or a submit's refusal.
  (define (fetch url . keys)
    (on-own-engine
     (lambda (e)
       (let ((submitted (guard (c ((curl-request-error? c) (refusal-of c)))
                          (curl-submit e (apply make-curl-request url 'timeout-ms 10000 keys)))))
         (if (curl-token? submitted) (outcome-of (awaited submitted)) submitted)))))

  (define ok '(response 200))

  ;; empty-userinfo-wire : (Listof (Pairof String (Listof Any)))
  ;; @ and :@ through the proxy, by version: 7.85.0, which reports neither
  ;; part, sends no Proxy-Authorization, where 8.5.0 and later refuse each
  ;; at submit, nothing sent (8.5.0 and 8.20.0 sent :, and 8.23.0 nothing,
  ;; the slice's measurement). 8.7.1's row is the Mac's.
  (define empty-later
    (list (list (list 'refused 'proxy '(proxy user) 'credentials-empty 'curl-submit) '())
          (list (list 'refused 'proxy '(proxy user) 'credentials-empty 'curl-submit) '())))
  (define empty-userinfo-wire
    (list (cons "7.85.0"
                (list (list ok '("request http conn=1 method=GET target=http://127.0.0.1:<http>/status/200 auth=-" "close http conn=1"))
                      (list ok '("request http conn=1 method=GET target=http://127.0.0.1:<http>/status/200 auth=-" "close http conn=1"))))
          (cons "8.5.0" empty-later) (cons "8.20.0" empty-later) (cons "8.23.0" empty-later)
          (cons "8.7.1" empty-later)))

  ;; --- a refused CONNECT, by version (ADR-0037, decision 9) ---

  ;; refused-rows : (Listof (Pairof String (Listof Any)))
  ;; Each refused CONNECT's code, class, CONNECT status and request size,
  ;; by version: 403, 407, 502 and 503 by the proxy's choice, a 407 for a
  ;; wrong password and for none at localhost, and a proxy that closes: 56,
  ;; send-receive, with the CONNECT's own bytes as the size on 7.85.0, and
  ;; 0 on 8.5.0; 7, connect, and 0, on 8.20.0 and 8.23.0; the close 56
  ;; everywhere, its status #f (the slice's measurement, item 4); on 8.7.1
  ;; 56, send-receive, and the size unknown, #f, as 8.7.x reports every
  ;; transfer's (the Mac's run, two runs alike).
  (define refused-statuses '(403 407 502 503 407 407 #f))
  (define (refused-row code class size)
    (map (lambda (status) (list (if status code 56) (if status class 'send-receive) status size))
         refused-statuses))
  (define refused-rows
    (list (cons "7.85.0" (refused-row 56 'send-receive 'the-connect))
          (cons "8.5.0" (refused-row 56 'send-receive 'zero))
          (cons "8.20.0" (refused-row 7 'connect 'zero))
          (cons "8.23.0" (refused-row 7 'connect 'zero))
          (cons "8.7.1" (refused-row 56 'send-receive 'unknown))))

  ;; refused-cell : String String -> (List Any Any Any Any)
  ;; URL through PROXY: its code, class, status and request size, the size
  ;; the-connect when it is the CONNECT's head on the proxy's log.
  (define (refused-cell url proxy)
    (let* ((c (proxied-raw (lambda () (fetch url 'proxy proxy))))
           (out (car c))
           (head (and (pair? (cadr c)) (head-of (car (cadr c))))))
      (if (and (pair? out) (eq? (car out) 'failed))
          (list (list-ref out 2) (list-ref out 3) (list-ref out 5)
                (let ((size (list-ref out 4)))
                  (cond ((not size) 'unknown) ((eqv? size 0) 'zero) ((and head (eqv? size head)) 'the-connect)
                        (else (list 'size size 'head head)))))
          (list out (cadr c)))))

  ;; --- no tunnel shared before 8.19.0 (ADR-0037, decision 8) ---

  ;; pair-run : String String -> (List Any Any Boolean (Listof String))
  ;; Two GETs of URL through PROXY on one engine, the second submitted once
  ;; the first is done and the proxy has had 1500 ms to see its connection
  ;; close: each outcome; whether the first's connection closed before the
  ;; second was submitted, FORBID_REUSE's effect; and the proxy's lines,
  ;; renumbered, the closes the engine's stop makes last, sorted, since
  ;; libcurl closes its pool in no fixed order.
  (define (pair-run url proxy)
    (let* ((mark (car (log-read 0)))
           (e (make-curl-engine))
           (first (outcome-of (awaited (curl-submit e (make-curl-request url 'timeout-ms 10000 'proxy proxy 'ca-file ca)))))
           (closed (and (wait-for (lambda ()
                                    (let ((lines (caddr (log-read mark))))
                                      (and (pair? lines)
                                           (exists (lambda (l) (string=? (substring l 0 (min 6 (string-length l))) "close ")) lines))))
                                  1500)
                        #t))
           (second (outcome-of (awaited (curl-submit e (make-curl-request url 'timeout-ms 10000 'proxy proxy 'ca-file ca))))))
      (stop-bounded e)
      (let* ((lines (map headless (renumbered (map (lambda (l) (with-ports-named o l)) (settled-lines mark)))))
             (closes (list-sort string<? (filter (lambda (l) (string=? (substring l 0 (min 6 (string-length l))) "close ")) lines)))
             (others (filter (lambda (l) (not (string=? (substring l 0 (min 6 (string-length l))) "close "))) lines)))
        (list first second closed (append others closes)))))

  ;; unshared-rows : (Listof (Pairof String (Listof Any)))
  ;; Two tunnels in turn through one proxy, by version: with alice's
  ;; userinfo, to localhost, and with none, to 127.0.0.1, each to the https
  ;; face. Below 8.19.0 each transfer opens a CONNECT of its own,
  ;; FRESH_CONNECT's effect, and alice's first closes as it ends,
  ;; FORBID_REUSE's, where the one with none stays in the pool until the
  ;; engine stops; from 8.19.0 the second rides the first's tunnel, and
  ;; nothing closes before the stop. 8.7.1's row is the Mac's.
  (define (unshared-below target auth)
    (list ok ok (string=? auth "basic:alice:s3cret")
          (append (if (string=? auth "basic:alice:s3cret")
                      (list (string-append "connect http conn=1 target=" target " answer=200 head=_ auth=" auth)
                            "inner https via=1 method=GET target=/status/200"
                            (string-append "connect http conn=2 target=" target " answer=200 head=_ auth=" auth)
                            "inner https via=2 method=GET target=/status/200")
                      (list (string-append "connect http conn=1 target=" target " answer=200 head=_ auth=" auth)
                            "inner https via=1 method=GET target=/status/200"
                            (string-append "connect http conn=2 target=" target " answer=200 head=_ auth=" auth)
                            "inner https via=2 method=GET target=/status/200"))
                  '("close http conn=1" "close http conn=2"))))
  (define (shared-from target auth)
    (list ok ok #f
          (list (string-append "connect http conn=1 target=" target " answer=200 head=_ auth=" auth)
                "inner https via=1 method=GET target=/status/200"
                "inner https via=1 method=GET target=/status/200"
                "close http conn=1")))
  (define unshared-rows
    (let ((below (list (unshared-below "localhost:<https>" "basic:alice:s3cret")
                       (unshared-below "127.0.0.1:<https>" "-")))
          (from (list (shared-from "localhost:<https>" "basic:alice:s3cret")
                      (shared-from "127.0.0.1:<https>" "-"))))
      (list (cons "7.85.0" below) (cons "8.5.0" below) (cons "8.20.0" from) (cons "8.23.0" from)
            (cons "8.7.1" below))))

  ;; tunnel-plans : (Listof (Pairof String (Listof Any)))
  ;; The tunnel settings a submit's plan holds, and whether it stops the
  ;; engine's multiplexing, by version: an https:// URL through a proxy URL
  ;; with userinfo, without, an http:// URL through one with userinfo, and
  ;; an https:// URL through environment and #f. 8.7.1's row is the Mac's.
  (define tunnel-plans
    (let ((below '(((("FRESH_CONNECT" . 1) ("FORBID_REUSE" . 1)) #t) ((("FRESH_CONNECT" . 1)) #f)
                   (() #t) (() #f) (() #f)))
          (from '((() #f) (() #f) (() #f) (() #f) (() #f))))
      (list (cons "7.85.0" below) (cons "8.5.0" below) (cons "8.20.0" from) (cons "8.23.0" from)
            (cons "8.7.1" below))))

  ;; --- no multiplexing once an authenticated proxy is used, before 8.19.0 (decision 11) ---

  ;; connection-numbers : (Listof String) -> (Listof Any)
  ;; Each body's /connection number, renumbered from 1 in the order first
  ;; seen; a body that names none as itself.
  (define (connection-numbers bodies)
    (let loop ((rest bodies) (seen '()) (found '()))
      (if (null? rest)
          (reverse found)
          (let* ((body (car rest))
                 (n (and (string? body) (> (string-length body) 11)
                         (string=? (substring body 0 11) "connection ")
                         (string->number (substring body 11 (digits-end body 11))))))
            (cond ((not n) (loop (cdr rest) seen (cons (list 'not-a-connection body) found)))
                  ((assv n seen) => (lambda (hit) (loop (cdr rest) seen (cons (cdr hit) found))))
                  (else (let ((k (+ 1 (length seen))))
                          (loop (cdr rest) (cons (cons n k) seen) (cons k found)))))))))

  ;; streamed-text : Token -> (U String List)
  ;; TOKEN's streamed body, read whole as Latin-1, each piece waited for
  ;; up to 20 s.
  (define (streamed-text token)
    (let loop ((found '()))
      (let ((p (curl-token-next-piece token 20000)))
        (if (bytevector? p)
            (loop (append found (bytevector->u8-list p)))
            (list->string (map integer->char found))))))

  ;; switch-run : -> (List Any Any Any Any)
  ;; On one engine: A1 and A2 stream /connection?delay=6000 on the h2 face,
  ;; each head in before the next, so they share a connection where the
  ;; engine multiplexes; then S, an https:// URL through the http face's
  ;; proxy with alice's userinfo, awaited; then B, /connection on the h2
  ;; face, direct, awaited while A1 and A2 are live. The engine's
  ;; multiplexing before and after S; the connections A1, A2 and B used,
  ;; renumbered; whether A1 and A2 were done when B ended; and the four
  ;; outcomes.
  (define (switch-run)
    (on-own-engine
     (lambda (e)
       (let* ((streamed (lambda (path)
                          (curl-submit e (make-curl-request (local-url o 'h2 path) 'proxy #f 'ca-file ca
                                                            'timeout-ms 30000 'stream-buffer 4096))))
              (before (curl-engine-multiplexing e))
              (a1 (streamed "/connection?delay=6000"))
              (h1 (curl-token-head-wait a1 20000))
              (a2 (streamed "/connection?delay=6000"))
              (h2-head (curl-token-head-wait a2 20000))
              (s (outcome-of (awaited (curl-submit e (make-curl-request (local-url o 'https "/status/200")
                                                                        'proxy (proxy-at o 'http "alice:s3cret")
                                                                        'ca-file ca 'timeout-ms 20000)))))
              (after (curl-engine-multiplexing e))
              (b (awaited (curl-submit e (make-curl-request (local-url o 'h2 "/connection") 'proxy #f
                                                            'ca-file ca 'timeout-ms 20000))))
              (done (list (curl-token-done? a1) (curl-token-done? a2)))
              (t1 (streamed-text a1))
              (t2 (streamed-text a2))
              (o1 (outcome-of (awaited a1)))
              (o2 (outcome-of (awaited a2))))
         (list (list (if h1 'head 'no-head) (if h2-head 'head 'no-head) before after)
               (connection-numbers (list t1 t2 (if (curl-response? b) (latin-1 (curl-response-body b)) b)))
               done
               (list s (outcome-of b) o1 o2))))))

  ;; switch-rows : (Listof (Pairof String (List Any Any Any Any)))
  ;; switch-run's answer by version: below 8.19.0 S switches the engine,
  ;; A1 and A2 end 200 on their shared connection, and B, which would have
  ;; joined it, opens its own; from 8.19.0 nothing switches and B rides
  ;; theirs (the fix round's measurement, two runs on each lane). 8.7.1's
  ;; row is the Mac's.
  (define switch-rows
    (let ((ends (list ok ok ok ok)))
      (list (cons "7.85.0" (list '(head head default switched) '(1 1 2) '(#f #f) ends))
            (cons "8.5.0" (list '(head head default switched) '(1 1 2) '(#f #f) ends))
            (cons "8.20.0" (list '(head head default default) '(1 1 1) '(#f #f) ends))
            (cons "8.23.0" (list '(head head default default) '(1 1 1) '(#f #f) ends))
            ;; 8.7.x's engine never multiplexes: off from its start, each
            ;; stream on a connection of its own (the Mac's run, two runs).
            (cons "8.7.1" (list '(head head off off) '(1 2 3) '(#f #f) ends)))))

  ;; join-child : -> Any
  ;; tests/proxy-env-join.sps in a child Chez, https_proxy naming the http
  ;; face's proxy with no userinfo, every other proxy variable unset: A
  ;; streams /connection?delay=3000 on the h2 face, at localhost, through
  ;; the named proxy with alice's userinfo, and once its head is in, B gets
  ;; /connection there through proxy environment. What the child printed,
  ;; read as data, or what went wrong.
  (define (join-child)
    (guard (e (#t (list 'raised (describe e))))
      (let ((r (capture-command
                (append (list "sh" "-c" child-script "sh" "env")
                        (apply append (map (lambda (name) (list "-u" name)) ambient-variables))
                        (list (string-append "https_proxy=" (proxy-at o 'http)))
                        (list (getenv "CHEZ") "--libdirs" (library-path)
                              "--program" "tests/proxy-env-join.sps" (proxy-at o 'http "alice:s3cret")
                              (local-url o 'h2 "/connection?delay=3000") (local-url o 'h2 "/connection") ca)))))
        (if (= (car r) 0)
            (read-all (cadr r))
            (list 'exit (car r) (cadr r) (caddr r))))))

  ;; join-rows : (Listof (Pairof String (List Any Any)))
  ;; join-child's answer and the proxy's lines, by version: below 8.19.0
  ;; the engine switches at A, so B sends a CONNECT of its own, refused 407,
  ;; where 7.85.0 had let it ride A's tunnel as a second stream and get
  ;; 200 (the review's probe); from 8.19.0 nothing switches, and B's own
  ;; CONNECT is refused alike. Its code is the refused CONNECT's, by
  ;; version. 8.7.1's row is the Mac's.
  (define (join-row before after code class)
    (list (list (list 'environment '(no_proxy . #f) '(NO_PROXY . #f) '(http_proxy . #f)
                      (cons 'https_proxy (proxy-at o 'http)) '(all_proxy . #f))
                (list 'multiplexing before after)
                (list 'join #t (list 'refused 'perform-failed code class 407) '(response 200))
                (list 'transfer zero-counts)
                '(done))
          '("connect http conn=1 target=localhost:<h2> answer=200 head=_ auth=basic:alice:s3cret"
            "inner h2 via=1 method=GET target=/connection?delay=3000"
            "connect http conn=2 target=localhost:<h2> answer=407 head=_ auth=-"
            "close http conn=1" "close http conn=2")))
  (define join-rows
    (list (cons "7.85.0" (join-row 'default 'switched 56 'send-receive))
          (cons "8.5.0" (join-row 'default 'switched 56 'send-receive))
          (cons "8.20.0" (join-row 'default 'default 7 'connect))
          (cons "8.23.0" (join-row 'default 'default 7 'connect))
          ;; 8.7.x's engine never multiplexes, so it reads off before and
          ;; after (the Mac's run, two runs).
          (cons "8.7.1" (join-row 'off 'off 56 'send-receive))))

  ;; --- the high level (the M7 plan, section 3.1) ---

  ;; call-outcome : (-> Any) -> Any
  ;; What a call answers, (answered STATUS), or raises, (raised FIELD VALUE
  ;; REASON TRANSFERS) for a request's refusal, (failed CODE STATUS
  ;; TRANSFERS) for a transfer's failure, (raised TEXT) else.
  (define (call-outcome thunk)
    (guard (e ((and (curl-request-error? e))
               (list 'raised (curl-request-error-field e) (curl-request-error-value e)
                     (curl-request-error-reason e) (and (http-exchange? e) (http-exchange-transfers e))))
              ((curl-transfer-error? e)
               (list 'failed (curl-transfer-error-code e) (curl-transfer-error-connect-code e)
                     (and (http-exchange? e) (http-exchange-transfers e))))
              (#t (list 'raised (describe e))))
      (let ((r (thunk)))
        (if (http-response? r) (list 'answered (http-response-status r)) (list 'not-a-response r)))))

  ;; in-session : List (Session -> Any) -> Any
  ;; PROC's answer on a session made with KEYS, closed after.
  (define (in-session keys proc)
    (guard (e (#t (list 'raised (describe e))))
      (let ((s (apply make-http-session keys)))
        (let ((answer (guard (e (#t (list 'raised (describe e)))) (proc s))))
          (http-session-close s)
          answer))))

  ;; pct-component : String -> String
  ;; S with each char but a letter, a digit, - . _ and ~ as %XX: a query
  ;; value the origin's redirect route decodes back to S.
  (define (pct-component s)
    (apply string-append
           (map (lambda (b)
                  (if (or (<= 48 b 57) (<= 65 b 90) (<= 97 b 122) (memv b '(45 46 95 126)))
                      (string (integer->char b))
                      (hex2 b)))
                (bytevector->u8-list (string->utf8 s)))))

  ;; --- a refused CONNECT retried by its status (ADR-0026, amended 2026-11-03) ---

  ;; retried : List String Symbol -> (List Any Natural)
  ;; A call of METHOD to URL through the http face's proxy, with POLICY-KEYS
  ;; for make-http-retry, on a session of its own: what it raised, and the
  ;; CONNECTs the proxy logged for it.
  (define (retried policy-keys url method)
    (let ((c (proxied-raw
              (lambda ()
                (in-session (list 'timeout-ms 10000 'proxy (proxy-at o 'http)
                                  'retry (apply make-http-retry 'backoff-ms 1 'jitter #f policy-keys))
                            (lambda (s)
                              (call-outcome (lambda ()
                                              (if (eq? method 'post)
                                                  (http-request s method url 'body "b=1")
                                                  (http-request s method url))))))))))
      (list (car c)
            (length (filter (lambda (l) (string=? (substring l 0 (min 8 (string-length l))) "connect ")) (cadr c))))))

  ;; code-of-refusal : Any
  ;; A refused CONNECT's code on this libcurl, refused-rows' first cell's;
  ;; with no row, (a-row-for VERSION), which no measurement gives.
  (define code-of-refusal
    (let ((row (assoc version refused-rows)))
      (if row (car (cadr row)) (list 'a-row-for version))))

  ;; closing-retries : (Listof (Pairof String (Listof Any)))
  ;; A proxy that closes a CONNECT keeps the class rule, by version: its
  ;; 56 carries the CONNECT's bytes as its request size on 7.85.0, so a post
  ;; outside the policy's methods is tried once there, and three times on
  ;; 8.5.0 and later, where its size is 0; a get, in the methods, three
  ;; times everywhere. 8.7.1's row is the Mac's.
  (define closing-retries
    (let ((later '(((failed 56 #f 3) 3) ((failed 56 #f 3) 3))))
      (list (cons "7.85.0" '(((failed 56 #f 1) 1) ((failed 56 #f 3) 3)))
            (cons "8.5.0" later) (cons "8.20.0" later) (cons "8.23.0" later)
            ;; 8.7.x reports no request size, so a post outside the methods
            ;; is tried once, as on 7.85.0 (ADR-0022; the Mac's run, two runs).
            (cons "8.7.1" '(((failed 56 #f 1) 1) ((failed 56 #f 3) 3))))))

  ;; --- in a child, given the environment through its command ---

  ;; child : (Listof String) String String String String String -> Any
  ;; tests/proxy-env.sps on URL through PROXY, with PROXY-CA-FILE, PROXY-VERIFY
  ;; and CA-FILE, in a child Chez, ASSIGNMENTS, each NAME=VALUE, in its
  ;; environment alone, every other proxy and CA variable unset there: what
  ;; it printed, read as data, from its environment line on, or what went
  ;; wrong.
  (define (child assignments url proxy proxy-ca-file proxy-verify ca-file)
    (guard (e (#t (list 'raised (describe e))))
      (let ((r (capture-command
                (append (list "sh" "-c" child-script "sh" "env")
                        (apply append (map (lambda (name) (list "-u" name)) ambient-variables))
                        assignments
                        (list (getenv "CHEZ") "--libdirs" (library-path)
                              "--program" "tests/proxy-env.sps" url proxy proxy-ca-file proxy-verify ca-file)))))
        (if (= (car r) 0)
            (read-all (cadr r))
            (list 'exit (car r) (cadr r) (caddr r))))))

  ;; no-proxy-cases : (Listof (List String (Listof String)))
  ;; Each environment beside a named proxy: no_proxy and NO_PROXY naming
  ;; the origin's host, no_proxy *, and the proxy variables naming another
  ;; proxy, a refused port, with no_proxy naming the host too.
  (define no-proxy-cases
    '(("no_proxy naming 127.0.0.1" ("no_proxy=127.0.0.1"))
      ("NO_PROXY naming 127.0.0.1" ("NO_PROXY=127.0.0.1"))
      ("no_proxy *" ("no_proxy=*"))
      ("http_proxy, https_proxy and all_proxy at a refused port, no_proxy naming 127.0.0.1"
       ("http_proxy=http://127.0.0.1:1" "https_proxy=http://127.0.0.1:1" "all_proxy=http://127.0.0.1:1"
        "no_proxy=127.0.0.1"))))

  ;; environment-of : (Listof String) -> (Listof (Pairof Symbol (U String #f)))
  ;; What the child's environment line holds for ASSIGNMENTS, every other
  ;; variable unset.
  (define (environment-of assignments)
    (map (lambda (name)
           (cons (string->symbol name)
                 (let ((hit (find (lambda (a) (and (> (string-length a) (string-length name))
                                                   (string=? (substring a 0 (+ 1 (string-length name)))
                                                             (string-append name "="))))
                                  assignments)))
                   (and hit (substring hit (+ 1 (string-length name)) (string-length hit))))))
         '("no_proxy" "NO_PROXY" "http_proxy" "https_proxy" "all_proxy" "SSL_CERT_FILE" "SSL_CERT_DIR")))

  ;; guix-libcurl? : Boolean
  ;; Whether this libcurl is Guix's, by the records test-transfer-tls holds
  ;; to its own reading: its mapped file under /gnu/store/, or holding the
  ;; patch's literal.
  (define guix-libcurl?
    (guard (e (#t #f))
      (let ((file (loaded-libcurl-file)))
        (or (eq? (loaded-libcurl-patched?) #t)
            (and (string? file) (>= (string-length file) 11) (string=? (substring file 0 11) "/gnu/store/"))))))

  ;; --- absolute form and its credentials' bytes ---

  (for-each
   (lambda (row)
     (test-equal (string-append "absolute form through an http:// proxy URL, its userinfo " (car row)
                                ": the proxy logs the request, its target in absolute form, and its Proxy-Authorization decoded, " (cadr row))
       (list ok (list (string-append "request http conn=1 method=GET target=http://127.0.0.1:<http>/status/200 auth=" (caddr row))
                      "close http conn=1"))
       (proxied (lambda () (fetch (face-url o 'http "/status/200") 'proxy (proxy-at o 'http (car row)))))))
   '(("u:p" "u:p" "basic:u:p")
     ("u%20x:p%3Aq" "a space in the user, a colon in the password" "basic:u x:p:q")
     ("%41%42:%7E%7e" "letters and tildes, encoded" "basic:AB:~~")
     ("%C3%A9l%C3%A8ve:p%C3%A4ss" "UTF-8, encoded" "basic:\\xc3\\xa9l\\xc3\\xa8ve:p\\xc3\\xa4ss")
     ("\xE9;l\xE8;ve:p\xE4;ss" "UTF-8, raw" "basic:\\xc3\\xa9l\\xc3\\xa8ve:p\\xc3\\xa4ss")
     ("u:p:q" "a raw colon in the password" "basic:u:p:q")
     ("u" "a user alone" "basic:u:")
     ("u:" "a user and an empty password" "basic:u:")
     (":p" "an empty user and a password" "basic::p")
     ("u:\x7E;%25" "a percent sign, encoded, and a raw tilde" "basic:u:~%")))

  (test-equal "absolute form through an http:// proxy URL with no userinfo: the proxy logs the request with no Proxy-Authorization"
    (list ok '("request http conn=1 method=GET target=http://127.0.0.1:<http>/status/200 auth=-" "close http conn=1"))
    (proxied (lambda () (fetch (face-url o 'http "/status/200") 'proxy (proxy-at o 'http)))))

  (let ((pair (by-version empty-userinfo-wire "empty-userinfo-wire" version
                          (lambda ()
                            (map (lambda (info)
                                   (proxied (lambda () (fetch (face-url o 'http "/status/200") 'proxy (proxy-at o 'http info)))))
                                 '("" ":"))))))
    (test-equal "an empty userinfo through the proxy, by version: @ and :@ send no Proxy-Authorization on 7.85.0, and are refused at submit from 8.5.0, the proxy getting nothing"
      (car pair)
      (cadr pair)))

  ;; --- CONNECT, through an http:// proxy URL ---

  (test-equal "an https:// URL through an http:// proxy URL goes by CONNECT: the proxy logs the CONNECT to the origin's face, its answer, the origin's request inside the tunnel, and the close"
    (list ok '("connect http conn=1 target=127.0.0.1:<https> answer=200 head=_ auth=-"
               "inner https via=1 method=GET target=/status/200"
               "close http conn=1"))
    (proxied (lambda () (fetch (face-url o 'https "/status/200") 'proxy (proxy-at o 'http) 'ca-file ca))))

  (test-equal "the proxy's credentials go on the CONNECT: alice and s3cret to localhost, which the proxy requires, pass; the origin's request inside the tunnel carries none of the proxy's"
    (list ok '("connect http conn=1 target=localhost:<https> answer=200 head=_ auth=basic:alice:s3cret"
               "inner https via=1 method=GET target=/status/200"
               "close http conn=1"))
    (proxied (lambda () (fetch (local-url o 'https "/status/200") 'proxy (proxy-at o 'http "alice:s3cret") 'ca-file ca))))

  (test-equal "an HTTP/2 origin through an http:// proxy URL: the CONNECT, then an HTTP/2 stream inside the tunnel"
    (list ok '("connect http conn=1 target=127.0.0.1:<h2> answer=200 head=_ auth=-"
               "inner h2 via=1 method=GET target=/status/200"
               "close http conn=1"))
    (proxied (lambda () (fetch (face-url o 'h2 "/status/200") 'proxy (proxy-at o 'http) 'ca-file ca))))

  ;; --- the copies, through the engine ---

  (test-equal "the copies through the engine: the caller's proxy string and proxy CA file string changed after the request was made, the proxy URL's password made wrong and the CA file's path one that names no file, the request goes as made, through the https:// proxy, its CA the copy's"
    (list ok '("request https conn=1 method=GET target=http://127.0.0.1:<http>/status/200 auth=basic:alice:s3cret"
               "close https conn=1"))
    (proxied (lambda ()
               (let* ((proxy (proxy-at o 'https "alice:s3cret"))
                      (path (string-copy ca))
                      (r (make-curl-request (face-url o 'http "/status/200") 'timeout-ms 10000 'proxy proxy
                                            'proxy-ca-file path)))
                 (string-set! proxy 15 #\X)
                 (string-set! path (- (string-length path) 1) #\X)
                 (on-own-engine (lambda (e) (outcome-of (awaited (curl-submit e r)))))))))

  ;; --- the proxy's TLS: each leaf, verification on and off ---

  (test-equal "an https:// proxy URL, its own CA file the run's: the good leaf passes, the request in absolute form on its log; the expired, wrong-host and untrusted leaves fail 60, tls, nothing sent and nothing on any log; each passes with the proxy's verification off, its log naming the face"
    (list (list ok '("request https conn=1 method=GET target=http://127.0.0.1:<http>/status/200 auth=-" "close https conn=1"))
          (list tls-failure '())
          (list tls-failure '())
          (list tls-failure '())
          (list ok '("request https-expired conn=1 method=GET target=http://127.0.0.1:<http>/status/200 auth=-" "close https-expired conn=1"))
          (list ok '("request https-wrong-host conn=1 method=GET target=http://127.0.0.1:<http>/status/200 auth=-" "close https-wrong-host conn=1"))
          (list ok '("request https-untrusted conn=1 method=GET target=http://127.0.0.1:<http>/status/200 auth=-" "close https-untrusted conn=1")))
    (let loop ((rest '((https #t) (https-expired #t) (https-wrong-host #t) (https-untrusted #t)
                       (https-expired #f) (https-wrong-host #f) (https-untrusted #f)))
               (found '()))
      (if (null? rest)
          (reverse found)
          (loop (cdr rest)
                (cons (proxied (lambda () (fetch (face-url o 'http "/status/200") 'proxy (proxy-at o (caar rest))
                                                 'proxy-ca-file ca 'proxy-verify (cadar rest))))
                      found)))))

  (test-equal "the proxy's TLS is its own: with no proxy CA file, the good leaf fails 60 against libcurl's default store, the origin's CA file beside it, or the origin's verification off, changing nothing; another CA as the proxy's fails 60; the origin's CA file another CA's changes nothing for an http:// URL through the proxy"
    (list (list tls-failure '())
          (list tls-failure '())
          (list tls-failure '())
          (list tls-failure '())
          (list ok '("request https conn=1 method=GET target=http://127.0.0.1:<http>/status/200 auth=-" "close https conn=1")))
    (let loop ((rest (list (list) (list 'ca-file ca) (list 'verify #f) (list 'proxy-ca-file other-ca)
                           (list 'proxy-ca-file ca 'ca-file other-ca)))
               (found '()))
      (if (null? rest)
          (reverse found)
          (loop (cdr rest)
                (cons (proxied (lambda () (apply fetch (face-url o 'http "/status/200") 'proxy (proxy-at o 'https) (car rest))))
                      found)))))

  (test-equal "the origin's TLS is its own: through an http:// proxy, the origin's CA file another CA's fails tls after the CONNECT passed, no request inside the tunnel; the proxy's verification never reaches it; the origin's verification off passes"
    (list (list 'tls '("connect http conn=1 target=127.0.0.1:<https> answer=200 head=_ auth=-" "close http conn=1"))
          (list ok '("connect http conn=1 target=127.0.0.1:<https> answer=200 head=_ auth=-"
                     "inner https via=1 method=GET target=/status/200" "close http conn=1")))
    (list (let ((c (proxied (lambda () (fetch (face-url o 'https "/status/200") 'proxy (proxy-at o 'http) 'ca-file other-ca)))))
            (list (if (and (pair? (car c)) (eq? (caar c) 'failed)) (list-ref (car c) 3) (car c)) (cadr c)))
          (proxied (lambda () (fetch (face-url o 'https "/status/200") 'proxy (proxy-at o 'http) 'verify #f)))))

  (let ((pair (by-version refused-rows "refused-connect" version
                          (lambda ()
                            (let loop ((rest (list (list "https://refuse-403.invalid:443/" (proxy-at o 'http))
                                                   (list "https://refuse-407.invalid:443/" (proxy-at o 'http))
                                                   (list "https://refuse-502.invalid:443/" (proxy-at o 'http))
                                                   (list "https://refuse-503.invalid:443/" (proxy-at o 'http))
                                                   (list (local-url o 'https "/") (proxy-at o 'http "alice:Wr0ngS3cr3t"))
                                                   (list (local-url o 'https "/") (proxy-at o 'http))
                                                   (list "https://close.invalid:443/" (proxy-at o 'http))))
                                       (found '()))
                              (if (null? rest)
                                  (reverse found)
                                  (loop (cdr rest) (cons (refused-cell (caar rest) (cadar rest)) found))))))))
    (test-equal "a refused CONNECT, by version: 403, 407, 502 and 503, a wrong password and none: 56 send-receive on 7.85.0 and 8.5.0, 7 connect on 8.20.0 and 8.23.0, each carrying the status as curl-transfer-error-connect-code; a close, 56 and no status; the request size the CONNECT's own bytes on 7.85.0 alone"
      (car pair)
      (cadr pair)))

  (test-equal "a transfer that sent no CONNECT, or whose tunnel opened, carries no CONNECT status: a refused port direct, and an origin's TLS refused inside a passing tunnel"
    '(no-status no-status)
    (map (lambda (c) (if (and (pair? c) (eq? (car c) 'failed)) (or (list-ref c 5) 'no-status) (list 'not-failed c)))
         (list (fetch "http://127.0.0.1:1/" 'proxy #f)
               (fetch (face-url o 'https "/") 'proxy (proxy-at o 'http) 'ca-file other-ca))))

  (let ((pair (by-version unshared-rows "unshared-tunnels" version
                          (lambda ()
                            (let* ((alice (pair-run (local-url o 'https "/status/200") (proxy-at o 'http "alice:s3cret")))
                                   (none (pair-run (face-url o 'https "/status/200") (proxy-at o 'http))))
                              (list alice none))))))
    (test-equal "two tunnels in turn through one proxy, by version: below 8.19.0 the second opens a CONNECT of its own, and the first, with userinfo, closes as it ends, where with none it stays pooled; from 8.19.0 the second rides the first's tunnel"
      (car pair)
      (cadr pair)))

  (test-equal "an http:// URL's requests in turn through the proxy, alice's userinfo on each, share the proxy's connection on every libcurl: no tunnel, so nothing is set to keep it apart"
    (list ok ok #f
          '("request http conn=1 method=GET target=http://127.0.0.1:<http>/status/200 auth=basic:alice:s3cret"
            "request http conn=1 method=GET target=http://127.0.0.1:<http>/status/200 auth=basic:alice:s3cret"
            "close http conn=1"))
    (pair-run (face-url o 'http "/status/200") (proxy-at o 'http "alice:s3cret")))

  (let ((pair (by-version tunnel-plans "tunnel-plans" version
                          (lambda ()
                            (map (lambda (args)
                                   (guard (e (#t (list 'raised (describe e))))
                                     (let ((plan (prepare-transfer (apply make-curl-request args))))
                                       (list (plan-tunnel plan) (plan-unmultiplex plan)))))
                                 (list (list nowhere-tls 'proxy "http://u:p@127.0.0.1:1")
                                       (list nowhere-tls 'proxy "http://127.0.0.1:1")
                                       (list nowhere 'proxy "http://u:p@127.0.0.1:1")
                                       (list nowhere-tls 'proxy 'environment)
                                       (list nowhere-tls 'proxy #f)))))))
    (test-equal "a submit's plan holds the tunnel settings and whether it stops the engine's multiplexing, by version: below 8.19.0 FRESH_CONNECT for an https:// URL through a proxy URL, FORBID_REUSE beside userinfo, and a proxy URL with userinfo stopping the multiplexing whatever the URL's scheme; nothing for an http:// URL's tunnel, nor beside environment or #f, nor from 8.19.0"
      (car pair)
      (cadr pair)))

  (let ((pair (by-version switch-rows "switch-live" version switch-run)))
    (test-equal "a transfer through a proxy URL with userinfo stops the engine's multiplexing, by version: below 8.19.0 the engine switches at it, the two streams live on one HTTP/2 connection end 200 on it, unbroken, and a third request to their origin, made while they are live, opens a connection of its own; from 8.19.0 nothing switches, and the third rides theirs"
      (car pair)
      (cadr pair)))

  (let ((pair (by-version join-rows "environment-join" version (lambda () (proxied join-child)))))
    (test-equal "in a child, https_proxy naming the proxy with no userinfo: a transfer through proxy environment, made while a named proxy's transfer with alice's userinfo has its HTTP/2 stream live, sends a CONNECT of its own and is refused 407, by version: below 8.19.0 the engine switched at alice's, where 7.85.0 had let it ride her tunnel; from 8.19.0 no switch"
      (car pair)
      (cadr pair)))

  (test-equal "an https:// URL through an https:// proxy, through the engine, each http-version: refused at submit where this lane's tls-in-tls-checks row says so, the proxy getting nothing; else 200, the CONNECT on the https face and the request inside it; every transfer bounded at 10 s, as the slice's measurement was, so a stall the refusal misses fails as 28"
    (if tls-in-tls-row
        (map (lambda (cell)
               (if (equal? cell tls-in-tls-refused)
                   (list (list 'refused 'proxy 'proxy 'proxy-tls-in-tls 'curl-submit) '())
                   (list ok '("connect https conn=1 target=127.0.0.1:<https> answer=200 head=_ auth=-"
                              "inner https via=1 method=GET target=/status/200" "close https conn=1"))))
             (list (list-ref (cdr tls-in-tls-row) 0) (list-ref (cdr tls-in-tls-row) 1) (list-ref (cdr tls-in-tls-row) 2)))
        (list 'a-row-for lane))
    (let loop ((rest '(#f http/1.1 http/2)) (found '()))
      (if (null? rest)
          (reverse found)
          (loop (cdr rest)
                (cons (proxied (lambda () (fetch (face-url o 'https "/status/200") 'proxy (proxy-at o 'https)
                                                 'proxy-ca-file ca 'ca-file ca 'http-version (car rest))))
                      found)))))

  (test-equal "an http:// URL through an https:// proxy, and an https:// URL through an http:// one, pass on every libcurl"
    (list (list ok '("request https conn=1 method=GET target=http://127.0.0.1:<http>/status/200 auth=-" "close https conn=1"))
          (list ok '("connect http conn=1 target=127.0.0.1:<https> answer=200 head=_ auth=-"
                     "inner https via=1 method=GET target=/status/200" "close http conn=1")))
    (list (proxied (lambda () (fetch (face-url o 'http "/status/200") 'proxy (proxy-at o 'https) 'proxy-ca-file ca)))
          (proxied (lambda () (fetch (face-url o 'https "/status/200") 'proxy (proxy-at o 'http) 'ca-file ca)))))

  ;; --- prior knowledge beside a named proxy, through the engine ---

  (test-equal "prior knowledge beside a proxy URL is refused at submit, the proxy getting nothing; beside proxy #f it speaks HTTP/2 to the h2c face, direct"
    (list (list (list 'refused 'http-version 'http/2-prior-knowledge 'prior-knowledge-through-proxy 'curl-submit) '())
          (list ok '()))
    (list (proxied (lambda () (fetch (face-url o 'h2c "/status/200") 'proxy (proxy-at o 'http) 'http-version 'http/2-prior-knowledge)))
          (proxied (lambda () (fetch (face-url o 'h2c "/status/200") 'proxy #f 'http-version 'http/2-prior-knowledge)))))

  (test-equal "a session's proxy and its TLS keys reach its call: an https:// proxy URL with alice's userinfo and the run's CA as the proxy's, the request on the https face's log"
    (list '(answered 200)
          '("request https conn=1 method=GET target=http://127.0.0.1:<http>/status/200 auth=basic:alice:s3cret"
            "close https conn=1"))
    (proxied (lambda ()
               (in-session (list 'timeout-ms 10000 'proxy (proxy-at o 'https "alice:s3cret") 'proxy-ca-file ca)
                           (lambda (s) (call-outcome (lambda () (http-get s (face-url o 'http "/status/200")))))))))

  (test-equal "a call that names its own proxy drops the session's proxy-ca-file and proxy-verify: an http:// proxy URL over a session's https:// one with its CA and its verification off passes, where kept they would be refused; one that names none keeps them; its own proxy-verify #f, over the session's, reaches the session's https:// proxy"
    (list (list '(answered 200)
                '("request http conn=1 method=GET target=http://127.0.0.1:<http>/status/200 auth=basic:bob:hunter2"
                  "close http conn=1"))
          (list '(answered 200)
                '("request https-expired conn=1 method=GET target=http://127.0.0.1:<http>/status/200 auth=-"
                  "close https-expired conn=1"))
          (list '(answered 200)
                '("request https-expired conn=1 method=GET target=http://127.0.0.1:<http>/status/200 auth=-"
                  "close https-expired conn=1")))
    (let ((url (face-url o 'http "/status/200")))
      (list (proxied (lambda ()
                       (in-session (list 'timeout-ms 10000 'proxy (proxy-at o 'https-expired) 'proxy-ca-file ca 'proxy-verify #f)
                                   (lambda (s) (call-outcome (lambda () (http-get s url 'proxy (proxy-at o 'http "bob:hunter2"))))))))
            (proxied (lambda ()
                       (in-session (list 'timeout-ms 10000 'proxy (proxy-at o 'https-expired) 'proxy-ca-file ca 'proxy-verify #f)
                                   (lambda (s) (call-outcome (lambda () (http-get s url)))))))
            (proxied (lambda ()
                       (in-session (list 'timeout-ms 10000 'proxy (proxy-at o 'https-expired) 'proxy-ca-file ca)
                                   (lambda (s) (call-outcome (lambda () (http-get s url 'proxy-verify #f))))))))))

  (test-equal "a call's proxy-ca-file replaces the session's: the other CA's from the call fails 60 at the proxy, nothing on its log; the run's from the call, over the session's other CA, passes"
    (list (list '(failed 60 #f 1) '())
          (list '(answered 200)
                '("request https conn=1 method=GET target=http://127.0.0.1:<http>/status/200 auth=-" "close https conn=1")))
    (let ((url (face-url o 'http "/status/200")))
      (list (proxied (lambda ()
                       (in-session (list 'timeout-ms 10000 'proxy (proxy-at o 'https) 'proxy-ca-file ca)
                                   (lambda (s) (call-outcome (lambda () (http-get s url 'proxy-ca-file other-ca)))))))
            (proxied (lambda ()
                       (in-session (list 'timeout-ms 10000 'proxy (proxy-at o 'https) 'proxy-ca-file other-ca)
                                   (lambda (s) (call-outcome (lambda () (http-get s url 'proxy-ca-file ca))))))))))

  (test-equal "a redirect's hops go through the call's proxy, another origin's too, the proxy URL's credentials on each: absolute form to the http face, then a CONNECT to the https face; the credentials key goes to the first origin alone, the second's echo holding no Authorization"
    (list '(answered 200 no-authorization)
          '("request http conn=1 method=GET target=http://127.0.0.1:<http>/redirect/302?to=https%3A%2F%2F127.0.0.1%3A<https>%2Fecho auth=basic:alice:s3cret"
            "connect http conn=2 target=127.0.0.1:<https> answer=200 head=_ auth=basic:alice:s3cret"
            "inner https via=2 method=GET target=/echo"
            "close http conn=1" "close http conn=2"))
    (let* ((to (pct-component (face-url o 'https "/echo")))
           (c (proxied
               (lambda ()
                 (in-session (list 'timeout-ms 10000 'proxy (proxy-at o 'http "alice:s3cret") 'ca-file ca
                                   'credentials '(basic "ouser" "opass"))
                             (lambda (s)
                               (guard (e (#t (list 'raised (describe e))))
                                 (let ((r (http-get s (face-url o 'http (string-append "/redirect/302?to=" to)))))
                                   (list 'answered (http-response-status r)
                                         (if (contains? (utf8->string (http-response-body r)) "Authorization")
                                             'authorization-reached-another-origin
                                             'no-authorization))))))))))
      ;; A port encoded as %3A then its digits is no :PORT: name it here.
      (list (car c)
            (map (lambda (line) (replace-all line (string-append "%3A" (port-of o 'https)) "%3A<https>")) (cadr c)))))

  (test-equal "a redirect's hop keeps the call's proxy-verify #f: through the https:// proxy on the expired leaf, which a verifying client refuses, its CA the run's, the first request and the hop's, to another origin, go by absolute form on its log, and the call answers 200; the hop verifying would fail 60 at the proxy"
    (list '(answered 200)
          '("request https-expired method=GET target=http://127.0.0.1:<http>/redirect/302?to=http%3A%2F%2Flocalhost%3A<http>%2Fstatus%2F200 auth=-"
            "request https-expired method=GET target=http://localhost:<http>/status/200 auth=-"))
    (let* ((to (pct-component (string-append "http://localhost:" (port-of o 'http) "/status/200")))
           (c (proxied
               (lambda ()
                 (in-session (list 'timeout-ms 10000 'proxy (proxy-at o 'https-expired) 'proxy-ca-file ca)
                             (lambda (s)
                               (call-outcome
                                (lambda ()
                                  (http-get s (face-url o 'http (string-append "/redirect/302?to=" to))
                                            'proxy-verify #f)))))))))
      ;; Whether the hop rides the first request's connection to the proxy
      ;; moves with the version: the requests alone, their connections'
      ;; numbers left out.
      (list (car c)
            (map (lambda (line)
                   (replace-all (replace-all (replace-all line (string-append "%3A" (port-of o 'http)) "%3A<http>")
                                             " conn=1 " " ")
                                " conn=2 " " "))
                 (filter (lambda (l) (not (close-line? l))) (cadr c))))))

  (begin
    (test-equal "a redirect's hop to https:// through an https:// proxy where TLS inside TLS stalls, by this lane's tls-in-tls-checks row, fails the call with the refusal, as its next request is submitted, one transfer counted; elsewhere it is followed; a lane with no row fails"
      (tls-in-tls-verdict '(raised proxy proxy proxy-tls-in-tls 1) '(answered 200))
      (in-session (list 'timeout-ms 10000 'proxy (proxy-at o 'https) 'proxy-ca-file ca 'ca-file ca)
                  (lambda (s)
                    (call-outcome
                     (lambda ()
                       (http-get s (face-url o 'http (string-append "/redirect/302?to=" (pct-component (face-url o 'https "/status/200")))))))))))

  (test-equal "a CONNECT refused 503 is retried as a 503 response would be: a post and a get, with statuses (503) and methods (get post), are tried three times, each CONNECT on the proxy's log; refused 407, once, on every libcurl, whatever the code and size, which move with the version"
    (list (list (list 'failed code-of-refusal 503 3) 3)
          (list (list 'failed code-of-refusal 407 1) 1)
          (list (list 'failed code-of-refusal 503 3) 3)
          (list (list 'failed code-of-refusal 407 1) 1))
    (let ((policy '(statuses (503) methods (get post))))
      (list (retried policy "https://refuse-503.invalid:443/" 'post)
            (retried policy "https://refuse-407.invalid:443/" 'post)
            (retried policy "https://refuse-503.invalid:443/" 'get)
            (retried policy "https://refuse-407.invalid:443/" 'get))))

  (let ((pair (by-version closing-retries "closing-retries" version
                          (lambda ()
                            (let* ((post (retried '(methods (get)) "https://close.invalid:443/" 'post))
                                   (get (retried '(methods (get)) "https://close.invalid:443/" 'get)))
                              (list post get))))))
    (test-equal "a CONNECT a proxy closes keeps the class rule, by version: a post outside the methods tried once on 7.85.0, whose size is the CONNECT's, and three times from 8.5.0; a get three times everywhere"
      (car pair)
      (cadr pair)))

  (for-each
   (lambda (case)
     (test-equal (string-append "in a child, " (car case) ": a named proxy still takes the transfer, NOPROXY \"\" reading no variable, its request on the proxy's log; the child saw the variables")
       (list (list (cons 'environment (environment-of (cadr case)))
                   '(check (checked))
                   (list 'transfer '(response 200 "status 200") zero-counts)
                   '(done))
             '("request http conn=1 method=GET target=http://127.0.0.1:<http>/status/200 auth=-" "close http conn=1"))
       (let ((c (proxied (lambda () (child (cadr case) (face-url o 'http "/status/200") (proxy-at o 'http) "-" "on" "-")))))
         (list (if (and (pair? (car c)) (pair? (cdar c))) (cons (caar c) (cddar c)) (car c)) (cadr c)))))
   no-proxy-cases)

  (test-equal "in a child, the control: proxy environment beside no_proxy naming the origin goes direct, the proxy getting nothing; beside http_proxy at a refused port, and no no_proxy, it goes there, refused, 7: so the variables arrived"
    (list (list (list 'transfer '(response 200 "status 200") zero-counts) '())
          (list (list 'transfer '(refused perform-failed 7 connect #f) zero-counts) '()))
    (map (lambda (assignments)
           (let ((c (proxied (lambda () (child assignments (face-url o 'http "/status/200") "environment" "-" "on" "-")))))
             (list (if (and (pair? (car c)) (> (length (car c)) 3)) (list-ref (car c) 3) (car c)) (cadr c))))
         '(("no_proxy=127.0.0.1" "http_proxy=http://127.0.0.1:1") ("http_proxy=http://127.0.0.1:1"))))

  (test-equal "in a child, SSL_CERT_FILE set as libcurl loads, beside a proxy CA file with the proxy's verification on: Guix's libcurl, which writes it over PROXY_CAINFO, is refused at check and submit, environment-override, field proxy-ca-file, naming the variable; elsewhere the variable changes nothing, the transfer through the https:// proxy on its log; the proxy's verification off, or no proxy CA file, is never refused"
    (list (if guix-libcurl?
              (list (list 'check (list 'request-refused 'proxy-ca-file ca 'environment-override '("SSL_CERT_FILE")))
                    (list 'transfer (list 'request-refused 'proxy-ca-file ca 'environment-override '("SSL_CERT_FILE"))
                          zero-counts))
              (list '(check (checked)) (list 'transfer '(response 200 "status 200") zero-counts)))
          (list '(check (checked)) (list 'transfer '(response 200 "status 200") zero-counts)))
    (map (lambda (verify)
           (let ((answer (child (list (string-append "SSL_CERT_FILE=" ca)) (face-url o 'http "/status/200")
                                (proxy-at o 'https) ca verify "-")))
             (if (and (pair? answer) (> (length answer) 3)) (list (list-ref answer 2) (list-ref answer 3)) answer)))
         '("on" "off")))

  ;; --- no exit prints the proxy's password ---

  (test-equal "no transfer's exit prints the proxy's password: a CONNECT refused 407 for it, a proxy whose port refuses, a proxy whose leaf fails, each condition with its error buffer, as write, display and display-condition print it; a response through the proxy; its token once done; a session holding it; a call's failure through it"
    '(no-secret no-secret no-secret no-secret no-secret no-secret no-secret)
    (let* ((with-secret (lambda (face) (proxy-at o face (string-append "alice:" secret))))
           (failure-text (lambda (url proxy . keys)
                           (on-own-engine
                            (lambda (e)
                              (let ((token (curl-submit e (apply make-curl-request url 'timeout-ms 10000 'proxy proxy keys))))
                                (awaited token)
                                (string-append (printed (curl-token-outcome token)) (printed token)))))))
           (verdict (lambda (text) (if (and (string? text) (not (contains? text secret))) 'no-secret (list 'printed text))))
           (a (failure-text (local-url o 'https "/") (with-secret 'http)))
           (b (failure-text (face-url o 'http "/") (string-append "http://alice:" secret "@127.0.0.1:1")))
           (c (failure-text (face-url o 'http "/") (with-secret 'https-expired) 'proxy-ca-file ca))
           (d (failure-text (face-url o 'http "/status/200") (with-secret 'http)))
           (e (guard (x (#t (list 'raised (describe x))))
                (let ((s (make-http-session 'proxy (with-secret 'http) 'timeout-ms 10000)))
                  (let ((text (printed s)))
                    (http-session-close s)
                    text))))
           (f (in-session (list 'proxy (with-secret 'http) 'timeout-ms 10000)
                          (lambda (s)
                            (guard (x (#t (printed x)))
                              (http-get s (local-url o 'https "/"))
                              "no-raise"))))
           (g (in-session (list 'proxy (with-secret 'http) 'timeout-ms 10000)
                          (lambda (s) (printed (http-get s (face-url o 'http "/status/200")))))))
      (map verdict (list a b c d e f g))))

  (stop-bounded log-engine)
  (test-equal "every engine the scenarios made has stopped: every count is zero"
    zero-counts
    (begin (wait-for (lambda () (equal? (native-counts) zero-counts)) 10000)
           (native-counts))))

;; --- the children's script, and the library path ---------------------------------------

;; library-path : -> String
;; This suite's library path, as --libdirs takes it.
(define (library-path)
  (let loop ((dirs (map car (library-directories))) (text ""))
    (cond ((null? dirs) text)
          ((string=? text "") (loop (cdr dirs) (car dirs)))
          (else (loop (cdr dirs) (string-append text ":" (car dirs)))))))

;; read-all : String -> (Listof Any)
;; TEXT read as data, each datum in turn; one that does not read ends the
;; list with (unreadable).
(define (read-all text)
  (let ((port (open-string-input-port text)))
    (let loop ((found '()))
      (let ((datum (guard (e (#t '(unreadable))) (read port))))
        (cond ((eof-object? datum) (reverse found))
              ((equal? datum '(unreadable)) (reverse (cons datum found)))
              (else (loop (cons datum found))))))))

;; child-script : String
;; sh -c CHILD-SCRIPT sh COMMAND...: COMMAND, with stdin at its end, under
;; GNU timeout (gtimeout on macOS), killed after 60 s, exit 137; with
;; neither found, exit 125, saying so. The shell's own stderr is /dev/null,
;; so dash's "Killed" is not the command's, as test-transfer-tls's child's.
(define child-script
  (string-append
   "t=$(command -v timeout || command -v gtimeout) || { echo 'proxy-env: no timeout' >&2; exit 125; }\n"
   "exec 3>&2 2>/dev/null\n"
   "( exec \"$t\" -s KILL 60 \"$@\" </dev/null 2>&3 3>&- )\n"
   "exit $?\n"))

;; The scenarios' tests run here, in a definition, and the verdict on their
;; origin after: SRFI-64 keeps one result per runner (traps.md).
(define scenarios-outcome
  (guard (e (#t (list 'raised (describe e))))
    (parameterize ((origin-pki pki))
      (call-with-origin (lambda (o) (scenarios o) 'done)))))

(test-equal "the scenarios' origin starts with the PKI, serves them all, and stops"
  'done
  scenarios-outcome)

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "proxy")

(exit (suite-exit-status runner))
