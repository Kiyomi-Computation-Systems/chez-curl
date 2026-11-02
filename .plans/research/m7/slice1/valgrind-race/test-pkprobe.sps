#!r6rs
;;; The suite for a request's HTTP version (ADR-0034; the M7 plan, sections
;;; 3.1, 3.2, 3.7 and 4.2), at both levels, against the test origin's four
;;; faces: http, HTTP/1.1; https, TLS with ALPN http/1.1 alone; h2c, HTTP/2
;;; by prior knowledge, plaintext; h2, TLS with ALPN h2 alone.
;;;
;;;   - the settings, as data: version-settings' answer written out whole,
;;;     for every value, and its refusal of any other; HTTP_VERSION standing
;;;     in transfer.sls only as request-field-options' data, and its twins,
;;;     SSL_ENABLE_ALPN and ALTSVC, only as owned-option-names';
;;;   - the refusal, prior-knowledge-over-https, beside its neighbours, at
;;;     curl-request-check and at a submit, with a sentinel of its own for
;;;     no raise: its field, value, reason and who; nothing queued and
;;;     nothing native left; a URL's own refusal first;
;;;   - each value over each face, each on an engine of its own, by the
;;;     slice's measurement (.plans/research/m7/slice1/): the whole outcome,
;;;     the status, the version and the echo's head, or the reason, code and
;;;     class. Every cell the measurement found alike on its five libcurls
;;;     is asserted on every lane. Prior knowledge to the HTTP/1.1 http face
;;;     fails by version: a row per libcurl, 8.7.1's from the Mac's C probe
;;;     (research/m7/http2/results/mac-8.7.1.log); a libcurl with no row
;;;     fails, naming its version, and prints what it measured;
;;;   - connection sharing, by the h2 and h2c faces' /connection, whose
;;;     body names the connection its stream came on: two submitted in one
;;;     batch, one submitted once the first's head is in, one once the
;;;     first has ended, each case on an engine of its own. No transfer sets
;;;     PIPEWAIT (ADR-0034, decision 3). The batch by prior knowledge over
;;;     h2c shares one connection on 7.85.0 alone: a row per libcurl, none
;;;     for 8.7.1, whose engine runs were never measured; the Mac's run
;;;     prints its row;
;;;   - the high level: the key from a session, a call's value replacing
;;;     it, carried across a redirect and read on the far side, the h2c
;;;     face, which answers HTTP/2 only by prior knowledge; and a redirect
;;;     from http:// to https:// by prior knowledge, which fails the call
;;;     with the low level's refusal, compounded with its &http-exchange.
;;;
;;; No test reads a timing: a reused connection's connect is 10 to 37 µs on
;;; 7.85.0, 0 elsewhere (the measurement). Every expected value is one the
;;; code under test cannot produce by failing: SRFI-64 makes #f of a raise
;;; in the actual expression, so none is #f.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) fork-thread make-mutex with-mutex sleep make-time current-time
              time-second time-nanosecond getenv parameterize)
        (curl-testing)
        (curl)
        (http-client)
        (only (curl private engine) call-with-engine-held)
        (only (curl private transfer) version-settings transfers-started)
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

(test-begin "pkprobe")

;; --- helpers --------------------------------------------------------------------------

(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0)))

;; one-engine-counts : (Listof (Pairof Symbol Natural))
;; The counts while one engine runs and no transfer is live: its multi
;; handle and its slot.
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

;; latin-1 : Bytevector -> String
(define (latin-1 bytes)
  (list->string (map integer->char (bytevector->u8-list bytes))))

;; hex2 : Natural -> String
;; %XX for B, upper case.
(define (hex2 b)
  (string #\% (string-ref "0123456789ABCDEF" (div b 16)) (string-ref "0123456789ABCDEF" (mod b 16))))

;; pct : String -> String
;; S, ASCII, each char kept when it is a letter, a digit, -, ., _ or ~, and
;; otherwise %XX: a query value the origin's faces decode back to S.
(define (pct s)
  (apply string-append
         (map (lambda (ch)
                (let ((b (char->integer ch)))
                  (if (or (<= 48 b 57) (<= 65 b 90) (<= 97 b 122) (memv b '(45 46 95 126)))
                      (string ch)
                      (hex2 b))))
              (string->list s))))

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
;; PROC's answer, given an engine made for it and stopped once it returns:
;; an engine of its own starts with an empty pool, so no other check's
;; connection reaches it; (raised TEXT) for a raise.
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

;; face-url : Origin Symbol String -> String
(define (face-url o face path)
  (let ((f (origin-face o face)))
    (string-append (if (memq face '(https h2)) "https://" "http://")
                   (car f) ":" (number->string (cdr f)) path)))

;; authority : Origin Symbol -> String
(define (authority o face)
  (let ((f (origin-face o face)))
    (string-append (car f) ":" (number->string (cdr f)))))

;; The run's PKI, for the TLS faces.
(define pki-made
  (guard (e (#t (list 'raised (describe e))))
    (list 'made (make-test-pki))))
(define pki (and (eq? (car pki-made) 'made) (cadr pki-made)))
(define ca (and pki (string-append pki "/ca.pem")))

;; version-request : Origin Symbol String (U Symbol #f) -> Request
;; A GET of PATH on FACE, direct, a 20 s timeout, the run's CA file, and
;; http-version VERSION.
(define (version-request o face path version)
  (make-curl-request (face-url o face path) 'proxy #f 'timeout-ms 20000 'ca-file ca
                     'http-version version))

;; echo-lines : Bytevector (U Symbol #f) -> (Listof String)
;; The head the origin's /echo read, from its body BYTES: each line before
;; the first empty one. Over HTTP/1.x the request line, then each header,
;; in the order sent; over HTTP/2 each pseudo-header and header, sorted, so
;; the order a libcurl version sends them in is no answer's.
(define (echo-lines bytes version)
  (let ((text (latin-1 bytes)))
    (let loop ((start 0) (i 0) (found '()))
      (cond ((= i (string-length text)) (list 'no-end-of-head text))
            ((char=? (string-ref text i) #\newline)
             (if (= i start)
                 (let ((lines (reverse found)))
                   (if (eq? version 'http/2) (list-sort string<? lines) lines))
                 (loop (+ i 1) (+ i 1) (cons (substring text start i) found))))
            (else (loop start (+ i 1) found))))))

;; h1-echo : Origin Symbol -> (Listof String)
;; What /echo on FACE reads of libcurl's GET over HTTP/1.1, exactly: the
;; request line, Host, Accept, and no Upgrade.
(define (h1-echo o face)
  (list "GET /echo HTTP/1.1" (string-append "Host: " (authority o face)) "Accept: */*"))

;; h2-echo : Origin Symbol -> (Listof String)
;; What /echo on FACE reads of libcurl's GET over HTTP/2, sorted: the four
;; pseudo-headers, the scheme the face's, and accept.
(define (h2-echo o face)
  (list (string-append ":authority: " (authority o face)) ":method: GET" ":path: /echo"
        (string-append ":scheme: " (if (eq? face 'h2) "https" "http")) "accept: */*"))

;; outcome-of : (U Response Condition 'hung) -> Outcome
;; A transfer's outcome, whole: (response STATUS VERSION ECHO), ECHO by
;; echo-lines; (failed REASON CODE CLASS) for a &curl-transfer-error;
;; (raised TEXT) for anything else.
(define (outcome-of x)
  (cond ((curl-response? x)
         (list 'response (curl-response-status x) (curl-response-http-version x)
               (echo-lines (curl-response-body x) (curl-response-http-version x))))
        ((curl-transfer-error? x)
         (list 'failed (curl-transfer-error-reason x) (curl-transfer-error-code x) (class-of x)))
        (else (list 'raised (if (condition? x) (describe x) x)))))

;; refusal-of : Condition -> (List 'refused Symbol Any Symbol (U Symbol #f))
;; A &curl-request-error's field, value, reason and who.
(define (refusal-of e)
  (list 'refused (curl-request-error-field e) (curl-request-error-value e)
        (curl-request-error-reason e) (and (who-condition? e) (condition-who e))))

;; cell : Origin Symbol (U Symbol #f) -> Outcome
;; VERSION over FACE's /echo, on an engine of its own: the submit's
;; refusal, by refusal-of, or the transfer's outcome, by outcome-of.
(define (cell o face version)
  (on-own-engine
   (lambda (e)
     (let ((submitted (guard (c ((curl-request-error? c) (refusal-of c)))
                        (curl-submit e (version-request o face "/echo" version)))))
       (if (curl-token? submitted) (outcome-of (awaited submitted)) submitted)))))

;; refused-prior-knowledge : Symbol -> Outcome
;; What a check or a submit as WHO raises for prior knowledge over https.
(define (refused-prior-knowledge who)
  (list 'refused 'http-version 'http/2-prior-knowledge 'prior-knowledge-over-https who))

;; --- hermetic --------------------------------------------------------------------------

(test-equal "hermetic: none of http_proxy, HTTP_PROXY, https_proxy, HTTPS_PROXY, all_proxy, ALL_PROXY, SSL_CERT_FILE and SSL_CERT_DIR is set"
  '()
  (filter (lambda (name) (getenv name))
          '("http_proxy" "HTTP_PROXY" "https_proxy" "HTTPS_PROXY" "all_proxy" "ALL_PROXY"
            "SSL_CERT_FILE" "SSL_CERT_DIR")))

(test-equal "the run's PKI is made"
  'made
  (car pki-made))

;; --- the settings, as data -------------------------------------------------------------

;; Written out whole: HTTP_VERSION at CURL_HTTP_VERSION_1_1, 2; 2TLS, 4; and
;; 2_PRIOR_KNOWLEDGE, 5 (curl/curl.h; tests/test-constants.sps holds the
;; constants to the headers). http/2 is 2TLS, never 2_0's 3, which sends
;; Upgrade: h2c over http:// (the M7 plan, section 3.1).
(test-equal "version-settings, written out: #f sets nothing; http/1.1 HTTP_VERSION at 2, 1_1; http/2 at 4, 2TLS; http/2-prior-knowledge at 5, 2_PRIOR_KNOWLEDGE"
  '(() (("HTTP_VERSION" . 2)) (("HTTP_VERSION" . 4)) (("HTTP_VERSION" . 5)))
  (map (lambda (v) (guard (e (#t (list 'raised (describe e)))) (version-settings v)))
       '(#f http/1.1 http/2 http/2-prior-knowledge)))

(test-equal "version-settings refuses any other value, an assertion violation: http/1.0, http/3, http/2.0, \"http/2\" and 2"
  (make-list-of 5 '(assertion-violation version-settings))
  (map (lambda (v)
         (guard (e ((and (assertion-violation? e) (who-condition? e))
                    (list 'assertion-violation (condition-who e)))
                   (#t (list 'raised (describe e))))
           (version-settings v)
           'no-raise))
       (list 'http/1.0 'http/3 'http/2.0 "http/2" 2)))

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

;; version-option-names : (Listof String)
(define version-option-names '("HTTP_VERSION" "SSL_ENABLE_ALPN" "ALTSVC"))

;; version-settings names its option through field-option, from
;; request-field-options, as tls-settings does: a literal there would pass
;; the table above, so the reading holds it.
(test-equal "the names HTTP_VERSION, SSL_ENABLE_ALPN and ALTSVC stand in transfer.sls only as quoted data: HTTP_VERSION in request-field-options, its twins SSL_ENABLE_ALPN and ALTSVC in owned-option-names"
  '(("HTTP_VERSION" request-field-options quoted) ("SSL_ENABLE_ALPN" owned-option-names quoted)
    ("ALTSVC" owned-option-names quoted))
  (guard (e (#t (list 'unreadable (describe e))))
    (name-places version-option-names transfer-library)))

(test-equal "name-places, the reader: a name in quoted data, and the same name in code, each with the definition holding it"
  '(("ALTSVC" a quoted) ("ALTSVC" b code))
  (name-places version-option-names
               '(library (x) (export) (import) (define a '("ALTSVC")) (define (b) (f "ALTSVC")))))

;; --- the refusal, prior-knowledge-over-https -------------------------------------------

;; checked : (-> Any) -> Any
;; What THUNK raised, by refusal-of for a &curl-request-error, (url-refused
;; REASON) for a &curl-url-error, (raised TEXT) for anything else; or
;; no-raise, a sentinel no refusal is, when it returned.
(define (checked thunk)
  (guard (e ((curl-request-error? e) (refusal-of e))
            ((curl-url-error? e) (list 'url-refused (curl-url-error-reason e)))
            (#t (list 'raised (describe e))))
    (thunk)
    'no-raise))

;; check-of : String (U Symbol #f) -> Any
;; checked's answer for curl-request-check of a request for URL with
;; http-version VERSION.
(define (check-of url version)
  (checked (lambda () (curl-request-check (make-curl-request url 'http-version version)))))

(test-equal "curl-request-check refuses http/2-prior-knowledge with an https URL, an upper-case HTTPS among them, as prior-knowledge-over-https, field http-version, value http/2-prior-knowledge; its neighbours pass: http/2, http/1.1 and #f over https, and prior knowledge over http"
  (list (refused-prior-knowledge 'curl-request-check) (refused-prior-knowledge 'curl-request-check)
        'no-raise 'no-raise 'no-raise 'no-raise 'no-raise)
  (list (check-of "https://127.0.0.1:1/" 'http/2-prior-knowledge)
        (check-of "HTTPS://127.0.0.1:1/" 'http/2-prior-knowledge)
        (check-of "https://127.0.0.1:1/" 'http/2)
        (check-of "https://127.0.0.1:1/" 'http/1.1)
        (check-of "https://127.0.0.1:1/" #f)
        (check-of "http://127.0.0.1:1/" 'http/2-prior-knowledge)
        (check-of "HTTP://127.0.0.1:1/" 'http/2-prior-knowledge)))

(test-equal "the URL is refused first, its parse and its scheme, before prior knowledge is checked against the scheme: a port past 65535 is bad-port-number, and ftp:// scheme-not-http"
  '((url-refused bad-port-number) (url-refused scheme-not-http))
  (list (check-of "https://127.0.0.1:99999/" 'http/2-prior-knowledge)
        (check-of "ftp://127.0.0.1/" 'http/2-prior-knowledge)))

(test-equal "the request is made, an https URL with prior knowledge too, and checked at submit as it is then: prior knowledge given by curl-request-with to an https request is refused, and http/2 given to one with prior knowledge passes"
  (list 'made (refused-prior-knowledge 'curl-request-check) 'no-raise 'made
        (refused-prior-knowledge 'curl-request-check))
  (let* ((with-pk (guard (e (#t (list 'raised (describe e))))
                    (make-curl-request "https://127.0.0.1:1/" 'http-version 'http/2-prior-knowledge)))
         (given-pk (guard (e (#t (list 'raised (describe e))))
                     (curl-request-with (make-curl-request "https://127.0.0.1:1/" 'http-version 'http/2)
                                        'http-version 'http/2-prior-knowledge))))
    (list (if (curl-request? with-pk) 'made with-pk)
          (checked (lambda () (curl-request-check with-pk)))
          (checked (lambda () (curl-request-check (curl-request-with with-pk 'http-version 'http/2))))
          (if (curl-request? given-pk) 'made given-pk)
          (checked (lambda () (curl-request-check given-pk))))))

;; The submit refuses on the caller's thread, before anything is queued: the
;; engine starts no transfer, and its counts are its own.
(test-equal "curl-submit refuses http/2-prior-knowledge with an https URL as curl-submit, on the caller's thread: no transfer started, the engine's counts its own; its neighbour, http/2 over https, is submitted"
  (list (refused-prior-knowledge 'curl-submit) 0 one-engine-counts 'token)
  (on-own-engine
   (lambda (e)
     (let* ((started (transfers-started))
            (refused (checked (lambda ()
                                (curl-submit e (make-curl-request "https://127.0.0.1:1/" 'proxy #f
                                                                  'http-version 'http/2-prior-knowledge)))))
            (after (- (transfers-started) started))
            (counts (native-counts))
            (neighbour (guard (c (#t (list 'raised (describe c))))
                         (let ((t (curl-submit e (make-curl-request "https://127.0.0.1:1/" 'proxy #f
                                                                    'timeout-ms 5000 'http-version 'http/2))))
                           (awaited t)
                           'token))))
       (list refused after counts neighbour)))))

;; --- each value over each face ----------------------------------------------------------

;; prior-knowledge-to-h1 : (Listof (Pairof String Outcome))
;; What prior knowledge to the http face, HTTP/1.1, answers, by version
;; (the M7 plan, section 3.7): libcurl sends its preface and request, then
;; fails as the server answers HTTP/1.1. 7.85.0 reads an empty reply, 52;
;; 8.5.0, OpenSSL's and GnuTLS's alike, 56; 8.20.0 and 8.23.0 16, a framing
;; error (the slice's measurement, two runs each, every lane alike in
;; both); Apple's 8.7.1 16 (its C probe, research/m7/http2/results/
;; mac-8.7.1.log). 52 and 56 are send-receive, 16 protocol.
(define prior-knowledge-to-h1
  '(("7.85.0" . (failed perform-failed 52 send-receive))
    ("8.5.0" . (failed perform-failed 56 send-receive))
    ("8.7.1" . (failed perform-failed 16 protocol))
    ("8.20.0" . (failed perform-failed 16 protocol))
    ("8.23.0" . (failed perform-failed 16 protocol))))

;; together-by-prior-knowledge : (Listof (Pairof String Natural))
;; How many connections two requests submitted in one batch, by prior
;; knowledge to the h2c face, use, by version: one on 7.85.0, which finds
;; the first's connection multiplexable inside the turn that set both up;
;; two on 8.5.0 ("Server doesn't support multiplex (yet)"), 8.20.0 and
;; 8.23.0 ("Connection #0 is not open enough"), in every rep of the
;; slice's two runs. 8.7.1 has none: its engine does not multiplex (ADR-0030,
;; amended), and no run of it was measured; the Mac's run prints its row.
(define together-by-prior-knowledge
  '(("7.85.0" . 1) ("8.5.0" . 2) ("8.20.0" . 2) ("8.23.0" . 2)))

;; by-version : (Listof (Pairof String Any)) String (-> Any) -> (List Any Any)
;; A per-version test's expected and actual values, from ROWS for the
;; loaded libcurl's version and MEASURE's answer: the row's value and the
;; measurement; with no row, (a-row-for VERSION), which no measurement
;; gives, and (no-row-for VERSION measured M), so the failure names the
;; version and prints the row it lacks (ADR-0017; AGENTS.md's by-version
;; trap). TAG names the table on the error port, and on stdout, with the
;; version and the measurement, as evidence of what ran.
(define (by-version rows tag measure)
  (let ((row (and (string? version) (assoc version rows)))
        (measured (measure)))
    (display (string-append "test-version: " tag " on " (written version) " measured "
                            (written measured) "\n"))
    (unless row
      (display (string-append "test-version: no row of " tag " for this libcurl; measured, it would be:\n")
               (current-error-port))
      (write (cons version measured) (current-error-port))
      (newline (current-error-port)))
    (if row
        (list (cdr row) measured)
        (list (list 'a-row-for version) (list 'no-row-for version 'measured measured)))))

;; connection-k : Bytevector -> (U Natural #f)
;; K of a /connection body, "connection K\n".
(define (connection-k bytes)
  (let ((s (latin-1 bytes)))
    (and (> (string-length s) 12) (string=? (substring s 0 11) "connection ")
         (char=? (string-ref s (- (string-length s) 1)) #\newline)
         (string->number (substring s 11 (- (string-length s) 1))))))

;; connections-used : (Listof (U Natural #f)) -> (U Natural (List 'unread ...))
;; How many connections the Ks name, each once.
(define (connections-used ks)
  (if (for-all (lambda (k) (and (integer? k) (exact? k))) ks)
      (length (fold-left (lambda (seen k) (if (memv k seen) seen (cons k seen))) '() ks))
      (cons 'unread ks)))

;; response-k : (U Response Condition 'hung) -> (U Natural (List Any))
(define (response-k x)
  (if (and (curl-response? x) (curl-response-body x))
      (or (connection-k (curl-response-body x)) (list 'no-k (latin-1 (curl-response-body x))))
      (list 'no-response (outcome-of x))))

;; version-of : (U Response Condition 'hung) -> Any
(define (version-of x)
  (if (curl-response? x) (curl-response-http-version x) (list 'no-response (outcome-of x))))

;; share-together : Origin Symbol (U Symbol #f) -> (List Natural (Listof Any))
;; Two GETs of /connection?delay=300 on FACE, by VERSION, submitted in one
;; batch, the engine held across both submits so one turn takes them: the
;; connections they used, and their versions.
(define (share-together o face version)
  (on-own-engine
   (lambda (e)
     (let* ((r (version-request o face "/connection?delay=300" version))
            (tokens (call-with-engine-held e (lambda ()
                                               (let* ((t1 (curl-submit e r)) (t2 (curl-submit e r)))
                                                 (list t1 t2)))))
            (o1 (awaited (car tokens)))
            (o2 (awaited (cadr tokens))))
       (list (connections-used (list (response-k o1) (response-k o2)))
             (list (version-of o1) (version-of o2)))))))

;; pieces-of : Token -> Bytevector
;; Every piece of TOKEN's streamed body, joined, each taken within 30 s.
(define (pieces-of token)
  (let loop ((found '()))
    (let ((p (curl-token-next-piece token 30000)))
      (if (bytevector? p)
          (loop (cons p found))
          (let* ((all (reverse found))
                 (out (make-bytevector (fold-left + 0 (map bytevector-length all)))))
            (fold-left (lambda (at p) (bytevector-copy! p 0 out at (bytevector-length p))
                         (+ at (bytevector-length p)))
                       0 all)
            out)))))

;; share-after-head : Origin Symbol (U Symbol #f) -> (List Any Boolean Any (Listof Any))
;; A GET of /connection?delay=1500 on FACE, by VERSION, streamed, then,
;; once its head is in, a second GET of /connection: whether the head came,
;; whether the first was still open when the second ended, the connections
;; the two used, and their versions.
(define (share-after-head o face version)
  (on-own-engine
   (lambda (e)
     (let* ((t1 (curl-submit e (curl-request-with (version-request o face "/connection?delay=1500" version)
                                                  'stream-buffer 4096)))
            (head (curl-token-head-wait t1 30000))
            (t2 (curl-submit e (version-request o face "/connection" version)))
            (o2 (awaited t2))
            (open (not (curl-token-done? t1)))
            (body1 (pieces-of t1))
            (o1 (awaited t1)))
       (list (if head 'head 'no-head) open
             (connections-used (list (or (connection-k body1) (list 'no-k (latin-1 body1))) (response-k o2)))
             (list (version-of o1) (version-of o2)))))))

;; share-after-end : Origin Symbol (U Symbol #f) -> (List Any (Listof Any))
;; A GET of /connection on FACE, by VERSION, awaited, then a second: the
;; connections the two used, and their versions.
(define (share-after-end o face version)
  (on-own-engine
   (lambda (e)
     (let* ((o1 (awaited (curl-submit e (version-request o face "/connection" version))))
            (o2 (awaited (curl-submit e (version-request o face "/connection" version)))))
       (list (connections-used (list (response-k o1) (response-k o2)))
             (list (version-of o1) (version-of o2)))))))

;; unmultiplexed : (Listof String)
;; The libcurl versions on which the engine multiplexes nothing, 8.7.0 and
;; 8.7.1 (ADR-0030, amended), written out here, not read from the engine's
;; table, which a mutant would loosen with the code (AGENTS.md):
;; tests/test-stream.sps holds that table to its own copy.
(define unmultiplexed '("8.7.0" "8.7.1"))

;; --- the high level ---------------------------------------------------------------------

;; history-of : Response -> (Listof (List Integer Any String))
(define (history-of r)
  (map (lambda (h) (list (http-response-status h) (http-response-http-version h) (http-response-url h)))
       (http-response-history r)))

;; call-outcome : (-> Response) -> Outcome
;; A call's answer, whole: (response STATUS VERSION ECHO HISTORY), ECHO by
;; echo-lines, HISTORY each earlier response's status, version and URL; or
;; (raised PARTS), PARTS each part of what it raised that is chez-curl's:
;; (request-refused FIELD VALUE REASON WHO), (failed REASON CODE CLASS),
;; (exchange METHOD URL HISTORY TRANSFERS), and (http-error BOOLEAN).
(define (call-outcome thunk)
  (guard (e (#t (list 'raised
                      (append (if (curl-request-error? e)
                                  (list (cons 'request-refused (cdr (refusal-of e))))
                                  '())
                              (if (curl-transfer-error? e)
                                  (list (list 'failed (curl-transfer-error-reason e)
                                              (curl-transfer-error-code e) (class-of e)))
                                  '())
                              (if (http-exchange? e)
                                  (list (list 'exchange (http-exchange-method e) (http-exchange-url e)
                                              (map (lambda (h) (list (http-response-status h)
                                                                     (http-response-http-version h)
                                                                     (http-response-url h)))
                                                   (http-exchange-history e))
                                              (http-exchange-transfers e)))
                                  '())
                              (list (list 'http-error (http-error? e)))
                              (if (or (curl-request-error? e) (curl-transfer-error? e) (http-exchange? e))
                                  '()
                                  (list (list 'other (describe e))))))))
    (let ((r (thunk)))
      (list 'response (http-response-status r) (http-response-http-version r)
            (echo-lines (http-response-body r) (http-response-http-version r))
            (history-of r)))))

;; in-session : List (Session -> Any) -> Any
;; PROC's answer, given a session with KEYS, direct, a 20 s timeout and the
;; run's CA file, closed once PROC returns; (raised TEXT) for a raise the
;; session itself makes.
(define (in-session keys proc)
  (guard (e (#t (list 'raised (describe e))))
    (apply call-with-http-session 'proxy #f 'timeout-ms 20000 'ca-file ca
           (append keys (list proc)))))

;; --- the scenarios, against the origin -------------------------------------------------

(define reps (let ((v (getenv "PROBE_REPS"))) (or (and v (string->number v)) 10)))

(define (tally xs)
  (fold-left (lambda (acc x)
               (let ((hit (assoc x acc)))
                 (if hit
                     (map (lambda (e) (if (eq? e hit) (cons (car e) (+ (cdr e) 1)) e)) acc)
                     (append acc (list (cons x 1))))))
             '() xs))

(define (repeat n thunk)
  (let loop ((i 0) (found '()))
    (if (= i n) (reverse found) (loop (+ i 1) (cons (thunk) found)))))

(define (summary o)
  (if (and (pair? o) (eq? (car o) 'response)) (list 'response (cadr o) (caddr o)) o))

(define (scenarios o)
  (for-each
   (lambda (c)
     (let ((face (car c)) (v (cadr c)))
       (display (list 'probe version face v (tally (repeat reps (lambda () (summary (cell o face v)))))))
       (newline)))
   '((http http/2-prior-knowledge) (h2c #f) (h2c http/1.1) (h2c http/2) (h2 http/1.1)))
  (display (list 'probe version 'together-h2c (tally (repeat reps (lambda () (share-together o 'h2c 'http/2-prior-knowledge))))))
  (newline)
  (test-equal "probe ran" #t #t))

(define scenarios-outcome
  (guard (e (#t (list 'raised (describe e))))
    (parameterize ((origin-pki pki))
      (call-with-origin (lambda (o) (scenarios o) 'done)))))

(test-equal "the probe's origin stops" 'done scenarios-outcome)
(test-end "pkprobe")

(exit (suite-exit-status runner))
