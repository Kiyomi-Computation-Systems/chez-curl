#!r6rs
;;; The suite for a multipart/form-data body (ADR-0039, amended twice; the
;;; M8 plan, sections 3.1, 3.4, 3.7 and 3.8), against the test origin's
;;; parts route, its bytes held by test-origin and test-origin-tls:
;;;
;;;   - every refusal of section 3.7 beside the neighbour that passes: the
;;;     shapes, assertion violations naming the body by its kind;
;;;     multipart-empty; part-empty; part-bytes over every char U+0000 to
;;;     U+001F, U+007F and ", at each place, beside U+0020, U+0021, U+0023,
;;;     U+007E, a char past ASCII and a leading U+FEFF; a file part's
;;;     default filename by the filename's rules; multipart-content-type, as
;;;     the request is made and at submit; part-file, made, submitted, and
;;;     a relative path at submit, through the private seam; the high
;;;     level's multipart-beside-body and body-not-allowed;
;;;   - the copies: each metadata string and the list mutated after the
;;;     request is made, then submitted; the accessor's copy mutated; a
;;;     relative path resolved when the request is made; the data copied at
;;;     submit, not when the request is made; and the high level's data and
;;;     paths taken once, as the call starts, a retry's wait between;
;;;   - the wire, byte for byte at the origin: each part kind and its
;;;     options, the default types, every method that sends a body, a body
;;;     past 1 MiB, the Content-Type: blank left out and the Expect: blank
;;;     kept, and the header cap beside the mime;
;;;   - the engine's check, by the private gate that changes a path after
;;;     the submit's stat; mime-failed and a refused curl_mime_filedata by
;;;     the private seam that plants a part's answer; an abandoned handle
;;;     keeping its mime, in a child;
;;;   - the high level's multipart key through a retry, a 307, a 308, a 303
;;;     and a group;
;;;   - a per-version table, written out here (ADR-0017): the request
;;;     size; a file grown, shrunk and removed once the origin holds the
;;;     head, after the engine's check; a FIFO swapped in, its writer
;;;     bounded; and the resends, the racing cell holding every answer
;;;     seen. A libcurl with no row fails by name, and prints the row it
;;;     measured;
;;;   - no secret printed: one secret in a value, a name, a filename, a
;;;     type and a path, through every refusal and every outcome.
;;;
;;; Each transfer runs on an engine of its own, stopped after it, so no
;;; connection outlives its test (traps.md). Every computation that can
;;; raise runs under a guard that names what was raised, and no expected
;;; value is #f: SRFI-64 makes #f of a raise in the actual expression.
(import (rnrs)
        (rnrs mutable-pairs)
        (rnrs mutable-strings)
        (srfi :64)
        (only (chezscheme) parameterize current-directory make-time sleep fork-thread make-mutex
              with-mutex critical-section display-condition mkdir getenv open-process-ports system
              library-directories file-directory? current-time time-second time-nanosecond chmod
              set-timer timer-interrupt-handler)
        (curl-testing)
        (only (auth-testing) sha256-hex)
        (curl)
        (curl unsupported)
        (http-client)
        (only (curl private transfer) curl-request-with-unresolved-path transfer-file-check-gate-set!
              transfer-mime-answer-set! transfer-mime-gate-set! curl-request-following
              curl-request-fault curl-request-follow hatch-settings-of curl-request-with-fault)
        (only (http-client private exchange) next-request)
        (curl private counters))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; written : Any -> String
(define (written x) (call-with-string-output-port (lambda (p) (write x p))))

;; shown : Any -> String
;; X written, cut to 4000 characters.
(define (shown x)
  (let ((text (written x)))
    (if (> (string-length text) 4000)
        (string-append (substring text 0 4000) "...")
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

(test-begin "multipart")

;; --- helpers --------------------------------------------------------------------------

(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)))

;; engine-counts : (Listof (Pairof Symbol Natural))
;; What a running engine counts with no transfer: its block and its multi
;; handle.
(define engine-counts
  '((block . 1) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 1) (share . 0) (mime . 0)))

;; The loaded libcurl's version, read before any engine's thread is forked.
(define version
  (guard (e (#t (list 'no-version (describe e))))
    (libcurl-info-version (loaded-libcurl))))

;; now-ms : -> Integer
(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

;; pause-ms : Natural -> Void
(define (pause-ms ms)
  (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))

;; contains? : String String -> Boolean
(define (contains? text part)
  (let ((n (string-length part)))
    (let loop ((i 0))
      (and (<= (+ i n) (string-length text))
           (or (string=? (substring text i (+ i n)) part) (loop (+ i 1)))))))

;; split-text : String Char -> (Listof String)
(define (split-text text c)
  (let loop ((i 0) (start 0) (found '()))
    (cond ((= i (string-length text)) (reverse (cons (substring text start i) found)))
          ((char=? (string-ref text i) c) (loop (+ i 1) (+ i 1) (cons (substring text start i) found)))
          (else (loop (+ i 1) start found)))))

;; bytes : Natural ... -> Bytevector
(define (bytes . octets) (u8-list->bytevector octets))

;; pattern-bytes : Natural -> Bytevector
;; N bytes, byte k being k mod 251: the origin's pattern.
(define (pattern-bytes n)
  (let ((b (make-bytevector n)))
    (do ((i 0 (+ i 1))) ((= i n) b) (bytevector-u8-set! b i (mod i 251)))))

;; shell-word : String -> String
;; S as one POSIX shell word, in single quotes.
(define (shell-word s)
  (call-with-string-output-port
   (lambda (p)
     (put-char p #\')
     (string-for-each (lambda (c) (if (char=? c #\') (put-string p "'\\''") (put-char p c))) s)
     (put-char p #\'))))

;; scratch : (U String #f)
;; A fresh directory for the suite's files, removed as the process ends.
(define scratch
  (guard (e (#t #f))
    (make-process-temp-directory)))

(test-equal "a scratch directory is made"
  'made
  (if (and (string? scratch) (file-directory? scratch)) 'made 'not-made))

(unless (and (string? scratch) (file-directory? scratch))
  (exit 1))

(define (in-scratch name) (string-append scratch "/" name))

;; write-bytes : String Bytevector -> Void
(define (write-bytes path bytes)
  (call-with-port (open-file-output-port path (file-options no-fail))
    (lambda (p) (put-bytevector p bytes))))

;; append-bytes : String Bytevector -> Void
(define (append-bytes path bytes)
  (call-with-port (open-file-output-port path (file-options no-fail no-truncate append))
    (lambda (p) (put-bytevector p bytes))))

;; make-directory : String -> String
(define (make-directory path) (mkdir path) path)

;; mkfifo : String -> Void
(define (mkfifo path)
  (unless (= 0 (system (string-append "mkfifo " (shell-word path))))
    (error 'mkfifo "mkfifo failed")))

;; next-key : String -> String
;; A key no other test uses: the counts live as long as the origin.
(define key-count 0)
(define (next-key what)
  (set! key-count (+ key-count 1))
  (string-append "mp-" what "-" (number->string key-count)))

;; The files every test may use, each the pattern's bytes or text.
(define file-a (in-scratch "a.bin"))
(define file-txt (in-scratch "t.txt"))
(define files-made
  (guard (e (#t (list 'raised (describe e))))
    (write-bytes file-a (pattern-bytes 300))
    (write-bytes file-txt (string->utf8 "a text file\n"))
    'made))

(test-equal "the suite's files are made"
  'made
  files-made)

;; refusal-of : (-> Any) -> List
;; What THUNK raised, as data: (refused WHO FIELD VALUE REASON) for a
;; &curl-request-error, (http-refused WHO FIELD VALUE REASON) for a
;; &http-request-error, (assertion WHO IRRITANTS) for an assertion
;; violation, (raised TEXT) for anything else; (made) when it raised
;; nothing.
(define (refusal-of thunk)
  (guard (e ((http-request-error? e)
             (list 'http-refused (and (who-condition? e) (condition-who e)) (http-request-error-field e)
                   (http-request-error-value e) (http-request-error-reason e)))
            ((curl-request-error? e)
             (list 'refused (and (who-condition? e) (condition-who e)) (curl-request-error-field e)
                   (curl-request-error-value e) (curl-request-error-reason e)))
            ((assertion-violation? e)
             (list 'assertion (and (who-condition? e) (condition-who e))
                   (if (irritants-condition? e) (condition-irritants e) '())))
            (#t (list 'raised (describe e))))
    (thunk)
    '(made)))

;; made : Any Any ... -> Request
;; A post of BODY to a port nothing listens on, with KEYS after.
(define (made body . keys)
  (apply make-curl-request "http://127.0.0.1:9/" 'method 'post 'proxy #f 'body body keys))

;; checked : Any Any ... -> List
;; refusal-of for a request of BODY made with KEYS, then checked as a
;; submit checks it.
(define (checked body . keys)
  (refusal-of (lambda () (curl-request-check (apply made body keys)))))

;; made-only : Any Any ... -> List
;; refusal-of for the request alone, made.
(define (made-only body . keys)
  (refusal-of (lambda () (apply made body keys))))

;; refused-at : Natural Symbol Symbol -> List
;; make-curl-request's refusal of part I's FIELD for REASON.
(define (refused-at i field reason)
  (list 'refused 'make-curl-request 'body (list 'part i field) reason))

;; --- the shapes: assertion violations, the body named by its kind ------------------

(define circular
  (let ((parts (list (list "a" "x"))))
    (set-cdr! parts parts)
    (cons 'multipart parts)))

(test-equal "a multipart body of a wrong shape is an assertion violation from make-curl-request, naming the body by its kind, never its strings: an improper list, a part no list, a part of one element, a name no string, a source no string, bytevector or (file PATH), (file) and (file PATH EXTRA), a path no string, an option with no value, an option given twice, an option but filename and type, an option's value no string, a part improper, and a cycle; the neighbour, a part of every kind with both options, is made"
  '((assertion make-curl-request ((kind list)))
    (assertion make-curl-request ((kind list)))
    (assertion make-curl-request ((kind list)))
    (assertion make-curl-request ((kind list)))
    (assertion make-curl-request ((kind list)))
    (assertion make-curl-request ((kind list)))
    (assertion make-curl-request ((kind list)))
    (assertion make-curl-request ((kind list)))
    (assertion make-curl-request ((kind list)))
    (assertion make-curl-request ((kind list)))
    (assertion make-curl-request ((kind list)))
    (assertion make-curl-request ((kind list)))
    (assertion make-curl-request ((kind list)))
    (assertion make-curl-request ((kind list)))
    (made))
  (map (lambda (body) (made-only body))
       (list '(multipart ("a" "x") . tail)
             '(multipart "a")
             '(multipart ("a"))
             '(multipart (a "x"))
             '(multipart ("a" 42))
             '(multipart ("a" (file)))
             (list 'multipart (list "a" (list 'file file-a "extra")))
             '(multipart ("a" (file 42)))
             '(multipart ("a" "x" filename))
             '(multipart ("a" "x" filename "f" filename "g"))
             '(multipart ("a" "x" name "n"))
             '(multipart ("a" "x" type 42))
             '(multipart ("a" "x" filename "f" . type))
             circular
             (list 'multipart (list "s" "x" 'filename "s.txt" 'type "text/x")
                   (list "b" (bytes 1 2) 'type "x/y" 'filename "b.bin")
                   (list "f" (list 'file file-a) 'filename "a.bin" 'type "application/x")))))

;; --- the refusals of section 3.7, each beside the neighbour that passes ----------------

(test-equal "multipart-empty: (multipart), field body, value multipart; a part with empty data is made"
  (list '(refused make-curl-request body multipart multipart-empty) '(made))
  (list (made-only '(multipart)) (made-only '(multipart ("a" "")))))

(test-equal "part-empty: an empty name, filename or type, each named by its part and field, at part 1; the neighbours of one char are made"
  (list (refused-at 1 'name 'part-empty) (refused-at 1 'filename 'part-empty) (refused-at 1 'type 'part-empty)
        '(made) '(made) '(made))
  (list (made-only '(multipart ("ok" "1") ("" "x")))
        (made-only '(multipart ("ok" "1") ("a" "x" filename "")))
        (made-only '(multipart ("ok" "1") ("a" "x" type "")))
        (made-only '(multipart ("ok" "1") ("a" "x")))
        (made-only '(multipart ("ok" "1") ("a" "x" filename "f")))
        (made-only '(multipart ("ok" "1") ("a" "x" type "t")))))

;; The byte rules, at each place, on values built to look like what passes:
;; a plausible name, filename and type, the char at its start, in its
;; middle and at its end, in part 1, after a part that passes.
(define bases '((name . "photo") (filename . "beach.jpg") (type . "image/jpeg")))

;; placed : String Char -> (Listof String)
(define (placed base c)
  (let ((n (string-length base)))
    (list (string-append (string c) base)
          (string-append (substring base 0 (div n 2)) (string c) (substring base (div n 2) n))
          (string-append base (string c)))))

;; part-with : Symbol String -> List
;; Part 1's body with FIELD at VALUE, the others plausible.
(define (part-with field value)
  (list 'multipart (list "ok" "1")
        (case field
          ((name) (list value "x" 'filename "beach.jpg" 'type "image/jpeg"))
          ((filename) (list "photo" "x" 'filename value 'type "image/jpeg"))
          (else (list "photo" "x" 'filename "beach.jpg" 'type value)))))

;; The byte rules over the whole complement: every char U+0000 to U+00FF,
;; and U+0100, U+FFFD and U+10FFFF beside them, at each place. The refused
;; codes are written out here, the rule's own: U+0000 to U+001F and U+007F
;; at every field, and " at a name and a filename alone.
(define control-codes
  '(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 127))

(define byte-rule-codes
  (append (let loop ((i 255) (found '()))
            (if (< i 0) found (loop (- i 1) (cons i found))))
          (list #x100 #xFFFD #x10FFFF)))

;; byte-rule-mismatches : Symbol -> (List Natural (Listof List))
;; For FIELD, how many values were made, and each whose answer is not the
;; rule's: (CODE PLACE WANT GOT), PLACE 0, 1 or 2, start, middle or end.
(define (byte-rule-mismatches field)
  (let ((base (cdr (assq field bases)))
        (refused (if (eq? field 'type) control-codes (cons 34 control-codes))))
    (let loop ((codes byte-rule-codes) (n 0) (found '()))
      (if (null? codes)
          (list n (reverse found))
          (let* ((code (car codes))
                 (want (if (memv code refused) (refused-at 1 field 'part-bytes) '(made))))
            (let place ((values (placed base (integer->char code))) (i 0) (n n) (found found))
              (if (null? values)
                  (loop (cdr codes) n found)
                  (let ((got (made-only (part-with field (car values)))))
                    (place (cdr values) (+ i 1) (+ n 1)
                           (if (equal? got want) found (cons (list code i want got) found)))))))))))

(for-each
 (lambda (field)
   (test-equal (string-append "part-bytes over the whole complement: a " (symbol->string field)
                              " holding each char U+0000 to U+00FF, U+0100, U+FFFD or U+10FFFF, at its start, in its middle and at its end, is refused, named by its part and field, exactly for U+0000 to U+001F and U+007F"
                              (if (eq? field 'type) "" ", and \"")
                              ", and made for every other: 777 values, none answering but the rule")
     (list 777 '())
     (guard (e (#t (list 'raised (describe e))))
       (byte-rule-mismatches field)))
   (test-equal (string-append "a " (symbol->string field) " beginning with U+FEFF is made: no decoder drops it here")
     '(made)
     (made-only (part-with field (string-append (string #\xFEFF) (cdr (assq field bases)))))))
 '(name filename type))

;; A file part's filename defaults to its path's last component, and the
;; filename's rules hold it: a " or a control char there is refused, unless
;; the part names a filename of its own. The rules are pure, and come before
;; the path's stat.
(define quote-file (in-scratch "a\"b.txt"))
(define control-file (in-scratch (string-append "a" (string (integer->char 1)) "b.txt")))
;; And the rules hold the last component alone: the same chars in a
;; directory's name pass, the default filename f.txt.
(define quote-dir-file (in-scratch "q\"dir/f.txt"))
(define control-dir-file (in-scratch (string-append "c" (string (integer->char 1)) "dir/f.txt")))
(define odd-files-made
  (guard (e (#t (list 'raised (describe e))))
    (write-bytes quote-file (string->utf8 "q"))
    (write-bytes control-file (string->utf8 "c"))
    (mkdir (in-scratch "q\"dir"))
    (mkdir (in-scratch (string-append "c" (string (integer->char 1)) "dir")))
    (write-bytes quote-dir-file (string->utf8 "f"))
    (write-bytes control-dir-file (string->utf8 "f"))
    'made))

(test-equal "a file part's default filename, its path's last component, is held by the filename's rules: a \" or U+0001 there is refused as the filename's part-bytes, and a filename of the part's own lets the same path through; the same chars in a directory's name pass, the last component f.txt"
  (list 'made (refused-at 0 'filename 'part-bytes) (refused-at 0 'filename 'part-bytes) '(made) '(made)
        '(made) '(made))
  (list odd-files-made
        (made-only (list 'multipart (list "f" (list 'file quote-file))))
        (made-only (list 'multipart (list "f" (list 'file control-file))))
        (made-only (list 'multipart (list "f" (list 'file quote-file) 'filename "q.txt")))
        (made-only (list 'multipart (list "f" (list 'file control-file) 'filename "c.txt")))
        (made-only (list 'multipart (list "f" (list 'file quote-dir-file))))
        (made-only (list 'multipart (list "f" (list 'file control-dir-file))))))

(test-equal "part-file as the request is made: an empty path, a path holding U+0000, a path that names nothing, a directory, a FIFO, and /dev/null, each named by its part, path; a regular file and a symbolic link to one are made"
  (list (refused-at 0 'path 'part-file) (refused-at 0 'path 'part-file) (refused-at 0 'path 'part-file)
        (refused-at 0 'path 'part-file) (refused-at 0 'path 'part-file) (refused-at 0 'path 'part-file)
        '(made) '(made))
  (let ((dir (in-scratch "a-dir")) (fifo (in-scratch "a-fifo")) (link (in-scratch "a-link")))
    (guard (e (#t (list 'raised (describe e))))
      (make-directory dir)
      (mkfifo fifo)
      (system (string-append "ln -s " (shell-word file-a) " " (shell-word link)))
      (map (lambda (path) (made-only (list 'multipart (list "f" (list 'file path)))))
           (list "" (string-append scratch "/a" (string #\nul) "b") (in-scratch "nothing-here")
                 dir fifo "/dev/null" file-a link)))))

(test-equal "part-file at submit: a file removed once the request is made is refused by curl-request-check, as a submit's own stat, named by its part; the request whose file stays passes"
  (list '(refused curl-request-check body (part 1 path) part-file) '(made))
  (let ((gone (in-scratch "gone.bin")))
    (guard (e (#t (list 'raised (describe e))))
      (write-bytes gone (pattern-bytes 10))
      (let ((r (made (list 'multipart (list "a" "x") (list "f" (list 'file gone)))))
            (stays (made (list 'multipart (list "a" "x") (list "f" (list 'file file-a))))))
        (delete-file gone)
        (list (refusal-of (lambda () (curl-request-check r)))
              (refusal-of (lambda () (curl-request-check stays))))))))

;; A request holds resolved paths, so only a fault hands a submit a
;; relative one: the private seam makes one (ADR-0039, amended 2026-11-07).
(test-equal "part-file at submit: a path that is not absolute, through the private seam that sets one unresolved, is refused, whether or not the working directory holds the file; the seam's absolute path passes"
  (list '(refused curl-request-check body (part 0 path) part-file)
        '(refused curl-request-check body (part 0 path) part-file)
        '(made))
  (guard (e (#t (list 'raised (describe e))))
    (let ((r (made (list 'multipart (list "f" (list 'file file-a))))))
      (list (refusal-of (lambda () (curl-request-check (curl-request-with-unresolved-path r 0 "a.bin"))))
            (parameterize ((current-directory scratch))
              (refusal-of (lambda () (curl-request-check (curl-request-with-unresolved-path r 0 "a.bin")))))
            (refusal-of (lambda () (curl-request-check (curl-request-with-unresolved-path r 0 file-a))))))))

(test-equal "multipart-content-type: a Content-Type header beside a multipart body, in any A to Z case, field header-name, its name as given; Content-Typ, X-Content-Type and Content-Type beside a whole body are made"
  (list '(refused make-curl-request header-name "Content-Type" multipart-content-type)
        '(refused make-curl-request header-name "content-TYPE" multipart-content-type)
        '(made) '(made) '(made))
  (list (made-only '(multipart ("a" "x")) 'headers '(("Content-Type" . "multipart/form-data")))
        (made-only '(multipart ("a" "x")) 'headers '(("X-A" . "1") ("content-TYPE" . "text/plain")))
        (made-only '(multipart ("a" "x")) 'headers '(("Content-Typ" . "x")))
        (made-only '(multipart ("a" "x")) 'headers '(("X-Content-Type" . "x")))
        (made-only (bytes 1) 'headers '(("Content-Type" . "x")))))

;; A request shares its header strings with its caller: a name changed to
;; Content-Type after the request is made is refused at submit, on the
;; submit's own copies.
(test-equal "multipart-content-type at submit: a header's name changed to Content-Type after the request is made is refused by the submit's check"
  (list '(made) '(refused curl-request-check header-name "Content-Type" multipart-content-type))
  ;; In turn, by let*: a list's arguments are evaluated in no fixed order
  ;; (AGENTS.md).
  (let* ((name (string-copy "Content-Typf"))
         (r (made '(multipart ("a" "x")) 'headers (list (cons name "x"))))
         (before (refusal-of (lambda () (curl-request-check r))))
         (changed (string-set! name 11 #\e))
         (after (refusal-of (lambda () (curl-request-check r)))))
    (list before after)))

(test-equal "a multipart body is a whole body: get and head refuse it, body-not-allowed, value the method; body-length beside it is body-length-without-stream; post, put, patch and delete take one"
  '((refused make-curl-request body get body-not-allowed)
    (refused make-curl-request body head body-not-allowed)
    (refused make-curl-request body-length 3 body-length-without-stream)
    (made) (made) (made) (made))
  (append (map (lambda (method)
                 (refusal-of (lambda () (make-curl-request "http://127.0.0.1:9/" 'method method
                                                           'body '(multipart ("a" "x"))))))
               '(get head))
          (list (made-only '(multipart ("a" "x")) 'body-length 3))
          (map (lambda (method)
                 (refusal-of (lambda () (make-curl-request "http://127.0.0.1:9/" 'method method
                                                           'body '(multipart ("a" "x"))))))
               '(post put patch delete))))

(test-equal "the loaded libcurl has mime, by the load's probe: curl_formadd answered 0 and curl_mime_init a mime (multipart-unsupported is tests/test-library-loading.sps's, on the decoy's switches)"
  'mime
  (guard (e ((curl-request-error? e) (list 'refused (curl-request-error-reason e))))
    (curl-request-check (made '(multipart ("a" "x"))))
    'mime))

;; --- a caller's timer across the checks of a file part (the slice's review) ----------------
;; A caller's timer handler raises wherever its timer runs out, inside a
;; check as anywhere: a guard that took every raise around the path's
;; stat answered the handler's raise as part-file (review-timer-rerun.log,
;; 6 of 20,000 ticks each for make-curl-request and curl-request-check).
;; Each operation is timed first, its band found: the first tick count,
;; doubling from 16, at which four runs in a row end before their timer;
;; then the timer is swept across the band a tick at a time, its handler
;; raising a sentinel. Every run answers the sentinel or no raise, never a
;; refusal, and both are seen, so the sweep reached the operation's end.

;; timer-sentinel : Pair
;; What the sweep's handler raises: a fresh pair no other raise is.
(define timer-sentinel (list 'timer-sentinel))

;; timed : (-> Any) Natural -> Any
;; THUNK run with a timer of N ticks armed, its handler raising the
;; sentinel: sentinel when it did, no-raise when THUNK ended first,
;; (refused REASON) for a &curl-request-error, (other TEXT) for anything
;; else. The timer is disarmed, and the handler put back, however it ends.
(define (timed thunk n)
  (let ((previous (timer-interrupt-handler)))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (guard (e ((eq? e timer-sentinel) 'sentinel)
                  ((curl-request-error? e) (list 'refused (curl-request-error-reason e)))
                  (#t (list 'other (describe e))))
          (timer-interrupt-handler (lambda () (raise timer-sentinel)))
          (set-timer n)
          (thunk)
          (set-timer 0)
          'no-raise))
      (lambda () (set-timer 0) (timer-interrupt-handler previous)))))

;; band-end : (-> Any) -> Natural
;; The first tick count, doubling from 16, at which THUNK ends before its
;; timer four runs in a row, at N to N + 3; 2^21 at most.
(define (band-end thunk)
  (let loop ((n 16))
    (if (or (>= n 2097152) (for-all (lambda (k) (eq? (timed thunk (+ n k)) 'no-raise)) '(0 1 2 3)))
        n
        (loop (* n 2)))))

;; swept : (-> Any) -> (List Natural (Listof Any))
;; The band's end, and every distinct answer of THUNK timed at each tick
;; count from 1 to it, sorted by their printed form.
(define (swept thunk)
  (let ((end (band-end thunk)))
    (let loop ((n 1) (found '()))
      (if (> n end)
          (list end (list-sort (lambda (a b) (string<? (written a) (written b))) found))
          (let ((answer (timed thunk n)))
            (loop (+ n 1) (if (member answer found) found (cons answer found))))))))

(define timer-file (in-scratch "timer.bin"))
(define timer-file-made
  (guard (e (#t (list 'raised (describe e))))
    (write-bytes timer-file (pattern-bytes 10))
    'made))

(define (timer-request)
  (make-curl-request "http://127.0.0.1:9/" 'method 'post 'proxy #f 'timeout-ms 2000
                     'body (list 'multipart (list "a" "x") (list "f" (list 'file timer-file)))))

(test-equal "a caller's timer swept a tick at a time across make-curl-request, curl-request-check and curl-submit of a body with a file part, its handler raising a sentinel: every run answers the sentinel or no raise, never a refusal, across each operation's band; and every count is zero after"
  (list 'made '(no-raise sentinel) '(no-raise sentinel) '(no-raise sentinel) zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (let* ((r (timer-request))
           (made (swept timer-request))
           (checked (swept (lambda () (curl-request-check r))))
           (submitted (let ((e (make-curl-engine)))
                        (dynamic-wind
                          (lambda () #f)
                          (lambda ()
                            (swept (lambda () (curl-token-cancel (curl-submit e r)))))
                          (lambda () (curl-engine-stop e))))))
      ;; The bands swept, as evidence of what ran.
      (display (string-append "test-multipart: timer swept a tick at a time to "
                              (number->string (car made)) " ticks for make-curl-request, "
                              (number->string (car checked)) " for curl-request-check and "
                              (number->string (car submitted)) " for curl-submit\n"))
      (list timer-file-made (cadr made) (cadr checked) (cadr submitted) (native-counts)))))

;; --- the high level's refusals ----------------------------------------------------------

(test-equal "the high level: multipart beside body or form is multipart-beside-body, field multipart, value #f; body beside form keeps body-and-form; multipart with get or head is body-not-allowed, field multipart, value the method; a call's own Content-Type beside it is the low level's multipart-content-type; a wrong shape the low level's assertion violation"
  '((http-refused http-request multipart #f multipart-beside-body)
    (http-refused http-request multipart #f multipart-beside-body)
    (http-refused http-request form #f body-and-form)
    (http-refused http-request multipart get body-not-allowed)
    (http-refused http-request multipart head body-not-allowed)
    (refused make-curl-request header-name "Content-Type" multipart-content-type)
    (assertion make-curl-request ((kind list))))
  (guard (e (#t (list 'raised (describe e))))
    (call-with-http-session 'proxy #f
      (lambda (s)
        (list (refusal-of (lambda () (http-request s 'post "http://127.0.0.1:9/" 'multipart '(("a" "x"))
                                                   'body "b")))
              (refusal-of (lambda () (http-request s 'post "http://127.0.0.1:9/" 'multipart '(("a" "x"))
                                                   'form '(("f" . "v")))))
              (refusal-of (lambda () (http-request s 'post "http://127.0.0.1:9/" 'body "b" 'form '(("f" . "v")))))
              (refusal-of (lambda () (http-request s 'get "http://127.0.0.1:9/" 'multipart '(("a" "x")))))
              (refusal-of (lambda () (http-request s 'head "http://127.0.0.1:9/" 'multipart '(("a" "x")))))
              (refusal-of (lambda () (http-request s 'post "http://127.0.0.1:9/" 'multipart '(("a" "x"))
                                                   'headers '(("Content-Type" . "x")))))
              (refusal-of (lambda () (http-request s 'post "http://127.0.0.1:9/" 'multipart '(("a" 42))))))))))

;; --- curl-request-with's url key (ADR-0023, after slice 3's review) ------------------------
;; The url key is checked as make-curl-request checks its first argument,
;; by the one path: as the request is made, a URL that is no string, and
;; the cookie jar's Host rule on the request's headers; then, at submit or
;; check, the URL cap, the parse and the scheme, and userinfo beside
;; credentials, in that order. Each row is a URL and the keys beside it,
;; and what make-curl-request's request answers, made, then checked; the
;; same must come from curl-request-with 'url, its own who where the
;; request is made. A row marked libcurls-own is libcurl's own parse, whose
;; code moves by version: there both answers must be url errors, alike.

;; url-answer : (-> Request) -> List
;; What MAKE's request does: (made CHECK), CHECK what curl-request-check
;; answers, or the refusal MAKE raised.
(define (url-answer make)
  (let ((made (guard (e (#t e)) (make))))
    (cond ((curl-request? made)
           (list 'made (guard (e ((curl-url-error? e)
                                  (list 'url-error (and (who-condition? e) (condition-who e))
                                        (curl-url-error-reason e) (curl-url-error-code e)))
                                 ((curl-request-error? e)
                                  (list 'refused (condition-who e) (curl-request-error-field e)
                                        (curl-request-error-value e) (curl-request-error-reason e)))
                                 (#t (list 'raised (describe e))))
                         (curl-request-check made)
                         'checked)))
          ((curl-request-error? made)
           (list 'refused (condition-who made) (curl-request-error-field made)
                 (curl-request-error-value made) (curl-request-error-reason made)))
          ((assertion-violation? made)
           (list 'assertion (condition-who made) (condition-irritants made)))
          (else (list 'raised (describe made))))))

(define url-key-engine (guard (e (#t #f)) (make-curl-engine)))
(define url-key-jar (and url-key-engine (guard (e (#t #f)) (make-curl-cookie-jar url-key-engine))))

;; url-rows : (Listof (List String Any List Any))
;; Each row: its name, the URL, the keys beside it, and make-curl-request's
;; answer, with WHO standing for the constructor's own name where the
;; request is made, or libcurls-own.
(define url-rows
  (list (list "no string" 42 '() '(assertion WHO (42)))
          (list "the scheme ftp" "ftp://127.0.0.1/" '() '(made (url-error chez-curl scheme-not-http #f)))
          (list "past the cap, 8,000,000 chars" (string-append "http://127.0.0.1/" (make-string 8000000 #\a)) '()
                '(made (url-error chez-curl malformed-input 3)))
          (list "a bracket left open" "http://[::1" '() 'libcurls-own)
          (list "empty" "" '() 'libcurls-own)
          (list "no scheme" "127.0.0.1/x" '() 'libcurls-own)
          (list "userinfo beside credentials" "http://u:p@127.0.0.1/" '(credentials (basic "a" "b"))
                '(made (refused curl-request-check credentials basic credentials-beside-userinfo)))
          (list "userinfo beside credentials, the scheme ftp: the scheme first" "ftp://u:p@127.0.0.1/"
                '(credentials (basic "a" "b")) '(made (url-error chez-curl scheme-not-http #f)))
          (list "a Host header beside a cookie jar" "http://127.0.0.1:9/" (list 'headers '(("Host" . "h")) 'cookie-jar url-key-jar)
                '(refused WHO header-name "Host" cookie-beside-jar))
          (list "a URL that passes" "http://127.0.0.1:9/x" (list 'cookie-jar url-key-jar) '(made checked))))

;; with-who : Any Symbol -> Any
(define (with-who answer who)
  (cond ((eq? answer 'WHO) who)
        ((pair? answer) (cons (with-who (car answer) who) (with-who (cdr answer) who)))
        (else answer)))

(define url-base (make-curl-request "http://127.0.0.1:9/" 'method 'post 'proxy #f))

(for-each
 (lambda (row)
   (let ((name (car row)) (url (cadr row)) (keys (caddr row)) (want (cadddr row)))
     (test-equal (string-append "curl-request-with's url key, beside make-curl-request's URL, " name
                                ": the same refusal, in the same place, its own who where the request is made")
       (if (eq? want 'libcurls-own)
           '(libcurls-own alike)
           (list (with-who want 'make-curl-request) (with-who want 'curl-request-with)))
       (let ((by-make (url-answer (lambda () (apply make-curl-request url 'method 'post 'proxy #f keys))))
             (by-with (url-answer (lambda () (apply curl-request-with url-base 'url url keys)))))
         (if (eq? want 'libcurls-own)
             (if (and (equal? by-make by-with) (eq? (car by-make) 'made) (pair? (cadr by-make))
                      (eq? (car (cadr by-make)) 'url-error))
                 '(libcurls-own alike)
                 (list by-make by-with))
             (list by-make by-with))))))
 url-rows)

(test-equal "curl-request-with takes url, make-curl-request does not: an unknown key there, as before; url given twice to curl-request-with is a repeated key; url left out keeps the request's"
  (list '(refused make-curl-request key url unknown-key)
        '(refused curl-request-with key url repeated-key)
        "http://127.0.0.1:9/"
        "http://127.0.0.1:9/other")
  (list (made-only #f 'url "http://127.0.0.1:9/other")
        (refusal-of (lambda () (curl-request-with url-base 'url "http://a/" 'url "http://b/")))
        (curl-request-url (curl-request-with url-base 'timeout-ms 5))
        (curl-request-url (curl-request-with url-base 'url "http://127.0.0.1:9/other"))))

(when url-key-engine (curl-engine-stop url-key-engine))

;; --- a redirect's hop, through curl-request-with (ADR-0023, after slice 3's review) ---------
;; next-request builds a hop from the last request through curl-request-with
;; 'url. Each hop must hold exactly what the hop built by make-curl-request
;; held before, field by field, for every redirect kind, method and body:
;; old-next-request below is that builder, as it stood, written out here,
;; with the three rules it read.
(define (old-body-dropped? status method)
  (case status
    ((301 302) (eq? method 'post))
    ((303) (not (eq? method 'head)))
    (else #f)))

(define (ascii-folded-name s)
  (list->string (map (lambda (c) (if (char<=? #\A c #\Z) (integer->char (+ (char->integer c) 32)) c))
                     (string->list s))))

(define (old-body-header? name)
  (let ((n (ascii-folded-name name)))
    (or (and (>= (string-length n) 8) (string=? (substring n 0 8) "content-"))
        (member n '("digest" "last-modified" "expect")))))

(define (old-credential-header? name)
  (and (member (ascii-folded-name name) '("authorization" "cookie")) #t))

(define (old-next-request last url status across another-host)
  (let* ((method (curl-request-method last))
         (dropped (old-body-dropped? status method))
         (headers (filter (lambda (header)
                            (let ((name (car header)))
                              (not (or (and dropped (old-body-header? name))
                                       (and across (old-credential-header? name))
                                       (and another-host (string=? (ascii-folded-name name) "host"))))))
                          (curl-request-headers last))))
    (make-curl-request url
                       'method (if dropped 'get method)
                       'headers headers
                       'body (if dropped #f (curl-request-body last))
                       'body-length (if dropped #f (curl-request-body-length last))
                       'stream-buffer (curl-request-stream-buffer last)
                       'user-agent (curl-request-user-agent last)
                       'timeout-ms (curl-request-timeout-ms last)
                       'connect-timeout-ms (curl-request-connect-timeout-ms last)
                       'body-limit (curl-request-body-limit last)
                       'ca-file (curl-request-ca-file last)
                       'verify (curl-request-verify last)
                       'proxy (curl-request-proxy last)
                       'http-version (curl-request-http-version last)
                       'credentials (if across #f (curl-request-credentials last))
                       'proxy-ca-file (curl-request-proxy-ca-file last)
                       'proxy-verify (curl-request-proxy-verify last)
                       'cookie-jar (curl-request-cookie-jar last))))

;; request-fields : Request -> List
;; Every field of REQUEST, public and private, by name.
(define (request-fields r)
  (list (cons 'url (curl-request-url r)) (cons 'method (curl-request-method r))
        (cons 'headers (curl-request-headers r)) (cons 'body (curl-request-body r))
        (cons 'user-agent (curl-request-user-agent r)) (cons 'timeout-ms (curl-request-timeout-ms r))
        (cons 'connect-timeout-ms (curl-request-connect-timeout-ms r))
        (cons 'body-limit (curl-request-body-limit r)) (cons 'ca-file (curl-request-ca-file r))
        (cons 'verify (curl-request-verify r)) (cons 'proxy (curl-request-proxy r))
        (cons 'stream-buffer (curl-request-stream-buffer r)) (cons 'body-length (curl-request-body-length r))
        (cons 'http-version (curl-request-http-version r)) (cons 'credentials (curl-request-credentials r))
        (cons 'proxy-ca-file (curl-request-proxy-ca-file r)) (cons 'proxy-verify (curl-request-proxy-verify r))
        (cons 'cookie-jar (curl-request-cookie-jar r)) (cons 'fault (curl-request-fault r))
        (cons 'follow (curl-request-follow r)) (cons 'options (hatch-settings-of r))))

;; hop-lasts : (Listof Request)
;; Last requests of every field set, but the private ones, a multipart body
;; with a file and data and a bytevector body, each by post, put and
;; delete: a Content-Language header, the body's; an Authorization header
;; beside no credentials, and a Cookie; a Host header; every timeout and
;; bound; a CA file; an https:// proxy, its CA file and verification; HTTP/1.1.
(define hop-lasts
  (guard (e (#t (list 'raised (describe e))))
    (apply append
           (map (lambda (method)
                  (apply append
                         (map (lambda (body)
                                (map (lambda (who)
                                       (apply make-curl-request "http://127.0.0.1:9/from?x=1" 'method method
                                              'headers (append (if (eq? who 'header) '(("Authorization" . "Bearer t")) '())
                                                               '(("Content-Language" . "en") ("Cookie" . "c=1")
                                                                 ("X-Kept" . "k") ("Host" . "127.0.0.1:9")))
                                              'body body 'user-agent "agent/1" 'timeout-ms 4000
                                              'connect-timeout-ms 3000 'body-limit 100000 'ca-file "ca.pem"
                                              'verify #f 'proxy "https://proxy.invalid:3128"
                                              'proxy-ca-file "proxy-ca.pem" 'proxy-verify #t 'http-version 'http/1.1
                                              (if (eq? who 'credentials) '(credentials (basic "u" "p")) '())))
                                     '(header credentials)))
                              (list (list 'multipart (list "d" (bytes 1 2 3) 'filename "d.bin")
                                          (list "f" (list 'file file-a) 'type "x/y"))
                                    (bytes 1 2 3)))))
                '(post put delete)))))

(test-equal "a redirect's hop, made through curl-request-with 'url, holds exactly what the hop make-curl-request built held, every field, the private fault, follow and hatch options among them: for each of 301, 302, 303, 307 and 308, post, put and delete, a multipart and a bytevector body, an Authorization header or credentials, within the origin and across it to another host; 120 hops, none differing"
  (list 120 '())
  (guard (e (#t (list 'raised (describe e))))
    (let loop ((cases (apply append
                             (map (lambda (last)
                                    (apply append
                                           (map (lambda (status)
                                                  (map (lambda (across) (list last status across)) '(#f #t)))
                                                '(301 302 303 307 308))))
                                  hop-lasts)))
               (n 0) (found '()))
      (if (null? cases)
          (list n (reverse found))
          (let* ((last (car (car cases))) (status (cadr (car cases))) (across (caddr (car cases)))
                 (url (if across "http://127.0.0.2:9/to" "http://127.0.0.1:9/to"))
                 (old (request-fields (old-next-request last url status across across)))
                 (new (request-fields (next-request last url status across across))))
            (loop (cdr cases) (+ n 1)
                  (if (equal? old new)
                      found
                      (cons (list (curl-request-method last) status across
                                  (filter (lambda (field) (not (member field old))) new))
                            found))))))))

;; A hop keeps the last request's hatch options, fault and follow, where
;; make-curl-request made them (), #f and #f. No high-level path sets them:
;; the hatch's (curl unsupported) and the private constructors of (curl
;; private transfer) are out of the high level's reach (check-seam's rules
;; (a) and (b)), so its last requests hold (), #f and #f, and the 120 hops
;; above stand for every hop it makes.
(test-equal "a hop keeps what only a low-level caller sets: the last request's hatch options, its private fault and its follow, which make-curl-request's hop reset to (), #f and #f"
  '((("LOW_SPEED_TIME" long 9)) 3 #t)
  (guard (e (#t (list 'raised (describe e))))
    (let* ((last (curl-request-following
                  (curl-request-with-fault
                   (curl-request-with-options (cadr hop-lasts) '(("LOW_SPEED_TIME" . 9)))
                   3)))
           (hop (next-request last "http://127.0.0.1:9/to" 307 #f #f)))
      (list (hatch-settings-of hop) (curl-request-fault hop) (curl-request-follow hop)))))

;; --- the copies (the M8 plan, section 3.1; ADR-0039, amended 2026-11-07) --------------

;; scratch-resolved : String
;; What a relative path made in scratch resolves to: current-directory's
;; answer there. On macOS that names /private/var where TMPDIR names /var,
;; a symbolic link to it, so scratch's own name is not it (the Mac's run,
;; 2026-11-07). Under a guard: a raise in an expected value kills the suite.
(define scratch-resolved
  (guard (e (#t "current-directory-refused"))
    (parameterize ((current-directory scratch)) (current-directory))))

(test-equal "curl-request-body answers a copy of a multipart body: fresh pairs, fresh name, filename, type and path strings, each path resolved, the data as given; a change to it reaches neither the request nor a second answer"
  (list (list 'multipart (list "n" "data" 'filename "f.txt" 'type "t/x")
              (list "f" (list 'file (string-append scratch-resolved "/a.bin"))))
        'fresh-strings 'the-data-itself
        (list 'multipart (list "n" "data" 'filename "f.txt" 'type "t/x")
              (list "f" (list 'file (string-append scratch-resolved "/a.bin")))))
  (guard (e (#t (list 'raised (describe e))))
    (let* ((data (string-copy "data"))
           (resolved (parameterize ((current-directory scratch))
                       (made (list 'multipart (list "n" data 'filename "f.txt" 'type "t/x")
                                   (list "f" (list 'file "a.bin"))))))
           (first (curl-request-body resolved))
           (second (curl-request-body resolved))
           ;; Each read and each change in turn, by let*: a list's
           ;; arguments are evaluated in no fixed order (AGENTS.md).
           (answered (curl-request-body resolved))
           (fresh (if (and (not (eq? (car (cadr first)) (car (cadr second))))
                           (not (eq? (cadr (caddr first)) (cadr (caddr second)))))
                      'fresh-strings 'shared))
           (itself (if (eq? (cadr (cadr first)) data) 'the-data-itself 'a-copy))
           (changed (begin
                      (string-set! (car (cadr first)) 0 #\X)
                      (set-car! (cdr (caddr first)) (list 'file "a.bin"))
                      (set-car! (cdr first) '("other" "y"))))
           (after (curl-request-body resolved)))
      (list answered fresh itself after))))

;; report-field : String String -> (U String #f)
;; The value of NAME=VALUE in the parts report TEXT's first line, or #f.
(define (report-field text name)
  (let* ((lines (split-text text #\newline))
         (words (if (pair? lines) (split-text (car lines) #\space) '()))
         (hit (find (lambda (w) (and (> (string-length w) (string-length name))
                                     (string=? (substring w 0 (+ 1 (string-length name)))
                                               (string-append name "="))))
                    words)))
    (and hit (substring hit (+ 1 (string-length name)) (string-length hit)))))

;; part : (Listof String) Bytevector -> Part
;; A part as it must arrive: its header lines, then its data.
(define (part headers data) (list headers data))

;; framed-parts : String (Listof Part) -> Bytevector
;; The body libcurl frames for PARTS by BOUNDARY: each part's delimiter, its
;; header lines, each ended by CR LF, an empty line, its data, CR LF; then
;; the closing delimiter and CR LF.
(define (framed-parts boundary parts)
  (call-with-bytevector-output-port
   (lambda (p)
     (for-each (lambda (pt)
                 (put-bytevector p (string->utf8 (string-append "--" boundary "\r\n")))
                 (for-each (lambda (h) (put-bytevector p (string->utf8 (string-append h "\r\n")))) (car pt))
                 (put-bytevector p (string->utf8 "\r\n"))
                 (put-bytevector p (cadr pt))
                 (put-bytevector p (string->utf8 "\r\n")))
               parts)
     (put-bytevector p (string->utf8 (string-append "--" boundary "--\r\n"))))))

;; render-report : String String String String (Listof Part) -> String
;; The parts route's whole report, written here, for PARTS framed by
;; BOUNDARY, sent by METHOD with EXPECT to FACE: its first line, cl and
;; bytes the body's length, te none, its SHA-256 computed here, no preamble,
;; the closing delimiter and its CR LF, then each part's line.
(define (render-report face method expect boundary parts)
  (let* ((body (framed-parts boundary parts))
         (n (number->string (bytevector-length body))))
    (apply string-append
           "parts " face " method=" method " cl=" n " te=- expect=" expect
           " ct=multipart/form-data;_boundary=" boundary " bytes=" n " sha256=" (sha256-hex body)
           " boundary=" boundary " preamble=0 closed=1 epilogue=2 count=" (number->string (length parts)) "\n"
           (let loop ((ps parts) (i 0) (found '()))
             (if (null? ps)
                 (reverse found)
                 (loop (cdr ps) (+ i 1)
                       (cons (string-append "part " (number->string i) " "
                                            (part-line (car (car ps)) (cadr (car ps))) "\n")
                             found)))))))

;; as-sent : String String String String (Listof Part) -> (U 'as-sent List)
;; Whether TEXT, a parts report, is render-report's whole, byte for byte,
;; by the boundary TEXT names: as-sent, or (differs TEXT WANT), or
;; (no-boundary TEXT). Every field is asserted: the method, cl, te, expect,
;; ct, the body's bytes and SHA-256, the preamble, the closing delimiter,
;; the epilogue, the count and each part's line.
(define (as-sent text face method expect parts)
  (let ((boundary (report-field text "boundary")))
    (if (or (not boundary) (string=? boundary "-"))
        (list 'no-boundary text)
        (let ((want (render-report face method expect boundary parts)))
          (if (string=? text want) 'as-sent (list 'differs text want))))))

;; outcome-as : Any String String String (Listof Part) -> List
;; A transfer's OUTCOME against PARTS: (STATUS as-sent), as-sent's verdict
;; on its report beside its status; (failed REASON CODE); or (other TEXT).
(define (outcome-as outcome face method expect parts)
  (cond ((curl-response? outcome)
         (list (curl-response-status outcome)
               (as-sent (guard (e (#t "")) (utf8->string (curl-response-body outcome))) face method expect parts)))
        ((curl-transfer-error? outcome)
         (list 'failed (curl-transfer-error-reason outcome) (curl-transfer-error-code outcome)))
        (else (list 'other (describe outcome)))))

;; brief : Any -> List
;; A transfer's OUTCOME, its report not read: (STATUS) or (failed REASON
;; CODE).
(define (brief outcome)
  (cond ((curl-response? outcome) (list (curl-response-status outcome)))
        ((curl-transfer-error? outcome)
         (list 'failed (curl-transfer-error-reason outcome) (curl-transfer-error-code outcome)))
        (else (list 'other (describe outcome)))))

;; escaped : Bytevector -> String
;; BYTES as the parts report shows them: \\ for a backslash, each byte 0x20
;; to 0x7E but | as itself, every other as \xNN.
(define (escaped bytes)
  (call-with-string-output-port
   (lambda (p)
     (for-each (lambda (b)
                 (cond ((= b #x5c) (put-string p "\\\\"))
                       ((and (>= b #x20) (< b #x7f) (not (= b #x7c))) (put-char p (integer->char b)))
                       (else (put-string p "\\x")
                             (when (< b 16) (put-char p #\0))
                             (put-string p (string-downcase (number->string b 16))))))
               (bytevector->u8-list bytes)))))

;; pattern-of : Bytevector -> String
(define (pattern-of bytes)
  (let loop ((k 0))
    (cond ((= k (bytevector-length bytes)) "ok")
          ((= (bytevector-u8-ref bytes k) (mod k 251)) (loop (+ k 1)))
          (else (string-append "bad@" (number->string k))))))

;; known-sha16 : (Listof (Pairof Natural String))
;; The first 16 hex digits of the SHA-256 of the pattern's first N bytes,
;; for the two lengths too long to hash here in good time, computed on the
;; host (sha256sum, and Python's hashlib, agreeing).
(define known-sha16 '((1048577 . "5769f52bc3eef28a") (4194304 . "a117210941a0b00d")))

;; sha16 : Bytevector -> String
;; DATA's SHA-256, its first 16 hex digits: known-sha16's for the pattern
;; at a length it names, else computed here.
(define (sha16 data)
  (let ((known (assv (bytevector-length data) known-sha16)))
    (if (and known (string=? (pattern-of data) "ok"))
        (cdr known)
        (substring (sha256-hex data) 0 16))))

;; part-line : (Listof String) Bytevector -> String
;; A part's report line after "part I ": HEADERS, its header lines, and its
;; DATA, as the parts route writes them, its SHA-256 sha16's.
(define (part-line headers data)
  (string-append "headers=" (let loop ((hs headers) (text ""))
                              (cond ((null? hs) text)
                                    ((string=? text "") (loop (cdr hs) (escaped (string->utf8 (car hs)))))
                                    (else (loop (cdr hs) (string-append text "|" (escaped (string->utf8 (car hs))))))))
                 " len=" (number->string (bytevector-length data))
                 " sha256=" (sha16 data)
                 " pattern=" (pattern-of data)
                 " data=" (if (<= (bytevector-length data) 256) (escaped data) "-")))

;; disposition : String (U String #f) -> String
(define (disposition name filename)
  (string-append "Content-Disposition: form-data; name=\"" name "\""
                 (if filename (string-append "; filename=\"" filename "\"") "")))

;; --- the origin's scenarios -------------------------------------------------------------

;; The run's PKI, for the h2 face.
(define pki-made
  (guard (e (#t (list 'raised (describe e))))
    (list 'made (make-test-pki))))
(define pki (and (eq? (car pki-made) 'made) (cadr pki-made)))
(define ca (and pki (string-append pki "/ca.pem")))

(test-equal "the run's PKI is made"
  'made
  (car pki-made))

;; hostport : Origin Symbol -> String
(define (hostport o face)
  (let ((f (origin-face o face))) (string-append (car f) ":" (number->string (cdr f)))))

;; face-url : Origin Symbol String -> String
(define (face-url o face path)
  (string-append (if (memq face '(raw http h2c)) "http://" "https://") (hostport o face) path))

;; face-keys : Symbol -> List
;; The keys a request to FACE needs: the run's CA file over TLS, and prior
;; knowledge on h2c.
(define (face-keys face)
  (case face
    ((h2) (list 'ca-file ca))
    ((h2c) (list 'http-version 'http/2-prior-knowledge))
    (else '())))

;; posted : Origin Symbol String Any Any ... -> Request
;; A post of BODY to PATH on FACE, direct, a 30 s bound, with KEYS after.
(define (posted o face path body . keys)
  (apply make-curl-request (face-url o face path) 'method 'post 'proxy #f 'timeout-ms 30000
         'body body (append (face-keys face) keys)))

;; with-engine : (Engine -> Any) -> Any
(define (with-engine proc)
  (let ((e (make-curl-engine)))
    (dynamic-wind (lambda () #f) (lambda () (proc e)) (lambda () (curl-engine-stop e)))))

;; sent-as : Request String String String (Listof Part) -> List
;; REQUEST's outcome, on an engine of its own, by outcome-as against PARTS,
;; sent by METHOD with EXPECT to FACE.
(define (sent-as request face method expect parts)
  (guard (e (#t (list 'raised (describe e))))
    (with-engine
     (lambda (e)
       (let ((token (curl-submit e request)))
         (if (curl-token-wait token 40000)
             (outcome-as (curl-token-outcome token) face method expect parts)
             (list 'not-ended)))))))

;; seen : Origin String -> (U Natural List)
;; The origin's count for KEY, by the http face's /seen.
(define (seen o key)
  (guard (e (#t (list 'raised (describe e))))
    (with-engine
     (lambda (e)
       (let* ((r (curl-token-await (curl-submit e (make-curl-request (face-url o 'http (string-append "/seen?key=" key))
                                                                     'proxy #f 'timeout-ms 10000))))
              (text (utf8->string (curl-response-body r))))
         (string->number (substring text 5 (- (string-length text) 1))))))))

;; wait-seen : Origin String Natural Natural -> Boolean
;; Whether KEY's count reaches N within MS milliseconds.
(define (wait-seen o key n ms)
  (let ((deadline (+ (now-ms) ms)))
    (let loop ()
      (let ((c (seen o key)))
        (cond ((and (integer? c) (>= c n)) #t)
              ((> (now-ms) deadline) #f)
              (else (pause-ms 20) (loop)))))))

;; release : Origin String -> Any
;; /raw/release?key=KEY, on an engine of its own: the raw face closes after
;; each script, so no connection to it is kept.
(define (release o key)
  (guard (e (#t (list 'raised (describe e))))
    (with-engine
     (lambda (e)
       (curl-response-status
        (curl-token-await (curl-submit e (make-curl-request (face-url o 'raw (string-append "/raw/release?key=" key))
                                                            'proxy #f 'timeout-ms 10000))))))))

;; octet-part : (Listof String) -> Part
;; The part a.bin makes, its default type, the pattern's 300 bytes.
(define (a-bin-part name)
  (part (list (disposition name "a.bin") "Content-Type: application/octet-stream") (pattern-bytes 300)))

;; engine-held : Origin Symbol String -> Request
;; A post of PARTS to FACE's parts route, held: Expect: 100-continue
;; asked, the 100 held until /raw/release names KEY, EXPECT_100_TIMEOUT_MS
;; at 60 s through the hatch, a timeout-ms of 20 s.
(define (engine-held o face key parts)
  (curl-request-with-options
   (apply make-curl-request (face-url o face (string-append "/parts?key=" key "&hold=1"))
          'method 'post 'proxy #f 'headers '(("Expect" . "100-continue")) 'timeout-ms 20000
          'body (cons 'multipart parts) (face-keys face))
   '(("EXPECT_100_TIMEOUT_MS" . 60000))))

(define (scenarios o)
  ;; --- the wire: each part kind, its options and the default types ----------------------
  (test-equal "each part kind and its options, byte for byte at the origin, over HTTP/1.1, the whole report: a string's UTF-8; a bytevector's bytes; a file's, its filename its path's last component; a filename and a type given; and libcurl's default types, text/plain for .TXT in any case, application/octet-stream for a file of no known extension, none for data with no filename, and the path's own for a file whose filename libcurl does not know; empty data; a name and a filename past ASCII, as UTF-8, and a name's leading U+FEFF kept"
    '(200 as-sent)
    (sent-as (posted o 'http (string-append "/parts?key=" (next-key "kinds"))
                     (list 'multipart
                           (list "s" "a string, sent as UTF-8: \xE9;")
                           (list "s2" "with a filename" 'filename "s.dat")
                           (list "s3" "with a type" 'type "text/x-chez")
                           (list "b" (bytes 0 1 2 255))
                           (list "b2" (bytes 104 105) 'filename "b.TXT")
                           (list "f" (list 'file file-a))
                           (list "f2" (list 'file file-txt) 'filename "renamed.bin")
                           (list "f3" (list 'file file-a) 'type "image/x-a")
                           (list "e" "")
                           (list "nom-\xE9;" "x" 'filename "\x3BB;.txt")
                           (list "\xFEFF;bom" "x")))
             "http" "POST" "-"
             (list (part (list (disposition "s" #f)) (string->utf8 "a string, sent as UTF-8: \xE9;"))
                   (part (list (disposition "s2" "s.dat")) (string->utf8 "with a filename"))
                   (part (list (disposition "s3" #f) "Content-Type: text/x-chez") (string->utf8 "with a type"))
                   (part (list (disposition "b" #f)) (bytes 0 1 2 255))
                   (part (list (disposition "b2" "b.TXT") "Content-Type: text/plain") (bytes 104 105))
                   (a-bin-part "f")
                   (part (list (disposition "f2" "renamed.bin") "Content-Type: text/plain")
                         (string->utf8 "a text file\n"))
                   (part (list (disposition "f3" "a.bin") "Content-Type: image/x-a") (pattern-bytes 300))
                   (part (list (disposition "e" #f)) (bytes))
                   (part (list (disposition "nom-\xE9;" "\x3BB;.txt") "Content-Type: text/plain") (string->utf8 "x"))
                   (part (list (disposition "\xFEFF;bom" #f)) (string->utf8 "x")))))

  (test-equal "the default types, by the filename's extension, for a data part with a filename: text/plain, text/html, image/gif, image/jpeg, image/png, image/svg+xml, application/pdf and application/xml; none for .json, .csv and none at all; a file part's application/octet-stream there; each the whole report"
    (map (lambda (row) '(200 as-sent))
         '("t.txt" "t.htm" "t.html" "t.gif" "t.jpg" "t.jpeg" "t.png" "t.svg" "t.pdf" "t.xml" "t.json" "t.csv" "t"))
    (map (lambda (row)
           (let ((name (car row)) (type (cadr row)))
             (let ((path (in-scratch name)))
               (guard (e (#t (list 'raised (describe e))))
                 (write-bytes path (bytes 120))
                 (sent-as (posted o 'http (string-append "/parts?key=" (next-key "types"))
                                  (list 'multipart (list "d" (bytes 1) 'filename name)
                                        (list "f" (list 'file path))))
                          "http" "POST" "-"
                          (list (part (if type
                                          (list (disposition "d" name) (string-append "Content-Type: " type))
                                          (list (disposition "d" name)))
                                      (bytes 1))
                                (part (list (disposition "f" name)
                                            (string-append "Content-Type: " (or type "application/octet-stream")))
                                      (bytes 120))))))))
         '(("t.txt" "text/plain") ("t.htm" "text/html") ("t.html" "text/html") ("t.gif" "image/gif")
           ("t.jpg" "image/jpeg") ("t.jpeg" "image/jpeg") ("t.png" "image/png") ("t.svg" "image/svg+xml")
           ("t.pdf" "application/pdf") ("t.xml" "application/xml") ("t.json" #f) ("t.csv" #f) ("t" #f))))

  ;; Beside MIMEPOST the Content-Type: blank sent "Content-Type: ;
  ;; boundary=B", every part an attachment; past 1 MiB libcurl adds Expect:
  ;; 100-continue over HTTP/1.1 and waits a second for a server that never
  ;; answers, which the Expect: blank removes (ADR-0039, context).
  (test-equal "every method that sends a body, over HTTP/1.1, h2c and h2: post, put, patch and delete each send multipart/form-data with the body's own boundary, every part form-data, the body whole, no Expect, closed by its delimiter: the whole report"
    (map (lambda (face) (map (lambda (method) '(200 as-sent)) '(post put patch delete))) '(http h2c h2))
    (map (lambda (face)
           (map (lambda (method)
                  (sent-as (apply make-curl-request (face-url o face (string-append "/parts?key=" (next-key "methods")))
                                  'method method 'proxy #f 'timeout-ms 30000
                                  'body (list 'multipart (list "a" "x") (list "f" (list 'file file-a)))
                                  (face-keys face))
                           (symbol->string face) (string-upcase (symbol->string method)) "-"
                           (list (part (list (disposition "a" #f)) (string->utf8 "x")) (a-bin-part "f"))))
                '(post put patch delete)))
         '(http h2c h2)))

  (test-equal "a data part of 1 MiB and one byte, over HTTP/1.1: the whole report, its expect field - , so the Expect: blank held past libcurl's 1 MiB threshold"
    '(200 as-sent)
    ;; No clock: the origin answers a 100 at once, so a client that sent
    ;; Expect would not wait either. The report's expect field is what
    ;; shows none went.
    (guard (e (#t (list 'raised (describe e))))
      (with-engine
       (lambda (e)
         (let* ((request (posted o 'http (string-append "/parts?key=" (next-key "big"))
                                 (list 'multipart (list "big" (pattern-bytes 1048577)))))
                (token (curl-submit e request)))
           (if (curl-token-wait token 40000)
               (outcome-as (curl-token-outcome token) "http" "POST" "-"
                           (list (part (list (disposition "big" #f)) (pattern-bytes 1048577))))
               (list 'not-ended)))))))

  ;; The cap on response headers (ADR-0040) beside the mime: slice 2's
  ;; callable and MIMEPOST sit together.
  (test-equal "the header cap beside a multipart body: 1,000 header lines answer the whole report; 1,001 refuse the transfer, header-limit, too large"
    (list '(200 as-sent) '(refused header-limit too-large))
    (list (sent-as (posted o 'http (string-append "/parts?key=" (next-key "cap") "&lines=1000")
                           '(multipart ("a" "x")))
                   "http" "POST" "-" (list (part (list (disposition "a" #f)) (string->utf8 "x"))))
          (guard (e (#t (list 'raised (describe e))))
            (with-engine
             (lambda (e)
               (let ((token (curl-submit e (posted o 'http (string-append "/parts?key=" (next-key "cap") "&lines=1001")
                                                   '(multipart ("a" "x"))))))
                 (curl-token-wait token 30000)
                 (let ((outcome (curl-token-outcome token)))
                   (if (curl-transfer-error? outcome)
                       (list 'refused (curl-transfer-error-reason outcome)
                             (if (curl-too-large? outcome) 'too-large 'other))
                       (list 'not-refused (brief outcome))))))))))

  ;; --- the copies, at the origin ----------------------------------------------------------
  (test-equal "each metadata string and the list, changed once the request is made, then submitted: the origin gets the name, filename and type the request was made with, and the path's file: the whole report"
    '(200 as-sent)
    (let* ((name (string-copy "name")) (filename (string-copy "file.txt")) (type (string-copy "type/x"))
           (path (string-copy file-a))
           (a-part (list name "data" 'filename filename 'type type))
           (body (list 'multipart a-part (list "f" (list 'file path))))
           (r (posted o 'http (string-append "/parts?key=" (next-key "mutated")) body)))
      (string-set! name 0 #\N)
      (string-set! filename 0 #\F)
      (string-set! type 0 #\T)
      (string-set! path (- (string-length path) 5) #\b)
      (set-car! (cdr body) (list "other" "y"))
      (sent-as r "http" "POST" "-"
               (list (part (list (disposition "name" "file.txt") "Content-Type: type/x") (string->utf8 "data"))
                     (a-bin-part "f")))))

  (test-equal "the accessor's copy changed: its name, its path and its pairs, then submitted: the origin gets what the request was made with: the whole report"
    '(200 as-sent)
    (let* ((r (posted o 'http (string-append "/parts?key=" (next-key "accessor"))
                      (list 'multipart (list "n" "v") (list "f" (list 'file file-a)))))
           (copy (curl-request-body r)))
      (string-set! (car (cadr copy)) 0 #\X)
      (set-car! (cdr (caddr copy)) (list 'file file-txt))
      (set-cdr! (cdr copy) '())
      (sent-as r "http" "POST" "-" (list (part (list (disposition "n" #f)) (string->utf8 "v")) (a-bin-part "f")))))

  ;; The data is copied at submit alone, as a whole body is (ADR-0023,
  ;; decision 4): a change before the submit is sent; one after it is not.
  ;; The private gate holds the engine's thread at the file check, before
  ;; the transfer's setup, until this thread has made its change, so the
  ;; change lands after the submit and before the mime is made.
  (test-equal "a part's data is copied at submit, not when the request is made: a bytevector and a string changed before the submit are sent changed; changed after the submit returns, held by the gate before the mime is made, the submit's bytes are sent: each the whole report"
    '((200 as-sent) (200 as-sent) gate-ran)
    (let* ((octets (bytes 1 2 3)) (text (string-copy "sxy"))
           (want (list (part (list (disposition "b" #f)) (bytes 66 2 3))
                       (part (list (disposition "s" #f)) (string->utf8 "Sxy"))
                       (a-bin-part "f")))
           (r (posted o 'http (string-append "/parts?key=" (next-key "data"))
                      (list 'multipart (list "b" octets) (list "s" text) (list "f" (list 'file file-a))))))
      (bytevector-u8-set! octets 0 66)
      (string-set! text 0 #\S)
      (let ((before (sent-as r "http" "POST" "-" want))
            (lock (make-mutex)) (state (vector 'waiting)))
        (guard (e (#t (transfer-file-check-gate-set! #f) (list 'raised (describe e))))
          (transfer-file-check-gate-set!
           (lambda ()
             (critical-section (with-mutex lock (vector-set! state 0 'held)))
             (let loop ((n 0))
               (unless (or (eq? (critical-section (with-mutex lock (vector-ref state 0))) 'changed) (> n 500))
                 (pause-ms 10)
                 (loop (+ n 1))))))
          (let ((after
                 (with-engine
                  (lambda (e)
                    (let ((token (curl-submit e r)))
                      (let wait ((n 0))
                        (unless (or (eq? (critical-section (with-mutex lock (vector-ref state 0))) 'held) (> n 500))
                          (pause-ms 10)
                          (wait (+ n 1))))
                      (bytevector-u8-set! octets 0 99)
                      (string-set! text 0 #\Z)
                      (critical-section (with-mutex lock (vector-set! state 0 'changed)))
                      (if (curl-token-wait token 30000)
                          (outcome-as (curl-token-outcome token) "http" "POST" "-" want)
                          (list 'not-ended)))))))
            (transfer-file-check-gate-set! #f)
            (list before after (if (eq? (vector-ref state 0) 'changed) 'gate-ran (vector-ref state 0))))))))

  ;; The working directory is the process's: a path resolved again at a
  ;; later submit would meet a chdir made between (ADR-0039, amended
  ;; 2026-11-06).
  (test-equal "a relative path is resolved as the request is made: submitted from another directory, whose file of that name differs, the origin gets the first directory's file: the whole report"
    '(200 as-sent)
    (guard (e (#t (list 'raised (describe e))))
      (let ((one (make-directory (in-scratch "dir-one"))) (two (make-directory (in-scratch "dir-two"))))
        (write-bytes (string-append one "/same.bin") (string->utf8 "first"))
        (write-bytes (string-append two "/same.bin") (string->utf8 "other"))
        (let ((r (parameterize ((current-directory one))
                   (posted o 'http (string-append "/parts?key=" (next-key "relative"))
                           '(multipart ("f" (file "same.bin")))))))
          (parameterize ((current-directory two))
            (sent-as r "http" "POST" "-"
                     (list (part (list (disposition "f" "same.bin") "Content-Type: application/octet-stream")
                                 (string->utf8 "first")))))))))

  ;; --- the engine's check (ADR-0039, amended 2026-11-06, decision 1) -----------------------
  ;; The gate changes the path after the submit's stat and before the
  ;; engine's: a check skipped would send a directory as an empty part,
  ;; answered 200, and a path removed would fail at curl_mime_filedata with
  ;; its code, 26, where the engine's check fails with none. A file made
  ;; unreadable, mode 000, passes every stat and fails the engine's open
  ;; alone: its row holds the suite's own open of it too, which must fail,
  ;; or the row says why it proves nothing (a run as root opens it).
  (test-equal "the engine's check, before the transfer's setup: a path removed, made a directory, made a FIFO, or made unreadable, mode 000, after the submit's stat fails the transfer part-file, no code, nothing sent, a request size of 0, the origin never counting it, the unreadable file one this suite cannot open either; a symbolic link to a regular file passes"
    '((failed part-file #f 0 0) (failed part-file #f 0 0) (failed part-file #f 0 0)
      (failed part-file #f 0 0 unopenable-here) (passed 200))
    (map (lambda (change)
           (let ((path (in-scratch (next-key "engine-check"))) (key (next-key "engine-check")))
             (guard (e (#t (transfer-file-check-gate-set! #f) (list 'raised (describe e))))
               (write-bytes path (pattern-bytes 50))
               (let ((r (posted o 'http (string-append "/parts?key=" key)
                                (list 'multipart (list "a" "x") (list "f" (list 'file path))))))
                 (transfer-file-check-gate-set!
                  (lambda ()
                    (case change
                      ((unreadable) (chmod path #o000))
                      (else
                       (delete-file path)
                       (case change
                         ((dir) (make-directory path))
                         ((fifo) (mkfifo path))
                         ((link) (system (string-append "ln -s " (shell-word file-a) " " (shell-word path)))))))))
                 (let* ((outcome (with-engine
                                  (lambda (e)
                                    (let ((token (curl-submit e r)))
                                      (if (curl-token-wait token 30000) (curl-token-outcome token) 'not-ended)))))
                        (here (and (eq? change 'unreadable)
                                   (guard (e ((i/o-error? e) 'unopenable-here))
                                     (close-port (open-file-input-port path))
                                     'opened-here-as-root-the-row-proves-nothing))))
                   (transfer-file-check-gate-set! #f)
                   (when (eq? change 'unreadable) (chmod path #o644))
                   (cond ((curl-transfer-error? outcome)
                          (append (list 'failed (curl-transfer-error-reason outcome) (curl-transfer-error-code outcome)
                                        (curl-transfer-error-request-size outcome) (seen o key))
                                  (if here (list here) '())))
                         ((curl-response? outcome) (list 'passed (curl-response-status outcome)))
                         (else (list 'other outcome))))))))
         '(removed dir fifo unreadable link)))

  ;; libcurl's own answer: the mime gate removes the path after the
  ;; engine's check, before curl_mime_filedata, which then refuses it with
  ;; CURLE_READ_ERROR, 26, on every lane (mime-files, case C-missing).
  (test-equal "a path lost between the engine's check and curl_mime_filedata meets libcurl's own refusal, 26: the transfer fails part-file, that code, a request size of 0, the origin never counting it"
    '(failed part-file 26 0 0)
    (let ((path (in-scratch (next-key "filedata"))) (key (next-key "filedata")))
      (guard (e (#t (transfer-mime-gate-set! #f) (list 'raised (describe e))))
        (write-bytes path (pattern-bytes 50))
        (let ((r (posted o 'http (string-append "/parts?key=" key)
                         (list 'multipart (list "a" "x") (list "f" (list 'file path))))))
          (transfer-mime-gate-set! (lambda () (delete-file path)))
          (let ((outcome (with-engine
                          (lambda (e)
                            (let ((token (curl-submit e r)))
                              (if (curl-token-wait token 30000) (curl-token-outcome token) 'not-ended))))))
            (transfer-mime-gate-set! #f)
            (if (curl-transfer-error? outcome)
                (list 'failed (curl-transfer-error-reason outcome) (curl-transfer-error-code outcome)
                      (curl-transfer-error-request-size outcome) (seen o key))
                (list 'other (brief outcome))))))))

  ;; No libcurl refuses a part the request's rules let through, so the
  ;; private seam plants the answer, after making the call.
  (test-equal "a part libcurl refuses fails the transfer before it starts, its mime freed: mime-failed for curl_mime_name's 43, part-file for curl_mime_filedata's 26, each with its code, a request size of 0, nothing sent; and every count is zero after"
    (list '(failed mime-failed 43 0 0) '(failed part-file 26 0 0) zero-counts)
    (let ((one (lambda (planted)
                 (let ((key (next-key "planted")))
                   (guard (e (#t (transfer-mime-answer-set! #f) (list 'raised (describe e))))
                     (transfer-mime-answer-set! planted)
                     (let ((outcome (with-engine
                                     (lambda (e)
                                       (let ((token (curl-submit e (posted o 'http (string-append "/parts?key=" key)
                                                                           (list 'multipart (list "a" "x")
                                                                                 (list "f" (list 'file file-a)))))))
                                         (if (curl-token-wait token 30000) (curl-token-outcome token) 'not-ended))))))
                       (transfer-mime-answer-set! #f)
                       (if (curl-transfer-error? outcome)
                           (list 'failed (curl-transfer-error-reason outcome) (curl-transfer-error-code outcome)
                                 (curl-transfer-error-request-size outcome) (seen o key))
                           (list 'other (brief outcome)))))))))
      (let* ((a (one '(0 name . 43))) (b (one '(1 filedata . 26))))
        (list a b (native-counts)))))

  ;; A live multipart transfer, held at the origin with its mime made,
  ;; cancelled, then another stopped with its engine: each mime freed with
  ;; its handle, every count back to the engine's own, then zero.
  (test-equal "a live multipart transfer, held at the origin, cancelled, ends cancelled, the engine's own block and multi handle all it still counts; another, its engine stopped, ends stopped, and every count is zero"
    (list 'cancelled engine-counts 'stopped zero-counts)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((parts (list (list "a" "x") (list "f" (list 'file file-a))))
             (cancelled
              (with-engine
               (lambda (e)
                 (let* ((key (next-key "cancel"))
                        (token (curl-submit e (engine-held o 'http key parts))))
                   (wait-seen o key 1 10000)
                   (curl-token-cancel token)
                   (let ((outcome (if (curl-token-wait token 20000) (curl-token-outcome token) 'not-ended)))
                     (release o key)
                     (list (if (curl-transfer-error? outcome) (curl-transfer-error-reason outcome) outcome)
                           (native-counts)))))))
             (stopped
              (let* ((e (make-curl-engine))
                     (key (next-key "stop"))
                     (token (curl-submit e (engine-held o 'http key parts))))
                (wait-seen o key 1 10000)
                (curl-engine-stop e)
                (release o key)
                (let ((outcome (if (curl-token-wait token 20000) (curl-token-outcome token) 'not-ended)))
                  (list (if (curl-transfer-error? outcome) (curl-transfer-error-reason outcome) outcome)
                        (native-counts))))))
        (append cancelled stopped))))

  ;; --- the high level (the M8 plan, section 3.1) ---------------------------------------------
  (let ((want (list (part (list (disposition "title" #f)) (string->utf8 "Holiday")) (a-bin-part "photo"))))
    (test-equal "the high level's multipart key: a post sends the parts, the session's Content-Type header dropped; through a 307 and a 308 each hop sends them again, whole; a 303 sends a get with no body; a group, http-parallel's two calls, sends each: each the whole report"
      (list '(200 as-sent) '(200 as-sent) '(200 as-sent)
            '(200 "parts http method=GET cl=- te=- expect=- ct=- bytes=0 sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 boundary=- preamble=- closed=0 epilogue=- count=0\n")
            '((200 as-sent) (200 as-sent)))
      (guard (e (#t (list 'raised (describe e))))
        (call-with-http-session 'proxy #f 'timeout-ms 30000 'headers '(("Content-Type" . "text/plain"))
          (lambda (s)
            (let ((parts (list (list "title" "Holiday") (list "photo" (list 'file file-a))))
                  (answer (lambda (method)
                            (lambda (r)
                              (list (http-response-status r)
                                    (as-sent (utf8->string (http-response-body r)) "http" method "-" want)))))
                  (hop (lambda (code)
                         (face-url o 'http (string-append "/redirect/" code "?to=%2Fparts%3Fkey%3D" (next-key "hop"))))))
              (list ((answer "POST") (http-post s (face-url o 'http (string-append "/parts?key=" (next-key "hl")))
                                                'multipart parts))
                    ((answer "POST") (http-post s (hop "307") 'multipart parts))
                    ((answer "POST") (http-post s (hop "308") 'multipart parts))
                    (let ((r (http-post s (hop "303") 'multipart parts)))
                      (list (http-response-status r) (utf8->string (http-response-body r))))
                    (let ((rs (http-parallel s (list (list 'post (face-url o 'http (string-append "/parts?key=" (next-key "group")))
                                                           'multipart parts)
                                                     (list 'put (face-url o 'http (string-append "/parts?key=" (next-key "group")))
                                                           'multipart parts)))))
                      (list ((answer "POST") (car rs)) ((answer "PUT") (cadr rs)))))))))))

  ;; A retry's wait lies between the call's first transfer and its second:
  ;; this thread waits until the origin has counted the first, then changes
  ;; the caller's bytevector and the working directory. The call took both
  ;; once, as it started, so the second sends what the first did.
  (test-equal "the high level takes a part's data and a relative path once, as the call starts: a retry, its first transfer answered 503 by fail=1, sends the bytes and the file the call began with, though the caller's bytevector and the working directory changed during its wait: the whole report"
    '((answered 200 as-sent) 2)
    (guard (e (#t (list 'raised (describe e))))
      (let ((key (next-key "retry")) (octets (bytes 1 2 3))
            (one (in-scratch "dir-one")) (two (in-scratch "dir-two"))
            (lock (make-mutex)) (box (vector #f)))
        (parameterize ((current-directory one))
          (fork-thread
           (lambda ()
             (let ((answer
                    (guard (e (#t (list 'raised (describe e))))
                      (call-with-http-session 'proxy #f 'timeout-ms 30000
                        'retry (make-http-retry 'attempts 2 'backoff-ms 800 'jitter #f 'statuses '(503)
                                                'methods '(post))
                        (lambda (s)
                          (let ((r (http-post s (face-url o 'http (string-append "/parts?key=" key "&fail=1"))
                                              'multipart (list (list "d" octets) (list "f" '(file "same.bin"))))))
                            (list 'answered (http-response-status r)
                                  (as-sent (utf8->string (http-response-body r)) "http" "POST" "-"
                                           (list (part (list (disposition "d" #f)) (bytes 1 2 3))
                                                 (part (list (disposition "f" "same.bin")
                                                             "Content-Type: application/octet-stream")
                                                       (string->utf8 "first")))))))))))
               (critical-section (with-mutex lock (vector-set! box 0 answer))))))
          (wait-seen o key 1 20000)
          (bytevector-u8-set! octets 0 99)
          (current-directory two))
        (let loop ((n 0))
          (let ((answer (critical-section (with-mutex lock (vector-ref box 0)))))
            (cond (answer (list answer (seen o key)))
                  ((> n 3000) (list 'no-answer))
                  (else (pause-ms 10) (loop (+ n 1)))))))))

  ;; A file part's file lost mid-call, four ways, each removed only once the
  ;; origin has counted the call's first request: a 307 hop, the raw face
  ;; answering it a second on; a retry with the session's timeout-ms, and
  ;; one with no bound, each after fail=1's 503; and a group's 307 hop.
  ;; Each hop and each retry is made with no file system call, its body
  ;; kept as the last request held it, so each is refused alike, at its
  ;; submit's stat (ADR-0023, after slice 3's review).
  (let* ((lost (lambda (name start)
                 ;; START's call, its file NAME removed once KEY's first request is counted
                 (let* ((key (next-key name))
                        (path (in-scratch (string-append key ".bin")))
                        (made (write-bytes path (pattern-bytes 10)))
                        (lock (make-mutex)) (box (vector #f)))
                   (fork-thread
                    (lambda ()
                      (let ((answer (guard (e ((curl-request-error? e)
                                               (list 'refused (and (who-condition? e) (condition-who e))
                                                     (curl-request-error-field e) (curl-request-error-value e)
                                                     (curl-request-error-reason e)
                                                     (if (http-exchange? e) 'with-exchange 'no-exchange)))
                                              (#t (list 'raised (describe e))))
                                      (start key path)
                                      'no-raise)))
                        (critical-section (with-mutex lock (vector-set! box 0 answer))))))
                   (let ((seen-first (wait-seen o key 1 20000)))
                     (when (file-exists? path) (delete-file path))
                     (let loop ((n 0))
                       (let ((answer (critical-section (with-mutex lock (vector-ref box 0)))))
                         (cond (answer (list (if seen-first 'removed-after-the-first answer) answer))
                               ((> n 4000) (list 'no-answer))
                               (else (pause-ms 10) (loop (+ n 1))))))))))
         (delayed-307 (lambda (key)
                        (let ((f (origin-face o 'http)))
                          (face-url o 'raw (string-append "/raw/location?code=307&ms=1000&key=" key
                                                          "&to=http%3A%2F%2F" (car f) "%3A" (number->string (cdr f))
                                                          "%2Fparts%3Fkey%3D" key "-hop")))))
         (retry (make-http-retry 'attempts 2 'backoff-ms 1000 'jitter #f 'statuses '(503) 'methods '(post))))
    (test-equal "a file part's file lost mid-call fails alike four ways, each at its submit's stat: a 307 hop, a retry with the session's timeout-ms, a retry with no bound, and a group's 307 hop each raise curl-submit's part-file, field body, value (part 0 path), compounded with &http-exchange, the file removed only once the origin counted the call's first request"
      (let ((want '(refused curl-submit body (part 0 path) part-file with-exchange)))
        (list (list 'removed-after-the-first want) (list 'removed-after-the-first want)
              (list 'removed-after-the-first want) (list 'removed-after-the-first want)))
      (list (lost "lost-hop"
                  (lambda (key path)
                    (call-with-http-session 'proxy #f
                      (lambda (s) (http-post s (delayed-307 key) 'multipart (list (list "f" (list 'file path))))))))
            (lost "lost-retry-bounded"
                  (lambda (key path)
                    (call-with-http-session 'proxy #f 'timeout-ms 30000 'retry retry
                      (lambda (s) (http-post s (face-url o 'http (string-append "/parts?key=" key "&fail=1"))
                                             'multipart (list (list "f" (list 'file path))))))))
            (lost "lost-retry-unbounded"
                  (lambda (key path)
                    (call-with-http-session 'proxy #f 'retry retry
                      (lambda (s) (http-post s (face-url o 'http (string-append "/parts?key=" key "&fail=1"))
                                             'multipart (list (list "f" (list 'file path))))))))
            (lost "lost-group-hop"
                  (lambda (key path)
                    (call-with-http-session 'proxy #f
                      (lambda (s) (http-parallel s (list (list 'post (delayed-307 key)
                                                               'multipart (list (list "f" (list 'file path)))))))))))))

  ;; --- the table ---------------------------------------------------------------------
  (table-scenarios o)
  'done)

;; --- the per-version table (ADR-0017; the M8 plan, section 3.8) -----------------------------

;; after-answer : Any String String (Listof Part) -> List
;; A transfer's outcome as a cell: (response STATUS whole), the whole
;; report as-sent's for PARTS sent to FACE with EXPECT; (response STATUS
;; unterminated) for a body whose closing delimiter never came; (response
;; STATUS parts-differ TEXT), what came; (response STATUS) when it is no
;; report; or (failed REASON CODE).
(define (after-answer outcome face expect parts)
  (cond ((curl-response? outcome)
         (let* ((status (curl-response-status outcome))
                (text (guard (e (#t "")) (utf8->string (curl-response-body outcome)))))
           (cond ((not (and (>= (string-length text) 6) (string=? (substring text 0 6) "parts ")))
                  (list 'response status))
                 ((eq? (as-sent text face "POST" expect parts) 'as-sent) (list 'response status 'whole))
                 ((equal? (report-field text "closed") "0") (list 'response status 'unterminated))
                 (else (list 'response status 'parts-differ text)))))
        ((curl-transfer-error? outcome)
         (list 'failed (curl-transfer-error-reason outcome) (curl-transfer-error-code outcome)))
        (else (list 'other (describe outcome)))))

;; after-cell : Origin Symbol Symbol -> List
;; A file part changed once the origin holds the request's head, after the
;; engine's check and curl_mime_filedata, before libcurl reads it: the head
;; waits for the 100 that the parts route holds until /raw/release names
;; its key, Expect: 100-continue asked, EXPECT_100_TIMEOUT_MS at 60 s
;; through the hatch. CHANGE is grown, 2,000 bytes appended to its 3,000;
;; shrunk, cut to 1,000, with a timeout-ms of 3,000; shrunk-none, cut so,
;; with none, judged stalled when 1,500 ms after the release pass with no
;; end; removed; or fifo, the path made a FIFO whose writer, a process of
;; its own, writes the 3,000 bytes a second on, and is killed once the
;; cell ends. The cell adds held for an end 800 ms or more after the
;; release.
(define (after-cell o face change)
  (let* ((key (next-key "after"))
         (p (in-scratch (string-append key ".bin")))
         (src (in-scratch (string-append key ".src")))
         (parts (list (list "before" "first") (list "f" (list 'file p)) (list "after" "last")))
         (want (list (part (list (disposition "before" #f)) (string->utf8 "first"))
                     (part (list (disposition "f" (string-append key ".bin")) "Content-Type: application/octet-stream")
                           (pattern-bytes 3000))
                     (part (list (disposition "after" #f)) (string->utf8 "last"))))
         (writer #f))
    (guard (e (#t (list 'raised (describe e))))
      (write-bytes p (pattern-bytes 3000))
      (write-bytes src (pattern-bytes 3000))
      (let ((request (curl-request-with-options
                      (apply make-curl-request (face-url o face (string-append "/parts?key=" key "&hold=1"))
                             'method 'post 'proxy #f 'headers '(("Expect" . "100-continue"))
                             'body (cons 'multipart parts)
                             (append (case change ((shrunk) '(timeout-ms 3000)) ((shrunk-none) '()) (else '(timeout-ms 20000)))
                                     (face-keys face)))
                      '(("EXPECT_100_TIMEOUT_MS" . 60000)))))
        (dynamic-wind
          (lambda () #f)
          (lambda ()
            (with-engine
             (lambda (e)
               (let* ((token (curl-submit e request))
                      (held (wait-seen o key 1 10000)))
                 (case change
                   ((grown) (append-bytes p (make-bytevector 2000 90)))
                   ((shrunk shrunk-none) (write-bytes p (pattern-bytes 1000)))
                   ((removed) (delete-file p))
                   ((fifo)
                    (delete-file p)
                    (mkfifo p)
                    (let-values (((to from err pid)
                                  (open-process-ports
                                   (string-append "exec sh -c " (shell-word (string-append "sleep 1; exec cat "
                                                                                           (shell-word src) " > "
                                                                                           (shell-word p)))))))
                      (set! writer (list pid to from err)))))
                 (let ((released (now-ms)))
                   (release o key)
                   (let ((ended (curl-token-wait token (if (eq? change 'shrunk-none) 1500 20000))))
                     (cond ((not held) (list 'never-held))
                           ((not ended) (list 'stalled))
                           (else
                            (let ((answer (after-answer (curl-token-outcome token) (symbol->string face)
                                                        "100-continue" want)))
                              (if (>= (- (now-ms) released) 800) (append answer '(held)) answer))))))))))
          (lambda ()
            (when writer
              (system (string-append "kill " (number->string (car writer)) " 2>/dev/null"))
              (for-each (lambda (port) (guard (e (#t #f)) (close-port port))) (cdr writer)))))))))

;; resend-cell : Origin Symbol Symbol -> List
;; A request libcurl sends again inside its transfer, its body whole each
;; time: kill, the http face's next request on a connection a warm
;; /close-after?then=kill marked, read whole and left unanswered, so libcurl
;; resends on a fresh connection; refused, h2c's /refuse?at=0, the stream
;; refused at its HEADERS and the next request answered as /sink, its sum
;; held against the body rebuilt here; 307, libcurl following a 307, its
;; FOLLOWLOCATION the private seam's, to the parts route, as follow; reset, a part of
;; 4 MiB to a connection a warm /close-after?then=resethead marked, reset
;; as its head arrives, which libcurl resends or fails by a race. KIND is
;; data or file. The cell is after-answer's, then the origin's count for
;; the key.
(define (resend-cell o how kind)
  (let* ((key (next-key (string-append "resend-" (symbol->string how))))
         (data (if (eq? how 'reset) #f (pattern-bytes 3000)))
         (path (in-scratch (string-append key ".bin")))
         (parts (list (list "field" "value")
                      (if (eq? kind 'data) (list "d" data) (list "f" (list 'file path)))))
         (want (list (part (list (disposition "field" #f)) (string->utf8 "value"))
                     (if (eq? kind 'data)
                         (part (list (disposition "d" #f)) data)
                         (part (list (disposition "f" (string-append key ".bin"))
                                     "Content-Type: application/octet-stream")
                               (pattern-bytes (if (eq? how 'reset) (* 4 1024 1024) 3000)))))))
    (guard (e (#t (list 'raised (describe e))))
      (when (eq? kind 'file) (write-bytes path (pattern-bytes (if (eq? how 'reset) (* 4 1024 1024) 3000))))
      (with-engine
       (lambda (e)
         (case how
           ((kill reset)
            (curl-token-await (curl-submit e (make-curl-request
                                              (face-url o 'http (if (eq? how 'kill) "/close-after?then=kill"
                                                                    "/close-after?then=resethead"))
                                              'proxy #f 'timeout-ms 10000)))))
         (let* ((request (case how
                           ((kill reset) (posted o 'http (string-append "/parts?key=" key) (cons 'multipart parts)))
                           ((refused) (posted o 'h2c (string-append "/refuse?key=" key "&at=0") (cons 'multipart parts)))
                           ((follow) (curl-request-following
                                   (posted o 'http (string-append "/redirect/307?to=%2Fparts%3Fkey%3D" key)
                                           (cons 'multipart parts))))))
                (token (curl-submit e request))
                (outcome (if (curl-token-wait token 40000) (curl-token-outcome token) 'not-ended)))
           (append (if (eq? how 'refused)
                       (sink-answer outcome parts)
                       (after-answer outcome "http" "-" want))
                   (list (seen o key)))))))))

;; sink-answer : Any List -> List
;; The /sink summary's verdict for a multipart body of PARTS: (response
;; STATUS whole) when its bytes are the body libcurl frames for them, by
;; the boundary its Content-Type named, rebuilt here and its SHA-256
;; computed here; else what differed.
(define (sink-answer outcome parts)
  (cond ((curl-response? outcome)
         (let* ((text (guard (e (#t "")) (utf8->string (curl-response-body outcome))))
                (words (split-text text #\space))
                (field (lambda (name)
                         (let ((hit (find (lambda (w) (and (> (string-length w) (string-length name))
                                                           (string=? (substring w 0 (+ 1 (string-length name)))
                                                                     (string-append name "="))))
                                          words)))
                           (and hit (substring hit (+ 1 (string-length name)) (string-length hit))))))
                (ct (field "ct"))
                (prefix "multipart/form-data;_boundary="))
           (if (and ct (> (string-length ct) (string-length prefix))
                    (string=? (substring ct 0 (string-length prefix)) prefix))
               (let* ((boundary (substring ct (string-length prefix) (string-length ct)))
                      (body (framed boundary parts)))
                 (if (equal? (field "sha256") (sha256-hex body))
                     (list 'response (curl-response-status outcome) 'whole)
                     (list 'response (curl-response-status outcome) 'differs (field "bytes")
                           (bytevector-length body))))
               (list 'response (curl-response-status outcome) 'no-boundary))))
        ((curl-transfer-error? outcome)
         (list 'failed (curl-transfer-error-reason outcome) (curl-transfer-error-code outcome)))
        (else (list 'other (describe outcome)))))

;; framed : String List -> Bytevector
;; The body libcurl frames for data PARTS, each (NAME DATA), by BOUNDARY:
;; each part's delimiter, its Content-Disposition and an empty line, its
;; data, CR LF; then the closing delimiter and CR LF.
(define (framed boundary parts)
  (call-with-bytevector-output-port
   (lambda (p)
     (for-each (lambda (part)
                 (put-bytevector p (string->utf8 (string-append "--" boundary "\r\n" (disposition (car part) #f) "\r\n\r\n")))
                 (put-bytevector p (if (string? (cadr part)) (string->utf8 (cadr part)) (cadr part)))
                 (put-bytevector p (string->utf8 "\r\n")))
               parts)
     (put-bytevector p (string->utf8 (string-append "--" boundary "--\r\n"))))))

;; size-cell : Origin -> List
;; CURLINFO_REQUEST_SIZE for a post of a 3,000-byte part, as a failure
;; carries it: a body-limit of 10 bytes refuses the report once the whole
;; request has gone, by the report's Content-Length. head-alone below
;; 3,000, head-and-body above, unknown where reported-request-size answers
;; #f.
(define (size-cell o)
  (guard (e (#t (list 'raised (describe e))))
    (with-engine
     (lambda (e)
       (let* ((token (curl-submit e (posted o 'http (string-append "/parts?key=" (next-key "size"))
                                            (list 'multipart (list "d" (pattern-bytes 3000)))
                                            'body-limit 10)))
              (outcome (if (curl-token-wait token 30000) (curl-token-outcome token) 'not-ended)))
         (if (curl-transfer-error? outcome)
             (let ((size (curl-transfer-error-request-size outcome)))
               (cond ((not size) 'unknown)
                     ((< size 3000) 'head-alone)
                     (else 'head-and-body)))
             (list 'not-refused (brief outcome))))))))

;; cases : (Listof (List Symbol (Origin -> Any)))
;; Each varying case, its name and its measurement, in the table's order.
(define cases
  (list (list 'request-size size-cell)
        (list 'after-grown-h1 (lambda (o) (after-cell o 'http 'grown)))
        (list 'after-shrunk-h1 (lambda (o) (after-cell o 'http 'shrunk)))
        (list 'after-shrunk-none-h1 (lambda (o) (after-cell o 'http 'shrunk-none)))
        (list 'after-removed-h1 (lambda (o) (after-cell o 'http 'removed)))
        (list 'after-fifo-h1 (lambda (o) (after-cell o 'http 'fifo)))
        (list 'after-grown-h2 (lambda (o) (after-cell o 'h2 'grown)))
        (list 'after-shrunk-h2 (lambda (o) (after-cell o 'h2 'shrunk)))
        (list 'after-removed-h2 (lambda (o) (after-cell o 'h2 'removed)))
        (list 'after-fifo-h2 (lambda (o) (after-cell o 'h2 'fifo)))
        (list 'resend-kill-data (lambda (o) (resend-cell o 'kill 'data)))
        (list 'resend-kill-file (lambda (o) (resend-cell o 'kill 'file)))
        (list 'resend-refused-data (lambda (o) (resend-cell o 'refused 'data)))
        (list 'resend-307-data (lambda (o) (resend-cell o 'follow 'data)))
        (list 'resend-307-file (lambda (o) (resend-cell o 'follow 'file)))
        (list 'resend-reset-file (lambda (o) (resend-cell o 'reset 'file)))))

;; rows : (Listof (Pair String (Listof (Pair Symbol Answer))))
;; Each libcurl's answer to every case, written out: the Linux libcurls'
;; measured through the engine by M8 slice 3's build, two runs each, 8.5.0
;; with OpenSSL and with GnuTLS alike; Apple's 8.7.1's from this suite's two
;; runs on the Mac, 2026-11-07 (research/m8/slice3/mac/), which agreed with
;; the mime-files probe's run there over HTTP/1.1, and with each other but
;; for the reset inside a large part, the race every lane holds.
;; An answer is the cell's, (one-of ANSWER ...) for a cell that races.
(define rows
  '(("7.85.0"
     (request-size . head-alone)
     (after-grown-h1 . (response 400))
     (after-shrunk-h1 . (failed perform-failed 28 held))
     (after-shrunk-none-h1 . (stalled))
     (after-removed-h1 . (failed perform-failed 26))
     (after-fifo-h1 . (response 200 whole held))
     (after-grown-h2 . (failed perform-failed 92))
     (after-shrunk-h2 . (failed perform-failed 92))
     (after-removed-h2 . (failed perform-failed 26))
     (after-fifo-h2 . (response 200 whole held))
     (resend-kill-data . (response 200 whole 2))
     (resend-kill-file . (response 200 whole 2))
     (resend-refused-data . (response 200 whole 2))
     (resend-307-data . (response 200 whole 1))
     (resend-307-file . (response 200 whole 1))
     (resend-reset-file . (one-of (response 200 whole 2) (failed perform-failed 55 1))))
    ("8.5.0"
     (request-size . head-alone)
     (after-grown-h1 . (response 400))
     (after-shrunk-h1 . (failed perform-failed 28 held))
     (after-shrunk-none-h1 . (stalled))
     (after-removed-h1 . (failed perform-failed 26))
     (after-fifo-h1 . (response 200 whole held))
     (after-grown-h2 . (failed perform-failed 92))
     (after-shrunk-h2 . (failed perform-failed 92))
     (after-removed-h2 . (failed perform-failed 26))
     (after-fifo-h2 . (response 200 whole held))
     (resend-kill-data . (response 200 whole 2))
     (resend-kill-file . (response 200 whole 2))
     (resend-refused-data . (response 200 whole 2))
     (resend-307-data . (response 200 whole 1))
     (resend-307-file . (response 200 whole 1))
     (resend-reset-file . (one-of (response 200 whole 2) (failed perform-failed 55 1))))
    ("8.7.1"
     (request-size . unknown)
     (after-grown-h1 . (response 200 unterminated))
     (after-shrunk-h1 . (failed perform-failed 26))
     (after-shrunk-none-h1 . (failed perform-failed 26))
     (after-removed-h1 . (failed perform-failed 26))
     (after-fifo-h1 . (response 200 whole held))
     (after-grown-h2 . (response 200 unterminated))
     (after-shrunk-h2 . (failed perform-failed 26))
     (after-removed-h2 . (failed perform-failed 26))
     (after-fifo-h2 . (response 200 whole held))
     (resend-kill-data . (response 200 whole 2))
     (resend-kill-file . (response 200 whole 2))
     (resend-refused-data . (response 200 whole 2))
     (resend-307-data . (response 200 whole 1))
     (resend-307-file . (response 200 whole 1))
     (resend-reset-file . (one-of (response 200 whole 2) (failed perform-failed 55 1))))
    ("8.20.0"
     (request-size . head-and-body)
     (after-grown-h1 . (response 200 unterminated))
     (after-shrunk-h1 . (failed perform-failed 26))
     (after-shrunk-none-h1 . (failed perform-failed 26))
     (after-removed-h1 . (failed perform-failed 26))
     (after-fifo-h1 . (response 200 whole held))
     (after-grown-h2 . (response 200 unterminated))
     (after-shrunk-h2 . (failed perform-failed 26))
     (after-removed-h2 . (failed perform-failed 26))
     (after-fifo-h2 . (response 200 whole held))
     (resend-kill-data . (response 200 whole 2))
     (resend-kill-file . (response 200 whole 2))
     (resend-refused-data . (response 200 whole 2))
     (resend-307-data . (response 200 whole 1))
     (resend-307-file . (response 200 whole 1))
     (resend-reset-file . (one-of (response 200 whole 2) (failed perform-failed 55 1))))
    ("8.23.0"
     (request-size . head-and-body)
     (after-grown-h1 . (response 200 unterminated))
     (after-shrunk-h1 . (failed perform-failed 26))
     (after-shrunk-none-h1 . (failed perform-failed 26))
     (after-removed-h1 . (failed perform-failed 26))
     (after-fifo-h1 . (response 200 whole held))
     (after-grown-h2 . (response 200 unterminated))
     (after-shrunk-h2 . (failed perform-failed 26))
     (after-removed-h2 . (failed perform-failed 26))
     (after-fifo-h2 . (response 200 whole held))
     (resend-kill-data . (response 200 whole 2))
     (resend-kill-file . (response 200 whole 2))
     (resend-refused-data . (response 200 whole 2))
     (resend-307-data . (response 200 whole 1))
     (resend-307-file . (response 200 whole 1))
     (resend-reset-file . (one-of (response 200 whole 2) (failed perform-failed 55 1))))))

;; row : (U (Listof (Pair Symbol Answer)) #f)
;; This libcurl's row.
(define row (let ((found (assoc version rows))) (and found (cdr found))))

;; cell : Symbol -> Any
;; This libcurl's answer to CASE: its row's, or (no-cell CASE), which no
;; measurement gives.
(define (cell case)
  (let ((found (and row (assq case row))))
    (if found (cdr found) (list 'no-cell case))))

;; matches? : Any Any -> Boolean
;; Whether MEASURED is the cell WANT, or one of a racing cell's answers.
(define (matches? want measured)
  (if (and (pair? want) (eq? (car want) 'one-of))
      (and (member measured (cdr want)) #t)
      (equal? want measured)))

(define (table-scenarios o)
  (let ((measured (map (lambda (c) (cons (car c) ((cadr c) o))) cases)))
    (display (string-append "test-multipart: libcurl " (written version) " measured "
                            (written (cons version measured)) "\n"))
    (unless (and row (for-all (lambda (m) (matches? (cell (car m)) (cdr m))) measured))
      (display (string-append "test-multipart: the row this libcurl's measurements make, for rows:\n")
               (current-error-port))
      (write (cons version measured) (current-error-port))
      (newline (current-error-port)))
    (test-equal (string-append "the loaded libcurl, " (written version) ", has a row in this suite's table")
      'has-a-row
      (if row 'has-a-row (list 'no-row version)))
    (for-each
     (lambda (m)
       (test-equal (string-append "by version, " (symbol->string (car m)) " answers as this libcurl's row says")
         (list (car m) 'as-the-row)
         (list (car m) (if (matches? (cell (car m)) (cdr m)) 'as-the-row
                           (list 'row (cell (car m)) 'measured (cdr m))))))
     measured)))

;; The scenarios' tests run here, in a definition, and the verdict on their
;; origin after: SRFI-64 keeps one result per runner (traps.md).
(define scenarios-outcome
  (guard (e (#t (list 'raised (describe e))))
    (parameterize ((origin-pki pki))
      (call-with-origin scenarios))))

(test-equal "the scenarios' origin starts with the PKI, serves them all, and stops"
  'done
  scenarios-outcome)

;; --- an abandoned handle keeps its mime (the M8 plan, section 3.4) ---------------------------

;; library-path : -> String
(define (library-path)
  (let loop ((dirs (map car (library-directories))) (text ""))
    (cond ((null? dirs) text)
          ((string=? text "") (loop (cdr dirs) (car dirs)))
          (else (loop (cdr dirs) (string-append text ":" (car dirs)))))))

;; abandon-child : String -> Any
;; tests/mime-abandon.sps in a child Chez, with HOW, abandon or free: what
;; it printed, read as data, or what went wrong.
(define (abandon-child how)
  (guard (e (#t (list 'raised (describe e))))
    (let ((r (capture-command (list (getenv "CHEZ") "--libdirs" (library-path) "--program"
                                    "tests/mime-abandon.sps" how))))
      (if (= (car r) 0)
          (read (open-string-input-port (cadr r)))
          (list 'exit (car r) (cadr r) (caddr r))))))

(test-equal "a failed engine that abandons a live multipart transfer's easy handle keeps its mime: one easy handle and one mime stay counted; the control, which frees the handle, frees the mime too, nothing counted"
  (list '((engine-error failed) ((block . 0) (easy . 1) (url . 0) (slist . 0) (curl-string . 0)
                                 (transfer . 0) (multi . 0) (share . 0) (mime . 1)))
        (list '(engine-error failed) zero-counts))
  (list (abandon-child "abandon") (abandon-child "free")))

;; --- no secret printed (the M8 plan, section 3.4) ----------------------------------------------

(define secret "s3cr3t-M8-p4rt")

;; texts-of : Any -> String
;; X as printed: a condition by display-condition, anything else written.
(define (text-of x)
  (call-with-string-output-port
   (lambda (p) (if (condition? x) (display-condition x p) (write x p)))))

(define secret-dir (in-scratch secret))

(test-equal "no secret printed: one secret in a part's value, name, filename, type and path, through every refusal of section 3.7 a full libcurl makes and every shape's assertion violation, part-file at the request, at submit and from the engine, and mime-failed by the private seam; each condition, the request, the token and the outcome printed hold none of it"
  (list '(refused refused refused refused refused refused refused refused refused refused
          assertion assertion assertion http-refused http-refused failed failed request token)
        '())
  (guard (e (#t (list 'raised (describe e))))
    (make-directory secret-dir)
    (let* ((secret-file (string-append secret-dir "/" secret ".txt"))
           (made-file (begin (write-bytes secret-file (string->utf8 secret)) secret-file))
           (raised (lambda (thunk)
                     (guard (e (#t e)) (thunk) 'no-raise)))
           (cases
            (list (raised (lambda () (made (list 'multipart (list (string-append "n" secret (string #\x1)) secret)))))
                  (raised (lambda () (made (list 'multipart (list (string-append "n" secret) secret 'type "")))))
                  (raised (lambda () (made '(multipart) 'headers (list (cons "X-S" secret)))))
                  (raised (lambda () (made (list 'multipart (list (string-append "n" secret) secret))
                                           'headers (list (cons "Content-Type" secret)))))
                  (raised (lambda () (made (list 'multipart (list "n" secret 'filename (string-append secret "\""))))))
                  (raised (lambda () (made (list 'multipart (list "n" secret 'type (string-append secret "\r\n"))))))
                  (raised (lambda () (made (list 'multipart (list "n" (list 'file (string-append "/nonexistent/" secret))
                                                                  'filename secret)))))
                  (raised (lambda () (curl-request-check
                                      (curl-request-with-unresolved-path
                                       (made (list 'multipart (list (string-append "n" secret) (list 'file made-file))))
                                       0 (string-append secret ".txt")))))
                  (raised (lambda () (make-curl-request "http://127.0.0.1:9/" 'method 'get
                                                        'body (list 'multipart (list secret secret)))))
                  (raised (lambda () (made (list 'multipart (list "n" secret)) 'body-length 1)))
                  (raised (lambda () (made (list 'multipart (list secret 42)))))
                  (raised (lambda () (made (list 'multipart (list "n" (list 'file made-file secret))))))
                  (raised (lambda () (made (list 'multipart (list "n" secret 'filename secret 'filename secret)))))
                  (raised (lambda () (call-with-http-session 'proxy #f
                                       (lambda (s) (http-post s "http://127.0.0.1:9/" 'body secret
                                                              'multipart (list (list secret secret)))))))
                  (raised (lambda () (call-with-http-session 'proxy #f
                                       (lambda (s) (http-get s "http://127.0.0.1:9/"
                                                             'multipart (list (list secret secret)))))))))
           (request (made (list 'multipart (list (string-append "n" secret) secret 'filename (string-append secret ".txt")
                                                 'type (string-append "t/" secret))
                                (list "f" (list 'file made-file)))))
           (engine-outcomes
            (with-engine
             (lambda (e)
               (let* ((gone (begin (transfer-file-check-gate-set! (lambda () (delete-file made-file)))
                                   (let ((t (curl-submit e request)))
                                     (curl-token-wait t 20000)
                                     (transfer-file-check-gate-set! #f)
                                     t)))
                      (planted (begin (write-bytes made-file (string->utf8 secret))
                                      (transfer-mime-answer-set! '(0 name . 43))
                                      (let ((t (curl-submit e request)))
                                        (curl-token-wait t 20000)
                                        (transfer-mime-answer-set! #f)
                                        t))))
                 (list gone planted)))))
           (outcomes (map curl-token-outcome engine-outcomes))
           (kinds (append (map (lambda (c)
                                 (cond ((http-request-error? c) 'http-refused)
                                       ((curl-request-error? c) 'refused)
                                       ((assertion-violation? c) 'assertion)
                                       (else (list 'other (text-of c)))))
                               cases)
                          (map (lambda (o) (if (curl-transfer-error? o) 'failed (list 'other (text-of o)))) outcomes)
                          (list (if (curl-request? request) 'request 'no-request)
                                (if (curl-token? (car engine-outcomes)) 'token 'no-token))))
           (texts (append (map text-of cases) (map text-of outcomes)
                          (list (text-of request) (text-of (car engine-outcomes)) (text-of (cadr engine-outcomes))))))
      (list kinds (filter (lambda (t) (contains? t secret)) texts)))))

;; --- freeing what it made ------------------------------------------------------------------

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "multipart")

(exit (suite-exit-status runner))
