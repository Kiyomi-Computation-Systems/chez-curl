#!r6rs
;;; The suite for (curl private verify): ADR-0003's decisions about a loaded
;;; libcurl, made here on synthetic inputs.
;;;
;;;   check-version   the floor, 7.85.0 (#x075500), then CURL_VERSION_SSL
;;;   check-apis      the options API and the header API, probed at load
;;;   feature-names   the features word as names, for the report ADR-0002
;;;                   asks of every load
;;;
;;; The numbers are written out from curl/curl.h and curl/header.h, never
;;; taken from (curl private constants), so a wrong constant fails here.
;;;
;;; Both checks run after curl_version_info is read, so each takes the
;;; library's report as well, and every refusal carries it.
;;;
;;; Each expected value is one the code under test cannot produce by failing.
;;; SRFI-64 turns a raise in the actual expression into #f, so no expected
;;; value here is #f: every call goes through `outcome`, which names what
;;; was raised or returned.
(import (rnrs)
        (srfi :64)
        (curl-testing)
        (curl private conditions)
        (curl private libcurl-info)
        (curl private verify))

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

;; The report every call below passes. No field of it equals an argument
;; the checks take, so only the report itself can be carried as itself.
(define report
  (make-libcurl-info "/gnu/store/report-path/lib/libcurl.so.4" 'guix-home "report-version"
                     1 2 '(report-feature) "ReportTLS/0" "report-host"))

;; outcome : (-> Any) -> (U (List 'returned Any)
;;                          (List 'refused Symbol Any Any Any Any Any)
;;                          (List 'assertion-violation Any)
;;                          (List 'other-raise String))
;; What THUNK did: returned a value, raised &curl-library-unavailable (its
;; reason, path, source, detail, candidates, and the-report when it
;; carries the report, else what it carries), raised an assertion
;; violation (its who), or raised something else.
(define (outcome thunk)
  (guard (e ((curl-library-unavailable? e)
             (list 'refused
                   (curl-library-unavailable-reason e)
                   (curl-library-unavailable-path e)
                   (curl-library-unavailable-source e)
                   (curl-library-unavailable-detail e)
                   (curl-library-unavailable-candidates e)
                   (let ((library (curl-library-unavailable-library e)))
                     (if (eq? library report) 'the-report library))))
            ((and (assertion-violation? e) (who-condition? e))
             (list 'assertion-violation (condition-who e)))
            (#t (list 'other-raise (describe e))))
    (list 'returned (thunk))))

;; readable : (-> Any) -> Symbol
;; readable when THUNK raised &curl-library-unavailable with a who and a
;; message for the default handler to print, bare when it raised one
;; without, other-raise for anything else, no-raise when it returned.
(define (readable thunk)
  (guard (e ((curl-library-unavailable? e)
             (if (and (who-condition? e) (message-condition? e)) 'readable 'bare))
            (#t 'other-raise))
    (thunk)
    'no-raise))

;; Every feature bit curl/curl.h defines: 1<<0 to 1<<30.
(define all-features #x7FFFFFFF)
(define ssl #x4)

(define path "/usr/lib/aarch64-linux-gnu/libcurl.so.4")

(test-begin "verify")

;; --- check-version: the floor, then SSL --------------------------------------

(test-equal "the floor is 7.85.0, #x075500"
  #x075500
  libcurl-floor)

;; Every feature is set, so only the version can refuse.
(test-equal "check-version: the floor itself, #x075500, is accepted"
  '(returned #t)
  (outcome (lambda () (check-version "7.85.0" #x075500 all-features path 'system report))))

(test-equal "check-version: one below the floor, #x0754ff, is below-floor, with the version, path and source"
  `(refused below-floor ,path system "7.84.255" () the-report)
  (outcome (lambda () (check-version "7.84.255" #x0754ff all-features path 'system report))))

(test-equal "check-version: every feature but SSL is no-ssl, with the version, path and source"
  `(refused no-ssl ,path override "8.20.0" () the-report)
  (outcome (lambda () (check-version "8.20.0" #x081400 (- all-features ssl) path 'override report))))

(test-equal "check-version: SSL, 1<<2, alone is enough"
  '(returned #t)
  (outcome (lambda () (check-version "8.20.0" #x081400 ssl path 'override report))))

(test-equal "check-version: below the floor and without SSL, below-floor wins"
  `(refused below-floor ,path guix-home "7.81.0" () the-report)
  (outcome (lambda () (check-version "7.81.0" #x075100 0 path 'guix-home report))))

;; --- check-apis: the two probes ---------------------------------------------

;; 3 is CURLHE_NOHEADERS: what 8.20.0 answers on a fresh handle (ADR-0003).
(test-equal "check-apis: an option found and header code 3 are accepted"
  '(returned #t)
  (outcome (lambda () (check-apis #t 3 path 'guix-profile report))))

(test-equal "check-apis: no option by name is missing-api, naming curl_easy_option_by_name"
  `(refused missing-api ,path guix-profile "curl_easy_option_by_name" () the-report)
  (outcome (lambda () (check-apis #f 3 path 'guix-profile report))))

(test-equal "check-apis: header code 7, CURLHE_NOT_BUILT_IN, is missing-api, naming curl_easy_header"
  `(refused missing-api ,path guix-system "curl_easy_header" () the-report)
  (outcome (lambda () (check-apis #t 7 path 'guix-system report))))

(test-equal "check-apis: every other header code is accepted"
  '((returned #t) (returned #t) (returned #t) (returned #t) (returned #t)
    (returned #t) (returned #t) (returned #t) (returned #t))
  (map (lambda (code) (outcome (lambda () (check-apis #t code path 'system report))))
       '(0 1 2 3 4 5 6 8 99)))

(test-equal "check-apis: with both APIs missing, the option probe is named: it runs first"
  `(refused missing-api ,path system "curl_easy_option_by_name" () the-report)
  (outcome (lambda () (check-apis #f 7 path 'system report))))

;; 0 is truthy in Scheme: a NULL pointer passed as the answer would pass.
(test-equal "check-apis: the option probe's answer is a boolean, so a NULL pointer, 0, is refused"
  '(assertion-violation check-apis)
  (outcome (lambda () (check-apis 0 3 path 'system report))))

(test-equal "check-version and check-apis: every refusal carries a who and a message, for the default handler"
  '(readable readable readable readable)
  (list (readable (lambda () (check-version "7.84.255" #x0754ff all-features path 'system report)))
        (readable (lambda () (check-version "8.20.0" #x081400 0 path 'system report)))
        (readable (lambda () (check-apis #f 3 path 'system report)))
        (readable (lambda () (check-apis #t 7 path 'system report)))))

;; --- feature-names ----------------------------------------------------------

;; bits : Natural -> (Listof Natural)
;; 1<<0 to 1<<(N-1).
(define (bits n)
  (let loop ((i (- n 1)) (found '()))
    (if (< i 0) found (loop (- i 1) (cons (expt 2 i) found)))))

(define curl.h-features
  '(ipv6 kerberos4 ssl libz ntlm gssnegotiate debug asynchdns spnego largefile
    idn sspi conv curldebug tlsauth-srp ntlm-wb http2 gssapi kerberos5
    unix-sockets psl https-proxy multi-ssl brotli altsvc http3 zstd unicode hsts
    gsasl threadsafe))

(test-equal "feature-names: each bit alone names its own CURL_VERSION_ feature"
  (map list curl.h-features)
  (map feature-names (bits 31)))

(test-equal "feature-names: every bit set names every feature, in curl.h's order"
  curl.h-features
  (feature-names all-features))

(test-equal "feature-names: only the bits that are set"
  '(ipv6 ssl http2 threadsafe)
  (feature-names (+ #x1 #x4 #x10000 #x40000000)))

(test-equal "feature-names: a bit not in the table comes back as an integer, after the names"
  '(ssl #x80000000 #x200000000)
  (feature-names (+ #x4 #x80000000 #x200000000)))

(test-equal "feature-names: no bits, no names"
  '()
  (feature-names 0))

(test-end "verify")

(exit (suite-exit-status runner))
