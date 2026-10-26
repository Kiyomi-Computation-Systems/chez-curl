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
        (only (chezscheme) getenv fork-thread make-mutex with-mutex make-condition condition-wait
              condition-broadcast get-thread-id make-list)
        (curl-testing)
        (libcurl-oracle)
        (curl private counters)
        (curl private conditions)
        (curl private constants)
        (curl private memory)
        (only (curl private native) loaded-protocols curl-easy-option
              curl-easy-init curl-easy-cleanup curl-easy-setopt-long curl-easy-setopt-pointer
              curl-easy-setopt-off-t curl-easy-getinfo curl-easy-getinfo-long
              curl-easy-getinfo-string curl-easy-nextheader call-with-c-string
              curl-url curl-url-set curl-url-get curl-url-cleanup
              curl-slist-append curl-slist-free-all
              curl-multi-init curl-multi-cleanup curl-multi-add-handle curl-multi-remove-handle
              curl-multi-perform curl-multi-poll curl-multi-wakeup curl-multi-info-read)
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
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0))
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

;; --- each handle's thread (ADR-0012, decision 3) -------------------------------

;; The other thread: one thread, forked once, that runs each thunk handed
;; it, so the handles it makes are freed on the thread that made them.
(define worker-mx (make-mutex))
(define worker-cv (make-condition))
(define worker-job #f)                  ; a thunk waiting to run, or #f
(define worker-answer #f)               ; (answer A) once it ran
(fork-thread
 (lambda ()
   (let loop ()
     (let ((job (with-mutex worker-mx
                  (let w () (if worker-job worker-job (begin (condition-wait worker-cv worker-mx) (w)))))))
       (let ((a (guard (e (#t (list 'raised (describe e)))) (job))))
         (with-mutex worker-mx
           (set! worker-job #f)
           (set! worker-answer (list 'answer a))
           (condition-broadcast worker-cv))
         (unless (eq? a 'stop-the-worker) (loop)))))))

;; on-thread : (-> Any) -> Any
;; THUNK's answer, run on the other thread, or (raised TEXT).
(define (on-thread thunk)
  (with-mutex worker-mx
    (set! worker-answer #f)
    (set! worker-job thunk)
    (condition-broadcast worker-cv)
    (let w () (unless worker-answer (condition-wait worker-cv worker-mx) (w)))
    (cadr worker-answer)))

;; wrong-thread-of : (-> Any) -> Any
;; THUNK's &curl-wrong-thread as (WHO EXPECTED ACTUAL); (no-raise) when it
;; raised nothing; (raised TEXT) for anything else.
(define (wrong-thread-of thunk)
  (guard (e ((curl-wrong-thread? e)
             (list (curl-wrong-thread-who e) (curl-wrong-thread-expected e)
                   (curl-wrong-thread-actual e)))
            (#t (list 'raised (describe e))))
    (thunk)
    '(no-raise)))

;; assertion-of : (-> Any) -> Any
;; THUNK's assertion violation as (assertion-violation WHO); (no-raise) when
;; it raised nothing.
(define (assertion-of thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e))
             (list 'assertion-violation (condition-who e)))
            (#t (list 'raised (describe e))))
    (thunk)
    '(no-raise)))

;; Each kind of handle, made on a thread of its own, and that thread's id:
;; (THREAD EASY URL SLIST MULTI).
(define made-elsewhere
  (on-thread
   (lambda ()
     (list (get-thread-id) (curl-easy-init) (curl-url)
           (call-with-c-string "X-A: b" (lambda (a) (curl-slist-append 0 a)))
           (curl-multi-init)))))

(define (option-id name) (car (curl-easy-option name)))

;; Every exported procedure that takes a handle, called here on handles
;; another thread made, each with its who: written out, so a wrapper that
;; lost its check fails by name.
(test-equal "every exported native procedure that takes a handle, called on this thread with a handle another thread made, raises &curl-wrong-thread from its own name, carrying the maker's thread and this one"
  (let ((maker (car made-elsewhere)) (me (get-thread-id)))
    (map (lambda (who) (list who maker me))
         '(curl-easy-setopt curl-easy-setopt curl-easy-setopt curl-easy-getinfo curl-easy-getinfo
           curl-easy-getinfo curl-easy-nextheader curl-easy-cleanup
           curl-url-set curl-url-get curl-url-cleanup
           curl-slist-append curl-slist-free-all
           curl-multi-add-handle curl-multi-add-handle curl-multi-remove-handle curl-multi-perform
           curl-multi-poll curl-multi-info-read curl-multi-cleanup)))
  (if (and (list? made-elsewhere) (= (length made-elsewhere) 5) (integer? (car made-elsewhere)))
      (let ((easy (list-ref made-elsewhere 1)) (url (list-ref made-elsewhere 2))
            (slist (list-ref made-elsewhere 3)) (multi (list-ref made-elsewhere 4))
            (slot (foreign-block 8))
            (own-multi (curl-multi-init)))
        (let ((answers
               (list (wrong-thread-of (lambda () (curl-easy-setopt-long easy (option-id "NOSIGNAL") 1)))
                     (wrong-thread-of (lambda () (curl-easy-setopt-pointer easy (option-id "PRIVATE") 0)))
                     (wrong-thread-of (lambda () (curl-easy-setopt-off-t easy (option-id "MAXFILESIZE_LARGE") 1)))
                     (wrong-thread-of (lambda () (curl-easy-getinfo easy curlinfo-response-code slot)))
                     (wrong-thread-of (lambda () (curl-easy-getinfo-long easy curlinfo-response-code)))
                     (wrong-thread-of (lambda () (curl-easy-getinfo-string easy curlinfo-effective-url)))
                     (wrong-thread-of (lambda () (curl-easy-nextheader easy curlh-header -1 0)))
                     (wrong-thread-of (lambda () (curl-easy-cleanup easy)))
                     (wrong-thread-of (lambda () (call-with-c-string "http://a/"
                                                   (lambda (a) (curl-url-set url curlupart-url a 0)))))
                     (wrong-thread-of (lambda () (curl-url-get url curlupart-url 0)))
                     (wrong-thread-of (lambda () (curl-url-cleanup url)))
                     (wrong-thread-of (lambda () (call-with-c-string "X-B: c"
                                                   (lambda (a) (curl-slist-append slist a)))))
                     (wrong-thread-of (lambda () (curl-slist-free-all slist)))
                     (wrong-thread-of (lambda () (curl-multi-add-handle multi easy)))
                     ;; This thread's multi handle, the other's easy one: the
                     ;; second check refuses it.
                     (wrong-thread-of (lambda () (curl-multi-add-handle own-multi easy)))
                     (wrong-thread-of (lambda () (curl-multi-remove-handle multi easy)))
                     (wrong-thread-of (lambda () (curl-multi-perform multi slot)))
                     (wrong-thread-of (lambda () (curl-multi-poll multi 0)))
                     (wrong-thread-of (lambda () (curl-multi-info-read multi slot)))
                     (wrong-thread-of (lambda () (curl-multi-cleanup multi))))))
          (free-foreign-block! slot)
          (curl-multi-cleanup own-multi)
          answers))
      made-elsewhere))

;; A slot is its caller's counted block, an address: anything else is
;; refused before C, which would write through it.
(test-equal "curl-multi-perform and curl-multi-info-read refuse a slot that is no address, 0, -8 or a string, as assertion violations, before C writes through it"
  (append (make-list 3 '(assertion-violation curl-multi-perform))
          (make-list 3 '(assertion-violation curl-multi-info-read)))
  (let* ((multi (curl-multi-init))
         (answers (append
                   (map (lambda (slot) (assertion-of (lambda () (curl-multi-perform multi slot))))
                        (list 0 -8 "slot"))
                   (map (lambda (slot) (assertion-of (lambda () (curl-multi-info-read multi slot))))
                        (list 0 -8 "slot")))))
    (curl-multi-cleanup multi)
    answers))

;; curl_multi_wakeup alone may be called from any thread, on a live multi
;; handle; on anything else it is refused before C.
(test-equal "curl-multi-wakeup, from this thread, wakes a multi handle another thread made, CURLM_OK; and refuses an easy handle, and a multi handle freed, as assertion violations"
  (list curlm-ok '(assertion-violation curl-multi-wakeup) '(assertion-violation curl-multi-wakeup))
  (if (and (list? made-elsewhere) (= (length made-elsewhere) 5))
      (let ((easy (list-ref made-elsewhere 1)) (multi (list-ref made-elsewhere 4)))
        (let* ((live (guard (e (#t (list 'raised (describe e)))) (curl-multi-wakeup multi)))
               (not-multi (assertion-of (lambda () (curl-multi-wakeup easy))))
               (freed (begin (on-thread (lambda () (curl-multi-cleanup multi)))
                             (assertion-of (lambda () (curl-multi-wakeup multi))))))
          (list live not-multi freed)))
      made-elsewhere))

(test-equal "the handles freed on the thread that made them, every count is zero"
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0))
  (if (and (list? made-elsewhere) (= (length made-elsewhere) 5))
      (begin
        (on-thread (lambda ()
                     (curl-easy-cleanup (list-ref made-elsewhere 1))
                     (curl-url-cleanup (list-ref made-elsewhere 2))
                     (curl-slist-free-all (list-ref made-elsewhere 3))))
        (on-thread (lambda () 'stop-the-worker))
        (native-counts))
      made-elsewhere))

(test-end "native")

(exit (suite-exit-status runner))
