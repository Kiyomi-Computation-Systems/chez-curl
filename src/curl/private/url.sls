#!r6rs
;;; (curl private url): URLs parsed, resolved and checked by libcurl's own
;;; URL API (ADR-0008; M2 plan, section 4.4).
;;;
;;; Every CURLU handle here is made and freed within one call, under
;;; dynamic-wind, on the calling thread: nothing native outlives the call
;;; that made it (M2 plan, section 3.1), and re-entering a finished call
;;; through a continuation raises. The one exception is an engine's
;;; transfer, which holds its URL's handle from its start to its end, on
;;; the engine's thread: parse-url makes it, in its caller's critical
;;; section, and free-parsed-url! frees it (M3 plan, section 3.1). Each dynamic-wind is critical, its
;;; critical? argument #t: a handle, or a string libcurl made, is made in
;;; the before thunk and recorded where the after thunk frees it in one
;;; critical section, so an interrupt that escapes, an engine's expiry say,
;;; cannot fall between (M2 fix round 2). Each string curl_url_get hands back is
;;; copied, then freed with curl_free. Each string handed to libcurl is a
;;; counted, NUL-terminated UTF-8 copy, freed as soon as curl_url_set
;;; returns: libcurl "does not have to keep content around after a
;;; successful call" (curl_url_set(3), 7.85.0).
;;;
;;; Every refusal raises &curl-url-error (curl private conditions): with
;;; libcurl's CURLUcode and its name, or with one of chez-curl's own
;;; reasons, scheme-not-http, embedded-nul, not-utf-8 or query-not-kept, and
;;; no code. A string holding U+0000 is refused before libcurl sees it: C
;;; reads a string to its first NUL, so "http://a/\x0;b" would reach libcurl
;;; as http://a/. Every string curl_url_get gives back is read as UTF-8, or
;;; refused as not-utf-8, never decoded with U+FFFD: libcurl decodes a
;;; host's %XX, so http://caf%E9.example/ comes back holding the byte 0xE9,
;;; on every libcurl measured (the M5 plan, section 3.1;
;;; .plans/research/m5/url-parts/).
;;;
;;; curl's verdicts vary by version (ADR-0008, amended 2026-10-19):
;;; tests/test-url.sps holds the shared answers, and
;;; tests/known-url-verdicts.sexp a row per libcurl for the rest.
(library (curl private url)
  (export url-normalize url-resolve call-with-parsed-url require-http-scheme
          parse-url free-parsed-url! curl-url-part curl-url-append-query appended-url)
  (import (curl private require-threaded)
          (except (rnrs) dynamic-wind)
          (only (chezscheme) dynamic-wind)
          (curl private conditions)
          (curl private constants)
          (curl private native))

  ;; refuse : String (U Symbol #f) (U Integer #f) (U String #f) -> Nothing
  (define (refuse input reason code message)
    (raise (condition (make-curl-url-error input reason code message)
                      (make-who-condition 'chez-curl)
                      (make-message-condition
                       (or message "libcurl's URL API refused a URL"))
                      (make-irritants-condition (list input)))))

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
      (assertion-violation who (string-append what " is a string") input))
    (let ((copy (string-copy input)))
      (when (holds-nul? copy)
        (refuse copy 'embedded-nul #f
                (string-append what " holds U+0000, which libcurl would read as its end")))
      copy))

  ;; checked-input : Symbol Any -> String
  ;; checked-string for a URL.
  (define (checked-input who input)
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
    (let ((code (call-with-c-string input
                  (lambda (address) (curl-url-set handle curlupart-url address 0)))))
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
            (assertion-violation 'get-part "re-entered after its string was freed" input))
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
    (define string (checked-input 'call-with-parsed-url input))
    (unless (procedure? proc)
      (assertion-violation 'call-with-parsed-url "not a procedure" proc))
    (let ((handle #f) (freed #f))
      (dynamic-wind #t
        (lambda ()
          (when freed
            (assertion-violation 'call-with-parsed-url
                                 "re-entered after its handle was freed" string))
          (let ((made (curl-url)))
            (when (eqv? made 0)
              (error 'call-with-parsed-url "curl_url returned NULL: no memory for a handle"))
            (set! handle made)))
        (lambda ()
          (set-url! handle string)
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
  ;; (ADR-0008, decision 4), as curl_url_get gives it back. A refusal of
  ;; either raises, naming the string refused.
  (define (url-resolve base input)
    (define reference (checked-input 'url-resolve input))
    (call-with-parsed-url base
      (lambda (handle)
        (set-url! handle reference)
        (get-part handle curlupart-url 0 #f reference))))

  ;; require-http-scheme : Positive-Integer String -> Void
  ;; Returns when the parsed HANDLE's scheme, as curl_url_get gives it, is
  ;; http or https. Otherwise raises &curl-url-error, reason
  ;; scheme-not-http, with the URL HANDLE holds as its input (ADR-0008,
  ;; decision 2). libcurl writes a scheme in lower case. INPUT, the string
  ;; HANDLE was parsed from, names the refusal of a URL libcurl gives back
  ;; as bytes that are not UTF-8, which has no string of its own.
  (define (require-http-scheme handle input)
    (let ((url (get-part handle curlupart-url 0 #f input)))
      (unless (member (get-part handle curlupart-scheme 0 #f url) '("http" "https"))
        (refuse url 'scheme-not-http #f "chez-curl fetches only http and https URLs"))))

  ;; code-of : Symbol -> Natural
  ;; The CURLUcode NAME names in curlue-codes.
  (define (code-of name) (cdr (assq name curlue-codes)))

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
          (list 'fragment curlupart-fragment 0 (code-of 'no-fragment))))

  ;; curl-url-part : String Symbol -> (U String Natural #f)
  ;; PART of URL, parsed by curl_url_set with no flags, as curl_url_get
  ;; gives it back with no flags: url, the whole URL; scheme, user,
  ;; password, host, path, query or fragment, a string, or #f for one the
  ;; URL lacks; or port, a natural, the scheme's default when the URL names
  ;; none. URL's refusal raises &curl-url-error, and so does an answer whose
  ;; bytes are not UTF-8, as not-utf-8. Whether an empty user, password or
  ;; query is "" or #f varies by version: tests/known-url-part-verdicts.sexp.
  (define (curl-url-part url part)
    (define string (checked-input 'curl-url-part url))
    (let ((row (assq part url-parts)))
      (unless row
        (assertion-violation 'curl-url-part "not a part of a URL" part))
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
  ;; nor answers "" for an empty fragment it leaves out of the URL; the
  ;; Mac's 8.7.1 is not measured. A stem ending in ? with no query loses it,
  ;; so the part never reads back as ?part; a "" fragment WHOLE lacks adds
  ;; no #. A non-empty fragment that is not WHOLE's end is an error.
  (define (appended-url whole query fragment part)
    (let* ((old (or query ""))
           (tail (cond ((not fragment) "")
                       ((string-suffix? whole (string-append "#" fragment))
                        (string-append "#" fragment))
                       ((string=? fragment "") "")
                       (else (error 'curl-url-append-query
                                    "libcurl's URL does not end with its fragment"
                                    whole fragment))))
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
                        "the query part would not come back as written"))
              answer)))))))
