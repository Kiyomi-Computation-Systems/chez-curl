#!r6rs
;;; (curl private url): URLs parsed, resolved and checked by libcurl's own
;;; URL API (ADR-0008).
;;;
;;; Every CURLU handle here is made and freed within one call, under
;;; dynamic-wind, on the calling thread: nothing native outlives the call
;;; that made it, and re-entering a finished call through a continuation
;;; raises. The one exception is an engine's transfer, which holds its URL's
;;; handle from its start to its end, on the engine's thread: parse-url
;;; makes it, in its caller's critical section, and free-parsed-url! frees
;;; it. Each dynamic-wind is critical, its critical? argument #t: a handle,
;;; or a string libcurl made, is made in the before thunk and recorded where
;;; the after thunk frees it in one critical section, so an interrupt that
;;; escapes, an engine's expiry say, cannot fall between. Each string
;;; curl_url_get hands back is copied, then freed with curl_free. Each
;;; string handed to libcurl is a counted, NUL-terminated UTF-8 copy, freed
;;; as soon as curl_url_set returns: libcurl "does not have to keep content
;;; around after a successful call" (curl_url_set(3), 7.85.0).
;;;
;;; Every refusal raises &curl-url-error (curl private conditions): with
;;; libcurl's CURLUcode and its name, or with one of chez-curl's own
;;; reasons, scheme-not-http, embedded-nul, not-utf-8 or query-not-kept, and
;;; no code. A string holding U+0000, or a bytevector holding 0x00, is
;;; refused before libcurl sees it: C reads a string to its first NUL, so
;;; "http://a/\x0;b" would reach libcurl as http://a/. A bytevector, a
;;; header's bytes, is encoded into ASCII by encoded-bytes before libcurl
;;; sees it (ADR-0029), so every string libcurl gets here is UTF-8; a
;;; refusal names the bytes read as Latin-1, as a header string holds them.
;;; Every string curl_url_get gives back is read as UTF-8, or refused as
;;; not-utf-8, never decoded with U+FFFD: libcurl decodes a host's %XX, so
;;; http://caf%E9.example/ comes back holding the byte 0xE9, on every
;;; libcurl measured.
;;;
;;; curl's verdicts vary by version (ADR-0008): tests/test-url.sps holds the
;;; shared answers, and tests/known-url-verdicts.sexp a row per libcurl for
;;; the rest; tests/test-url-parts.sps and tests/test-url-location.sps hold
;;; the verdicts of curl-url-part, curl-url-append-query, curl-url-resolve
;;; and curl-url-with-fragment the same way, each with a rows file of its
;;; own.
(library (curl private url)
  (export url-normalize url-resolve call-with-parsed-url require-http-scheme userinfo-parts
          parse-url free-parsed-url! curl-url-part curl-url-append-query appended-url
          curl-url-resolve curl-url-with-fragment fragment-url encoded-bytes proxy-url-reading)
  (import (curl private require-threaded)
          (except (rnrs) dynamic-wind)
          (only (chezscheme) dynamic-wind)
          (curl private conditions)
          (curl private constants)
          (curl private native))

  ;; refuse : String (U Symbol #f) (U Integer #f) (U String #f) [Symbol] -> Nothing
  ;; Raises &curl-url-error for INPUT: its input field holds INPUT, which
  ;; curl-url-error-input gives back, but its message and irritants name
  ;; FIELD, url by default, reference, query or fragment, never the string:
  ;; a URL can hold userinfo, so ftp://u:PW@h/, refused scheme-not-http,
  ;; printed its password (ADR-0008).
  (define (refuse input reason code message . field)
    (raise (condition (make-curl-url-error input reason code message)
                      (make-who-condition 'chez-curl)
                      (make-message-condition
                       (or message "libcurl's URL API refused a URL"))
                      (make-irritants-condition (list (if (pair? field) (car field) 'url))))))

  ;; field-of : String -> Symbol
  ;; The field a checked string is, by WHAT names it: url, reference, query
  ;; or fragment.
  (define (field-of what)
    (cond ((string=? what "a reference") 'reference)
          ((string=? what "a query part") 'query)
          ((string=? what "a fragment") 'fragment)
          (else 'url)))

  ;; refuse-code : String Integer -> Nothing
  ;; libcurl's refusal of INPUT with CODE.
  (define (refuse-code input code)
    (refuse input (curl-url-code-reason code) code (curl-url-strerror code)))

  ;; holds-nul? : String -> Boolean
  (define (holds-nul? s)
    (let loop ((i 0))
      (and (< i (string-length s))
           (or (char=? (string-ref s i) #\nul) (loop (+ i 1))))))

  ;; checked-string : Symbol Any String -> String
  ;; A copy of INPUT, a string without U+0000: an assertion violation from
  ;; WHO for what is no string, and embedded-nul for one that holds it, each
  ;; naming WHAT INPUT is. The copy is what is checked, and what the caller
  ;; hands libcurl: INPUT is the caller's, and another thread could change
  ;; it between a check of it and a use of it.
  (define (checked-string who input what)
    (unless (string? input)
      (assertion-violation who (string-append what " is a string") (shown-value input)))
    (let ((copy (string-copy input)))
      (when (holds-nul? copy)
        (refuse copy 'embedded-nul #f
                (string-append what " holds U+0000, which libcurl would read as its end")
                (field-of what)))
      copy))

  ;; url-input-cap : Positive-Integer
  ;; libcurl's cap on a URL, CURL_MAX_INPUT_LENGTH, in bytes: 8,000,000 on
  ;; every libcurl measured.
  (define url-input-cap 8000000)

  ;; checked-input : Symbol Any -> String
  ;; checked-string for a URL; but a string of more than url-input-cap
  ;; chars, whose UTF-8 bytes are more than libcurl's cap, is refused at
  ;; once as libcurl refuses it, malformed-input with libcurl's own message,
  ;; its input the string as given, before any copy or scan: its cost then
  ;; stays the same whatever its length, where the copy, the NUL scan and
  ;; the encoding grew with it, about 22 ms a million chars, inside a call's
  ;; checks' critical section. A string of url-input-cap chars or fewer goes
  ;; to libcurl, which refuses one whose UTF-8 bytes pass the cap itself.
  (define (checked-input who input)
    (when (and (string? input) (> (string-length input) url-input-cap))
      (refuse-code input (code-of 'malformed-input)))
    (checked-string who input "a URL"))

  ;; strict-utf-8 : Transcoder
  ;; UTF-8 that raises on a malformed sequence, where utf8->string reads one
  ;; as U+FFFD.
  (define strict-utf-8
    (make-transcoder (utf-8-codec) (eol-style none) (error-handling-mode raise)))

  ;; decoded : Bytevector String -> String
  ;; BYTES read as UTF-8, or INPUT refused as not-utf-8. Chez's decoder
  ;; drops a leading byte-order mark, its first alone, so one is put back: a
  ;; query or a fragment can begin with U+FEFF.
  (define (decoded bytes input)
    (let ((text (guard (e ((i/o-decoding-error? e) #f))
                  (bytevector->string bytes strict-utf-8))))
      (unless text
        (refuse input 'not-utf-8 #f
                "libcurl gave back a URL, or a part of one, whose bytes are not UTF-8"))
      (if (and (>= (bytevector-length bytes) 3)
               (= (bytevector-u8-ref bytes 0) #xEF)
               (= (bytevector-u8-ref bytes 1) #xBB)
               (= (bytevector-u8-ref bytes 2) #xBF))
          (string-append "\xFEFF;" text)
          text)))

  ;; set-url! : Positive-Integer String -> Void
  ;; curl_url_set of the whole URL on HANDLE: INPUT parsed, or resolved
  ;; against what HANDLE holds; raises its refusal.
  (define (set-url! handle input)
    (set-url-flagged! handle input 0))

  ;; set-url-flagged! : Positive-Integer String Natural -> Void
  ;; set-url!, with curl_url_set's FLAGS.
  (define (set-url-flagged! handle input flags)
    (let ((code (call-with-c-string input
                  (lambda (address) (curl-url-set handle curlupart-url address flags)))))
      (unless (eqv? code curlue-ok)
        (refuse-code input code))))

  ;; get-part : Positive-Integer Natural Natural (U Natural #f) String
  ;;            -> (U String #f)
  ;; PART of HANDLE, as curl_url_get writes it with FLAGS, copied, then
  ;; freed with curl_free, and read as UTF-8; #f when curl_url_get answers
  ;; ABSENT, the code that says the URL lacks the part. INPUT names the
  ;; refusal, if any. The string is made, and its address recorded for the
  ;; after thunk, in the critical before thunk.
  (define (get-part handle part flags absent input)
    (let ((code #f) (address 0) (freed #f))
      (dynamic-wind #t
        (lambda ()
          (when freed
            (assertion-violation 'get-part "re-entered after its string was freed" 'url))
          (let-values (((c a) (curl-url-get handle part flags)))
            (set! code c)
            (set! address a)))
        (lambda ()
          (cond ((eqv? code curlue-ok) (decoded (c-string->bytevector address) input))
                ((and absent (eqv? code absent)) #f)
                (else (refuse-code input code))))
        (lambda ()
          (set! freed #t)
          (unless (eqv? address 0)
            (curl-free address))))))

  ;; call-with-parsed-url : String (Positive-Integer -> Any) -> Any
  ;; PROC's answer, PROC given a CURLU handle that holds INPUT, parsed by
  ;; curl_url_set with no flags: a copy of INPUT, checked, then parsed. The handle is freed once PROC returns,
  ;; raises or escapes. STRING's refusal raises &curl-url-error before PROC
  ;; runs. Re-entering PROC through a continuation, once the handle is
  ;; freed, raises an assertion violation.
  (define (call-with-parsed-url input proc)
    (call-with-flagged-url 'call-with-parsed-url input 0 proc))

  ;; call-with-flagged-url : Symbol String Natural (Positive-Integer -> Any) -> Any
  ;; call-with-parsed-url's answer, INPUT parsed by curl_url_set with FLAGS,
  ;; as WHO.
  (define (call-with-flagged-url who input flags proc)
    (define string (checked-input who input))
    (unless (procedure? proc)
      (assertion-violation who "not a procedure" proc))
    (let ((handle #f) (freed #f))
      (dynamic-wind #t
        (lambda ()
          (when freed
            (assertion-violation who "re-entered after its handle was freed" 'url))
          (let ((made (curl-url)))
            (when (eqv? made 0)
              (error who "curl_url returned NULL: no memory for a handle"))
            (set! handle made)))
        (lambda ()
          (set-url-flagged! handle string flags)
          (proc handle))
        (lambda ()
          (set! freed #t)
          (curl-url-cleanup handle)))))

  ;; parse-url : String -> Positive-Integer
  ;; A fresh CURLU handle holding INPUT, parsed as call-with-parsed-url
  ;; parses it, for a caller that frees it with free-parsed-url!: a copy of
  ;; INPUT, checked, then parsed. A refusal frees the handle first, then
  ;; raises. The caller makes the call, and records the handle, in one
  ;; critical section, so no escape falls between.
  (define (parse-url input)
    ;; let*: a let's inits run in no fixed order, and the check must come
    ;; before the handle is made.
    (let* ((string (checked-input 'parse-url input))
           (handle (curl-url)))
      (when (eqv? handle 0)
        (error 'parse-url "curl_url returned NULL: no memory for a handle"))
      (guard (e (#t (curl-url-cleanup handle) (raise e)))
        (set-url! handle string))
      handle))

  ;; free-parsed-url! : Positive-Integer -> Void
  ;; Frees HANDLE, which parse-url made, on the thread that made it.
  (define (free-parsed-url! handle)
    (curl-url-cleanup handle))

  ;; url-normalize : String -> String
  ;; What curl_url_get gives back for STRING, parsed: libcurl's own form of
  ;; it, dot segments removed. Its scheme is not checked here:
  ;; require-http-scheme does that.
  (define (url-normalize string)
    (call-with-parsed-url string
      (lambda (handle) (get-part handle curlupart-url 0 #f string))))

  ;; url-resolve : String String -> String
  ;; REFERENCE resolved against BASE, by curl_url_set on BASE's handle
  ;; (ADR-0008), as curl_url_get gives it back. A refusal of either raises,
  ;; naming the string refused.
  (define (url-resolve base input)
    (define reference (checked-input 'url-resolve input))
    (call-with-parsed-url base
      (lambda (handle)
        (set-url! handle reference)
        (get-part handle curlupart-url 0 #f reference))))

  ;; require-http-scheme : Positive-Integer String -> String
  ;; The parsed HANDLE's scheme, as curl_url_get gives it, when it is http
  ;; or https: the one a submit's checks read prior knowledge against
  ;; (ADR-0034). Otherwise raises &curl-url-error, reason scheme-not-http,
  ;; with the URL HANDLE holds as its input (ADR-0008). libcurl writes a
  ;; scheme in lower case. INPUT, the string HANDLE was parsed from, names
  ;; the refusal of a URL libcurl gives back as bytes that are not UTF-8,
  ;; which has no string of its own.
  (define (require-http-scheme handle input)
    (let* ((url (get-part handle curlupart-url 0 #f input))
           (scheme (get-part handle curlupart-scheme 0 #f url)))
      (unless (member scheme '("http" "https"))
        (refuse url 'scheme-not-http #f "chez-curl fetches only http and https URLs"))
      scheme))

  ;; userinfo-parts : Positive-Integer String -> (List (U String #f) (U String #f))
  ;; The parsed HANDLE's user and password parts, as curl_url_get gives
  ;; them, each #f when it answers that the URL lacks the part: what a
  ;; submit reads credentials against (ADR-0036). Whether an empty user or
  ;; password is "" or #f varies by version: 7.85.0 reports none for
  ;; http://:p@h/, and no password for http://u:@h/, where 8.5.0 and later
  ;; report "" (tests/known-url-part-verdicts.sexp). INPUT, the string
  ;; HANDLE was parsed from, names the refusal of a part whose bytes are not
  ;; UTF-8.
  (define (userinfo-parts handle input)
    ;; let*: the user is read first.
    (let* ((user (get-part handle curlupart-user 0 (code-of 'no-user) input))
           (password (get-part handle curlupart-password 0 (code-of 'no-password) input)))
      (list user password)))

  ;; code-of : Symbol -> Natural
  ;; The CURLUcode NAME names in curlue-codes.
  (define (code-of name) (cdr (assq name curlue-codes)))

  ;; ascii-folded-text : String -> String
  ;; S with A to Z as a to z, and nothing else changed: never string-downcase,
  ;; which folds U+212A KELVIN SIGN to k.
  (define (ascii-folded-text s)
    (list->string (map (lambda (c) (if (char<=? #\A c #\Z) (integer->char (+ (char->integer c) 32)) c))
                       (string->list s))))

  ;; proxy-url-reading : String -> (List String (U String #f) (U String #f) String (U String #f) (U String #f) String)
  ;; INPUT, a proxy URL, parsed by curl_url_set with
  ;; CURLU_NON_SUPPORT_SCHEME, so that a scheme libcurl does not know parses
  ;; as any other, alike on every libcurl: with no flags, 7.85.0 to 8.20.0
  ;; refuse socks5:// as an unsupported scheme and 8.23.0 parses it. Answers
  ;; (SCHEME USER PASSWORD PATH QUERY FRAGMENT URL): each part as
  ;; curl_url_get gives it with no flags, the user and the password still
  ;; percent-encoded, #f for one the URL lacks; and URL, the whole URL as
  ;; curl_url_get gives it back once a port the URL lacks is set to its
  ;; scheme's default, 80 for http and 443 for https, A to Z folded, as
  ;; chez-curl hands it to PROXY (ADR-0037): with no port, 7.85.0 to 8.20.0
  ;; try 1080 and 8.23.0 tries 80. Any other scheme's URL is given back as
  ;; it is. Every refusal raises &curl-url-error, whose input is INPUT, and
  ;; a not-utf-8 answer among them: the caller makes its own refusal of it,
  ;; and hands INPUT, which can hold a password, nowhere.
  (define (proxy-url-reading input)
    (call-with-flagged-url 'proxy-url-reading input curlu-non-support-scheme
      (lambda (handle)
        ;; let*: the parts are read in this order, the URL last.
        (let* ((scheme (get-part handle curlupart-scheme 0 #f input))
               (user (get-part handle curlupart-user 0 (code-of 'no-user) input))
               (password (get-part handle curlupart-password 0 (code-of 'no-password) input))
               (path (get-part handle curlupart-path 0 #f input))
               (query (get-part handle curlupart-query 0 (code-of 'no-query) input))
               (fragment (get-part handle curlupart-fragment 0 (code-of 'no-fragment) input))
               (port (get-part handle curlupart-port 0 (code-of 'no-port) input))
               (default (cdr (or (assoc (ascii-folded-text scheme) '(("http" . "80") ("https" . "443")))
                                 '(#f . #f)))))
          (when (and (not port) default)
            (let ((code (call-with-c-string default
                          (lambda (address) (curl-url-set handle curlupart-port address 0)))))
              (unless (eqv? code curlue-ok)
                (refuse-code input code))))
          (list scheme user password path query fragment
                (get-part handle curlupart-url 0 #f input))))))

  ;; url-parts : (Listof (List Symbol Natural Natural (U Natural #f)))
  ;; Each part curl-url-part reads: its name, its CURLUPart, the flags
  ;; curl_url_get takes for it, and the code that says a URL lacks it. A
  ;; parsed URL always has the first two. The port is the scheme's default
  ;; when the URL names none, CURLU_DEFAULT_PORT.
  (define url-parts
    (list (list 'url curlupart-url 0 #f)
          (list 'scheme curlupart-scheme 0 #f)
          (list 'user curlupart-user 0 (code-of 'no-user))
          (list 'password curlupart-password 0 (code-of 'no-password))
          (list 'host curlupart-host 0 (code-of 'no-host))
          (list 'port curlupart-port curlu-default-port (code-of 'no-port))
          (list 'path curlupart-path 0 #f)
          (list 'query curlupart-query 0 (code-of 'no-query))
          (list 'fragment curlupart-fragment 0 (code-of 'no-fragment))
          (list 'zoneid curlupart-zoneid 0 (code-of 'no-zoneid))))

  ;; curl-url-part : String Symbol -> (U String Natural #f)
  ;; PART of URL, parsed by curl_url_set with no flags, as curl_url_get
  ;; gives it back with no flags: url, the whole URL; scheme, user,
  ;; password, host, path, query, fragment or zoneid, a string, or #f for
  ;; one the URL lacks; or port, a natural, the scheme's default when the
  ;; URL names none. An IPv6 host comes without its zone ID, which zoneid
  ;; gives, as written. URL's refusal raises &curl-url-error, and so does an
  ;; answer whose bytes are not UTF-8, as not-utf-8. Whether an empty user,
  ;; password or query is "" or #f varies by version:
  ;; tests/known-url-part-verdicts.sexp.
  (define (curl-url-part url part)
    (define string (checked-input 'curl-url-part url))
    (let ((row (assq part url-parts)))
      (unless row
        (assertion-violation 'curl-url-part "not a part of a URL" (shown-value part)))
      (call-with-parsed-url string
        (lambda (handle)
          (let ((text (get-part handle (cadr row) (caddr row) (cadddr row) string)))
            (if (and text (eq? part 'port))
                (let ((n (string->number text 10)))
                  (unless (and n (exact? n) (integer? n) (>= n 0))
                    (error 'curl-url-part "libcurl gave back a port that is not a natural" text))
                  n)
                text))))))

  ;; string-suffix? : String String -> Boolean
  (define (string-suffix? s tail)
    (let ((n (string-length s)) (k (string-length tail)))
      (and (>= n k) (string=? (substring s (- n k) n) tail))))

  ;; appended-url : String (U String #f) (U String #f) String -> (List String String)
  ;; The string curl-url-append-query has curl_url parse whole, and the
  ;; query it must read back: from WHOLE, a URL as curl_url_get gives it
  ;; back, its QUERY and FRAGMENT as curl_url_get gives them, #f for one it
  ;; lacks, and PART. The fragment, with its #, comes off the end of WHOLE;
  ;; then ? when the query is absent or empty, & unless it ends in one, PART,
  ;; and the fragment again. Pure, so the suite drives it by tables, with
  ;; answers no libcurl measured gives: none writes a ? for an empty query,
  ;; nor answers "" for an empty fragment it leaves out of the URL; Apple's
  ;; 8.7.1 is not measured. A stem ending in ? with no query loses it, so
  ;; the part never reads back as ?part; a "" fragment WHOLE lacks adds no
  ;; #. A non-empty fragment that is not WHOLE's end is an error.
  (define (appended-url whole query fragment part)
    (let* ((old (or query ""))
           (tail (cond ((not fragment) "")
                       ((string-suffix? whole (string-append "#" fragment))
                        (string-append "#" fragment))
                       ((string=? fragment "") "")
                       ;; Its irritants name the fields, never the URL.
                       (else (error 'curl-url-append-query
                                    "libcurl's URL does not end with its fragment"
                                    'url 'fragment))))
           (stem (let ((s (substring whole 0 (- (string-length whole) (string-length tail)))))
                   (if (and (string=? old "") (string-suffix? s "?"))
                       (substring s 0 (- (string-length s) 1))
                       s)))
           (separator (cond ((string=? old "") "?")
                            ((string-suffix? old "&") "")
                            (else "&"))))
      (list (string-append stem separator part tail)
            (if (string=? old "") part (string-append old separator part)))))

  ;; curl-url-append-query : String String -> String
  ;; URL with PART appended to its query (ADR-0028): URL parsed, its url,
  ;; query and fragment read back, the URL written again with ? when the
  ;; query is absent or empty, & unless it ends in one, then PART, then the
  ;; fragment, and that string parsed whole, as url-normalize parses one,
  ;; which keeps PART's hex case on every libcurl, where curl_url_set of a
  ;; query part does not. PART comes encoded: nothing here encodes it. The
  ;; answer's query must read back as the old query, the separator and PART,
  ;; or the call raises &curl-url-error, query-not-kept, naming PART: a #
  ;; in PART would start a fragment. A refusal of the string written names
  ;; that string.
  (define (curl-url-append-query url part)
    (define string (checked-input 'curl-url-append-query url))
    (define addition (checked-string 'curl-url-append-query part "a query part"))
    (let-values (((whole query fragment)
                  (call-with-parsed-url string
                    (lambda (handle)
                      (let* ((whole (get-part handle curlupart-url 0 #f string))
                             (query (get-part handle curlupart-query 0 (code-of 'no-query) string))
                             (fragment (get-part handle curlupart-fragment 0 (code-of 'no-fragment)
                                                 string)))
                        (values whole query fragment))))))
      (let* ((plan (appended-url whole query fragment addition))
             (written (car plan))
             (expected (cadr plan)))
        (call-with-parsed-url written
          (lambda (handle)
            (let* ((answer (get-part handle curlupart-url 0 #f written))
                   (kept (or (get-part handle curlupart-query 0 (code-of 'no-query) written) "")))
              (unless (string=? kept expected)
                (refuse addition 'query-not-kept #f
                        "the query part would not come back as written" 'query))
              answer))))))

  ;; latin-1 : Bytevector -> String
  ;; BYTES read as Latin-1, the byte nn as U+00nn, as a header string holds
  ;; them.
  (define (latin-1 bytes)
    (list->string (map integer->char (bytevector->u8-list bytes))))

  ;; checked-bytes : Symbol Any String -> Bytevector
  ;; A copy of INPUT, a bytevector without 0x00: an assertion violation from
  ;; WHO for what is no bytevector, and embedded-nul for one that holds it,
  ;; naming the bytes read as Latin-1. As checked-string, the copy is what is
  ;; checked and what libcurl gets.
  (define (checked-bytes who input what)
    (unless (bytevector? input)
      (assertion-violation who (string-append what " is a bytevector") (shown-value input)))
    (let ((copy (bytevector-copy input)))
      (let scan ((i 0))
        (when (< i (bytevector-length copy))
          (when (= (bytevector-u8-ref copy i) 0)
            (refuse (latin-1 copy) 'embedded-nul #f
                    (string-append what " holds 0x00, which libcurl would read as its end")
                    (field-of what)))
          (scan (+ i 1))))
      copy))

  ;; set-url-named! : Positive-Integer String String -> Void
  ;; set-url! of TEXT, its refusal's input NAME, its field reference.
  (define (set-url-named! handle text name)
    (let ((code (call-with-c-string text
                  (lambda (address) (curl-url-set handle curlupart-url address 0)))))
      (unless (eqv? code curlue-ok)
        (refuse name (curl-url-code-reason code) code (curl-url-strerror code) 'reference))))

  ;; curl-url-resolve : String (U String Bytevector) -> String
  ;; REFERENCE resolved against BASE, by curl_url_set on BASE's handle
  ;; (ADR-0008), as curl_url_get gives it back, read as UTF-8. A string is a
  ;; URL as make-curl-request takes one, sent as UTF-8. A bytevector, a
  ;; header's bytes, is encoded by encoded-bytes first, as
  ;; curl-url-with-fragment encodes one (ADR-0029): a byte above 0x7F, in
  ;; any part, is then followed, never refused for the answer it would make,
  ;; but in a host, which libcurl decodes. A refusal names the string
  ;; refused, a bytevector's bytes read as Latin-1; one 0x00 among them is
  ;; refused as embedded-nul.
  (define (curl-url-resolve base reference)
    (define string (checked-input 'curl-url-resolve base))
    (if (bytevector? reference)
        (let* ((bytes (checked-bytes 'curl-url-resolve reference "a reference"))
               (name (latin-1 bytes))
               (text (encoded-bytes bytes)))
          (call-with-parsed-url string
            (lambda (handle)
              (set-url-named! handle text name)
              (get-part handle curlupart-url 0 #f name))))
        (let ((text (checked-string 'curl-url-resolve reference "a reference")))
          (call-with-parsed-url string
            (lambda (handle)
              (set-url! handle text)
              (get-part handle curlupart-url 0 #f text))))))

  ;; encoded-bytes : Bytevector -> String
  ;; BYTES, a header's, as chez-curl hands them to libcurl, for a fragment
  ;; curl-url-with-fragment writes and a reference curl-url-resolve
  ;; resolves: each byte at or below 0x20, 0x7F and each above 0x7F as %
  ;; and two upper-case hex digits, every other byte as its char, % and #
  ;; among them (ADR-0029). Pure, so the suite drives it over every byte.
  (define (encoded-bytes bytes)
    (let loop ((i (- (bytevector-length bytes) 1)) (acc '()))
      (if (< i 0)
          (apply string-append acc)
          (let ((b (bytevector-u8-ref bytes i)))
            (loop (- i 1)
                  (cons (if (or (<= b #x20) (>= b #x7F))
                            (string #\% (string-ref "0123456789ABCDEF" (div b 16))
                                    (string-ref "0123456789ABCDEF" (mod b 16)))
                            (string (integer->char b)))
                        acc))))))

  ;; fragment-url : String (U String #f) String -> String
  ;; The string curl-url-with-fragment has curl_url parse whole: from WHOLE,
  ;; a URL as curl_url_get gives it back, and its FRAGMENT as curl_url_get
  ;; gives it, #f for none, the fragment, with its #, comes off the end of
  ;; WHOLE; then # and NEW, unless NEW is empty. Pure, as appended-url is: a
  ;; "" fragment WHOLE lacks cuts nothing, and a non-empty fragment that is
  ;; not WHOLE's end is an error.
  (define (fragment-url whole fragment new)
    (let ((stem (cond ((not fragment) whole)
                      ((string-suffix? whole (string-append "#" fragment))
                       (substring whole 0 (- (string-length whole)
                                             (+ 1 (string-length fragment)))))
                      ((string=? fragment "") whole)
                      ;; Its irritants name the fields, never the URL.
                      (else (error 'curl-url-with-fragment
                                   "libcurl's URL does not end with its fragment"
                                   'url 'fragment)))))
      (if (string=? new "") stem (string-append stem "#" new))))

  ;; curl-url-with-fragment : String (U String Bytevector #f) -> String
  ;; URL with its fragment replaced by FRAGMENT, or cleared by #f or an
  ;; empty one (ADR-0029): URL parsed, its url and fragment read back, the
  ;; URL written again with # and FRAGMENT in place of its own, and that
  ;; string parsed whole, as url-normalize parses one, which keeps every
  ;; byte and its hex case on every libcurl, where curl_url_set of the part
  ;; stores the bytes unchecked and moves the hex case by version. A
  ;; bytevector, a header's bytes, is encoded first, by encoded-bytes,
  ;; and one holding 0x00 is refused as embedded-nul; a string comes as a
  ;; URL holds it, and nothing here encodes it. A refusal of the string
  ;; written names that string.
  (define (curl-url-with-fragment url fragment)
    (define string (checked-input 'curl-url-with-fragment url))
    (define addition
      (cond ((not fragment) "")
            ((bytevector? fragment)
             (encoded-bytes (checked-bytes 'curl-url-with-fragment fragment "a fragment")))
            ((string? fragment) (checked-string 'curl-url-with-fragment fragment "a fragment"))
            (else (assertion-violation 'curl-url-with-fragment
                                       "a fragment is a string, a bytevector or #f" (shown-value fragment)))))
    (let-values (((whole old)
                  (call-with-parsed-url string
                    (lambda (handle)
                      (let* ((whole (get-part handle curlupart-url 0 #f string))
                             (old (get-part handle curlupart-fragment 0 (code-of 'no-fragment)
                                            string)))
                        (values whole old))))))
      (let ((written (fragment-url whole old addition)))
        (call-with-parsed-url written
          (lambda (handle) (get-part handle curlupart-url 0 #f written)))))))
