#!r6rs
;;; (curl private conditions): chez-curl's condition types. Every one is a
;;; &curl-error, so a caller can catch the family or one member.
;;;
;;;   &curl-error                 the base, under &error
;;;   &curl-library-unavailable   libcurl was refused (ADR-0002, ADR-0003)
;;;   &curl-wrong-thread          an engine-owned handle used from another
;;;                               thread (ADR-0012)
;;;   &curl-embedded-nul          a string C would read short: it holds
;;;                               U+0000 (M2 plan, section 3.3)
;;;   &curl-url-error             a URL refused: by libcurl's URL API, or by
;;;                               chez-curl's own checks (ADR-0008)
;;;   &curl-request-error         a request's field refused, before anything
;;;                               native is made (M2 plan, section 5.3); or
;;;                               a piece put past a streamed body's length,
;;;                               on a token live (the M6 plan, section 3.3)
;;;   &curl-transfer-error        a transfer that failed: libcurl's code and
;;;                               texts, what the write callable recorded,
;;;                               and the bytes of request sent (M2 plan,
;;;                               sections 3.7 and 5.3), or one cancelled or
;;;                               stopped (M3 plan, section 3.4); and under
;;;                               it, its classes (ADR-0022):
;;;     &curl-timeout             28
;;;     &curl-connect-error       5, 6, 7, 45, 96, 97
;;;     &curl-send-receive-error  18, 52, 55, 56
;;;     &curl-tls-error           35, 53, 54, 58, 59, 60, 64, 66, 77, 80, 82,
;;;                               83, 90, 91, 98, 101
;;;     &curl-protocol-error      1, 8, 16, 61, 92, 95
;;;     &curl-too-large           63, 100, and the body limit
;;;   &curl-engine-error          an engine that has stopped, or failed, and
;;;                               the condition it failed with (M3 plan,
;;;                               sections 3.4 and 3.7)
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
          curl-transfer-error-reasons make-classed-transfer-error
          curl-code-classes curl-code-class
          &curl-timeout make-curl-timeout curl-timeout?
          &curl-connect-error make-curl-connect-error curl-connect-error?
          &curl-send-receive-error make-curl-send-receive-error curl-send-receive-error?
          &curl-tls-error make-curl-tls-error curl-tls-error?
          &curl-protocol-error make-curl-protocol-error curl-protocol-error?
          &curl-too-large make-curl-too-large curl-too-large?

          &curl-engine-error make-curl-engine-error curl-engine-error?
          curl-engine-error-reason curl-engine-error-condition curl-engine-error-reasons)
  (import (curl private require-threaded)
          (rnrs)
          (curl private libcurl-info)
          (curl private constants))

  ;; make-curl-error : -> &curl-error
  ;; curl-error? : Any -> Boolean
  (define-condition-type &curl-error &error
    make-curl-error curl-error?)

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
  ;;               (ADR-0002, decision 4)
  (define-condition-type &curl-library-unavailable &curl-error
    unchecked-make-curl-library-unavailable curl-library-unavailable?
    (reason curl-library-unavailable-reason)
    (path curl-library-unavailable-path)
    (source curl-library-unavailable-source)
    (detail curl-library-unavailable-detail)
    (candidates curl-library-unavailable-candidates)
    (library curl-library-unavailable-library))

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
    (who curl-wrong-thread-who)
    (expected curl-wrong-thread-expected)
    (actual curl-wrong-thread-actual))

  ;; --- &curl-embedded-nul ----------------------------------------------------

  ;; make-curl-embedded-nul : String -> &curl-embedded-nul
  ;; curl-embedded-nul? : Any -> Boolean
  ;; curl-embedded-nul-string : &curl-embedded-nul -> String
  ;; STRING holds U+0000, so C, which reads a string to its first NUL, would
  ;; read it short. Refused before anything is allocated (M2 plan, section
  ;; 3.3).
  (define-condition-type &curl-embedded-nul &curl-error
    make-curl-embedded-nul curl-embedded-nul?
    (string curl-embedded-nul-string))

  ;; --- &curl-url-error ---------------------------------------------------------

  ;; The fields:
  ;;
  ;;   input    the string refused, or a bytevector's bytes read as Latin-1
  ;;   reason   (U Symbol #f): for libcurl's refusal, its CURLUcode's name in
  ;;            (curl private constants)'s curlue-codes, ok and the floor's
  ;;            others, or #f for a code that list lacks, a later libcurl's;
  ;;            for chez-curl's own, one of its four reasons:
  ;;              scheme-not-http  the URL parsed, but its scheme is neither
  ;;                               http nor https (ADR-0008, decision 2)
  ;;              embedded-nul     the input holds U+0000, or a bytevector
  ;;                               0x00, which libcurl would read as its
  ;;                               end; a bytevector's input is its bytes
  ;;                               read as Latin-1
  ;;              not-utf-8        libcurl gave back a URL, or a part of one,
  ;;                               whose bytes are not UTF-8: it decodes a
  ;;                               host's %XX (the M5 plan, section 3.1)
  ;;              query-not-kept   a query part appended did not come back
  ;;                               as written, one holding # among them
  ;;                               (ADR-0028); the input is the part
  ;;   code     (U Integer #f): libcurl's CURLUcode, or #f for chez-curl's
  ;;            own refusals
  ;;   message  (U String #f): curl_url_strerror's text, or chez-curl's own
  ;;
  ;; Tests assert the reason and the code, never the message.
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
    (input curl-url-error-input)
    (reason curl-url-error-reason)
    (code curl-url-error-code)
    (message curl-url-error-message))

  ;; --- &curl-request-error -------------------------------------------------------

  ;; curl-request-error-reasons : (Listof Symbol)
  ;; Why a request's field is refused (M2 plan, section 5.3):
  ;;
  ;;   embedded-nul  a value holds U+0000, which C would read as its end: a
  ;;                 header's, a CA file's path, or a hatch option's name or
  ;;                 string
  ;;   line-break    a value holds CR or LF, which would end its header line,
  ;;                 or a line libcurl sends: a header's, or a hatch
  ;;                 option's string
  ;;   not-latin-1   a value holds a char above U+00FF, which has no byte:
  ;;                 header strings are Latin-1, both ways (ADR-0001,
  ;;                 amended 2026-10-23)
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
  ;;                 id (ADR-0009, amended 2026-10-23 and 2026-10-27)
  ;;   unsupported-type
  ;;                 an option the hatch may not attach for its type: only
  ;;                 long, enumerated values, off_t, a string, a string list
  ;;                 and a blob, so no address of the caller's passes
  ;;   unknown-option
  ;;                 an option's name the loaded libcurl does not know
  ;;                 (ADR-0009, decision 3)
  ;;   repeated-option
  ;;                 an option the request carries already, or one attached
  ;;                 earlier in the same call, by any of its names: its id
  ;;   unknown-key   a key make-curl-request or curl-request-with does not
  ;;                 take (ADR-0023)
  ;;   repeated-key  a key given twice to one call
  ;;   missing-value a key given last, with no value after it
  ;;   body-not-allowed
  ;;                 a body with get or head, which send none (the M4 plan,
  ;;                 section 3.2)
  ;;   pkcs11-url    a CA file's path that begins pkcs11:, in any ASCII case,
  ;;                 which GnuTLS reads as a PKCS#11 URL, not a file
  ;;                 (ADR-0024, decision 4)
  ;;   environment-override
  ;;                 a CA file, verification on, on a libcurl that is Guix's,
  ;;                 every one of which is taken to write SSL_CERT_FILE over
  ;;                 it or add SSL_CERT_DIR beside it, with either set when
  ;;                 libcurl loaded (ADR-0024, decision 2); the irritants
  ;;                 name each one set
  ;;   keychain-fallback
  ;;                 a CA file, verification on, on macOS with Apple's
  ;;                 LibreSSL the TLS backend in use, which checks the
  ;;                 keychain when a CA file fails (ADR-0024, amended
  ;;                 2026-10-27); the irritants name the backend
  ;;   stream-with-rounds
  ;;                 a request that streams its response, stream-buffer,
  ;;                 beside a second request inside its transfer: the
  ;;                 private follow field, the hatch's PROXYAUTH, or an
  ;;                 Expect header whose value holds
  ;;                 100-continue, in any ASCII case, refused whatever the
  ;;                 method: a request that sends a body is sent again on a
  ;;                 417. Each would publish the head of the round before
  ;;                 the last (the M6 plan, section 3.2)
  ;;   body-length-without-stream
  ;;                 a body-length beside a body that does not stream, a
  ;;                 bytevector or none: libcurl frames a whole body from
  ;;                 its own length (the M6 plan, section 3.1)
  ;;   body-length-mismatch
  ;;                 a piece put past a streamed body's body-length, not
  ;;                 taken; the transfer then fails with the same reason,
  ;;                 unless another came first: by the read callable's abort
  ;;                 while libcurl still reads the body, else as its outcome
  ;;                 is read (the M6 plan, section 3.3; ADR-0030, amended
  ;;                 2026-10-31)
  ;;   prior-knowledge-over-https
  ;;                 an http-version of http/2-prior-knowledge beside an
  ;;                 https:// URL, refused at submit, where the URL is
  ;;                 parsed: HTTP/2 by prior knowledge is for http:// alone,
  ;;                 and over https:// http/2 gets HTTP/2 by ALPN (ADR-0034,
  ;;                 decision 2)
  ;;   credentials-bytes
  ;;                 a credentials string, a user, a password or a token,
  ;;                 holding a control char, U+0000 to U+001F or U+007F,
  ;;                 which libcurl writes into its header unescaped; or a
  ;;                 Basic user holding a colon, where RFC 7617 ends the
  ;;                 user (ADR-0036, amended 2026-11-02, decision 6)
  ;;   credentials-empty
  ;;                 credentials with nothing to send: a Bearer token "", or
  ;;                 a Basic or Digest user and password both "", which
  ;;                 8.23.0 sends no header for (ADR-0036, decision 7)
  ;;   credentials-beside-userinfo
  ;;                 credentials beside a URL whose user or password part
  ;;                 libcurl's URL API reports, "" among them, refused at
  ;;                 submit, where the URL is parsed (ADR-0036, decision 1)
  ;;   credentials-beside-authorization
  ;;                 credentials beside a header named Authorization, A to Z
  ;;                 folded: libcurl drops its own Basic and Bearer for the
  ;;                 caller's, and sends both beside Digest (ADR-0036,
  ;;                 decision 4)
  ;;   digest-with-stream
  ;;                 Digest credentials beside a streamed body or a streamed
  ;;                 response: Digest's second request inside the transfer
  ;;                 would publish the probe's 401 head, and its body rides a
  ;;                 pooled connection (ADR-0036, decision 3)
  ;;
  ;; A value is scanned left to right, and its first offending char decides;
  ;; only when none offends are its ends checked.
  (define curl-request-error-reasons
    '(embedded-nul line-break not-latin-1 not-a-token surrounding-whitespace duplicates-field
      framing-header owned-option unsupported-type unknown-option repeated-option
      unknown-key repeated-key missing-value body-not-allowed pkcs11-url environment-override
      keychain-fallback stream-with-rounds body-length-without-stream body-length-mismatch
      prior-knowledge-over-https credentials-bytes credentials-empty credentials-beside-userinfo
      credentials-beside-authorization digest-with-stream))

  ;; The fields:
  ;;
  ;;   field   Symbol: the field refused, header-name, header-value,
  ;;           user-agent, ca-file, or options, the hatch's; key for
  ;;           unknown-key, repeated-key and missing-value; body for
  ;;           body-not-allowed; stream-buffer for stream-with-rounds;
  ;;           body-length for body-length-without-stream and
  ;;           body-length-mismatch; http-version for
  ;;           prior-knowledge-over-https; credentials for the five
  ;;           credentials reasons
  ;;   value   the string refused, whole, or the option's name; the key, as
  ;;           given, for a key's refusal; the method, for body-not-allowed;
  ;;           the stream-buffer, for stream-with-rounds; the body-length,
  ;;           for body-length-without-stream and body-length-mismatch; the
  ;;           http-version, for prior-knowledge-over-https; for
  ;;           credentials-bytes and credentials-empty, (SCHEME PART), the
  ;;           scheme, basic, digest or bearer, and the part refused, user,
  ;;           password or token, user for an empty user and password; for
  ;;           the other three, the scheme alone. No credentials string is
  ;;           ever a value or an irritant: a refusal names a secret by its
  ;;           part (the M7 plan, section 3.1)
  ;;   reason  one of curl-request-error-reasons
  (define-condition-type &curl-request-error &curl-error
    unchecked-make-curl-request-error curl-request-error?
    (field curl-request-error-field)
    (value curl-request-error-value)
    (reason curl-request-error-reason))

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
  ;; Why a transfer failed (M2 plan, section 5.3; M3 plan, section 3.4):
  ;;
  ;;   perform-failed   the transfer ended with a CURLcode, which
  ;;                    curl_multi_info_read gave the engine, and the write
  ;;                    callable recorded nothing
  ;;   body-limit       the callable refused a chunk past the body limit
  ;;   callback-raised  something raised inside the callable, which recorded it
  ;;   setopt-failed    curl_easy_setopt answered a code, for the option named
  ;;   unknown-option   the loaded libcurl does not know the option named
  ;;   no-handle        curl_easy_init answered NULL
  ;;   cancelled        the caller cancelled it before it ended (M3 plan,
  ;;                    section 3.5)
  ;;   stopped          its engine stopped before it ended
  ;;   pause-failed     curl_easy_pause answered other than 0 when the engine
  ;;                    resumed a streamed transfer, and no callable recorded
  ;;                    a reason inside the call, which would win; the code
  ;;                    is the call's (ADR-0012, amended 2026-10-29)
  ;;   body-length-mismatch
  ;;                    a streamed body ended short of its body-length, or a
  ;;                    piece was put past it, alike on every libcurl (the M6
  ;;                    plan, section 3.3): the read callable recorded it and
  ;;                    aborted the transfer, the code 42; or, for a piece
  ;;                    put once libcurl had read the length whole, and
  ;;                    called the read callable no more, the outcome reads
  ;;                    the put's refusal, the code libcurl's own, 0 among
  ;;                    them (ADR-0030, amended 2026-10-31)
  ;;   body-not-replayable
  ;;                    libcurl wanted to send a streamed body again, by a
  ;;                    rewind or a later attempt, once the read callable had
  ;;                    handed it a byte: the seek or the prerequest callable
  ;;                    recorded it and refused (ADR-0032)
  ;; A reason a callable recorded wins over libcurl's code, which the code
  ;; field still carries.
  (define curl-transfer-error-reasons
    '(perform-failed body-limit callback-raised setopt-failed unknown-option no-handle
      cancelled stopped pause-failed body-length-mismatch body-not-replayable))

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
  ;;                 body-length-mismatch or body-not-replayable,
  ;;                 CURLINFO_REQUEST_SIZE:
  ;;                 the bytes of request libcurl sent, its body's among
  ;;                 them, summed over every attempt it made, a resend on a
  ;;                 fresh connection after a dead one included, and 0 when
  ;;                 it sent none, or #f on a libcurl whose count is known
  ;;                 broken, 8.7.0 and 8.7.1 (ADR-0022, amended
  ;;                 2026-10-27); 0 for one refused while it was set up,
  ;;                 setopt-failed, unknown-option or no-handle, which sent
  ;;                 nothing; #f for one cancelled or stopped, taken apart
  ;;                 unread. Whether it is 0 is what M5's retry policy reads
  ;;                 to tell whether a request was sent: a failure's timings
  ;;                 move with the version, and this does not (ADR-0022,
  ;;                 amended 2026-10-26)
  ;;
  ;; Tests assert the reason, the code, the option, the recorded object and
  ;; the request size, and a text only where a version row pins it.
  (define-condition-type &curl-transfer-error &curl-error
    unchecked-make-curl-transfer-error curl-transfer-error?
    (reason curl-transfer-error-reason)
    (code curl-transfer-error-code)
    (option curl-transfer-error-option)
    (strerror curl-transfer-error-strerror)
    (error-buffer curl-transfer-error-error-buffer)
    (recorded curl-transfer-error-recorded)
    (request-size curl-transfer-error-request-size))

  ;; check-transfer-error : Symbol Symbol (Listof Symbol) -> Void
  ;; Refuses a REASON that is not in REASONS, as WHO, with an assertion
  ;; violation.
  (define (check-transfer-error who reason reasons)
    (unless (memq reason reasons)
      (assertion-violation who "not a reason a chez-curl transfer fails for here" reason)))

  ;; make-curl-transfer-error : Symbol (U Integer #f) (U String #f) (U String #f)
  ;;                            (U String #f) Any (U Natural #f) -> &curl-transfer-error
  ;; The base type, unclassed. Refuses a REASON that is not one of the
  ;; eleven with an assertion violation. It checks nothing else, so a code a
  ;; later libcurl answers still reaches the caller.
  (define (make-curl-transfer-error reason code option strerror error-buffer recorded
                                    request-size)
    (check-transfer-error 'make-curl-transfer-error reason curl-transfer-error-reasons)
    (unchecked-make-curl-transfer-error reason code option strerror error-buffer recorded
                                        request-size))

  ;; curl-transfer-error? : Any -> Boolean
  ;; curl-transfer-error-reason : &curl-transfer-error -> Symbol
  ;; curl-transfer-error-code : &curl-transfer-error -> (U Integer #f)
  ;; curl-transfer-error-option : &curl-transfer-error -> (U String #f)
  ;; curl-transfer-error-strerror : &curl-transfer-error -> (U String #f)
  ;; curl-transfer-error-error-buffer : &curl-transfer-error -> (U String #f)
  ;; curl-transfer-error-recorded : &curl-transfer-error -> Any
  ;; curl-transfer-error-request-size : &curl-transfer-error -> (U Natural #f)

  ;; --- the classes (ADR-0022) ------------------------------------------------------

  ;; curl-code-classes : (Listof (Pairof Symbol (Listof Positive-Integer)))
  ;; Each class, with the CURLcodes it names, by their names in (curl
  ;; private constants). A class is described in curl's words for its
  ;; codes, from libcurl-errors, never by a cause: one failure's code moves
  ;; with the version (ADR-0022, amended 2026-10-26).
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
  ;; with a code the class names, or, for too-large, body-limit too, with
  ;; any code.
  ;;
  ;; make-curl-timeout, make-curl-connect-error, make-curl-send-receive-error,
  ;; make-curl-tls-error, make-curl-protocol-error, make-curl-too-large :
  ;;   Symbol (U Integer #f) (U String #f) (U String #f) (U String #f) Any
  ;;   (U Natural #f) -> &curl-transfer-error
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
  ;; for too-large, body-limit too.
  (define (check-class who class reason code)
    (unless (or (and (eq? reason 'perform-failed) (eq? (curl-code-class code) class))
                (and (eq? class 'too-large) (eq? reason 'body-limit)))
      (assertion-violation who "not a reason and code this class takes" reason code)))

  (define (make-curl-timeout reason code option strerror error-buffer recorded request-size)
    (check-class 'make-curl-timeout 'timeout reason code)
    (unchecked-make-curl-timeout reason code option strerror error-buffer recorded
                                 request-size))

  (define (make-curl-connect-error reason code option strerror error-buffer recorded
                                   request-size)
    (check-class 'make-curl-connect-error 'connect reason code)
    (unchecked-make-curl-connect-error reason code option strerror error-buffer recorded
                                       request-size))

  (define (make-curl-send-receive-error reason code option strerror error-buffer recorded
                                        request-size)
    (check-class 'make-curl-send-receive-error 'send-receive reason code)
    (unchecked-make-curl-send-receive-error reason code option strerror error-buffer recorded
                                            request-size))

  (define (make-curl-tls-error reason code option strerror error-buffer recorded request-size)
    (check-class 'make-curl-tls-error 'tls reason code)
    (unchecked-make-curl-tls-error reason code option strerror error-buffer recorded
                                   request-size))

  (define (make-curl-protocol-error reason code option strerror error-buffer recorded
                                    request-size)
    (check-class 'make-curl-protocol-error 'protocol reason code)
    (unchecked-make-curl-protocol-error reason code option strerror error-buffer recorded
                                        request-size))

  (define (make-curl-too-large reason code option strerror error-buffer recorded request-size)
    (check-class 'make-curl-too-large 'too-large reason code)
    (unchecked-make-curl-too-large reason code option strerror error-buffer recorded
                                   request-size))

  ;; make-classed-transfer-error : Symbol (U Integer #f) (U String #f) (U String #f)
  ;;                               (U String #f) Any (U Natural #f) -> &curl-transfer-error
  ;; What a failed transfer raises (ADR-0022, amended 2026-10-26): for
  ;; perform-failed, the class its CODE has, or the base type for a code no
  ;; class names; for body-limit, too-large, whatever its code; for every
  ;; other reason, the base type, a setopt-failed whose code a class names
  ;; among them. A REASON not among the eleven is an assertion violation.
  (define (make-classed-transfer-error reason code option strerror error-buffer recorded
                                       request-size)
    (check-transfer-error 'make-classed-transfer-error reason curl-transfer-error-reasons)
    (let ((make (case (if (eq? reason 'body-limit)
                          'too-large
                          (and (eq? reason 'perform-failed) (curl-code-class code)))
                  ((timeout) make-curl-timeout)
                  ((connect) make-curl-connect-error)
                  ((send-receive) make-curl-send-receive-error)
                  ((tls) make-curl-tls-error)
                  ((protocol) make-curl-protocol-error)
                  ((too-large) make-curl-too-large)
                  (else make-curl-transfer-error))))
      (make reason code option strerror error-buffer recorded request-size)))

  ;; --- &curl-engine-error -------------------------------------------------------

  ;; curl-engine-error-reasons : (Listof Symbol)
  ;; Why an engine refused a message, or failed a transfer (M3 plan, sections
  ;; 3.4 and 3.7):
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
    (reason curl-engine-error-reason)
    (condition curl-engine-error-condition))

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
