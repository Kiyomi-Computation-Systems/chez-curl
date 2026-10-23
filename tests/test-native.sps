#!r6rs
;;; The suite for (curl private native) in a process of its own: it imports
;;; (curl) and calls loaded-libcurl here, so the whole load runs in this
;;; process. The memory gate (ADR-0014) runs every suite under Valgrind,
;;; and this is the one that runs the load there, the header probe's
;;; counted easy handle and slot included, each freed before the load
;;; returns.
;;;
;;; Importing (curl) runs the load before this suite's first line, so a
;;; refused libcurl kills it with Chez's message and exit 255, which make
;;; test names FAIL. tests/test-library-loading.sps covers refusals, each
;;; in a probe of its own.
;;;
;;; What the record reports is compared with what tests/libcurl-oracle.c
;;; reads from the same file, field by field. Each side is (FIELD . VALUE),
;;; so no expected value is #f: SRFI-64 makes #f of a raise in the actual
;;; expression.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) getenv)
        (curl-testing)
        (libcurl-oracle)
        (curl private counters)
        (only (curl private native) loaded-protocols)
        (curl))

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

(define info (loaded-libcurl))

;; The counts once the load has returned: its header probe's easy handle
;; and slot are counted, and freed before it returns (M2 plan, section 4.2).
(define counts-after-load (native-counts))

;; reported : Symbol -> Pair
;; The record's (FIELD . VALUE), for each of oracle-fields.
(define (reported field)
  (cons field
        (case field
          ((version) (libcurl-info-version info))
          ((version-num) (libcurl-info-version-number info))
          ((features) (libcurl-info-features info))
          ((ssl-version) (libcurl-info-ssl-version info))
          ((host) (libcurl-info-host info))
          (else 'no-accessor))))

;; oracle : (U Report (List 'no-oracle Symbol Any))
;; Read only from a record: anything else would raise here, before the
;; first test could name it.
(define oracle
  (if (libcurl-info? info)
      (libcurl-oracle getenv (libcurl-info-path info))
      (list 'no-oracle 'not-a-record info)))

;; read-by-oracle : Symbol -> Pair
;; The oracle's (FIELD . VALUE), or (FIELD no-oracle) when it failed.
(define (read-by-oracle field)
  (or (and (list? oracle) (for-all pair? oracle) (assq field oracle))
      (list field 'no-oracle)))

(test-begin "native")

(test-equal "loaded-libcurl answers a libcurl-info"
  'libcurl-info
  (if (libcurl-info? info) 'libcurl-info info))

(test-equal "every native count is zero once the load has returned: the header probe freed its handle and its slot"
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0))
  counts-after-load)

(test-equal "loaded-libcurl answers the same record at every call"
  'same
  (if (eq? (loaded-libcurl) info) 'same 'different))

;; A record that record-rtd opens can be rebuilt from its type: one holding
;; any path, version and features, and answering libcurl-info? true. Opaque,
;; it raises instead. The expected value names what was raised, and a
;; no-raise sentinel the raise cannot produce.
(test-equal "the report is opaque: record-rtd on a genuine one raises an assertion violation"
  '(assertion-violation record-rtd)
  (guard (e ((and (assertion-violation? e) (who-condition? e))
             (list 'assertion-violation (condition-who e)))
            (#t (list 'other-raise (describe e))))
    (list 'no-raise (record-type-name (record-rtd info)))))

(test-equal "the C oracle read the loaded libcurl"
  'read
  (if (eq? (car oracle) 'no-oracle) oracle 'read))

(for-each
 (lambda (field)
   (test-equal (string-append "the record's " (symbol->string field) " is the C oracle's")
     (read-by-oracle field)
     (reported field)))
 oracle-fields)

;; The protocol list native reads, every entry in its place, against the
;; list C reads from the same file: a reading that skipped the first entry,
;; or the last, would still hold http and https.
(define protocols-oracle
  (if (libcurl-info? info)
      (libcurl-protocols-oracle getenv (libcurl-info-path info))
      (list 'no-oracle 'not-a-record info)))

(test-equal "loaded-protocols is the protocol list the C oracle reads, in order, every entry"
  (list 'protocols protocols-oracle)
  (list 'protocols (loaded-protocols)))

(test-equal "the C oracle read a protocol list with http and https in it"
  'read
  (if (and (list? protocols-oracle) (member "http" protocols-oracle) (member "https" protocols-oracle))
      'read
      protocols-oracle))

(test-end "native")

(exit (suite-exit-status runner))
