#!r6rs
;;; The suite for (curl private conditions): chez-curl's condition types, all
;;; under &curl-error (harness plan §1).
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
;;;   &curl-request-error         a request's field refused before anything
;;;                               native is made, with one of four reasons
;;;   &curl-transfer-error        a blocking transfer failed, with one of six
;;;                               reasons, its code, option, libcurl's texts
;;;                               and what the write callable recorded
;;;                               (M2 plan, section 5.3)
;;;
;;; Each expected value is one the code under test cannot produce by failing.
;;; SRFI-64 turns a raise in the actual expression into #f, so no expected
;;; value here is #f, and every refusal is compared against a no-raise
;;; sentinel. Each fixture field holds a value no other field holds, so an
;;; accessor that read the wrong field cannot pass.
(import (rnrs)
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
    framing-header owned-option unsupported-type))

(test-equal "request-error: an error and a curl-error, and none of the other kinds, carrying its field, value and reason"
  '(#t #t #f #f #f #f #t #f header-value "a\rb" line-break)
  (let ((c (make-curl-request-error 'header-value "a\rb" 'line-break)))
    (append (kinds c)
            (list (curl-embedded-nul? c) (curl-url-error? c) (curl-request-error? c)
                  (curl-transfer-error? c)
                  (curl-request-error-field c) (curl-request-error-value c)
                  (curl-request-error-reason c)))))

(test-equal "the request-error reasons are exactly embedded-nul, line-break, not-latin-1, not-a-token, surrounding-whitespace, duplicates-field, framing-header, owned-option and unsupported-type, in order"
  request-reasons
  curl-request-error-reasons)

(test-equal "the request-error constructor takes each of the nine reasons"
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
  '(perform-failed body-limit callback-raised setopt-failed unknown-option no-handle))

;; A recorded object no field could hand back by another route.
(define the-raised (list 'raised-in-the-callable))

(test-equal "transfer-error: an error and a curl-error, and none of the other kinds, carrying its reason, code, option, strerror, error buffer and recorded object"
  '(#t #t #f #f #f #f #f #t callback-raised 23 "MAXFILESIZE_LARGE" "Failed writing received data to disk/application" "Failure writing output to destination" the-raised)
  (let ((c (make-curl-transfer-error 'callback-raised 23 "MAXFILESIZE_LARGE"
                                     "Failed writing received data to disk/application"
                                     "Failure writing output to destination" the-raised)))
    (append (kinds c)
            (list (curl-embedded-nul? c) (curl-url-error? c) (curl-request-error? c)
                  (curl-transfer-error? c)
                  (curl-transfer-error-reason c) (curl-transfer-error-code c)
                  (curl-transfer-error-option c) (curl-transfer-error-strerror c)
                  (curl-transfer-error-error-buffer c)
                  (let ((r (curl-transfer-error-recorded c))) (if (eq? r the-raised) 'the-raised r))))))

(test-equal "the transfer-error reasons are exactly perform-failed, body-limit, callback-raised, setopt-failed, unknown-option and no-handle, in order"
  transfer-reasons
  curl-transfer-error-reasons)

(test-equal "the transfer-error constructor takes each of the six reasons, with #f in every other field"
  (map (lambda (reason) (list reason #f #f #f #f 'no-recorded)) transfer-reasons)
  (map (lambda (reason)
         (let ((c (make-curl-transfer-error reason #f #f #f #f #f)))
           (list (curl-transfer-error-reason c) (curl-transfer-error-code c)
                 (curl-transfer-error-option c) (curl-transfer-error-strerror c)
                 (curl-transfer-error-error-buffer c)
                 (if (eq? (curl-transfer-error-recorded c) #f) 'no-recorded 'recorded))))
       transfer-reasons))

(test-equal "the transfer-error constructor refuses a symbol that is no reason, a reason spelled as a string, and #f"
  '((assertion-violation make-curl-transfer-error (timed-out))
    (assertion-violation make-curl-transfer-error ("body-limit"))
    (assertion-violation make-curl-transfer-error (#f)))
  (map (lambda (reason)
         (raised (lambda () (make-curl-transfer-error reason 28 #f #f #f #f))))
       (list 'timed-out "body-limit" #f)))

(test-end "conditions")

(exit (suite-exit-status runner))
