#!r6rs
;;; (curl private conditions): chez-curl's condition types. Every one is a
;;; &curl-error, so a caller can catch the family or one member.
;;;
;;;   &curl-error                 the base, under &error
;;;   &curl-library-unavailable   libcurl was refused (ADR-0002, ADR-0003)
;;;   &curl-wrong-thread          an engine-owned handle used from another
;;;                               thread (ADR-0012)
;;;   &curl-embedded-nul          a string C would read short: it holds
;;;                               U+0000
;;;   &curl-url-error             a URL refused: by libcurl's URL API, or by
;;;                               chez-curl's own checks (ADR-0008)
;;;   &curl-request-error         a request's field refused, before anything
;;;                               native is made; or a piece put past a
;;;                               streamed body's length, on a token live
;;;   &curl-transfer-error        a transfer that failed: libcurl's code and
;;;                               texts, what the write callable recorded,
;;;                               the bytes of request sent, and the status a
;;;                               proxy refused its CONNECT with (ADR-0037),
;;;                               or one cancelled or stopped; and under it,
;;;                               its classes (ADR-0022):
;;;     &curl-timeout             28
;;;     &curl-connect-error       5, 6, 7, 45, 96, 97
;;;     &curl-send-receive-error  18, 52, 55, 56
;;;     &curl-tls-error           35, 53, 54, 58, 59, 60, 64, 66, 77, 80, 82,
;;;                               83, 90, 91, 98, 101
;;;     &curl-protocol-error      1, 8, 16, 61, 92, 95
;;;     &curl-too-large           63, 100, the body limit and the header cap
;;;   &curl-engine-error          an engine that has stopped, or failed, and
;;;                               the condition it failed with
;;;
;;; A raise may compound one with &who, &message and &irritants, so that
;;; the default handler prints readable text. Tests assert the reason symbol
;;; and the fields, never that text.
(library (curl private conditions)
  (export &curl-error make-curl-error curl-error?

          &curl-library-unavailable make-curl-library-unavailable
          curl-library-unavailable?
          curl-library-unavailable-reason curl-library-unavailable-path
          curl-library-unavailable-source curl-library-unavailable-detail
          curl-library-unavailable-candidates
          curl-library-unavailable-library
          curl-library-unavailable-reasons

          &curl-wrong-thread make-curl-wrong-thread curl-wrong-thread?
          curl-wrong-thread-who curl-wrong-thread-expected
          curl-wrong-thread-actual

          &curl-embedded-nul make-curl-embedded-nul curl-embedded-nul?
          curl-embedded-nul-string

          &curl-url-error make-curl-url-error curl-url-error?
          curl-url-error-input curl-url-error-reason curl-url-error-code
          curl-url-error-message curl-url-code-reason

          &curl-request-error make-curl-request-error curl-request-error?
          curl-request-error-field curl-request-error-value curl-request-error-reason
          curl-request-error-reasons

          &curl-transfer-error make-curl-transfer-error curl-transfer-error?
          curl-transfer-error-reason curl-transfer-error-code curl-transfer-error-option
          curl-transfer-error-strerror curl-transfer-error-error-buffer
          curl-transfer-error-recorded curl-transfer-error-request-size
          curl-transfer-error-connect-code
          curl-transfer-error-reasons make-classed-transfer-error
          curl-code-classes curl-code-class
          &curl-timeout make-curl-timeout curl-timeout?
          &curl-connect-error make-curl-connect-error curl-connect-error?
          &curl-send-receive-error make-curl-send-receive-error curl-send-receive-error?
          &curl-tls-error make-curl-tls-error curl-tls-error?
          &curl-protocol-error make-curl-protocol-error curl-protocol-error?
          &curl-too-large make-curl-too-large curl-too-large?

          &curl-engine-error make-curl-engine-error curl-engine-error?
          curl-engine-error-reason curl-engine-error-condition curl-engine-error-reasons

          kind-of shown-value shown-key checked-accessor)
  (import (curl private require-threaded)
          (rnrs)
          (curl private libcurl-info)
          (curl private constants))

  ;; make-curl-error : -> &curl-error
  ;; curl-error? : Any -> Boolean
  (define-condition-type &curl-error &error
    make-curl-error curl-error?)

  ;; --- a caller's value, as a refusal names it -------------------------------------

  ;; kind-of : Any -> Symbol
  ;; X's kind: string, list, number, boolean, char, symbol, bytevector,
  ;; vector, procedure or other. Pure.
  (define (kind-of x)
    (cond ((string? x) 'string)
          ((or (pair? x) (null? x)) 'list)
          ((number? x) 'number)
          ((boolean? x) 'boolean)
          ((char? x) 'char)
          ((symbol? x) 'symbol)
          ((bytevector? x) 'bytevector)
          ((vector? x) 'vector)
          ((procedure? x) 'procedure)
          (else 'other)))

  ;; shown-atom? : Any -> Boolean
  ;; Whether X is a symbol, a number, a boolean, a char or (): none holds a
  ;; URL, a header, credentials or a body.
  (define (shown-atom? x)
    (or (symbol? x) (number? x) (boolean? x) (char? x) (null? x)))

  ;; shown-value : Any -> Any
  ;; X as a refusal or an assertion names a caller's value where another
  ;; belongs: itself when it is shown-atom?, or a proper list of them, a
  ;; policy's statuses or methods; else (kind K), K its kind-of, never the
  ;; value: a string, or a list holding one, can be a URL, a header,
  ;; credentials or a body. A proxy URL or a credentials list handed where
  ;; a key or another value belongs was printed whole. Pure.
  (define (shown-value x)
    (if (or (shown-atom? x) (and (list? x) (for-all shown-atom? x)))
        x
        (list 'kind (kind-of x))))

  ;; shown-key : Any -> Any
  ;; X as a key's refusal names it: itself when it is a symbol, as a key is;
  ;; else (kind K), K its kind-of, a number's among them. Pure.
  (define (shown-key x)
    (if (symbol? x) x (list 'kind (kind-of x))))

  ;; checked-accessor : Symbol (Any -> Boolean) String (Any -> Any) -> (Any -> Any)
  ;; ACCESSOR, a record's or a condition type's, for WHO: called on what
  ;; PREDICATE holds; anything else an assertion violation from WHO, "not
  ;; WHAT", naming it by shown-value, never the value. Chez's own check
  ;; named what it refused, so (curl-request-url "http://u:PW@h/") printed
  ;; the password (ADR-0036).
  (define (checked-accessor who predicate what accessor)
    (lambda (x)
      (unless (predicate x)
        (assertion-violation who (string-append "not " what) (shown-value x)))
      (accessor x)))

  ;; --- &curl-library-unavailable ---------------------------------------------

  ;; curl-library-unavailable-reasons : (Listof Symbol)
  ;; Why a libcurl was refused. They are the contract: tests and CI assert
  ;; these symbols, never the message (ADR-0002, ADR-0003).
  ;;
  ;;   invalid-override  CHEZ_CURL_LIBCURL is set, but not to an absolute path
  ;;   not-found         no candidate exists
  ;;   load-failed       the loader refused the chosen path
  ;;   below-floor       the library is older than 7.85.0
  ;;   no-ssl            the library lacks CURL_VERSION_SSL
  ;;   missing-api       the options API or the header API is built out
  (define curl-library-unavailable-reasons
    '(invalid-override not-found load-failed below-floor no-ssl missing-api))

  ;; The fields:
  ;;
  ;;   reason      one of curl-library-unavailable-reasons
  ;;   path        (U String #f): the library refused, #f when none was chosen
  ;;   source      (U Symbol #f): where the path came from, one of
  ;;               (curl private discovery)'s libcurl-sources, or #f
  ;;   detail      by reason: the override's value (invalid-override), the
  ;;               loader's message (load-failed), the version string
  ;;               (below-floor, no-ssl), the API's C name (missing-api),
  ;;               #f (not-found)
  ;;   candidates  (Listof String): every path checked, in order (not-found)
  ;;   library     (U Libcurl-Info #f): what the library reported, for a
  ;;               refusal made after curl_version_info was read
  ;;               (below-floor, no-ssl, missing-api for any entry point
  ;;               but curl_version_info, and load-failed from
  ;;               curl_global_init or curl_easy_init); #f before that
  ;;               (ADR-0002)
  (define-condition-type &curl-library-unavailable &curl-error
    unchecked-make-curl-library-unavailable curl-library-unavailable?
    (reason unchecked-curl-library-unavailable-reason)
    (path unchecked-curl-library-unavailable-path)
    (source unchecked-curl-library-unavailable-source)
    (detail unchecked-curl-library-unavailable-detail)
    (candidates unchecked-curl-library-unavailable-candidates)
    (library unchecked-curl-library-unavailable-library))

  ;; Each accessor checks its argument first: anything else is an assertion
  ;; violation from the accessor, naming it by its kind, shown-value's,
  ;; never printed, as Chez's own check printed it (ADR-0036).
  (define curl-library-unavailable-reason
    (checked-accessor 'curl-library-unavailable-reason curl-library-unavailable? "a &curl-library-unavailable" unchecked-curl-library-unavailable-reason))
  (define curl-library-unavailable-path
    (checked-accessor 'curl-library-unavailable-path curl-library-unavailable? "a &curl-library-unavailable" unchecked-curl-library-unavailable-path))
  (define curl-library-unavailable-source
    (checked-accessor 'curl-library-unavailable-source curl-library-unavailable? "a &curl-library-unavailable" unchecked-curl-library-unavailable-source))
  (define curl-library-unavailable-detail
    (checked-accessor 'curl-library-unavailable-detail curl-library-unavailable? "a &curl-library-unavailable" unchecked-curl-library-unavailable-detail))
  (define curl-library-unavailable-candidates
    (checked-accessor 'curl-library-unavailable-candidates curl-library-unavailable? "a &curl-library-unavailable" unchecked-curl-library-unavailable-candidates))
  (define curl-library-unavailable-library
    (checked-accessor 'curl-library-unavailable-library curl-library-unavailable? "a &curl-library-unavailable" unchecked-curl-library-unavailable-library))

  ;; make-curl-library-unavailable : Symbol (U String #f) (U Symbol #f) Any
  ;;                                 (Listof String) (U Libcurl-Info #f)
  ;;                                 -> &curl-library-unavailable
  ;; Refuses a REASON that is not one of the six, and a LIBRARY that is
  ;; neither a libcurl-info nor #f, with an assertion violation, so a
  ;; misspelt reason cannot reach a caller who tests for the right one.
  (define (make-curl-library-unavailable reason path source detail candidates library)
    (unless (memq reason curl-library-unavailable-reasons)
      (assertion-violation 'make-curl-library-unavailable
                           "not a reason chez-curl refuses a libcurl for"
                           reason))
    (unless (or (not library) (libcurl-info? library))
      (assertion-violation 'make-curl-library-unavailable
                           "a refusal's library is a libcurl-info or #f"
                           library))
    (unchecked-make-curl-library-unavailable reason path source detail candidates
                                             library))

  ;; curl-library-unavailable? : Any -> Boolean
  ;; curl-library-unavailable-reason : &curl-library-unavailable -> Symbol
  ;; curl-library-unavailable-path : &curl-library-unavailable -> (U String #f)
  ;; curl-library-unavailable-source : &curl-library-unavailable -> (U Symbol #f)
  ;; curl-library-unavailable-detail : &curl-library-unavailable -> Any
  ;; curl-library-unavailable-candidates : &curl-library-unavailable
  ;;                                       -> (Listof String)
  ;; curl-library-unavailable-library : &curl-library-unavailable
  ;;                                    -> (U Libcurl-Info #f)

  ;; --- &curl-wrong-thread ----------------------------------------------------

  ;; make-curl-wrong-thread : Symbol Integer Integer -> &curl-wrong-thread
  ;; curl-wrong-thread? : Any -> Boolean
  ;; curl-wrong-thread-who : &curl-wrong-thread -> Symbol
  ;; curl-wrong-thread-expected : &curl-wrong-thread -> Integer
  ;; curl-wrong-thread-actual : &curl-wrong-thread -> Integer
  ;; An operation on an engine-owned handle ran on another thread: WHO is the
  ;; operation, EXPECTED the owner's get-thread-id, ACTUAL the caller's
  ;; (ADR-0012).
  (define-condition-type &curl-wrong-thread &curl-error
    make-curl-wrong-thread curl-wrong-thread?
    (who unchecked-curl-wrong-thread-who)
    (expected unchecked-curl-wrong-thread-expected)
    (actual unchecked-curl-wrong-thread-actual))

  ;; Each accessor checks its argument first: anything else is an assertion
  ;; violation from the accessor, naming it by its kind, shown-value's,
  ;; never printed, as Chez's own check printed it (ADR-0036).
  (define curl-wrong-thread-who
    (checked-accessor 'curl-wrong-thread-who curl-wrong-thread? "a &curl-wrong-thread" unchecked-curl-wrong-thread-who))
  (define curl-wrong-thread-expected
    (checked-accessor 'curl-wrong-thread-expected curl-wrong-thread? "a &curl-wrong-thread" unchecked-curl-wrong-thread-expected))
  (define curl-wrong-thread-actual
    (checked-accessor 'curl-wrong-thread-actual curl-wrong-thread? "a &curl-wrong-thread" unchecked-curl-wrong-thread-actual))

  ;; --- &curl-embedded-nul ----------------------------------------------------

  ;; make-curl-embedded-nul : String -> &curl-embedded-nul
  ;; curl-embedded-nul? : Any -> Boolean
  ;; curl-embedded-nul-string : &curl-embedded-nul -> String
  ;; STRING holds U+0000, so C, which reads a string to its first NUL, would
  ;; read it short. Refused before anything is allocated.
  (define-condition-type &curl-embedded-nul &curl-error
    make-curl-embedded-nul curl-embedded-nul?
    (string unchecked-curl-embedded-nul-string))

  ;; Each accessor checks its argument first: anything else is an assertion
  ;; violation from the accessor, naming it by its kind, shown-value's,
  ;; never printed, as Chez's own check printed it (ADR-0036).
  (define curl-embedded-nul-string
    (checked-accessor 'curl-embedded-nul-string curl-embedded-nul? "a &curl-embedded-nul" unchecked-curl-embedded-nul-string))

  ;; --- &curl-url-error ---------------------------------------------------------

  ;; The fields:
  ;;
  ;;   input    the string refused, or a bytevector's bytes read as Latin-1
  ;;   reason   (U Symbol #f): for libcurl's refusal, its CURLUcode's name in
  ;;            (curl private constants)'s curlue-codes, ok and the floor's
  ;;            others, or #f for a code that list lacks, a later libcurl's;
  ;;            for chez-curl's own, one of its four reasons:
  ;;              scheme-not-http  the URL parsed, but its scheme is neither
  ;;                               http nor https (ADR-0008)
  ;;              embedded-nul     the input holds U+0000, or a bytevector
  ;;                               0x00, which libcurl would read as its
  ;;                               end; a bytevector's input is its bytes
  ;;                               read as Latin-1
  ;;              not-utf-8        libcurl gave back a URL, or a part of one,
  ;;                               whose bytes are not UTF-8: it decodes a
  ;;                               host's %XX
  ;;              query-not-kept   a query part appended did not come back
  ;;                               as written, one holding # among them
  ;;                               (ADR-0028); the input is the part
  ;;   code     (U Integer #f): libcurl's CURLUcode, or #f for chez-curl's
  ;;            own refusals
  ;;   message  (U String #f): curl_url_strerror's text, or chez-curl's own
  ;;
  ;; Tests assert the reason and the code, never the message. The input is
  ;; this field's alone: a refusal's message and irritants name its field,
  ;; url, reference, query or fragment, never the string, which can hold
  ;; userinfo (ADR-0008; (curl private url)'s refuse).
  ;;
  ;; make-curl-url-error : Any Any Any Any -> &curl-url-error
  ;; curl-url-error? : Any -> Boolean
  ;; curl-url-error-input : &curl-url-error -> String
  ;; curl-url-error-reason : &curl-url-error -> (U Symbol #f)
  ;; curl-url-error-code : &curl-url-error -> (U Integer #f)
  ;; curl-url-error-message : &curl-url-error -> (U String #f)
  ;; The constructor checks nothing, so building a refusal never raises: a
  ;; code a later libcurl answers must still reach the caller.
  (define-condition-type &curl-url-error &curl-error
    make-curl-url-error curl-url-error?
    (input unchecked-curl-url-error-input)
    (reason unchecked-curl-url-error-reason)
    (code unchecked-curl-url-error-code)
    (message unchecked-curl-url-error-message))

  ;; Each accessor checks its argument first: anything else is an assertion
  ;; violation from the accessor, naming it by its kind, shown-value's,
  ;; never printed, as Chez's own check printed it (ADR-0036).
  (define curl-url-error-input
    (checked-accessor 'curl-url-error-input curl-url-error? "a &curl-url-error" unchecked-curl-url-error-input))
  (define curl-url-error-reason
    (checked-accessor 'curl-url-error-reason curl-url-error? "a &curl-url-error" unchecked-curl-url-error-reason))
  (define curl-url-error-code
    (checked-accessor 'curl-url-error-code curl-url-error? "a &curl-url-error" unchecked-curl-url-error-code))
  (define curl-url-error-message
    (checked-accessor 'curl-url-error-message curl-url-error? "a &curl-url-error" unchecked-curl-url-error-message))

  ;; --- &curl-request-error -------------------------------------------------------

  ;; curl-request-error-reasons : (Listof Symbol)
  ;; Why a request's field is refused:
  ;;
  ;;   embedded-nul  a value holds U+0000, which C would read as its end: a
  ;;                 header's, a CA file's path, or a hatch option's name or
  ;;                 string
  ;;   line-break    a value holds CR or LF, which would end its header line,
  ;;                 or a line libcurl sends: a header's, or a hatch
  ;;                 option's string
  ;;   not-latin-1   a value holds a char above U+00FF, which has no byte:
  ;;                 header strings are Latin-1, both ways (ADR-0001)
  ;;   not-a-token   a header name is empty, or holds a char that is no
  ;;                 tchar (RFC 9110, section 5.6.2)
  ;;   surrounding-whitespace
  ;;                 a value's first or last char is SP, HTAB, VT or FF:
  ;;                 RFC 9110 field values have none, and libcurl drops a
  ;;                 value of whitespace alone, and trims what it reads
  ;;   duplicates-field
  ;;                 a header named User-Agent, in any case, beside a user
  ;;                 agent given as its own field: libcurl lets the header
  ;;                 win; or a second header named Host, in any case:
  ;;                 libcurl sends only the first
  ;;   framing-header
  ;;                 a header named Content-Length or Transfer-Encoding, in
  ;;                 any case: libcurl frames the message, from the body it
  ;;                 is handed
  ;;   owned-option  an option the hatch may not attach: chez-curl sets it,
  ;;                 a request field sets it, it is the twin of one that
  ;;                 does, or chez-curl keeps it from the hatch, compared by
  ;;                 id (ADR-0009)
  ;;   unsupported-type
  ;;                 an option the hatch may not attach for its type: only
  ;;                 long, enumerated values, off_t, a string, a string list
  ;;                 and a blob, so no address of the caller's passes
  ;;   unknown-option
  ;;                 an option's name the loaded libcurl does not know
  ;;                 (ADR-0009)
  ;;   repeated-option
  ;;                 an option the request carries already, or one attached
  ;;                 earlier in the same call, by any of its names: its id
  ;;   unknown-key   a key make-curl-request or curl-request-with does not
  ;;                 take (ADR-0023)
  ;;   repeated-key  a key given twice to one call
  ;;   missing-value a key given last, with no value after it
  ;;   body-not-allowed
  ;;                 a body with get or head, which send none
  ;;   pkcs11-url    a CA file's path that begins pkcs11:, in any ASCII case,
  ;;                 which GnuTLS reads as a PKCS#11 URL, not a file (ADR-0024)
  ;;   environment-override
  ;;                 a CA file, verification on, on a libcurl that is Guix's,
  ;;                 every one of which is taken to write SSL_CERT_FILE over
  ;;                 it or add SSL_CERT_DIR beside it, with either set when
  ;;                 libcurl loaded (ADR-0024); the irritants
  ;;                 name each one set
  ;;   keychain-fallback
  ;;                 a CA file, verification on, on macOS with Apple's
  ;;                 LibreSSL the TLS backend in use, which checks the
  ;;                 keychain when a CA file fails (ADR-0024); the
  ;;                 irritants name the backend
  ;;   stream-with-rounds
  ;;                 a request that streams its response, stream-buffer,
  ;;                 beside a second request inside its transfer: the
  ;;                 private follow field, or an
  ;;                 Expect header whose value holds
  ;;                 100-continue, in any ASCII case, refused whatever the
  ;;                 method: a request that sends a body is sent again on a
  ;;                 417. Each would publish the head of the round before
  ;;                 the last
  ;;   body-length-without-stream
  ;;                 a body-length beside a body that does not stream, a
  ;;                 bytevector or none: libcurl frames a whole body from
  ;;                 its own length
  ;;   body-length-mismatch
  ;;                 a piece put past a streamed body's body-length, not
  ;;                 taken; the transfer then fails with the same reason,
  ;;                 unless another came first: by the read callable's abort
  ;;                 while libcurl still reads the body, else as its outcome
  ;;                 is read (ADR-0030)
  ;;   prior-knowledge-over-https
  ;;                 an http-version of http/2-prior-knowledge beside an
  ;;                 https:// URL, refused at submit, where the URL is
  ;;                 parsed: HTTP/2 by prior knowledge is for http:// alone,
  ;;                 and over https:// http/2 gets HTTP/2 by ALPN (ADR-0034)
  ;;   credentials-bytes
  ;;                 a credentials string, a user, a password or a token,
  ;;                 holding a control char, U+0000 to U+001F or U+007F,
  ;;                 which libcurl writes into its header unescaped; or a
  ;;                 Basic user holding a colon, where RFC 7617 ends the
  ;;                 user (ADR-0036)
  ;;   credentials-empty
  ;;                 credentials with nothing to send: a Bearer token "", or
  ;;                 a Basic or Digest user and password both "", which
  ;;                 8.23.0 sends no header for (ADR-0036)
  ;;   credentials-beside-userinfo
  ;;                 credentials beside a URL whose user or password part
  ;;                 libcurl's URL API reports, "" among them, refused at
  ;;                 submit, where the URL is parsed (ADR-0036)
  ;;   credentials-beside-authorization
  ;;                 credentials beside a header named Authorization, A to Z
  ;;                 folded: libcurl drops its own Basic and Bearer for the
  ;;                 caller's, and sends both beside Digest (ADR-0036)
  ;;   digest-with-stream
  ;;                 Digest credentials beside a streamed body or a streamed
  ;;                 response: Digest's second request inside the transfer
  ;;                 would publish the probe's 401 head, and its body rides a
  ;;                 pooled connection (ADR-0036)
  ;;   prior-knowledge-through-proxy
  ;;                 an http-version of http/2-prior-knowledge beside a proxy
  ;;                 URL, refused at submit: libcurl ignores prior knowledge
  ;;                 through a proxy that does not tunnel, and sends HTTP/1.1
  ;;                 (ADR-0034)
  ;;   proxy-url     a proxy URL libcurl's URL API cannot parse, one that
  ;;                 names no scheme among them, or whose user or password
  ;;                 holds a % not followed by two hex digits, refused at
  ;;                 submit (ADR-0037)
  ;;   proxy-scheme  a proxy URL whose scheme is neither http nor https, A to
  ;;                 Z folded, judged by chez-curl alike on every libcurl
  ;;   proxy-url-parts
  ;;                 a proxy URL with a path but /, a query or a fragment
  ;;   proxy-authorization-header
  ;;                 a header named Proxy-Authorization, A to Z folded,
  ;;                 whatever proxy the request names: inside a tunnel libcurl
  ;;                 sends it to the origin; a proxy's credentials are its
  ;;                 URL's userinfo (ADR-0037)
  ;;   proxy-tls-without-https-proxy
  ;;                 a proxy-ca-file, or proxy-verify #f, beside any proxy but
  ;;                 an https:// URL, refused at submit: the proxy's TLS
  ;;                 settings are an https:// proxy's alone
  ;;   proxy-tls-in-tls
  ;;                 an https:// URL through an https:// proxy URL on a
  ;;                 libcurl where TLS inside TLS stalls until its timeout:
  ;;                 Ubuntu's 8.5.0 with GnuTLS, whatever the http-version,
  ;;                 and 7.85.0 unless the request asks http/1.1 (ADR-0037)
  ;;   https-proxy-unsupported
  ;;                 an https:// proxy URL on a libcurl whose features lack
  ;;                 CURL_VERSION_HTTPS_PROXY: libcurl would refuse it, and
  ;;                 write the whole URL, its password with it, into its
  ;;                 error buffer (read in source)
  ;;   cookie-line   a line a cookie jar's load refuses, every line checked
  ;;                 before any is loaded: one not in the form a read-out
  ;;                 writes, seven tab-separated fields with no control
  ;;                 byte, TRUE or FALSE, the domain's dot beside TRUE, an
  ;;                 absolute path, an expiry of decimal digits, a name, a
  ;;                 name and value of 4,096 bytes at most; or holding a char
  ;;                 above U+00FF, which has no byte (ADR-0035)
  ;;   cookie-jar-engine
  ;;                 a request whose cookie-jar is another engine's than the
  ;;                 one it is submitted to: a jar is its engine's alone
  ;;   cookie-jar-closed
  ;;                 a request whose cookie-jar is closed, or closing,
  ;;                 refused at submit, or, a close crossing the submit, as
  ;;                 its transfer is set up, its token's outcome; or a
  ;;                 read-out or a load of a jar so
  ;;   cookie-beside-jar
  ;;                 a header named Cookie or Host, A to Z folded, any value,
  ;;                 beside a cookie jar: libcurl sends a caller's Cookie
  ;;                 beside the jar's, and matches the jar's cookies against
  ;;                 a caller's Host (ADR-0035)
  ;;   part-bytes    a multipart part's name, filename or type holding a
  ;;                 control char, U+0000 to U+001F or U+007F, or its name or
  ;;                 filename a ", a file part's default filename, its path's
  ;;                 last component, among them: libcurl would escape some
  ;;                 and send the rest raw, by version (ADR-0039)
  ;;   part-empty    a multipart part's name, filename or type that is ""
  ;;   multipart-empty
  ;;                 a multipart body with no part: libcurl would send a
  ;;                 closing delimiter alone
  ;;   multipart-content-type
  ;;                 a header named Content-Type, A to Z folded, beside a
  ;;                 multipart body: libcurl writes the body's type, its
  ;;                 boundary with it (ADR-0039)
  ;;   part-file     a file part's path that is empty, holds U+0000, or names
  ;;                 no regular file by stat, symlinks followed, as the
  ;;                 request is made or at submit; or, at submit, a path that
  ;;                 is not absolute, which only a fault can bring there
  ;;                 (ADR-0039)
  ;;   multipart-unsupported
  ;;                 a multipart body, at submit, on a libcurl whose load's
  ;;                 probe found no mime: curl_formadd answered other than 0,
  ;;                 or curl_mime_init made none (ADR-0039); the irritants
  ;;                 hold the probe's answer
  ;;
  ;; A value is scanned left to right, and its first offending char decides;
  ;; only when none offends are its ends checked.
  (define curl-request-error-reasons
    '(embedded-nul line-break not-latin-1 not-a-token surrounding-whitespace duplicates-field
      framing-header owned-option unsupported-type unknown-option repeated-option
      unknown-key repeated-key missing-value body-not-allowed pkcs11-url environment-override
      keychain-fallback stream-with-rounds body-length-without-stream body-length-mismatch
      prior-knowledge-over-https credentials-bytes credentials-empty credentials-beside-userinfo
      credentials-beside-authorization digest-with-stream prior-knowledge-through-proxy
      proxy-url proxy-scheme proxy-url-parts proxy-authorization-header
      proxy-tls-without-https-proxy proxy-tls-in-tls https-proxy-unsupported
      cookie-line cookie-jar-engine cookie-jar-closed cookie-beside-jar
      part-bytes part-empty multipart-empty multipart-content-type part-file
      multipart-unsupported))

  ;; The fields:
  ;;
  ;;   field   Symbol: the field refused, header-name, header-value,
  ;;           user-agent, ca-file, proxy-ca-file, or options, the hatch's;
  ;;           key for unknown-key, repeated-key and missing-value; body for
  ;;           body-not-allowed; stream-buffer for stream-with-rounds;
  ;;           body-length for body-length-without-stream and
  ;;           body-length-mismatch; http-version for
  ;;           prior-knowledge-over-https and prior-knowledge-through-proxy;
  ;;           credentials for the five credentials reasons; proxy for
  ;;           proxy-url, proxy-scheme, proxy-url-parts, proxy-tls-in-tls and
  ;;           https-proxy-unsupported, and for credentials-bytes and credentials-empty of a proxy
  ;;           URL's userinfo; header-name for proxy-authorization-header;
  ;;           proxy-ca-file or proxy-verify for
  ;;           proxy-tls-without-https-proxy; lines for cookie-line, a jar's
  ;;           load's; cookie-jar for cookie-jar-engine and
  ;;           cookie-jar-closed; header-name for cookie-beside-jar and
  ;;           multipart-content-type; body for the multipart reasons but
  ;;           that one
  ;;   value   the string refused, whole, or the option's name, but a header's
  ;;           value, named by its header's name, as given; the key, as
  ;;           given, for a key's refusal, but a key that is no symbol,
  ;;           named by its kind, (kind K), shown-key's: a proxy URL or a
  ;;           credentials list handed where a key belongs was printed whole;
  ;;           the method, for body-not-allowed;
  ;;           the stream-buffer, for stream-with-rounds; the body-length,
  ;;           for body-length-without-stream and body-length-mismatch; the
  ;;           http-version, for prior-knowledge-over-https and
  ;;           prior-knowledge-through-proxy; for credentials-bytes and
  ;;           credentials-empty, (SCHEME PART), the scheme, basic, digest or
  ;;           bearer, and the part refused, user, password or token, user
  ;;           for an empty user and password, or (proxy PART), user or
  ;;           password, for a proxy URL's userinfo; for the other three
  ;;           credentials reasons, the scheme alone; the symbol proxy for
  ;;           proxy-url, proxy-scheme, proxy-url-parts, proxy-tls-in-tls and
  ;;           https-proxy-unsupported, never the URL, which can hold a password; the header's name,
  ;;           as given, for proxy-authorization-header, never its value;
  ;;           the path, or #f, for proxy-tls-without-https-proxy; the
  ;;           line's index in the load's list, from 0, never the line, for
  ;;           cookie-line, whose irritants are the index and the rule it
  ;;           broke; the symbol cookie-jar for cookie-jar-engine and
  ;;           cookie-jar-closed; the header's name, as given, never its
  ;;           value, for cookie-beside-jar and multipart-content-type; for
  ;;           part-bytes, part-empty and part-file, (part I FIELD), the
  ;;           part's index, from 0, and name, filename, type or path, never
  ;;           the string, which can be a secret; the symbol multipart for
  ;;           multipart-empty and multipart-unsupported. A cookie's value is a secret,
  ;;           as a password is. No
  ;;           credentials string is ever a value or an irritant: a refusal
  ;;           names a secret by its part
  ;;   reason  one of curl-request-error-reasons
  (define-condition-type &curl-request-error &curl-error
    unchecked-make-curl-request-error curl-request-error?
    (field unchecked-curl-request-error-field)
    (value unchecked-curl-request-error-value)
    (reason unchecked-curl-request-error-reason))

  ;; Each accessor checks its argument first: anything else is an assertion
  ;; violation from the accessor, naming it by its kind, shown-value's,
  ;; never printed, as Chez's own check printed it (ADR-0036).
  (define curl-request-error-field
    (checked-accessor 'curl-request-error-field curl-request-error? "a &curl-request-error" unchecked-curl-request-error-field))
  (define curl-request-error-value
    (checked-accessor 'curl-request-error-value curl-request-error? "a &curl-request-error" unchecked-curl-request-error-value))
  (define curl-request-error-reason
    (checked-accessor 'curl-request-error-reason curl-request-error? "a &curl-request-error" unchecked-curl-request-error-reason))

  ;; make-curl-request-error : Symbol Any Symbol -> &curl-request-error
  ;; Refuses a REASON that is not one of curl-request-error-reasons with an
  ;; assertion violation, as make-curl-library-unavailable does.
  (define (make-curl-request-error field value reason)
    (unless (memq reason curl-request-error-reasons)
      (assertion-violation 'make-curl-request-error
                           "not a reason chez-curl refuses a request's field for"
                           reason))
    (unchecked-make-curl-request-error field value reason))

  ;; curl-request-error? : Any -> Boolean
  ;; curl-request-error-field : &curl-request-error -> Symbol
  ;; curl-request-error-value : &curl-request-error -> Any
  ;; curl-request-error-reason : &curl-request-error -> Symbol

  ;; --- &curl-transfer-error ------------------------------------------------------

  ;; curl-transfer-error-reasons : (Listof Symbol)
  ;; Why a transfer failed:
  ;;
  ;;   perform-failed   the transfer ended with a CURLcode, which
  ;;                    curl_multi_info_read gave the engine, and the write
  ;;                    callable recorded nothing
  ;;   body-limit       the callable refused a chunk past the body limit
  ;;   header-limit     the header callable refused a line past the cap on a
  ;;                    transfer's response headers, 1,000 header lines or
  ;;                    102,400 bytes over the whole transfer (ADR-0040); the
  ;;                    code is libcurl's answer to that refusal, 23, but 0
  ;;                    on 8.5.0 for an HTTP/2 trailer, whose refusal libcurl
  ;;                    loses, and on 8.7.1 56 for an HTTP/2 head, 23 for
  ;;                    its trailers
  ;;   callback-raised  something raised inside the callable, which recorded it
  ;;   setopt-failed    curl_easy_setopt answered a code, for the option named
  ;;   unknown-option   the loaded libcurl does not know the option named
  ;;   no-handle        curl_easy_init answered NULL
  ;;   cancelled        the caller cancelled it before it ended
  ;;   stopped          its engine stopped before it ended
  ;;   pause-failed     curl_easy_pause answered other than 0 when the engine
  ;;                    resumed a streamed transfer, and no callable recorded
  ;;                    a reason inside the call, which would win; the code
  ;;                    is the call's (ADR-0012)
  ;;   body-length-mismatch
  ;;                    a streamed body ended short of its body-length, or a
  ;;                    piece was put past it, alike on every libcurl: the read
  ;;                    callable recorded it and aborted the transfer, the code
  ;;                    42; or, for a piece put once libcurl had read the length
  ;;                    whole, and called the read callable no more, the outcome
  ;;                    reads the put's refusal, the code libcurl's own, 0 among
  ;;                    them (ADR-0030)
  ;;   body-not-replayable
  ;;                    libcurl wanted to send a streamed body again, by a
  ;;                    rewind or a later attempt, once the read callable had
  ;;                    handed it a byte: the seek or the prerequest callable
  ;;                    recorded it and refused (ADR-0032)
  ;;   part-file        a multipart body's file part failed the engine's
  ;;                    check, on its thread, before the transfer was set up:
  ;;                    no regular file there by stat, or one that does not
  ;;                    open, with no code; or curl_mime_filedata answered
  ;;                    one, its code (ADR-0039)
  ;;   mime-failed      curl_mime_init answered NULL, with no code, or another
  ;;                    call making the mime's parts answered one, its code
  ;; A reason a callable recorded wins over libcurl's code, which the code
  ;; field still carries.
  (define curl-transfer-error-reasons
    '(perform-failed body-limit callback-raised setopt-failed unknown-option no-handle
      cancelled stopped pause-failed body-length-mismatch body-not-replayable header-limit
      part-file mime-failed))

  ;; The fields:
  ;;
  ;;   reason        one of curl-transfer-error-reasons
  ;;   code          (U Integer #f): the CURLcode, a number, since codes
  ;;                 past the headers' have no name; #f when libcurl answered
  ;;                 none (unknown-option, no-handle, cancelled, stopped);
  ;;                 curl_easy_pause's answer for a failure in a resume
  ;;   option        (U String #f): the option's name, without CURLOPT_
  ;;   strerror      (U String #f): curl_easy_strerror's text for the code
  ;;   error-buffer  (U String #f): CURLOPT_ERRORBUFFER's text, read as
  ;;                 Latin-1, or #f when it is empty
  ;;   recorded      what the callable recorded: the raised object for
  ;;                 callback-raised, else #f
  ;;   request-size  (U Natural #f): for a transfer that ran, perform-failed,
  ;;                 body-limit, callback-raised, pause-failed,
  ;;                 body-length-mismatch, body-not-replayable or
  ;;                 header-limit,
  ;;                 CURLINFO_REQUEST_SIZE:
  ;;                 the bytes of request libcurl sent, its body's among
  ;;                 them, summed over every attempt it made, a resend on a
  ;;                 fresh connection after a dead one included, and 0 when
  ;;                 it sent none, or #f on a libcurl whose count is known
  ;;                 broken, 8.7.0 and 8.7.1 (ADR-0022); for a multipart body,
  ;;                 on 7.85.0 and 8.5.0, the head alone, whatever of the body
  ;;                 went, and on 8.20.0 and 8.23.0 the head and the body's
  ;;                 bytes sent; 0 for one refused while it was set up,
  ;;                 setopt-failed, unknown-option, no-handle, part-file or
  ;;                 mime-failed, which sent nothing; #f for one cancelled or
  ;;                 stopped, taken apart unread. Whether it is 0 is what the
  ;;                 retry policy reads to tell whether a request was sent: a
  ;;                 failure's timings move with the version, and this does not
  ;;                 (ADR-0022)
  ;;   connect-code  (U Positive-Integer #f): the status a proxy answered the
  ;;                 transfer's CONNECT with, CURLINFO_HTTP_CONNECTCODE, when
  ;;                 it is no 2xx: a proxy refused the tunnel, 403, 407, 502,
  ;;                 503 or any other; #f when the transfer sent no CONNECT, a
  ;;                 proxy ended it with no status, or the tunnel opened, and
  ;;                 for a transfer refused while it was set up, cancelled or
  ;;                 stopped. Such a failure's code moves with the version, 56
  ;;                 on 7.85.0 and 8.5.0 and 7 on 8.20.0 and 8.23.0, and its
  ;;                 status does not, so the high level's retry reads it
  ;;                 (ADR-0037 and ADR-0026)
  ;;
  ;; Tests assert the reason, the code, the option, the recorded object, the
  ;; request size and the CONNECT's status, and a text only where a version
  ;; row pins it.
  (define-condition-type &curl-transfer-error &curl-error
    unchecked-make-curl-transfer-error curl-transfer-error?
    (reason unchecked-curl-transfer-error-reason)
    (code unchecked-curl-transfer-error-code)
    (option unchecked-curl-transfer-error-option)
    (strerror unchecked-curl-transfer-error-strerror)
    (error-buffer unchecked-curl-transfer-error-error-buffer)
    (recorded unchecked-curl-transfer-error-recorded)
    (request-size unchecked-curl-transfer-error-request-size)
    (connect-code unchecked-curl-transfer-error-connect-code))

  ;; Each accessor checks its argument first: anything else is an assertion
  ;; violation from the accessor, naming it by its kind, shown-value's,
  ;; never printed, as Chez's own check printed it (ADR-0036).
  (define curl-transfer-error-reason
    (checked-accessor 'curl-transfer-error-reason curl-transfer-error? "a &curl-transfer-error" unchecked-curl-transfer-error-reason))
  (define curl-transfer-error-code
    (checked-accessor 'curl-transfer-error-code curl-transfer-error? "a &curl-transfer-error" unchecked-curl-transfer-error-code))
  (define curl-transfer-error-option
    (checked-accessor 'curl-transfer-error-option curl-transfer-error? "a &curl-transfer-error" unchecked-curl-transfer-error-option))
  (define curl-transfer-error-strerror
    (checked-accessor 'curl-transfer-error-strerror curl-transfer-error? "a &curl-transfer-error" unchecked-curl-transfer-error-strerror))
  (define curl-transfer-error-error-buffer
    (checked-accessor 'curl-transfer-error-error-buffer curl-transfer-error? "a &curl-transfer-error" unchecked-curl-transfer-error-error-buffer))
  (define curl-transfer-error-recorded
    (checked-accessor 'curl-transfer-error-recorded curl-transfer-error? "a &curl-transfer-error" unchecked-curl-transfer-error-recorded))
  (define curl-transfer-error-request-size
    (checked-accessor 'curl-transfer-error-request-size curl-transfer-error? "a &curl-transfer-error" unchecked-curl-transfer-error-request-size))
  (define curl-transfer-error-connect-code
    (checked-accessor 'curl-transfer-error-connect-code curl-transfer-error? "a &curl-transfer-error" unchecked-curl-transfer-error-connect-code))

  ;; check-transfer-error : Symbol Symbol (Listof Symbol) -> Void
  ;; Refuses a REASON that is not in REASONS, as WHO, with an assertion
  ;; violation.
  (define (check-transfer-error who reason reasons)
    (unless (memq reason reasons)
      (assertion-violation who "not a reason a chez-curl transfer fails for here" reason)))

  ;; make-curl-transfer-error : Symbol (U Integer #f) (U String #f) (U String #f)
  ;;                            (U String #f) Any (U Natural #f) (U Positive-Integer #f)
  ;;                            -> &curl-transfer-error
  ;; The base type, unclassed. Refuses a REASON that is not one of the
  ;; fourteen with an assertion violation. It checks nothing else, so a code a
  ;; later libcurl answers still reaches the caller.
  (define (make-curl-transfer-error reason code option strerror error-buffer recorded
                                    request-size connect-code)
    (check-transfer-error 'make-curl-transfer-error reason curl-transfer-error-reasons)
    (unchecked-make-curl-transfer-error reason code option strerror error-buffer recorded
                                        request-size connect-code))

  ;; curl-transfer-error? : Any -> Boolean
  ;; curl-transfer-error-reason : &curl-transfer-error -> Symbol
  ;; curl-transfer-error-code : &curl-transfer-error -> (U Integer #f)
  ;; curl-transfer-error-option : &curl-transfer-error -> (U String #f)
  ;; curl-transfer-error-strerror : &curl-transfer-error -> (U String #f)
  ;; curl-transfer-error-error-buffer : &curl-transfer-error -> (U String #f)
  ;; curl-transfer-error-recorded : &curl-transfer-error -> Any
  ;; curl-transfer-error-request-size : &curl-transfer-error -> (U Natural #f)
  ;; curl-transfer-error-connect-code : &curl-transfer-error -> (U Positive-Integer #f)

  ;; --- the classes (ADR-0022) ------------------------------------------------------

  ;; curl-code-classes : (Listof (Pairof Symbol (Listof Positive-Integer)))
  ;; Each class, with the CURLcodes it names, by their names in (curl
  ;; private constants). A class is described in curl's words for its
  ;; codes, from libcurl-errors, never by a cause: one failure's code moves
  ;; with the version (ADR-0022).
  ;;
  ;;   timeout       the operation timed out
  ;;   connect       a proxy or host was not resolved, connect() to the host
  ;;                 or proxy failed, an outgoing interface could not be
  ;;                 used, a QUIC connection failed, or a proxy's handshake
  ;;   send-receive  sending or receiving network data failed, nothing was
  ;;                 returned, or the transfer was shorter or larger than
  ;;                 expected
  ;;   tls           the TLS handshake, the server's certificate, the local
  ;;                 client certificate, CA cert, CRL or crypto engine, the
  ;;                 cipher, the pinned key, the certificate status, or ECH
  ;;   protocol      a protocol this libcurl does not support, data it could
  ;;                 not parse, the HTTP/2 or HTTP/3 layer, or an
  ;;                 unrecognized encoding
  ;;   too-large     a maximum file size, a value or a data field exceeded
  ;;
  ;; Every other code has no class, and raises the base type.
  ;; tests/test-conditions.sps writes out every code from 0 to 101.
  (define curl-code-classes
    `((timeout ,curle-operation-timedout)
      (connect ,curle-couldnt-resolve-proxy ,curle-couldnt-resolve-host ,curle-couldnt-connect
               ,curle-interface-failed ,curle-quic-connect-error ,curle-proxy)
      (send-receive ,curle-partial-file ,curle-got-nothing ,curle-send-error ,curle-recv-error)
      (tls ,curle-ssl-connect-error ,curle-ssl-engine-notfound ,curle-ssl-engine-setfailed
           ,curle-ssl-certproblem ,curle-ssl-cipher ,curle-peer-failed-verification
           ,curle-use-ssl-failed ,curle-ssl-engine-initfailed ,curle-ssl-cacert-badfile
           ,curle-ssl-shutdown-failed ,curle-ssl-crl-badfile ,curle-ssl-issuer-error
           ,curle-ssl-pinnedpubkeynotmatch ,curle-ssl-invalidcertstatus ,curle-ssl-clientcert
           ,curle-ech-required)
      (protocol ,curle-unsupported-protocol ,curle-weird-server-reply ,curle-http2
                ,curle-bad-content-encoding ,curle-http2-stream ,curle-http3)
      (too-large ,curle-filesize-exceeded ,curle-too-large)))

  ;; curl-code-class : Any -> (U Symbol #f)
  ;; The class curl-code-classes names CODE in, or #f: a code no class
  ;; names, a code past the table, or no code. It never raises.
  (define (curl-code-class code)
    (let loop ((classes curl-code-classes))
      (cond ((null? classes) #f)
            ((memv code (cdar classes)) (caar classes))
            (else (loop (cdr classes))))))

  ;; Each class is a condition type under &curl-transfer-error, with every
  ;; field the base has, and a constructor that takes perform-failed alone,
  ;; with a code the class names, or, for too-large, body-limit and
  ;; header-limit too, with any code.
  ;;
  ;; make-curl-timeout, make-curl-connect-error, make-curl-send-receive-error,
  ;; make-curl-tls-error, make-curl-protocol-error, make-curl-too-large :
  ;;   Symbol (U Integer #f) (U String #f) (U String #f) (U String #f) Any
  ;;   (U Natural #f) (U Positive-Integer #f) -> &curl-transfer-error
  ;; curl-timeout?, curl-connect-error?, curl-send-receive-error?,
  ;; curl-tls-error?, curl-protocol-error?, curl-too-large? : Any -> Boolean
  (define-condition-type &curl-timeout &curl-transfer-error
    unchecked-make-curl-timeout curl-timeout?)
  (define-condition-type &curl-connect-error &curl-transfer-error
    unchecked-make-curl-connect-error curl-connect-error?)
  (define-condition-type &curl-send-receive-error &curl-transfer-error
    unchecked-make-curl-send-receive-error curl-send-receive-error?)
  (define-condition-type &curl-tls-error &curl-transfer-error
    unchecked-make-curl-tls-error curl-tls-error?)
  (define-condition-type &curl-protocol-error &curl-transfer-error
    unchecked-make-curl-protocol-error curl-protocol-error?)
  (define-condition-type &curl-too-large &curl-transfer-error
    unchecked-make-curl-too-large curl-too-large?)

  ;; check-class : Symbol Symbol Symbol Any -> Void
  ;; Refuses, as WHO, with an assertion violation, a REASON and CODE the
  ;; class CLASS does not take: perform-failed with a code CLASS names, or,
  ;; for too-large, body-limit and header-limit too.
  (define (check-class who class reason code)
    (unless (or (and (eq? reason 'perform-failed) (eq? (curl-code-class code) class))
                (and (eq? class 'too-large) (memq reason '(body-limit header-limit))))
      (assertion-violation who "not a reason and code this class takes" reason code)))

  (define (make-curl-timeout reason code option strerror error-buffer recorded
                             request-size connect-code)
    (check-class 'make-curl-timeout 'timeout reason code)
    (unchecked-make-curl-timeout reason code option strerror error-buffer recorded
                                 request-size connect-code))

  (define (make-curl-connect-error reason code option strerror error-buffer recorded
                                   request-size connect-code)
    (check-class 'make-curl-connect-error 'connect reason code)
    (unchecked-make-curl-connect-error reason code option strerror error-buffer recorded
                                       request-size connect-code))

  (define (make-curl-send-receive-error reason code option strerror error-buffer recorded
                                        request-size connect-code)
    (check-class 'make-curl-send-receive-error 'send-receive reason code)
    (unchecked-make-curl-send-receive-error reason code option strerror error-buffer recorded
                                            request-size connect-code))

  (define (make-curl-tls-error reason code option strerror error-buffer recorded
                               request-size connect-code)
    (check-class 'make-curl-tls-error 'tls reason code)
    (unchecked-make-curl-tls-error reason code option strerror error-buffer recorded
                                   request-size connect-code))

  (define (make-curl-protocol-error reason code option strerror error-buffer recorded
                                    request-size connect-code)
    (check-class 'make-curl-protocol-error 'protocol reason code)
    (unchecked-make-curl-protocol-error reason code option strerror error-buffer recorded
                                        request-size connect-code))

  (define (make-curl-too-large reason code option strerror error-buffer recorded
                               request-size connect-code)
    (check-class 'make-curl-too-large 'too-large reason code)
    (unchecked-make-curl-too-large reason code option strerror error-buffer recorded
                                   request-size connect-code))

  ;; make-classed-transfer-error : Symbol (U Integer #f) (U String #f) (U String #f)
  ;;                               (U String #f) Any (U Natural #f) (U Positive-Integer #f)
  ;;                               -> &curl-transfer-error
  ;; What a failed transfer raises (ADR-0022): for
  ;; perform-failed, the class its CODE has, or the base type for a code no
  ;; class names; for body-limit and header-limit, too-large, whatever its
  ;; code; for every other reason, the base type, a setopt-failed whose code
  ;; a class names among them. A REASON not among the fourteen is an
  ;; assertion violation.
  (define (make-classed-transfer-error reason code option strerror error-buffer recorded
                                       request-size connect-code)
    (check-transfer-error 'make-classed-transfer-error reason curl-transfer-error-reasons)
    (let ((make (case (if (memq reason '(body-limit header-limit))
                          'too-large
                          (and (eq? reason 'perform-failed) (curl-code-class code)))
                  ((timeout) make-curl-timeout)
                  ((connect) make-curl-connect-error)
                  ((send-receive) make-curl-send-receive-error)
                  ((tls) make-curl-tls-error)
                  ((protocol) make-curl-protocol-error)
                  ((too-large) make-curl-too-large)
                  (else make-curl-transfer-error))))
      (make reason code option strerror error-buffer recorded request-size connect-code)))

  ;; --- &curl-engine-error -------------------------------------------------------

  ;; curl-engine-error-reasons : (Listof Symbol)
  ;; Why an engine refused a message, or failed a transfer:
  ;;
  ;;   stopped  the engine was stopped: a submit after its stop
  ;;   failed   something raised inside the engine's loop: every transfer it
  ;;            held, and a later submit, carries the condition
  (define curl-engine-error-reasons '(stopped failed))

  ;; The fields:
  ;;
  ;;   reason     one of curl-engine-error-reasons
  ;;   condition  what the loop raised, for failed; #f for stopped
  ;;
  ;; Tests assert the reason and the condition, never the message.
  (define-condition-type &curl-engine-error &curl-error
    unchecked-make-curl-engine-error curl-engine-error?
    (reason unchecked-curl-engine-error-reason)
    (condition unchecked-curl-engine-error-condition))

  ;; Each accessor checks its argument first: anything else is an assertion
  ;; violation from the accessor, naming it by its kind, shown-value's,
  ;; never printed, as Chez's own check printed it (ADR-0036).
  (define curl-engine-error-reason
    (checked-accessor 'curl-engine-error-reason curl-engine-error? "a &curl-engine-error" unchecked-curl-engine-error-reason))
  (define curl-engine-error-condition
    (checked-accessor 'curl-engine-error-condition curl-engine-error? "a &curl-engine-error" unchecked-curl-engine-error-condition))

  ;; make-curl-engine-error : Symbol Any -> &curl-engine-error
  ;; Refuses a REASON that is not one of the two with an assertion violation.
  (define (make-curl-engine-error reason condition)
    (unless (memq reason curl-engine-error-reasons)
      (assertion-violation 'make-curl-engine-error
                           "not a reason a chez-curl engine refuses or fails for"
                           reason))
    (unchecked-make-curl-engine-error reason condition))

  ;; curl-engine-error? : Any -> Boolean
  ;; curl-engine-error-reason : &curl-engine-error -> Symbol
  ;; curl-engine-error-condition : &curl-engine-error -> Any

  ;; curl-url-code-reason : Any -> (U Symbol #f)
  ;; CODE's name in curlue-codes, or #f for anything else: a later
  ;; libcurl's code, or no code at all. It never raises.
  (define (curl-url-code-reason code)
    (let loop ((codes curlue-codes))
      (cond ((null? codes) #f)
            ((eqv? (cdar codes) code) (caar codes))
            (else (loop (cdr codes)))))))
