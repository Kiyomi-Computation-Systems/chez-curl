#!r6rs
;;; The suite for (curl private transfer): a request, submitted to an
;;; engine and awaited, against the test origin's plaintext faces (M2 plan,
;;; section 5; M3 plan, sections 3.6 and 5.2). Every transfer runs on the
;;; suite's one engine, made near the top.
;;;
;;; Every scenario is asserted whole: the status, the HTTP version, every
;;; header in libcurl's order, and the body, or the &curl-transfer-error's
;;; reason and CURLcode, with the native counts after it, which must be the
;;; engine's multi handle alone, refusals included; once the engine has
;;; stopped, at the end, all zero. curl's verdicts vary by version (plan,
;;; section 5.1.1), so, as test-url does:
;;;
;;;   - shared answers hold what every recorded libcurl answers, 7.85.0,
;;;     8.5.0 (OpenSSL and GnuTLS) and 8.20.0, measured through C, and
;;;     Apple's 8.7.1, through this suite on the Mac;
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
;;;     plus one, and what the callable accepted, read from the chunk log
;;;     write-body keeps on the token (M3 plan, section 3.6);
;;;   - a raise inside the callable, planted as data by a request's fault,
;;;     recorded by the transfer;
;;;   - two threads submitting to the one engine at once, with positive
;;;     evidence their transfers were live together;
;;;   - the lock: a drip beside a thread that collects every 2 ms;
;;;   - the option table and its bindings, written out here, since on
;;;     x86-64 a long sent through the off_t binding arrives all the same;
;;;     the field table and the record's fields, written out too;
;;;   - the test seam, curl-engine-submit-with, held to ADR-0009's rules,
;;;     narrowed (amended 2026-10-23): long, enumerated-value and off_t
;;;     options alone, none the transfer owns, compared by id, the TLS
;;;     fields' four and the CA file's twins written out (amended
;;;     2026-10-24), each refused at submit; through it, the last request's
;;;     headers after a redirect followed, and the redirect pin observed;
;;;   - the request's snapshot, taken at submit: a request changed after it
;;;     was made is refused there, in prepare-transfer's order, and a value
;;;     another thread changes is sent whole or refused, never otherwise;
;;;   - a mutex held across an asynchronous escape: sweeps of the calls
;;;     that take transfer.sls's mutexes, and of a refused submit;
;;;   - framing headers, Content-Length and Transfer-Encoding, refused;
;;;   - hermetic: no proxy variable is set;
;;;   - the native objects' lifetimes: the counts while a transfer is live,
;;;     and, read from transfer.sls as data, set-transfer-options!' order,
;;;     start-transfer!'s making order against free-transfer!'s freeing
;;;     order, and prepare-transfer's checks, since libcurl 8.20.0's cleanup
;;;     reads none of the objects a wrong order would free first.
;;;
;;; M2's escape child, tests/transfer-escapes.sps, its performing mark and
;;; the chunk hook's refusals retired with perform-transfer: the engine's
;;; thread runs no caller code, sets no timer and gets no Ctrl-C (ADR-0013,
;;; amended 2026-10-25).
;;;
;;; Importing (curl) runs the load before this suite's first line, on this
;;; thread: a first reference from a second thread during the load would
;;; raise cyclic dependency (ADR-0002, amended). The suite's top level also
;;; reaches (curl private transfer), then makes its engine, before any
;;; other thread is forked. Every expected value is one the code under test
;;; cannot produce by failing: SRFI-64 makes #f of a raise in the actual
;;; expression, so none is #f.
(import (rnrs)
        (srfi :64)
        (rnrs mutable-strings)
        (rnrs mutable-pairs)
        (only (chezscheme) fork-thread thread-join make-mutex with-mutex collect-rendezvous
              sleep make-time current-time time-second time-nanosecond getenv get-thread-id)
        (curl-testing)
        (curl)
        (curl private engine)
        (curl private transfer)
        (curl private conditions)
        (curl private constants)
        (curl private counters)
        (only (curl private native) curl-easy-setopt-long curl-easy-setopt-off-t
              curl-easy-setopt-pointer call-with-c-string curl-slist-append curl-slist-free-all
              curl-easy-strerror loaded-protocols curl-easy-option)
        (only (chezscheme) make-engine)
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
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0)))

;; running-counts : (Listof (Pairof Symbol Natural))
;; The counts while the suite's engine runs and no transfer is live: its
;; multi handle and its slot, a counted block it holds while it runs, and
;; nothing else.
(define running-counts
  '((block . 1) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 1)))

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

;; The suite's one engine, made here, on this thread, once the load and
;; (curl private transfer)'s body have run, and before any other thread is
;; forked. Every transfer below runs on it. A failure to make it is the
;; first test's, below.
(define engine
  (guard (e (#t (list 'raised (describe e))))
    (make-curl-engine)))

(define engine-made? (curl-engine? engine))

;; engine-thread-id : (U Integer #f)
;; The get-thread-id of the engine's thread, where every chunk must run.
(define engine-thread-id (and engine-made? (curl-engine-thread engine)))

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
;; user agent, default-timeout, no body limit, libcurl's system store,
;; verification on, and no fault. OPTIONS are keyword and value: method,
;; headers, user-agent, timeout, limit, ca-file, verify, fault.
(define (request target . options)
  (let ((given (lambda (key default)
                 (let ((at (memq key options))) (if at (cadr at) default)))))
    (make-transfer-request target (given 'method 'get) (given 'headers '())
                           (given 'user-agent #f) (given 'timeout default-timeout)
                           (given 'limit #f) (given 'ca-file #f) (given 'verify #t)
                           (given 'fault #f))))

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

;; perform-with : Request (Listof (Pairof String Integer)) -> Response
;; perform's, through the test seam, curl-engine-submit-with, with OPTIONS.
(define (perform-with r options) (await-token (curl-engine-submit-with engine r options)))

;; settled : Any -> Any
;; X, as it is; a token is cancelled first, and awaited, whatever it ended
;; with, so that a submit a check expected refused leaves nothing running.
(define (settled x)
  (when (curl-token? x)
    (curl-token-cancel x)
    (guard (e (#t #f)) (await-token x)))
  x)

;; log-of : Token -> (U (Listof (List Positive-Integer Symbol)) (List 'off-the-engine Any))
;; TOKEN's chunk log, write-body's, each entry's length and verdict, once
;; every entry ran on the suite's engine's thread; else (off-the-engine
;; LOG), the log whole.
(define (log-of token)
  (let ((chunks (curl-token-chunks token)))
    (if (for-all (lambda (c) (and (list? c) (= (length c) 3) (eqv? (cadr c) engine-thread-id))) chunks)
        (map (lambda (c) (list (car c) (caddr c))) chunks)
        (list 'off-the-engine chunks))))

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

;; submitted : (-> Token) -> Answer
;; What THUNK's submit raised, as answer-of names it: a refusal at submit,
;; on this thread, before anything is queued. When it raised nothing,
;; (not-refused-at-submit ANSWER), ANSWER what its token, cancelled, then
;; answered.
(define (submitted thunk)
  (let ((outcome (guard (e (#t (cons 'raised-at-submit e))) (cons 'token (thunk)))))
    (if (eq? (car outcome) 'raised-at-submit)
        (answer-of (lambda () (raise (cdr outcome))))
        (let ((token (settled (cdr outcome))))
          (list 'not-refused-at-submit
                (if (curl-token? token) (answer-of (lambda () (await-token token))) token))))))

;; run : Request -> (List Answer Any)
;; What R answers through the suite's engine, as answer-of names it, and its
;; token's log, by log-of; refused-at-submit for the log of a submit that
;; raised.
(define (run r)
  (let ((token (guard (e (#t (cons 'raised-at-submit e))) (curl-engine-submit engine r))))
    (if (curl-token? token)
        (list (answer-of (lambda () (await-token token))) (log-of token))
        (list (answer-of (lambda () (raise (cdr token)))) 'refused-at-submit))))

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
;; What CASE, (get FACE PATH), answers against O, through perform.
(define (case-answer o a-case)
  (answer-of (lambda () (perform (request (url-of o (cadr a-case) (caddr a-case)))))))

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
;; dynamic-wind's after thunk; and the counts after. no-raise when nothing
;; was raised: a token THUNK answered, a submit not refused, is settled
;; first.
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
                (lambda () (settled (thunk)) 'no-raise)))))
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
  (lambda () (make-transfer-request "http://127.0.0.1:1/" 'get (list (cons name value)) #f #f #f #f #t #f)))

;; agent-request : String -> (-> Request)
(define (agent-request agent)
  (lambda () (make-transfer-request "http://127.0.0.1:1/" 'get '() agent #f #f #f #t #f)))

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

;; --- the suite's engine ------------------------------------------------------------------

(test-equal "the suite's engine is made: running, on a thread of its own, holding its multi handle and nothing else"
  (list 'running #t running-counts)
  (if engine-made?
      (list (curl-engine-state engine) (not (eqv? engine-thread-id (get-thread-id))) (native-counts))
      engine))

;; --- the request record -------------------------------------------------------------------

(for-each
 (lambda (offence)
   (let ((reason (car offence)) (c (cadr offence)))
     (test-equal (string-append "a header value with U+" (number->string (char->integer c) 16)
                                " at each of its places, and alone, is refused as "
                                (symbol->string reason) ", naming header-value and the value, with nothing native at the raise")
       (map (lambda (value) (list (list 'request-refused 'header-value value reason) running-counts running-counts))
            (at-each-place c))
       (map (lambda (value) (refusal (header-request "X-Value" value))) (at-each-place c)))
     (test-equal (string-append "a user agent with U+" (number->string (char->integer c) 16)
                                " at each of its places, and alone, is refused as "
                                (symbol->string reason) ", naming user-agent, with nothing native at the raise")
       (map (lambda (value) (list (list 'request-refused 'user-agent value reason) running-counts running-counts))
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
                                      running-counts running-counts))
                    values)
               (map (lambda (v) (list (list 'request-refused 'user-agent v 'surrounding-whitespace)
                                      running-counts running-counts))
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
  (list '(assertion-violation make-transfer-request) running-counts running-counts)
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
                                                          "agent" #f #f #f #t #f)))))
        '("User-Agent" "user-agent" "USER-AGENT" "uSeR-aGeNt"))
   (list (car (refusal (lambda () (make-transfer-request "http://127.0.0.1:1/" 'get '(("User-Agent" . "x"))
                                                         #f #f #f #f #t #f))))
         (car (refusal (lambda () (make-transfer-request "http://127.0.0.1:1/" 'get '(("User-Agents" . "x"))
                                                         "agent" #f #f #f #t #f)))))))

(test-equal "a second Host header, in any case, is refused as duplicates-field, naming it: libcurl sends only the first, and RFC 9112 has a server answer 400 to two; one Host is a header like any other"
  '((request-refused header-name "Host" duplicates-field)
    (request-refused header-name "HOST" duplicates-field)
    (request-refused header-name "host" duplicates-field)
    no-raise)
  (map (lambda (headers)
         (car (refusal (lambda () (make-transfer-request "http://127.0.0.1:1/" 'get headers #f #f #f #f #t #f)))))
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
                                                         #f #f #f #f #t #f)))))
       '("Content-Length" "content-length" "CONTENT-LENGTH" "cOnTeNt-LeNgTh"
         "Transfer-Encoding" "transfer-encoding" "TRANSFER-ENCODING" "tRaNsFeR-eNcOdInG"
         "Content-Type" "TE" "X-Content-Length" "Transfer-Encodings")))

(test-equal "a request whose header name becomes Content-Length, or Transfer-Encoding, after it was made is refused as framing-header at submit, before anything native"
  (list '(request-refused header-name framing-header) '(request-refused header-name framing-header) running-counts)
  (let* ((changed (lambda (spelt at char)
                    (let* ((name (string-copy spelt))
                           (r (make-transfer-request "http://127.0.0.1:1/" 'get (list (cons name "0")) #f #f #f #f #t #f)))
                      (string-set! name at char)
                      (submitted (lambda () (curl-engine-submit engine r))))))
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
;; A submit takes a snapshot and checks it, on this thread, so a change
;; made after the constructor's check is refused at submit, before anything
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
;; then CHANGE made to them, then submitted: what refusal says of it.
(define (made-then-changed change)
  (let* ((url (string-copy "http://127.0.0.1:1/x"))
         (name (string-copy "X-Name"))
         (value (string-copy "safe-value-xxxxxxx"))
         (header (cons name value))
         (other (string-copy "other"))
         (headers (list header (cons (string-copy "X-Other") other)))
         (agent (string-copy "an-agent"))
         (r (make-transfer-request url 'get headers agent #f #f #f #t #f)))
    (change url name value header headers agent other)
    (refusal (lambda () (curl-engine-submit engine r)))))

(test-equal "a request changed after it was made is refused at submit, at each field, before anything native: the URL, a header's name, its value, CR LF that would inject a header, the user agent, the list, a pair's car and cdr, the second header's value, and the list's or a name's type"
  (map (lambda (r) (list r running-counts running-counts))
       '((url-refused embedded-nul)
         (request-refused header-name "X:Name" not-a-token)
         (request-refused header-value "safe-value-xxxxx\rx" line-break)
         (request-refused header-value "a\r\nX-Injected: yes" line-break)
         (request-refused user-agent "an\nagent" line-break)
         (request-refused header-name "X:" not-a-token)
         (request-refused header-name "X Y" not-a-token)
         (request-refused header-value " v" surrounding-whitespace)
         (request-refused header-value "o\x100;her" not-latin-1)
         (assertion-violation curl-engine-submit)
         (assertion-violation curl-engine-submit)))
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

;; A submit checks a request in prepare-transfer's order: the snapshot of
;; the headers and the user agent, the CA file's copy, the test seam's
;; options, then the URL, parsed and its scheme checked. Each row makes its
;; field wrong and every field checked after it, so a check out of order,
;; or one left to the engine's thread, names another answer.
(test-equal "a submit checks in prepare-transfer's order, each refusal raised at submit: a header, while the CA file, the test seam's options and the URL are wrong too; the CA file, while the options and the URL are; the options, while the URL is, each before anything native; then the URL, parsed on this thread, its CURLU live at the raise and freed after"
  (list (list '(request-refused header-name "X Name" not-a-token) running-counts running-counts)
        (list '(request-refused ca-file "/x/c\x0;.pem" embedded-nul) running-counts running-counts)
        (list '(request-refused options "URL" owned-option) running-counts running-counts)
        (list '(url-refused scheme-not-http)
              '((block . 1) (easy . 0) (url . 1) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 1))
              running-counts))
  (map (lambda (wrong)
         (let* ((name (string-copy "X-Name"))
                (path (string-copy "/x/ca.pem"))
                (r (make-transfer-request (if (memq 'url wrong) "ftp://127.0.0.1:1/x" "http://127.0.0.1:1/x")
                                          'get (list (cons name "v")) #f #f #f path #t #f)))
           (when (memq 'header wrong) (string-set! name 1 #\space))
           (when (memq 'ca-file wrong) (string-set! path 4 #\nul))
           (refusal (lambda ()
                      (curl-engine-submit-with engine r (if (memq 'options wrong) '(("URL" . 1)) '()))))))
       '((header ca-file options url) (ca-file options url) (options url) (url))))

(test-equal "values that hold every char U+0001 to U+00FF but CR and LF are taken, as a header value and as a user agent, and nothing native is made"
  (list (list 'no-raise 'no-raise running-counts) (list 'no-raise 'no-raise running-counts))
  (list (refusal (header-request "X-Value" every-byte-but-cr-lf))
        (refusal (agent-request every-byte-but-cr-lf))))

(test-equal "every tchar, alone, and all of them together, is a name the request takes"
  (map (lambda (c) 'no-raise) (cons #f tchars))
  (map (lambda (name) (car (refusal (header-request name "v"))))
       (cons (list->string tchars) (map string tchars))))

(test-equal "every char from U+0000 to U+00FF that is no tchar, and U+0100, U+20AC and U+1F600, in the middle of a name, is refused as not-a-token, naming header-name, with nothing native at the raise"
  (map (lambda (c) (list (list 'request-refused 'header-name (string #\a c #\b) 'not-a-token)
                         running-counts running-counts))
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
       (list (list "http://127.0.0.1:1/" 'get '(("X-A" . "1") ("X-B" . "2") ("X:" . "3")) #f #f #f #f #t #f)
             (list "http://127.0.0.1:1/" 'get '(("X-A" . "1") ("X-B" . "2") ("X-C" . "a\nb")) #f #f #f #f #t #f)
             (list "http://127.0.0.1:1/" 'get '(("X-A" . "1") ("X-B" . "2")) "a\x0;b" #f #f #f #t #f))))

(test-equal "a header's name is checked before its value, and headers in order: the first header's fault is the one named"
  '((request-refused header-name "X:" not-a-token)
    (request-refused header-value "a\rb" line-break)
    (request-refused header-name "X:" not-a-token))
  (list (car (refusal (lambda () (make-transfer-request "http://127.0.0.1:1/" 'get '(("X:" . "a\rb")) #f #f #f #f #t #f))))
        (car (refusal (lambda () (make-transfer-request "http://127.0.0.1:1/" 'get
                                                        '(("X-Ok" . "a\rb") ("X:" . "v")) #f #f #f #f #t #f))))
        (car (refusal (lambda () (make-transfer-request "http://127.0.0.1:1/" 'get
                                                        '(("X:" . "v")) "a\rb" #f #f #f #t #f))))))

(test-equal "wrong types are assertion violations from make-transfer-request, with nothing native made: a fault that is a symbol, a string, 0, -1, 1.5 or a procedure among them, since a request holds no caller code"
  (map (lambda (x) (list '(assertion-violation make-transfer-request) running-counts running-counts))
       (iota-from 0 25))
  (map (lambda (args) (refusal (lambda () (apply make-transfer-request args))))
       (list (list 'not-a-url 'get '() #f #f #f #f #t #f)
             (list "http://a/" 'post '() #f #f #f #f #t #f)
             (list "http://a/" "get" '() #f #f #f #f #t #f)
             (list "http://a/" 'get 'none #f #f #f #f #t #f)
             (list "http://a/" 'get '(("X" . 1)) #f #f #f #f #t #f)
             (list "http://a/" 'get '((x . "v")) #f #f #f #f #t #f)
             (list "http://a/" 'get '(("X" "v")) #f #f #f #f #t #f)
             (list "http://a/" 'get '(("X" . "v") . tail) #f #f #f #f #t #f)
             (list "http://a/" 'get '() 'agent #f #f #f #t #f)
             (list "http://a/" 'get '() #f 0 #f #f #t #f)
             (list "http://a/" 'get '() #f -1 #f #f #t #f)
             (list "http://a/" 'get '() #f 1.5 #f #f #t #f)
             (list "http://a/" 'get '() #f (expt 2 63) #f #f #t #f)
             (list "http://a/" 'get '() #f "300" #f #f #t #f)
             (list "http://a/" 'get '() #f #f -1 #f #t #f)
             (list "http://a/" 'get '() #f #f 1.0 #f #t #f)
             (list "http://a/" 'get '() #f #f (- (expt 2 63) 1) #f #t #f)
             (list "http://a/" 'get '() #f #f (expt 2 63) #f #t #f)
             (list "http://a/" 'get '() #f #f "10" #f #t #f)
             (list "http://a/" 'get '() #f #f #f #f #t 'hook)
             (list "http://a/" 'get '() #f #f #f #f #t "hook")
             (list "http://a/" 'get '() #f #f #f #f #t 0)
             (list "http://a/" 'get '() #f #f #f #f #t -1)
             (list "http://a/" 'get '() #f #f #f #f #t 1.5)
             (list "http://a/" 'get '() #f #f #f #f #t (lambda (chunk) chunk)))))

(test-equal "the edges a request takes: a timeout of 1 and of the largest long, a body limit of 0 and of 2^63 - 2, method head, a fault at chunk 1 and at chunk 2^70"
  '(no-raise no-raise no-raise no-raise no-raise no-raise no-raise)
  (map (lambda (args) (car (refusal (lambda () (apply make-transfer-request args)))))
       (list (list "http://a/" 'get '() #f 1 #f #f #t #f)
             (list "http://a/" 'get '() #f (- (expt 2 63) 1) #f #f #t #f)
             (list "http://a/" 'get '() #f #f 0 #f #t #f)
             (list "http://a/" 'get '() #f #f (- (expt 2 63) 2) #f #t #f)
             (list "http://a/" 'head '() #f #f #f #f #t #f)
             (list "http://a/" 'get '() #f #f #f #f #t 1)
             (list "http://a/" 'get '() #f #f #f #f #t (expt 2 70)))))

(test-equal "a request's fields read back as given"
  (list "http://a/b" 'head '(("X-A" . "1") ("X-A" . "2")) "agent" 300 10 "/a/ca.pem" 'verify-off 3)
  (let ((r (make-transfer-request "http://a/b" 'head '(("X-A" . "1") ("X-A" . "2")) "agent" 300 10
                                  "/a/ca.pem" #f 3)))
    (list (transfer-request-url r) (transfer-request-method r) (transfer-request-headers r)
          (transfer-request-user-agent r) (transfer-request-timeout-ms r)
          (transfer-request-body-limit r) (transfer-request-ca-file r)
          (if (eq? (transfer-request-verify r) #f) 'verify-off (transfer-request-verify r))
          (transfer-request-fault r))))

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
;; long it grows, and a second free refused before C: native records each
;; list with the thread that made it, and forgets it when it is freed, so
;; curl-slist-free-all's own check finds it no longer live (ADR-0012).
(test-equal "a string list is counted slist once it holds a string, still once after a second, and zero once freed; freeing it again raises before C, from curl-slist-free-all, which no longer finds it live"
  '(((slist . 1)) ((slist . 1)) ((slist . 0)) (assertion-violation curl-slist-free-all) ((slist . 0)))
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

(test-equal "owned-option-names, written out: the options the transfer always sets and the pins' bitmasks, then each request field's, then the owned settings' twins, the CA file's CAINFO_BLOB and SSL_OPTIONS among them"
  '("URL" "PROTOCOLS_STR" "REDIR_PROTOCOLS_STR" "PROTOCOLS" "REDIR_PROTOCOLS" "NOSIGNAL"
    "WRITEFUNCTION" "WRITEDATA" "ERRORBUFFER"
    "CURLU" "NOBODY" "HTTPHEADER" "USERAGENT" "TIMEOUT_MS" "MAXFILESIZE_LARGE"
    "CAINFO" "CAPATH" "SSL_VERIFYPEER" "SSL_VERIFYHOST"
    "TIMEOUT" "MAXFILESIZE" "HTTPGET" "POST" "UPLOAD" "PUT" "CAINFO_BLOB" "SSL_OPTIONS")
  owned-option-names)

(test-equal "request-field-options, written out: url's CURLU, method's NOBODY, headers' HTTPHEADER, user-agent's USERAGENT, timeout-ms's TIMEOUT_MS, body-limit's MAXFILESIZE_LARGE, ca-file's CAINFO and CAPATH, and verify's SSL_VERIFYPEER and SSL_VERIFYHOST"
  '((url "CURLU") (method "NOBODY") (headers "HTTPHEADER") (user-agent "USERAGENT")
    (timeout-ms "TIMEOUT_MS") (body-limit "MAXFILESIZE_LARGE") (ca-file "CAINFO" "CAPATH")
    (verify "SSL_VERIFYPEER" "SSL_VERIFYHOST"))
  request-field-options)

(test-equal "every option of every request field is an owned option, so the test seam refuses it"
  '()
  (filter (lambda (name) (not (member name owned-option-names)))
          (apply append (map cdr request-field-options))))

(test-equal "a request's fields, written out, in the record's order: url, method, headers, user-agent, timeout-ms, body-limit, ca-file, verify and fault"
  '(url method headers user-agent timeout-ms body-limit ca-file verify fault)
  (guard (e (#t (list 'raised (describe e))))
    (vector->list (record-type-field-names
                   (record-rtd (make-transfer-request "http://a/" 'get '() #f #f #f #f #t #f))))))

;; The record's own fields, read from its record type: a field added later
;; needs a row, or its place here among the fields that set no option.
(test-equal "every field of a request has a row in request-field-options, but fault, which sets no option"
  '()
  (guard (e (#t (list 'raised (describe e))))
    (filter (lambda (field) (not (or (assq field request-field-options) (memq field '(fault)))))
            (vector->list (record-type-field-names
                           (record-rtd (make-transfer-request "http://a/" 'get '() #f #f #f #f #t #f)))))))

;; seam-refusal : (Listof Pair) -> Refusal
;; What refusal says of a submit through the test seam given OPTIONS, on a
;; URL nothing listens on: a refusal is raised at submit, before anything
;; native, and a transfer that ran would answer 7 there.
(define (seam-refusal options)
  (refusal (lambda () (curl-engine-submit-with engine (request "http://127.0.0.1:1/") options))))

(test-equal "the test seam refuses each owned option this libcurl knows, by id, as owned-option, naming it, at submit, before anything native"
  (map (lambda (name)
         (list (if (curl-easy-option name)
                   (list 'request-refused 'options name 'owned-option)
                   (list 'transfer-refused 'unknown-option name))
               running-counts running-counts))
       owned-option-names)
  (map (lambda (name) (seam-refusal (list (cons name 1)))) owned-option-names))

;; The TLS fields' options and the CA file's twins, written out here: the
;; loop above is held by owned-option-names, the table it loops over, so a
;; name dropped from both would pass it (ADR-0009, amended 2026-10-24).
(test-equal "the test seam refuses CAINFO, CAPATH, SSL_VERIFYPEER and SSL_VERIFYHOST, the TLS fields' options, and CAINFO_BLOB and SSL_OPTIONS, the CA file's twins, each by id, as owned-option, naming it, at submit, before anything native"
  (map (lambda (name) (list (list 'request-refused 'options name 'owned-option) running-counts running-counts))
       '("CAINFO" "CAPATH" "SSL_VERIFYPEER" "SSL_VERIFYHOST" "CAINFO_BLOB" "SSL_OPTIONS"))
  (map (lambda (name) (seam-refusal (list (cons name 1))))
       '("CAINFO" "CAPATH" "SSL_VERIFYPEER" "SSL_VERIFYHOST" "CAINFO_BLOB" "SSL_OPTIONS")))

(test-equal "an alias of an owned option is refused as owned-option: FILE is WRITEDATA's id, and RTSPHEADER HTTPHEADER's"
  (list '(same same)
        (list '(request-refused options "FILE" owned-option) running-counts running-counts)
        (list '(request-refused options "RTSPHEADER" owned-option) running-counts running-counts))
  (list (map (lambda (pair)
               (let ((a (curl-easy-option (car pair))) (b (curl-easy-option (cdr pair))))
                 (if (and a b (= (car a) (car b))) 'same (list (car pair) a (cdr pair) b))))
             '(("FILE" . "WRITEDATA") ("RTSPHEADER" . "HTTPHEADER")))
        (seam-refusal '(("FILE" . 1)))
        (seam-refusal '(("RTSPHEADER" . 1)))))

(test-equal "the test seam refuses an option of every other CURLOT type as unsupported-type, at submit, before anything native: a string, a string list, an object, a callback pointer, a function and a blob"
  (list '(string slist object cbptr function blob)
        (map (lambda (name) (list (list 'request-refused 'options name 'unsupported-type) running-counts running-counts))
             '("ACCEPT_ENCODING" "HTTP200ALIASES" "STDERR" "HEADERDATA" "XFERINFOFUNCTION" "SSLCERT_BLOB")))
  (list (map (lambda (name)
               (let ((o (curl-easy-option name)))
                 (if o (car (find (lambda (entry) (= (cdr entry) (cdr o))) curlot-types)) (list 'unknown name))))
             '("ACCEPT_ENCODING" "HTTP200ALIASES" "STDERR" "HEADERDATA" "XFERINFOFUNCTION" "SSLCERT_BLOB"))
        (map (lambda (name) (seam-refusal (list (cons name 1))))
             '("ACCEPT_ENCODING" "HTTP200ALIASES" "STDERR" "HEADERDATA" "XFERINFOFUNCTION" "SSLCERT_BLOB"))))

(test-equal "the test seam's values are checked at submit, before anything native: a string for a long, a long past long's range, an off_t past its range, are assertion violations from curl-engine-submit-with; options of any other shape too; an unknown name is unknown-option"
  (map (lambda (r) (list r running-counts running-counts))
       '((assertion-violation curl-engine-submit-with)
         (assertion-violation curl-engine-submit-with)
         (assertion-violation curl-engine-submit-with)
         (assertion-violation curl-engine-submit-with)
         (assertion-violation curl-engine-submit-with)
         (transfer-refused unknown-option "NO_SUCH_OPTION")))
  (map seam-refusal
       (list '(("MAXREDIRS" . "3"))
             (list (cons "MAXREDIRS" (expt 2 63)))
             (list (cons "MAX_RECV_SPEED_LARGE" (expt 2 63)))
             'not-a-list
             '((maxredirs . 3))
             '(("NO_SUCH_OPTION" . 1)))))

;; --- what a transfer sets, read from transfer.sls as data -----------------------------
;; On the engine's thread, start-transfer! makes a transfer's native objects
;; and set-transfer-options! every setting its easy handle gets, in one
;; order; free-transfer! frees them the other way round (M3 plan, section
;; 5.2). libcurl reads no setting before the transfer runs, and 8.20.0's
;; curl_easy_cleanup reads none of the objects a wrong order would free
;; first: freed first, each passed every behavioural check, Valgrind's too
;; (traps.md). So the orders are read. Their limit is the pins': they hold
;; an accidental move, not a rewrite made to pass them.

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

;; transfer-sets : Any
;; Each set-option! and set-string-option! call in set-transfer-options!,
;; as option-sets reads it, or what went wrong.
(define transfer-sets
  (let ((d (transfer-definition 'set-transfer-options!)))
    (if (and (pair? d) (eq? (car d) 'define)) (option-sets (cddr d) '()) d)))

;; --- the pins, read from transfer.sls as data ----------------------------------------
;; ADR-0003's protocol pins and the signal rule are one table, set by one
;; call, the first form of set-transfer-options!, before any other setting;
;; their names, and the deprecated bitmasks', stand nowhere else. The limit
;; of these checks: they hold the pins against an accidental move, a set
;; made later, or conditionally, or never, or an owned name undone in place;
;; not against a rewrite made to pass them, such as a name built from
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

;; holds? : Any Any -> Boolean
(define (holds? x datum)
  (or (equal? x datum) (and (pair? x) (or (holds? (car x) datum) (holds? (cdr x) datum)))))

;; symbol-count : Symbol Any -> Natural
(define (symbol-count name x)
  (cond ((eq? x name) 1)
        ((pair? x) (+ (symbol-count name (car x)) (symbol-count name (cdr x))))
        (else 0)))

;; set-name : Any -> Any
;; NAME, as a set-option! call writes it: a string as itself; (field-option
;; 'FIELD) as FIELD's one option, from request-field-options; (car
;; setting), the test seam's loop, as seam; anything else as (unread NAME).
(define (set-name name)
  (cond ((string? name) name)
        ((and (list? name) (= (length name) 2) (eq? (car name) 'field-option)
              (pair? (cadr name)) (eq? (car (cadr name)) 'quote) (pair? (cdr (cadr name)))
              (assq (cadr (cadr name)) request-field-options))
         => (lambda (row) (if (= (length row) 2) (cadr row) (list 'several row))))
        ((equal? name '(car setting)) 'seam)
        (else (list 'unread name))))

;; setting-order : Any -> Any
;; What each form of the definition D's body sets, in order: pins for
;; (set-pinned-options! easy buffer); tls for (set-tls-options! easy
;; (plan-ca-file plan) (plan-verify plan) buffer); else each set-option!
;; and set-string-option! call in it, by set-name; (other FORM) for a form
;; that sets nothing. D itself when it is no definition: what went wrong.
(define (setting-order d)
  (if (and (list? d) (pair? d) (eq? (car d) 'define))
      (apply append
             (map (lambda (form)
                    (cond ((equal? form '(set-pinned-options! easy buffer)) '(pins))
                          ((equal? form '(set-tls-options! easy (plan-ca-file plan) (plan-verify plan) buffer))
                           '(tls))
                          (else (let ((sets (option-sets form '())))
                                  (if (null? sets)
                                      (list (list 'other form))
                                      (map (lambda (s) (set-name (car s))) sets))))))
                  (cddr d)))
      d))

(test-equal "set-transfer-options!, read from transfer.sls, form by form: the pins first, then ERRORBUFFER, CURLU, WRITEFUNCTION and WRITEDATA, then the request's NOBODY, HTTPHEADER, USERAGENT, TIMEOUT_MS and MAXFILESIZE_LARGE, then set-tls-options!, then the test seam's settings; set-pinned-options! and set-transfer-options! each stand twice in transfer.sls, a definition and one call"
  '((pins "ERRORBUFFER" "CURLU" "WRITEFUNCTION" "WRITEDATA" "NOBODY" "HTTPHEADER" "USERAGENT" "TIMEOUT_MS"
          "MAXFILESIZE_LARGE" tls seam)
    2 2)
  (list (setting-order (transfer-definition 'set-transfer-options!))
        (symbol-count 'set-pinned-options! transfer-library)
        (symbol-count 'set-transfer-options! transfer-library)))

(test-equal "setting-order, the reader: pins, tls, each set's name at any depth, a field's through field-option, the seam's loop, a form that sets nothing, and a name it cannot read"
  '(pins "A" "NOBODY" "B" tls seam (other (f x)) (unread n))
  (setting-order '(define (g)
                    (set-pinned-options! easy buffer)
                    (set-option! e "A" 1 b)
                    (when h (set-option! e (field-option 'method) 1 b) (set-string-option! e "B" "x" b))
                    (set-tls-options! easy (plan-ca-file plan) (plan-verify plan) buffer)
                    (for-each (lambda (setting) (set-option! e (car setting) (cdr setting) b)) s)
                    (f x)
                    (set-option! e n 1 b))))

;; symbols-in : (Listof Symbol) Any -> (Listof Symbol)
;; Each of NAMES standing in X, in the order written, depth first.
(define (symbols-in names x)
  (cond ((and (symbol? x) (memq x names)) (list x))
        ((pair? x) (append (symbols-in names (car x)) (symbols-in names (cdr x))))
        (else '())))

(test-equal "symbols-in, the reader: each listed symbol at any depth, a form's head among them, in the order written, and an unlisted one passed over"
  '(a b a c)
  (symbols-in '(a b c) '(a (x b) ((a)) y . c)))

;; live-setters : (Listof Symbol)
;; The live record's setters: the key's, its sink's, and one per native
;; object a transfer holds.
(define live-setters
  '(live-transfer-key-set! live-transfer-sink-set! live-transfer-url-set! live-transfer-buffer-set!
    live-transfer-header-list-set! live-transfer-easy-set!))

;; making-order : (Listof Symbol)
;; start-transfer!'s setters, its settings' calls and its free, as written.
(define making-order
  (symbols-in (append live-setters '(set-transfer-options! set-option! set-string-option! free-transfer!))
              (transfer-definition 'start-transfer!)))

;; freeing-order : (Listof Symbol)
;; free-transfer!'s frees and setters, as written.
(define freeing-order
  (symbols-in (append live-setters '(curl-easy-cleanup curl-slist-free-all free-foreign-block! free-parsed-url!
                                     count-down!))
              (transfer-definition 'free-transfer!)))

(test-equal "start-transfer!, read from transfer.sls, records what it makes in order: free-transfer! on a raise; then the key and its sink, the CURLU, the error buffer, the header list, then the easy handle; then set-transfer-options!, once, and no setting of its own"
  '(free-transfer! live-transfer-key-set! live-transfer-sink-set! live-transfer-url-set!
    live-transfer-buffer-set! live-transfer-header-list-set! live-transfer-easy-set! set-transfer-options!)
  making-order)

(test-equal "free-transfer!, read from transfer.sls, frees the other way round from start-transfer!'s making: the easy handle, the header list, the error buffer, the CURLU, then the key, each freed before its record is cleared"
  (list '(curl-easy-cleanup live-transfer-easy-set! curl-slist-free-all live-transfer-header-list-set!
          free-foreign-block! live-transfer-buffer-set! free-parsed-url! live-transfer-url-set!
          count-down! live-transfer-key-set!)
        'the-making-reversed)
  (list freeing-order
        (let ((made (filter (lambda (s) (memq s live-setters)) making-order))
              (freed (filter (lambda (s) (memq s live-setters)) freeing-order)))
          (if (equal? (reverse (remq 'live-transfer-sink-set! made)) freed)
              'the-making-reversed
              (list 'made made 'freed freed)))))

(test-equal "prepare-transfer, read from transfer.sls, checks on the caller's thread in order: that it has a request, the snapshot of the headers and the user agent, the CA file's copy, the test seam's settings, then the URL, parsed and its scheme checked; then it makes the plan"
  '(transfer-request? snapshot ca-file-copy checked-settings call-with-parsed-url require-http-scheme make-plan)
  (symbols-in '(transfer-request? snapshot ca-file-copy checked-settings call-with-parsed-url require-http-scheme
                make-plan)
              (transfer-definition 'prepare-transfer)))

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

(test-equal "every option set-transfer-options! sets is an owned option, written as a literal or through field-option, but for the test seam's own settings, set once, by (car setting)"
  '(() 1)
  (if (list? transfer-sets)
      (list (map car (filter (lambda (s) (not (or (owned-set? (car s)) (equal? (car s) '(car setting)))))
                             transfer-sets))
            (length (filter (lambda (s) (equal? (car s) '(car setting))) transfer-sets)))
      transfer-sets))

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
;; THUNK run in a fresh Chez engine, make-engine's, not chez-curl's, with
;; fuel 1, 1+STEP, 1+2 STEP and so on, each that runs out abandoned, until
;; one completes: (completed EXPIRED), or (never-completed EXPIRED) past
;; 100000 fuel.
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
;; Takes each mutex transfer.sls and the counters hold, in turn, and the
;; suite's engine's: the live-transfer table's, the option cache's, the
;; counts', and the engine's.
(define (every-lock)
  (live-transfer-count)
  (cached-option-names)
  (native-counts)
  (curl-engine-state engine))

;; log-shape : Any -> Any
;; A chunk log, by log-of, as (ACCEPTED ENDING): how many bytes its
;; accepted chunks held, and refused when one refused chunk ended it, none
;; when it holds accepted chunks alone; else (odd LOG).
(define (log-shape log)
  (if (and (list? log) (for-all (lambda (c) (and (list? c) (= (length c) 2) (integer? (car c)))) log))
      (let loop ((rest log) (bytes 0))
        (cond ((null? rest) (list bytes 'none))
              ((eq? (cadr (car rest)) 'accepted) (loop (cdr rest) (+ bytes (car (car rest)))))
              ((and (eq? (cadr (car rest)) 'refused) (null? (cdr rest))) (list bytes 'refused))
              (else (list 'odd log))))
      (list 'odd log)))

;; recorded-run : Request -> (List Any Any)
;; What R answers through the suite's engine, a &curl-transfer-error as
;; (refused REASON CODE RECORDED), RECORDED the object it recorded, else as
;; answer-of names it; and its token's log, by log-of.
(define (recorded-run r)
  (guard (e (#t (list (list 'raised-at-submit (describe e)) 'no-log)))
    (let ((token (curl-engine-submit engine r)))
      (list (guard (e ((curl-transfer-error? e)
                       (list 'refused (curl-transfer-error-reason e) (curl-transfer-error-code e)
                             (curl-transfer-error-recorded e))))
              (let ((response (await-token token)))
                (answer-of (lambda () response))))
            (log-of token)))))

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
     (test-equal (string-append "shared: " (case-text (car pair)) ", whole, and the counts back to the engine's alone")
       (list (expanded (cadr pair)) running-counts)
       (with-counts (case-answer o (car pair)))))
   shared-answers)

  ;; --- the varying scenarios, against this libcurl's row
  (set! varying-answered
        (map (lambda (a-case) (list a-case (case-answer o a-case) (native-counts))) varying-cases))
  (for-each
   (lambda (entry)
     (let ((want (and the-row (assoc (car entry) (row-answers the-row)))))
       (test-equal (string-append "varying: " (case-text (car entry)) ", as this libcurl's row says, and the counts back to the engine's alone")
         (list (if want (expanded (cadr want)) (list 'no-row-for version)) running-counts)
         (list (cadr entry) (caddr entry)))))
   varying-answered)

  ;; --- the echoes, whose Host holds the origin's port
  (test-equal "echo: GET /raw/echo sends Host and libcurl's Accept, and no User-Agent unless asked"
    (list (echoed (raw-echo-body o '("Accept: */*\r\n"))) running-counts)
    (with-counts (answer-of (lambda () (perform (request (url-of o 'raw "/raw/echo")))))))
  (let ((node-echo (string-append "GET /echo HTTP/1.1\nHost: " (host-of o 'http) "\nAccept: */*\n\n")))
    (test-equal "echo: GET /echo on the http face, as Node parsed it"
      (list (list 'response 200 'http/1.1
                  (list (list "Content-Length" (number->string (string-length node-echo)))
                        '("Connection" "keep-alive"))
                  node-echo)
            running-counts)
      (with-counts (answer-of (lambda () (perform (request (url-of o 'http "/echo"))))))))

  ;; --- the setopt bindings, observed (ADR-0001's FFI test)
  ;; A string: USERAGENT's chars U+0080 to U+00FF arrive as single bytes,
  ;; never UTF-8's two.
  (let ((agent (chars (iota-from #x80 128))))
    (test-equal "USERAGENT: chars U+0080 to U+00FF arrive in /raw/echo as exactly those bytes, one each, between Host and Accept"
      (list (echoed (raw-echo-body o (list (string-append "User-Agent: " agent "\r\n") "Accept: */*\r\n")))
            running-counts)
      (with-counts (answer-of (lambda () (perform (request (url-of o 'raw "/raw/echo")
                                                           'user-agent agent)))))))
  ;; A long: TIMEOUT_MS. Without it, a stall never ends.
  (for-each
   (lambda (path)
     ;; Measured, 8 runs each: 301 to 304 ms natively, 303 to 386 under the
     ;; memory gate's Valgrind, the first the slowest. 600 catches a timeout
     ;; that arrived doubled.
     (test-equal (string-append "TIMEOUT_MS 300 against " path ": 28, no sooner than 300 ms and sooner than 600")
       (list (list 'refused 'perform-failed curle-operation-timedout) 'within running-counts)
       (let* ((start (now-ms))
              (a (answer-of (lambda () (perform (request (url-of o 'raw path) 'timeout 300)))))
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
            running-counts)
      (with-counts (answer-of (lambda () (perform (request (url-of o 'http "/echo") 'method 'head)))))))
  (test-equal "NOBODY: head of /status/200 gets its headers and no body"
    (list '(response 200 http/1.1 (("Content-Length" "11") ("Connection" "keep-alive")) "") running-counts)
    (with-counts (answer-of (lambda () (perform (request (url-of o 'http "/status/200") 'method 'head))))))
  ;; An off_t: MAXFILESIZE_LARGE, at the body limit plus one, below a
  ;; Content-Length: refused before any body.
  (test-equal "MAXFILESIZE_LARGE below a Content-Length: a body limit of 9 against /status/200's 11 is 63, perform-failed, before any chunk: the chunk log is empty"
    (list (list (list 'refused 'perform-failed curle-filesize-exceeded) '()) running-counts)
    (with-counts (run (request (url-of o 'http "/status/200") 'limit 9))))

  ;; --- Latin-1, both ways
  (test-equal "a request header whose value holds every char U+0001 to U+00FF but CR and LF arrives in /raw/echo byte for byte, after Accept"
    (list (echoed (raw-echo-body o (list "Accept: */*\r\n"
                                         (string-append "X-Bytes: " every-byte-but-cr-lf "\r\n"))))
          running-counts)
    (with-counts (answer-of (lambda () (perform (request (url-of o 'raw "/raw/echo")
                                                         'headers (list (cons "X-Bytes" every-byte-but-cr-lf))))))))
  (test-equal "request headers keep their order and their repeats, and an empty value is sent as libcurl's Name; form writes it"
    (list (echoed (raw-echo-body o '("Accept: */*\r\n" "X-One: 1\r\n" "X-Dup: a\r\n" "X-Empty:\r\n"
                                     "X-Dup: b\r\n" "X-Two: two  words\r\n")))
          running-counts)
    (with-counts (answer-of (lambda () (perform (request (url-of o 'raw "/raw/echo")
                                                         'headers '(("X-One" . "1") ("X-Dup" . "a") ("X-Empty" . "")
                                                                    ("X-Dup" . "b") ("X-Two" . "two  words"))))))))

  (test-equal "a Host header is libcurl's exception to order: sent first, in place of libcurl's own, spelt Host, ahead of Accept and the headers before it"
    (list (echoed "GET /raw/echo HTTP/1.1\r\nHost: a.example\r\nAccept: */*\r\nX-A: 1\r\nX-B: 2\r\n\r\n")
          running-counts)
    (with-counts (answer-of (lambda () (perform (request (url-of o 'raw "/raw/echo")
                                                         'headers '(("X-A" . "1") ("hOsT" . "a.example") ("X-B" . "2"))))))))

  ;; --- the effective URL, libcurl's own form, read as UTF-8
  (test-equal "the effective URL: libcurl's parse of the request, dot segments gone; a redirect not followed keeps the request's; é in a path reads back as é"
    (list (url-of o 'http "/status/200")
          (url-of o 'http "/redirect/302?to=/status/200")
          (url-of o 'http "/caf\xE9;")
          running-counts)
    (let ((effective (lambda (path)
                       (guard (e (#t (list 'raised (describe e))))
                         (transfer-response-effective-url (perform (request (url-of o 'http path))))))))
      (list (effective "/a/../status/200")
            (effective "/redirect/302?to=/status/200")
            (effective "/caf\xE9;")
            (native-counts))))

  ;; --- the last request's headers: a redirect followed, through the test
  ;; seam, makes two requests, and the first one's headers are not the
  ;; response's
  (test-equal "with FOLLOWLOCATION set through the test seam, a followed redirect answers the last request's status, headers and body, and its effective URL"
    (list (list '(response 200 http/1.1 (("Content-Length" "11") ("Connection" "keep-alive")) "status 200\n")
                (url-of o 'http "/status/200"))
          running-counts)
    (list (guard (e (#t (list 'raised (describe e))))
            (let ((r (perform-with (request (url-of o 'http "/redirect/302?to=/status/200"))
                                   '(("FOLLOWLOCATION" . 1)))))
              (list (answer-of (lambda () r)) (transfer-response-effective-url r))))
          (native-counts)))

  ;; --- the URL, checked at submit, on this thread
  (test-equal "a URL whose scheme is not http or https is refused at submit as scheme-not-http, and one curl_url refuses with its code; nothing native is left"
    (list '(url-refused scheme-not-http #f) '(url-refused bad-port-number 4) running-counts)
    (list (submitted (lambda () (curl-engine-submit engine (request "file:///etc/passwd"))))
          (submitted (lambda () (curl-engine-submit engine (request "http://127.0.0.1:99999/"))))
          (native-counts)))

  ;; --- the counts while a transfer is live, read on this thread while the
  ;; engine's table holds a drip, before the counts and after them: the
  ;; engine records a transfer once start-transfer! has made everything,
  ;; and takes it out before free-transfer! frees anything
  (let ((live-counts '((block . 2) (easy . 1) (url . 1) (slist . 1) (curl-string . 0) (transfer . 1) (multi . 1))))
    (test-equal "while a transfer is live, it holds its easy handle, its CURLU, its header list, its error buffer and itself, one each, beside the engine's multi handle and slot, and the live-transfer table and the engine's table each hold it; once it ends, the engine's handle and slot alone, and both tables empty"
      (list live-counts 1 1
            '(response 200 http/1.1 (("Content-Length" "20")) "abcdefghijklmnopqrst")
            running-counts 0 0)
      (let* ((t (curl-engine-submit engine (request (url-of o 'raw "/raw/drip?bytes=20&gap=50")
                                                    'headers '(("X-A" . "1")))))
             ;; Sampled until a sample is the expected one, or the drip ends:
             ;; the engine's own slots come and go (native-counts).
             (seen (let wait ((deadline (+ (now-ms) 10000)) (last '(never-seen-live)))
                     (cond ((or (curl-token-done? t) (> (now-ms) deadline)) last)
                           ((= (curl-engine-live-count engine) 1)
                            (let* ((counts (native-counts))
                                   (live (live-transfer-count))
                                   (table (curl-engine-live-count engine))
                                   (sample (list counts live table)))
                              (cond ((not (= table 1)) (pause-ms 1) (wait deadline last))
                                    ((equal? counts live-counts) sample)
                                    (else (pause-ms 1) (wait deadline sample)))))
                           (else (pause-ms 5) (wait deadline last)))))
             (a (answer-of (lambda () (await-token t)))))
        (append seen (list a (native-counts) (live-transfer-count) (curl-engine-live-count engine))))))

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
                (lambda () (perform (apply request (url-of o face path) options))))))
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
           (list "a fault planted at chunk 1" (get 'http "/status/200" 'fault 1) #f))))

  ;; --- the body limit, at its edges: limit-*.txt's 20 cases. The chunk
  ;; log shows what the callable did: how many bytes it accepted, and
  ;; whether it refused the chunk that ended the transfer.
  (for-each
   (lambda (row)
     (let ((face (car row)) (path (cadr row)) (limit (caddr row)) (want (cadddr row)) (accepted (list-ref row 4)))
       (test-equal (string-append "body limit " (number->string limit) " against " (symbol->string face) " " path
                                  ": " (written want) ", the callable having accepted " (written accepted)
                                  (if (eq? (cadr want) 'body-limit) ", then refused the next chunk" ", and refused none")
                                  ", each chunk on the engine's thread")
         (list want (list (string-length accepted) (if (eq? (cadr want) 'body-limit) 'refused 'none)) running-counts)
         (let ((r (run (request (url-of o face path) 'limit limit))))
           (list (car r) (log-shape (cadr r)) (native-counts))))))
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

  ;; --- a raise inside the callable, planted by a request's fault: data,
  ;; never a procedure (M3 plan, section 3.6)
  (for-each
   (lambda (row)
     (test-equal (string-append "a fault " (car row) ", each chunk logged on the engine's thread")
       (list (caddr row) running-counts)
       (let ((r (recorded-run (cadr row))))
         (with-counts (if (null? (cdddr row)) r (list (car r) (log-shape (cadr r))))))))
   (list (list "at chunk 1 of /status/200's one: the callable raises (planted-fault 1), so the transfer is callback-raised, 23, recording it, the chunk logged raised"
               (request (url-of o 'http "/status/200") 'fault 1)
               `((refused callback-raised ,curle-write-error ,(planted-fault 1)) ((11 raised))))
         (list "at chunk 2 of /chunked's three: the first accepted, the second raised, recording (planted-fault 2), and no third"
               (request (url-of o 'http "/chunked") 'fault 2)
               `((refused callback-raised ,curle-write-error ,(planted-fault 2)) ((6 accepted) (5 raised))))
         (list "at chunk 1 of /status/200, with a body limit of 10 it passes: the fault comes before the limit check, so callback-raised, not body-limit"
               (request (url-of o 'http "/status/200") 'limit 10 'fault 1)
               `((refused callback-raised ,curle-write-error ,(planted-fault 1)) ((11 raised))))
         (list "at chunk 2 of /status/200's one: never reached, so the response whole, its chunk accepted"
               (request (url-of o 'http "/status/200") 'fault 2)
               `((response 200 http/1.1 (("Content-Length" "11") ("Connection" "keep-alive")) ,ok)
                 ((11 accepted))))
         ;; How long the refused chunk is can vary: 8.20.0 cuts it to the
         ;; one byte MAXFILESIZE_LARGE leaves, where the whole chunk is 5. So
         ;; the log is read as its shape: the bytes accepted, then a refusal.
         (list "at chunk 3 of /chunked, with a body limit of 6: never reached, since the limit refuses chunk 2 and ends the transfer as body-limit, recording nothing; the log, 6 bytes accepted, then a refusal"
               (request (url-of o 'http "/chunked") 'limit 6 'fault 3)
               `((refused body-limit ,curle-write-error #f) (6 refused))
               'shape)))
  ;; --- the user agent another thread changes while transfers run
  (test-equal "a user agent another thread flips between c and CR while 300 transfers run: each is refused as line-break, or sends the agent whole, never the CR, both seen; the counts back to the engine's alone"
    (list '() '(refused whole) running-counts)
    (let* ((agent (string-copy "abcdef"))
           (r (make-transfer-request (url-of o 'raw "/raw/echo") 'get '() agent default-timeout #f #f #t #f))
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
                (let* ((a (answer-of (lambda () (perform r))))
                       (k (cond ((equal? a clean) 'whole)
                                ((equal? a '(request-refused user-agent line-break)) 'refused)
                                (else #f))))
                  (loop (+ i 1)
                        (if k odd (cons a odd))
                        (if (and k (not (memq k seen))) (cons k seen) seen))))))
        (lambda () (set! stop #t) (thread-join flipper)))))

  ;; --- a mutex held across an asynchronous escape: Chez's with-mutex is a
  ;; dynamic-wind whose before thunk takes the mutex, so a Chez engine that
  ;; runs out between the take and the wind leaves it held, with no after
  ;; thunk to release it, and every other thread then blocks on it; and one
  ;; that runs out between making a native object and recording it leaks
  ;; the object. A caller's thread runs no transfer now, only a submit and
  ;; an await. Each sweep runs out at every tick of a call that takes a
  ;; mutex: the live-transfer table's, the option cache's; through a submit
  ;; whose seam setting is refused after a known one, the lookup's; and,
  ;; through a submit to a stopped engine, the URL's CURLU, made and freed
  ;; on this thread, and that engine's own mutex, which refuses it.
  (test-equal "a Chez engine that runs out at every tick of live-transfer-count, of cached-option-names, of a submit through the test seam refused as unknown-option after MAXREDIRS, and of a submit to a stopped engine, refused as stopped once its URL was parsed, each abandoned, until one completes: each completes, no native object is left, and another thread then takes every lock, both engines' among them"
    `(stopped (completed expired-first) (completed expired-first) (completed expired-first)
      (completed expired-first) ,running-counts other-thread-ran)
    (let* ((refused (request "http://127.0.0.1:1/"))
           (stopped (guard (e (#t (list 'raised (describe e))))
                      (let ((made (make-curl-engine))) (curl-engine-stop made) made)))
           (submit-to-stopped
            (lambda ()
              (guard (e ((curl-engine-error? e) (curl-engine-error-reason e))
                        (#t (list 'raised (describe e))))
                (curl-engine-submit stopped refused)
                'queued)))
           (stopped-refuses (submit-to-stopped))
           (sweeps (map (lambda (thunk)
                          (let ((r (engine-sweep thunk 1)))
                            (if (and (eq? (car r) 'completed) (> (cadr r) 0)) '(completed expired-first) r)))
                        (list live-transfer-count
                              cached-option-names
                              (lambda ()
                                (answer-of (lambda ()
                                             (curl-engine-submit-with engine refused
                                                                      '(("MAXREDIRS" . 1) ("NO_SUCH_OPTION" . 1))))))
                              submit-to-stopped))))
      (append (list stopped-refuses) sweeps
              (list (native-counts)
                    (other-thread-can (lambda () (every-lock) (curl-engine-state stopped)))))))

  (test-equal "the error carries libcurl's texts: strerror for 23, and the error buffer's, both strings; no recorded object for the body limit"
    '(body-limit 23 #t #t no-recorded)
    (guard (e ((curl-transfer-error? e)
               (list (curl-transfer-error-reason e) (curl-transfer-error-code e)
                     (string? (curl-transfer-error-strerror e))
                     (string? (curl-transfer-error-error-buffer e))
                     (if (eq? (curl-transfer-error-recorded e) #f) 'no-recorded 'recorded)))
              (#t (list 'raised (describe e))))
      (perform (request (url-of o 'http "/status/200") 'limit 10))
      'no-raise))

  ;; --- options through the test seam, curl-engine-submit-with
  (test-equal "an option the loaded libcurl does not know raises unknown-option, naming it, with no code, and the counts back to the engine's alone"
    (list '(unknown-option #f "NO_SUCH_OPTION") running-counts)
    (list (guard (e ((curl-transfer-error? e)
                     (list (curl-transfer-error-reason e) (curl-transfer-error-code e)
                           (curl-transfer-error-option e)))
                    (#t (list 'raised (describe e))))
            (perform-with (request (url-of o 'http "/status/200")) '(("NO_SUCH_OPTION" . 1)))
            'no-raise)
          (native-counts)))
  (test-equal "an option libcurl refuses raises setopt-failed, naming it, with its code, through each integer binding: MAXREDIRS -2 through the long one and MAX_RECV_SPEED_LARGE -1 through the off_t one are 43, never taken zero-extended, as 4294967294 and 4294967295 would be; the counts back to the engine's alone"
    (list (list 'setopt-failed curle-bad-function-argument "MAXREDIRS")
          (list 'setopt-failed curle-bad-function-argument "MAX_RECV_SPEED_LARGE")
          running-counts)
    (append (map (lambda (option)
                   (guard (e ((curl-transfer-error? e)
                              (list (curl-transfer-error-reason e) (curl-transfer-error-code e)
                                    (curl-transfer-error-option e)))
                             (#t (list 'raised (describe e))))
                     (perform-with (request (url-of o 'http "/status/200")) (list option))
                     'no-raise))
                 (list '("MAXREDIRS" . -2) '("MAX_RECV_SPEED_LARGE" . -1)))
            (list (native-counts))))

  ;; --- the redirect pin, observed: without REDIR_PROTOCOLS_STR, libcurl
  ;; would follow to FTP, and answer 7, connection refused
  (test-equal "REDIR_PROTOCOLS_STR, observed: FOLLOWLOCATION through the test seam, to ftp://127.0.0.1:1/, a protocol this libcurl lists, is refused as 1, CURLE_UNSUPPORTED_PROTOCOL, never tried; the counts back to the engine's alone"
    (list 'ftp-listed (list 'refused 'perform-failed curle-unsupported-protocol) running-counts)
    (list (if (member "ftp" (loaded-protocols)) 'ftp-listed (list 'no-ftp-in (loaded-protocols)))
          (answer-of (lambda ()
                       (perform-with (request (url-of o 'http "/redirect/302?to=ftp://127.0.0.1:1/"))
                                     '(("FOLLOWLOCATION" . 1)))))
          (native-counts)))

  ;; --- the option cache keeps its own copy of a name
  (test-equal "the option cache keeps a copy of each name: a caller's name, changed after its transfer, leaves the cache's key as it was"
    '(kept not-taken)
    (let ((name (string-copy "LOW_SPEED_TIME")))
      (perform-with (request (url-of o 'http "/status/200")) (list (cons name 30)))
      (string-set! name 0 #\X)
      (let ((keys (cached-option-names)))
        (list (if (member "LOW_SPEED_TIME" keys) 'kept 'lost)
              (if (member "XOW_SPEED_TIME" keys) 'taken 'not-taken)))))

  ;; --- a header value another thread changes while transfers run
  (test-equal "a header value another thread flips between c and CR while 300 transfers run: each is refused as line-break, or sends the value whole, never the CR, both seen; the counts back to the engine's alone"
    (list '() '(refused whole) running-counts)
    (let* ((value (string-copy "abcdef"))
           (r (make-transfer-request (url-of o 'raw "/raw/echo") 'get (list (cons "X-Race" value))
                                     #f default-timeout #f #f #t #f))
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
                (let* ((a (answer-of (lambda () (perform r))))
                       (k (cond ((equal? a clean) 'whole)
                                ((equal? a '(request-refused header-value line-break)) 'refused)
                                (else #f))))
                  (loop (+ i 1)
                        (if k odd (cons a odd))
                        (if (and k (not (memq k seen))) (cons k seen) seen))))))
        (lambda () (set! stop #t) (thread-join flipper)))))

  ;; --- two threads, each submitting its own transfer to the one engine, at
  ;; once. Positive evidence that the transfers overlapped: this thread saw
  ;; the engine's table hold both.
  (test-equal "two threads, each submitting its own transfer to the one engine at once: the engine's table held both together, both bodies whole, each chunk on the engine's thread, and the counts back to the engine's alone"
    (list 'overlapped
          '(((response 200 http/1.1 (("Content-Length" "11")) "hello world") ((5 accepted) (6 accepted)))
            ((response 200 http/1.1 (("Content-Length" "11")) "hello world") ((5 accepted) (6 accepted))))
          running-counts)
    (let* ((results (make-vector 2 'never-ran))
           (submitter (lambda (i)
                        (lambda ()
                          (vector-set! results i (run (request (url-of o 'raw "/raw/pause-mid-body?ms=600")))))))
           (threads (list (fork-thread (submitter 0)) (fork-thread (submitter 1))))
           (most (let watch ((most 0) (deadline (+ (now-ms) 20000)))
                   (if (or (> (now-ms) deadline)
                           (for-all (lambda (r) (not (eq? r 'never-ran))) (vector->list results)))
                       most
                       (let ((now-live (curl-engine-live-count engine)))
                         (pause-ms 5)
                         (watch (max most now-live) deadline))))))
      (for-each thread-join threads)
      (list (if (= most 2) 'overlapped (list 'most-live most))
            (vector->list results)
            (native-counts))))

  ;; --- the lock: a drip beside a thread that collects every 2 ms. The
  ;; engine's thread waits in its __collect_safe poll between chunks, so the
  ;; collector runs between the callable's calls. Without lock-object a
  ;; collection moves the callable's code, and libcurl calls where it was
  ;; (plan, section 5.1.1). The positive evidence: collections made while
  ;; the engine's table held the transfer, more than its connect and the
  ;; 10 ms before its first byte leave room for.
  (test-equal "the lock: a 50-byte drip, 10 ms apart, beside a thread that collects every 2 ms: the whole body, every chunk accepted on the engine's thread, ten collections or more while it was live, and the counts back to the engine's alone"
    (list (list (list 'response 200 'http/1.1 '(("Content-Length" "50"))
                      "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwx")
                '(50 none))
          'collected-while-live running-counts)
    (let* ((stop #f)
           (while-live 0)
           (collector (fork-thread
                       (lambda ()
                         (let loop ()
                           (unless stop
                             (make-bytevector 20000 1)
                             (collect-rendezvous)
                             (when (> (curl-engine-live-count engine) 0) (set! while-live (+ while-live 1)))
                             (pause-ms 2)
                             (loop))))))
           (r (run (request (url-of o 'raw "/raw/drip?bytes=50&gap=10")))))
      (set! stop #t)
      (thread-join collector)
      (list (list (car r) (log-shape (cadr r)))
            (if (>= while-live 10) 'collected-while-live (list 'collections-while-live while-live))
            (native-counts)))))

(define scenarios-outcome
  (guard (e (#t (list 'raised (describe e))))
    (call-with-origin (lambda (o) (scenarios o) 'done))))

(test-equal "the scenarios' origin starts, serves them all, and stops"
  'done
  scenarios-outcome)

(test-equal "once every transfer has ended, the live-transfer table and the engine's are empty, and the transfer count zero"
  '(0 0 0)
  (list (live-transfer-count) (if engine-made? (curl-engine-live-count engine) engine)
        (cdr (assq 'transfer (native-counts)))))

;; The engine stops before the suite ends: suite-exit-status fails a suite
;; whose counts are not all zero at its end, and the engine's multi handle
;; is counted until its stop.
(test-equal "the suite's engine stops, and every count is zero after"
  (list 'stopped 0 zero-counts 0)
  (if engine-made?
      (begin (curl-engine-stop engine)
             (list (curl-engine-state engine) (curl-engine-live-count engine) (native-counts)
                   (live-transfer-count)))
      engine))

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

(test-equal "it holds rows for 7.85.0, 8.5.0 and 8.20.0, the libcurls the lanes run, and 8.7.1, Apple's"
  '("7.85.0" "8.5.0" "8.7.1" "8.20.0")
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

(test-equal "the loaded libcurl's version has exactly one row in tests/known-transfer-verdicts.sexp"
  (list version)
  (map row-version matches))

(test-end "transfer")

(exit (suite-exit-status runner))
