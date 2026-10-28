#!r6rs
;;; The suite for retries, the high level's third slice (the M5 plan,
;;; sections 3.5 and 6; ADR-0026, amended 2026-10-28; ADR-0022, amended
;;; 2026-10-28): make-http-retry, the retry key, the retry rules in
;;; exchange-step, the waits, Retry-After, and the session's generator.
;;;
;;;   - the policy: its defaults and keys, each refusal by name and by
;;;     value, in order, its private copies, and the retry key of a session
;;;     and a call;
;;;   - the Retry-After reader, pure: delta-seconds, the three HTTP-date
;;;     forms, each field's bounds, and a cross-check of every form against
;;;     Chez's own UTC dates, 1900 to 2099; the backoff, pure;
;;;   - exchange-step by tables, both clocks and the draw given: which
;;;     failures and statuses are retried, for which methods, by request
;;;     size; each never-retried case; the attempts, the backoff's doubling
;;;     and cap, jitter, Retry-After over the backoff, unreadable, past
;;;     max-backoff-ms and past the time left; the bound's 28; a redirect
;;;     starting the count again; the history; the next request;
;;;   - the generator: a session's own, which draws in (0, 1), differently
;;;     in each process where Chez's random repeats, once per step, and
;;;     whose draw sets a jitter's wait, predicted from a copy of its state;
;;;   - against the origin's retry script, each check with its own session:
;;;     a close, a reset, and a status with Retry-After by delta-seconds and
;;;     by an IMF-fixdate; a control per rule, a post after a send not
;;;     retried and one before a send, a refused connect, retried, but on
;;;     8.7.0 and 8.7.1, whose request size is unknown; no policy, the
;;;     call's over the session's; the last attempt; the call's bound across
;;;     a retry's wait; and an escape during the wait. The origin counts the
;;;     attempts that reached it.
;;;
;;; Every check on the raw face makes its own session: the raw face closes
;;; after each script, and curl 8.23.0 resends on each dead pooled
;;; connection (traps.md). The retry script says Connection: close, so its
;;; connections go back to no pool. Every expected value is one the code
;;; under test cannot produce by failing: SRFI-64 makes #f of a raise in
;;; the actual expression, so none is #f.
(import (rnrs)
        (srfi :64)
        (rnrs mutable-pairs)
        (only (chezscheme) sleep make-time current-time time-second time-nanosecond getenv
              set-timer timer-interrupt-handler iota make-list library-directories
              time-utc->date date-year date-month date-day date-hour date-minute date-second
              date-week-day pseudo-random-generator->vector vector->pseudo-random-generator
              pseudo-random-generator-next! fork-thread make-mutex with-mutex critical-section)
        (curl-testing)
        (curl)
        (http-client)
        (only (http-client private call) http-retry-attempts http-retry-backoff-ms
              http-retry-max-backoff-ms http-retry-jitter http-retry-statuses http-retry-methods
              retry-keys http-session-draw http-session-generator)
        (only (http-client private exchange) make-exchange exchange-submission exchange-step
              exchange-request exchange-flight exchange-history exchange-transfers
              exchange-attempts exchange-policy exchange-retried make-http-response retry-after-ms
              http-date-seconds backoff-wait)
        (only (http-client private drive) drive-exchange monotonic-ns)
        (only (curl private conditions) make-classed-transfer-error make-curl-engine-error
              make-curl-url-error)
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

(test-begin "retry")

;; --- helpers --------------------------------------------------------------------------

(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0)))

;; now-ms : -> Integer
(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

;; utc-now : -> Integer
(define (utc-now) (time-second (current-time 'time-utc)))

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
(define (hex2 b)
  (string #\% (string-ref "0123456789ABCDEF" (div b 16)) (string-ref "0123456789ABCDEF" (mod b 16))))

;; pct : String -> String
;; S, chars below U+0100, each kept when an ASCII letter or digit, -, ., _
;; or ~, else %XX: a query value the raw face decodes back to its bytes.
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

;; size-kind : (U Natural #f) -> Symbol
;; zero, nothing sent; sent; or unknown, #f.
(define (size-kind size)
  (cond ((eqv? size 0) 'zero) ((not size) 'unknown) (else 'sent)))

;; summary : Response -> (List Integer String (Listof Any))
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
                        (http-request-error-reason e)
                        (and (who-condition? e) (condition-who e))))
             (and (http-redirect-error? e)
                  (list 'http-redirect-error (http-redirect-error-reason e)))
             (and (http-timeout? e) (list 'http-timeout (http-timeout-timeout-ms e)))
             (and (curl-url-error? e) (list 'curl-url-error (curl-url-error-reason e)))
             (and (curl-engine-error? e) (list 'curl-engine-error (curl-engine-error-reason e)))
             (and (curl-transfer-error? e)
                  (list 'curl-transfer-error (class-of e) (curl-transfer-error-reason e)
                        (curl-transfer-error-code e)
                        (size-kind (curl-transfer-error-request-size e))))
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

;; policy-fields : Retry -> (Listof Any)
(define (policy-fields p)
  (list (http-retry-attempts p) (http-retry-backoff-ms p) (http-retry-max-backoff-ms p)
        (http-retry-jitter p) (http-retry-statuses p) (http-retry-methods p)))

;; --- the policy -----------------------------------------------------------------------

;; Before any session is made here: no engine runs, so the multi count is
;; the suite's own evidence that a refusal made none.

(test-equal "make-http-retry with no keys: attempts 3, backoff-ms 200, max-backoff-ms 10000, jitter #t, statuses (429 503), methods (get head put delete)"
  '(3 200 10000 #t (429 503) (get head put delete))
  (policy-fields (make-http-retry)))

(test-equal "make-http-retry takes each key, in any order, each value kept: the bounds of each, attempts 1, backoffs 0, statuses 400 and 599, every method, and empty lists"
  (list '(7 0 50 #f (599 400 500) (post patch delete put head get))
        '(1 1234 0 #t () ())
        '(3 200 10000 #f (429 503) (get head put delete)))
  (list (policy-fields (make-http-retry 'methods '(post patch delete put head get) 'jitter #f
                                        'statuses '(599 400 500) 'max-backoff-ms 50 'backoff-ms 0
                                        'attempts 7))
        (policy-fields (make-http-retry 'attempts 1 'backoff-ms 1234 'max-backoff-ms 0 'statuses '()
                                        'methods '()))
        (policy-fields (make-http-retry 'jitter #f))))

(test-equal "retry-keys, written out, in the order make-http-retry checks their values"
  '(attempts backoff-ms max-backoff-ms jitter statuses methods)
  retry-keys)

(test-equal "http-retry? holds of a policy, and of nothing else: not #f, a list of its fields, nor a symbol"
  '(#t #f #f #f)
  (list (http-retry? (make-http-retry)) (http-retry? #f) (http-retry? '(3 200 10000 #t (429 503)))
        (http-retry? 'retry)))

(test-equal "make-http-retry refuses its keys by name, as &http-request-error from make-http-retry: an unknown key, retry and attempt among them; a repeated key; a key with no value"
  (list '(raised (http-error) (http-request-error key attempt unknown-key make-http-retry))
        '(raised (http-error) (http-request-error key retry unknown-key make-http-retry))
        '(raised (http-error) (http-request-error key timeout-ms unknown-key make-http-retry))
        '(raised (http-error) (http-request-error key jitter repeated-key make-http-retry))
        '(raised (http-error) (http-request-error key statuses missing-value make-http-retry)))
  (in-order (lambda (plist) (outcome (lambda () (apply make-http-retry plist))))
            '((attempt 3) (retry 3) (timeout-ms 1) (jitter #t jitter #f) (attempts 2 statuses))))

;; value-rows : (Listof (List Symbol Any Symbol))
;; Written out: a key, a value it refuses, and the reason.
(define value-rows
  (list '(attempts 0 not-an-attempt-count) '(attempts -1 not-an-attempt-count)
          '(attempts 1.0 not-an-attempt-count) '(attempts 3/2 not-an-attempt-count)
          '(attempts "3" not-an-attempt-count) '(attempts #f not-an-attempt-count)
          '(backoff-ms -1 not-a-backoff) '(backoff-ms 1.5 not-a-backoff)
          '(backoff-ms 200.0 not-a-backoff) '(backoff-ms "200" not-a-backoff)
          '(backoff-ms #f not-a-backoff)
          '(max-backoff-ms -1 not-a-backoff) '(max-backoff-ms 2/3 not-a-backoff)
          '(max-backoff-ms #t not-a-backoff)
          '(jitter 1 not-a-boolean) '(jitter yes not-a-boolean) '(jitter () not-a-boolean)
          '(statuses 503 not-a-status-list) '(statuses (503 . 429) not-a-status-list)
          '(statuses ("503") not-a-status-list) '(statuses (199) not-a-status-list)
          '(statuses (399) not-a-status-list) '(statuses (302) not-a-status-list)
          '(statuses (200) not-a-status-list) '(statuses (429 301) not-a-status-list)
          '(statuses (600) not-a-status-list) '(statuses (503.0) not-a-status-list)
          '(statuses (100) not-a-status-list) '(statuses #f not-a-status-list)
          '(methods get not-a-method-list) '(methods (GET) not-a-method-list)
          '(methods ("get") not-a-method-list) '(methods (options) not-a-method-list)
          '(methods (get . head) not-a-method-list) '(methods #f not-a-method-list)))

(test-equal "make-http-retry refuses each value outside its range or shape, as &http-request-error with the key as its field and the value as given"
  (map (lambda (row) (list 'raised '(http-error)
                           (list 'http-request-error (car row) (cadr row) (caddr row) 'make-http-retry)))
       value-rows)
  (in-order (lambda (row) (outcome (lambda () (make-http-retry (car row) (cadr row))))) value-rows))

;; A circular list is compared by eq? alone, and never written: a failure's
;; print of it would not end.
(test-equal "make-http-retry refuses a circular statuses and methods, as not-a-status-list and not-a-method-list, the value the very list given, and answers at once"
  '((statuses not-a-status-list the-cycle) (methods not-a-method-list the-cycle))
  (let ((statuses (list 429 503)) (methods (list 'get 'put)))
    (set-cdr! (cdr statuses) statuses)
    (set-cdr! (cdr methods) methods)
    (in-order (lambda (row)
                (guard (e ((http-request-error? e)
                           (list (http-request-error-field e) (http-request-error-reason e)
                                 (if (eq? (http-request-error-value e) (cadr row)) 'the-cycle 'another)))
                          (#t (list 'raised-other (condition? e))))
                  (make-http-retry (car row) (cadr row))
                  '(returned)))
              (list (list 'statuses statuses) (list 'methods methods)))))

(test-equal "make-http-retry refuses the keys by name before any value, and then the values in retry-keys' order, whatever order they come in"
  (list '(raised (http-error) (http-request-error key nope unknown-key make-http-retry))
        '(raised (http-error) (http-request-error attempts 0 not-an-attempt-count make-http-retry))
        '(raised (http-error) (http-request-error max-backoff-ms -1 not-a-backoff make-http-retry))
        '(raised (http-error) (http-request-error statuses (1) not-a-status-list make-http-retry)))
  (in-order (lambda (plist) (outcome (lambda () (apply make-http-retry plist))))
            '((attempts 0 nope 1) (methods bad statuses (1) attempts 0)
              (methods bad jitter 2 statuses (1) max-backoff-ms -1)
              (methods bad statuses (1)))))

(test-equal "a policy keeps copies of its lists: a change to the caller's statuses or methods after it is made is not the policy's"
  '((429 503) (get put) fresh)
  (let* ((statuses (list 429 503))
         (methods (list 'get 'put))
         (p (make-http-retry 'statuses statuses 'methods methods)))
    (set-car! statuses 500)
    (set-car! methods 'post)
    (list (http-retry-statuses p) (http-retry-methods p)
          (if (or (eq? (http-retry-statuses p) statuses) (eq? (http-retry-methods p) methods))
              'shared
              'fresh))))

(test-equal "make-http-session refuses a retry that is neither a policy nor #f, as &http-request-error, not-a-retry-policy, after redirects and allow-downgrade, with no engine made"
  (list '(raised (http-error) (http-request-error retry 3 not-a-retry-policy make-http-session))
        '(raised (http-error) (http-request-error retry #t not-a-retry-policy make-http-session))
        '(raised (http-error) (http-request-error retry () not-a-retry-policy make-http-session))
        '(raised (http-error) (http-request-error redirects -1 not-a-redirect-count make-http-session))
        '(raised (http-error) (http-request-error allow-downgrade 1 not-a-boolean make-http-session))
        '(raised (http-error) (http-request-error key retry repeated-key make-http-session))
        0)
  (let* ((refusals (in-order (lambda (plist) (outcome (lambda () (apply make-http-session plist))))
                             '((retry 3) (retry #t) (retry ()) (retry 1 redirects -1)
                               (retry 1 allow-downgrade 1) (retry #f retry #f))))
         (multi (count-of 'multi)))
    (append refusals (list multi))))

(test-equal "make-http-session and call-with-http-session take a policy, and #f; call-with-http-session refuses a bad one before it makes a session"
  (list '(#t #t) 'session
        '(raised (http-error) (http-request-error retry x not-a-retry-policy make-http-session)) 0)
  (let* ((made (in-order (lambda (plist) (with-session plist (lambda (s) (http-session? s))))
                         (list (list 'retry (make-http-retry)) '(retry #f))))
         (called (call-with-http-session 'retry (make-http-retry 'attempts 2)
                   (lambda (s) (if (http-session? s) 'session 'other))))
         (refused (outcome (lambda () (call-with-http-session 'retry 'x (lambda (s) s)))))
         (multi (count-of 'multi)))
    (list made called refused multi)))

;; --- the Retry-After reader and the backoff, pure -------------------------------------

;; U : Integer
;; 2026-10-28 12:00:00 UTC, a Wednesday: the UTC time every table reads.
(define U 1793188800)

(test-equal "http-date-seconds reads RFC 9110's three forms of one date alike: IMF-fixdate, rfc850-date and asctime-date, the RFC's own example among them, and asctime's day as SP DIGIT or 2DIGIT"
  '(784111777 784111777 784111777 784111777 1793188800 1793188800 1793188800)
  (map (lambda (s) (http-date-seconds s U))
       '("Sun, 06 Nov 1994 08:49:37 GMT" "Sunday, 06-Nov-94 08:49:37 GMT" "Sun Nov  6 08:49:37 1994"
         "Sun Nov 06 08:49:37 1994" "Wed, 28 Oct 2026 12:00:00 GMT"
         "Wednesday, 28-Oct-26 12:00:00 GMT" "Wed Oct 28 12:00:00 2026")))

(test-equal "http-date-seconds reads every month's name, each in the IMF-fixdate, the rfc850-date and the asctime-date"
  (let ((firsts '(1767225600 1769904000 1772323200 1775001600 1777593600 1780272000 1782864000
                  1785542400 1788220800 1790812800 1793491200)))
    (list firsts firsts firsts))
  (let ((months '("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov")))
    (list (map (lambda (m) (http-date-seconds (string-append "Mon, 01 " m " 2026 00:00:00 GMT") U)) months)
          (map (lambda (m) (http-date-seconds (string-append "Monday, 01-" m "-26 00:00:00 GMT") U)) months)
          (map (lambda (m) (http-date-seconds (string-append "Mon " m "  1 00:00:00 2026") U)) months))))

(test-equal "http-date-seconds: the year's last second in December; 29 February in a leap year, 2024 and 2000, and in none, 2026 and 2100; the 30th and 31st by month; day 00 and 32"
  '(1798761599 1709164800 951782400 #f #f 1777507200 #f #f #f #f)
  (map (lambda (s) (http-date-seconds s U))
       '("Thu, 31 Dec 2026 23:59:59 GMT" "Thu, 29 Feb 2024 00:00:00 GMT" "Tue, 29 Feb 2000 00:00:00 GMT"
         "Sun, 29 Feb 2026 00:00:00 GMT" "Mon, 29 Feb 2100 00:00:00 GMT" "Thu, 30 Apr 2026 00:00:00 GMT"
         "Fri, 31 Apr 2026 00:00:00 GMT" "Mon, 31 Nov 2026 00:00:00 GMT" "Mon, 00 Jan 2026 00:00:00 GMT"
         "Mon, 32 Jan 2026 00:00:00 GMT")))

(test-equal "http-date-seconds: the time of day, 23:59:59, a leap second's 23:59:60, the next day's first second; an hour of 24, a minute of 60, a second of 61"
  '(1793231999 1793232000 1793232000 #f #f #f)
  (map (lambda (s) (http-date-seconds s U))
       '("Wed, 28 Oct 2026 23:59:59 GMT" "Wed, 28 Oct 2026 23:59:60 GMT" "Thu, 29 Oct 2026 00:00:00 GMT"
         "Wed, 28 Oct 2026 24:00:00 GMT" "Wed, 28 Oct 2026 23:60:00 GMT" "Wed, 28 Oct 2026 23:59:61 GMT")))

(test-equal "http-date-seconds reads an rfc850-date's two-digit year by its timestamp (RFC 9110, section 5.6.7): in this century, unless that is more than 50 years after U, 2076-10-28 12:00:00, then the last; at that second exactly, and a second before, 2076; a second after, and 31 December, 1976; 26, 00, 77 and 94 too"
  '(1793232000 972691200 3371068800 246844800 784111777 3371112000 3371111999 3370982400 215352001
    220924799)
  (map (lambda (s) (http-date-seconds s U))
       '("Thursday, 29-Oct-26 00:00:00 GMT" "Saturday, 28-Oct-00 00:00:00 GMT"
         "Wednesday, 28-Oct-76 00:00:00 GMT" "Friday, 28-Oct-77 00:00:00 GMT"
         "Sunday, 06-Nov-94 08:49:37 GMT" "Wednesday, 28-Oct-76 12:00:00 GMT"
         "Wednesday, 28-Oct-76 11:59:59 GMT" "Tuesday, 27-Oct-76 00:00:00 GMT"
         "Thursday, 28-Oct-76 12:00:01 GMT" "Friday, 31-Dec-76 23:59:59 GMT")))

(test-equal "http-date-seconds refuses, as #f, every near miss: names in another case, a long name in the IMF-fixdate or a short one in the rfc850-date, a name it does not know, gmt and UTC, a missing or doubled separator, a one-digit day or a two-digit year in the IMF-fixdate, a one-space asctime day, a non-ASCII digit, a trailing space, and the empty string"
  (make-list 21 #f)
  (map (lambda (s) (http-date-seconds s U))
       '("sun, 06 Nov 1994 08:49:37 GMT" "Sun, 06 nov 1994 08:49:37 GMT" "Sunday, 06 Nov 1994 08:49:37 GMT"
         "Sun, 06-Nov-94 08:49:37 GMT" "Sunny, 06-Nov-94 08:49:37 GMT" "Sun, 06 Nov 1994 08:49:37 gmt"
         "Sun, 06 Nov 1994 08:49:37 UTC" "Sun 06 Nov 1994 08:49:37 GMT" "Sun,  06 Nov 1994 08:49:37 GMT"
         "Sun, 06 Nov 1994 08.49:37 GMT" "Sun, 6 Nov 1994 08:49:37 GMT" "Sun, 06 Nov 94 08:49:37 GMT"
         "Sun Nov 6 08:49:37 1994" "Sun Nov  6 08:49:37 94" "Sunday, 06-Nov-1994 08:49:37 GMT"
         "Sun, \x666;6 Nov 1994 08:49:37 GMT" "Sun, 06 Nov 1994 08:49:37 GMT " "Sun Nov  6 08:49:37 1994 "
         "" "Sunday, 06-Nov-94 08:49:37 GMT " "Sun, 06 Nov 1994 08:49:3x GMT")))

;; month-names-written, week-days-written : (Vectorof String)
;; Written out here, apart from the code's lists.
(define month-names-written '#("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))
(define week-days-written '#("Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat"))
(define long-days-written '#("Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday"))

;; two : Natural -> String
(define (two n) (if (< n 10) (string-append "0" (number->string n)) (number->string n)))

;; date-forms : Integer -> (List String String String)
;; S's IMF-fixdate, rfc850-date and asctime-date, from Chez's own UTC date.
(define (date-forms s)
  (let* ((d (time-utc->date (make-time 'time-utc 0 s) 0))
         (clock (string-append (two (date-hour d)) ":" (two (date-minute d)) ":" (two (date-second d))))
         (month (vector-ref month-names-written (- (date-month d) 1)))
         (year (number->string (date-year d))))
    (list (string-append (vector-ref week-days-written (date-week-day d)) ", " (two (date-day d)) " "
                         month " " year " " clock " GMT")
          (string-append (vector-ref long-days-written (date-week-day d)) ", " (two (date-day d)) "-"
                         month "-" (two (mod (date-year d) 100)) " " clock " GMT")
          (string-append (vector-ref week-days-written (date-week-day d)) " " month " "
                         (if (< (date-day d) 10)
                             (string-append " " (number->string (date-day d)))
                             (number->string (date-day d)))
                         " " clock " " year))))

;; cross-times : (Listof Integer)
;; 3000 times from 1900 to 2099, spread over days, months and seconds.
(define cross-times
  (map (lambda (k) (+ -2208988800 (* k 2103840) (mod (* k k 7919) 86400))) (iota 3000)))

(test-equal "http-date-seconds against Chez's own UTC dates: 3000 times from 1900 to 2099 read back from each form, the rfc850-date's where its two digits name the time, after 1976-10-28 12:00:00 and at or before 2076-10-28 12:00:00"
  '(0 0 0)
  (let ((misses (lambda (pick ok?)
                  (length (filter (lambda (s)
                                    (and (ok? s)
                                         (not (eqv? (http-date-seconds (pick (date-forms s)) U) s))))
                                  cross-times)))))
    (list (misses car (lambda (s) #t))
          (misses cadr (lambda (s) (and (> s 215352000) (<= s 3371112000))))
          (misses caddr (lambda (s) #t)))))

(test-equal "retry-after-ms: delta-seconds, one or more ASCII digits, times 1000, its SP and HTAB trimmed, a leading zero and a large one among them"
  '(0 1000 120000 7000 5000 5000 99999999999999999999000)
  (map (lambda (v) (retry-after-ms v U)) '("0" "1" "120" "007" " 5 " "\t5\t" "99999999999999999999")))

(test-equal "retry-after-ms: an HTTP-date, in each form, as the ms from UTC-S, 0 at or before it, trimmed too"
  '(3000 3000 3000 0 0 3000)
  (map (lambda (v) (retry-after-ms v U))
       '("Wed, 28 Oct 2026 12:00:03 GMT" "Wednesday, 28-Oct-26 12:00:03 GMT" "Wed Oct 28 12:00:03 2026"
         "Wed, 28 Oct 2026 12:00:00 GMT" "Wed, 28 Oct 2026 11:58:20 GMT" " Wed, 28 Oct 2026 12:00:03 GMT\t")))

(test-equal "retry-after-ms: what is neither is #f, read as absent: a sign, a fraction, an exponent, a unit, an empty or blank value, a non-ASCII digit, a bad date"
  (make-list 10 #f)
  (map (lambda (v) (retry-after-ms v U))
       '("-1" "+1" "1.5" "1e3" "5 s" "" "  " "\x661;" "soon" "Wed, 28 Oct 2026 12:00:03 UTC")))

(test-equal "backoff-wait without jitter: backoff-ms for the first retry, doubling for each after, capped at max-backoff-ms; a backoff of 0, a cap of 0, and a cap below the backoff"
  '((100 200 400 800 1000 1000 1000) (0 0 0) (0 0) (300 300))
  (let ((rows (lambda (policy attempts)
                (map (lambda (a) (backoff-wait policy a 0.5)) attempts))))
    (list (rows (make-http-retry 'backoff-ms 100 'max-backoff-ms 1000 'jitter #f) '(1 2 3 4 5 6 40))
          (rows (make-http-retry 'backoff-ms 0 'max-backoff-ms 1000 'jitter #f) '(1 2 1000000))
          (rows (make-http-retry 'backoff-ms 100 'max-backoff-ms 0 'jitter #f) '(1 2))
          (rows (make-http-retry 'backoff-ms 500 'max-backoff-ms 300 'jitter #f) '(1 3)))))

(test-equal "backoff-wait with jitter: DRAW times the backoff, rounded down to a whole ms, exact: 0, a quarter, just under 1, a third, a flonum's product, and half the doubled and the capped backoff"
  '(0 250 999 333 100 1000 1500)
  (let ((p (make-http-retry 'backoff-ms 1000 'max-backoff-ms 3000 'jitter #t)))
    (list (backoff-wait p 1 0.0) (backoff-wait p 1 0.25) (backoff-wait p 1 0.9999) (backoff-wait p 1 1/3)
          (backoff-wait p 1 0.1) (backoff-wait p 2 0.5) (backoff-wait p 5 0.5))))

;; --- exchange-step, by tables ---------------------------------------------------------

;; Every table's call starts at table-start, a time no clock gives, bounded
;; by 5000 ms, its transfer's connect timeout 700, shorter than the bound,
;; so the deadline alone says whether a 28 is the bound's.
(define table-start 7000000000123)
(define table-url "http://h.example/r?q=1")
(define given "http://Given.example/r")

;; at : Natural -> Integer
;; The monotonic time MS ms into the call.
(define (at ms) (+ table-start (* ms 1000000)))

;; table-request : Symbol [(U Positive-Integer #f)] -> Request
;; METHOD on table-url, a body unless get or head, with a connect timeout
;; of 700, or CONNECT.
(define (table-request method . connect)
  (make-curl-request table-url 'method method 'headers '(("X-A" . "1"))
                     'body (if (memq method '(get head)) #f (bytes-of "b=1"))
                     'user-agent "ua/1" 'timeout-ms 5000
                     'connect-timeout-ms (if (pair? connect) (car connect) 700)))

;; plain-made : (U Retry (Pairof 'raised Any))
;; 3 attempts, backoff 100, capped at 1000, no jitter: made under a guard,
;; so a regression in make-http-retry names the test below, not the suite's
;; death at a top-level definition.
(define plain-made
  (guard (e (#t (cons 'raised (described e))))
    (make-http-retry 'attempts 3 'backoff-ms 100 'max-backoff-ms 1000 'jitter #f)))

;; plain : (U Retry #f)
(define plain (and (http-retry? plain-made) plain-made))

(test-equal "the tables' policy plain is made: 3 attempts, backoff 100, capped at 1000, no jitter"
  '(3 100 1000 #f (429 503) (get head put delete))
  (if plain (policy-fields plain) plain-made))

;; rstate : Symbol (U Retry #f) [(U Positive-Integer #f)] -> State
;; A call of METHOD with POLICY, bounded by 5000 ms, or BOUND.
(define (rstate method policy . bound)
  (make-exchange method given (table-request method) (if (pair? bound) (car bound) 5000) table-start
                 20 #f policy))

;; failure : (U Integer #f) (U Natural #f) [Symbol] -> Condition
;; A transfer's failure of CODE, its request size SIZE, perform-failed or
;; REASON.
(define (failure code size . reason)
  (make-classed-transfer-error (if (pair? reason) (car reason) 'perform-failed) code #f "a failure" #f #f
                               size))

;; reply : Integer (Listof (Pairof String String)) -> Response
(define (reply status headers)
  (make-http-response status 'http/1.1 "http://ignored.example/" headers (bytes-of "body") '((total . 1))
                      '()))

;; fails, answers : State Condition-or-Response Natural [Real] -> Answer
;; The core's answer to the failure or the response MS ms into the call,
;; at U, with DRAW, 0.0 by default.
(define (fails state c ms . draw)
  (exchange-step state (list 'failed c) (at ms) U (if (pair? draw) (car draw) 0.0)))
(define (answers state r ms . draw)
  (exchange-step state (list 'response r) (at ms) U (if (pair? draw) (car draw) 0.0)))

;; seen : Answer -> (Listof Any)
;; (next WAIT ATTEMPTS TRANSFERS), (done STATUS HISTORY), or (fail
;; . DESCRIBED).
(define (seen answer)
  (case (car answer)
    ((next) (list 'next (cadddr answer) (exchange-attempts (cadr answer))
                  (exchange-transfers (cadr answer))))
    ((done) (list 'done (http-response-status (cadr answer))
                  (map summary (http-response-history (cadr answer)))))
    ((fail) (cons 'fail (described (cadr answer))))
    (else (list 'unknown answer))))

;; through : State (Listof (-> State Answer)) -> (Listof Any)
;; Each step's answer, seen, stepping each next's state into the following
;; step, until one is not a next, or the steps end.
(define (through state steps)
  (let loop ((state state) (rest steps) (seen-so-far '()))
    (if (null? rest)
        (reverse seen-so-far)
        (let ((a ((car rest) state)))
          (if (eq? (car a) 'next)
              (loop (cadr a) (cdr rest) (cons (seen a) seen-so-far))
              (reverse (cons (seen a) seen-so-far)))))))

;; failed-as : Symbol Symbol Symbol (U Integer #f) Symbol Natural -> (Listof Any)
;; The fail a METHOD call makes with a failure of CLASS, REASON, CODE and
;; SIZE-KIND, after TRANSFERS transfers.
(define (failed-as method class reason code size transfers)
  (list 'fail (list 'curl-transfer-error class reason code size)
        (list 'exchange method given '() transfers)))

(define all-methods '(get head post put patch delete))

;; retried-codes : (Listof (List Integer Symbol))
;; Written out: a code of each class a retry repeats, connect,
;; send-receive and timeout, and its class.
(define retried-codes
  '((6 connect) (7 connect) (18 send-receive) (52 send-receive) (55 send-receive) (56 send-receive)
    (28 timeout)))

(test-equal "exchange-step: a perform-failed failure of the connect, send-receive or timeout class with a request size of 0, nothing sent, is retried for every method, its 28 before the deadline the transfer's own: next, after the backoff, 100"
  (map (lambda (row) (map (lambda (m) (list (car row) m '(next 100 1 1))) all-methods)) retried-codes)
  (map (lambda (row)
         (map (lambda (m) (list (car row) m (seen (fails (rstate m plain) (failure (car row) 0) 1000))))
              all-methods))
       retried-codes))

(test-equal "exchange-step: the same with a request size above 0, or #f, unknown, is retried for a method in the policy's methods alone: get, head, put and delete by default, and post alone with methods (post)"
  (list (map (lambda (row)
               (map (lambda (m)
                      (list (car row) m
                            (if (memq m '(post patch))
                                (failed-as m (cadr row) 'perform-failed (car row) 'sent 1)
                                '(next 100 1 1))))
                    all-methods))
             retried-codes)
        (map (lambda (m)
               (list m (if (memq m '(post patch))
                           (failed-as m 'send-receive 'perform-failed 52 'unknown 1)
                           '(next 100 1 1))))
             all-methods)
        (map (lambda (m) (list m (if (eq? m 'post) '(next 100 1 1) (failed-as m 'send-receive 'perform-failed 56 'sent 1))))
             all-methods))
  (list (map (lambda (row)
               (map (lambda (m) (list (car row) m (seen (fails (rstate m plain) (failure (car row) 75) 1000))))
                    all-methods))
             retried-codes)
        (map (lambda (m) (list m (seen (fails (rstate m plain) (failure 52 #f) 1000)))) all-methods)
        (let ((posts (make-http-retry 'backoff-ms 100 'jitter #f 'methods '(post))))
          (map (lambda (m) (list m (seen (fails (rstate m posts) (failure 56 9) 1000)))) all-methods))))

;; never-rows : (Listof (List (U Integer #f) Symbol Symbol))
;; Written out: a failure no retry repeats, nothing sent, for a get: CODE,
;; its class, and its reason.
(define never-rows
  '((35 tls perform-failed) (60 tls perform-failed) (16 protocol perform-failed)
    (92 protocol perform-failed) (1 protocol perform-failed) (8 protocol perform-failed)
    (100 too-large perform-failed) (63 too-large perform-failed) (2 none perform-failed)
    (999 none perform-failed) (23 too-large body-limit) (#f none callback-raised)
    (7 none setopt-failed) (#f none unknown-option) (#f none no-handle) (#f none cancelled)
    (#f none stopped)))

(test-equal "exchange-step never retries a TLS, protocol or too-large class, a code no class names, nor any reason but perform-failed, a setopt-failed whose code is connect's and the engine's stop among them: each fails at once, nothing sent, for a get"
  (map (lambda (row) (failed-as 'get (cadr row) (caddr row) (car row) 'zero 1)) never-rows)
  (map (lambda (row) (seen (fails (rstate 'get plain) (failure (car row) 0 (caddr row)) 1000))) never-rows))

(test-equal "exchange-step never retries a refused submit, whatever refused it, the engine's stop, a URL, and a connect class among them: it fails, no transfer counted"
  (list (list 'fail '(curl-engine-error stopped) (list 'exchange 'get given '() 0))
        (list 'fail '(curl-url-error scheme-not-http) (list 'exchange 'get given '() 0))
        (list 'fail '(curl-transfer-error connect perform-failed 7 zero) (list 'exchange 'get given '() 0)))
  (map (lambda (c) (seen (exchange-step (rstate 'get plain) (list 'refused c) (at 1000) U 0.0)))
       (list (make-curl-engine-error 'stopped #f) (make-curl-url-error "ftp://x/" 'scheme-not-http #f #f)
             (failure 7 0))))

(test-equal "exchange-step: a 28 that is the bound's is never retried, &http-timeout: the transfer's connect timeout the time left, as exchange-submission gives it, or one at the deadline; a 28 before it with a shorter connect timeout is retried, and so is one with no bound"
  (list (list 'fail '(http-error) '(http-timeout 5000) '(curl-transfer-error timeout perform-failed 28 zero)
              (list 'exchange 'get given '() 1))
        (list 'fail '(http-error) '(http-timeout 5000) '(curl-transfer-error timeout perform-failed 28 zero)
              (list 'exchange 'get given '() 1))
        '(next 100 1 1)
        '(next 100 1 1))
  (let ((own (make-exchange 'get given (table-request 'get #f) 5000 table-start 20 #f plain)))
    (list (let ((s (exchange-submission own (at 100))))
            (if (eq? (car s) 'submit) (seen (fails (cadr s) (failure 28 0) 600)) s))
          (seen (fails (rstate 'get plain) (failure 28 0) 5000))
          (seen (fails (rstate 'get plain) (failure 28 0) 4000))
          (seen (fails (rstate 'get plain #f) (failure 28 0) 900000)))))

;; status-rows : (Listof Integer)
(define status-rows '(429 503 500 200 404 301))

(test-equal "exchange-step: a status in the policy's statuses, 429 and 503 by default, is retried for a method in its methods, get, head, put and delete; post and patch answer it; any other status is answered"
  (map (lambda (status)
         (map (lambda (m)
                (list status m (if (and (memv status '(429 503)) (memq m '(get head put delete)))
                                   '(next 100 1 1)
                                   (list 'done status '()))))
              all-methods))
       status-rows)
  (map (lambda (status)
         (map (lambda (m) (list status m (seen (answers (rstate m plain) (reply status '()) 1000))))
              all-methods))
       status-rows))

(test-equal "exchange-step: a policy's own statuses and methods: statuses (500 418) with methods (post) retries a post's 500 and 418, and answers its 503 and a get's 500"
  '((next 100 1 1) (next 100 1 1) (done 503 ()) (done 500 ()))
  (let ((p (make-http-retry 'backoff-ms 100 'jitter #f 'statuses '(500 418) 'methods '(post))))
    (list (seen (answers (rstate 'post p) (reply 500 '()) 1000))
          (seen (answers (rstate 'post p) (reply 418 '()) 1000))
          (seen (answers (rstate 'post p) (reply 503 '()) 1000))
          (seen (answers (rstate 'get p) (reply 500 '()) 1000)))))

(test-equal "exchange-step: with no policy, nothing is retried: a failure nothing sent fails, and a 503 is answered"
  (list (failed-as 'get 'send-receive 'perform-failed 52 'zero 1) '(done 503 ()))
  (list (seen (fails (rstate 'get #f) (failure 52 0) 1000))
        (seen (answers (rstate 'get #f) (reply 503 '()) 1000))))

(test-equal "exchange-step's attempts: 3 makes two retries, then the third failure fails and the third 503 is answered, every transfer counted; 1 makes none"
  (list (list '(next 100 1 1) '(next 200 2 2) (failed-as 'get 'send-receive 'perform-failed 52 'zero 3))
        (list '(next 100 1 1) '(next 200 2 2) '(done 503 ()))
        (list (failed-as 'get 'send-receive 'perform-failed 52 'zero 1))
        (list '(done 503 ())))
  (let ((fail52 (lambda (s) (fails s (failure 52 0) 1000)))
        (got503 (lambda (s) (answers s (reply 503 '()) 1000)))
        (once (make-http-retry 'attempts 1 'backoff-ms 100 'jitter #f)))
    (list (through (rstate 'get plain) (list fail52 fail52 fail52))
          (through (rstate 'get plain) (list got503 got503 got503))
          (through (rstate 'get once) (list fail52))
          (through (rstate 'get once) (list got503)))))

(test-equal "exchange-step's backoff: 100, doubling per retry of the step, capped at 500, then the last attempt fails; with a backoff of 0 every wait is 0"
  (list (list '(next 100 1 1) '(next 200 2 2) '(next 400 3 3) '(next 500 4 4) '(next 500 5 5)
              (failed-as 'get 'connect 'perform-failed 7 'zero 6))
        (list '(next 0 1 1) '(next 0 2 2) (failed-as 'get 'connect 'perform-failed 7 'zero 3)))
  (let ((fail7 (lambda (s) (fails s (failure 7 0) 100))))
    (list (through (rstate 'get (make-http-retry 'attempts 6 'backoff-ms 100 'max-backoff-ms 500 'jitter #f) 60000)
                   (make-list 6 fail7))
          (through (rstate 'get (make-http-retry 'backoff-ms 0 'jitter #f)) (make-list 3 fail7)))))

(test-equal "exchange-step's jitter: the draw times the backoff, rounded down, for a failure and a status: 0.0, 0.25 and 0.9999 of 1000, a third, and half the second retry's 2000"
  '((next 0 1 1) (next 250 1 1) (next 999 1 1) (next 333 1 1) (next 1000 2 2) (next 250 1 1))
  (let ((p (make-http-retry 'backoff-ms 1000 'max-backoff-ms 10000 'jitter #t)))
    (list (seen (fails (rstate 'get p) (failure 56 0) 100 0.0))
          (seen (fails (rstate 'get p) (failure 56 0) 100 0.25))
          (seen (fails (rstate 'get p) (failure 56 0) 100 0.9999))
          (seen (fails (rstate 'get p) (failure 56 0) 100 1/3))
          (let ((a (fails (rstate 'get p) (failure 56 0) 100 0.9)))
            (if (eq? (car a) 'next) (seen (fails (cadr a) (failure 56 0) 1100 0.5)) (seen a)))
          (seen (answers (rstate 'get p) (reply 503 '()) 100 0.25)))))

;; after : String -> (Listof (Pairof String String))
(define (after value) (list (cons "Retry-After" value)))

;; wide-made : (U Retry (Pairof 'raised Any))
;; Jitter on, backoff 1000, max-backoff-ms 10000: made under a guard, as
;; plain is.
(define wide-made
  (guard (e (#t (cons 'raised (described e))))
    (make-http-retry 'backoff-ms 1000 'max-backoff-ms 10000 'jitter #t)))

;; wide : (U Retry #f)
(define wide (and (http-retry? wide-made) wide-made))

(test-equal "the tables' policy wide is made: jitter on, backoff 1000, max-backoff-ms 10000"
  '(3 1000 10000 #t (429 503) (get head put delete))
  (if wide (policy-fields wide) wide-made))

(test-equal "exchange-step: a retried status's Retry-After sets the wait in place of the backoff, and jitter never shortens it: delta-seconds 0, 2 and 3, and an HTTP-date in each form, 3 s past U, and one past, 0"
  '((next 0 1 1) (next 2000 1 1) (next 3000 1 1) (next 3000 1 1) (next 3000 1 1) (next 3000 1 1)
    (next 0 1 1))
  (map (lambda (value) (seen (answers (rstate 'get wide) (reply 503 (after value)) 100 0.25)))
       '("0" "2" " 3 " "Wed, 28 Oct 2026 12:00:03 GMT" "Wednesday, 28-Oct-26 12:00:03 GMT"
         "Wed Oct 28 12:00:03 2026" "Wed, 28 Oct 2026 11:58:20 GMT")))

(test-equal "exchange-step: a Retry-After that cannot be read is absent, and the backoff waits, its jitter drawn: half of 1000"
  (make-list 7 '(next 500 1 1))
  (map (lambda (value) (seen (answers (rstate 'get wide) (reply 429 (after value)) 100 0.5)))
       '("soon" "1.5" "-1" "+2" "" "Wed, 28 Oct 2026 12:00:03 UTC" "Wed, 28 Oct 2026 25:00:03 GMT")))

(test-equal "exchange-step reads the first Retry-After, A to Z folded, and no other header: not Retry-Afterx nor X-Retry-After"
  '((next 3000 1 1) (next 4000 1 1) (next 100 1 1) (next 100 1 1))
  (let ((p (make-http-retry 'backoff-ms 100 'max-backoff-ms 10000 'jitter #f)))
    (map (lambda (headers) (seen (answers (rstate 'get p) (reply 503 headers) 100)))
         '((("retry-after" . "3") ("Retry-After" . "9")) (("X-A" . "1") ("RETRY-AFTER" . "4"))
           (("Retry-Afterx" . "4")) (("X-Retry-After" . "4"))))))

(test-equal "exchange-step: a Retry-After longer than max-backoff-ms answers the response; one of exactly max-backoff-ms waits it, by delta-seconds and by date"
  '((done 503 ()) (next 1000 1 1) (done 503 ()) (next 1000 1 1))
  (map (lambda (value) (seen (answers (rstate 'get plain) (reply 503 (after value)) 100)))
       '("2" "1" "Wed, 28 Oct 2026 12:00:02 GMT" "Wed, 28 Oct 2026 12:00:01 GMT")))

(test-equal "exchange-step: a wait must end before the call's bound, 5000 ms: a Retry-After that would end at or past it answers the response; a backoff past it fails the failure as it is, no &http-timeout, and answers a status; with jitter the drawn wait is what must fit"
  (list '(done 503 ()) '(next 1000 1 1)
        (failed-as 'get 'send-receive 'perform-failed 52 'zero 1) '(next 3000 1 1) '(done 503 ())
        '(next 1500 1 1) '(done 503 ()))
  (let ((long (make-http-retry 'backoff-ms 3000 'max-backoff-ms 10000 'jitter #f))
        (drawn (make-http-retry 'backoff-ms 3000 'max-backoff-ms 10000 'jitter #t)))
    (list (seen (answers (rstate 'get wide) (reply 503 (after "2")) 3000))
          (seen (answers (rstate 'get wide) (reply 503 (after "1")) 3000))
          (seen (fails (rstate 'get long) (failure 52 0) 2000))
          (seen (fails (rstate 'get long) (failure 52 0) 1999))
          (seen (answers (rstate 'get long) (reply 503 '()) 2000))
          (seen (answers (rstate 'get drawn) (reply 503 '()) 3499 0.5))
          (seen (answers (rstate 'get drawn) (reply 503 '()) 3500 0.5)))))

(test-equal "exchange-step: with no bound, any wait fits"
  '((next 3000 1 1) (next 9000 1 1))
  (let ((long (make-http-retry 'backoff-ms 3000 'max-backoff-ms 10000 'jitter #f)))
    (list (seen (fails (rstate 'get long #f) (failure 52 0) 999999))
          (seen (answers (rstate 'get long #f) (reply 503 (after "9")) 999999)))))

;; redirect-reply : Integer String -> Response
(define (redirect-reply status location) (reply status (list (cons "Location" location))))

(test-equal "exchange-step: a step is one URL: a redirect starts the count again, so with attempts 2 a failure, a 302, then two failures retry once on each side, four transfers made"
  (list '(next 100 1 1) '(next 0 0 2) '(next 100 1 3)
        (list 'fail '(curl-transfer-error send-receive perform-failed 52 zero)
              (list 'exchange 'get given '((302 "http://h.example/r?q=1" ())) 4)))
  (let ((p (make-http-retry 'attempts 2 'backoff-ms 100 'jitter #f))
        (fail52 (lambda (s) (fails s (failure 52 0) 100))))
    (through (rstate 'get p) (list fail52 (lambda (s) (answers s (redirect-reply 302 "/n") 100)) fail52 fail52))))

(test-equal "exchange-step reads the step's method: a post a 303 made a get is retried after a send, as a get is; the post itself is not"
  (list '(next 0 0 1) '(next 100 1 2) (failed-as 'post 'send-receive 'perform-failed 52 'sent 1))
  (append (through (rstate 'post plain)
                   (list (lambda (s) (answers s (redirect-reply 303 "/n") 100))
                         (lambda (s) (fails s (failure 52 75) 100))))
          (list (seen (fails (rstate 'post plain) (failure 52 75) 100)))))

(test-equal "exchange-step's status retry reads the step's method: a post a 303 made a get has its 503 retried, as a get's is; the post's own 503 is answered"
  (list '(next 0 0 1) '(next 100 1 2) '(done 503 ()))
  (append (through (rstate 'post plain)
                   (list (lambda (s) (answers s (redirect-reply 303 "/n") 100))
                         (lambda (s) (answers s (reply 503 '()) 100))))
          (list (seen (answers (rstate 'post plain) (reply 503 '()) 100)))))

(test-equal "exchange-step's history holds the responses that redirected, never one a retry repeated: a 302, a 503 retried, then a 200, three transfers"
  (list '(next 0 0 1) '(next 100 1 2) (list 'done 200 '((302 "http://h.example/r?q=1" ()))) 3)
  (let* ((s0 (rstate 'get plain))
         (a1 (answers s0 (redirect-reply 302 "/n") 100))
         (a2 (answers (cadr a1) (reply 503 '()) 200))
         (a3 (answers (cadr a2) (reply 200 '()) 300)))
    (list (seen a1) (seen a2) (seen a3) (+ (exchange-transfers (cadr a2)) 1))))

(test-equal "exchange-step's retry: the next request is the step's request, the state's request and in flight; exchange-submission gives it the time left, 4000 ms at 1000 in, its method, URL, headers and body kept"
  '(same same same (submit 4000 700 "http://h.example/r?q=1" put (("X-A" . "1")) "b=1"))
  (let* ((s0 (rstate 'put plain))
         (a (answers s0 (reply 503 '()) 900)))
    (if (eq? (car a) 'next)
        (let ((state (cadr a)) (r (caddr a)))
          (list (if (eq? r (exchange-request s0)) 'same 'other)
                (if (eq? r (exchange-request state)) 'same 'other)
                (if (eq? r (exchange-flight state)) 'same 'other)
                (let ((s (exchange-submission state (at 1000))))
                  (if (eq? (car s) 'submit)
                      (let ((q (caddr s)))
                        (list 'submit (curl-request-timeout-ms q) (curl-request-connect-timeout-ms q)
                              (curl-request-url q) (curl-request-method q) (curl-request-headers q)
                              (latin-1 (curl-request-body q))))
                      (seen s)))))
        (seen a))))

(test-equal "exchange-step: a refused submit after a retry fails, with the transfers so far, one"
  (list '(next 100 1 1) (list 'fail '(curl-engine-error stopped) (list 'exchange 'get given '() 1)))
  (through (rstate 'get plain)
           (list (lambda (s) (fails s (failure 52 0) 100))
                 (lambda (s) (exchange-step s (list 'refused (make-curl-engine-error 'stopped #f)) (at 200) U
                                            0.0)))))

;; --- a retry that runs out of time answers what it retried

;; at-deadline : Answer -> (Listof Any)
;; What exchange-submission answers for the state of a next, at the bound's
;; 5000 ms: (submit), or the answer seen.
(define (at-deadline a)
  (if (eq? (car a) 'next)
      (let ((s (exchange-submission (cadr a) (at 5000))))
        (if (eq? (car s) 'submit) '(submit) (seen s)))
      (list 'not-a-next (seen a))))

(test-equal "exchange-submission with no time left for a retry answers what it retried, as with no policy: a 503 retried is answered, a 52 retried is raised with &http-exchange and no &http-timeout; the first request, and one after a redirect, get the plain &http-timeout; with time left it submits"
  (list '(done 503 ())
        (list 'fail '(curl-transfer-error send-receive perform-failed 52 zero) (list 'exchange 'get given '() 1))
        (list 'fail '(http-error) '(http-timeout 5000) (list 'exchange 'get given '() 0))
        (list 'fail '(http-error) '(http-timeout 5000)
              (list 'exchange 'get given '((302 "http://h.example/r?q=1" ())) 2))
        '(submit))
  (list (at-deadline (answers (rstate 'get plain) (reply 503 '()) 900))
        (at-deadline (fails (rstate 'get plain) (failure 52 0) 900))
        (let ((s (exchange-submission (rstate 'get plain) (at 5000)))) (seen s))
        (let ((a (answers (rstate 'get plain) (reply 503 '()) 900)))
          (if (eq? (car a) 'next)
              (at-deadline (answers (cadr a) (redirect-reply 302 "/n") 1000))
              (seen a)))
        (let ((a (answers (rstate 'get plain) (reply 503 '()) 900)))
          (if (eq? (car a) 'next)
              (let ((s (exchange-submission (cadr a) (at 4999)))) (if (eq? (car s) 'submit) '(submit) (seen s)))
              (seen a)))))

(test-equal "exchange-step: a retried transfer that fails with the bound's 28 answers what was retried, the 503 with its URL and body, or raises the 52 with every transfer counted and no &http-timeout; after a redirect the 28 is the plain &http-timeout"
  (list '(done 503 "http://h.example/r?q=1" "body" ())
        (list 'fail '(curl-transfer-error send-receive perform-failed 52 zero) (list 'exchange 'get given '() 2))
        (list 'fail '(http-error) '(http-timeout 5000) '(curl-transfer-error timeout perform-failed 28 zero)
              (list 'exchange 'get given '((302 "http://h.example/r?q=1" ())) 3)))
  (let ((c28 (failure 28 0)))
    (list (let ((a (answers (rstate 'get plain) (reply 503 '()) 900)))
            (if (eq? (car a) 'next)
                (let ((b (fails (cadr a) c28 5000)))
                  (if (eq? (car b) 'done)
                      (let ((r (cadr b)))
                        (list 'done (http-response-status r) (http-response-url r) (latin-1 (http-response-body r))
                              (http-response-history r)))
                      (seen b)))
                (seen a)))
          (let ((a (fails (rstate 'get plain) (failure 52 0) 900)))
            (if (eq? (car a) 'next) (seen (fails (cadr a) c28 5000)) (seen a)))
          (let ((a (answers (rstate 'get plain) (reply 503 '()) 900)))
            (if (eq? (car a) 'next)
                (let ((b (answers (cadr a) (redirect-reply 302 "/n") 1000)))
                  (if (eq? (car b) 'next) (seen (fails (cadr b) c28 5000)) (seen b)))
                (seen a))))))

(test-equal "exchange-step: a retried transfer that ends any other way goes through the rules: a 200 is answered, a 52 whose backoff no longer fits raises the 52, a 28 before the deadline with a shorter connect timeout is retried; each keeps the latest retried outcome"
  (list '(done 200 ())
        (failed-as 'get 'send-receive 'perform-failed 52 'zero 2)
        '(next 200 2 2)
        '(failed 28))
  (let ((retried (lambda () (answers (rstate 'get plain) (reply 503 '()) 900))))
    (list (let ((a (retried))) (if (eq? (car a) 'next) (seen (answers (cadr a) (reply 200 '()) 1000)) (seen a)))
          (let ((a (retried))) (if (eq? (car a) 'next) (seen (fails (cadr a) (failure 52 0) 4900)) (seen a)))
          (let ((a (retried))) (if (eq? (car a) 'next) (seen (fails (cadr a) (failure 28 0) 1000)) (seen a)))
          (let ((a (retried)))
            (if (eq? (car a) 'next)
                (let ((b (fails (cadr a) (failure 28 0) 1000)))
                  (if (eq? (car b) 'next)
                      (let ((kept (exchange-retried (cadr b))))
                        (list (car kept) (curl-transfer-error-code (cadr kept))))
                      (seen b)))
                (seen a))))))

;; after-retried : Answer Condition -> (Listof Any)
;; The answer to C, a bound's 28 at 5000 ms, after A, a retry's next.
(define (after-retried a c)
  (if (eq? (car a) 'next) (seen (fails (cadr a) c 5000)) (list 'not-a-next (seen a))))

(test-equal "exchange-step: the bound's 28 on a retried transfer answers what was retried only when the retry sent nothing, a request size of 0; above 0, or #f, unknown, it may have reached the server, and raises &http-timeout as with no policy; after a retried failure and after a retried response"
  (list (list 'fail '(curl-transfer-error send-receive perform-failed 52 zero) (list 'exchange 'get given '() 2))
        (list 'fail '(http-error) '(http-timeout 5000) '(curl-transfer-error timeout perform-failed 28 sent)
              (list 'exchange 'get given '() 2))
        (list 'fail '(http-error) '(http-timeout 5000) '(curl-transfer-error timeout perform-failed 28 unknown)
              (list 'exchange 'get given '() 2))
        '(done 503 ())
        (list 'fail '(http-error) '(http-timeout 5000) '(curl-transfer-error timeout perform-failed 28 sent)
              (list 'exchange 'get given '() 2))
        (list 'fail '(http-error) '(http-timeout 5000) '(curl-transfer-error timeout perform-failed 28 unknown)
              (list 'exchange 'get given '() 2)))
  (append (map (lambda (size) (after-retried (fails (rstate 'get plain) (failure 52 0) 900) (failure 28 size)))
               '(0 75 #f))
          (map (lambda (size) (after-retried (answers (rstate 'get plain) (reply 503 '()) 900) (failure 28 size)))
               '(0 75 #f))))

(test-equal "make-exchange refuses a retry that is neither a policy nor #f, an assertion violation; with seven arguments it has none"
  '((raised (assertion make-exchange)) (raised (assertion make-exchange)) none)
  (let ((r (make-curl-request table-url)))
    (list (outcome (lambda () (make-exchange 'get table-url r #f table-start 20 #f 3)))
          (outcome (lambda () (make-exchange 'get table-url r #f table-start 20 #f '(3 200))))
          (if (exchange-policy (make-exchange 'get table-url r #f table-start 20 #f)) 'some 'none))))

;; --- the generator --------------------------------------------------------------------

(test-equal "a session's draws: 10000 flonums, each strictly between 0 and 1; two sessions hold generators of their own"
  '(10000 0 distinct)
  (with-session '()
    (lambda (s)
      (with-session '()
        (lambda (t)
          (let ((draws (let loop ((i 0) (acc '()))
                         (if (= i 10000) acc (loop (+ i 1) (cons (http-session-draw s) acc))))))
            (list (length draws)
                  (length (filter (lambda (d) (not (and (flonum? d) (< 0 d) (< d 1)))) draws))
                  (if (eq? (http-session-generator s) (http-session-generator t)) 'shared 'distinct))))))))

;; library-path : -> String
(define (library-path)
  (let loop ((dirs (map car (library-directories))) (text ""))
    (cond ((null? dirs) text)
          ((string=? text "") (loop (cdr dirs) (car dirs)))
          (else (loop (cdr dirs) (string-append text ":" (car dirs)))))))

;; draws-child : (Listof Datum)
;; A program: a session's first three draws, then Chez's random's, each
;; printed, then the counts once the session is closed.
(define draws-child
  '((import (chezscheme) (http-client) (only (http-client private call) http-session-draw)
            (curl private counters))
    (define s (make-http-session))
    (define draws (let* ((a (http-session-draw s)) (b (http-session-draw s)) (c (http-session-draw s)))
                    (list a b c)))
    (define randoms (let* ((a (random 1.0)) (b (random 1.0)) (c (random 1.0))) (list a b c)))
    (http-session-close s)
    (write (list 'draws draws)) (newline)
    (write (list 'random randoms)) (newline)
    (write (list 'counts (native-counts))) (newline)))

;; read-all : String -> (Listof Any)
(define (read-all text)
  (let ((port (open-string-input-port text)))
    (let loop ((found '()))
      (let ((datum (guard (e (#t '(unreadable))) (read port))))
        (cond ((eof-object? datum) (reverse found))
              ((equal? datum '(unreadable)) (reverse (cons datum found)))
              (else (loop (cons datum found))))))))

;; run-draws-child : -> (List Integer (Listof Any))
(define (run-draws-child)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (let ((program (string-append dir "/draws-child.sps")))
         (call-with-output-file program
           (lambda (port) (for-each (lambda (form) (write form port) (newline port)) draws-child)))
         (let ((r (capture-command (list (getenv "CHEZ") "--libdirs" (library-path) "--program" program))))
           (list (car r) (read-all (cadr r)))))))))

(test-equal "a session's generator draws differently in each process, where Chez's random, the control, draws the same: two children's draws differ, their randoms agree, each exits 0 with every count zero"
  (list 'draws-differ 'randoms-agree '(0 0) (list (list 'counts zero-counts) (list 'counts zero-counts)))
  (let* ((one (run-draws-child))
         (two (run-draws-child))
         (field (lambda (run name) (and (pair? (cdr run)) (list? (cadr run)) (assq name (cadr run))))))
    (list (if (and (field one 'draws) (field two 'draws) (not (equal? (field one 'draws) (field two 'draws))))
              'draws-differ
              (list 'draws (field one 'draws) (field two 'draws) one two))
          (if (and (field one 'random) (equal? (field one 'random) (field two 'random)))
              'randoms-agree
              (list 'randoms (field one 'random) (field two 'random)))
          (list (car one) (car two))
          (list (field one 'counts) (field two 'counts)))))

;; --- the session's mutex ---------------------------------------------------------------

;; Evidence on the plain lanes alone: two threads that draw at once from a
;; generator with no lock lose and repeat draws (the slice's review, 3 of 3
;; runs), so their multiset parts from a copy's draws in turn. Under
;; Valgrind, which runs one thread at a time, the draws never overlap, and
;; this test cannot fail there.
(test-equal "evidence on the plain lanes, where threads run at once: two threads drawing 100000 each from one session draw the multiset that 200000 draws in turn from a copy of its generator give, the session's mutex holding each draw; under Valgrind, one thread at a time, it cannot fail"
  '(same-multiset 200000)
  (with-session '()
    (lambda (s)
      (let* ((g (http-session-generator s))
             (copy (vector->pseudo-random-generator (pseudo-random-generator->vector g)))
             (n 100000)
             (lock (make-mutex))
             (results '())
             (finish (lambda (r) (critical-section (with-mutex lock (set! results (cons r results))))))
             (got (lambda () (critical-section (with-mutex lock results)))))
        (for-each (lambda (i)
                    (fork-thread
                     (lambda ()
                       (finish (guard (e (#t 'raised))
                                 (let loop ((k 0) (acc '()))
                                   (if (= k n) acc (loop (+ k 1) (cons (http-session-draw s) acc)))))))))
                  '(0 1))
        ;; Each thread's answer is its list, or raised: the wait is bounded,
        ;; 120 s in steps of 10 ms.
        (let wait ((left 12000))
          (unless (or (= (length (got)) 2) (= left 0))
            (pause-ms 10)
            (wait (- left 1))))
        (let ((both (got)))
          (if (and (= (length both) 2) (for-all list? both))
              (let ((drawn (append (car both) (cadr both)))
                    (in-turn (let loop ((k 0) (acc '()))
                               (if (= k (* 2 n))
                                   acc
                                   (loop (+ k 1) (cons (pseudo-random-generator-next! copy) acc))))))
                (list (if (equal? (list-sort < drawn) (list-sort < in-turn)) 'same-multiset 'different-multiset)
                      (length drawn)))
              (list 'threads both)))))))

;; --- against the origin ----------------------------------------------------------------

;; environment-variables : (Listof String)
;; With a proxy variable set, libcurl would send this suite's transfers to
;; the proxy.
(define environment-variables
  '("http_proxy" "HTTP_PROXY" "https_proxy" "HTTPS_PROXY" "all_proxy" "ALL_PROXY"))

(test-equal "hermetic: none of the proxy variables is set"
  '()
  (filter (lambda (name) (getenv name)) environment-variables))

;; version : String
(define version (guard (e (#t "unknown")) (libcurl-info-version (loaded-libcurl))))

;; unknown-size-versions : (Listof String)
;; Written out: the libcurls whose request size is unknown, #f, for every
;; transfer that ran (ADR-0022, amended 2026-10-27), so a post's failure
;; there is never retried, a refused connect's among them.
(define unknown-size-versions '("8.7.0" "8.7.1"))

;; size-known? : Boolean
(define size-known? (not (member version unknown-size-versions)))

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

;; imf-date : Integer -> String
;; S's IMF-fixdate, from Chez's own UTC date.
(define (imf-date s) (car (date-forms s)))

;; storm : Symbol Natural String -> (List (Listof (Pairof Any Natural)) Any)
;; RUNS calls to URL, all on one session of its own making, bounded by 5000
;; ms, while a timer's handler raises continuably every 1 to 97 ticks, a
;; period that moves with the run, once the call's transfer has started:
;; #f, for MODE false; for prearm, (tick), re-arming the timer inside the
;; raise itself, 3 to 42 ticks on, so a tick lands while one is handled.
;; Three nested handlers resume every tick and #f, and count each they see;
;; the innermost ends the call on anything else. Answers the tally of how
;; each call ended, returned, compounded (a transfer error with
;; &http-exchange), raw (one without), (assertion WHO IRRITANTS) or (other
;; X); and no-raise-lost when every raise sent reached a handler, else
;; (lost SENT REACHED). Adapted from the slice's second review's probes.
(define (storm mode runs url)
  (let ((s (make-http-session 'timeout-ms 5000))
        (sent 0) (reached 0) (period 1) (base 0) (active #f) (in-raise #f) (tally '())
        (previous (timer-interrupt-handler)))
    (define (tick? e) (or (not e) (and (pair? e) (eq? (car e) 'tick))))
    (define (bump! k)
      (let ((a (assoc k tally)))
        (if a (set-cdr! a (+ (cdr a) 1)) (set! tally (cons (cons k 1) tally)))))
    (define (count-it e) (set! reached (+ reached 1)) 'resumed)
    (define (handler)
      (cond ((not active) #f)
            (in-raise (unless (eq? mode 'prearm) (set-timer period)))
            ((= (transfers-started) base) (set-timer period))
            (else
             (set! sent (+ sent 1))
             (let ((v (dynamic-wind
                        (lambda () (set! in-raise #t))
                        (lambda ()
                          (when (eq? mode 'prearm) (set-timer (+ 3 (mod sent 40))))
                          (raise-continuable (if (eq? mode 'false) #f (list 'tick))))
                        (lambda () (set! in-raise #f)))))
               (set-timer period)
               v))))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (let loop ((i 0))
          (when (< i runs)
            (set! base (transfers-started))
            (set! period (+ 1 (mod (* i 7) 97)))
            (timer-interrupt-handler handler)
            (let ((r (call/cc
                      (lambda (k)
                        (with-exception-handler
                         count-it
                         (lambda ()
                           (with-exception-handler
                            count-it
                            (lambda ()
                              (with-exception-handler
                               (lambda (e)
                                 (if (tick? e)
                                     (count-it e)
                                     (begin (set! active #f) (k (list 'raised e)))))
                               (lambda ()
                                 (set! active #t)
                                 (set-timer period)
                                 (let ((v (http-get s url))) (set! active #f) v)))))))))))
              (set-timer 0)
              (set! active #f)
              (bump! (cond ((not (and (pair? r) (eq? (car r) 'raised))) 'returned)
                           ((and (condition? (cadr r)) (http-exchange? (cadr r)) (curl-transfer-error? (cadr r)))
                            'compounded)
                           ((and (condition? (cadr r)) (curl-transfer-error? (cadr r))) 'raw)
                           ((and (condition? (cadr r)) (assertion-violation? (cadr r)) (who-condition? (cadr r)))
                            (list 'assertion (condition-who (cadr r))
                                  (and (irritants-condition? (cadr r)) (condition-irritants (cadr r)))))
                           (else (list 'other (cadr r))))))
            (loop (+ i 1))))
        (list tally (if (= sent reached) 'no-raise-lost (list 'lost sent reached))))
      (lambda ()
        (set-timer 0)
        (timer-interrupt-handler previous)
        (http-session-close s)))))

;; handler-raise : String (U Retry #f) -> (Listof Any)
;; A post to URL, a stall, on a session with POLICY, its await interrupted by
;; a timer's handler once its transfer is live and 300 ms have passed:
;; the handler makes a call of its own, to a port that refuses, and
;; raises what that raised, a &curl-error, uncaught. Answers whether the
;; post raised that very object, its &http-exchange, the transfers started,
;; the post's and the handler's, whether the raise reached the caller
;; within 1500 ms of the call's start, where the post's bound is 3000, and
;; whether none is live within 3 s.
(define (handler-raise url policy)
  (let ((s2 (make-http-session 'timeout-ms 2000)))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (with-session (append '(timeout-ms 3000) (if policy (list 'retry policy) '()))
          (lambda (own)
            (let* ((t0 (now-ms))
                   (started (transfers-started))
                   (planted #f)
                   (fired #f)
                   (previous (timer-interrupt-handler))
                   (caught (guard (e (#t e))
                             (timer-interrupt-handler
                              (lambda ()
                                (cond (fired #f)
                                      ((and (>= (- (now-ms) t0) 300) (= (- (transfers-started) started) 1)
                                            (= (count-of 'transfer) 1))
                                       (set! fired #t)
                                       (let ((c (guard (x (#t x)) (http-get s2 "http://127.0.0.1:1/heartbeat") 'returned)))
                                         (set! planted c)
                                         (raise c)))
                                      (else (set-timer 200)))))
                             (set-timer 200)
                             (http-post own url 'body "b=1")
                             'returned))
                   (took (- (now-ms) t0)))
              (set-timer 0)
              (timer-interrupt-handler previous)
              (let* ((made (- (transfers-started) started))
                     (ended (ended-within 3000)))
                (list (cond ((not planted) 'never-planted)
                            ((eq? caught planted) 'the-handler-s-own)
                            (else (cons 'another (if (condition? caught) (described caught) caught))))
                      (if (and (condition? planted) (http-exchange? planted))
                          (list (http-exchange-method planted) (http-exchange-transfers planted))
                          planted)
                      made (if (< took 1500) 'promptly (list 'took took)) ended))))))
      (lambda () (http-session-close s2)))))

(call-with-origin
 (lambda (o)
   ;; at-raw : String -> String
   (define (at-raw path)
     (guard (e (#t "http://no-raw-face/"))
       (let ((f (origin-face o 'raw)))
         (string-append "http://" (car f) ":" (number->string (cdr f)) path))))

   ;; retry-url : String Natural String [Integer [String]] -> String
   ;; The raw face's retry script for KEY: FAIL failures by HOW, then 200;
   ;; with CODE, and AFTER, the Retry-After's bytes, for a status.
   (define (retry-url key fail how . more)
     (at-raw (string-append "/raw/retry?key=" key "&fail=" (number->string fail) "&how=" how
                            (if (pair? more) (string-append "&code=" (number->string (car more))) "")
                            (if (and (pair? more) (pair? (cdr more)))
                                (string-append "&after=" (pct (cadr more)))
                                ""))))

   ;; stall-url : String Natural String [Integer] -> String
   ;; The retry script for KEY, FAIL failures by HOW, with CODE, then a
   ;; stall: the retried request is never answered.
   (define (stall-url key fail how . code)
     (at-raw (string-append "/raw/retry?key=" key "&fail=" (number->string fail) "&how=" how
                            (if (pair? code) (string-append "&code=" (number->string (car code))) "")
                            "&then=stall")))

   ;; attempts-of : String -> String
   ;; The raw face's count for KEY, its body, read on a session of its own
   ;; with no policy.
   (define (attempts-of key)
     (guard (e (#t (list 'raised (described e))))
       (with-session '(timeout-ms 20000)
         (lambda (own)
           (latin-1 (http-response-body (http-get own (at-raw (string-append "/raw/attempts?key=" key)))))))))

   ;; retrying : Natural Natural [Boolean] -> (Listof Any)
   ;; A session's keys: a bound of 20 s and a policy of ATTEMPTS, BACKOFF
   ;; ms, no jitter.
   (define (retrying attempts backoff)
     (list 'timeout-ms 20000
           'retry (make-http-retry 'attempts attempts 'backoff-ms backoff 'max-backoff-ms 5000 'jitter #f)))

   ;; timed : (-> Any) -> (List Any Natural Natural)
   ;; THUNK's answer, the ms it took, and the transfers started meanwhile.
   (define (timed thunk)
     (let* ((started (transfers-started))
            (t0 (now-ms))
            (a (answer thunk))
            (took (- (now-ms) t0))
            (made (- (transfers-started) started)))
       (list a took made)))

   ;; --- each kind of failure, retried

   (let ((url (retry-url "close-get" 2 "close")))
     (test-equal "a close before any response, live: a get is retried twice, the third attempt's 200 answered with no history; three transfers, three attempts at the origin, after waits of 50 then 100 ms"
       (list (list 'answered 200 url "attempt 3\n" '()) 3 "attempts 3\n" 'waited)
       (with-session (retrying 3 50)
         (lambda (own)
           (let* ((r (timed (lambda () (http-get own url))))
                  (count (attempts-of "close-get")))
             (list (car r) (caddr r) count (if (>= (cadr r) 150) 'waited (list 'took (cadr r)))))))))

   (let ((url (retry-url "reset-get" 2 "reset")))
     (test-equal "a reset before any response, live: a get is retried twice, the third attempt's 200 answered; three attempts at the origin"
       (list (list 'answered 200 url "attempt 3\n" '()) 3 "attempts 3\n")
       (with-session (retrying 3 50)
         (lambda (own)
           (let* ((r (timed (lambda () (http-get own url))))
                  (count (attempts-of "reset-get")))
             (list (car r) (caddr r) count))))))

   (let ((url (retry-url "after-delta" 1 "status" 503 "1")))
     (test-equal "a 503 with Retry-After: 1, live: the get waits 1 s, not the backoff's 100 ms, then its 200 is answered; two attempts at the origin, no sooner than 1000 ms and sooner than 2000"
       (list (list 'answered 200 url "attempt 2\n" '()) 2 "attempts 2\n" 'within)
       (with-session (retrying 3 100)
         (lambda (own)
           (let* ((r (timed (lambda () (http-get own url))))
                  (count (attempts-of "after-delta")))
             (list (car r) (caddr r) count
                   (if (and (>= (cadr r) 1000) (< (cadr r) 2000)) 'within (list 'took (cadr r)))))))))

   ;; The date names a whole second, 2 s past the UTC second read before the
   ;; call, so the wait is 2 s, or 1 s once that second has ended when the
   ;; 429 arrives: the date's 1 s resolution.
   (let* ((date (guard (e (#t "no date")) (imf-date (+ (utc-now) 2))))
          (url (retry-url "after-date" 1 "status" 429 date)))
     (test-equal "a 429 with Retry-After an IMF-fixdate 2 s ahead, live: the get waits until that second, 1 to 2 s by the date's resolution, then its 200 is answered; two attempts at the origin"
       (list (list 'answered 200 url "attempt 2\n" '()) 2 "attempts 2\n" 'within)
       (with-session (retrying 3 100)
         (lambda (own)
           (let* ((r (timed (lambda () (http-get own url))))
                  (count (attempts-of "after-date")))
             (list (car r) (caddr r) count
                   (if (and (>= (cadr r) 1000) (< (cadr r) 2600)) 'within (list 'took (cadr r) date))))))))

   ;; --- the controls

   (let ((url (retry-url "close-post" 1 "close")))
     (test-equal "the control, live: a post that met a close after its request was sent is not retried, by default methods: the low level's send-receive 52, its request size sent, or unknown on 8.7.0 and 8.7.1; one attempt at the origin"
       (list (list 'raised (list 'curl-transfer-error 'send-receive 'perform-failed 52 (if size-known? 'sent 'unknown))
                   (list 'exchange 'post url '() 1))
             1 "attempts 1\n")
       (with-session (retrying 3 50)
         (lambda (own)
           (let* ((r (timed (lambda () (http-post own url 'body "b=1"))))
                  (count (attempts-of "close-post")))
             (list (car r) (caddr r) count))))))

   ;; Port 1 on 127.0.0.1 refuses every connect: nothing is sent, and the
   ;; size says so, but on 8.7.0 and 8.7.1, where it is unknown.
   (let ((refused "http://127.0.0.1:1/refused"))
     (test-equal (string-append "a refused connect, live, on " version
                                ": a get is retried, nothing sent, and so is a post, but on 8.7.0 and 8.7.1, whose request size is unknown, where the post is made once")
       (list (list (list 'raised (list 'curl-transfer-error 'connect 'perform-failed 7 (if size-known? 'zero 'unknown))
                         (list 'exchange 'get refused '() 3))
                   3)
             (list (list 'raised (list 'curl-transfer-error 'connect 'perform-failed 7 (if size-known? 'zero 'unknown))
                         (list 'exchange 'post refused '() (if size-known? 3 1)))
                   (if size-known? 3 1)))
       (with-session (retrying 3 20)
         (lambda (own)
           (let* ((get (timed (lambda () (http-get own refused))))
                  (post (timed (lambda () (http-post own refused 'body "b=1")))))
             (list (list (car get) (caddr get)) (list (car post) (caddr post))))))))

   (let ((url (retry-url "no-policy" 1 "close")))
     (test-equal "no policy, live: a get's close is raised at once, the low level's 52, one attempt at the origin (ADR-0026)"
       (list (list 'raised (list 'curl-transfer-error 'send-receive 'perform-failed 52 (if size-known? 'sent 'unknown))
                   (list 'exchange 'get url '() 1))
             1 "attempts 1\n")
       (with-session '(timeout-ms 20000)
         (lambda (own)
           (let* ((r (timed (lambda () (http-get own url))))
                  (count (attempts-of "no-policy")))
             (list (car r) (caddr r) count))))))

   (let ((off (retry-url "call-off" 1 "close"))
         (on (retry-url "call-on" 1 "close")))
     (test-equal "a call's retry replaces its session's, live: #f over the session's policy makes one attempt; a policy over the session's #f retries"
       (list (list 1 "attempts 1\n") (list (list 'answered 200 on "attempt 2\n" '()) "attempts 2\n"))
       (list (with-session (retrying 3 20)
               (lambda (own)
                 (let* ((r (timed (lambda () (http-get own off 'retry #f))))
                        (count (attempts-of "call-off")))
                   (list (caddr r) count))))
             (with-session '(timeout-ms 20000)
               (lambda (own)
                 (let* ((a (answer (lambda () (http-get own on 'retry (make-http-retry 'backoff-ms 20)))))
                        (count (attempts-of "call-on")))
                   (list a count)))))))

   (let ((post (retry-url "status-post" 1 "status" 503))
         (other (retry-url "status-other" 1 "status" 500)))
     (test-equal "the controls for a status, live: a post's 503 is answered, post being in no default methods, and a get's 500, in no default statuses; one attempt each"
       (list (list (list 'answered 503 post "attempt 1\n" '()) "attempts 1\n")
             (list (list 'answered 500 other "attempt 1\n" '()) "attempts 1\n"))
       (with-session (retrying 3 20)
         (lambda (own)
           (let* ((a (answer (lambda () (http-post own post 'body "b=1"))))
                  (ca (attempts-of "status-post"))
                  (b (answer (lambda () (http-get own other))))
                  (cb (attempts-of "status-other")))
             (list (list a ca) (list b cb)))))))

   ;; --- the last attempt

   (let ((close (retry-url "last-close" 5 "close"))
         (status (retry-url "last-status" 5 "status" 503)))
     (test-equal "after the last attempt, live: a close raises the low level's 52, with three transfers, and a 503 is answered, with no history; three attempts at the origin each"
       (list (list (list 'raised (list 'curl-transfer-error 'send-receive 'perform-failed 52 (if size-known? 'sent 'unknown))
                         (list 'exchange 'get close '() 3))
                   "attempts 3\n")
             (list (list 'answered 503 status "attempt 3\n" '()) "attempts 3\n"))
       (with-session (retrying 3 20)
         (lambda (own)
           (let* ((a (answer (lambda () (http-get own close))))
                  (ca (attempts-of "last-close"))
                  (b (answer (lambda () (http-get own status))))
                  (cb (attempts-of "last-status")))
             (list (list a ca) (list b cb)))))))

   ;; --- the call's bound across a retry's wait

   ;; The backoff is 4000 ms and the call's bound 1000: a wait the bound
   ;; cannot hold is not taken, and the call answers at once. Taken, the
   ;; wait would end past the bound, and the call raise &http-timeout after
   ;; 4 s.
   (let ((status (retry-url "bound-status" 1 "status" 503))
         (close (retry-url "bound-close" 1 "close"))
         (after (retry-url "bound-after" 1 "status" 503 "2")))
     (test-equal "the call's bound across a retry's wait, live: with a bound of 1000 ms and a backoff of 4000, a 503 is answered and a close raised at once, and a Retry-After of 2 s answers the 503; one attempt at the origin each, each sooner than 1000 ms"
       (list (list (list 'answered 503 status "attempt 1\n" '()) "attempts 1\n" 'at-once)
             (list (list 'raised (list 'curl-transfer-error 'send-receive 'perform-failed 52 (if size-known? 'sent 'unknown))
                         (list 'exchange 'get close '() 1))
                   "attempts 1\n" 'at-once)
             (list (list 'answered 503 after "attempt 1\n" '()) "attempts 1\n" 'at-once))
       (with-session (list 'timeout-ms 20000
                           'retry (make-http-retry 'backoff-ms 4000 'max-backoff-ms 10000 'jitter #f))
         (lambda (own)
           (in-order (lambda (row)
                       (let* ((r (timed (lambda () (http-get own (car row) 'timeout-ms 1000))))
                              (count (attempts-of (cadr row))))
                         (list (car r) count (if (< (cadr r) 1000) 'at-once (list 'took (cadr r))))))
                     (list (list status "bound-status") (list close "bound-close")
                           (list after "bound-after")))))))

   (let ((url (retry-url "bound-fits" 1 "status" 503)))
     (test-equal "the bound's control, live: a wait of 300 ms that ends before a bound of 5000 is taken, and the 200 answered; two attempts at the origin"
       (list (list 'answered 200 url "attempt 2\n" '()) "attempts 2\n")
       (with-session (retrying 3 300)
         (lambda (own)
           (let* ((a (answer (lambda () (http-get own url 'timeout-ms 5000))))
                  (count (attempts-of "bound-fits")))
             (list a count))))))

   ;; --- an escape during a retry's wait

   ;; The first attempt's close comes at once, and the backoff is 3000 ms: a
   ;; timer's handler escapes once one transfer has started, none is live,
   ;; and 300 ms have passed, which is inside the wait.
   (let ((url (retry-url "escape-wait" 1 "close")))
     (test-equal "an escape during a retry's wait, by a timer's handler, lands in the wait, sooner than 2000 ms where it runs 3000; the call ends with no transfer live, one started, one attempt at the origin"
       (list 'escaped 'in-the-wait 'ended 1 "attempts 1\n")
       (with-session (list 'timeout-ms 30000 'retry (make-http-retry 'backoff-ms 3000 'jitter #f))
         (lambda (own)
           (let* ((t0 (now-ms))
                  (started (transfers-started))
                  (how (escape-when (lambda ()
                                      (and (>= (- (now-ms) t0) 300)
                                           (>= (- (transfers-started) started) 1)
                                           (= (count-of 'transfer) 0)))
                                    (lambda () (http-get own url))))
                  (took (- (now-ms) t0))
                  (ended (ended-within 3000))
                  (made (- (transfers-started) started))
                  (count (attempts-of "escape-wait")))
             (list how (if (< took 2000) 'in-the-wait (list 'took took)) ended made count))))))

   ;; --- a retry that runs out of time, live

   ;; The first attempt fails at once, the wait is 300 ms, and the retried
   ;; request reaches the origin, which stalls, so its transfer ends with the
   ;; bound's 28, at 1500 ms, its request sent: the call raises the bound's
   ;; &http-timeout, as with no policy, never the 503 or the 52 it retried.
   (let ((status (stall-url "out-status" 1 "status" 503))
         (close (stall-url "out-close" 1 "close")))
     (test-equal "a retry that runs out of time after its request went out, live: the retried request reaches the origin, which stalls, until the call's bound of 1500 ms, and the call raises &http-timeout with the low level's 28, its request sent, after a 503 and after a close alike; two attempts at the origin each, the call ending no sooner than 1500 ms and sooner than 2500"
       (let ((timed-out (lambda (url)
                          (list 'raised '(http-error) '(http-timeout 1500)
                                (list 'curl-transfer-error 'timeout 'perform-failed 28 (if size-known? 'sent 'unknown))
                                (list 'exchange 'get url '() 2)))))
         (list (list (timed-out status) "attempts 2\n" 'at-the-bound)
               (list (timed-out close) "attempts 2\n" 'at-the-bound)))
       (with-session (list 'timeout-ms 20000
                           'retry (make-http-retry 'backoff-ms 300 'max-backoff-ms 5000 'jitter #f))
         (lambda (own)
           (in-order (lambda (row)
                       (let* ((r (timed (lambda () (http-get own (car row) 'timeout-ms 1500))))
                              (count (attempts-of (cadr row))))
                         (list (car r) count
                               (if (and (>= (cadr r) 1500) (< (cadr r) 2500)) 'at-the-bound (list 'took (cadr r))))))
                     (list (list status "out-status") (list close "out-close")))))))

   ;; An https request to the raw face stalls in its TLS handshake, since
   ;; the raw face reads a ClientHello as part of a head it waits for: a 28
   ;; with nothing sent, a request size of 0. The call's connect timeout of
   ;; 900 ms ends the first attempt before the bound of 1500, as the
   ;; transfer's own, which is retried after 100 ms; the retry has at most
   ;; 500 ms left, under its connect timeout, so its 28 is the bound's, again
   ;; with nothing sent, and the call raises the 28 it retried, with no
   ;; &http-timeout. The first attempt has 500 ms to spare: under Valgrind
   ;; and load its 28 came at about 800 ms of a 600 ms timeout (the slice's
   ;; third review), which a bound of 1000 left 100 ms for. On 8.7.0 and
   ;; 8.7.1 the size is unknown, so the retry may have sent its request,
   ;; and the call raises the bound's &http-timeout.
   (let ((url (guard (e (#t "https://no-raw-face/stall"))
                (let ((f (origin-face o 'raw)))
                  (string-append "https://" (car f) ":" (number->string (cdr f)) "/stall")))))
     (test-equal (string-append "a retry that runs out of time having sent nothing, live, on " version
                                ": two TLS handshakes stall at the raw face, the second until the call's bound of 1500 ms, and the call raises the first 28 it retried, nothing sent, with two transfers and no &http-timeout; on 8.7.0 and 8.7.1, &http-timeout")
       (list (if size-known?
                 (list 'raised '(curl-transfer-error timeout perform-failed 28 zero) (list 'exchange 'get url '() 2))
                 (list 'raised '(http-error) '(http-timeout 1500) '(curl-transfer-error timeout perform-failed 28 unknown)
                       (list 'exchange 'get url '() 2)))
             'at-the-bound)
       (with-session (list 'timeout-ms 20000
                           'retry (make-http-retry 'backoff-ms 100 'max-backoff-ms 5000 'jitter #f))
         (lambda (own)
           (let ((r (timed (lambda () (http-get own url 'timeout-ms 1500 'connect-timeout-ms 900)))))
             (list (car r) (if (and (>= (cadr r) 1500) (< (cadr r) 2300)) 'at-the-bound (list 'took (cadr r)))))))))

   ;; --- a storm of the caller's own raises during the await

   (let ((ok-url (guard (e (#t "http://no-http-face/status/200"))
                   (let ((f (origin-face o 'http)))
                     (string-append "http://" (car f) ":" (number->string (cdr f)) "/status/200")))))
     (test-equal "a storm of #f raised continuably by a timer's handler through 20 calls to a 200, each resumed by the caller's handler, which counts it: every call answers its 200, none ends in an assertion, and no raise is lost"
       '(((returned . 20)) no-raise-lost)
       (storm 'false 20 ok-url))

     (test-equal "a storm of ticks, the timer re-armed inside each raise, through 20 calls to a refused port: every call raises its own failure compounded with &http-exchange, none ends in an assertion or as a raw transfer error, and no raise is lost"
       '(((compounded . 20)) no-raise-lost)
       (storm 'prearm 20 "http://127.0.0.1:1/x")))

   ;; --- a condition the caller's handler raises during the await


   (test-equal "a &curl-error the caller's timer handler raises while a post with a policy awaits is no outcome of the post's: it reaches the caller as raised, that very object, the handler's own get's, at once, and the post is neither retried nor left live: two transfers, the post's and the handler's, none live within 3 s"
     (list 'the-handler-s-own '(get 1) 2 'promptly 'ended)
     (handler-raise (at-raw "/raw/stall-before-head") (make-http-retry 'backoff-ms 50 'jitter #f)))

   (test-equal "the same with no policy: the handler's &curl-error reaches the caller as raised, not compounded with the post's &http-exchange, and the post is cancelled"
     (list 'the-handler-s-own '(get 1) 2 'promptly 'ended)
     (handler-raise (at-raw "/raw/stall-before-head") #f))

   ;; A session closed while a retrying call awaits its transfer: the engine
   ;; ends the transfer as stopped, which no policy retries, and the drive
   ;; reads it through curl-token-outcome, a condition that is no class's,
   ;; and the call raises it, one transfer made (the slice's third review).
   (test-equal "a session closed during a retrying call's await, live: the transfer ends as stopped, which is never retried, and the call raises it, compounded, with one transfer and no &http-timeout"
     '(stopped 1 #f)
     (let* ((s (make-http-session 'timeout-ms 10000 'retry (make-http-retry 'backoff-ms 50 'jitter #f)))
            (closer (fork-thread
                     (lambda ()
                       (guard (e (#t #f))
                         (sleep (make-time 'time-duration 300000000 0))
                         (http-session-close s))))))
       (guard (e ((and (curl-transfer-error? e) (http-exchange? e))
                  (list (curl-transfer-error-reason e) (http-exchange-transfers e) (http-timeout? e)))
                 (#t (list 'other (describe e))))
         (http-get s (at-raw "/raw/stall-before-head"))
         'returned)))

   ;; --- the session's draw, live

   ;; The session's generator is copied, by its state, to see its next draw
   ;; without taking it: the suite draws from the session until that lies
   ;; in [0.3, 0.5], so the wait it sets, of a 2000 ms backoff, is 600 to
   ;; 1000 ms, far from 0, and the call, with its two transfers, takes less
   ;; than 900 ms more, so less than the 2000 a wait with no jitter takes.
   ;; The call then makes two steps, the 503 and the 200, and draws twice,
   ;; once each.
   (let ((url (retry-url "jitter-draw" 1 "status" 503)))
     (test-equal "a call's jitter is the session's draw, live: the wait is that draw times the backoff, predicted from a copy of the generator, and the call draws once per step, two"
       (list (list 'answered 200 url "attempt 2\n" '()) 'as-drawn 'two-draws)
       (with-session (list 'timeout-ms 20000
                           'retry (make-http-retry 'backoff-ms 2000 'max-backoff-ms 2000 'jitter #t))
         (lambda (own)
           (let* ((g (http-session-generator own))
                  (copy (lambda () (vector->pseudo-random-generator (pseudo-random-generator->vector g))))
                  (skipped (let loop ((k 0))
                             (let ((d (pseudo-random-generator-next! (copy))))
                               (if (or (and (>= d 0.3) (<= d 0.5)) (> k 1000))
                                   k
                                   (begin (http-session-draw own) (loop (+ k 1)))))))
                  (ahead (copy))
                  (d1 (pseudo-random-generator-next! ahead))
                  (d2 (pseudo-random-generator-next! ahead))
                  (predicted (floor (* (exact d1) 2000)))
                  (t0 (now-ms))
                  (a (answer (lambda () (http-get own url))))
                  (took (- (now-ms) t0)))
             (list a
                   (if (and (>= took predicted) (< took (+ predicted 900)))
                       'as-drawn
                       (list 'took took 'predicted predicted 'skipped skipped))
                   (if (equal? (pseudo-random-generator->vector g) (pseudo-random-generator->vector ahead))
                       'two-draws
                       'other-draws)))))))

   ;; The drive takes its draw as a procedure: a fixed one, 0.9 of a 600 ms
   ;; backoff, waits 540 ms, so the drive hands the core what it drew, once
   ;; per step.
   (let ((url (retry-url "drive-draw" 1 "close")))
     (test-equal "drive-exchange hands the core its draw, once per step: a draw of 0.9 of a 600 ms backoff waits 540 ms, and two steps draw twice"
       (list 200 "attempt 2\n" 'waited 2)
       (let* ((engine (make-curl-engine))
              (draws 0)
              (state (make-exchange 'get url (make-curl-request url 'timeout-ms 20000) 20000 (monotonic-ns) 20 #f
                                    (make-http-retry 'backoff-ms 600 'jitter #t)))
              (t0 (now-ms))
              (r (guard (e (#t (cons 'raised (described e))))
                   (dynamic-wind
                     (lambda () #f)
                     (lambda () (drive-exchange engine state (lambda () (set! draws (+ draws 1)) 0.9)))
                     (lambda () (curl-engine-stop engine)))))
              (took (- (now-ms) t0)))
         (if (http-response? r)
             (list (http-response-status r) (latin-1 (http-response-body r))
                   (if (and (>= took 540) (< took 1500)) 'waited (list 'took took)) draws)
             r))))

   (test-equal "every count is zero once the suite's sessions have closed"
     zero-counts
     (native-counts))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "retry")

(exit (suite-exit-status runner))
