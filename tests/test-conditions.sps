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

(test-end "conditions")

(exit (suite-exit-status runner))
