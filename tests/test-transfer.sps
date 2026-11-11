#!r6rs
;;; The suite for (curl private transfer): a request, submitted to an
;;; engine and awaited, against the test origin's plaintext faces. Every
;;; transfer runs on the suite's one engine, made near the top.
;;;
;;; Every scenario is asserted whole: the status, the HTTP version, every
;;; header in libcurl's order, and the body, or the &curl-transfer-error's
;;; reason and CURLcode, with the native counts after it, which must be the
;;; engine's multi handle alone, refusals included; once the engine has
;;; stopped, at the end, all zero. curl's verdicts vary by version, so, as
;;; test-url does:
;;;
;;;   - shared answers hold what every recorded libcurl answers, 7.85.0,
;;;     8.5.0 (OpenSSL and GnuTLS) and 8.20.0, measured through C, and
;;;     Apple's 8.7.1, through this suite on macOS;
;;;   - tests/known-transfer-verdicts.sexp holds a row per libcurl version
;;;     for the scenarios that vary. A libcurl with no row fails, and the
;;;     suite prints the row it would need on the error port.
;;;
;;; Each answer that raises a &curl-transfer-error, a shared answer's, this
;;; libcurl's row's or a test's own, is also asserted of its class
;;; (ADR-0022): the rows stay codes, and the suite derives each one's class
;;; through a table of its own, code-classes, and the rule for reasons
;;; written out beside it, then asserts the raised condition is of that
;;; class, by the six predicates, and of no other. A cancelled and a stopped
;;; transfer, and a refusal while a transfer was set up, are of none.
;;;
;;; Then what the binding itself does:
;;;
;;;   - the setopt bindings, each observed in a transfer (ADR-0001's FFI
;;;     test): a string, USERAGENT, arrives as Latin-1 bytes; longs,
;;;     TIMEOUT_MS and NOBODY; an off_t, MAXFILESIZE_LARGE;
;;;   - header strings are Latin-1 both ways (ADR-0001): every byte 0x01 to
;;;     0xFF but CR and LF, sent and read;
;;;   - the request's refusals, each reason at every position of a value,
;;;     the name rule against the whole complement of tchar from U+0000 to
;;;     U+00FF and beyond, and nothing native made at the raise;
;;;   - the body limit at its edges, with MAXFILESIZE_LARGE at the limit
;;;     plus one, and what the callable accepted, read from the chunk log
;;;     write-body keeps on the token;
;;;   - a raise inside the callable, planted as data by a request's fault,
;;;     recorded by the transfer;
;;;   - two threads submitting to the one engine at once, with positive
;;;     evidence their transfers were live together;
;;;   - the lock: a drip beside a thread that collects every 2 ms;
;;;   - the option table and its bindings, written out here, since on
;;;     x86-64 a long sent through the off_t binding arrives all the same;
;;;     the field table and the record's fields, written out too;
;;;   - the hatch's settings as the engine sets them (ADR-0009): a setopt
;;;     libcurl refuses, through each integer binding, and the option
;;;     cache's own copy of a name; option-named's refusal of a name the
;;;     libcurl does not know. The hatch's own rules are test-unsupported's.
;;;     Through the private follow field, curl-request-following, the last
;;;     request's headers after a redirect followed, and the redirect pin
;;;     observed;
;;;   - the request's snapshot, taken at submit: a request changed after it
;;;     was made is refused there, in prepare-transfer's order, and a value
;;;     another thread changes is sent whole or refused, never otherwise;
;;;   - a mutex held across an asynchronous escape: sweeps of the calls
;;;     that take transfer.sls's mutexes, of a refused attach, and of a
;;;     refused submit;
;;;   - framing headers, Content-Length and Transfer-Encoding, refused;
;;;   - hermetic: no proxy variable is set;
;;;   - the proxy field, in a child, tests/transfer-proxy.sps, given
;;;     http_proxy or all_proxy at the http face, which stands in for the
;;;     proxy, through its command alone, no_proxy and NO_PROXY cleared:
;;;     environment goes through it, #f direct, judged by the target the
;;;     face's /echo saw (ADR-0024);
;;;   - the native objects' lifetimes: the counts while a transfer is live,
;;;     and, read from transfer.sls as data, set-transfer-options!' order,
;;;     start-transfer!'s making order against free-transfer!'s freeing
;;;     order, and prepare-transfer's checks, since libcurl 8.20.0's cleanup
;;;     reads none of the objects a wrong order would free first.
;;;
;;; The engine's thread runs no caller code, sets no timer and gets no
;;; Ctrl-C (ADR-0013).
;;;
;;; Importing (curl) runs the load before this suite's first line, on this
;;; thread: a first reference from a second thread during the load would
;;; raise cyclic dependency (ADR-0002). The suite's top level also reaches
;;; (curl private transfer), then makes its engine, before any other thread
;;; is forked. Every expected value is one the code under test cannot
;;; produce by failing: SRFI-64 makes #f of a raise in the actual
;;; expression, so none is #f.
(import (rnrs)
        (srfi :64)
        (rnrs mutable-strings)
        (rnrs mutable-pairs)
        (only (chezscheme) fork-thread thread-join make-mutex with-mutex collect-rendezvous
              sleep make-time current-time time-second time-nanosecond getenv get-thread-id
              library-directories)
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
        (only (chezscheme) make-engine))

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
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)))

;; running-counts : (Listof (Pairof Symbol Natural))
;; The counts while the suite's engine runs and no transfer is live: its
;; multi handle and its slot, a counted block it holds while it runs, and
;; nothing else.
(define running-counts
  '((block . 1) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 1) (share . 0) (mime . 0)))

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
;; headers, user-agent, timeout, limit, ca-file, verify, fault; a fault is
;; set by the private curl-request-with-fault.
(define (request target . options)
  (let* ((given (lambda (key default)
                  (let ((at (memq key options))) (if at (cadr at) default))))
         (r (make-curl-request target 'method (given 'method 'get) 'headers (given 'headers '())
                               'user-agent (given 'user-agent #f)
                               'timeout-ms (given 'timeout default-timeout)
                               'body-limit (given 'limit #f) 'ca-file (given 'ca-file #f)
                               'verify (given 'verify #t))))
    (if (given 'fault #f) (curl-request-with-fault r (given 'fault #f)) r)))

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
(define (perform r) (await-token (curl-submit engine r)))

;; perform-with : Request (Listof (Pairof String Any)) -> Response
;; perform's, of R with OPTIONS attached through the hatch.
(define (perform-with r options) (perform (curl-request-with-options r options)))

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
      (list 'response (curl-response-status r) (curl-response-http-version r)
            (map (lambda (h) (list (car h) (cdr h))) (curl-response-headers r))
            (latin-1 (curl-response-body r))))))

;; --- the classes (ADR-0022), by the suite's own table ------------------------------------

;; code-classes : (Listof (Pairof Natural Symbol))
;; Each CURLcode a transfer in this suite answers, in a shared answer, a
;; version row of any libcurl, or a test's own, with the class ADR-0022
;; gives it, none for a code no class names: written out here, never read
;; from the library, whose table is the thing checked. A perform-failed code
;; with no row here is (no-row CODE), which no raise matches.
(define code-classes
  '((1 . protocol)        ; CURLE_UNSUPPORTED_PROTOCOL: bad-status-line, http09, the redirect pin, bad-status-code to 8.7.1
    (8 . protocol)        ; CURLE_WEIRD_SERVER_REPLY: header-no-colon, nul-in-header, conflicting-content-length from 8.20.0
    (18 . send-receive)   ; CURLE_PARTIAL_FILE: short-body
    (23 . none)           ; CURLE_WRITE_ERROR: the callable's answer, for body-limit, header-limit and callback-raised
    (27 . none)           ; CURLE_OUT_OF_MEMORY: big-header past CURL_MAX_HTTP_HEADER on 7.85.0 and 8.5.0
    (28 . timeout)        ; CURLE_OPERATION_TIMEDOUT: TIMEOUT_MS
    (43 . none)           ; CURLE_BAD_FUNCTION_ARGUMENT: setopt-failed
    (52 . send-receive)   ; CURLE_GOT_NOTHING: close-before-response
    (56 . send-receive)   ; CURLE_RECV_ERROR: the resets, bad-chunk-size
    (63 . too-large)      ; CURLE_FILESIZE_EXCEEDED: MAXFILESIZE_LARGE below a Content-Length
    (100 . too-large)))   ; CURLE_TOO_LARGE: big-header from 8.7.1

;; table-class : Symbol (U Integer #f) -> Any
;; The class a failure of REASON and CODE is raised as, by the suite's
;; table and ADR-0022's rule for reasons, written out: body-limit and
;; header-limit, too-large, whatever its code (ADR-0040); perform-failed,
;; its code's row in code-classes, or (no-row CODE); every other reason,
;; none.
(define (table-class reason code)
  (case reason
    ((body-limit header-limit) 'too-large)
    ((perform-failed) (let ((row (assv code code-classes))) (if row (cdr row) (list 'no-row code))))
    (else 'none)))

;; class-predicates : (Listof (Pairof Symbol (Any -> Boolean)))
;; Each class, by its name in code-classes, with its predicate.
(define class-predicates
  (list (cons 'timeout curl-timeout?) (cons 'connect curl-connect-error?)
        (cons 'send-receive curl-send-receive-error?) (cons 'tls curl-tls-error?)
        (cons 'protocol curl-protocol-error?) (cons 'too-large curl-too-large?)))

;; class-of : Any -> Any
;; The class E was raised as, by the six predicates: the name of the one
;; that holds; none when none holds; (several CLASS ...) when more than one
;; does.
(define (class-of e)
  (let ((held (map car (filter (lambda (p) ((cdr p) e)) class-predicates))))
    (cond ((null? held) 'none)
          ((null? (cdr held)) (car held))
          (else (cons 'several held)))))

;; classing : &curl-transfer-error -> (List Symbol (U Integer #f) Any)
;; E as (REASON CODE CLASS), CLASS by class-of.
(define (classing e)
  (list (curl-transfer-error-reason e) (curl-transfer-error-code e) (class-of e)))

;; refused-answer? : Any -> Boolean
;; ANSWER is (refused REASON CODE ...): a &curl-transfer-error's.
(define (refused-answer? answer)
  (and (list? answer) (>= (length answer) 3) (eq? (car answer) 'refused)))

;; expected-classing : Answer -> Any
;; What a transfer that answers ANSWER raises, by the suite's table:
;; (REASON CODE CLASS) for (refused REASON CODE ...), CLASS table-class's;
;; no-transfer-error for any other answer.
(define (expected-classing answer)
  (if (refused-answer? answer)
      (list (cadr answer) (caddr answer) (table-class (cadr answer) (caddr answer)))
      'no-transfer-error))

;; classed : ((-> Any) -> Any) (-> Any) -> (List Any Any)
;; What NAME-ANSWER, answer-of or error-text-of, names THUNK's answer, and
;; what THUNK raised: its classing for a &curl-transfer-error, raised on to
;; NAME-ANSWER; no-transfer-error for anything else, or nothing.
(define (classed name-answer thunk)
  (let* ((seen 'no-transfer-error)
         (answer (name-answer
                  (lambda ()
                    (guard (e ((curl-transfer-error? e) (set! seen (classing e)) (raise e)))
                      (thunk))))))
    (list answer seen)))

;; class-text : String Case Answer -> String
;; The name of the check that CASE, answering ANSWER, a refusal, raises
;; the class the suite's table gives it, WHERE saying whose answer it is.
(define (class-text where a-case answer)
  (string-append "class, " where ": " (case-text a-case) " raises " (written (cadr answer)) " "
                 (written (caddr answer)) ", as the class the suite's table gives it, "
                 (written (table-class (cadr answer) (caddr answer))) ", and no other"))

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

;; run-classed : Request -> (List Answer Any Any)
;; What R answers through the suite's engine, as answer-of names it, its
;; token's log, by log-of, and what it raised, as classed names it;
;; refused-at-submit for the log and the classing of a submit that raised.
(define (run-classed r)
  (let ((token (guard (e (#t (cons 'raised-at-submit e))) (curl-submit engine r))))
    (if (curl-token? token)
        (let ((answered (classed answer-of (lambda () (await-token token)))))
          (list (car answered) (log-of token) (cadr answered)))
        (list (answer-of (lambda () (raise (cdr token)))) 'refused-at-submit 'refused-at-submit))))

;; run : Request -> (List Answer Any)
;; run-classed's answer and log.
(define (run r)
  (let ((answered (run-classed r)))
    (list (car answered) (cadr answered))))

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

;; case-classed : Origin Case -> (List Answer Any)
;; What CASE answers against O, through perform: for (get FACE PATH), what
;; answer-of names; for (error-text FACE PATH), what error-text-of does;
;; and what it raised, as classed names it.
(define (case-classed o a-case)
  (let ((thunk (lambda () (perform (request (url-of o (cadr a-case) (caddr a-case)))))))
    (classed (if (eq? (car a-case) 'error-text) error-text-of answer-of) thunk)))

;; error-text-of : (-> Any) -> Any
;; The error buffer of THUNK's &curl-transfer-error, as (error-text TEXT);
;; (no-raise) when it raised nothing; (raised TEXT) for anything else.
(define (error-text-of thunk)
  (guard (e ((curl-transfer-error? e) (list 'error-text (curl-transfer-error-error-buffer e)))
            (#t (list 'raised (describe e))))
    (thunk)
    '(no-raise)))

;; case-text : Case -> String
(define (case-text a-case)
  (string-append (if (eq? (car a-case) 'error-text) "the error buffer of GET " "GET ")
                 (symbol->string (cadr a-case)) " " (caddr a-case)))

;; --- the shared answers ------------------------------------------------------------------

(define ok "status 200\n")

;; shared-answers : (Listof (List Case Answer))
;; Every plaintext scenario all four recorded libcurls answer alike: the
;; http face's routes, every raw script with the parameters the C
;; measurements used. A redirect is not followed.
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
;; The scenarios whose answers vary by version, in the order every row answers
;; them: big-header at both sizes past CURL_MAX_HTTP_HEADER, bad-status-code
;; and conflicting-content-length. many-headers at 50,000 would vary too,
;; but the cap on response headers makes it header-limit on every libcurl
;; (ADR-0040): it is a cap test, with big-header at the cap's edge.
;; A fifth scenario, MAXFILESIZE_LARGE set alone, is not reachable: the hatch
;; refuses it, a request field's option (ADR-0009). Then a text:
;; nul-in-header's error buffer, which 8.23.0 capitalised (ADR-0020).
(define varying-cases
  '((get raw "/raw/big-header?bytes=102400")
    (get raw "/raw/big-header?bytes=1048576")
    (get raw "/raw/bad-status-code")
    (get raw "/raw/conflicting-content-length")
    (error-text raw "/raw/nul-in-header")))

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

;; text-answer-shaped? : Any -> Boolean
;; (error-text TEXT), TEXT a string.
(define (text-answer-shaped? x)
  (and (list? x) (= (length x) 2) (eq? (car x) 'error-text) (string? (cadr x))))

;; case-shaped? : Any -> Boolean
;; (get FACE PATH) or (error-text FACE PATH), FACE http or raw.
(define (case-shaped? x)
  (and (list? x)
       (= (length x) 3)
       (memq (car x) '(get error-text))
       (memq (cadr x) '(http raw))
       (string? (caddr x))
       #t))

;; fits? : Case Any -> Boolean
;; Whether ANSWER is the shape CASE's kind answers: a get's, by
;; answer-shaped?; an error-text's, by text-answer-shaped?.
(define (fits? a-case answer)
  (if (eq? (car a-case) 'error-text)
      (text-answer-shaped? answer)
      (answer-shaped? answer)))

;; row-problem : Any -> (U 'ok (Listof Any))
;; ok when ROW is (libcurl (where S) (version S) (answers (CASE ANSWER) ...)),
;; each CASE well formed and each ANSWER the shape its CASE's kind answers;
;; else what is wrong. Total.
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
                       (case-shaped? (car pair)) (fits? (car pair) (cadr pair)))))
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
;; What THUNK raised: (request-refused FIELD VALUE REASON), (url-refused
;; REASON), (transfer-refused REASON OPTION REQUEST-SIZE), or
;; (assertion-violation WHO); the native counts at the raise, read by a
;; handler before any dynamic-wind's after thunk; and the counts after.
;; no-raise when nothing was raised: a token THUNK answered, a submit not
;; refused, is settled first.
(define (refusal thunk)
  (let* ((seen 'no-raise)
         (r (guard (e ((curl-request-error? e)
                       (list 'request-refused (curl-request-error-field e)
                             (curl-request-error-value e) (curl-request-error-reason e)))
                      ((curl-url-error? e) (list 'url-refused (curl-url-error-reason e)))
                      ((curl-transfer-error? e)
                       (list 'transfer-refused (curl-transfer-error-reason e)
                             (curl-transfer-error-option e) (curl-transfer-error-request-size e)))
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
  (lambda () (make-curl-request "http://127.0.0.1:1/" 'headers (list (cons name value)))))

;; agent-request : String -> (-> Request)
(define (agent-request agent)
  (lambda () (make-curl-request "http://127.0.0.1:1/" 'user-agent agent)))

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
;; name. This suite runs with none.
(define proxy-variables '("http_proxy" "HTTP_PROXY" "https_proxy" "HTTPS_PROXY" "all_proxy" "ALL_PROXY"))

(test-equal "hermetic: none of http_proxy, HTTP_PROXY, https_proxy, HTTPS_PROXY, all_proxy and ALL_PROXY is set, or libcurl would send this suite's transfers to it"
  '()
  (filter (lambda (name) (getenv name)) proxy-variables))

;; --- the proxy field's child: tests/transfer-proxy.sps ----------------------------------

;; library-path : -> String
;; This suite's library path, as --libdirs takes it.
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

;; child-script : String
;; sh -c CHILD-SCRIPT sh COMMAND...: COMMAND, with stdin at its end, under
;; GNU timeout (gtimeout on macOS), killed with SIGKILL after 60 s, exit
;; 137; with neither found, exit 125, saying so. The shell's own stderr is
;; /dev/null, so dash's "Killed" is not the command's, as in
;; (curl-testing)'s bounded-script.
(define child-script
  (string-append
   "t=$(command -v timeout || command -v gtimeout) || { echo 'transfer-proxy: no timeout' >&2; exit 125; }\n"
   "exec 3>&2 2>/dev/null\n"
   "( exec \"$t\" -s KILL 60 \"$@\" </dev/null 2>&3 3>&- )\n"
   "exit $?\n"))

;; proxy-child : (Listof String) String String -> (U (List Integer (Listof Any) String) (List 'raised String))
;; tests/transfer-proxy.sps on URL with the proxy field PROXY, environment
;; or none, in a child Chez under child-script, with no_proxy and NO_PROXY
;; cleared and ASSIGNMENTS, each NAME=VALUE, in its environment alone, set
;; by env in its command: its exit status, what it printed, read as data,
;; and its stderr.
(define (proxy-child assignments url proxy)
  (guard (e (#t (list 'raised (describe e))))
    (let ((r (capture-command (append (list "sh" "-c" child-script "sh" "env" "-u" "no_proxy" "-u" "NO_PROXY")
                                      assignments
                                      (list (getenv "CHEZ") "--libdirs" (library-path)
                                            "--program" "tests/transfer-proxy.sps" url proxy)))))
      (list (car r) (read-all (cadr r)) (caddr r)))))

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
                                (symbol->string reason) ", naming header-value and the header's name, never the value, which can be a secret, with nothing native at the raise")
       (map (lambda (value) (list (list 'request-refused 'header-value "X-Value" reason) running-counts running-counts))
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
(test-equal "a value's first offending char decides its reason, each way round, for a header value, named by its header's name, and a user agent"
  (let ((pairs '(("a\x0;\rb" embedded-nul) ("a\r\x0;b" line-break) ("a\x100;\nb" not-latin-1)
                 ("a\n\x100;b" line-break) ("a\x0;\x100;" embedded-nul) ("\x100;\x0;" not-latin-1))))
    (append (map (lambda (p) (list 'request-refused 'header-value "X-Value" (cadr p))) pairs)
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
       (append (map (lambda (v) (list (list 'request-refused 'header-value "X-Value" 'surrounding-whitespace)
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
  '((request-refused header-value "X-Value" line-break)
    (request-refused header-value "X-Value" embedded-nul)
    (request-refused header-value "X-Value" not-latin-1)
    (request-refused user-agent "\ta\n" line-break))
  (list (car (refusal (header-request "X-Value" " a\r")))
        (car (refusal (header-request "X-Value" "\x0; ")))
        (car (refusal (header-request "X-Value" " \x100;")))
        (car (refusal (agent-request "\ta\n")))))

(test-equal "an empty user agent is an assertion violation from make-curl-request: a user agent is a non-empty string or #f"
  (list '(assertion-violation make-curl-request) running-counts running-counts)
  (refusal (agent-request "")))

(test-equal "a header named User-Agent, in any case, beside a user agent, is refused as duplicates-field, naming header-name: libcurl would let the header win; with no user agent, or another name, it is a header like any other"
  '((request-refused header-name "User-Agent" duplicates-field)
    (request-refused header-name "user-agent" duplicates-field)
    (request-refused header-name "USER-AGENT" duplicates-field)
    (request-refused header-name "uSeR-aGeNt" duplicates-field)
    no-raise no-raise)
  (append
   (map (lambda (name)
          (car (refusal (lambda () (make-curl-request "http://127.0.0.1:1/" 'headers (list (cons name "x"))
                                                      'user-agent "agent")))))
        '("User-Agent" "user-agent" "USER-AGENT" "uSeR-aGeNt"))
   (list (car (refusal (lambda () (make-curl-request "http://127.0.0.1:1/" 'headers '(("User-Agent" . "x"))))))
         (car (refusal (lambda () (make-curl-request "http://127.0.0.1:1/" 'headers '(("User-Agents" . "x"))
                                                     'user-agent "agent")))))))

(test-equal "a second Host header, in any case, is refused as duplicates-field, naming it: libcurl sends only the first, and RFC 9112 has a server answer 400 to two; one Host is a header like any other"
  '((request-refused header-name "Host" duplicates-field)
    (request-refused header-name "HOST" duplicates-field)
    (request-refused header-name "host" duplicates-field)
    no-raise)
  (map (lambda (headers)
         (car (refusal (lambda () (make-curl-request "http://127.0.0.1:1/" 'headers headers)))))
       '((("Host" . "a.example") ("Host" . "b.example"))
         (("host" . "a.example") ("X-B" . "2") ("HOST" . "c.example"))
         (("Host" . "a.example") ("host" . "b.example"))
         (("X-A" . "1") ("host" . "a.example")))))

(test-equal "a header named Content-Length or Transfer-Encoding, in any case, is refused as framing-header, naming it: libcurl frames the message, from the body it is handed, and a header that framed it otherwise would have a server wait, or read past it; Content-Type, TE, X-Content-Length and Transfer-Encodings are headers like any other"
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
         (car (refusal (lambda () (make-curl-request "http://127.0.0.1:1/"
                                                     'headers (list (cons "X-A" "1") (cons name "0")))))))
       '("Content-Length" "content-length" "CONTENT-LENGTH" "cOnTeNt-LeNgTh"
         "Transfer-Encoding" "transfer-encoding" "TRANSFER-ENCODING" "tRaNsFeR-eNcOdInG"
         "Content-Type" "TE" "X-Content-Length" "Transfer-Encodings")))

(test-equal "a request whose header name becomes Content-Length, or Transfer-Encoding, after it was made is refused as framing-header at submit, before anything native"
  (list '(request-refused header-name framing-header) '(request-refused header-name framing-header) running-counts)
  (let* ((changed (lambda (spelt at char)
                    (let* ((name (string-copy spelt))
                           (r (make-curl-request "http://127.0.0.1:1/" 'headers (list (cons name "0")))))
                      (string-set! name at char)
                      (submitted (lambda () (curl-submit engine r))))))
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
         (r (make-curl-request url 'headers headers 'user-agent agent)))
    (change url name value header headers agent other)
    (refusal (lambda () (curl-submit engine r)))))

(test-equal "a request changed after it was made is refused at submit, at each field, before anything native: the URL, a header's name, its value, CR LF that would inject a header, the user agent, the list, a pair's car and cdr, the second header's value, and the list's or a name's type"
  (map (lambda (r) (list r running-counts running-counts))
       '((url-refused embedded-nul)
         (request-refused header-name "X:Name" not-a-token)
         (request-refused header-value "X-Name" line-break)
         (request-refused header-value "X-Name" line-break)
         (request-refused user-agent "an\nagent" line-break)
         (request-refused header-name "X:" not-a-token)
         (request-refused header-name "X Y" not-a-token)
         (request-refused header-value "X-Name" surrounding-whitespace)
         (request-refused header-value "X-Other" not-latin-1)
         (assertion-violation curl-submit)
         (assertion-violation curl-submit)))
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

;; A submit checks a request in prepare-transfer's order: the snapshot of the
;; headers and the user agent, the CA file's copy, then the URL, parsed and
;; its scheme checked. Each row makes its field wrong and every field checked
;; after it, so a check out of order, or one left to the engine's thread,
;; names another answer. The hatch's options were checked as they were
;; attached, and are private copies: a submit has nothing of theirs to check
;; (ADR-0009). The URL's parse runs in a critical section of its own, its
;; refusal answered as data and raised once the section has ended (ADR-0025):
;; the CURLU, which the parse makes on this thread, is freed by then, so the
;; caller's handler counts none, where a handler run inside the parse would
;; count one.
(test-equal "a submit checks in prepare-transfer's order, each refusal raised at submit: a header, while the CA file and the URL are wrong too; the CA file, while the URL is, each before anything native; then the URL, parsed on this thread, in a section of its own, its CURLU freed before its refusal is raised"
  (list (list '(request-refused header-name "X Name" not-a-token) running-counts running-counts)
        (list '(request-refused ca-file "/x/c\x0;.pem" embedded-nul) running-counts running-counts)
        (list '(url-refused scheme-not-http) running-counts running-counts))
  (map (lambda (wrong)
         (let* ((name (string-copy "X-Name"))
                (path (string-copy "/x/ca.pem"))
                (r (make-curl-request (if (memq 'url wrong) "ftp://127.0.0.1:1/x" "http://127.0.0.1:1/x")
                                      'headers (list (cons name "v")) 'ca-file path)))
           (when (memq 'header wrong) (string-set! name 1 #\space))
           (when (memq 'ca-file wrong) (string-set! path 4 #\nul))
           (refusal (lambda () (curl-submit engine r)))))
       '((header ca-file url) (ca-file url) (url))))

;; curl-request-check runs request-checks, the submit's own (ADR-0023). Each
;; row makes one request wrong, after its constructor's check where the field
;; allows it, and both the check and a submit are given that same request:
;; what each raised is compared whole, its type, field, value, reason, input,
;; code, message and irritants, but for its who, which is curl-request-check
;; where a submit's is curl-submit. A refusal that names no who of its own, a
;; URL's, names chez-curl in both.

;; raised-fields : (-> Any) -> (U 'no-raise (Listof Any))
;; What THUNK raised, as data: whether it is a request error, a URL error
;; and an assertion violation; the request error's field, value and reason;
;; the URL error's input, reason, code and message; then the message, the
;; irritants and the who.
(define (raised-fields thunk)
  (guard (e ((condition? e)
             (list (curl-request-error? e) (curl-url-error? e) (assertion-violation? e)
                   (and (curl-request-error? e)
                        (list (curl-request-error-field e) (curl-request-error-value e)
                              (curl-request-error-reason e)))
                   (and (curl-url-error? e)
                        (list (curl-url-error-input e) (curl-url-error-reason e) (curl-url-error-code e)
                              (curl-url-error-message e)))
                   (and (message-condition? e) (condition-message e))
                   (and (irritants-condition? e) (condition-irritants e))
                   (and (who-condition? e) (condition-who e))))
            (#t (list 'non-condition e)))
    (thunk)
    'no-raise))

;; as-checked : (Listof Any) -> (Listof Any)
;; A submit's raised-fields with its who curl-submit read as the check's.
(define (as-checked fields)
  (if (and (pair? fields) (= (length fields) 8) (eq? (list-ref fields 7) 'curl-submit))
      (append (reverse (cdr (reverse fields))) '(curl-request-check))
      fields))

;; check-rows : (Listof (List Symbol (-> Any)))
;; Each a name, and a maker of the wrong request, or of a thing no request.
(define check-rows
  (list (list 'not-a-token
              (lambda () (let* ((name (string-copy "X-Name"))
                                (r (make-curl-request "http://127.0.0.1:1/x" 'headers (list (cons name "v")))))
                           (string-set! name 1 #\space) r)))
        (list 'line-break
              (lambda () (let* ((agent (string-copy "an-agent"))
                                (r (make-curl-request "http://127.0.0.1:1/x" 'user-agent agent)))
                           (string-set! agent 2 #\newline) r)))
        (list 'ca-file-embedded-nul
              (lambda () (let* ((path (string-copy "/x/ca.pem"))
                                (r (make-curl-request "http://127.0.0.1:1/x" 'ca-file path)))
                           (string-set! path 4 #\nul) r)))
        (list 'pkcs11-url
              (lambda () (let* ((path (string-copy "/x/ca.pem"))
                                (r (make-curl-request "http://127.0.0.1:1/x" 'ca-file path)))
                           (let loop ((i 0))
                             (when (< i 7)
                               (string-set! path i (string-ref "PKCS11:" i))
                               (loop (+ i 1))))
                           r)))
        (list 'scheme-not-http (lambda () (make-curl-request "ftp://127.0.0.1:1/x")))
        (list 'bad-port-number (lambda () (make-curl-request "http://127.0.0.1:99999/x")))
        (list 'url-embedded-nul
              (lambda () (let* ((url (string-copy "http://127.0.0.1:1/x"))
                                (r (make-curl-request url)))
                           (string-set! url 7 #\nul) r)))
        (list 'headers-improper
              (lambda () (let* ((headers (list (cons "X-A" "1") (cons "X-B" "2")))
                                (r (make-curl-request "http://127.0.0.1:1/x" 'headers headers)))
                           (set-cdr! (cdr headers) 'tail) r)))
        (list 'not-a-request (lambda () 'not-a-request))))

(test-equal "curl-request-check refuses what a submit refuses, each refusal whole but its who, curl-request-check for curl-submit: a header's name, the user agent, the CA file's NUL and its pkcs11: prefix, the URL's scheme, its port and its NUL, an improper header list, and no request; nothing native at the raise or after, and the submit queued nothing"
  (append (map (lambda (row) (list (car row) 'alike)) check-rows)
          (list (list running-counts 0)))
  (let* ((started (transfers-started))
         (rows (let loop ((rest check-rows) (done '()))
                 (if (null? rest)
                     (reverse done)
                     (let* ((row (car rest))
                            (r ((cadr row)))
                            (checked (raised-fields (lambda () (curl-request-check r))))
                            (submitted (raised-fields (lambda () (curl-submit engine r)))))
                       (loop (cdr rest)
                             (cons (list (car row)
                                         (if (and (pair? checked) (equal? checked (as-checked submitted)))
                                             'alike
                                             (list 'checked checked 'submitted submitted)))
                                   done)))))))
    (append rows (list (list (native-counts) (- (transfers-started) started))))))

(test-equal "curl-request-check of a request every check takes returns, leaves nothing native, the CURLU it parses freed, starts no transfer and queues nothing on any engine: the engine's queue stays empty, and the request, submitted after, runs"
  (list 'returned running-counts 0 0 '(refused perform-failed 7))
  (let* ((r (make-curl-request "http://127.0.0.1:1/x" 'headers '(("X-A" . "1")) 'user-agent "a/1"
                               'body (make-bytevector 16 0) 'method 'post))
         (started (transfers-started))
         (checked (guard (e (#t (list 'raised (describe e)))) (curl-request-check r) 'returned))
         (counts (native-counts))
         (made (- (transfers-started) started))
         (queued (curl-engine-queued-count engine)))
    (list checked counts made queued (answer-of (lambda () (perform r))))))

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
    (request-refused header-value "X-C" line-break)
    (request-refused user-agent "a\x0;b" embedded-nul))
  (map (lambda (args) (car (refusal (lambda () (apply make-curl-request args)))))
       (list (list "http://127.0.0.1:1/" 'headers '(("X-A" . "1") ("X-B" . "2") ("X:" . "3")))
             (list "http://127.0.0.1:1/" 'headers '(("X-A" . "1") ("X-B" . "2") ("X-C" . "a\nb")))
             (list "http://127.0.0.1:1/" 'headers '(("X-A" . "1") ("X-B" . "2")) 'user-agent "a\x0;b"))))

(test-equal "a header's name is checked before its value, and headers in order: the first header's fault is the one named"
  '((request-refused header-name "X:" not-a-token)
    (request-refused header-value "X-Ok" line-break)
    (request-refused header-name "X:" not-a-token))
  (list (car (refusal (lambda () (make-curl-request "http://127.0.0.1:1/" 'headers '(("X:" . "a\rb"))))))
        (car (refusal (lambda () (make-curl-request "http://127.0.0.1:1/"
                                                    'headers '(("X-Ok" . "a\rb") ("X:" . "v"))))))
        (car (refusal (lambda () (make-curl-request "http://127.0.0.1:1/"
                                                    'headers '(("X:" . "v")) 'user-agent "a\rb"))))))

(test-equal "wrong types are assertion violations from make-curl-request, with nothing native made: a URL, a method, headers, a user agent, a timeout and a body limit"
  (map (lambda (x) (list '(assertion-violation make-curl-request) running-counts running-counts))
       (iota-from 0 19))
  (map (lambda (args) (refusal (lambda () (apply make-curl-request args))))
       (list (list 'not-a-url)
             (list "http://a/" 'method 'options)
             (list "http://a/" 'method "get")
             (list "http://a/" 'headers 'none)
             (list "http://a/" 'headers '(("X" . 1)))
             (list "http://a/" 'headers '((x . "v")))
             (list "http://a/" 'headers '(("X" "v")))
             (list "http://a/" 'headers '(("X" . "v") . tail))
             (list "http://a/" 'user-agent 'agent)
             (list "http://a/" 'timeout-ms 0)
             (list "http://a/" 'timeout-ms -1)
             (list "http://a/" 'timeout-ms 1.5)
             (list "http://a/" 'timeout-ms (expt 2 63))
             (list "http://a/" 'timeout-ms "300")
             (list "http://a/" 'body-limit -1)
             (list "http://a/" 'body-limit 1.0)
             (list "http://a/" 'body-limit (- (expt 2 63) 1))
             (list "http://a/" 'body-limit (expt 2 63))
             (list "http://a/" 'body-limit "10"))))

(test-equal "a fault of the wrong type is an assertion violation from curl-request-with-fault, with nothing native made: a symbol, a string, 0, -1, 1.5 or a procedure, since a request holds no caller code"
  (map (lambda (x) (list '(assertion-violation curl-request-with-fault) running-counts running-counts))
       (iota-from 0 6))
  (map (lambda (fault)
         (refusal (lambda () (curl-request-with-fault (make-curl-request "http://a/") fault))))
       (list 'hook "hook" 0 -1 1.5 (lambda (chunk) chunk))))

(test-equal "the header seams' refusals, each an assertion violation from its own constructor, by its own message, with nothing native made: curl-request-with-head-mark and curl-request-with-head-fault of no request, and of a line of 0, -1, 1.5 or a symbol; beside them, each of line 1, taken"
  (append (apply append
                 (map (lambda (who)
                        (cons (list (list (list 'assertion-violation who) running-counts running-counts)
                                    (list who "not a request"))
                              (map (lambda (x)
                                     (list (list (list 'assertion-violation who) running-counts running-counts)
                                           (list who "a head's line is a positive exact integer")))
                                   (iota-from 0 4))))
                      '(curl-request-with-head-mark curl-request-with-head-fault)))
          '(no-raise no-raise))
  (append (map (lambda (args)
                 (let ((thunk (lambda () ((car args) (cadr args) (caddr args)))))
                   (list (refusal thunk)
                         (guard (e ((and (assertion-violation? e) (who-condition? e) (message-condition? e))
                                    (list (condition-who e) (condition-message e)))
                                   (#t (list 'raised (describe e))))
                           (thunk)
                           'no-raise))))
               (apply append
                      (map (lambda (make)
                             (list (list make 'not-a-request 1) (list make (make-curl-request "http://a/") 0)
                                   (list make (make-curl-request "http://a/") -1)
                                   (list make (make-curl-request "http://a/") 1.5)
                                   (list make (make-curl-request "http://a/") 'two)))
                           (list curl-request-with-head-mark curl-request-with-head-fault))))
          (list (car (refusal (lambda () (curl-request-with-head-mark (make-curl-request "http://a/") 1))))
                (car (refusal (lambda () (curl-request-with-head-fault (make-curl-request "http://a/") 1)))))))

(test-equal "a request's checks refuse a header seam's fault of a line that is no positive exact integer, (mark 0), (mark -1), (mark 1.5), (head 0), as an assertion violation from the checking constructor, through request-like as each constructor reaches them; (mark 1) and (head 1) are taken"
  (append (map (lambda (x) (list '(assertion-violation checking) running-counts running-counts)) (iota-from 0 4))
          '(no-raise no-raise))
  (append (map (lambda (fault)
                 (refusal (lambda () (request-like 'checking (make-curl-request "http://a/") '() "http://a/"
                                                   fault #f '()))))
               '((mark 0) (mark -1) (mark 1.5) (head 0)))
          (map (lambda (fault)
                 (car (refusal (lambda () (request-like 'checking (make-curl-request "http://a/") '() "http://a/"
                                                        fault #f '())))))
               '((mark 1) (head 1)))))

(test-equal "the edges a request takes: a timeout of 1 and of the largest long, a body limit of 0 and of 2^63 - 2, method head, a fault at chunk 1 and at chunk 2^70"
  '(no-raise no-raise no-raise no-raise no-raise no-raise no-raise)
  (map (lambda (thunk) (car (refusal thunk)))
       (list (lambda () (make-curl-request "http://a/" 'timeout-ms 1))
             (lambda () (make-curl-request "http://a/" 'timeout-ms (- (expt 2 63) 1)))
             (lambda () (make-curl-request "http://a/" 'body-limit 0))
             (lambda () (make-curl-request "http://a/" 'body-limit (- (expt 2 63) 2)))
             (lambda () (make-curl-request "http://a/" 'method 'head))
             (lambda () (curl-request-with-fault (make-curl-request "http://a/") 1))
             (lambda () (curl-request-with-fault (make-curl-request "http://a/") (expt 2 70))))))

(test-equal "a request's fields read back as given"
  (list "http://a/b" 'head '(("X-A" . "1") ("X-A" . "2")) "agent" 300 10 "/a/ca.pem" 'verify-off 3)
  (let ((r (curl-request-with-fault
            (make-curl-request "http://a/b" 'method 'head 'headers '(("X-A" . "1") ("X-A" . "2"))
                               'user-agent "agent" 'timeout-ms 300 'body-limit 10
                               'ca-file "/a/ca.pem" 'verify #f)
            3)))
    (list (curl-request-url r) (curl-request-method r) (curl-request-headers r)
          (curl-request-user-agent r) (curl-request-timeout-ms r)
          (curl-request-body-limit r) (curl-request-ca-file r)
          (if (eq? (curl-request-verify r) #f) 'verify-off (curl-request-verify r))
          (curl-request-fault r))))

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

;; --- the hatch's deny-list (ADR-0009) -----------------------------------------------------

(test-equal "owned-option-names, written out: the options the transfer always sets, QUICK_EXIT and MAXREDIRS among them, and the pins' bitmasks; then each request field's, a streamed body's POST and UPLOAD, its read, seek and prerequest callables and their data, and FRESH_CONNECT, a multipart body's MIMEPOST, stream-buffer's header callable and its data, HEADERFUNCTION and HEADERDATA, body-length's INFILESIZE_LARGE, http-version's HTTP_VERSION, credentials' HTTPAUTH, USERNAME, PASSWORD and XOAUTH2_BEARER, cookie-jar's SHARE and COOKIEFILE, and FOLLOWLOCATION the private follow field's; then the owned settings' twins: the timeouts' and the body limit's, the method's and the body's, the URL's PORT and REQUEST_TARGET, the body's CRLF and the response's HEADER, a multipart body's MIME_OPTIONS, owned and never set, in MIMEPOST's place among the twins, the CA file's CAINFO_BLOB and SSL_OPTIONS, and the proxy field's PRE_PROXY, PROXYPORT and PROXYTYPE; then slice 4's: TRANSFERTEXT, CRLF's twin; the URL's USERPWD, NETRC and HSTS; the proxy field's UNIX_SOCKET_PATH and ABSTRACT_UNIX_SOCKET; the headers' PROXYHEADER and HEADEROPT; and RESUME_FROM, RESUME_FROM_LARGE, COOKIEJAR, CONNECT_ONLY, DOH_URL, RESOLVE and SSLENGINE_DEFAULT, kept from the hatch; then M7 slice 1's, the HTTP version's twins SSL_ENABLE_ALPN, ALTSVC and ALTSVC_CTRL; then M7 slice 2's, the credentials' twin AWS_SIGV4; then M7 slice 3's, the proxy's twins PROXYAUTH, PROXYUSERPWD, PROXYUSERNAME, PROXYPASSWORD, HTTPPROXYTUNNEL, HAPROXYPROTOCOL and HAPROXY_CLIENT_IP; then M7 slice 4's, the cookie jar's twins COOKIE, COOKIELIST and COOKIESESSION; then M8 slice 2's, the header callable's twin SUPPRESS_CONNECT_HEADERS; then every proxy TLS option but the four proxy-ca-file and proxy-verify set, which are fields' now, as NOPROXY and FORBID_REUSE are proxy's, and COOKIEFILE cookie-jar's"
  '("URL" "PROTOCOLS_STR" "REDIR_PROTOCOLS_STR" "PROTOCOLS" "REDIR_PROTOCOLS" "NOSIGNAL" "QUICK_EXIT"
    "MAXREDIRS" "WRITEFUNCTION" "WRITEDATA" "ERRORBUFFER"
    "CURLU" "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD" "HTTPHEADER"
    "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA"
    "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT" "MIMEPOST" "USERAGENT"
    "TIMEOUT_MS" "CONNECTTIMEOUT_MS" "MAXFILESIZE_LARGE" "CAINFO" "CAPATH"
    "SSL_VERIFYPEER" "SSL_VERIFYHOST" "PROXY" "NOPROXY" "FORBID_REUSE"
    "HEADERFUNCTION" "HEADERDATA" "INFILESIZE_LARGE"
    "HTTP_VERSION" "HTTPAUTH" "USERNAME" "PASSWORD" "XOAUTH2_BEARER"
    "PROXY_CAINFO" "PROXY_CAPATH" "PROXY_SSL_VERIFYPEER" "PROXY_SSL_VERIFYHOST"
    "SHARE" "COOKIEFILE" "FOLLOWLOCATION"
    "TIMEOUT" "CONNECTTIMEOUT" "MAXFILESIZE" "HTTPGET" "PUT"
    "POSTFIELDS" "POSTFIELDSIZE" "HTTPPOST" "MIME_OPTIONS" "INFILESIZE"
    "PORT" "REQUEST_TARGET" "CRLF" "HEADER" "CAINFO_BLOB" "SSL_OPTIONS"
    "PRE_PROXY" "PROXYPORT" "PROXYTYPE"
    "TRANSFERTEXT" "USERPWD" "NETRC" "HSTS"
    "UNIX_SOCKET_PATH" "ABSTRACT_UNIX_SOCKET" "PROXYHEADER" "HEADEROPT"
    "RESUME_FROM" "RESUME_FROM_LARGE" "COOKIEJAR" "CONNECT_ONLY"
    "DOH_URL" "RESOLVE" "SSLENGINE_DEFAULT"
    "SSL_ENABLE_ALPN" "ALTSVC" "ALTSVC_CTRL"
    "AWS_SIGV4"
    "PROXYAUTH" "PROXYUSERPWD" "PROXYUSERNAME" "PROXYPASSWORD"
    "HTTPPROXYTUNNEL" "HAPROXYPROTOCOL" "HAPROXY_CLIENT_IP"
    "COOKIE" "COOKIELIST" "COOKIESESSION"
    "SUPPRESS_CONNECT_HEADERS"
    "PROXY_SSL_OPTIONS" "PROXY_SSL_CIPHER_LIST"
    "PROXY_CAINFO_BLOB" "PROXY_CRLFILE" "PROXY_ISSUERCERT"
    "PROXY_ISSUERCERT_BLOB" "PROXY_PINNEDPUBLICKEY" "PROXY_SSLVERSION" "PROXY_TLS13_CIPHERS"
    "PROXY_SSLCERT" "PROXY_SSLCERT_BLOB" "PROXY_SSLCERTTYPE" "PROXY_SSLKEY" "PROXY_SSLKEY_BLOB"
    "PROXY_SSLKEYTYPE" "PROXY_KEYPASSWD" "PROXY_TLSAUTH_TYPE" "PROXY_TLSAUTH_USERNAME"
    "PROXY_TLSAUTH_PASSWORD")
  owned-option-names)

(test-equal "request-field-options, written out: url's CURLU; method's NOBODY and CUSTOMREQUEST, and a streamed body's POST and UPLOAD; headers' HTTPHEADER; body's POSTFIELDSIZE_LARGE and COPYPOSTFIELDS, then a streamed one's READFUNCTION, READDATA, SEEKFUNCTION, SEEKDATA, PREREQFUNCTION, PREREQDATA and FRESH_CONNECT, then a multipart one's MIMEPOST; user-agent's USERAGENT; timeout-ms's TIMEOUT_MS; connect-timeout-ms's CONNECTTIMEOUT_MS; body-limit's MAXFILESIZE_LARGE; ca-file's CAINFO and CAPATH; verify's SSL_VERIFYPEER and SSL_VERIFYHOST; proxy's PROXY, NOPROXY and FORBID_REUSE; stream-buffer's HEADERFUNCTION and HEADERDATA; body-length's INFILESIZE_LARGE; http-version's HTTP_VERSION; credentials' HTTPAUTH, USERNAME, PASSWORD and XOAUTH2_BEARER; proxy-ca-file's PROXY_CAINFO and PROXY_CAPATH; proxy-verify's PROXY_SSL_VERIFYPEER and PROXY_SSL_VERIFYHOST; cookie-jar's SHARE and COOKIEFILE; and follow's FOLLOWLOCATION"
  '((url "CURLU") (method "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD") (headers "HTTPHEADER")
    (body "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA"
          "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT" "MIMEPOST")
    (user-agent "USERAGENT")
    (timeout-ms "TIMEOUT_MS") (connect-timeout-ms "CONNECTTIMEOUT_MS")
    (body-limit "MAXFILESIZE_LARGE") (ca-file "CAINFO" "CAPATH")
    (verify "SSL_VERIFYPEER" "SSL_VERIFYHOST") (proxy "PROXY" "NOPROXY" "FORBID_REUSE")
    (stream-buffer "HEADERFUNCTION" "HEADERDATA") (body-length "INFILESIZE_LARGE")
    (http-version "HTTP_VERSION") (credentials "HTTPAUTH" "USERNAME" "PASSWORD" "XOAUTH2_BEARER")
    (proxy-ca-file "PROXY_CAINFO" "PROXY_CAPATH")
    (proxy-verify "PROXY_SSL_VERIFYPEER" "PROXY_SSL_VERIFYHOST")
    (cookie-jar "SHARE" "COOKIEFILE")
    (follow "FOLLOWLOCATION"))
  request-field-options)

(test-equal "every option of every request field is an owned option, so the hatch refuses it"
  '()
  (filter (lambda (name) (not (member name owned-option-names)))
          (apply append (map cdr request-field-options))))

(test-equal "a request's fields, written out, in the record's order: url, method, headers, body, user-agent, timeout-ms, connect-timeout-ms, body-limit, ca-file, verify, proxy, stream-buffer, body-length, http-version, credentials, proxy-ca-file, proxy-verify, cookie-jar, then the private fault and follow, then the hatch's options"
  '(url method headers body user-agent timeout-ms connect-timeout-ms body-limit ca-file verify proxy stream-buffer body-length http-version credentials proxy-ca-file proxy-verify cookie-jar fault follow options)
  (guard (e (#t (list 'raised (describe e))))
    (request-field-names)))

;; The record's own fields, read from its record type: a field added later
;; needs a row, or its place here among the fields that set no option.
(test-equal "every field of a request has a row in request-field-options, but fault and the hatch's options, which set no option of their own"
  '()
  (guard (e (#t (list 'raised (describe e))))
    (filter (lambda (field) (not (or (assq field request-field-options) (memq field '(fault options)))))
            (request-field-names))))

;; --- what a transfer sets, read from transfer.sls as data -----------------------------
;; On the engine's thread, start-transfer! makes a transfer's native objects
;; and set-transfer-options! every setting its easy handle gets, in one order;
;; free-transfer! frees them the other way round. libcurl reads no setting
;; before the transfer runs, and 8.20.0's curl_easy_cleanup reads none of the
;; objects a wrong order would free first: freed first, each passed every
;; behavioural check, Valgrind's too. So the orders are read. Their limit is
;; the pins': they hold an accidental move, not a rewrite made to pass them.

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

(test-equal "pinned-options, written out: PROTOCOLS_STR and REDIR_PROTOCOLS_STR at \"http,https\", NOSIGNAL at 1, and MAXREDIRS at 30, which bounds the follows libcurl makes inside a transfer (ADR-0036, decision 8)"
  '(("PROTOCOLS_STR" . "http,https") ("REDIR_PROTOCOLS_STR" . "http,https") ("NOSIGNAL" . 1)
    ("MAXREDIRS" . 30))
  pinned-options)

(test-equal "quick-exit-pin, written out: QUICK_EXIT at 1 (ADR-0019)"
  '("QUICK_EXIT" . 1)
  quick-exit-pin)

(test-equal "pinned-settings, written out for each answer: the pins alone, or the pins and then QUICK_EXIT at 1"
  '((("PROTOCOLS_STR" . "http,https") ("REDIR_PROTOCOLS_STR" . "http,https") ("NOSIGNAL" . 1)
     ("MAXREDIRS" . 30))
    (("PROTOCOLS_STR" . "http,https") ("REDIR_PROTOCOLS_STR" . "http,https") ("NOSIGNAL" . 1)
     ("MAXREDIRS" . 30) ("QUICK_EXIT" . 1)))
  (list (pinned-settings #f) (pinned-settings #t)))

;; CURLOPT_QUICK_EXIT(3), 8.20.0: "Added in curl 7.87.0", 0x075700.
(test-equal "quick-exit-known? answers whether the loaded libcurl is 7.87.0 or later, where QUICK_EXIT came in, and curl-easy-option agrees"
  (let ((at-least (and (string? version) (>= (libcurl-info-version-number (loaded-libcurl)) #x075700))))
    (list at-least at-least))
  (list (quick-exit-known?) (and (curl-easy-option "QUICK_EXIT") #t)))

(test-equal "set-pinned-options!, read from transfer.sls, is exactly the loop that sets each of pinned-settings' answer, QUICK_EXIT among them when the engine says so and the libcurl knows it, a string through set-string-option!, a number through set-option!, then counts QUICK_EXIT once libcurl has taken it"
  '(define (set-pinned-options! easy buffer quick-exit)
     (let ((settings (pinned-settings (and quick-exit (quick-exit-known?)))))
       (for-each (lambda (pin)
                   (if (string? (cdr pin))
                       (set-string-option! easy (car pin) (cdr pin) buffer)
                       (set-option! easy (car pin) (cdr pin) buffer)))
                 settings)
       (when (member quick-exit-pin settings)
         (locked sinks-lock (lambda () (set! quick-exit-count (+ quick-exit-count 1)))))))
  (transfer-definition 'set-pinned-options!))

(test-equal "pinned-settings and quick-exit-known?, read from transfer.sls, held whole: pinned-options then quick-exit-pin, and the lookup of quick-exit-pin's name by curl-easy-option"
  '((define (pinned-settings quick-exit)
      (if quick-exit (append pinned-options (list quick-exit-pin)) pinned-options))
    (define (quick-exit-known?)
      (and (curl-easy-option (car quick-exit-pin)) #t)))
  (list (transfer-definition 'pinned-settings) (transfer-definition 'quick-exit-known?)))

;; holds? : Any Any -> Boolean
(define (holds? x datum)
  (or (equal? x datum) (and (pair? x) (or (holds? (car x) datum) (holds? (cdr x) datum)))))

;; symbol-count : Symbol Any -> Natural
(define (symbol-count name x)
  (cond ((eq? x name) 1)
        ((pair? x) (+ (symbol-count name (car x)) (symbol-count name (cdr x))))
        (else 0)))

;; definitions-naming : Symbol Any -> (Listof Symbol)
;; The name of each top-level definition in LIBRARY, a library form, whose
;; body names NAME, in order.
(define (definitions-naming name library)
  (if (and (list? library) (> (length library) 4))
      (fold-right (lambda (form found)
                    (if (and (pair? form) (eq? (car form) 'define) (pair? (cdr form))
                             (> (symbol-count name (cddr form)) 0))
                        (cons (if (pair? (cadr form)) (car (cadr form)) (cadr form)) found)
                        found))
                  '() (cddddr library))
      (list 'no-library library)))

;; A transfer that ran reports libcurl's count through ran-request-size alone,
;; which reported-request-size judges by version: #f on 8.7.0 and 8.7.1, whose
;; count is broken (ADR-0022). Only a lane on one of them shows it by
;; behaviour, and CI runs none, so the reading is held here, as data.
(test-equal "CURLINFO_REQUEST_SIZE is read in transfer.sls by ran-request-size alone, through reported-request-size; finish-transfer reads a size by ran-request-size at both its failures, and never curlinfo-request-size itself"
  '((ran-request-size) 1 2 0)
  (list (definitions-naming 'curlinfo-request-size transfer-library)
        (symbol-count 'reported-request-size (transfer-definition 'ran-request-size))
        (symbol-count 'ran-request-size (transfer-definition 'finish-transfer))
        (symbol-count 'curlinfo-request-size (transfer-definition 'finish-transfer))))

;; set-name : Any -> Any
;; NAME, as a set-option! call writes it: a string as itself; (field-option
;; 'FIELD) as FIELD's one option, from request-field-options; anything else
;; as (unread NAME).
(define (set-name name)
  (cond ((string? name) name)
        ((and (list? name) (= (length name) 2) (eq? (car name) 'field-option)
              (pair? (cadr name)) (eq? (car (cadr name)) 'quote) (pair? (cdr (cadr name)))
              (assq (cadr (cadr name)) request-field-options))
         => (lambda (row) (if (= (length row) 2) (cadr row) (list 'several row))))
        (else (list 'unread name))))

;; hatch-loop? : Any -> Boolean
;; FORM is a for-each over the plan's hatch settings, each set by
;; set-hatch-option!, with the string list start-transfer! built for it.
(define (hatch-loop? form)
  (equal? form '(for-each (lambda (setting)
                            (set-hatch-option! easy setting
                                               (let ((held (assq setting lists))) (and held (cdr held)))
                                               buffer))
                          (plan-settings plan))))

;; method-loop? : Any -> Boolean
;; FORM is a for-each over method-settings' answer for the plan's method,
;; body and body-length, whose settings it sets by (car setting).
(define (method-loop? form)
  (and (list? form) (= (length form) 3) (eq? (car form) 'for-each)
       (equal? (caddr form) '(method-settings (plan-method plan) (plan-body plan) (plan-body-length plan)))))

;; version-loop? : Any -> Boolean
;; FORM is a for-each over version-settings' answer for the plan's
;; http-version, whose settings it sets by (car setting).
(define (version-loop? form)
  (and (list? form) (= (length form) 3) (eq? (car form) 'for-each)
       (equal? (caddr form) '(version-settings (plan-http-version plan)))))

;; proxy-loop? : Any -> Boolean
;; FORM is a for-each over proxy-settings' answer for the plan's proxy,
;; proxy CA file and proxy verification, whose settings it sets by (car
;; setting).
(define (proxy-loop? form)
  (and (list? form) (= (length form) 3) (eq? (car form) 'for-each)
       (equal? (caddr form)
               '(proxy-settings (plan-proxy plan) (plan-proxy-ca-file plan) (plan-proxy-verify plan)))))

;; credentials-loop? : Any -> Boolean
;; FORM is a for-each over credentials-settings' answer for the plan's
;; credentials, whose settings it sets by (car setting).
(define (credentials-loop? form)
  (and (list? form) (= (length form) 3) (eq? (car form) 'for-each)
       (equal? (caddr form) '(credentials-settings (plan-credentials plan)))))

;; jar-loop? : Any -> Boolean
;; FORM is a for-each over jar-settings' answer for the plan's cookie jar's
;; share, whose settings it sets by (car setting).
(define (jar-loop? form)
  (and (list? form) (= (length form) 3) (eq? (car form) 'for-each)
       (equal? (caddr form) '(jar-settings (plan-share plan)))))

;; setting-order : Any -> Any
;; What each form of the definition D's body sets, in order: pins for
;; (set-pinned-options! easy buffer quick-exit); tls for (set-tls-options! easy
;; (plan-ca-file plan) (plan-verify plan) buffer); method for the loop over
;; method-settings' answer, by method-loop?; version for the loop over
;; version-settings' answer, by version-loop?; proxy for the loop over
;; proxy-settings' answer, by proxy-loop?; credentials for the loop over
;; credentials-settings' answer, by credentials-loop?; jar for the loop over
;; jar-settings' answer, by jar-loop?; hatch for the loop over the
;; hatch's settings, by hatch-loop?; else each set-option! and
;; set-string-option! call in it, by set-name; (other FORM) for a form that
;; sets nothing. D itself when it is no definition: what went wrong.
(define (setting-order d)
  (if (and (list? d) (pair? d) (eq? (car d) 'define))
      (apply append
             (map (lambda (form)
                    (cond ((equal? form '(set-pinned-options! easy buffer quick-exit)) '(pins))
                          ((equal? form '(set-tls-options! easy (plan-ca-file plan) (plan-verify plan) buffer))
                           '(tls))
                          ((method-loop? form) '(method))
                          ((version-loop? form) '(version))
                          ((proxy-loop? form) '(proxy))
                          ((credentials-loop? form) '(credentials))
                          ((jar-loop? form) '(jar))
                          ((hatch-loop? form) '(hatch))
                          (else (let ((sets (option-sets form '())))
                                  (if (null? sets)
                                      (list (list 'other form))
                                      (map (lambda (s) (set-name (car s))) sets))))))
                  (cddr d)))
      d))

(test-equal "set-transfer-options!, read from transfer.sls, form by form: the pins first, then ERRORBUFFER, CURLU, WRITEFUNCTION and WRITEDATA, then a streamed response's HEADERFUNCTION and HEADERDATA, then a streamed body's READFUNCTION, READDATA, SEEKFUNCTION, SEEKDATA, PREREQFUNCTION and PREREQDATA, then FRESH_CONNECT, a streamed body's or a tunnel's, then a tunnel's FORBID_REUSE, then the loop over method-settings' answer, then the request's HTTPHEADER, USERAGENT, TIMEOUT_MS, CONNECTTIMEOUT_MS and MAXFILESIZE_LARGE, then the loop over proxy-settings' answer, then the loop over version-settings' answer, then the loop over credentials-settings' answer, then the loop over jar-settings' answer, then set-tls-options!, then the private follow field's FOLLOWLOCATION, then, last, the loop over the hatch's settings; set-pinned-options!, set-transfer-options! and set-hatch-option! each stand twice in transfer.sls, a definition and one call"
  '((pins "ERRORBUFFER" "CURLU" "WRITEFUNCTION" "WRITEDATA" "HEADERFUNCTION" "HEADERDATA"
          "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA" "PREREQFUNCTION" "PREREQDATA"
          "FRESH_CONNECT" "FORBID_REUSE" method
          "HTTPHEADER" "USERAGENT" "TIMEOUT_MS" "CONNECTTIMEOUT_MS" "MAXFILESIZE_LARGE" proxy version
          credentials jar tls "FOLLOWLOCATION" hatch)
    2 2 2)
  (list (setting-order (transfer-definition 'set-transfer-options!))
        (symbol-count 'set-pinned-options! transfer-library)
        (symbol-count 'set-transfer-options! transfer-library)
        (symbol-count 'set-hatch-option! transfer-library)))

(test-equal "setting-order, the reader: pins, tls, the loop over method-settings' answer, the loop over version-settings', the loop over credentials-settings', the loop over jar-settings', each set's name at any depth, a field's through field-option, the hatch's loop, a form that sets nothing, a loop by (car setting), and a name it cannot read"
  '(pins "A" "USERAGENT" "B" tls method version credentials jar hatch (other (f x)) (unread (car setting)) (unread n))
  (setting-order '(define (g)
                    (set-pinned-options! easy buffer quick-exit)
                    (set-option! e "A" 1 b)
                    (when h (set-option! e (field-option 'user-agent) 1 b) (set-string-option! e "B" "x" b))
                    (set-tls-options! easy (plan-ca-file plan) (plan-verify plan) buffer)
                    (for-each (lambda (setting) (set-option! e (car setting) (cdr setting) b))
                              (method-settings (plan-method plan) (plan-body plan) (plan-body-length plan)))
                    (for-each (lambda (setting) (set-option! e (car setting) (cdr setting) b))
                              (version-settings (plan-http-version plan)))
                    (for-each (lambda (setting) (set-option! e (car setting) (cdr setting) b))
                              (credentials-settings (plan-credentials plan)))
                    (for-each (lambda (setting) (set-option! e (car setting) (cdr setting) b))
                              (jar-settings (plan-share plan)))
                    (for-each (lambda (setting)
                                (set-hatch-option! easy setting
                                                   (let ((held (assq setting lists))) (and held (cdr held)))
                                                   buffer))
                              (plan-settings plan))
                    (f x)
                    (for-each (lambda (setting) (set-option! e (car setting) (cdr setting) b)) s)
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
;; object a transfer holds, a multipart body's mime among them.
(define live-setters
  '(live-transfer-key-set! live-transfer-sink-set! live-transfer-url-set! live-transfer-buffer-set!
    live-transfer-header-list-set! live-transfer-lists-set! live-transfer-easy-set!
    live-transfer-mime-set!))

;; making-order : (Listof Symbol)
;; start-transfer!'s setters, its settings' calls and its free, as written.
(define making-order
  (symbols-in (append live-setters '(set-transfer-options! set-option! set-string-option! free-transfer!))
              (transfer-definition 'start-transfer!)))

;; freeing-order : (Listof Symbol)
;; free-transfer!'s frees and setters, as written.
(define freeing-order
  (symbols-in (append live-setters '(curl-easy-cleanup curl-mime-free curl-slist-free-all free-foreign-block!
                                     free-parsed-url! count-down!))
              (transfer-definition 'free-transfer!)))

(test-equal "start-transfer!, read from transfer.sls, records what it makes in order: free-transfer! on a raise; then the key and its sink, the CURLU, the error buffer, the header list, the hatch's string lists, then the easy handle, then a multipart body's mime, made with it; then set-transfer-options!, once, and no setting of its own"
  '(free-transfer! live-transfer-key-set! live-transfer-sink-set! live-transfer-url-set!
    live-transfer-buffer-set! live-transfer-header-list-set! live-transfer-lists-set!
    live-transfer-easy-set! live-transfer-mime-set! set-transfer-options!)
  making-order)

;; libcurl's cleanup reads nothing a transfer handed it, so a mime freed
;; before curl_easy_cleanup passes every behavioural check: the order is
;; read here. The mime, made with the easy handle, is freed after its
;; cleanup, the order libcurl's examples take, so it alone stands out of the
;; making reversed.
(test-equal "free-transfer!, read from transfer.sls, frees the other way round from start-transfer!'s making, but a multipart body's mime: the easy handle, then the mime, after curl_easy_cleanup, then the hatch's string lists, the header list, the error buffer, the CURLU, then the key, each freed before its record is cleared"
  (list '(curl-easy-cleanup live-transfer-easy-set! curl-mime-free live-transfer-mime-set!
          curl-slist-free-all live-transfer-lists-set!
          curl-slist-free-all live-transfer-header-list-set!
          free-foreign-block! live-transfer-buffer-set! free-parsed-url! live-transfer-url-set!
          count-down! live-transfer-key-set!)
        'the-making-reversed-the-mime-after-the-easy-handle)
  (list freeing-order
        (let ((made (filter (lambda (s) (memq s live-setters)) making-order))
              (freed (filter (lambda (s) (memq s live-setters)) freeing-order)))
          (if (equal? (let ((reversed (reverse (remq 'live-transfer-sink-set! made))))
                        (cons* (cadr reversed) (car reversed) (cddr reversed)))
                      freed)
              'the-making-reversed-the-mime-after-the-easy-handle
              (list 'made made 'freed freed)))))

(test-equal "prepare-transfer and curl-request-check, read from transfer.sls, share the checks' one owner, request-checks, which checks on the caller's thread in order: that it has a request, the snapshot of the headers and the user agent, the CA file's copy, the credentials' copy, the proxy CA file's copy, the Expect round, the credentials beside the headers' copies and the streams, a cookie jar beside them, then for a multipart body the loaded libcurl's mime, a Content-Type beside it, and the body's copy, its paths checked unresolved, the CA file against the environment the libcurl loaded with, a proxy URL, an https:// proxy URL against the libcurl's features, the proxy's TLS fields beside it, the proxy CA file against the environment, then the URL, parsed and its scheme checked, its user and password read beside credentials, then prior knowledge against that scheme and against a proxy URL, then TLS inside TLS, the tunnel's settings, and whether it stops the engine's multiplexing; prepare-transfer calls it as curl-submit, then copies the body, a multipart body's data from the checked copy, and makes the plan, the request's hatch settings in it as they are; curl-request-check calls it as curl-request-check, and does nothing else"
  ;; Each definition's header names it first, a symbol like the rest.
  '((request-checks curl-request? snapshot ca-file-copy credentials-copy path-copy check-expect-round
                    check-credentials multipart? check-multipart-supported check-multipart-content-type
                    multipart-paths-checked multipart-copy check-ca-environment check-proxy-url
                    check-https-proxy check-proxy-tls
                    check-ca-environment call-with-parsed-url
                    require-http-scheme check-userinfo userinfo-parts check-prior-knowledge
                    check-prior-knowledge-proxy check-tls-in-tls unshared-tunnel-settings
                    stops-multiplexing?)
    (request-checks curl-submit bytevector-copy multipart-for-plan make-plan curl-request-options)
    (curl-request-check request-checks curl-request-check))
  (let ((names '(request-checks curl-submit curl-request-check curl-request? snapshot ca-file-copy
                 checked-settings check-ca-environment call-with-parsed-url require-http-scheme
                 credentials-copy check-expect-round check-credentials check-userinfo userinfo-parts
                 check-prior-knowledge bytevector-copy make-plan curl-request-options curl-submit-queue
                 path-copy check-proxy-url check-https-proxy check-proxy-tls check-prior-knowledge-proxy check-tls-in-tls
                 unshared-tunnel-settings stops-multiplexing? multipart? check-multipart-supported
                 check-multipart-content-type multipart-paths-checked multipart-copy multipart-for-plan)))
    (list (symbols-in names (transfer-definition 'request-checks))
          (symbols-in names (transfer-definition 'prepare-transfer))
          (symbols-in names (transfer-definition 'curl-request-check)))))

;; pin-names : (Listof String)
(define pin-names '("PROTOCOLS_STR" "REDIR_PROTOCOLS_STR" "PROTOCOLS" "REDIR_PROTOCOLS" "NOSIGNAL" "QUICK_EXIT"
                    "MAXREDIRS"))

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

(test-equal "the names PROTOCOLS_STR, REDIR_PROTOCOLS_STR, PROTOCOLS, REDIR_PROTOCOLS, NOSIGNAL, QUICK_EXIT and MAXREDIRS stand in transfer.sls only as quoted data: seven in owned-option-names, four in pinned-options, and QUICK_EXIT in quick-exit-pin"
  (list-sort (lambda (a b) (string<? (written a) (written b)))
             '(("PROTOCOLS_STR" owned-option-names quoted) ("REDIR_PROTOCOLS_STR" owned-option-names quoted)
               ("PROTOCOLS" owned-option-names quoted) ("REDIR_PROTOCOLS" owned-option-names quoted)
               ("NOSIGNAL" owned-option-names quoted) ("QUICK_EXIT" owned-option-names quoted)
               ("MAXREDIRS" owned-option-names quoted)
               ("PROTOCOLS_STR" pinned-options quoted) ("REDIR_PROTOCOLS_STR" pinned-options quoted)
               ("NOSIGNAL" pinned-options quoted) ("MAXREDIRS" pinned-options quoted)
               ("QUICK_EXIT" quick-exit-pin quoted)))
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

;; setting-loops : Any -> Any
;; Each form of the definition D's body that sets by (car setting), as
;; (LIST N): the list the form's for-each walks, or (not-a-loop FORM), and
;; how many sets by (car setting) stand in it. D itself when it is no
;; definition: what went wrong.
(define (setting-loops d)
  (if (and (list? d) (pair? d) (eq? (car d) 'define))
      (fold-right
       (lambda (form found)
         (let ((n (length (filter (lambda (s) (equal? (car s) '(car setting))) (option-sets form '())))))
           (if (= n 0)
               found
               (cons (list (if (and (list? form) (= (length form) 3) (eq? (car form) 'for-each))
                               (caddr form)
                               (list 'not-a-loop form))
                           n)
                     found))))
       '() (cddr d))
      d))

;; method-settings' names are its fields' rows in request-field-options,
;; through field-options: tests/test-request.sps writes out every method's
;; answer, names and all.
(test-equal "every option set-transfer-options! sets is an owned option, written as a literal or through field-option, but for those set by (car setting): four in the loop over method-settings' answer for the plan's method, body and body-length, a string's, the mime's placeholder's, a bytevector's and a number's, two, a string's and a number's, in the loop over proxy-settings' answer for the plan's proxy, proxy CA file and proxy verification, one in the loop over version-settings' answer for the plan's http-version, two in the loop over credentials-settings' answer for the plan's credentials, and two in the loop over jar-settings' answer for the plan's cookie jar's share; the hatch's settings are set by set-hatch-option!, through its loop alone"
  '(() (((method-settings (plan-method plan) (plan-body plan) (plan-body-length plan)) 4)
        ((proxy-settings (plan-proxy plan) (plan-proxy-ca-file plan) (plan-proxy-verify plan)) 2)
        ((version-settings (plan-http-version plan)) 1)
        ((credentials-settings (plan-credentials plan)) 2)
        ((jar-settings (plan-share plan)) 2)))
  (if (list? transfer-sets)
      (list (map car (filter (lambda (s) (not (or (owned-set? (car s)) (equal? (car s) '(car setting)))))
                             transfer-sets))
            (setting-loops (transfer-definition 'set-transfer-options!)))
      transfer-sets))

(test-equal "setting-loops, the reader: a loop's list and its sets by (car setting) at any depth, a form setting by (car setting) outside a loop, and forms that set by name alone passed over"
  '((m 2) ((not-a-loop (when x (set-option! e (car setting) 1 b))) 1) ((plan-settings plan) 1))
  (setting-loops '(define (g)
                    (set-option! e "A" 1 b)
                    (for-each (lambda (setting)
                                (if y (set-option! e (car setting) 1 b) (f (set-string-option! e (car setting) "v" b))))
                              m)
                    (when x (set-option! e (car setting) 1 b))
                    (for-each (lambda (setting) (set-option! e (car setting) (cdr setting) b)) (plan-settings plan)))))

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

;; recorded-run : Request -> (List Any Any Any)
;; What R answers through the suite's engine, a &curl-transfer-error as
;; (refused REASON CODE RECORDED), RECORDED the object it recorded, else as
;; answer-of names it; its token's log, by log-of; and what it raised, as
;; classed names it.
(define (recorded-run r)
  (guard (e (#t (list (list 'raised-at-submit (describe e)) 'no-log 'no-classing)))
    (let* ((token (curl-submit engine r))
           (answered (classed (lambda (thunk)
                                (guard (e ((curl-transfer-error? e)
                                           (list 'refused (curl-transfer-error-reason e)
                                                 (curl-transfer-error-code e)
                                                 (curl-transfer-error-recorded e))))
                                  (let ((response (thunk)))
                                    (answer-of (lambda () response)))))
                              (lambda () (await-token token)))))
      (list (car answered) (log-of token) (cadr answered)))))

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
;; The error-buffer texts the four libcurls measured wrote alike, and
;; 8.23.0 too. nul-in-header's is not one: 8.23.0 capitalised it, so it is
;; a varying case's answer (ADR-0020).
(define measured-texts
  '("Recv failure: Connection reset by peer" "Received HTTP/0.9 when not allowed"
    "Header without colon" "Empty reply from server" "Maximum file size exceeded"))

(define (scenarios o)
  ;; --- every shared scenario, whole; and each refusal's class, by the
  ;; suite's table
  (for-each
   (lambda (pair)
     (let* ((answered (case-classed o (car pair)))
            (counts (native-counts)))
       (test-equal (string-append "shared: " (case-text (car pair)) ", whole, and the counts back to the engine's alone")
         (list (expanded (cadr pair)) running-counts)
         (list (car answered) counts))
       (when (refused-answer? (cadr pair))
         (test-equal (class-text "shared" (car pair) (cadr pair))
           (expected-classing (cadr pair))
           (cadr answered)))))
   shared-answers)

  ;; --- the cap on response headers (ADR-0040), the raw face's oversized
  ;; scripts at its edges: big-header's status line, 17 bytes, its X-Big line,
  ;; the value and 9, and the empty line, 2, take 102,400 at bytes=102372;
  ;; many-headers' status line is left out of the count, so 1,000 X-H lines
  ;; are taken, the shared answers' count=1000. Each refusal is read by its
  ;; reason and class, never its code, which is test-headers' to hold by
  ;; version; 50,000 lines, which each libcurl answers its own way without
  ;; the cap, are header-limit on every one.
  (test-equal "the cap: GET raw /raw/big-header?bytes=102372, 102,400 bytes with its status line and empty line, is taken whole; bytes=102373 and bytes=102380 are refused, header-limit, of &curl-too-large; GET raw /raw/many-headers at 1,001 and 50,000 lines, header-limit too; each with the counts back to the engine's alone"
    (list (list (list 'response 200 'http/1.1 (list (list "X-Big" (make-string 102372 #\a))) "")
                'no-transfer-error running-counts)
          (list '(refused header-limit) '(header-limit too-large) running-counts)
          (list '(refused header-limit) '(header-limit too-large) running-counts)
          (list '(refused header-limit) '(header-limit too-large) running-counts)
          (list '(refused header-limit) '(header-limit too-large) running-counts))
    (map (lambda (path)
           (let* ((answered (case-classed o (list 'get 'raw path)))
                  (counts (native-counts))
                  (answer (car answered))
                  (seen (cadr answered)))
             (list (if (refused-answer? answer) (list 'refused (cadr answer)) answer)
                   (if (pair? seen) (list (car seen) (caddr seen)) seen)
                   counts)))
         '("/raw/big-header?bytes=102372" "/raw/big-header?bytes=102373" "/raw/big-header?bytes=102380"
           "/raw/many-headers?count=1001" "/raw/many-headers?count=50000")))

  ;; --- the varying scenarios, against this libcurl's row; and each of its
  ;; refusals' class, by the suite's table. Each entry is (CASE ANSWER
  ;; COUNTS CLASSING), in varying-cases' order.
  (set! varying-answered
        (let loop ((rest varying-cases) (found '()))
          (if (null? rest)
              (reverse found)
              (let* ((answered (case-classed o (car rest)))
                     (counts (native-counts)))
                (loop (cdr rest) (cons (list (car rest) (car answered) counts (cadr answered)) found))))))
  (for-each
   (lambda (entry)
     (let ((want (and the-row (assoc (car entry) (row-answers the-row)))))
       (test-equal (string-append "varying: " (case-text (car entry)) ", as this libcurl's row says, and the counts back to the engine's alone")
         (list (if want (expanded (cadr want)) (list 'no-row-for version)) running-counts)
         (list (cadr entry) (caddr entry)))
       (when (and want (refused-answer? (cadr want)))
         (test-equal (class-text (string-append "by the row for " (written version)) (car entry) (cadr want))
           (expected-classing (cadr want))
           (cadddr entry)))))
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
     (test-equal (string-append "TIMEOUT_MS 300 against " path ": 28, of the class the suite's table gives it, and no other, no sooner than 300 ms and sooner than 600")
       (let ((want (list 'refused 'perform-failed curle-operation-timedout)))
         (list want (expected-classing want) 'within running-counts))
       (let* ((start (now-ms))
              (a (classed answer-of (lambda () (perform (request (url-of o 'raw path) 'timeout 300)))))
              (took (- (now-ms) start)))
         (list (car a) (cadr a) (if (and (>= took 300) (< took 600)) 'within (list 'took took))
               (native-counts)))))
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
  (test-equal "MAXFILESIZE_LARGE below a Content-Length: a body limit of 9 against /status/200's 11 is 63, perform-failed, of the class the suite's table gives it, and no other, before any chunk: the chunk log is empty"
    (let ((want (list 'refused 'perform-failed curle-filesize-exceeded)))
      (list (list want '() (expected-classing want)) running-counts))
    (with-counts (run-classed (request (url-of o 'http "/status/200") 'limit 9))))

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
                         (curl-response-effective-url (perform (request (url-of o 'http path))))))))
      (list (effective "/a/../status/200")
            (effective "/redirect/302?to=/status/200")
            (effective "/caf\xE9;")
            (native-counts))))

  ;; --- the last request's headers: a redirect followed, through the
  ;; private follow field, makes two requests, and the first one's headers
  ;; are not the response's. FOLLOWLOCATION is owned: the hatch refuses
  ;; it.
  (test-equal "with FOLLOWLOCATION set by the private follow field, curl-request-following, a followed redirect answers the last request's status, headers and body, and its effective URL"
    (list (list '(response 200 http/1.1 (("Content-Length" "11") ("Connection" "keep-alive")) "status 200\n")
                (url-of o 'http "/status/200"))
          running-counts)
    (list (guard (e (#t (list 'raised (describe e))))
            (let ((r (perform (curl-request-following
                               (request (url-of o 'http "/redirect/302?to=/status/200"))))))
              (list (answer-of (lambda () r)) (curl-response-effective-url r))))
          (native-counts)))

  ;; --- the URL, checked at submit, on this thread
  (test-equal "a URL whose scheme is not http or https is refused at submit as scheme-not-http, and one curl_url refuses with its code; nothing native is left"
    (list '(url-refused scheme-not-http #f) '(url-refused bad-port-number 4) running-counts)
    (list (submitted (lambda () (curl-submit engine (request "file:///etc/passwd"))))
          (submitted (lambda () (curl-submit engine (request "http://127.0.0.1:99999/"))))
          (native-counts)))

  ;; --- the counts while a transfer is live, read on this thread while the
  ;; engine's table holds a drip, before the counts and after them: the
  ;; engine records a transfer once start-transfer! has made everything,
  ;; and takes it out before free-transfer! frees anything
  (let ((live-counts '((block . 2) (easy . 1) (url . 1) (slist . 1) (curl-string . 0) (transfer . 1) (multi . 1) (share . 0) (mime . 0))))
    (test-equal "while a transfer is live, it holds its easy handle, its CURLU, its header list, its error buffer and itself, one each, beside the engine's multi handle and slot, and the live-transfer table and the engine's table each hold it; once it ends, the engine's handle and slot alone, and both tables empty"
      (list live-counts 1 1
            '(response 200 http/1.1 (("Content-Length" "20")) "abcdefghijklmnopqrst")
            running-counts 0 0)
      (let* ((t (curl-submit engine (request (url-of o 'raw "/raw/drip?bytes=20&gap=50")
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
  ;; same text, that text whole. nul-in-header's text varies by version, so
  ;; its row's answer holds it.
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
           (list "nul-in-header, whose text is a varying case's" (get 'raw "/raw/nul-in-header") #f)
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
                                  ", each chunk on the engine's thread; a refusal of the class the suite's table gives it, and no other")
         (list want (list (string-length accepted) (if (eq? (cadr want) 'body-limit) 'refused 'none))
               (expected-classing want) running-counts)
         (let ((r (run-classed (request (url-of o face path) 'limit limit))))
           (list (car r) (log-shape (cadr r)) (caddr r) (native-counts))))))
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
  ;; never a procedure
  (for-each
   (lambda (row)
     (test-equal (string-append "a fault " (car row) ", each chunk logged on the engine's thread; a refusal of the class the suite's table gives it, and no other")
       (list (append (caddr row) (list (expected-classing (car (caddr row))))) running-counts)
       (let ((r (recorded-run (cadr row))))
         (with-counts (list (car r) (if (null? (cdddr row)) (cadr r) (log-shape (cadr r))) (caddr r))))))
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
           (r (make-curl-request (url-of o 'raw "/raw/echo") 'user-agent agent 'timeout-ms default-timeout))
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
                  ;; A refusal comes before anything waits, so with no yield
                  ;; the next transfer can read the flipper's same CR: under
                  ;; Valgrind, which runs one thread at a time, every one of
                  ;; the 300 was refused, the flipper never seen at c, in 5 of
                  ;; 22 runs of the memory gate, the submit's URL parse in a
                  ;; section of its own, and 0 of 12 without it. A refusal
                  ;; sleeps 1 ms, so the flipper moves on.
                  (when (eq? k 'refused) (pause-ms 1))
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
  ;; mutex: the live-transfer table's, the option cache's; through the
  ;; hatch, an attach refused as unknown-option after LOW_SPEED_LIMIT, the
  ;; lookup's; and, through a submit to a stopped engine, the URL's CURLU,
  ;; made and freed on this thread, and that engine's own mutex, which
  ;; refuses it.
  (test-equal "a Chez engine that runs out at every tick of live-transfer-count, of cached-option-names, of an attach through the hatch refused as unknown-option after LOW_SPEED_LIMIT, and of a submit to a stopped engine, refused as stopped once its URL was parsed, each abandoned, until one completes: each completes, no native object is left, and another thread then takes every lock, both engines' among them"
    `(stopped (completed expired-first) (completed expired-first) (completed expired-first)
      (completed expired-first) ,running-counts other-thread-ran)
    (let* ((refused (request "http://127.0.0.1:1/"))
           (stopped (guard (e (#t (list 'raised (describe e))))
                      (let ((made (make-curl-engine))) (curl-engine-stop made) made)))
           (submit-to-stopped
            (lambda ()
              (guard (e ((curl-engine-error? e) (curl-engine-error-reason e))
                        (#t (list 'raised (describe e))))
                (curl-submit stopped refused)
                'queued)))
           (stopped-refuses (submit-to-stopped))
           (sweeps (map (lambda (thunk)
                          (let ((r (engine-sweep thunk 1)))
                            (if (and (eq? (car r) 'completed) (> (cadr r) 0)) '(completed expired-first) r)))
                        (list live-transfer-count
                              cached-option-names
                              (lambda ()
                                (answer-of (lambda ()
                                             (curl-request-with-options
                                              refused '(("LOW_SPEED_LIMIT" . 1) ("NO_SUCH_OPTION" . 1))))))
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

  ;; --- options the hatch attached, as the engine sets them
  ;; The hatch refuses a name the libcurl does not know as it is attached
  ;; (test-unsupported), so no transfer reaches option-named with one; it
  ;; refuses one all the same, for chez-curl's own names, QUICK_EXIT's on a
  ;; libcurl without it among them, called here on this thread.
  (test-equal "option-named, through which every option is set, refuses a name the loaded libcurl does not know as unknown-option, naming it, with no code and a request size of 0, of no class"
    (list 'unknown-option #f "NO_SUCH_OPTION" 0 (table-class 'unknown-option #f))
    (guard (e ((curl-transfer-error? e)
               (list (curl-transfer-error-reason e) (curl-transfer-error-code e)
                     (curl-transfer-error-option e) (curl-transfer-error-request-size e)
                     (class-of e)))
              (#t (list 'raised (describe e))))
      (option-named "NO_SUCH_OPTION")
      'no-raise))
  (test-equal "an option libcurl refuses raises setopt-failed, naming it, with its code and a request size of 0, of no class, through each integer binding: LOW_SPEED_LIMIT -2 through the long one and MAX_RECV_SPEED_LARGE -1 through the off_t one are 43, never taken zero-extended, as 4294967294 and 4294967295 would be; the counts back to the engine's alone"
    (list (list 'setopt-failed curle-bad-function-argument "LOW_SPEED_LIMIT" 0
                (table-class 'setopt-failed curle-bad-function-argument))
          (list 'setopt-failed curle-bad-function-argument "MAX_RECV_SPEED_LARGE" 0
                (table-class 'setopt-failed curle-bad-function-argument))
          running-counts)
    (append (map (lambda (option)
                   (guard (e ((curl-transfer-error? e)
                              (list (curl-transfer-error-reason e) (curl-transfer-error-code e)
                                    (curl-transfer-error-option e) (curl-transfer-error-request-size e)
                                    (class-of e)))
                             (#t (list 'raised (describe e))))
                     (perform-with (request (url-of o 'http "/status/200")) (list option))
                     'no-raise))
                 (list '("LOW_SPEED_LIMIT" . -2) '("MAX_RECV_SPEED_LARGE" . -1)))
            (list (native-counts))))

  ;; --- the redirect pin, observed: without REDIR_PROTOCOLS_STR, libcurl
  ;; would follow to FTP, and answer 7, connection refused
  (test-equal "REDIR_PROTOCOLS_STR, observed: FOLLOWLOCATION by the private follow field, to ftp://127.0.0.1:1/, a protocol this libcurl lists, is refused as 1, CURLE_UNSUPPORTED_PROTOCOL, never tried, of the class the suite's table gives it, and no other; the counts back to the engine's alone"
    (let ((want (list 'refused 'perform-failed curle-unsupported-protocol)))
      (list 'ftp-listed (list want (expected-classing want)) running-counts))
    (list (if (member "ftp" (loaded-protocols)) 'ftp-listed (list 'no-ftp-in (loaded-protocols)))
          (classed answer-of
                   (lambda ()
                     (perform (curl-request-following
                               (request (url-of o 'http "/redirect/302?to=ftp://127.0.0.1:1/"))))))
          (native-counts)))

  ;; --- the outcomes of no class: a transfer cancelled, and one whose
  ;; engine stopped, before either ended. Each drip takes a second; the
  ;; stopped one runs on an engine of its own.
  (test-equal "class: a drip cancelled before it ended, and one whose engine stopped before it ended, each raise the base type alone, of no class, with no code; the counts back to the engine's alone"
    (list (list 'cancelled #f (table-class 'cancelled #f)) (list 'stopped #f (table-class 'stopped #f))
          running-counts)
    (let* ((cancelled
            (let ((t (curl-submit engine (request (url-of o 'raw "/raw/drip?bytes=20&gap=50")))))
              (curl-token-cancel t)
              (cadr (classed answer-of (lambda () (await-token t))))))
           (stopped
            (let* ((own (make-curl-engine))
                   (t (curl-submit own (request (url-of o 'raw "/raw/drip?bytes=20&gap=50")))))
              (curl-engine-stop own)
              (cadr (classed answer-of (lambda () (await-token t)))))))
      (list cancelled stopped (native-counts))))

  ;; --- the option cache keeps its own copy of a name
  ;; Through option-named directly: the hatch copies a name itself before
  ;; the lookup, so through it option-found's own copy would be unseen. The
  ;; name is one nothing in this suite looks up, so the lookup is its first,
  ;; and a key the cache made of the caller's string would change with it.
  (test-equal "the option cache keeps a copy of each name: MAXAGE_CONN, looked up first by option-named in a caller's string, changed after, leaves the cache's key as it was"
    '(not-cached kept not-taken)
    (let ((name (string-copy "MAXAGE_CONN"))
          (before (cached-option-names)))
      (option-named name)
      (string-set! name 0 #\X)
      (let ((keys (cached-option-names)))
        (list (if (member "MAXAGE_CONN" before) 'cached-before 'not-cached)
              (if (member "MAXAGE_CONN" keys) 'kept 'lost)
              (if (member "XAXAGE_CONN" keys) 'taken 'not-taken)))))

  ;; --- a header value another thread changes while transfers run
  (test-equal "a header value another thread flips between c and CR while 300 transfers run: each is refused as line-break, or sends the value whole, never the CR, both seen; the counts back to the engine's alone"
    (list '() '(refused whole) running-counts)
    (let* ((value (string-copy "abcdef"))
           (r (make-curl-request (url-of o 'raw "/raw/echo") 'headers (list (cons "X-Race" value))
                                 'timeout-ms default-timeout))
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
                  ;; A refusal comes before anything waits, so with no yield
                  ;; the next transfer can read the flipper's same CR: under
                  ;; Valgrind, which runs one thread at a time, every one of
                  ;; the 300 was refused, the flipper never seen at c, in 5 of
                  ;; 22 runs of the memory gate, the submit's URL parse in a
                  ;; section of its own, and 0 of 12 without it. A refusal
                  ;; sleeps 1 ms, so the flipper moves on.
                  (when (eq? k 'refused) (pause-ms 1))
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
  ;; collection moves the callable's code, and libcurl calls where it was. The
  ;; positive evidence: collections made while the engine's table held the
  ;; transfer, more than its connect and the 10 ms before its first byte leave
  ;; room for.
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
            (native-counts))))

  ;; --- the proxy field (ADR-0024), in a child given http_proxy or all_proxy
  ;; at the http face, and no no_proxy or NO_PROXY, through its command alone,
  ;; so this suite stays hermetic. The http face stands in for the proxy: a
  ;; target in absolute form is routed by its path, and /echo's first line
  ;; shows the target as it came. So the proxy's own record says how each
  ;; request reached it: GET http://HOST/echo through the proxy, GET /echo
  ;; direct.
  (let* ((proxy (string-append "http://" (host-of o 'http)))
         (url (url-of o 'http "/echo"))
         (through (string-append "GET " url " HTTP/1.1"))
         (direct "GET /echo HTTP/1.1"))
    (for-each
     (lambda (row)
       (let ((variable (list-ref row 0)) (field (list-ref row 1)) (line (list-ref row 2))
             (text (list-ref row 3)))
         (test-equal (string-append "the proxy field, in a child: " text)
           (list 0
                 (list (list 'environment
                             (cons 'http_proxy (and (equal? variable "http_proxy") proxy))
                             (cons 'all_proxy (and (equal? variable "all_proxy") proxy))
                             '(no_proxy . #f) '(NO_PROXY . #f))
                       (list 'transfer (list 'response 200 line) zero-counts)
                       '(done))
                 "")
           (proxy-child (if variable (list (string-append variable "=" proxy)) '()) url field))))
     (list (list "http_proxy" "default" through
                 "http_proxy at the http face and no proxy key, the default: the request reaches the proxy, its target in absolute form")
           (list "http_proxy" "environment" through
                 "http_proxy at the http face and the proxy key at environment: through the proxy")
           (list "http_proxy" "none" direct
                 "http_proxy at the http face and the proxy key at #f: the request goes direct, PROXY \"\" reading no variable")
           (list "all_proxy" "default" through
                 "all_proxy at the http face and no proxy key, the default: through the proxy")
           (list "all_proxy" "none" direct
                 "all_proxy at the http face and the proxy key at #f: direct")
           (list #f "default" direct
                 "no proxy variable and no proxy key: direct, so the variable is what sent the others through")))))

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

(test-equal "it holds rows for 7.85.0, 8.5.0 and 8.23.0, the libcurls the lanes run, 8.20.0, the container's, and 8.7.1, Apple's"
  '("7.85.0" "8.5.0" "8.7.1" "8.20.0" "8.23.0")
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

;; --- the suite's class table -----------------------------------------------------------------

(test-equal "the suite's class table has a row for each code a perform-failed refusal answers, among the shared answers and in every version row, so each lane classes its own answers by it"
  '()
  (let ((answers (append (map cadr shared-answers)
                         (apply append (map (lambda (row) (map cadr (row-answers row)))
                                            (filter (lambda (row) (eq? (row-problem row) 'ok)) rows))))))
    (filter (lambda (code) (not (assv code code-classes)))
            (map caddr (filter (lambda (a) (and (refused-answer? a) (eq? (cadr a) 'perform-failed)))
                               answers)))))

(test-equal "table-class, the rule written out: body-limit and header-limit are too-large whatever the code, 0 among them; perform-failed takes its code's row, and a code with no row is (no-row CODE); every other reason is of no class, whatever its code"
  '(too-large too-large too-large too-large too-large send-receive none (no-row 7) none none none none none none)
  (list (table-class 'body-limit 23) (table-class 'body-limit 56)
        (table-class 'header-limit 23) (table-class 'header-limit 0) (table-class 'header-limit 56)
        (table-class 'perform-failed 56)
        (table-class 'perform-failed 23) (table-class 'perform-failed 7)
        (table-class 'callback-raised 23) (table-class 'setopt-failed 1)
        (table-class 'unknown-option #f) (table-class 'no-handle #f)
        (table-class 'cancelled #f) (table-class 'stopped #f)))

(test-equal "class-of, the reader: each class's condition by its own name, the base type and a non-condition as none, and a condition of two classes as several"
  '(timeout connect send-receive tls protocol too-large none none (several timeout tls))
  (guard (e (#t (list 'raised (describe e))))
    (list (class-of (make-curl-timeout 'perform-failed 28 #f #f #f #f 0 #f))
          (class-of (make-curl-connect-error 'perform-failed 7 #f #f #f #f 0 #f))
          (class-of (make-curl-send-receive-error 'perform-failed 56 #f #f #f #f 0 #f))
          (class-of (make-curl-tls-error 'perform-failed 60 #f #f #f #f 0 #f))
          (class-of (make-curl-protocol-error 'perform-failed 1 #f #f #f #f 0 #f))
          (class-of (make-curl-too-large 'body-limit 23 #f #f #f #f 0 #f))
          (class-of (make-curl-transfer-error 'perform-failed 28 #f #f #f #f 0 #f))
          (class-of 'not-a-condition)
          (class-of (condition (make-curl-timeout 'perform-failed 28 #f #f #f #f 0 #f)
                               (make-curl-tls-error 'perform-failed 60 #f #f #f #f 0 #f))))))

(define made-up-row
  `(libcurl (where "made up") (version "9.9.9")
            (answers ((get raw "/raw/x") (refused perform-failed 7)))))

(test-equal "the matcher: a version with one row is one, with none is none, with two is several; a malformed row is never a match"
  '(one none several none)
  (list (version-verdict (list made-up-row) "9.9.9")
        (version-verdict (list made-up-row) "9.9.8")
        (version-verdict (list made-up-row made-up-row) "9.9.9")
        (version-verdict (list '(libcurl (version "9.9.9"))) "9.9.9")))

(test-equal "the shape: a row missing where, an answer with a reason no transfer error has, or a code that is no number, or headers that are no pairs, is refused; each kind of case takes its own answer, and only it"
  '(rejected rejected rejected rejected ok ok ok rejected rejected rejected rejected rejected rejected rejected)
  (map (lambda (row) (if (eq? (row-problem row) 'ok) 'ok 'rejected))
       (list '(libcurl (version "9.9.9") (answers ((get raw "/raw/x") (refused perform-failed 7))))
             '(libcurl (where "w") (version "9.9.9") (answers ((get raw "/raw/x") (refused timed-out 28))))
             '(libcurl (where "w") (version "9.9.9") (answers ((get raw "/raw/x") (refused perform-failed "28"))))
             '(libcurl (where "w") (version "9.9.9") (answers ((get raw "/raw/x") (response 200 http/1.1 (("A" . "b")) ""))))
             '(libcurl (where "w") (version "9.9.9") (answers ((get raw "/raw/x") (response 200 http/1.1 (numbered "X-H-" 3 "v") ""))))
             made-up-row
             '(libcurl (where "w") (version "9.9.9") (answers ((error-text raw "/raw/x") (error-text "t"))))
             '(libcurl (where "w") (version "9.9.9") (answers ((error-text raw "/raw/x") (refused perform-failed 7))))
             '(libcurl (where "w") (version "9.9.9") (answers ((get raw "/raw/x") (error-text "t"))))
             '(libcurl (where "w") (version "9.9.9") (answers ((error-text raw "/raw/x") (error-text 7))))
             '(libcurl (where "w") (version "9.9.9") (answers ((error-text tls "/raw/x") (error-text "t"))))
             '(libcurl (where "w") (version "9.9.9") (answers ((head raw "/raw/x") (refused perform-failed 7))))
             '(libcurl (where "w") (version "9.9.9") (answers ((error-text raw "/raw/x") (error-text "t" "u"))))
             '(libcurl (where "w") (version "9.9.9") (answers ((error-text raw "/raw/x") (error-text)))))))

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
                      (row-text "9.9.9" (map (lambda (a-case)
                                               (list a-case (if (eq? (car a-case) 'error-text)
                                                                '(error-text "t")
                                                                '(refused perform-failed 7))))
                                             varying-cases))))))
      (cond ((not (eq? (row-problem row) 'ok)) (row-problem row))
            ((not (same-cases? (map car (row-answers row)) varying-cases)) (row-answers row))
            (else 'ok)))))

(test-equal "the loaded libcurl's version has exactly one row in tests/known-transfer-verdicts.sexp"
  (list version)
  (map row-version matches))

(test-end "transfer")

(exit (suite-exit-status runner))
