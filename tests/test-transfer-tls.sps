#!r6rs
;;; The suite for a request's TLS fields (M2 plan, section 6; ADR-0018):
;;; (curl private transfer), each request submitted to the suite's one
;;; engine and awaited (M3 plan, section 5.2), against the test origin's
;;; TLS faces, with one PKI per run, made by make-test-pki, which the origin
;;; serves.
;;;
;;; Every transfer is asserted whole: the status, the HTTP version, every
;;; header in libcurl's order and the body, or the &curl-transfer-error's
;;; reason and CURLcode, with the native counts after it, which must be the
;;; engine's multi handle alone; once the engine has stopped, at the end,
;;; all zero. The expected bytes are this suite's own copies, never read from
;;; the origin. Every URL's host is 127.0.0.1, which the good leaf names.
;;; The four recorded Linux libcurls gave section 6's verdicts alike (plan,
;;; section 6.1), so the answers are shared, and there is no row file. The
;;; h2 face's headers were read on 8.20.0 alone.
;;;
;;; It holds:
;;;
;;;   - hermetic first: no proxy variable, nor SSL_CERT_FILE nor
;;;     SSL_CERT_DIR, is set, each one set named;
;;;   - verification on, the run CA as the CA file: https 200 over HTTP/1.1;
;;;     https-expired, https-wrong-host and https-untrusted 60; h2 200 over
;;;     HTTP/2, on a libcurl with the http2 feature, every recorded one;
;;;   - verification off: all four https faces 200 with no CA file, and the
;;;     three failing ones 200 with the run CA;
;;;   - the control, the system store: https 60, so a refusal above is the
;;;     run CA's absence, not a broken TLS stack; 77 there is a machine with
;;;     no system CA store, and the failure says so;
;;;   - the CA file decides: the other CA's file refuses https, 60; a
;;;     missing file, a directory, and a path with CR, LF and U+0100 that
;;;     names no file are 77, never a fallback to the system store; a path
;;;     past libcurl's string limit is a setopt it refuses, 43, naming
;;;     CAINFO;
;;;   - the path's encoding: a copy of ca.pem under a directory named with é
;;;     and λ, which ls lists as UTF-8, passes https;
;;;   - the request's refusals: a CA file with U+0000 at every place,
;;;     refused as embedded-nul, naming ca-file, by the constructor and by
;;;     the snapshot a submit takes, with nothing native at the raise; wrong
;;;     types; a change after the request was made, sent as changed; and a
;;;     CA file another thread flips to U+0000 while transfers run, refused
;;;     or sent whole, which a transfer that checked the caller's string,
;;;     not its own copy, fails in a native run;
;;;   - the settings, as data: tls-settings' answers, written out, for each
;;;     CA file and verification; setopt-accepted? against every code from
;;;     -1 to 300; and, read from transfer.sls and held whole, every
;;;     definition from a request's CA file and verification to the setopt
;;;     binding: ca-file?, ca-file-copy, field-options, tls-settings,
;;;     set-tls-options!, set-string-option!, set-option!, setopt-accepted?
;;;     and option-named; what prepare-transfer hands the plan, and
;;;     set-transfer-options!' call of set-tls-options! with the plan's,
;;;     after the request's other settings and before the test seam's; and
;;;     the six TLS option names, standing in transfer.sls only as data in
;;;     its two tables;
;;;   - the Guix pin, in a child, tests/transfer-tls-env.sps, given
;;;     SSL_CERT_FILE or SSL_CERT_DIR through its command alone, three
;;;     cases, the two SSL_CERT_FILE ones mirrored: by ADR-0002's world and
;;;     the libcurl's version, through guix-pin-verdicts, on Guix's 8.20.0
;;;     SSL_CERT_FILE replaces the CA file and SSL_CERT_DIR adds a CA
;;;     directory; elsewhere both are ignored; a Guix libcurl of another
;;;     version fails, named, its verdicts unrecorded (ADR-0018, decision 5).
;;;
;;; Its limit (ADR-0018, consequences): no lane can show CAPATH's clear by
;;; behaviour. No lane's system store, nor any default CA directory, trusts
;;; the run CA, so a transfer that left CAPATH set would pass every case
;;; here. The clear is held as data alone, by tls-settings' answers and
;;; set-tls-options!' form; the Docker measurement ADR-0018 records is the
;;; behavioural evidence. Nor can a Linux lane show the CURLE_NOT_BUILT_IN
;;; a backend with no CA directory answers the clear: none answers it. So
;;; each definition on the way from the request to the setopt binding is
;;; held whole, and setopt-accepted? as a function too: a rewrite of any
;;; of them could drop the clear, or refuse CURLE_NOT_BUILT_IN for it, and
;;; pass every transfer here. Past option-named, the bindings are native's,
;;; held by its own suites.
;;;
;;; Importing (curl) runs the load before this suite's first line, on this
;;; thread, and the suite's top level reaches (curl private transfer), then
;;; makes its engine, before any other thread is forked. SRFI-64 makes #f of
;;; a raise in the actual
;;; expression, so no expected value is #f, and each computation that can
;;; raise at the top level runs under a guard.
(import (rnrs)
        (srfi :64)
        (rnrs mutable-strings)
        (only (chezscheme) parameterize getenv fork-thread thread-join sleep make-time mkdir
              directory-list library-directories current-time time-second time-nanosecond)
        (curl-testing)
        (curl)
        (curl private engine)
        (curl private transfer)
        (curl private conditions)
        (curl private counters)
        (only (curl private discovery) libcurl-world))

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

;; --- helpers --------------------------------------------------------------------------

(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0)))

;; running-counts : (Listof (Pairof Symbol Natural))
;; The counts while the suite's engine runs and no transfer is live: its
;; multi handle and its slot, a counted block it holds while it runs, and
;; nothing else. The child's counts, read once its own
;; engine has stopped, are zero-counts.
(define running-counts
  '((block . 1) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 1)))

;; The loaded libcurl's feature names, read here, on this thread, so the
;; load runs before any thread is forked.
(define feature-names
  (guard (e (#t (list 'raised (describe e))))
    (libcurl-info-feature-names (loaded-libcurl))))

;; The TLS settings for verification and no CA file, read here, so (curl
;; private transfer)'s body runs on this thread too.
(define settings-read
  (guard (e (#t (list 'raised (describe e))))
    (tls-settings #f #t)))

;; The suite's one engine, made here, on this thread, once the load and
;; (curl private transfer)'s body have run, and before any other thread is
;; forked. Every transfer below runs on it. A failure to make it is a
;; test's, below.
(define engine
  (guard (e (#t (list 'raised (describe e))))
    (make-curl-engine)))

(define engine-made? (curl-engine? engine))

;; await-bound-ms : Positive-Integer
;; The longest this suite awaits a token: past every transfer's own
;; timeout, default-timeout's 20 s. An engine that never completes a token
;; would hang an await for good, and a hang names no test: so the check
;; that awaited it fails, by name, and the suite goes on.
(define await-bound-ms 60000)

;; await-token : Token -> Response
;; TOKEN's response, or a raise of what it ended with, as curl-token-await
;; answers once TOKEN is done; a raise of (never-completed MS) when it is
;; not done within await-bound-ms.
(define (await-token token)
  (let ((deadline (+ (now-ms) await-bound-ms)))
    (let wait ()
      (cond ((curl-token-done? token) (curl-token-await token))
            ((> (now-ms) deadline) (raise (list 'never-completed await-bound-ms)))
            (else (pause-ms 1) (wait))))))

;; perform : Request -> Response
;; R submitted to the suite's engine, then awaited: its response, or a raise
;; of what it ended with, at submit, on this thread, or on the engine's.
(define (perform r) (await-token (curl-engine-submit engine r)))

;; settled : Any -> Any
;; X, as it is; a token is cancelled first, and awaited, whatever it ended
;; with, so that a submit a check expected refused leaves nothing running.
(define (settled x)
  (when (curl-token? x)
    (curl-token-cancel x)
    (guard (e (#t #f)) (await-token x)))
  x)

;; iota-from : Integer Natural -> (Listof Integer)
(define (iota-from start n)
  (if (= n 0) '() (cons start (iota-from (+ start 1) (- n 1)))))

;; latin-1 : Bytevector -> String
(define (latin-1 bytes)
  (list->string (map integer->char (bytevector->u8-list bytes))))

;; now-ms : -> Integer
(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

;; pause-ms : Natural -> Unit
(define (pause-ms ms)
  (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))

;; How long a transfer may take before libcurl gives up: long enough for a
;; handshake under the memory gate's Valgrind.
(define default-timeout 20000)

;; request : String . (Listof Any) -> Request
;; A GET of TARGET with no headers, no user agent, default-timeout and no
;; body limit, nor fault. OPTIONS are keyword and value: ca-file, #f unless
;; given, and verify, #t unless given.
(define (request target . options)
  (let ((given (lambda (key default)
                 (let ((at (memq key options))) (if at (cadr at) default)))))
    (make-curl-request target 'timeout-ms default-timeout
                       'ca-file (given 'ca-file #f) 'verify (given 'verify #t))))

;; answer-of : (-> Response) -> Answer
;; What THUNK's transfer answers, whole: (response STATUS VERSION HEADERS
;; BODY), each header (NAME VALUE) and the body read as Latin-1; (refused
;; REASON CODE) for a &curl-transfer-error; (request-refused FIELD REASON)
;; for a &curl-request-error; (raised TEXT) for anything else.
(define (answer-of thunk)
  (guard (e ((curl-transfer-error? e)
             (list 'refused (curl-transfer-error-reason e) (curl-transfer-error-code e)))
            ((curl-request-error? e)
             (list 'request-refused (curl-request-error-field e) (curl-request-error-reason e)))
            (#t (list 'raised (describe e))))
    (let ((r (thunk)))
      (list 'response (curl-response-status r) (curl-response-http-version r)
            (map (lambda (h) (list (car h) (cdr h))) (curl-response-headers r))
            (latin-1 (curl-response-body r))))))

;; with-counts : Any -> (List Any (Listof (Pairof Symbol Natural)))
;; ANSWER, and the native counts once it was answered.
(define (with-counts answer) (list answer (native-counts)))

;; refusal : (-> Any) -> (List Any (Listof (Pairof Symbol Natural)) (Listof (Pairof Symbol Natural)))
;; What THUNK raised: (request-refused FIELD VALUE REASON), or
;; (assertion-violation WHO), or as answer-of names it; the native counts
;; at the raise, read by a handler before any dynamic-wind's after thunk;
;; and the counts after. no-raise when nothing was raised: a token THUNK
;; answered, a submit not refused, is settled first.
(define (refusal thunk)
  (let* ((seen 'no-raise)
         (r (guard (e ((curl-request-error? e)
                       (list 'request-refused (curl-request-error-field e)
                             (curl-request-error-value e) (curl-request-error-reason e)))
                      ((curl-transfer-error? e)
                       (list 'transfer-refused (curl-transfer-error-reason e)
                             (curl-transfer-error-code e)))
                      ((and (assertion-violation? e) (who-condition? e))
                       (list 'assertion-violation (condition-who e)))
                      (#t (list 'raised (describe e))))
              (with-exception-handler
                (lambda (c) (set! seen (native-counts)) (raise c))
                (lambda () (settled (thunk)) 'no-raise)))))
    (list r seen (native-counts))))

;; lines-of : String -> (Listof String)
;; TEXT's lines, each without its newline; a last line without one too.
(define (lines-of text)
  (let loop ((i 0) (start 0) (found '()))
    (cond ((= i (string-length text))
           (reverse (if (= start i) found (cons (substring text start i) found))))
          ((char=? (string-ref text i) #\newline)
           (loop (+ i 1) (+ i 1) (cons (substring text start i) found)))
          (else (loop (+ i 1) start found)))))

;; copy-file : String String -> Unit
;; The bytes of the file at FROM written to a new file at TO.
(define (copy-file from to)
  (let ((bytes (call-with-port (open-file-input-port from) get-bytevector-all)))
    (call-with-port (open-file-output-port to)
      (lambda (p) (put-bytevector p bytes)))))

;; The answers, this suite's own copies of the origin's bytes. The https
;; faces serve the http face's routes; h2 serves the HTTP/2 ones, and
;; curl_easy_nextheader gives an HTTP/2 response's headers as sent, in
;; lower case, with no :status pseudo-header (measured on 8.20.0,
;; build/verify/m2s3/work/h2-headers.sps).
(define good-answer
  '(response 200 http/1.1 (("Content-Length" "11") ("Connection" "keep-alive")) "status 200\n"))
(define h2-answer
  '(response 200 http/2 (("content-length" "11")) "status 200\n"))
(define peer-refused '(refused perform-failed 60))
(define ca-file-refused '(refused perform-failed 77))

(test-begin "transfer-tls")

;; --- hermetic: nothing from the environment --------------------------------------------
;; libcurl reads the proxy variables, and would send every transfer here to
;; the proxy they name. Guix's libcurl writes SSL_CERT_FILE and
;; SSL_CERT_DIR over CAINFO and CAPATH when a transfer starts (ADR-0018):
;; with either set, the CA file would not be what a transfer trusts. This
;; suite sets them only for its child, through the child's command.
(define environment-variables
  '("http_proxy" "HTTP_PROXY" "https_proxy" "HTTPS_PROXY" "all_proxy" "ALL_PROXY"
    "SSL_CERT_FILE" "SSL_CERT_DIR"))

(test-equal "hermetic: none of http_proxy, HTTP_PROXY, https_proxy, HTTPS_PROXY, all_proxy, ALL_PROXY, SSL_CERT_FILE and SSL_CERT_DIR is set: libcurl would send this suite's transfers to the proxy, and Guix's would trust the CA store named, not the CA file"
  '()
  (filter (lambda (name) (getenv name)) environment-variables))

(test-equal "the suite's engine is made: running, holding its multi handle and nothing else"
  (list 'running running-counts)
  (if engine-made? (list (curl-engine-state engine) (native-counts)) engine))

;; --- the PKI, and the copies of its CAs ------------------------------------------------

(define pki-made
  (guard (e (#t (list 'raised (describe e))))
    (list 'made (make-test-pki))))
(define pki (and (eq? (car pki-made) 'made) (cadr pki-made)))

(test-equal "make-test-pki makes this run's PKI"
  'made
  (car pki-made))

;; pki-file : String -> String
(define (pki-file name) (string-append (or pki "/no-pki") "/" name))

;; The copies live in a process temp directory of their own: the PKI's
;; directory must hold exactly its ten files.
(define scratch-made
  (guard (e (#t (list 'raised (describe e))))
    (list 'made (make-process-temp-directory))))
(define scratch (and (eq? (car scratch-made) 'made) (cadr scratch-made)))

;; scratch-file : String -> String
(define (scratch-file name) (string-append (or scratch "/no-scratch") "/" name))

;; utf8-name : String
;; café-λ: é is two bytes in UTF-8, and λ, above U+00FF, has no Latin-1 byte.
(define utf8-name (string #\c #\a #\f (integer->char #xE9) #\- (integer->char #x3BB)))

(define utf8-ca (string-append (scratch-file utf8-name) "/ca.pem"))
(define cert-dir (scratch-file "cert-dir"))
(define run-ca-copy (scratch-file "a.pem"))
(define other-ca-copy (scratch-file "b.pem"))

;; copies : (U (List 'made String) (List 'raised String))
;; ca.pem under café-λ; cert-dir, holding a copy of ca.pem and its openssl
;; x509 -hash link alone, for SSL_CERT_DIR; and a.pem and b.pem, copies of
;; ca.pem and other-ca.pem whose paths differ in one char. Answers the
;; hash's link name.
(define copies
  (guard (e (#t (list 'raised (describe e))))
    (unless (and pki scratch) (error 'copies "no PKI, or no scratch directory"))
    (mkdir (scratch-file utf8-name))
    (copy-file (pki-file "ca.pem") utf8-ca)
    (mkdir cert-dir)
    (copy-file (pki-file "ca.pem") (string-append cert-dir "/ca.pem"))
    (copy-file (pki-file "ca.pem") run-ca-copy)
    (copy-file (pki-file "other-ca.pem") other-ca-copy)
    (let* ((hashed (capture-command (list (openssl-program) "x509" "-hash" "-noout"
                                          "-in" (string-append cert-dir "/ca.pem"))))
           (lines (lines-of (cadr hashed))))
      (unless (and (= (car hashed) 0) (= (length lines) 1) (string=? (caddr hashed) ""))
        (error 'copies "openssl x509 -hash did not answer one line" hashed))
      (let* ((link (string-append (car lines) ".0"))
             (linked (capture-command (list "ln" "-s" "ca.pem" (string-append cert-dir "/" link)))))
        (unless (equal? linked '(0 "" ""))
          (error 'copies "ln -s did not link the hash" linked))
        (list 'made link)))))

(define hash-link (and (eq? (car copies) 'made) (cadr copies)))

(test-equal "the copies are made: ca.pem under café-λ, cert-dir with ca.pem and its hash link, and a.pem and b.pem"
  'made
  (car copies))

(test-equal "on disk: the PKI's directory holds its ten files alone; the scratch directory, as ls lists it, read as UTF-8, a.pem, b.pem, café-λ and cert-dir; cert-dir, ca.pem and its hash link"
  (list '("ca.pem" "expired.key" "expired.pem" "good.key" "good.pem" "other-ca.pem"
          "untrusted.key" "untrusted.pem" "wrong-host.key" "wrong-host.pem")
        (list-sort string<? (list "a.pem" "b.pem" utf8-name "cert-dir"))
        (list-sort string<? (list "ca.pem" (or hash-link "no-link"))))
  (guard (e (#t (list 'raised (describe e))))
    (list (list-sort string<? (directory-list pki))
          (let ((listed (capture-command (list "ls" "-1" scratch))))
            (if (and (= (car listed) 0) (string=? (caddr listed) ""))
                (list-sort string<? (lines-of (cadr listed)))
                (list 'ls listed)))
          (list-sort string<? (directory-list cert-dir)))))

;; --- the request's refusals ------------------------------------------------------------

;; a-path : String
;; A CA file's path, for the refusals: no transfer here reads it.
(define a-path "/x/ca.pem")

;; with-nul-at : Natural -> String
;; a-path with U+0000 put before its char I, or at its end.
(define (with-nul-at i)
  (string-append (substring a-path 0 i) (string #\nul) (substring a-path i (string-length a-path))))

;; nul-paths : (Listof String)
;; a-path with U+0000 at each of its ten places, and U+0000 alone.
(define nul-paths
  (append (map with-nul-at (iota-from 0 (+ (string-length a-path) 1))) (list (string #\nul))))

(test-equal "a CA file with U+0000 at each of its places, and alone, is refused by make-curl-request as embedded-nul, naming ca-file and the path, with nothing native at the raise"
  (map (lambda (path) (list (list 'request-refused 'ca-file path 'embedded-nul) running-counts running-counts))
       nul-paths)
  (map (lambda (path)
         (refusal (lambda () (make-curl-request "http://127.0.0.1:1/" 'ca-file path))))
       nul-paths))

;; set-nul-at : Natural -> String
;; a-path with its char I made U+0000.
(define (set-nul-at i)
  (let ((path (string-copy a-path))) (string-set! path i #\nul) path))

(test-equal "a request whose CA file is changed after it was made, by string-set!, to hold U+0000 at each of its places, is refused at submit as embedded-nul, naming ca-file and the path as changed, with nothing native at the raise"
  (map (lambda (i) (list (list 'request-refused 'ca-file (set-nul-at i) 'embedded-nul) running-counts running-counts))
       (iota-from 0 (string-length a-path)))
  (map (lambda (i)
         (let* ((path (string-copy a-path))
                (r (make-curl-request "http://127.0.0.1:1/" 'ca-file path)))
           (string-set! path i #\nul)
           (refusal (lambda () (curl-engine-submit engine r)))))
       (iota-from 0 (string-length a-path))))

(test-equal "wrong types are assertion violations from make-curl-request, with nothing native made: a CA file that is a number, the empty string, a symbol, #t or a list; verification that is 1, 0, a symbol, a string or the empty list"
  (map (lambda (i) (list '(assertion-violation make-curl-request) running-counts running-counts))
       (iota-from 0 10))
  (map (lambda (fields)
         (refusal (lambda () (make-curl-request "http://127.0.0.1:1/"
                                                'ca-file (car fields) 'verify (cadr fields)))))
       '((1 #t) ("" #t) (ca.pem #t) (#t #t) (("ca.pem") #t)
         ("/x/ca.pem" 1) ("/x/ca.pem" 0) ("/x/ca.pem" yes) ("/x/ca.pem" "true") ("/x/ca.pem" ()))))

(test-equal "the CA files a request takes, each with verification on and off: #f; a path of one char; a relative path; one holding CR, LF, HTAB, U+00E9, U+0100 and U+1F600, since a path may hold any char but U+0000"
  (map (lambda (i) 'no-raise) (iota-from 0 8))
  (apply append
         (map (lambda (ca-file)
                (map (lambda (verify)
                       (car (refusal (lambda () (make-curl-request "http://127.0.0.1:1/"
                                                                   'ca-file ca-file 'verify verify)))))
                     '(#t #f)))
              (list #f "c" "certs/ca.pem"
                    (string #\/ #\a #\return #\b #\newline #\c #\tab (integer->char #xE9)
                            (integer->char #x100) (integer->char #x1F600))))))

(test-equal "a request's CA file and verification read back as given: the caller's very string, and #f"
  '(the-string verify-off)
  (let* ((path (string-copy "/x/ca.pem"))
         (r (make-curl-request "http://127.0.0.1:1/" 'ca-file path 'verify #f)))
    (list (if (eq? (curl-request-ca-file r) path) 'the-string (curl-request-ca-file r))
          (if (eq? (curl-request-verify r) #f) 'verify-off (curl-request-verify r)))))

;; --- the settings, as data ---------------------------------------------------------------

(test-equal "tls-settings, written out, for each CA file and verification: SSL_VERIFYPEER at 1 and SSL_VERIFYHOST at 2, or both at 0; then, with a CA file alone, CAINFO at its path and CAPATH at #f, a clear"
  '((("SSL_VERIFYPEER" . 1) ("SSL_VERIFYHOST" . 2) ("CAINFO" . "/x/ca.pem") ("CAPATH" . #f))
    (("SSL_VERIFYPEER" . 0) ("SSL_VERIFYHOST" . 0) ("CAINFO" . "/x/ca.pem") ("CAPATH" . #f))
    (("SSL_VERIFYPEER" . 1) ("SSL_VERIFYHOST" . 2))
    (("SSL_VERIFYPEER" . 0) ("SSL_VERIFYHOST" . 0)))
  (guard (e (#t (list 'raised (describe e))))
    (list (tls-settings "/x/ca.pem" #t) (tls-settings "/x/ca.pem" #f)
          settings-read (tls-settings #f #f))))

(test-equal "setopt-accepted?, at every code from -1 to 300: a clear, #f, takes CURLE_OK and CURLE_NOT_BUILT_IN, 0 and 4; a path, and the numbers 1, 2 and 0, take CURLE_OK alone"
  '((clear 0 4) (path 0) (1 0) (2 0) (0 0))
  (guard (e (#t (list 'raised (describe e))))
    (map (lambda (value)
           (cons (cond ((not value) 'clear) ((string? value) 'path) (else value))
                 (filter (lambda (code) (setopt-accepted? value code)) (iota-from -1 302))))
         (list #f "/x/ca.pem" 1 2 0))))

;; --- transfer.sls, read as data ------------------------------------------------------------
;; The limit of these reads, as test-transfer's: they hold the settings
;; against an accidental change, a setting dropped, moved, made
;; conditional or written twice; not against a rewrite made to pass them.

(define transfer-source "src/curl/private/transfer.sls")

;; transfer-library : Any
;; transfer.sls's library form, or what went wrong.
(define transfer-library
  (guard (e (#t (list 'unreadable (describe e))))
    (call-with-port (open-file-input-port transfer-source (file-options) (buffer-mode block)
                                          (make-transcoder (utf-8-codec)))
      read)))

;; transfer-definition : Symbol -> Any
;; The (define (NAME ...) ...) form in transfer.sls's library, or what went
;; wrong.
(define (transfer-definition name)
  (if (and (list? transfer-library) (> (length transfer-library) 4))
      (or (find (lambda (f) (and (pair? f) (eq? (car f) 'define) (pair? (cdr f))
                                 (pair? (cadr f)) (eq? (car (cadr f)) name)))
                (cddddr transfer-library))
          (list 'no-definition name))
      transfer-library))

;; holds? : Any Any -> Boolean
(define (holds? x datum)
  (or (equal? x datum) (and (pair? x) (or (holds? (car x) datum) (holds? (cdr x) datum)))))

;; symbol-count : Symbol Any -> Natural
(define (symbol-count name x)
  (cond ((eq? x name) 1)
        ((pair? x) (+ (symbol-count name (car x)) (symbol-count name (cdr x))))
        (else 0)))

;; held-definitions : (Listof (List Symbol String Any))
;; Every definition of transfer.sls between a request's CA file and
;; verification and the setopt binding they reach, whose change would
;; change what libcurl is handed, written out whole here: no lane can show
;; CAPATH's clear, nor CURLE_NOT_BUILT_IN taken for it, by behaviour, so a
;; rewrite of any of them could drop either while every transfer passes.
;; option-binding and option-setter are not here: test-transfer holds each
;; over its whole domain. prepare-transfer and set-transfer-options! are
;; held below, by what they hand set-tls-options!.
(define held-definitions
  '((ca-file? "a CA file is #f, or a non-empty string"
     (define (ca-file? x)
       (or (not x) (and (string? x) (> (string-length x) 0)))))
    (ca-file-copy "the CA file sent is a fresh copy, scanned for U+0000 by index, refused there"
     (define (ca-file-copy who ca-file)
       (and ca-file
            (let ((copy (string-copy ca-file)))
              (let scan ((i 0))
                (when (< i (string-length copy))
                  (when (char=? (string-ref copy i) #\nul)
                    (refuse-ca-file who copy))
                  (scan (+ i 1))))
              copy))))
    (field-options "a field's options are its row's names, in order"
     (define (field-options field) (cdr (assq field request-field-options))))
    (tls-settings "the verification pair, then CAINFO at the path and CAPATH at #f with a CA file alone"
     (define (tls-settings ca-file verify)
       (let ((verify-names (field-options 'verify))
             (ca-file-names (field-options 'ca-file)))
         (append (list (cons (car verify-names) (if verify 1 0))
                       (cons (cadr verify-names) (if verify 2 0)))
                 (if ca-file
                     (list (cons (car ca-file-names) ca-file) (cons (cadr ca-file-names) #f))
                     '())))))
    (set-tls-options! "each setting in order, a string through set-string-option!, a number or #f through set-option!"
     (define (set-tls-options! easy ca-file verify buffer)
       (for-each (lambda (setting)
                   (if (string? (cdr setting))
                       (set-string-option! easy (car setting) (cdr setting) buffer)
                       (set-option! easy (car setting) (cdr setting) buffer)))
                 (tls-settings ca-file verify))))
    (set-string-option! "a string goes as call-with-c-string's counted UTF-8 copy"
     (define (set-string-option! easy name text buffer)
       (call-with-c-string text (lambda (address) (set-option! easy name address buffer)))))
    (set-option! "#f goes as NULL, (or value 0), on every call, and each code is judged by setopt-accepted? with the value given"
     (define (set-option! easy name value buffer)
       (let* ((option (option-named name))
              (binding (option-binding (cdr option))))
         (unless (case binding
                   ((long) (long? value))
                   ((off-t) (off-t? value))
                   (else (or (not value) (pointer? value))))
           (assertion-violation 'set-option! "the value does not fit the option's type" name value))
         (let ((code ((option-setter binding) easy (car option) (or value 0))))
           (unless (setopt-accepted? value code)
             (fail 'setopt-failed code name buffer #f))))))
    (setopt-accepted? "CURLE_OK, or CURLE_NOT_BUILT_IN for a clear alone"
     (define (setopt-accepted? value code)
       (or (eqv? code curle-ok)
           (and (not value) (eqv? code curle-not-built-in)))))
    (option-named "a name is looked up as given, by curl-easy-option, through the cache"
     (define (option-named name)
       (unless (string? name)
         (assertion-violation 'set-option! "an option's name is a string without U+0000" name))
       (let ((name (string-copy name)))
         (when (memv #\nul (string->list name))
           (assertion-violation 'set-option! "an option's name is a string without U+0000" name))
         (let ((found (locked option-lock
                        (lambda ()
                          (or (hashtable-ref option-cache name #f)
                              (let ((option (or (curl-easy-option name) 'unknown)))
                                (hashtable-set! option-cache name option)
                                option))))))
           (if (eq? found 'unknown)
               (fail 'unknown-option #f name #f #f)
               found)))))))

(for-each
 (lambda (row)
   (test-equal (string-append (symbol->string (car row)) ", read from transfer.sls, held whole: " (cadr row))
     (caddr row)
     (transfer-definition (car row))))
 held-definitions)

;; let*-bindings : Any -> (U (Listof Any) #f)
;; The bindings of the first let* in X, depth first.
(define (let*-bindings x)
  (cond ((and (list? x) (> (length x) 1) (eq? (car x) 'let*) (list? (cadr x))) (cadr x))
        ((pair? x) (or (let*-bindings (car x)) (let*-bindings (cdr x))))
        (else #f)))

;; form-headed : Symbol Any -> (U (Listof Any) #f)
;; The first form in X headed by HEAD, depth first.
(define (form-headed head x)
  (cond ((and (list? x) (pair? x) (eq? (car x) head)) x)
        ((pair? x) (or (form-headed head (car x)) (form-headed head (cdr x))))
        (else #f)))

;; plan-fields : Any
;; The fields of transfer.sls's plan record, as its define-record-type
;; writes them, or what went wrong.
(define plan-fields
  (let ((d (and (list? transfer-library) (> (length transfer-library) 4)
                (find (lambda (f) (and (list? f) (> (length f) 2) (eq? (car f) 'define-record-type)
                                       (eq? (cadr f) 'plan)))
                      (cddddr transfer-library)))))
    (if d (cdr (or (assq 'fields (cddr d)) '(fields no-fields))) (list 'no-plan-record transfer-library))))

;; The way from a request to set-tls-options!: prepare-transfer copies the
;; CA file, on the caller's thread, into the plan's ninth field, and the
;; verification into its tenth; set-transfer-options! hands set-tls-options!
;; those two fields. A plan handed the caller's own string would be sent
;; whatever another thread made it after the check.
(test-equal "prepare-transfer hands the plan its snapshot: its let* binds ca-file to (ca-file-copy 'curl-engine-submit (curl-request-ca-file request)), make-plan takes ca-file and (curl-request-verify request) as its ninth and tenth arguments, the plan's ninth and tenth fields are ca-file and verify, and ca-file stands twice in prepare-transfer, that binding and that argument"
  '((ca-file (ca-file-copy 'curl-engine-submit (curl-request-ca-file request)))
    (ca-file (curl-request-verify request))
    ((immutable ca-file) (immutable verify))
    2)
  (let* ((d (transfer-definition 'prepare-transfer))
         (bindings (or (let*-bindings d) '()))
         (made (form-headed 'make-plan d)))
    (list (assq 'ca-file bindings)
          (if (and made (> (length made) 10)) (list (list-ref made 9) (list-ref made 10)) (list 'make-plan made))
          (if (and (list? plan-fields) (> (length plan-fields) 9))
              (list (list-ref plan-fields 8) (list-ref plan-fields 9))
              plan-fields)
          (symbol-count 'ca-file d))))

;; form-kind : Any -> Symbol
;; A form of set-transfer-options!, by what it does: pins, the pins' call;
;; tls, set-tls-options!'s, handed the plan's CA file and verification;
;; follow, the private follow field's setting; seam, the loop over the test
;; seam's settings; else request, one of the request's other settings.
(define (form-kind form)
  (cond ((equal? form '(set-pinned-options! easy buffer quick-exit)) 'pins)
        ((equal? form '(set-tls-options! easy (plan-ca-file plan) (plan-verify plan) buffer)) 'tls)
        ((holds? form '(plan-follow plan)) 'follow)
        ((holds? form '(plan-settings plan)) 'seam)
        (else 'request)))

;; runs : (Listof Symbol) -> (Listof Symbol)
;; KINDS with each run of one kind written once.
(define (runs kinds)
  (fold-right (lambda (k found) (if (and (pair? found) (eq? (car found) k)) found (cons k found)))
              '() kinds))

(test-equal "set-transfer-options!, form by form: the pins first, then the request's other settings, then set-tls-options! once, as (set-tls-options! easy (plan-ca-file plan) (plan-verify plan) buffer), then the private follow field's setting, then the test seam's settings; and set-tls-options! stands twice in transfer.sls, its definition and that call"
  '((pins request tls follow seam) 2)
  (let ((d (transfer-definition 'set-transfer-options!)))
    (if (and (list? d) (eq? (car d) 'define))
        (list (runs (map form-kind (cddr d))) (symbol-count 'set-tls-options! transfer-library))
        (list 'no-definition d))))

(test-equal "the form reader: kinds by form, and a run of one kind written once"
  '(pins request tls follow seam)
  (runs (map form-kind '((set-pinned-options! easy buffer quick-exit) (set-option! easy "A" 1 buffer)
                         (when x (set-option! easy "B" 2 buffer))
                         (set-tls-options! easy (plan-ca-file plan) (plan-verify plan) buffer)
                         (when (plan-follow plan) (set-option! easy "C" 1 buffer))
                         (for-each f (plan-settings plan))))))

;; tls-names : (Listof String)
;; The TLS fields' four options and the CA file's two twins.
(define tls-names '("CAINFO" "CAPATH" "SSL_VERIFYPEER" "SSL_VERIFYHOST" "CAINFO_BLOB" "SSL_OPTIONS"))

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
  (apply append
         (map (lambda (form)
                (walk form (and (pair? form) (eq? (car form) 'define) (pair? (cdr form))
                                (if (pair? (cadr form)) (car (cadr form)) (cadr form)))
                      #f))
              (cddddr library))))

;; by-text : (Listof Any) -> (Listof Any)
(define (by-text xs) (list-sort (lambda (a b) (string<? (written a) (written b))) xs))

(test-equal "the names CAINFO, CAPATH, SSL_VERIFYPEER and SSL_VERIFYHOST stand in transfer.sls only as quoted data in request-field-options, and CAINFO_BLOB and SSL_OPTIONS only in owned-option-names"
  (by-text '(("CAINFO" request-field-options quoted) ("CAPATH" request-field-options quoted)
             ("SSL_VERIFYPEER" request-field-options quoted) ("SSL_VERIFYHOST" request-field-options quoted)
             ("CAINFO_BLOB" owned-option-names quoted) ("SSL_OPTIONS" owned-option-names quoted)))
  (guard (e (#t (list 'unreadable (describe e))))
    (by-text (name-places tls-names transfer-library))))

(test-equal "name-places, the reader: a name in quoted data, and the same name in code, each with the definition holding it"
  '(("CAPATH" a quoted) ("CAPATH" b code))
  (name-places tls-names '(library (x) (export) (import) (define a '("CAPATH")) (define (b) (f "CAPATH")))))

;; --- the Guix pin's child: tests/transfer-tls-env.sps ----------------------------------

;; library-path : -> String
;; This suite's library path, as --libdirs takes it.
(define (library-path)
  (let loop ((dirs (map car (library-directories))) (text ""))
    (cond ((null? dirs) text)
          ((string=? text "") (loop (cdr dirs) (car dirs)))
          (else (loop (cdr dirs) (string-append text ":" (car dirs)))))))

;; read-all : String -> (Listof Any)
;; TEXT read as data, each datum in turn; a datum that does not read ends
;; the list with (unreadable).
(define (read-all text)
  (let ((port (open-string-input-port text)))
    (let loop ((found '()))
      (let ((datum (guard (e (#t '(unreadable))) (read port))))
        (cond ((eof-object? datum) (reverse found))
              ((equal? datum '(unreadable)) (reverse (cons datum found)))
              (else (loop (cons datum found))))))))

;; child-bound : Positive-Integer
;; The seconds the child may run before it is killed: it loads libcurl and
;; makes one transfer, a second or so natively.
(define child-bound 60)

;; child-script : String
;; sh -c CHILD-SCRIPT sh COMMAND...: COMMAND, with stdin at its end, under
;; GNU timeout (gtimeout on macOS), killed with SIGKILL after child-bound
;; seconds, exit 137; with neither found, exit 125, saying so. The shell's
;; own stderr is /dev/null, so dash's "Killed" is not the command's, as in
;; (curl-testing)'s bounded-script.
(define child-script
  (string-append
   "t=$(command -v timeout || command -v gtimeout) || { echo 'transfer-tls-env: no timeout' >&2; exit 125; }\n"
   "exec 3>&2 2>/dev/null\n"
   "( exec \"$t\" -s KILL " (number->string child-bound) " \"$@\" </dev/null 2>&3 3>&- )\n"
   "exit $?\n"))

;; child-run : String String String String -> (U (List Integer (Listof Any) String) (List 'raised String))
;; tests/transfer-tls-env.sps on URL with CA-FILE, in a child Chez under
;; child-script, with the variable NAME at VALUE in its environment alone,
;; set by env in its command: its exit status, what it printed, read as
;; data, and its stderr.
(define (child-run name value url ca-file)
  (guard (e (#t (list 'raised (describe e))))
    (let ((r (capture-command (list "sh" "-c" child-script "sh" "env" (string-append name "=" value)
                                    (getenv "CHEZ") "--libdirs" (library-path)
                                    "--program" "tests/transfer-tls-env.sps" url ca-file))))
      (list (car r) (read-all (cadr r)) (caddr r)))))

;; maps-text : (U String #f)
;; This process's /proc/self/maps, as the native layer reads it; #f off
;; Linux. The child runs the same Chez, so it lives in the same world.
(define maps-text
  (guard (e (#t #f))
    (call-with-port (open-file-input-port "/proc/self/maps" (file-options) (buffer-mode block)
                                          (make-transcoder (utf-8-codec)))
      get-string-all)))

;; world : (U 'guix 'fhs)
;; ADR-0002's world: guix when libc is mapped from /gnu/store; fhs on any
;; other Linux, and on macOS.
(define world (libcurl-world maps-text))

;; libcurl-version : (U String (List 'raised String))
;; The loaded libcurl's version, which the child loads too.
(define libcurl-version
  (guard (e (#t (list 'raised (describe e))))
    (libcurl-info-version (loaded-libcurl))))

;; guix-pin-verdicts : (Listof (List String Symbol))
;; Guix's libcurl, by version, and what its environment patch does to a
;; transfer's CA settings. 8.20.0's writes SSL_CERT_FILE over CAINFO and
;; SSL_CERT_DIR over CAPATH when a transfer starts, after every setopt:
;; overridden (ADR-0018). Guix's 8.6.0 sets them as the easy handle's
;; defaults instead, which the request's setopts win, so it answers each
;; case the other way (measured in M2 slice 3's review); no lane runs it,
;; so it has no row. A Guix libcurl of any other version fails the pin,
;; named: measure its three cases, and add its row.
(define guix-pin-verdicts '(("8.20.0" overridden)))

;; pin-verdict : Symbol Any -> (U 'overridden 'ignored (List 'unrecorded Any))
;; What SSL_CERT_FILE and SSL_CERT_DIR do to a transfer in WORLD, on the
;; libcurl at VERSION: in a Guix world, its version's row; in any other,
;; ignored, since no other libcurl reads them; unrecorded for a Guix
;; libcurl with no row.
(define (pin-verdict world version)
  (cond ((not (eq? world 'guix)) 'ignored)
        ((and (string? version) (assoc version guix-pin-verdicts)) => cadr)
        (else (list 'unrecorded version))))

(define verdict (pin-verdict world libcurl-version))

(test-equal "pin-verdict, the Guix pin's table: Guix's 8.20.0 overridden; every other world ignored, whatever its version; a Guix libcurl with no row, 8.6.0 among them, unrecorded, naming its version"
  '(overridden ignored ignored (unrecorded "8.6.0") (unrecorded "8.21.0"))
  (list (pin-verdict 'guix "8.20.0") (pin-verdict 'fhs "8.20.0") (pin-verdict 'fhs "8.5.0")
        (pin-verdict 'guix "8.6.0") (pin-verdict 'guix "8.21.0")))

(test-equal (string-append "the Guix pin has a verdict for this world, " (symbol->string world)
                           ", and this libcurl, " (written libcurl-version)
                           ": a Guix libcurl's comes from its version's row in guix-pin-verdicts; one with no row has unrecorded verdicts: measure the pin's three cases on it, and add its row")
  'recorded
  (if (pair? verdict)
      (list 'unrecorded-guix-libcurl libcurl-version
            "its pin verdicts are unrecorded: measure the pin's three cases, and add a row to guix-pin-verdicts")
      'recorded))

;; --- against the origin --------------------------------------------------------------------

;; url-of : Origin Symbol String -> String
;; FACE's URL for PATH, at 127.0.0.1, which the good leaf names: http:// for
;; the plaintext faces, https:// for the TLS ones.
(define (url-of o face path)
  (string-append (if (memq face '(http raw h2c)) "http://" "https://")
                 "127.0.0.1:" (number->string (cdr (origin-face o face))) path))

(define (scenarios o)
  ;; get : Symbol . (Listof Any) -> Answer
  ;; What a GET of FACE's /status/200 answers, with OPTIONS as request's.
  (define (get face . options)
    (answer-of (lambda () (perform (apply request (url-of o face "/status/200") options)))))

  ;; --- verification on, the run CA as the CA file
  (test-equal "verification on, the run CA as the CA file: https answers 200 over HTTP/1.1, whole, and the counts back to the engine's alone"
    (list good-answer running-counts)
    (with-counts (get 'https 'ca-file (pki-file "ca.pem"))))
  (for-each
   (lambda (face)
     (test-equal (string-append "verification on, the run CA as the CA file: " (symbol->string face)
                                " is refused, 60, CURLE_PEER_FAILED_VERIFICATION, and the counts back to the engine's alone")
       (list peer-refused running-counts)
       (with-counts (get face 'ca-file (pki-file "ca.pem")))))
   '(https-expired https-wrong-host https-untrusted))

  ;; --- HTTP/2, by ALPN
  (test-equal "the loaded libcurl has the http2 feature, as every recorded libcurl does"
    'http2
    (if (and (list? feature-names) (memq 'http2 feature-names)) 'http2 (list 'no-http2 feature-names)))
  (test-equal "verification on, the run CA as the CA file: h2 answers 200 over HTTP/2, chosen by ALPN, whole: curl_easy_nextheader gives content-length alone, lower case as sent, and no :status; the counts back to the engine's alone"
    (list h2-answer running-counts)
    (with-counts (get 'h2 'ca-file (pki-file "ca.pem"))))

  ;; --- verification off
  (for-each
   (lambda (face)
     (test-equal (string-append "verification off, no CA file: " (symbol->string face)
                                " answers 200 over HTTP/1.1, whole, and the counts back to the engine's alone")
       (list good-answer running-counts)
       (with-counts (get face 'verify #f))))
   '(https https-expired https-wrong-host https-untrusted))
  (for-each
   (lambda (face)
     (test-equal (string-append "verification off, the run CA as the CA file: " (symbol->string face)
                                " answers 200 over HTTP/1.1, whole, and the counts back to the engine's alone")
       (list good-answer running-counts)
       (with-counts (get face 'ca-file (pki-file "ca.pem") 'verify #f))))
   '(https-expired https-wrong-host https-untrusted))

  ;; --- the control: the system store. It shows a refusal above is the run
  ;; CA's absence, not a broken TLS stack. A machine with no system CA
  ;; store answers 77 on OpenSSL builds, whose default CA file is missing
  ;; (ADR-0018, consequences): the failure names that cause.
  (test-equal "the control, the system store, no CA file, verification on: https is refused, 60, since no system store trusts the run CA; 77 would be a machine with no system CA store; the counts back to the engine's alone"
    (list peer-refused running-counts)
    (let ((a (get 'https)))
      (list (if (equal? a ca-file-refused)
                '(no-system-ca-store "libcurl answered 77, CURLE_SSL_CACERT_BADFILE, for its own CA store: this machine has none. Install one, ca-certificates on Debian and Ubuntu (ADR-0018, consequences)")
                a)
            (native-counts))))

  ;; --- the CA file decides, and has no fallback
  (test-equal "the CA file decides: https with other-ca.pem as the CA file is refused, 60, and the counts back to the engine's alone"
    (list peer-refused running-counts)
    (with-counts (get 'https 'ca-file (pki-file "other-ca.pem"))))
  (test-equal "no fallback: https with a CA file that does not exist, and with a directory as the CA file, is refused, 77, CURLE_SSL_CACERT_BADFILE, never tried against the system store; the counts back to the engine's alone"
    (list ca-file-refused ca-file-refused running-counts)
    (list (get 'https 'ca-file (pki-file "no-such-ca.pem"))
          (get 'https 'ca-file pki)
          (native-counts)))
  (test-equal "a path holding CR, LF and U+0100 reaches libcurl, which finds no such file: 77, and the counts back to the engine's alone"
    (list ca-file-refused running-counts)
    (with-counts (get 'https 'ca-file (string-append (pki-file "ca") (string #\return #\newline (integer->char #x100))
                                                     ".pem"))))

  ;; --- a setopt libcurl refuses: a string past CURL_MAX_INPUT_LENGTH,
  ;; 8000000 bytes, is CURLE_BAD_FUNCTION_ARGUMENT on all four recorded
  ;; Linux libcurls (measured in M2 slice 3's review)
  (test-equal "a CA file of 8000001 bytes, past libcurl's string limit of 8000000, is refused by curl_easy_setopt: setopt-failed, 43, CURLE_BAD_FUNCTION_ARGUMENT, naming CAINFO, with a request size of 0, and the counts back to the engine's alone"
    (list '(setopt-failed 43 "CAINFO" 0) running-counts)
    (list (guard (e ((curl-transfer-error? e)
                     (list (curl-transfer-error-reason e) (curl-transfer-error-code e)
                           (curl-transfer-error-option e) (curl-transfer-error-request-size e)))
                    (#t (list 'raised (describe e))))
            (perform (request (url-of o 'https "/status/200")
                              'ca-file (string-append "/" (make-string 8000000 #\a))))
            'no-raise)
          (native-counts)))

  ;; --- the path's encoding
  (test-equal "the path's encoding: https with a copy of ca.pem under café-λ answers 200, whole, so the path reached libcurl as the UTF-8 the file system holds; the counts back to the engine's alone"
    (list good-answer running-counts)
    (with-counts (get 'https 'ca-file utf8-ca)))

  ;; --- a change after the request was made is the caller's until a submit
  ;; takes its copy: a.pem and b.pem, the run CA and the other, differ in
  ;; their one char
  (test-equal "a request whose CA file is changed after it was made is sent as changed: a.pem, the run CA, made b.pem, the other CA, is refused, 60; b.pem made a.pem answers 200, whole; the counts back to the engine's alone"
    (list peer-refused good-answer running-counts)
    (let ((changed (lambda (from to)
                     (let* ((path (string-copy from))
                            (r (request (url-of o 'https "/status/200") 'ca-file path)))
                       (string-set! path (- (string-length path) 5) (string-ref to (- (string-length to) 5)))
                       (answer-of (lambda () (perform r)))))))
      (list (changed run-ca-copy other-ca-copy)
            (changed other-ca-copy run-ca-copy)
            (native-counts))))

  ;; --- a CA file another thread changes while transfers run. A submit
  ;; takes its own copy and checks that alone: a transfer that checked the
  ;; caller's string, then sent it, would find U+0000 in it only on the
  ;; engine's thread, once native objects were made, and raise
  ;; call-with-c-string's refusal. The
  ;; http face reads no CA, yet every transfer sets CAINFO. The flipper
  ;; flips 1000000 times as fast as it can, then yields once in each
  ;; state, as test-transfer's do. Measured against that transfer: natively,
  ;; dozens of the 300 raised call-with-c-string's refusal; under Valgrind,
  ;; which runs one thread at a time, none did, so only a native run shows
  ;; it.
  (let ((http-answer '(response 200 http/1.1 (("Content-Length" "11") ("Connection" "keep-alive"))
                                "status 200\n")))
    (test-equal "a CA file another thread flips between s and U+0000 while 300 transfers run against the http face: each is refused as embedded-nul, naming ca-file, or answers whole, never otherwise, both seen; the counts back to the engine's alone"
      (list '() '(refused whole) running-counts)
      (let* ((path (string-copy "/no/such/ca.pem"))
             (r (request (url-of o 'http "/status/200") 'ca-file path))
             (stop #f)
             (flip (lambda ()
                     (let loop ((i 0))
                       (when (< i 1000000)
                         (string-set! path 4 #\nul)
                         (string-set! path 4 #\s)
                         (loop (+ i 1))))))
             (flipper (fork-thread (lambda ()
                                     (let loop ()
                                       (unless stop
                                         (flip)
                                         (pause-ms 0)
                                         (flip)
                                         (string-set! path 4 #\nul)
                                         (pause-ms 0)
                                         (loop)))))))
        (dynamic-wind
          (lambda () #f)
          (lambda ()
            (let loop ((i 0) (odd '()) (seen '()))
              (if (= i 300)
                  (list (reverse odd) (filter (lambda (k) (memq k seen)) '(refused whole)) (native-counts))
                  (let* ((a (answer-of (lambda () (perform r))))
                         (k (cond ((equal? a http-answer) 'whole)
                                  ((equal? a '(request-refused ca-file embedded-nul)) 'refused)
                                  (else #f))))
                    (loop (+ i 1)
                          (if k odd (cons a odd))
                          (if (and k (not (memq k seen))) (cons k seen) seen))))))
          (lambda () (set! stop #t) (thread-join flipper))))))

  ;; --- the Guix pin, in a child (ADR-0018, decision 5). Guix's 8.20.0
  ;; writes SSL_CERT_FILE over CAINFO and SSL_CERT_DIR over CAPATH when a
  ;; transfer starts; any other libcurl ignores both. The child is handed
  ;; the variable through its command, so this process's environment stays
  ;; hermetic, and it prints the libcurl it loaded and the variables it
  ;; saw. Each case answers one way overridden and the other ignored, the
  ;; two SSL_CERT_FILE cases mirrored, so that ignored is told from added.
  (for-each
   (lambda (pin)
     (let ((name (list-ref pin 0)) (value (list-ref pin 1)) (ca-file (list-ref pin 2))
           (overridden (list-ref pin 3)) (ignored (list-ref pin 4)) (text (list-ref pin 5)))
       (test-equal (string-append "the Guix pin, in a child given " text ", in this world, " (symbol->string world)
                                  ", on libcurl " (written libcurl-version) ": "
                                  (case verdict
                                    ((overridden) "overridden, ")
                                    ((ignored) "ignored, ")
                                    (else "with no recorded verdict, "))
                                  (written (if (eq? verdict 'overridden) overridden ignored))
                                  ", whole; the child's counts zero")
         (list 0
               (list (list 'libcurl libcurl-version)
                     (list 'environment
                           (cons 'SSL_CERT_FILE (and (string=? name "SSL_CERT_FILE") value))
                           (cons 'SSL_CERT_DIR (and (string=? name "SSL_CERT_DIR") value)))
                     (list 'transfer
                           (case verdict
                             ((overridden) overridden)
                             ((ignored) ignored)
                             (else (list 'no-verdict-for verdict)))
                           zero-counts)
                     '(done))
               "")
         (child-run name value (url-of o 'https "/status/200") ca-file))))
   (list (list "SSL_CERT_FILE" (pki-file "other-ca.pem") (pki-file "ca.pem") peer-refused good-answer
               "SSL_CERT_FILE at other-ca.pem alone, and the run CA as the CA file")
         (list "SSL_CERT_FILE" (pki-file "ca.pem") (pki-file "other-ca.pem") good-answer peer-refused
               "SSL_CERT_FILE at ca.pem alone, and other-ca.pem as the CA file")
         (list "SSL_CERT_DIR" cert-dir (pki-file "other-ca.pem") good-answer peer-refused
               "SSL_CERT_DIR at a directory holding ca.pem and its hash link alone, and other-ca.pem as the CA file"))))

(define scenarios-outcome
  (guard (e (#t (list 'raised (describe e))))
    (parameterize ((origin-pki pki))
      (call-with-origin (lambda (o) (scenarios o) 'done)))))

(test-equal "the scenarios' origin starts with the PKI, serves them all, and stops"
  'done
  scenarios-outcome)

(test-equal "once every transfer has ended, the live-transfer table and the engine's are empty, and the counts the engine's alone"
  (list 0 0 running-counts)
  (list (live-transfer-count) (if engine-made? (curl-engine-live-count engine) engine) (native-counts)))

;; The engine stops before the suite ends: suite-exit-status fails a suite
;; whose counts are not all zero at its end.
(test-equal "the suite's engine stops, and every count is zero after"
  (list 'stopped 0 zero-counts 0)
  (if engine-made?
      (begin (curl-engine-stop engine)
             (list (curl-engine-state engine) (curl-engine-live-count engine) (native-counts)
                   (live-transfer-count)))
      engine))

(test-end "transfer-tls")

(exit (suite-exit-status runner))
