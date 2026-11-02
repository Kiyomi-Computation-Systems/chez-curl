#!r6rs
;;; The suite for redirects, the high level's second slice (the M5 plan,
;;; sections 3.4 and 5; ADR-0008, amended 2026-10-27 and 2026-10-28;
;;; ADR-0027; ADR-0029): the redirect rules in exchange-step, the history,
;;; &http-redirect-error, and the session's and the call's keys, redirects
;;; and allow-downgrade.
;;;
;;;   - the keys: taken by a session and a call, a bad value refused by
;;;     name, with no engine made and no transfer; the condition's type, its
;;;     reasons written out, and its constructor's refusal;
;;;   - exchange-step by tables, pure, with no origin: which statuses
;;;     redirect; the first Location, A to Z folded; an empty or blank one;
;;;     the bound, #f, 0 and N; each new URL, a lone # and the fragment
;;;     carried among them; each bad-location, by a URL function's refusal
;;;     and by scheme; the downgrade; the method and the body for every
;;;     status and method, head's among them; the origin rule, by port, by
;;;     scheme, by host, by the host's case and by an explicit default port,
;;;     Host on a change of host alone, and a header dropped for good; the
;;;     next request's other keys; the time left through a redirect; and the
;;;     history;
;;;   - against the origin, with this run's PKI: 300 to 308 with get, post,
;;;     put, patch and delete, at the http face's /echo; the origin rule by
;;;     port, the http face to the raw face's echo, and back; by scheme,
;;;     http to https; by host, localhost; the downgrade refused, and
;;;     allowed; the bound, a loop and #f; each bad-location, through the
;;;     raw face's location script, with a row per libcurl where curl_url
;;;     answers by version; a lone #, and a fragment carried; the history of
;;;     a three-hop call; two Location headers, by version; the call's bound
;;;     across a redirect whose hops each take most of it; and an escape
;;;     from a redirect's await, which cancels that transfer.
;;;
;;; Every check on the origin's raw face makes its own session: the raw face
;;; closes after each script, and curl 8.23.0 resends on each dead pooled
;;; connection (traps.md). The location script says Connection: close, so
;;; its own connections go back to no pool. Every expected value is one the
;;; code under test cannot produce by failing: SRFI-64 makes #f of a raise
;;; in the actual expression, so none is #f. Where curl_url's answer varies
;;; by version, the row below for the libcurl loaded holds it; a libcurl
;;; with no row fails, and the suite prints the row it measured.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) parameterize sleep make-time current-time time-second time-nanosecond
              getenv iota set-timer timer-interrupt-handler)
        (curl-testing)
        (curl)
        (http-client)
        (only (http-client private conditions) make-http-redirect-error)
        (only (http-client private exchange) make-exchange exchange-submission exchange-step
              exchange-request exchange-flight exchange-history exchange-transfers
              exchange-followed make-http-response exchange-steps-past?)
        (only (curl private transfer) transfers-started)
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

(test-begin "redirect")

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
(define (count-of kind) (cdr (assq kind (native-counts))))

;; latin-1 : Bytevector -> String
(define (latin-1 bytes)
  (list->string (map integer->char (bytevector->u8-list bytes))))

;; bytes-of : String -> Bytevector
;; The bytes of S, a string of chars below U+0100, one each.
(define (bytes-of s)
  (u8-list->bytevector (map char->integer (string->list s))))

;; hex2 : Natural -> String
;; %XX for B, upper case.
(define (hex2 b)
  (string #\% (string-ref "0123456789ABCDEF" (div b 16)) (string-ref "0123456789ABCDEF" (mod b 16))))

;; pct : String -> String
;; S, a string of chars below U+0100, each char's byte kept when it is an
;; ASCII letter or digit, -, ., _ or ~, and otherwise %XX: a query value
;; that the origin's faces decode back to those bytes.
(define (pct s)
  (apply string-append
         (map (lambda (ch)
                (let ((b (char->integer ch)))
                  (if (or (<= 48 b 57) (<= 65 b 90) (<= 97 b 122) (memv b '(45 46 95 126)))
                      (string ch)
                      (hex2 b))))
              (string->list s))))

;; class-of : Condition -> Symbol
(define (class-of e)
  (cond ((curl-timeout? e) 'timeout)
        ((curl-connect-error? e) 'connect)
        ((curl-send-receive-error? e) 'send-receive)
        ((curl-tls-error? e) 'tls)
        ((curl-protocol-error? e) 'protocol)
        ((curl-too-large? e) 'too-large)
        (else 'none)))

;; summary : Response -> (List Integer String (Listof Any))
;; A response's status, URL and history, each of the history summarised.
(define (summary r)
  (if (http-response? r)
      (list (http-response-status r) (http-response-url r) (map summary (http-response-history r)))
      (list 'not-a-response r)))

;; described : Any -> (Listof Any)
;; What a raised object is, whole: for a condition, each of these it is, in
;; this order, with its fields; for anything else, (non-condition X).
(define (described e)
  (if (condition? e)
      (filter
       (lambda (x) x)
       (list (and (http-error? e) '(http-error))
             (and (http-request-error? e)
                  (list 'http-request-error (http-request-error-field e) (http-request-error-value e)
                        (http-request-error-reason e)))
             (and (http-redirect-error? e)
                  (list 'http-redirect-error (http-redirect-error-reason e)
                        (http-redirect-error-location e) (summary (http-redirect-error-response e))))
             (and (http-timeout? e) (list 'http-timeout (http-timeout-timeout-ms e)))
             (and (curl-request-error? e)
                  (list 'curl-request-error (curl-request-error-field e) (curl-request-error-value e)
                        (curl-request-error-reason e)))
             (and (curl-url-error? e) (list 'curl-url-error (curl-url-error-reason e)
                                            (curl-url-error-code e)))
             (and (curl-engine-error? e) (list 'curl-engine-error (curl-engine-error-reason e)))
             (and (curl-transfer-error? e)
                  (list 'curl-transfer-error (class-of e) (curl-transfer-error-reason e)
                        (curl-transfer-error-code e)))
             (and (assertion-violation? e)
                  (list 'assertion (and (who-condition? e) (condition-who e))))
             (and (http-exchange? e)
                  (list 'exchange (http-exchange-method e) (http-exchange-url e)
                        (map summary (http-exchange-history e)) (http-exchange-transfers e)))))
      (list 'non-condition e)))

;; outcome : (-> Any) -> (Pairof Symbol Any)
;; (returned VALUE), or (raised . DESCRIBED).
(define (outcome thunk)
  (guard (e (#t (cons 'raised (described e))))
    (list 'returned (thunk))))

;; answer : (-> Response) -> Any
;; What THUNK's call answers: (answered STATUS URL TEXT HISTORY), the body
;; read as Latin-1 and the history summarised; or what it raised.
(define (answer thunk)
  (guard (e (#t (cons 'raised (described e))))
    (let ((r (thunk)))
      (if (http-response? r)
          (list 'answered (http-response-status r) (http-response-url r)
                (latin-1 (http-response-body r)) (map summary (http-response-history r)))
          (list 'not-a-response r)))))

;; in-order : (Any -> Any) (Listof Any) -> (Listof Any)
;; PROC of each of ITEMS, called first to last: map calls its procedure in
;; no fixed order (traps.md).
(define (in-order proc items)
  (let loop ((rest items) (answers '()))
    (if (null? rest)
        (reverse answers)
        (let ((answer (proc (car rest))))
          (loop (cdr rest) (cons answer answers))))))

;; with-session : (Listof Any) (Session -> Any) -> Any
;; PROC's answer, on a session of its own made from PLIST, closed after.
(define (with-session plist proc)
  (let ((session (apply make-http-session plist)))
    (dynamic-wind
      (lambda () #f)
      (lambda () (proc session))
      (lambda () (http-session-close session)))))

;; --- the version rows --------------------------------------------------------------

;; version : String
(define version (guard (e (#t "unknown")) (libcurl-info-version (loaded-libcurl))))

;; location-rows : (Listof (Pairof String (Listof (List Symbol Any ...))))
;; Where curl_url's answer varies by version, each libcurl's, measured by
;; .plans/research/m5/location/ on 7.85.0, Ubuntu's 8.5.0 with OpenSSL and
;; with GnuTLS, Guix's 8.20.0 and 8.23.0; the Mac's 8.7.1 answers as 8.5.0
;; for the URL API (ADR-0008, amended 2026-10-27). Each case is a Location
;; through the raw face's location script, from /raw/location:
;;   javascript  javascript:alert(1)
;;   bad-ipv6    http://[::1/x
;;   ctl         /x, 0x01, y
;;   del         /x, 0x7F, y
;;   two         two Location headers, the http face's /echo first
;; and each answer is (refused CODE), curl_url_set's CURLUcode, so
;; bad-location; (followed PATH), the URL followed, at the raw face, whose
;; 400 is the answer; (first), the first of two followed; or (fails CODE),
;; the transfer's libcurl code.
(define location-rows
  (let ((v8.5 '((javascript refused 5) (bad-ipv6 refused 22) (two first)))
        (v8.20 '((javascript refused 5) (bad-ipv6 refused 22) (two fails 8))))
    (list (cons "7.85.0" '((javascript followed "/raw/javascript:alert(1)") (bad-ipv6 refused 4)
                           (two first)))
          (cons "8.5.0" v8.5)
          (cons "8.7.1" v8.5)
          (cons "8.20.0" v8.20)
          (cons "8.23.0" v8.20))))

;; row-of : Symbol -> (U (List Symbol Any ...) #f)
;; This libcurl's answer for CASE, or #f when it has no row.
(define (row-of case)
  (let ((row (assoc version location-rows)))
    (and row (let ((hit (assq case (cdr row)))) (and hit (cdr hit))))))

;; --- the condition and the keys, pure -------------------------------------------------

(test-equal "http-redirect-error-reasons, written out"
  '(too-many-redirects bad-location insecure-redirect body-not-replayable)
  http-redirect-error-reasons)

(test-equal "&http-redirect-error is under &http-error, &curl-error and &error, and is no request error, timeout or exchange; its fields are what it was made with"
  '(#t #t #t #t #f #f #f bad-location the-response "/x")
  (let ((c (make-http-redirect-error 'bad-location 'the-response "/x")))
    (list (error? c) (curl-error? c) (http-error? c) (http-redirect-error? c)
          (http-request-error? c) (http-timeout? c) (http-exchange? c)
          (http-redirect-error-reason c) (http-redirect-error-response c)
          (http-redirect-error-location c))))

(test-equal "make-http-redirect-error refuses a reason that is not one of the four, an assertion violation"
  '((raised (assertion make-http-redirect-error)) (raised (assertion make-http-redirect-error)))
  (list (outcome (lambda () (make-http-redirect-error 'too-many 'r #f)))
        (outcome (lambda () (make-http-redirect-error 'unknown-key 'r #f)))))

;; Before any session is made here: no engine runs, so the multi count is
;; the suite's own evidence that a refusal made none.
(test-equal "make-http-session refuses a redirects that is no exact natural nor #f, and an allow-downgrade that is no boolean, as &http-request-error, with no engine made"
  (list '(raised (http-error) (http-request-error redirects -1 not-a-redirect-count))
        '(raised (http-error) (http-request-error redirects 1.0 not-a-redirect-count))
        '(raised (http-error) (http-request-error redirects 3/2 not-a-redirect-count))
        '(raised (http-error) (http-request-error redirects "3" not-a-redirect-count))
        '(raised (http-error) (http-request-error redirects #t not-a-redirect-count))
        '(raised (http-error) (http-request-error allow-downgrade yes not-a-boolean))
        '(raised (http-error) (http-request-error allow-downgrade 0 not-a-boolean))
        '(raised (http-error) (http-request-error allow-downgrade () not-a-boolean))
        0)
  (let* ((refusals (in-order (lambda (plist) (outcome (lambda () (apply make-http-session plist))))
                             '((redirects -1) (redirects 1.0) (redirects 3/2) (redirects "3")
                               (redirects #t) (allow-downgrade yes) (allow-downgrade 0)
                               (allow-downgrade ()))))
         (multi (count-of 'multi)))
    (append refusals (list multi))))

(test-equal "make-http-session refuses a repeated redirects and a missing allow-downgrade by name, and a bad value of its own before one the low level refuses, with no engine made"
  (list '(raised (http-error) (http-request-error key redirects repeated-key))
        '(raised (http-error) (http-request-error key allow-downgrade missing-value))
        '(raised (http-error) (http-request-error allow-downgrade 1 not-a-boolean))
        0)
  (let* ((repeated (outcome (lambda () (make-http-session 'redirects 1 'redirects 2))))
         (missing (outcome (lambda () (make-http-session 'redirects 1 'allow-downgrade))))
         (first (outcome (lambda () (make-http-session 'timeout-ms 0 'allow-downgrade 1))))
         (multi (count-of 'multi)))
    (list repeated missing first multi)))

(test-equal "make-http-session takes redirects 0, 5 and #f, and allow-downgrade #t and #f, and call-with-http-session takes them too, each session closed after"
  '((#t #t #t #t #t) session 0)
  (let* ((made (in-order (lambda (plist) (with-session plist (lambda (s) (http-session? s))))
                         '((redirects 0) (redirects 5) (redirects #f) (allow-downgrade #t)
                           (allow-downgrade #f redirects 3 timeout-ms 1000))))
         (called (call-with-http-session 'redirects 7 'allow-downgrade #t
                   (lambda (s) (if (http-session? s) 'session 'other))))
         (multi (count-of 'multi)))
    (list made called multi)))

;; --- exchange-step, by tables ---------------------------------------------------------

;; Every table's call starts at table-start, a time no clock gives, bounded
;; by 5000 ms, as the caller gave it on "http://Given.example/".
(define table-start 7000000000123)
(define given "http://Given.example/")

;; table-request : String Symbol (U Bytevector #f) (Listof (Pairof String String)) -> Request
;; A step's request for URL, METHOD, BODY and HEADERS, with every other key
;; set from its default.
(define (table-request url method body headers)
  (make-curl-request url 'method method 'headers headers 'body body 'user-agent "ua/1"
                     'timeout-ms 5000 'connect-timeout-ms 700 'body-limit 9999
                     'ca-file "/no/ca.pem" 'verify #f 'proxy #f 'http-version 'http/2-prior-knowledge))

;; table-state : Request (U Natural #f) Boolean -> State
(define (table-state request redirects allow-downgrade)
  (make-exchange 'post given request 5000 table-start redirects allow-downgrade))

;; state-at : String [Symbol (U Bytevector #f) (Listof (Pairof String String)) (U Natural #f) Boolean]
;;            -> State
;; A get of URL, no headers, bound 20, no downgrade, unless given.
(define (state-at url . more)
  (let ((method (if (pair? more) (car more) 'get))
        (body (if (> (length more) 1) (cadr more) #f))
        (headers (if (> (length more) 2) (caddr more) '()))
        (redirects (if (> (length more) 3) (cadddr more) 20))
        (allow (if (> (length more) 4) (car (cddddr more)) #f)))
    (table-state (table-request url method body headers) redirects allow)))

;; reply : Integer (Listof (Pairof String String)) -> Response
;; A response a table hands the core: STATUS and HEADERS, a body and
;; timings of its own, and a URL and a history the core replaces.
(define (reply status headers)
  (make-http-response status 'http/1.1 "http://ignored.example/" headers (bytes-of "body")
                      '((total . 1)) (list 'ignored)))

;; heads-seen : (Listof (List Boolean Any))
;; Every row the tables step a response through: whether exchange-step
;; answered next, and what exchange-steps-past? answered for the same
;; state, clocks and draw, given the response as a head, its body and
;; timings #f (the M6 plan, section 6.2).
(define heads-seen '())

;; step : State Response -> Answer
;; The core's answer to RESPONSE, 1 ms into the call; its row noted for the
;; head's predicate.
(define (step state response)
  (let ((a (exchange-step state (list 'response response) (+ table-start 1000000) 1800000000 0.0))
        (head (make-http-response (http-response-status response) (http-response-http-version response) ""
                                  (http-response-headers response) #f #f '())))
    (set! heads-seen
          (cons (list (eq? (car a) 'next)
                      (guard (e (#t (list 'raised (describe e))))
                        (exchange-steps-past? state head (+ table-start 1000000) 1800000000 0.0)))
                heads-seen))
    a))

;; redirect-to : String -> (Listof (Pairof String String))
(define (redirect-to location) (list (cons "Location" location)))

;; seen : Answer -> (Listof Any)
;; An answer, whole enough to compare: (done STATUS URL HISTORY), (next URL
;; METHOD HEADERS BODY WAIT), or (fail . DESCRIBED).
(define (seen answer)
  (case (car answer)
    ((done) (cons 'done (summary (cadr answer))))
    ((next) (let ((request (caddr answer)))
              (list 'next (curl-request-url request) (curl-request-method request)
                    (curl-request-headers request)
                    (let ((b (curl-request-body request))) (and b (latin-1 b)))
                    (cadddr answer))))
    ((fail) (cons 'fail (described (cadr answer))))
    (else (list 'unknown answer))))

;; where : Answer -> (Listof Any)
;; Less: (done STATUS), (next URL METHOD), or (fail REASON).
(define (where answer)
  (case (car answer)
    ((done) (list 'done (http-response-status (cadr answer))))
    ((next) (list 'next (curl-request-url (caddr answer)) (curl-request-method (caddr answer))))
    ((fail) (list 'fail (let ((c (cadr answer)))
                          (if (http-redirect-error? c) (http-redirect-error-reason c) (described c)))))
    (else (list 'unknown answer))))

;; through : State (Listof Response) -> (Listof Answer)
;; Each answer, stepping the state of each next into the following
;; response, until one is not a next, or RESPONSES end.
(define (through state responses)
  (let loop ((state state) (rest responses) (answers '()))
    (if (null? rest)
        (reverse answers)
        (let ((a (step state (car rest))))
          (if (eq? (car a) 'next)
              (loop (cadr a) (cdr rest) (cons a answers))
              (reverse (cons a answers)))))))

(define base "http://h.example/a/b?q=1")

;; --- which responses redirect

(test-equal "exchange-step: a 301, 302, 303, 307 and 308 with a Location redirect; 200, 300, 304, 305, 306, 309, 399 and 400 with one are answered"
  (map (lambda (status)
         (if (memv status '(301 302 303 307 308))
             (list 'next "http://h.example/n" 'get)
             (list 'done status)))
       '(200 300 301 302 303 304 305 306 307 308 309 399 400))
  (map (lambda (status) (where (step (state-at base) (reply status (redirect-to "/n")))))
       '(200 300 301 302 303 304 305 306 307 308 309 399 400)))

(test-equal "exchange-step: the first header named Location, A to Z folded, is read, and no other: not Location2, X-Location, nor LOCATİON, whose U+0130 char-downcase makes i"
  '((next "http://h.example/up" get) (next "http://h.example/lo" get)
    (next "http://h.example/first" get) (done 302) (done 302) (done 302))
  (map (lambda (headers) (where (step (state-at base) (reply 302 headers))))
       (list '(("LOCATION" . "/up"))
             '(("X-A" . "1") ("location" . "/lo"))
             '(("Location" . "/first") ("lOcAtIoN" . "/second"))
             '(("Location2" . "/no") ("X-Location" . "/no"))
             (list (cons "LOCAT\x130;ON" "/no"))
             '())))

(test-equal "exchange-step: an empty Location, and a blank one of SP, HTAB or CR, the lone CR 8.5.0 gives for an empty one among them, is no redirect: the 302 is answered, and a later Location is not read"
  '((done 302) (done 302) (done 302) (done 302) (done 302) (done 302))
  (map (lambda (value)
         (where (step (state-at base) (reply 302 (list (cons "Location" value)
                                                       (cons "Location" "/later"))))))
       '("" " " "\t" "\r" " \t\r " "\r\r")))

;; --- the bound

(test-equal "exchange-step's bound: with redirects #f a redirect is answered; with 0 the first fails as too-many-redirects; with 2, two are followed and the third fails"
  (list '((done 302))
        '((fail too-many-redirects))
        '((next "http://h.example/1" get) (next "http://h.example/2" get) (fail too-many-redirects)))
  (list (map where (through (state-at base 'get #f '() #f) (list (reply 302 (redirect-to "/1")))))
        (map where (through (state-at base 'get #f '() 0) (list (reply 302 (redirect-to "/1")))))
        (map where (through (state-at base 'get #f '() 2)
                            (list (reply 302 (redirect-to "/1")) (reply 307 (redirect-to "/2"))
                                  (reply 301 (redirect-to "/3")))))))

(test-equal "exchange-step's too-many-redirects carries the response that named it, with the history before it, its Location, and &http-exchange with that history and every transfer counted; checked before the Location is read"
  (list 'fail '(http-error)
        (list 'http-redirect-error 'too-many-redirects "ftp://refused.example/"
              (list 301 "http://h.example/2"
                    '((302 "http://h.example/a/b?q=1" ()) (307 "http://h.example/1" ()))))
        (list 'exchange 'post given
              '((302 "http://h.example/a/b?q=1" ()) (307 "http://h.example/1" ())) 3))
  (seen (list-ref (through (state-at base 'get #f '() 2)
                           (list (reply 302 (redirect-to "/1")) (reply 307 (redirect-to "/2"))
                                 (reply 301 (redirect-to "ftp://refused.example/"))))
                  2)))

;; --- the new URL

(test-equal "exchange-step: a Location is resolved against the URL requested, a path, a relative path, a query, a network path and an absolute URL"
  '("http://h.example/x/y?z=1" "http://h.example/a/c" "http://h.example/a/b?r=2"
    "http://other.example/p" "https://h.example/s")
  (map (lambda (location)
         (let ((a (step (state-at base) (reply 302 (redirect-to location)))))
           (if (eq? (car a) 'next) (curl-request-url (caddr a)) (seen a))))
       '("/x/y?z=1" "c" "?r=2" "//other.example/p" "https://h.example/s")))

(test-equal "exchange-step: a Location that is # and a fragment keeps the URL requested, its last segment and its query, the fragment's hex case as given, its other bytes encoded upper case, a # inside kept; a lone # clears the fragment"
  '("http://h.example/a/b?q=1#frag%e9" "http://h.example/a/b?q=1#caf%E9%20x%7F"
    "http://h.example/a/b?q=1#a#b" "http://h.example/a/b?q=1")
  (map (lambda (location)
         (let ((a (step (state-at base) (reply 302 (redirect-to location)))))
           (if (eq? (car a) 'next) (curl-request-url (caddr a)) (seen a))))
       (list "#frag%e9" "#caf\xE9; x\x7F;" "#a#b" "#")))

(test-equal "exchange-step: a Location with no # takes the URL requested's own fragment, as it holds it; one with a fragment of its own keeps that one, an empty one too, which takes none; a # and a fragment replaces it; a lone # clears it"
  '("http://h.example/x#keep%e9" "http://other.example/y?z#keep%e9" "http://h.example/x#own"
    "http://h.example/x" "http://h.example/a/b?q=1#new" "http://h.example/a/b?q=1")
  (map (lambda (location)
         (let ((a (step (state-at "http://h.example/a/b?q=1#keep%e9") (reply 302 (redirect-to location)))))
           (if (eq? (car a) 'next) (curl-request-url (caddr a)) (seen a))))
       '("/x" "http://other.example/y?z" "/x#own" "/x#" "#new" "#")))

;; --- bad-location

;; refused-as : String (U (List Symbol (U Natural #f)) #f) -> (Listof Any)
;; The fail a 302 to LOCATION from base makes: bad-location, its response,
;; URL-ERROR's reason and code when one is compounded, and the context.
(define (refused-as location url-error)
  (append (list 'fail '(http-error)
                (list 'http-redirect-error 'bad-location location (list 302 base '())))
          (if url-error (list (cons 'curl-url-error url-error)) '())
          (list (list 'exchange 'post given '() 1))))

(test-equal "exchange-step's bad-location: refused by curl-url-resolve, compounded with its &curl-url-error, an unknown scheme, a port above 65535, a 0x00, and a Latin-1 host whose answer is not UTF-8; refused by curl-url-with-fragment, a 0x00 after a #; and a scheme that is not http or https, with none"
  (list (refused-as "foo://bar/x" '(unsupported-scheme 5))
        (refused-as "http://h.example:99999/x" '(bad-port-number 4))
        (refused-as "/a\x0;b" '(embedded-nul #f))
        (refused-as "http://caf\xE9;.example/" '(not-utf-8 #f))
        (refused-as "#a\x0;b" '(embedded-nul #f))
        (refused-as "ftp://h.example/f" #f)
        (refused-as "file:///etc/passwd" #f)
        (refused-as "FTP://h.example/f" #f))
  (map (lambda (location) (seen (step (state-at base) (reply 302 (redirect-to location)))))
       (list "foo://bar/x" "http://h.example:99999/x" "/a\x0;b" "http://caf\xE9;.example/" "#a\x0;b"
             "ftp://h.example/f" "file:///etc/passwd" "FTP://h.example/f")))

;; --- the downgrade

(test-equal "exchange-step's downgrade: https to http fails as insecure-redirect, carrying the response and its Location, unless allow-downgrade; http to https, https to https and a network path from https are followed"
  (list (list 'fail '(http-error)
              (list 'http-redirect-error 'insecure-redirect "http://h.example/x"
                    '(302 "https://h.example/a" ()))
              (list 'exchange 'post given '() 1))
        (list 'fail '(http-error)
              (list 'http-redirect-error 'insecure-redirect "HTTP://h.example:443/x"
                    '(302 "https://h.example/a" ()))
              (list 'exchange 'post given '() 1))
        '(next "http://h.example/x" get)
        '(next "https://h.example/x" get)
        '(next "https://other.example/y" get)
        '(next "https://h.example/n" get))
  (list (seen (step (state-at "https://h.example/a") (reply 302 (redirect-to "http://h.example/x"))))
        (seen (step (state-at "https://h.example/a") (reply 302 (redirect-to "HTTP://h.example:443/x"))))
        (where (step (state-at "https://h.example/a" 'get #f '() 20 #t)
                     (reply 302 (redirect-to "http://h.example/x"))))
        (where (step (state-at "http://h.example/a") (reply 302 (redirect-to "https://h.example/x"))))
        (where (step (state-at "https://h.example/a") (reply 302 (redirect-to "https://other.example/y"))))
        (where (step (state-at "https://h.example/a") (reply 302 (redirect-to "//h.example/n"))))))

;; --- the method and the body

;; body-headers : (Listof (Pairof String String))
;; A call's headers: the body's, Content-*, Digest and Last-Modified, in A
;; to Z cases of their own, and some that only look like them.
(define body-headers
  '(("Content-Type" . "text/x") ("X-Keep" . "1") ("content-language" . "en") ("DIGEST" . "sha-256=x")
    ("Last-modified" . "Tue") ("expect" . "100-continue") ("Content" . "kept")
    ("X-Content-Type" . "kept") ("Digests" . "kept") ("Last-Modified-By" . "kept")
    ("Expects" . "kept")))

;; kept-headers : (Listof (Pairof String String))
;; body-headers without the body's.
(define kept-headers
  '(("X-Keep" . "1") ("Content" . "kept") ("X-Content-Type" . "kept") ("Digests" . "kept")
    ("Last-Modified-By" . "kept") ("Expects" . "kept")))

;; method-rows : (Listof (List Integer Symbol Symbol Symbol))
;; Written out: STATUS, METHOD, the method followed, and whether the body
;; and its headers are kept or dropped (RFC 9110, section 15.4).
(define method-rows
  '((301 get get kept) (301 head head kept) (301 post get dropped) (301 put put kept)
    (301 patch patch kept) (301 delete delete kept)
    (302 get get kept) (302 head head kept) (302 post get dropped) (302 put put kept)
    (302 patch patch kept) (302 delete delete kept)
    (303 get get dropped) (303 head head kept) (303 post get dropped) (303 put get dropped)
    (303 patch get dropped) (303 delete get dropped)
    (307 get get kept) (307 head head kept) (307 post post kept) (307 put put kept)
    (307 patch patch kept) (307 delete delete kept)
    (308 get get kept) (308 head head kept) (308 post post kept) (308 put put kept)
    (308 patch patch kept) (308 delete delete kept)))

;; table-body : Symbol -> (U Bytevector #f)
;; The body a table's METHOD sends: none for get and head.
(define (table-body method) (if (memq method '(get head)) #f (bytes-of "b=1")))

(test-equal "exchange-step's method and body, for each redirecting status and every method, head's among them: a 301 and a 302 make a post a get, a 303 every method but head, each without its body and its headers, Content-*, Digest, Last-Modified and Expect in any case; every other is kept, its body and every header too"
  (map (lambda (row)
         (let ((kept (eq? (cadddr row) 'kept)) (method (cadr row)))
           (list (car row) method
                 (list 'next "http://h.example/n" (caddr row) (if kept body-headers kept-headers)
                       (and kept (table-body method) "b=1") 0))))
       method-rows)
  (map (lambda (row)
         (let ((method (cadr row)))
           (list (car row) method
                 (seen (step (state-at base method (table-body method) body-headers)
                             (reply (car row) (redirect-to "/n")))))))
       method-rows))

;; --- the origin

;; origin-headers : (Listof (Pairof String String))
;; The credentials, in cases of their own, Host, and two that follow.
(define origin-headers
  '(("Authorization" . "Bearer a") ("cookie" . "c=1") ("PROXY-AUTHORIZATION" . "Basic p")
    ("HOST" . "h.example") ("X-Api-Key" . "k") ("Authorization-X" . "kept")))

(define without-credentials '(("HOST" . "h.example") ("X-Api-Key" . "k") ("Authorization-X" . "kept")))
(define without-host '(("X-Api-Key" . "k") ("Authorization-X" . "kept")))

;; headers-after : String String -> (Listof (Pairof String String))
;; The headers the next request carries, from URL with origin-headers,
;; after a 302 to LOCATION.
(define (headers-after url location)
  (let ((a (step (state-at url 'get #f origin-headers) (reply 302 (redirect-to location)))))
    (if (eq? (car a) 'next) (curl-request-headers (caddr a)) (seen a))))

(test-equal "exchange-step's origin rule: the same origin keeps every header, by the host's case and by an explicit default port too; another port or scheme, the scheme alone on one port among them, drops Authorization, Cookie and Proxy-Authorization, in any case, and keeps Host; another host drops Host too, in any case, and so does another zone ID of one IPv6 address, or none; every other header follows"
  (list origin-headers origin-headers origin-headers origin-headers
        without-credentials without-credentials without-credentials without-host without-host
        origin-headers without-host without-host)
  (list (headers-after "http://h.example/p" "/same")
        (headers-after "http://h.example/p" "http://H.EXAMPLE/case")
        (headers-after "http://h.example/p" "http://h.example:80/port")
        (headers-after "https://h.example/p" "https://h.example:443/port")
        (headers-after "http://h.example/p" "http://h.example:8080/")
        (headers-after "http://h.example/p" "https://h.example/")
        (headers-after "http://h.example:8443/p" "https://h.example:8443/x")
        (headers-after "http://h.example/p" "http://other.example/")
        (headers-after "http://h.example/p" "http://h.example.other/")
        (headers-after "http://[fe80::1%25eth0]/p" "/same")
        (headers-after "http://[fe80::1%25eth0]/p" "http://[fe80::1%25eth1]/q")
        (headers-after "http://[fe80::1%25eth0]/p" "http://[fe80::1]/q")))

;; credentials-after : String String -> Any
;; The credentials the next request carries, from URL with Digest
;; credentials and no header, after a 302 to LOCATION.
(define (credentials-after url location)
  (let ((a (step (table-state (curl-request-with (table-request url 'get #f '()) 'credentials '(digest "u" "p"))
                              20 #f)
                 (reply 302 (redirect-to location)))))
    (if (eq? (car a) 'next) (curl-request-credentials (caddr a)) (seen a))))

(test-equal "exchange-step's origin rule for the credentials key (ADR-0036; the M7 plan, section 3.1): the same origin keeps it, by the host's case and by an explicit default port too; another port, scheme, the scheme alone on one port among them, host, and zone ID drop it, as they drop an Authorization header"
  '((digest "u" "p") (digest "u" "p") (digest "u" "p") (digest "u" "p")
    dropped dropped dropped dropped dropped dropped)
  (map (lambda (c) (or c 'dropped))
       (list (credentials-after "http://h.example/p" "/same")
             (credentials-after "http://h.example/p" "http://H.EXAMPLE/case")
             (credentials-after "http://h.example/p" "http://h.example:80/port")
             (credentials-after "https://h.example/p" "https://h.example:443/port")
             (credentials-after "http://h.example/p" "http://h.example:8080/")
             (credentials-after "http://h.example/p" "https://h.example/")
             (credentials-after "http://h.example:8443/p" "https://h.example:8443/x")
             (credentials-after "http://h.example/p" "http://other.example/")
             (credentials-after "http://[fe80::1%25eth0]/p" "http://[fe80::1%25eth1]/q")
             (credentials-after "http://[fe80::1%25eth0]/p" "http://[fe80::1]/q"))))

(test-equal "exchange-step: a header dropped stays dropped, through a hop back to the first origin"
  (list without-host without-host)
  (map (lambda (a) (if (eq? (car a) 'next) (curl-request-headers (caddr a)) (seen a)))
       (cdr (through (state-at "http://h.example/p" 'get #f origin-headers)
                     (list (reply 302 (redirect-to "http://other.example/q"))
                           (reply 302 (redirect-to "http://h.example/p"))
                           (reply 302 (redirect-to "/back")))))))

(test-equal "exchange-step: a submit refused after a redirect fails with what refused it and the history so far, and counts no transfer of its own"
  (list 'next (list 'fail '(curl-url-error bad-port-number 4)
                    (list 'exchange 'post given '((302 "http://h.example/a/b?q=1" ())) 1)))
  (let ((a (step (state-at base) (reply 302 (redirect-to "/n"))))
        (refusal (guard (e (#t e)) (curl-url-part "http://h.example:99999/" 'host))))
    (list (car a)
          (if (eq? (car a) 'next)
              (seen (exchange-step (cadr a) (list 'refused refusal) (+ table-start 2000000)
                                   1800000000 0.0))
              (seen a)))))

;; --- the next request, and its time

(test-equal "exchange-step's next request: its URL, every other key the step's request's, the call's timeout-ms among them, not the time left in flight, and its http-version; the state holds it as its request and in flight; the wait is 0"
  '("http://h.example/n" get "ua/1" 5000 700 9999 "/no/ca.pem" #f #f http/2-prior-knowledge same same 0 1)
  (let* ((submitted (exchange-submission (state-at base) (+ table-start 3000000000)))
         (a (exchange-step (cadr submitted) (list 'response (reply 302 (redirect-to "/n")))
                           (+ table-start 3100000000) 1800000000 0.0)))
    (if (eq? (car a) 'next)
        (let ((state (cadr a)) (r (caddr a)))
          (list (curl-request-url r) (curl-request-method r) (curl-request-user-agent r)
                (curl-request-timeout-ms r) (curl-request-connect-timeout-ms r)
                (curl-request-body-limit r) (curl-request-ca-file r) (curl-request-verify r)
                (curl-request-proxy r) (curl-request-http-version r)
                (if (eq? (exchange-request state) r) 'same 'other)
                (if (eq? (exchange-flight state) r) 'same 'other)
                (cadddr a) (exchange-followed state)))
        (seen a))))

(test-equal "a redirect's request, through exchange-submission, gets the time left of the call's bound: 5000 ms from the start, 3100 in, it is 1900, its connect timeout the caller's 700; past the bound, &http-timeout before any submit"
  (list '(submit 1900 700)
        (list 'fail '(http-error) '(http-timeout 5000)
              (list 'exchange 'post given '((302 "http://h.example/a/b?q=1" ())) 1)))
  (let* ((submitted (exchange-submission (state-at base) table-start))
         (a (exchange-step (cadr submitted) (list 'response (reply 302 (redirect-to "/n")))
                           (+ table-start 3100000000) 1800000000 0.0)))
    (if (eq? (car a) 'next)
        (list (let ((s (exchange-submission (cadr a) (+ table-start 3100000000))))
                (if (eq? (car s) 'submit)
                    (list 'submit (curl-request-timeout-ms (caddr s))
                          (curl-request-connect-timeout-ms (caddr s)))
                    (seen s)))
              (let ((s (exchange-submission (cadr a) (+ table-start 5000000000))))
                (if (eq? (car s) 'fail) (seen s) (list 'submitted s))))
        (seen a))))

;; --- the history

(test-equal "exchange-step's history: each followed response joins it, oldest first, with the URL it was requested at and a history of (); the answer carries it, and the transfers count each"
  (list '(next next next done)
        (list 200 "http://h.example/3"
              '((301 "http://h.example/a/b?q=1" ()) (302 "http://h.example/1" ())
                (307 "http://h.example/2" ())))
        '(3 4))
  (let* ((answers (through (state-at base)
                           (list (reply 301 (redirect-to "/1")) (reply 302 (redirect-to "/2"))
                                 (reply 307 (redirect-to "/3")) (reply 200 '()))))
         (last (list-ref answers 3))
         (state (cadr (list-ref answers 2))))
    (list (map car answers)
          (summary (cadr last))
          (list (length (exchange-history state)) (+ (exchange-transfers state) 1)))))

(test-equal "exchange-step: each history response keeps its own status, headers, body and timings"
  '((301 http/1.1 (("Location" . "/1")) "body" ((total . 1))))
  (let ((answers (through (state-at base) (list (reply 301 (redirect-to "/1")) (reply 200 '())))))
    (map (lambda (r)
           (list (http-response-status r) (http-response-http-version r) (http-response-headers r)
                 (latin-1 (http-response-body r)) (http-response-timings r)))
         (http-response-history (cadr (list-ref answers 1))))))

(test-equal "the head's predicate, exchange-steps-past?, agrees with exchange-step on every row these tables stepped a response through, the response given as a head, its body and timings #f, with the same clocks and draw: 100 rows or more, each a next exactly where the predicate answers #t (the M6 plan, section 6.2)"
  '(agreed more-than-100)
  (let ((apart (filter (lambda (row) (not (eq? (car row) (cadr row)))) heads-seen)))
    ;; The rows' count, on stdout, as evidence.
    (display (list 'head-predicate-rows (length heads-seen))) (newline)
    (list (if (null? apart) 'agreed apart)
          (if (> (length heads-seen) 100) 'more-than-100 (length heads-seen)))))

(test-equal "make-exchange refuses a redirects that is no exact natural nor #f, and an allow-downgrade that is no boolean, each an assertion violation"
  '((raised (assertion make-exchange)) (raised (assertion make-exchange))
    (raised (assertion make-exchange)))
  (let ((r (make-curl-request base)))
    (list (outcome (lambda () (make-exchange 'get base r #f table-start -1 #f)))
          (outcome (lambda () (make-exchange 'get base r #f table-start 'all #f)))
          (outcome (lambda () (make-exchange 'get base r #f table-start 20 'no))))))

;; --- against the origin ----------------------------------------------------------------

;; environment-variables : (Listof String)
;; With a proxy variable set, libcurl would send this suite's transfers to
;; the proxy; with SSL_CERT_FILE or SSL_CERT_DIR set, Guix's would trust
;; the CA store named, not the CA file.
(define environment-variables
  '("http_proxy" "HTTP_PROXY" "https_proxy" "HTTPS_PROXY" "all_proxy" "ALL_PROXY"
    "SSL_CERT_FILE" "SSL_CERT_DIR"))

(test-equal "hermetic: none of the proxy variables, SSL_CERT_FILE and SSL_CERT_DIR is set"
  '()
  (filter (lambda (name) (getenv name)) environment-variables))

(define pki-made
  (guard (e (#t (list 'raised (describe e))))
    (list 'made (make-test-pki))))
(define pki (and (eq? (car pki-made) 'made) (cadr pki-made)))

(test-equal "make-test-pki makes this run's PKI"
  'made
  (car pki-made))

;; ca-file : String
(define ca-file (string-append (or pki "/no-pki") "/ca.pem"))

;; escape-when : (-> Boolean) (-> Any) -> Symbol
;; THUNK, run with a timer whose handler escapes from it once READY? holds:
;; escaped, or returned if THUNK returned first. The handler re-arms the
;; timer every 200 ticks until then.
(define (escape-when ready? thunk)
  (let* ((previous (timer-interrupt-handler))
         (how (call/cc
               (lambda (k)
                 (timer-interrupt-handler
                  (lambda () (if (ready?) (k 'escaped) (set-timer 200))))
                 (set-timer 200)
                 (thunk)
                 'returned))))
    (set-timer 0)
    (timer-interrupt-handler previous)
    how))

;; ended-within : Natural -> Symbol
(define (ended-within ms)
  (let ((deadline (+ (now-ms) ms)))
    (let loop ()
      (cond ((= (count-of 'transfer) 0) 'ended)
            ((> (now-ms) deadline) 'still-live)
            (else (pause-ms 10) (loop))))))

(parameterize ((origin-pki pki))
  (call-with-origin
   (lambda (o)
     ;; authority : Symbol -> String
     ;; A face's address and port, as a URL and libcurl's Host write them.
     (define (authority face)
       (guard (e (#t (string-append "no-" (symbol->string face) "-face")))
         (let ((f (origin-face o face)))
           (string-append (car f) ":" (number->string (cdr f))))))

     (define http-authority (authority 'http))
     (define raw-authority (authority 'raw))
     (define https-authority (authority 'https))

     ;; at : Symbol String -> String
     (define (at face path)
       (string-append (if (eq? face 'https) "https://" "http://") (authority face) path))

     ;; redirect : Symbol String String -> String
     ;; FACE's /redirect/CODE?to=TARGET, TARGET encoded.
     (define (redirect face code target)
       (at face (string-append "/redirect/" code "?to=" (pct target))))

     ;; location : String Natural String ... -> String
     ;; The raw face's location script: CODE after MS ms, a Location for
     ;; each of TARGETS, each a string of bytes, encoded.
     (define (location code ms . targets)
       (at 'raw (apply string-append "/raw/location?code=" code
                       (if (= ms 0) "" (string-append "&ms=" (number->string ms)))
                       (map (lambda (t) (string-append "&to=" (pct t))) targets))))

     ;; echo-text : String String String String ... -> String
     ;; The http faces' /echo text for METHOD TARGET at AUTHORITY, with
     ;; libcurl's Host and Accept, then LINES, then the blank line.
     (define (echo-text authority method target . lines)
       (apply string-append method " " target " HTTP/1.1\nHost: " authority "\nAccept: */*\n"
              (append (map (lambda (line) (string-append line "\n")) lines) (list "\n"))))

     ;; raw-echo : String String ... -> String
     ;; The raw face's echo of a GET of /raw/echo, its Host HOST, then LINES.
     (define (raw-echo host . lines)
       (apply string-append "GET /raw/echo HTTP/1.1\r\nHost: " host "\r\nAccept: */*\r\n"
              (append (map (lambda (line) (string-append line "\r\n")) lines) (list "\r\n"))))

     ;; The suite's session for the well-formed faces: every call bounded by
     ;; 20 s, trusting this run's CA.
     (define s (make-http-session 'timeout-ms 20000 'ca-file ca-file))

     (define echo (at 'http "/echo"))

     ;; --- statuses and methods

     ;; matrix-headers : (Listof (Pairof String String))
     (define matrix-headers
       '(("X-Keep" . "1") ("Content-Type" . "text/x") ("Digest" . "sha-256=x")
         ("Last-Modified" . "Tue, 01 Oct 2024 00:00:00 GMT")))

     ;; matrix-expected : String Symbol -> (Listof Any)
     ;; A METHOD call through /redirect/CODE?to=/echo: the 3xx answered for
     ;; 300, 304, 305 and 306; otherwise /echo's text, by method-rows.
     (define (matrix-expected code method)
       (let ((url (redirect 'http code "/echo"))
             (status (string->number code)))
         (if (memv status '(300 304 305 306))
             (list 'answered status url (if (= status 304) "" (string-append "redirect " code "\n"))
                   '())
             (let* ((row (find (lambda (r) (and (= (car r) status) (eq? (cadr r) method)))
                               method-rows))
                    (kept (eq? (cadddr row) 'kept))
                    (body (and kept (not (eq? method 'get)))))
               (list 'answered 200 echo
                     (string-append
                      (apply echo-text http-authority (string-upcase (symbol->string (caddr row)))
                             "/echo"
                             (append (list "X-Keep: 1")
                                     (if kept
                                         (list "Content-Type: text/x" "Digest: sha-256=x"
                                               "Last-Modified: Tue, 01 Oct 2024 00:00:00 GMT")
                                         '())
                                     (if body (list "Content-Length: 3") '())))
                      (if body "b=1" ""))
                     (list (list status url '())))))))

     ;; chain-1, chain-2, chain-3 : String
     ;; A 301, to a 302, to a 307, to /echo, on the http face.
     (define chain-3 (redirect 'http "307" "/echo"))
     (define chain-2 (redirect 'http "302" (substring chain-3 (string-length (at 'http "")) (string-length chain-3))))
     (define chain-1 (redirect 'http "301" (substring chain-2 (string-length (at 'http "")) (string-length chain-2))))

     ;; bad-location-case : Symbol String -> (Listof Any)
     ;; NAME's call: a get of the location script's 302 to LOCATION, on a
     ;; session of its own.
     (define (bad-location-case name loc)
       (with-session '(timeout-ms 20000)
         (lambda (own) (answer (lambda () (http-get own (location "302" 0 loc)))))))

     ;; bad-location-expected : String (U (List Symbol Any ...) Symbol #f) -> (Listof Any)
     ;; What a 302 to LOC answers, by VERDICT: (refused CODE), or not-utf-8,
     ;; a bad-location compounded with that refusal; scheme, a bad-location
     ;; with none; (followed PATH), the raw face's 400 for PATH there; #f, no
     ;; row.
     (define (bad-location-expected loc verdict)
       (let ((url (location "302" 0 loc)))
         (cond ((not verdict) (list 'no-row-for version))
               ((eq? verdict 'scheme)
                (list 'raised '(http-error)
                      (list 'http-redirect-error 'bad-location loc (list 302 url '()))
                      (list 'exchange 'get url '() 1)))
               ((eq? verdict 'not-utf-8)
                (list 'raised '(http-error)
                      (list 'http-redirect-error 'bad-location loc (list 302 url '()))
                      '(curl-url-error not-utf-8 #f)
                      (list 'exchange 'get url '() 1)))
               ((eq? (car verdict) 'refused)
                (list 'raised '(http-error)
                      (list 'http-redirect-error 'bad-location loc (list 302 url '()))
                      (list 'curl-url-error
                            (let ((hit (assv (cadr verdict)
                                             '((3 . malformed-input) (4 . bad-port-number)
                                               (5 . unsupported-scheme) (22 . bad-ipv6)
                                               (25 . bad-path)))))
                              (if hit (cdr hit) 'no-name))
                            (cadr verdict))
                      (list 'exchange 'get url '() 1)))
               (else
                (list 'answered 400 (at 'raw (cadr verdict)) "bad request\n"
                      (list (list 302 url '())))))))

     ;; measured-verdict : (Listof Any) -> Any
     ;; A live answer as a row's verdict, for a row this libcurl lacks.
     (define (measured-verdict a)
       (cond ((and (eq? (car a) 'answered) (= (cadr a) 400))
              (list 'followed (substring (caddr a) (string-length (at 'raw "")) (string-length (caddr a)))))
             ((and (eq? (car a) 'answered) (= (cadr a) 200)) '(first))
             ((assq 'curl-url-error (cdr a)) => (lambda (u) (list 'refused (caddr u))))
             ((assq 'curl-transfer-error (cdr a)) => (lambda (t) (list 'fails (cadddr t))))
             (else (list 'unknown a))))

     (for-each
      (lambda (code)
        (test-equal (string-append "a " code " to /echo, live, with get, post, put, patch and delete, a body and its headers on each but get: "
                                   (case (string->number code)
                                     ((300 304 305 306) "answered")
                                     ((301 302) "followed, a post as a get without its body or its headers")
                                     ((303) "followed as a get without a body or its headers")
                                     (else "followed with the method, the body and every header")))
          (map (lambda (method) (matrix-expected code method)) '(get post put patch delete))
          (in-order (lambda (method)
                      (answer (lambda ()
                                (apply http-request s method (redirect 'http code "/echo")
                                       'headers matrix-headers
                                       (if (eq? method 'get) '() '(body "b=1"))))))
                    '(get post put patch delete))))
      '("300" "301" "302" "303" "304" "305" "306" "307" "308"))

     ;; --- the origin rule, live

     (test-equal "the origin rule by port, live: the http face to the raw face's echo drops the session's Authorization and the call's Cookie and Proxy-Authorization, and keeps the rest"
       (list 'answered 200 (at 'raw "/raw/echo") (raw-echo raw-authority "X-Api-Key: k")
             (list (list 302 (redirect 'http "302" (at 'raw "/raw/echo")) '())))
       (with-session (list 'timeout-ms 20000 'headers '(("Authorization" . "Bearer s")))
         (lambda (own)
           (answer (lambda ()
                     (http-get own (redirect 'http "302" (at 'raw "/raw/echo"))
                               'headers '(("Cookie" . "c=1") ("Proxy-Authorization" . "Basic cA==")
                                          ("X-Api-Key" . "k"))))))))

     (test-equal "the origin rule's control, live: to the same origin, every header arrives"
       (list 'answered 200 echo
             (echo-text http-authority "GET" "/echo" "Authorization: Bearer s" "Cookie: c=1"
                        "Proxy-Authorization: Basic cA==" "X-Api-Key: k")
             (list (list 302 (redirect 'http "302" "/echo") '())))
       (with-session (list 'timeout-ms 20000 'headers '(("Authorization" . "Bearer s")))
         (lambda (own)
           (answer (lambda ()
                     (http-get own (redirect 'http "302" "/echo")
                               'headers '(("Cookie" . "c=1") ("Proxy-Authorization" . "Basic cA==")
                                          ("X-Api-Key" . "k"))))))))

     (test-equal "a header dropped stays dropped, live: the http face to the raw face, whose location script sends the call back to the http face's echo, which gets none of the three"
       (let ((back (location "302" 0 echo)))
         (list 'answered 200 echo (echo-text http-authority "GET" "/echo" "X-Api-Key: k")
               (list (list 302 (redirect 'http "302" back) '()) (list 302 back '()))))
       (with-session (list 'timeout-ms 20000)
         (lambda (own)
           (answer (lambda ()
                     (http-get own (redirect 'http "302" (location "302" 0 echo))
                               'headers '(("Authorization" . "Bearer c") ("Cookie" . "c=1")
                                          ("Proxy-Authorization" . "Basic cA==")
                                          ("X-Api-Key" . "k"))))))))

     (test-equal "a custom Host follows a change of port alone, live: the raw face's echo gets it"
       (list 'answered 200 (at 'raw "/raw/echo") (raw-echo "custom.example")
             (list (list 302 (redirect 'http "302" (at 'raw "/raw/echo")) '())))
       (with-session (list 'timeout-ms 20000)
         (lambda (own)
           (answer (lambda ()
                     (http-get own (redirect 'http "302" (at 'raw "/raw/echo"))
                               'headers '(("Host" . "custom.example"))))))))

     (test-equal "the origin rule by scheme, live: http to https is followed, and drops Authorization"
       (list 'answered 200 (at 'https "/echo") (echo-text https-authority "GET" "/echo" "X-Api-Key: k")
             (list (list 302 (redirect 'http "302" (at 'https "/echo")) '())))
       (answer (lambda ()
                 (http-get s (redirect 'http "302" (at 'https "/echo"))
                           'headers '(("Authorization" . "Bearer a") ("X-Api-Key" . "k"))))))

     (let* ((port (let ((i (let loop ((i (- (string-length http-authority) 1)))
                             (if (or (< i 0) (char=? (string-ref http-authority i) #\:)) i
                                 (loop (- i 1))))))
                    (substring http-authority (+ i 1) (string-length http-authority))))
            (local-authority (string-append "localhost:" port))
            (local-echo (string-append "http://" local-authority "/echo")))
       (test-equal "the origin rule by host, live: 127.0.0.1 to localhost, which reaches the origin, drops a custom Host, which libcurl then writes itself, and the credentials"
         (list 'answered 200 local-echo (echo-text local-authority "GET" "/echo" "X-Api-Key: k")
               (list (list 302 (redirect 'http "302" local-echo) '())))
         (answer (lambda ()
                   (http-get s (redirect 'http "302" local-echo)
                             'headers '(("Host" . "custom.example") ("Cookie" . "c=1")
                                        ("X-Api-Key" . "k")))))))

     ;; --- the downgrade, live

     (let ((down (redirect 'https "302" echo)))
       (test-equal "the downgrade, live: https to http raises &http-redirect-error insecure-redirect, with the 302 and its Location, and &http-exchange, one transfer; the call's #f wins over the session's #t"
         (let ((refused (list 'raised '(http-error)
                              (list 'http-redirect-error 'insecure-redirect echo (list 302 down '()))
                              (list 'exchange 'get down '() 1))))
           (list refused refused))
         (list (answer (lambda () (http-get s down)))
               (with-session (list 'timeout-ms 20000 'ca-file ca-file 'allow-downgrade #t)
                 (lambda (own) (answer (lambda () (http-get own down 'allow-downgrade #f)))))))

       (test-equal "the downgrade allowed, live: by the session, and by the call over the session's #f, it is followed"
         (let ((followed (list 'answered 200 echo (echo-text http-authority "GET" "/echo")
                               (list (list 302 down '())))))
           (list followed followed))
         (list (with-session (list 'timeout-ms 20000 'ca-file ca-file 'allow-downgrade #t)
                 (lambda (own) (answer (lambda () (http-get own down)))))
               (answer (lambda () (http-get s down 'allow-downgrade #t))))))

     ;; --- the bound, live

     (test-equal "the history of a three-hop call, live: the 301, the 302 and the 307, oldest first, each at its URL with its own body and a history of (), and the echo's answer carrying them"
       (list (list 'answered 200 echo (echo-text http-authority "GET" "/echo")
                   (list (list 301 chain-1 '()) (list 302 chain-2 '()) (list 307 chain-3 '())))
             '("redirect 301\n" "redirect 302\n" "redirect 307\n"))
       (guard (e (#t (cons 'raised (described e))))
         (let ((r (http-get s chain-1)))
           (list (answer (lambda () r))
                 (map (lambda (h) (latin-1 (http-response-body h))) (http-response-history r))))))

     (test-equal "the bound, live: redirects 2 follows two of three, and the third raises too-many-redirects, with the 307, its history and three transfers; redirects 3 follows all three"
       (list (list 'raised '(http-error)
                   (list 'http-redirect-error 'too-many-redirects "/echo"
                         (list 307 chain-3 (list (list 301 chain-1 '()) (list 302 chain-2 '()))))
                   (list 'exchange 'get chain-1 (list (list 301 chain-1 '()) (list 302 chain-2 '())) 3))
             (list 'answered 200 echo (echo-text http-authority "GET" "/echo")
                   (list (list 301 chain-1 '()) (list 302 chain-2 '()) (list 307 chain-3 '()))))
       (list (answer (lambda () (http-get s chain-1 'redirects 2)))
             (answer (lambda () (http-get s chain-1 'redirects 3)))))

     (let* ((loop-url (redirect 'http "302" "#loop"))
            (looped (string-append loop-url "#loop")))
       (test-equal "a loop, live: a 302 to # and a fragment requests the same URL again, and the default bound, 20, follows 20, then raises too-many-redirects, 21 transfers made"
         (list 'raised '(http-error)
               (list 'http-redirect-error 'too-many-redirects "#loop"
                     (list 302 looped (cons (list 302 loop-url '())
                                            (map (lambda (i) (list 302 looped '())) (iota 19)))))
               (list 'exchange 'get loop-url
                     (cons (list 302 loop-url '()) (map (lambda (i) (list 302 looped '())) (iota 19)))
                     21))
         (answer (lambda () (http-get s loop-url)))))

     (test-equal "redirects #f, live, the call's over the session's 20 and the session's alike, answers the 302 itself, its Location unread; redirects 0 raises too-many-redirects at once; the call's 1 over the session's 0 follows"
       (let ((url (redirect 'http "302" "/echo")))
         (list (list 'answered 302 url "redirect 302\n" '())
               (list 'answered 302 url "redirect 302\n" '())
               (list 'raised '(http-error)
                     (list 'http-redirect-error 'too-many-redirects "/echo" (list 302 url '()))
                     (list 'exchange 'get url '() 1))
               (list 'answered 200 echo (echo-text http-authority "GET" "/echo")
                     (list (list 302 url '())))))
       (let ((url (redirect 'http "302" "/echo")))
         (list (answer (lambda () (http-get s url 'redirects #f)))
               (with-session '(timeout-ms 20000 redirects #f)
                 (lambda (own) (answer (lambda () (http-get own url)))))
               (answer (lambda () (http-get s url 'redirects 0)))
               (with-session '(timeout-ms 20000 redirects 0)
                 (lambda (own) (answer (lambda () (http-get own url 'redirects 1))))))))

     (test-equal "a call's own redirects and allow-downgrade refused, live, compounded with &http-exchange, no transfer made"
       (list (list 'raised '(http-error) '(http-request-error redirects -2 not-a-redirect-count)
                   (list 'exchange 'get echo '() 0))
             (list 'raised '(http-error) '(http-request-error allow-downgrade "no" not-a-boolean)
                   (list 'exchange 'get echo '() 0))
             0)
       (let* ((started (transfers-started))
              (refusals (in-order (lambda (thunk) (answer thunk))
                                  (list (lambda () (http-get s echo 'redirects -2))
                                        (lambda () (http-get s echo 'allow-downgrade "no"))))))
         (append refusals (list (- (transfers-started) started)))))

     ;; --- bad-location, live, through the raw face

     (for-each
      (lambda (row)
        (let ((name (car row)) (loc (cadr row)) (verdict (caddr row)))
          (test-equal (string-append "bad-location, live, alike on every libcurl: " (symbol->string name))
            (bad-location-expected loc verdict)
            (bad-location-case name loc))))
      (list (list 'unknown-scheme "foo://bar/x" '(refused 5))
            (list 'bad-port "http://127.0.0.1:99999/x" '(refused 4))
            (list 'ftp "ftp://127.0.0.1/f" 'scheme)
            (list 'file "file:///etc/passwd" 'scheme)
            (list 'latin-1-host "http://caf\xE9;.invalid/" 'not-utf-8)))

     ;; A Location's bytes are encoded before they are resolved (ADR-0029,
     ;; amended), so 0x01 and 0x7F, which 7.85.0 and 8.5.0 refused raw, and a
     ;; Latin-1 byte in an absolute URL's path, which every libcurl gave back
     ;; raw, as no UTF-8, are followed alike: the raw face answers each path
     ;; with its fixed 400.
     (for-each
      (lambda (row)
        (let ((name (car row)) (loc (cadr row)) (verdict (caddr row)))
          (test-equal (string-append "a Location's bytes encoded, live, followed alike on every libcurl: "
                                     (symbol->string name))
            (bad-location-expected loc verdict)
            (bad-location-case name loc))))
      (list (list 'ctl "/x\x1;y" '(followed "/x%01y"))
            (list 'del "/x\x7F;y" '(followed "/x%7Fy"))
            (list 'latin-1-path "/caf\xE9;" '(followed "/caf%E9"))
            (list 'absolute-latin-1-path (at 'raw "/caf\xE9;") '(followed "/caf%E9"))))

     (let ((measured
            (in-order
             (lambda (row)
               (let* ((name (car row)) (loc (cadr row)) (a (bad-location-case name loc)))
                 (test-equal (string-append "bad-location, live, by version, " version "'s row: "
                                            (symbol->string name))
                   (bad-location-expected loc (row-of name))
                   a)
                 (list name (measured-verdict a))))
             (list (list 'javascript "javascript:alert(1)")
                   (list 'bad-ipv6 "http://[::1/x"))))
           (two-url (location "302" 0 echo "/second")))
       (let ((two (with-session '(timeout-ms 20000)
                    (lambda (own) (answer (lambda () (http-get own two-url)))))))
         (test-equal (string-append "two Location headers, live, by version, " version "'s row: the first followed before 8.20.0, and from it the transfer fails with 8, (curl)'s &curl-protocol-error, compounded with &http-exchange")
           (let ((verdict (row-of 'two)))
             (cond ((not verdict) (list 'no-row-for version))
                   ((eq? (car verdict) 'first)
                    (list 'answered 200 echo (echo-text http-authority "GET" "/echo")
                          (list (list 302 two-url '()))))
                   (else
                    (list 'raised (list 'curl-transfer-error 'protocol 'perform-failed (cadr verdict))
                          (list 'exchange 'get two-url '() 1)))))
           two)
         (unless (assoc version location-rows)
           (let ((err (current-error-port)))
             (put-string err (string-append "test-redirect: no row for libcurl " version
                                            "; the row it measured:\n"))
             (write (cons version (append measured (list (list 'two (measured-verdict two))))) err)
             (newline err)
             (flush-output-port err)))))

     (test-equal "this libcurl's version has a row in location-rows"
       (list version 'has-a-row)
       (list version (if (assoc version location-rows) 'has-a-row 'has-no-row)))

     ;; --- fragments, live

     (let* ((url (redirect 'http "302" "#frag%e9"))
            (kept (string-append url "#frag%e9")))
       (test-equal "a lone # and a fragment, live, on every libcurl: the URL is kept, its last segment and its query, the hex case as given; redirects 1 then refuses the same 302 again"
         (list 'raised '(http-error)
               (list 'http-redirect-error 'too-many-redirects "#frag%e9"
                     (list 302 kept (list (list 302 url '()))))
               (list 'exchange 'get url (list (list 302 url '())) 2))
         (answer (lambda () (http-get s url 'redirects 1)))))

     (test-equal "the URL requested's fragment, live, is carried to a Location with none, never sent; a Location's own fragment wins"
       (list (list 'answered 200 (string-append echo "#keep%e9") (echo-text http-authority "GET" "/echo")
                   (list (list 302 (string-append (redirect 'http "302" "/echo") "#keep%e9") '())))
             (list 'answered 200 (string-append echo "#own") (echo-text http-authority "GET" "/echo")
                   (list (list 302 (string-append (redirect 'http "302" "/echo#own") "#keep") '()))))
       (list (answer (lambda () (http-get s (string-append (redirect 'http "302" "/echo") "#keep%e9"))))
             (answer (lambda () (http-get s (string-append (redirect 'http "302" "/echo#own") "#keep"))))))

     ;; --- the call's bound across a redirect

     ;; Each hop takes 600 ms of the call's 1000: the location script waits
     ;; 600 ms before its 302, and the drip it names waits 600 ms mid-body.
     ;; The second transfer gets the 400 ms or so left, and its 28 is the
     ;; bound's. A transfer given the whole bound would finish at about 1200
     ;; ms, and answer 200.
     (let* ((drip (at 'raw "/raw/pause-mid-body?ms=600"))
            (url (location "302" 600 drip)))
       (test-equal "the call's bound across a redirect, live: a timeout-ms of 1000, whose first hop takes 600 ms and second 600 more, raises &http-timeout and the low level's &curl-timeout together, with the 302 in the history, two transfers, no sooner than 1000 ms and sooner than 1600"
         (list (list 'raised '(http-error) '(http-timeout 1000)
                     '(curl-transfer-error timeout perform-failed 28)
                     (list 'exchange 'get url (list (list 302 url '())) 2))
               'within)
         (with-session '(timeout-ms 20000)
           (lambda (own)
             (let* ((start (now-ms))
                    (a (answer (lambda () (http-get own url 'timeout-ms 1000))))
                    (took (- (now-ms) start)))
               (list a (if (and (>= took 1000) (< took 1600)) 'within (list 'took took))))))))

     ;; --- an escape from a redirect's await

     (test-equal "an escape from the await of a redirect's transfer, by a timer's handler, cancels that transfer: none is live within 3 s, where the drip runs 10 s"
       (list 'escaped 'ended)
       (with-session '(timeout-ms 30000)
         (lambda (own)
           (let* ((url (redirect 'http "302" (at 'raw "/raw/pause-mid-body?ms=10000")))
                  (t0 (now-ms))
                  (started (transfers-started))
                  (how (escape-when (lambda ()
                                      (and (>= (- (now-ms) t0) 200)
                                           (= (- (transfers-started) started) 2)
                                           (= (count-of 'transfer) 1)))
                                    (lambda () (http-get own url)))))
             (list how (ended-within 3000))))))

     (test-equal "the suite's session closes, and every count is zero after"
       zero-counts
       (begin (http-session-close s) (native-counts))))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "redirect")

(exit (suite-exit-status runner))
