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
              condition-broadcast get-thread-id make-list library-exports)
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
              curl-multi-perform curl-multi-poll curl-multi-wakeup curl-multi-info-read
              curl-share-init curl-share-setopt-int curl-share-cleanup
              curl-easy-getinfo-cookielist curl-slist-strings
              curl-easy-getinfo-off-t curl-multi-setopt-long curl-easy-pause
              curl-mime-init curl-mime-free curl-mime-add-part!)
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
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0))
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
;; (THREAD EASY URL SLIST MULTI SHARE MIME), the mime made with that easy
;; handle.
(define made-elsewhere
  (on-thread
   (lambda ()
     (let* ((easy (curl-easy-init)) (url (curl-url))
            (slist (call-with-c-string "X-A: b" (lambda (a) (curl-slist-append 0 a))))
            (multi (curl-multi-init)) (share (curl-share-init)) (mime (curl-mime-init easy)))
       (list (get-thread-id) easy url slist multi share mime)))))

;; made? : Any -> Boolean
(define (made? x) (and (list? x) (= (length x) 7) (integer? (car x))))

(define (option-id name) (car (curl-easy-option name)))

;; wrong-thread-rows : Natural ... -> (Listof (List Symbol Symbol (-> Any)))
;; The wrong-thread table: each exported procedure that takes a handle,
;; the who its refusal must name, written out, and a thunk calling it on
;; the handles another thread made, EASY to MIME, with SLOT and OWN-MULTI
;; this thread's. The exports check below reads the table's first column,
;; so a row dropped is an export no row calls, and fails there.
(define (wrong-thread-rows easy url slist multi share mime slot own-multi)
  (list (list 'curl-easy-setopt-long 'curl-easy-setopt
              (lambda () (curl-easy-setopt-long easy (option-id "NOSIGNAL") 1)))
        (list 'curl-easy-setopt-pointer 'curl-easy-setopt
              (lambda () (curl-easy-setopt-pointer easy (option-id "PRIVATE") 0)))
        (list 'curl-easy-setopt-off-t 'curl-easy-setopt
              (lambda () (curl-easy-setopt-off-t easy (option-id "MAXFILESIZE_LARGE") 1)))
        (list 'curl-easy-getinfo 'curl-easy-getinfo
              (lambda () (curl-easy-getinfo easy curlinfo-response-code slot)))
        (list 'curl-easy-getinfo-long 'curl-easy-getinfo
              (lambda () (curl-easy-getinfo-long easy curlinfo-response-code)))
        (list 'curl-easy-getinfo-string 'curl-easy-getinfo
              (lambda () (curl-easy-getinfo-string easy curlinfo-effective-url)))
        (list 'curl-easy-nextheader 'curl-easy-nextheader
              (lambda () (curl-easy-nextheader easy curlh-header -1 0)))
        (list 'curl-easy-cleanup 'curl-easy-cleanup (lambda () (curl-easy-cleanup easy)))
        (list 'curl-url-set 'curl-url-set
              (lambda () (call-with-c-string "http://a/" (lambda (a) (curl-url-set url curlupart-url a 0)))))
        (list 'curl-url-get 'curl-url-get (lambda () (curl-url-get url curlupart-url 0)))
        (list 'curl-url-cleanup 'curl-url-cleanup (lambda () (curl-url-cleanup url)))
        (list 'curl-slist-append 'curl-slist-append
              (lambda () (call-with-c-string "X-B: c" (lambda (a) (curl-slist-append slist a)))))
        (list 'curl-slist-free-all 'curl-slist-free-all (lambda () (curl-slist-free-all slist)))
        (list 'curl-multi-add-handle 'curl-multi-add-handle (lambda () (curl-multi-add-handle multi easy)))
        ;; This thread's multi handle, the other's easy one: the second
        ;; check refuses it.
        (list 'curl-multi-add-handle 'curl-multi-add-handle (lambda () (curl-multi-add-handle own-multi easy)))
        (list 'curl-multi-remove-handle 'curl-multi-remove-handle
              (lambda () (curl-multi-remove-handle multi easy)))
        (list 'curl-multi-perform 'curl-multi-perform (lambda () (curl-multi-perform multi slot)))
        (list 'curl-multi-poll 'curl-multi-poll (lambda () (curl-multi-poll multi 0)))
        (list 'curl-multi-info-read 'curl-multi-info-read (lambda () (curl-multi-info-read multi slot)))
        (list 'curl-multi-cleanup 'curl-multi-cleanup (lambda () (curl-multi-cleanup multi)))
        (list 'curl-share-setopt-int 'curl-share-setopt
              (lambda () (curl-share-setopt-int share curlshopt-share curl-lock-data-cookie)))
        (list 'curl-share-cleanup 'curl-share-cleanup (lambda () (curl-share-cleanup share)))
        (list 'curl-easy-getinfo-cookielist 'curl-easy-getinfo (lambda () (curl-easy-getinfo-cookielist easy)))
        (list 'curl-slist-strings 'curl-slist-strings (lambda () (curl-slist-strings slist)))
        (list 'curl-easy-getinfo-off-t 'curl-easy-getinfo
              (lambda () (curl-easy-getinfo-off-t easy curlinfo-request-size)))
        (list 'curl-multi-setopt-long 'curl-multi-setopt
              (lambda () (curl-multi-setopt-long multi curlmopt-max-total-connections 1)))
        (list 'curl-easy-pause 'curl-easy-pause (lambda () (curl-easy-pause easy 0)))
        ;; The other thread's easy handle: the mime would be this thread's,
        ;; of a handle it does not own.
        (list 'curl-mime-init 'curl-mime-init (lambda () (curl-mime-init easy)))
        (list 'curl-mime-add-part! 'curl-mime-add-part!
              (lambda () (curl-mime-add-part! mime "a" 'data (make-bytevector 1 98) #f #f)))
        (list 'curl-mime-free 'curl-mime-free (lambda () (curl-mime-free mime)))))

;; Every exported procedure that takes a handle, called here on handles
;; another thread made, each with its who: written out, so a wrapper that
;; lost its check fails by name.
(test-equal "every exported native procedure that takes a handle, called on this thread with a handle another thread made, raises &curl-wrong-thread from its own name, carrying the maker's thread and this one"
  (if (made? made-elsewhere)
      (let ((maker (car made-elsewhere)) (me (get-thread-id)))
        (map (lambda (row) (list (car row) (cadr row) maker me)) (wrong-thread-rows 0 0 0 0 0 0 0 0)))
      'made-elsewhere)
  (if (made? made-elsewhere)
      (let* ((easy (list-ref made-elsewhere 1)) (url (list-ref made-elsewhere 2))
             (slist (list-ref made-elsewhere 3)) (multi (list-ref made-elsewhere 4))
             (share (list-ref made-elsewhere 5)) (mime (list-ref made-elsewhere 6))
             (slot (foreign-block 8))
             (own-multi (curl-multi-init))
             (answers (let loop ((rows (wrong-thread-rows easy url slist multi share mime slot own-multi))
                                 (found '()))
                        (if (null? rows)
                            (reverse found)
                            (loop (cdr rows)
                                  (cons (cons (car (car rows)) (wrong-thread-of (caddr (car rows)))) found))))))
        (free-foreign-block! slot)
        (curl-multi-cleanup own-multi)
        answers)
      made-elsewhere))

;; curl-mime-add-part! hands back libcurl's own answer, step by step, on
;; every lane: curl_mime_filedata refuses a path that names nothing with
;; CURLE_READ_ERROR, 26, alike on 7.85.0, 8.5.0, 8.20.0, 8.23.0 and 8.7.1
;; (mime-files, case C-missing), and the steps before it answered 0. A
;; wrapper that read no code, or one step's code for another's, fails here,
;; where the engine's own check stands before the call in every transfer.
(test-equal "curl-mime-add-part!, on this thread's mime, answers libcurl's own codes: (filedata . 26), CURLE_READ_ERROR, for a file part whose path names nothing; #f for a data part, an empty one, and a file part of /dev/null, with a filename and a type; every count as it was before, once the mime and the handle are freed"
  (list '(filedata . 26) #f #f #f 'counts-as-before)
  (let* ((before (native-counts))
         (easy (curl-easy-init))
         (mime (curl-mime-init easy))
         (missing (guard (e (#t (list 'raised (describe e))))
                    (curl-mime-add-part! mime "f" 'file "/nonexistent-chez-curl/part" #f #f)))
         (data (guard (e (#t (list 'raised (describe e))))
                 (curl-mime-add-part! mime "d" 'data (make-bytevector 3 120) "d.txt" "text/plain")))
         (empty (guard (e (#t (list 'raised (describe e))))
                  (curl-mime-add-part! mime "e" 'data (make-bytevector 0) #f #f)))
         (devnull (guard (e (#t (list 'raised (describe e))))
                    (curl-mime-add-part! mime "n" 'file "/dev/null" "n.bin" "application/x-n"))))
    (curl-mime-free mime)
    (curl-easy-cleanup easy)
    (list missing data empty devnull
          (let ((after (native-counts))) (if (equal? before after) 'counts-as-before (list before after))))))

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
  (if (made? made-elsewhere)
      (let ((easy (list-ref made-elsewhere 1)) (multi (list-ref made-elsewhere 4)))
        (let* ((live (guard (e (#t (list 'raised (describe e)))) (curl-multi-wakeup multi)))
               (not-multi (assertion-of (lambda () (curl-multi-wakeup easy))))
               (freed (begin (on-thread (lambda () (curl-multi-cleanup multi)))
                             (assertion-of (lambda () (curl-multi-wakeup multi))))))
          (list live not-multi freed)))
      made-elsewhere))

;; The table above names every export that takes a handle a thread owns.
;; The rest, written out here, take none: the load's answers, options by
;; name, the makers of a fresh handle, the checked copies and C strings,
;; libcurl's texts, a header's bytes, curl-free of a string libcurl
;; handed back, curl-multi-wakeup, which any thread may call, and the mime
;; probe's form. A new export that takes a handle fails here by name until
;; the table calls it (the M8 plan, section 3.4).
(define exports-without-a-handle
  '(loaded-libcurl loaded-libcurl-file loaded-libcurl-patched? loaded-ca-variables loaded-tls-backend
    loaded-features loaded-on-macos? loaded-protocols loaded-mime-probe loaded-mime?
    curl-easy-option curl-easy-init curl-url curl-multi-init curl-share-init
    copy-foreign->bytevector! copy-bytevector->foreign! call-with-c-string call-with-latin-1-c-string
    call-with-foreign-bytes call-with-curl-blob c-string->bytevector
    curl-url-strerror curl-easy-strerror curl-multi-strerror curl-header-bytes curl-free
    curl-multi-wakeup curl-formadd-code))

;; exports-the-table-calls : (Listof Symbol)
;; The exports the wrong-thread table calls, its first column, read from
;; the table itself, no handle touched: a row dropped from the table is an
;; export no row calls.
(define exports-the-table-calls
  (let loop ((names (map car (wrong-thread-rows 0 0 0 0 0 0 0 0))) (found '()))
    (cond ((null? names) (reverse found))
          ((memq (car names) found) (loop (cdr names) found))
          (else (loop (cdr names) (cons (car names) found))))))

;; symbols-sorted : (Listof Symbol) -> (Listof Symbol)
(define (symbols-sorted names)
  (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) names))

(test-equal "every export of (curl private native) is one the wrong-thread table calls, or one written out as taking no handle a thread owns, and none is both"
  (list (symbols-sorted (library-exports '(curl private native))) '())
  (list (symbols-sorted (append exports-the-table-calls exports-without-a-handle))
        (filter (lambda (name) (memq name exports-without-a-handle)) exports-the-table-calls)))

(test-equal "the handles freed on the thread that made them, every count is zero"
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0))
  (if (made? made-elsewhere)
      (begin
        (on-thread (lambda ()
                     (curl-mime-free (list-ref made-elsewhere 6))
                     (curl-easy-cleanup (list-ref made-elsewhere 1))
                     (curl-url-cleanup (list-ref made-elsewhere 2))
                     (curl-slist-free-all (list-ref made-elsewhere 3))
                     (curl-share-cleanup (list-ref made-elsewhere 5))))
        (on-thread (lambda () 'stop-the-worker))
        (native-counts))
      made-elsewhere))

(test-end "native")

(exit (suite-exit-status runner))
