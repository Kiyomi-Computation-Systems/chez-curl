#!r6rs
;;; The suite for the public request (ADR-0023; the M4 plan, sections 3.2 to
;;; 3.4 and 4.2): its keys, its checks and its bodies, its connect timeout,
;;; the response's timings and a failure's request size.
;;;
;;;   - the keys, written out, their defaults, and each one read back;
;;;   - the keys' refusals, unknown-key, missing-value and repeated-key, by
;;;     name and before anything else, with nothing native made;
;;;   - the types each new key takes, and body-not-allowed;
;;;   - curl-request-with, and the private constructors;
;;;   - sent-header-lines, written out: "Content-Type:" and "Expect:" take
;;;     libcurl's own away from a body, unless the request names its own;
;;;   - each method with and without a body, its head as the origin's raw
;;;     face read it, byte for byte, and its body as the http face read it:
;;;     every byte value, and 1,048,577 bytes, past libcurl's Expect
;;;     threshold;
;;;   - the body copied at submit: the engine held across the submit and
;;;     the change, the token caught queued;
;;;   - the connect timeout ending a TLS handshake the server never
;;;     answers, with a control a transfer past its connect phase outlives;
;;;   - the timings, on a plaintext and a TLS pause of 300 ms mid-body;
;;;   - a failure's class and request size: 0 when nothing was sent, the
;;;     head's length when it was; #f, unknown, for one that ran on 8.7.0 or
;;;     8.7.1, whose count is broken, and the library's table of them held to
;;;     this suite's copy (ADR-0022, amended 2026-10-27);
;;;   - no redirect followed, but through the private follow field.
;;;
;;; Each transfer's native counts are the engine's alone after it, and all
;;; zero once the engine stops. Every expected value is one the code under
;;; test cannot produce by failing: SRFI-64 makes #f of a raise in the
;;; actual expression, so none is #f.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) parameterize getenv sleep make-time current-time time-second
              time-nanosecond)
        (curl-testing)
        (curl)
        (curl unsupported)
        (curl private engine)
        (only (curl private transfer) curl-request-fault curl-request-follow
              curl-request-with-fault curl-request-following request-keys request-methods
              sent-header-lines timing-infos live-transfer-count request-size-unreliable
              reported-request-size method-settings sends-body?)
        (curl private counters))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; written : Any -> String
(define (written x) (call-with-string-output-port (lambda (p) (write x p))))

;; shown : Any -> String
;; X written, cut to 3000 characters: a body may be a mebibyte.
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
      (flush-output-port (current-output-port)))))

(test-begin "request")

;; --- helpers --------------------------------------------------------------------------

(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0)))

;; running-counts : (Listof (Pairof Symbol Natural))
;; The counts while the suite's engine runs and no transfer is live: its
;; multi handle and its slot, and nothing else.
(define running-counts
  '((block . 1) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 1)))

;; The load runs here, on this thread, before any engine's thread is forked.
(define version
  (guard (e (#t (list 'no-version (describe e))))
    (libcurl-info-version (loaded-libcurl))))

;; The suite's one engine. Every transfer below runs on it.
(define engine
  (guard (e (#t (list 'raised (describe e))))
    (make-curl-engine)))

(define engine-made? (curl-engine? engine))

;; now-ms : -> Integer
(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

;; pause-ms : Natural -> Unit
(define (pause-ms ms)
  (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))

;; await-token : Token -> Response
;; TOKEN's response, or a raise of what it ended with; a raise of
;; (never-completed MS) when it is not done within a minute, so a check
;; that awaited it fails by name.
(define (await-token token)
  (let ((deadline (+ (now-ms) 60000)))
    (let wait ()
      (cond ((curl-token-done? token) (curl-token-await token))
            ((> (now-ms) deadline) (raise (list 'never-completed 60000)))
            (else (pause-ms 1) (wait))))))

;; perform : Request -> Response
(define (perform r) (await-token (curl-submit engine r)))

;; on-own-engine : Request -> Answer
;; What R answers, through failed, on an engine of its own, made before and
;; stopped after. An engine that cannot be made, or stopped, answers
;; (raised TEXT).
(define (on-own-engine r)
  (guard (e (#t (list 'raised (describe e))))
    (let* ((own (make-curl-engine))
           (answer (failed (lambda () (await-token (curl-submit own r))))))
      (curl-engine-stop own)
      answer)))

;; latin-1 : Bytevector -> String
(define (latin-1 bytes)
  (list->string (map integer->char (bytevector->u8-list bytes))))

;; class-predicates : (Listof (Pairof Symbol (Any -> Boolean)))
(define class-predicates
  (list (cons 'timeout curl-timeout?) (cons 'connect curl-connect-error?)
        (cons 'send-receive curl-send-receive-error?) (cons 'tls curl-tls-error?)
        (cons 'protocol curl-protocol-error?) (cons 'too-large curl-too-large?)))

;; class-of : Any -> (U Symbol (Listof Symbol))
;; C's one class, none for the base type, or every class that holds when
;; more than one does.
(define (class-of c)
  (let ((found (map car (filter (lambda (p) ((cdr p) c)) class-predicates))))
    (cond ((null? found) 'none)
          ((null? (cdr found)) (car found))
          (else found))))

;; failed : (-> Any) -> Any
;; What THUNK raised, whole: (refused REASON CODE CLASS REQUEST-SIZE) for a
;; &curl-transfer-error; (request-refused FIELD VALUE REASON) for a
;; &curl-request-error; (assertion-violation WHO) for an assertion
;; violation; (raised TEXT) for anything else; (no-raise VALUE) when it
;; returned.
(define (failed thunk)
  (guard (e ((curl-transfer-error? e)
             (list 'refused (curl-transfer-error-reason e) (curl-transfer-error-code e)
                   (class-of e) (curl-transfer-error-request-size e)))
            ((curl-request-error? e)
             (list 'request-refused (curl-request-error-field e) (curl-request-error-value e)
                   (curl-request-error-reason e)))
            ((and (assertion-violation? e) (who-condition? e))
             (list 'assertion-violation (condition-who e)))
            (#t (list 'raised (describe e))))
    (list 'no-raise (thunk))))

;; with-counts : Any -> (List Any Counts)
(define (with-counts x) (list x (native-counts)))

;; then-counts : (Listof Any) -> (Listof Any)
;; ANSWERS with the native counts read after them, last: ANSWERS is an
;; argument, so every action in it has run before the counts are read,
;; whatever order a list's arguments are evaluated in (AGENTS.md).
(define (then-counts answers) (append answers (list (native-counts))))

;; url-of : Origin Symbol String -> String
(define (url-of o face path)
  (let ((f (origin-face o face)))
    (string-append "http://" (car f) ":" (number->string (cdr f)) path)))

;; tls-url-of : Origin Symbol String -> String
(define (tls-url-of o face path)
  (let ((f (origin-face o face)))
    (string-append "https://" (car f) ":" (number->string (cdr f)) path)))

;; host-of : Origin Symbol -> String
(define (host-of o face)
  (let ((f (origin-face o face)))
    (string-append (car f) ":" (number->string (cdr f)))))

;; get-head : Origin String -> String
;; The head libcurl sends for a GET of PATH on the raw face, CRLF line ends,
;; written out: what its request size counts.
(define (get-head o path)
  (string-append "GET " path " HTTP/1.1\r\nHost: " (host-of o 'raw) "\r\nAccept: */*\r\n\r\n"))

;; every-byte : Bytevector
;; Each byte value from 0 to 255, once, in order.
(define every-byte
  (let ((b (make-bytevector 256)))
    (let loop ((i 0)) (when (< i 256) (bytevector-u8-set! b i i) (loop (+ i 1))))
    b))

;; big-body : Bytevector
;; 1,048,577 bytes, byte i being (i * 31 + 7) mod 256: one past libcurl's
;; Expect threshold, 1 MiB.
;; bytes-append : Bytevector Bytevector -> Bytevector
(define (bytes-append a b)
  (let ((out (make-bytevector (+ (bytevector-length a) (bytevector-length b)))))
    (bytevector-copy! a 0 out 0 (bytevector-length a))
    (bytevector-copy! b 0 out (bytevector-length a) (bytevector-length b))
    out))

(define big-body
  (let* ((n 1048577) (b (make-bytevector n)))
    (let loop ((i 0)) (when (< i n) (bytevector-u8-set! b i (mod (+ (* i 31) 7) 256)) (loop (+ i 1))))
    b))

;; --- hermetic --------------------------------------------------------------------------

(test-equal "hermetic: none of http_proxy, HTTP_PROXY, https_proxy, HTTPS_PROXY, all_proxy, ALL_PROXY, SSL_CERT_FILE and SSL_CERT_DIR is set"
  '()
  (filter (lambda (name) (getenv name))
          '("http_proxy" "HTTP_PROXY" "https_proxy" "HTTPS_PROXY" "all_proxy" "ALL_PROXY"
            "SSL_CERT_FILE" "SSL_CERT_DIR")))

(test-equal "the suite's engine is made: running, holding its multi handle and nothing else"
  (list 'running running-counts)
  (if engine-made? (list (curl-engine-state engine) (native-counts)) engine))

;; --- the keys --------------------------------------------------------------------------

(test-equal "the keys are exactly method, headers, body, user-agent, timeout-ms, connect-timeout-ms, body-limit, ca-file, verify, proxy, stream-buffer, body-length and http-version, in order"
  '(method headers body user-agent timeout-ms connect-timeout-ms body-limit ca-file verify proxy
    stream-buffer body-length http-version)
  request-keys)

(test-equal "the methods are exactly get, head, post, put, patch and delete, in order"
  '(get head post put patch delete)
  request-methods)

;; request-fields : Request -> (Listof Any)
;; Every field of R, the private two last.
(define (request-fields r)
  (list (curl-request-url r) (curl-request-method r) (curl-request-headers r)
        (curl-request-body r) (curl-request-user-agent r) (curl-request-timeout-ms r)
        (curl-request-connect-timeout-ms r) (curl-request-body-limit r) (curl-request-ca-file r)
        (curl-request-verify r) (curl-request-proxy r) (curl-request-stream-buffer r)
        (curl-request-body-length r) (curl-request-http-version r) (curl-request-fault r)
        (curl-request-follow r)))

(test-equal "a request with no key takes every default: get, no headers, no body, no user agent, no timeouts, no body limit, the system store, verification on, the environment's proxy, the whole body kept, no body-length, no HTTP version; and no fault, no following"
  (list '("http://a/b" get () #f #f #f #f #f #f #t environment #f #f #f #f #f) running-counts)
  (with-counts (request-fields (make-curl-request "http://a/b"))))

;; Each value differs from its default. verify's and proxy's are both #f,
;; the one value each takes but its default; every other key's differs.
(define all-keys
  (list 'method 'put 'headers '(("X-A" . "1")) 'body #vu8(1 2 3) 'user-agent "agent"
        'timeout-ms 4000 'connect-timeout-ms 3000 'body-limit 9 'ca-file "ca.pem" 'verify #f
        'proxy #f 'stream-buffer 65536 'http-version 'http/2-prior-knowledge))

(test-equal "each key sets its own field, in any order"
  (list '("http://a/b" put (("X-A" . "1")) #vu8(1 2 3) "agent" 4000 3000 9 "ca.pem" #f #f 65536 #f http/2-prior-knowledge #f #f)
        '("http://a/b" put (("X-A" . "1")) #vu8(1 2 3) "agent" 4000 3000 9 "ca.pem" #f #f 65536 #f http/2-prior-knowledge #f #f))
  (list (request-fields (apply make-curl-request "http://a/b" all-keys))
        (request-fields (apply make-curl-request "http://a/b"
                       (let loop ((rest all-keys) (pairs '()))
                         (if (null? rest)
                             (apply append pairs)
                             (loop (cddr rest) (cons (list (car rest) (cadr rest)) pairs))))))))

(test-equal "each body method takes a body, and an empty one; get and head take #f"
  '((post #vu8(1)) (put #vu8(1)) (patch #vu8(1)) (delete #vu8(1))
    (post #vu8()) (put #vu8()) (patch #vu8()) (delete #vu8()) (get #f) (head #f))
  (map (lambda (args)
         (let ((r (make-curl-request "http://a/" 'method (car args) 'body (cadr args))))
           (list (curl-request-method r) (curl-request-body r))))
       (list '(post #vu8(1)) '(put #vu8(1)) '(patch #vu8(1)) '(delete #vu8(1))
             '(post #vu8()) '(put #vu8()) '(patch #vu8()) '(delete #vu8()) '(get #f) '(head #f))))

;; --- the keys' refusals ----------------------------------------------------------------

(test-equal "an unknown key is refused by name, before anything else is checked: a symbol no key is, url, fault and follow, a key spelt as a string, and #f; a URL that is no string beside it does not raise first; nothing native is made"
  (list (map (lambda (k) (list 'request-refused 'key k 'unknown-key))
             (list 'nope 'url 'fault 'follow "method" #f))
        '(request-refused key nope unknown-key)
        running-counts)
  (then-counts
   (list (map (lambda (k) (failed (lambda () (make-curl-request "http://a/" k 1))))
              (list 'nope 'url 'fault 'follow "method" #f))
         (failed (lambda () (make-curl-request 42 'nope 1))))))

(test-equal "a key with no value after it is refused as missing-value, naming the key, before its other keys' values are checked; an unknown key with no value is unknown-key"
  '((request-refused key method missing-value)
    (request-refused key verify missing-value)
    (request-refused key nope unknown-key))
  (list (failed (lambda () (make-curl-request "http://a/" 'method)))
        (failed (lambda () (make-curl-request "http://a/" 'timeout-ms -1 'verify)))
        (failed (lambda () (make-curl-request "http://a/" 'method 'get 'nope)))))

(test-equal "a key given twice is refused as repeated-key, naming it, whatever its values, and whether or not they agree"
  '((request-refused key method repeated-key)
    (request-refused key body repeated-key)
    (request-refused key timeout-ms repeated-key))
  (list (failed (lambda () (make-curl-request "http://a/" 'method 'post 'method 'post)))
        (failed (lambda () (make-curl-request "http://a/" 'body #vu8(1) 'verify #t 'body 'not-a-body)))
        (failed (lambda () (make-curl-request "http://a/" 'timeout-ms 'bad 'timeout-ms 'worse)))))

(test-equal "the keys come first, then the URL's type, then each key's type: a URL that is a number with good keys is an assertion violation from make-curl-request"
  '(assertion-violation make-curl-request)
  (failed (lambda () (make-curl-request 42 'method 'get))))

;; --- the new keys' types, and body-not-allowed -----------------------------------------

(test-equal "wrong types are assertion violations from make-curl-request, with nothing native made: a method that is GET, \"get\", options or #f; a body that is a string, a list, 0 or #t; a connect timeout that is 0, -1, 1.5, \"10\" or past a long"
  (list (vector->list (make-vector 13 '(assertion-violation make-curl-request))) running-counts)
  (then-counts
   (list (append
          (map (lambda (m) (failed (lambda () (make-curl-request "http://a/" 'method m))))
               (list 'GET "get" 'options #f))
          (map (lambda (b) (failed (lambda () (make-curl-request "http://a/" 'method 'post 'body b))))
               (list "abc" '(1 2) 0 #t))
          (map (lambda (t) (failed (lambda () (make-curl-request "http://a/" 'connect-timeout-ms t))))
               (list 0 -1 1.5 "10" (expt 2 63)))))))

(test-equal "a body with get or head is refused as body-not-allowed, naming body and the method, an empty body too; with the method left out, get"
  '((request-refused body get body-not-allowed)
    (request-refused body head body-not-allowed)
    (request-refused body get body-not-allowed)
    (request-refused body head body-not-allowed))
  (list (failed (lambda () (make-curl-request "http://a/" 'method 'get 'body #vu8(1))))
        (failed (lambda () (make-curl-request "http://a/" 'method 'head 'body #vu8(1))))
        (failed (lambda () (make-curl-request "http://a/" 'body #vu8())))
        (failed (lambda () (make-curl-request "http://a/" 'body #vu8(9) 'method 'head)))))

(test-equal "a Content-Length or Transfer-Encoding header is still refused, beside a body too: libcurl frames the message"
  '((request-refused header-name "Content-Length" framing-header)
    (request-refused header-name "transfer-encoding" framing-header))
  (list (failed (lambda () (make-curl-request "http://a/" 'method 'post 'body #vu8(1)
                                              'headers '(("Content-Length" . "1")))))
        (failed (lambda () (make-curl-request "http://a/" 'method 'put
                                              'headers '(("transfer-encoding" . "chunked")))))))

;; --- the stream-buffer key (ADR-0030; the M6 plan, section 3.1) -------------------------

(test-equal "stream-buffer takes a positive exact integer, kept, or #f, the default, the whole body; curl-request-with replaces it either way and keeps it when not given; any other value is an assertion violation, from make-curl-request or curl-request-with, with nothing native made: 0, -1, 1.5, 65536.0, \"10\", #t and stream"
  (list '(1 65536 #f 7 #f 3)
        (vector->list (make-vector 7 '(assertion-violation make-curl-request)))
        '(assertion-violation curl-request-with)
        running-counts)
  (then-counts
   (list (list (curl-request-stream-buffer (make-curl-request "http://a/" 'stream-buffer 1))
               (curl-request-stream-buffer (make-curl-request "http://a/" 'stream-buffer 65536))
               (curl-request-stream-buffer (make-curl-request "http://a/" 'stream-buffer #f))
               (curl-request-stream-buffer (curl-request-with (make-curl-request "http://a/") 'stream-buffer 7))
               (curl-request-stream-buffer (curl-request-with (make-curl-request "http://a/" 'stream-buffer 7)
                                                              'stream-buffer #f))
               (curl-request-stream-buffer (curl-request-with (make-curl-request "http://a/" 'stream-buffer 3)
                                                              'method 'post)))
         (map (lambda (v) (failed (lambda () (make-curl-request "http://a/" 'stream-buffer v))))
              (list 0 -1 1.5 65536.0 "10" #t 'stream))
         (failed (lambda () (curl-request-with (make-curl-request "http://a/") 'stream-buffer 0))))))

;; --- the proxy field (ADR-0024, decision 1) ---------------------------------------------

(test-equal "proxy takes environment and #f, each kept, and curl-request-with replaces it either way and keeps it when not given; any other value is an assertion violation, from make-curl-request or curl-request-with, with nothing native made: #t, none, \"environment\", Environment, () and 0"
  (list '(environment #f environment #f #f)
        (vector->list (make-vector 6 '(assertion-violation make-curl-request)))
        '(assertion-violation curl-request-with)
        running-counts)
  (then-counts
   (list (list (curl-request-proxy (make-curl-request "http://a/" 'proxy 'environment))
               (curl-request-proxy (make-curl-request "http://a/" 'proxy #f))
               (curl-request-proxy (curl-request-with (make-curl-request "http://a/" 'proxy #f)
                                                      'proxy 'environment))
               (curl-request-proxy (curl-request-with (make-curl-request "http://a/") 'proxy #f))
               (curl-request-proxy (curl-request-with (make-curl-request "http://a/" 'proxy #f)
                                                      'method 'post)))
         (map (lambda (v) (failed (lambda () (make-curl-request "http://a/" 'proxy v))))
              (list #t 'none "environment" 'Environment '() 0))
         (failed (lambda () (curl-request-with (make-curl-request "http://a/") 'proxy 'direct))))))

;; --- the http-version key (ADR-0034; the M7 plan, section 3.1) ---------------------------

(test-equal "http-version takes http/1.1, http/2 and http/2-prior-knowledge, each kept, or #f, the default, none; curl-request-with replaces it either way and keeps it when not given; any other value is an assertion violation, from make-curl-request or curl-request-with, with nothing native made: http/1.0, http/3, HTTP/2, \"http/2\", h2, 2, #t and ()"
  (list '(http/1.1 http/2 http/2-prior-knowledge #f http/2 #f http/1.1)
        (vector->list (make-vector 8 '(assertion-violation make-curl-request)))
        '(assertion-violation curl-request-with)
        running-counts)
  (then-counts
   (list (list (curl-request-http-version (make-curl-request "http://a/" 'http-version 'http/1.1))
               (curl-request-http-version (make-curl-request "http://a/" 'http-version 'http/2))
               (curl-request-http-version (make-curl-request "http://a/" 'http-version 'http/2-prior-knowledge))
               (curl-request-http-version (make-curl-request "http://a/" 'http-version #f))
               (curl-request-http-version (curl-request-with (make-curl-request "http://a/") 'http-version 'http/2))
               (curl-request-http-version (curl-request-with (make-curl-request "http://a/" 'http-version 'http/2)
                                                             'http-version #f))
               (curl-request-http-version (curl-request-with (make-curl-request "http://a/" 'http-version 'http/1.1)
                                                             'method 'post)))
         (map (lambda (v) (failed (lambda () (make-curl-request "http://a/" 'http-version v))))
              (list 'http/1.0 'http/3 'HTTP/2 "http/2" 'h2 2 #t '()))
         (failed (lambda () (curl-request-with (make-curl-request "http://a/") 'http-version 'http/2.0))))))

(test-equal "http-version http/2-prior-knowledge is not refused as a request is made, an https URL's too: the URL is parsed at submit alone"
  '(http/2-prior-knowledge http/2-prior-knowledge)
  (list (curl-request-http-version (make-curl-request "https://a/" 'http-version 'http/2-prior-knowledge))
        (curl-request-http-version (curl-request-with (make-curl-request "https://a/") 'http-version 'http/2-prior-knowledge))))

;; --- body stream and body-length (ADR-0030; the M6 plan, section 3.1) --------------------

(test-equal "body takes stream with post, put, patch and delete, and body-length sets its own field beside it: a natural, 0 and 2^63 - 2 among them, or #f, the default, kept by curl-request-with when not given and replaced when given; the other fields keep their defaults; nothing native made"
  (list '((post stream 7) (put stream 0) (patch stream 9223372036854775806) (delete stream #f))
        '("http://a/b" post () stream #f #f #f #f #f #t environment #f 7 #f #f #f)
        '("http://a/b" post () stream #f #f #f #f #f #t environment #f 5 #f #f #f)
        '("http://a/b" post () stream #f #f #f #f #f #t environment #f #f #f #f #f)
        running-counts)
  (then-counts
   (list (map (lambda (args)
                (let ((r (make-curl-request "http://a/" 'method (car args) 'body 'stream 'body-length (cadr args))))
                  (list (curl-request-method r) (curl-request-body r) (curl-request-body-length r))))
              (list '(post 7) '(put 0) (list 'patch (- (expt 2 63) 2)) '(delete #f)))
         (request-fields (curl-request-with (make-curl-request "http://a/b" 'method 'post 'body 'stream 'body-length 7)))
         (request-fields (curl-request-with (make-curl-request "http://a/b" 'method 'post 'body 'stream 'body-length 7)
                                            'body-length 5))
         (request-fields (curl-request-with (make-curl-request "http://a/b" 'method 'post 'body 'stream 'body-length 7)
                                            'body-length #f)))))

(test-equal "body-length's wrong types are assertion violations, from make-curl-request and curl-request-with, before anything native: -1, 2^63 - 1, 1.5, 7.0, \"7\", #t and stream; a body that is a symbol but stream, an assertion violation too"
  (list (vector->list (make-vector 7 '(assertion-violation make-curl-request)))
        '(assertion-violation curl-request-with)
        '((assertion-violation make-curl-request) (assertion-violation make-curl-request))
        running-counts)
  (then-counts
   (list (map (lambda (v) (failed (lambda () (make-curl-request "http://a/" 'method 'post 'body 'stream 'body-length v))))
              (list -1 (- (expt 2 63) 1) 1.5 7.0 "7" #t 'stream))
         (failed (lambda () (curl-request-with (make-curl-request "http://a/" 'method 'post 'body 'stream) 'body-length -1)))
         (list (failed (lambda () (make-curl-request "http://a/" 'method 'post 'body 'streams)))
               (failed (lambda () (make-curl-request "http://a/" 'method 'post 'body 'Stream)))))))

(test-equal "a streamed body with get or head is refused as body-not-allowed, naming body and the method; with the method left out, get"
  '((request-refused body get body-not-allowed)
    (request-refused body head body-not-allowed)
    (request-refused body get body-not-allowed))
  (list (failed (lambda () (make-curl-request "http://a/" 'method 'get 'body 'stream)))
        (failed (lambda () (make-curl-request "http://a/" 'method 'head 'body 'stream 'body-length 1)))
        (failed (lambda () (make-curl-request "http://a/" 'body 'stream)))))

(test-equal "a body-length beside a body that does not stream is refused as body-length-without-stream, naming body-length and its value, 0 among them, however the two came together: made beside a whole body or none, a whole body given to a streamed one by curl-request-with, a body-length added to a whole one, and body #f given to a streamed one; body-length #f clears the refusal"
  '((request-refused body-length 10 body-length-without-stream)
    (request-refused body-length 0 body-length-without-stream)
    (request-refused body-length 10 body-length-without-stream)
    (request-refused body-length 4 body-length-without-stream)
    (request-refused body-length 10 body-length-without-stream)
    (returned #vu8(1)))
  (list (failed (lambda () (make-curl-request "http://a/" 'method 'post 'body #vu8(1) 'body-length 10)))
        (failed (lambda () (make-curl-request "http://a/" 'method 'post 'body-length 0)))
        (failed (lambda () (curl-request-with (make-curl-request "http://a/" 'method 'post 'body 'stream 'body-length 10)
                                              'body #vu8(1))))
        (failed (lambda () (curl-request-with (make-curl-request "http://a/" 'method 'post 'body #vu8(1)) 'body-length 4)))
        (failed (lambda () (curl-request-with (make-curl-request "http://a/" 'method 'post 'body 'stream 'body-length 10)
                                              'body #f)))
        (list 'returned
              (curl-request-body (curl-request-with (make-curl-request "http://a/" 'method 'post 'body 'stream 'body-length 10)
                                                    'body #vu8(1) 'body-length #f)))))

(test-equal "method-settings for a streamed body, written out: post, POST and POSTFIELDSIZE_LARGE at the length; put, UPLOAD and INFILESIZE_LARGE; patch and delete, POST, CUSTOMREQUEST and POSTFIELDSIZE_LARGE; the length -1 for none, chunked; and a whole body's, unchanged, for post and put"
  '(((post 7) (("POST" . 1) ("POSTFIELDSIZE_LARGE" . 7)))
    ((post #f) (("POST" . 1) ("POSTFIELDSIZE_LARGE" . -1)))
    ((put 0) (("UPLOAD" . 1) ("INFILESIZE_LARGE" . 0)))
    ((put #f) (("UPLOAD" . 1) ("INFILESIZE_LARGE" . -1)))
    ((patch 5) (("POST" . 1) ("CUSTOMREQUEST" . "PATCH") ("POSTFIELDSIZE_LARGE" . 5)))
    ((delete #f) (("POST" . 1) ("CUSTOMREQUEST" . "DELETE") ("POSTFIELDSIZE_LARGE" . -1)))
    (whole-post (("POSTFIELDSIZE_LARGE" . 2) ("COPYPOSTFIELDS" . #vu8(1 2))))
    (whole-put (("CUSTOMREQUEST" . "PUT") ("POSTFIELDSIZE_LARGE" . 0) ("COPYPOSTFIELDS" . #vu8()))))
  (append (map (lambda (args) (list args (method-settings (car args) 'stream (cadr args))))
               '((post 7) (post #f) (put 0) (put #f) (patch 5) (delete #f)))
          (list (list 'whole-post (method-settings 'post #vu8(1 2) #f))
                (list 'whole-put (method-settings 'put #f #f)))))

(test-equal "sends-body?: a streamed body is sent by post, put, patch and delete, as a whole one is, delete's alone only with one"
  '(#t #t #t #t #f #t #f #f)
  (list (sends-body? 'post 'stream) (sends-body? 'put 'stream) (sends-body? 'patch 'stream)
        (sends-body? 'delete 'stream) (sends-body? 'delete #f) (sends-body? 'delete #vu8())
        (sends-body? 'get #f) (sends-body? 'head #f)))

;; --- curl-request-with, and the private constructors -----------------------------------

(define base (apply make-curl-request "http://a/b" all-keys))

(test-equal "curl-request-with replaces the keys given and keeps the rest; with none, every field"
  (list '("http://a/b" patch (("X-A" . "1")) #vu8(4) "agent" 4000 10 9 "ca.pem" #f #f 65536 #f http/2-prior-knowledge #f #f)
        '("http://a/b" put (("X-A" . "1")) #vu8(1 2 3) "agent" 4000 3000 9 "ca.pem" #f #f 65536 #f http/2-prior-knowledge #f #f))
  (list (request-fields (curl-request-with base 'connect-timeout-ms 10 'method 'patch 'body #vu8(4)))
        (request-fields (curl-request-with base))))

(test-equal "curl-request-with refuses as make-curl-request does, as curl-request-with: an unknown key, a missing value, a repeated key, a wrong type, a body kept with get, and what is no request"
  '((request-refused key url unknown-key)
    (request-refused key body missing-value)
    (request-refused key verify repeated-key)
    (assertion-violation curl-request-with)
    (request-refused body get body-not-allowed)
    (assertion-violation curl-request-with))
  (list (failed (lambda () (curl-request-with base 'url "http://b/")))
        (failed (lambda () (curl-request-with base 'body)))
        (failed (lambda () (curl-request-with base 'verify #t 'verify #t)))
        (failed (lambda () (curl-request-with base 'connect-timeout-ms 0)))
        (failed (lambda () (curl-request-with base 'method 'get)))
        (failed (lambda () (curl-request-with "http://a/" 'method 'get)))))

;; whole : Request
;; base, its whole body kept: following refuses a streamed response
;; (stream-with-rounds, tests/test-stream.sps).
(define whole (curl-request-with base 'stream-buffer #f))

(test-equal "the private constructors set the fault and following, keep every other field, and curl-request-with keeps both"
  (list '("http://a/b" put (("X-A" . "1")) #vu8(1 2 3) "agent" 4000 3000 9 "ca.pem" #f #f 65536 #f http/2-prior-knowledge 2 #f)
        '("http://a/b" put (("X-A" . "1")) #vu8(1 2 3) "agent" 4000 3000 9 "ca.pem" #f #f #f #f http/2-prior-knowledge #f #t)
        '("http://a/b" delete (("X-A" . "1")) #vu8(1 2 3) "agent" 4000 3000 9 "ca.pem" #f #f #f #f http/2-prior-knowledge 2 #t))
  (list (request-fields (curl-request-with-fault base 2))
        (request-fields (curl-request-following whole))
        (request-fields (curl-request-with (curl-request-following (curl-request-with-fault whole 2))
                                   'method 'delete))))

;; --- the header lines --------------------------------------------------------------------

(test-equal "sent-header-lines: each header as its line, then, for a body, whole or streamed, a streamed delete's too, Content-Type: and Expect:, each unless a header of that name, in any case, is given"
  '(()
    ()
    ("X-A: 1" "Content-Type:" "Expect:")
    ("Content-Type:" "Expect:")
    ("Content-Type:" "Expect:")
    ()
    ("Content-Type:" "Expect:")
    ("Content-Type:" "Expect:")
    ("Content-Type: text/plain" "Expect:")
    ("content-type: x" "EXPECT: 100-continue")
    ("X-E;" "expect: y" "Content-Type:")
    ("X-A: 1")
    ("Content-Type:" "Expect:")
    ("Content-Type: text/plain" "Expect:"))
  (list (sent-header-lines '() 'get #f)
        (sent-header-lines '() 'head #f)
        (sent-header-lines '(("X-A" . "1")) 'post #f)
        (sent-header-lines '() 'put #f)
        (sent-header-lines '() 'patch #vu8())
        (sent-header-lines '() 'delete #f)
        (sent-header-lines '() 'delete #vu8(1))
        (sent-header-lines '() 'delete #vu8())
        (sent-header-lines '(("Content-Type" . "text/plain")) 'post #vu8(1))
        (sent-header-lines '(("content-type" . "x") ("EXPECT" . "100-continue")) 'put #vu8(1))
        (sent-header-lines '(("X-E" . "") ("expect" . "y")) 'patch #f)
        (sent-header-lines '(("X-A" . "1")) 'get #f)
        (sent-header-lines '() 'delete 'stream)
        (sent-header-lines '(("Content-Type" . "text/plain")) 'put 'stream)))

(test-equal "the timings are name-lookup, connect, tls-handshake, first-byte and total, in order, each read from its CURLINFO_*_TIME_T"
  '((name-lookup . 6291507) (connect . 6291508) (tls-handshake . 6291512)
    (first-byte . 6291510) (total . 6291506))
  timing-infos)

;; --- the PKI, for the TLS checks ---------------------------------------------------------

(define pki-made
  (guard (e (#t (list 'raised (describe e))))
    (list 'made (make-test-pki))))
(define pki (and (eq? (car pki-made) 'made) (cadr pki-made)))

(test-equal "make-test-pki makes this run's PKI"
  'made
  (car pki-made))

;; ca-file : String
(define ca-file (string-append (or pki "/no-pki") "/ca.pem"))

;; --- the scenarios -------------------------------------------------------------------------

;; Each scenario's outcome, recorded as it ran, and asserted after the
;; origin stops: a test inside call-with-origin would be lost to a raise
;; that ends it.
(define outcomes '())
(define (record! name value) (set! outcomes (cons (cons name value) outcomes)))
(define (outcome name)
  (let ((hit (assq name outcomes))) (if hit (cdr hit) (list 'never-ran name))))

;; heads : the methods and bodies whose heads the raw face echoes, each
;; (METHOD BODY HEAD-TAIL): HEAD-TAIL what follows Accept.
(define heads
  '((get #f "")
    (post #f "Content-Length: 0\r\n")
    (post #vu8(104 101 108 108 111) "Content-Length: 5\r\n")
    (put #f "Content-Length: 0\r\n")
    (put #vu8(104 101 108 108 111) "Content-Length: 5\r\n")
    (patch #f "Content-Length: 0\r\n")
    (patch #vu8(104 101 108 108 111) "Content-Length: 5\r\n")
    (delete #f "")
    (delete #vu8() "Content-Length: 0\r\n")
    (delete #vu8(104 101 108 108 111) "Content-Length: 5\r\n")))

;; method-text : Symbol -> String
(define (method-text m) (string-upcase (symbol->string m)))

(define (scenarios o)
  ;; Each method's head, byte for byte, as the raw face read it: no
  ;; Content-Type and no Expect, a Content-Length for a body, an empty one
  ;; for post, put and patch without one, none for delete without one.
  (record! 'heads
    (map (lambda (h)
           (let ((a (failed (lambda ()
                              (perform (make-curl-request (url-of o 'raw "/raw/echo")
                                                          'method (car h) 'body (cadr h)
                                                          'timeout-ms 20000))))))
             (list (car h) (cadr h)
                   (if (eq? (car a) 'no-raise)
                       (let ((r (cadr a)))
                         (list (curl-response-status r) (latin-1 (curl-response-body r))))
                       a))))
         heads))
  (record! 'heads-counts (native-counts))
  ;; Every byte value, through each body method, as the http face read it.
  (record! 'every-byte
    (map (lambda (m)
           (let ((a (failed (lambda ()
                              (perform (make-curl-request (url-of o 'http "/echo") 'method m
                                                          'body every-byte 'timeout-ms 20000))))))
             (if (eq? (car a) 'no-raise)
                 (let ((r (cadr a)))
                   (list m (curl-response-status r) (curl-response-body r)))
                 (list m a))))
         '(post put patch delete)))
  ;; 1,048,577 bytes, past the Expect threshold.
  (record! 'big
    (let ((a (failed (lambda ()
                       (perform (make-curl-request (url-of o 'http "/echo") 'method 'post
                                                   'body big-body 'timeout-ms 20000))))))
      (if (eq? (car a) 'no-raise) (cadr a) a)))
  ;; The request's own Content-Type and Expect replace libcurl's.
  (record! 'own-headers
    (let ((a (failed (lambda ()
                       (perform (make-curl-request (url-of o 'raw "/raw/echo") 'method 'post
                                                   'body #vu8(97)
                                                   'headers '(("Content-Type" . "application/json")
                                                              ("Expect" . "100-continue"))
                                                   'timeout-ms 20000))))))
      (if (eq? (car a) 'no-raise) (latin-1 (curl-response-body (cadr a))) a)))
  ;; The body copied at submit: the engine held across the submit and the
  ;; change, so the token is still queued when the bytevector changes.
  (record! 'copied
    (let* ((body (string->utf8 "aaaa"))
           (held (failed (lambda ()
                           (call-with-engine-held engine
                             (lambda ()
                               (let ((token (curl-submit
                                             engine
                                             (make-curl-request (url-of o 'http "/echo")
                                                                'method 'put 'body body
                                                                'timeout-ms 20000))))
                                 (bytevector-copy! (string->utf8 "bbbb") 0 body 0 4)
                                 (list token (curl-engine-queued-count engine)
                                       (curl-token-done? token)))))))))
      (if (eq? (car held) 'no-raise)
          (let* ((token (car (cadr held)))
                 (a (failed (lambda () (await-token token)))))
            (list (cdr (cadr held))
                  (if (eq? (car a) 'no-raise) (curl-response-body (cadr a)) a)))
          held)))
  ;; The connect timeout ends a TLS handshake the raw face never answers:
  ;; it reads the ClientHello as the start of a head, and waits.
  (record! 'connect-timeout
    (let* ((start (now-ms))
           (a (failed (lambda ()
                        (perform (make-curl-request (tls-url-of o 'raw "/raw/echo")
                                                    'connect-timeout-ms 300
                                                    'timeout-ms 10000)))))
           (elapsed (- (now-ms) start)))
      (list a (if (and (>= elapsed 300) (< elapsed 2000)) 'within-300-to-2000-ms (list 'took elapsed)))))
  ;; Its control: a transfer past its connect phase outlives the bound.
  (record! 'connect-control
    (let* ((start (now-ms))
           (a (failed (lambda ()
                        (perform (make-curl-request (url-of o 'raw "/raw/pause-mid-body?ms=1000")
                                                    'connect-timeout-ms 300
                                                    'timeout-ms 20000)))))
           (elapsed (- (now-ms) start)))
      (list (if (eq? (car a) 'no-raise)
                (let ((r (cadr a))) (list (curl-response-status r) (latin-1 (curl-response-body r))))
                a)
            (if (>= elapsed 1000) 'past-1-s (list 'took elapsed)))))
  ;; The timings, over plaintext and TLS, each with a pause of 300 ms
  ;; mid-body.
  (record! 'timings
    (map (lambda (url-and-ca)
           (let ((a (failed (lambda ()
                              (perform (make-curl-request (car url-and-ca) 'ca-file (cadr url-and-ca)
                                                          'timeout-ms 20000))))))
             (if (eq? (car a) 'no-raise) (curl-response-timings (cadr a)) a)))
         (list (list (url-of o 'raw "/raw/pause-mid-body?ms=300") #f)
               (list (tls-url-of o 'raw-tls "/raw/pause-mid-body?ms=300") ca-file))))
  ;; A failure's class and request size.
  ;; Each on an engine of its own, its connection pool empty: curl 8.23.0
  ;; reuses, unchecked, a connection that went back to its pool under 1 s
  ;; before, and the raw face closes after each script without saying so, so
  ;; a head sent on a dead connection, then again on a fresh one, counts
  ;; twice (ADR-0020; ADR-0022, amended 2026-10-26). let*, so each runs
  ;; after the last.
  (record! 'failures
    (let* ((refused (on-own-engine (make-curl-request "http://127.0.0.1:1/" 'timeout-ms 20000)))
           (untrusted (on-own-engine (make-curl-request (tls-url-of o 'https-untrusted "/status/200")
                                                        'ca-file ca-file 'timeout-ms 20000)))
           (timeout (on-own-engine (make-curl-request (url-of o 'raw "/raw/stall-before-head")
                                                      'timeout-ms 300)))
           (nothing (on-own-engine (make-curl-request (url-of o 'raw "/raw/close-before-response")
                                                      'timeout-ms 20000)))
           (limit (on-own-engine (make-curl-request (url-of o 'http "/chunked")
                                                    'body-limit 3 'timeout-ms 20000)))
           (raised (on-own-engine (curl-request-with-fault
                                   (make-curl-request (url-of o 'http "/status/200") 'timeout-ms 20000)
                                   1)))
           (setopt (on-own-engine (curl-request-with-options
                                   (make-curl-request (url-of o 'http "/status/200"))
                                   '(("MAXREDIRS" . -2))))))
      (list refused untrusted timeout nothing limit raised setopt)))
  ;; A token cancelled while queued completes with no request size: it is
  ;; taken apart unread.
  (record! 'cancelled
    (let ((token (failed (lambda ()
                           (call-with-engine-held engine
                             (lambda ()
                               (let ((t (curl-submit
                                         engine (make-curl-request (url-of o 'raw "/raw/echo")
                                                                   'timeout-ms 20000))))
                                 (curl-token-cancel t)
                                 t)))))))
      (if (eq? (car token) 'no-raise) (failed (lambda () (await-token (cadr token)))) token)))
  (record! 'heads-for-sizes
    (list (string-length (get-head o "/raw/stall-before-head"))
          (string-length (get-head o "/raw/close-before-response"))
          (string-length (string-append "GET /chunked HTTP/1.1\r\nHost: " (host-of o 'http)
                                        "\r\nAccept: */*\r\n\r\n"))
          (string-length (string-append "GET /status/200 HTTP/1.1\r\nHost: " (host-of o 'http)
                                        "\r\nAccept: */*\r\n\r\n"))))
  ;; No redirect is followed, a POST's included; the private follow field
  ;; follows one.
  (record! 'redirects
    (map (lambda (r)
           (let ((a (failed (lambda () (perform r)))))
             (if (eq? (car a) 'no-raise)
                 (list (curl-response-status (cadr a)) (curl-response-effective-url (cadr a)))
                 a)))
         (list (make-curl-request (url-of o 'http "/redirect/302?to=/status/200")
                                  'method 'post 'body #vu8(1) 'timeout-ms 20000)
               (curl-request-following
                (make-curl-request (url-of o 'http "/redirect/302?to=/status/200")
                                   'timeout-ms 20000)))))
  (record! 'redirect-urls
    (list (url-of o 'http "/redirect/302?to=/status/200") (url-of o 'http "/status/200")))
  (record! 'hosts (list (host-of o 'raw) (host-of o 'http)))
  (record! 'end-counts (native-counts)))

(define scenarios-outcome
  (guard (e (#t (list 'raised (describe e))))
    (parameterize ((origin-pki pki))
      (call-with-origin (lambda (o) (scenarios o) 'done)))))

(test-equal "the scenarios' origin starts with the PKI, serves them all, and stops"
  'done
  scenarios-outcome)

(define raw-host
  (let ((h (outcome 'hosts))) (if (and (list? h) (= (length h) 2) (string? (car h))) (car h) "no-host")))
(define http-host
  (let ((h (outcome 'hosts))) (if (and (list? h) (= (length h) 2) (string? (cadr h))) (cadr h) "no-host")))

(test-equal "each method's head, as the raw face read it, byte for byte: no Content-Type and no Expect; Content-Length 5 for a body, 0 for post, put and patch without one, none for get and delete without one; the counts back to the engine's alone"
  (list (map (lambda (h)
               (list (car h) (cadr h)
                     (list 200 (string-append (method-text (car h)) " /raw/echo HTTP/1.1\r\nHost: "
                                              raw-host "\r\nAccept: */*\r\n" (caddr h) "\r\n"))))
             heads)
        running-counts)
  (list (outcome 'heads) (outcome 'heads-counts)))

(test-equal "every byte value, through post, put, patch and delete, reaches the http face whole, after a head with no Content-Type and no Expect"
  (map (lambda (m)
         (list m 200
               (bytes-append
                (string->utf8 (string-append (method-text m) " /echo HTTP/1.1\nHost: " http-host
                                             "\nAccept: */*\nContent-Length: 256\n\n"))
                every-byte)))
       '(post put patch delete))
  (outcome 'every-byte))

(test-equal "1,048,577 bytes, one past libcurl's Expect threshold, reach the http face whole, with no Expect and no Content-Type"
  (list 200 (bytes-append (string->utf8 (string-append "POST /echo HTTP/1.1\nHost: " http-host
                                                       "\nAccept: */*\nContent-Length: 1048577\n\n"))
                          big-body))
  (let ((r (outcome 'big)))
    (if (curl-response? r) (list (curl-response-status r) (curl-response-body r)) r)))

(test-equal "a request that names its own Content-Type and Expect sends them, in its order, after Accept, in place of libcurl's"
  (string-append "POST /raw/echo HTTP/1.1\r\nHost: " raw-host
                 "\r\nAccept: */*\r\nContent-Type: application/json\r\nExpect: 100-continue\r\nContent-Length: 1\r\n\r\n")
  (outcome 'own-headers))

(test-equal "the body is copied at submit: changed while the engine is held and the token still queued, the origin gets it as it was"
  (list '(1 #f)
        (string->utf8 (string-append "PUT /echo HTTP/1.1\nHost: " http-host
                                     "\nAccept: */*\nContent-Length: 4\n\naaaa")))
  (outcome 'copied))

;; request-size-broken : (Listof String)
;; This suite's copy of the library's request-size-unreliable, written
;; apart: the libcurl versions whose CURLINFO_REQUEST_SIZE answers 0 for
;; every transfer, measured on upstream 8.7.0 and 8.7.1, where 8.6.0 and
;; 8.8.0 answered each request's length (ADR-0022, amended 2026-10-27).
(define request-size-broken '("8.7.0" "8.7.1"))

;; size-broken? : Boolean
;; Whether the loaded libcurl is one of them.
(define size-broken?
  (guard (e (#t #f))
    (and (member (libcurl-info-version (loaded-libcurl)) request-size-broken) #t)))

;; ran-size : Natural -> (U Natural #f)
;; What a transfer that ran reports as its request size here: SIZE, or #f
;; on a libcurl whose count is broken.
(define (ran-size size) (if size-broken? #f size))

(test-equal (string-append "the connect timeout ends a TLS handshake the server never answers: 28, a timeout, with nothing sent, between 300 ms and 2 s, so neither its whole bound, 10 s, nor ten times its own; 2 s leaves the memory gate's Valgrind room, where it took 990 ms; "
                           (if size-broken?
                               "its request size #f, unknown, on this libcurl, whose count is broken"
                               "its request size 0"))
  (list (list 'refused 'perform-failed 28 'timeout (ran-size 0)) 'within-300-to-2000-ms)
  (outcome 'connect-timeout))

(test-equal "the connect timeout bounds the connection phase alone: a transfer that pauses 1 s mid-body, past its 300 ms connect timeout, succeeds"
  '((200 "hello world") past-1-s)
  (outcome 'connect-control))

;; timing-shape : Any Boolean -> Any
;; What T, a response's timings, shows: its names in order, each a natural,
;; then the order of its phases; tls-handshake 0 without TLS, past connect
;; with it; and total at least 250 ms past first-byte, for a pause of 300
;; ms mid-body. Anything else as itself.
(define (timing-shape t tls)
  (if (and (list? t) (for-all pair? t) (equal? (map car t) (map car timing-infos))
           (for-all (lambda (p) (and (integer? (cdr p)) (exact? (cdr p)) (>= (cdr p) 0))) t))
      (let ((lookup (cdr (assq 'name-lookup t))) (connect (cdr (assq 'connect t)))
            (handshake (cdr (assq 'tls-handshake t))) (first (cdr (assq 'first-byte t)))
            (total (cdr (assq 'total t))))
        (list (<= lookup connect) (> connect 0)
              (if tls (and (> handshake connect) (>= first handshake)) (= handshake 0))
              (> first connect) (<= first total) (>= (- total first) 250000)))
      (list 'not-timings t)))

(test-equal "the timings, plaintext and over TLS, with a pause of 300 ms mid-body: name-lookup, connect, tls-handshake, first-byte and total, each a natural, in order; the handshake 0 without TLS and past connect with it; total at least 250 ms past first-byte"
  '((#t #t #t #t #t #t) (#t #t #t #t #t #t))
  (let ((t (outcome 'timings)))
    (if (and (list? t) (= (length t) 2))
        (list (timing-shape (car t) #f) (timing-shape (cadr t) #t))
        t)))

(test-equal "request-size-unreliable, the library's table, is this suite's copy: 8.7.0 and 8.7.1"
  request-size-broken
  request-size-unreliable)

(test-equal "reported-request-size: #f, unknown, for any size on 8.7.0 and 8.7.1; the size itself, 0 among them, on 8.6.0, 8.8.0 and 8.20.0"
  '(#f #f #f 75 0 79)
  (list (reported-request-size "8.7.0" 75) (reported-request-size "8.7.1" 0)
        (reported-request-size "8.7.1" 79) (reported-request-size "8.6.0" 75)
        (reported-request-size "8.8.0" 0) (reported-request-size "8.20.0" 79)))

(test-equal (string-append "a failure's class and request size, each on an engine of its own: a refused connect, 7, connect, and a TLS failure, 60, tls, send nothing, 0; a timeout before the head, 28, a server that closes before answering, 52, send-receive, the body limit, too-large, and a raise in the callable, of no class, sent the head, its length; a setopt the libcurl refuses, 43, the base type, sent nothing, 0; "
                           (if size-broken?
                               "on this libcurl, whose count is broken, each that ran #f, unknown"
                               "each that ran, the size libcurl counted"))
  (let ((sizes (outcome 'heads-for-sizes)))
    (if (and (list? sizes) (= (length sizes) 4))
        (list (list 'refused 'perform-failed 7 'connect (ran-size 0))
              (list 'refused 'perform-failed 60 'tls (ran-size 0))
              (list 'refused 'perform-failed 28 'timeout (ran-size (car sizes)))
              (list 'refused 'perform-failed 52 'send-receive (ran-size (cadr sizes)))
              (list 'refused 'body-limit 23 'too-large (ran-size (caddr sizes)))
              (list 'refused 'callback-raised 23 'none (ran-size (cadddr sizes)))
              '(refused setopt-failed 43 none 0))
        sizes))
  (outcome 'failures))

(test-equal "a token cancelled while queued is of no class, and has no request size: it is taken apart unread"
  '(refused cancelled #f none #f)
  (outcome 'cancelled))

(test-equal "no redirect is followed, a POST's neither; the private follow field follows one"
  (let ((urls (outcome 'redirect-urls)))
    (if (and (list? urls) (= (length urls) 2))
        (list (list 302 (car urls)) (list 200 (cadr urls)))
        urls))
  (outcome 'redirects))

(test-equal "after the scenarios, the counts are the engine's alone"
  running-counts
  (outcome 'end-counts))

(test-equal "once every transfer has ended, the live-transfer table and the engine's are empty"
  '(0 0)
  (list (live-transfer-count) (if engine-made? (curl-engine-live-count engine) engine)))

;; The engine stops before the suite ends: suite-exit-status fails a suite
;; whose counts are not all zero at its end.
(test-equal "the suite's engine stops, and every count is zero after"
  (list 'stopped zero-counts)
  (if engine-made?
      (begin (curl-engine-stop engine) (list (curl-engine-state engine) (native-counts)))
      engine))

(test-end "request")

(exit (suite-exit-status runner))
