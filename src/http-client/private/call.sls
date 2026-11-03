#!r6rs
;;; (http-client private call): a session's and a call's keys, checked; the
;;; session's record, with its jitter generator; the retry policy, made
;;; from its keys; the merge of a call's keys with its session's; the form
;;; encoding; a call made into its first request, with its redirect and
;;; retry policies; and a request group's limit (the M5 plan, sections 3.2,
;;; 3.4, 3.5 and 3.7; ADR-0025, ADR-0026, ADR-0027).
;;;
;;; Every check of a caller's string or list runs on a private copy, and the
;;; copy is what is used (ADR-0001, amended): headers, the user agent, the
;;; CA file's path, a body, a form, params, and a policy's statuses and
;;; methods are copied before anything reads them. The keys are refused by
;;; name first, as the low level refuses its own; then the high level's own
;;; values, a body, a form, params, redirects, allow-downgrade and retry;
;;; then the low level's, by building a request from them, whose refusal
;;; passes through as it was raised.
;;;
;;; A session's one mutable part, beside its engine, is its jitter
;;; generator, a make-pseudo-random-generator of its own, time-seeded, never
;;; Chez's random, which draws the same sequence in every process (the M5
;;; plan, section 2). Chez 10.4.0 seeds each from the UTC time, (time-second
;;; + time-nanosecond) & 0xFFFFFFFF (its s/5_3.ss). Each draw holds the
;;; session's own mutex, inside a critical section around with-mutex, so an
;;; escape cannot leave the mutex held (traps.md), and threads that share
;;; the session draw one at a time: two threads drawing at once from a bare
;;; generator lose and repeat draws (the slice's review).
;;;
;;; Header names are compared with A to Z folded alone, never char-downcase
;;; or char-foldcase, which fold U+212A KELVIN SIGN to k and U+017F LONG S
;;; to s (traps.md): libcurl and a server compare bytes.
(library (http-client private call)
  (export session-keys call-keys port-keys retry-keys key-settings string-pairs string-pairs-within
          ascii-ci=? form-encode form-type with-form-type merge-fields
          make-http-retry http-retry? http-retry-attempts http-retry-backoff-ms
          http-retry-max-backoff-ms http-retry-jitter http-retry-statuses http-retry-methods
          new-http-session http-session? http-session-engine http-session-defaults
          http-session-redirects http-session-allow-downgrade http-session-retry
          http-session-draw http-session-generator
          default-redirects default-stream-buffer session-defaults session-policy call-request
          call-request-of group-keys group-limit)
  (import (curl)
          (rnrs)
          (only (chezscheme) critical-section make-mutex with-mutex make-pseudo-random-generator
                pseudo-random-generator-next!)
          (http-client private conditions))

  ;; --- refusals --------------------------------------------------------------------

  ;; refuse : Symbol Symbol Any Symbol String -> Nothing
  ;; Raises &http-request-error FIELD VALUE REASON, as WHO, with MESSAGE.
  (define (refuse who field value reason message)
    (raise (condition (make-http-request-error field value reason)
                      (make-who-condition who)
                      (make-message-condition message)
                      (make-irritants-condition (list value)))))

  ;; --- the keys --------------------------------------------------------------------

  ;; request-session-keys : (Listof Symbol)
  ;; The session's keys that are make-curl-request's, each with the low
  ;; level's default (the M5 plan, section 3.2), http-version, credentials,
  ;; proxy-ca-file and proxy-verify among them (the M7 plan, section 3.1).
  (define request-session-keys
    '(headers user-agent timeout-ms connect-timeout-ms body-limit ca-file verify proxy
      http-version credentials proxy-ca-file proxy-verify))

  ;; policy-keys : (Listof Symbol)
  ;; The session's keys that are the high level's own: redirects, the most
  ;; redirects a call follows, an exact natural or #f, 20 by default;
  ;; allow-downgrade, whether a redirect from https to http is followed, a
  ;; boolean, #f by default (ADR-0027); and retry, a policy, or #f, none,
  ;; by default (ADR-0026).
  (define policy-keys '(redirects allow-downgrade retry))

  ;; session-keys : (Listof Symbol)
  ;; The keys make-http-session takes: the request's, then the policy's.
  (define session-keys (append request-session-keys policy-keys))

  ;; call-keys : (Listof Symbol)
  ;; The keys a call takes: the session's, each replacing the session's
  ;; value, then body, form, params and body-length, a producer's length
  ;; (ADR-0031, decision 2).
  (define call-keys (append session-keys '(body form params body-length)))

  ;; port-keys : (Listof Symbol)
  ;; The keys call-with-response-port takes: a call's, then stream-buffer,
  ;; its own (ADR-0031, decision 1).
  (define port-keys (append call-keys '(stream-buffer)))

  ;; default-redirects : Natural
  ;; The most redirects a call follows when neither the session nor the
  ;; call names a bound: 20, after the browsers' (the M5 plan, section 3.2).
  (define default-redirects 20)

  ;; default-stream-buffer : Positive-Integer
  ;; The bytes of a streamed response's body a call's token buffers when
  ;; the call names no stream-buffer: 65,536 (the M6 plan, section 3.1).
  (define default-stream-buffer 65536)

  ;; key-settings : Symbol (Listof Symbol) List -> (Listof (Pairof Symbol Any))
  ;; PLIST, KEY VALUE ..., as (KEY . VALUE) pairs, in its order, each key
  ;; refused by name, as WHO, before anything else: one KEYS lacks,
  ;; unknown-key; one with no value after it, missing-value; one given
  ;; twice, repeated-key. Each is &http-request-error, field key, whose
  ;; value is the key as given, or, for a key that is no symbol, its kind,
  ;; shown-key's: a value found where a key belongs can be a proxy URL or
  ;; credentials. PLIST is a rest argument's, fresh.
  (define (key-settings who keys plist)
    (let loop ((rest plist) (found '()))
      (if (null? rest)
          (reverse found)
          (let ((key (car rest)))
            (unless (memq key keys)
              (refuse who 'key (shown-key key) 'unknown-key "not a key this takes"))
            (when (null? (cdr rest))
              (refuse who 'key key 'missing-value "a key with no value after it"))
            (when (assq key found)
              (refuse who 'key key 'repeated-key "a key given twice"))
            (loop (cddr rest) (cons (cons key (cadr rest)) found))))))

  ;; settings->plist : (Listof (Pairof Symbol Any)) -> List
  (define (settings->plist settings)
    (fold-right (lambda (setting plist) (cons (car setting) (cons (cdr setting) plist)))
                '() settings))

  ;; --- private copies --------------------------------------------------------------

  ;; string-pairs : Any -> (U (Listof (Pairof String String)) #f)
  ;; A fresh copy of X, a list of pairs of two strings: fresh pairs, fresh
  ;; strings. #f for anything else. X is walked once to measure it, by
  ;; length, which refuses an improper or a circular list itself, and the
  ;; copy is bounded by that length, as the low level's snapshot bounds its
  ;; own (curl private transfer): another thread's set-cdr! that makes X
  ;; longer, shorter or cyclic after the measure answers #f, never a loop.
  ;; No list? walks it first: a set-cdr! between the two walks made length
  ;; raise "circular" where list? had passed (the slice's second review:
  ;; once in 20,000 calls on a 3000-pair list).
  (define (string-pairs x)
    (let ((n (guard (e ((assertion-violation? e) #f)) (length x))))
      (and n (string-pairs-within x n))))

  ;; string-pairs-within : Any Natural -> (U (Listof (Pairof String String)) #f)
  ;; A fresh copy of X when X is a list of exactly LEFT pairs of two
  ;; strings, else #f, having read at most LEFT pairs of it. Each pair's car
  ;; and cdr are read once, so the copy is what was checked.
  (define (string-pairs-within x left)
    (let loop ((rest x) (left left) (copied '()))
      (cond ((and (null? rest) (= left 0)) (reverse copied))
            ((or (= left 0) (not (pair? rest))) #f)
            (else
             (let ((p (car rest)))
               (and (pair? p)
                    (let ((name (car p)) (value (cdr p)))
                      (and (string? name) (string? value)
                           (loop (cdr rest) (- left 1)
                                 (cons (cons (string-copy name) (string-copy value))
                                       copied))))))))))

  ;; copied-setting : (Pairof Symbol Any) -> (Pairof Symbol Any)
  ;; A request key's value, copied where it can change: headers, when a
  ;; list of string pairs, and the user agent, the CA file, a proxy URL and
  ;; the proxy CA file, when strings. Anything else is kept as given, for
  ;; the low level to refuse.
  (define (copied-setting setting)
    (let ((key (car setting)) (value (cdr setting)))
      (cons key
            (case key
              ((headers) (or (string-pairs value) value))
              ((user-agent ca-file proxy proxy-ca-file) (if (string? value) (string-copy value) value))
              (else value)))))

  ;; --- A to Z folding --------------------------------------------------------------

  ;; ascii-downcase : Char -> Char
  ;; C, with A to Z made a to z, and nothing else changed.
  (define (ascii-downcase c)
    (if (and (char<=? #\A c) (char<=? c #\Z))
        (integer->char (+ (char->integer c) 32))
        c))

  ;; ascii-ci=? : String String -> Boolean
  ;; Whether A and B are equal with A to Z folded alone.
  (define (ascii-ci=? a b)
    (let ((n (string-length a)))
      (and (= n (string-length b))
           (let loop ((i 0))
             (or (= i n)
                 (and (char=? (ascii-downcase (string-ref a i)) (ascii-downcase (string-ref b i)))
                      (loop (+ i 1))))))))

  ;; named? : (Listof (Pairof String String)) String -> Boolean
  ;; Whether HEADERS hold one named NAME, A to Z folded.
  (define (named? headers name)
    (exists (lambda (header) (ascii-ci=? (car header) name)) headers))

  ;; --- the merge -------------------------------------------------------------------

  ;; merge-fields : (Listof (Pairof String String)) (U String #f)
  ;;                (Listof (Pairof String String)) (U '() (List (U String #f)))
  ;;                -> (List (Listof (Pairof String String)) (U String #f))
  ;; A call's headers and user agent merged with its session's (the M5
  ;; plan, section 3.2): the merged headers, and the merged user-agent
  ;; field. CALL-AGENT is () when the call gives no user-agent, and (A)
  ;; when it gives A.
  ;;   - A call's header replaces every session header of its name, A to Z
  ;;     folded: the session's other headers come first, in their order,
  ;;     then the call's, in theirs.
  ;;   - A call's User-Agent header makes the field #f. Otherwise a call's
  ;;     user-agent field is the field, and drops the session's User-Agent
  ;;     header, which the low level would refuse beside it. Otherwise the
  ;;     session's field stands.
  (define (merge-fields session-headers session-agent call-headers call-agent)
    (let* ((replaced (filter (lambda (header) (not (named? call-headers (car header))))
                             session-headers))
           (kept (if (pair? call-agent)
                     (filter (lambda (header) (not (ascii-ci=? (car header) "User-Agent")))
                             replaced)
                     replaced))
           (agent (cond ((named? call-headers "User-Agent") #f)
                        ((pair? call-agent) (car call-agent))
                        (else session-agent))))
      (list (append kept call-headers) agent)))

  ;; --- the form encoding -----------------------------------------------------------

  ;; form-type : String
  (define form-type "application/x-www-form-urlencoded")

  ;; with-form-type : (Listof (Pairof String String)) -> (Listof (Pairof String String))
  ;; HEADERS, with Content-Type: application/x-www-form-urlencoded appended,
  ;; unless they name a Content-Type, A to Z folded.
  (define (with-form-type headers)
    (if (named? headers "Content-Type")
        headers
        (append headers (list (cons "Content-Type" form-type)))))

  ;; kept-byte? : Natural -> Boolean
  ;; Whether the form encoding writes byte B as its own char: *, -, ., _,
  ;; and ASCII letters and digits.
  (define (kept-byte? b)
    (or (memv b '(#x2A #x2D #x2E #x5F))
        (<= #x30 b #x39)
        (<= #x41 b #x5A)
        (<= #x61 b #x7A)))

  (define hex-digits "0123456789ABCDEF")

  ;; put-component : Output-Port String -> Void
  ;; S's UTF-8 bytes, each kept, a space as +, or %XX in upper-case hex.
  (define (put-component out s)
    (for-each (lambda (b)
                (cond ((kept-byte? b) (put-char out (integer->char b)))
                      ((= b #x20) (put-char out #\+))
                      (else
                       (put-char out #\%)
                       (put-char out (string-ref hex-digits (div b 16)))
                       (put-char out (string-ref hex-digits (mod b 16))))))
              (bytevector->u8-list (string->utf8 s))))

  ;; form-encode : (Listof (Pairof String String)) -> String
  ;; PAIRS as the WHATWG URL Standard's application/x-www-form-urlencoded
  ;; serializer writes them, on UTF-8 bytes: each name, =, its value, with &
  ;; between pairs, in the order given. A copy of PAIRS is what is encoded;
  ;; anything but a list of string pairs is an assertion violation.
  (define (form-encode pairs)
    (let ((copy (string-pairs pairs)))
      (unless copy
        (assertion-violation 'form-encode "a list of pairs of a name and a value, both strings"
                             (shown-value pairs)))
      (call-with-string-output-port
       (lambda (out)
         (let loop ((rest copy) (first? #t))
           (unless (null? rest)
             (unless first? (put-char out #\&))
             (put-component out (caar rest))
             (put-char out #\=)
             (put-component out (cdar rest))
             (loop (cdr rest) #f)))))))

  ;; --- the policy ------------------------------------------------------------------

  ;; checked-redirects : Symbol Any -> (U Natural #f)
  ;; VALUE, a redirects value: an exact natural, or #f; anything else is
  ;; refused as WHO, not-a-redirect-count.
  (define (checked-redirects who value)
    (unless (or (not value) (and (integer? value) (exact? value) (>= value 0)))
      (refuse who 'redirects (shown-value value) 'not-a-redirect-count
              "redirects is an exact natural, the most redirects a call follows, or #f, none"))
    value)

  ;; checked-allow-downgrade : Symbol Any -> Boolean
  ;; VALUE, an allow-downgrade value, #t or #f; anything else is refused as
  ;; WHO, not-a-boolean.
  (define (checked-allow-downgrade who value)
    (unless (boolean? value)
      (refuse who 'allow-downgrade (shown-value value) 'not-a-boolean "allow-downgrade is #t or #f"))
    value)

  ;; checked-retry : Symbol Any -> (U Retry #f)
  ;; VALUE, a retry value: a policy, or #f; anything else is refused as WHO,
  ;; not-a-retry-policy.
  (define (checked-retry who value)
    (unless (or (not value) (http-retry? value))
      (refuse who 'retry (shown-value value) 'not-a-retry-policy
              "retry is a policy, made by make-http-retry, or #f, none"))
    value)

  ;; policy-of : Symbol (Listof (Pairof Symbol Any)) (U Natural #f) Boolean (U Retry #f)
  ;;             -> (List (U Natural #f) Boolean (U Retry #f))
  ;; SETTINGS' redirects, allow-downgrade and retry, each checked, as WHO,
  ;; in that order; each one SETTINGS lack is REDIRECTS, ALLOW-DOWNGRADE or
  ;; RETRY.
  (define (policy-of who settings redirects allow-downgrade retry)
    (let* ((r (assq 'redirects settings))
           (a (assq 'allow-downgrade settings))
           (p (assq 'retry settings))
           (redirects (if r (checked-redirects who (cdr r)) redirects))
           (allow-downgrade (if a (checked-allow-downgrade who (cdr a)) allow-downgrade))
           (retry (if p (checked-retry who (cdr p)) retry)))
      (list redirects allow-downgrade retry)))

  ;; session-policy : (Listof (Pairof Symbol Any))
  ;;                  -> (List (U Natural #f) Boolean (U Retry #f))
  ;; A session's redirects, allow-downgrade and retry, from its SETTINGS,
  ;; each checked, or the default: 20, #f and #f.
  (define (session-policy settings)
    (policy-of 'make-http-session settings default-redirects #f #f))

  ;; --- a request group's keys (the M5 plan, section 3.7) ---------------------------

  ;; group-keys : (Listof Symbol)
  ;; The keys call-with-request-group and http-parallel take: limit alone.
  (define group-keys '(limit))

  ;; group-limit : Symbol List -> (U Positive-Integer #f)
  ;; A group's limit, the most calls in flight, from PLIST, KEY VALUE ...,
  ;; refused as WHO: its keys first, by key-settings' rules, then the
  ;; value, an exact positive integer, or #f for none, the default; anything
  ;; else is &http-request-error, field limit, not-a-limit, its value as
  ;; given.
  (define (group-limit who plist)
    (let* ((settings (key-settings who group-keys plist))
           (hit (assq 'limit settings)))
      (if hit
          (let ((v (cdr hit)))
            (unless (or (not v) (and (integer? v) (exact? v) (positive? v)))
              (refuse who 'limit (shown-value v) 'not-a-limit
                      "limit is an exact positive integer, the most calls in flight, or #f, none"))
            v)
          #f)))

  ;; --- the retry policy (ADR-0026; the M5 plan, section 3.5) -----------------------

  ;; A policy, data alone: what exchange-step reads to retry.
  ;; http-retry? : Any -> Boolean
  ;; http-retry-attempts : Retry -> Positive-Integer
  ;;   transfers per step, the first among them
  ;; http-retry-backoff-ms : Retry -> Natural
  ;;   the first retry's backoff, doubling for each later one in the step
  ;; http-retry-max-backoff-ms : Retry -> Natural
  ;;   the backoff's cap, and the longest Retry-After the policy waits
  ;; http-retry-jitter : Retry -> Boolean
  ;;   whether a backoff's wait is a draw's share of it, "full jitter"
  ;; http-retry-statuses : Retry -> (Listof Integer)
  ;; http-retry-methods : Retry -> (Listof Symbol)
  ;;   the methods a status, or a failure after a request was sent, is
  ;;   retried for
  (define-record-type (http-retry new-http-retry http-retry?)
    (fields (immutable attempts http-retry-attempts)
            (immutable backoff-ms http-retry-backoff-ms)
            (immutable max-backoff-ms http-retry-max-backoff-ms)
            (immutable jitter http-retry-jitter)
            (immutable statuses http-retry-statuses)
            (immutable methods http-retry-methods))
    (sealed #t)
    (opaque #t))

  ;; retry-keys : (Listof Symbol)
  ;; The keys make-http-retry takes, in the order it checks them.
  (define retry-keys '(attempts backoff-ms max-backoff-ms jitter statuses methods))

  ;; call-methods : (Listof Symbol)
  ;; The methods a call takes, and a policy's methods may name.
  (define call-methods '(get head post put patch delete))

  ;; exact-natural? : Any -> Boolean
  (define (exact-natural? x) (and (integer? x) (exact? x) (>= x 0)))

  ;; list-within : Any (Any -> Boolean) -> (U List #f)
  ;; A fresh copy of X when X is a list each of whose elements OK? takes,
  ;; else #f. X is measured once, by length, which refuses an improper or a
  ;; circular list itself, and read once, within that bound, as
  ;; string-pairs reads its list: the copy is what was checked.
  (define (list-within x ok?)
    (let ((n (guard (e ((assertion-violation? e) #f)) (length x))))
      (and n
           (let loop ((rest x) (left n) (copied '()))
             (cond ((and (null? rest) (= left 0)) (reverse copied))
                   ((or (= left 0) (not (pair? rest))) #f)
                   (else
                    (let ((v (car rest)))
                      (and (ok? v) (loop (cdr rest) (- left 1) (cons v copied))))))))))

  ;; status? : Any -> Boolean
  ;; Whether X is an exact integer from 400 to 599, a client's or a
  ;; server's error: a 3xx a policy could retry would also be a redirect,
  ;; and a 2xx is a success (decided by the maintainer, 2026-10-28).
  (define (status? x) (and (integer? x) (exact? x) (<= 400 x 599)))

  ;; make-http-retry : Any ... -> Retry
  ;; (make-http-retry KEY VALUE ...): a policy, each key once at most, each
  ;; left out its default. The keys are refused by name first, as a
  ;; session's are, with who make-http-retry; then each value, in
  ;; retry-keys' order:
  ;;   attempts        an exact integer of 1 or more; 3; not-an-attempt-count
  ;;   backoff-ms      an exact natural; 200; not-a-backoff
  ;;   max-backoff-ms  an exact natural; 10000; not-a-backoff
  ;;   jitter          a boolean; #t; not-a-boolean
  ;;   statuses        a list of exact integers from 400 to 599; (429 503);
  ;;                   not-a-status-list
  ;;   methods         a list of get, head, post, put, patch and delete;
  ;;                   (get head put delete), which RFC 9110, section 9.2.2,
  ;;                   calls idempotent; not-a-method-list
  ;; each &http-request-error, its field the key, its value as given. A
  ;; list is copied, so a later change to the caller's is not the policy's.
  (define (make-http-retry . plist)
    (let* ((settings (key-settings 'make-http-retry retry-keys plist))
           (value (lambda (key default)
                    (let ((hit (assq key settings))) (if hit (cdr hit) default))))
           (attempts (let ((v (value 'attempts 3)))
                       (unless (and (integer? v) (exact? v) (>= v 1))
                         (refuse 'make-http-retry 'attempts (shown-value v) 'not-an-attempt-count
                                 "attempts is an exact integer of 1 or more, the transfers per step"))
                       v))
           (backoff (let ((v (value 'backoff-ms 200)))
                      (unless (exact-natural? v)
                        (refuse 'make-http-retry 'backoff-ms (shown-value v) 'not-a-backoff
                                "backoff-ms is an exact natural number of ms"))
                      v))
           (cap (let ((v (value 'max-backoff-ms 10000)))
                  (unless (exact-natural? v)
                    (refuse 'make-http-retry 'max-backoff-ms (shown-value v) 'not-a-backoff
                            "max-backoff-ms is an exact natural number of ms"))
                  v))
           (jitter (let ((v (value 'jitter #t)))
                     (unless (boolean? v)
                       (refuse 'make-http-retry 'jitter (shown-value v) 'not-a-boolean "jitter is #t or #f"))
                     v))
           (statuses (let ((v (value 'statuses '(429 503))))
                       (or (list-within v status?)
                           (refuse 'make-http-retry 'statuses (shown-value v) 'not-a-status-list
                                   "statuses is a list of exact integers from 400 to 599"))))
           (methods (let ((v (value 'methods '(get head put delete))))
                      (or (list-within v (lambda (m) (and (memq m call-methods) #t)))
                          (refuse 'make-http-retry 'methods (shown-value v) 'not-a-method-list
                                  "methods is a list of get, head, post, put, patch and delete")))))
      (new-http-retry attempts backoff cap jitter statuses methods)))

  ;; --- the session -----------------------------------------------------------------

  ;; A session: its engine; DEFAULTS, a request of the session's request
  ;; keys, checked by make-curl-request, whose URL nothing reads; its
  ;; redirect and retry policies, checked; and its jitter generator, with
  ;; the mutex every draw holds.
  ;; new-http-session : Engine Request (U Natural #f) Boolean (U Retry #f) -> Session
  ;;   a fresh generator, and a fresh mutex
  ;; http-session? : Any -> Boolean
  ;; http-session-engine : Session -> Engine
  ;; http-session-defaults : Session -> Request
  ;; http-session-redirects : Session -> (U Natural #f)
  ;; http-session-allow-downgrade : Session -> Boolean
  ;; http-session-retry : Session -> (U Retry #f)
  ;; http-session-generator : Session -> Pseudo-Random-Generator
  ;;   for the suites alone, which read its state to predict a draw
  (define-record-type (http-session make-session-record http-session?)
    (fields (immutable engine http-session-engine)
            (immutable defaults http-session-defaults)
            (immutable redirects http-session-redirects)
            (immutable allow-downgrade http-session-allow-downgrade)
            (immutable retry http-session-retry)
            (immutable generator http-session-generator)
            (immutable lock http-session-lock))
    (sealed #t)
    (opaque #t))

  (define (new-http-session engine defaults redirects allow-downgrade retry)
    (make-session-record engine defaults redirects allow-downgrade retry
                         (make-pseudo-random-generator) (make-mutex)))

  ;; http-session-draw : Session -> Real
  ;; The next draw from SESSION's generator, a flonum strictly between 0
  ;; and 1, so in [0, 1), as exchange-step takes one: Chez 10.4.0's
  ;; S_random_state_next_double (its c/random.c) answers (y + 1) * norm,
  ;; y from MRG32k3a in [0, m1 - 1] and norm 1 / (m1 + 1). It holds the
  ;; session's mutex, within a critical section, for the draw alone.
  (define (http-session-draw session)
    (let ((generator (http-session-generator session)))
      (critical-section
       (with-mutex (http-session-lock session)
         (pseudo-random-generator-next! generator)))))

  ;; check-url : String
  ;; The URL the checks' requests carry: make-curl-request parses no URL.
  (define check-url "http://localhost/")

  ;; request-settings : (Listof (Pairof Symbol Any)) -> (Listof (Pairof Symbol Any))
  ;; SETTINGS' request keys alone, in their order.
  (define (request-settings settings)
    (filter (lambda (setting) (memq (car setting) request-session-keys)) settings))

  ;; session-defaults : (Listof (Pairof Symbol Any)) -> Request
  ;; SETTINGS' request keys, a session's, copied, as a request
  ;; make-curl-request checks: its refusal raises as it was raised.
  (define (session-defaults settings)
    (apply make-curl-request check-url
           (settings->plist (map copied-setting (request-settings settings)))))

  ;; --- a call ----------------------------------------------------------------------

  ;; call-body : Symbol Any -> (U Bytevector Procedure)
  ;; A copy of a call's body: a bytevector's bytes, or a string's UTF-8
  ;; bytes; a procedure, a producer, as it is (ADR-0031, decision 2);
  ;; anything else is not-a-body, as WHO.
  (define (call-body who value)
    (cond ((bytevector? value) (bytevector-copy value))
          ((string? value) (string->utf8 value))
          ((procedure? value) value)
          (else (refuse who 'body (shown-value value) 'not-a-body
                        "a body is a bytevector, a string, sent as UTF-8, or a producer, a procedure of no arguments"))))

  ;; call-pairs : Symbol Symbol Any -> (Listof (Pairof String String))
  ;; A copy of a call's form or params, FIELD; anything but a list of
  ;; string pairs is not-name-value-pairs, as WHO.
  (define (call-pairs who field value)
    (or (string-pairs value)
        (refuse who field (shown-value value) 'not-name-value-pairs
                "a list of pairs of a name and a value, both strings")))

  ;; call-request : Session Any Any List
  ;;                -> (Values Request (U Natural #f) Boolean (U Retry #f))
  ;; call-request-of's first four answers for http-request's call, its keys
  ;; call-keys, as http-request, a producer among the bodies it takes.
  (define (call-request session method url plist)
    (let-values (((request redirects allow-downgrade retry producer)
                  (call-request-of 'http-request 'request session method url plist)))
      (values request redirects allow-downgrade retry)))

  ;; call-request-of : Symbol (U 'request 'group 'port) Session Any Any List
  ;;                   -> (Values Request (U Natural #f) Boolean (U Retry #f)
  ;;                              (U Procedure #f))
  ;; The first request of a call of METHOD on URL, with PLIST's keys merged
  ;; with SESSION's, then the call's redirects, allow-downgrade and retry:
  ;; each the call's, or else the session's; a call's retry #f is none, over
  ;; a session's policy; and its producer, or #f. MODE says whose call it
  ;; is: request, http-request's and a verb's; group, a request group's go
  ;; or http-parallel's spec; port, call-with-response-port's, whose keys
  ;; are port-keys. Each refusal is WHO's. In order, each raising as it is
  ;; refused:
  ;;   1. the keys, by key-settings' rules;
  ;;   2. body, not-a-body; form, then params, not-name-value-pairs;
  ;;      redirects, not-a-redirect-count; allow-downgrade, not-a-boolean;
  ;;      retry, not-a-retry-policy;
  ;;   3. body and form together, body-and-form; either with get or head,
  ;;      body-not-allowed, field the one given; a producer in a group's
  ;;      call, stream-in-group, field body, before anything is submitted
  ;;      (the M6 plan, section 3.6); a port's stream-buffer of #f, an
  ;;      assertion violation, since every response of its streams;
  ;;   4. the method and the call's own request keys, by make-curl-request,
  ;;      with the body, its body-length and its stream-buffer: the low
  ;;      level's refusal, body-length-without-stream beside a body that is
  ;;      no producer among them;
  ;;   5. the URL: params, when non-empty, appended by curl-url-append-query,
  ;;      then the whole read back by curl-url-part, the URL requested.
  ;; The merge (merge-fields) gives the headers and the user agent; a form
  ;; is sent as its encoding's bytes, with-form-type's header added. A
  ;; producer's request has body stream, and body-length as the call gives
  ;; it; it streams its response too, by the call's stream-buffer for a
  ;; port, 65,536 by default, and by 65,536 for http-request, which reads
  ;; the response's body whole. Every other request key is the call's, or
  ;; else the session's, credentials among them: a call's #f sends none
  ;; over a session's; but a call that names its own proxy drops the
  ;; session's proxy-ca-file and proxy-verify, each then the call's or its
  ;; default, #f and #t, so a session's https:// proxy's TLS settings never
  ;; meet a call's other proxy (the M7 plan, section 3.1). make-curl-request
  ;; checks the merge, so a session's
  ;; credentials beside a call's Authorization header, or a session's
  ;; Digest beside a call's stream, is refused as the request is built,
  ;; as the low level raises it; a Proxy-Authorization header, a session's
  ;; or a call's, is refused so too.
  (define (call-request-of who mode session method url plist)
    (let* ((settings (key-settings who (if (eq? mode 'port) port-keys call-keys) plist))
           (body-given (assq 'body settings))
           (form-given (assq 'form settings))
           (params-given (assq 'params settings))
           (length-given (assq 'body-length settings))
           (buffer-given (assq 'stream-buffer settings))
           (body (and body-given (call-body who (cdr body-given))))
           (form (and form-given (call-pairs who 'form (cdr form-given))))
           (params (and params-given (call-pairs who 'params (cdr params-given))))
           (policy (policy-of who settings (http-session-redirects session)
                              (http-session-allow-downgrade session)
                              (http-session-retry session)))
           (producer (and (procedure? body) body)))
      (when (and body-given form-given)
        (refuse who 'form #f 'body-and-form "a body and a form together"))
      (when (and (memq method '(get head)) (or body-given form-given))
        (refuse who (if body-given 'body 'form) method 'body-not-allowed
                "a body or a form with get or head, which send none"))
      (when (and producer (eq? mode 'group))
        (refuse who 'body producer 'stream-in-group
                "a request group takes no producer: its calls share one thread, which a producer's wait would hold"))
      (when (and buffer-given (not (cdr buffer-given)))
        (assertion-violation who
          "a stream-buffer is a positive exact integer: every response of call-with-response-port streams"
          #f))
      (let* ((own (map copied-setting (request-settings settings)))
             (bytes (if producer #f (or body (and form (string->utf8 (form-encode form))))))
             (sent (cond (producer 'stream) (else bytes)))
             (body-length (and length-given (cdr length-given)))
             (stream-buffer (cond ((eq? mode 'port)
                                   (if buffer-given (cdr buffer-given) default-stream-buffer))
                                  (producer default-stream-buffer)
                                  (else #f)))
             (checked (apply make-curl-request check-url 'method method
                             (append (settings->plist own)
                                     (if sent (list 'body sent) '())
                                     (if length-given (list 'body-length body-length) '())
                                     (if stream-buffer (list 'stream-buffer stream-buffer) '()))))
             (defaults (http-session-defaults session))
             (hit (lambda (key) (assq key own)))
             (merged (merge-fields (curl-request-headers defaults)
                                   (curl-request-user-agent defaults)
                                   (curl-request-headers checked)
                                   (if (hit 'user-agent) (list (cdr (hit 'user-agent))) '())))
             (headers (if form (with-form-type (car merged)) (car merged)))
             (pick (lambda (key accessor)
                     (if (hit key) (accessor checked) (accessor defaults))))
             (target (curl-url-part (if (and params (pair? params))
                                        (curl-url-append-query url (form-encode params))
                                        url)
                                    'url)))
        (values (make-curl-request target
                                   'method method
                                   'headers headers
                                   'body sent
                                   'body-length body-length
                                   'stream-buffer stream-buffer
                                   'user-agent (cadr merged)
                                   'timeout-ms (pick 'timeout-ms curl-request-timeout-ms)
                                   'connect-timeout-ms (pick 'connect-timeout-ms
                                                             curl-request-connect-timeout-ms)
                                   'body-limit (pick 'body-limit curl-request-body-limit)
                                   'ca-file (pick 'ca-file curl-request-ca-file)
                                   'verify (pick 'verify curl-request-verify)
                                   'proxy (pick 'proxy curl-request-proxy)
                                   'http-version (pick 'http-version curl-request-http-version)
                                   'credentials (pick 'credentials curl-request-credentials)
                                   'proxy-ca-file (cond ((hit 'proxy-ca-file)
                                                         (curl-request-proxy-ca-file checked))
                                                        ((hit 'proxy) #f)
                                                        (else (curl-request-proxy-ca-file defaults)))
                                   'proxy-verify (cond ((hit 'proxy-verify)
                                                        (curl-request-proxy-verify checked))
                                                       ((hit 'proxy) #t)
                                                       (else (curl-request-proxy-verify defaults))))
                (car policy)
                (cadr policy)
                (caddr policy)
                producer)))))
