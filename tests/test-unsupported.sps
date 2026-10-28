#!r6rs
;;; The suite for (curl unsupported), the hatch (ADR-0009; the M4 plan,
;;; sections 3.7 and 7.2): options chez-curl does not wrap, attached to a
;;; request by name, checked as they are attached, and set by the engine
;;; last.
;;;
;;;   - the surface: (curl unsupported) exports curl-request-with-options
;;;     alone, and (curl) does not export it;
;;;   - each refusal rule watched firing, with nothing native made: a
;;;     request or options of the wrong shape; a name holding U+0000; an
;;;     unknown name; every owned option and twin, written out here, rather
;;;     than read from owned-option-names, a table only the library's copy
;;;     holds; an alias of an owned option, and a name in another case; an
;;;     object, a callback pointer and a function; a repeated option, by
;;;     name, by case and by alias, in one call and across two; the name's
;;;     checks before the value's; each value's shape and range, at its
;;;     edges; CR, LF and U+0000 at every position of a string and of each
;;;     string of a list, the first offending char deciding;
;;;   - the copies: the caller's name, string, list and bytevector changed
;;;     after the attach leave the request's settings as they were, and the
;;;     engine sends the copy; another thread flipping a string, and a
;;;     string of a list, between a char and CR while transfers run, each
;;;     refused at the attach or sent whole;
;;;   - each type reaching libcurl: a string's UTF-8 bytes, as the raw face
;;;     read them; a string list, HTTP200ALIASES, which makes libcurl take a
;;;     status line it refuses otherwise; a blob, by what each TLS backend
;;;     makes of it, a row per libcurl, and native's struct curl_blob read
;;;     back, on every lane; curl-request-with keeping the options;
;;;   - the counts: the engine's alone after each transfer, all zero once
;;;     the engine stops.
;;;
;;; Every expected value is one the code under test cannot produce by
;;; failing: SRFI-64 makes #f of a raise in the actual expression, so none
;;; is #f.
(import (rnrs)
        (srfi :64)
        (rnrs mutable-strings)
        (rnrs mutable-pairs)
        (only (chezscheme) fork-thread sleep make-time current-time time-second time-nanosecond
              library-exports foreign-sizeof foreign-ref ftype-ref make-ftype-pointer make-list
              parameterize environment eval)
        (curl-testing)
        (curl)
        (curl unsupported)
        (only (curl private transfer) hatch-settings-of)
        (only (curl private native) curl-easy-option call-with-curl-blob loaded-tls-backend)
        (only (curl private constants) curlot-types)
        (only (curl private layouts) curl-blob)
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
      (flush-output-port (current-output-port)))))

(test-begin "unsupported")

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

;; backend : String
;; The TLS backend in use, as native read it after curl_global_init, its
;; name before any /: OpenSSL, GnuTLS, SecureTransport.
(define backend
  (guard (e (#t "no-backend"))
    (let* ((text (loaded-tls-backend))
           (slash (let loop ((i 0))
                    (cond ((= i (string-length text)) i)
                          ((char=? (string-ref text i) #\/) i)
                          (else (loop (+ i 1)))))))
      (substring text 0 slash))))

;; The suite's one engine. Every transfer below runs on it.
(define engine
  (guard (e (#t (list 'raised (describe e))))
    (make-curl-engine)))

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

;; iota-from : Integer Natural -> (Listof Integer)
;; COUNT integers, from START up.
(define (iota-from start count)
  (let loop ((i (- count 1)) (found '()))
    (if (< i 0) found (loop (- i 1) (cons (+ start i) found)))))

;; latin-1 : Bytevector -> String
(define (latin-1 bytes)
  (list->string (map integer->char (bytevector->u8-list bytes))))

;; answer-of : (-> Response) -> Answer
;; What THUNK's transfer answers: (response STATUS VERSION BODY), the body
;; read as Latin-1; (refused REASON CODE OPTION) for a
;; &curl-transfer-error; (request-refused FIELD VALUE REASON) for a
;; &curl-request-error; (raised TEXT) for anything else.
(define (answer-of thunk)
  (guard (e ((curl-transfer-error? e)
             (list 'refused (curl-transfer-error-reason e) (curl-transfer-error-code e)
                   (curl-transfer-error-option e)))
            ((curl-request-error? e)
             (list 'request-refused (curl-request-error-field e) (curl-request-error-value e)
                   (curl-request-error-reason e)))
            (#t (list 'raised (describe e))))
    (let ((r (thunk)))
      (list 'response (curl-response-status r) (curl-response-http-version r)
            (latin-1 (curl-response-body r))))))

;; refusal : (-> Any) -> (List Any Counts Counts)
;; What THUNK raised, the native counts at the raise, and the counts after:
;; (request-refused FIELD VALUE REASON) for a &curl-request-error;
;; (assertion-violation WHO) for an assertion violation; (raised TEXT) for
;; anything else; no-raise, with the counts at the raise no-raise too, when
;; it returned.
(define (refusal thunk)
  (let* ((seen 'no-raise)
         (r (guard (e ((curl-request-error? e)
                       (list 'request-refused (curl-request-error-field e)
                             (curl-request-error-value e) (curl-request-error-reason e)))
                      ((and (assertion-violation? e) (who-condition? e))
                       (list 'assertion-violation (condition-who e)))
                      (#t (list 'raised (describe e))))
              (with-exception-handler
                (lambda (c) (set! seen (native-counts)) (raise c))
                (lambda () (thunk) 'no-raise)))))
    (list r seen (native-counts))))

;; base : Request
;; A request nothing listens for, carrying no option.
(define base (make-curl-request "http://127.0.0.1:1/" 'timeout-ms 20000))

;; attach : (Listof (Pairof String Any)) -> (List Any Counts Counts)
;; refusal's answer for OPTIONS attached to base.
(define (attach options)
  (refusal (lambda () (curl-request-with-options base options))))

;; refused-as : String Symbol -> (List Any Counts Counts)
;; What attach answers for an option NAME refused for REASON, before
;; anything native: the counts at the raise and after are the engine's.
(define (refused-as name reason)
  (list (list 'request-refused 'options name reason) running-counts running-counts))

;; assertion : (List Any Counts Counts)
;; What attach answers for options of a wrong shape or a value out of
;; range.
(define assertion
  (list '(assertion-violation curl-request-with-options) running-counts running-counts))

;; taken : (List Any Counts Counts)
(define taken (list 'no-raise 'no-raise running-counts))

;; type-of : String -> (U Symbol (List 'unknown String))
;; NAME's CURLOT type, by its name in curlot-types, as the loaded libcurl's
;; own table gives it.
(define (type-of name)
  (let ((o (curl-easy-option name)))
    (if o
        (car (find (lambda (entry) (= (cdr entry) (cdr o))) curlot-types))
        (list 'unknown name))))

;; long-bits : Natural
(define long-bits (* 8 (foreign-sizeof 'long)))

;; --- the surface ----------------------------------------------------------------------

;; (curl private transfer) exports the procedure too, beside the request's
;; constructor it needs, and any (curl ...) library may import that library:
;; check-seam's rule (j) closes only the route through (curl unsupported).
;; So (curl)'s exports are held here by what each is bound to, which a
;; rename cannot hide.

;; bound-to-hatch : (Listof Symbol) (Symbol -> Any) -> (Listof Symbol)
;; Each of NAMES whose value, by VALUE-OF, is curl-request-with-options. A
;; name whose value raises, as syntax does when evaluated, is none.
(define (bound-to-hatch names value-of)
  (filter (lambda (name) (guard (e (#t #f)) (eq? (value-of name) curl-request-with-options)))
          names))

(test-equal "(curl unsupported) exports curl-request-with-options alone; (curl) exports no binding of it, by that name or another, of its 100 or more exports"
  '((curl-request-with-options) () #t)
  (list (guard (e (#t (list 'raised (describe e)))) (library-exports '(curl unsupported)))
        (guard (e (#t (list 'raised (describe e))))
          (let ((env (environment '(curl))))
            (bound-to-hatch (library-exports '(curl)) (lambda (name) (eval name env)))))
        (guard (e (#t (list 'raised (describe e))))
          (>= (length (library-exports '(curl))) 100))))

(test-equal "bound-to-hatch, the reader: a name bound to the hatch under another name is found; one bound to another procedure, and one that raises, as syntax does, are not"
  '(renamed)
  (bound-to-hatch '(renamed make-curl-request syntax)
                  (lambda (name)
                    (case name
                      ((renamed) curl-request-with-options)
                      ((make-curl-request) make-curl-request)
                      (else (raise 'syntax))))))

;; --- the shapes ---------------------------------------------------------------------------

(test-equal "what is not a request, and options that are not a list of (NAME . VALUE) with a string NAME, are assertion violations, before anything native: a symbol, an improper list, an element that is no pair, a NAME that is a symbol, a cyclic list"
  (append (list (list '(assertion-violation curl-request-with-options) running-counts running-counts))
          (make-list 5 assertion))
  (cons (refusal (lambda () (curl-request-with-options 'not-a-request '())))
        (map attach
             (list 'not-a-list
                   '(("LOW_SPEED_TIME" . 1) . tail)
                   '(x)
                   '((low-speed-time . 1))
                   (let ((cycle (list (cons "LOW_SPEED_TIME" 1) (cons "IPRESOLVE" 1))))
                     (set-cdr! (cdr cycle) cycle)
                     cycle)))))

;; --- the names --------------------------------------------------------------------------------

(test-equal "a name holding U+0000 is refused as embedded-nul, before it is looked up: URL<NUL>x, which curl_easy_option_by_name would read as URL, an owned option, and a NUL alone"
  (list (refused-as "URL\x0;x" 'embedded-nul) (refused-as "\x0;" 'embedded-nul))
  (list (attach '(("URL\x0;x" . 1))) (attach '(("\x0;" . 1)))))

(test-equal "a name the loaded libcurl does not know is refused as unknown-option: NO_SUCH_OPTION, and the empty name"
  (list (refused-as "NO_SUCH_OPTION" 'unknown-option) (refused-as "" 'unknown-option))
  (list (attach '(("NO_SUCH_OPTION" . 1))) (attach '(("" . 1)))))

;; owned-names : (Listof String)
;; Every option chez-curl owns, and every owned setting's twin, written out
;; here (ADR-0009, amended): the options the transfer always sets and the
;; pins' bitmasks; each request field's; the twins; the options slice 4's
;; review found, twins and the hazards kept from the hatch (amended
;; 2026-10-27); every proxy TLS option.
(define owned-names
  '("URL" "PROTOCOLS_STR" "REDIR_PROTOCOLS_STR" "PROTOCOLS" "REDIR_PROTOCOLS" "NOSIGNAL" "QUICK_EXIT"
    "WRITEFUNCTION" "WRITEDATA" "ERRORBUFFER"
    "CURLU" "NOBODY" "CUSTOMREQUEST" "HTTPHEADER" "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "USERAGENT"
    "TIMEOUT_MS" "CONNECTTIMEOUT_MS" "MAXFILESIZE_LARGE" "CAINFO" "CAPATH"
    "SSL_VERIFYPEER" "SSL_VERIFYHOST" "PROXY" "FOLLOWLOCATION"
    "TIMEOUT" "CONNECTTIMEOUT" "MAXFILESIZE" "HTTPGET" "POST" "PUT" "UPLOAD"
    "POSTFIELDS" "POSTFIELDSIZE" "HTTPPOST" "MIMEPOST" "INFILESIZE" "INFILESIZE_LARGE"
    "PORT" "REQUEST_TARGET" "CRLF" "HEADER" "CAINFO_BLOB" "SSL_OPTIONS"
    "NOPROXY" "PRE_PROXY" "PROXYPORT" "PROXYTYPE"
    "TRANSFERTEXT" "USERPWD" "USERNAME" "PASSWORD" "NETRC" "HSTS"
    "UNIX_SOCKET_PATH" "ABSTRACT_UNIX_SOCKET" "PROXYHEADER" "HEADEROPT"
    "RESUME_FROM" "RESUME_FROM_LARGE" "COOKIEFILE" "COOKIEJAR" "CONNECT_ONLY"
    "DOH_URL" "RESOLVE" "SSLENGINE_DEFAULT"
    "PROXY_SSL_VERIFYPEER" "PROXY_SSL_VERIFYHOST" "PROXY_SSL_OPTIONS" "PROXY_SSL_CIPHER_LIST"
    "PROXY_CAINFO" "PROXY_CAINFO_BLOB" "PROXY_CAPATH" "PROXY_CRLFILE" "PROXY_ISSUERCERT"
    "PROXY_ISSUERCERT_BLOB" "PROXY_PINNEDPUBLICKEY" "PROXY_SSLVERSION" "PROXY_TLS13_CIPHERS"
    "PROXY_SSLCERT" "PROXY_SSLCERT_BLOB" "PROXY_SSLCERTTYPE" "PROXY_SSLKEY" "PROXY_SSLKEY_BLOB"
    "PROXY_SSLKEYTYPE" "PROXY_KEYPASSWD" "PROXY_TLSAUTH_TYPE" "PROXY_TLSAUTH_USERNAME"
    "PROXY_TLSAUTH_PASSWORD"))

;; value-for : String -> Any
;; A value NAME's type takes, so that only the name can be refused.
(define (value-for name)
  (case (type-of name)
    ((string) "x")
    ((slist) '("x"))
    ((blob) #vu8(120))
    (else 1)))

(test-equal "each owned option and twin, written out here, is refused as owned-option where the loaded libcurl knows it, by id, and as unknown-option where it does not, before anything native, each with a value its type takes"
  (map (lambda (name)
         (refused-as name (if (curl-easy-option name) 'owned-option 'unknown-option)))
       owned-names)
  (map (lambda (name) (attach (list (cons name (value-for name))))) owned-names))

(test-equal "an alias of an owned option is refused as owned-option, by id: FILE is WRITEDATA's id and RTSPHEADER HTTPHEADER's; and a name in another case, url, Url and cainfo, as curl_easy_option_by_name reads it"
  (list '(same same)
        (refused-as "FILE" 'owned-option) (refused-as "RTSPHEADER" 'owned-option)
        (refused-as "url" 'owned-option) (refused-as "Url" 'owned-option)
        (refused-as "cainfo" 'owned-option))
  (cons (map (lambda (pair)
               (let ((a (curl-easy-option (car pair))) (b (curl-easy-option (cdr pair))))
                 (if (and a b (= (car a) (car b))) 'same (list (car pair) a (cdr pair) b))))
             '(("FILE" . "WRITEDATA") ("RTSPHEADER" . "HTTPHEADER")))
        (map attach '((("FILE" . 1)) (("RTSPHEADER" "x")) (("url" . "x")) (("Url" . "x"))
                      (("cainfo" . "x"))))))

(test-equal "an option of a type the hatch does not take is refused as unsupported-type: an object, STDERR; a callback pointer, HEADERDATA; a function, XFERINFOFUNCTION"
  (list '(object cbptr function)
        (refused-as "STDERR" 'unsupported-type) (refused-as "HEADERDATA" 'unsupported-type)
        (refused-as "XFERINFOFUNCTION" 'unsupported-type))
  (cons (map type-of '("STDERR" "HEADERDATA" "XFERINFOFUNCTION"))
        (map attach '((("STDERR" . 1)) (("HEADERDATA" . 1)) (("XFERINFOFUNCTION" . 1))))))

(test-equal "an option of each type the hatch takes is attached, its setting a copy of the value given: a long, LOW_SPEED_TIME; enumerated values, IPRESOLVE; an off_t, MAX_RECV_SPEED_LARGE; a string, COOKIE; a string list, HTTP200ALIASES; a blob, SSLCERT_BLOB"
  (list '(long values off-t string slist blob)
        '(("LOW_SPEED_TIME" long 30) ("IPRESOLVE" values 1) ("MAX_RECV_SPEED_LARGE" off-t 1000000)
          ("COOKIE" string "a=b") ("HTTP200ALIASES" slist ("ICY 200 OK" "x"))
          ("SSLCERT_BLOB" blob #vu8(0 1 255)))
        running-counts)
  (list (map type-of '("LOW_SPEED_TIME" "IPRESOLVE" "MAX_RECV_SPEED_LARGE" "COOKIE" "HTTP200ALIASES"
                       "SSLCERT_BLOB"))
        (guard (e (#t (list 'raised (describe e))))
          (hatch-settings-of
           (curl-request-with-options base '(("LOW_SPEED_TIME" . 30) ("IPRESOLVE" . 1)
                                             ("MAX_RECV_SPEED_LARGE" . 1000000) ("COOKIE" . "a=b")
                                             ("HTTP200ALIASES" "ICY 200 OK" "x")
                                             ("SSLCERT_BLOB" . #vu8(0 1 255))))))
        (native-counts)))

(test-equal "an option the request carries already is refused as repeated-option: twice in one call; in another case; by an alias, ENCODING after ACCEPT_ENCODING; across two attaches; and after curl-request-with, which keeps the options"
  (list (refused-as "LOW_SPEED_TIME" 'repeated-option) (refused-as "low_speed_time" 'repeated-option)
        (refused-as "ENCODING" 'repeated-option)
        (list '(request-refused options "LOW_SPEED_TIME" repeated-option) running-counts running-counts)
        (list '(request-refused options "LOW_SPEED_TIME" repeated-option) running-counts running-counts))
  (let ((once (curl-request-with-options base '(("LOW_SPEED_TIME" . 1)))))
    (list (attach '(("LOW_SPEED_TIME" . 1) ("LOW_SPEED_TIME" . 2)))
          (attach '(("LOW_SPEED_TIME" . 1) ("low_speed_time" . 2)))
          (attach '(("ACCEPT_ENCODING" . "") ("ENCODING" . "")))
          (refusal (lambda () (curl-request-with-options once '(("LOW_SPEED_TIME" . 2)))))
          (refusal (lambda ()
                     (curl-request-with-options (curl-request-with once 'timeout-ms 5)
                                                '(("LOW_SPEED_TIME" . 2))))))))

(test-equal "a name is checked before its value: an owned name, an unknown one, one of an object, and a repeated one, each with a value no type takes, are refused for the name"
  (list (refused-as "URL" 'owned-option) (refused-as "NO_SUCH_OPTION" 'unknown-option)
        (refused-as "STDERR" 'unsupported-type) (refused-as "LOW_SPEED_TIME" 'repeated-option))
  (map attach '((("URL" . no-value)) (("NO_SUCH_OPTION" . no-value)) (("STDERR" . no-value))
                (("LOW_SPEED_TIME" . 1) ("LOW_SPEED_TIME" . no-value)))))

(test-equal "a refusal leaves the request as it was: an attach of a good option, then a bad one, raises, and the request it was handed still carries nothing"
  (list (refused-as "NO_SUCH_OPTION" 'unknown-option) '())
  (list (attach '(("LOW_SPEED_TIME" . 1) ("NO_SUCH_OPTION" . 1)))
        (hatch-settings-of base)))

;; --- the values ---------------------------------------------------------------------------

(test-equal "a long, and an enumerated value, is an exact integer a C long holds: its two ends taken; one past either, a string, an inexact integer and a fraction, assertion violations"
  (list taken taken taken assertion assertion assertion assertion assertion)
  (map (lambda (value) (attach (list (cons "LOW_SPEED_TIME" value))))
       (list (- (expt 2 (- long-bits 1)) 1) (- (expt 2 (- long-bits 1))) 0
             (expt 2 (- long-bits 1)) (- -1 (expt 2 (- long-bits 1))) "30" 30.0 1/2)))

(test-equal "an off_t is an exact integer of 64 bits: its two ends taken; one past either, and a string, assertion violations"
  (list taken taken assertion assertion assertion)
  (map (lambda (value) (attach (list (cons "MAX_RECV_SPEED_LARGE" value))))
       (list (- (expt 2 63) 1) (- (expt 2 63)) (expt 2 63) (- -1 (expt 2 63)) "1")))

(test-equal "a string option takes a string, a string list a list of strings, and a blob a bytevector: each other shape an assertion violation, the empty list and the empty bytevector taken"
  (list assertion assertion assertion
        assertion assertion assertion assertion taken
        assertion assertion taken)
  (append (map (lambda (value) (attach (list (cons "COOKIE" value)))) (list 1 #vu8(1) '("a")))
          (map (lambda (value) (attach (list (cons "HTTP200ALIASES" value))))
               (list "a" '("a" . "b") '("a" 1) '("a" #\b) '()))
          (map (lambda (value) (attach (list (cons "SSLCERT_BLOB" value)))) (list "x" '(1) #vu8()))))

;; with-char : String Natural Char -> String
;; A copy of S with the char at I replaced by C.
(define (with-char s i c)
  (let ((copy (string-copy s))) (string-set! copy i c) copy))

(test-equal "U+0000, CR and LF at every position of a string are refused, embedded-nul, line-break and line-break, naming the option; the first offending char decides"
  (append (apply append (map (lambda (i) (list (refused-as "COOKIE" 'embedded-nul)
                                                (refused-as "COOKIE" 'line-break)
                                                (refused-as "COOKIE" 'line-break)))
                             '(0 1 2)))
          (list (refused-as "COOKIE" 'embedded-nul) (refused-as "COOKIE" 'line-break)
                (refused-as "COOKIE" 'line-break)))
  (append (apply append (map (lambda (i)
                               (map (lambda (c) (attach (list (cons "COOKIE" (with-char "abc" i c)))))
                                    (list #\nul #\return #\newline)))
                             '(0 1 2)))
          (map (lambda (s) (attach (list (cons "COOKIE" s)))) '("\x0;\r" "\r\x0;" "\n\x0;"))))

(test-equal "every char from U+0001 to U+00FF but CR and LF, and U+0100, U+20AC and U+1F600, is taken in a string, and in a string of a list"
  (list taken taken)
  (let ((every (list->string
                (append (filter (lambda (c) (not (memv c '(#\return #\newline))))
                                (map integer->char (iota-from 1 255)))
                        (list (integer->char #x100) (integer->char #x20AC) (integer->char #x1F600))))))
    (list (attach (list (cons "COOKIE" every))) (attach (list (list "HTTP200ALIASES" "a" every))))))

(test-equal "U+0000, CR and LF in each string of a list, at each of its three places, are refused, naming the option"
  (apply append (map (lambda (i) (list (refused-as "HTTP200ALIASES" 'embedded-nul)
                                       (refused-as "HTTP200ALIASES" 'line-break)
                                       (refused-as "HTTP200ALIASES" 'line-break)))
                     '(0 1 2)))
  (apply append (map (lambda (i)
                       (map (lambda (c)
                              (attach (list (cons "HTTP200ALIASES"
                                                  (map (lambda (j) (if (= i j) (string #\a c) "a"))
                                                       '(0 1 2))))))
                            (list #\nul #\return #\newline)))
                     '(0 1 2))))

;; --- the copies -----------------------------------------------------------------------------

(test-equal "the request keeps copies: the caller's name, string, list, the list's strings and bytevector, each changed after the attach, leave its settings as they were; and the copies hatch-settings-of answers are fresh: a change to one leaves the next as it was"
  (let ((settings '(("COOKIE" string "k=v") ("HTTP200ALIASES" slist ("ICY 200 OK"))
                    ("SSLCERT_BLOB" blob #vu8(1 2 3)))))
    (list (written settings) settings))
  (guard (e (#t (list 'raised (describe e))))
    (let* ((name (string-copy "COOKIE"))
           (value (string-copy "k=v"))
           (element (string-copy "ICY 200 OK"))
           (aliases (list element))
           (blob (bytevector-copy #vu8(1 2 3)))
           (r (curl-request-with-options base (list (cons name value) (cons "HTTP200ALIASES" aliases)
                                                    (cons "SSLCERT_BLOB" blob)))))
      (string-set! name 0 #\X)
      (string-set! value 0 #\X)
      (string-set! element 0 #\X)
      (set-cdr! aliases (list "more"))
      (bytevector-u8-set! blob 0 9)
      (let* ((first (hatch-settings-of r))
             (as-read (written first)))
        (string-set! (car (car first)) 0 #\Y)
        (list as-read (hatch-settings-of r))))))

(test-equal "hatch-settings-of's answer is the caller's to change, so the check above can see a change to it: Y in COOKIE's first place shows"
  "YOOKIE"
  (guard (e (#t (list 'raised (describe e))))
    (let ((first (hatch-settings-of (curl-request-with-options base '(("COOKIE" . "k=v"))))))
      (string-set! (car (car first)) 0 #\Y)
      (car (car first)))))

;; --- struct curl_blob, as native fills it ----------------------------------------------

;; blob-read-back : Bytevector -> Any
;; What call-with-curl-blob hands its procedure, read back through the
;; layout: the data's bytes, len and flags, and the blocks counted during;
;; then the blocks counted after.
(define (blob-read-back bytes)
  (guard (e (#t (list 'raised (describe e))))
    (let ((during
           (call-with-curl-blob bytes
             (lambda (address)
               (let* ((blob (make-ftype-pointer curl-blob address))
                      (data (ftype-ref curl-blob (data) blob))
                      (len (ftype-ref curl-blob (len) blob)))
                 (list (map (lambda (i) (foreign-ref 'unsigned-8 data i)) (iota-from 0 len))
                       len (ftype-ref curl-blob (flags) blob)
                       (not (zero? data))
                       (cdr (assq 'block (native-counts)))))))))
      (list during (cdr (assq 'block (native-counts)))))))

(test-equal "call-with-curl-blob hands its procedure a struct curl_blob, two counted blocks: its data the bytes, every value of a byte, its len their count, its flags CURL_BLOB_COPY, 1; an empty bytevector's data no NULL; both blocks freed after, and after a raise"
  (list (list (list '(0 1 127 128 255 0) 6 1 #t 3) 1)
        (list (list '() 0 1 #t 3) 1)
        (list 'raised-and-freed 1))
  (list (blob-read-back #vu8(0 1 127 128 255 0))
        (blob-read-back #vu8())
        (guard (e (#t (list (if (eq? e 'planted) 'raised-and-freed (list 'raised (describe e)))
                            (cdr (assq 'block (native-counts))))))
          (call-with-curl-blob #vu8(1 2) (lambda (address) (raise 'planted))))))

;; --- against the origin -----------------------------------------------------------------

(define pki-made
  (guard (e (#t (list 'raised (describe e))))
    (list 'made (make-test-pki))))
(define pki (and (eq? (car pki-made) 'made) (cadr pki-made)))

(test-equal "make-test-pki makes this run's PKI"
  'made
  (car pki-made))

(define ca-file (string-append (or pki "/no-pki") "/ca.pem"))
(define other-ca-file (string-append (or pki "/no-pki") "/other-ca.pem"))

;; file-bytes : String -> (U Bytevector #f)
(define (file-bytes path)
  (guard (e (#t #f))
    (call-with-port (open-file-input-port path) get-bytevector-all)))

;; Each scenario's outcome, recorded as it ran, and asserted after the
;; origin stops: a test inside call-with-origin would be lost to a raise
;; that ends it.
(define outcomes '())
(define (record! name value) (set! outcomes (cons (cons name value) outcomes)))
(define (outcome name)
  (let ((hit (assq name outcomes))) (if hit (cdr hit) (list 'never-ran name))))

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

;; race : Request (-> Any) (-> Any) Answer Answer -> (List (Listof Answer) (Listof Symbol) Counts)
;; 300 transfers of BASE with ATTACH's options, while another thread runs
;; FLIP: each answer that is neither WHOLE nor REFUSED, both of those seen,
;; and the counts after. ATTACH reads the caller's objects FLIP changes.
(define (race attach-to flip whole refused)
  (let* ((stop #f)
         ;; It flips as fast as it can, then yields once in each state, a
         ;; sleep of no time, as test-transfer's header race does.
         (flipper (fork-thread (lambda ()
                                 (let loop ()
                                   (unless stop
                                     (flip #f)
                                     (pause-ms 0)
                                     (flip #t)
                                     (pause-ms 0)
                                     (loop)))))))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (let loop ((i 0) (odd '()) (seen '()))
          (if (= i 300)
              (list (reverse odd) (filter (lambda (k) (memq k seen)) '(refused whole)) (native-counts))
              (let* ((a (answer-of (lambda () (perform (attach-to)))))
                     (k (cond ((equal? a whole) 'whole)
                              ((equal? a refused) 'refused)
                              (else #f))))
                (loop (+ i 1)
                      (if k odd (cons a odd))
                      (if (and k (not (memq k seen))) (cons k seen) seen))))))
      (lambda () (set! stop #t)))))

;; flipper-of : String Natural Char -> (Boolean -> Unit)
;; A flip of S's char at I: a million times between C and CR, ending on C,
;; or, when ON-CR, ending on CR.
(define (flipper-of s i c)
  (lambda (on-cr)
    (let loop ((n 0))
      (when (< n 1000000)
        (string-set! s i #\return)
        (string-set! s i c)
        (loop (+ n 1))))
    (when on-cr (string-set! s i #\return))))

(define (scenarios o)
  (let ((echo (url-of o 'raw "/raw/echo")))
    ;; A string's bytes: UTF-8, as the raw face read them, after libcurl's
    ;; Accept.
    (record! 'utf-8
      (answer-of (lambda ()
                   (perform (curl-request-with-options
                             (make-curl-request echo 'timeout-ms 20000)
                             (list (cons "COOKIE" (string #\k #\= #\v (integer->char #xE9)))))))))
    ;; The copy is what is sent, and curl-request-with keeps it.
    (record! 'sent-copy
      (let* ((value (string-copy "k=copied"))
             (r (curl-request-with-options (make-curl-request echo 'timeout-ms 20000)
                                           (list (cons "COOKIE" value)))))
        (string-set! value 0 #\X)
        (list (answer-of (lambda () (perform r)))
              (answer-of (lambda () (perform (curl-request-with r 'timeout-ms 20001)))))))
    ;; A string list: HTTP200ALIASES makes libcurl take a status line it
    ;; refuses otherwise; an empty list sets none; a list's second string
    ;; is read too.
    (record! 'aliases
      (let ((bad (make-curl-request (url-of o 'raw "/raw/bad-status-line") 'timeout-ms 20000)))
        (map (lambda (aliases)
               (answer-of (lambda ()
                            (perform (if aliases
                                         (curl-request-with-options bad (list (cons "HTTP200ALIASES" aliases)))
                                         bad)))))
             (list #f '("HTP/1.1 200 OK") '() '("ICY 200 OK" "HTP/1.1 200 OK")))))
    ;; A blob: what each TLS backend makes of an issuer, the run CA and the
    ;; other CA, and of a client certificate that is no certificate.
    (record! 'blobs
      (let ((tls (make-curl-request (tls-url-of o 'https "/status/200") 'ca-file ca-file
                                    'timeout-ms 20000)))
        (map (lambda (option)
               (let ((a (answer-of (lambda () (perform (curl-request-with-options tls (list option)))))))
                 (if (eq? (car a) 'response) (list 'response (cadr a)) a)))
             (list (cons "ISSUERCERT_BLOB" (or (file-bytes ca-file) #vu8()))
                   (cons "ISSUERCERT_BLOB" (or (file-bytes other-ca-file) #vu8()))
                   (cons "SSLCERT_BLOB" (string->utf8 "no certificate here\n"))))))
    ;; Another thread flips a string, and a list's string, while the
    ;; attaches and transfers run.
    (record! 'string-race
      (let ((value (string-copy "abcdef")))
        (race (lambda () (curl-request-with-options (make-curl-request echo 'timeout-ms 20000)
                                                    (list (cons "COOKIE" value))))
              (flipper-of value 2 #\c)
              (list 'response 200 'http/1.1
                    (string-append "GET /raw/echo HTTP/1.1\r\nHost: " (host-of o 'raw)
                                   "\r\nAccept: */*\r\nCookie: abcdef\r\n\r\n"))
              '(request-refused options "COOKIE" line-break))))
    (record! 'list-race
      (let ((alias (string-copy "HTP/1.1 200 OK")))
        (race (lambda () (curl-request-with-options
                          (make-curl-request (url-of o 'raw "/raw/bad-status-line") 'timeout-ms 20000)
                          (list (list "HTTP200ALIASES" alias))))
              (flipper-of alias 2 #\P)
              '(response 200 http/1.0 "hello\n")
              '(request-refused options "HTTP200ALIASES" line-break))))
    (record! 'hosts (host-of o 'raw))
    (record! 'end-counts (native-counts))))

(define scenarios-outcome
  (guard (e (#t (list 'raised (describe e))))
    (parameterize ((origin-pki pki))
      (call-with-origin (lambda (o) (scenarios o) 'done)))))

(test-equal "the scenarios' origin starts with the PKI, serves them all, and stops"
  'done
  scenarios-outcome)

(define raw-host (let ((h (outcome 'hosts))) (if (string? h) h "no-host")))

;; echoed-cookie : String -> Answer
;; What /raw/echo answers for a GET whose Cookie header is VALUE, its bytes
;; read as Latin-1.
(define (echoed-cookie value)
  (list 'response 200 'http/1.1
        (string-append "GET /raw/echo HTTP/1.1\r\nHost: " raw-host "\r\nAccept: */*\r\nCookie: "
                       value "\r\n\r\n")))

(test-equal "a string is sent as its UTF-8 bytes: COOKIE k=v<U+00E9> reaches the raw face as k=v, C3 and A9, never Latin-1's E9"
  (echoed-cookie (string #\k #\= #\v (integer->char #xC3) (integer->char #xA9)))
  (outcome 'utf-8))

(test-equal "the engine sends the attach's copy: the caller's string changed after the attach is sent as it was; and curl-request-with keeps the option"
  (list (echoed-cookie "k=copied") (echoed-cookie "k=copied"))
  (outcome 'sent-copy))

(test-equal "a string list reaches libcurl: /raw/bad-status-line's HTP/1.1 is refused alone, protocol error 1, and taken as 200, HTTP/1.0, with HTTP200ALIASES naming it; an empty list sets none; a list's second string is read too"
  (list '(refused perform-failed 1 #f) '(response 200 http/1.0 "hello\n") '(refused perform-failed 1 #f)
        '(response 200 http/1.0 "hello\n"))
  (outcome 'aliases))

;; blob-rows : (Listof (Pairof (Pairof String String) (Listof Answer)))
;; What each libcurl, by its version and TLS backend, makes of three blobs
;; (the M4 plan, section 7.1, measured): ISSUERCERT_BLOB at the run CA,
;; then at the other CA, then SSLCERT_BLOB at bytes that are no
;; certificate. OpenSSL reads all three: 83, CURLE_SSL_ISSUER_ERROR, for the
;; wrong issuer, and 58, CURLE_SSL_CERTPROBLEM, for the certificate. GnuTLS
;; takes SSLCERT_BLOB and ignores it; 8.5.0's ignores ISSUERCERT_BLOB too,
;; and 8.20.0's setopt refuses it, CURLE_NOT_BUILT_IN. Apple's 8.7.1 on
;; SecureTransport, which make test selects on macOS, ignores ISSUERCERT_BLOB
;; and refuses the certificate, 58 (the Mac's make test, 2026-10-27,
;; .plans/research/m4/slice4/results/mac-8.7.1-make-test.log).
(define blob-rows
  '((("7.85.0" . "OpenSSL") (response 200) (refused perform-failed 83 #f) (refused perform-failed 58 #f))
    (("8.5.0" . "OpenSSL") (response 200) (refused perform-failed 83 #f) (refused perform-failed 58 #f))
    (("8.5.0" . "GnuTLS") (response 200) (response 200) (response 200))
    (("8.20.0" . "GnuTLS") (refused setopt-failed 4 "ISSUERCERT_BLOB")
     (refused setopt-failed 4 "ISSUERCERT_BLOB") (response 200))
    (("8.23.0" . "OpenSSL") (response 200) (refused perform-failed 83 #f) (refused perform-failed 58 #f))
    (("8.7.1" . "SecureTransport") (response 200) (response 200) (refused perform-failed 58 #f))))

(define blob-row (assoc (cons version backend) blob-rows))

(test-equal (string-append "a blob reaches libcurl, as " (written (cons version backend)) "'s row of blob-rows says")
  (if blob-row (cdr blob-row) (list 'no-row (cons version backend)))
  (outcome 'blobs))

(unless blob-row
  (display "test-unsupported: no row of blob-rows for this libcurl; measured, it would be:\n"
           (current-error-port))
  (write (cons (cons version backend) (outcome 'blobs)) (current-error-port))
  (newline (current-error-port)))

(test-equal "a string another thread flips between c and CR while 300 attaches and transfers run: each attach is refused as line-break, or its transfer sends the value whole, never the CR, both seen; the counts back to the engine's alone"
  (list '() '(refused whole) running-counts)
  (outcome 'string-race))

(test-equal "a list's string another thread flips between P and CR while 300 attaches and transfers run: each attach is refused as line-break, or its transfer takes the status line, both seen; the counts back to the engine's alone"
  (list '() '(refused whole) running-counts)
  (outcome 'list-race))

(test-equal "after the scenarios, the counts are the engine's alone"
  running-counts
  (outcome 'end-counts))

(test-equal "once the engine stops, every count is zero"
  zero-counts
  (begin (guard (e (#t #f)) (curl-engine-stop engine))
         (native-counts)))

(test-end "unsupported")

(exit (suite-exit-status runner))
