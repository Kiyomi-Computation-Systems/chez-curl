#!r6rs
;;; The suite for (curl private transfer): one blocking request on the
;;; calling thread, against the test origin's plaintext faces (M2 plan,
;;; section 5).
;;;
;;; Every scenario is asserted whole: the status, the HTTP version, every
;;; header in libcurl's order, and the body, or the &curl-transfer-error's
;;; reason and CURLcode, with the native counts after it, which must all be
;;; zero, refusals included. curl's verdicts vary by version (plan, section
;;; 5.1.1), so, as test-url does:
;;;
;;;   - shared answers hold what every recorded libcurl answers, 7.85.0,
;;;     8.5.0 (OpenSSL and GnuTLS) and 8.20.0, measured through C;
;;;   - tests/known-transfer-verdicts.sexp holds a row per libcurl version
;;;     for the scenarios that vary. A libcurl with no row fails, and the
;;;     suite prints the row it would need on the error port.
;;;
;;; Then what the binding itself does:
;;;
;;;   - the setopt bindings, each observed in a transfer (ADR-0001's FFI
;;;     test): a string, USERAGENT, arrives as Latin-1 bytes; longs,
;;;     TIMEOUT_MS and NOBODY; an off_t, MAXFILESIZE_LARGE;
;;;   - header strings are Latin-1 both ways (ADR-0001, amended
;;;     2026-10-23): every byte 0x01 to 0xFF but CR and LF, sent and read;
;;;   - the request's refusals, each reason at every position of a value,
;;;     the name rule against the whole complement of tchar from U+0000 to
;;;     U+00FF and beyond, and nothing native made at the raise;
;;;   - the body limit at its edges, with MAXFILESIZE_LARGE at the limit
;;;     plus one, and what the callable accepted, seen through CHUNK-HOOK;
;;;   - a raise inside the callable, re-raised by the transfer;
;;;   - two threads' transfers at once, with positive evidence they
;;;     overlapped;
;;;   - the lock: a drip beside a thread that collects every 2 ms;
;;;   - the option table and its bindings, written out here, since on
;;;     x86-64 a long sent through the off_t binding arrives all the same;
;;;   - the test seam, perform-transfer-with, held to ADR-0009's rules,
;;;     narrowed (amended 2026-10-23): long, enumerated-value and off_t
;;;     options alone, none the transfer owns, compared by id; through it,
;;;     the last request's headers after a redirect followed, and the
;;;     redirect pin observed;
;;;   - the request's snapshot: a request changed after it was made is
;;;     refused at the transfer, and a value another thread changes is
;;;     sent whole or refused, never otherwise;
;;;   - caller code leaving the callable other than by its return, refused,
;;;     and no socket left behind;
;;;   - asynchronous escapes, an engine's or a timer's, allowed and counted
;;;     (ADR-0013, amended 2026-10-23): in a child, tests/transfer-escapes.sps,
;;;     a sweep at every tick, timers, and a handler that must run while
;;;     perform does, judged here; and sweeps of the mutexes, here;
;;;   - framing headers, Content-Length and Transfer-Encoding, refused;
;;;   - hermetic: no proxy variable is set;
;;;   - the native objects' lifetimes: the counts inside the callable,
;;;     re-entry through a continuation refused by the outermost extent,
;;;     and the extents' nesting, read from transfer.sls as data, since
;;;     libcurl 8.20.0's cleanup reads none of the objects a wrong order
;;;     would free first.
;;;
;;; Importing (curl) runs the load before this suite's first line, on this
;;; thread: a first reference from a second thread during the load would
;;; raise cyclic dependency (ADR-0002, amended). The suite's top level also
;;; reaches (curl private transfer) before any thread is forked. Every
;;; expected value is one the code under test cannot produce by failing:
;;; SRFI-64 makes #f of a raise in the actual expression, so none is #f.
(import (rnrs)
        (srfi :64)
        (rnrs mutable-strings)
        (rnrs mutable-pairs)
        (only (chezscheme) fork-thread thread-join make-mutex with-mutex collect-rendezvous
              sleep make-time current-time time-second time-nanosecond getenv get-process-id
              file-directory?)
        (curl-testing)
        (curl)
        (curl private transfer)
        (curl private conditions)
        (curl private constants)
        (curl private counters)
        (only (curl private native) curl-easy-setopt-long curl-easy-setopt-off-t
              curl-easy-setopt-pointer call-with-c-string curl-slist-append curl-slist-free-all
              curl-easy-strerror loaded-protocols curl-easy-option)
        (only (chezscheme) make-engine library-directories)
        (only (rnrs records inspection) record-rtd record-type-field-names))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; written : Any -> String
(define (written x) (call-with-string-output-port (lambda (p) (write x p))))

;; shown : Any -> String
;; X written, cut to 3000 characters: some answers hold 100,000 headers.
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
      ;; A suite killed at its bound never flushes: flush each verdict, so a
      ;; HUNG run still names the tests that failed before it hung.
      (flush-output-port (current-output-port)))))

;; --- helpers --------------------------------------------------------------------------

(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0)))

;; The loaded libcurl's version, read here, on this thread, so the load runs
;; before any thread is forked.
(define version
  (guard (e (#t (list 'no-version (describe e))))
    (libcurl-info-version (loaded-libcurl))))

;; The option table, read here, so (curl private transfer)'s body runs on
;; this thread too.
(define bindings-read
  (guard (e (#t (list 'raised (describe e))))
    option-bindings))

;; latin-1 : Bytevector -> String
;; Each byte as the char of its code.
(define (latin-1 bytes)
  (list->string (map integer->char (bytevector->u8-list bytes))))

;; iota-from : Integer Natural -> (Listof Integer)
(define (iota-from start n)
  (if (= n 0) '() (cons start (iota-from (+ start 1) (- n 1)))))

;; chars : (Listof Natural) -> String
(define (chars codes) (list->string (map integer->char codes)))

;; every-byte-but-cr-lf : String
;; Each char from U+0001 to U+00FF but CR and LF, in order.
(define every-byte-but-cr-lf
  (chars (filter (lambda (b) (not (memv b '(10 13)))) (iota-from 1 255))))

;; now-ms : -> Integer
(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

;; pause-ms : Natural -> Unit
(define (pause-ms ms)
  (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))

;; How long a transfer may take before libcurl gives up, unless a test says
;; otherwise: long enough for the memory gate's Valgrind.
(define default-timeout 20000)

;; request : String . (Listof Any) -> Request
;; A request for TARGET with the suite's defaults: a GET, no headers, no
;; user agent, default-timeout, no body limit and no hook. OPTIONS are
;; keyword and value: method, headers, user-agent, timeout, limit, hook.
(define (request target . options)
  (let ((given (lambda (key default)
                 (let ((at (memq key options))) (if at (cadr at) default)))))
    (make-transfer-request target (given 'method 'get) (given 'headers '())
                           (given 'user-agent #f) (given 'timeout default-timeout)
                           (given 'limit #f) (given 'hook #f))))

;; answer-of : (-> Response) -> Answer
;; What THUNK's transfer answers, whole: (response STATUS VERSION HEADERS
;; BODY), each header (NAME VALUE) and the body read as Latin-1;
;; (refused REASON CODE) for a &curl-transfer-error; (request-refused FIELD
;; REASON) for a &curl-request-error; (url-refused REASON CODE) for a
;; &curl-url-error; (raised TEXT) for anything else.
(define (answer-of thunk)
  (guard (e ((curl-transfer-error? e)
             (list 'refused (curl-transfer-error-reason e) (curl-transfer-error-code e)))
            ((curl-request-error? e)
             (list 'request-refused (curl-request-error-field e) (curl-request-error-reason e)))
            ((curl-url-error? e)
             (list 'url-refused (curl-url-error-reason e) (curl-url-error-code e)))
            (#t (list 'raised (describe e))))
    (let ((r (thunk)))
      (list 'response (transfer-response-status r) (transfer-response-http-version r)
            (map (lambda (h) (list (car h) (cdr h))) (transfer-response-headers r))
            (latin-1 (transfer-response-body r))))))

;; with-counts : Any -> (List Any (Listof (Pairof Symbol Natural)))
;; ANSWER, and the native counts once it was answered.
(define (with-counts answer) (list answer (native-counts)))

;; numbered : String Natural String -> (Listof (List String String))
;; COUNT headers PREFIX1 to PREFIXCOUNT, each VALUE.
(define (numbered prefix count value)
  (map (lambda (i) (list (string-append prefix (number->string i)) value)) (iota-from 1 count)))

;; expanded : Answer -> Answer
;; ANSWER with a (numbered PREFIX COUNT VALUE) header list written out.
(define (expanded answer)
  (if (and (pair? answer) (eq? (car answer) 'response) (= (length answer) 5)
           (pair? (cadddr answer)) (eq? (car (cadddr answer)) 'numbered))
      (let ((n (cadddr answer)))
        (list 'response (cadr answer) (caddr answer)
              (numbered (cadr n) (caddr n) (cadddr n)) (car (cddddr answer))))
      answer))

;; compressed : Answer -> Answer
;; ANSWER with a header list of 50 or more X-H- headers, each v, numbered
;; from 1, written as (numbered "X-H-" COUNT "v"): how the row file holds it.
(define (compressed answer)
  (if (and (pair? answer) (eq? (car answer) 'response) (= (length answer) 5)
           (list? (cadddr answer)) (>= (length (cadddr answer)) 50)
           (equal? (cadddr answer) (numbered "X-H-" (length (cadddr answer)) "v")))
      (list 'response (cadr answer) (caddr answer)
            (list 'numbered "X-H-" (length (cadddr answer)) "v") (car (cddddr answer)))
      answer))

;; url-of : Origin Symbol String -> String
(define (url-of o face path)
  (let ((f (origin-face o face)))
    (string-append "http://" (car f) ":" (number->string (cdr f)) path)))

;; host-of : Origin Symbol -> String
;; FACE's address and port, as libcurl writes Host.
(define (host-of o face)
  (let ((f (origin-face o face)))
    (string-append (car f) ":" (number->string (cdr f)))))

;; case-answer : Origin Case -> Answer
;; What CASE, (get FACE PATH), answers against O, through perform-transfer.
(define (case-answer o a-case)
  (answer-of (lambda () (perform-transfer (request (url-of o (cadr a-case) (caddr a-case)))))))

;; case-text : Case -> String
(define (case-text a-case)
  (string-append "GET " (symbol->string (cadr a-case)) " " (caddr a-case)))

;; --- the shared answers ------------------------------------------------------------------

(define ok "status 200\n")

;; shared-answers : (Listof (List Case Answer))
;; Every plaintext scenario all four recorded libcurls answer alike (plan,
;; section 5.1.1): the http face's routes, every raw script with the
;; parameters build/verify/m2s2/measure/scenarios.c used. A redirect is
;; not followed.
;; Headers are those curl_easy_nextheader gives for CURLH_HEADER and the
;; last request, so a trailer is not among them.
(define shared-answers
  `(((get http "/status/200")
     (response 200 http/1.1 (("Content-Length" "11") ("Connection" "keep-alive")) ,ok))
    ((get http "/status/204") (response 204 http/1.1 (("Connection" "keep-alive")) ""))
    ((get http "/status/205")
     (response 205 http/1.1 (("Content-Length" "0") ("Connection" "keep-alive")) ""))
    ((get http "/status/304") (response 304 http/1.1 (("Connection" "keep-alive")) ""))
    ((get http "/status/404")
     (response 404 http/1.1 (("Content-Length" "11") ("Connection" "keep-alive")) "status 404\n"))
    ((get http "/status/500")
     (response 500 http/1.1 (("Content-Length" "11") ("Connection" "keep-alive")) "status 500\n"))
    ((get http "/status/599")
     (response 599 http/1.1 (("Content-Length" "11") ("Connection" "keep-alive")) "status 599\n"))
    ((get http "/redirect/302?to=/status/200")
     (response 302 http/1.1 (("Location" "/status/200") ("Content-Length" "13") ("Connection" "keep-alive"))
               "redirect 302\n"))
    ((get http "/redirect/301?to=http://elsewhere.invalid/")
     (response 301 http/1.1 (("Location" "http://elsewhere.invalid/") ("Content-Length" "13")
                             ("Connection" "keep-alive"))
               "redirect 301\n"))
    ((get http "/chunked")
     (response 200 http/1.1 (("Transfer-Encoding" "chunked") ("Connection" "keep-alive"))
               "alpha\nbeta\ngamma\n"))
    ((get http "/nowhere")
     (response 404 http/1.1 (("Content-Length" "10") ("Connection" "keep-alive")) "not found\n"))
    ((get raw "/raw/content-length") (response 200 http/1.1 (("Content-Length" "6")) "hello\n"))
    ((get raw "/raw/chunked") (response 200 http/1.1 (("Transfer-Encoding" "chunked")) "hello\n"))
    ((get raw "/raw/chunked-extensions-trailers")
     (response 200 http/1.1 (("Transfer-Encoding" "chunked") ("Trailer" "X-Trailer")) "hello world\n"))
    ((get raw "/raw/chunked-tiny") (response 200 http/1.1 (("Transfer-Encoding" "chunked")) "hello\n"))
    ((get raw "/raw/close-delimited") (response 200 http/1.1 (("Connection" "close")) "hello\n"))
    ((get raw "/raw/http10") (response 200 http/1.0 () "hello\n"))
    ((get raw "/raw/drip?bytes=3&gap=20") (response 200 http/1.1 (("Content-Length" "3")) "abc"))
    ((get raw "/raw/pause-mid-body?ms=50") (response 200 http/1.1 (("Content-Length" "11")) "hello world"))
    ((get raw "/raw/reset-after-pause?ms=50") (refused perform-failed ,curle-recv-error))
    ((get raw "/raw/big-header?bytes=1000")
     (response 200 http/1.1 (("X-Big" ,(make-string 1000 #\a))) ""))
    ((get raw "/raw/big-header?bytes=102380")
     (response 200 http/1.1 (("X-Big" ,(make-string 102380 #\a))) ""))
    ((get raw "/raw/many-headers?count=10") (response 200 http/1.1 (numbered "X-H-" 10 "v") ""))
    ((get raw "/raw/many-headers?count=1000") (response 200 http/1.1 (numbered "X-H-" 1000 "v") ""))
    ((get raw "/raw/bad-status-line") (refused perform-failed ,curle-unsupported-protocol))
    ((get raw "/raw/bad-chunk-size") (refused perform-failed ,curle-recv-error))
    ((get raw "/raw/short-body") (refused perform-failed ,curle-partial-file))
    ((get raw "/raw/reset-mid-body") (refused perform-failed ,curle-recv-error))
    ((get raw "/raw/chunked-and-content-length")
     (response 200 http/1.1 (("Content-Length" "6") ("Transfer-Encoding" "chunked")) "hello\n"))
    ((get raw "/raw/header-no-colon") (refused perform-failed ,curle-weird-server-reply))
    ((get raw "/raw/nul-in-header") (refused perform-failed ,curle-weird-server-reply))
    ((get raw "/raw/close-before-response") (refused perform-failed ,curle-got-nothing))
    ((get raw "/raw/http09") (refused perform-failed ,curle-unsupported-protocol))
    ((get raw "/raw/bare-lf") (response 200 http/1.1 (("Content-Length" "6")) "hello\n"))
    ((get raw "/raw/unknown-script")
     (response 400 http/1.1 (("Content-Length" "12") ("Connection" "close")) "bad request\n"))
    ((get raw "/raw/header-bytes")
     (response 200 http/1.1 (("X-Bytes" ,(string-append "a" every-byte-but-cr-lf "z"))
                             ("Content-Length" "0"))
               ""))))

;; varying-cases : (Listof Case)
;; The scenarios whose answers vary by version, in the order every row
;; answers them: big-header at both sizes past CURL_MAX_HTTP_HEADER,
;; many-headers, bad-status-code and conflicting-content-length. The plan's
;; fifth, MAXFILESIZE_LARGE alone, is no longer reachable: the test seam
;; refuses it, a request field's option (ADR-0009, amended 2026-10-23).
(define varying-cases
  '((get raw "/raw/big-header?bytes=102400")
    (get raw "/raw/big-header?bytes=1048576")
    (get raw "/raw/many-headers?count=100000")
    (get raw "/raw/bad-status-code")
    (get raw "/raw/conflicting-content-length")))

;; --- the rows, read under a guard ------------------------------------------------------

(define verdicts-file "tests/known-transfer-verdicts.sexp")

;; read-data : String -> (U (List 'data (Listof Any)) (List 'unreadable String))
;; Every datum of the file at PATH: strict UTF-8, and nothing after an
;; end-of-file mark.
(define (read-data path)
  (guard (e (#t (list 'unreadable (describe e))))
    (call-with-port
     (open-file-input-port path (file-options) (buffer-mode block)
                           (make-transcoder (utf-8-codec) (native-eol-style)
                                            (error-handling-mode raise)))
     (lambda (port)
       (let loop ((found '()))
         (let ((datum (read port)))
           (cond ((not (eof-object? datum)) (loop (cons datum found)))
                 ((port-eof? port) (list 'data (reverse found)))
                 (else (list 'unreadable "text after an end-of-file mark")))))))))

(define file-result (read-data verdicts-file))

(define rows (if (eq? (car file-result) 'data) (cadr file-result) '()))

;; header-shaped? : Any -> Boolean
(define (header-shaped? h)
  (and (list? h) (= (length h) 2) (string? (car h)) (string? (cadr h))))

;; answer-shaped? : Any -> Boolean
;; (refused REASON CODE), REASON a transfer error's reason and CODE an exact
;; integer, or (response STATUS VERSION HEADERS BODY).
(define (answer-shaped? x)
  (and (list? x)
       (or (and (= (length x) 3) (eq? (car x) 'refused)
                (memq (cadr x) curl-transfer-error-reasons)
                (integer? (caddr x)) (exact? (caddr x)))
           (and (= (length x) 5) (eq? (car x) 'response)
                (integer? (cadr x)) (exact? (cadr x))
                (or (symbol? (caddr x)) (not (caddr x)) (integer? (caddr x)))
                (let ((hs (cadddr x)))
                  (or (and (list? hs) (for-all header-shaped? hs))
                      (and (list? hs) (= (length hs) 4) (eq? (car hs) 'numbered)
                           (string? (cadr hs)) (integer? (caddr hs)) (exact? (caddr hs))
                           (>= (caddr hs) 0) (string? (cadddr hs)))))
                (string? (car (cddddr x)))))
       #t))

;; case-shaped? : Any -> Boolean
(define (case-shaped? x)
  (and (list? x)
       (= (length x) 3)
       (eq? (car x) 'get)
       (memq (cadr x) '(http raw))
       (string? (caddr x))
       #t))

;; row-problem : Any -> (U 'ok (Listof Any))
;; ok when ROW is (libcurl (where S) (version S) (answers (CASE ANSWER) ...)),
;; each CASE and ANSWER well formed; else what is wrong. Total.
(define (row-problem row)
  (cond
    ((not (and (list? row) (= (length row) 4) (eq? (car row) 'libcurl)))
     (list 'not-a-row-of-three-fields row))
    ((not (and (list? (cadr row)) (= (length (cadr row)) 2) (eq? (car (cadr row)) 'where)
               (string? (cadr (cadr row)))))
     (list 'where-is (cadr row)))
    ((not (and (list? (caddr row)) (= (length (caddr row)) 2) (eq? (car (caddr row)) 'version)
               (string? (cadr (caddr row)))))
     (list 'version-is (caddr row)))
    ((not (and (list? (cadddr row)) (pair? (cadddr row)) (eq? (car (cadddr row)) 'answers)))
     (list 'answers-is (cadddr row)))
    ((find (lambda (pair)
             (not (and (list? pair) (= (length pair) 2)
                       (case-shaped? (car pair)) (answer-shaped? (cadr pair)))))
           (cdr (cadddr row)))
     => (lambda (pair) (list 'not-a-case-and-an-answer pair)))
    (else 'ok)))

;; row-version : Row -> String
(define (row-version row) (cadr (caddr row)))

;; row-answers : Row -> (Listof (List Case Answer))
(define (row-answers row) (cdr (cadddr row)))

;; rows-for-version : (Listof Any) String -> (Listof Row)
(define (rows-for-version rows version)
  (filter (lambda (row) (and (eq? (row-problem row) 'ok) (string=? (row-version row) version)))
          rows))

;; version-verdict : (Listof Any) String -> (U 'one 'none 'several)
(define (version-verdict rows version)
  (let ((n (length (rows-for-version rows version))))
    (cond ((= n 1) 'one) ((= n 0) 'none) (else 'several))))

;; distinct? : (Listof Any) -> Boolean
(define (distinct? xs)
  (or (null? xs) (and (not (member (car xs) (cdr xs))) (distinct? (cdr xs)))))

;; same-cases? : (Listof Case) (Listof Case) -> Boolean
(define (same-cases? a b)
  (and (distinct? a) (distinct? b) (= (length a) (length b))
       (for-all (lambda (a-case) (member a-case b)) a)
       #t))

(define matches (if (string? version) (rows-for-version rows version) '()))

(define the-row (and (= (length matches) 1) (car matches)))

;; row-text : String (Listof (List Case Answer)) -> String
;; The row a libcurl at VERSION would need, given what it answered, ready
;; to paste, its where to be replaced.
(define (row-text version answered)
  (string-append
   "(libcurl\n"
   " (where \"TODO: say where this libcurl runs\")\n"
   " (version " (written version) ")\n"
   " (answers"
   (apply string-append
          (map (lambda (pair)
                 (string-append "\n  (" (written (car pair)) " " (written (compressed (cadr pair))) ")"))
               answered))
   "))\n"))

;; --- the request's refusals --------------------------------------------------------------

;; refusal : (-> Any) -> (List Any (Listof (Pairof Symbol Natural)) (Listof (Pairof Symbol Natural)))
;; What THUNK raised, as answer-of names it, or (assertion-violation WHO);
;; the native counts at the raise, read by a handler before any
;; dynamic-wind's after thunk; and the counts after.
(define (refusal thunk)
  (let* ((seen 'no-raise)
         (r (guard (e ((curl-request-error? e)
                       (list 'request-refused (curl-request-error-field e)
                             (curl-request-error-value e) (curl-request-error-reason e)))
                      ((curl-url-error? e) (list 'url-refused (curl-url-error-reason e)))
                      ((curl-transfer-error? e)
                       (list 'transfer-refused (curl-transfer-error-reason e)
                             (curl-transfer-error-option e)))
                      ((and (assertion-violation? e) (who-condition? e))
                       (list 'assertion-violation (condition-who e)))
                      (#t (list 'raised (describe e))))
              (with-exception-handler
                (lambda (c) (set! seen (native-counts)) (raise c))
                (lambda () (thunk) 'no-raise)))))
    (list r seen (native-counts))))

;; tchars : (Listof Char)
;; RFC 9110, section 5.6.2's tchar, written out: the fifteen marks, the
;; digits and the ASCII letters.
(define tchars
  (append (string->list "!#$%&'*+-.^_`|~")
          (map integer->char (iota-from 48 10))
          (map integer->char (iota-from 65 26))
          (map integer->char (iota-from 97 26))))

;; not-tchars : (Listof Char)
;; Every char from U+0000 to U+00FF that is no tchar, then three above.
(define not-tchars
  (append (filter (lambda (c) (not (memv c tchars))) (map integer->char (iota-from 0 256)))
          (list (integer->char #x100) (integer->char #x20AC) (integer->char #x1F600))))

;; header-request : String String -> (-> Request)
(define (header-request name value)
  (lambda () (make-transfer-request "http://127.0.0.1:1/" 'get (list (cons name value)) #f #f #f #f)))

;; agent-request : String -> (-> Request)
(define (agent-request agent)
  (lambda () (make-transfer-request "http://127.0.0.1:1/" 'get '() agent #f #f #f)))

;; at-each-place : Char -> (Listof String)
;; "abcde" with C in place of each of its five chars, and C alone.
(define (at-each-place c)
  (append (map (lambda (i)
                 (string-append (substring "abcde" 0 i) (string c) (substring "abcde" (+ i 1) 5)))
               (iota-from 0 5))
          (list (string c))))

;; The offending chars, by reason, for a value.
(define value-offences
  `((embedded-nul ,(integer->char 0))
    (line-break #\return)
    (line-break #\newline)
    (not-latin-1 ,(integer->char #x100))
    (not-latin-1 ,(integer->char #x20AC))
    (not-latin-1 ,(integer->char #x1F600))))

(test-begin "transfer")

;; --- hermetic: no proxy from the environment ---------------------------------------------
;; libcurl reads these, and would send every transfer here to the proxy they
;; name. The proxy policy is M4's; this suite runs with none.
(define proxy-variables '("http_proxy" "HTTP_PROXY" "https_proxy" "HTTPS_PROXY" "all_proxy" "ALL_PROXY"))

(test-equal "hermetic: none of http_proxy, HTTP_PROXY, https_proxy, HTTPS_PROXY, all_proxy and ALL_PROXY is set, or libcurl would send this suite's transfers to it"
  '()
  (filter (lambda (name) (getenv name)) proxy-variables))

;; --- the request record -------------------------------------------------------------------

(for-each
 (lambda (offence)
   (let ((reason (car offence)) (c (cadr offence)))
     (test-equal (string-append "a header value with U+" (number->string (char->integer c) 16)
                                " at each of its places, and alone, is refused as "
                                (symbol->string reason) ", naming header-value and the value, with nothing native at the raise")
       (map (lambda (value) (list (list 'request-refused 'header-value value reason) zero-counts zero-counts))
            (at-each-place c))
       (map (lambda (value) (refusal (header-request "X-Value" value))) (at-each-place c)))
     (test-equal (string-append "a user agent with U+" (number->string (char->integer c) 16)
                                " at each of its places, and alone, is refused as "
                                (symbol->string reason) ", naming user-agent, with nothing native at the raise")
       (map (lambda (value) (list (list 'request-refused 'user-agent value reason) zero-counts zero-counts))
            (at-each-place c))
       (map (lambda (value) (refusal (agent-request value))) (at-each-place c)))))
 value-offences)

;; Two offending chars: the first decides, each way round.
(test-equal "a value's first offending char decides its reason, each way round, for a header value and a user agent"
  (let ((pairs '(("a\x0;\rb" embedded-nul) ("a\r\x0;b" line-break) ("a\x100;\nb" not-latin-1)
                 ("a\n\x100;b" line-break) ("a\x0;\x100;" embedded-nul) ("\x100;\x0;" not-latin-1))))
    (append (map (lambda (p) (list 'request-refused 'header-value (car p) (cadr p))) pairs)
            (map (lambda (p) (list 'request-refused 'user-agent (car p) (cadr p))) pairs)))
  (let ((values '("a\x0;\rb" "a\r\x0;b" "a\x100;\nb" "a\n\x100;b" "a\x0;\x100;" "\x100;\x0;")))
    (append (map (lambda (v) (car (refusal (header-request "X-Value" v)))) values)
            (map (lambda (v) (car (refusal (agent-request v)))) values))))

;; Whitespace at a value's ends: SP, HTAB, VT and FF, which libcurl trims.
(define end-whitespace (list #\space #\tab (integer->char 11) (integer->char 12)))

;; whitespace-name : Char -> String
(define (whitespace-name c)
  (case (char->integer c) ((32) "SP") ((9) "HTAB") ((11) "VT") (else "FF")))

(for-each
 (lambda (c)
   (let ((values (list (string c #\a) (string #\a c) (string c #\a #\b c) (string c) (string c c))))
     (test-equal (string-append "a header value and a user agent with " (whitespace-name c)
                                " first, last, at both ends, alone, or twice alone, are refused as surrounding-whitespace, with nothing native at the raise")
       (append (map (lambda (v) (list (list 'request-refused 'header-value v 'surrounding-whitespace)
                                      zero-counts zero-counts))
                    values)
               (map (lambda (v) (list (list 'request-refused 'user-agent v 'surrounding-whitespace)
                                      zero-counts zero-counts))
                    values))
       (append (map (lambda (v) (refusal (header-request "X-Value" v))) values)
               (map (lambda (v) (refusal (agent-request v))) values)))))
 end-whitespace)

(test-equal "whitespace inside a value is the value's: SP, HTAB, VT and FF between two chars, and whitespace the four leave out, U+00A0, at the ends, are each taken, as a header value and as a user agent"
  (map (lambda (v) '(no-raise no-raise))
       '(1 2 3 4 5))
  (map (lambda (v) (list (car (refusal (header-request "X-Value" v))) (car (refusal (agent-request v)))))
       (append (map (lambda (c) (string #\a c #\b)) end-whitespace)
               (list (string (integer->char #xA0) #\a (integer->char #xA0))))))

(test-equal "the char scan comes first: an offending char anywhere decides before whitespace at an end"
  '((request-refused header-value " a\r" line-break)
    (request-refused header-value "\x0; " embedded-nul)
    (request-refused header-value " \x100;" not-latin-1)
    (request-refused user-agent "\ta\n" line-break))
  (list (car (refusal (header-request "X-Value" " a\r")))
        (car (refusal (header-request "X-Value" "\x0; ")))
        (car (refusal (header-request "X-Value" " \x100;")))
        (car (refusal (agent-request "\ta\n")))))

(test-equal "an empty user agent is an assertion violation from make-transfer-request: a user agent is a non-empty string or #f"
  (list '(assertion-violation make-transfer-request) zero-counts zero-counts)
  (refusal (agent-request "")))

(test-equal "a header named User-Agent, in any case, beside a user agent, is refused as duplicates-field, naming header-name: libcurl would let the header win; with no user agent, or another name, it is a header like any other"
  '((request-refused header-name "User-Agent" duplicates-field)
    (request-refused header-name "user-agent" duplicates-field)
    (request-refused header-name "USER-AGENT" duplicates-field)
    (request-refused header-name "uSeR-aGeNt" duplicates-field)
    no-raise no-raise)
  (append
   (map (lambda (name)
          (car (refusal (lambda () (make-transfer-request "http://127.0.0.1:1/" 'get (list (cons name "x"))
                                                          "agent" #f #f #f)))))
        '("User-Agent" "user-agent" "USER-AGENT" "uSeR-aGeNt"))
   (list (car (refusal (lambda () (make-transfer-request "http://127.0.0.1:1/" 'get '(("User-Agent" . "x"))
                                                         #f #f #f #f))))
         (car (refusal (lambda () (make-transfer-request "http://127.0.0.1:1/" 'get '(("User-Agents" . "x"))
                                                         "agent" #f #f #f)))))))

(test-equal "a second Host header, in any case, is refused as duplicates-field, naming it: libcurl sends only the first, and RFC 9112 has a server answer 400 to two; one Host is a header like any other"
  '((request-refused header-name "Host" duplicates-field)
    (request-refused header-name "HOST" duplicates-field)
    (request-refused header-name "host" duplicates-field)
    no-raise)
  (map (lambda (headers)
         (car (refusal (lambda () (make-transfer-request "http://127.0.0.1:1/" 'get headers #f #f #f #f)))))
       '((("Host" . "a.example") ("Host" . "b.example"))
         (("host" . "a.example") ("X-B" . "2") ("HOST" . "c.example"))
         (("Host" . "a.example") ("host" . "b.example"))
         (("X-A" . "1") ("host" . "a.example")))))

(test-equal "a header named Content-Length or Transfer-Encoding, in any case, is refused as framing-header, naming it: libcurl frames the message, and M2 sends no body, so a server would wait for one; Content-Type, TE, X-Content-Length and Transfer-Encodings are headers like any other"
  '((request-refused header-name "Content-Length" framing-header)
    (request-refused header-name "content-length" framing-header)
    (request-refused header-name "CONTENT-LENGTH" framing-header)
    (request-refused header-name "cOnTeNt-LeNgTh" framing-header)
    (request-refused header-name "Transfer-Encoding" framing-header)
    (request-refused header-name "transfer-encoding" framing-header)
    (request-refused header-name "TRANSFER-ENCODING" framing-header)
    (request-refused header-name "tRaNsFeR-eNcOdInG" framing-header)
    no-raise no-raise no-raise no-raise)
  (map (lambda (name)
         (car (refusal (lambda () (make-transfer-request "http://127.0.0.1:1/" 'get (list (cons "X-A" "1") (cons name "0"))
                                                         #f #f #f #f)))))
       '("Content-Length" "content-length" "CONTENT-LENGTH" "cOnTeNt-LeNgTh"
         "Transfer-Encoding" "transfer-encoding" "TRANSFER-ENCODING" "tRaNsFeR-eNcOdInG"
         "Content-Type" "TE" "X-Content-Length" "Transfer-Encodings")))

(test-equal "a request whose header name becomes Content-Length, or Transfer-Encoding, after it was made is refused as framing-header by perform-transfer, before anything native"
  (list '(request-refused header-name framing-header) '(request-refused header-name framing-header) zero-counts)
  (let* ((changed (lambda (spelt at char)
                    (let* ((name (string-copy spelt))
                           (r (make-transfer-request "http://127.0.0.1:1/" 'get (list (cons name "0")) #f #f #f #f)))
                      (string-set! name at char)
                      (answer-of (lambda () (perform-transfer r))))))
         (framed-length (changed "Content-Lengtx" 13 #\h))
         (encoding (changed "Transfer-Encodinx" 16 #\g)))
    (list framed-length encoding (native-counts))))

(test-equal "an option's name holding U+0000 is an assertion violation from curl-easy-option, which would otherwise pass URL then anything as URL; the name without it is no option"
  '((assertion-violation curl-easy-option) not-an-option)
  (list (guard (e ((and (assertion-violation? e) (who-condition? e))
                   (list 'assertion-violation (condition-who e))))
          (curl-easy-option "URL\x0;junk"))
        (if (curl-easy-option "URLjunk") 'an-option 'not-an-option)))

;; The same name another thread flips between URLxjunk, no option, and
;; URL, U+0000, junk: each lookup is refused or finds nothing, and never URL,
;; which C would read from the flipped name. The flipper flips 100000 times
;; between sleeps of no time, once in each state, and the caller sleeps no
;; time before every tenth, so that Valgrind, running one thread at a time,
;; lets both states reach the calls.
(test-equal "curl-easy-option, while another thread flips a char of its name to U+0000: 2000 lookups each refused or finding nothing, never URL, both seen"
  '(() (refused nothing))
  (let* ((name (string-copy "URLxjunk"))
         (stop #f)
         (yield (lambda () (sleep (make-time 'time-duration 0 0))))
         (flip (lambda ()
                 (let loop ((i 0))
                   (when (< i 100000)
                     (string-set! name 3 #\nul)
                     (string-set! name 3 #\x)
                     (loop (+ i 1))))))
         (flipper (fork-thread (lambda ()
                                 (let loop ()
                                   (unless stop
                                     (flip)
                                     (yield)
                                     (flip)
                                     (string-set! name 3 #\nul)
                                     (yield)
                                     (loop)))))))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (let loop ((i 0) (odd '()) (seen '()))
          (if (= i 2000)
              (list (reverse odd) (filter (lambda (k) (memq k seen)) '(refused nothing)))
              (let ((o (begin
                         (when (= (mod i 10) 0) (yield))
                         (guard (e ((and (assertion-violation? e) (who-condition? e)
                                         (eq? (condition-who e) 'curl-easy-option))
                                    'refused))
                           (let ((found (curl-easy-option name))) (if found (list 'found found) 'nothing))))))
                (loop (+ i 1)
                      (if (memq o '(refused nothing)) odd (cons o odd))
                      (if (and (memq o '(refused nothing)) (not (memq o seen))) (cons o seen) seen))))))
      (lambda () (set! stop #t) (thread-join flipper)))))

;; --- a request changed after it was made -----------------------------------------------
;; The record holds the caller's strings and pairs, which stay mutable.
;; perform-transfer takes a snapshot and checks it, so a change made after
;; the constructor's check is refused at the transfer, before anything
;; native, wherever it is made.

;; overwrite! : String String -> Unit
;; S's chars made TEXT's, one by one; the two are the same length.
(define (overwrite! s text)
  (let loop ((i 0))
    (when (< i (string-length text))
      (string-set! s i (string-ref text i))
      (loop (+ i 1)))))

;; made-then-changed : (String String String Pair List String -> Unit) -> Refusal
;; A request made from fresh strings and pairs, passed by its constructor,
;; then CHANGE made to them, then performed: what refusal says of it.
(define (made-then-changed change)
  (let* ((url (string-copy "http://127.0.0.1:1/x"))
         (name (string-copy "X-Name"))
         (value (string-copy "safe-value-xxxxxxx"))
         (header (cons name value))
         (other (string-copy "other"))
         (headers (list header (cons (string-copy "X-Other") other)))
         (agent (string-copy "an-agent"))
         (r (make-transfer-request url 'get headers agent #f #f #f)))
    (change url name value header headers agent other)
    (refusal (lambda () (perform-transfer r)))))

(test-equal "a request changed after it was made is refused by perform-transfer, at each field, before anything native: the URL, a header's name, its value, CR LF that would inject a header, the user agent, the list, a pair's car and cdr, the second header's value, and the list's or a name's type"
  (map (lambda (r) (list r zero-counts zero-counts))
       '((url-refused embedded-nul)
         (request-refused header-name "X:Name" not-a-token)
         (request-refused header-value "safe-value-xxxxx\rx" line-break)
         (request-refused header-value "a\r\nX-Injected: yes" line-break)
         (request-refused user-agent "an\nagent" line-break)
         (request-refused header-name "X:" not-a-token)
         (request-refused header-name "X Y" not-a-token)
         (request-refused header-value " v" surrounding-whitespace)
         (request-refused header-value "o\x100;her" not-latin-1)
         (assertion-violation perform-transfer)
         (assertion-violation perform-transfer)))
  (map made-then-changed
       (list (lambda (url name value header headers agent other) (string-set! url 7 #\nul))
             (lambda (url name value header headers agent other) (string-set! name 1 #\:))
             (lambda (url name value header headers agent other) (string-set! value 16 #\return))
             (lambda (url name value header headers agent other) (overwrite! value "a\r\nX-Injected: yes"))
             (lambda (url name value header headers agent other) (string-set! agent 2 #\newline))
             (lambda (url name value header headers agent other) (set-car! headers (cons "X:" "v")))
             (lambda (url name value header headers agent other) (set-car! header (string-copy "X Y")))
             (lambda (url name value header headers agent other) (set-cdr! header (string-copy " v")))
             (lambda (url name value header headers agent other) (string-set! other 1 (integer->char #x100)))
             (lambda (url name value header headers agent other) (set-cdr! (cdr headers) 'tail))
             (lambda (url name value header headers agent other) (set-car! header 'x-name)))))

(test-equal "values that hold every char U+0001 to U+00FF but CR and LF are taken, as a header value and as a user agent, and nothing native is made"
  (list (list 'no-raise 'no-raise zero-counts) (list 'no-raise 'no-raise zero-counts))
  (list (refusal (header-request "X-Value" every-byte-but-cr-lf))
        (refusal (agent-request every-byte-but-cr-lf))))

(test-equal "every tchar, alone, and all of them together, is a name the request takes"
  (map (lambda (c) 'no-raise) (cons #f tchars))
  (map (lambda (name) (car (refusal (header-request name "v"))))
       (cons (list->string tchars) (map string tchars))))

(test-equal "every char from U+0000 to U+00FF that is no tchar, and U+0100, U+20AC and U+1F600, in the middle of a name, is refused as not-a-token, naming header-name, with nothing native at the raise"
  (map (lambda (c) (list (list 'request-refused 'header-name (string #\a c #\b) 'not-a-token)
                         zero-counts zero-counts))
       not-tchars)
  (map (lambda (c) (refusal (header-request (string #\a c #\b) "v"))) not-tchars))

(test-equal "the complement holds 182 chars: 179 of U+0000 to U+00FF, and three above"
  '(77 182)
  (list (length tchars) (length not-tchars)))

(test-equal "a name's offending char at each place is refused, and an empty name is no token"
  (map (lambda (name) (list 'request-refused 'header-name name 'not-a-token))
       '(":abcd" "a:bcd" "ab:cd" "abc:d" "abcd:" ":" " X" "X " "X Y" "X\x0;" "\xE9;" ""))
  (map (lambda (name) (car (refusal (header-request name "v"))))
       '(":abcd" "a:bcd" "ab:cd" "abc:d" "abcd:" ":" " X" "X " "X Y" "X\x0;" "\xE9;" "")))

(test-equal "every header is checked, the last of three among them, and the user agent after them"
  '((request-refused header-name "X:" not-a-token)
    (request-refused header-value "a\nb" line-break)
    (request-refused user-agent "a\x0;b" embedded-nul))
  (map (lambda (args) (car (refusal (lambda () (apply make-transfer-request args)))))
       (list (list "http://127.0.0.1:1/" 'get '(("X-A" . "1") ("X-B" . "2") ("X:" . "3")) #f #f #f #f)
             (list "http://127.0.0.1:1/" 'get '(("X-A" . "1") ("X-B" . "2") ("X-C" . "a\nb")) #f #f #f #f)
             (list "http://127.0.0.1:1/" 'get '(("X-A" . "1") ("X-B" . "2")) "a\x0;b" #f #f #f))))

(test-equal "a header's name is checked before its value, and headers in order: the first header's fault is the one named"
  '((request-refused header-name "X:" not-a-token)
    (request-refused header-value "a\rb" line-break)
    (request-refused header-name "X:" not-a-token))
  (list (car (refusal (lambda () (make-transfer-request "http://127.0.0.1:1/" 'get '(("X:" . "a\rb")) #f #f #f #f))))
        (car (refusal (lambda () (make-transfer-request "http://127.0.0.1:1/" 'get
                                                        '(("X-Ok" . "a\rb") ("X:" . "v")) #f #f #f #f))))
        (car (refusal (lambda () (make-transfer-request "http://127.0.0.1:1/" 'get
                                                        '(("X:" . "v")) "a\rb" #f #f #f))))))

(test-equal "wrong types are assertion violations from make-transfer-request, with nothing native made"
  (map (lambda (x) (list '(assertion-violation make-transfer-request) zero-counts zero-counts))
       (iota-from 0 21))
  (map (lambda (args) (refusal (lambda () (apply make-transfer-request args))))
       (list (list 'not-a-url 'get '() #f #f #f #f)
             (list "http://a/" 'post '() #f #f #f #f)
             (list "http://a/" "get" '() #f #f #f #f)
             (list "http://a/" 'get 'none #f #f #f #f)
             (list "http://a/" 'get '(("X" . 1)) #f #f #f #f)
             (list "http://a/" 'get '((x . "v")) #f #f #f #f)
             (list "http://a/" 'get '(("X" "v")) #f #f #f #f)
             (list "http://a/" 'get '(("X" . "v") . tail) #f #f #f #f)
             (list "http://a/" 'get '() 'agent #f #f #f)
             (list "http://a/" 'get '() #f 0 #f #f)
             (list "http://a/" 'get '() #f -1 #f #f)
             (list "http://a/" 'get '() #f 1.5 #f #f)
             (list "http://a/" 'get '() #f (expt 2 63) #f #f)
             (list "http://a/" 'get '() #f "300" #f #f)
             (list "http://a/" 'get '() #f #f -1 #f)
             (list "http://a/" 'get '() #f #f 1.0 #f)
             (list "http://a/" 'get '() #f #f (- (expt 2 63) 1) #f)
             (list "http://a/" 'get '() #f #f (expt 2 63) #f)
             (list "http://a/" 'get '() #f #f "10" #f)
             (list "http://a/" 'get '() #f #f #f 'hook)
             (list "http://a/" 'get '() #f #f #f "hook"))))

(test-equal "the edges a request takes: a timeout of 1 and of the largest long, a body limit of 0 and of 2^63 - 2, method head"
  '(no-raise no-raise no-raise no-raise no-raise)
  (map (lambda (args) (car (refusal (lambda () (apply make-transfer-request args)))))
       (list (list "http://a/" 'get '() #f 1 #f #f)
             (list "http://a/" 'get '() #f (- (expt 2 63) 1) #f #f)
             (list "http://a/" 'get '() #f #f 0 #f)
             (list "http://a/" 'get '() #f #f (- (expt 2 63) 2) #f)
             (list "http://a/" 'head '() #f #f #f #f))))

(test-equal "a request's fields read back as given"
  (list "http://a/b" 'head '(("X-A" . "1") ("X-A" . "2")) "agent" 300 10 'the-hook)
  (let* ((hook (lambda (chunk) #f))
         (r (make-transfer-request "http://a/b" 'head '(("X-A" . "1") ("X-A" . "2")) "agent" 300 10 hook)))
    (list (transfer-request-url r) (transfer-request-method r) (transfer-request-headers r)
          (transfer-request-user-agent r) (transfer-request-timeout-ms r)
          (transfer-request-body-limit r)
          (if (eq? (transfer-request-chunk-hook r) hook) 'the-hook (transfer-request-chunk-hook r)))))

;; --- the option table, written out here ---------------------------------------------------

(test-equal "option-bindings: long and values to the long binding, off-t to off-t, and every other CURLOT type to the pointer binding"
  '((long . long) (values . long) (off-t . off-t) (object . pointer) (string . pointer)
    (slist . pointer) (cbptr . pointer) (blob . pointer) (function . pointer))
  bindings-read)

(test-equal "option-bindings names each of curlot-types' types once, in its order"
  (map car curlot-types)
  (guard (e (#t (list 'raised (describe e)))) (map car option-bindings)))

(test-equal "option-binding: each CURLOT code to its binding, by curlot-types, and a code no type has is refused"
  '(long long off-t pointer pointer pointer pointer pointer pointer (assertion-violation option-binding))
  (map (lambda (code)
         (guard (e ((and (assertion-violation? e) (who-condition? e))
                    (list 'assertion-violation (condition-who e))))
           (option-binding code)))
       '(0 1 2 3 4 5 6 7 8 9)))

(test-equal "option-setter: long is native's curl-easy-setopt-long, off-t its curl-easy-setopt-off-t, pointer its curl-easy-setopt-pointer, and any other name is refused"
  '(#t #t #t (assertion-violation option-setter))
  (list (eq? (option-setter 'long) curl-easy-setopt-long)
        (eq? (option-setter 'off-t) curl-easy-setopt-off-t)
        (eq? (option-setter 'pointer) curl-easy-setopt-pointer)
        (guard (e ((and (assertion-violation? e) (who-condition? e))
                   (list 'assertion-violation (condition-who e))))
          (option-setter 'string))))

;; The string list's count: slist while the list is not NULL, once however
;; long it grows, and a second free refused before C.
(test-equal "a string list is counted slist once it holds a string, still once after a second, and zero once freed; freeing it again raises before C"
  '(((slist . 1)) ((slist . 1)) ((slist . 0)) (assertion-violation count-down!) ((slist . 0)))
  (let* ((slist-count (lambda () (list (assq 'slist (native-counts)))))
         (list1 (call-with-c-string "X-A: 1" (lambda (address) (curl-slist-append 0 address))))
         (after-one (slist-count))
         (list2 (call-with-c-string "X-B: 2" (lambda (address) (curl-slist-append list1 address))))
         (after-two (slist-count)))
    (curl-slist-free-all list2)
    ;; The second free is tried only once the count reads zero, where it
    ;; must raise before C: with a count left over, it would reach
    ;; curl_slist_free_all, and free the list twice.
    (let* ((after-free (slist-count))
           (again (if (equal? after-free '((slist . 0)))
                      (guard (e ((and (assertion-violation? e) (who-condition? e))
                                 (list 'assertion-violation (condition-who e))))
                        (curl-slist-free-all list2)
                        'freed-twice)
                      'not-tried-with-a-count-left)))
      (list after-one after-two after-free again (slist-count)))))

;; --- the test seam's deny-list (ADR-0009, amended 2026-10-23) ---------------------------

(test-equal "owned-option-names, written out: the options the transfer always sets and the pins' bitmasks, then each request field's, then the owned settings' twins"
  '("URL" "PROTOCOLS_STR" "REDIR_PROTOCOLS_STR" "PROTOCOLS" "REDIR_PROTOCOLS" "NOSIGNAL"
    "WRITEFUNCTION" "WRITEDATA" "ERRORBUFFER"
    "CURLU" "NOBODY" "HTTPHEADER" "USERAGENT" "TIMEOUT_MS" "MAXFILESIZE_LARGE"
    "TIMEOUT" "MAXFILESIZE" "HTTPGET" "POST" "UPLOAD" "PUT")
  owned-option-names)

(test-equal "request-field-options, written out: url's CURLU, method's NOBODY, headers' HTTPHEADER, user-agent's USERAGENT, timeout-ms's TIMEOUT_MS and body-limit's MAXFILESIZE_LARGE"
  '((url . "CURLU") (method . "NOBODY") (headers . "HTTPHEADER") (user-agent . "USERAGENT")
    (timeout-ms . "TIMEOUT_MS") (body-limit . "MAXFILESIZE_LARGE"))
  request-field-options)

(test-equal "every request field's option is an owned option, so the test seam refuses it"
  '()
  (filter (lambda (entry) (not (member (cdr entry) owned-option-names))) request-field-options))

;; The record's own fields, read from its record type: a field added later
;; needs a row, or its place here among the fields that set no option.
(test-equal "every field of a request has a row in request-field-options, but chunk-hook, which sets no option"
  '()
  (guard (e (#t (list 'raised (describe e))))
    (filter (lambda (field) (not (or (assq field request-field-options) (memq field '(chunk-hook)))))
            (vector->list (record-type-field-names
                           (record-rtd (make-transfer-request "http://a/" 'get '() #f #f #f #f)))))))

;; seam-refusal : (Listof Pair) -> Refusal
;; What refusal says of the test seam given OPTIONS, on a URL nothing
;; listens on: a refusal comes before anything native, and a transfer that
;; ran would answer 7 there.
(define (seam-refusal options)
  (refusal (lambda () (perform-transfer-with (request "http://127.0.0.1:1/") options))))

(test-equal "the test seam refuses each owned option this libcurl knows, by id, as owned-option, naming it, before anything native"
  (map (lambda (name)
         (list (if (curl-easy-option name)
                   (list 'request-refused 'options name 'owned-option)
                   (list 'transfer-refused 'unknown-option name))
               zero-counts zero-counts))
       owned-option-names)
  (map (lambda (name) (seam-refusal (list (cons name 1)))) owned-option-names))

(test-equal "an alias of an owned option is refused as owned-option: FILE is WRITEDATA's id, and RTSPHEADER HTTPHEADER's"
  (list '(same same)
        (list '(request-refused options "FILE" owned-option) zero-counts zero-counts)
        (list '(request-refused options "RTSPHEADER" owned-option) zero-counts zero-counts))
  (list (map (lambda (pair)
               (let ((a (curl-easy-option (car pair))) (b (curl-easy-option (cdr pair))))
                 (if (and a b (= (car a) (car b))) 'same (list (car pair) a (cdr pair) b))))
             '(("FILE" . "WRITEDATA") ("RTSPHEADER" . "HTTPHEADER")))
        (seam-refusal '(("FILE" . 1)))
        (seam-refusal '(("RTSPHEADER" . 1)))))

(test-equal "the test seam refuses an option of every other CURLOT type as unsupported-type, before anything native: a string, a string list, an object, a callback pointer, a function and a blob"
  (list '(string slist object cbptr function blob)
        (map (lambda (name) (list (list 'request-refused 'options name 'unsupported-type) zero-counts zero-counts))
             '("ACCEPT_ENCODING" "HTTP200ALIASES" "STDERR" "HEADERDATA" "XFERINFOFUNCTION" "SSLCERT_BLOB")))
  (list (map (lambda (name)
               (let ((o (curl-easy-option name)))
                 (if o (car (find (lambda (entry) (= (cdr entry) (cdr o))) curlot-types)) (list 'unknown name))))
             '("ACCEPT_ENCODING" "HTTP200ALIASES" "STDERR" "HEADERDATA" "XFERINFOFUNCTION" "SSLCERT_BLOB"))
        (map (lambda (name) (seam-refusal (list (cons name 1))))
             '("ACCEPT_ENCODING" "HTTP200ALIASES" "STDERR" "HEADERDATA" "XFERINFOFUNCTION" "SSLCERT_BLOB"))))

(test-equal "the test seam's values are checked before anything native: a string for a long, a long past long's range, an off_t past its range, are assertion violations from perform-transfer-with; options of any other shape too; an unknown name is unknown-option"
  (map (lambda (r) (list r zero-counts zero-counts))
       '((assertion-violation perform-transfer-with)
         (assertion-violation perform-transfer-with)
         (assertion-violation perform-transfer-with)
         (assertion-violation perform-transfer-with)
         (assertion-violation perform-transfer-with)
         (transfer-refused unknown-option "NO_SUCH_OPTION")))
  (map seam-refusal
       (list '(("MAXREDIRS" . "3"))
             (list (cons "MAXREDIRS" (expt 2 63)))
             (list (cons "MAX_RECV_SPEED_LARGE" (expt 2 63)))
             'not-a-list
             '((maxredirs . 3))
             '(("NO_SUCH_OPTION" . 1)))))

;; --- what perform-transfer-with sets, read from transfer.sls as data ---------------------

(define transfer-source "src/curl/private/transfer.sls")

;; transfer-definition : Symbol -> Any
;; The (define (NAME ...) ...) form in transfer.sls's library, or what went
;; wrong.
(define (transfer-definition name)
  (guard (e (#t (list 'unreadable (describe e))))
    (let* ((form (call-with-port (open-file-input-port transfer-source (file-options) (buffer-mode block)
                                                       (make-transcoder (utf-8-codec)))
                   read))
           (definition (find (lambda (f) (and (pair? f) (eq? (car f) 'define) (pair? (cdr f))
                                              (pair? (cadr f)) (eq? (car (cadr f)) name)))
                             (cddddr form))))
      (or definition (list 'no-definition name)))))

;; option-sets : Any (Listof Symbol) -> (Listof (List Any Any (Listof Symbol)))
;; Each (set-option! EASY NAME VALUE BUFFER) and (set-string-option! ...)
;; in X: its NAME and VALUE as written, and the heads of the forms around
;; it, outermost first, ENCLOSING among them.
(define (option-sets x enclosing)
  (if (pair? x)
      (let ((inner (if (symbol? (car x)) (append enclosing (list (car x))) enclosing)))
        (append (if (and (memq (car x) '(set-option! set-string-option!)) (list? x) (= (length x) 5))
                    (list (list (caddr x) (cadddr x) enclosing))
                    '())
                (option-sets (car x) enclosing)
                (let loop ((rest (cdr x)) (found '()))
                  (if (pair? rest) (loop (cdr rest) (append found (option-sets (car rest) inner))) found))))
      '()))

(define perform-sets
  (let ((d (transfer-definition 'perform-transfer-with)))
    (if (and (pair? d) (eq? (car d) 'define)) (option-sets (cddr d) '()) d)))

;; --- the pins, read from transfer.sls as data ----------------------------------------
;; ADR-0003's protocol pins and the signal rule are one table, set by one
;; call, the first form of the easy handle's extent, before the transfer
;; runs; their names, and the deprecated bitmasks', stand nowhere else. The
;; limit of these checks: they hold the pins against an accidental move, a
;; set made later, or conditionally, or never, or an owned name undone in
;; place; not against a rewrite made to pass them, such as a name built from
;; pieces at run time.

;; transfer-library : Any
;; transfer.sls's library form, or what went wrong.
(define transfer-library
  (guard (e (#t (list 'unreadable (describe e))))
    (call-with-port (open-file-input-port transfer-source (file-options) (buffer-mode block)
                                          (make-transcoder (utf-8-codec)))
      read)))

(test-equal "pinned-options, written out: PROTOCOLS_STR and REDIR_PROTOCOLS_STR at \"http,https\", and NOSIGNAL at 1"
  '(("PROTOCOLS_STR" . "http,https") ("REDIR_PROTOCOLS_STR" . "http,https") ("NOSIGNAL" . 1))
  pinned-options)

(test-equal "set-pinned-options!, read from transfer.sls, is exactly the loop that sets each pinned option, a string through set-string-option!, a number through set-option!"
  '(define (set-pinned-options! easy buffer)
     (for-each (lambda (pin)
                 (if (string? (cdr pin))
                     (set-string-option! easy (car pin) (cdr pin) buffer)
                     (set-option! easy (car pin) (cdr pin) buffer)))
               pinned-options))
  (transfer-definition 'set-pinned-options!))

;; easy-body : Any -> (U (Listof Any) #f)
;; The body of the lambda handed to call-with-easy in X.
(define (easy-body x)
  (cond ((and (list? x) (= (length x) 2) (eq? (car x) 'call-with-easy)
              (pair? (cadr x)) (eq? (car (cadr x)) 'lambda) (list? (cadr x)))
         (cddr (cadr x)))
        ((pair? x) (or (easy-body (car x)) (easy-body (cdr x))))
        (else #f)))

;; holds? : Any Any -> Boolean
(define (holds? x datum)
  (or (equal? x datum) (and (pair? x) (or (holds? (car x) datum) (holds? (cdr x) datum)))))

;; symbol-count : Symbol Any -> Natural
(define (symbol-count name x)
  (cond ((eq? x name) 1)
        ((pair? x) (+ (symbol-count name (car x)) (symbol-count name (cdr x))))
        (else 0)))

(test-equal "the easy handle's extent sets the pins first: its body's first form is (set-pinned-options! easy buffer), a later form calls (perform), which runs curl_easy_perform, and set-pinned-options! stands twice in transfer.sls, its definition and that call"
  '(pins-first perform-later 2)
  (let ((body (easy-body (transfer-definition 'perform-transfer-with))))
    (if body
        (list (if (equal? (car body) '(set-pinned-options! easy buffer)) 'pins-first (list 'first-form (car body)))
              (if (exists (lambda (f) (holds? f '(perform))) (cdr body)) 'perform-later 'no-perform-after)
              (symbol-count 'set-pinned-options! transfer-library))
        (list 'no-easy-body))))

;; pin-names : (Listof String)
(define pin-names '("PROTOCOLS_STR" "REDIR_PROTOCOLS_STR" "PROTOCOLS" "REDIR_PROTOCOLS" "NOSIGNAL"))

;; pin-name-places : Any -> (Listof (List String Any Symbol))
;; Each of pin-names as a string in the library form's body: the name, the
;; top-level definition holding it, and whether it stands inside a quote.
(define (pin-name-places library)
  (define (walk x where quoted?)
    (cond ((and (string? x) (member x pin-names)) (list (list x where (if quoted? 'quoted 'code))))
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

(test-equal "the names PROTOCOLS_STR, REDIR_PROTOCOLS_STR, PROTOCOLS, REDIR_PROTOCOLS and NOSIGNAL stand in transfer.sls only as quoted data: five in owned-option-names, three in pinned-options"
  (list-sort (lambda (a b) (string<? (written a) (written b)))
             '(("PROTOCOLS_STR" owned-option-names quoted) ("REDIR_PROTOCOLS_STR" owned-option-names quoted)
               ("PROTOCOLS" owned-option-names quoted) ("REDIR_PROTOCOLS" owned-option-names quoted)
               ("NOSIGNAL" owned-option-names quoted)
               ("PROTOCOLS_STR" pinned-options quoted) ("REDIR_PROTOCOLS_STR" pinned-options quoted)
               ("NOSIGNAL" pinned-options quoted)))
  (guard (e (#t (list 'unreadable (describe e))))
    (list-sort (lambda (a b) (string<? (written a) (written b))) (pin-name-places transfer-library))))

(test-equal "pin-name-places, the reader: a name in quoted data, and the same name in code, each with the definition holding it"
  '(("NOSIGNAL" a quoted) ("NOSIGNAL" b code))
  (pin-name-places '(library (x) (export) (import) (define a '("NOSIGNAL")) (define (b) (f "NOSIGNAL")))))

;; --- the mutexes, read from transfer.sls as data ---------------------------------------
;; transfer.sls holds each of its mutexes through locked, inside a critical
;; section, so no engine's expiry, nor timer, falls between the take and
;; its dynamic-wind, nor abandons a table's update half made. The limit is
;; the pins': this holds a with-mutex added by accident, not a rewrite made
;; to pass, such as a mutex reached under another name.

(test-equal "locked, read from transfer.sls, holds its mutex inside a critical section; with-mutex stands twice in transfer.sls, in its import and in locked, and mutex-acquire and mutex-release nowhere"
  '((define (locked lock thunk) (critical-section (with-mutex lock (thunk)))) 2 0 0)
  (list (transfer-definition 'locked)
        (symbol-count 'with-mutex transfer-library)
        (symbol-count 'mutex-acquire transfer-library)
        (symbol-count 'mutex-release transfer-library)))

;; owned-set? : Any -> Boolean
;; NAME, as a set-option! call writes it, is an owned option: a literal
;; owned-option-names holds, or (field-option 'FIELD) for a field
;; request-field-options holds.
(define (owned-set? name)
  (or (and (string? name) (member name owned-option-names) #t)
      (and (list? name) (= (length name) 2) (eq? (car name) 'field-option)
           (pair? (cadr name)) (eq? (car (cadr name)) 'quote)
           (assq (cadr (cadr name)) request-field-options) #t)))

(test-equal "every option perform-transfer-with sets is an owned option, written as a literal or through field-option, but for the test seam's own settings, set once, by (car setting)"
  '(() 1)
  (if (list? perform-sets)
      (list (map car (filter (lambda (s) (not (or (owned-set? (car s)) (equal? (car s) '(car setting)))))
                             perform-sets))
            (length (filter (lambda (s) (equal? (car s) '(car setting))) perform-sets)))
      perform-sets))

(test-equal "option-sets, the reader: a set at any depth, a form's head among them, with the heads around it, and its name and value as written"
  '(("A" 1 (begin)) ("B" "x" (begin when)) ((field-option 'url) u (begin)))
  (option-sets '(begin (set-option! e "A" 1 b) (when c (set-string-option! e "B" "x" b))
                       ((set-option! e (field-option 'url) u b)))
               '()))

(test-equal "http-version-symbol: CURL_HTTP_VERSION_1_0, 1_1, 2_0 and 3 as http/1.0, http/1.1, http/2 and http/3, 0 as no version, and any other number as itself"
  '(no-version http/1.0 http/1.1 http/2 http/3 4 31)
  (map (lambda (n) (or (http-version-symbol n) 'no-version)) '(0 1 2 3 30 4 31)))

(test-equal "bytes->latin-1: each byte its own char, so C3 A9 is two chars, U+00C3 and U+00A9, never UTF-8's é; 0x80 to 0xFF each U+0080 to U+00FF"
  (list (string (integer->char #xC3) (integer->char #xA9)) (chars (iota-from #x80 128)))
  (list (bytes->latin-1 (u8-list->bytevector '(#xC3 #xA9)))
        (bytes->latin-1 (u8-list->bytevector (iota-from #x80 128)))))

;; --- against the origin ------------------------------------------------------------------

;; Answers the origin run records, for the verdict tests after it.
(define varying-answered '())

;; raw-echo-body : Origin (Listof String) -> String
;; The request head /raw/echo echoes for a GET whose lines after Host are
;; LINES, libcurl's own Accept among them, each with its CRLF: its exact
;; bytes.
(define (raw-echo-body o lines)
  (apply string-append "GET /raw/echo HTTP/1.1\r\nHost: " (host-of o 'raw) "\r\n"
         (append lines (list "\r\n"))))

;; echoed : String -> Answer
;; What /raw/echo's whole response is for a request head BODY.
(define (echoed body)
  (list 'response 200 'http/1.1 (list (list "Content-Length" (number->string (string-length body)))) body))

;; engine-sweep : (-> Any) Natural -> (List Symbol Natural)
;; THUNK run in a fresh engine with fuel 1, 1+STEP, 1+2 STEP and so on, each
;; that runs out abandoned, until one completes: (completed EXPIRED), or
;; (never-completed EXPIRED) past 100000 fuel.
(define (engine-sweep thunk step)
  (let loop ((fuel 1) (expired 0))
    (cond ((> fuel 100000) (list 'never-completed expired))
          (((make-engine thunk) fuel (lambda (ticks v) #t) (lambda (e) #f)) (list 'completed expired))
          (else (loop (+ fuel step) (+ expired 1))))))

;; swept : (List Symbol Natural) -> Any
;; completed-after-expiries when the sweep completed after more than ten
;; engines ran out, its positive evidence; else the sweep itself.
(define (swept result)
  (if (and (eq? (car result) 'completed) (> (cadr result) 10)) 'completed-after-expiries result))

;; guarded : (-> Any) -> Any
;; THUNK's value, or (raised TEXT) for whatever it raised.
(define (guarded thunk)
  (guard (e (#t (list 'raised (describe e)))) (thunk)))

;; other-thread-can : (-> Any) -> Symbol
;; other-thread-ran when THUNK, run in a fresh thread, returns within 10 s;
;; other-thread-raised when it raises; other-thread-blocked when it does
;; neither. A mutex this thread left held blocks another thread, never this
;; one: Chez's mutexes are recursive. A blocked thread is left blocked.
(define (other-thread-can thunk)
  (let ((done #f))
    (fork-thread (lambda () (guard (e (#t (set! done 'raised))) (thunk) (set! done 'ran))))
    (let loop ((i 0))
      (cond ((eq? done 'ran) 'other-thread-ran)
            ((eq? done 'raised) 'other-thread-raised)
            ((= i 1000) 'other-thread-blocked)
            (else (pause-ms 10) (loop (+ i 1)))))))

;; every-lock : -> Any
;; Takes each mutex transfer.sls and the counters hold, in turn: the
;; live-transfer table's, the option cache's, and the counts'.
(define (every-lock)
  (live-transfer-count)
  (cached-option-names)
  (native-counts))

;; --- the escape child: tests/transfer-escapes.sps ---------------------------------------

;; library-path : -> String
;; This suite's library path, as --libdirs takes it: so the child finds the
;; libraries this suite found, wherever it runs, make test or a copy.
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

;; escape-bound : Positive-Integer
;; The seconds the child may run before it is killed. Measured: about 8 s
;; natively, the same beside 4 busy loops on 18 cores, and 39 s beside 36,
;; most of it in the shells that count sockets. make test gives the whole
;; suite 300 s.
(define escape-bound 180)

;; escape-script : String
;; sh -c ESCAPE-SCRIPT sh COMMAND...: COMMAND, with stdin at its end, under
;; GNU timeout (gtimeout on macOS), killed with SIGKILL after escape-bound
;; seconds, exit 137; with neither found, exit 125, saying so. It is
;; (curl-testing)'s bounded-script, whose bound is 10 s, with this bound,
;; for the reasons given there: the shell's stderr is /dev/null, so dash's
;; "Killed" is not the command's.
(define escape-script
  (string-append
   "t=$(command -v timeout || command -v gtimeout) || { echo 'transfer-escapes: no timeout' >&2; exit 125; }\n"
   "exec 3>&2 2>/dev/null\n"
   "( exec \"$t\" -s KILL " (number->string escape-bound) " \"$@\" </dev/null 2>&3 3>&- )\n"
   "exit $?\n"))

;; escape-run : (U (List Integer (Listof Any) String) (List 'raised String))
;; tests/transfer-escapes.sps run once, in a child Chez, under
;; escape-script: its exit status, what it printed, read as data, and its
;; stderr.
(define escape-run
  (guard (e (#t (list 'raised (describe e))))
    (let ((r (capture-command (list "sh" "-c" escape-script "sh" (getenv "CHEZ") "--libdirs" (library-path)
                                    "--program" "tests/transfer-escapes.sps"))))
      (list (car r) (read-all (cadr r)) (caddr r)))))

;; escape-shapes : (Listof (Pairof Symbol Natural))
;; Each datum the child prints, by its head, and its length.
(define escape-shapes '((sweep . 6) (timer . 5) (interrupt . 4) (after . 4) (done . 1)))

;; run-problem : Any Positive-Integer -> Any
;; #f when RUN, an escape-run, ran to its end: exit 0, every datum of a
;; known shape, (done) last and only there, nothing on stderr. Else what
;; went wrong, short, so a failing test names it whole: (child-did-not-run
;; TEXT), (child-timed-out BOUND), (child-exited STATUS STDERR),
;; (child-output-ended-early LAST), (child-printed-an-unknown-shape DATUM)
;; or (child-wrote-on-stderr STDERR).
(define (run-problem run bound)
  (define (cut text) (if (> (string-length text) 300) (string-append (substring text 0 300) "...") text))
  (define (shaped? d)
    (and (list? d) (pair? d) (assq (car d) escape-shapes)
         (= (length d) (cdr (assq (car d) escape-shapes)))))
  (cond ((not (and (list? run) (= (length run) 3))) (list 'child-did-not-run run))
        ((eq? (car run) 'raised) (list 'child-did-not-run (cadr run)))
        ((eqv? (car run) 137) (list 'child-timed-out bound))
        ((not (eqv? (car run) 0)) (list 'child-exited (car run) (cut (caddr run))))
        ((or (null? (cadr run)) (not (equal? (list-ref (cadr run) (- (length (cadr run)) 1)) '(done))))
         (list 'child-output-ended-early (if (null? (cadr run)) 'nothing (list-ref (cadr run) (- (length (cadr run)) 1)))))
        ((find (lambda (d) (not (shaped? d))) (cadr run))
         => (lambda (d) (list 'child-printed-an-unknown-shape d)))
        ((not (= (length (filter (lambda (d) (equal? d '(done))) (cadr run))) 1))
         (list 'child-printed-an-unknown-shape '(done)))
        ((not (string=? (caddr run) "")) (list 'child-wrote-on-stderr (cut (caddr run))))
        (else #f)))

;; escape-problem : Any
;; What went wrong with the child's run, or #f.
(define escape-problem (run-problem escape-run escape-bound))

;; escape-data : Symbol -> (Listof (Listof Any))
;; The child's data headed by HEAD; none when its run went wrong.
(define (escape-data head)
  (if escape-problem
      '()
      (filter (lambda (d) (eq? (car d) head)) (cadr escape-run))))

(define one-easy
  '((block . 0) (easy . 1) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0)))

;; escape-cases : -> (Listof (List Any Any Any))
;; Every sweep and timer case the child printed, well formed, as its
;; OUTCOME, its counts' DELTA and its new SOCKETS: (sweep NAME FUEL OUTCOME
;; DELTA SOCKETS) and (timer TICKS OUTCOME DELTA SOCKETS).
(define (escape-cases)
  (append (map (lambda (d) (list-tail d 3)) (filter (lambda (d) (= (length d) 6)) (escape-data 'sweep)))
          (map (lambda (d) (list-tail d 2)) (filter (lambda (d) (= (length d) 5)) (escape-data 'timer)))))

;; escape-kind : Any Any -> (U 'completed 'outside 'inside #f)
;; A case's OUTCOME and the COUNTS it left, judged: completed, every count
;; zero; outside, run out or escaped outside perform, every count zero;
;; inside, escaped inside perform, one easy left and nothing else. #f for
;; anything else.
(define (escape-kind outcome counts)
  (cond ((and (pair? outcome) (eq? (car outcome) 'completed) (equal? counts zero-counts)) 'completed)
        ((and (memq outcome '(expired escaped)) (equal? counts zero-counts)) 'outside)
        ((and (memq outcome '(expired escaped)) (equal? counts one-easy)) 'inside)
        (else #f)))

;; sweep-verdict : String -> Any
;; The child's sweep NAME: the cases no kind fits, whether some ran out
;; outside perform and some escaped inside it, how many completed, the
;; last case's outcome, and whether the fuels ran 1, 2, 3 on, once each.
(define (sweep-verdict name)
  (let* ((cases (filter (lambda (d) (and (= (length d) 6) (equal? (cadr d) name))) (escape-data 'sweep)))
         (kinds (map (lambda (c) (escape-kind (list-ref c 3) (list-ref c 4))) cases)))
    (cond
      (escape-problem escape-problem)
      ((null? cases) (list 'no-cases name))
      (else
        (list (filter (lambda (c) (not (escape-kind (list-ref c 3) (list-ref c 4)))) cases)
              (if (memq 'outside kinds) 'outside-seen 'no-outside)
              (if (memq 'inside kinds) 'inside-seen 'no-inside)
              (length (filter (lambda (k) (eq? k 'completed)) kinds))
              (list-ref (list-ref cases (- (length cases) 1)) 3)
              (equal? (map caddr cases) (iota-from-1 (length cases))))))))

;; inside-count : String -> Natural
;; How many of the child's sweep NAME's engines escaped inside perform.
(define (inside-count name)
  (length (filter (lambda (d) (and (= (length d) 6) (equal? (cadr d) name)
                                   (eq? (escape-kind (list-ref d 3) (list-ref d 4)) 'inside)))
                  (escape-data 'sweep))))

;; iota-from-1 : Natural -> (Listof Natural)
(define (iota-from-1 n)
  (let loop ((i n) (found '()))
    (if (= i 0) found (loop (- i 1) (cons i found)))))

;; timer-verdict : -> Any
;; The child's timer cases: those no kind fits, or that completed otherwise
;; than whole; whether one escaped inside perform; and whether every
;; completion was the 40-byte body.
(define (timer-verdict)
  (let ((cases (filter (lambda (d) (= (length d) 5)) (escape-data 'timer))))
    (cond
      (escape-problem escape-problem)
      ((null? cases) '(no-cases timer))
      (else
        (list (filter (lambda (c) (not (escape-kind (caddr c) (cadddr c)))) cases)
              (if (exists (lambda (c) (eq? (escape-kind (caddr c) (cadddr c)) 'inside)) cases)
                  'inside-seen
                  'no-inside)
              (if (for-all (lambda (c) (or (not (pair? (caddr c)))
                                           (equal? (caddr c) '(completed (response 200 40)))))
                           cases)
                  'whole
                  'not-whole))))))

;; interrupt-verdict : -> Any
;; The child's interrupt case: whether its handler ran once, with 3 to 19
;; bytes come, then the transfer's answer and the counts it left.
(define (interrupt-verdict)
  (let ((cases (escape-data 'interrupt)))
    (if (or escape-problem (not (= (length cases) 1)))
        (or escape-problem (list 'interrupt-cases (length cases)))
        (let ((fired (cadr (car cases))))
          (list (if (and (list? fired) (= (length fired) 1) (<= 3 (car fired) 19))
                    'once-before-the-end
                    (list 'fired fired))
                (caddr (car cases))
                (cadddr (car cases)))))))

;; after-verdict : -> Any
;; The child's after line: live transfers, whether another thread took
;; every mutex, and whether the counts are one easy per escape inside
;; perform and nothing else.
(define (after-verdict)
  (let ((cases (escape-data 'after))
        (inside (length (filter (lambda (c) (eq? (escape-kind (car c) (cadr c)) 'inside)) (escape-cases)))))
    (if (or escape-problem (not (= (length cases) 1)))
        (or escape-problem (list 'after-cases (length cases)))
        (let ((counts (cadddr (car cases))))
          (list (cadr (car cases))
                (caddr (car cases))
                (if (equal? counts (map (lambda (k) (if (eq? (car k) 'easy) (cons 'easy inside) k)) zero-counts))
                    'escapes-counted
                    (list 'counts counts 'inside inside)))))))

;; sockets-verdict : -> Any
;; The child's sweep and timer cases that completed, or ran out outside
;; perform, and left a new socket; and whether an escape inside perform
;; left one, which shows the sockets were counted. Off Linux, where the
;; child counts none, unmeasured.
(define (sockets-verdict)
  (let ((cases (escape-cases)))
    (cond (escape-problem escape-problem)
          ((null? cases) '(no-cases sweep timer))
          ((not (for-all (lambda (c) (integer? (caddr c))) cases)) 'unmeasured)
          (else
           (list (filter (lambda (c) (and (memq (escape-kind (car c) (cadr c)) '(completed outside))
                                          (not (= (caddr c) 0))))
                         cases)
                 (if (exists (lambda (c) (and (eq? (escape-kind (car c) (cadr c)) 'inside) (> (caddr c) 0)))
                             cases)
                     'inside-left-sockets
                     'no-inside-left-sockets))))))

;; refused-recording : (-> Any) -> Any
;; THUNK's &curl-transfer-error as (refused REASON CODE (WHO IRRITANTS)),
;; the recorded object's who and irritants; anything else as answer-of
;; names it.
(define (refused-recording thunk)
  (guard (e ((curl-transfer-error? e)
             (let ((rec (curl-transfer-error-recorded e)))
               (list 'refused (curl-transfer-error-reason e) (curl-transfer-error-code e)
                     (if (and (condition? rec) (who-condition? rec) (irritants-condition? rec))
                         (list (condition-who rec) (condition-irritants rec))
                         (list 'recorded rec)))))
            (#t (list 'raised (describe e))))
    (thunk)
    'no-raise))

;; sockets-open : -> (U Natural #f)
;; The sockets this process holds, counted from /proc on Linux; #f
;; elsewhere.
(define (sockets-open)
  (and (file-directory? "/proc/self/fd")
       (let ((r (capture-command
                 (list "sh" "-c" (string-append "ls -l /proc/" (number->string (get-process-id))
                                                "/fd | grep -c socket:")))))
         (let ((text (cadr r)))
           (string->number (if (and (> (string-length text) 0)
                                    (char=? (string-ref text (- (string-length text) 1)) #\newline))
                               (substring text 0 (- (string-length text) 1))
                               text))))))

;; texts-of : (-> Any) -> Any
;; For THUNK's &curl-transfer-error: whether its strerror is
;; curl_easy_strerror's for its code, called here, and its error buffer's
;; text, or buffer-is-text when that is a non-empty string, no U+0000 in
;; it, shorter than CURL_ERROR_SIZE, and not one of the measured texts.
(define (texts-of thunk)
  (guard (e ((curl-transfer-error? e)
             (let ((strerror (curl-transfer-error-strerror e))
                   (buffer (curl-transfer-error-error-buffer e)))
               (list (if (and (string? strerror)
                              (equal? strerror (curl-easy-strerror (curl-transfer-error-code e))))
                         'strerror-is-libcurls
                         (list 'strerror strerror 'code (curl-transfer-error-code e)))
                     (cond ((member buffer measured-texts) buffer)
                           ((and (string? buffer) (> (string-length buffer) 0)
                                 (< (string-length buffer) curl-error-size)
                                 (not (memv #\nul (string->list buffer))))
                            'buffer-is-text)
                           (else (list 'buffer buffer))))))
            (#t (list 'raised (describe e))))
    (thunk)
    'no-raise))

;; measured-texts : (Listof String)
;; The error-buffer texts the four libcurls measured wrote alike.
(define measured-texts
  '("Recv failure: Connection reset by peer" "Received HTTP/0.9 when not allowed"
    "Header without colon" "Nul byte in header" "Empty reply from server"
    "Maximum file size exceeded"))

(define (scenarios o)
  ;; --- every shared scenario, whole
  (for-each
   (lambda (pair)
     (test-equal (string-append "shared: " (case-text (car pair)) ", whole, and the counts back at zero")
       (list (expanded (cadr pair)) zero-counts)
       (with-counts (case-answer o (car pair)))))
   shared-answers)

  ;; --- the varying scenarios, against this libcurl's row
  (set! varying-answered
        (map (lambda (a-case) (list a-case (case-answer o a-case) (native-counts))) varying-cases))
  (for-each
   (lambda (entry)
     (let ((want (and the-row (assoc (car entry) (row-answers the-row)))))
       (test-equal (string-append "varying: " (case-text (car entry)) ", as this libcurl's row says, and the counts back at zero")
         (list (if want (expanded (cadr want)) (list 'no-row-for version)) zero-counts)
         (list (cadr entry) (caddr entry)))))
   varying-answered)

  ;; --- the echoes, whose Host holds the origin's port
  (test-equal "echo: GET /raw/echo sends Host and libcurl's Accept, and no User-Agent unless asked"
    (list (echoed (raw-echo-body o '("Accept: */*\r\n"))) zero-counts)
    (with-counts (answer-of (lambda () (perform-transfer (request (url-of o 'raw "/raw/echo")))))))
  (let ((node-echo (string-append "GET /echo HTTP/1.1\nHost: " (host-of o 'http) "\nAccept: */*\n\n")))
    (test-equal "echo: GET /echo on the http face, as Node parsed it"
      (list (list 'response 200 'http/1.1
                  (list (list "Content-Length" (number->string (string-length node-echo)))
                        '("Connection" "keep-alive"))
                  node-echo)
            zero-counts)
      (with-counts (answer-of (lambda () (perform-transfer (request (url-of o 'http "/echo"))))))))

  ;; --- the setopt bindings, observed (ADR-0001's FFI test)
  ;; A string: USERAGENT's chars U+0080 to U+00FF arrive as single bytes,
  ;; never UTF-8's two.
  (let ((agent (chars (iota-from #x80 128))))
    (test-equal "USERAGENT: chars U+0080 to U+00FF arrive in /raw/echo as exactly those bytes, one each, between Host and Accept"
      (list (echoed (raw-echo-body o (list (string-append "User-Agent: " agent "\r\n") "Accept: */*\r\n")))
            zero-counts)
      (with-counts (answer-of (lambda () (perform-transfer (request (url-of o 'raw "/raw/echo")
                                                                    'user-agent agent)))))))
  ;; A long: TIMEOUT_MS. Without it, a stall never ends.
  (for-each
   (lambda (path)
     ;; Measured, 8 runs each: 301 to 304 ms natively, 303 to 386 under the
     ;; memory gate's Valgrind, the first the slowest. 600 catches a timeout
     ;; that arrived doubled.
     (test-equal (string-append "TIMEOUT_MS 300 against " path ": 28, no sooner than 300 ms and sooner than 600")
       (list (list 'refused 'perform-failed curle-operation-timedout) 'within zero-counts)
       (let* ((start (now-ms))
              (a (answer-of (lambda () (perform-transfer (request (url-of o 'raw path) 'timeout 300)))))
              (took (- (now-ms) start)))
         (list a (if (and (>= took 300) (< took 600)) 'within (list 'took took)) (native-counts)))))
   '("/raw/stall-after-head" "/raw/stall-before-head"))
  ;; A long: NOBODY, for head. /echo's Content-Length is the length of the
  ;; head Node read, so it shows the method sent was HEAD.
  (let ((head-echo (string-append "HEAD /echo HTTP/1.1\nHost: " (host-of o 'http) "\nAccept: */*\n\n")))
    (test-equal "NOBODY: head of /echo gets no body, and a Content-Length that counts a HEAD request's echo"
      (list (list 'response 200 'http/1.1
                  (list (list "Content-Length" (number->string (string-length head-echo)))
                        '("Connection" "keep-alive"))
                  "")
            zero-counts)
      (with-counts (answer-of (lambda () (perform-transfer (request (url-of o 'http "/echo") 'method 'head)))))))
  (test-equal "NOBODY: head of /status/200 gets its headers and no body"
    (list '(response 200 http/1.1 (("Content-Length" "11") ("Connection" "keep-alive")) "") zero-counts)
    (with-counts (answer-of (lambda () (perform-transfer (request (url-of o 'http "/status/200") 'method 'head))))))
  ;; An off_t: MAXFILESIZE_LARGE, at the body limit plus one, below a
  ;; Content-Length: refused before any body.
  (test-equal "MAXFILESIZE_LARGE below a Content-Length: a body limit of 9 against /status/200's 11 is 63, perform-failed, before any chunk"
    (list (list 'refused 'perform-failed curle-filesize-exceeded) "" zero-counts)
    (let* ((seen '())
           (a (answer-of (lambda ()
                           (perform-transfer
                            (request (url-of o 'http "/status/200") 'limit 9
                                     'hook (lambda (chunk) (set! seen (cons chunk seen)))))))))
      (list a (apply string-append (map latin-1 (reverse seen))) (native-counts))))

  ;; --- Latin-1, both ways
  (test-equal "a request header whose value holds every char U+0001 to U+00FF but CR and LF arrives in /raw/echo byte for byte, after Accept"
    (list (echoed (raw-echo-body o (list "Accept: */*\r\n"
                                         (string-append "X-Bytes: " every-byte-but-cr-lf "\r\n"))))
          zero-counts)
    (with-counts (answer-of (lambda () (perform-transfer (request (url-of o 'raw "/raw/echo")
                                                                  'headers (list (cons "X-Bytes" every-byte-but-cr-lf))))))))
  (test-equal "request headers keep their order and their repeats, and an empty value is sent as libcurl's Name; form writes it"
    (list (echoed (raw-echo-body o '("Accept: */*\r\n" "X-One: 1\r\n" "X-Dup: a\r\n" "X-Empty:\r\n"
                                     "X-Dup: b\r\n" "X-Two: two  words\r\n")))
          zero-counts)
    (with-counts (answer-of (lambda () (perform-transfer (request (url-of o 'raw "/raw/echo")
                                                                  'headers '(("X-One" . "1") ("X-Dup" . "a") ("X-Empty" . "")
                                                                             ("X-Dup" . "b") ("X-Two" . "two  words"))))))))

  (test-equal "a Host header is libcurl's exception to order: sent first, in place of libcurl's own, spelt Host, ahead of Accept and the headers before it"
    (list (echoed "GET /raw/echo HTTP/1.1\r\nHost: a.example\r\nAccept: */*\r\nX-A: 1\r\nX-B: 2\r\n\r\n")
          zero-counts)
    (with-counts (answer-of (lambda () (perform-transfer (request (url-of o 'raw "/raw/echo")
                                                                  'headers '(("X-A" . "1") ("hOsT" . "a.example") ("X-B" . "2"))))))))

  ;; --- the effective URL, libcurl's own form, read as UTF-8
  (test-equal "the effective URL: libcurl's parse of the request, dot segments gone; a redirect not followed keeps the request's; é in a path reads back as é"
    (list (url-of o 'http "/status/200")
          (url-of o 'http "/redirect/302?to=/status/200")
          (url-of o 'http "/caf\xE9;")
          zero-counts)
    (let ((effective (lambda (path)
                       (guard (e (#t (list 'raised (describe e))))
                         (transfer-response-effective-url (perform-transfer (request (url-of o 'http path))))))))
      (list (effective "/a/../status/200")
            (effective "/redirect/302?to=/status/200")
            (effective "/caf\xE9;")
            (native-counts))))

  ;; --- the last request's headers: a redirect followed, through the test
  ;; seam, makes two requests, and the first one's headers are not the
  ;; response's
  (test-equal "with FOLLOWLOCATION set through perform-transfer-with, a followed redirect answers the last request's status, headers and body, and its effective URL"
    (list (list '(response 200 http/1.1 (("Content-Length" "11") ("Connection" "keep-alive")) "status 200\n")
                (url-of o 'http "/status/200"))
          zero-counts)
    (list (guard (e (#t (list 'raised (describe e))))
            (let ((r (perform-transfer-with (request (url-of o 'http "/redirect/302?to=/status/200"))
                                            '(("FOLLOWLOCATION" . 1)))))
              (list (answer-of (lambda () r)) (transfer-response-effective-url r))))
          (native-counts)))

  ;; --- the URL, checked as the transfer runs
  (test-equal "a URL whose scheme is not http or https is refused as scheme-not-http, and one curl_url refuses with its code; nothing native is left"
    (list '(url-refused scheme-not-http #f) '(url-refused bad-port-number 4) zero-counts)
    (list (answer-of (lambda () (perform-transfer (request "file:///etc/passwd"))))
          (answer-of (lambda () (perform-transfer (request "http://127.0.0.1:99999/"))))
          (native-counts)))

  ;; --- re-entry: a continuation captured inside the callable, invoked once
  ;; the transfer has returned, is refused by the outermost extent's
  ;; before thunk, before anything resumes into C: the CURLU's, which
  ;; outlives every other native object the transfer makes
  (test-equal "re-entering a transfer through a continuation captured in CHUNK-HOOK raises from call-with-parsed-url, the outermost extent, the hook having run once, and the counts back at zero"
    (list '(assertion-violation call-with-parsed-url) 1 zero-counts)
    (let ((k #f) (runs 0))
      (let ((r (guard (e ((and (assertion-violation? e) (who-condition? e))
                          (list 'assertion-violation (condition-who e)))
                         (#t (list 'other (describe e))))
                 (perform-transfer
                  (request (url-of o 'http "/status/200")
                           'hook (lambda (chunk)
                                   (call/cc (lambda (c) (set! k c)))
                                   (set! runs (+ runs 1)))))
                 (if (= runs 1) (k #f) (list 'reentered runs)))))
        (list r runs (native-counts)))))

  ;; --- the counts while a transfer runs
  (test-equal "inside the callable, the transfer holds its easy handle, its CURLU, its header list, its error buffer and itself, one each, and the live-transfer table holds it; all zero after"
    (list '((block . 1) (easy . 1) (url . 1) (slist . 1) (curl-string . 0) (transfer . 1)) 1
          zero-counts 0)
    (let* ((inside #f)
           (live #f)
           (a (answer-of (lambda ()
                           (perform-transfer
                            (request (url-of o 'http "/status/200") 'headers '(("X-A" . "1"))
                                     'hook (lambda (chunk)
                                             (unless inside
                                               (set! inside (native-counts))
                                               (set! live (live-transfer-count))))))))))
      (list inside live (native-counts) (live-transfer-count))))

  ;; --- libcurl's texts, as the error carries them: strerror is
  ;; curl_easy_strerror's for the code, called here; the error buffer is
  ;; text, cut at its NUL, and where the four libcurls measured wrote the
  ;; same text, that text whole (build/verify/m2s2/measure/out-*.txt)
  (for-each
   (lambda (row)
     (test-equal (string-append "libcurl's texts for " (car row) ": strerror is curl_easy_strerror's for the code, and the error buffer "
                                (if (caddr row) (written (caddr row)) "a non-empty text, no U+0000 in it, shorter than CURL_ERROR_SIZE"))
       (list 'strerror-is-libcurls (or (caddr row) 'buffer-is-text))
       (texts-of (cadr row))))
   (let ((get (lambda (face path . options)
                (lambda () (perform-transfer (apply request (url-of o face path) options))))))
     (list (list "reset-after-pause" (get 'raw "/raw/reset-after-pause?ms=50") "Recv failure: Connection reset by peer")
           (list "reset-mid-body" (get 'raw "/raw/reset-mid-body") "Recv failure: Connection reset by peer")
           (list "bad-status-line" (get 'raw "/raw/bad-status-line") "Received HTTP/0.9 when not allowed")
           (list "http09" (get 'raw "/raw/http09") "Received HTTP/0.9 when not allowed")
           (list "header-no-colon" (get 'raw "/raw/header-no-colon") "Header without colon")
           (list "nul-in-header" (get 'raw "/raw/nul-in-header") "Nul byte in header")
           (list "close-before-response" (get 'raw "/raw/close-before-response") "Empty reply from server")
           (list "a body limit below a Content-Length" (get 'http "/status/200" 'limit 9) "Maximum file size exceeded")
           (list "bad-chunk-size" (get 'raw "/raw/bad-chunk-size") #f)
           (list "short-body" (get 'raw "/raw/short-body") #f)
           (list "stall-after-head, TIMEOUT_MS 300" (get 'raw "/raw/stall-after-head" 'timeout 300) #f)
           (list "a body limit the callable enforces" (get 'http "/status/200" 'limit 10) #f)
           (list "a raise in CHUNK-HOOK" (get 'http "/status/200" 'hook (lambda (chunk) (raise 'x))) #f))))

  ;; --- the body limit, at its edges: limit-*.txt's 20 cases. The hook sees
  ;; what the callable accepted.
  (for-each
   (lambda (row)
     (let ((face (car row)) (path (cadr row)) (limit (caddr row)) (want (cadddr row)) (accepted (list-ref row 4)))
       (test-equal (string-append "body limit " (number->string limit) " against " (symbol->string face) " " path
                                  ": " (written want) ", the callable having accepted " (written accepted))
         (list want accepted zero-counts)
         (let* ((seen '())
                (a (answer-of (lambda ()
                                (perform-transfer
                                 (request (url-of o face path) 'limit limit
                                          'hook (lambda (chunk) (set! seen (cons chunk seen)))))))))
           (list a (apply string-append (map latin-1 (reverse seen))) (native-counts))))))
   (let ((limit `(refused body-limit ,curle-write-error))
         (size `(refused perform-failed ,curle-filesize-exceeded))
         (status-200 `(response 200 http/1.1 (("Content-Length" "11") ("Connection" "keep-alive")) ,ok))
         (chunked `(response 200 http/1.1 (("Transfer-Encoding" "chunked") ("Connection" "keep-alive"))
                             "alpha\nbeta\ngamma\n")))
     `((http "/status/200" 10 ,limit "")
       (http "/status/200" 11 ,status-200 ,ok)
       (http "/status/200" 9 ,size "")
       (http "/status/200" 0 ,size "")
       (http "/chunked" 5 ,limit "")
       (http "/chunked" 6 ,limit "alpha\n")
       (http "/chunked" 16 ,limit "alpha\nbeta\n")
       (http "/chunked" 17 ,chunked "alpha\nbeta\ngamma\n")
       (http "/chunked" 0 ,limit "")
       (raw "/raw/content-length" 5 ,limit "")
       (raw "/raw/content-length" 6 (response 200 http/1.1 (("Content-Length" "6")) "hello\n") "hello\n")
       (raw "/raw/chunked" 3 ,limit "")
       (raw "/raw/chunked" 5 ,limit "hello")
       (raw "/raw/chunked" 6 (response 200 http/1.1 (("Transfer-Encoding" "chunked")) "hello\n") "hello\n")
       (raw "/raw/close-delimited" 3 ,limit "")
       (raw "/raw/close-delimited" 5 ,limit "")
       (raw "/raw/close-delimited" 6 (response 200 http/1.1 (("Connection" "close")) "hello\n") "hello\n")
       (raw "/raw/chunked-tiny" 2 ,limit "he")
       (raw "/raw/http10" 5 ,limit "")
       (raw "/raw/drip?bytes=5&gap=10" 3 ,size ""))))

  ;; --- a raise inside the callable
  (let ((thrown (list 'thrown-inside-the-callable)))
    (test-equal "a raise inside the callable, through CHUNK-HOOK: callback-raised, 23, recording the very object raised, and the counts back at zero"
      (list (list 'callback-raised curle-write-error 'the-object) zero-counts)
      (let ((r (guard (e ((curl-transfer-error? e)
                          (list (curl-transfer-error-reason e) (curl-transfer-error-code e)
                                (if (eq? (curl-transfer-error-recorded e) thrown)
                                    'the-object
                                    (curl-transfer-error-recorded e))))
                         (#t (list 'raised (describe e))))
                 (perform-transfer (request (url-of o 'http "/status/200")
                                            'hook (lambda (chunk) (raise thrown))))
                 'no-raise)))
        (list r (native-counts)))))
  ;; --- the user agent another thread changes while transfers run
  (test-equal "a user agent another thread flips between c and CR while 300 transfers run: each is refused as line-break, or sends the agent whole, never the CR, both seen; the counts back at zero"
    (list '() '(refused whole) zero-counts)
    (let* ((agent (string-copy "abcdef"))
           (r (make-transfer-request (url-of o 'raw "/raw/echo") 'get '() agent default-timeout #f #f))
           (clean (echoed (raw-echo-body o '("User-Agent: abcdef\r\n" "Accept: */*\r\n"))))
           (stop #f)
           (flip (lambda ()
                   (let loop ((i 0))
                     (when (< i 1000000)
                       (string-set! agent 2 #\return)
                       (string-set! agent 2 #\c)
                       (loop (+ i 1))))))
           ;; As the header race's flipper: 1000000 flips between sleeps of
           ;; no time, once in each state.
           (flipper (fork-thread (lambda ()
                                   (let loop ()
                                     (unless stop
                                       (flip)
                                       (pause-ms 0)
                                       (flip)
                                       (string-set! agent 2 #\return)
                                       (pause-ms 0)
                                       (loop)))))))
      (dynamic-wind
        (lambda () #f)
        (lambda ()
          (let loop ((i 0) (odd '()) (seen '()))
            (if (= i 300)
                (list (reverse odd) (filter (lambda (k) (memq k seen)) '(refused whole)) (native-counts))
                (let* ((a (answer-of (lambda () (perform-transfer r))))
                       (k (cond ((equal? a clean) 'whole)
                                ((equal? a '(request-refused user-agent line-break)) 'refused)
                                (else #f))))
                  (loop (+ i 1)
                        (if k odd (cons a odd))
                        (if (and k (not (memq k seen))) (cons k seen) seen))))))
        (lambda () (set! stop #t) (thread-join flipper)))))

  ;; --- a mutex held across an asynchronous escape: Chez's with-mutex is a
  ;; dynamic-wind whose before thunk takes the mutex, so an engine that runs
  ;; out between the take and the wind leaves it held, with no after thunk
  ;; to release it, and every other thread then blocks on it. Each sweep
  ;; runs out at every tick of a call that takes one: the live-transfer
  ;; table's, the option cache's, and, through a seam setting refused after
  ;; a known one, the lookup's.
  (test-equal "an engine that runs out at every tick of live-transfer-count, of cached-option-names, and of a seam call refused as unknown-option after MAXREDIRS, each abandoned, until one completes: each completes, and another thread then takes every lock"
    '((completed expired-first) (completed expired-first) (completed expired-first) other-thread-ran)
    (let* ((refused (request "http://127.0.0.1:1/"))
           (sweeps (map (lambda (thunk)
                          (let ((r (engine-sweep thunk 1)))
                            (if (and (eq? (car r) 'completed) (> (cadr r) 0)) '(completed expired-first) r)))
                        (list live-transfer-count
                              cached-option-names
                              (lambda () (answer-of (lambda () (perform-transfer-with refused '(("MAXREDIRS" . 1) ("NO_SUCH_OPTION" . 1))))))))))
      (append sweeps (list (other-thread-can every-lock)))))

  ;; --- asynchronous escapes: an engine's fuel, or a timer, running out
  ;; anywhere in a transfer, perform included (ADR-0013, amended
  ;; 2026-10-23). An escape from inside perform is allowed, and counted:
  ;; its easy handle is never cleaned up, so it stays counted as easy, and
  ;; libcurl's connection leaks, with its connection's sockets. Under the memory gate Valgrind would see
  ;; that leak in this process, so the sweeps and the timers run in a child,
  ;; tests/transfer-escapes.sps, which prints each case and the counts it
  ;; left. These tests judge what it printed.
  (test-equal "the escape child runs to its end within its bound: exit 0, each line a case of a known shape, (done) last, and nothing on stderr; else every test of it names what went wrong"
    'ran-to-its-end
    (or escape-problem 'ran-to-its-end))
  (test-equal "run-problem, the judge of the child's run: a kill at the bound is child-timed-out, an end before (done) child-output-ended-early, an exit child-exited, a datum of no known shape named, and a whole run none"
    '((child-timed-out 180) (child-output-ended-early (timer 300 escaped x 0)) (child-output-ended-early nothing)
      (child-exited 1 "boom") (child-printed-an-unknown-shape (sweep "whole" 1 expired x))
      (child-wrote-on-stderr "w") #f)
    (map (lambda (run) (run-problem run 180))
         '((137 () "")
           (0 ((sweep "whole" 1 expired x 0) (timer 300 escaped x 0)) "")
           (0 () "")
           (1 ((done)) "boom")
           (0 ((sweep "whole" 1 expired x) (done)) "")
           (0 ((done)) "w")
           (0 ((sweep "whole" 1 expired x 0) (timer 300 escaped x 0) (interrupt (3) a x) (after 0 l x) (done)) ""))))
  ;; The refused transfer runs no callback, so its escapes inside perform
  ;; are the ones around the call, between the mark and curl_easy_perform:
  ;; measured, two, and three in one run of perform in a critical section.
  ;; The whole transfer escaping inside more than twice as often as the
  ;; refused one, plus one, shows escapes from write-body, inside the call:
  ;; measured, 32.
  (test-equal "a transfer in an engine that runs out at every tick, in the child: each engine completed, ran out outside perform, or escaped inside it, each with its counts; some ran out outside and some escaped inside, more than twice as often as the refused transfer below, plus one, so from write-body; one completed, the last, whole; and the fuels ran 1, 2, 3 on"
    '(() outside-seen inside-seen 1 (completed (response 200 17)) #t more-inside-than-refused)
    (or escape-problem
        (append (sweep-verdict "whole")
                (list (if (> (inside-count "whole") (* 2 (+ (inside-count "refused") 1)))
                          'more-inside-than-refused
                          (list 'inside (inside-count "whole") 'refused (inside-count "refused")))))))
  (test-equal "a transfer refused at connect, to a closed port, in an engine that runs out at every tick, in the child: the same, its one completion the refusal, 7"
    '(() outside-seen inside-seen 1 (completed (refused perform-failed 7)) #t)
    (sweep-verdict "refused"))
  (test-equal "a timer-interrupt-handler that escapes through a continuation, armed 300 to 1700 ticks into a 40-chunk transfer, in the child: each case completed whole, escaped outside perform, or escaped inside it, each with its counts, and one escaped inside at least"
    '(() inside-seen whole)
    (timer-verdict))
  (test-equal "interrupts are not put off while perform runs: a timer handler armed once 3 bytes of a 20-byte, 1 s drip have come runs, once, before the last byte, and the transfer then completes whole, with every count zero"
    (list 'once-before-the-end '(response 200 20) zero-counts)
    (interrupt-verdict))
  (test-equal "once every case has run, in the child: no live transfer, no mutex held, and the counts exactly one easy per escape inside perform"
    '(0 other-thread-ran escapes-counted)
    (after-verdict))
  ;; An escape inside perform leaks its connection's sockets: how many is
  ;; libcurl's, one on 8.20.0, nearer three on 7.85.0. Every other case
  ;; leaves none.
  (unless (file-directory? "/proc/self/fd") (test-skip 1))
  (test-equal "in the child, each case that completed, or ran out outside perform, left no new socket, and an escape inside perform left its connection's sockets (Linux, from /proc; skipped elsewhere)"
    '(() inside-left-sockets)
    (sockets-verdict))

  ;; --- control leaving the callable other than by its return: an outer
  ;; continuation invoked from CHUNK-HOOK, and an earlier chunk's from a
  ;; later chunk. Either would abandon curl_easy_perform's C frames, and
  ;; libcurl's connection: so each is refused, as a raise, in the callable.
  (let* ((before (sockets-open))
         (escaped (call/cc
                   (lambda (k)
                     (refused-recording
                      (lambda ()
                        (perform-transfer (request (url-of o 'http "/status/200")
                                                   'hook (lambda (chunk) (k 'escaped)))))))))
         (escaped-counts (native-counts))
         (calls 0)
         (stale (let ((kept #f))
                  (refused-recording
                   (lambda ()
                     (perform-transfer
                      (request (url-of o 'raw "/raw/drip?bytes=3&gap=20")
                               'hook (lambda (chunk)
                                       (set! calls (+ calls 1))
                                       (if kept
                                           (let ((k kept)) (set! kept #f) (k 'again))
                                           (call/cc (lambda (c) (set! kept c)))))))))))
         (stale-counts (native-counts))
         (after (sockets-open)))
    (test-equal "CHUNK-HOOK escaping through a continuation captured outside the transfer is refused in the callable: callback-raised, 23, recording write-body's refusal of an escape, and the counts back at zero"
      (list '(refused callback-raised 23 (write-body (escaped))) zero-counts)
      (list escaped escaped-counts))
    (test-equal "CHUNK-HOOK invoking an earlier chunk's continuation from a later chunk is refused the same way, the hook called twice, and the counts back at zero"
      (list '(refused callback-raised 23 (write-body (escaped))) 2 zero-counts)
      (list stale calls stale-counts))
    (unless before (test-skip 1))
    (test-equal "after both, this process holds as many sockets as before: libcurl closed each connection (Linux, from /proc; skipped elsewhere)"
      'as-many
      (if (and before after (= before after)) 'as-many (list 'before before 'after after))))

  (test-equal "the error carries libcurl's texts: strerror for 23, and the error buffer's, both strings; no recorded object for the body limit"
    '(body-limit 23 #t #t no-recorded)
    (guard (e ((curl-transfer-error? e)
               (list (curl-transfer-error-reason e) (curl-transfer-error-code e)
                     (string? (curl-transfer-error-strerror e))
                     (string? (curl-transfer-error-error-buffer e))
                     (if (eq? (curl-transfer-error-recorded e) #f) 'no-recorded 'recorded)))
              (#t (list 'raised (describe e))))
      (perform-transfer (request (url-of o 'http "/status/200") 'limit 10))
      'no-raise))

  ;; --- options through perform-transfer-with
  (test-equal "an option the loaded libcurl does not know raises unknown-option, naming it, with no code, and the counts back at zero"
    (list '(unknown-option #f "NO_SUCH_OPTION") zero-counts)
    (list (guard (e ((curl-transfer-error? e)
                     (list (curl-transfer-error-reason e) (curl-transfer-error-code e)
                           (curl-transfer-error-option e)))
                    (#t (list 'raised (describe e))))
            (perform-transfer-with (request (url-of o 'http "/status/200")) '(("NO_SUCH_OPTION" . 1)))
            'no-raise)
          (native-counts)))
  (test-equal "an option libcurl refuses raises setopt-failed, naming it, with its code, through each integer binding: MAXREDIRS -2 through the long one and MAX_RECV_SPEED_LARGE -1 through the off_t one are 43, never taken zero-extended, as 4294967294 and 4294967295 would be; the counts back at zero"
    (list (list 'setopt-failed curle-bad-function-argument "MAXREDIRS")
          (list 'setopt-failed curle-bad-function-argument "MAX_RECV_SPEED_LARGE")
          zero-counts)
    (append (map (lambda (option)
                   (guard (e ((curl-transfer-error? e)
                              (list (curl-transfer-error-reason e) (curl-transfer-error-code e)
                                    (curl-transfer-error-option e)))
                             (#t (list 'raised (describe e))))
                     (perform-transfer-with (request (url-of o 'http "/status/200")) (list option))
                     'no-raise))
                 (list '("MAXREDIRS" . -2) '("MAX_RECV_SPEED_LARGE" . -1)))
            (list (native-counts))))

  ;; --- the redirect pin, observed: without REDIR_PROTOCOLS_STR, libcurl
  ;; would follow to FTP, and answer 7, connection refused
  (test-equal "REDIR_PROTOCOLS_STR, observed: FOLLOWLOCATION through the test seam, to ftp://127.0.0.1:1/, a protocol this libcurl lists, is refused as 1, CURLE_UNSUPPORTED_PROTOCOL, never tried; the counts back at zero"
    (list 'ftp-listed (list 'refused 'perform-failed curle-unsupported-protocol) zero-counts)
    (list (if (member "ftp" (loaded-protocols)) 'ftp-listed (list 'no-ftp-in (loaded-protocols)))
          (answer-of (lambda ()
                       (perform-transfer-with (request (url-of o 'http "/redirect/302?to=ftp://127.0.0.1:1/"))
                                              '(("FOLLOWLOCATION" . 1)))))
          (native-counts)))

  ;; --- the option cache keeps its own copy of a name
  (test-equal "the option cache keeps a copy of each name: a caller's name, changed after its transfer, leaves the cache's key as it was"
    '(kept not-taken)
    (let ((name (string-copy "LOW_SPEED_TIME")))
      (perform-transfer-with (request (url-of o 'http "/status/200")) (list (cons name 30)))
      (string-set! name 0 #\X)
      (let ((keys (cached-option-names)))
        (list (if (member "LOW_SPEED_TIME" keys) 'kept 'lost)
              (if (member "XOW_SPEED_TIME" keys) 'taken 'not-taken)))))

  ;; --- a header value another thread changes while transfers run
  (test-equal "a header value another thread flips between c and CR while 300 transfers run: each is refused as line-break, or sends the value whole, never the CR, both seen; the counts back at zero"
    (list '() '(refused whole) zero-counts)
    (let* ((value (string-copy "abcdef"))
           (r (make-transfer-request (url-of o 'raw "/raw/echo") 'get (list (cons "X-Race" value))
                                     #f default-timeout #f #f))
           (clean (echoed (raw-echo-body o '("Accept: */*\r\n" "X-Race: abcdef\r\n"))))
           (stop #f)
           (flip (lambda ()
                   (let loop ((i 0))
                     (when (< i 1000000)
                       (string-set! value 2 #\return)
                       (string-set! value 2 #\c)
                       (loop (+ i 1))))))
           ;; It flips 1000000 times as fast as it can, then yields once in
           ;; each state, a sleep of no time: natively it spins most of the
           ;; time, and under Valgrind, which runs one thread at a time, it
           ;; holds the transfers up little. Measured against the snapshot
           ;; checked and the original sent: 21 of 300 transfers injected.
           (flipper (fork-thread (lambda ()
                                   (let loop ()
                                     (unless stop
                                       (flip)
                                       (pause-ms 0)
                                       (flip)
                                       (string-set! value 2 #\return)
                                       (pause-ms 0)
                                       (loop)))))))
      (dynamic-wind
        (lambda () #f)
        (lambda ()
          (let loop ((i 0) (odd '()) (seen '()))
            (if (= i 300)
                (list (reverse odd) (filter (lambda (k) (memq k seen)) '(refused whole)) (native-counts))
                (let* ((a (answer-of (lambda () (perform-transfer r))))
                       (k (cond ((equal? a clean) 'whole)
                                ((equal? a '(request-refused header-value line-break)) 'refused)
                                (else #f))))
                  (loop (+ i 1)
                        (if k odd (cons a odd))
                        (if (and k (not (memq k seen))) (cons k seen) seen))))))
        (lambda () (set! stop #t) (thread-join flipper)))))

  ;; --- two threads, each with its own transfer, at once. Positive evidence
  ;; that they overlapped: each one's first chunk came before either ended.
  (test-equal "two threads, each with its own transfer, at once: both started before either ended, both bodies whole, and the counts back at zero"
    (list 'overlapped
          '((response 200 http/1.1 (("Content-Length" "11")) "hello world")
            (response 200 http/1.1 (("Content-Length" "11")) "hello world"))
          zero-counts)
    (let* ((lock (make-mutex))
           (events '())
           (note! (lambda (event) (with-mutex lock (set! events (cons event events)))))
           (results (make-vector 2 'never-ran))
           (run (lambda (i)
                  (lambda ()
                    (let ((first? #t))
                      (vector-set! results i
                                   (answer-of
                                    (lambda ()
                                      (perform-transfer
                                       (request (url-of o 'raw "/raw/pause-mid-body?ms=600")
                                                'hook (lambda (chunk)
                                                        (when first? (set! first? #f) (note! (list i 'started)))))))))
                      (note! (list i 'ended))))))
           (threads (list (fork-thread (run 0)) (fork-thread (run 1)))))
      (for-each thread-join threads)
      (let* ((order (reverse events))
             (index (lambda (event) (let loop ((rest order) (n 0))
                                      (cond ((null? rest) #f)
                                            ((equal? (car rest) event) n)
                                            (else (loop (cdr rest) (+ n 1)))))))
             (s0 (index '(0 started))) (s1 (index '(1 started)))
             (e0 (index '(0 ended))) (e1 (index '(1 ended))))
        (list (if (and s0 s1 e0 e1 (< (max s0 s1) (min e0 e1))) 'overlapped (list 'order order))
              (vector->list results)
              (native-counts)))))

  ;; --- the lock: a drip beside a thread that collects every 2 ms, so the
  ;; collector runs between the callable's calls. Without lock-object it
  ;; moves the callable's code, and libcurl calls where it was (plan,
  ;; section 5.1.1).
  (test-equal "the lock: a 50-byte drip, 10 ms apart, beside a thread that collects every 2 ms: the whole body, collections between the first chunk and the last, and the counts back at zero"
    (list (list 'response 200 'http/1.1 '(("Content-Length" "50"))
                "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwx")
          'collected-between zero-counts)
    (let* ((stop #f)
           (collected 0)
           (collector (fork-thread
                       (lambda ()
                         (let loop ()
                           (unless stop
                             (make-bytevector 20000 1)
                             (collect-rendezvous)
                             (set! collected (+ collected 1))
                             (pause-ms 2)
                             (loop))))))
           (at-first #f)
           (at-last #f)
           (a (answer-of (lambda ()
                           (perform-transfer
                            (request (url-of o 'raw "/raw/drip?bytes=50&gap=10")
                                     'hook (lambda (chunk)
                                             (unless at-first (set! at-first collected))
                                             (set! at-last collected))))))))
      (set! stop #t)
      (thread-join collector)
      (list a
            (if (and at-first at-last (> at-last at-first)) 'collected-between (list 'collections at-first at-last))
            (native-counts)))))

(define scenarios-outcome
  (guard (e (#t (list 'raised (describe e))))
    (call-with-origin (lambda (o) (scenarios o) 'done))))

(test-equal "the scenarios' origin starts, serves them all, and stops"
  'done
  scenarios-outcome)

(test-equal "once every transfer has ended, the live-transfer table is empty, and the transfer count zero"
  '(0 0)
  (list (live-transfer-count) (cdr (assq 'transfer (native-counts)))))

;; No row: say so on the error port, with the row to add.
(when (and (string? version) (not the-row))
  (let ((err (current-error-port)))
    (put-string err
      (string-append
       "test-transfer: " (if (null? matches) "no row" "more than one row") " of " verdicts-file
       " is for libcurl " version ".\n"
       "test-transfer: if it is one to support, review its answers, and add this row,\n"
       "test-transfer: with `where` saying where it runs (M2 plan, section 5.3):\n\n"
       (row-text version (map (lambda (entry) (list (car entry) (cadr entry))) varying-answered)) "\n"))
    (flush-output-port err)))

;; --- the verdict file ----------------------------------------------------------------------

(test-equal "tests/known-transfer-verdicts.sexp reads as data"
  'read
  (if (eq? (car file-result) 'data) 'read file-result))

(test-equal "it holds rows for 7.85.0, 8.5.0 and 8.20.0, the libcurls the lanes run"
  '("7.85.0" "8.5.0" "8.20.0")
  (map (lambda (row) (if (eq? (row-problem row) 'ok) (row-version row) row)) rows))

(let loop ((i 1) (rest rows))
  (unless (null? rest)
    (let ((row (car rest)))
      (test-equal (string-append "row " (number->string i)
                                 " is (libcurl (where S) (version S) (answers (CASE ANSWER) ...))")
        'ok
        (row-problem row))
      (test-equal (string-append "row " (number->string i) " answers exactly the varying cases, each once")
        'exactly
        (if (and (eq? (row-problem row) 'ok)
                 (same-cases? (map car (row-answers row)) varying-cases))
            'exactly
            (if (eq? (row-problem row) 'ok) (map car (row-answers row)) row))))
    (loop (+ i 1) (cdr rest))))

(test-equal "each varying case has different answers in two rows at least: one all rows answer alike is a shared answer"
  '()
  (filter (lambda (a-case)
            (let ((answers (map (lambda (row) (let ((p (assoc a-case (row-answers row)))) (and p (cadr p))))
                                (filter (lambda (row) (eq? (row-problem row) 'ok)) rows))))
              (< (length (fold-left (lambda (seen a) (if (member a seen) seen (cons a seen))) '() answers)) 2)))
          varying-cases))

(test-equal "no two rows share a version"
  'distinct
  (let ((versions (map (lambda (row) (if (eq? (row-problem row) 'ok) (row-version row) row)) rows)))
    (if (distinct? versions) 'distinct versions)))

(test-equal "the varying cases are none of the shared ones, and each once"
  '(() distinct)
  (list (filter (lambda (a-case) (assoc a-case shared-answers)) varying-cases)
        (if (distinct? (append varying-cases (map car shared-answers))) 'distinct 'repeated)))

(define made-up-row
  `(libcurl (where "made up") (version "9.9.9")
            (answers ((get raw "/raw/x") (refused perform-failed 7)))))

(test-equal "the matcher: a version with one row is one, with none is none, with two is several; a malformed row is never a match"
  '(one none several none)
  (list (version-verdict (list made-up-row) "9.9.9")
        (version-verdict (list made-up-row) "9.9.8")
        (version-verdict (list made-up-row made-up-row) "9.9.9")
        (version-verdict (list '(libcurl (version "9.9.9"))) "9.9.9")))

(test-equal "the shape: a row missing where, an answer with a reason no transfer error has, or a code that is no number, or headers that are no pairs, is refused"
  '(rejected rejected rejected rejected ok ok)
  (map (lambda (row) (if (eq? (row-problem row) 'ok) 'ok 'rejected))
       (list '(libcurl (version "9.9.9") (answers ((get raw "/raw/x") (refused perform-failed 7))))
             '(libcurl (where "w") (version "9.9.9") (answers ((get raw "/raw/x") (refused timed-out 28))))
             '(libcurl (where "w") (version "9.9.9") (answers ((get raw "/raw/x") (refused perform-failed "28"))))
             '(libcurl (where "w") (version "9.9.9") (answers ((get raw "/raw/x") (response 200 http/1.1 (("A" . "b")) ""))))
             '(libcurl (where "w") (version "9.9.9") (answers ((get raw "/raw/x") (response 200 http/1.1 (numbered "X-H-" 3 "v") ""))))
             made-up-row)))

(test-equal "the numbered form: compressed writes a long run of X-H- headers so, expanded writes it out, and a short list or another run is left alone"
  (list '(response 200 http/1.1 (numbered "X-H-" 60 "v") "")
        (list 'response 200 'http/1.1 (numbered "X-H-" 60 "v") "")
        '(response 200 http/1.1 (("X-H-1" "v") ("X-H-2" "v")) "")
        (list 'response 200 'http/1.1 (cons '("X-H-0" "v") (numbered "X-H-" 59 "v")) ""))
  (list (compressed (list 'response 200 'http/1.1 (numbered "X-H-" 60 "v") ""))
        (expanded '(response 200 http/1.1 (numbered "X-H-" 60 "v") ""))
        (compressed '(response 200 http/1.1 (("X-H-1" "v") ("X-H-2" "v")) ""))
        (compressed (list 'response 200 'http/1.1 (cons '("X-H-0" "v") (numbered "X-H-" 59 "v")) ""))))

(test-equal "the printed row reads back as a well-formed row for this version, answering exactly the varying cases"
  'ok
  (guard (e (#t (list 'raised (describe e))))
    (let ((row (read (open-string-input-port
                      (row-text "9.9.9" (map (lambda (a-case) (list a-case '(refused perform-failed 7)))
                                             varying-cases))))))
      (cond ((not (eq? (row-problem row) 'ok)) (row-problem row))
            ((not (same-cases? (map car (row-answers row)) varying-cases)) (row-answers row))
            (else 'ok)))))

;; --- the order the extents nest in, read from transfer.sls as data ------------------------
;; libcurl documents that the CURLU, the header list and the error buffer must
;; outlive the easy handle that uses them, yet 8.20.0's curl_easy_cleanup
;; reads none of them: freed first, each passed every test above, under
;; Valgrind too (the mutation log). So the nesting is read: each extent of
;; perform-transfer-with stands once, inside exactly the ones before it.

;; extent-heads : (Listof Symbol)
;; perform-transfer-with's extents, outermost first.
(define extent-heads
  '(call-with-parsed-url call-with-sink call-with-error-buffer call-with-header-list call-with-easy))

;; extents-within : Any (Listof Symbol) -> (Listof (Pairof Symbol (Listof Symbol)))
;; Each form in X headed by one of extent-heads, with the heads of those
;; around it, outermost first, ENCLOSING among them.
(define (extents-within x enclosing)
  (cond ((pair? x)
         (let ((inner (if (memq (car x) extent-heads) (append enclosing (list (car x))) enclosing)))
           (append (if (memq (car x) extent-heads) (list (cons (car x) enclosing)) '())
                   (extents-within (car x) enclosing)
                   (let loop ((rest (cdr x)) (found '()))
                     (cond ((pair? rest) (loop (cdr rest) (append found (extents-within (car rest) inner))))
                           (else found))))))
        (else '())))

;; transfer-extents : Any
;; The extents of transfer.sls's perform-transfer-with, or what went wrong.
(define transfer-extents
  (guard (e (#t (list 'unreadable (describe e))))
    (let* ((form (call-with-port (open-file-input-port transfer-source (file-options) (buffer-mode block)
                                                       (make-transcoder (utf-8-codec)))
                   read))
           (definition (find (lambda (f) (and (pair? f) (eq? (car f) 'define) (pair? (cdr f))
                                              (pair? (cadr f)) (eq? (car (cadr f)) 'perform-transfer-with)))
                             (cddddr form))))
      (if definition (extents-within (cddr definition) '()) '(no-definition)))))

(test-equal "perform-transfer-with's extents each stand once, each inside exactly those before it: the CURLU, the key, the error buffer, the header list, then the easy handle, innermost, so cleaned up first"
  '((call-with-parsed-url) (call-with-sink call-with-parsed-url)
    (call-with-error-buffer call-with-parsed-url call-with-sink)
    (call-with-header-list call-with-parsed-url call-with-sink call-with-error-buffer)
    (call-with-easy call-with-parsed-url call-with-sink call-with-error-buffer call-with-header-list))
  transfer-extents)

(test-equal "the extent reader: a head is found at any depth, a form's head among them, with the heads around it, and a head in a sibling is not around another"
  '((call-with-sink) (call-with-easy call-with-sink) (call-with-easy call-with-sink)
    (call-with-error-buffer) (call-with-easy))
  (extents-within '(begin (call-with-sink (lambda (k) (x (call-with-easy f)) (call-with-easy g)))
                          (call-with-error-buffer h)
                          ((call-with-easy (lambda (e) e)) 1))
                  '()))

(test-equal "the loaded libcurl's version has exactly one row in tests/known-transfer-verdicts.sexp"
  (list version)
  (map row-version matches))

(test-end "transfer")

(exit (suite-exit-status runner))
