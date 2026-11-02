#!r6rs
;;; The suite for a request's server credentials (ADR-0036, amended twice;
;;; the M7 plan, sections 3.1, 3.3, 3.6, 3.7 and 5.2), at both levels,
;;; against the test origin's auth route on its http, https and h2 faces,
;;; and its raw face's 417 loop.
;;;
;;;   - the arithmetic this suite writes its expected headers with, (auth-
;;;     testing)'s MD5, SHA-256, base64 and Digest response, held to their
;;;     published vectors;
;;;   - the settings, as data: credentials-settings' answer written out
;;;     whole, for every scheme and #f, and its refusal of any other; the
;;;     field's four option names, and AWS_SIGV4, standing in transfer.sls
;;;     only as data;
;;;   - the key: its default, each scheme kept, curl-request-with, each
;;;     wrong shape an assertion violation; the copies, the caller's list
;;;     and strings and the accessor's answer each changed after;
;;;   - every refusal beside a neighbour that passes, with a sentinel of its
;;;     own for no raise: credentials-bytes on every control char in each
;;;     part of each scheme, and the chars beside them that pass; a colon;
;;;     credentials-empty; credentials-beside-authorization; digest-with-
;;;     stream; at construction, at curl-request-check and at a submit, on
;;;     the submit's own copies; credentials-beside-userinfo at submit
;;;     alone; and no refusal holding a credentials string;
;;;   - each scheme over each face, a get and a post, its requests at the
;;;     origin as whole lines, each Authorization header whole, computed
;;;     here for Digest, whose challenge has no qop and a nonce the query
;;;     names; a wrong password's 401, code 0; Digest's post to a server
;;;     that never challenges, sent twice; a streamed body, sized and
;;;     chunked, and a streamed response, under Basic and Bearer;
;;;   - MAXREDIRS 30, every transfer's: a caller's Expect: 100-continue
;;;     answered 417 for ever stops at 31 requests, 47, and so does a Digest
;;;     route that answers stale=true for ever; 47 is of no class, and a
;;;     call's retry does not repeat it;
;;;   - what varies by version, each a table keyed by version (ADR-0017's
;;;     rule), a missing row failing by name with what it measured: the
;;;     Digest algorithms; a UTF-8 Digest user name; what the empty-userinfo
;;;     URLs report and send beside credentials; a 1 MiB password's and
;;;     token's code;
;;;   - the high level: the key from a session, a call's replacing it, kept
;;;     on a hop within the origin, dropped on a hop to another port and to
;;;     another host; a hop to a URL holding userinfo refused; a refusal made
;;;     as a call's request is built.
;;;
;;; Every expected value is one the code under test cannot produce by
;;; failing: SRFI-64 makes #f of a raise in the actual expression, so none
;;; is #f.
(import (rnrs)
        (rnrs mutable-pairs)
        (rnrs mutable-strings)
        (srfi :64)
        (only (chezscheme) fork-thread make-mutex with-mutex sleep make-time current-time
              time-second time-nanosecond getenv parameterize display-condition)
        (curl-testing)
        (auth-testing)
        (curl)
        (http-client)
        (only (curl private transfer) credentials-settings transfers-started prepare-transfer
              start-transfer! free-transfer!)
        (only (curl private engine) call-with-engine-held)
        (only (http-client private exchange) make-exchange)
        (curl private counters))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; written : Any -> String
(define (written x) (call-with-string-output-port (lambda (p) (write x p))))

;; shown : Any -> String
;; X written, cut to 3000 characters.
(define (shown x)
  (let ((text (written x)))
    (if (> (string-length text) 3000)
        (string-append (substring text 0 3000) "...")
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

(test-begin "auth")

;; --- helpers --------------------------------------------------------------------------

(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0)))

;; one-engine-counts : (Listof (Pairof Symbol Natural))
;; The counts while one engine runs and no transfer is live.
(define one-engine-counts
  '((block . 1) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 1)))

;; The loaded libcurl's version, read here, on this thread, before any
;; engine's thread is forked.
(define version
  (guard (e (#t (list 'no-version (describe e))))
    (libcurl-info-version (loaded-libcurl))))

;; now-ms : -> Integer
(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

;; pause-ms : Natural -> Unit
(define (pause-ms ms)
  (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))

;; wait-for : (-> Any) Natural -> Any
;; THUNK's first true answer, read every 1 ms, or #f after MS ms.
(define (wait-for thunk ms)
  (let ((deadline (+ (now-ms) ms)))
    (let loop ()
      (or (thunk)
          (and (< (now-ms) deadline)
               (begin (pause-ms 1) (loop)))))))

;; make-list-of : Natural Any -> (Listof Any)
(define (make-list-of n x) (if (= n 0) '() (cons x (make-list-of (- n 1) x))))

;; iota-from : Natural Natural -> (Listof Natural)
;; FROM, FROM + 1, ... below TO.
(define (iota-from from to) (if (>= from to) '() (cons from (iota-from (+ from 1) to))))

;; latin-1 : Bytevector -> String
(define (latin-1 bytes)
  (list->string (map integer->char (bytevector->u8-list bytes))))

;; octets : String -> Bytevector
;; Each char, all below 256, as its byte.
(define (octets s) (u8-list->bytevector (map char->integer (string->list s))))

;; hex2 : Natural -> String
;; %XX for B, upper case.
(define (hex2 b)
  (string #\% (string-ref "0123456789ABCDEF" (div b 16)) (string-ref "0123456789ABCDEF" (mod b 16))))

;; pct : String -> String
;; S's UTF-8 bytes, each kept when it is a letter, a digit, -, ., _ or ~,
;; and otherwise %XX: a query value the origin decodes back to S's bytes.
(define (pct s)
  (apply string-append
         (map (lambda (b)
                (if (or (<= 48 b 57) (<= 65 b 90) (<= 97 b 122) (memv b '(45 46 95 126)))
                    (string (integer->char b))
                    (hex2 b)))
              (bytevector->u8-list (string->utf8 s)))))

;; pattern-bytes : Natural -> Bytevector
;; N bytes, byte i being i mod 251: the origin logs any other body as bad.
(define (pattern-bytes n)
  (let ((bv (make-bytevector n)))
    (let loop ((i 0))
      (when (< i n)
        (bytevector-u8-set! bv i (mod i 251))
        (loop (+ i 1))))
    bv))

;; letters : Natural -> String
;; N chars, char i a to z, i mod 26.
(define (letters n)
  (let ((s (make-string n)))
    (let loop ((i 0))
      (when (< i n)
        (string-set! s i (integer->char (+ 97 (mod i 26))))
        (loop (+ i 1))))
    s))

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

;; outcome-of : (U Response Condition 'hung) -> Outcome
;; A transfer's outcome: (response STATUS), (failed REASON CODE CLASS), or
;; (raised TEXT).
(define (outcome-of x)
  (cond ((curl-response? x) (list 'response (curl-response-status x)))
        ((curl-transfer-error? x)
         (list 'failed (curl-transfer-error-reason x) (curl-transfer-error-code x) (class-of x)))
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

;; check-of : String . Keys -> Any
;; checked's answer for curl-request-check of a request for URL with KEYS,
;; or the making's refusal.
(define (check-of url . keys)
  (checked (lambda () (curl-request-check (apply make-curl-request url keys)))))

;; The run's PKI, for the TLS faces.
(define pki-made
  (guard (e (#t (list 'raised (describe e))))
    (list 'made (make-test-pki))))
(define pki (and (eq? (car pki-made) 'made) (cadr pki-made)))
(define ca (and pki (string-append pki "/ca.pem")))

;; by-version : (Listof (Pairof String Any)) String (-> Any) -> (List Any Any)
;; A per-version test's expected and actual values, from ROWS for the
;; loaded libcurl's version and MEASURE's answer: the row's value and the
;; measurement; with no row, (a-row-for VERSION), which no measurement
;; gives, and (no-row-for VERSION measured M), so the failure names the
;; version and prints the row it lacks (ADR-0017; AGENTS.md's by-version
;; trap). TAG names the table, on stdout with the version and the
;; measurement, as evidence of what ran, and on the error port with the row
;; a libcurl with none would need.
(define (by-version rows tag measure)
  (let ((row (and (string? version) (assoc version rows)))
        (measured (measure)))
    (display (string-append "test-auth: " tag " on " (written version) " measured "
                            (written measured) "\n"))
    (unless row
      (display (string-append "test-auth: no row of " tag " for this libcurl; measured, it would be:\n")
               (current-error-port))
      (write (cons version measured) (current-error-port))
      (newline (current-error-port)))
    (if row
        (list (cdr row) measured)
        (list (list 'a-row-for version) (list 'no-row-for version 'measured measured)))))

;; --- hermetic --------------------------------------------------------------------------

(test-equal "hermetic: none of http_proxy, HTTP_PROXY, https_proxy, HTTPS_PROXY, all_proxy, ALL_PROXY, SSL_CERT_FILE and SSL_CERT_DIR is set"
  '()
  (filter (lambda (name) (getenv name))
          '("http_proxy" "HTTP_PROXY" "https_proxy" "HTTPS_PROXY" "all_proxy" "ALL_PROXY"
            "SSL_CERT_FILE" "SSL_CERT_DIR")))

(test-equal "the run's PKI is made"
  'made
  (car pki-made))

;; --- the suite's own arithmetic, (auth-testing) ------------------------------------------

;; RFC 1321, appendix A.5; FIPS 180-4's examples (NIST's "abc" and the
;; two-block message); RFC 4648, section 10.
(test-equal "md5-hex: RFC 1321's seven test vectors"
  '("d41d8cd98f00b204e9800998ecf8427e" "0cc175b9c0f1b6a831c399e269772661" "900150983cd24fb0d6963f7d28e17f72"
    "f96b697d7cb7938d525a2f31aaf161d0" "c3fcd3d76192e4007dfb496cca67e13b" "d174ab98d277d9f5a5611c2c9f419d9f"
    "57edf4a22be3c955ac49da2e2107b67a")
  (map (lambda (s) (md5-hex (string->utf8 s)))
       '("" "a" "abc" "message digest" "abcdefghijklmnopqrstuvwxyz"
         "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
         "12345678901234567890123456789012345678901234567890123456789012345678901234567890")))

(test-equal "sha256-hex: FIPS 180-4's examples, the empty message, abc and the two-block message"
  '("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
  (map (lambda (s) (sha256-hex (string->utf8 s)))
       '("" "abc" "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")))

(test-equal "base64-encode: RFC 4648's seven test vectors"
  '("" "Zg==" "Zm8=" "Zm9v" "Zm9vYg==" "Zm9vYmE=" "Zm9vYmFy")
  (map (lambda (s) (base64-encode (string->utf8 s))) '("" "f" "fo" "foo" "foob" "fooba" "foobar")))

(test-equal "digest-response: RFC 2617's MD5 example and RFC 7616's SHA-256 one, each with qop auth"
  '("6629fae49393a05397450978507c4ef1" "753927fa0e85d155564e2e272a28d1802ca10daf4496794697cf8db5856cb6c1")
  (list (digest-response 'md5 (string->utf8 "Mufasa") "testrealm@host.com" (string->utf8 "Circle Of Life")
                         "dcd98b7102dd2f0e8b11d0f600bfb0c093" "0a4f113b" "00000001" "auth" "GET"
                         "/dir/index.html")
        (digest-response 'sha-256 (string->utf8 "Mufasa") "http-auth@example.org"
                         (string->utf8 "Circle of Life") "7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v"
                         "f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ" "00000001" "auth" "GET"
                         "/dir/index.html")))

;; RFC 2069's form, H(HA1:nonce:HA2), written out: HA1 and HA2 by md5-hex,
;; which its vectors hold, the joining here.
(test-equal "digest-response with no qop is RFC 2069's: H(H(user:realm:password):nonce:H(method:uri))"
  (md5-hex (string->utf8 (string-append (md5-hex (string->utf8 "user:chez-curl-test:pass")) ":abc:"
                                        (md5-hex (string->utf8 "GET:/x")))))
  (digest-response 'md5 (string->utf8 "user") "chez-curl-test" (string->utf8 "pass") "abc" #f #f #f
                   "GET" "/x"))

;; --- the settings, as data ---------------------------------------------------------------

;; Written out whole: HTTPAUTH at CURLAUTH_BASIC 1, CURLAUTH_DIGEST 2 and
;; CURLAUTH_BEARER 64 (curl/curl.h; tests/test-constants.sps holds the
;; constants to the headers), then the strings.
(test-equal "credentials-settings, written out: #f sets nothing; basic HTTPAUTH 1, USERNAME and PASSWORD; digest HTTPAUTH 2, USERNAME and PASSWORD; bearer HTTPAUTH 64 and XOAUTH2_BEARER"
  '(() (("HTTPAUTH" . 1) ("USERNAME" . "u1") ("PASSWORD" . "p1"))
    (("HTTPAUTH" . 2) ("USERNAME" . "u2") ("PASSWORD" . "p2"))
    (("HTTPAUTH" . 64) ("XOAUTH2_BEARER" . "t3")))
  (map (lambda (c) (guard (e (#t (list 'raised (describe e)))) (credentials-settings c)))
       '(#f (basic "u1" "p1") (digest "u2" "p2") (bearer "t3"))))

(test-equal "credentials-settings refuses any other value, an assertion violation naming its scheme alone: basic alone, an unknown scheme, a wrong count each way, and a part that is no string"
  '((assertion credentials-settings (credentials)) (assertion credentials-settings (ntlm))
    (assertion credentials-settings (basic)) (assertion credentials-settings (bearer))
    (assertion credentials-settings (digest)))
  (map (lambda (c) (checked (lambda () (credentials-settings c))))
       (list 'basic '(ntlm "u" "p") '(basic "u") '(bearer "t" "x") '(digest "u" 1))))

(define transfer-source "src/curl/private/transfer.sls")

;; transfer-library : Any
;; transfer.sls read as one datum, its library form, or what went wrong.
(define transfer-library
  (guard (e (#t (list 'unreadable (describe e))))
    (call-with-port (open-file-input-port transfer-source (file-options) (buffer-mode block)
                                          (make-transcoder (utf-8-codec)))
      read)))

;; name-places : (Listof String) Any -> (Listof (List String Any Symbol))
;; Each of NAMES as a string in LIBRARY's body: the name, the top-level
;; definition holding it, and whether it stands inside a quote.
(define (name-places names library)
  (define (walk x where quoted?)
    (cond ((and (string? x) (member x names)) (list (list x where (if quoted? 'quoted 'code))))
          ((pair? x)
           (let ((quoted? (or quoted? (eq? (car x) 'quote))))
             (append (walk (car x) where quoted?) (walk (cdr x) where quoted?))))
          (else '())))
  (if (and (list? library) (> (length library) 4))
      (apply append
             (map (lambda (form)
                    (walk form (and (pair? form) (eq? (car form) 'define) (pair? (cdr form))
                                    (if (pair? (cadr form)) (car (cadr form)) (cadr form)))
                          #f))
                  (cddddr library)))
      (list 'no-library library)))

;; credentials-settings names its options through field-options, from
;; request-field-options: a literal there would pass the table above, so
;; the reading holds it.
(test-equal "the names HTTPAUTH, USERNAME, PASSWORD, XOAUTH2_BEARER and AWS_SIGV4 stand in transfer.sls only as quoted data: the first four in request-field-options, AWS_SIGV4, their twin, in owned-option-names"
  '(("HTTPAUTH" request-field-options quoted) ("USERNAME" request-field-options quoted)
    ("PASSWORD" request-field-options quoted) ("XOAUTH2_BEARER" request-field-options quoted)
    ("AWS_SIGV4" owned-option-names quoted))
  (name-places '("HTTPAUTH" "USERNAME" "PASSWORD" "XOAUTH2_BEARER" "AWS_SIGV4") transfer-library))

(test-equal "name-places, the reader: a name in quoted data, and the same name in code, each with the definition holding it"
  '(("HTTPAUTH" a quoted) ("HTTPAUTH" b code))
  (name-places '("HTTPAUTH")
               '(library (x) (export) (import) (define a '("HTTPAUTH")) (define (b) (f "HTTPAUTH")))))

;; --- the key -------------------------------------------------------------------------

(test-equal "credentials takes basic, digest and bearer, each kept as given, and #f, the default, none; curl-request-with replaces it, clears it with #f, and keeps it when not given"
  '(#f (basic "u" "p") (digest "u" "p") (bearer "t") #f (bearer "t") #f (digest "u" "p"))
  (guard (e (#t (list 'raised (describe e))))
    (let ((digest (make-curl-request nowhere 'credentials '(digest "u" "p"))))
      (list (curl-request-credentials (make-curl-request nowhere))
            (curl-request-credentials (make-curl-request nowhere 'credentials '(basic "u" "p")))
            (curl-request-credentials digest)
            (curl-request-credentials (make-curl-request nowhere 'credentials '(bearer "t")))
            (curl-request-credentials (make-curl-request nowhere 'credentials #f))
            (curl-request-credentials (curl-request-with digest 'credentials '(bearer "t")))
            (curl-request-credentials (curl-request-with digest 'credentials #f))
            (curl-request-credentials (curl-request-with digest 'timeout-ms 1000))))))

;; Each its own wrong shape, refused before anything else is made; the
;; irritant names the key alone, never what was given.
(test-equal "any other credentials is an assertion violation from make-curl-request, and from curl-request-with, its irritant the key's name alone: a scheme alone, as a symbol and a string; a wrong count each way; an improper list; a part that is no string, a symbol among them; an unknown scheme, a scheme in another case, and one as a string; and #t"
  (append (make-list-of 13 '(assertion make-curl-request (credentials)))
          '((assertion curl-request-with (credentials))))
  (append (map (lambda (c) (made (lambda () (make-curl-request nowhere 'credentials c))))
               (list 'basic "basic" '(basic "u") '(basic "u" "p" "x") '(bearer) '(bearer "a" "b")
                     (cons 'basic (cons "u" "p")) '(basic "u" 1) '(digest u p) '(ntlm "u" "p")
                     '(BASIC "u" "p") '("basic" "u" "p") #t))
          (list (made (lambda () (curl-request-with (make-curl-request nowhere) 'credentials '(bearer 1)))))))

(test-equal "a circular credentials list is refused, an assertion violation, never followed round"
  '(assertion make-curl-request (credentials))
  (made (lambda ()
          (let ((cycle (list 'basic "u" "p")))
            (set-cdr! (cddr cycle) cycle)
            (make-curl-request nowhere 'credentials cycle)))))

;; The record keeps a copy, checked, and the accessor answers a fresh copy
;; (decision 2): a change to the caller's list, its strings, or the
;; accessor's answer reaches no request.
(test-equal "the copies: the caller's list and strings changed after the request was made, and the accessor's answer changed, the request still answers (basic \"user\" \"pass\"), a fresh list each time"
  '((basic "user" "pass") (basic "user" "pass") (basic "user" "pass") fresh fresh)
  (guard (e (#t (list 'raised (describe e))))
    (let* ((user (string-copy "user"))
           (pass (string-copy "pass"))
           (given (list 'basic user pass))
           (r (make-curl-request nowhere 'credentials given)))
      (string-set! user 0 #\X)
      (string-set! pass 0 #\Y)
      (set-car! given 'bearer)
      (set-car! (cddr given) "other")
      (let* ((first (curl-request-credentials r))
             (answer (curl-request-credentials r)))
        (string-set! (cadr answer) 0 #\Z)
        (set-car! answer 'digest)
        (let ((third (curl-request-credentials r)))
          (list first (curl-request-credentials r) third
                (if (eq? first third) 'same 'fresh)
                (if (eq? (cadr first) (cadr third)) 'same 'fresh)))))))

;; --- the refusals ----------------------------------------------------------------------

;; part-credentials : Symbol Symbol String -> Credentials
;; SCHEME's credentials with TEXT as PART, the rest "user", "pass" or "tok".
(define (part-credentials scheme part text)
  (case scheme
    ((bearer) (list 'bearer text))
    (else (if (eq? part 'user) (list scheme text "pass") (list scheme "user" text)))))

;; The parts each scheme has.
(define parts '((basic user) (basic password) (digest user) (digest password) (bearer token)))

;; The test of every control char in every part: the expected refusal, or
;; the measured answer, for each, in order.
;; placed : Char Symbol -> String
;; C at PLACE in a part: first, before "ab"; middle, between a and b; last,
;; after "ab". A scan is tested at both its ends and inside, so one that
;; skips the first or the last char is seen.
(define (placed c place)
  (case place
    ((first) (string c #\a #\b))
    ((middle) (string #\a c #\b))
    (else (string #\a #\b c))))

;; refused-char? : Char Symbol Symbol -> Boolean
;; The rule, written here: a part is refused for C when C is U+0000 to
;; U+001F or U+007F, or C is a colon in a Basic user.
(define (refused-char? c scheme part)
  (let ((code (char->integer c)))
    (or (<= code #x1F) (= code #x7F)
        (and (char=? c #\:) (eq? scheme 'basic) (eq? part 'user)))))

;; tested-chars : (Listof Char)
;; Every char U+0000 to U+00FF, then U+0100, U+FFFD, U+10000 and U+10FFFF.
(define tested-chars
  (append (map integer->char (iota-from 0 256))
          (map integer->char '(#x100 #xFFFD #x10000 #x10FFFF))))

;; Every char, at every place, in every part of every scheme: the cases
;; whose answer is not the rule's, by the rule's own verdict, the refusal
;; whole or made; and how many cases ran, written out, 260 chars at three
;; places in five parts, so neither an empty run nor a narrowed one passes.
(test-equal "credentials-bytes: every char U+0000 to U+00FF, and U+0100, U+FFFD, U+10000 and U+10FFFF, at the first, a middle and the last index of each part of each scheme, a Basic and a Digest user and password and a Bearer token, is refused, field credentials, its value the scheme and the part, never the string, exactly when it is U+0000 to U+001F or U+007F, or a colon in a Basic user; every other is made"
  (list 3900 '())
  (let loop ((cases (apply append
                           (map (lambda (sp)
                                  (apply append
                                         (map (lambda (place) (map (lambda (c) (list sp place c)) tested-chars))
                                              '(first middle last))))
                                parts)))
             (n 0) (wrong '()))
    (if (null? cases)
        (list n (reverse wrong))
        (let* ((sp (car (car cases))) (place (cadr (car cases))) (c (caddr (car cases)))
               (want (if (refused-char? c (car sp) (cadr sp))
                         (list 'refused 'credentials sp 'credentials-bytes 'make-curl-request)
                         'made))
               (got (made (lambda ()
                            (make-curl-request nowhere 'credentials
                                               (part-credentials (car sp) (cadr sp) (placed c place)))))))
          (loop (cdr cases) (+ n 1)
                (if (equal? got want) wrong (cons (list sp place (char->integer c) got) wrong)))))))

(test-equal "placed and refused-char?, the readers: a char first, in the middle and last; the rule's verdict on NUL, US, SP, ~, DEL, U+0080 and a colon, in a Basic user and password and a Digest user"
  '("xab" "axb" "abx" #t #t #f #f #t #f #t #f #f)
  (list (placed #\x 'first) (placed #\x 'middle) (placed #\x 'last)
        (refused-char? (integer->char 0) 'bearer 'token) (refused-char? (integer->char #x1F) 'basic 'password)
        (refused-char? #\space 'basic 'user) (refused-char? #\~ 'digest 'user)
        (refused-char? (integer->char #x7F) 'digest 'password) (refused-char? (integer->char #x80) 'basic 'user)
        (refused-char? #\: 'basic 'user) (refused-char? #\: 'basic 'password) (refused-char? #\: 'digest 'user)))

(test-equal "a colon in a Basic user is refused, credentials-bytes (basic user), RFC 7617's end of the user; in a Basic password, a Digest user, a Digest password and a Bearer token, it passes"
  (list '(refused credentials (basic user) credentials-bytes make-curl-request) 'made 'made 'made 'made)
  (map (lambda (c) (made (lambda () (make-curl-request nowhere 'credentials c))))
       '((basic "us:er" "pass") (basic "user" "pa:ss") (digest "us:er" "pass") (digest "user" "pa:ss")
         (bearer "to:k"))))

(test-equal "credentials-empty: a Bearer token \"\", and a Basic or Digest user and password both \"\", refused, the value naming the token, or the user; one empty part beside the other passes, and so does a token of one char"
  (list '(refused credentials (bearer token) credentials-empty make-curl-request)
        '(refused credentials (basic user) credentials-empty make-curl-request)
        '(refused credentials (digest user) credentials-empty make-curl-request)
        'made 'made 'made 'made 'made)
  (map (lambda (c) (made (lambda () (make-curl-request nowhere 'credentials c))))
       '((bearer "") (basic "" "") (digest "" "") (basic "" "p") (basic "u" "") (digest "" "p")
         (digest "u" "") (bearer "t"))))

;; A to Z folded alone (traps.md): a header name is a token, so no char a
;; wider fold reaches stands in one, and the cases are what differ.
(test-equal "credentials-beside-authorization: credentials of each scheme beside a header named Authorization, in four ASCII cases, refused, value the scheme; beside Authorization-X and X-Authorization they pass, and so does an Authorization header with no credentials"
  (append (map (lambda (scheme) (list 'refused 'credentials scheme 'credentials-beside-authorization 'make-curl-request))
               '(basic digest bearer basic basic basic))
          '(made made made))
  (append (map (lambda (c h) (made (lambda () (make-curl-request nowhere 'credentials c 'headers (list (cons h "x"))))))
               '((basic "u" "p") (digest "u" "p") (bearer "t") (basic "u" "p") (basic "u" "p") (basic "u" "p"))
               '("Authorization" "Authorization" "Authorization" "authorization" "AUTHORIZATION" "aUtHoRiZaTiOn"))
          (list (made (lambda () (make-curl-request nowhere 'credentials '(basic "u" "p")
                                                    'headers '(("Authorization-X" . "x")))))
                (made (lambda () (make-curl-request nowhere 'credentials '(basic "u" "p")
                                                    'headers '(("X-Authorization" . "x")))))
                (made (lambda () (make-curl-request nowhere 'headers '(("Authorization" . "Bearer x"))))))))

(test-equal "credentials-beside-authorization finds the header first, in the middle and last among three headers, for each scheme, as the request is made"
  (apply append
         (map (lambda (scheme)
                (make-list-of 3 (list 'refused 'credentials scheme 'credentials-beside-authorization 'make-curl-request)))
              '(basic digest bearer)))
  (apply append
         (map (lambda (c)
                (map (lambda (headers) (made (lambda () (make-curl-request nowhere 'credentials c 'headers headers))))
                     (list '(("authorization" . "x") ("X-A" . "1") ("X-B" . "2"))
                           '(("X-A" . "1") ("Authorization" . "x") ("X-B" . "2"))
                           '(("X-A" . "1") ("X-B" . "2") ("AUTHORIZATION" . "x")))))
              '((basic "u" "p") (digest "u" "p") (bearer "t")))))

(test-equal "digest-with-stream: Digest beside a streamed body, sized and chunked, and beside a stream-buffer, refused, value digest; Basic and Bearer beside each pass, and so does Digest beside a whole body"
  (list '(refused credentials digest digest-with-stream make-curl-request)
        '(refused credentials digest digest-with-stream make-curl-request)
        '(refused credentials digest digest-with-stream make-curl-request)
        'made 'made 'made 'made 'made 'made 'made)
  (list (made (lambda () (make-curl-request nowhere 'method 'post 'body 'stream 'body-length 10
                                            'credentials '(digest "u" "p"))))
        (made (lambda () (make-curl-request nowhere 'method 'post 'body 'stream 'credentials '(digest "u" "p"))))
        (made (lambda () (make-curl-request nowhere 'stream-buffer 4096 'credentials '(digest "u" "p"))))
        (made (lambda () (make-curl-request nowhere 'method 'post 'body 'stream 'credentials '(basic "u" "p"))))
        (made (lambda () (make-curl-request nowhere 'method 'post 'body 'stream 'credentials '(bearer "t"))))
        (made (lambda () (make-curl-request nowhere 'stream-buffer 4096 'credentials '(basic "u" "p"))))
        (made (lambda () (make-curl-request nowhere 'stream-buffer 4096 'credentials '(bearer "t"))))
        (made (lambda () (make-curl-request nowhere 'method 'put 'body 'stream 'body-length 3
                                            'credentials '(bearer "t"))))
        (made (lambda () (make-curl-request nowhere 'method 'post 'body #vu8(1 2) 'credentials '(digest "u" "p"))))
        (made (lambda () (make-curl-request nowhere 'stream-buffer 4096)))))

(test-equal "the refusals however the two came together: curl-request-with adding credentials beside an Authorization header, an Authorization header beside credentials, a stream-buffer to a Digest request, and Digest to a streamed one, each as curl-request-with"
  '((refused credentials basic credentials-beside-authorization curl-request-with)
    (refused credentials bearer credentials-beside-authorization curl-request-with)
    (refused credentials digest digest-with-stream curl-request-with)
    (refused credentials digest digest-with-stream curl-request-with))
  (list (made (lambda () (curl-request-with (make-curl-request nowhere 'headers '(("Authorization" . "x")))
                                            'credentials '(basic "u" "p"))))
        (made (lambda () (curl-request-with (make-curl-request nowhere 'credentials '(bearer "t"))
                                            'headers '(("authorization" . "x")))))
        (made (lambda () (curl-request-with (make-curl-request nowhere 'credentials '(digest "u" "p"))
                                            'stream-buffer 10)))
        (made (lambda () (curl-request-with (make-curl-request nowhere 'method 'post 'body 'stream)
                                            'credentials '(digest "u" "p"))))))

;; The checks a request's shape makes run again at submit on the submit's
;; own copies (decision 4): a header name changed after the request was
;; made to Authorization is refused there.
(test-equal "credentials-beside-authorization is checked again at curl-request-check and at a submit, on their own copies: a header named Authorizatioz, changed to Authorization once the request was made, refused by each as its who, nothing started by the submit; the request as made checks clean"
  (list 'no-raise
        '(refused credentials basic credentials-beside-authorization curl-request-check)
        '(refused credentials basic credentials-beside-authorization curl-submit)
        0)
  (on-own-engine
   (lambda (e)
     (let* ((name (string-copy "Authorizatioz"))
            (r (make-curl-request nowhere 'headers (list (cons name "x")) 'credentials '(basic "u" "p")))
            (before (checked (lambda () (curl-request-check r)))))
       (string-set! name 12 #\n)
       (let* ((check (checked (lambda () (curl-request-check r))))
              (started (transfers-started))
              (submit (checked (lambda () (curl-submit e r)))))
         (list before check submit (- (transfers-started) started)))))))

;; Read from curl_url at submit alone, in request-checks, once the URL is
;; parsed: a request is made with any URL.
(test-equal "credentials-beside-userinfo: credentials of each scheme beside a URL holding a user and a password are made, and refused at curl-request-check and at a submit, value the scheme, nothing started; the URL's userinfo alone, and credentials with no userinfo, pass"
  (list 'made
        '(refused credentials basic credentials-beside-userinfo curl-request-check)
        '(refused credentials digest credentials-beside-userinfo curl-request-check)
        '(refused credentials bearer credentials-beside-userinfo curl-request-check)
        '(refused credentials basic credentials-beside-userinfo curl-submit)
        0 'no-raise 'no-raise)
  (on-own-engine
   (lambda (e)
     (let* ((with-userinfo "http://u:p@127.0.0.1:1/")
            (making (made (lambda () (make-curl-request with-userinfo 'credentials '(basic "u" "p")))))
            (checks (map (lambda (c) (check-of with-userinfo 'credentials c))
                         '((basic "u" "p") (digest "u" "p") (bearer "t"))))
            (started (transfers-started))
            (submit (checked (lambda () (curl-submit e (make-curl-request with-userinfo 'proxy #f
                                                                          'credentials '(basic "u" "p"))))))
            (after (- (transfers-started) started)))
       (append (list making) checks
               (list submit after (check-of with-userinfo)
                     (check-of nowhere 'credentials '(basic "u" "p"))))))))

(test-equal "the URL is refused first, its parse and its scheme, before its userinfo is read beside credentials: ftp:// with userinfo is scheme-not-http, and a port past 65535 bad-port-number"
  '((url-refused scheme-not-http) (url-refused bad-port-number))
  (list (check-of "ftp://u:p@127.0.0.1/" 'credentials '(basic "u" "p"))
        (check-of "http://u:p@127.0.0.1:99999/" 'credentials '(basic "u" "p"))))

;; secrets : (Listof String)
;; Each credentials string a refusal below is given, long enough that no
;; message holds one by chance.
(define secrets '("s3cretUser" "s3cretPass" "s3cretTok"))

;; holds-text? : String String -> Boolean
;; Whether TEXT holds PART at some index.
(define (holds-text? text part)
  (let ((n (string-length text)) (k (string-length part)))
    (let loop ((i 0))
      (and (<= (+ i k) n)
           (or (string=? (substring text i (+ i k)) part) (loop (+ i 1)))))))

;; secrets-in : String -> (Listof String)
;; Each of secrets TEXT holds, in secrets' order.
(define (secrets-in text)
  (filter (lambda (secret) (holds-text? text secret)) secrets))

;; reachable-strings : Any -> (Listof String)
;; Every string X holds, at any depth, through pairs and vectors, and
;; through a request its credentials, by curl-request-credentials: a
;; request is opaque, so its printed form shows none of them, but a caller
;; that catches a condition holding one can read them.
(define (reachable-strings x)
  (cond ((string? x) (list x))
        ((pair? x) (append (reachable-strings (car x)) (reachable-strings (cdr x))))
        ((vector? x) (reachable-strings (vector->list x)))
        ((curl-request? x) (reachable-strings (curl-request-credentials x)))
        (else '())))

;; quietly : (-> Any) -> Any
;; THUNK's answer, each warning it raises answered so it goes on: write
;; warns of a cycle a record's fields make, and goes on with print-graph.
(define (quietly thunk)
  (with-exception-handler (lambda (c) (if (warning? c) #f (raise-continuable c))) thunk))

;; condition-text : Condition -> String
;; C as display-condition prints it, whole, then its irritants written:
;; what a caller's handler or the REPL shows.
(define (condition-text c)
  (call-with-string-output-port
   (lambda (p)
     (quietly (lambda ()
                (display-condition c p)
                (newline p)
                (when (irritants-condition? c) (write (condition-irritants c) p)))))))

;; leaked : (-> Any) -> (U (List Symbol (Listof String)) Symbol)
;; What THUNK raised, by its kind, and each secret its printed text holds,
;; condition-text's, or a string reachable from its irritants or a
;; &curl-request-error's value holds; no-raise when it returned.
(define (leaked thunk)
  (guard (e ((condition? e)
             (list (cond ((curl-request-error? e) (curl-request-error-reason e))
                         ((assertion-violation? e) 'assertion)
                         (else 'other))
                   (secrets-in
                    (apply string-append (condition-text e) " "
                           (reachable-strings (list (if (irritants-condition? e) (condition-irritants e) '())
                                                    (if (curl-request-error? e) (curl-request-error-value e) '()))))))))
    (thunk)
    'no-raise))

;; A record of the suite's own, opaque to nothing: display-condition prints
;; its fields, as it printed a request's before requests were opaque.
(define-record-type holder (fields value))

(test-equal "no refusal holds a credentials string: each refusal and each wrong shape, given the secrets, holds none of them in its printed text, display-condition's and its irritants written, nor among the strings and requests its irritants and its value reach"
  '((credentials-bytes ()) (credentials-bytes ()) (credentials-bytes ()) (credentials-bytes ())
    (credentials-beside-authorization ()) (credentials-beside-authorization ())
    (digest-with-stream ()) (credentials-beside-userinfo ()) (credentials-beside-userinfo ())
    (assertion ()) (assertion ()) (assertion ()))
  (list (leaked (lambda () (make-curl-request nowhere 'credentials '(basic "s3cretUser\x1;" "s3cretPass"))))
        (leaked (lambda () (make-curl-request nowhere 'credentials '(basic "s3cret:User" "s3cretPass"))))
        (leaked (lambda () (make-curl-request nowhere 'credentials '(digest "s3cretUser" "s3cretPass\x7f;"))))
        (leaked (lambda () (make-curl-request nowhere 'credentials '(bearer "s3cretTok\r\n"))))
        (leaked (lambda () (make-curl-request nowhere 'credentials '(basic "s3cretUser" "s3cretPass")
                                              'headers '(("Authorization" . "x")))))
        (leaked (lambda () (make-curl-request nowhere 'credentials '(bearer "s3cretTok")
                                              'headers '(("authorization" . "x")))))
        (leaked (lambda () (make-curl-request nowhere 'stream-buffer 10
                                              'credentials '(digest "s3cretUser" "s3cretPass"))))
        (leaked (lambda () (curl-request-check (make-curl-request "http://s3cretUser:x@127.0.0.1:1/"
                                                                  'credentials '(basic "s3cretUser" "s3cretPass")))))
        (leaked (lambda () (curl-request-check (make-curl-request "http://a@127.0.0.1:1/"
                                                                  'credentials '(bearer "s3cretTok")))))
        (leaked (lambda () (make-curl-request nowhere 'credentials '(basic "s3cretUser" 1))))
        (leaked (lambda () (make-curl-request nowhere 'credentials '(ntlm "s3cretUser" "s3cretPass"))))
        (leaked (lambda () (make-curl-request nowhere 'credentials (list "s3cretTok"))))))

(test-equal "leaked, the reader: a secret in an irritant, deep in a list, is found; one inside a record of the suite's, by the printed text; one in a request's credentials, a request an irritant; one in the message, by display-condition's text; and a string that holds none is passed over"
  '((other ("s3cretPass")) (other ("s3cretUser")) (other ("s3cretTok")) (other ("s3cretPass")) (other ()))
  (list (leaked (lambda () (error 'w "m" (list 1 (vector "x s3cretPass y")))))
        (leaked (lambda () (error 'w "m" (make-holder (list "s3cretUser")))))
        (leaked (lambda () (error 'w "m" (list 'basic (make-curl-request nowhere 'credentials '(bearer "s3cretTok"))))))
        (leaked (lambda () (error 'w "a message holding s3cretPass")))
        (leaked (lambda () (error 'w "m" "s3cret")))))

;; --- what a printed request, plan, token or engine shows (the review of M7 slice 2) -------

;; printed : Any -> String
(define (printed x) (call-with-string-output-port (lambda (p) (quietly (lambda () (write x p))))))

;; rtd-of : Any -> Symbol
;; opened when record-rtd answers X's type, which could read and change
;; its fields; not-a-record when it refuses X, as for an opaque record.
(define (rtd-of x)
  (guard (e ((assertion-violation? e) 'not-a-record) (#t (list 'raised (describe e))))
    (record-rtd x)
    'opened))

;; Every record that holds a request, a plan, a token or credentials is
;; opaque: Chez prints a record's every field, so a printed token showed
;; its plan's password, and its engine's table another request's token.
(test-equal "a request with credentials, its plan, a live transfer made from it, its token queued on a held engine, that engine, a mailbox holding the done token, and a call's exchange holding the request each print as their type alone, holding no credentials string, and record-rtd opens none of them"
  (list '("#<curl-request>" "#<plan>" "#<live-transfer>" "#<curl-token>" "#<curl-engine>" "#<curl-mailbox>" "#<exchange>")
        '()
        (make-list-of 7 'not-a-record)
        zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (let* ((r (make-curl-request nowhere 'proxy #f 'timeout-ms 5000 'credentials '(basic "s3cretUser" "s3cretPass")))
           (plan (prepare-transfer r))
           (live (start-transfer! plan #f (vector 0) '()))
           (live-text (printed live))
           (live-rtd (rtd-of live))
           (freed (free-transfer! live))
           (e (make-curl-engine))
           (m (make-curl-mailbox))
           (held (call-with-engine-held e (lambda () (let ((t (curl-submit e r m))) (list t (printed t) (printed e))))))
           (t (car held))
           (done (curl-token-wait t 20000))
           (mailbox-text (printed m))
           (taken (curl-mailbox-take m 5000))
           (state (make-exchange 'get nowhere r #f 0 20 #f))
           (texts (list (printed r) (printed plan) live-text (cadr held) (caddr held) mailbox-text (printed state)))
           (rtds (list (rtd-of r) (rtd-of plan) live-rtd (rtd-of t) (rtd-of e) (rtd-of m) (rtd-of state)))
           (stopped (stop-bounded e)))
      (list texts (secrets-in (apply string-append texts)) rtds
            (begin (wait-for (lambda () (equal? (native-counts) zero-counts)) 10000) (native-counts))))))

;; token-text : (-> Any) -> (U (List String (Listof String)) Symbol)
;; What THUNK raised: its irritants written, and each secret its printed
;; text holds, condition-text's; no-raise when it returned.
(define (token-text thunk)
  (guard (e ((condition? e)
             (list (printed (if (irritants-condition? e) (condition-irritants e) '()))
                   (secrets-in (condition-text e)))))
    (thunk)
    'no-raise))

;; The token's own assertions hand the whole token as their irritant
;; (engine.sls), and so does the high level's group, for a token stepped
;; before it was done (drive.sls), which no call reaches: an assertion
;; with the token as its irritant stands for it.
(test-equal "the token's assertion violations, each with the token as its irritant, print it as its type alone and hold no credentials string: curl-token-next-piece of a whole body's token, curl-token-put-piece! of one that streams no body, a second curl-token-body-port of a streamed response's, and an assertion with the token as its irritant, as the high level's group raises one"
  (append (make-list-of 4 '("(#<curl-token>)" ())) (list zero-counts))
  (guard (e (#t (list 'raised (describe e))))
    (let* ((e (make-curl-engine))
           (whole (curl-submit e (make-curl-request nowhere 'proxy #f 'timeout-ms 5000
                                                    'credentials '(basic "s3cretUser" "s3cretPass"))))
           (streamed (curl-submit e (make-curl-request nowhere 'proxy #f 'timeout-ms 5000 'stream-buffer 4096
                                                       'credentials '(bearer "s3cretTok"))))
           (a (token-text (lambda () (curl-token-next-piece whole 10))))
           (b (token-text (lambda () (curl-token-put-piece! whole #vu8(1) 10))))
           (port (curl-token-body-port streamed))
           (c (token-text (lambda () (curl-token-body-port streamed))))
           (d (token-text (lambda () (assertion-violation 'drive-group "a token stepped before it was done" whole)))))
      (close-port port)
      (curl-token-wait whole 20000)
      (curl-token-wait streamed 20000)
      (stop-bounded e)
      (list a b c d (begin (wait-for (lambda () (equal? (native-counts) zero-counts)) 10000) (native-counts))))))

;; --- the origin's log, read whole --------------------------------------------------------

;; face-url : Origin Symbol String -> String
(define (face-url o face path)
  (let ((f (origin-face o face)))
    (string-append (if (memq face '(https h2 raw-tls)) "https://" "http://")
                   (car f) ":" (number->string (cdr f)) path)))

;; split-lines : String -> (Listof String)
;; TEXT's lines, each without its newline; an unterminated last one too.
(define (split-lines text)
  (let loop ((start 0) (i 0) (found '()))
    (cond ((= i (string-length text))
           (reverse (if (= start i) found (cons (substring text start i) found))))
          ((char=? (string-ref text i) #\newline)
           (loop (+ i 1) (+ i 1) (cons (substring text start i) found)))
          (else (loop start (+ i 1) found)))))

;; field-of : String String -> (U String #f)
;; The value after " NAME=" in LINE, up to the next space; #f with none.
(define (field-of line name)
  (let ((key (string-append " " name "=")))
    (let loop ((i 0))
      (cond ((> (+ i (string-length key)) (string-length line)) #f)
            ((string=? (substring line i (+ i (string-length key))) key)
             (let ((start (+ i (string-length key))))
               (let scan ((j start))
                 (if (or (= j (string-length line)) (char=? (string-ref line j) #\space))
                     (substring line start j)
                     (scan (+ j 1))))))
            (else (loop (+ i 1)))))))

;; with-field : String String String -> String
;; LINE with NAME's value, as field-of reads it, replaced by VALUE.
(define (with-field line name value)
  (let ((key (string-append " " name "=")))
    (let loop ((i 0))
      (cond ((> (+ i (string-length key)) (string-length line)) line)
            ((string=? (substring line i (+ i (string-length key))) key)
             (let* ((start (+ i (string-length key)))
                    (end (let scan ((j start))
                           (if (or (= j (string-length line)) (char=? (string-ref line j) #\space)) j
                               (scan (+ j 1))))))
               (string-append (substring line 0 start) value (substring line end (string-length line)))))
            (else (loop (+ i 1)))))))

;; lettered : (Listof String) -> (Listof String)
;; LINES, a log's request lines, each conn=C made conn=L, L a letter, A, B
;; ..., by the face and the number's first appearance: a connection's
;; number is its face's count since the origin started, which earlier
;; checks move.
(define (lettered lines)
  (let loop ((rest lines) (seen '()) (out '()))
    (if (null? rest)
        (reverse out)
        (let* ((line (car rest))
               (conn (field-of line "conn"))
               (id (cons (field-of line "face") conn))
               (hit (assoc id seen))
               (seen (if hit seen (append seen (list (cons id (string (integer->char (+ 65 (length seen))))))))))
          (loop (cdr rest) seen
                (cons (if conn (with-field line "conn" (cdr (assoc id seen))) line) out))))))

;; log-engine : (U Engine #f)
;; The engine the scenarios read the origin's logs through, made with them.
(define log-engine #f)

;; log-of : Origin String -> (U (Listof String) (List 'raised ...))
;; KEY's log at the origin, its lines whole, but each conn lettered.
(define (log-of o key)
  (guard (e (#t (list 'raised (describe e))))
    (let* ((t (curl-submit log-engine (make-curl-request (face-url o 'http (string-append "/auth-log?key=" key))
                                                         'proxy #f 'timeout-ms 20000)))
           (r (awaited t)))
      (if (and (curl-response? r) (= (curl-response-status r) 200))
          (let ((lines (split-lines (latin-1 (curl-response-body r)))))
            (cons (car lines) (lettered (cdr lines))))
          (list 'no-log (outcome-of r))))))

;; line : Natural Symbol String String Natural String Natural String -> String
;; Request N's line as the origin logs it, on FACE's connection CONN, a
;; letter.
(define (line n face conn method body verdict status authorization)
  (string-append "request " (number->string n) " face=" (symbol->string face) " conn=" conn
                 " method=" method " body=" (if (number? body) (number->string body) body)
                 " verdict=" verdict " status=" (number->string status) " authorization=" authorization))

;; without-conn : String -> String
;; LINE, a log's request line, with its conn field taken out.
(define (without-conn line)
  (let ((conn (field-of line "conn")))
    (if conn
        (let* ((key (string-append " conn=" conn))
               (at (let loop ((i 0))
                     (if (string=? (substring line i (+ i (string-length key))) key) i (loop (+ i 1))))))
          (string-append (substring line 0 at) (substring line (+ at (string-length key)) (string-length line))))
        line)))

;; log-head : String Natural -> String
(define (log-head key n) (string-append "log " key " " (number->string n)))

;; basic-header : String String -> String
(define (basic-header user pass)
  (string-append "Basic " (base64-encode (string->utf8 (string-append user ":" pass)))))

;; digest-header : Symbol String String String String String -> String
;; libcurl's Digest header for a challenge with no qop: HASH md5 or
;; sha-256, ALG its token, the account's USER and PASS, the NONCE named, the
;; request's METHOD and URI, in libcurl's order.
(define (digest-header hash alg user pass nonce method uri)
  (string-append "Digest username=\"" user "\", realm=\"chez-curl-test\", nonce=\"" nonce "\", uri=\"" uri
                 "\", response=\"" (digest-response hash (string->utf8 user) "chez-curl-test"
                                                    (string->utf8 pass) nonce #f #f #f method uri)
                 "\", opaque=\"opq5ccb\", algorithm=" alg))

;; fetched : Engine Request -> Outcome
;; REQUEST submitted on ENGINE and awaited: its outcome-of, or a submit's
;; refusal.
(define (fetched e request)
  (let ((submitted (guard (c ((curl-request-error? c) (refusal-of c))) (curl-submit e request))))
    (if (curl-token? submitted) (outcome-of (awaited submitted)) submitted)))

;; auth-request : Origin Symbol String . Keys -> Request
;; A request of PATH on FACE, direct, a 20 s timeout, the run's CA file,
;; and KEYS.
(define (auth-request o face path . keys)
  (apply make-curl-request (face-url o face path) 'proxy #f 'timeout-ms 20000 'ca-file ca keys))

;; cell : Origin Symbol String String . Keys -> (List Outcome Log)
;; A request of PATH, for KEY, on FACE, with KEYS, on an engine of its own:
;; its outcome, and KEY's log after.
(define (cell o face key path . keys)
  (let ((answer (on-own-engine (lambda (e) (fetched e (apply auth-request o face path keys))))))
    (list answer (log-of o key))))


;; --- the tables of what varies by version (the M7 plan, section 3.7) ------------------

;; digest-algorithms : (Listof (Pairof String (Listof Cell)))
;; Each Digest variant's outcome, by version: the final status, and each
;; request's verdict and status at the origin, for MD5, MD5-sess,
;; SHA-256, SHA-256-sess and SHA-512-256, with qop=auth, and the three
;; without -sess with no qop: SHA-512-256 verifies on 8.20.0 and 8.23.0
;; alone; 7.85.0 and 8.5.0 send SHA-256's response under
;; algorithm=SHA-512-256 (the slice's measurement, item 1, two runs on
;; each lane). 8.7.1's row is the Mac's auth probe's (research/m7/auth/
;; results/mac-8.7.1-{1,2}.log, D:alg, two runs): every variant 200.
(define digest-variants
  '(("MD5" "auth") ("MD5" "none") ("MD5-sess" "auth") ("SHA-256" "auth") ("SHA-256" "none")
    ("SHA-256-sess" "auth") ("SHA-512-256" "auth") ("SHA-512-256" "none")))
(define digest-ok '(200 ("none" 401) ("ok" 200)))
(define digest-512-bad '(401 ("none" 401) ("bad(response)" 401)))
(define digest-algorithms
  (list (cons "7.85.0" (append (make-list-of 6 digest-ok) (list digest-512-bad digest-512-bad)))
        (cons "8.5.0" (append (make-list-of 6 digest-ok) (list digest-512-bad digest-512-bad)))
        (cons "8.7.1" (make-list-of 8 digest-ok))
        (cons "8.20.0" (make-list-of 8 digest-ok))
        (cons "8.23.0" (make-list-of 8 digest-ok))))

;; verdicts : Log -> (List Any ...)
;; Each request line's verdict and status.
(define (verdicts log)
  (if (and (pair? log) (string? (car log)))
      (map (lambda (l) (list (field-of l "verdict") (string->number (or (field-of l "status") "-"))))
           (cdr log))
      (list 'no-log log)))

;; utf8-digest-user : (Listof (Pairof String Any))
;; A Digest user name üser, by the credentials key, sent as UTF-8, with
;; qop=auth: the final status, each request's verdict and status, and
;; the username parameter as the origin received it, escaped. 8.23.0
;; percent-encodes it and hashes the raw bytes, so the origin refuses it;
;; the rest send the bytes raw (the slice's measurement, bytes87, two
;; runs on each lane). No row for 8.7.1: the Mac's auth probe gave the
;; name in the URL's userinfo (D:utf8:MD5), not by USERNAME, the field's
;; path, and ADR-0036's Context has the two paths differ; the Mac's make
;; test measures the field's, and prints its row.
(define utf8-digest-user
  (let ((raw '(200 (("none" 401) ("ok" 200)) "\\xc3\\xbcser")))
    (list (cons "7.85.0" raw) (cons "8.5.0" raw) (cons "8.20.0" raw)
          (cons "8.23.0" '(401 (("none" 401) ("bad(username)" 401)) "%C3%BCser")))))

;; username-of : String -> (U String #f)
;; The username parameter's quoted value in a logged Digest header.
(define (username-of l)
  (let* ((key "username=\"")
         (at (let loop ((i 0))
               (cond ((> (+ i (string-length key)) (string-length l)) #f)
                     ((string=? (substring l i (+ i (string-length key))) key) (+ i (string-length key)))
                     (else (loop (+ i 1)))))))
    (and at (let scan ((j at))
              (cond ((= j (string-length l)) #f)
                    ((char=? (string-ref l j) #\") (substring l at j))
                    (else (scan (+ j 1))))))))

;; empty-userinfo : (Listof (Pairof String Any))
;; Each URL whose userinfo is present but empty, in part or whole, and its
;; neighbours, beside (basic "user" "pass"): the user and password parts
;; curl-url-part reports, as a submit reads them, and the outcome: the
;; refusal, credentials-beside-userinfo, of a URL with either part; or,
;; where neither is reported, the request the origin received. 7.85.0
;; reports neither part for http://@h/ and http://:@h/, which pass there,
;; and send the field's credentials, as every libcurl sent them beside a
;; URL's userinfo (the auth probe's C:curlu cases); it reports no user for
;; http://:p@h/, and no password for http://u:@h/, each refused by its
;; other part. 8.5.0, OpenSSL's and GnuTLS's alike, 8.20.0 and 8.23.0
;; report "" for an empty part beside an @, so all five are refused there.
;; Measured by this suite on M7 slice 2's build, two runs on each lane:
;; Docker ubuntu:24.04 for 7.85.0, both 8.5.0s and 8.23.0, the Guix
;; container for 8.20.0. No row for 8.7.1: the Mac's auth probe sent each
;; URL beside both options, but read no URL part of http://@h/ or
;; http://:@h/ (its make test prints the row).
(define empty-userinfo
  (let ((sent-alone '((response 200)
                      ("request 1 face=http conn=A method=GET body=0 verdict=ok status=200 authorization=Basic dXNlcjpwYXNz")))
        (refused '(refused credentials-beside-userinfo)))
    (list (cons "7.85.0" (list (list "@" #f #f sent-alone) (list ":@" #f #f sent-alone)
                               (list ":p@" #f "p" refused) (list "u@" "u" #f refused) (list "u:@" "u" #f refused)))
          (cons "8.5.0" (list (list "@" "" #f refused) (list ":@" "" "" refused) (list ":p@" "" "p" refused)
                              (list "u@" "u" #f refused) (list "u:@" "u" "" refused)))
          (cons "8.20.0" (list (list "@" "" #f refused) (list ":@" "" "" refused) (list ":p@" "" "p" refused)
                               (list "u@" "u" #f refused) (list "u:@" "u" "" refused)))
          (cons "8.23.0" (list (list "@" "" #f refused) (list ":@" "" "" refused) (list ":p@" "" "p" refused)
                               (list "u@" "u" #f refused) (list "u:@" "u" "" refused))))))

;; mib-credentials : (Listof (Pairof String Any))
;; A 1 MiB Basic password and Bearer token: the failure, before anything
;; is sent, by version: 27 on 7.85.0 and 8.5.0, of no class; 100,
;; too-large, on 8.20.0 and 8.23.0 (the slice's measurement, bytes96, two
;; runs on each lane). No row for 8.7.1, which no probe measured.
(define mib-credentials
  (let ((oom '(((failed perform-failed 27 none) 0) ((failed perform-failed 27 none) 0)))
        (large '(((failed perform-failed 100 too-large) 0) ((failed perform-failed 100 too-large) 0))))
    (list (cons "7.85.0" oom) (cons "8.5.0" oom) (cons "8.20.0" large) (cons "8.23.0" large))))

;; --- the scenarios, against the origin -------------------------------------------------

;; faces : (Listof Symbol)
;; The auth route's faces this suite drives: HTTP/1.1, over TLS, and h2.
(define auth-faces '(http https h2))

;; face-key : String Symbol -> String
(define (face-key stem face) (string-append stem "-" (symbol->string face)))

(define (scenarios o)
  (set! log-engine (make-curl-engine))
  (let* ((body (pattern-bytes 1024))
         (basic '(basic "user" "pass"))
         (bearer '(bearer "tok123")))

    ;; --- each scheme, each face, a get and a post ---

    (for-each
     (lambda (face)
       (let ((key-get (face-key "basic-get" face)) (key-post (face-key "basic-post" face))
             (key-bget (face-key "bearer-get" face)) (key-bpost (face-key "bearer-post" face)))
         (test-equal (string-append "Basic over " (symbol->string face) ", a get and a post: one request each, its Authorization Basic dXNlcjpwYXNz, the post's body whole, answered 200")
           (list (list '(response 200)
                       (list (log-head key-get 1)
                             (line 1 face "A" "GET" 0 "ok" 200 (basic-header "user" "pass"))))
                 (list '(response 200)
                       (list (log-head key-post 1)
                             (line 1 face "A" "POST" 1024 "ok" 200 (basic-header "user" "pass")))))
           (list (cell o face key-get (string-append "/auth?key=" key-get "&ch=basic") 'credentials basic)
                 (cell o face key-post (string-append "/auth?key=" key-post "&ch=basic") 'credentials basic
                       'method 'post 'body body)))
         (test-equal (string-append "Bearer over " (symbol->string face) ", a get and a post: one request each, its Authorization Bearer tok123, answered 200")
           (list (list '(response 200)
                       (list (log-head key-bget 1) (line 1 face "A" "GET" 0 "ok" 200 "Bearer tok123")))
                 (list '(response 200)
                       (list (log-head key-bpost 1) (line 1 face "A" "POST" 1024 "ok" 200 "Bearer tok123"))))
           (list (cell o face key-bget (string-append "/auth?key=" key-bget "&ch=bearer") 'credentials bearer)
                 (cell o face key-bpost (string-append "/auth?key=" key-bpost "&ch=bearer") 'credentials bearer
                       'method 'post 'body body)))
         ;; The challenge has no qop and the nonce the query names, so the
         ;; whole header is computed here; the probe is bare, a post's with
         ;; no body, and the round rides its connection.
         (let* ((key-dget (face-key "digest-get" face)) (key-dpost (face-key "digest-post" face))
                (path-get (string-append "/auth?key=" key-dget "&ch=digest&nonce=nget&qop=none"))
                (path-post (string-append "/auth?key=" key-dpost "&ch=digest&nonce=npost&qop=none")))
           (test-equal (string-append "Digest over " (symbol->string face) ", a get and a post: a bare request answered 401, then one more on its connection, its Authorization whole, the post's body on the second alone, answered 200")
             (list (list '(response 200)
                         (list (log-head key-dget 2)
                               (line 1 face "A" "GET" 0 "none" 401 "-")
                               (line 2 face "A" "GET" 0 "ok" 200
                                     (digest-header 'md5 "MD5" "user" "pass" "nget" "GET" path-get))))
                   (list '(response 200)
                         (list (log-head key-dpost 2)
                               (line 1 face "A" "POST" 0 "none" 401 "-")
                               (line 2 face "A" "POST" 1024 "ok" 200
                                     (digest-header 'md5 "MD5" "user" "pass" "npost" "POST" path-post)))))
             (list (cell o face key-dget path-get 'credentials '(digest "user" "pass"))
                   (cell o face key-dpost path-post 'credentials '(digest "user" "pass")
                         'method 'post 'body body))))))
     auth-faces)

    (let* ((key "digest-sha256")
           (path (string-append "/auth?key=" key "&ch=digest&alg=SHA-256&nonce=nsha&qop=none")))
      (test-equal "Digest by SHA-256 over http: the bare request, then its Authorization whole, algorithm=SHA-256, answered 200"
        (list '(response 200)
              (list (log-head key 2) (line 1 'http "A" "GET" 0 "none" 401 "-")
                    (line 2 'http "A" "GET" 0 "ok" 200
                          (digest-header 'sha-256 "SHA-256" "user" "pass" "nsha" "GET" path))))
        (cell o 'http key path 'credentials '(digest "user" "pass"))))

    ;; --- a wrong password, and Digest to a server that never challenges ---

    (let* ((kb "wrong-basic") (kt "wrong-bearer") (kd "wrong-digest")
           (pd (string-append "/auth?key=" kd "&ch=digest&nonce=nwrong&qop=none")))
      (test-equal "a wrong password or token ends with the server's 401, code 0, no failure: Basic and Bearer after one request, Digest after its bare one and one more, judged bad(response)"
        (list (list '(response 401)
                    (list (log-head kb 1) (line 1 'http "A" "GET" 0 "bad" 401 (basic-header "user" "wrong"))))
              (list '(response 401)
                    (list (log-head kt 1) (line 1 'http "A" "GET" 0 "bad" 401 "Bearer wrong")))
              (list '(response 401)
                    (list (log-head kd 2) (line 1 'http "A" "GET" 0 "none" 401 "-")
                          (line 2 'http "A" "GET" 0 "bad(response)" 401
                                (digest-header 'md5 "MD5" "user" "wrong" "nwrong" "GET" pd)))))
        (list (cell o 'http kb (string-append "/auth?key=" kb "&ch=basic") 'credentials '(basic "user" "wrong"))
              (cell o 'http kt (string-append "/auth?key=" kt "&ch=bearer") 'credentials '(bearer "wrong"))
              (cell o 'http kd pd 'credentials '(digest "user" "wrong")))))

    ;; ADR-0036, amended (schemes20): the bare probe goes with
    ;; Content-Length: 0, is answered 200, and the post goes again, its body
    ;; with it, answered 200. Documented, not refused.
    (let ((key "digest-open"))
      (test-equal "a Digest post to a server that never challenges is sent twice: the bare probe, no body, answered 200, then the post again with its body, answered 200; a get is one bare request"
        (list (list '(response 200)
                    (list (log-head key 2) (line 1 'http "A" "POST" 0 "none" 200 "-")
                          (line 2 'http "A" "POST" 1024 "none" 200 "-")))
              (list '(response 200)
                    (list (log-head "digest-open-get" 1) (line 1 'http "A" "GET" 0 "none" 200 "-"))))
        (list (cell o 'http key (string-append "/auth?key=" key "&ch=open") 'credentials '(digest "user" "pass")
                    'method 'post 'body body)
              (cell o 'http "digest-open-get" "/auth?key=digest-open-get&ch=open"
                    'credentials '(digest "user" "pass")))))

    ;; --- streams, under Basic and Bearer ---

    (let ((stream-cell
           (lambda (face key credentials length)
             (let ((answer
                    (on-own-engine
                     (lambda (e)
                       (let* ((t (curl-submit e (apply auth-request o face (string-append "/auth?key=" key "&ch="
                                                                                         (symbol->string (car credentials)))
                                                       'method 'post 'body 'stream 'credentials credentials
                                                       (if length (list 'body-length length) '()))))
                              (whole (pattern-bytes 262144))
                              (puts (let loop ((at 0) (found '()))
                                      (if (= at 262144)
                                          (reverse found)
                                          (let ((piece (make-bytevector 16384)))
                                            (bytevector-copy! whole at piece 0 16384)
                                            (loop (+ at 16384) (cons (curl-token-put-piece! t piece 10000) found)))))))
                         (curl-token-end-body! t)
                         (list (if (for-all (lambda (p) (eq? p #t)) puts) 'every-piece-taken puts)
                               (outcome-of (awaited t))))))))
               (list answer (log-of o key))))))
      (for-each
       (lambda (face)
         (test-equal (string-append "a streamed body under Basic and Bearer over " (symbol->string face) ", sized and chunked: one request, the 256 KiB body whole at the origin, answered 200")
           (list (list '(every-piece-taken (response 200))
                       (list (log-head (face-key "stream-basic-sized" face) 1)
                             (line 1 face "A" "POST" 262144 "ok" 200 (basic-header "user" "pass"))))
                 (list '(every-piece-taken (response 200))
                       (list (log-head (face-key "stream-basic-chunked" face) 1)
                             (line 1 face "A" "POST" 262144 "ok" 200 (basic-header "user" "pass"))))
                 (list '(every-piece-taken (response 200))
                       (list (log-head (face-key "stream-bearer-sized" face) 1)
                             (line 1 face "A" "POST" 262144 "ok" 200 "Bearer tok123")))
                 (list '(every-piece-taken (response 200))
                       (list (log-head (face-key "stream-bearer-chunked" face) 1)
                             (line 1 face "A" "POST" 262144 "ok" 200 "Bearer tok123"))))
           (list (stream-cell face (face-key "stream-basic-sized" face) basic 262144)
                 (stream-cell face (face-key "stream-basic-chunked" face) basic #f)
                 (stream-cell face (face-key "stream-bearer-sized" face) bearer 262144)
                 (stream-cell face (face-key "stream-bearer-chunked" face) bearer #f))))
       '(http h2)))

    (let ((response-cell
           (lambda (face key credentials)
             (let ((answer
                    (on-own-engine
                     (lambda (e)
                       (let* ((t (curl-submit e (auth-request o face (string-append "/auth?key=" key "&size=262144&ch="
                                                                                    (symbol->string (car credentials)))
                                                              'stream-buffer 4096 'credentials credentials)))
                              (head (and (curl-token-head-wait t 20000) (curl-token-head t)))
                              (bytes (let loop ((n 0))
                                       (let ((p (curl-token-next-piece t 20000)))
                                         (if (bytevector? p) (loop (+ n (bytevector-length p))) n)))))
                         (list (and head (curl-head-status head)) bytes (outcome-of (awaited t))))))))
               (list answer (log-of o key))))))
      (for-each
       (lambda (face)
         (test-equal (string-append "a streamed response under Basic and Bearer over " (symbol->string face) ": one request, the head 200, the 256 KiB body read whole through the token")
           (list (list (list 200 262144 '(response 200))
                       (list (log-head (face-key "response-basic" face) 1)
                             (line 1 face "A" "GET" 0 "ok" 200 (basic-header "user" "pass"))))
                 (list (list 200 262144 '(response 200))
                       (list (log-head (face-key "response-bearer" face) 1)
                             (line 1 face "A" "GET" 0 "ok" 200 "Bearer tok123"))))
           (list (response-cell face (face-key "response-basic" face) basic)
                 (response-cell face (face-key "response-bearer" face) bearer))))
       '(http h2)))

    ;; --- a live token's assertion (the review of M7 slice 2) ---

    ;; The raw face's stall-before-head never answers, so the token stays
    ;; live once its body has ended, where a put is an assertion violation.
    (test-equal "a put after curl-token-end-body! on a live streamed body's token, its credentials Basic, raises an assertion violation that prints the token as its type alone, holding no credentials string; the token cancelled after"
      (list '("(#<curl-token>)" ()) 'cancelled)
      (on-own-engine
       (lambda (e)
         (let* ((t (curl-submit e (make-curl-request (face-url o 'raw "/raw/stall-before-head") 'proxy #f
                                                     'timeout-ms 20000 'method 'post 'body 'stream
                                                     'credentials '(basic "s3cretUser" "s3cretPass"))))
                (ended (curl-token-end-body! t))
                (text (token-text (lambda () (curl-token-put-piece! t #vu8(1) 1000)))))
           (curl-token-cancel t)
           (curl-token-wait t 10000)
           (list text (let ((x (curl-token-outcome t)))
                        (if (curl-transfer-error? x) (curl-transfer-error-reason x) (list 'outcome x))))))))

    ;; --- the copies, live ---

    (let ((key "copies"))
      (test-equal "the copies, live: the caller's list and strings, and the accessor's answer, changed after the request was made, the origin receives the credentials as given"
        (list '(response 200)
              (list (log-head key 1) (line 1 'http "A" "GET" 0 "ok" 200 (basic-header "user" "pass"))))
        (on-own-engine
         (lambda (e)
           (let* ((user (string-copy "user"))
                  (pass (string-copy "pass"))
                  (given (list 'basic user pass))
                  (r (auth-request o 'http (string-append "/auth?key=" key "&ch=basic") 'credentials given)))
             (string-set! user 0 #\X)
             (string-set! pass 3 #\X)
             (set-car! given 'bearer)
             (let ((answer (curl-request-credentials r)))
               (string-set! (caddr answer) 0 #\X)
               (set-car! (cdr answer) "other"))
             (list (fetched e r) (log-of o key)))))))

    ;; --- MAXREDIRS 30, every transfer's (ADR-0036, decision 8) ---

    ;; The raw face's /raw/auth417 answers 417 to every request carrying
    ;; Expect: 100-continue, keeping the connection: libcurl resends each,
    ;; the caller's header with it, a follow MAXREDIRS counts. At 30 it
    ;; stops at 31 requests, 47, which is of no class; at 7.85.0's default,
    ;; -1, it would loop to the timeout (maxredirs1, maxredirs6). Natively
    ;; every resend rides the first connection; under the memory gate's
    ;; Valgrind, 8.20.0's moved to a new one now and then (5, 11 and 15
    ;; requests a connection, one run), so no line here names its
    ;; connection: the count and the code are the point.
    (let* ((key "expect417")
           (expected-lines (map (lambda (n) (without-conn (line n 'raw "A" "POST" "-" "ok" 417 (basic-header "user" "pass"))))
                                (iota-from 1 32)))
           (measured (cell o 'raw key (string-append "/raw/auth417?key=" key) 'method 'post 'body (pattern-bytes 65536)
                           'headers '(("Expect" . "100-continue")) 'credentials basic)))
      (test-equal "a Basic post with a caller's Expect: 100-continue, answered 417 for ever on a kept connection, stops at 31 requests, failing 47 of no class"
        (list '(failed perform-failed 47 none) (cons (log-head key 31) expected-lines))
        (list (car measured)
              (if (and (pair? (cadr measured)) (string? (car (cadr measured))))
                  (cons (car (cadr measured)) (map without-conn (cdr (cadr measured))))
                  (cadr measured)))))

    ;; Each stale answer's resend is a follow too (maxredirs4, maxredirs9):
    ;; the route names each stale nonce from the query's, so every header is
    ;; computed here.
    (let* ((key "stale")
           (path (string-append "/auth?key=" key "&ch=digest&stale=forever&nonce=st&qop=none"))
           (nonce-of (lambda (n) (if (= n 2) "st" (string-append "st-" (number->string (- n 2)))))))
      (test-equal "a Digest route that answers stale=true for ever stops at 31 requests, the bare one and 30 more, each with the last answer's nonce, failing 47 of no class"
        (list '(failed perform-failed 47 none)
              (cons (log-head key 31)
                    (cons (line 1 'http "A" "GET" 0 "none" 401 "-")
                          (map (lambda (n)
                                 (line n 'http "A" "GET" 0 "ok" 401
                                       (digest-header 'md5 "MD5" "user" "pass" (nonce-of n) "GET" path)))
                               (iota-from 2 32)))))
        (cell o 'http key path 'credentials '(digest "user" "pass"))))

    ;; --- what varies by version (the M7 plan, section 3.7) ---

    (let ((pair (by-version digest-algorithms "digest-algorithms"
                            (lambda ()
                              (map (lambda (v)
                                     (let* ((key (string-append "alg-" (car v) "-" (cadr v)))
                                            (c (cell o 'http key (string-append "/auth?key=" key "&ch=digest&alg=" (car v)
                                                                                 "&qop=" (cadr v))
                                                     'credentials '(digest "user" "pass"))))
                                       (cons (if (eq? (car (car c)) 'response) (cadr (car c)) (car c))
                                             (verdicts (cadr c)))))
                                   digest-variants)))))
      (test-equal (string-append "the Digest algorithms on " (written version) ", as its row says: MD5, MD5-sess, SHA-256 and SHA-256-sess everywhere, SHA-512-256 on 8.7.1, 8.20.0 and 8.23.0 alone; a libcurl with no row fails, naming its version and printing what it measured")
        (car pair)
        (cadr pair)))

    (let ((pair (by-version utf8-digest-user "utf8-digest-user"
                            (lambda ()
                              (let* ((key "utf8-user")
                                     (c (cell o 'http key (string-append "/auth?key=" key "&ch=digest&u=" (pct "\xFC;ser"))
                                              'credentials '(digest "\xFC;ser" "pass"))))
                                (list (if (eq? (car (car c)) 'response) (cadr (car c)) (car c))
                                      (verdicts (cadr c))
                                      (and (pair? (cadr c)) (= (length (cadr c)) 3)
                                           (username-of (caddr (cadr c))))))))))
      (test-equal (string-append "a UTF-8 Digest user name on " (written version) ", as its row says: sent raw and verified, but on 8.23.0, which percent-encodes it and hashes the raw bytes; a libcurl with no row fails, naming its version and printing what it measured")
        (car pair)
        (cadr pair)))

    (let* ((userinfos '("@" ":@" ":p@" "u@" "u:@"))
           (pair (by-version empty-userinfo "empty-userinfo"
                             (lambda ()
                               (map (lambda (userinfo)
                                      (let* ((f (origin-face o 'http))
                                             (key (string-append "userinfo-" (number->string (string-length userinfo))
                                                                 (if (char=? (string-ref userinfo 0) #\u) "u" "")))
                                             (url (string-append "http://" userinfo (car f) ":" (number->string (cdr f))
                                                                 "/auth?key=" key "&ch=basic"))
                                             (part (lambda (p) (guard (e (#t (list 'raised (describe e))))
                                                                 (curl-url-part url p))))
                                             (answer (on-own-engine
                                                      (lambda (e)
                                                        (fetched e (make-curl-request url 'proxy #f 'timeout-ms 20000
                                                                                      'credentials basic)))))
                                             (log (log-of o key)))
                                        (list userinfo (part 'user) (part 'password)
                                              (if (and (pair? answer) (eq? (car answer) 'refused))
                                                  (list 'refused (cadddr answer))
                                                  (list answer (if (pair? log) (cdr log) log))))))
                                    userinfos)))))
      (test-equal (string-append "the URLs with an empty userinfo, or part of one, beside credentials on " (written version) ", as its row says: a URL whose user or password part is reported is refused at submit, credentials-beside-userinfo; one with neither sends the field's credentials; a libcurl with no row fails, naming its version and printing what it measured")
        (car pair)
        (cadr pair)))

    (let ((pair (by-version mib-credentials "mib-credentials"
                            (lambda ()
                              (map (lambda (scheme c)
                                     (let* ((key (string-append "mib-" scheme))
                                            (answer (cell o 'http key (string-append "/auth?key=" key "&ch=" scheme)
                                                          'credentials c)))
                                       (list (car answer)
                                             (if (and (pair? (cadr answer)) (string? (car (cadr answer))))
                                                 (length (cdr (cadr answer)))
                                                 (cadr answer)))))
                                   '("basic" "bearer")
                                   (list (list 'basic "user" (letters 1048576)) (list 'bearer (letters 1048576))))))))
      (test-equal (string-append "a 1 MiB Basic password and Bearer token on " (written version) ", as its row says: refused by libcurl before anything is sent, 27 on 7.85.0 and 8.5.0, 100 on 8.20.0 and 8.23.0; a libcurl with no row fails, naming its version and printing what it measured")
        (car pair)
        (cadr pair)))

    ;; --- the high level ---

    (let ((in-session
           (lambda (keys proc)
             (guard (e (#t (list 'raised (describe e))))
               (apply call-with-http-session 'proxy #f 'timeout-ms 20000 'ca-file ca
                      (append keys (list proc))))))
          (call-outcome
           (lambda (thunk)
             (guard (e (#t (list 'raised
                                 (append (if (curl-request-error? e) (list (cons 'request-refused (cdr (refusal-of e)))) '())
                                         (if (curl-transfer-error? e)
                                             (list (list 'failed (curl-transfer-error-reason e)
                                                         (curl-transfer-error-code e) (class-of e)))
                                             '())
                                         (if (http-exchange? e)
                                             (list (list 'exchange (http-exchange-method e) (http-exchange-url e)
                                                         (map (lambda (h) (list (http-response-status h) (http-response-url h)))
                                                              (http-exchange-history e))
                                                         (http-exchange-transfers e)))
                                             '())
                                         (list (list 'http-error (http-error? e)))
                                         (if (or (curl-request-error? e) (curl-transfer-error? e) (http-exchange? e))
                                             '()
                                             (list (list 'other (describe e))))))))
               (let ((r (thunk)))
                 (list 'response (http-response-status r)
                       (map (lambda (h) (list (http-response-status h) (http-response-url h)))
                            (http-response-history r)))))))
          (auth-url (lambda (key ch) (face-url o 'http (string-append "/auth?key=" key "&ch=" ch)))))

      (test-equal "a session's credentials reach its call: Basic, sent on its one request, answered 200; a session with none sends none, 401"
        (list (list '(response 200 ()) (list (log-head "hl-session" 1) (line 1 'http "A" "GET" 0 "ok" 200 (basic-header "user" "pass"))))
              (list '(response 401 ()) (list (log-head "hl-none" 1) (line 1 'http "A" "GET" 0 "none" 401 "-"))))
        (list (list (in-session (list 'credentials basic)
                                (lambda (s) (call-outcome (lambda () (http-get s (auth-url "hl-session" "basic"))))))
                    (log-of o "hl-session"))
              (list (in-session '() (lambda (s) (call-outcome (lambda () (http-get s (auth-url "hl-none" "basic"))))))
                    (log-of o "hl-none"))))

      (test-equal "a call's credentials replace the session's: the right password over a session's wrong one, 200; Bearer over a session's Basic, 200; #f over a session's Basic sends none, 401"
        (list (list '(response 200 ()) (list (log-head "hl-replace" 1) (line 1 'http "A" "GET" 0 "ok" 200 (basic-header "user" "pass"))))
              (list '(response 200 ()) (list (log-head "hl-bearer" 1) (line 1 'http "A" "GET" 0 "ok" 200 "Bearer tok123")))
              (list '(response 401 ()) (list (log-head "hl-cleared" 1) (line 1 'http "A" "GET" 0 "none" 401 "-"))))
        (in-session '(credentials (basic "user" "wrong"))
                    (lambda (s)
                      (let* ((a (call-outcome (lambda () (http-get s (auth-url "hl-replace" "basic") 'credentials basic))))
                             (la (log-of o "hl-replace"))
                             (b (call-outcome (lambda () (http-get s (auth-url "hl-bearer" "bearer") 'credentials bearer))))
                             (lb (log-of o "hl-bearer"))
                             (c (call-outcome (lambda () (http-get s (auth-url "hl-cleared" "basic") 'credentials #f))))
                             (lc (log-of o "hl-cleared")))
                        (list (list a la) (list b lb) (list c lc))))))

      ;; A hop within the origin keeps the credentials; to another port, the
      ;; raw face's echo, and to another host, they are dropped, as an
      ;; Authorization header is. Each hop's own request is read: the auth
      ;; route's log line, or the raw echo's head whole.
      (let* ((http (origin-face o 'http))
             (raw (origin-face o 'raw))
             (port (number->string (cdr http)))
             (redirect (lambda (from target)
                         (string-append from "/redirect/302?to=" (pct target))))
             (here (string-append "http://127.0.0.1:" port))
             (local (string-append "http://localhost:" port))
             (raw-echo (face-url o 'raw "/raw/echo"))
             (raw-authority (string-append (car raw) ":" (number->string (cdr raw)))))
        (test-equal "credentials are kept on a hop within the origin, from a session and from a call: the hop's own request carries Basic, 200"
          (let ((start (redirect here "/auth?key=hl-kept&ch=basic")))
            (list (list (list 'response 200 (list (list 302 start)))
                        (list (log-head "hl-kept" 1) (line 1 'http "A" "GET" 0 "ok" 200 (basic-header "user" "pass"))))
                  (list (list 'response 200 (list (list 302 (redirect here "/auth?key=hl-kept-call&ch=bearer"))))
                        (list (log-head "hl-kept-call" 1) (line 1 'http "A" "GET" 0 "ok" 200 "Bearer tok123")))))
          (list (list (in-session (list 'credentials basic)
                                  (lambda (s) (call-outcome (lambda () (http-get s (redirect here "/auth?key=hl-kept&ch=basic"))))))
                      (log-of o "hl-kept"))
                (list (in-session '()
                                  (lambda (s) (call-outcome (lambda () (http-get s (redirect here "/auth?key=hl-kept-call&ch=bearer")
                                                                                 'credentials bearer)))))
                      (log-of o "hl-kept-call"))))

        (test-equal "credentials are dropped on a hop to another port, the raw face's echo, which reads no Authorization, from a session and from a call"
          (let ((echoed (string-append "GET /raw/echo HTTP/1.1\r\nHost: " raw-authority "\r\nAccept: */*\r\n\r\n")))
            (list (list 'response 200 (list (list 302 (redirect here raw-echo)))) echoed
                  (list 'response 200 (list (list 302 (redirect here raw-echo)))) echoed))
          (let ((echo-of (lambda (keys plist)
                           (in-session keys
                                       (lambda (s)
                                         (guard (e (#t (list (list 'raised (describe e)) #f)))
                                           (let ((r (apply http-get s (redirect here raw-echo) plist)))
                                             (list (list 'response (http-response-status r)
                                                         (map (lambda (h) (list (http-response-status h) (http-response-url h)))
                                                              (http-response-history r)))
                                                   (latin-1 (http-response-body r))))))))))
            (append (echo-of (list 'credentials basic) '())
                    (echo-of '() (list 'credentials basic)))))

        (test-equal "credentials are dropped on a hop to another host, 127.0.0.1 to localhost and localhost to 127.0.0.1: the hop's request carries none, 401"
          (list (list (list 'response 401 (list (list 302 (redirect here (string-append local "/auth?key=hl-to-local&ch=basic")))))
                      (list (log-head "hl-to-local" 1) (line 1 'http "A" "GET" 0 "none" 401 "-")))
                (list (list 'response 401 (list (list 302 (redirect local (string-append here "/auth?key=hl-to-ip&ch=basic")))))
                      (list (log-head "hl-to-ip" 1) (line 1 'http "A" "GET" 0 "none" 401 "-"))))
          (in-session (list 'credentials basic)
                      (lambda (s)
                        (let* ((a (call-outcome (lambda () (http-get s (redirect here (string-append local "/auth?key=hl-to-local&ch=basic"))))))
                               (la (log-of o "hl-to-local"))
                               (b (call-outcome (lambda () (http-get s (redirect local (string-append here "/auth?key=hl-to-ip&ch=basic"))))))
                               (lb (log-of o "hl-to-ip")))
                          (list (list a la) (list b lb))))))

        ;; A Location within the origin holding userinfo, beside credentials
        ;; kept: the hop's request is made, and its submit refuses it, as any
        ;; submit does (ADR-0036, amended). The call fails with that refusal,
        ;; compounded with its &http-exchange, the 302 in its history and one
        ;; transfer. Its neighbour, the same hop with no credentials, is
        ;; followed, and libcurl sends the URL's userinfo, u2:p2, by Basic.
        (let* ((target (string-append "http://u2:p2@127.0.0.1:" port "/auth?key=hl-userinfo&ch=basic"))
               (start (redirect here target)))
          (test-equal "a hop within the origin to a URL holding userinfo, beside credentials, fails the call with the low level's refusal, credentials-beside-userinfo, as curl-submit, compounded with its &http-exchange, the 302 in its history, one transfer, nothing sent there; with no credentials the hop is followed, the URL's userinfo sent by Basic"
            (list (list 'raised (list '(request-refused credentials basic credentials-beside-userinfo curl-submit)
                                      (list 'exchange 'get start (list (list 302 start)) 1)
                                      '(http-error #f)))
                  (list (log-head "hl-userinfo" 0))
                  (list 'response 401 (list (list 302 start)))
                  (list (log-head "hl-userinfo" 1) (line 1 'http "A" "GET" 0 "bad" 401 (basic-header "u2" "p2"))))
            (let* ((refused (in-session (list 'credentials basic) (lambda (s) (call-outcome (lambda () (http-get s start))))))
                   (log-refused (log-of o "hl-userinfo"))
                   (followed (in-session '() (lambda (s) (call-outcome (lambda () (http-get s start))))))
                   (log-followed (log-of o "hl-userinfo")))
              (list refused log-refused followed log-followed)))))

      ;; A refusal made as the call's request is built, from the merge of the
      ;; session's keys and the call's, reaches the caller as the low level
      ;; raised it, compounded with the call's &http-exchange, no transfer
      ;; made; a session's own, as make-http-session raises it.
      (test-equal "a refusal made as a call's request is built reaches the caller as the low level raised it, compounded with its &http-exchange, no transfer made: a session's credentials beside a call's Authorization header, a call's beside a session's, and a session's Digest beside call-with-response-port's stream; a session made with credentials beside its own Authorization header is refused as make-curl-request raised it"
        (let ((url (auth-url "hl-built" "basic")))
          (list (list 'raised (list '(request-refused credentials basic credentials-beside-authorization make-curl-request)
                                    (list 'exchange 'get url '() 0) '(http-error #f)))
                (list 'raised (list '(request-refused credentials bearer credentials-beside-authorization make-curl-request)
                                    (list 'exchange 'get url '() 0) '(http-error #f)))
                (list 'raised (list '(request-refused credentials digest digest-with-stream make-curl-request)
                                    (list 'exchange 'get url '() 0) '(http-error #f)))
                '(refused credentials basic credentials-beside-authorization make-curl-request)
                (list (log-head "hl-built" 0))))
        (let ((url (auth-url "hl-built" "basic")))
          (list (in-session (list 'credentials basic)
                            (lambda (s) (call-outcome (lambda () (http-get s url 'headers '(("Authorization" . "Bearer x")))))))
                (in-session '(headers (("Authorization" . "Bearer x")))
                            (lambda (s) (call-outcome (lambda () (http-get s url 'credentials bearer)))))
                (in-session '(credentials (digest "user" "pass"))
                            (lambda (s) (call-outcome (lambda () (call-with-response-port s 'get url (lambda (r p) r))))))
                (checked (lambda () (make-http-session 'credentials basic 'headers '(("Authorization" . "x")))))
                (log-of o "hl-built"))))

      ;; The merge's headers are checked whole, wherever Authorization
      ;; stands among them: a rule that read the first header alone would
      ;; pass two of each three.
      (let ((url (auth-url "hl-merge" "basic"))
            (three (list '(("authorization" . "x") ("X-A" . "1") ("X-B" . "2"))
                         '(("X-A" . "1") ("Authorization" . "x") ("X-B" . "2"))
                         '(("X-A" . "1") ("X-B" . "2") ("AUTHORIZATION" . "x")))))
        (test-equal "the high level's merge is checked whole: a session's three headers, Authorization first, in the middle and last, beside a call's credentials, and a session's credentials beside a call's three headers so, each refused as the call's request is built, as make-curl-request raised it, compounded with its &http-exchange, no transfer made"
          (make-list-of 6 (list 'raised (list '(request-refused credentials basic credentials-beside-authorization make-curl-request)
                                              (list 'exchange 'get url '() 0) '(http-error #f))))
          (append (map (lambda (h)
                         (in-session (list 'headers h)
                                     (lambda (s) (call-outcome (lambda () (http-get s url 'credentials basic))))))
                       three)
                  (map (lambda (h)
                         (in-session (list 'credentials basic)
                                     (lambda (s) (call-outcome (lambda () (http-get s url 'headers h))))))
                       three))))

      ;; 47 is of no class (ADR-0022): a retry repeats the connect,
      ;; send-receive and timeout classes alone, so a policy that retries a
      ;; post leaves it, and the call fails after one transfer.
      (test-equal "a call whose transfer fails 47, the 417 loop, under a retry policy for post, is not retried: it fails with 47 of no class after one transfer, 31 requests at the origin"
        (list (list 'raised (list '(failed perform-failed 47 none)
                                  (list 'exchange 'post (face-url o 'raw "/raw/auth417?key=hl-retry") '() 1)
                                  '(http-error #f)))
              31)
        (list (in-session (list 'credentials basic 'retry (make-http-retry 'methods '(post) 'backoff-ms 0))
                          (lambda (s)
                            (call-outcome (lambda () (http-post s (face-url o 'raw "/raw/auth417?key=hl-retry")
                                                                'body (pattern-bytes 65536)
                                                                'headers '(("Expect" . "100-continue")))))))
              (let ((log (log-of o "hl-retry"))) (if (pair? log) (length (cdr log)) log)))))

    (stop-bounded log-engine)
    (test-equal "every engine the scenarios made has stopped: every count is zero"
      zero-counts
      (begin (wait-for (lambda () (equal? (native-counts) zero-counts)) 10000)
             (native-counts)))))

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

(test-end "auth")

(exit (suite-exit-status runner))
