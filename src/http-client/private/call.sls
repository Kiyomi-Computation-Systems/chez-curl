#!r6rs
;;; (http-client private call): a session's and a call's keys, checked; the
;;; session's record; the merge of a call's keys with its session's; the
;;; form encoding; and a call made into its first request, with its
;;; redirect policy (the M5 plan, sections 3.2 and 3.4; ADR-0025,
;;; ADR-0027).
;;;
;;; Every check of a caller's string or list runs on a private copy, and the
;;; copy is what is used (ADR-0001, amended): headers, the user agent, the
;;; CA file's path, a body, a form and params are copied before anything
;;; reads them. The keys are refused by name first, as the low level refuses
;;; its own; then the high level's own values, a body, a form, params,
;;; redirects and allow-downgrade; then the low level's, by building a
;;; request from them, whose refusal passes through as it was raised.
;;;
;;; Header names are compared with A to Z folded alone, never char-downcase
;;; or char-foldcase, which fold U+212A KELVIN SIGN to k and U+017F LONG S
;;; to s (traps.md): libcurl and a server compare bytes.
(library (http-client private call)
  (export session-keys call-keys key-settings string-pairs string-pairs-within ascii-ci=?
          form-encode form-type with-form-type merge-fields
          new-http-session http-session? http-session-engine http-session-defaults
          http-session-redirects http-session-allow-downgrade
          default-redirects session-defaults session-policy call-request)
  (import (curl)
          (rnrs)
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
  ;; level's default (the M5 plan, section 3.2).
  (define request-session-keys
    '(headers user-agent timeout-ms connect-timeout-ms body-limit ca-file verify proxy))

  ;; policy-keys : (Listof Symbol)
  ;; The session's keys that are the high level's own: redirects, the most
  ;; redirects a call follows, an exact natural or #f, 20 by default; and
  ;; allow-downgrade, whether a redirect from https to http is followed, a
  ;; boolean, #f by default (ADR-0027). retry comes with retries.
  (define policy-keys '(redirects allow-downgrade))

  ;; session-keys : (Listof Symbol)
  ;; The keys make-http-session takes: the request's, then the policy's.
  (define session-keys (append request-session-keys policy-keys))

  ;; call-keys : (Listof Symbol)
  ;; The keys a call takes: the session's, each replacing the session's
  ;; value, then body, form and params.
  (define call-keys (append session-keys '(body form params)))

  ;; default-redirects : Natural
  ;; The most redirects a call follows when neither the session nor the
  ;; call names a bound: 20, after the browsers' (the M5 plan, section 3.2).
  (define default-redirects 20)

  ;; key-settings : Symbol (Listof Symbol) List -> (Listof (Pairof Symbol Any))
  ;; PLIST, KEY VALUE ..., as (KEY . VALUE) pairs, in its order, each key
  ;; refused by name, as WHO, before anything else: one KEYS lacks,
  ;; unknown-key; one with no value after it, missing-value; one given
  ;; twice, repeated-key. Each is &http-request-error, field key, whose
  ;; value is the key as given. PLIST is a rest argument's, fresh.
  (define (key-settings who keys plist)
    (let loop ((rest plist) (found '()))
      (if (null? rest)
          (reverse found)
          (let ((key (car rest)))
            (unless (memq key keys)
              (refuse who 'key key 'unknown-key "not a key this takes"))
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
  ;; list of string pairs, and the user agent and the CA file, when strings.
  ;; Anything else is kept as given, for the low level to refuse.
  (define (copied-setting setting)
    (let ((key (car setting)) (value (cdr setting)))
      (cons key
            (case key
              ((headers) (or (string-pairs value) value))
              ((user-agent ca-file) (if (string? value) (string-copy value) value))
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
                             pairs))
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
      (refuse who 'redirects value 'not-a-redirect-count
              "redirects is an exact natural, the most redirects a call follows, or #f, none"))
    value)

  ;; checked-allow-downgrade : Symbol Any -> Boolean
  ;; VALUE, an allow-downgrade value, #t or #f; anything else is refused as
  ;; WHO, not-a-boolean.
  (define (checked-allow-downgrade who value)
    (unless (boolean? value)
      (refuse who 'allow-downgrade value 'not-a-boolean "allow-downgrade is #t or #f"))
    value)

  ;; policy-of : Symbol (Listof (Pairof Symbol Any)) (U Natural #f) Boolean
  ;;             -> (List (U Natural #f) Boolean)
  ;; SETTINGS' redirects and allow-downgrade, each checked, as WHO, in that
  ;; order; each one SETTINGS lack is REDIRECTS or ALLOW-DOWNGRADE.
  (define (policy-of who settings redirects allow-downgrade)
    (let* ((r (assq 'redirects settings))
           (a (assq 'allow-downgrade settings))
           (redirects (if r (checked-redirects who (cdr r)) redirects))
           (allow-downgrade (if a (checked-allow-downgrade who (cdr a)) allow-downgrade)))
      (list redirects allow-downgrade)))

  ;; session-policy : (Listof (Pairof Symbol Any)) -> (List (U Natural #f) Boolean)
  ;; A session's redirects and allow-downgrade, from its SETTINGS, each
  ;; checked, or the default: 20, and #f.
  (define (session-policy settings)
    (policy-of 'make-http-session settings default-redirects #f))

  ;; --- the session -----------------------------------------------------------------

  ;; A session: its engine; DEFAULTS, a request of the session's request
  ;; keys, checked by make-curl-request, whose URL nothing reads; and its
  ;; redirect policy, checked.
  ;; new-http-session : Engine Request (U Natural #f) Boolean -> Session
  ;; http-session? : Any -> Boolean
  ;; http-session-engine : Session -> Engine
  ;; http-session-defaults : Session -> Request
  ;; http-session-redirects : Session -> (U Natural #f)
  ;; http-session-allow-downgrade : Session -> Boolean
  (define-record-type (http-session new-http-session http-session?)
    (fields (immutable engine http-session-engine)
            (immutable defaults http-session-defaults)
            (immutable redirects http-session-redirects)
            (immutable allow-downgrade http-session-allow-downgrade))
    (sealed #t)
    (opaque #t))

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

  ;; call-body : Any -> Bytevector
  ;; A copy of a call's body: a bytevector's bytes, or a string's UTF-8
  ;; bytes; anything else is not-a-body.
  (define (call-body value)
    (cond ((bytevector? value) (bytevector-copy value))
          ((string? value) (string->utf8 value))
          (else (refuse 'http-request 'body value 'not-a-body
                        "a body is a bytevector, or a string, sent as UTF-8"))))

  ;; call-pairs : Symbol Any -> (Listof (Pairof String String))
  ;; A copy of a call's form or params, FIELD; anything but a list of
  ;; string pairs is not-name-value-pairs.
  (define (call-pairs field value)
    (or (string-pairs value)
        (refuse 'http-request field value 'not-name-value-pairs
                "a list of pairs of a name and a value, both strings")))

  ;; call-request : Session Any Any List
  ;;                -> (Values Request (U Natural #f) Boolean)
  ;; The first request of a call of METHOD on URL, with PLIST's keys merged
  ;; with SESSION's, then the call's redirects and allow-downgrade: each the
  ;; call's, or else the session's. In order, each raising as it is
  ;; refused:
  ;;   1. the keys, by key-settings' rules;
  ;;   2. body, not-a-body; form, then params, not-name-value-pairs;
  ;;      redirects, not-a-redirect-count; allow-downgrade, not-a-boolean;
  ;;   3. body and form together, body-and-form; either with get or head,
  ;;      body-not-allowed, field the one given;
  ;;   4. the method and the call's own request keys, by make-curl-request,
  ;;      with the body: the low level's refusal;
  ;;   5. the URL: params, when non-empty, appended by curl-url-append-query,
  ;;      then the whole read back by curl-url-part, the URL requested.
  ;; The merge (merge-fields) gives the headers and the user agent; a form
  ;; is sent as its encoding's bytes, with-form-type's header added. Every
  ;; other request key is the call's, or else the session's.
  (define (call-request session method url plist)
    (let* ((settings (key-settings 'http-request call-keys plist))
           (body-given (assq 'body settings))
           (form-given (assq 'form settings))
           (params-given (assq 'params settings))
           (body (and body-given (call-body (cdr body-given))))
           (form (and form-given (call-pairs 'form (cdr form-given))))
           (params (and params-given (call-pairs 'params (cdr params-given))))
           (policy (policy-of 'http-request settings (http-session-redirects session)
                              (http-session-allow-downgrade session))))
      (when (and body-given form-given)
        (refuse 'http-request 'form #f 'body-and-form "a body and a form together"))
      (when (and (memq method '(get head)) (or body-given form-given))
        (refuse 'http-request (if body-given 'body 'form) method 'body-not-allowed
                "a body or a form with get or head, which send none"))
      (let* ((own (map copied-setting (request-settings settings)))
             (bytes (or body (and form (string->utf8 (form-encode form)))))
             (checked (apply make-curl-request check-url 'method method
                             (append (settings->plist own)
                                     (if bytes (list 'body bytes) '()))))
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
                                   'body bytes
                                   'user-agent (cadr merged)
                                   'timeout-ms (pick 'timeout-ms curl-request-timeout-ms)
                                   'connect-timeout-ms (pick 'connect-timeout-ms
                                                             curl-request-connect-timeout-ms)
                                   'body-limit (pick 'body-limit curl-request-body-limit)
                                   'ca-file (pick 'ca-file curl-request-ca-file)
                                   'verify (pick 'verify curl-request-verify)
                                   'proxy (pick 'proxy curl-request-proxy))
                (car policy)
                (cadr policy))))))
