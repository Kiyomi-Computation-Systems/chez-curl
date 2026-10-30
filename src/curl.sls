#!r6rs
;;; (curl): chez-curl's low-level library, the one public (curl ...) library
;;; (ADR-0007, ADR-0010).
;;;
;;; It reports the libcurl it loaded, makes requests and reads responses
;;; (ADR-0023), runs them on an engine, and hands back each one's token,
;;; which a caller awaits, or takes from a mailbox (ADR-0012, ADR-0021); and
;;; it carries chez-curl's conditions, a failed transfer's classes among
;;; them (ADR-0022). libcurl is loaded the first time a program reaches a
;;; binding that needs it: loaded-libcurl, or the request's, the
;;; response's, the engine's, the token's or the mailbox's, whose libraries
;;; import (curl private native); in a program that imports
;;; (curl) and references one, before the program's own body runs, so a
;;; guard in the program cannot catch its refusal. The conditions'
;;; bindings load nothing. A refused libcurl raises
;;; &curl-library-unavailable there, and again at every later reference:
;;; the load runs once per process (ADR-0002, ADR-0003).
;;; The report's accessors live apart, in (curl private libcurl-info), so a
;;; refusal's report can be read after the refusal.
(library (curl)
  (export
   ;; loaded-libcurl : -> Libcurl-Info
   ;; The libcurl this process loaded and accepted.
   loaded-libcurl

   ;; libcurl-info? : Any -> Boolean
   ;; libcurl-info-path : Libcurl-Info -> String
   ;; libcurl-info-source : Libcurl-Info -> Symbol
   ;; libcurl-info-version : Libcurl-Info -> String
   ;; libcurl-info-version-number : Libcurl-Info -> Natural
   ;; libcurl-info-features : Libcurl-Info -> Natural
   ;; libcurl-info-feature-names : Libcurl-Info -> (Listof (U Symbol Positive-Integer))
   ;; libcurl-info-ssl-version : Libcurl-Info -> (U String #f)
   ;; libcurl-info-host : Libcurl-Info -> (U String #f)
   ;; What it reports: the path loaded and where it came from, then
   ;; curl_version_info's version, version_num, features (as the word and
   ;; as names), ssl_version and host, as it answered them before
   ;; curl_global_init. On a libcurl with more than one TLS backend, Apple's,
   ;; ssl_version and the features then name its first backend, whatever the
   ;; init puts in use. See (curl private libcurl-info).
   libcurl-info? libcurl-info-path libcurl-info-source libcurl-info-version
   libcurl-info-version-number libcurl-info-features libcurl-info-feature-names
   libcurl-info-ssl-version libcurl-info-host

   ;; &curl-error: the base of every chez-curl condition, under &error.
   ;; curl-error? : Any -> Boolean
   &curl-error curl-error?

   ;; &curl-library-unavailable: libcurl was refused.
   ;; curl-library-unavailable? : Any -> Boolean
   ;; curl-library-unavailable-reason : &curl-library-unavailable -> Symbol
   ;; curl-library-unavailable-path : &curl-library-unavailable -> (U String #f)
   ;; curl-library-unavailable-source : &curl-library-unavailable -> (U Symbol #f)
   ;; curl-library-unavailable-detail : &curl-library-unavailable -> Any
   ;; curl-library-unavailable-candidates : &curl-library-unavailable
   ;;                                       -> (Listof String)
   ;; curl-library-unavailable-library : &curl-library-unavailable
   ;;                                    -> (U Libcurl-Info #f)
   ;; curl-library-unavailable-reasons : (Listof Symbol)
   ;; See (curl private conditions) for each field and reason.
   &curl-library-unavailable curl-library-unavailable?
   curl-library-unavailable-reason curl-library-unavailable-path
   curl-library-unavailable-source curl-library-unavailable-detail
   curl-library-unavailable-candidates curl-library-unavailable-library
   curl-library-unavailable-reasons

   ;; &curl-wrong-thread: an engine-owned handle used from another thread
   ;; (ADR-0012).
   ;; curl-wrong-thread? : Any -> Boolean
   ;; curl-wrong-thread-who : &curl-wrong-thread -> Symbol
   ;; curl-wrong-thread-expected : &curl-wrong-thread -> Integer
   ;; curl-wrong-thread-actual : &curl-wrong-thread -> Integer
   &curl-wrong-thread curl-wrong-thread?
   curl-wrong-thread-who curl-wrong-thread-expected curl-wrong-thread-actual

   ;; --- the request (ADR-0023) ---------------------------------------------
   ;; make-curl-request : String Symbol Any ... -> Request
   ;; (make-curl-request URL KEY VALUE ...): a request for URL, http:// or
   ;; https://, with these keys, each once at most, each left out taking its
   ;; default, libcurl's own:
   ;;   method              get, head, post, put, patch or delete; get
   ;;   headers             (Listof (Pairof String String)), Latin-1; ()
   ;;   body                Bytevector, or #f; #f. post, put and patch send an
   ;;                       empty one for #f; get and head refuse one
   ;;   user-agent          a non-empty Latin-1 string, or #f; #f
   ;;   timeout-ms          the whole transfer's bound, or #f; #f
   ;;   connect-timeout-ms  the connection phase's bound, its TLS handshake
   ;;                       among it, or #f; #f
   ;;   body-limit          the body's bound in bytes, or #f; #f
   ;;   ca-file             the only CA file to trust, or #f for the system
   ;;                       store; #f. A path beginning pkcs11:, in any
   ;;                       ASCII case, is refused: reach such a file as
   ;;                       ./pkcs11:... On any Guix libcurl, a submit
   ;;                       refuses a CA file, verify on, when SSL_CERT_FILE
   ;;                       or SSL_CERT_DIR was set at the load, which
   ;;                       would replace it, or add to it; and on macOS
   ;;                       with Apple's LibreSSL in use, which checks the
   ;;                       keychain when it fails: set
   ;;                       CURL_SSL_BACKEND=secure-transport
   ;;   verify              whether to verify the peer; #t
   ;;   proxy               environment, through the proxy http_proxy,
   ;;                       https_proxy or all_proxy names, by libcurl's
   ;;                       rules; or #f, direct; environment
   ;;   stream-buffer       the bytes of the response's body the token
   ;;                       buffers, a positive exact integer, read as it
   ;;                       arrives through the token; or #f, the whole body
   ;;                       in the response; #f. Refused beside a hatch's
   ;;                       HTTPAUTH or PROXYAUTH, or an Expect header whose
   ;;                       value holds 100-continue, as stream-with-rounds
   ;; A key it does not take, one given twice, and one with no value are
   ;; refused by name, as &curl-request-error, before anything else.
   ;; curl-request-with : Request Symbol Any ... -> Request
   ;; A new request, with the keys given replaced and the rest kept.
   ;; curl-request? : Any -> Boolean
   ;; curl-request-url : Request -> String
   ;; curl-request-method : Request -> Symbol
   ;; curl-request-headers : Request -> (Listof (Pairof String String))
   ;; curl-request-body : Request -> (U Bytevector #f)
   ;; curl-request-user-agent : Request -> (U String #f)
   ;; curl-request-timeout-ms : Request -> (U Positive-Integer #f)
   ;; curl-request-connect-timeout-ms : Request -> (U Positive-Integer #f)
   ;; curl-request-body-limit : Request -> (U Natural #f)
   ;; curl-request-ca-file : Request -> (U String #f)
   ;; curl-request-verify : Request -> Boolean
   ;; curl-request-proxy : Request -> (U 'environment #f)
   ;; curl-request-stream-buffer : Request -> (U Positive-Integer #f)
   make-curl-request curl-request-with curl-request?
   curl-request-url curl-request-method curl-request-headers curl-request-body
   curl-request-user-agent curl-request-timeout-ms curl-request-connect-timeout-ms
   curl-request-body-limit curl-request-ca-file curl-request-verify curl-request-proxy
   curl-request-stream-buffer

   ;; --- URLs (ADR-0008) ----------------------------------------------------
   ;; curl-url-part : String Symbol -> (U String Natural #f)
   ;; (curl-url-part URL PART): PART of URL, parsed by libcurl's URL API, as
   ;; it gives it back: url, the whole URL; scheme, user, password, host,
   ;; path, query, fragment or zoneid, a string, or #f for one the URL
   ;; lacks; or port, a natural, the scheme's default when the URL names
   ;; none. An IPv6 host comes without its zone ID, which zoneid gives.
   ;; Whether an empty user, password or query is "" or #f varies by
   ;; libcurl.
   ;; curl-url-append-query : String String -> String
   ;; (curl-url-append-query URL PART): URL with PART, already encoded,
   ;; appended to its query, after a & unless the query is empty or ends in
   ;; one; its fragment kept. PART goes out as written, on every libcurl
   ;; (ADR-0028).
   ;; curl-url-resolve : String (U String Bytevector) -> String
   ;; (curl-url-resolve BASE REFERENCE): REFERENCE resolved against BASE by
   ;; libcurl's URL API. A string is sent as UTF-8. A bytevector, a header's
   ;; bytes, a Location header's Latin-1 string as bytes, has each byte at
   ;; or below 0x20, 0x7F and each above encoded as upper-case %XX first, as
   ;; curl-url-with-fragment's has (ADR-0029, amended).
   ;; curl-url-with-fragment : String (U String Bytevector #f) -> String
   ;; (curl-url-with-fragment URL FRAGMENT): URL with its fragment replaced
   ;; by FRAGMENT, or cleared by #f or an empty one. A bytevector, a header's
   ;; bytes, has each byte at or below 0x20, 0x7F and each above encoded as
   ;; upper-case %XX; a string comes as a URL holds it. Alike on every
   ;; libcurl (ADR-0029).
   ;; Each refusal raises &curl-url-error: libcurl's, a URL holding U+0000 or
   ;; a bytevector 0x00, an answer whose bytes are not UTF-8, as libcurl's
   ;; decoding of a host's %XX can make, and a part that would not come back
   ;; as written, one holding #.
   curl-url-part curl-url-append-query curl-url-resolve curl-url-with-fragment

   ;; --- the response -------------------------------------------------------
   ;; curl-response? : Any -> Boolean
   ;; curl-response-status : Response -> Integer
   ;; curl-response-http-version : Response -> (U 'http/1.0 'http/1.1 'http/2 'http/3 Integer #f)
   ;; curl-response-effective-url : Response -> (U String #f)
   ;; curl-response-headers : Response -> (Listof (Pairof String String))
   ;; curl-response-body : Response -> (U Bytevector #f)
   ;; curl-response-timings : Response -> (Listof (Pairof Symbol Natural))
   ;; The timings are name-lookup, connect, tls-handshake, first-byte and
   ;; total, in that order, each the microseconds from the transfer's start
   ;; to that phase's end, and 0 for a phase the transfer skipped: the
   ;; handshake without TLS, and the first three on a connection reused. A
   ;; streamed response's body is #f: its token held the pieces.
   curl-response? curl-response-status curl-response-http-version
   curl-response-effective-url curl-response-headers curl-response-body
   curl-response-timings

   ;; --- the engine (ADR-0012) ----------------------------------------------
   ;; make-curl-engine : -> Engine
   ;; A fresh engine: a thread of its own, which runs every transfer
   ;; submitted to it. It loads libcurl first, on this thread.
   ;; curl-engine? : Any -> Boolean
   ;; curl-engine-stop : Engine -> Void
   ;; Completes every transfer the engine holds as stopped, frees all, and
   ;; returns once its thread has ended. A later stop returns at once, and a
   ;; later submit raises &curl-engine-error, stopped. An engine that failed
   ;; completed its transfers as failed when it did: a stop of it returns
   ;; once its thread has ended, and a submit raises its failure.
   ;; curl-submit : Engine Request [(U Mailbox #f) [(U (Token -> Any) #f)]] -> Token
   ;; Queues the request's transfer, a private copy of it checked on this
   ;; thread, and answers its token. With a mailbox, the token goes there
   ;; when done; with a callback too, a delivery from there calls it. A
   ;; callback without a mailbox is refused.
   ;; curl-request-check : Request -> Void
   ;; Runs the checks curl-submit makes of the request on this thread, and
   ;; raises what they raise, as a submit would: the headers' and the user
   ;; agent's, the CA file's and the environment's it loaded with, and the
   ;; URL's parse and scheme; its who is curl-request-check where a
   ;; submit's is curl-submit. It copies no body and queues nothing, so a
   ;; batch can be checked before any of it is submitted; an engine's own
   ;; state can still refuse the submit (ADR-0023, amended 2026-10-28). A
   ;; request shares its strings and lists with its caller, so the check
   ;; holds for them as they were when it ran: a submit checks its own
   ;; copies again, and refuses one changed since.
   make-curl-engine curl-engine? curl-engine-stop curl-submit curl-request-check

   ;; --- the token ----------------------------------------------------------
   ;; curl-token? : Any -> Boolean
   ;; curl-token-await : Token -> Response
   ;; Waits for the transfer, and answers its response, or raises what it
   ;; ended with. Any thread may await a token, any number of times.
   ;; curl-token-wait : Token Natural -> Boolean
   ;; Whether the transfer ends within the milliseconds given; it runs on
   ;; either way.
   ;; curl-token-cancel : Token -> Void
   ;; Ends the transfer as cancelled and returns at once: a queued one at
   ;; once, here, a live one by a message to its engine. One that has ended
   ;; keeps its outcome, and so does a live one whose engine is stopping or
   ;; failing, which ends it as stopped or failed.
   ;; curl-token-done? : Token -> Boolean
   ;; curl-token-outcome : Token -> (U Response Condition #f)
   ;; Once the transfer has ended, the response await answers, or the
   ;; condition it raises, the same object, as data; #f before. It never
   ;; waits, and never raises.
   ;; Every wait sleeps between its looks, so Ctrl-C reaches it, and none may
   ;; run inside a critical section.
   curl-token? curl-token-await curl-token-wait curl-token-cancel curl-token-done?
   curl-token-outcome

   ;; --- a streamed response (ADR-0030) ----------------------------------------
   ;; A token whose request has a stream-buffer holds its response's body as
   ;; pieces, at most stream-buffer bytes or one chunk of libcurl's, 16 KiB,
   ;; whichever is more, and the piece a reader holds. A full buffer pauses
   ;; the transfer; a read that drains it to half resumes it. Over HTTP/1.1
   ;; the server's writes then stall; over HTTP/2 a paused stream beside an
   ;; active one keeps receiving, into libcurl's memory, up to its window.
   ;; The transfer's timeout runs while it is paused. Each wait answers as
   ;; data and never raises the transfer's failure, which the outcome holds;
   ;; the port alone raises it. A token whose request does not stream its
   ;; response refuses each of these, an assertion violation.
   ;; curl-token-head-wait : Token Natural -> Boolean
   ;; Whether the final head has arrived, or the transfer has ended, within
   ;; the milliseconds given.
   ;; curl-token-head : Token -> (U Head #f)
   ;; The final head once it has arrived; never waits. A 1xx head and a
   ;; proxy's CONNECT head are passed over.
   ;; curl-head? : Any -> Boolean
   ;; curl-head-status : Head -> Integer
   ;; curl-head-http-version : Head -> (U 'http/1.0 'http/1.1 'http/2 'http/3 Integer #f)
   ;; curl-head-headers : Head -> (Listof (Pairof String String))
   ;; As the response's accessors read them.
   ;; curl-token-next-piece : Token Natural -> (U Bytevector Eof #f)
   ;; The next piece, a bytevector of a byte or more, the caller's to keep;
   ;; the eof object once every piece is taken and the transfer has ended,
   ;; however it ended; #f once the milliseconds given pass.
   ;; curl-token-body-port : Token -> Binary-Input-Port
   ;; A binary input port over the pieces, made once per token, read and
   ;; closed only on the thread that made it: another thread's close raises
   ;; &curl-wrong-thread, and so does any read of its that needs more than
   ;; the port had buffered; bytes the port had buffered go to whichever
   ;; thread reads them, and a get-bytevector-n, -n! or -all from another
   ;; thread that takes them, then raises, loses them. At the end it answers the end
   ;; for a response, every time, and raises the failure for one that
   ;; failed, every time. Its close cancels the transfer. A port never
   ;; closed leaves its transfer paused until its timeout or its engine's
   ;; stop. A failure raised in get-bytevector-n, -n! or -all loses the
   ;; bytes that call had read; get-bytevector-some, -some! and get-u8 lose
   ;; none.
   curl-token-head-wait curl-token-head curl-head? curl-head-status curl-head-http-version
   curl-head-headers curl-token-next-piece curl-token-body-port

   ;; --- the mailbox (ADR-0021) ---------------------------------------------
   ;; make-curl-mailbox : -> Mailbox
   ;; An empty mailbox, which collects finished tokens, from any number of
   ;; engines, oldest first.
   ;; curl-mailbox? : Any -> Boolean
   ;; curl-mailbox-take : Mailbox Natural -> (U Token #f)
   ;; The next finished token, taken out, waiting up to the milliseconds
   ;; given, or #f. It calls no callback.
   ;; curl-mailbox-deliver : Mailbox Natural -> (U Token #f)
   ;; Takes as curl-mailbox-take does, then calls the token's callback, if it
   ;; has one, with the token, on this thread; answers the token, or #f. The
   ;; callback's raise leaves through it.
   ;; A take that an interrupt handler escapes from can lose the token's
   ;; place in the mailbox, never its outcome: keep the tokens, and await
   ;; them, where handlers can escape.
   make-curl-mailbox curl-mailbox? curl-mailbox-take curl-mailbox-deliver

   ;; --- what a caller can meet ---------------------------------------------
   ;; &curl-embedded-nul: a string C would read short, holding U+0000.
   ;; curl-embedded-nul? : Any -> Boolean
   ;; curl-embedded-nul-string : &curl-embedded-nul -> String
   &curl-embedded-nul curl-embedded-nul? curl-embedded-nul-string

   ;; &curl-url-error: a URL refused (ADR-0008).
   ;; curl-url-error? : Any -> Boolean
   ;; curl-url-error-input : &curl-url-error -> String
   ;; curl-url-error-reason : &curl-url-error -> (U Symbol #f)
   ;; curl-url-error-code : &curl-url-error -> (U Integer #f)
   ;; curl-url-error-message : &curl-url-error -> (U String #f)
   &curl-url-error curl-url-error? curl-url-error-input curl-url-error-reason
   curl-url-error-code curl-url-error-message

   ;; &curl-request-error: a request's key or field refused.
   ;; curl-request-error? : Any -> Boolean
   ;; curl-request-error-field : &curl-request-error -> Symbol
   ;; curl-request-error-value : &curl-request-error -> Any
   ;; curl-request-error-reason : &curl-request-error -> Symbol
   ;; curl-request-error-reasons : (Listof Symbol)
   ;; See (curl private conditions) for each field and reason.
   &curl-request-error curl-request-error? curl-request-error-field
   curl-request-error-value curl-request-error-reason curl-request-error-reasons

   ;; &curl-transfer-error: a transfer that failed (ADR-0022).
   ;; curl-transfer-error? : Any -> Boolean
   ;; curl-transfer-error-reason : &curl-transfer-error -> Symbol
   ;; curl-transfer-error-code : &curl-transfer-error -> (U Integer #f)
   ;; curl-transfer-error-option : &curl-transfer-error -> (U String #f)
   ;; curl-transfer-error-strerror : &curl-transfer-error -> (U String #f)
   ;; curl-transfer-error-error-buffer : &curl-transfer-error -> (U String #f)
   ;; curl-transfer-error-recorded : &curl-transfer-error -> Any
   ;; curl-transfer-error-request-size : &curl-transfer-error -> (U Natural #f)
   ;;   the bytes of request sent: 0 when none was; #f when it is unknown,
   ;;   a transfer cancelled or stopped, or one that ran on libcurl 8.7.0 or
   ;;   8.7.1, whose count is broken, the Mac's among them
   ;; curl-transfer-error-reasons : (Listof Symbol)
   ;; See (curl private conditions) for each field and reason.
   &curl-transfer-error curl-transfer-error? curl-transfer-error-reason
   curl-transfer-error-code curl-transfer-error-option curl-transfer-error-strerror
   curl-transfer-error-error-buffer curl-transfer-error-recorded
   curl-transfer-error-request-size curl-transfer-error-reasons

   ;; Its classes, each a &curl-transfer-error, by libcurl's code, for
   ;; perform-failed: a code no class names raises the base type.
   ;; curl-timeout? : Any -> Boolean            28
   ;; curl-connect-error? : Any -> Boolean      5, 6, 7, 45, 96, 97
   ;; curl-send-receive-error? : Any -> Boolean 18, 52, 55, 56
   ;; curl-tls-error? : Any -> Boolean          35, 53, 54, 58, 59, 60, 64, 66,
   ;;                                           77, 80, 82, 83, 90, 91, 98, 101
   ;; curl-protocol-error? : Any -> Boolean     1, 8, 16, 61, 92, 95
   ;; curl-too-large? : Any -> Boolean          63, 100, and the body limit
   &curl-timeout curl-timeout? &curl-connect-error curl-connect-error?
   &curl-send-receive-error curl-send-receive-error? &curl-tls-error curl-tls-error?
   &curl-protocol-error curl-protocol-error? &curl-too-large curl-too-large?

   ;; &curl-engine-error: an engine that stopped, or failed.
   ;; curl-engine-error? : Any -> Boolean
   ;; curl-engine-error-reason : &curl-engine-error -> Symbol
   ;; curl-engine-error-condition : &curl-engine-error -> Any
   ;;   for failed, what raised inside the engine; #f for stopped
   ;; curl-engine-error-reasons : (Listof Symbol)
   ;; See (curl private conditions) for each reason.
   &curl-engine-error curl-engine-error? curl-engine-error-reason
   curl-engine-error-condition curl-engine-error-reasons)
  (import (curl private require-threaded)
          (rnrs)
          (curl private conditions)
          (curl private engine)
          (curl private libcurl-info)
          (curl private native)
          (curl private transfer)
          (curl private url)))
