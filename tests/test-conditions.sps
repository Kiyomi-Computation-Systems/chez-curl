#!r6rs
;;; The suite for (curl private conditions): chez-curl's condition types, all
;;; under &curl-error.
;;;
;;;   &curl-error                 the base, under &error
;;;   &curl-library-unavailable   libcurl was refused: ADR-0002's and ADR-0003's
;;;                               six reasons, what the refusal is about, and
;;;                               the library's own report once it was read
;;;   &curl-wrong-thread          an engine-owned handle used from another
;;;                               thread (ADR-0012)
;;;   &curl-embedded-nul          a string C would read short, holding U+0000
;;;   &curl-url-error             a URL refused, by libcurl or by chez-curl
;;;                               (ADR-0008), with its reason: the CURLUcode's
;;;                               name, by curl-url-code-reason, or #f for a
;;;                               code the floor's headers lack
;;;   &curl-request-error         a request's key or field refused before
;;;                               anything native is made, with one of
;;;                               forty-five reasons
;;;   &curl-transfer-error        a transfer failed, with one of fourteen
;;;                               reasons, its code, option, libcurl's texts,
;;;                               what the write callable recorded and its
;;;                               request size, cancelled and stopped among
;;;                               them; and its six classes, every code from
;;;                               0 to 101 written out (ADR-0022)
;;;   &curl-engine-error          an engine stopped, or failed, with the
;;;                               condition it failed with
;;;
;;; Each expected value is one the code under test cannot produce by failing.
;;; SRFI-64 turns a raise in the actual expression into #f, so no expected
;;; value here is #f, and every refusal is compared against a no-raise
;;; sentinel. Each fixture field holds a value no other field holds, so an
;;; accessor that read the wrong field cannot pass.
(import (rnrs)
        (rnrs mutable-pairs)
        (srfi :64)
        (curl-testing)
        (curl private libcurl-info)
        (curl private conditions))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; The simple runner names a failing test but not its values. Print both.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (display "  expected: ")
        (write (test-result-ref r 'expected-value))
        (newline)
        (display "  actual:   ")
        (write (test-result-ref r 'actual-value))
        (newline)))))

;; raised : (-> Any) -> Any
;; What THUNK raised: (assertion-violation WHO IRRITANTS) for an assertion
;; violation, (other-raise TEXT) for anything else, and the symbol no-raise
;; if THUNK returned.
(define (raised thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e)
                  (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'other-raise (describe e))))
    (thunk)
    'no-raise))

;; kinds : Any -> (List Boolean Boolean Boolean Boolean)
;; Which of the four predicates hold for C: error?, curl-error?,
;; curl-library-unavailable? and curl-wrong-thread?.
(define (kinds c)
  (list (error? c) (curl-error? c) (curl-library-unavailable? c)
        (curl-wrong-thread? c)))

;; A report whose every field differs from the refusal's fields below.
(define a-report
  (make-libcurl-info "/opt/curl/lib/libcurl.so.4.8.0" 'guix-profile "7.84.0" #x075400
                     #x40000005 '(ipv6 ssl threadsafe) "OpenSSL/3.0.2" "aarch64-unknown-linux-gnu"))

;; A refusal whose every field differs from every other field.
(define (a-library-unavailable)
  (make-curl-library-unavailable 'below-floor
                                 "/opt/curl/lib/libcurl.so.4"
                                 'override
                                 "libnghttp2.so.14: cannot open shared object file"
                                 '("/opt/curl/lib/libcurl.so.4" "/usr/lib/libcurl.so.4")
                                 a-report))

(test-begin "conditions")

;; --- &curl-error -----------------------------------------------------------

(test-equal "make-curl-error: an error and a curl-error, and neither subtype"
  '(#t #t #f #f)
  (kinds (make-curl-error)))

;; --- &curl-library-unavailable ----------------------------------------------

(test-equal "library-unavailable: an error and a curl-error, not a wrong-thread"
  '(#t #t #t #f)
  (kinds (a-library-unavailable)))

(test-equal "library-unavailable carries its reason, path, source, detail, candidates and library"
  '(below-floor
    "/opt/curl/lib/libcurl.so.4"
    override
    "libnghttp2.so.14: cannot open shared object file"
    ("/opt/curl/lib/libcurl.so.4" "/usr/lib/libcurl.so.4")
    the-report)
  (let ((c (a-library-unavailable)))
    (list (curl-library-unavailable-reason c)
          (curl-library-unavailable-path c)
          (curl-library-unavailable-source c)
          (curl-library-unavailable-detail c)
          (curl-library-unavailable-candidates c)
          (let ((library (curl-library-unavailable-library c)))
            (if (eq? library a-report) 'the-report library)))))

(test-equal "library-unavailable's library may be #f: no report was read"
  'no-report
  (let ((library (curl-library-unavailable-library
                  (make-curl-library-unavailable 'not-found #f #f #f '() #f))))
    (if (eq? library #f) 'no-report library)))

(test-equal "the reasons are exactly ADR-0002's and ADR-0003's six, in order"
  '(invalid-override not-found load-failed below-floor no-ssl missing-api)
  curl-library-unavailable-reasons)

;; Written out here, not taken from the export: a reason dropped from the
;; exported list must fail this test, not shrink it.
(test-equal "the constructor takes each of the six reasons"
  '(invalid-override not-found load-failed below-floor no-ssl missing-api)
  (map (lambda (reason)
         (curl-library-unavailable-reason
          (make-curl-library-unavailable reason #f #f #f '() #f)))
       '(invalid-override not-found load-failed below-floor no-ssl missing-api)))

(test-equal "the constructor refuses a symbol that is not a reason"
  '(assertion-violation make-curl-library-unavailable (library-missing))
  (raised (lambda ()
            (make-curl-library-unavailable 'library-missing #f #f #f '() #f))))

(test-equal "the constructor refuses a reason spelled as a string"
  '(assertion-violation make-curl-library-unavailable ("not-found"))
  (raised (lambda ()
            (make-curl-library-unavailable "not-found" #f #f #f '() #f))))

(test-equal "the constructor refuses a library that is neither a libcurl-info nor #f"
  '(assertion-violation make-curl-library-unavailable ("8.20.0"))
  (raised (lambda ()
            (make-curl-library-unavailable 'below-floor "/usr/lib/libcurl.so.4" 'system
                                           "7.81.0" '() "8.20.0"))))

;; --- &curl-wrong-thread ------------------------------------------------------

(test-equal "wrong-thread: an error and a curl-error, not a library-unavailable"
  '(#t #t #f #t)
  (kinds (make-curl-wrong-thread 'curl-multi-poll 3 7)))

(test-equal "wrong-thread carries who, expected and actual"
  '(curl-multi-poll 3 7)
  (let ((c (make-curl-wrong-thread 'curl-multi-poll 3 7)))
    (list (curl-wrong-thread-who c)
          (curl-wrong-thread-expected c)
          (curl-wrong-thread-actual c))))

;; --- &curl-embedded-nul ----------------------------------------------------------

(test-equal "embedded-nul: an error and a curl-error, not a library-unavailable nor a wrong-thread, carrying its string"
  '(#t #t #f #f #t "a\x0;b")
  (let ((c (make-curl-embedded-nul "a\x0;b")))
    (append (kinds c) (list (curl-embedded-nul? c) (curl-embedded-nul-string c)))))

;; --- &curl-url-error ---------------------------------------------------------------

(test-equal "url-error: an error and a curl-error, nothing else, carrying input, reason, code and message"
  '(#t #t #f #f #f #t "http://x:99999/" bad-port-number 4 "Port number was not a decimal number")
  (let ((c (make-curl-url-error "http://x:99999/" 'bad-port-number 4
                                "Port number was not a decimal number")))
    (append (kinds c) (list (curl-embedded-nul? c) (curl-url-error? c)
                            (curl-url-error-input c) (curl-url-error-reason c)
                            (curl-url-error-code c) (curl-url-error-message c)))))

(test-equal "the url-error constructor checks nothing, so a later libcurl's refusal always reaches the caller: odd values come back as given"
  '(no-input-string #f 31 #f)
  (let ((c (make-curl-url-error 'no-input-string #f 31 #f)))
    (list (curl-url-error-input c) (curl-url-error-reason c) (curl-url-error-code c)
          (curl-url-error-message c))))

;; Written out here, from 7.85.0's curl/urlapi.h, not read from
;; curlue-codes: a list shifted by one would shift the names the other
;; side reads too.
(test-equal "curl-url-code-reason names each of the floor's 30 CURLUcodes, 0 to 29"
  '(ok bad-handle bad-partpointer malformed-input bad-port-number unsupported-scheme
    urldecode out-of-memory user-not-allowed unknown-part no-scheme no-user no-password
    no-options no-host no-port no-query no-fragment no-zoneid bad-file-url bad-fragment
    bad-hostname bad-ipv6 bad-login bad-password bad-path bad-query bad-scheme
    bad-slashes bad-user)
  (let loop ((code 29) (names '()))
    (if (< code 0)
        names
        (loop (- code 1) (cons (or (curl-url-code-reason code) (list 'unnamed code)) names)))))

(test-equal "curl-url-code-reason: a code the floor lacks, 30 and 31 in 8.20.0, and what is no code, have no name, and raise nothing"
  '(unnamed unnamed unnamed unnamed unnamed unnamed)
  (map (lambda (code)
         (guard (e (#t (list 'raised (describe e))))
           (or (curl-url-code-reason code) 'unnamed)))
       (list 30 31 -1 'malformed-input "3" 3.0)))

;; --- &curl-request-error ---------------------------------------------------------------

;; Written out here, not read from the export: a reason dropped from the
;; exported list must fail these tests, not shrink them.
(define request-reasons
  '(embedded-nul line-break not-latin-1 not-a-token surrounding-whitespace duplicates-field
    framing-header owned-option unsupported-type unknown-option repeated-option unknown-key
    repeated-key missing-value body-not-allowed pkcs11-url environment-override keychain-fallback
    stream-with-rounds body-length-without-stream body-length-mismatch prior-knowledge-over-https
    credentials-bytes credentials-empty credentials-beside-userinfo credentials-beside-authorization
    digest-with-stream prior-knowledge-through-proxy proxy-url proxy-scheme proxy-url-parts
    proxy-authorization-header proxy-tls-without-https-proxy proxy-tls-in-tls
    https-proxy-unsupported cookie-line cookie-jar-engine cookie-jar-closed cookie-beside-jar
    part-bytes part-empty multipart-empty multipart-content-type part-file multipart-unsupported))

(test-equal "request-error: an error and a curl-error, and none of the other kinds, carrying its field, value and reason"
  '(#t #t #f #f #f #f #t #f header-value "a\rb" line-break)
  (let ((c (make-curl-request-error 'header-value "a\rb" 'line-break)))
    (append (kinds c)
            (list (curl-embedded-nul? c) (curl-url-error? c) (curl-request-error? c)
                  (curl-transfer-error? c)
                  (curl-request-error-field c) (curl-request-error-value c)
                  (curl-request-error-reason c)))))

(test-equal "the request-error reasons are exactly embedded-nul, line-break, not-latin-1, not-a-token, surrounding-whitespace, duplicates-field, framing-header, owned-option, unsupported-type, unknown-option, repeated-option, unknown-key, repeated-key, missing-value, body-not-allowed, pkcs11-url, environment-override, keychain-fallback, stream-with-rounds, body-length-without-stream, body-length-mismatch, prior-knowledge-over-https, credentials-bytes, credentials-empty, credentials-beside-userinfo, credentials-beside-authorization, digest-with-stream, prior-knowledge-through-proxy, proxy-url, proxy-scheme, proxy-url-parts, proxy-authorization-header, proxy-tls-without-https-proxy, proxy-tls-in-tls, https-proxy-unsupported, cookie-line, cookie-jar-engine, cookie-jar-closed, cookie-beside-jar, part-bytes, part-empty, multipart-empty, multipart-content-type, part-file and multipart-unsupported, in order"
  request-reasons
  curl-request-error-reasons)

(test-equal "the request-error constructor takes each of the forty-five reasons"
  request-reasons
  (map (lambda (reason)
         (curl-request-error-reason (make-curl-request-error 'user-agent "x" reason)))
       request-reasons))

(test-equal "the request-error constructor refuses a symbol that is no reason, a reason spelled as a string, and #f"
  '((assertion-violation make-curl-request-error (scheme-not-http))
    (assertion-violation make-curl-request-error ("line-break"))
    (assertion-violation make-curl-request-error (#f)))
  (map (lambda (reason)
         (raised (lambda () (make-curl-request-error 'header-name "x" reason))))
       (list 'scheme-not-http "line-break" #f)))

;; --- &curl-transfer-error --------------------------------------------------------------

(define transfer-reasons
  '(perform-failed body-limit callback-raised setopt-failed unknown-option no-handle
    cancelled stopped pause-failed body-length-mismatch body-not-replayable header-limit
    part-file mime-failed))

;; A recorded object no field could hand back by another route.
(define the-raised (list 'raised-in-the-callable))

(test-equal "transfer-error: an error and a curl-error, and none of the other kinds, carrying its reason, code, option, strerror, error buffer, recorded object, request size and CONNECT status"
  '(#t #t #f #f #f #f #f #t callback-raised 23 "MAXFILESIZE_LARGE" "Failed writing received data to disk/application" "Failure writing output to destination" the-raised 75 407)
  (let ((c (make-curl-transfer-error 'callback-raised 23 "MAXFILESIZE_LARGE"
                                     "Failed writing received data to disk/application"
                                     "Failure writing output to destination" the-raised 75 407)))
    (append (kinds c)
            (list (curl-embedded-nul? c) (curl-url-error? c) (curl-request-error? c)
                  (curl-transfer-error? c)
                  (curl-transfer-error-reason c) (curl-transfer-error-code c)
                  (curl-transfer-error-option c) (curl-transfer-error-strerror c)
                  (curl-transfer-error-error-buffer c)
                  (let ((r (curl-transfer-error-recorded c))) (if (eq? r the-raised) 'the-raised r))
                  (curl-transfer-error-request-size c) (curl-transfer-error-connect-code c)))))

(test-equal "the transfer-error reasons are exactly perform-failed, body-limit, callback-raised, setopt-failed, unknown-option, no-handle, cancelled, stopped, pause-failed, body-length-mismatch, body-not-replayable, header-limit, part-file and mime-failed, in order"
  transfer-reasons
  curl-transfer-error-reasons)

(test-equal "the transfer-error constructor takes each of the fourteen reasons, with #f in every other field"
  (map (lambda (reason) (list reason #f #f #f #f 'no-recorded #f #f)) transfer-reasons)
  (map (lambda (reason)
         (let ((c (make-curl-transfer-error reason #f #f #f #f #f #f #f)))
           (list (curl-transfer-error-reason c) (curl-transfer-error-code c)
                 (curl-transfer-error-option c) (curl-transfer-error-strerror c)
                 (curl-transfer-error-error-buffer c)
                 (if (eq? (curl-transfer-error-recorded c) #f) 'no-recorded 'recorded)
                 (curl-transfer-error-request-size c) (curl-transfer-error-connect-code c))))
       transfer-reasons))

(test-equal "the transfer-error constructor refuses a symbol that is no reason, a reason spelled as a string, and #f"
  '((assertion-violation make-curl-transfer-error (timed-out))
    (assertion-violation make-curl-transfer-error ("body-limit"))
    (assertion-violation make-curl-transfer-error (#f)))
  (map (lambda (reason)
         (raised (lambda () (make-curl-transfer-error reason 28 #f #f #f #f 0 #f))))
       (list 'timed-out "body-limit" #f)))

;; --- the classes (ADR-0022) -------------------------------------------------------------

;; code-rows : (Listof (List Integer Symbol))
;; Every CURLcode from 0 to 101, with its class, or none, settled against
;; curl's description of each code in libcurl-errors (8.23.0). Written out
;; here, never read from the library's table, so a code moved there fails
;; here, by that code.
(define code-rows
  '((0 none) (1 protocol) (2 none) (3 none) (4 none) (5 connect) (6 connect) (7 connect)
    (8 protocol) (9 none) (10 none) (11 none) (12 none) (13 none) (14 none) (15 none)
    (16 protocol) (17 none) (18 send-receive) (19 none) (20 none) (21 none) (22 none) (23 none)
    (24 none) (25 none) (26 none) (27 none) (28 timeout) (29 none) (30 none) (31 none)
    (32 none) (33 none) (34 none) (35 tls) (36 none) (37 none) (38 none) (39 none) (40 none)
    (41 none) (42 none) (43 none) (44 none) (45 connect) (46 none) (47 none) (48 none)
    (49 none) (50 none) (51 none) (52 send-receive) (53 tls) (54 tls) (55 send-receive)
    (56 send-receive) (57 none) (58 tls) (59 tls) (60 tls) (61 protocol) (62 none)
    (63 too-large) (64 tls) (65 none) (66 tls) (67 none) (68 none) (69 none) (70 none)
    (71 none) (72 none) (73 none) (74 none) (75 none) (76 none) (77 tls) (78 none) (79 none)
    (80 tls) (81 none) (82 tls) (83 tls) (84 none) (85 none) (86 none) (87 none) (88 none)
    (89 none) (90 tls) (91 tls) (92 protocol) (93 none) (94 none) (95 protocol) (96 connect)
    (97 connect) (98 tls) (99 none) (100 too-large) (101 tls)))

;; class-predicates : (Listof (Pairof Symbol (Any -> Boolean)))
(define class-predicates
  (list (cons 'timeout curl-timeout?) (cons 'connect curl-connect-error?)
        (cons 'send-receive curl-send-receive-error?) (cons 'tls curl-tls-error?)
        (cons 'protocol curl-protocol-error?) (cons 'too-large curl-too-large?)))

;; classes-of : Any -> (Listof Symbol)
;; Every class whose predicate holds for C, in class-predicates' order: one
;; for a classed condition, none for the base type.
(define (classes-of c)
  (map car (filter (lambda (p) ((cdr p) c)) class-predicates)))

;; class-of : Any -> Symbol
;; C's one class, none for the base type, or (several ...) when more than
;; one predicate holds.
(define (class-of c)
  (let ((found (classes-of c)))
    (cond ((null? found) 'none)
          ((null? (cdr found)) (car found))
          (else (cons 'several found)))))

(test-equal "code-rows is 0 to 101, each once, in order"
  (let loop ((n 101) (found '())) (if (< n 0) found (loop (- n 1) (cons n found))))
  (map car code-rows))

(test-equal "curl-code-class answers each code's class, written out, from 0 to 101"
  code-rows
  (map (lambda (row) (list (car row) (or (curl-code-class (car row)) 'none))) code-rows))

(test-equal "curl-code-class: a code past the table, 102 and 999, what is no code, -1, 28.0, \"28\", the symbol timeout and #f, have no class, and raise nothing"
  '(none none none none none none none)
  (map (lambda (code)
         (guard (e (#t (list 'raised (describe e))))
           (or (curl-code-class code) 'none)))
       (list 102 999 -1 28.0 "28" 'timeout #f)))

(test-equal "a perform-failed of each code from 0 to 101, and of 102 and 999, raises its class, the base type for none; every one is a transfer-error carrying its code"
  (append code-rows '((102 none) (999 none)))
  (map (lambda (code)
         (let ((c (make-classed-transfer-error 'perform-failed code #f #f #f #f 0 #f)))
           (list (if (and (curl-transfer-error? c) (eqv? (curl-transfer-error-code c) code))
                     code
                     (list 'not-a-transfer-error-of code))
                 (class-of c))))
       (append (map car code-rows) '(102 999))))

(test-equal "the class follows the code for perform-failed alone: body-limit and header-limit are too-large whatever the code, 23, 28 or none; every other reason raises the base type, a setopt-failed, callback-raised, pause-failed, body-length-mismatch, body-not-replayable, part-file or mime-failed whose code a class names among them"
  '((perform-failed (timeout connect send-receive tls protocol too-large none none))
    (body-limit (too-large too-large too-large too-large too-large too-large too-large too-large))
    (callback-raised (none none none none none none none none))
    (setopt-failed (none none none none none none none none))
    (unknown-option (none none none none none none none none))
    (no-handle (none none none none none none none none))
    (cancelled (none none none none none none none none))
    (stopped (none none none none none none none none))
    (pause-failed (none none none none none none none none))
    (body-length-mismatch (none none none none none none none none))
    (body-not-replayable (none none none none none none none none))
    (header-limit (too-large too-large too-large too-large too-large too-large too-large too-large))
    (part-file (none none none none none none none none))
    (mime-failed (none none none none none none none none)))
  (map (lambda (reason)
         (list reason
               (map (lambda (code)
                      (class-of (make-classed-transfer-error reason code #f #f #f #f 0 #f)))
                    (list 28 7 56 60 1 63 23 #f))))
       transfer-reasons))

(test-equal "each class is a transfer-error and a curl-error, carrying every base field, the request size and the CONNECT status among them"
  (map (lambda (row)
         (list (car row) #t #t #t 'perform-failed (cadr row) "OPT" "strerror" "buffer" 'the-raised 79 503))
       '((timeout 28) (connect 7) (send-receive 56) (tls 60) (protocol 8) (too-large 100)))
  (map (lambda (row)
         (let ((c ((cadr row) 'perform-failed (caddr row) "OPT" "strerror" "buffer" the-raised 79 503)))
           (list (class-of c) (error? c) (curl-error? c) (curl-transfer-error? c)
                 (curl-transfer-error-reason c) (curl-transfer-error-code c)
                 (curl-transfer-error-option c) (curl-transfer-error-strerror c)
                 (curl-transfer-error-error-buffer c)
                 (if (eq? (curl-transfer-error-recorded c) the-raised) 'the-raised 'other)
                 (curl-transfer-error-request-size c) (curl-transfer-error-connect-code c))))
       (list (list 'timeout make-curl-timeout 28) (list 'connect make-curl-connect-error 7)
             (list 'send-receive make-curl-send-receive-error 56) (list 'tls make-curl-tls-error 60)
             (list 'protocol make-curl-protocol-error 8) (list 'too-large make-curl-too-large 100))))

(test-equal "each class's constructor refuses a reason it does not take, and a code it does not name; too-large alone takes body-limit and header-limit, with any code"
  '((assertion-violation make-curl-timeout (body-limit 28))
    (assertion-violation make-curl-timeout (perform-failed 7))
    (assertion-violation make-curl-timeout (setopt-failed 28))
    (assertion-violation make-curl-connect-error (perform-failed 28))
    (assertion-violation make-curl-connect-error (cancelled #f))
    (assertion-violation make-curl-send-receive-error (perform-failed 60))
    (assertion-violation make-curl-send-receive-error (callback-raised 56))
    (assertion-violation make-curl-tls-error (perform-failed 56))
    (assertion-violation make-curl-tls-error (body-limit 60))
    (assertion-violation make-curl-protocol-error (perform-failed 102))
    (assertion-violation make-curl-protocol-error (no-handle 1))
    (assertion-violation make-curl-too-large (perform-failed 23))
    (assertion-violation make-curl-too-large (callback-raised 23))
    (assertion-violation make-curl-tls-error (header-limit 60))
    (assertion-violation make-curl-send-receive-error (header-limit 56))
    too-large too-large too-large too-large too-large)
  (append
   (map (lambda (args)
          (raised (lambda () ((car args) (cadr args) (caddr args) #f #f #f #f 0 #f))))
        (list (list make-curl-timeout 'body-limit 28) (list make-curl-timeout 'perform-failed 7)
              (list make-curl-timeout 'setopt-failed 28)
              (list make-curl-connect-error 'perform-failed 28)
              (list make-curl-connect-error 'cancelled #f)
              (list make-curl-send-receive-error 'perform-failed 60)
              (list make-curl-send-receive-error 'callback-raised 56)
              (list make-curl-tls-error 'perform-failed 56) (list make-curl-tls-error 'body-limit 60)
              (list make-curl-protocol-error 'perform-failed 102)
              (list make-curl-protocol-error 'no-handle 1)
              (list make-curl-too-large 'perform-failed 23)
              (list make-curl-too-large 'callback-raised 23)
              (list make-curl-tls-error 'header-limit 60)
              (list make-curl-send-receive-error 'header-limit 56)))
   (map (lambda (code) (class-of (make-curl-too-large 'body-limit code #f #f #f #f 0 #f)))
        (list 23 #f))
   (map (lambda (code) (class-of (make-curl-too-large 'header-limit code #f #f #f #f 0 #f)))
        (list 23 0 #f))))

(test-equal "make-classed-transfer-error refuses a symbol that is no reason, a reason spelled as a string, and #f"
  '((assertion-violation make-classed-transfer-error (timed-out))
    (assertion-violation make-classed-transfer-error ("perform-failed"))
    (assertion-violation make-classed-transfer-error (#f)))
  (map (lambda (reason)
         (raised (lambda () (make-classed-transfer-error reason 28 #f #f #f #f 0 #f))))
       (list 'timed-out "perform-failed" #f)))

(test-equal "no other kind is of a class: a request-error, an engine-error, a url-error, a curl-error and the base transfer-error are none"
  '(none none none none none)
  (map class-of
       (list (make-curl-request-error 'header-value "a\rb" 'line-break)
             (make-curl-engine-error 'stopped #f)
             (make-curl-url-error "x" #f #f #f)
             (make-curl-error)
             (make-curl-transfer-error 'perform-failed 28 #f #f #f #f 0 #f))))

;; --- &curl-engine-error ---------------------------------------------------------------

;; Written out here, not read from the export.
(define engine-reasons '(stopped failed))

;; A condition the engine failed with, which no other field could hand back.
(define the-failure (list 'raised-in-the-loop))

(test-equal "engine-error: an error and a curl-error, and none of the other kinds, carrying its reason and the condition it failed with"
  '(#t #t #f #f #f #f #f #f #t failed the-failure)
  (let ((c (make-curl-engine-error 'failed the-failure)))
    (append (kinds c)
            (list (curl-embedded-nul? c) (curl-url-error? c) (curl-request-error? c)
                  (curl-transfer-error? c) (curl-engine-error? c)
                  (curl-engine-error-reason c)
                  (let ((r (curl-engine-error-condition c))) (if (eq? r the-failure) 'the-failure r))))))

(test-equal "no other kind is an engine-error"
  '(#f #f #f)
  (list (curl-engine-error? (make-curl-transfer-error 'stopped #f #f #f #f #f #f #f))
        (curl-engine-error? (make-curl-request-error 'header-value "a\rb" 'line-break))
        (curl-engine-error? (make-curl-error))))

(test-equal "the engine-error reasons are exactly stopped and failed, in order"
  engine-reasons
  curl-engine-error-reasons)

(test-equal "the engine-error constructor takes each of the two reasons"
  (list '(stopped no-condition) '(failed the-failure))
  (map (lambda (reason condition)
         (let ((c (make-curl-engine-error reason condition)))
           (list (curl-engine-error-reason c)
                 (cond ((not (curl-engine-error-condition c)) 'no-condition)
                       ((eq? (curl-engine-error-condition c) the-failure) 'the-failure)
                       (else (curl-engine-error-condition c))))))
       engine-reasons (list #f the-failure)))

(test-equal "the engine-error constructor refuses a symbol that is no reason, a reason spelled as a string, and #f"
  '((assertion-violation make-curl-engine-error (cancelled))
    (assertion-violation make-curl-engine-error ("failed"))
    (assertion-violation make-curl-engine-error (#f)))
  (map (lambda (reason)
         (raised (lambda () (make-curl-engine-error reason #f))))
       (list 'cancelled "failed" #f)))

;; --- a caller's value, as a refusal names it -------------------------

;; circular : List
;; A list whose last pair points back at its first.
(define circular (let ((l (list 1 2))) (set-cdr! (cdr l) l) l))

(test-equal "kind-of, written out: a string, a list, () among them, a number, exact and inexact, a boolean, a char, a symbol, a bytevector, a vector, a procedure, and anything else, a hashtable"
  '(string list list number number boolean char symbol bytevector vector procedure other)
  (map kind-of (list "s" '(a) '() 5 1.5 #t #\a 'x (make-bytevector 1 0) (vector 1) car (make-eq-hashtable))))

(test-equal "shown-value, written out against the whole complement of what it shows: a symbol, a number, a boolean, a char, (), and a proper list of them, a policy's statuses or methods, as given; a string, a proxy URL among them, a list holding a string, credentials among them, an improper list, a circular one, a bytevector, a vector, a procedure and a hashtable by their kind"
  (list 'x 5 #f #\a '() '(429 503) '(get post)
        '(kind string) '(kind list) '(kind list) '(kind list) '(kind bytevector) '(kind vector)
        '(kind procedure) '(kind other))
  (map shown-value (list 'x 5 #f #\a '() '(429 503) '(get post)
                         "http://u:Pr0xyS3cr3t@h/" '(basic "alice" "Pr0xyS3cr3t") '(1 . 2) circular
                         (make-bytevector 1 0) (vector "p") car (make-eq-hashtable))))

(test-equal "shown-key, written out: a symbol as given; every other kind by its kind, a number's and a boolean's among them"
  '(proxy (kind string) (kind list) (kind number) (kind boolean) (kind char) (kind list))
  (map shown-key (list 'proxy "http://u:Pr0xyS3cr3t@h/" '(basic "alice" "Pr0xyS3cr3t") 5 #f #\a '())))

(test-end "conditions")

(exit (suite-exit-status runner))
