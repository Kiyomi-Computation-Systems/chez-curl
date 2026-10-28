#!r6rs
;;; The suite for (http-client), the high level's first slice (ADR-0025; the
;;; M5 plan, sections 3.1 to 3.3, 3.6 and 4): sessions, the verbs, the keys
;;; and their merge, the encodings, the response, the conditions, the
;;; call's bound, the functional core and the shell for one call.
;;;
;;;   - (http-client)'s exports, written out;
;;;   - sessions: their keys refused by name, a bad value refused with no
;;;     engine made, close, a second close, a call after close, and
;;;     call-with-http-session closing on a return and on an escape;
;;;   - each verb's method at the origin's /echo, and http-request's;
;;;   - the merge, as a pure procedure, then live: order, replacement by
;;;     name, A to Z folding against U+212A KELVIN SIGN and U+017F LONG S,
;;;     and both user-agent rules;
;;;   - the bodies, a string, a bytevector and a form, and their refusals;
;;;   - the form encoding, pure: every char below U+0100, one of each UTF-8
;;;     length, the kept set against its whole complement, and a space, +,
;;;     = and & in names and values;
;;;   - the private copy of a form, params or headers, bounded by the
;;;     length measured, so a list made cyclic after it cannot loop;
;;;   - params, at the origin and in the response's URL, which is curl_url's
;;;     whole form of the URL requested;
;;;   - the response's accessors, the header lookup's folding, and the
;;;     text's decoding;
;;;   - &http-exchange compounded onto what a call raises; a call inside a
;;;     critical section refused before it submits, by a pre-check that
;;;     matches the take's refusal alone;
;;;   - the call's bound, live, against a drip;
;;;   - exchange-submission and exchange-step, by tables: a bounded transfer
;;;     with no connect timeout gets the time left as one, capped at
;;;     libcurl's own 300 s;
;;;   - an escape from the await, which cancels the transfer, with a control
;;;     that does not; a condition the caller's timer raises in the await,
;;;     left unchanged, and a continuable one returned from, which resumes
;;;     the call; a Chez engine's expiry in the await; a second escape swept
;;;     over the first one's unwind, which cannot skip the cancel, with the
;;;     sweep's evidence that it reached the after thunk; and, in a child
;;;     written from data here, an escape planted at the end of the
;;;     submit's critical section, by SIGINT, which still cancels it.
;;;
;;; Every check on the origin's raw face makes its own session: the raw face
;;; closes after each script without saying so, and curl 8.23.0 then resends
;;; on each dead pooled connection (traps.md). Every expected value is one
;;; the code under test cannot produce by failing: SRFI-64 makes #f of a
;;; raise in the actual expression, so none is #f, and an absent header is
;;; (absent).
(import (rnrs)
        (srfi :64)
        (rnrs mutable-strings)
        (rnrs mutable-pairs)
        (only (chezscheme) sleep make-time current-time time-second time-nanosecond getenv
              library-directories library-exports set-timer timer-interrupt-handler iota
              critical-section fork-thread make-mutex with-mutex make-engine)
        (curl-testing)
        (curl)
        (http-client)
        (only (http-client private conditions) make-http-request-error make-http-timeout
              make-http-exchange)
        (only (http-client private call) form-encode merge-fields with-form-type string-pairs
              string-pairs-within)
        (only (http-client private exchange) make-exchange exchange-submission exchange-step
              exchange-flight exchange-transfers exchange-request make-http-response)
        (only (curl private conditions) make-classed-transfer-error make-curl-engine-error
              make-curl-url-error)
        (only (curl private transfer) transfers-started)
        (only (http-client private drive) take-refusal?)
        (curl private counters))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; written : Any -> String
(define (written x) (call-with-string-output-port (lambda (p) (write x p))))

;; shown : Any -> String
;; X written, cut to 3000 characters.
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
      ;; A suite killed at its bound never flushes: flush each verdict.
      (flush-output-port (current-output-port)))))

(test-begin "http-client")

;; --- helpers --------------------------------------------------------------------------

(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0)))

;; now-ms : -> Integer
(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

;; pause-ms : Natural -> Unit
(define (pause-ms ms)
  (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))

;; count-of : Symbol -> Natural
;; KIND's native count now.
(define (count-of kind) (cdr (assq kind (native-counts))))

;; latin-1 : Bytevector -> String
(define (latin-1 bytes)
  (list->string (map integer->char (bytevector->u8-list bytes))))

;; bytes-of : String -> Bytevector
;; The bytes of S, a string of chars below U+0100, one each.
(define (bytes-of s)
  (u8-list->bytevector (map char->integer (string->list s))))

;; class-of : Condition -> Symbol
;; A transfer failure's class, by (curl)'s predicates, or none.
(define (class-of e)
  (cond ((curl-timeout? e) 'timeout)
        ((curl-connect-error? e) 'connect)
        ((curl-send-receive-error? e) 'send-receive)
        ((curl-tls-error? e) 'tls)
        ((curl-protocol-error? e) 'protocol)
        ((curl-too-large? e) 'too-large)
        (else 'none)))

;; described : Any -> (Listof Any)
;; What a raised object is, whole: for a condition, each of these it is,
;; in this order, with its fields; for anything else, (non-condition X).
(define (described e)
  (if (condition? e)
      (filter
       (lambda (x) x)
       (list (and (http-error? e) '(http-error))
             (and (http-request-error? e)
                  (list 'http-request-error (http-request-error-field e) (http-request-error-value e)
                        (http-request-error-reason e)))
             (and (http-timeout? e) (list 'http-timeout (http-timeout-timeout-ms e)))
             (and (curl-request-error? e)
                  (list 'curl-request-error (curl-request-error-field e) (curl-request-error-value e)
                        (curl-request-error-reason e)))
             (and (curl-url-error? e) (list 'curl-url-error (curl-url-error-reason e)))
             (and (curl-engine-error? e) (list 'curl-engine-error (curl-engine-error-reason e)))
             (and (curl-transfer-error? e)
                  (list 'curl-transfer-error (class-of e) (curl-transfer-error-reason e)
                        (curl-transfer-error-code e)))
             (and (assertion-violation? e)
                  (list 'assertion (and (who-condition? e) (condition-who e))))
             (and (http-exchange? e)
                  (list 'exchange (http-exchange-method e) (http-exchange-url e)
                        (http-exchange-history e) (http-exchange-transfers e)))))
      (list 'non-condition e)))

;; outcome : (-> Any) -> (Pairof Symbol Any)
;; (returned VALUE), or (raised . DESCRIBED).
(define (outcome thunk)
  (guard (e (#t (cons 'raised (described e))))
    (list 'returned (thunk))))

;; echoed : Response -> (List Integer String)
;; A response's status, and its body read as Latin-1: /echo's text.
(define (echoed r)
  (if (http-response? r)
      (list (http-response-status r) (latin-1 (http-response-body r)))
      (list 'not-a-response r)))

;; answer : (-> Response) -> Any
;; What THUNK's call answers, through echoed, or what it raised.
(define (answer thunk)
  (guard (e (#t (cons 'raised (described e))))
    (echoed (thunk))))

;; library-path : -> String
;; This suite's library path, as --libdirs takes it.
(define (library-path)
  (let loop ((dirs (map car (library-directories))) (text ""))
    (cond ((null? dirs) text)
          ((string=? text "") (loop (cdr dirs) (car dirs)))
          (else (loop (cdr dirs) (string-append text ":" (car dirs)))))))

;; read-all : String -> (Listof Any)
(define (read-all text)
  (let ((port (open-string-input-port text)))
    (let loop ((found '()))
      (let ((datum (guard (e (#t '(unreadable))) (read port))))
        (cond ((eof-object? datum) (reverse found))
              ((equal? datum '(unreadable)) (reverse (cons datum found)))
              (else (loop (cons datum found))))))))

;; in-order : (Any -> Any) (Listof Any) -> (Listof Any)
;; PROC of each of ITEMS, called first to last: map calls its procedure in
;; no fixed order (traps.md), and each call here has effects a later read
;; must follow.
(define (in-order proc items)
  (let loop ((rest items) (answers '()))
    (if (null? rest)
        (reverse answers)
        (let ((answer (proc (car rest))))
          (loop (cdr rest) (cons answer answers))))))

;; iota-from : Integer Natural -> (Listof Integer)
;; N integers, from START up.
(define (iota-from start n) (map (lambda (i) (+ start i)) (iota n)))

;; symbols-sorted : (Listof Symbol) -> (Listof Symbol)
(define (symbols-sorted names)
  (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) names))

;; --- the exports ----------------------------------------------------------------------

;; Written out: the M5 plan's slice 1, section 3.1, and the brief's names.
(define http-client-exports
  '(make-http-session http-session? http-session-close call-with-http-session
    http-request http-get http-head http-post http-put http-patch http-delete
    http-response? http-response-status http-response-http-version http-response-url
    http-response-headers http-response-body http-response-timings http-response-history
    http-response-header http-response-text
    &http-error http-error?
    &http-request-error http-request-error? http-request-error-field http-request-error-value
    http-request-error-reason http-request-error-reasons
    &http-timeout http-timeout? http-timeout-timeout-ms
    &http-exchange http-exchange? http-exchange-method http-exchange-url http-exchange-history
    http-exchange-transfers))

(test-equal "(http-client) exports exactly slice 1's names, none of them (curl)'s"
  (list (symbols-sorted http-client-exports) '())
  (let ((exports (library-exports '(http-client))))
    (list (symbols-sorted exports)
          (filter (lambda (name) (memq name (library-exports '(curl)))) exports))))

(test-equal "http-request-error-reasons, written out"
  '(unknown-key repeated-key missing-value body-and-form body-not-allowed not-a-body
    not-name-value-pairs)
  http-request-error-reasons)

(test-equal "the conditions' types: the request error and the timeout under &http-error, under &curl-error and &error; &http-exchange under &condition alone, no error"
  '((#t #t #t #t #f) (#t #t #t #f #t) (#f #f #f #f #f #t))
  (list (let ((c (make-http-request-error 'key 'k 'unknown-key)))
          (list (error? c) (curl-error? c) (http-error? c) (http-request-error? c) (http-timeout? c)))
        (let ((c (make-http-timeout 400)))
          (list (error? c) (curl-error? c) (http-error? c) (http-request-error? c) (http-timeout? c)))
        (let ((c (make-http-exchange 'get "http://h.example/" '() 0)))
          (list (serious-condition? c) (error? c) (curl-error? c) (http-error? c) (http-timeout? c)
                (http-exchange? c)))))

(test-equal "make-http-request-error refuses a reason that is not one of the seven, an assertion violation"
  '(raised (assertion make-http-request-error))
  (outcome (lambda () (make-http-request-error 'key 'k 'unknown))))

(test-equal "what is no session is refused at a call, an assertion violation compounded with &http-exchange, no &http-error"
  '(raised (assertion http-request) (exchange get "http://127.0.0.1:1/" () 0))
  (outcome (lambda () (http-get 'not-a-session "http://127.0.0.1:1/"))))

;; --- sessions ---------------------------------------------------------------------------

;; Before any session is made here: no engine runs, so the multi count is
;; the suite's own evidence that a refusal made none.

(test-equal "make-http-session refuses an unknown key by name, redirects, allow-downgrade, retry, body, method and a string among them, each as &http-request-error, field key, with no engine made"
  (map (lambda (key) (list (list 'raised '(http-error) (list 'http-request-error 'key key 'unknown-key)) 0))
       (list 'redirects 'allow-downgrade 'retry 'body 'method "timeout-ms"))
  (in-order (lambda (key)
              (let* ((refused (outcome (lambda () (make-http-session key 1))))
                     (multi (count-of 'multi)))
                (list refused multi)))
            (list 'redirects 'allow-downgrade 'retry 'body 'method "timeout-ms")))

(test-equal "make-http-session refuses a repeated key and a key with no value by name, and an unknown key before a missing value, with no engine made"
  (list '(raised (http-error) (http-request-error key timeout-ms repeated-key))
        '(raised (http-error) (http-request-error key headers missing-value))
        '(raised (http-error) (http-request-error key nope unknown-key))
        '(raised (http-error) (http-request-error key verify repeated-key))
        0)
  (let* ((repeated (outcome (lambda () (make-http-session 'timeout-ms 1 'timeout-ms 2))))
         (missing (outcome (lambda () (make-http-session 'verify #f 'headers))))
         (unknown (outcome (lambda () (make-http-session 'nope))))
         (again (outcome (lambda () (make-http-session 'verify #t 'proxy #f 'verify #t))))
         (multi (count-of 'multi)))
    (list repeated missing unknown again multi)))

(test-equal "make-http-session refuses a bad value as the low level does, its condition unchanged, no &http-exchange, with no engine made"
  (list '(raised (curl-request-error header-value "a\nb" line-break))
        '(raised (assertion make-curl-request))
        '(raised (assertion make-curl-request))
        '(raised (assertion make-curl-request))
        '(raised (curl-request-error ca-file "pkcs11:x" pkcs11-url))
        '(raised (curl-request-error header-name "Content-Length" framing-header))
        0)
  (let* ((line-break (outcome (lambda () (make-http-session 'headers '(("X-A" . "a\nb"))))))
         (empty-agent (outcome (lambda () (make-http-session 'user-agent ""))))
         (zero (outcome (lambda () (make-http-session 'timeout-ms 0))))
         (not-a-list (outcome (lambda () (make-http-session 'headers 'not-a-list))))
         (pkcs11 (outcome (lambda () (make-http-session 'ca-file "pkcs11:x"))))
         (framing (outcome (lambda () (make-http-session 'headers '(("Content-Length" . "1"))))))
         (multi (count-of 'multi)))
    (list line-break empty-agent zero not-a-list pkcs11 framing multi)))

(test-equal "a session made: http-session? holds, its engine runs, and nothing else does; a close stops it; a second close returns; a call after close raises the engine's &curl-engine-error stopped, compounded with &http-exchange, no transfer made"
  (list #t #f 1 '(returned closed) 0 '(returned closed-again)
        '(raised (curl-engine-error stopped) (exchange get "http://127.0.0.1:1/x" () 0))
        zero-counts)
  (let* ((s (make-http-session 'timeout-ms 5000))
         (made (list (http-session? s) (http-session? 'other) (count-of 'multi)))
         (closed (outcome (lambda () (http-session-close s) 'closed)))
         (multi (count-of 'multi))
         (again (outcome (lambda () (http-session-close s) 'closed-again)))
         (call (outcome (lambda () (http-get s "http://127.0.0.1:1/x"))))
         (counts (native-counts)))
    (append made (list closed multi again call counts))))

(test-equal "http-session-close refuses what is no session, an assertion violation"
  '(raised (assertion http-session-close))
  (outcome (lambda () (http-session-close 'not-a-session))))

(test-equal "call-with-http-session hands PROC a session made from the keys, answers PROC's value, and closes the session when PROC returns"
  (list '(value #t 1) 0
        '(raised (curl-engine-error stopped) (exchange get "http://127.0.0.1:1/x" () 0)))
  (let* ((kept #f)
         (value (call-with-http-session 'timeout-ms 5000 'verify #f
                  (lambda (s) (set! kept s) (list 'value (http-session? s) (count-of 'multi)))))
         (multi (count-of 'multi))
         (call (outcome (lambda () (http-get kept "http://127.0.0.1:1/x")))))
    (list value multi call)))

(test-equal "call-with-http-session closes the session when PROC escapes, by a raise and by a continuation"
  (list 'caught 0 '(raised (curl-engine-error stopped) (exchange get "http://127.0.0.1:1/x" () 0))
        'escaped 0 '(raised (curl-engine-error stopped) (exchange get "http://127.0.0.1:1/x" () 0)))
  (let* ((raised-in #f)
         (caught (guard (e ((eq? e 'planted) 'caught))
                   (call-with-http-session (lambda (s) (set! raised-in s) (raise 'planted)))))
         (after-raise (count-of 'multi))
         (raised-call (outcome (lambda () (http-get raised-in "http://127.0.0.1:1/x"))))
         (escaped-in #f)
         (escaped (call/cc
                   (lambda (k)
                     (call-with-http-session 'timeout-ms 5000
                       (lambda (s) (set! escaped-in s) (k 'escaped))))))
         (after-escape (count-of 'multi))
         (escaped-call (outcome (lambda () (http-get escaped-in "http://127.0.0.1:1/x")))))
    (list caught after-raise raised-call escaped after-escape escaped-call)))

(test-equal "call-with-http-session refuses no procedure last, and a refused key, with no engine made"
  (list '(raised (assertion call-with-http-session))
        '(raised (assertion call-with-http-session))
        '(raised (http-error) (http-request-error key redirects unknown-key))
        0)
  (let* ((none (outcome (lambda () (call-with-http-session))))
         (no-procedure (outcome (lambda () (call-with-http-session 'timeout-ms 5000))))
         (refused-key (outcome (lambda () (call-with-http-session 'redirects 3 (lambda (s) s)))))
         (multi (count-of 'multi)))
    (list none no-procedure refused-key multi)))

;; --- the merge, pure ---------------------------------------------------------------------

(test-equal "the merge: a call's header replaces every session header of its name, A to Z folded; the session's others come first, in order, then the call's, in theirs, repeats kept"
  (list (list '(("A" . "1") ("C" . "3") ("X" . "9") ("b" . "5")) #f)
        (list '(("A" . "1") ("X" . "1") ("x" . "2")) "s/1")
        (list '(("A" . "1") ("B" . "2")) "s/1")
        (list '(("B" . "1") ("a" . "2")) #f))
  (list (merge-fields '(("A" . "1") ("B" . "2") ("C" . "3") ("b" . "4")) #f
                      '(("X" . "9") ("b" . "5")) '())
        (merge-fields '(("A" . "1") ("X" . "0")) "s/1" '(("X" . "1") ("x" . "2")) '())
        (merge-fields '(("A" . "1") ("B" . "2")) "s/1" '() '())
        (merge-fields '() #f '(("B" . "1") ("a" . "2")) '())))

(test-equal "the merge folds A to Z alone: KELVIN SIGN is no k, LONG S no s, [ no {, @ no `, either way round"
  (list (list '(("X-\x212A;" . "1") ("X-K" . "3")) #f)
        (list '(("X-k" . "1") ("X-\x212A;" . "3")) #f)
        (list '(("X-\x17F;" . "1") ("X-S" . "3")) #f)
        (list '(("X-s" . "1") ("X-\x17F;" . "3")) #f)
        (list '(("X-{" . "1") ("X-@" . "2") ("X-[" . "3") ("X-`" . "4")) #f))
  (list (merge-fields '(("X-\x212A;" . "1") ("X-k" . "2")) #f '(("X-K" . "3")) '())
        (merge-fields '(("X-k" . "1")) #f '(("X-\x212A;" . "3")) '())
        (merge-fields '(("X-\x17F;" . "1") ("X-s" . "2")) #f '(("X-S" . "3")) '())
        (merge-fields '(("X-s" . "1")) #f '(("X-\x17F;" . "3")) '())
        (merge-fields '(("X-{" . "1") ("X-@" . "2")) #f '(("X-[" . "3") ("X-`" . "4")) '())))

(test-equal "the merge's user agent: a call's User-Agent header, in any case, makes the field #f; a call's user-agent field, #f too, is the field and drops the session's User-Agent header; otherwise the session's field stands, and its header too"
  (list (list '(("A" . "1") ("user-AGENT" . "c/1")) #f)
        (list '(("A" . "1") ("B" . "2")) "c/2")
        (list '(("A" . "1")) #f)
        (list '(("A" . "1")) "s/1")
        (list '(("User-Agent" . "h/1") ("A" . "1")) #f)
        (list '(("User-Agent\x212A;" . "x") ("A" . "1")) "c/3"))
  (list (merge-fields '(("A" . "1")) "s/1" '(("user-AGENT" . "c/1")) '())
        (merge-fields '(("A" . "1") ("USER-agent" . "h/1") ("B" . "2")) #f '() '("c/2"))
        (merge-fields '(("A" . "1") ("User-Agent" . "h/1")) "s/1" '() '(#f))
        (merge-fields '(("A" . "1")) "s/1" '() '())
        (merge-fields '(("User-Agent" . "h/1") ("A" . "1")) #f '() '())
        (merge-fields '(("User-Agent\x212A;" . "x") ("A" . "1")) #f '() '("c/3"))))

(test-equal "with-form-type appends the form's Content-Type unless the headers name one, in any A to Z case"
  (list '(("A" . "1") ("Content-Type" . "application/x-www-form-urlencoded"))
        '(("content-TYPE" . "text/plain") ("A" . "1"))
        '(("Content-Types" . "x") ("Content-Type" . "application/x-www-form-urlencoded")))
  (list (with-form-type '(("A" . "1")))
        (with-form-type '(("content-TYPE" . "text/plain") ("A" . "1")))
        (with-form-type '(("Content-Types" . "x")))))

;; --- the form encoding, pure ---------------------------------------------------------------

;; kept-set : String
;; The chars the WHATWG serializer keeps as themselves, written out, in
;; code point order.
(define kept-set "*-.0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz")

;; hex2 : Natural -> String
;; %XX for B, upper case, two digits.
(define (hex2 b)
  (string-append "%" (if (< b 16) "0" "") (string-upcase (number->string b 16))))

;; expected-char : Natural -> String
;; What the form encoding writes for the char with code C, below U+0100:
;; a kept char as itself, a space as +, any other below U+0080 as its one
;; byte's %XX, and one from U+0080 as its two UTF-8 bytes, C2 or C3 then
;; 80 + its low six bits.
(define (expected-char c)
  (cond ((memv (integer->char c) (string->list kept-set)) (string (integer->char c)))
        ((= c 32) "+")
        ((< c 128) (hex2 c))
        (else (string-append (hex2 (+ #xC0 (div c 64))) (hex2 (+ #x80 (mod c 64)))))))

(test-equal "the form encoding of every char below U+0100, as a name and as a value: kept, +, or upper-case %XX of its UTF-8 bytes"
  (map (lambda (c) (string-append (expected-char c) "=" (expected-char c))) (iota 256))
  (map (lambda (c) (let ((s (string (integer->char c)))) (form-encode (list (cons s s)))))
       (iota 256)))

(test-equal "the form encoding keeps exactly the kept set, and encodes its whole complement below U+0100"
  (list (string->list kept-set) 0)
  (let ((kept (filter (lambda (ch) (string=? (form-encode (list (cons (string ch) ""))) (string ch #\=)))
                      (map integer->char (iota 256)))))
    (list kept
          (length (filter (lambda (c)
                            (let ((ch (integer->char c)))
                              (and (not (memv ch (string->list kept-set)))
                                   (string=? (form-encode (list (cons (string ch) ""))) (string ch #\=)))))
                          (iota 256))))))

(test-equal "the form encoding of one char of each UTF-8 length: A, U+00E9, U+20AC and U+1F600"
  "A=%C3%A9&%E2%82%AC=%F0%9F%98%80"
  (form-encode '(("A" . "\xE9;") ("\x20AC;" . "\x1F600;"))))

(test-equal "the form encoding of a space, +, = and & in names and values, empty names and values, and pairs in the order given"
  "a+b%2Bc%3Dd%26e=f+g%2Bh%3Di%26j&=&%3D=%26&z=1&a=2"
  (form-encode '(("a b+c=d&e" . "f g+h=i&j") ("" . "") ("=" . "&") ("z" . "1") ("a" . "2"))))

(test-equal "the form encoding of no pairs is empty, and anything but a list of string pairs is an assertion violation"
  (list '(returned "") '(raised (assertion form-encode)) '(raised (assertion form-encode))
        '(raised (assertion form-encode)))
  (list (outcome (lambda () (form-encode '())))
        (outcome (lambda () (form-encode '(("a" . 1)))))
        (outcome (lambda () (form-encode '(("a" . "1") . tail))))
        (outcome (lambda () (form-encode "a=1")))))

;; --- private copies of lists ---------------------------------------------------------------

(test-equal "string-pairs copies a list of string pairs whole, in fresh pairs and fresh strings, and answers #f for anything else: an improper list, an element no string pair, a string, a symbol, a cyclic list, each measured by length, which refuses the improper and the cyclic itself"
  (list '(("a" . "1") ("b" . "2")) 'fresh '#(#f #f #f #f #f #f))
  (let* ((given (list (cons (string-copy "a") "1") (cons (string-copy "b") "2")))
         (copy (string-pairs given)))
    (list copy
          (if (and (pair? copy) (not (eq? copy given)) (not (eq? (car copy) (car given)))
                   (not (eq? (caar copy) (caar given))) (not (eq? (cdar copy) (cdar given))))
              'fresh
              'shared)
          (vector (string-pairs '(("a" . "1") . tail)) (string-pairs '(("a" . 1)))
                  (string-pairs '(a)) (string-pairs "a=1") (string-pairs 'pairs)
                  (let ((cycle (list (cons "a" "1") (cons "b" "2"))))
                    (set-cdr! (cdr cycle) cycle)
                    (string-pairs cycle))))))

(test-equal "string-pairs-within reads no more pairs than the length measured: a list of exactly that many is copied, and one longer, shorter, or ending improperly, read in that bound, is #f"
  '((("a" . "1") ("b" . "2")) #f #f #f #f (("a" . "1")))
  (in-order (lambda (row) (string-pairs-within (car row) (cadr row)))
            (list (list '(("a" . "1") ("b" . "2")) 2)
                  (list '(("a" . "1") ("b" . "2") ("c" . "3")) 2)
                  (list '(("a" . "1")) 2)
                  (list '(("a" . "1") . tail) 1)
                  (list '(("a" . "1") ("b" . "2")) 0)
                  (list '(("a" . "1")) 1))))

;; A list made cyclic after string-pairs measured it is what the bound is
;; for: another thread's set-cdr! could otherwise keep the copy looping.
;; The list here is cyclic from the start, and a second thread opens it
;; 100 ms in; a copy bounded by the length 2 answers at once, where an
;; unbounded one loops, copying, until the cycle opens.
(test-equal "string-pairs-within, handed a cyclic list and the length 2, answers #f at once, before another thread opens the cycle 100 ms later"
  '(#f before-open)
  (let* ((cycle (list (cons "a" "1") (cons "b" "2")))
         (lock (make-mutex))
         (opened #f)
         (open? (lambda () (critical-section (with-mutex lock opened)))))
    (set-cdr! (cdr cycle) cycle)
    (fork-thread
     (lambda ()
       (pause-ms 100)
       (critical-section (with-mutex lock (set-cdr! (cdr cycle) '()) (set! opened #t)))))
    (let* ((answer (string-pairs-within cycle 2))
           (seen (if (open?) 'after-open 'before-open)))
      ;; The opener ends before the test does, bounded at 10 s.
      (let wait ((left 1000))
        (unless (or (open?) (= left 0))
          (pause-ms 10)
          (wait (- left 1))))
      (list answer seen))))

;; --- the drive's pre-check ------------------------------------------------------------------

(test-equal "take-refusal? matches the take's own refusal inside a critical section, and nothing else: another who's assertion violation, one with no who, a &error whose who is curl-mailbox-take, and what is no condition"
  '(refusal other other other other)
  (map (lambda (x) (if (take-refusal? x) 'refusal 'other))
       (list (guard (e (#t e)) (critical-section (curl-mailbox-take (make-curl-mailbox) 0)))
             (guard (e (#t e)) (assertion-violation 'my-handler "planted"))
             (condition (make-assertion-violation) (make-message-condition "no who"))
             (condition (make-error) (make-who-condition 'curl-mailbox-take))
             'curl-mailbox-take)))

;; --- the response, constructed ------------------------------------------------------------

(define made-response
  (make-http-response 200 'http/1.1 "http://h.example/" '(("X-k" . "1") ("X-s" . "2") ("x-K" . "3")
                                                         ("X-{" . "4") ("A" . "5") ("a" . "6"))
                      (bytes-of "h\xFF;i") '() '()))

(test-equal "http-response-header answers the first header of a name, A to Z folded alone: not across KELVIN SIGN, LONG S, or [ and {"
  '("1" "1" absent absent "2" absent "5" "5" absent)
  (map (lambda (name) (or (http-response-header made-response name) 'absent))
       '("X-K" "x-k" "X-\x212A;" "X-\x17F;" "X-S" "X-[" "a" "A" "X")))

(test-equal "http-response-text decodes UTF-8: a malformed byte as U+FFFD, and a leading byte-order mark dropped"
  '("h\xFFFD;i" "hi" "\xE9;" "")
  (map (lambda (bytes)
         (http-response-text (make-http-response 200 'http/1.1 "http://h.example/" '() bytes '() '())))
       (list (bytes-of "h\xFF;i") (bytes-of "\xEF;\xBB;\xBF;hi") (bytes-of "\xC3;\xA9;") (bytes-of ""))))

(test-equal "http-response-header and http-response-text refuse what is no response, and a name that is no string"
  '((raised (assertion http-response-header)) (raised (assertion http-response-header))
    (raised (assertion http-response-text)))
  (list (outcome (lambda () (http-response-header 'x "A")))
        (outcome (lambda () (http-response-header made-response 'a)))
        (outcome (lambda () (http-response-text 'x)))))

;; --- the core, by tables -------------------------------------------------------------------

;; Every table starts its call at table-start, a time no clock gives, and
;; requests table-url, with a header and a method of its own.
(define table-start 7000000000123)
(define table-url "http://h.example/p?q=1")

;; table-request : (U Positive-Integer #f) (U Positive-Integer #f) -> Request
(define (table-request bound connect)
  (make-curl-request table-url 'method 'post 'headers '(("X-A" . "1")) 'timeout-ms bound
                     'connect-timeout-ms connect))

;; table-state : (U Positive-Integer #f) (U Positive-Integer #f) -> State
(define (table-state bound connect)
  (make-exchange 'post "http://H.example/p?q=1" (table-request bound connect) bound table-start))

;; parts : Condition (Listof Condition) -> (Listof Any)
;; C's simple conditions, each named: (http-timeout MS), (exchange ...),
;; c for one of OWN's, and other.
(define (parts c own)
  (map (lambda (p)
         (cond ((http-timeout? p) (list 'http-timeout (http-timeout-timeout-ms p)))
               ((http-exchange? p) (list 'exchange (http-exchange-method p) (http-exchange-url p)
                                         (http-exchange-history p) (http-exchange-transfers p)))
               ((memq p own) 'c)
               (else 'other)))
       (simple-conditions c)))

;; submitted : (List Symbol Any ...) Request -> (Listof Any)
;; A submission's answer: (submit TIMEOUT-MS CONNECT-TIMEOUT-MS KEPT
;; IN-FLIGHT TRANSFERS), KEPT whether every other field of the request is
;; ORIGINAL's, IN-FLIGHT whether the state holds it in flight; or (fail
;; PARTS).
(define (submitted answer original)
  (case (car answer)
    ((submit)
     (let ((state (cadr answer)) (sent (caddr answer)))
       (list 'submit (curl-request-timeout-ms sent) (curl-request-connect-timeout-ms sent)
             (if (and (equal? (curl-request-url sent) (curl-request-url original))
                      (eq? (curl-request-method sent) (curl-request-method original))
                      (equal? (curl-request-headers sent) (curl-request-headers original))
                      (eqv? (curl-request-body-limit sent) (curl-request-body-limit original))
                      (eq? (curl-request-verify sent) (curl-request-verify original)))
                 'kept
                 'changed)
             (if (eq? (exchange-flight state) sent) 'in-flight 'not-in-flight)
             (exchange-transfers state))))
    ((fail) (list 'fail (parts (cadr answer) '())))
    (else (list 'unknown answer))))

(define table-exchange-0 '(exchange post "http://H.example/p?q=1" () 0))
(define table-exchange-1 '(exchange post "http://H.example/p?q=1" () 1))

(test-equal "exchange-submission gives a transfer with no connect timeout the time left, rounded up to a whole ms, as both its timeout-ms and its connect-timeout-ms, the request otherwise kept and put in flight; with none left, &http-timeout and &http-exchange alone"
  (list '(submit 400 400 kept in-flight 0) '(submit 400 400 kept in-flight 0)
        '(submit 400 400 kept in-flight 0) '(submit 399 399 kept in-flight 0)
        '(submit 300 300 kept in-flight 0) '(submit 1 1 kept in-flight 0)
        '(submit 1 1 kept in-flight 0)
        (list 'fail (list '(http-timeout 400) table-exchange-0))
        (list 'fail (list '(http-timeout 400) table-exchange-0)))
  (map (lambda (offset)
         (let ((state (table-state 400 #f)))
           (submitted (exchange-submission state (+ table-start offset)) (exchange-request state))))
       '(0 1 999999 1000000 100000000 399000000 399999999 400000000 400000001)))

(test-equal "exchange-submission caps the connect timeout it gives at libcurl's own default, 300000 ms: a bound of 600 s with no connect timeout submits 300000 until less than that is left, then the time left"
  (list '(submit 600000 300000 kept in-flight 0) '(submit 300001 300000 kept in-flight 0)
        '(submit 300000 300000 kept in-flight 0) '(submit 200000 200000 kept in-flight 0))
  (map (lambda (offset)
         (let ((state (table-state 600000 #f)))
           (submitted (exchange-submission state (+ table-start offset)) (exchange-request state))))
       '(0 299999000000 300000000000 400000000000)))

(test-equal "exchange-submission keeps the caller's connect timeout, shorter than the time left or longer, and gives the time left as timeout-ms alone"
  (list '(submit 400 250 kept in-flight 0) '(submit 200 250 kept in-flight 0)
        '(submit 400 900 kept in-flight 0) '(submit 1 900 kept in-flight 0))
  (map (lambda (connect offset)
         (let ((state (table-state 400 connect)))
           (submitted (exchange-submission state (+ table-start offset)) (exchange-request state))))
       '(250 250 900 900)
       '(0 200000000 0 399999999)))

(test-equal "exchange-submission with no bound submits the request as it was, whenever"
  '((as-it-was in-flight) (as-it-was in-flight))
  (map (lambda (offset)
         (let* ((state (table-state #f 300))
                (answer (exchange-submission state (+ table-start offset))))
           (list (if (and (eq? (car answer) 'submit) (eq? (caddr answer) (exchange-request state)))
                     'as-it-was
                     answer)
                 (if (eq? (exchange-flight (cadr answer)) (caddr answer)) 'in-flight 'not-in-flight))))
       '(0 1000000000000)))

;; c28, c7 : Condition
;; A 28, perform-failed, of the class timeout; and a 7, connect.
(define c28 (make-classed-transfer-error 'perform-failed 28 #f "Timeout was reached" #f #f 0))
(define c7 (make-classed-transfer-error 'perform-failed 7 #f "Couldn't connect to server" #f #f 0))
(define stopped (make-curl-engine-error 'stopped #f))

;; stepped : (U Positive-Integer #f) (U Positive-Integer #f) Integer Symbol Condition -> (Listof Any)
;; A call bounded by BOUND, its transfer's connect timeout CONNECT,
;; submitted 100 ms in, so with a bound of 400 its timeout-ms is 300; then
;; its outcome KIND with C, at OFFSET ns from its start: (fail PARTS).
(define (stepped bound connect offset kind c)
  (let* ((submission (exchange-submission (table-state bound connect) (+ table-start 100000000)))
         (step (exchange-step (cadr submission) (list kind c) (+ table-start offset) 1800000000 0.0)))
    (if (eq? (car step) 'fail)
        (list 'fail (parts (cadr step) (simple-conditions c)))
        (list 'not-fail step))))

(test-equal "exchange-step: a 28 is the bound's, with &http-timeout, when the transfer's connect timeout is not shorter than its timeout-ms, the time left, 300: the time left itself, when the caller gave none, 300, 301, and 900, longer than the whole bound; with a shorter one, before the deadline, it is the transfer's own"
  (list (list 'fail (list '(http-timeout 400) 'c table-exchange-1))
        (list 'fail (list '(http-timeout 400) 'c table-exchange-1))
        (list 'fail (list '(http-timeout 400) 'c table-exchange-1))
        (list 'fail (list '(http-timeout 400) 'c table-exchange-1))
        (list 'fail (list 'c table-exchange-1))
        (list 'fail (list 'c table-exchange-1)))
  (list (stepped 400 #f 200000000 'failed c28)
        (stepped 400 300 200000000 'failed c28)
        (stepped 400 301 200000000 'failed c28)
        (stepped 400 900 200000000 'failed c28)
        (stepped 400 299 200000000 'failed c28)
        (stepped 400 299 399999999 'failed c28)))

(test-equal "exchange-step: under a bound of 600 s with no connect timeout, the transfer's is libcurl's 300 s, so a 28 before the deadline is the transfer's own, and one at it the bound's"
  (list (list 'fail (list 'c table-exchange-1))
        (list 'fail (list '(http-timeout 600000) 'c table-exchange-1)))
  (list (stepped 600000 #f 300100000000 'failed c28)
        (stepped 600000 #f 600000000000 'failed c28)))

(test-equal "exchange-step on a state no submission made, its first request in flight with no connect timeout: only the deadline decides, so a 28 before it is the transfer's own, and one at it the bound's"
  (list (list 'fail (list 'c table-exchange-1))
        (list 'fail (list '(http-timeout 400) 'c table-exchange-1)))
  (in-order (lambda (offset)
              (let ((step (exchange-step (table-state 400 #f) (list 'failed c28) (+ table-start offset)
                                         1800000000 0.0)))
                (if (eq? (car step) 'fail)
                    (list 'fail (parts (cadr step) (simple-conditions c28)))
                    (list 'not-fail step))))
            '(200000000 400000000)))

(test-equal "exchange-step: a 28 at or past the deadline is the bound's, whatever the connect timeout"
  (list (list 'fail (list '(http-timeout 400) 'c table-exchange-1))
        (list 'fail (list '(http-timeout 400) 'c table-exchange-1))
        (list 'fail (list '(http-timeout 400) 'c table-exchange-1)))
  (list (stepped 400 299 400000000 'failed c28)
        (stepped 400 299 400000001 'failed c28)
        (stepped 400 1 900000000 'failed c28)))

(test-equal "exchange-step: with no bound a 28 is the transfer's own; a failure that is no 28 never carries &http-timeout"
  (list (list 'fail (list 'c table-exchange-1))
        (list 'fail (list 'c table-exchange-1))
        (list 'fail (list 'c table-exchange-1))
        (list 'fail (list 'c table-exchange-1)))
  (list (stepped #f #f 900000000 'failed c28)
        (stepped #f 100 900000000 'failed c28)
        (stepped 400 #f 900000000 'failed c7)
        (stepped 400 #f 200000000 'failed c7)))

(test-equal "exchange-step: a refused submit counts no transfer, and carries no &http-timeout, even a 28 past the deadline"
  (list (list 'fail (list 'c table-exchange-0))
        (list 'fail (list 'c table-exchange-0))
        (list 'fail (list 'c table-exchange-0)))
  (list (stepped 400 #f 900000000 'refused c28)
        (stepped 400 #f 200000000 'refused stopped)
        (stepped #f #f 200000000 'refused (make-curl-url-error "ftp://x/" 'scheme-not-http #f #f))))

(test-equal "exchange-step refuses an outcome that is none of the three, a draw outside [0, 1), and a time that is no exact integer, each an assertion violation"
  '((raised (assertion exchange-step)) (raised (assertion exchange-step))
    (raised (assertion exchange-step)) (raised (assertion exchange-step))
    (raised (assertion exchange-step)))
  (let ((state (cadr (exchange-submission (table-state 400 #f) table-start))))
    (list (outcome (lambda () (exchange-step state (list 'finished c7) table-start 0 0.0)))
          (outcome (lambda () (exchange-step state (list 'failed 'not-a-condition) table-start 0 0.0)))
          (outcome (lambda () (exchange-step state (list 'response c7) table-start 0 0.0)))
          (outcome (lambda () (exchange-step state (list 'failed c7) table-start 0 1.0)))
          (outcome (lambda () (exchange-step state (list 'failed c7) 1.5 0 0.0))))))

;; --- against the origin --------------------------------------------------------------------

;; --- an escape from the await --------------------------------------------------------

;; escape-await : (-> Any) -> Symbol
;; THUNK, run with a timer whose handler escapes from it once a transfer
;; is live and 200 ms have passed: escaped, or returned if THUNK
;; returned first. The handler re-arms the timer every 200 ticks until
;; then, so it lands in the await's polling.
(define (escape-await thunk)
  (let* ((t0 (now-ms))
         (previous (timer-interrupt-handler))
         (how (call/cc
               (lambda (k)
                 (timer-interrupt-handler
                  (lambda ()
                    (if (and (>= (- (now-ms) t0) 200) (= (count-of 'transfer) 1))
                        (k 'escaped)
                        (set-timer 200))))
                 (set-timer 200)
                 (thunk)
                 'returned))))
    (set-timer 0)
    (timer-interrupt-handler previous)
    how))

;; ended-within : Natural -> Symbol
;; ended once no transfer is live, polled every 10 ms, or still-live
;; once MS ms pass.
(define (ended-within ms)
  (let ((deadline (+ (now-ms) ms)))
    (let loop ()
      (cond ((= (count-of 'transfer) 0) 'ended)
            ((> (now-ms) deadline) 'still-live)
            (else (pause-ms 10) (loop))))))


;; twice-then-once : (Listof Symbol) -> (U 'twice-then-once (Listof Symbol))
;; twice-then-once when HOWS is one twice or more, then one once or more,
;; and nothing else; else HOWS, to show.
(define (twice-then-once hows)
  (let loop ((rest hows) (twice? #f))
    (cond ((null? rest) hows)
          ((eq? (car rest) 'twice) (loop (cdr rest) #t))
          ((and twice? (for-all (lambda (how) (eq? how 'once)) rest)) 'twice-then-once)
          (else hows))))

;; escape-twice : String Natural -> (List Natural Symbol Symbol)
;; A call to URL on a session of its own, escaped from its await by a
;; timer's handler once its transfer is live and 100 ms have passed. That
;; handler sets the timer again, for TICKS, before it escapes, so a second
;; escape lands TICKS ticks into the unwind: in the drive's after thunk,
;; for some TICKS, if its interrupts were on. Answers TICKS, how far the
;; escapes went, once or twice, and whether no transfer is live within 3
;; s, ended, or still-live.
(define (escape-twice url ticks)
  (let* ((own (make-http-session 'timeout-ms 30000))
         (t0 (now-ms))
         (phase 'first)
         (previous (timer-interrupt-handler))
         (how (call/cc
               (lambda (twice)
                 (call/cc
                  (lambda (once)
                    (timer-interrupt-handler
                     (lambda ()
                       (case phase
                         ((first)
                          (if (and (>= (- (now-ms) t0) 100) (= (count-of 'transfer) 1))
                              (begin (set! phase 'second) (set-timer ticks) (once 'once))
                              (set-timer 200)))
                         ((second) (set! phase 'done) (twice 'twice))
                         (else #f))))
                    (set-timer 200)
                    (http-get own url)))
                 (set-timer 0)
                 'once))))
    (set-timer 0)
    (set! phase 'done)
    (timer-interrupt-handler previous)
    (let ((ended (ended-within 3000)))
      (http-session-close own)
      (list ticks how ended))))

;; --- an escape at the end of the submit's critical section, in a child ----------------

;; escape-child : (Listof Datum)
;; A program: it holds its session's engine's mutex from another thread
;; for 3 s, through the private call-with-engine-held, prints (ready PID),
;; and calls URL, its first argument, a 10 s drip, whose submit blocks on
;; that mutex inside the drive's critical section. The suite sends SIGINT
;; about 500 ms after ready: a keyboard interrupt made pending inside a
;; critical section runs as it ends (traps.md), so the handler, which
;; escapes, runs once the submit has returned.
;;
;; The handler records whether the holder had begun to let go, a flag it
;; sets just before it does: after-release shows the escape came once the
;; submit could take the mutex, before-release that SIGINT came before the
;; submit blocked. The engine is not asked. Its queue and its live table
;; are read in two holds, and it moves the token between them, or holds it
;; in neither between taking it from the queue and entering it in the
;; table: the first version of this child read the sum there, and under 24
;; busy loops it read 0 four times and 2 once in 40 runs, where 1 was
;; right. This witness passed 40 of 40 runs so loaded and 40 of 40 idle,
;; and the record-after-section mutant failed 30 of 30
;; (.plans/research/m5/http-client/witness/). For the same reason the
;; settle waits 500 ms past the release, when the engine has set up
;; anything it took, then up to 3 s for it to hold nothing, queued or live.
;;
;; Prints (escape HOW WHEN SETTLED), then (counts COUNTS), once the session
;; is closed.
(define escape-child
  '((import (chezscheme) (curl) (http-client)
            (only (http-client private call) http-session-engine)
            (only (curl private engine) call-with-engine-held curl-engine-live-count
                  curl-engine-queued-count)
            (curl private counters))
    (define url (car (command-line-arguments)))
    (define (now-ms)
      (let ((t (current-time 'time-monotonic)))
        (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))
    (define (held engine) (+ (curl-engine-queued-count engine) (curl-engine-live-count engine)))
    (define session (make-http-session 'timeout-ms 30000))
    (define engine (http-session-engine session))
    (define lock (make-mutex))
    (define holding #f)
    (define letting-go #f)
    (define released #f)
    (define (flag get) (critical-section (with-mutex lock (get))))
    (fork-thread
     (lambda ()
       (call-with-engine-held engine
         (lambda ()
           (critical-section (with-mutex lock (set! holding #t)))
           (sleep (make-time 'time-duration 0 3))
           (critical-section (with-mutex lock (set! letting-go #t)))))
       (critical-section (with-mutex lock (set! released #t)))))
    (let spin ()
      (unless (flag (lambda () holding))
        (sleep (make-time 'time-duration 1000000 0))
        (spin)))
    (define when-escaped #f)
    (define how
      (call/cc
       (lambda (out)
         (keyboard-interrupt-handler
          (lambda ()
            (set! when-escaped (if (flag (lambda () letting-go)) 'after-release 'before-release))
            (out 'escaped)))
         (write (list 'ready (get-process-id)))
         (newline)
         (flush-output-port (current-output-port))
         (http-get session url)
         'returned)))
    (keyboard-interrupt-handler void)
    (let spin ()
      (unless (flag (lambda () released))
        (sleep (make-time 'time-duration 1000000 0))
        (spin)))
    (sleep (make-time 'time-duration 500000000 0))
    (define settled
      (let ((deadline (+ (now-ms) 3000)))
        (let loop ()
          (cond ((= (held engine) 0) 'cancelled)
                ((> (now-ms) deadline) 'still-live)
                (else (sleep (make-time 'time-duration 10000000 0)) (loop))))))
    (write (list 'escape how when-escaped settled))
    (newline)
    (http-session-close session)
    (write (list 'counts (native-counts)))
    (newline)))

;; interrupt-script : String
;; sh -c INTERRUPT-SCRIPT sh COMMAND...: COMMAND under GNU timeout
;; (gtimeout on macOS), killed with SIGKILL after 60 s, its output in a
;; file made under TMPDIR; once it prints (ready PID), 500 ms later,
;; SIGINT to PID, the child Chez itself; then its exit status, and its
;; output but the ready line. Exit 125 with no timeout, 126 when the
;; child never says it is ready, within 20 s.
(define interrupt-script
  (string-append
   "t=$(command -v timeout || command -v gtimeout) || { echo 'http-client escape: no timeout' >&2; exit 125; }\n"
   "out=$(mktemp \"${TMPDIR:-/tmp}/http-client-escape.XXXXXX\") || exit 125\n"
   "\"$t\" -s KILL 60 \"$@\" >\"$out\" 2>&1 </dev/null &\n"
   "waiter=$!\n"
   "n=0\n"
   "until grep -q '^(ready ' \"$out\" || [ \"$n\" -ge 400 ]; do sleep 0.05; n=$((n + 1)); done\n"
   "pid=$(sed -n 's/^(ready \\([0-9]*\\))$/\\1/p' \"$out\")\n"
   "if [ -z \"$pid\" ]; then kill \"$waiter\"; wait \"$waiter\"; cat \"$out\" >&2; rm -f \"$out\"; echo 'http-client escape: the child never said it was ready' >&2; exit 126; fi\n"
   "sleep 0.5\n"
   "kill -INT \"$pid\"\n"
   "wait \"$waiter\"\n"
   "status=$?\n"
   "grep -v '^(ready ' \"$out\"\n"
   "rm -f \"$out\"\n"
   "exit $status\n"))

;; run-escape-child : String -> (List Integer (Listof Any) String)
;; escape-child, written to a directory of its own, run on URL under
;; interrupt-script: its exit status, what it printed but its ready
;; line, read as data, and the script's stderr.
(define (run-escape-child url)
  (guard (e (#t (list 'raised (describe e) "")))
    (call-with-temp-directory
     (lambda (dir)
       (let ((program (string-append dir "/escape-child.sps")))
         (call-with-output-file program
           (lambda (port)
             (for-each (lambda (form) (write form port) (newline port)) escape-child)))
         (let ((r (capture-command (list "sh" "-c" interrupt-script "sh" (getenv "CHEZ")
                                         "--libdirs" (library-path) "--program" program url))))
           (list (car r) (read-all (cadr r)) (caddr r))))))))

(call-with-origin
 (lambda (o)
   ;; url-of : Symbol String -> String
   (define (url-of face path)
     (let ((f (origin-face o face)))
       (string-append "http://" (car f) ":" (number->string (cdr f)) path)))

   ;; host : String
   ;; The http face's address and port, as libcurl writes Host.
   (define host
     (let ((f (origin-face o 'http)))
       (string-append (car f) ":" (number->string (cdr f)))))

   (define echo (url-of 'http "/echo"))

   ;; head-of : String String ... -> String
   ;; /echo's text for a request line METHOD TARGET, then Host and Accept,
   ;; as libcurl sends them with no user agent, then LINES, each a header
   ;; line without its newline, then the blank line.
   (define (head-of method target . lines)
     (apply string-append method " " target " HTTP/1.1\nHost: " host "\nAccept: */*\n"
            (append (map (lambda (line) (string-append line "\n")) lines) (list "\n"))))

   ;; The suite's session for the http face: every call bounded by 20 s.
   (define s (make-http-session 'timeout-ms 20000))

   ;; session-counts : (Listof (Pairof Symbol Natural))
   ;; The counts while the suite's session runs and no transfer is live: its
   ;; engine's multi handle and slot.
   (define session-counts
     '((block . 1) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 1)))

   ;; long-drip : String
   ;; A drip that pauses 10 s mid-body, on the raw face.
   (define long-drip (url-of 'raw "/raw/pause-mid-body?ms=10000"))

   ;; --- the verbs ------------------------------------------------------------------

   (test-equal "each verb sends its method: get and delete with no body, post, put and patch with an empty one, and head, whose echo's length comes back as its Content-Length"
     (list (list 200 (head-of "GET" "/echo"))
           (list 200 (head-of "POST" "/echo" "Content-Length: 0"))
           (list 200 (head-of "PUT" "/echo" "Content-Length: 0"))
           (list 200 (head-of "PATCH" "/echo" "Content-Length: 0"))
           (list 200 (head-of "DELETE" "/echo"))
           (list 200 "" (number->string (string-length (head-of "HEAD" "/echo")))))
     (list (answer (lambda () (http-get s echo)))
           (answer (lambda () (http-post s echo)))
           (answer (lambda () (http-put s echo)))
           (answer (lambda () (http-patch s echo)))
           (answer (lambda () (http-delete s echo)))
           (guard (e (#t (cons 'raised (described e))))
             (let ((r (http-head s echo)))
               (append (echoed r) (list (http-response-header r "Content-Length")))))))

   (test-equal "http-request takes the method as a symbol, each of the six"
     (list (list 200 (head-of "PUT" "/echo" "Content-Length: 0"))
           (list 200 (head-of "GET" "/echo"))
           (list 200 (head-of "DELETE" "/echo"))
           (list 200 (head-of "POST" "/echo" "Content-Length: 0"))
           (list 200 (head-of "PATCH" "/echo" "Content-Length: 0"))
           (list 200 ""))
     (map (lambda (method) (answer (lambda () (http-request s method echo))))
          '(put get delete post patch head)))

   (test-equal "http-request refuses a method the low level does not take, compounded with &http-exchange, no transfer made"
     (list (list 'raised (list 'assertion 'make-curl-request) (list 'exchange 'options echo '() 0))
           (list 'raised (list 'assertion 'make-curl-request) (list 'exchange "GET" echo '() 0)))
     (list (outcome (lambda () (http-request s 'options echo)))
           (outcome (lambda () (http-request s "GET" echo)))))

   ;; --- the merge, live --------------------------------------------------------------

   (test-equal "the merged headers arrive: the session's user agent, its others first, a call's header replacing the session's of its name, then the call's"
     (list 200 (string-append "GET /echo HTTP/1.1\nHost: " host "\nUser-Agent: sess/1\nAccept: */*\n"
                              "X-A: 1\nx-b: 3\nX-C: 4\n\n"))
     (let ((m (make-http-session 'timeout-ms 20000 'headers '(("X-A" . "1") ("X-B" . "2"))
                                 'user-agent "sess/1")))
       (dynamic-wind
         (lambda () #f)
         (lambda () (answer (lambda () (http-get m echo 'headers '(("x-b" . "3") ("X-C" . "4"))))))
         (lambda () (http-session-close m)))))

   (test-equal "the user agent, live: a call's user-agent field replaces a session's User-Agent header, and a call's User-Agent header the session's field, each sent once"
     (list (list 200 (string-append "GET /echo HTTP/1.1\nHost: " host "\nUser-Agent: call/2\nAccept: */*\n"
                                    "X-A: 1\n\n"))
           (list 200 (string-append "GET /echo HTTP/1.1\nHost: " host "\nAccept: */*\n"
                                    "User-Agent: hdr/3\n\n")))
     (let ((m (make-http-session 'timeout-ms 20000 'headers '(("User-Agent" . "hdr/s") ("X-A" . "1"))))
           (n (make-http-session 'timeout-ms 20000 'user-agent "sess/1")))
       (dynamic-wind
         (lambda () #f)
         (lambda ()
           (list (answer (lambda () (http-get m echo 'user-agent "call/2")))
                 (answer (lambda () (http-get n echo 'headers '(("User-Agent" . "hdr/3")))))))
         (lambda () (http-session-close m) (http-session-close n)))))

   (test-equal "a session keeps copies of its strings: a change to the caller's header, user agent or list after the session is made is not sent"
     (list 200 (string-append "GET /echo HTTP/1.1\nHost: " host "\nUser-Agent: ua\nAccept: */*\n"
                              "X-A: 1\n\n"))
     (let* ((value (string-copy "1"))
            (agent (string-copy "ua"))
            (headers (list (cons "X-A" value)))
            (m (make-http-session 'timeout-ms 20000 'headers headers 'user-agent agent)))
       (string-set! value 0 #\9)
       (string-set! agent 0 #\x)
       (set-car! headers (cons "X-Injected" "yes"))
       (dynamic-wind
         (lambda () #f)
         (lambda () (answer (lambda () (http-get m echo))))
         (lambda () (http-session-close m)))))

   ;; --- the bodies -------------------------------------------------------------------

   (test-equal "a string body is sent as its UTF-8 bytes, with no Content-Type; a bytevector as it is"
     (list (list 200 (string-append (head-of "POST" "/echo" "Content-Length: 10")
                                    "h\xC3;\xA9;llo \xE2;\x98;\x83;"))
           (list 200 (string-append (head-of "PUT" "/echo" "Content-Length: 256")
                                    (latin-1 (u8-list->bytevector (iota 256))))))
     (list (answer (lambda () (http-post s echo 'body "h\xE9;llo \x2603;")))
           (answer (lambda () (http-put s echo 'body (u8-list->bytevector (iota 256)))))))

   (test-equal "a form is sent encoded, with the form's Content-Type; with a Content-Type of the call's or the session's in another case, that one alone; an empty form as an empty body, with the type"
     (list (list 200 (string-append (head-of "POST" "/echo"
                                             "Content-Type: application/x-www-form-urlencoded"
                                             "Content-Length: 13")
                                    "a=1&b+c=d%26e"))
           (list 200 (string-append (head-of "PATCH" "/echo" "content-TYPE: text/plain"
                                             "Content-Length: 13")
                                    "a=1&b+c=d%26e"))
           (list 200 (string-append (head-of "PUT" "/echo" "CONTENT-type: text/x"
                                             "Content-Length: 10")
                                    "%E2%9C%93="))
           (list 200 (head-of "DELETE" "/echo" "Content-Type: application/x-www-form-urlencoded"
                              "Content-Length: 0")))
     (let ((typed (make-http-session 'timeout-ms 20000 'headers '(("CONTENT-type" . "text/x")))))
       (dynamic-wind
         (lambda () #f)
         (lambda ()
           (list (answer (lambda () (http-post s echo 'form '(("a" . "1") ("b c" . "d&e")))))
                 (answer (lambda () (http-patch s echo 'form '(("a" . "1") ("b c" . "d&e"))
                                                'headers '(("content-TYPE" . "text/plain")))))
                 (answer (lambda () (http-put typed echo 'form '(("\x2713;" . "")))))
                 (answer (lambda () (http-delete s echo 'form '())))))
         (lambda () (http-session-close typed)))))

   (test-equal "a call's own refusals, each &http-request-error compounded with &http-exchange, no transfer made: body and form, either with get or head, a body neither bytevector nor string, a form or params not a list of string pairs"
     (list (list 'raised '(http-error) '(http-request-error form #f body-and-form)
                 (list 'exchange 'post echo '() 0))
           (list 'raised '(http-error) '(http-request-error body get body-not-allowed)
                 (list 'exchange 'get echo '() 0))
           (list 'raised '(http-error) '(http-request-error form head body-not-allowed)
                 (list 'exchange 'head echo '() 0))
           (list 'raised '(http-error) '(http-request-error body get body-not-allowed)
                 (list 'exchange 'get echo '() 0))
           (list 'raised '(http-error) '(http-request-error body 42 not-a-body)
                 (list 'exchange 'post echo '() 0))
           (list 'raised '(http-error) '(http-request-error body #f not-a-body)
                 (list 'exchange 'put echo '() 0))
           (list 'raised '(http-error) '(http-request-error form "a=1" not-name-value-pairs)
                 (list 'exchange 'post echo '() 0))
           (list 'raised '(http-error) '(http-request-error form (("a" . 1)) not-name-value-pairs)
                 (list 'exchange 'post echo '() 0))
           (list 'raised '(http-error) '(http-request-error params (("a" . "1") . tail) not-name-value-pairs)
                 (list 'exchange 'get echo '() 0))
           (list 'raised '(http-error) '(http-request-error params (a) not-name-value-pairs)
                 (list 'exchange 'get echo '() 0))
           0)
     (let* ((started (transfers-started))
            (refusals
             (in-order (lambda (thunk) (outcome thunk))
                       (list (lambda () (http-post s echo 'body "x" 'form '()))
                             (lambda () (http-get s echo 'body "x"))
                             (lambda () (http-head s echo 'form '()))
                             (lambda () (http-request s 'get echo 'body #vu8()))
                             (lambda () (http-post s echo 'body 42))
                             (lambda () (http-put s echo 'body #f))
                             (lambda () (http-post s echo 'form "a=1"))
                             (lambda () (http-post s echo 'form '(("a" . 1))))
                             (lambda () (http-get s echo 'params '(("a" . "1") . tail)))
                             (lambda () (http-get s echo 'params '(a))))))
            (more (- (transfers-started) started)))
       (append refusals (list more))))

   (test-equal "a call's keys refused by name, compounded with &http-exchange: unknown, redirects among them in slice 1; repeated; missing a value"
     (list (list 'raised '(http-error) '(http-request-error key redirects unknown-key)
                 (list 'exchange 'get echo '() 0))
           (list 'raised '(http-error) '(http-request-error key body repeated-key)
                 (list 'exchange 'post echo '() 0))
           (list 'raised '(http-error) '(http-request-error key form missing-value)
                 (list 'exchange 'post echo '() 0))
           (list 'raised '(http-error) '(http-request-error key method unknown-key)
                 (list 'exchange 'get echo '() 0)))
     (list (outcome (lambda () (http-get s echo 'redirects 3)))
           (outcome (lambda () (http-post s echo 'body "a" 'body "b")))
           (outcome (lambda () (http-post s echo 'timeout-ms 1000 'form)))
           (outcome (lambda () (http-get s echo 'method 'post)))))

   (test-equal "a call's value the low level refuses passes through, compounded with &http-exchange, no &http-error"
     (list (list 'raised '(curl-request-error header-value "a\nb" line-break)
                 (list 'exchange 'get echo '() 0))
           (list 'raised '(assertion make-curl-request) (list 'exchange 'get echo '() 0))
           (list 'raised '(curl-request-error header-name "User-Agent" duplicates-field)
                 (list 'exchange 'get echo '() 0)))
     (list (outcome (lambda () (http-get s echo 'headers '(("X-A" . "a\nb")))))
           (outcome (lambda () (http-get s echo 'timeout-ms 0)))
           (outcome (lambda () (http-get s echo 'user-agent "u" 'headers '(("User-Agent" . "h")))))))

   (test-equal "a call inside a critical section is refused before it submits: an assertion violation from http-request, compounded with &http-exchange, no transfer made, none started"
     (list (list 'raised '(assertion http-request) (list 'exchange 'get echo '() 0)) 0 session-counts)
     (let* ((started (transfers-started))
            (refused (outcome (lambda () (critical-section (http-get s echo)))))
            (more (- (transfers-started) started))
            (counts (native-counts)))
       (list refused more counts)))

   ;; --- params -----------------------------------------------------------------------

   (test-equal "params are appended to a URL with no query, one with a query, and one with a fragment, arriving as encoded, upper-case hex and all; () appends nothing"
     (list (list 200 (head-of "GET" "/echo?a=1&b+c=%C3%A9%3D*"))
           (list 200 (head-of "GET" "/echo?x=y&a=1"))
           (list 200 (head-of "GET" "/echo?a=%7E"))
           (list 200 (head-of "GET" "/echo")))
     (list (answer (lambda () (http-get s echo 'params '(("a" . "1") ("b c" . "\xE9;=*")))))
           (answer (lambda () (http-get s (string-append echo "?x=y") 'params '(("a" . "1")))))
           (answer (lambda () (http-get s (string-append echo "#frag") 'params '(("a" . "~")))))
           (answer (lambda () (http-get s echo 'params '())))))

   (test-equal "http-response-url is the URL requested, params appended, its fragment kept"
     (list (string-append echo "?a=1&b+c=%C3%A9")
           (string-append echo "?x=y&a=1")
           (string-append echo "?a=%7E#frag")
           echo)
     (list (http-response-url (http-get s echo 'params '(("a" . "1") ("b c" . "\xE9;"))))
           (http-response-url (http-get s (string-append echo "?x=y") 'params '(("a" . "1"))))
           (http-response-url (http-get s (string-append echo "#frag") 'params '(("a" . "~"))))
           (http-response-url (http-get s echo 'params '()))))

   (test-equal "http-response-url is the URL curl_url gives back whole, its scheme in lower case and its dot segments removed, with and without params, and that URL is the one requested; &http-exchange keeps the URL as the caller gave it"
     (list (list echo (list 200 (head-of "GET" "/echo")))
           (list (string-append echo "?a=1") (list 200 (head-of "GET" "/echo?a=1")))
           '(raised (curl-transfer-error connect perform-failed 7)
                    (exchange get "HTTP://127.0.0.1:1/a/../x" () 1)))
     (let* ((given (string-append "HTTP://" host "/a/../echo"))
            (plain (http-get s given))
            (with-params (http-get s given 'params '(("a" . "1"))))
            (refused (outcome (lambda () (http-get s "HTTP://127.0.0.1:1/a/../x")))))
       (list (list (http-response-url plain) (echoed plain))
             (list (http-response-url with-params) (echoed with-params))
             refused)))

   ;; --- the response -----------------------------------------------------------------

   (test-equal "every accessor of a response: status, HTTP version, URL, headers, body, timings, history, a header by name and the text"
     (list 200 'http/1.1 (url-of 'http "/status/200")
           '(("Content-Length" . "11") ("Connection" . "keep-alive"))
           "status 200\n" '(name-lookup connect tls-handshake first-byte total) #t '()
           "11" "11" "status 200\n")
     (let ((r (http-get s (url-of 'http "/status/200"))))
       (list (http-response-status r) (http-response-http-version r) (http-response-url r)
             (http-response-headers r) (latin-1 (http-response-body r))
             (map car (http-response-timings r))
             (for-all (lambda (t) (and (integer? (cdr t)) (exact? (cdr t)) (>= (cdr t) 0)))
                      (http-response-timings r))
             (http-response-history r)
             (http-response-header r "content-LENGTH") (http-response-header r "CONTENT-LENGTH")
             (http-response-text r))))

   (test-equal "a status is data: 404, 500 and 503 are answered, never raised"
     '((404 "status 404\n") (500 "status 500\n") (503 "status 503\n"))
     (map (lambda (code)
            (answer (lambda () (http-get s (url-of 'http (string-append "/status/" (number->string code)))))))
          '(404 500 503)))

   ;; --- &http-exchange ---------------------------------------------------------------

   (test-equal "a connect refused on a closed port raises the low level's class, compounded with &http-exchange: the method and URL as given, its user info kept, history (), one transfer; no &http-error"
     (list '(raised (curl-transfer-error connect perform-failed 7)
                    (exchange get "http://u:p@127.0.0.1:1/x" () 1))
           '(raised (curl-transfer-error connect perform-failed 7)
                    (exchange post "http://127.0.0.1:1/y" () 1)))
     (list (outcome (lambda () (http-get s "http://u:p@127.0.0.1:1/x")))
           (outcome (lambda () (http-post s "http://127.0.0.1:1/y" 'form '(("a" . "1")))))))

   (test-equal "a URL refused at the call's start, and one the submit refuses, each compounded with &http-exchange, no transfer made"
     (list '(raised (curl-url-error embedded-nul) (exchange get "http://127.0.0.1:1/\x0;" () 0))
           '(raised (curl-url-error scheme-not-http) (exchange get "ftp://127.0.0.1:1/x" () 0))
           '(raised (assertion curl-url-part) (exchange get not-a-url () 0)))
     (list (outcome (lambda () (http-get s "http://127.0.0.1:1/\x0;")))
           (outcome (lambda () (http-get s "ftp://127.0.0.1:1/x")))
           (outcome (lambda () (http-get s 'not-a-url)))))

   ;; --- the core's response, from a live transfer -------------------------------------

   (test-equal "exchange-step: a response is done, with every field the transfer's, the URL of the request in flight, not the URL as the caller gave it, and no history"
     '(done 200 http/1.1 "http://h.example/p?q=1" #t #t #t ())
     (let* ((engine (make-curl-engine))
            (r (dynamic-wind
                 (lambda () #f)
                 (lambda () (curl-token-await (curl-submit engine (make-curl-request echo))))
                 (lambda () (curl-engine-stop engine))))
            (state (cadr (exchange-submission (table-state 400 #f) (+ table-start 100000000))))
            (step (exchange-step state (list 'response r) (+ table-start 900000000) 1800000000 0.0)))
       (if (eq? (car step) 'done)
           (let ((h (cadr step)))
             (list 'done (http-response-status h) (http-response-http-version h) (http-response-url h)
                   (eq? (http-response-headers h) (curl-response-headers r))
                   (eq? (http-response-body h) (curl-response-body r))
                   (eq? (http-response-timings h) (curl-response-timings r))
                   (http-response-history h)))
           step)))

   ;; --- the call's bound, live ---------------------------------------------------------

   ;; Each on its own session: the raw face closes after every script.
   ;; Measured in the container, on 8.20.0, 10 runs natively: each call
   ;; ended 405 to 407 ms after it started; 3 runs under Valgrind with
   ;; ADR-0014's four flags: 411 to 480, the call's own bound the slowest
   ;; (.plans/research/m5/http-client/timing/). The bound below allows that,
   ;; and fails a 28 that arrived after the drip, 3 s, or a bound doubled.
   (for-each
    (lambda (where)
      (test-equal (string-append "a call's timeout-ms of 400, " (car where)
                                 ", against a 3 s drip raises &http-timeout and the low level's &curl-timeout together, with &http-exchange, one transfer, no sooner than 400 ms and sooner than 800")
        (list (list 'raised '(http-error) '(http-timeout 400)
                    '(curl-transfer-error timeout perform-failed 28)
                    (list 'exchange 'get (url-of 'raw "/raw/pause-mid-body?ms=3000") '() 1))
              'within)
        (let ((own (apply make-http-session (cadr where))))
          (dynamic-wind
            (lambda () #f)
            (lambda ()
              (let* ((start (now-ms))
                     (a (outcome (lambda ()
                                   (apply http-get own (url-of 'raw "/raw/pause-mid-body?ms=3000")
                                          (caddr where)))))
                     (took (- (now-ms) start)))
                (list a (if (and (>= took 400) (< took 800)) 'within (list 'took took)))))
            (lambda () (http-session-close own))))))
    (list (list "the call's" '(timeout-ms 20000) '(timeout-ms 400))
          (list "the session's" '(timeout-ms 400) '())
          (list "the call's, with a shorter connect timeout" '(timeout-ms 20000)
                '(timeout-ms 400 connect-timeout-ms 100))))


   ;; Measured as the bound was, the same runs: the transfer ended 1 to 2
   ;; ms after the escape natively, 6 to 10 under Valgrind.
   (test-equal "an escape from a call's await, by a timer's handler, cancels its transfer: no transfer is live within 3 s, where the drip runs 10 s"
     (list 'escaped 'ended session-counts)
     (let ((own (make-http-session 'timeout-ms 30000)))
       (let* ((how (escape-await (lambda () (http-get own long-drip))))
              (ended (ended-within 3000)))
         (http-session-close own)
         (list how ended (native-counts)))))

   (test-equal "the control: the same escape from a plain curl-token-await, which cancels nothing, leaves the transfer live past 3 s; then cancelled"
     (list 'escaped 'still-live '(transfer-error cancelled) session-counts)
     (let* ((engine (make-curl-engine))
            (token (curl-submit engine (make-curl-request long-drip 'timeout-ms 30000)))
            (how (escape-await (lambda () (curl-token-await token))))
            (ended (ended-within 3000)))
       (curl-token-cancel token)
       (let ((cancelled (guard (e ((curl-transfer-error? e)
                                   (list 'transfer-error (curl-transfer-error-reason e))))
                          (and (curl-token-wait token 10000) (curl-token-await token))
                          '(not-cancelled))))
         (curl-engine-stop engine)
         (list how ended cancelled (native-counts)))))


   (test-equal "a condition the caller's timer handler raises while a call awaits reaches the caller as raised, with no &http-exchange compounded onto it, and the transfer is cancelled"
     (list 'the-planted-condition 'not-compounded 'ended session-counts)
     (let* ((own (make-http-session 'timeout-ms 30000))
            (planted (condition (make-error) (make-message-condition "planted by the suite's timer")))
            (t0 (now-ms))
            (previous (timer-interrupt-handler))
            (caught (guard (e (#t e))
                      (timer-interrupt-handler
                       (lambda ()
                         (if (and (>= (- (now-ms) t0) 100) (= (count-of 'transfer) 1))
                             (raise planted)
                             (set-timer 200))))
                      (set-timer 200)
                      (http-get own long-drip)
                      'returned)))
       (set-timer 0)
       (timer-interrupt-handler previous)
       (let* ((ended (ended-within 3000))
              (closed (http-session-close own))
              (counts (native-counts)))
         (list (if (eq? caught planted) 'the-planted-condition caught)
               (if (and (condition? caught) (http-exchange? caught)) 'compounded 'not-compounded)
               ended counts))))

   (test-equal "a continuable &warning the caller's timer handler raises while a call awaits, which the caller's handler returns from, resumes the call, which answers its response"
     (list 'returned 200 "hello world" 'raised-once session-counts)
     (let* ((own (make-http-session 'timeout-ms 30000))
            (t0 (now-ms))
            (fired #f)
            (previous (timer-interrupt-handler))
            (answer (guard (e (#t (cons 'raised (described e))))
                      (with-exception-handler
                       (lambda (c) (if (warning? c) 'ignored (raise c)))
                       (lambda ()
                         (timer-interrupt-handler
                          (lambda ()
                            (cond (fired #f)
                                  ((and (>= (- (now-ms) t0) 100) (= (count-of 'transfer) 1))
                                   (set! fired #t)
                                   (raise-continuable
                                    (condition (make-warning) (make-message-condition "a tick"))))
                                  (else (set-timer 200)))))
                         (set-timer 200)
                         (let ((r (http-get own (url-of 'raw "/raw/pause-mid-body?ms=1000"))))
                           (list 'returned (http-response-status r)
                                 (latin-1 (http-response-body r)))))))))
       (set-timer 0)
       (timer-interrupt-handler previous)
       (let* ((closed (http-session-close own))
              (counts (native-counts)))
         (append answer (list (if fired 'raised-once 'never-raised) counts)))))

   ;; A Chez engine's expiry is an escape. The call runs in an engine with
   ;; fuel of 50000 ticks, which run out in its await: a call's setup spends
   ;; about 6700 of them and its await about 100 every 10 ms, so the expiry
   ;; lands about 440 ms into the await of a 10 s drip, its transfer live
   ;; (measured, .plans/research/m5/http-client/engine/). Slices of 1000
   ;; ticks raced the engine's thread: an expiry just after the submit
   ;; cancelled the token still queued, before the engine started its
   ;; transfer, so no expiry found it live, in 10 of 10 runs under 24 busy
   ;; loops and none of 10 idle; the suite with them failed 2 of 10 runs
   ;; idle and 10 of 10 loaded.
   (test-equal "a call in a Chez engine whose fuel runs out in its await: the expiry cancels the transfer, which ends before the engine is resumed; resumed, the call raises the low level's cancelled, compounded with &http-exchange, one transfer"
     (list '(expired live ended)
           (list 'raised '(curl-transfer-error none cancelled #f) (list 'exchange 'get long-drip '() 1))
           session-counts)
     (let* ((own (make-http-session 'timeout-ms 30000))
            (engine (make-engine (lambda () (outcome (lambda () (http-get own long-drip))))))
            (first (engine 50000
                           (lambda (ticks value) (list 'completed value))
                           (lambda (next)
                             (let* ((live (if (= (count-of 'transfer) 1) 'live 'not-live))
                                    (ended (ended-within 3000)))
                               (list 'expired live ended next)))))
            (answer (if (eq? (car first) 'expired)
                        ((cadddr first) 100000000
                                        (lambda (ticks value) value)
                                        (lambda (next) 'expired-again))
                        'never-expired))
            (closed (http-session-close own))
            (counts (native-counts)))
       (list (if (eq? (car first) 'expired) (list 'expired (cadr first) (caddr first)) first)
             answer counts)))

   ;; A second escape, landing as the first one unwinds: swept over its
   ;; ticks, 1 to 24, so that some land in the drive's after thunk. With
   ;; that thunk's interrupts on, a plain dynamic-wind, it was cut short
   ;; before its cancel, and the transfer stayed live at ticks 5 to 9, as
   ;; the slice's review found (.plans/research/m5/http-client/
   ;; double-escape/). The critical wind holds the second escape off past
   ;; the unwind, so from the tick that would land in the after thunk on,
   ;; it never comes: ticks 1 to 4 escape twice, before the after thunk,
   ;; and 5 on once. Both kinds seen, in that order, are the sweep's
   ;; evidence that it reached the after thunk; with the plain wind, 1 to 9
   ;; escaped twice.
   (test-equal "a second escape that lands as the first unwinds, at each of ticks 1 to 24, still leaves no transfer live within 3 s; the early ticks escape twice, then the rest once"
     (list (map (lambda (ticks) (list ticks 'ended)) (iota-from 1 24)) 'twice-then-once)
     (let ((rows (in-order (lambda (ticks) (escape-twice long-drip ticks)) (iota-from 1 24))))
       (list (map (lambda (row) (list (car row) (caddr row))) rows)
             (twice-then-once (map cadr rows)))))

   (test-equal "SIGINT while a call's submit blocks inside its critical section escapes as the section ends, after the submit took the mutex, and the drive still cancels the transfer: the engine holds nothing within 3.5 s of the release, where the drip runs 10 s; the child's counts zero"
     (list 0 '((escape escaped after-release cancelled) (counts ((block . 0) (easy . 0) (url . 0) (slist . 0)
                                                     (curl-string . 0) (transfer . 0) (multi . 0))))
           "")
     (run-escape-child long-drip))

   (test-equal "the suite's session closes, and every count is zero after"
     zero-counts
     (begin (http-session-close s) (native-counts)))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "http-client")

(exit (suite-exit-status runner))
