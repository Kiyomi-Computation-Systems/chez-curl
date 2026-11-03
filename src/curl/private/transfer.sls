#!r6rs
;;; (curl private transfer): a request, and its transfer on an engine's
;;; thread (M2 plan, sections 3 and 5; M3 plan, sections 3.1 and 5.2; M4
;;; plan, sections 3.2 to 3.4). (curl) exports the request and the
;;; response; (curl private engine) runs the transfer.
;;;
;;; A request is made from a property list, (make-curl-request URL KEY
;;; VALUE ...), and curl-request-with makes a new one with keys replaced
;;; (ADR-0023). An unknown key, a key with no value and a repeated key are
;;; refused by name before anything else is checked. Then its fields are
;;; checked, before anything native: wrong types are assertion violations,
;;; and a body with get or head, a header or a user agent libcurl would
;;; send otherwise than asked, or a CA file's path holding U+0000, is a
;;; &curl-request-error. Header strings are Latin-1, both ways (ADR-0001,
;;; amended 2026-10-23); a CA file's path is UTF-8, as every other string.
;;; A request holds no procedure: its private fields, a fault and whether
;;; to follow redirects, are data, set by private constructors alone (M3
;;; plan, section 3.6; M4 plan, section 3.2).
;;;
;;; A request holds the caller's strings, lists and body, which stay
;;; mutable. So a submit, on the caller's thread, checks nothing it does
;;; not own: prepare-transfer takes a plan, fresh pairs and fresh strings
;;; for the URL, the headers, the user agent and the CA file, and a fresh
;;; copy of the body, checks the plan by the constructor's rules, and
;;; parses the plan's URL and checks its scheme, freeing that CURLU before
;;; it returns (ADR-0008, amended
;;; 2026-10-24). Every refusal raises there, before anything is queued. A
;;; request changed after it was made is refused then; a change it takes is
;;; sent as changed. The engine sends only the plan.
;;;
;;; A body (M4 plan, section 3.2). post, put and patch always send one,
;;; empty when the request has none, and delete sends one only when it has
;;; one: POSTFIELDSIZE_LARGE at its length, then COPYPOSTFIELDS at a counted
;;; copy of it, which libcurl copies and which is freed once setopt
;;; returns. An empty body is a block of one byte, never NULL, as a
;;; defence: with a size of 0 libcurl reads nothing either way, but NULL
;;; tells its setopt to send the body through its read callback, whose
;;; default reads stdin, and its setopt allocates a byte for a size of 0
;;; "to mark that postfields is used rather than read function"
;;; (lib/setopt.c, 7.85.0).
;;; put, patch and delete set CUSTOMREQUEST to their names. libcurl adds
;;; Content-Type: application/x-www-form-urlencoded to every body, and
;;; Expect: 100-continue past 1 MiB, then waits a second for a server that
;;; never answers it; so a request that sends a body also sends "Content-Type:"
;;; and "Expect:", which take libcurl's own away, unless it names a header
;;; of that name itself, which replaces libcurl's (measured on five
;;; libcurls, the M4 plan, section 4.1). Nothing follows a redirect:
;;; FOLLOWLOCATION is owned, and set only for the private follow field.
;;;
;;; A finished transfer's response carries its timings, read as curl_off_t
;;; microseconds through native's off_t reader. A failed one carries its
;;; request size, CURLINFO_REQUEST_SIZE, and raises its code's class
;;; (ADR-0022, amended 2026-10-26).
;;;
;;; On the engine's thread (ADR-0012), start-transfer! makes, in order:
;;;
;;;   - the transfer's key, registered in a table write-body reads, counted
;;;     as transfer;
;;;   - the URL's CURLU handle, the plan's URL parsed again, its scheme
;;;     checked again;
;;;   - the error buffer, a counted block of CURL_ERROR_SIZE bytes, zeroed
;;;     through the checked copy;
;;;   - the header list, a string list of Latin-1 copies, counted as slist;
;;;   - the easy handle, with every setting set-transfer-options! makes.
;;;
;;; The engine adds the easy handle to its multi handle. Once
;;; curl_multi_info_read says the transfer is done, finish-transfer reads
;;; what it ended with, and once the engine has removed the handle,
;;; free-transfer! frees each object the other way round: the easy handle
;;; before the header list, the error buffer and the CURLU it used. A
;;; transfer cancelled, or stopped, is freed the same way, unread. Each
;;; object is made, and recorded in the transfer's live record, in one
;;; critical section, and freed, and cleared, in another (ADR-0013, amended
;;; 2026-10-23). Each mutex is held through locked, in a critical section,
;;; and no hold waits.
;;;
;;; Options are named, never numbered: their ids and CURLOT types come from
;;; the loaded library, through curl-easy-option, cached once per process
;;; behind a mutex (ADR-0001, decision 2). Setting one checks the value
;;; against its type, sends it through the binding option-bindings names
;;; for that type, and judges the code libcurl answers by setopt-accepted?:
;;; CURLE_OK, or CURLE_NOT_BUILT_IN for a clear. Every option a request
;;; field sets is named once, in request-field-options, where a field may
;;; name several.
;;;
;;; TLS (ADR-0018). Every transfer, an http:// one too, makes the settings
;;; tls-settings computes from its plan's CA file and verification, as
;;; data, by one call, set-tls-options!, after the request's other settings
;;; and before the hatch's: SSL_VERIFYPEER and SSL_VERIFYHOST at 1 and
;;; 2, or both 0 with verification off; then, with a CA file, CAINFO at its
;;; path and CAPATH cleared, so the CA file is the request's only trust
;;; anchor, whatever CA directory the build defaults to. A backend with no
;;; CA directory answers the clear CURLE_NOT_BUILT_IN, which is taken. A CA
;;; file of #f is libcurl's system store, as built, and sets neither. The
;;; four names stand in this file only in request-field-options.
;;;
;;; The HTTP version (ADR-0034). A request's http-version makes the settings
;;; version-settings computes, as data, HTTP_VERSION alone or nothing, set
;;; with the request's other settings, before tls-settings'. A submit
;;; refuses http/2-prior-knowledge beside an https:// URL, once the URL is
;;; parsed, as prior-knowledge-over-https. No transfer sets PIPEWAIT.
;;;
;;; Credentials (ADR-0036, amended twice). A request's credentials, one
;;; scheme's, Basic, Digest or Bearer, make the settings
;;; credentials-settings computes, as data, HTTPAUTH at the scheme's bit,
;;; then USERNAME and PASSWORD, or XOAUTH2_BEARER, each a UTF-8 string, set
;;; with the request's other settings, before tls-settings'. The record
;;; keeps a fresh copy, checked, and answers a fresh copy, so no caller
;;; holds what is sent. Its shape is checked as the request is made, and
;;; again at submit on the submit's own copies: a control char in any
;;; part, or a colon in a Basic user, credentials-bytes; nothing to send,
;;; credentials-empty; an Authorization header beside it,
;;; credentials-beside-authorization; Digest beside a streamed body or
;;; response, digest-with-stream. A submit refuses it beside a URL whose
;;; user or password part libcurl reports, once the URL is parsed, as
;;; credentials-beside-userinfo. No refusal names a credentials string:
;;; each names the scheme, and the part refused. Every transfer pins
;;; MAXREDIRS at 30, which bounds the follows libcurl makes inside a
;;; transfer, an auth round's, a stale round's and a 417's resend among
;;; them; never its retry of a request a dead or refused connection lost.
;;;
;;; The environment (ADR-0024). Guix's 8.20.0 writes SSL_CERT_FILE over
;;; CAINFO and SSL_CERT_DIR over the cleared CAPATH when a transfer starts,
;;; after every setopt, as they were at curl_global_init. So a submit
;;; refuses a CA file, with verification on, as environment-override, on a
;;; libcurl guix-ca-overrides names, when either was set as it loaded: the
;;; native layer records both there, the file the libcurl is mapped from,
;;; and whether that file holds Guix's patch's literal, so a copy out of
;;; the store is Guix's too. A CA file's path beginning pkcs11:, in any ASCII case, is refused
;;; whenever it is checked, as pkcs11-url: GnuTLS reads it as a PKCS#11
;;; URL. The proxy variables are libcurl's to read; a proxy of #f sets
;;; PROXY to "", which reads none of them.
;;;
;;; A proxy given by URL (ADR-0037, amended twice; the M7 plan, section
;;; 3.4). A request's proxy may be a URL string, copied as the request is
;;; made, the copy what every later check and use reads. A submit parses it
;;; with CURLU_NON_SUPPORT_SCHEME, so chez-curl judges its scheme alike on
;;; every libcurl, and refuses, as WHO, field proxy, value the symbol proxy,
;;; never the URL, which can hold a password: a URL libcurl cannot parse,
;;; or whose user or password holds a % not followed by two hex digits,
;;; proxy-url; a scheme but http or https, A to Z folded, proxy-scheme; a
;;; path but /, a query or a fragment, proxy-url-parts; then the userinfo,
;;; percent-decoded here from the parts libcurl gives back still encoded,
;;; by the server credentials' rules (ADR-0036, decisions 5 to 7), value
;;; (proxy PART): a decoded control byte, bytes that are not UTF-8, or a
;;; colon in the user, credentials-bytes; a user and a password both
;;; empty, credentials-empty. A decoded control byte sent 7.85.0 and 8.5.0
;;; around the proxy, direct. PROXY gets the URL libcurl gives back, its
;;; scheme's port set when it names none, and NOPROXY "", so no variable
;;; sends the transfer direct. proxy-ca-file and proxy-verify are an
;;; https:// proxy URL's alone, PROXY_CAINFO with PROXY_CAPATH cleared, and
;;; the two verify switches, refused beside any other proxy as
;;; proxy-tls-without-https-proxy, and a proxy CA file refused against the
;;; environment as a CA file is. proxy-settings computes them all, as data.
;;; A caller's Proxy-Authorization header is refused, as is prior knowledge
;;; beside a proxy URL, an https:// URL through an https:// proxy where TLS
;;; inside TLS stalls, tls-in-tls-stall?'s list, and an https:// proxy URL
;;; on a libcurl built without HTTPS-proxy support, which would write the
;;; URL whole into its error buffer. Before libcurl 8.19.0
;;; an https:// URL's tunnel through a proxy URL sets FRESH_CONNECT, and
;;; with userinfo FORBID_REUSE too, unshared-tunnel-settings': 7.85.0 let a
;;; later request ride a pooled tunnel another user had opened
;;; (CVE-2026-3784). And before 8.19.0 a transfer through a proxy URL that
;;; holds userinfo stops its engine's multiplexing, stops-multiplexing?'s,
;;; for good: 7.85.0 let a transfer through the environment's proxy ride a
;;; live authenticated tunnel as a second HTTP/2 stream (ADR-0037, decision
;;; 11). A failed transfer carries the status a proxy refused
;;; its CONNECT with, CURLINFO_HTTP_CONNECTCODE, when it is no 2xx.
;;;
;;; The callables (M2 plan, section 3.5; ADR-0030): write-body for every
;;; transfer, and read-head, the header callable, for a streamed response
;;; alone. Each is __collect_safe, since curl_multi_perform and
;;; curl_easy_pause, where they fire, are (ADR-0013, accepted 2026-10-24),
;;; locked where it is defined and never unlocked, and handed the
;;; transfer's key, an integer, as its WRITEDATA or HEADERDATA, so no Scheme
;;; object crosses into C. Neither runs a procedure a caller supplied
;;; (ADR-0012, decision 4). write-body logs each chunk libcurl hands it, its
;;; length, the thread it ran on and what became of it, as data the engine
;;; hands the token; for a stream, a count of each verdict and its threads.
;;; No raise leaves either: its whole body runs under a guard that records
;;; anything raised against the key and returns 0. libcurl then answers
;;; CURLE_WRITE_ERROR, 23, and the transfer fails with what was recorded. A
;;; request's fault plants such a raise, at the chunk it names. The body
;;; limit takes the same path: CURLOPT_MAXFILESIZE_LARGE is the limit plus
;;; one (M2 plan, section 5.3), so a declared length past that is refused
;;; before its body, and the callable refuses the first byte past the limit
;;; itself, on every libcurl, a stream's bytes counted as a whole body's.
;;;
;;; A streamed response (ADR-0030; the M6 plan, sections 3.2 to 3.5): a
;;; request's stream-buffer gives each submit a stream of its own, made
;;; with its plan. write-body fills its bounded buffer, a queue of pieces,
;;; each a fresh bytevector the checked copy filled once, and answers
;;; CURL_WRITEFUNC_PAUSE when it is full, the check and the receive bit in
;;; one hold of the stream's mutex; read-head publishes the first final
;;; head. A taker leaves a piece in place inside its look's hold and removes
;;; it after, writing fields only the taker writes; every look decides the
;;; resume. The engine's token operations take from it.
;;;
;;; The hatch (ADR-0009; the M4 plan, section 3.7): curl-request-with-options,
;;; which (curl unsupported) exports, attaches options to a request by name.
;;; Each is checked as it is attached, on the caller's thread, against the
;;; loaded libcurl's own table: a type that hands libcurl no address of the
;;; caller's, long, enumerated values, off_t, a string, a string list or a
;;; blob; a value that fits it, no string holding U+0000, CR or LF; and
;;; none chez-curl owns, nor an owned setting's twin, compared by id. The
;;; request keeps a copy of each value, the one checked, so a submit has
;;; nothing of the hatch's to check, and the engine sets the copies last,
;;; after every option chez-curl sets itself. It took the place of M2's
;;; and M3's test seam, curl-engine-submit-with, which took long,
;;; enumerated-value and off_t options alone (ADR-0009, amended 2026-10-27).
;;;
;;; The pins, ADR-0003's PROTOCOLS_STR and REDIR_PROTOCOLS_STR at
;;; "http,https", NOSIGNAL at 1 and ADR-0036's MAXREDIRS at 30, which
;;; bounds libcurl's follows inside a transfer, are pinned-options, set by one call,
;;; set-pinned-options!, the first form of set-transfer-options!. With
;;; them, ADR-0019's QUICK_EXIT at 1, quick-exit-pin, where the loaded
;;; libcurl knows it, from 7.87.0: a transfer taken apart while its name
;;; lookup stalls then leaves the resolver thread behind, rather than wait
;;; for it, up to 10 s, holding the engine. pinned-settings computes the
;;; whole list as data. An engine made without it, a private test seam,
;;; passes start-transfer! #f, and the pins are set alone. Their names, and
;;; the deprecated bitmasks', stand in this file only as data, in
;;; pinned-options, quick-exit-pin and owned-option-names.
;;;
;;; It imports foreign-callable, foreign-callable-entry-point and
;;; lock-object, which check-seam lets this library alone import (ADR-0007,
;;; M2 plan, section 3.6).
(library (curl private transfer)
  (export make-curl-request curl-request-with curl-request?
          curl-request-url curl-request-method curl-request-headers curl-request-body
          curl-request-user-agent curl-request-timeout-ms curl-request-connect-timeout-ms
          curl-request-body-limit curl-request-ca-file curl-request-verify curl-request-proxy
          curl-request-http-version version-settings curl-request-credentials credentials-settings
          curl-request-proxy-ca-file curl-request-proxy-verify proxy-settings
          unshared-tunnel-settings unshared-tunnel-floor tls-in-tls-stalls tls-in-tls-stall?
          percent-decoded connect-status check-proxy-url plan-proxy plan-tunnel
          stops-multiplexing? plan-unmultiplex https-proxy-supported? check-https-proxy
          request-field-names
          curl-request-fault curl-request-follow curl-request-with-fault curl-request-following
          request-keys request-methods sent-header-lines timing-infos
          prepare-transfer curl-request-check start-transfer! finish-transfer free-transfer!
          live-transfer-easy live-transfer-chunks transfer-ended planted-fault transfers-started
          abandon-transfer-easy!
          curl-response? curl-response-status curl-response-http-version
          curl-response-effective-url curl-response-headers curl-response-body
          curl-response-timings
          option-bindings option-binding option-setter http-version-symbol bytes->latin-1 pinned-options
          request-field-options owned-option-names live-transfer-count cached-option-names
          tls-settings setopt-accepted? quick-exit-pin pinned-settings quick-exit-known?
          quick-exits-set guix-ca-overrides ca-overridden? pkcs11-prefix? overriding-variables
          keychain-fallback? request-size-unreliable reported-request-size
          curl-request-with-options hatch-types option-named hatch-settings-of
          curl-request-stream-buffer
          curl-head? curl-head-status curl-head-http-version curl-head-headers curl-head-body-asked?
          plan-stream live-transfer-stream response-stream? stream-lock stream-limit stream-look!
          stream-remove! stream-clear-pause! stream-resumed! stream-paused? stream-head
          stream-stats resume-failure stream-verdicts expect-continue? ascii-folded
          curl-request-with-head-fault planted-head-fault stream-plant-stall! stream-stall-state
          curl-request-body-length plan-upload upload? upload-lock upload-buffer-limit upload-put!
          upload-end! upload-room? upload-count upload-stats upload-verdicts clear-pauses!
          live-transfer-paused? resumed! method-settings sends-body? live-transfer-upload
          plan-body-length curl-request-with-upload-fault planted-upload-fault upload-plant-split!
          upload-split-commit!)
  (import (curl private require-threaded)
          (rnrs)
          (rnrs mutable-strings)
          (rnrs mutable-pairs)
          (only (chezscheme) critical-section foreign-callable foreign-callable-entry-point
                lock-object make-mutex with-mutex foreign-sizeof get-thread-id current-time
                time-second time-nanosecond make-time sleep)
          (curl private conditions)
          (curl private constants)
          (curl private counters)
          (curl private memory)
          (curl private native)
          (only (curl private libcurl-info) libcurl-info-path libcurl-info-version
                libcurl-info-version-number libcurl-info-features)
          (curl private url))

  ;; --- ranges -------------------------------------------------------------------

  ;; signed-range? : Any Natural -> Boolean
  ;; X is an exact integer a signed C integer of BYTES bytes holds.
  (define (signed-range? x bytes)
    (let ((half (expt 2 (- (* 8 bytes) 1))))
      (and (integer? x) (exact? x) (<= (- half) x) (< x half))))

  ;; long? : Any -> Boolean
  (define (long? x) (signed-range? x (foreign-sizeof 'long)))

  ;; off-t? : Any -> Boolean
  ;; curl_off_t is 64 bits on every platform chez-curl supports.
  (define (off-t? x) (signed-range? x 8))

  ;; pointer? : Any -> Boolean
  ;; X is an exact natural a pointer holds.
  (define (pointer? x)
    (and (integer? x) (exact? x) (<= 0 x) (< x (expt 2 (* 8 (foreign-sizeof 'void*))))))

  ;; --- the request ------------------------------------------------------------------

  ;; tchar? : Char -> Boolean
  ;; RFC 9110, section 5.6.2: ! # $ % & ' * + - . ^ _ ` | ~, DIGIT and ALPHA,
  ;; ASCII alone.
  (define (tchar? c)
    (or (char<=? #\a c #\z) (char<=? #\A c #\Z) (char<=? #\0 c #\9)
        (and (memv c '(#\! #\# #\$ #\% #\& #\' #\* #\+ #\- #\. #\^ #\_ #\` #\| #\~)) #t)))

  ;; token? : String -> Boolean
  ;; A non-empty string of tchars.
  (define (token? s)
    (and (> (string-length s) 0)
         (let loop ((i 0))
           (or (= i (string-length s))
               (and (tchar? (string-ref s i)) (loop (+ i 1)))))))

  ;; value-fault : String -> (U Symbol #f)
  ;; The reason S is refused as a header value or a user agent, read left to
  ;; right, its first offending char deciding: U+0000 embedded-nul, CR or LF
  ;; line-break, a char above U+00FF not-latin-1; #f when none offends.
  (define (value-fault s)
    (let ((n (string-length s)))
      (let loop ((i 0))
        (and (< i n)
             (let ((code (char->integer (string-ref s i))))
               (cond ((= code 0) 'embedded-nul)
                     ((or (= code 10) (= code 13)) 'line-break)
                     ((> code 255) 'not-latin-1)
                     (else (loop (+ i 1)))))))))

  ;; surrounding? : Char -> Boolean
  ;; SP, HTAB, VT or FF: whitespace libcurl trims from a value's ends.
  (define (surrounding? c)
    (and (memv (char->integer c) '(32 9 11 12)) #t))

  ;; value-problem : String -> (U Symbol #f)
  ;; value-fault's answer; when it has none, surrounding-whitespace for a
  ;; value whose first or last char is SP, HTAB, VT or FF. RFC 9110 field
  ;; values have none there, and libcurl drops a value of whitespace alone,
  ;; and with Accept, its own header too. Interior whitespace is a value's.
  (define (value-problem s)
    (or (value-fault s)
        (let ((n (string-length s)))
          (and (> n 0)
               (or (surrounding? (string-ref s 0)) (surrounding? (string-ref s (- n 1))))
               'surrounding-whitespace))))

  ;; refuse-field : Symbol Symbol String Symbol -> Nothing
  (define (refuse-field who field value reason)
    (raise (condition (make-curl-request-error field value reason)
                      (make-who-condition who)
                      (make-message-condition
                       (case reason
                         ((not-a-token) "a header name must be an RFC 9110 token")
                         ((embedded-nul) "a header string holds U+0000, which C would read as its end")
                         ((line-break) "a header string holds CR or LF, which would end its line")
                         ((not-latin-1) "a header string holds a char above U+00FF, which has no Latin-1 byte")
                         ((surrounding-whitespace) "a header string starts or ends with whitespace, which libcurl trims")
                         ((duplicates-field) "a User-Agent header beside the user agent field, which libcurl would let win, or a second Host header, which libcurl would drop")
                         ((framing-header) "a Content-Length or Transfer-Encoding header: libcurl frames the message, from the body it is handed")
                         ((unknown-key) "not a key a request takes")
                         ((repeated-key) "a key given twice")
                         ((missing-value) "a key given last, with no value after it")
                         ((stream-with-rounds) "a streamed response takes one request in its transfer: follow and an Expect of 100-continue would make a second, whose head the stream would not publish")
                         ((body-length-without-stream) "a body-length is a streamed body's length: give it with body stream, or leave it #f; libcurl frames a whole body by its own length")
                         ((prior-knowledge-over-https) "HTTP/2 by prior knowledge is for http:// URLs alone: over https://, http/2 gets HTTP/2 by ALPN")
                         ((credentials-bytes) "a credentials string holds a control char, U+0000 to U+001F or U+007F, which libcurl would write into its header unescaped, or a Basic user name holds a colon, where RFC 7617 ends the user")
                         ((credentials-empty) "credentials with nothing to send: a Bearer token, or a user and a password, that are all empty")
                         ((credentials-beside-userinfo) "credentials beside a URL that holds a user or a password: give them once, by the credentials key or in the URL")
                         ((credentials-beside-authorization) "credentials beside an Authorization header: libcurl would send one of the two, or both")
                         ((digest-with-stream) "Digest credentials beside a streamed body or response: Digest makes a second request inside the transfer, which a stream cannot follow; Basic and Bearer send one")
                         ((prior-knowledge-through-proxy) "HTTP/2 by prior knowledge beside a proxy URL: libcurl ignores prior knowledge through a proxy that does not tunnel, and sends HTTP/1.1")
                         ((proxy-url) "a proxy URL libcurl cannot parse, or that names no scheme, or whose user or password holds a % not followed by two hex digits")
                         ((proxy-scheme) "a proxy URL's scheme is http or https")
                         ((proxy-url-parts) "a proxy URL names a host and a port alone: no path but /, no query and no fragment")
                         ((proxy-authorization-header) "a Proxy-Authorization header: inside a tunnel libcurl sends it to the origin; give a proxy's credentials in its URL")
                         ((proxy-tls-without-https-proxy) "a proxy CA file, or a proxy's verification off, beside a proxy that is no https:// URL, which has no TLS of its own to set")
                         ((proxy-tls-in-tls) "an https:// URL through an https:// proxy, on a libcurl where TLS inside TLS stalls until the transfer's timeout")
                         ((https-proxy-unsupported) "an https:// proxy URL on a libcurl built without HTTPS-proxy support, which would refuse it and write the whole URL, its password with it, into its error buffer")
                         (else "a body with get or head, which send none")))
                      (make-irritants-condition (list value)))))

  ;; snapshot : Symbol Any Any -> (Pairof (Listof (Pairof String String)) (U String #f))
  ;; HEADERS and USER-AGENT as fresh pairs and fresh strings, checked, in
  ;; order: what WHO may send. A wrong type is an assertion violation from
  ;; WHO: headers that are no list of (NAME . VALUE) strings, or a user
  ;; agent that is neither a non-empty string nor #f. Then each header's
  ;; name, which must be a token; its value, value-problem's rules; a name
  ;; User-Agent, in any case, beside a user agent, which is
  ;; duplicates-field: libcurl would send the header, and drop the field;
  ;; and a second name Host, in any case, duplicates-field too: libcurl
  ;; sends only the first; and a name Content-Length or Transfer-Encoding,
  ;; in any case, framing-header: libcurl frames the message, from the body
  ;; it is handed. A name Proxy-Authorization, A to Z folded, is refused as
  ;; proxy-authorization-header right after the name's token check, before
  ;; its value is read, so the refusal names the header, never its value,
  ;; a proxy's secret: inside a tunnel libcurl sends a caller's
  ;; Proxy-Authorization to the origin, and a proxy's credentials are its
  ;; URL's userinfo (ADR-0037, decision 4).
  ;; Then the user agent, value-problem's rules. Each refusal is a
  ;; &curl-request-error naming the field; a header value's names its
  ;; header's name, never the value, which can be a secret: an
  ;; Authorization's or a Cookie's. A wrong type's assertion names what it
  ;; found by shown-value, never the headers whole, which can hold one. The
  ;; copies are made before any check, so what is checked is what is sent,
  ;; whatever the caller's objects become after.
  (define (snapshot who headers user-agent)
    (define (wrong message irritant) (assertion-violation who message (shown-value irritant)))
    (unless (list? headers)
      (wrong "headers are a list of (NAME . VALUE) strings" headers))
    (let* ((copies
            (let loop ((rest headers) (left (length headers)) (found '()))
              (cond ((and (null? rest) (= left 0)) (reverse found))
                    ((or (= left 0) (not (pair? rest)))
                     (wrong "headers are a list of (NAME . VALUE) strings" headers))
                    (else
                     (let ((header (car rest)))
                       (unless (pair? header)
                         (wrong "headers are a list of (NAME . VALUE) strings" headers))
                       (let ((name (car header)) (value (cdr header)))
                         (unless (and (string? name) (string? value))
                           (wrong "headers are a list of (NAME . VALUE) strings" headers))
                         (loop (cdr rest) (- left 1)
                               (cons (cons (string-copy name) (string-copy value)) found))))))))
           (agent (cond ((not user-agent) #f)
                        ((and (string? user-agent) (> (string-length user-agent) 0))
                         (string-copy user-agent))
                        (else (wrong "a user agent is a non-empty string or #f" user-agent)))))
      (let ((host-seen #f))
        (for-each (lambda (header)
                    (unless (token? (car header))
                      (refuse-field who 'header-name (car header) 'not-a-token))
                    (when (string=? (ascii-folded (car header)) "proxy-authorization")
                      (refuse-field who 'header-name (car header) 'proxy-authorization-header))
                    (let ((problem (value-problem (cdr header))))
                      (when problem (refuse-field who 'header-value (car header) problem)))
                    (when (and agent (string-ci=? (car header) "User-Agent"))
                      (refuse-field who 'header-name (car header) 'duplicates-field))
                    (when (string-ci=? (car header) "Host")
                      (when host-seen
                        (refuse-field who 'header-name (car header) 'duplicates-field))
                      (set! host-seen #t))
                    (when (or (string-ci=? (car header) "Content-Length")
                              (string-ci=? (car header) "Transfer-Encoding"))
                      (refuse-field who 'header-name (car header) 'framing-header)))
                  copies))
      (when agent
        (let ((problem (value-problem agent)))
          (when problem (refuse-field who 'user-agent agent problem))))
      (cons copies agent)))

  ;; ca-file? : Any -> Boolean
  ;; X is a CA file: #f, libcurl's system store, or a non-empty string, its
  ;; path.
  (define (ca-file? x)
    (or (not x) (and (string? x) (> (string-length x) 0))))

  ;; refuse-ca-file : Symbol Symbol String Symbol String (Listof Any) -> Nothing
  ;; The refusal of the CA file PATH, FIELD's, ca-file or proxy-ca-file, for
  ;; REASON, as WHO, with MESSAGE, and IRRITANTS after PATH.
  (define (refuse-ca-file who field path reason message irritants)
    (raise (condition (make-curl-request-error field path reason)
                      (make-who-condition who)
                      (make-message-condition message)
                      (make-irritants-condition (cons path irritants)))))

  ;; pkcs11-prefix? : String -> Boolean
  ;; Whether PATH begins pkcs11:, in any ASCII case. GnuTLS reads such a CA
  ;; path as a PKCS#11 URL, not a file, in every ASCII case, even with a
  ;; file of that name there (GnuTLS 3.8.3, 3.8.9 and 3.8.13; ADR-0024,
  ;; amended 2026-10-26). A to Z alone fold: char-downcase and string-ci=?
  ;; fold U+212A KELVIN SIGN to k, and GnuTLS compares bytes, so p, U+212A,
  ;; cs11: names a file.
  (define (pkcs11-prefix? path)
    (let ((prefix "pkcs11:"))
      (and (>= (string-length path) (string-length prefix))
           (let loop ((i 0))
             (or (= i (string-length prefix))
                 (and (char=? (ascii-downcase (string-ref path i)) (string-ref prefix i))
                      (loop (+ i 1))))))))

  ;; ascii-downcase : Char -> Char
  ;; C, with A to Z as a to z; any other char as it is.
  (define (ascii-downcase c)
    (if (char<=? #\A c #\Z) (integer->char (+ (char->integer c) 32)) c))

  ;; ca-file-copy : Symbol (U String #f) -> (U String #f)
  ;; CA-FILE, a ca-file?, as a fresh string, checked: what WHO may send as
  ;; CAINFO; #f for #f; path-copy's, for the field ca-file.
  (define (ca-file-copy who ca-file)
    (path-copy who 'ca-file ca-file))

  ;; path-copy : Symbol Symbol (U String #f) -> (U String #f)
  ;; CA-FILE, a ca-file?, FIELD's, ca-file or proxy-ca-file, as a fresh
  ;; string, checked: what WHO may send as CAINFO, or PROXY_CAINFO; #f for
  ;; #f. A path holding U+0000 is refused as embedded-nul;
  ;; then one that begins pkcs11:, in any ASCII case, as pkcs11-url, on
  ;; every backend, so the field always names a file, and a file really
  ;; named so is reached as ./pkcs11:... (ADR-0024, decision 4). Each is a
  ;; &curl-request-error naming FIELD. No other char is refused: a path
  ;; may hold CR or LF. The copy is made before the checks, so what is
  ;; checked is what is sent. It is scanned by index, allocating nothing:
  ;; a path may be megabytes long, and libcurl refuses one past 8000000
  ;; bytes itself.
  (define (path-copy who field ca-file)
    (and ca-file
         (let ((copy (string-copy ca-file)))
           (let scan ((i 0))
             (when (< i (string-length copy))
               (when (char=? (string-ref copy i) #\nul)
                 (refuse-ca-file who field copy 'embedded-nul
                                 "a CA file's path holds U+0000, where C would end it, and libcurl would open another file"
                                 '()))
               (scan (+ i 1))))
           (when (pkcs11-prefix? copy)
             (refuse-ca-file who field copy 'pkcs11-url
                             "a CA file's path that begins pkcs11:, in any ASCII case, is a PKCS#11 URL to GnuTLS, not a file; reach a file of that name as ./pkcs11:..."
                             '()))
           copy)))

  ;; guix-ca-overrides : (Listof (Pairof String Symbol))
  ;; Guix's libcurls, by version, and what each one's environment patch
  ;; does to a request's CA file when SSL_CERT_FILE or SSL_CERT_DIR was set
  ;; as libcurl loaded: overrides, for one that writes SSL_CERT_FILE over
  ;; CAINFO and SSL_CERT_DIR over the cleared CAPATH when a transfer starts,
  ;; after every setopt (ADR-0018; ADR-0024, decision 2). 8.20.0's was
  ;; measured, in Guix and outside it. A Guix libcurl with no row is taken
  ;; to override: 8.6.0's older patch does not, and the maintainer kept it
  ;; taken to, since no lane runs it (ADR-0024, amended 2026-10-26).
  ;; tests/test-transfer-tls.sps holds it to its own copy.
  (define guix-ca-overrides '(("8.20.0" . overrides)))

  ;; ca-overridden? : (U String #f) String Boolean String -> Boolean
  ;; Whether a libcurl at VERSION, mapped from FILE, or loaded from PATH
  ;; where FILE is #f, is Guix's and writes the variables over a CA file.
  ;; It is Guix's when that file is under /gnu/store/, or when PATCHED, its
  ;; file holding Guix's patch's literal, SSL_CERT_FILE (ADR-0024, amended
  ;; 2026-10-26: the key); then its version's row in guix-ca-overrides says
  ;; overrides, or it has no row. FILE is the native layer's
  ;; loaded-libcurl-file, every symlink resolved, so a profile's link is
  ;; Guix's, and so is a Guix libcurl loaded by a Chez outside Guix; PATCHED
  ;; is its loaded-libcurl-patched?, so a copy out of the store is too.
  (define (ca-overridden? file path patched version)
    (and (or patched (string-prefix? "/gnu/store/" (or file path)))
         (let ((row (assoc version guix-ca-overrides)))
           (or (not row) (eq? (cdr row) 'overrides)))))

  ;; string-prefix? : String String -> Boolean
  (define (string-prefix? prefix s)
    (and (>= (string-length s) (string-length prefix))
         (string=? (substring s 0 (string-length prefix)) prefix)))

  ;; overriding-variables : (U String #f) Boolean (U String #f) String Boolean String
  ;;                         (Listof (Pairof String (U String #f))) -> (Listof String)
  ;; The variables that would override CA-FILE, with VERIFY, on the libcurl
  ;; at VERSION mapped from FILE, or loaded from PATH, its file holding
  ;; Guix's patch's literal when PATCHED, given VARIABLES, each (NAME .
  ;; VALUE) as the native layer recorded it at the load, #f for one unset or
  ;; empty: each NAME whose VALUE is a string, in VARIABLES' order, when
  ;; CA-FILE is a path, VERIFY is on, and ca-overridden? says the libcurl
  ;; writes them over a CA file; () otherwise (ADR-0024, decision
  ;; 2). With VERIFY off, libcurl reads no CA, and a request with no CA
  ;; file trusts the store the variables name, the operator's setting:
  ;; neither is refused. Pure: check-ca-environment hands it native's.
  (define (overriding-variables ca-file verify file path patched version variables)
    (if (and ca-file verify (ca-overridden? file path patched version))
        (map car (filter cdr variables))
        '()))

  ;; keychain-fallback? : (U String #f) Boolean Boolean String (U String #f) -> Boolean
  ;; Whether CA-FILE, with VERIFY, would fail to be the only anchor on the
  ;; libcurl loaded from PATH, MACOS being whether this is macOS, BACKEND
  ;; the TLS backend its init put in use: on Apple's own libcurl, under
  ;; /usr/lib/, with LibreSSL in use, or a backend that could not be read.
  ;; Apple's LibreSSL checks the keychain when a CA file fails to verify, so
  ;; example.com, which the keychain trusts, passed a CA file that named
  ;; another CA; SecureTransport, selected by CURL_SSL_BACKEND, keeps the CA
  ;; file the only anchor (measured on Apple's 8.7.1; ADR-0024, amended
  ;; 2026-10-27). A libcurl built elsewhere on upstream LibreSSL has no
  ;; keychain to fall back to. Pure: check-ca-environment hands it native's
  ;; records.
  (define (keychain-fallback? ca-file verify macos path backend)
    (and ca-file verify macos (string-prefix? "/usr/lib/" path)
         (or (not (string? backend)) (string-prefix? "LibreSSL" backend))
         #t))

  ;; check-ca-environment : Symbol Symbol (U String #f) Boolean -> Void
  ;; Refuses CA-FILE, a checked copy, FIELD's, ca-file with verify or
  ;; proxy-ca-file with proxy-verify, with VERIFY, as WHO, when
  ;; overriding-variables names any for the loaded libcurl and what the
  ;; native layer recorded at its load: environment-override, a
  ;; &curl-request-error naming FIELD, whose irritants are the path, then
  ;; each variable's name, in that order; and when keychain-fallback? says
  ;; so for the loaded libcurl and the backend its init put in use:
  ;; keychain-fallback, whose irritants are the path, then that backend.
  ;; Guix's 8.20.0 writes SSL_CERT_FILE and SSL_CERT_DIR over PROXY_CAINFO
  ;; as over CAINFO, cleared PROXY_CAPATH or not (M7 slice 3's
  ;; measurement); no probe has a proxy CA the keychain trusts, and the
  ;; proxy's is refused there by analogy (the M7 plan, section 3.4).
  (define (check-ca-environment who field ca-file verify)
    (let* ((info (loaded-libcurl))
           (names (overriding-variables ca-file verify (loaded-libcurl-file) (libcurl-info-path info)
                                        (loaded-libcurl-patched?) (libcurl-info-version info)
                                        (loaded-ca-variables)))
           (backend (loaded-tls-backend)))
      (unless (null? names)
        (refuse-ca-file who field ca-file 'environment-override
                        (string-append
                         "Guix's libcurl writes SSL_CERT_FILE over a CA file, and adds SSL_CERT_DIR beside it, as they were when it loaded; unset "
                         (fold-right (lambda (name rest) (if (string=? rest "") name (string-append name " and " rest)))
                                     "" names)
                         " before the program starts, or trust the store it names with no CA file")
                        names))
      (when (keychain-fallback? ca-file verify (loaded-on-macos?) (libcurl-info-path info) backend)
        (refuse-ca-file who field ca-file 'keychain-fallback
                        "Apple's libcurl uses its LibreSSL, which checks the keychain when a CA file fails, so the CA file would not be the only anchor; start the program with CURL_SSL_BACKEND=secure-transport, where this libcurl has it, or pass no CA file"
                        (list backend)))))

  ;; body-limit-bound : Positive-Integer
  ;; A body limit is below 2^63 - 1, so the limit plus one, which
  ;; MAXFILESIZE_LARGE gets, is a curl_off_t.
  (define body-limit-bound (- (expt 2 63) 1))

  ;; request-methods : (Listof Symbol)
  ;; The methods a request may have, the M4 plan's fixed set (ADR-0023,
  ;; decision 4). post, put, patch and delete may carry a body.
  (define request-methods '(get head post put patch delete))

  ;; request-keys : (Listof Symbol)
  ;; The keys make-curl-request and curl-request-with take, in the record's
  ;; order. tests/test-request.sps writes it out.
  (define request-keys
    '(method headers body user-agent timeout-ms connect-timeout-ms body-limit ca-file verify proxy
      stream-buffer body-length http-version credentials proxy-ca-file proxy-verify))

  ;; http-versions : (Listof Symbol)
  ;; The values http-version takes but #f: HTTP/1.1, HTTP/2, and HTTP/2 by
  ;; prior knowledge, each spelt as a response's http-version reads it
  ;; (ADR-0034; the M7 plan, section 3.1).
  (define http-versions '(http/1.1 http/2 http/2-prior-knowledge))

  ;; credentials-arities : (Listof (Pairof Symbol Natural))
  ;; Each scheme a credentials key names, with the strings it carries: basic
  ;; and digest a user and a password, bearer a token (ADR-0036, decision
  ;; 2; the M7 plan, section 3.1).
  (define credentials-arities '((basic . 2) (digest . 2) (bearer . 1)))

  ;; credentials-copy : Symbol Any -> (U Credentials #f)
  ;; CREDENTIALS, a credentials value, as a fresh list of fresh strings, the
  ;; copy made as it is read: #f for #f; (basic USER PASSWORD), (digest USER
  ;; PASSWORD) or (bearer TOKEN), each a string. Any other shape, an unknown
  ;; scheme, a wrong count or a part that is no string, is an assertion
  ;; violation from WHO, whose irritant is the key's name alone, so a
  ;; secret given in the wrong shape is never handed on. The list is read
  ;; once, by the count its scheme has, its tag and each part once, so
  ;; another thread that changes it meanwhile is refused or copied, never
  ;; followed round a cycle; and the copy is what is checked and sent
  ;; (AGENTS.md's mutable values).
  (define (credentials-copy who credentials)
    (define (wrong)
      (assertion-violation who
                           "credentials are (basic USER PASSWORD), (digest USER PASSWORD) or (bearer TOKEN), each part a string, or #f"
                           'credentials))
    (cond ((not credentials) #f)
          ((not (pair? credentials)) (wrong))
          (else
           (let* ((tag (car credentials))
                  (arity (assq tag credentials-arities)))
             (unless arity (wrong))
             (let loop ((rest (cdr credentials)) (left (cdr arity)) (found '()))
               (cond ((= left 0) (if (null? rest) (cons tag (reverse found)) (wrong)))
                     ((not (pair? rest)) (wrong))
                     (else
                      (let ((part (car rest)))
                        (unless (string? part) (wrong))
                        (loop (cdr rest) (- left 1) (cons (string-copy part) found))))))))))

  ;; credentials-parts : Credentials -> (Listof (Pairof Symbol String))
  ;; CREDENTIALS' strings, each with its part's name, in order: (user .
  ;; USER) and (password . PASSWORD), or (token . TOKEN).
  (define (credentials-parts credentials)
    (if (eq? (car credentials) 'bearer)
        (list (cons 'token (cadr credentials)))
        (list (cons 'user (cadr credentials)) (cons 'password (caddr credentials)))))

  ;; control-char? : Char -> Boolean
  ;; U+0000 to U+001F, or U+007F: each a control byte in UTF-8, and no byte
  ;; of a char above it is one.
  (define (control-char? c)
    (let ((code (char->integer c)))
      (or (< code #x20) (= code #x7F))))

  ;; refuse-credentials : Symbol Any Symbol -> Nothing
  ;; The refusal, as WHO, of a request's credentials for REASON, naming
  ;; VALUE, never a credentials string: (SCHEME PART), or SCHEME.
  (define (refuse-credentials who value reason)
    (refuse-field who 'credentials value reason))

  ;; check-credentials : Symbol (U Credentials #f) (Listof (Pairof String String))
  ;;                     (U Bytevector 'stream #f) (U Positive-Integer #f) -> Void
  ;; Refuses, as WHO, CREDENTIALS, a checked copy, beside HEADERS, the
  ;; snapshot's copies, BODY and STREAM-BUFFER, by the rules a request's
  ;; shape holds (ADR-0036, amended 2026-11-02), in order, each a
  ;; &curl-request-error, field credentials:
  ;;   - each part in order, user then password, or the token, its first
  ;;     offending char deciding: a control char, U+0000 to U+001F or
  ;;     U+007F, which libcurl writes into its header unescaped, or, in a
  ;;     Basic user, a colon, which ends the user in RFC 7617:
  ;;     credentials-bytes, value (SCHEME PART). A char above U+007F is no
  ;;     control byte in UTF-8, and passes; a colon in a Digest user, or in
  ;;     any password, passes;
  ;;   - a Bearer token "", or a user and a password both "":
  ;;     credentials-empty, value (bearer token), or (SCHEME user). One
  ;;     empty part beside the other passes, alike on every libcurl;
  ;;   - a header named Authorization, A to Z folded:
  ;;     credentials-beside-authorization, value SCHEME;
  ;;   - Digest beside a body that streams, or a stream-buffer:
  ;;     digest-with-stream, value digest. Basic and Bearer pass.
  ;; Checked as the request is made, and again at submit on the submit's
  ;; own copies, since a caller's header strings may change between.
  (define (check-credentials who credentials headers body stream-buffer)
    (when credentials
      (let ((scheme (car credentials)))
        (for-each (lambda (part)
                    (let ((text (cdr part)))
                      (let scan ((i 0))
                        (when (< i (string-length text))
                          (let ((c (string-ref text i)))
                            (when (or (control-char? c)
                                      (and (char=? c #\:) (eq? scheme 'basic) (eq? (car part) 'user)))
                              (refuse-credentials who (list scheme (car part)) 'credentials-bytes)))
                          (scan (+ i 1))))))
                  (credentials-parts credentials))
        (when (for-all (lambda (part) (string=? (cdr part) "")) (credentials-parts credentials))
          (refuse-credentials who (list scheme (car (car (credentials-parts credentials))))
                              'credentials-empty))
        (when (exists (lambda (header) (string=? (ascii-folded (car header)) "authorization")) headers)
          (refuse-credentials who scheme 'credentials-beside-authorization))
        (when (and (eq? scheme 'digest) (or (eq? body 'stream) stream-buffer))
          (refuse-credentials who scheme 'digest-with-stream)))))

  ;; timeout? : Any -> Boolean
  ;; X is a timeout: #f, none, or a positive exact integer a long holds.
  (define (timeout? x)
    (or (not x) (and (long? x) (positive? x))))

  ;; request-settings : Symbol List -> (Listof (Pairof Symbol Any))
  ;; PLIST, KEY VALUE ..., as (KEY . VALUE) pairs, in its order, each key
  ;; refused by name, as WHO, before anything else is checked: one
  ;; request-keys lacks, unknown-key; one with no value after it,
  ;; missing-value; one given twice, repeated-key. Each is a
  ;; &curl-request-error, field key, whose value is the key as given, or,
  ;; for a key that is no symbol, its kind, shown-key's: a value found
  ;; where a key belongs can be a proxy URL or credentials.
  (define (request-settings who plist)
    (let loop ((rest plist) (found '()))
      (if (null? rest)
          (reverse found)
          (let ((key (car rest)))
            (unless (memq key request-keys) (refuse-field who 'key (shown-key key) 'unknown-key))
            (when (null? (cdr rest)) (refuse-field who 'key key 'missing-value))
            (when (assq key found) (refuse-field who 'key key 'repeated-key))
            (loop (cddr rest) (cons (cons key (cadr rest)) found))))))

  ;; make-curl-request : String Symbol Any ... -> Request
  ;; curl-request-with : Request Symbol Any ... -> Request
  ;; curl-request? : Any -> Boolean
  ;; curl-request-url : Request -> String
  ;; curl-request-method : Request -> (U 'get 'head 'post 'put 'patch 'delete)
  ;; curl-request-headers : Request -> (Listof (Pairof String String))
  ;; curl-request-body : Request -> (U Bytevector 'stream #f)
  ;; curl-request-user-agent : Request -> (U String #f)
  ;; curl-request-timeout-ms : Request -> (U Positive-Integer #f)
  ;; curl-request-connect-timeout-ms : Request -> (U Positive-Integer #f)
  ;; curl-request-body-limit : Request -> (U Natural #f)
  ;; curl-request-ca-file : Request -> (U String #f)
  ;; curl-request-verify : Request -> Boolean
  ;; curl-request-proxy : Request -> (U 'environment #f String)
  ;; curl-request-stream-buffer : Request -> (U Positive-Integer #f)
  ;; curl-request-body-length : Request -> (U Natural #f)
  ;; curl-request-http-version : Request -> (U 'http/1.1 'http/2 'http/2-prior-knowledge #f)
  ;; curl-request-credentials : Request -> (U (List 'basic String String) (List 'digest String String) (List 'bearer String) #f)
  ;; curl-request-proxy-ca-file : Request -> (U String #f)
  ;; curl-request-proxy-verify : Request -> Boolean
  ;; curl-request-fault : Request -> (U Positive-Integer (List 'head Positive-Integer) #f)   private
  ;; curl-request-follow : Request -> Boolean                  private
  ;; curl-request-options : Request -> (Listof Hatch-Setting)  private
  ;;
  ;; (make-curl-request URL KEY VALUE ...): URL, a string, parsed at
  ;; submit, and again on the engine's thread. The keys, each once at most,
  ;; in any order (ADR-0023), each left out taking its default:
  ;;
  ;;   method              get (the default), head, post, put, patch or delete
  ;;   headers             (NAME . VALUE) strings, in the order sent, repeats
  ;;                       kept, but for Host: libcurl sends a Host header in
  ;;                       place of its own, first, spelt Host, whatever its
  ;;                       case here; and a second Host header, in any case,
  ;;                       is refused as duplicates-field (RFC 9112, section
  ;;                       3.2, has a server answer 400 to more than one); and
  ;;                       a Content-Length or Transfer-Encoding header, in
  ;;                       any case, as framing-header: libcurl frames the
  ;;                       message. Default ()
  ;;   body                a bytevector, sent whole, or #f, none, the default;
  ;;                       or stream, a body the token's puts give as it is
  ;;                       produced, sent at most once, on a connection of
  ;;                       its own (ADR-0030, ADR-0032). With get or head it
  ;;                       is refused as body-not-allowed. post, put and patch
  ;;                       send an empty one when it is #f; delete sends none
  ;;   user-agent          a non-empty string, or #f for none, the default
  ;;   timeout-ms          the whole transfer's bound: a positive exact integer
  ;;                       a long holds, or #f, libcurl's default, none
  ;;   connect-timeout-ms  the connection phase's bound, its TLS handshake
  ;;                       among it, as timeout-ms; #f is libcurl's default
  ;;   body-limit          an exact natural below 2^63 - 1, or #f for none
  ;;   ca-file             a CA file's path, a non-empty string, sent as
  ;;                       given, relative or absolute: the request's only
  ;;                       trust anchor (ADR-0018); or #f, the default, for
  ;;                       libcurl's system store, as built
  ;;   verify              #t, the default, to verify the peer's chain and
  ;;                       its name; #f to verify neither: libcurl then reads
  ;;                       no CA
  ;;   proxy               environment, the default, to go through the proxy
  ;;                       the environment names, by libcurl's own rules:
  ;;                       http_proxy, https_proxy, HTTPS_PROXY, all_proxy and
  ;;                       ALL_PROXY, with no_proxy and NO_PROXY, but never
  ;;                       HTTP_PROXY; or #f, to go direct, whatever they say
  ;;                       (ADR-0024, decision 1); or a URL string, an
  ;;                       http:// or https:// proxy every transfer goes
  ;;                       through, whatever a variable says, no_proxy and
  ;;                       NO_PROXY among them (ADR-0037): the record keeps a
  ;;                       copy, and curl-request-proxy answers a fresh one.
  ;;                       Its userinfo is the proxy's credentials, sent by
  ;;                       Basic on the first request, percent-decoded; a URL
  ;;                       with no port gets its scheme's, 80 or 443. A submit
  ;;                       refuses, field proxy, naming the field, never the
  ;;                       URL: one libcurl cannot parse, or whose user or
  ;;                       password holds a % not followed by two hex digits,
  ;;                       as proxy-url; a scheme but http or https, A to Z
  ;;                       folded, as proxy-scheme; a path but /, a query or a
  ;;                       fragment, as proxy-url-parts; a decoded control
  ;;                       byte, bytes that are not UTF-8 or a colon in the
  ;;                       user, as credentials-bytes, value (proxy PART), and
  ;;                       a user and password both empty as credentials-empty.
  ;;                       Neither ca-file nor verify reaches a proxy: the
  ;;                       environment's is verified against libcurl's
  ;;                       default store, a URL's by the two keys below
  ;;   stream-buffer       a positive exact integer, the bytes of the
  ;;                       response's body the token buffers, read as it
  ;;                       arrives, a piece at a time or through a port; or
  ;;                       #f, the default, which keeps the whole body
  ;;                       (ADR-0030). Beside the private follow field, the
  ;;                       hatch's HTTPAUTH or PROXYAUTH, or an Expect header
  ;;                       whose value holds 100-continue, in any ASCII case,
  ;;                       it is refused as stream-with-rounds, however the
  ;;                       two came together: each makes a second request
  ;;                       inside the transfer, whose head the stream would
  ;;                       not publish (the M6 plan, section 3.2)
  ;;   body-length         a streamed body's length, an exact natural below
  ;;                       2^63 - 1, sent as Content-Length; or #f, the
  ;;                       default, which sends it chunked over HTTP/1.1 and
  ;;                       as DATA frames over HTTP/2. Beside a body that does
  ;;                       not stream it is refused as body-length-without-
  ;;                       stream (the M6 plan, section 3.1)
  ;;   http-version        the HTTP version libcurl asks for, HTTP_VERSION
  ;;                       (ADR-0034): http/1.1, HTTP/1.1 alone, 1_1;
  ;;                       http/2, HTTP/2 by ALPN over https://, and HTTP/1.1
  ;;                       with no Upgrade over http://, 2TLS; or
  ;;                       http/2-prior-knowledge, HTTP/2 with no HTTP/1.1
  ;;                       first, for http:// URLs alone, 2_PRIOR_KNOWLEDGE:
  ;;                       with an https:// URL a submit refuses it as
  ;;                       prior-knowledge-over-https. Through an HTTP
  ;;                       proxy that does not tunnel, an http:// or
  ;;                       https:// one, the environment's among them,
  ;;                       libcurl ignores prior knowledge, and sends
  ;;                       HTTP/1.1 (the slice's measurement). Or #f, the
  ;;                       default, which sets no HTTP_VERSION: libcurl's
  ;;                       own, which acts as 2TLS on every libcurl
  ;;                       measured. No transfer sets PIPEWAIT, so requests
  ;;                       started together open their own connections, but
  ;;                       for two by prior knowledge on 7.85.0, which share
  ;;                       one, and a later one reuses an open one: over
  ;;                       http://, a #f or http/2 request to an origin the
  ;;                       engine holds an HTTP/2 connection to, made by
  ;;                       prior knowledge, reuses it and reads HTTP/2
  ;;   credentials         a server's credentials, one scheme's (ADR-0036):
  ;;                       (basic USER PASSWORD), sent on the first request;
  ;;                       (digest USER PASSWORD), sent after the bare
  ;;                       request a server answers with its challenge, a
  ;;                       second request inside the transfer, so a request
  ;;                       with a body, a post or a put, to a server that
  ;;                       never challenges goes twice, the first with no
  ;;                       body; or (bearer TOKEN), sent on the
  ;;                       first request. Each part is a string, sent as
  ;;                       UTF-8: by HTTPAUTH at the scheme's bit, then
  ;;                       USERNAME and PASSWORD, or XOAUTH2_BEARER. Refused
  ;;                       when any part holds a control char, U+0000 to
  ;;                       U+001F or U+007F, or a Basic user a colon, as
  ;;                       credentials-bytes; when a Bearer token, or a user
  ;;                       and a password both, are "", as credentials-empty;
  ;;                       beside a header named Authorization, in any ASCII
  ;;                       case, as credentials-beside-authorization; Digest
  ;;                       beside body stream or a stream-buffer, as
  ;;                       digest-with-stream; and, at submit, beside a URL
  ;;                       whose user or password part libcurl reports, as
  ;;                       credentials-beside-userinfo. No refusal names a
  ;;                       credentials string. The record keeps a copy, and
  ;;                       curl-request-credentials answers a fresh one. A
  ;;                       wrong password ends with the server's 401 and
  ;;                       code 0. Or #f, the default, which sets none of
  ;;                       their options, as before them
  ;;   proxy-ca-file       an https:// proxy URL's only CA file, PROXY_CAINFO,
  ;;                       with PROXY_CAPATH cleared, a non-empty string kept
  ;;                       as a copy and checked as ca-file is, pkcs11: and
  ;;                       U+0000 refused, and at submit against the
  ;;                       environment; or #f, the default, libcurl's default
  ;;                       store. Beside any proxy but an https:// URL a
  ;;                       submit refuses it as proxy-tls-without-https-proxy
  ;;   proxy-verify        #t, the default, to verify an https:// proxy's
  ;;                       chain and name, PROXY_SSL_VERIFYPEER and
  ;;                       PROXY_SSL_VERIFYHOST at 1 and 2; #f, both 0, which
  ;;                       beside any proxy but an https:// URL a submit
  ;;                       refuses as proxy-tls-without-https-proxy
  ;;
  ;; A caller's Proxy-Authorization header, in any ASCII case, is refused
  ;; whatever proxy names, as proxy-authorization-header. At submit,
  ;; http/2-prior-knowledge beside a proxy URL is refused as
  ;; prior-knowledge-through-proxy, and an https:// URL through an https://
  ;; proxy URL, on a libcurl tls-in-tls-stall? names, as proxy-tls-in-tls.
  ;;
  ;; The defaults set no policy: libcurl's own stand (ADR-0023, decision 3).
  ;; The keys are refused first, by request-settings' rules, then a URL
  ;; that is not a string, then a wrong type for method, body, timeout-ms,
  ;; connect-timeout-ms, body-limit, ca-file, verify, proxy, stream-buffer,
  ;; body-length, http-version, credentials, proxy-ca-file or proxy-verify,
  ;; each an assertion violation, the empty string as a CA file among them;
  ;; then a body with get or head, body-not-allowed; then a
  ;; body-length beside a body that does not stream,
  ;; body-length-without-stream; then a
  ;; stream-buffer beside follow, stream-with-rounds,
  ;; checked here, where every constructor's request is checked, the
  ;; private ones' and the hatch's among them; then snapshot's rules for the
  ;; headers and the user agent, their types first, as assertion
  ;; violations; then an Expect header holding 100-continue beside
  ;; stream-buffer, stream-with-rounds, by expect-continue?, which a submit
  ;; checks again on its own copies; then the credentials, by
  ;; check-credentials, which a submit checks again too; then ca-file-copy's
  ;; for the CA file, and path-copy's for the proxy CA file. Each refusal of
  ;; a value is a &curl-request-error naming the field. The record keeps the
  ;; caller's objects, but for its credentials, its proxy URL and its proxy
  ;; CA file, private copies; a submit checks them again, as a plan.
  ;;
  ;; (curl-request-with REQUEST KEY VALUE ...): a new request, with the
  ;; keys given replaced and the rest kept, its private fields among them,
  ;; checked as make-curl-request checks a new one.
  ;;
  ;; The private fields are no keys, and (curl) exports none: FAULT, #f, or
  ;; a positive exact integer, a planted fault that makes the callable
  ;; raise (planted-fault FAULT) at the chunk of that number, counting from
  ;; 1, before its limit check (M3 plan, section 3.6); FOLLOW, a
  ;; boolean, FOLLOWLOCATION at 1 when #t, for the tests that follow a
  ;; redirect, which nothing public may (M4 plan, section 3.2); and
  ;; OPTIONS, the hatch's settings, () until curl-request-with-options
  ;; attaches some, each a copy no caller holds, which curl-request-with
  ;; and the private constructors keep (ADR-0009). Each is data, never a
  ;; procedure: a request holds no caller code (ADR-0012, decision 4).
  (define-record-type (curl-request new-curl-request curl-request?)
    (fields (immutable url unchecked-curl-request-url)
            (immutable method unchecked-curl-request-method)
            (immutable headers unchecked-curl-request-headers)
            (immutable body unchecked-curl-request-body)
            (immutable user-agent unchecked-curl-request-user-agent)
            (immutable timeout-ms unchecked-curl-request-timeout-ms)
            (immutable connect-timeout-ms unchecked-curl-request-connect-timeout-ms)
            (immutable body-limit unchecked-curl-request-body-limit)
            (immutable ca-file unchecked-curl-request-ca-file)
            (immutable verify unchecked-curl-request-verify)
            (immutable proxy request-proxy)
            (immutable stream-buffer unchecked-curl-request-stream-buffer)
            (immutable body-length unchecked-curl-request-body-length)
            (immutable http-version unchecked-curl-request-http-version)
            (immutable credentials request-credentials)
            (immutable proxy-ca-file request-proxy-ca-file)
            (immutable proxy-verify unchecked-curl-request-proxy-verify)
            (immutable fault curl-request-fault)
            (immutable follow curl-request-follow)
            (immutable options curl-request-options))
    ;; Opaque: Chez prints a record's every field, and record-rtd opens
    ;; one, so a printed request showed its credentials, and reflection
    ;; read and changed its private copy (the review of M7 slice 2). A
    ;; request prints as #<curl-request>.
    (opaque #t))

  ;; Each accessor checks its argument first: anything else is an assertion
  ;; violation from the accessor, naming it by its kind, shown-value's,
  ;; never printed, as Chez's own check printed it (ADR-0036, amended
  ;; 2026-11-03).
  (define curl-request-url
    (checked-accessor 'curl-request-url curl-request? "a request" unchecked-curl-request-url))
  (define curl-request-method
    (checked-accessor 'curl-request-method curl-request? "a request" unchecked-curl-request-method))
  (define curl-request-headers
    (checked-accessor 'curl-request-headers curl-request? "a request" unchecked-curl-request-headers))
  (define curl-request-body
    (checked-accessor 'curl-request-body curl-request? "a request" unchecked-curl-request-body))
  (define curl-request-user-agent
    (checked-accessor 'curl-request-user-agent curl-request? "a request" unchecked-curl-request-user-agent))
  (define curl-request-timeout-ms
    (checked-accessor 'curl-request-timeout-ms curl-request? "a request" unchecked-curl-request-timeout-ms))
  (define curl-request-connect-timeout-ms
    (checked-accessor 'curl-request-connect-timeout-ms curl-request? "a request" unchecked-curl-request-connect-timeout-ms))
  (define curl-request-body-limit
    (checked-accessor 'curl-request-body-limit curl-request? "a request" unchecked-curl-request-body-limit))
  (define curl-request-ca-file
    (checked-accessor 'curl-request-ca-file curl-request? "a request" unchecked-curl-request-ca-file))
  (define curl-request-verify
    (checked-accessor 'curl-request-verify curl-request? "a request" unchecked-curl-request-verify))
  (define curl-request-stream-buffer
    (checked-accessor 'curl-request-stream-buffer curl-request? "a request" unchecked-curl-request-stream-buffer))
  (define curl-request-body-length
    (checked-accessor 'curl-request-body-length curl-request? "a request" unchecked-curl-request-body-length))
  (define curl-request-http-version
    (checked-accessor 'curl-request-http-version curl-request? "a request" unchecked-curl-request-http-version))
  (define curl-request-proxy-verify
    (checked-accessor 'curl-request-proxy-verify curl-request? "a request" unchecked-curl-request-proxy-verify))

  ;; request-field-names : -> (Listof Symbol)
  ;; The request record's fields, in its order: a private accessor, for
  ;; the suites that read them, since record-rtd opens no opaque record.
  (define (request-field-names)
    (vector->list (record-type-field-names (record-type-descriptor curl-request))))

  ;; request-credentials : Request -> (U Credentials #f)
  ;; The record's own copy of its credentials, which no caller holds: the
  ;; constructors and a submit read it, each copying it again.

  (define (curl-request-credentials request)
    (unless (curl-request? request)
      (assertion-violation 'curl-request-credentials "not a request" (shown-value request)))
    (credentials-copy 'curl-request-credentials (request-credentials request)))

  ;; request-proxy : Request -> (U 'environment #f String)
  ;; request-proxy-ca-file : Request -> (U String #f)
  ;; The record's own copies, which no caller holds: the constructors and a
  ;; submit read them, a submit copying them again.

  (define (curl-request-proxy request)
    (unless (curl-request? request)
      (assertion-violation 'curl-request-proxy "not a request" (shown-value request)))
    (let ((proxy (request-proxy request)))
      (if (string? proxy) (string-copy proxy) proxy)))

  (define (curl-request-proxy-ca-file request)
    (unless (curl-request? request)
      (assertion-violation 'curl-request-proxy-ca-file "not a request" (shown-value request)))
    (let ((path (request-proxy-ca-file request)))
      (and path (string-copy path))))

  ;; checked-request : Symbol Any Any Any Any Any Any Any Any Any Any Any Any Any Any Any Any Any Any Any (Listof Hatch-Setting) -> Request
  ;; A request of these fields, checked as WHO by make-curl-request's rules,
  ;; after the keys. OPTIONS, the hatch's, were checked as they were
  ;; attached, and are private copies, so they are kept as they are.
  ;; CREDENTIALS, a PROXY string and PROXY-CA-FILE are copied first, and
  ;; each copy is checked and kept.
  (define (checked-request who url method headers body user-agent timeout-ms
                           connect-timeout-ms body-limit ca-file verify proxy stream-buffer
                           body-length http-version credentials proxy-ca-file proxy-verify
                           fault follow options)
    (define (wrong message irritant) (assertion-violation who message (shown-value irritant)))
    (unless (string? url) (wrong "a URL is a string" url))
    (unless (memq method request-methods)
      (wrong "a method is get, head, post, put, patch or delete" method))
    (unless (or (not body) (bytevector? body) (eq? body 'stream))
      (wrong "a body is a bytevector, stream, or #f" body))
    (unless (timeout? timeout-ms)
      (wrong "a timeout is a positive exact integer a long holds, or #f" timeout-ms))
    (unless (timeout? connect-timeout-ms)
      (wrong "a connect timeout is a positive exact integer a long holds, or #f"
             connect-timeout-ms))
    (unless (or (not body-limit)
                (and (integer? body-limit) (exact? body-limit) (<= 0 body-limit)
                     (< body-limit body-limit-bound)))
      (wrong "a body limit is an exact natural below 2^63 - 1, or #f" body-limit))
    (unless (ca-file? ca-file)
      (wrong "a CA file is a non-empty string, its path, or #f" ca-file))
    (unless (boolean? verify) (wrong "verify is #t or #f" verify))
    (unless (or (eq? proxy 'environment) (not proxy) (string? proxy))
      (wrong "a proxy is environment, the environment's, #f, none, or a URL string" 'proxy))
    (unless (or (not stream-buffer)
                (and (integer? stream-buffer) (exact? stream-buffer) (positive? stream-buffer)))
      (wrong "a stream-buffer is a positive exact integer, the bytes a token buffers, or #f, the whole body"
             stream-buffer))
    (unless (or (not body-length)
                (and (integer? body-length) (exact? body-length) (<= 0 body-length)
                     (< body-length body-limit-bound)))
      (wrong "a body-length is an exact natural below 2^63 - 1, a streamed body's length, or #f"
             body-length))
    (unless (or (not http-version) (memq http-version http-versions))
      (wrong "an http-version is http/1.1, http/2, http/2-prior-knowledge, or #f, libcurl's own"
             http-version))
    (let ((credentials (credentials-copy who credentials))
          (proxy (if (string? proxy) (string-copy proxy) proxy)))
      (unless (ca-file? proxy-ca-file)
        (wrong "a proxy CA file is a non-empty string, its path, or #f" proxy-ca-file))
      (unless (boolean? proxy-verify) (wrong "proxy-verify is #t or #f" proxy-verify))
      (unless (or (not fault) (chunk-fault? fault) (head-fault? fault) (upload-fault? fault))
        (wrong "a fault is a positive exact integer, the chunk it raises at, (head N), the head's line it raises at, (read N), (seek N) or (prereq N), that callable's call it raises at, or #f: a request holds no procedure"
               fault))
      (unless (boolean? follow) (wrong "follow is #t or #f" follow))
      (when (and body (memq method '(get head)))
        (refuse-field who 'body method 'body-not-allowed))
      (when (and body-length (not (eq? body 'stream)))
        (refuse-field who 'body-length body-length 'body-length-without-stream))
      (when (and stream-buffer follow)
        (refuse-field who 'stream-buffer stream-buffer 'stream-with-rounds))
      (let ((header-copies (car (snapshot who headers user-agent))))
        (check-expect-round who stream-buffer header-copies)
        (check-credentials who credentials header-copies body stream-buffer))
      (ca-file-copy who ca-file)
      (new-curl-request url method headers body user-agent timeout-ms connect-timeout-ms
                        body-limit ca-file verify proxy stream-buffer body-length http-version
                        credentials (path-copy who 'proxy-ca-file proxy-ca-file) proxy-verify
                        fault follow options)))

  ;; chunk-fault? : Any -> Boolean
  ;; X is a fault the write callable raises at: the chunk's number, a
  ;; positive exact integer.
  (define (chunk-fault? x) (and (integer? x) (exact? x) (positive? x)))

  ;; head-fault? : Any -> Boolean
  ;; X is a fault the header callable raises at, (head N), N the head's
  ;; line, counting from 1, a positive exact integer.
  (define (head-fault? x)
    (and (list? x) (= (length x) 2) (eq? (car x) 'head) (chunk-fault? (cadr x))))

  ;; upload-fault? : Any -> Boolean
  ;; X is a fault a request stream's callable raises at, (KIND N): KIND
  ;; read, seek or prereq, the callable, and N its call, counting from 1, a
  ;; positive exact integer.
  (define (upload-fault? x)
    (and (list? x) (= (length x) 2) (memq (car x) '(read seek prereq)) (chunk-fault? (cadr x)) #t))

  ;; ascii-folded : String -> String
  ;; S with A to Z as a to z, and every other char as it is: how an Expect
  ;; header's name and value are compared, as libcurl compares them. Never
  ;; string-ci=? nor char-foldcase, which fold U+017F LONG S to s and
  ;; U+212A KELVIN SIGN to k (traps.md).
  (define (ascii-folded s)
    (list->string (map ascii-downcase (string->list s))))

  ;; expect-continue? : (Listof (Pairof String String)) -> Boolean
  ;; Whether HEADERS, checked copies, name Expect, in any ASCII case, with a
  ;; value that holds 100-continue, in any ASCII case, anywhere in it:
  ;; libcurl then waits for a 100 before a body, and on a 417 resends the
  ;; request, without it, inside the same transfer; a get, or a delete
  ;; with no body, it sends once, the 417 final (slice 1's second review,
  ;; on 8.20.0), and the rule refuses those too. 7.85.0 and 8.5.0 match it so,
  ;; anywhere in the value, "x100-continue" and "100-continue;q=1" among
  ;; them; 8.20.0 and 8.23.0 as an element of a comma-separated list alone,
  ;; as M6 slice 1's Expect probe measured. This holds the wider rule, on
  ;; every Expect header, not only the first, which libcurl reads. Pure.
  (define (expect-continue? headers)
    (exists (lambda (header)
              (and (string=? (ascii-folded (car header)) "expect")
                   (holds-text? (ascii-folded (cdr header)) "100-continue")))
            headers))

  ;; holds-text? : String String -> Boolean
  ;; Whether TEXT holds PART, char for char, at some position.
  (define (holds-text? text part)
    (let ((n (string-length text)) (k (string-length part)))
      (let loop ((i 0))
        (and (<= (+ i k) n)
             (or (string=? (substring text i (+ i k)) part)
                 (loop (+ i 1)))))))

  ;; check-expect-round : Symbol (U Positive-Integer #f) (Listof (Pairof String String)) -> Void
  ;; Refuses, as WHO, a streamed response, STREAM-BUFFER, beside HEADERS, the
  ;; snapshot's copies, that name Expect: 100-continue: stream-with-rounds,
  ;; whatever the method, since a 417 makes libcurl resend a request that
  ;; sends a body inside the transfer, and the head
  ;; published would be the 417's (the M6 plan, section 3.2: one transfer,
  ;; one request). Checked as the request is made, and again at submit on
  ;; the submit's own copies, since a caller's string may change between.
  (define (check-expect-round who stream-buffer headers)
    (when (and stream-buffer (expect-continue? headers))
      (refuse-field who 'stream-buffer stream-buffer 'stream-with-rounds)))

  ;; request-like : Symbol Request (Listof (Pairof Symbol Any)) String Any Any
  ;;                (Listof Hatch-Setting) -> Request
  ;; REQUEST with SETTINGS' keys replaced, URL, FAULT, FOLLOW and OPTIONS
  ;; given, the rest kept, checked as WHO.
  (define (request-like who request settings url fault follow options)
    (define (given key accessor)
      (let ((hit (assq key settings))) (if hit (cdr hit) (accessor request))))
    (checked-request who url
                     (given 'method curl-request-method)
                     (given 'headers curl-request-headers)
                     (given 'body curl-request-body)
                     (given 'user-agent curl-request-user-agent)
                     (given 'timeout-ms curl-request-timeout-ms)
                     (given 'connect-timeout-ms curl-request-connect-timeout-ms)
                     (given 'body-limit curl-request-body-limit)
                     (given 'ca-file curl-request-ca-file)
                     (given 'verify curl-request-verify)
                     (given 'proxy request-proxy)
                     (given 'stream-buffer curl-request-stream-buffer)
                     (given 'body-length curl-request-body-length)
                     (given 'http-version curl-request-http-version)
                     (given 'credentials request-credentials)
                     (given 'proxy-ca-file request-proxy-ca-file)
                     (given 'proxy-verify curl-request-proxy-verify)
                     fault follow options))

  ;; default-request : Request
  ;; Every key at its default, for a URL nothing reads: what
  ;; make-curl-request replaces keys in.
  (define default-request
    (new-curl-request "" 'get '() #f #f #f #f #f #f #t 'environment #f #f #f #f #f #t #f #f '()))

  (define (make-curl-request url . plist)
    (request-like 'make-curl-request default-request
                  (request-settings 'make-curl-request plist) url #f #f '()))

  (define (curl-request-with request . plist)
    (unless (curl-request? request)
      (assertion-violation 'curl-request-with "not a request" (shown-value request)))
    (request-like 'curl-request-with request (request-settings 'curl-request-with plist)
                  (curl-request-url request) (curl-request-fault request)
                  (curl-request-follow request) (curl-request-options request)))

  ;; curl-request-with-fault : Request (U Positive-Integer #f) -> Request
  ;; REQUEST with its private fault FAULT, the test seam's (M3 plan, section
  ;; 3.6). (curl) does not export it.
  (define (curl-request-with-fault request fault)
    (unless (curl-request? request)
      (assertion-violation 'curl-request-with-fault "not a request" (shown-value request)))
    (unless (or (not fault) (chunk-fault? fault))
      (assertion-violation 'curl-request-with-fault
                           "a fault is a positive exact integer, the chunk it raises at, or #f: a request holds no procedure"
                           fault))
    (request-like 'curl-request-with-fault request '() (curl-request-url request) fault
                  (curl-request-follow request) (curl-request-options request)))

  ;; curl-request-with-head-fault : Request Positive-Integer -> Request
  ;; REQUEST with its private fault (head N): the header callable raises
  ;; (planted-head-fault N) at the head's line N, counting from 1, for a
  ;; streamed response, so a test can watch its guard record it. A test
  ;; seam; (curl) does not export it.
  (define (curl-request-with-head-fault request n)
    (unless (curl-request? request)
      (assertion-violation 'curl-request-with-head-fault "not a request" (shown-value request)))
    (unless (chunk-fault? n)
      (assertion-violation 'curl-request-with-head-fault "a head's line is a positive exact integer" n))
    (request-like 'curl-request-with-head-fault request '() (curl-request-url request) (list 'head n)
                  (curl-request-follow request) (curl-request-options request)))

  ;; curl-request-with-upload-fault : Request (U 'read 'seek 'prereq) Positive-Integer -> Request
  ;; REQUEST with its private fault (KIND N): the request stream's callable
  ;; KIND, the read, seek or prerequest callable, raises
  ;; (planted-upload-fault KIND N) at its call N, counting from 1, so a
  ;; test can watch its guard record it. A test seam; (curl) does not
  ;; export it.
  (define (curl-request-with-upload-fault request kind n)
    (unless (curl-request? request)
      (assertion-violation 'curl-request-with-upload-fault "not a request" (shown-value request)))
    (unless (and (memq kind '(read seek prereq)) (chunk-fault? n))
      (assertion-violation 'curl-request-with-upload-fault
                           "a fault names read, seek or prereq, and a call, a positive exact integer"
                           (list kind n)))
    (request-like 'curl-request-with-upload-fault request '() (curl-request-url request) (list kind n)
                  (curl-request-follow request) (curl-request-options request)))

  ;; curl-request-following : Request -> Request
  ;; REQUEST, following redirects: FOLLOWLOCATION at 1, for the tests of a
  ;; followed redirect and of ADR-0003's redirect pin. Nothing public
  ;; follows one: through a 301, 302 or 303, libcurl resends a custom
  ;; method without its body (ADR-0023, amended 2026-10-26). (curl) does
  ;; not export it.
  (define (curl-request-following request)
    (unless (curl-request? request)
      (assertion-violation 'curl-request-following "not a request" (shown-value request)))
    (request-like 'curl-request-following request '() (curl-request-url request)
                  (curl-request-fault request) #t (curl-request-options request)))

  ;; --- the response -----------------------------------------------------------------

  ;; curl-response? : Any -> Boolean
  ;; curl-response-status : Response -> Integer
  ;; curl-response-http-version : Response -> (U Symbol Integer #f)
  ;; curl-response-effective-url : Response -> (U String #f)
  ;; curl-response-headers : Response -> (Listof (Pairof String String))
  ;; curl-response-body : Response -> (U Bytevector #f)
  ;; curl-response-timings : Response -> (Listof (Pairof Symbol Natural))
  ;; What a transfer answered: RESPONSE_CODE; HTTP_VERSION, by
  ;; http-version-symbol; EFFECTIVE_URL, read as UTF-8; every header of the
  ;; last request, CURLH_HEADER's, as Latin-1 strings in libcurl's order;
  ;; the body, #f for a streamed one; and its timings, timing-infos' names
  ;; in its order, each the microseconds from the transfer's start to that
  ;; phase's end, as libcurl reports them (M4 plan, section 3.3).
  (define-record-type (curl-response make-curl-response curl-response?)
    (fields (immutable status unchecked-curl-response-status)
            (immutable http-version unchecked-curl-response-http-version)
            (immutable effective-url unchecked-curl-response-effective-url)
            (immutable headers unchecked-curl-response-headers)
            (immutable body unchecked-curl-response-body)
            (immutable timings unchecked-curl-response-timings)))

  ;; Each accessor checks its argument first: anything else is an assertion
  ;; violation from the accessor, naming it by its kind, shown-value's,
  ;; never printed, as Chez's own check printed it (ADR-0036, amended
  ;; 2026-11-03).
  (define curl-response-status
    (checked-accessor 'curl-response-status curl-response? "a response" unchecked-curl-response-status))
  (define curl-response-http-version
    (checked-accessor 'curl-response-http-version curl-response? "a response" unchecked-curl-response-http-version))
  (define curl-response-effective-url
    (checked-accessor 'curl-response-effective-url curl-response? "a response" unchecked-curl-response-effective-url))
  (define curl-response-headers
    (checked-accessor 'curl-response-headers curl-response? "a response" unchecked-curl-response-headers))
  (define curl-response-body
    (checked-accessor 'curl-response-body curl-response? "a response" unchecked-curl-response-body))
  (define curl-response-timings
    (checked-accessor 'curl-response-timings curl-response? "a response" unchecked-curl-response-timings))

  ;; timing-infos : (Listof (Pairof Symbol Positive-Integer))
  ;; Each timing a response carries, in its order, with the CURLINFO_ it is
  ;; read from, a curl_off_t of microseconds: name-lookup, NAMELOOKUP_TIME_T;
  ;; connect, CONNECT_TIME_T; tls-handshake, APPCONNECT_TIME_T, 0 without
  ;; TLS; first-byte, STARTTRANSFER_TIME_T; total, TOTAL_TIME_T. On a
  ;; success every libcurl measured reports them in that order (M4 plan,
  ;; section 4.1), and a phase the transfer skipped as 0: on a connection
  ;; reused, name-lookup, connect and tls-handshake are all 0 (8.20.0, the
  ;; slice's review), but for 7.85.0's connect, 10 to 37 microseconds on a
  ;; connection reused once the transfer before had ended (M7 slice 1).
  ;; tests/test-request.sps writes it out.
  (define timing-infos
    `((name-lookup . ,curlinfo-namelookup-time-t)
      (connect . ,curlinfo-connect-time-t)
      (tls-handshake . ,curlinfo-appconnect-time-t)
      (first-byte . ,curlinfo-starttransfer-time-t)
      (total . ,curlinfo-total-time-t)))

  ;; http-version-symbol : Integer -> (U Symbol Integer #f)
  ;; CURLINFO_HTTP_VERSION's answer N as a symbol: http/1.0, http/1.1,
  ;; http/2 or http/3; #f for 0, no response; any other number as itself.
  (define (http-version-symbol n)
    (cond ((eqv? n curl-http-version-1-0) 'http/1.0)
          ((eqv? n curl-http-version-1-1) 'http/1.1)
          ((eqv? n curl-http-version-2-0) 'http/2)
          ((eqv? n curl-http-version-3) 'http/3)
          ((eqv? n 0) #f)
          (else n)))

  ;; bytes->latin-1 : Bytevector -> String
  ;; Each byte as one char, byte n as U+00nn: how a header's bytes become a
  ;; string (ADR-0001, amended 2026-10-23).
  (define (bytes->latin-1 bytes)
    (let* ((n (bytevector-length bytes)) (s (make-string n)))
      (let loop ((i 0))
        (when (< i n)
          (string-set! s i (integer->char (bytevector-u8-ref bytes i)))
          (loop (+ i 1))))
      s))

  ;; --- failures ---------------------------------------------------------------------

  ;; error-buffer-text : (U Positive-Integer #f) -> (U String #f)
  ;; The text in the error buffer at BUFFER, all CURL_ERROR_SIZE bytes of it
  ;; read with the checked copy and cut at the first NUL, as Latin-1; #f
  ;; when it is empty, or there is no buffer yet.
  (define (error-buffer-text buffer)
    (and buffer
         (let ((bytes (make-bytevector curl-error-size 0)))
           (copy-foreign->bytevector! buffer bytes 0 curl-error-size)
           (let loop ((i 0))
             (cond ((= i curl-error-size) (bytes->latin-1 bytes))
                   ((= (bytevector-u8-ref bytes i) 0)
                    (and (> i 0)
                         (let ((text (make-bytevector i)))
                           (bytevector-copy! bytes 0 text 0 i)
                           (bytes->latin-1 text))))
                   (else (loop (+ i 1))))))))

  ;; failure : Symbol (U Integer #f) (U String #f) (U Positive-Integer #f) Any (U Natural #f)
  ;;           (U Positive-Integer #f) -> Condition
  ;; What a transfer that failed for REASON raises: the class of CODE, by
  ;; make-classed-transfer-error's rule (ADR-0022, amended 2026-10-26), with
  ;; CODE's strerror, the error buffer's text, read now, while the buffer
  ;; lives, REQUEST-SIZE, the bytes of request sent, and CONNECT-CODE, the
  ;; status a proxy refused the transfer's CONNECT with, or #f.
  (define (failure reason code option buffer recorded request-size connect-code)
    (let ((strerror (and code (curl-easy-strerror code))))
      (condition (make-classed-transfer-error reason code option strerror
                                              (error-buffer-text buffer) recorded request-size
                                              connect-code)
                 (make-who-condition 'curl-transfer)
                 (make-message-condition
                  (or strerror
                      (case reason
                        ((unknown-option) "the loaded libcurl does not know this option")
                        ((no-handle) "curl_easy_init returned NULL")
                        ((cancelled) "the transfer was cancelled before it ended")
                        ((stopped) "the transfer's engine stopped before it ended")
                        (else "the transfer failed"))))
                 (make-irritants-condition (if option (list option) '())))))

  ;; request-size-unreliable : (Listof String)
  ;; The libcurl versions whose CURLINFO_REQUEST_SIZE answers 0 for every
  ;; transfer, one that sent its request too: upstream 8.7.0 and 8.7.1, the
  ;; Mac's, measured on slice 1's probe's 21 transfers, where 8.6.0 and
  ;; 8.8.0 answered each request's length (ADR-0022, amended 2026-10-27).
  ;; tests/test-request.sps holds it to its own copy.
  (define request-size-unreliable '("8.7.0" "8.7.1"))

  ;; reported-request-size : String Natural -> (U Natural #f)
  ;; SIZE, CURLINFO_REQUEST_SIZE's answer for a transfer that ran, on the
  ;; libcurl at VERSION: #f, unknown, where request-size-unreliable names
  ;; VERSION, so 0 there never claims that nothing was sent; SIZE elsewhere.
  (define (reported-request-size version size)
    (if (member version request-size-unreliable) #f size))

  ;; connect-status : Integer -> (U Positive-Integer #f)
  ;; CODE, CURLINFO_HTTP_CONNECTCODE's answer, as a failure carries it: the
  ;; status a proxy answered a CONNECT with, when it is no 2xx; #f for 0, no
  ;; CONNECT status, and for a 2xx, the tunnel opened (ADR-0037, decision 9).
  ;; Pure.
  (define (connect-status code)
    (and (integer? code) (positive? code) (not (<= 200 code 299)) code))

  ;; ran-connect-status : Positive-Integer -> (U Positive-Integer #f)
  ;; connect-status of EASY's CURLINFO_HTTP_CONNECTCODE.
  (define (ran-connect-status easy)
    (connect-status (info-long easy curlinfo-http-connectcode)))

  ;; ran-request-size : Positive-Integer -> (U Natural #f)
  ;; reported-request-size for EASY's transfer, which ran, on the loaded
  ;; libcurl.
  (define (ran-request-size easy)
    (reported-request-size (libcurl-info-version (loaded-libcurl))
                           (info-long easy curlinfo-request-size)))

  ;; fail : Symbol (U Integer #f) (U String #f) (U Positive-Integer #f) Any -> Nothing
  ;; Raises failure's condition for a transfer refused while it was set up,
  ;; before anything was sent: its request size is 0, which chez-curl knows
  ;; itself, on every libcurl, and it sent no CONNECT.
  (define (fail reason code option buffer recorded)
    (raise (failure reason code option buffer recorded 0 #f)))

  ;; transfer-ended : (U 'cancelled 'stopped) -> Condition
  ;; The outcome of a transfer cancelled, or whose engine stopped, before
  ;; it ended: &curl-transfer-error with that reason, no code, and no
  ;; request size: it is taken apart unread.
  (define (transfer-ended reason)
    (unless (memq reason '(cancelled stopped))
      (assertion-violation 'transfer-ended "a transfer ends early cancelled or stopped" reason))
    (failure reason #f #f #f #f #f #f))

  ;; --- options ----------------------------------------------------------------------

  ;; option-bindings : (Listof (Pairof Symbol Symbol))
  ;; Each CURLOT type, by its name in curlot-types, in its order, with the
  ;; setopt binding a value of it goes through: long, curl-easy-setopt-long;
  ;; off-t, curl-easy-setopt-off-t; pointer, curl-easy-setopt-pointer.
  ;; tests/test-transfer.sps holds it to a table written out there.
  (define option-bindings
    '((long . long) (values . long) (off-t . off-t) (object . pointer) (string . pointer)
      (slist . pointer) (cbptr . pointer) (blob . pointer) (function . pointer)))

  ;; option-binding : Natural -> Symbol
  ;; The binding for the CURLOT code CODE: its name's in option-bindings. A
  ;; code curlot-types does not name, a later libcurl's, is an assertion
  ;; violation: no binding is known to fit it.
  (define (option-binding code)
    (let ((type (find (lambda (entry) (eqv? (cdr entry) code)) curlot-types)))
      (unless type
        (assertion-violation 'option-binding "a CURLOT type chez-curl does not know" code))
      (cdr (assq (car type) option-bindings))))

  ;; option-setter : Symbol -> (Positive-Integer Integer Integer -> Integer)
  ;; The setopt binding a binding's name in option-bindings stands for:
  ;; long, off-t or pointer. tests/test-transfer.sps holds each to native's
  ;; own, by eq?: on x86-64 a long sent through the off_t binding arrives
  ;; all the same, so only the table can show it.
  (define (option-setter binding)
    (case binding
      ((long) curl-easy-setopt-long)
      ((off-t) curl-easy-setopt-off-t)
      ((pointer) curl-easy-setopt-pointer)
      (else (assertion-violation 'option-setter "not a setopt binding's name" binding))))

  ;; request-field-options : (Listof (Pairof Symbol (Listof String)))
  ;; Each request field that sets options, with their names, (FIELD NAME
  ;; ...): the one place the transfer reads them from, and part of
  ;; owned-option-names, so a field's options are closed to the hatch by
  ;; being a field's (ADR-0009, consequences). method sets NOBODY for head
  ;; and CUSTOMREQUEST for put, patch and delete, and for a streamed body
  ;; POST, or UPLOAD for put (the M6 plan, section 3.3); body, for a whole
  ;; one, POSTFIELDSIZE_LARGE then COPYPOSTFIELDS, in that order, since
  ;; libcurl copies the size the first set, and for a streamed one
  ;; POSTFIELDSIZE_LARGE, put's aside, the read callable and its data, the
  ;; seek callable's, the prerequest callable's and FRESH_CONNECT (ADR-0032);
  ;; body-length, put's INFILESIZE_LARGE, the length a streamed put sends.
  ;; The TLS fields set two each, in the order tls-settings makes
  ;; them: ca-file CAINFO, its path, then CAPATH, cleared; verify
  ;; SSL_VERIFYPEER, then SSL_VERIFYHOST (ADR-0018). proxy sets PROXY, to ""
  ;; when it is #f (ADR-0024, decision 1), and for a URL PROXY at it, then
  ;; NOPROXY at "", so no variable sends the transfer direct, and
  ;; FORBID_REUSE, with FRESH_CONNECT, the body's, where
  ;; unshared-tunnel-settings asks (ADR-0037, amended twice): NOPROXY was
  ;; the field's twin before; proxy-ca-file PROXY_CAINFO, its path, then
  ;; PROXY_CAPATH, cleared; proxy-verify PROXY_SSL_VERIFYPEER, then
  ;; PROXY_SSL_VERIFYHOST, by proxy-settings. follow is the private field's
  ;; (M4 plan, section 3.2). stream-buffer sets the header callable and its
  ;; data, the transfer's key, for a streamed response alone (the M6 plan,
  ;; sections 3.2 and 3.3). http-version sets HTTP_VERSION, by
  ;; version-settings, when it is not #f (ADR-0034). credentials sets
  ;; HTTPAUTH at its scheme's bit, then USERNAME and PASSWORD, or
  ;; XOAUTH2_BEARER, by credentials-settings, when it is not #f (ADR-0036).
  ;; USERNAME and PASSWORD were owned before as the URL's twins, which each
  ;; replace part of the URL's credentials on some version (M4 slice 4's
  ;; review); now they are this field's.
  (define request-field-options
    '((url "CURLU") (method "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD") (headers "HTTPHEADER")
      (body "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION"
            "SEEKDATA" "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT")
      (user-agent "USERAGENT")
      (timeout-ms "TIMEOUT_MS") (connect-timeout-ms "CONNECTTIMEOUT_MS")
      (body-limit "MAXFILESIZE_LARGE") (ca-file "CAINFO" "CAPATH")
      (verify "SSL_VERIFYPEER" "SSL_VERIFYHOST") (proxy "PROXY" "NOPROXY" "FORBID_REUSE")
      (stream-buffer "HEADERFUNCTION" "HEADERDATA") (body-length "INFILESIZE_LARGE")
      (http-version "HTTP_VERSION") (credentials "HTTPAUTH" "USERNAME" "PASSWORD" "XOAUTH2_BEARER")
      (proxy-ca-file "PROXY_CAINFO" "PROXY_CAPATH")
      (proxy-verify "PROXY_SSL_VERIFYPEER" "PROXY_SSL_VERIFYHOST")
      (follow "FOLLOWLOCATION")))

  ;; field-options : Symbol -> (Listof String)
  ;; FIELD's options, in request-field-options' order.
  (define (field-options field) (cdr (assq field request-field-options)))

  ;; field-option : Symbol -> String
  ;; The option of FIELD, a field that sets one; a field that sets several
  ;; is an assertion violation.
  (define (field-option field)
    (let ((names (field-options field)))
      (unless (= (length names) 1)
        (assertion-violation 'field-option "this field sets more than one option" field))
      (car names)))

  ;; proxy-tls-option-names : (Listof String)
  ;; Every option that sets a proxy's TLS but the four the proxy-ca-file and
  ;; proxy-verify fields set, PROXY_CAINFO, PROXY_CAPATH,
  ;; PROXY_SSL_VERIFYPEER and PROXY_SSL_VERIFYHOST, in the options tables of
  ;; the five libcurls the M4 plan measured, 7.85.0 to 8.23.0: each other
  ;; PROXY_SSL_* and PROXY_CA* option, and the rest of the PROXY_ TLS
  ;; settings, which could loosen it too, its version, ciphers and TLS-SRP
  ;; among them. Each is a twin of those fields', owned since M4 (ADR-0024,
  ;; amended 2026-10-26, decided by the maintainer); a proxy's own CA and
  ;; verification are the fields' from M7 slice 3 (ADR-0037, decision 5).
  (define proxy-tls-option-names
    '("PROXY_SSL_OPTIONS" "PROXY_SSL_CIPHER_LIST"
      "PROXY_CAINFO_BLOB" "PROXY_CRLFILE" "PROXY_ISSUERCERT"
      "PROXY_ISSUERCERT_BLOB" "PROXY_PINNEDPUBLICKEY" "PROXY_SSLVERSION" "PROXY_TLS13_CIPHERS"
      "PROXY_SSLCERT" "PROXY_SSLCERT_BLOB" "PROXY_SSLCERTTYPE" "PROXY_SSLKEY" "PROXY_SSLKEY_BLOB"
      "PROXY_SSLKEYTYPE" "PROXY_KEYPASSWD" "PROXY_TLSAUTH_TYPE" "PROXY_TLSAUTH_USERNAME"
      "PROXY_TLSAUTH_PASSWORD"))

  ;; owned-option-names : (Listof String)
  ;; The options the hatch refuses, by name (ADR-0009, amended
  ;; 2026-10-23 to 2026-10-27): those the transfer always sets, QUICK_EXIT
  ;; among them where the libcurl knows it, and MAXREDIRS, pinned at 30
  ;; (ADR-0036, amended 2026-11-02, decision 8), and the protocol pins'
  ;; deprecated bitmasks; then every option of each request field, the
  ;; credentials field's HTTPAUTH, USERNAME, PASSWORD and XOAUTH2_BEARER
  ;; among them; then
  ;; each owned setting's twin, an option with an id of its own that sets
  ;; the same thing:
  ;;   - the timeouts' and the body limit's: TIMEOUT, CONNECTTIMEOUT and
  ;;     MAXFILESIZE, in seconds or as a long;
  ;;   - the method's and the body's: HTTPGET and PUT, which set the
  ;;     method, as the method field's POST and UPLOAD do; POSTFIELDS,
  ;;     POSTFIELDSIZE, HTTPPOST and MIMEPOST, another body, size or form;
  ;;     INFILESIZE, an upload's size, as body-length's INFILESIZE_LARGE;
  ;;   - the URL's: PORT, which replaces its port, and REQUEST_TARGET, its
  ;;     target on the request line (the options tables, M4 slice 1);
  ;;   - the body's and the response's, found by the slice's review: CRLF,
  ;;     which rewrites each LF in what libcurl sends as CRLF, the body's too,
  ;;     and HEADER, which hands the response's head to WRITEFUNCTION with
  ;;     its body, against the body limit;
  ;;   - the CA file's: CAINFO_BLOB, which adds a CA, and SSL_OPTIONS, whose
  ;;     NATIVE_CA adds the system store;
  ;;   - the proxy field's (ADR-0024, decision 1): PRE_PROXY, a SOCKS proxy
  ;;     before it; PROXYPORT and PROXYTYPE, its port and its kind, parts
  ;;     of the proxy PROXY names, as PORT is of the URL. NOPROXY, whose "*"
  ;;     turns the environment's proxy off as PROXY "" does, was its twin
  ;;     until M7 slice 3 made it the field's own;
  ;;   - found by M4 slice 4's review of every option the hatch's types
  ;;     reach, each measured on five libcurls but where named (ADR-0009,
  ;;     amended 2026-10-27, decided by the maintainer): TRANSFERTEXT, which
  ;;     rewrites the body as CRLF does; USERPWD and NETRC, which each
  ;;     replace part of the URL's credentials on some version, as USERNAME
  ;;     and PASSWORD do, which are the credentials field's now, and HSTS,
  ;;     which turns its http:// into https://;
  ;;     UNIX_SOCKET_PATH and ABSTRACT_UNIX_SOCKET, which skip the
  ;;     environment's proxy, as NOPROXY does; PROXYHEADER, whose headers
  ;;     reach a proxied request past the header checks, a second
  ;;     Content-Length among them, and HEADEROPT, whose UNIFIED sends the
  ;;     request's headers to the proxy in a CONNECT;
  ;;   - and, kept from the hatch though no twin: RESUME_FROM and
  ;;     RESUME_FROM_LARGE, which beside a body read stdin on 7.85.0 and
  ;;     send part of the body; COOKIEFILE and COOKIEJAR, whose "-" reads
  ;;     stdin and writes stdout from the engine's thread; CONNECT_ONLY,
  ;;     which sends no request and ends OK; DOH_URL, whose lookups ignore
  ;;     the proxy field; RESOLVE, whose entries reach every later request
  ;;     on the engine through the DNS cache its multi handle shares; and
  ;;     SSLENGINE_DEFAULT, which sets OpenSSL's default for the whole
  ;;     process, by curl's source;
  ;;   - the HTTP version's, measured through the engine on five libcurls
  ;;     (M7 slice 1; ADR-0009, amended 2026-11-02): SSL_ENABLE_ALPN, whose
  ;;     0 turns http/2's HTTP/2 into HTTP/1.1 at a server offering both;
  ;;     ALTSVC, whose cache file, an earlier transfer's or written by hand,
  ;;     moves a later transfer to another port, host and version, at
  ;;     http/1.1 too, and which libcurl writes as the engine cleans the
  ;;     handle up, on its thread; and ALTSVC_CTRL, which alone makes the
  ;;     handle a cache in memory that an Alt-Svc header fills: the 417's
  ;;     resend of a caller's Expect: 100-continue, a second request on the
  ;;     same handle, went to the first response's alternative, another
  ;;     port, and over HTTP/2 to an h2 one (8.20.0, the slice's review); a
  ;;     hatch HTTPAUTH round and the private follow make second requests
  ;;     too. HSTS_CTRL stays the hatch's: libcurl reads
  ;;     Strict-Transport-Security from an https:// response alone, and
  ;;     rewrites an http:// URL alone (7.85.0's url.c and http.c, 8.23.0's
  ;;     hsts_upgrade and Curl_xfer_is_secure, read), and no second
  ;;     request within one transfer changes its URL, but the private
  ;;     follow's, which nothing public sets. PIPEWAIT, HTTP09_ALLOWED,
  ;;     HTTP200ALIASES and CONNECT_TO stay the hatch's too, and
  ;;     HTTPPROXYTUNNEL did until M7 slice 3;
  ;;   - the credentials field's, measured through the engine on five
  ;;     libcurls (M7 slice 2; ADR-0036, amended 2026-11-02): AWS_SIGV4,
  ;;     which set after HTTPAUTH replaced every scheme's header with an
  ;;     AWS4-HMAC-SHA256 signature. FAILONERROR, which makes a wrong
  ;;     password's 401 code 22, AUTOREFERER, which adds a Referer to
  ;;     Digest's second request, KEEP_SENDING_ON_ERROR, UNRESTRICTED_AUTH,
  ;;     which reaches libcurl's own follow alone, DISALLOW_USERNAME_IN_URL,
  ;;     LOGIN_OPTIONS, SASL_AUTHZID, SASL_IR, SERVICE_NAME and NETRC_FILE
  ;;     stay the hatch's, each changing nothing the field sends;
  ;;   - the proxy field's, measured through the engine on five libcurls
  ;;     (M7 slice 3; ADR-0037, amended 2026-11-03): PROXYAUTH,
  ;;     PROXYUSERPWD, PROXYUSERNAME and PROXYPASSWORD, which set a proxy's
  ;;     credentials another way than its URL's userinfo, and decode them
  ;;     differently by version; HTTPPROXYTUNNEL, which moves an http://
  ;;     URL's request from the proxy into a tunnel to the origin, with
  ;;     every caller header, and lets prior knowledge speak HTTP/2 through
  ;;     a named proxy; HAPROXYPROTOCOL, which writes a PROXY line to the
  ;;     proxy by absolute form and to the origin inside a tunnel, breaking
  ;;     a TLS origin's handshake, 35, and HAPROXY_CLIENT_IP, which rewrites
  ;;     that line's addresses: 7.85.0 knows no HAPROXY_CLIENT_IP, and an
  ;;     owned name a libcurl does not know is no id of its own, its
  ;;     attachment refused as unknown-option first.
  ;;     SUPPRESS_CONNECT_HEADERS, PROXY_SERVICE_NAME and SOCKS5_AUTH stay
  ;;     the hatch's, each changing no byte either side got, and nothing
  ;;     chez-curl reads;
  ;; then proxy-tls-option-names. They are compared by id, so an alias name
  ;; is refused too.
  (define owned-option-names
    (append '("URL" "PROTOCOLS_STR" "REDIR_PROTOCOLS_STR" "PROTOCOLS" "REDIR_PROTOCOLS"
              "NOSIGNAL" "QUICK_EXIT" "MAXREDIRS" "WRITEFUNCTION" "WRITEDATA" "ERRORBUFFER")
            (apply append (map cdr request-field-options))
            '("TIMEOUT" "CONNECTTIMEOUT" "MAXFILESIZE" "HTTPGET" "PUT"
              "POSTFIELDS" "POSTFIELDSIZE" "HTTPPOST" "MIMEPOST" "INFILESIZE"
              "PORT" "REQUEST_TARGET" "CRLF" "HEADER" "CAINFO_BLOB" "SSL_OPTIONS"
              "PRE_PROXY" "PROXYPORT" "PROXYTYPE"
              "TRANSFERTEXT" "USERPWD" "NETRC" "HSTS"
              "UNIX_SOCKET_PATH" "ABSTRACT_UNIX_SOCKET" "PROXYHEADER" "HEADEROPT"
              "RESUME_FROM" "RESUME_FROM_LARGE" "COOKIEFILE" "COOKIEJAR" "CONNECT_ONLY"
              "DOH_URL" "RESOLVE" "SSLENGINE_DEFAULT"
              "SSL_ENABLE_ALPN" "ALTSVC" "ALTSVC_CTRL"
              "AWS_SIGV4"
              "PROXYAUTH" "PROXYUSERPWD" "PROXYUSERNAME" "PROXYPASSWORD"
              "HTTPPROXYTUNNEL" "HAPROXYPROTOCOL" "HAPROXY_CLIENT_IP")
            proxy-tls-option-names))

  ;; pinned-options : (Listof (Pairof String (U String Integer)))
  ;; The settings every transfer makes, before its own: ADR-0003's protocol
  ;; pins, PROTOCOLS_STR and REDIR_PROTOCOLS_STR at "http,https", and
  ;; NOSIGNAL at 1, so that no signal handler is installed in a process that
  ;; runs threads; and MAXREDIRS at 30 (ADR-0036, amended 2026-11-02,
  ;; decision 8). libcurl counts each follow it makes against MAXREDIRS,
  ;; FOLLOW_REDIR: a redirect, and every new request a transfer makes
  ;; inside it as one, an auth round, a stale=true round, and a 417's
  ;; resend of a caller's Expect: 100-continue alike; never FOLLOW_RETRY,
  ;; its retry of a request a dead reused or refused connection lost
  ;; (7.85.0 transfer.c:1583-1593; 8.20.0 http.c:1154-1165). 7.85.0's default is
  ;; -1, unbounded: against a server that answers 417, or stale=true, for
  ;; ever, it made about 90,000 and 43,000 requests in 5 s, and with no
  ;; timeout would never stop. At 30 it stops at 31 requests, 47, as 8.5.0
  ;; and later do at their default, 30, and a Digest round still ends in
  ;; two. Nothing public follows a redirect, so the count reaches those
  ;; follows inside a transfer alone. tests/test-transfer.sps writes it
  ;; out.
  (define pinned-options
    '(("PROTOCOLS_STR" . "http,https") ("REDIR_PROTOCOLS_STR" . "http,https") ("NOSIGNAL" . 1)
      ("MAXREDIRS" . 30)))

  ;; quick-exit-pin : (Pairof String Integer)
  ;; ADR-0019's setting, QUICK_EXIT at 1: taken apart during a stalled name
  ;; lookup, or timed out in one, the transfer leaves libcurl's resolver
  ;; thread behind rather than wait for it. libcurl has it from 7.87.0.
  ;; tests/test-transfer.sps writes it out.
  (define quick-exit-pin '("QUICK_EXIT" . 1))

  ;; pinned-settings : Boolean -> (Listof (Pairof String (U String Integer)))
  ;; The settings a transfer makes before its own, in order: pinned-options,
  ;; then quick-exit-pin when QUICK-EXIT. tests/test-transfer.sps writes out
  ;; both answers.
  (define (pinned-settings quick-exit)
    (if quick-exit (append pinned-options (list quick-exit-pin)) pinned-options))

  ;; quick-exit-known? : -> Boolean
  ;; Whether the loaded libcurl knows quick-exit-pin's option, by name: the
  ;; floor, 7.85.0, does not (ADR-0019, decision 1).
  (define (quick-exit-known?)
    (and (curl-easy-option (car quick-exit-pin)) #t))

  ;; locked : Mutex (-> Any) -> Any
  ;; THUNK's value, run holding LOCK, in a critical section. Chez's
  ;; with-mutex is a dynamic-wind whose before thunk takes the mutex, so an
  ;; interrupt that escapes, an engine's expiry say, between the take and
  ;; the wind would leave it held, with no after thunk to release it, and
  ;; block every other thread. Every mutex here is held through locked.
  (define (locked lock thunk)
    (critical-section (with-mutex lock (thunk))))

  ;; The options looked up, by name: (ID . TYPE), or unknown. Once per name,
  ;; per process, under the mutex; and the owned ids, once.
  (define option-cache (make-hashtable string-hash string=?))
  (define option-lock (make-mutex))
  (define owned-ids #f)

  ;; option-found : String -> (U (Pairof Integer Natural) #f)
  ;; NAME's id and CURLOT type in the loaded libcurl, or #f when it does not
  ;; know NAME, looked up once per name, per process, under the mutex. NAME
  ;; is copied first: the copy is the cache's key, and what is looked up,
  ;; so the caller's string may change after. A NAME that is no string, or
  ;; holds U+0000, which curl_easy_option_by_name would read short, is an
  ;; assertion violation.
  (define (option-found name)
    (unless (string? name)
      (assertion-violation 'set-option! "an option's name is a string without U+0000" name))
    (let ((name (string-copy name)))
      (when (memv #\nul (string->list name))
        (assertion-violation 'set-option! "an option's name is a string without U+0000" name))
      (let ((found (locked option-lock
                     (lambda ()
                       (or (hashtable-ref option-cache name #f)
                           (let ((option (or (curl-easy-option name) 'unknown)))
                             (hashtable-set! option-cache name option)
                             option))))))
        (and (not (eq? found 'unknown)) found))))

  ;; option-named : String -> (Pairof Integer Natural)
  ;; option-found's answer for NAME; unknown-option, naming it, when the
  ;; loaded libcurl does not know NAME.
  (define (option-named name)
    (or (option-found name) (fail 'unknown-option #f name #f #f)))

  ;; cached-option-names : -> (Listof String)
  ;; The option cache's keys, sorted: a private accessor, for the test that
  ;; a caller's name, changed after, leaves them as they were.
  (define (cached-option-names)
    (list-sort string<? (locked option-lock (lambda () (vector->list (hashtable-keys option-cache))))))

  ;; owned-option-ids : -> (Listof Integer)
  ;; The ids of owned-option-names the loaded libcurl knows, found once.
  (define (owned-option-ids)
    (or owned-ids
        (let ((ids (fold-left (lambda (found name)
                                (let ((option (curl-easy-option name)))
                                  (if option (cons (car option) found) found)))
                              '() owned-option-names)))
          (locked option-lock (lambda () (unless owned-ids (set! owned-ids ids))))
          owned-ids)))

  ;; setopt-accepted? : (U String Integer #f) Integer -> Boolean
  ;; Whether CODE, curl_easy_setopt's answer to a setting of VALUE, is
  ;; taken: CURLE_OK, always; CURLE_NOT_BUILT_IN too when VALUE is #f, a
  ;; clear, since a build without the option holds nothing to clear, as a
  ;; TLS backend with no CA directory answers CAPATH (ADR-0018). Any other
  ;; code, and CURLE_NOT_BUILT_IN for a string or a number, is refused.
  (define (setopt-accepted? value code)
    (or (eqv? code curle-ok)
        (and (not value) (eqv? code curle-not-built-in))))

  ;; set-option! : Positive-Integer String (U Integer #f) (U Positive-Integer #f) -> Void
  ;; Sets the option NAME on EASY to VALUE, through the binding its CURLOT
  ;; type takes, once VALUE is checked against that type: a long or an
  ;; off_t in range, or a pointer, an exact natural, or #f, sent as NULL,
  ;; which clears it. A value that does not fit is an assertion violation.
  ;; A code setopt-accepted? refuses raises setopt-failed, naming NAME,
  ;; with BUFFER's text.
  (define (set-option! easy name value buffer)
    (let* ((option (option-named name))
           (binding (option-binding (cdr option))))
      (unless (case binding
                ((long) (long? value))
                ((off-t) (off-t? value))
                (else (or (not value) (pointer? value))))
        (assertion-violation 'set-option! "the value does not fit the option's type" name (shown-value value)))
      (let ((code ((option-setter binding) easy (car option) (or value 0))))
        (unless (setopt-accepted? value code)
          (fail 'setopt-failed code name buffer #f)))))

  ;; set-string-option! : Positive-Integer String String (U Positive-Integer #f) -> Void
  ;; NAME set to a counted UTF-8 copy of TEXT, freed once setopt returns:
  ;; libcurl copies its string options (plan, section 2).
  (define (set-string-option! easy name text buffer)
    (call-with-c-string text (lambda (address) (set-option! easy name address buffer))))

  ;; set-pinned-options! : Positive-Integer (U Positive-Integer #f) Boolean -> Void
  ;; Each of pinned-settings' answer set on EASY, in order: a string through
  ;; a C string, a number as it is. QUICK_EXIT is among them when
  ;; QUICK-EXIT, the engine's say, and the loaded libcurl knows it; once
  ;; libcurl has taken it, it is counted, for quick-exits-set.
  (define (set-pinned-options! easy buffer quick-exit)
    (let ((settings (pinned-settings (and quick-exit (quick-exit-known?)))))
      (for-each (lambda (pin)
                  (if (string? (cdr pin))
                      (set-string-option! easy (car pin) (cdr pin) buffer)
                      (set-option! easy (car pin) (cdr pin) buffer)))
                settings)
      (when (member quick-exit-pin settings)
        (locked sinks-lock (lambda () (set! quick-exit-count (+ quick-exit-count 1)))))))

  ;; tls-settings : (U String #f) Boolean -> (Listof (Pairof String (U String Integer #f)))
  ;; The TLS settings for a snapshot's CA-FILE and VERIFY (ADR-0018), in
  ;; order: verify's options, SSL_VERIFYPEER at 1 and SSL_VERIFYHOST at 2,
  ;; or both at 0 when VERIFY is #f; then, with a CA file alone, ca-file's,
  ;; CAINFO at its path and CAPATH at #f, a clear, so that no CA directory
  ;; the build defaults to is trusted beside it. A CA-FILE of #f is
  ;; libcurl's system store, as built, and sets neither. The names are
  ;; request-field-options', in its order. tests/test-transfer-tls.sps
  ;; writes out all four answers.
  (define (tls-settings ca-file verify)
    (let ((verify-names (field-options 'verify))
          (ca-file-names (field-options 'ca-file)))
      (append (list (cons (car verify-names) (if verify 1 0))
                    (cons (cadr verify-names) (if verify 2 0)))
              (if ca-file
                  (list (cons (car ca-file-names) ca-file) (cons (cadr ca-file-names) #f))
                  '()))))

  ;; set-tls-options! : Positive-Integer (U String #f) Boolean (U Positive-Integer #f) -> Void
  ;; Each of tls-settings' answer for CA-FILE and VERIFY set on EASY, in
  ;; order: a string through set-string-option!, a counted UTF-8 copy, and
  ;; a number, or #f as NULL, through set-option!, which judges each code
  ;; by setopt-accepted?. tests/test-transfer-tls.sps holds it whole.
  (define (set-tls-options! easy ca-file verify buffer)
    (for-each (lambda (setting)
                (if (string? (cdr setting))
                    (set-string-option! easy (car setting) (cdr setting) buffer)
                    (set-option! easy (car setting) (cdr setting) buffer)))
              (tls-settings ca-file verify)))

  ;; version-settings : (U Symbol #f) -> (Listof (Pairof String Integer))
  ;; The settings an http-version VERSION makes (ADR-0034), as data: #f,
  ;; none, so libcurl keeps its own; http/1.1, HTTP_VERSION at
  ;; CURL_HTTP_VERSION_1_1; http/2, at CURL_HTTP_VERSION_2TLS, not 2_0,
  ;; whose Upgrade: h2c over http:// no server here takes (the M7 plan,
  ;; section 3.1); http/2-prior-knowledge, at
  ;; CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE. Any other VERSION is an assertion
  ;; violation. The name is request-field-options'. Pure.
  ;; tests/test-version.sps writes out every answer.
  (define (version-settings version)
    (let ((name (field-option 'http-version)))
      (case version
        ((#f) '())
        ((http/1.1) (list (cons name curl-http-version-1-1)))
        ((http/2) (list (cons name curl-http-version-2tls)))
        ((http/2-prior-knowledge) (list (cons name curl-http-version-2-prior-knowledge)))
        (else (assertion-violation 'version-settings "not an http-version" version)))))

  ;; credentials-settings : (U Credentials #f) -> (Listof (Pairof String (U Integer String)))
  ;; The settings a request's CREDENTIALS make (ADR-0036), as data, in
  ;; order: #f, none, so libcurl sends no credentials of the field's;
  ;; (basic U P), HTTPAUTH at CURLAUTH_BASIC, USERNAME at U and PASSWORD at
  ;; P; (digest U P), HTTPAUTH at CURLAUTH_DIGEST, then the same two;
  ;; (bearer T), HTTPAUTH at CURLAUTH_BEARER and XOAUTH2_BEARER at T. One
  ;; scheme's bit alone, never a set nor ANY: libcurl then sends Basic and
  ;; Bearer on the first request, and Digest after a bare one. HTTPAUTH
  ;; first: libcurl reads every one as the transfer starts, whatever the
  ;; order. Each string is the answer's, set as UTF-8 by set-string-option!
  ;; (ADR-0036, decision 5). Anything but credentials-copy's shape is an
  ;; assertion violation, naming its scheme alone. The names are
  ;; request-field-options'. Pure. tests/test-auth.sps writes out every
  ;; scheme's answer.
  (define (credentials-settings credentials)
    (let ((names (field-options 'credentials)))
      (cond ((not credentials) '())
            ((not (and (pair? credentials) (assq (car credentials) credentials-arities)
                       (list? credentials)
                       (= (length credentials) (+ 1 (cdr (assq (car credentials) credentials-arities))))
                       (for-all string? (cdr credentials))))
             (assertion-violation 'credentials-settings "not credentials"
                                  (if (pair? credentials) (car credentials) 'credentials)))
            ((eq? (car credentials) 'bearer)
             (list (cons (car names) curlauth-bearer) (cons (cadddr names) (cadr credentials))))
            (else
             (list (cons (car names) (if (eq? (car credentials) 'basic) curlauth-basic curlauth-digest))
                   (cons (cadr names) (cadr credentials))
                   (cons (caddr names) (caddr credentials)))))))

  ;; proxy-settings : (U 'environment #f String) (U String #f) Boolean
  ;;                  -> (Listof (Pairof String (U String Integer #f)))
  ;; The settings a request's PROXY, its PROXY-CA-FILE and its VERIFY make
  ;; (ADR-0024, decision 1; ADR-0037), as data, in order: environment, none,
  ;; so libcurl reads the proxy variables by its own rules, and keeps its
  ;; verified default for the proxy they name; #f, PROXY at "", which reads
  ;; none of them; a URL, the one a submit hands libcurl, its scheme's port
  ;; set when it named none: PROXY at it and NOPROXY at "", so no_proxy and
  ;; NO_PROXY send nothing around it, then the proxy's verification,
  ;; PROXY_SSL_VERIFYPEER at 1 and PROXY_SSL_VERIFYHOST at 2, or both at 0
  ;; when VERIFY is #f, then, with a PROXY-CA-FILE alone, PROXY_CAINFO at its
  ;; path and PROXY_CAPATH at #f, a clear, so the file is the proxy's only
  ;; anchor, as tls-settings makes the origin's (ADR-0018). An http:// proxy
  ;; URL's verification is set alike, and reads nothing: a submit refuses a
  ;; proxy CA file, and VERIFY #f, beside any proxy but an https:// URL. Any
  ;; other PROXY is an assertion violation, naming proxy alone. The names
  ;; are request-field-options'. Pure. tests/test-proxy.sps writes out every
  ;; answer.
  (define (proxy-settings proxy proxy-ca-file verify)
    (let ((names (field-options 'proxy))
          (ca-names (field-options 'proxy-ca-file))
          (verify-names (field-options 'proxy-verify)))
      (cond ((eq? proxy 'environment) '())
            ((not proxy) (list (cons (car names) "")))
            ((string? proxy)
             (append (list (cons (car names) proxy) (cons (cadr names) "")
                           (cons (car verify-names) (if verify 1 0))
                           (cons (cadr verify-names) (if verify 2 0)))
                     (if proxy-ca-file
                         (list (cons (car ca-names) proxy-ca-file) (cons (cadr ca-names) #f))
                         '())))
            (else (assertion-violation 'proxy-settings "not a proxy" 'proxy)))))

  ;; unshared-tunnel-floor : Positive-Integer
  ;; 8.19.0's version_num, #x081300: the first libcurl whose match of a
  ;; pooled proxy connection compares the proxy's user and password, so no
  ;; request rides a tunnel another user's credentials opened
  ;; (CVE-2026-3784, "wrong proxy connection reuse with credentials", in
  ;; curl 7.7 to 8.18.0). tests/test-proxy.sps writes it out.
  (define unshared-tunnel-floor #x081300)

  ;; unshared-tunnel-settings : Natural (U String #f) Boolean Boolean
  ;;                            -> (Listof (Pairof String Integer))
  ;; The settings that keep a tunnel through a named proxy unshared, by
  ;; ADR-0037's decision 8 (amended 2026-11-03), as data: on a libcurl whose
  ;; VERSION-NUMBER is below unshared-tunnel-floor, a transfer to an https://
  ;; URL, SCHEME being the scheme libcurl gives back, in lower case, through
  ;; a PROXY-URL, FRESH_CONNECT at 1, so it joins no connection, live or
  ;; pooled; and with USERINFO, a user or a password in the proxy URL,
  ;; FORBID_REUSE at 1 too, so it leaves none behind. () otherwise: an
  ;; http:// URL's request goes to the proxy by absolute form, each with its
  ;; own credentials, and from 8.19.0 libcurl's own match keeps another
  ;; user's request off a tunnel. 7.85.0 let a second transfer, a turn
  ;; after the first, with another user's userinfo, a wrong password or none,
  ;; ride the first's authenticated tunnel and get 200; Ubuntu's 8.5.0
  ;; carries the fix, but a version cannot show a backport, so it pays for
  ;; the new connection too (M7 slice 3's measurement). FRESH_CONNECT is
  ;; the streamed body's too: the transfer sets it once when either asks.
  ;; The names are request-field-options'. Pure. tests/test-proxy.sps
  ;; writes out every answer.
  (define (unshared-tunnel-settings version-number scheme proxy-url userinfo)
    (let ((fresh (list-ref (field-options 'body) 8))
          (forbid (list-ref (field-options 'proxy) 2)))
      (if (and proxy-url (equal? scheme "https") (< version-number unshared-tunnel-floor))
          (if userinfo
              (list (cons fresh 1) (cons forbid 1))
              (list (cons fresh 1)))
          '())))

  ;; stops-multiplexing? : Natural Boolean Boolean -> Boolean
  ;; Whether a transfer stops its engine's multiplexing, by ADR-0037's
  ;; decision 11: on a libcurl whose VERSION-NUMBER is below
  ;; unshared-tunnel-floor, a transfer through a PROXY-URL whose USERINFO
  ;; holds a user or a password, whatever its URL's scheme. Before 8.19.0
  ;; libcurl matches a live proxy connection by host and port alone, so on
  ;; 7.85.0 a transfer through proxy environment, its variable naming the
  ;; same proxy with no userinfo, rode a named proxy's live authenticated
  ;; tunnel as a second HTTP/2 stream and got 200 (M7 slice 3's review);
  ;; FRESH_CONNECT keeps only the transfer that sets it off a live
  ;; connection. An engine that does not multiplex sent that transfer's own
  ;; CONNECT. The engine's thread acts on it, before the transfer's handle
  ;; is added, and never resumes. Pure. tests/test-proxy.sps writes out
  ;; every answer.
  (define (stops-multiplexing? version-number proxy-url userinfo)
    (and proxy-url userinfo (< version-number unshared-tunnel-floor) #t))

  ;; tls-in-tls-stalls : (Listof (List String (U String #f) (Listof (U Symbol #f))))
  ;; The libcurls where an https:// URL through an https:// proxy stalls,
  ;; its request sent and the origin's answer tunnelled back, until the
  ;; transfer's timeout, 28, each (VERSION BACKEND VERSIONS-ASKED): its
  ;; version, the TLS backend in use, by its name's start, #f for any, and
  ;; the http-version values that stall there (ADR-0037, decisions 7 and
  ;; 10). Ubuntu's 8.5.0 with GnuTLS stalled an https:// URL and an HTTP/2
  ;; one, ten times of ten in each run, whatever was asked; 7.85.0 stalled an
  ;; HTTP/2 one at times, 7 of 50 across five runs, and passed HTTP/1.1 50
  ;; of 50, so it stalls for any request but one asking http/1.1, which
  ;; keeps the server from choosing HTTP/2 (M7 slice 3's measurement).
  ;; Keyed as the engine's multiplexing rule is, by the loaded libcurl's
  ;; version, and by the backend as ADR-0024's table keys by more than a
  ;; version. tests/test-proxy.sps holds it to its own copy.
  (define tls-in-tls-stalls
    '(("7.85.0" #f (#f http/2))
      ("8.5.0" "GnuTLS" (#f http/1.1 http/2))))

  ;; tls-in-tls-stall? : String (U String #f) (U Symbol #f) -> Boolean
  ;; Whether tls-in-tls-stalls holds a row for VERSION whose backend is
  ;; any, or begins BACKEND's name, the backend in use, or BACKEND could not
  ;; be read, which errs toward refusing, and whose values asked hold
  ;; HTTP-VERSION. Pure.
  (define (tls-in-tls-stall? version backend http-version)
    (and (exists (lambda (row)
                   (and (string=? (car row) version)
                        (or (not (cadr row)) (not (string? backend))
                            (string-prefix? (cadr row) backend))
                        (memq http-version (caddr row))
                        #t))
                 tls-in-tls-stalls)
         #t))

  ;; --- the hatch (ADR-0009; the M4 plan, section 3.7) ---------------------------------

  ;; hatch-types : (Listof Symbol)
  ;; The CURLOT types the hatch takes: long, enumerated values, off_t, a
  ;; string, a string list and a blob. Every other hands libcurl an object,
  ;; a callback's pointer or a function (ADR-0009, decision 3).
  (define hatch-types '(long values off-t string slist blob))

  ;; A hatch setting: an option the hatch attached to a request, its name as
  ;; given, its id and its CURLOT type's name in the loaded libcurl, and its
  ;; value, a private copy, checked: no caller holds it.
  (define-record-type hatch-setting
    (fields (immutable name) (immutable id) (immutable type) (immutable value)))

  ;; refuse-option : Symbol String Symbol -> Nothing
  ;; The hatch's refusal, as WHO, of the option NAME, for REASON: a
  ;; &curl-request-error, field options, whose value is NAME.
  (define (refuse-option who name reason)
    (raise (condition (make-curl-request-error 'options name reason)
                      (make-who-condition who)
                      (make-message-condition
                       (case reason
                         ((unknown-option) "the loaded libcurl knows no option by this name")
                         ((owned-option) "chez-curl owns this option: it sets it, sets it another way, or keeps it from the hatch")
                         ((unsupported-type) "the hatch takes long, enumerated-value, off_t, string, string-list and blob options alone")
                         ((repeated-option) "the request carries this option already, by this name or another of its id")
                         ((embedded-nul) "a string of the option's value holds U+0000, which C would read as its end")
                         (else "a string of the option's value holds CR or LF, which could end a line libcurl sends")))
                      (make-irritants-condition (list name)))))

  ;; option-pairs : Symbol Any -> (Listof (Pairof String Any))
  ;; OPTIONS, a list of (NAME . VALUE) pairs, each NAME a string, as fresh
  ;; pairs holding a fresh copy of each NAME, in order; any other shape is
  ;; an assertion violation from WHO. The list is walked by the count it had
  ;; when checked, so another thread that changes it meanwhile is refused,
  ;; never followed round a cycle.
  (define (option-pairs who options)
    (define (wrong) (assertion-violation who "options are a list of (NAME . VALUE), each NAME a string" (shown-value options)))
    (unless (list? options) (wrong))
    (let loop ((rest options) (left (length options)) (found '()))
      (cond ((and (null? rest) (= left 0)) (reverse found))
            ((or (= left 0) (not (pair? rest))) (wrong))
            (else
             (let ((option (car rest)))
               (unless (and (pair? option) (string? (car option))) (wrong))
               (loop (cdr rest) (- left 1)
                     (cons (cons (string-copy (car option)) (cdr option)) found)))))))

  ;; text-fault : String -> (U Symbol #f)
  ;; The reason the hatch refuses S, read left to right, its first offending
  ;; char deciding: U+0000 embedded-nul, CR or LF line-break; #f when none
  ;; offends.
  (define (text-fault s)
    (let ((n (string-length s)))
      (let loop ((i 0))
        (and (< i n)
             (case (char->integer (string-ref s i))
               ((0) 'embedded-nul)
               ((10 13) 'line-break)
               (else (loop (+ i 1))))))))

  ;; hatch-value : Symbol String Symbol Any -> Any
  ;; VALUE, the value of the option NAME, of the hatch type TYPE, as the
  ;; setting keeps it: copied first, and the copy checked (ADR-0009,
  ;; decision 3). A long or an enumerated value is an exact integer a C long
  ;; holds; an off_t one a 64-bit signed one, each kept as it is; a string a
  ;; fresh copy; a blob a fresh copy of a bytevector; a string list fresh
  ;; pairs of fresh copies, walked by its count as option-pairs walks. A
  ;; value of the wrong shape, or out of range, is an assertion violation
  ;; from WHO; then a copied string that holds U+0000, CR or LF, the list's
  ;; each in turn, is refused by text-fault's reason.
  (define (hatch-value who name type value)
    (define (wrong message) (assertion-violation who message (cons name (shown-value value))))
    (define (checked text)
      (let ((fault (text-fault text)))
        (when fault (refuse-option who name fault))
        text))
    (case type
      ((long values)
       (unless (long? value) (wrong "the option takes an exact integer a C long holds"))
       value)
      ((off-t)
       (unless (off-t? value) (wrong "the option takes an exact integer a curl_off_t holds"))
       value)
      ((string)
       (unless (string? value) (wrong "the option takes a string"))
       (checked (string-copy value)))
      ((blob)
       (unless (bytevector? value) (wrong "the option takes a bytevector"))
       (bytevector-copy value))
      (else
       (unless (list? value) (wrong "the option takes a list of strings"))
       (let ((copies
              (let loop ((rest value) (left (length value)) (found '()))
                (cond ((and (null? rest) (= left 0)) (reverse found))
                      ((or (= left 0) (not (pair? rest)))
                       (wrong "the option takes a list of strings"))
                      (else
                       (let ((element (car rest)))
                         (unless (string? element) (wrong "the option takes a list of strings"))
                         (loop (cdr rest) (- left 1) (cons (string-copy element) found))))))))
         (for-each checked copies)
         copies))))

  ;; curl-request-with-options : Request (Listof (Pairof String Any)) -> Request
  ;; A new request, REQUEST's fields and the options it carries kept, with
  ;; each of OPTIONS, (NAME . VALUE) pairs, attached after them, in order:
  ;; the hatch, which (curl unsupported) exports and (curl) does not
  ;; (ADR-0009). The engine sets them last, after every option chez-curl
  ;; sets itself. Each is checked as it is attached, on this thread, and
  ;; the setting keeps a copy, the one checked, so the caller's objects are
  ;; never read again. In order, the first refusal raising:
  ;;   - REQUEST no request, or OPTIONS of another shape, an assertion
  ;;     violation;
  ;;   - then each option, its name first: one holding U+0000, which
  ;;     curl_easy_option_by_name would read short, embedded-nul; one the
  ;;     loaded libcurl does not know, unknown-option; one whose id is an
  ;;     owned option's, an alias's too, owned-option; one of a type but
  ;;     hatch-types', unsupported-type; one whose id the request carries
  ;;     already, or an earlier option here, repeated-option;
  ;;   - then its value, by hatch-value's rules.
  ;; Each refusal of a name or a string is a &curl-request-error, field
  ;; options, naming the option as given. Then REQUEST's own fields are
  ;; checked, as curl-request-with checks them.
  (define (curl-request-with-options request options)
    (define who 'curl-request-with-options)
    (unless (curl-request? request) (assertion-violation who "not a request" (shown-value request)))
    (let loop ((rest (option-pairs who options))
               (found (reverse (curl-request-options request))))
      (if (null? rest)
          (request-like who request '() (curl-request-url request) (curl-request-fault request)
                        (curl-request-follow request) (reverse found))
          (let ((name (caar rest)))
            (when (memv #\nul (string->list name)) (refuse-option who name 'embedded-nul))
            (let* ((option (or (option-found name) (refuse-option who name 'unknown-option)))
                   (type (find (lambda (entry) (eqv? (cdr entry) (cdr option))) curlot-types)))
              (when (memv (car option) (owned-option-ids)) (refuse-option who name 'owned-option))
              (unless (and type (memq (car type) hatch-types))
                (refuse-option who name 'unsupported-type))
              (when (find (lambda (setting) (eqv? (hatch-setting-id setting) (car option))) found)
                (refuse-option who name 'repeated-option))
              (loop (cdr rest)
                    (cons (make-hatch-setting name (car option) (car type)
                                              (hatch-value who name (car type) (cdar rest)))
                          found)))))))

  ;; hatch-settings-of : Request -> (Listof (List String Symbol Any))
  ;; The hatch settings REQUEST carries, in order, each (NAME TYPE VALUE),
  ;; fresh copies all: a private accessor, for the tests that a setting
  ;; keeps a copy of its own. Neither (curl) nor (curl unsupported) exports
  ;; it.
  (define (hatch-settings-of request)
    (unless (curl-request? request)
      (assertion-violation 'hatch-settings-of "not a request" (shown-value request)))
    (map (lambda (setting)
           (let ((value (hatch-setting-value setting)))
             (list (string-copy (hatch-setting-name setting)) (hatch-setting-type setting)
                   (cond ((string? value) (string-copy value))
                         ((bytevector? value) (bytevector-copy value))
                         ((list? value) (map string-copy value))
                         (else value)))))
         (curl-request-options request)))

  ;; set-hatch-option! : Positive-Integer Hatch-Setting (U Natural #f) (U Positive-Integer #f) -> Void
  ;; SETTING set on EASY, by its type: a long, an enumerated value or an
  ;; off_t through set-option!, which sends each through its type's binding;
  ;; a string through set-string-option!, a counted UTF-8 copy; a blob
  ;; through call-with-curl-blob, a counted struct curl_blob flagged
  ;; CURL_BLOB_COPY; a string list as LIST, the string list start-transfer!
  ;; built for it, or #f, NULL, for an empty one. Each code libcurl answers
  ;; is judged by setopt-accepted?.
  (define (set-hatch-option! easy setting list buffer)
    (let ((name (hatch-setting-name setting))
          (value (hatch-setting-value setting)))
      (case (hatch-setting-type setting)
        ((string) (set-string-option! easy name value buffer))
        ((blob) (call-with-curl-blob value
                  (lambda (address) (set-option! easy name address buffer))))
        ((slist) (set-option! easy name list buffer))
        (else (set-option! easy name value buffer)))))

  ;; --- the transfers the callables serve ------------------------------------------------

  ;; A sink is what one transfer's callables write to: its limit and its
  ;; planted fault, the bytes received, the chunks kept, newest first, the
  ;; log of what libcurl handed it, and what was recorded, #f or (REASON .
  ;; OBJECT); its response stream, #f for a whole body; the counter its
  ;; engine reads, a vector of one natural, bumped for every callable's
  ;; call that took bytes, which tells the paced poll that a turn moved
  ;; one (the M6 plan, section 3.4); and, for a stream, the write
  ;; callable's calls so far, which a planted fault counts, the easy
  ;; handle the header callable reads, whether it has published the head,
  ;; and the head's lines so far, which a planted (head N) counts; and, for
  ;; a streamed body, its request stream, #f otherwise, whether the
  ;; engine's rewinding seam lets the seek callable answer OK once bytes
  ;; were handed, the read callable's calls so far, which a planted
  ;; (read N) counts, and the engine's prereq-hold seam's HOLD, a thunk the
  ;; prerequest callable calls at the first attempt, #f but for that seam.
  ;; Every field but the streams' is the engine thread's alone.
  ;;
  ;; The log of a whole body keeps every chunk, (LENGTH THREAD VERDICT),
  ;; newest first; a stream's keeps, for each verdict, how many calls had
  ;; it and the threads they ran on, so a long stream's log stays small
  ;; (the M6 plan, section 3.2).
  (define-record-type sink
    (fields (immutable limit) (immutable fault)
            (mutable received) (mutable chunks) (mutable log) (mutable recorded)
            (immutable stream) (immutable moves) (mutable offers) (mutable easy)
            (mutable published) (mutable lines) (immutable upload) (immutable rewinding)
            (mutable reads) (immutable prereq-hold)))

  ;; The live transfers, by key, and the next key, under the mutex. Every
  ;; engine's thread reads it: each callable serves them all.
  (define sinks (make-eqv-hashtable))
  (define sinks-lock (make-mutex))
  (define next-key 1)

  ;; live-transfer-count : -> Natural
  ;; How many transfers the table holds now: a private accessor, for the
  ;; test that it is empty once they have ended.
  (define (live-transfer-count)
    (locked sinks-lock (lambda () (hashtable-size sinks))))

  ;; How many transfers have set QUICK_EXIT, ever, under sinks-lock.
  (define quick-exit-count 0)

  ;; quick-exits-set : -> Natural
  ;; How many transfers have set QUICK_EXIT in this process, ever, each
  ;; counted once libcurl took it: a private accessor, for the test that an
  ;; engine's transfers set it, or leave it out, as the engine says
  ;; (ADR-0019).
  (define (quick-exits-set)
    (locked sinks-lock (lambda () quick-exit-count)))

  ;; transfers-started : -> Natural
  ;; How many transfers start-transfer! has registered in this process, ever:
  ;; a private accessor, for the test that a cancel or a stop of a queued
  ;; token makes nothing native. One less than the next key.
  (define (transfers-started)
    (locked sinks-lock (lambda () (- next-key 1))))

  ;; sink-of : Natural -> (U Sink #f)
  (define (sink-of key)
    (locked sinks-lock (lambda () (hashtable-ref sinks key #f))))

  ;; record! : Natural Symbol Any -> Void
  ;; REASON and OBJECT recorded against KEY's transfer, unless something is
  ;; recorded already. It never raises: the callables' guards call it.
  (define (record! key reason object)
    (guard (e (#t #f))
      (let ((sink (sink-of key)))
        (when (and sink (not (sink-recorded sink)))
          (sink-recorded-set! sink (cons reason object))))))

  ;; moved! : Sink -> Void
  ;; SINK's engine's counter, bumped: a callable took bytes. The engine's
  ;; thread alone runs the callables and reads it, so it needs no mutex.
  (define (moved! sink)
    (let ((moves (sink-moves sink)))
      (vector-set! moves 0 (+ (vector-ref moves 0) 1))))

  ;; planted-fault : Positive-Integer -> (List 'planted-fault Positive-Integer)
  ;; What write-body raises at the chunk N a request's fault names: data, so
  ;; a test can tell it from every other raise.
  (define (planted-fault n) (list 'planted-fault n))

  ;; planted-head-fault : Positive-Integer -> (List 'planted-head-fault Positive-Integer)
  ;; What read-head raises at the head's line N a request's (head N) names:
  ;; data, as planted-fault's.
  (define (planted-head-fault n) (list 'planted-head-fault n))

  ;; planted-upload-fault : Symbol Positive-Integer -> (List 'planted-upload-fault Symbol Positive-Integer)
  ;; What the request stream's callable KIND raises at its call N, as a
  ;; request's (KIND N) names: data, as planted-fault's.
  (define (planted-upload-fault kind n) (list 'planted-upload-fault kind n))

  ;; upload-fault-at! : Sink Symbol Positive-Integer -> Void
  ;; Raises (planted-upload-fault KIND N) when SINK's planted fault is
  ;; (KIND N), N being this call's count.
  (define (upload-fault-at! sink kind n)
    (let ((fault (sink-fault sink)))
      (when (and (upload-fault? fault) (eq? (car fault) kind) (= (cadr fault) n))
        (raise (planted-upload-fault kind n)))))

  ;; --- the response stream (ADR-0030; the M6 plan, sections 3.2 to 3.5) ----------------

  ;; curl-head? : Any -> Boolean
  ;; curl-head-status : Head -> Integer
  ;; curl-head-http-version : Head -> (U Symbol Integer #f)
  ;; curl-head-headers : Head -> (Listof (Pairof String String))
  ;; curl-head-body-asked? : Head -> Boolean
  ;; A streamed response's final head, read by the header callable at its
  ;; empty line, as finish-transfer reads a response's: RESPONSE_CODE;
  ;; HTTP_VERSION, by http-version-symbol; and every CURLH_HEADER header of
  ;; request -1, as Latin-1 strings in libcurl's order. It reads no length:
  ;; 8.7.1 writes the empty line before it reads one (the M6 plan, section
  ;; 2.2). And whether libcurl had asked for the request's body by this
  ;; head: #t when the request streams its body and the read callable had
  ;; been called, read in the hold that publishes the head; #f otherwise, a
  ;; request that does not stream its body among them (the M6 plan, section
  ;; 3.2; ADR-0032, decision 3).
  (define-record-type (curl-head make-curl-head curl-head?)
    (fields (immutable status unchecked-curl-head-status)
            (immutable http-version unchecked-curl-head-http-version)
            (immutable headers unchecked-curl-head-headers)
            (immutable body-asked unchecked-curl-head-body-asked?)))

  ;; Each accessor checks its argument first: anything else is an assertion
  ;; violation from the accessor, naming it by its kind, shown-value's,
  ;; never printed, as Chez's own check printed it (ADR-0036, amended
  ;; 2026-11-03).
  (define curl-head-status
    (checked-accessor 'curl-head-status curl-head? "a head" unchecked-curl-head-status))
  (define curl-head-http-version
    (checked-accessor 'curl-head-http-version curl-head? "a head" unchecked-curl-head-http-version))
  (define curl-head-headers
    (checked-accessor 'curl-head-headers curl-head? "a head" unchecked-curl-head-headers))
  (define curl-head-body-asked?
    (checked-accessor 'curl-head-body-asked? curl-head? "a head" unchecked-curl-head-body-asked?))

  ;; A response stream, made at submit, one per submit, with its plan
  ;; (ADR-0030, decision 1): its mutex and its stream-buffer, LIMIT. Its
  ;; pieces are a queue of pairs, (PIECE . NEXT), behind a sentinel pair.
  ;;
  ;;   - Under its mutex, the engine's thread writes the queue's tail, the
  ;;     bytes appended, and the receive bit, set by the write callable in
  ;;     the hold that found the buffer full; the pauses, and the most the
  ;;     buffer held as an append left it; the head, once, and when, and
  ;;     when the first piece was appended, each a monotonic time in ns; and
  ;;     the resumes carried out, with the last one's delay.
  ;;   - Under its mutex too, the flag that a resume is queued, and when:
  ;;     a look sets it, and the resume step clears it, with the bit, in
  ;;     one hold (the M6 plan, section 3.4).
  ;;   - Under its mutex, a test seam's stall: #f, or a vector of its
  ;;     milliseconds and its phase, armed, stalling or done.
  ;;   - The taker alone writes the queue's front, the pair before the next
  ;;     piece, and the bytes taken, outside any hold, the last thing a take
  ;;     does (section 3.5). The buffer is the bytes appended less those
  ;;     taken: the engine reads the taker's count, and a count it reads
  ;;     late is a buffer it takes for fuller, which pauses, and a later
  ;;     look resumes.
  ;;
  ;; One taker at a time: the engine's token operations take from it, and a
  ;; test seam's plant, data on the token, never a procedure, may hold one up.
  ;;
  ;; response-stream? : Any -> Boolean
  ;; stream-lock : Stream -> Mutex
  ;; stream-limit : Stream -> Positive-Integer
  (define-record-type (response-stream make-stream-record response-stream?)
    (fields (immutable lock stream-lock)
            (immutable limit stream-limit)
            (mutable tail stream-tail stream-tail-set!)
            (mutable appended stream-appended stream-appended-set!)
            (mutable paused stream-paused stream-paused-set!)
            (mutable pauses stream-pauses stream-pauses-set!)
            (mutable most stream-most stream-most-set!)
            (mutable queued stream-queued stream-queued-set!)
            (mutable queued-at stream-queued-at stream-queued-at-set!)
            (mutable resumes stream-resumes stream-resumes-set!)
            (mutable last-resume stream-last-resume stream-last-resume-set!)
            (mutable head stream-head-field stream-head-set!)
            (mutable head-at stream-head-at stream-head-at-set!)
            (mutable first-at stream-first-at stream-first-at-set!)
            (mutable front stream-front stream-front-set!)
            (mutable taken stream-taken stream-taken-set!)
            (mutable stall stream-stall stream-stall-set!)))

  ;; monotonic-ns : -> Integer
  (define (monotonic-ns)
    (let ((t (current-time 'time-monotonic)))
      (+ (* (time-second t) 1000000000) (time-nanosecond t))))

  ;; make-response-stream : Positive-Integer -> Stream
  ;; An empty stream that buffers LIMIT bytes, or one chunk.
  (define (make-response-stream limit)
    (let ((sentinel (cons #f '())))
      (make-stream-record (make-mutex) limit sentinel 0 #f 0 0 #f #f 0 #f #f #f #f sentinel 0 #f)))

  ;; stream-plant-stall! : Stream Positive-Integer -> Void
  ;; A test seam, private: the write callable's next call for STREAM sleeps
  ;; MS milliseconds before anything else, in its phase stalling, holding
  ;; nothing, then sets it done. Armed while the transfer is paused, that
  ;; call is the replay inside curl_easy_pause, so a test can watch what the
  ;; resume step holds while a replay runs long (the M6 plan, section 3.4).
  (define (stream-plant-stall! stream ms)
    (unless (and (integer? ms) (exact? ms) (positive? ms))
      (assertion-violation 'stream-plant-stall! "a stall is a positive exact integer of milliseconds" ms))
    (locked (stream-lock stream) (lambda () (stream-stall-set! stream (vector ms 'armed)))))

  ;; stream-stall-state : Stream -> (U #f 'armed 'stalling 'done)
  ;; The stall's phase, read in a hold; #f, never armed.
  (define (stream-stall-state stream)
    (locked (stream-lock stream)
      (lambda () (let ((stall (stream-stall stream))) (and stall (vector-ref stall 1))))))

  ;; stall-if-armed! : Stream -> Void
  ;; The write callable's first step: an armed stall taken, in one hold,
  ;; then slept out holding nothing, then marked done.
  (define (stall-if-armed! stream)
    (let ((ms (locked (stream-lock stream)
                (lambda ()
                  (let ((stall (stream-stall stream)))
                    (and stall (eq? (vector-ref stall 1) 'armed)
                         (begin (vector-set! stall 1 'stalling) (vector-ref stall 0))))))))
      (when ms
        (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000)))
        (locked (stream-lock stream) (lambda () (vector-set! (stream-stall stream) 1 'done))))))

  ;; stream-room! : Stream Positive-Integer -> Boolean
  ;; The write callable's check for a chunk of N bytes, in one hold: #t
  ;; when the buffer is empty, or holds less than the stream-buffer with
  ;; the chunk added; else #f, with the receive bit set and the pause
  ;; counted, in the same hold (the M6 plan, section 3.2).
  (define (stream-room! stream n)
    (locked (stream-lock stream)
      (lambda ()
        (let ((buffered (- (stream-appended stream) (stream-taken stream))))
          (or (= buffered 0)
              (< (+ buffered n) (stream-limit stream))
              (begin
                (stream-paused-set! stream #t)
                (stream-pauses-set! stream (+ (stream-pauses stream) 1))
                #f))))))

  ;; stream-append! : Stream Bytevector -> Void
  ;; PIECE at the queue's tail, in one hold, counted as appended, and the
  ;; most the buffer has held, as the append leaves it, kept.
  (define (stream-append! stream piece)
    (locked (stream-lock stream)
      (lambda ()
        (let ((node (cons piece '())))
          (unless (stream-first-at stream) (stream-first-at-set! stream (monotonic-ns)))
          (set-cdr! (stream-tail stream) node)
          (stream-tail-set! stream node)
          (stream-appended-set! stream (+ (stream-appended stream) (bytevector-length piece)))
          (let ((buffered (- (stream-appended stream) (stream-taken stream))))
            (when (> buffered (stream-most stream))
              (stream-most-set! stream buffered)))))))

  ;; stream-look! : Stream Integer -> (List (U Pair #f) (U Bytevector #f) Boolean)
  ;; A taker's look, in one hold of the stream's mutex: the pair holding the
  ;; next piece and the piece, both left in place, or #f and #f; and whether
  ;; this look queues a resume (the M6 plan, section 3.5): the transfer
  ;; paused for receiving, no resume queued, and the buffer, as the taker
  ;; will count it once this piece is removed, at or below half of the
  ;; stream-buffer. Then it sets the flag, and NOW, a monotonic time in ns,
  ;; as the time it was queued, in the same hold: its caller queues the
  ;; resume in its next hold, of the engine's mutex, inside the same
  ;; critical section.
  (define (stream-look! stream now)
    (locked (stream-lock stream)
      (lambda ()
        (let* ((node (cdr (stream-front stream)))
               (piece (and (pair? node) (car node)))
               (after (- (stream-appended stream) (stream-taken stream)
                         (if piece (bytevector-length piece) 0)))
               (queue (and (stream-paused stream) (not (stream-queued stream))
                           (<= (* 2 after) (stream-limit stream)))))
          (when queue
            (stream-queued-set! stream #t)
            (stream-queued-at-set! stream now))
          (list (and piece node) piece queue)))))

  ;; stream-remove! : Stream Pair Bytevector -> Void
  ;; PIECE, held at NODE, taken out of STREAM: the front moved to NODE, and
  ;; its bytes counted as taken, plain writes of the taker's own fields and
  ;; nothing else, so no event check falls between them. A take calls it
  ;; last, after its hold, so an escape as that hold's critical section
  ;; ends leaves the piece for the next take (the M6 plan, section 3.5).
  (define (stream-remove! stream node piece)
    (stream-front-set! stream node)
    (stream-taken-set! stream (+ (stream-taken stream) (bytevector-length piece))))

  ;; stream-clear-pause! : Stream -> (U Integer #f)
  ;; The resume step's hold: the receive bit and the resume's flag cleared
  ;; together; answers when the flag was set, #f when it was not.
  (define (stream-clear-pause! stream)
    (locked (stream-lock stream)
      (lambda ()
        (let ((at (and (stream-queued stream) (stream-queued-at stream))))
          (stream-paused-set! stream #f)
          (stream-queued-set! stream #f)
          at))))

  ;; stream-resumed! : Stream (U Integer #f) Integer -> Void
  ;; A resume carried out, its curl_easy_pause called at CALLED, a
  ;; monotonic time in ns, for a flag set at QUEUED: counted, and its delay
  ;; kept as the last.
  (define (stream-resumed! stream queued called)
    (locked (stream-lock stream)
      (lambda ()
        (stream-resumes-set! stream (+ (stream-resumes stream) 1))
        (stream-last-resume-set! stream (and queued (- called queued))))))

  ;; stream-paused? : Stream -> Boolean
  ;; Whether its transfer is paused for receiving, read in a hold.
  (define (stream-paused? stream)
    (locked (stream-lock stream) (lambda () (stream-paused stream))))

  ;; stream-head : Stream -> (U Head #f)
  ;; Its final head once the header callable has published it, read in a
  ;; hold of its mutex, the lock it is published under.
  (define (stream-head stream)
    (locked (stream-lock stream) (lambda () (stream-head-field stream))))

  ;; stream-stats : Stream -> (Listof (Pairof Symbol Any))
  ;; What a test reads of STREAM, in one hold: the bytes appended and
  ;; taken, the most the buffer held, the write callable's pauses, the
  ;; resumes carried out and the last one's delay in ns, the receive bit,
  ;; the resume's flag, whether a head is published, and when it was, and
  ;; when the first piece was appended, each a monotonic time in ns or #f.
  (define (stream-stats stream)
    (locked (stream-lock stream)
      (lambda ()
        (list (cons 'appended (stream-appended stream)) (cons 'taken (stream-taken stream))
              (cons 'most (stream-most stream)) (cons 'pauses (stream-pauses stream))
              (cons 'resumes (stream-resumes stream))
              (cons 'last-resume-ns (stream-last-resume stream))
              (cons 'paused (stream-paused stream)) (cons 'queued (stream-queued stream))
              (cons 'head (and (stream-head-field stream) #t))
              (cons 'head-at (stream-head-at stream)) (cons 'first-at (stream-first-at stream))))))

  ;; stream-verdicts : (Listof Symbol)
  ;; What the write callable did with a streamed chunk, in its log's order:
  ;; accepted, appended to the stream; paused, the buffer full; refused,
  ;; past the body limit; raised, at a planted fault.
  (define stream-verdicts '(accepted paused refused raised))

  ;; tally : (Listof (List Symbol Natural (Listof Integer))) Symbol Integer
  ;;         -> (Listof (List Symbol Natural (Listof Integer)))
  ;; LOG, a stream's, with one more call of VERDICT, on THREAD.
  (define (tally log verdict thread)
    (let ((entry (assq verdict log)))
      (if entry
          (map (lambda (e)
                 (if (eq? e entry)
                     (list verdict (+ (cadr e) 1)
                           (if (memv thread (caddr e)) (caddr e) (cons thread (caddr e))))
                     e))
               log)
          (cons (list verdict 1 (list thread)) log))))

  ;; stream-chunk! : Natural Sink Positive-Integer Natural -> Natural
  ;; The write callable's step for a streamed response's chunk of N bytes at
  ;; DATA, for KEY's transfer (the M6 plan, section 3.2): first a test
  ;; seam's stall, armed by stream-plant-stall!; once a reason is
  ;; recorded against the transfer, it refuses every later call, answering
  ;; 0, verdict refused: Apple's 8.7.1 hands a chunk the callable refused
  ;; inside curl_easy_pause's replay to it again, after the call, and the
  ;; stream took it, past the failure (the Mac's make test, 2026-10-30); at
  ;; the call the request's fault names, counting every call with bytes, a
  ;; replay's among them, it raises (planted-fault N); then, the buffer full, it
  ;; answers CURL_WRITEFUNC_PAUSE, its check and the receive bit in one
  ;; hold, and libcurl hands the chunk again once resumed; then, for bytes
  ;; that would take it past its limit, it records body-limit and answers
  ;; 0; otherwise it copies them once, by the checked copy, into a fresh
  ;; bytevector, the piece a caller takes, appends it, and answers N.
  (define (stream-chunk! key sink data n)
    (stall-if-armed! (sink-stream sink))
    (let ((stream (sink-stream sink))
          (offer (+ (sink-offers sink) 1)))
      (define (log! verdict)
        (sink-log-set! sink (tally (sink-log sink) verdict (get-thread-id))))
      (sink-offers-set! sink offer)
      (cond
        ((sink-recorded sink)
         (log! 'refused)
         0)
        ((and (chunk-fault? (sink-fault sink)) (= offer (sink-fault sink)))
         (log! 'raised)
         (raise (planted-fault (sink-fault sink))))
        ((not (stream-room! stream n))
         (log! 'paused)
         curl-writefunc-pause)
        ((and (sink-limit sink) (> (+ (sink-received sink) n) (sink-limit sink)))
         (log! 'refused)
         (record! key 'body-limit #f)
         0)
        (else
         (let ((piece (make-bytevector n)))
           (copy-foreign->bytevector! data piece 0 n)
           (stream-append! stream piece)
           (sink-received-set! sink (+ (sink-received sink) n))
           (moved! sink)
           (log! 'accepted)
           n)))))

  ;; write-body : Code
  ;; libcurl's curl_write_callback for every transfer: DATA, SIZE times
  ;; NMEMB bytes of body, for the transfer KEY names. For a streamed
  ;; response, stream-chunk!'s answer. For a whole body it logs each chunk,
  ;; (LENGTH THREAD VERDICT), THREAD its get-thread-id, then: at the chunk
  ;; the transfer's fault names, it raises (planted-fault N), verdict
  ;; raised; for bytes that would take it past its limit, it records
  ;; body-limit and answers 0, verdict refused; otherwise it copies them
  ;; with the checked copy, keeps the chunk, and answers their count,
  ;; verdict accepted. No raise leaves it: its whole body runs under a
  ;; guard, which records anything raised as callback-raised and answers 0.
  ;; An empty chunk, which libcurl hands an empty body, is kept as nothing,
  ;; and not logged. It runs no procedure a caller supplied.
  (define write-body
    (foreign-callable __collect_safe
      (lambda (data size nmemb key)
        (guard (e (#t (record! key 'callback-raised e) 0))
          (let ((sink (sink-of key)) (n (* size nmemb)))
            (define (log! verdict)
              (sink-log-set! sink (cons (list n (get-thread-id) verdict) (sink-log sink))))
            (cond
              ((not sink) 0)
              ((= n 0) 0)
              ((sink-stream sink) (stream-chunk! key sink data n))
              ((and (chunk-fault? (sink-fault sink)) (= (+ (length (sink-log sink)) 1) (sink-fault sink)))
               (log! 'raised)
               (raise (planted-fault (sink-fault sink))))
              ((and (sink-limit sink) (> (+ (sink-received sink) n) (sink-limit sink)))
               (log! 'refused)
               (record! key 'body-limit #f)
               0)
              (else
               (let ((chunk (make-bytevector n)))
                 (copy-foreign->bytevector! data chunk 0 n)
                 (log! 'accepted)
                 (sink-received-set! sink (+ (sink-received sink) n))
                 (sink-chunks-set! sink (cons chunk (sink-chunks sink)))
                 (moved! sink)
                 n))))))
      (uptr size_t size_t uptr)
      size_t))

  ;; Locked where it is defined, and never unlocked: libcurl holds its entry
  ;; point for as long as the process runs, and a collection would move it.
  (define write-body-locked
    (begin (lock-object write-body) #t))

  ;; write-body-entry : Positive-Integer
  (define write-body-entry (foreign-callable-entry-point write-body))

  ;; empty-line? : Positive-Integer Natural -> Boolean
  ;; Whether the N bytes at DATA are "\r\n" or "\n", a head's end, read by
  ;; the checked copy.
  (define (empty-line? data n)
    (and (<= 1 n 2)
         (let ((bytes (make-bytevector n)))
           (copy-foreign->bytevector! data bytes 0 n)
           (if (= n 1)
               (= (bytevector-u8-ref bytes 0) 10)
               (and (= (bytevector-u8-ref bytes 0) 13) (= (bytevector-u8-ref bytes 1) 10))))))

  ;; head-line! : Sink Stream -> Void
  ;; At a head's empty line: CURLINFO_RESPONSE_CODE; below 200, a 1xx
  ;; head's, or 0, a proxy's CONNECT head's, nothing more: the next head is
  ;; awaited. At the first final head, its status, version and headers, as
  ;; finish-transfer reads a response's, published on the stream in one
  ;; hold of its mutex, a critical section, with whether libcurl had asked
  ;; for a streamed body by then, read in that hold: a request that streams
  ;; both ways shares the mutex with its request stream (the M6 plan,
  ;; section 3.2).
  (define (head-line! sink stream)
    (let* ((easy (sink-easy sink))
           (status (info-long easy curlinfo-response-code)))
      (when (>= status 200)
        (let ((version (http-version-symbol (info-long easy curlinfo-http-version)))
              (headers (response-headers easy))
              (up (sink-upload sink)))
          (sink-published-set! sink #t)
          (locked (stream-lock stream)
            (lambda ()
              (stream-head-set! stream (make-curl-head status version headers
                                                       (and up (upload-asked up) #t)))
              (stream-head-at-set! stream (monotonic-ns))))))))

  ;; read-head : Code
  ;; libcurl's header callback for a streamed response, which alone sets it:
  ;; SIZE times NITEMS bytes of a head's line at DATA, for the transfer KEY
  ;; names. It reads nothing but a head's empty line, before the head is
  ;; published, where head-line! reads it, and answers the line's length.
  ;; At the line a request's private (head N) names, counting every line
  ;; it is handed, it raises (planted-head-fault N), for the guard's test.
  ;; __collect_safe, locked where it is defined, as write-body: it fires
  ;; inside curl_multi_perform and curl_easy_pause (ADR-0030,
  ;; consequences). No raise leaves it: its body runs under a guard that
  ;; records what is raised as callback-raised and answers 0, which fails
  ;; the transfer. It runs no procedure a caller supplied.
  (define read-head
    (foreign-callable __collect_safe
      (lambda (data size nitems key)
        (guard (e (#t (record! key 'callback-raised e) 0))
          (let ((sink (sink-of key)) (n (* size nitems)))
            (cond
              ((not sink) 0)
              (else
               (sink-lines-set! sink (+ (sink-lines sink) 1))
               (when (and (head-fault? (sink-fault sink))
                          (= (sink-lines sink) (cadr (sink-fault sink))))
                 (raise (planted-head-fault (cadr (sink-fault sink)))))
               (let ((stream (sink-stream sink)))
                 (when (and stream (not (sink-published sink)) (empty-line? data n))
                   (head-line! sink stream)))
               (moved! sink)
               n)))))
      (uptr size_t size_t uptr)
      size_t))

  ;; Locked where it is defined, and never unlocked, as write-body is.
  (define read-head-locked
    (begin (lock-object read-head) #t))

  ;; read-head-entry : Positive-Integer
  (define read-head-entry (foreign-callable-entry-point read-head))

  ;; --- the request stream (ADR-0030; the M6 plan, sections 3.3 to 3.5) -----------------

  ;; upload-buffer-limit : Positive-Integer
  ;; A put waits while the request's buffer holds this many bytes or more,
  ;; so it holds at most this, less one, and the piece put (the M6 plan,
  ;; section 3.3).
  (define upload-buffer-limit 65536)

  ;; upload-verdicts : (Listof Symbol)
  ;; What the read callable answered, in its log's order: gave, bytes
  ;; handed; ended, 0, the body's end; paused, nothing buffered and no end;
  ;; aborted, a refusal.
  (define upload-verdicts '(gave ended paused aborted))

  ;; A request stream, made at submit, one per submit, with its plan
  ;; (ADR-0030, decision 1): its mutex, the response stream's when the
  ;; request streams both ways, and that stream, its partner, whose resume
  ;; flag is the transfer's one flag (the M6 plan, section 3.4); and its
  ;; body-length, LENGTH, or #f. Its pieces are a queue of pairs, (PIECE .
  ;; NEXT), behind a sentinel pair. Every field below is read and written
  ;; under its mutex:
  ;;
  ;;   - the putter's: the queue's tail and the bytes committed, both
  ;;     written in the hold that takes a piece, with its resume decision
  ;;     (section 3.5); whether the body has ended; and whether a put was
  ;;     refused past the length;
  ;;   - whether it is closed: the engine's thread closes it as the
  ;;     transfer's outcome is read, in the hold that reads the refusal, and
  ;;     as the transfer is freed, so a put after that takes nothing;
  ;;   - the read callable's, the engine thread's: the queue's front, the
  ;;     pair before the next piece, the offset into that piece, the bytes
  ;;     handed to libcurl, and whether libcurl has asked, and when;
  ;;   - the send bit, set by the read callable in the hold that found the
  ;;     buffer empty, and cleared by the resume step and by the prerequest
  ;;     callable at each attempt; the resume's flag, and when it was set,
  ;;     the partner's when there is one;
  ;;   - the counts a test reads: the prerequest callable's calls, the seek
  ;;     callable's, the read callable's pauses, the resumes carried out and
  ;;     the last one's delay, the puts taken, those that found the buffer
  ;;     full, the most it held; and the read callable's log, for each
  ;;     verdict how many calls had it and the threads they ran on;
  ;;   - a test seam's plant, split: a put links its piece in its hold but
  ;;     commits it after, in upload-split-commit!, the timer sweep's
  ;;     planted control (the M6 plan, section 3.5).
  ;;
  ;; upload? : Any -> Boolean
  ;; upload-lock : Upload -> Mutex
  (define-record-type (upload make-upload-record upload?)
    (fields (immutable lock upload-lock)
            (immutable partner upload-partner)
            (immutable length upload-length)
            (mutable tail upload-tail upload-tail-set!)
            (mutable committed upload-committed upload-committed-set!)
            (mutable ended upload-ended upload-ended-set!)
            (mutable refused upload-refused upload-refused-set!)
            (mutable closed upload-closed upload-closed-set!)
            (mutable front upload-front upload-front-set!)
            (mutable offset upload-offset upload-offset-set!)
            (mutable handed upload-handed upload-handed-set!)
            (mutable asked upload-asked upload-asked-set!)
            (mutable asked-at upload-asked-at upload-asked-at-set!)
            (mutable paused upload-paused upload-paused-set!)
            (mutable queued upload-queued upload-queued-set!)
            (mutable queued-at upload-queued-at upload-queued-at-set!)
            (mutable attempts upload-attempts upload-attempts-set!)
            (mutable seeks upload-seeks upload-seeks-set!)
            (mutable pauses upload-pauses upload-pauses-set!)
            (mutable resumes upload-resumes upload-resumes-set!)
            (mutable last-resume upload-last-resume upload-last-resume-set!)
            (mutable puts upload-puts upload-puts-set!)
            (mutable fulls upload-fulls upload-fulls-set!)
            (mutable most upload-most upload-most-set!)
            (mutable log upload-log upload-log-set!)
            (mutable split upload-split upload-split-set!)))

  ;; make-upload : (U Stream #f) (U Natural #f) -> Upload
  ;; An empty request stream of LENGTH, beside the response stream PARTNER,
  ;; whose mutex it shares, or with a mutex of its own for #f.
  (define (make-upload partner length)
    (let ((sentinel (cons #f '())))
      (make-upload-record (if partner (stream-lock partner) (make-mutex)) partner length
                          sentinel 0 #f #f #f sentinel 0 0 #f #f #f #f #f 0 0 0 0 #f 0 0 0 '() #f)))

  ;; upload-flag : Upload -> Boolean
  ;; upload-flag-at : Upload -> (U Integer #f)
  ;; upload-raise-flag! : Upload Integer -> Void
  ;; upload-lower-flag! : Upload -> Void
  ;; The transfer's one resume flag, its partner's when there is one, read
  ;; and written in a hold of the shared mutex.
  (define (upload-flag up)
    (let ((p (upload-partner up))) (if p (stream-queued p) (upload-queued up))))
  (define (upload-flag-at up)
    (let ((p (upload-partner up))) (if p (stream-queued-at p) (upload-queued-at up))))
  (define (upload-raise-flag! up now)
    (let ((p (upload-partner up)))
      (if p
          (begin (stream-queued-set! p #t) (stream-queued-at-set! p now))
          (begin (upload-queued-set! up #t) (upload-queued-at-set! up now)))))
  (define (upload-lower-flag! up)
    (let ((p (upload-partner up)))
      (if p (stream-queued-set! p #f) (upload-queued-set! up #f))))

  ;; upload-decide! : Upload Integer -> Boolean
  ;; In a hold: whether this put, or this end, queues a resume: the
  ;; transfer paused for sending and none queued; then the flag is set, at
  ;; NOW, in the same hold (the M6 plan, section 3.3).
  (define (upload-decide! up now)
    (and (upload-paused up) (not (upload-flag up))
         (begin (upload-raise-flag! up now) #t)))

  ;; upload-put! : Upload Bytevector Integer -> (List (U 'taken 'full 'refused 'ended 'closed) Boolean)
  ;; A put's hold, at NOW: closed, the transfer's outcome read or the
  ;; transfer freed, nothing changed; ended, the body ended already;
  ;; refused, PIECE would take the bytes committed past the length, the
  ;; refusal set; full, the buffer at upload-buffer-limit or more; or
  ;; taken, PIECE linked at the queue's tail and committed. With each,
  ;; whether it queues a resume, decided in the same hold, for refused and
  ;; taken alone, so a read callable that paused finds the piece or the
  ;; refusal once resumed (the M6 plan, section 3.5).
  (define (upload-put! up piece now)
    (locked (upload-lock up)
      (lambda ()
        (let ((n (bytevector-length piece))
              (size (upload-length up))
              (buffered (- (upload-committed up) (upload-handed up))))
          (cond
            ((upload-closed up) (list 'closed #f))
            ((upload-ended up) (list 'ended #f))
            ((and size (> (+ (upload-committed up) n) size))
             (upload-refused-set! up #t)
             (list 'refused (upload-decide! up now)))
            ((>= buffered upload-buffer-limit)
             (upload-fulls-set! up (+ (upload-fulls up) 1))
             (list 'full #f))
            ((upload-split up)
             (let ((node (cons piece '())))
               (set-cdr! (upload-tail up) node)
               (list 'taken (upload-decide! up now) node)))
            (else
             (let ((node (cons piece '())))
               (set-cdr! (upload-tail up) node)
               (upload-tail-set! up node)
               (upload-committed-set! up (+ (upload-committed up) n))
               (upload-puts-set! up (+ (upload-puts up) 1))
               (when (> (+ buffered n) (upload-most up)) (upload-most-set! up (+ buffered n)))
               (list 'taken (upload-decide! up now)))))))))

  ;; upload-plant-split! : Upload Boolean -> Void
  ;; A test seam, private: ON, the plant split, or none, set in a hold.
  (define (upload-plant-split! up on)
    (locked (upload-lock up) (lambda () (upload-split-set! up (and on #t)))))

  ;; upload-split-commit! : Upload Pair Bytevector -> Void
  ;; The split plant's commit of PIECE, linked at NODE in its put's hold:
  ;; after that hold's section, plain writes, the tail, a loop where a
  ;; timer's expiry can land, then the count, so an expiry between leaves
  ;; the tail moved and the piece uncounted, which a put's caller cannot
  ;; tell from a piece not taken. The timer sweep's planted control, never
  ;; the put's own path.
  (define (upload-split-commit! up node piece)
    (upload-tail-set! up node)
    (let loop ((i 0)) (unless (= i 3) (loop (+ i 1))))
    (upload-committed-set! up (+ (upload-committed up) (bytevector-length piece))))

  ;; upload-end! : Upload Integer -> Boolean
  ;; The body's end, in one hold, at NOW: once; whether it queues a resume.
  ;; A second end changes nothing, and queues none.
  (define (upload-end! up now)
    (locked (upload-lock up)
      (lambda ()
        (and (not (upload-ended up)) (not (upload-closed up))
             (begin
               (upload-ended-set! up #t)
               (upload-decide! up now))))))

  ;; upload-room? : Upload -> Boolean
  ;; Whether libcurl has asked for the body and the buffer has room, the
  ;; request stream not closed, read in a hold.
  (define (upload-room? up)
    (locked (upload-lock up)
      (lambda ()
        (and (upload-asked up) (not (upload-closed up))
             (< (- (upload-committed up) (upload-handed up)) upload-buffer-limit)))))

  ;; upload-count : Upload -> Natural
  ;; The bytes the puts have committed, read in a hold.
  (define (upload-count up)
    (locked (upload-lock up) (lambda () (upload-committed up))))

  ;; upload-stats : Upload -> (Listof (Pairof Symbol Any))
  ;; What a test reads of UP, in one hold: the bytes committed and handed,
  ;; whether the body ended, a put was refused, libcurl asked, and when; the
  ;; send bit, the resume's flag; the prerequest callable's calls and the
  ;; seek callable's; the read callable's pauses, the resumes carried out
  ;; and the last one's delay in ns; the puts taken, those that found the
  ;; buffer full, the most it held; and the read callable's log, each
  ;; verdict any call had, in upload-verdicts' order, (VERDICT COUNT
  ;; THREADS).
  (define (upload-stats up)
    (locked (upload-lock up)
      (lambda ()
        (list (cons 'committed (upload-committed up)) (cons 'handed (upload-handed up))
              (cons 'ended (upload-ended up)) (cons 'refused (upload-refused up))
              (cons 'closed (upload-closed up))
              (cons 'asked (upload-asked up)) (cons 'asked-at (upload-asked-at up))
              (cons 'paused (upload-paused up)) (cons 'queued (upload-flag up))
              (cons 'attempts (upload-attempts up)) (cons 'seeks (upload-seeks up))
              (cons 'pauses (upload-pauses up)) (cons 'resumes (upload-resumes up))
              (cons 'last-resume-ns (upload-last-resume up))
              (cons 'puts (upload-puts up)) (cons 'fulls (upload-fulls up)) (cons 'most (upload-most up))
              (cons 'reads (fold-right (lambda (verdict found)
                                         (let ((entry (assq verdict (upload-log up))))
                                           (if entry (cons entry found) found)))
                                       '() upload-verdicts))))))

  ;; upload-close! : Upload -> Boolean
  ;; The request stream closed, in one hold; answers whether a put was
  ;; refused past the length before it closed.
  (define (upload-close! up)
    (locked (upload-lock up)
      (lambda () (upload-closed-set! up #t) (upload-refused up))))

  ;; clear-pauses! : Live -> (U Integer #f)
  ;; The resume step's hold (the M6 plan, section 3.4): both directions'
  ;; bits and the resume's flag cleared together, in one hold of the
  ;; transfer's one stream mutex; answers when the flag was set, #f when it
  ;; was not.
  (define (clear-pauses! live)
    (let ((stream (live-transfer-stream live))
          (up (plan-upload (live-transfer-plan live))))
      (if up
          (locked (upload-lock up)
            (lambda ()
              (let ((at (and (upload-flag up) (upload-flag-at up))))
                (upload-paused-set! up #f)
                (when stream (stream-paused-set! stream #f))
                (upload-lower-flag! up)
                at)))
          (stream-clear-pause! stream))))

  ;; resumed! : Live (U Integer #f) Integer -> Void
  ;; A resume carried out, its curl_easy_pause called at CALLED, for a flag
  ;; set at QUEUED: counted on each of LIVE's streams, with its delay.
  (define (resumed! live queued called)
    (let ((stream (live-transfer-stream live))
          (up (plan-upload (live-transfer-plan live))))
      (when stream (stream-resumed! stream queued called))
      (when up
        (locked (upload-lock up)
          (lambda ()
            (upload-resumes-set! up (+ (upload-resumes up) 1))
            (upload-last-resume-set! up (and queued (- called queued))))))))

  ;; live-transfer-paused? : Live -> Boolean
  ;; Whether LIVE's transfer is paused either way: the paced poll's
  ;; "paused" (the M6 plan, section 3.4), each bit read in a hold.
  (define (live-transfer-paused? live)
    (let ((stream (live-transfer-stream live))
          (up (plan-upload (live-transfer-plan live))))
      (or (and stream (stream-paused? stream) #t)
          (and up (locked (upload-lock up) (lambda () (upload-paused up))) #t))))

  ;; copy-out! : Upload Positive-Integer Positive-Integer -> Void
  ;; K bytes from the queue's front to DATA, by the checked copy, across
  ;; pieces, the front and the offset moved on and the bytes counted as
  ;; handed. In the read callable's hold.
  (define (copy-out! up data k)
    (let loop ((left k) (at data))
      (when (> left 0)
        (let* ((node (cdr (upload-front up)))
               (piece (car node))
               (offset (upload-offset up))
               (rest (- (bytevector-length piece) offset))
               (n (min left rest)))
          (copy-bytevector->foreign! piece offset at n)
          (if (= n rest)
              (begin (upload-front-set! up node) (upload-offset-set! up 0))
              (upload-offset-set! up (+ offset n)))
          (upload-handed-set! up (+ (upload-handed up) n))
          (loop (- left n) (+ at n))))))

  ;; read-verdict : (U Natural Symbol) -> Symbol
  (define (read-verdict answer)
    (cond ((memq answer '(refuse mismatch)) 'aborted)
          ((eq? answer 'pause) 'paused)
          ((eqv? answer 0) 'ended)
          (else 'gave)))

  ;; body-read! : Natural Sink Positive-Integer Natural -> Natural
  ;; The read callable's step for KEY's transfer, ROOM bytes at DATA (the
  ;; M6 plan, section 3.3), in one hold of the request stream's mutex, its
  ;; first call marking that libcurl has asked: once a reason is recorded
  ;; against the transfer, CURL_READFUNC_ABORT, at every later call, as
  ;; stream-chunk! refuses; a put refused past the length,
  ;; body-length-mismatch and ABORT; the least of ROOM, the bytes buffered
  ;; and what the length still owes, copied by the checked copy, the
  ;; paced poll's counter bumped; 0 once the length is given whole, or at
  ;; the end with nothing buffered; at an end short of the length,
  ;; body-length-mismatch and ABORT; else the send bit set, in the hold that
  ;; found the buffer empty, and CURL_READFUNC_PAUSE. Each call is logged,
  ;; its verdict and its thread. The reasons are recorded after the hold.
  (define (body-read! key sink data room)
    (let* ((up (sink-upload sink))
           (recorded (sink-recorded sink))
           (thread (get-thread-id))
           (answer
            (locked (upload-lock up)
              (lambda ()
                (unless (upload-asked up)
                  (upload-asked-set! up #t)
                  (upload-asked-at-set! up (monotonic-ns)))
                (let* ((size (upload-length up))
                       (handed (upload-handed up))
                       (buffered (- (upload-committed up) handed))
                       (owed (if size (- size handed) buffered))
                       (k (min room buffered owed))
                       (answer
                        (cond
                          (recorded 'refuse)
                          ((upload-refused up) 'mismatch)
                          ((> k 0) (copy-out! up data k) k)
                          ((and size (= owed 0)) 0)
                          ((and (upload-ended up) (= buffered 0)) (if size 'mismatch 0))
                          (else
                           (upload-paused-set! up #t)
                           (upload-pauses-set! up (+ (upload-pauses up) 1))
                           'pause))))
                  (upload-log-set! up (tally (upload-log up) (read-verdict answer) thread))
                  answer)))))
      (case answer
        ((refuse) curl-readfunc-abort)
        ((mismatch) (record! key 'body-length-mismatch #f) curl-readfunc-abort)
        ((pause) curl-readfunc-pause)
        (else (when (> answer 0) (moved! sink)) answer))))

  ;; read-body : Code
  ;; libcurl's read callback for a streamed body, which alone sets it:
  ;; SIZE times NITEMS bytes of room at DATA, for the transfer KEY names;
  ;; body-read!'s answer; at the call a request's private (read N) names,
  ;; it raises (planted-upload-fault 'read N) first, for the guard's test.
  ;; __collect_safe, as curl_multi_perform, where it
  ;; fires, is (ADR-0013), locked where it is defined, and handed the
  ;; transfer's key as its READDATA, so no Scheme object crosses into C.
  ;; No raise leaves it: its body runs under a guard that records what is
  ;; raised as callback-raised and answers CURL_READFUNC_ABORT, which fails
  ;; the transfer. It runs no procedure a caller supplied (ADR-0012,
  ;; decision 4).
  (define read-body
    (foreign-callable __collect_safe
      (lambda (data size nitems key)
        (guard (e (#t (record! key 'callback-raised e) curl-readfunc-abort))
          (let ((sink (sink-of key)))
            (if (and sink (sink-upload sink))
                (begin
                  (sink-reads-set! sink (+ (sink-reads sink) 1))
                  (upload-fault-at! sink 'read (sink-reads sink))
                  (body-read! key sink data (* size nitems)))
                curl-readfunc-abort))))
      (uptr size_t size_t uptr)
      size_t))

  ;; Locked where it is defined, and never unlocked, as write-body is.
  (define read-body-locked
    (begin (lock-object read-body) #t))

  ;; read-body-entry : Positive-Integer
  (define read-body-entry (foreign-callable-entry-point read-body))

  ;; seek-body : Code
  ;; libcurl's seek callback for a streamed body, KEY its SEEKDATA, at a
  ;; rewind (ADR-0032, amended): CURL_SEEKFUNC_OK for an OFFSET of 0 from
  ;; SEEK_SET while the read callable has handed libcurl no byte, a rewind
  ;; then being a no-op, and while no reason is recorded; otherwise
  ;; body-not-replayable recorded, unless a reason is already, and
  ;; CURL_SEEKFUNC_CANTSEEK. With the transfer's rewinding seam, an
  ;; engine's test seam, it answers OK for an offset of 0 from SEEK_SET
  ;; once bytes were handed too, so the resend reaches the prerequest
  ;; callable. Each call is counted, and at the call a request's private
  ;; (seek N) names it raises (planted-upload-fault 'seek N), for the
  ;; guard's test. __collect_safe, locked, under a guard that records what
  ;; is raised and answers CANTSEEK.
  (define seek-body
    (foreign-callable __collect_safe
      (lambda (key offset origin)
        (guard (e (#t (record! key 'callback-raised e) curl-seekfunc-cantseek))
          (let* ((sink (sink-of key)) (up (and sink (sink-upload sink))))
            (if (not up)
                curl-seekfunc-cantseek
                (let ((seen (locked (upload-lock up)
                              (lambda ()
                                (upload-seeks-set! up (+ (upload-seeks up) 1))
                                (cons (upload-seeks up)
                                      (and (= offset 0) (= origin seek-set)
                                           (or (= (upload-handed up) 0) (sink-rewinding sink))))))))
                  (upload-fault-at! sink 'seek (car seen))
                  (if (and (cdr seen) (not (sink-recorded sink)))
                      curl-seekfunc-ok
                      (begin (record! key 'body-not-replayable #f) curl-seekfunc-cantseek)))))))
      (uptr integer-64 int)
      int))

  ;; Locked where it is defined, and never unlocked, as write-body is.
  (define seek-body-locked
    (begin (lock-object seek-body) #t))

  ;; seek-body-entry : Positive-Integer
  (define seek-body-entry (foreign-callable-entry-point seek-body))

  ;; prereq-body : Code
  ;; libcurl's prerequest callback for a streamed body, KEY its
  ;; PREREQDATA, before each attempt's request is sent (ADR-0032, amended):
  ;; it counts the attempt and clears the send bit, since libcurl's own
  ;; resend starts its attempt unpaused (the M6 plan, section 3.4); then
  ;; CURL_PREREQFUNC_OK at the first attempt, and at a later one while the
  ;; read callable has handed no byte, while no reason is recorded;
  ;; otherwise body-not-replayable recorded, unless a reason is already, and
  ;; CURL_PREREQFUNC_ABORT. At the first attempt, the engine's prereq-hold
  ;; seam's HOLD, a test seam's, runs after the upload's hold, never in it:
  ;; HOLD refuses to sleep with interrupts off. At the attempt a request's
  ;; private (prereq N) names it raises (planted-upload-fault 'prereq N),
  ;; for the guard's test. __collect_safe, locked, under a guard that records what is
  ;; raised and answers ABORT.
  (define prereq-body
    (foreign-callable __collect_safe
      (lambda (key primary-ip local-ip primary-port local-port)
        (guard (e (#t (record! key 'callback-raised e) curl-prereqfunc-abort))
          (let* ((sink (sink-of key)) (up (and sink (sink-upload sink))))
            (if (not up)
                curl-prereqfunc-abort
                (let ((seen (locked (upload-lock up)
                              (lambda ()
                                (let ((attempt (+ (upload-attempts up) 1)))
                                  (upload-attempts-set! up attempt)
                                  (upload-paused-set! up #f)
                                  (cons attempt (or (= attempt 1) (= (upload-handed up) 0))))))))
                  (when (and (= (car seen) 1) (sink-prereq-hold sink))
                    ((sink-prereq-hold sink)))
                  (upload-fault-at! sink 'prereq (car seen))
                  (if (and (cdr seen) (not (sink-recorded sink)))
                      curl-prereqfunc-ok
                      (begin (record! key 'body-not-replayable #f) curl-prereqfunc-abort)))))))
      (uptr uptr uptr int int)
      int))

  ;; Locked where it is defined, and never unlocked, as write-body is.
  (define prereq-body-locked
    (begin (lock-object prereq-body) #t))

  ;; prereq-body-entry : Positive-Integer
  (define prereq-body-entry (foreign-callable-entry-point prereq-body))

  ;; --- the plan, on the caller's thread -------------------------------------------------

  ;; A plan is what a submit checked: fresh copies of the request's URL,
  ;; headers, user agent, CA file and body, its other fields, the hatch's
  ;; settings, private copies checked as they were attached, and its private
  ;; fields; and, for a request with a stream-buffer, the submit's own
  ;; response stream, made with it, so a stream operation on a token still
  ;; queued has a stream to look at (ADR-0030, decision 1); then its
  ;; body-length; and, for a request whose body streams, the submit's own
  ;; request stream, beside the response stream when it streams both ways;
  ;; its http-version; the submit's checked copy of its credentials; and its
  ;; proxy's: the proxy, environment, #f or the URL the submit checked and
  ;; hands PROXY, its port set; the proxy CA file's copy and its
  ;; verification; the tunnel's settings, unshared-tunnel-settings'; and
  ;; whether it stops its engine's multiplexing, stops-multiplexing?'s.
  (define-record-type plan
    (fields (immutable url) (immutable method) (immutable headers) (immutable agent)
            (immutable body) (immutable timeout-ms) (immutable connect-timeout-ms)
            (immutable body-limit) (immutable ca-file) (immutable verify) (immutable proxy)
            (immutable settings) (immutable fault) (immutable follow) (immutable stream)
            (immutable body-length) (immutable upload) (immutable http-version)
            (immutable credentials) (immutable proxy-ca-file) (immutable proxy-verify)
            (immutable tunnel) (immutable unmultiplex))
    ;; Opaque, as a request is: a plan holds the submit's copy of its
    ;; credentials, and its proxy URL, and a token holds its plan.
    (opaque #t))

  ;; plan-stream : Plan -> (U Stream #f)
  ;; The plan's response stream, #f for a whole body.
  ;; plan-upload : Plan -> (U Upload #f)
  ;; The plan's request stream, #f for a body that does not stream.
  ;; plan-body-length : Plan -> (U Natural #f)
  ;; The plan's body-length, the request's, #f for none.

  ;; prepare-transfer : Request -> Plan
  ;; REQUEST's plan, checked on the caller's thread, before anything is
  ;; queued (M3 plan, section 3.4): request-checks', as curl-submit, which
  ;; curl-request-check shares (ADR-0023, amended 2026-10-28): the snapshot
  ;; of the headers and the user agent, the CA file's copy, the CA file
  ;; against the environment the libcurl loaded with, then the URL's copy,
  ;; parsed and its scheme checked, its CURLU freed before this returns
  ;; (ADR-0008, amended 2026-10-24), then prior knowledge against that
  ;; scheme, and the credentials' copy against its userinfo, and the proxy's
  ;; checks, request-checks'. Each refusal raises here. Then the
  ;; body is copied, after every check, so
  ;; the caller's bytevector may change once this returns (ADR-0023,
  ;; decision 4); a request's method and the presence of its body cannot
  ;; change, so body-not-allowed needs no second check. Last, a request with
  ;; a stream-buffer gets a fresh stream, this submit's alone, and one whose
  ;; body streams a fresh request stream, beside it, sharing its mutex,
  ;; when it streams both ways. A request's fields are immutable, so
  ;; stream-with-rounds and body-length-without-stream, checked as it was
  ;; made, hold here too.
  (define (prepare-transfer request)
    (let-values (((url fields ca-file credentials proxy proxy-ca-file tunnel unmultiplex)
                  (request-checks 'curl-submit request)))
      (let* ((given (curl-request-body request))
             (body (if (bytevector? given) (bytevector-copy given) given))
             (limit (curl-request-stream-buffer request))
             (stream (and limit (make-response-stream limit)))
             (length (curl-request-body-length request)))
        (make-plan url (curl-request-method request) (car fields) (cdr fields) body
                   (curl-request-timeout-ms request) (curl-request-connect-timeout-ms request)
                   (curl-request-body-limit request) ca-file (curl-request-verify request)
                   proxy
                   (curl-request-options request) (curl-request-fault request)
                   (curl-request-follow request)
                   stream length (and (eq? body 'stream) (make-upload stream length))
                   (curl-request-http-version request) credentials proxy-ca-file
                   (curl-request-proxy-verify request) tunnel unmultiplex))))

  ;; request-checks : Symbol Request
  ;;                  -> (Values String (Pairof Headers (U String #f)) (U String #f)
  ;;                             (U Credentials #f) (U 'environment #f String) (U String #f)
  ;;                             (Listof (Pairof String Integer)) Boolean)
  ;; The checks a submit makes of REQUEST on the caller's thread, as WHO,
  ;; their one owner: prepare-transfer's, as WHO curl-submit, and
  ;; curl-request-check's (ADR-0023, amended 2026-10-28). In order: what is
  ;; no request, an assertion violation; the URL's copy; the snapshot of the
  ;; headers and the user agent, Proxy-Authorization among its refusals; the
  ;; CA file's copy; the credentials' copy; the proxy's copy and the proxy CA
  ;; file's, path-copy's; an Expect header
  ;; holding 100-continue in the snapshot's copies beside a stream-buffer,
  ;; stream-with-rounds, by check-expect-round, since the caller's strings
  ;; may have changed since the request was made; the credentials beside
  ;; those copies, by check-credentials, for the same reason; then the CA
  ;; file against the environment the libcurl loaded with, by
  ;; check-ca-environment; then a proxy URL, by check-proxy-url; then an
  ;; https:// proxy URL against the libcurl's features, by
  ;; check-https-proxy; then the proxy's TLS fields beside it, by
  ;; check-proxy-tls, and the proxy CA file
  ;; against the environment, by check-ca-environment; then the URL, parsed
  ;; by call-with-parsed-url and checked by require-http-scheme, and, with
  ;; credentials, its user and password parts read by userinfo-parts, by
  ;; check-userinfo, its CURLU freed before this returns;
  ;; then the http-version against the scheme it answered, by
  ;; check-prior-knowledge, and against a proxy URL, by
  ;; check-prior-knowledge-proxy; then the URL's scheme through an https://
  ;; proxy URL, by check-tls-in-tls. Each refusal raises here, as WHO where
  ;; its check names one. Answers the checked copies: the URL, the fields,
  ;; the CA file and the credentials; the proxy, environment, #f, or the URL
  ;; the proxy URL's check answered, which PROXY gets; the proxy CA file;
  ;; unshared-tunnel-settings' for the loaded libcurl, the URL's scheme
  ;; and the proxy; and stops-multiplexing?'s for the loaded libcurl and the
  ;; proxy. The body is no check's: a submit copies it after.
  (define (request-checks who request)
    (unless (curl-request? request)
      (assertion-violation who "not a request" (shown-value request)))
    (let* ((url (string-copy (curl-request-url request)))
           (fields (snapshot who (curl-request-headers request) (curl-request-user-agent request)))
           (ca-file (ca-file-copy who (curl-request-ca-file request)))
           (credentials (credentials-copy who (request-credentials request)))
           (proxy (let ((given (request-proxy request)))
                    (if (string? given) (string-copy given) given)))
           (proxy-ca-file (path-copy who 'proxy-ca-file (request-proxy-ca-file request)))
           (proxy-verify (curl-request-proxy-verify request))
           (version (curl-request-http-version request)))
      (check-expect-round who (curl-request-stream-buffer request) (car fields))
      (check-credentials who credentials (car fields) (curl-request-body request)
                         (curl-request-stream-buffer request))
      (check-ca-environment who 'ca-file ca-file (curl-request-verify request))
      (let ((reading (and (string? proxy) (check-proxy-url who proxy))))
        (check-https-proxy who (and reading (string=? (cadr reading) "https"))
                           (libcurl-info-features (loaded-libcurl)))
        (check-proxy-tls who (and reading (string=? (cadr reading) "https")) proxy-ca-file
                         proxy-verify)
        (check-ca-environment who 'proxy-ca-file proxy-ca-file proxy-verify)
        (let ((scheme (call-with-parsed-url url
                        (lambda (handle)
                          (let ((scheme (require-http-scheme handle url)))
                            (when credentials
                              (check-userinfo who credentials (userinfo-parts handle url)))
                            scheme)))))
          (check-prior-knowledge who version scheme)
          (check-prior-knowledge-proxy who version reading)
          (check-tls-in-tls who scheme reading version)
          (let ((version-number (libcurl-info-version-number (loaded-libcurl))))
            (values url fields ca-file credentials (if reading (car reading) proxy) proxy-ca-file
                    (unshared-tunnel-settings version-number scheme
                                              (and reading #t) (and reading (caddr reading)))
                    (stops-multiplexing? version-number (and reading #t) (and reading (caddr reading)))))))))

  ;; refuse-proxy : Symbol Any Symbol -> Nothing
  ;; The refusal, as WHO, of a request's proxy URL for REASON, field proxy,
  ;; naming VALUE, the symbol proxy or (proxy PART), never the URL: its
  ;; userinfo can hold the proxy's password.
  (define (refuse-proxy who value reason)
    (refuse-field who 'proxy value reason))

  ;; hex-digit-value : Char -> (U Natural #f)
  ;; C's value as a hex digit, either case, ASCII alone; #f for any other.
  (define (hex-digit-value c)
    (cond ((char<=? #\0 c #\9) (- (char->integer c) 48))
          ((char<=? #\a c #\f) (- (char->integer c) 87))
          ((char<=? #\A c #\F) (- (char->integer c) 55))
          (else #f)))

  ;; percent-decoded : String -> (U Bytevector #f)
  ;; TEXT, a URL's part as libcurl gives it back, still percent-encoded, as
  ;; bytes: each % and the two hex digits after it, in either case, the byte
  ;; they name; each other char its UTF-8 bytes, a char above U+007F given
  ;; raw among them; or #f for a % not followed by two hex digits, which no
  ;; libcurl refuses in a userinfo and each sends on as it is (M7 slice 3's
  ;; build). Pure.
  (define (percent-decoded text)
    (let ((n (string-length text)))
      (let loop ((i 0) (chunks '()))
        (cond ((= i n) (apply bytevector-append-all (reverse chunks)))
              ((char=? (string-ref text i) #\%)
               (let ((high (and (< (+ i 2) n) (hex-digit-value (string-ref text (+ i 1)))))
                     (low (and (< (+ i 2) n) (hex-digit-value (string-ref text (+ i 2))))))
                 (and high low
                      (loop (+ i 3) (cons (u8-list->bytevector (list (+ (* high 16) low))) chunks)))))
              (else (loop (+ i 1) (cons (string->utf8 (string (string-ref text i))) chunks)))))))

  ;; bytevector-append-all : Bytevector ... -> Bytevector
  (define (bytevector-append-all . parts)
    (let* ((total (fold-left (lambda (sum part) (+ sum (bytevector-length part))) 0 parts))
           (out (make-bytevector total)))
      (let loop ((rest parts) (at 0))
        (unless (null? rest)
          (bytevector-copy! (car rest) 0 out at (bytevector-length (car rest)))
          (loop (cdr rest) (+ at (bytevector-length (car rest))))))
      out))

  ;; utf-8-bytes? : Bytevector -> Boolean
  ;; Whether BYTES are UTF-8, read by a strict transcoder.
  (define (utf-8-bytes? bytes)
    (guard (e ((i/o-decoding-error? e) #f))
      (bytevector->string bytes (make-transcoder (utf-8-codec) (eol-style none)
                                                 (error-handling-mode raise)))
      #t))

  ;; check-proxy-url : Symbol String -> (List String String Boolean)
  ;; PROXY, a request's proxy URL, a checked copy, parsed by
  ;; proxy-url-reading and checked, as WHO, each refusal raising, field
  ;; proxy, never naming the URL (ADR-0037, amended 2026-11-03), in order:
  ;;   - proxy-url, value proxy: libcurl's URL API cannot parse it, a URL
  ;;     that names no scheme, holds U+0000, or whose answer is not UTF-8
  ;;     among them, alike on every libcurl; or its user or its password,
  ;;     as libcurl gives it back, still encoded, holds a % not followed by
  ;;     two hex digits, which every libcurl measured took, and would send
  ;;     on as it is;
  ;;   - proxy-scheme, value proxy: a scheme but http or https, A to Z
  ;;     folded: chez-curl's to judge, since CURLU_NON_SUPPORT_SCHEME lets
  ;;     curl_url parse any scheme, socks5:// and foo:// among them, where
  ;;     with no flags it refuses foo:// everywhere and socks5:// but on
  ;;     8.23.0;
  ;;   - proxy-url-parts, value proxy: a path but /, a query, or a
  ;;     fragment. An empty query or fragment, which 7.85.0 and 8.5.0 report
  ;;     as "" and later libcurls as none, counts as none, and goes out as
  ;;     none, alike;
  ;;   - the userinfo, by check-proxy-userinfo.
  ;; Answers (URL SCHEME USERINFO): the URL libcurl gives back, its scheme's
  ;; port set when it named none, which PROXY gets; the scheme, A to Z
  ;; folded; and whether the URL holds a user or a password part libcurl
  ;; reports. libcurl's own refusal, which holds the URL, is never handed
  ;; on.
  (define (check-proxy-url who proxy)
    (let ((reading (guard (e ((curl-url-error? e) #f)) (proxy-url-reading proxy))))
      (unless reading (refuse-proxy who 'proxy 'proxy-url))
      (let* ((scheme (ascii-folded (list-ref reading 0)))
             (user (list-ref reading 1))
             (password (list-ref reading 2))
             (path (list-ref reading 3))
             (query (list-ref reading 4))
             (fragment (list-ref reading 5))
             (user-bytes (and user (percent-decoded user)))
             (password-bytes (and password (percent-decoded password))))
        (when (or (and user (not user-bytes)) (and password (not password-bytes)))
          (refuse-proxy who 'proxy 'proxy-url))
        (unless (member scheme '("http" "https"))
          (refuse-proxy who 'proxy 'proxy-scheme))
        (unless (and (or (not path) (string=? path "/"))
                     (or (not query) (string=? query ""))
                     (or (not fragment) (string=? fragment "")))
          (refuse-proxy who 'proxy 'proxy-url-parts))
        (check-proxy-userinfo who user-bytes password-bytes)
        (list (list-ref reading 6) scheme (and (or user password) #t)))))

  ;; check-proxy-userinfo : Symbol (U Bytevector #f) (U Bytevector #f) -> Void
  ;; Refuses, as WHO, a proxy URL's USER and PASSWORD, each percent-decoded,
  ;; #f for a part libcurl does not report, by the server credentials' rules
  ;; (ADR-0036, decisions 5 to 7; ADR-0037, amended 2026-11-03), in order,
  ;; each a &curl-request-error, field proxy:
  ;;   - each part present, user then password: a byte from 0x00 to 0x1F,
  ;;     or 0x7F, or bytes that are not UTF-8, %FF or a lone continuation
  ;;     byte among them, or, in the user, a colon, which ends the user at
  ;;     the proxy: credentials-bytes, value (proxy PART). Decoded, a
  ;;     control byte made 7.85.0 and both 8.5.0 builds drop the proxy and
  ;;     go direct, the origin answering, and 8.20.0 and 8.23.0 fail 3;
  ;;     encoded, every form is ASCII, so the rule reads the bytes decoded.
  ;;     A space, 0x7E, a colon in the password, and UTF-8, raw or encoded,
  ;;     pass;
  ;;   - a user and a password both empty, a part not reported read as
  ;;     empty, when either is reported: credentials-empty, value (proxy
  ;;     user). @ and :@ sent : on 8.5.0 and 8.20.0, and nothing on 8.23.0;
  ;;     7.85.0 reports neither part for them, so neither is refused there,
  ;;     and it sends nothing (tests/test-proxy.sps pins each by version).
  ;;     One empty part beside the other passes, alike on every libcurl.
  (define (check-proxy-userinfo who user password)
    (when (or user password)
      (for-each (lambda (part)
                  (let ((bytes (cdr part)))
                    (when bytes
                      (let scan ((i 0))
                        (when (< i (bytevector-length bytes))
                          (let ((b (bytevector-u8-ref bytes i)))
                            (when (or (< b #x20) (= b #x7F)
                                      (and (= b #x3A) (eq? (car part) 'user)))
                              (refuse-proxy who (list 'proxy (car part)) 'credentials-bytes)))
                          (scan (+ i 1))))
                      (unless (utf-8-bytes? bytes)
                        (refuse-proxy who (list 'proxy (car part)) 'credentials-bytes)))))
                (list (cons 'user user) (cons 'password password)))
      (when (and (or (not user) (= (bytevector-length user) 0))
                 (or (not password) (= (bytevector-length password) 0)))
        (refuse-proxy who '(proxy user) 'credentials-empty))))

  ;; https-proxy-supported? : Natural -> Boolean
  ;; Whether FEATURES, a curl_version_info features word, holds
  ;; CURL_VERSION_HTTPS_PROXY. Pure.
  (define (https-proxy-supported? features)
    (not (zero? (bitwise-and features curl-version-https-proxy))))

  ;; check-https-proxy : Symbol Boolean Natural -> Void
  ;; Refuses, as WHO, an HTTPS-PROXY, an https:// proxy URL, where FEATURES
  ;; lack CURL_VERSION_HTTPS_PROXY: https-proxy-unsupported, field proxy,
  ;; value proxy, never the URL. libcurl refuses such a URL itself, and
  ;; writes it whole, its userinfo with it, into the error buffer the
  ;; failure carries (7.85.0 lib/url.c:2496, 8.20.0 lib/url.c:1994, 8.23.0
  ;; lib/peer.c:654, read in source). No lane lacks the feature.
  (define (check-https-proxy who https-proxy features)
    (when (and https-proxy (not (https-proxy-supported? features)))
      (refuse-proxy who 'proxy 'https-proxy-unsupported)))

  ;; check-proxy-tls : Symbol Boolean (U String #f) Boolean -> Void
  ;; Refuses, as WHO, PROXY-CA-FILE, then VERIFY at #f, beside a proxy that
  ;; is not HTTPS-PROXY, an https:// proxy URL: proxy-tls-without-https-proxy,
  ;; field proxy-ca-file, value the path, or field proxy-verify, value #f.
  ;; The proxy's TLS settings are an https:// proxy's alone: beside
  ;; environment they would reach a proxy a variable names, or none, and
  ;; beside #f or an http:// proxy nothing (the M7 plan, section 3.1).
  ;; VERIFY at #t, the default, is never refused.
  (define (check-proxy-tls who https-proxy proxy-ca-file verify)
    (unless https-proxy
      (when proxy-ca-file
        (refuse-field who 'proxy-ca-file proxy-ca-file 'proxy-tls-without-https-proxy))
      (unless verify
        (refuse-field who 'proxy-verify verify 'proxy-tls-without-https-proxy))))

  ;; check-prior-knowledge-proxy : Symbol (U Symbol #f) (U (List String String Boolean) #f) -> Void
  ;; Refuses, as WHO, an http-version VERSION of http/2-prior-knowledge
  ;; beside READING, a proxy URL's check: prior-knowledge-through-proxy,
  ;; field http-version. Through a proxy that does not tunnel libcurl
  ;; ignores prior knowledge, and sends HTTP/1.1 in absolute form, on every
  ;; libcurl measured (ADR-0034, amended). Beside the environment's proxy
  ;; it is documented, not refused: no submit knows whether a variable
  ;; names one.
  (define (check-prior-knowledge-proxy who version reading)
    (when (and reading (eq? version 'http/2-prior-knowledge))
      (refuse-field who 'http-version version 'prior-knowledge-through-proxy)))

  ;; check-tls-in-tls : Symbol String (U (List String String Boolean) #f) (U Symbol #f) -> Void
  ;; Refuses, as WHO, a URL of SCHEME https through READING, an https://
  ;; proxy URL's check, on the loaded libcurl, with VERSION asked, when
  ;; tls-in-tls-stall? names it: proxy-tls-in-tls, field proxy, value proxy,
  ;; whose irritants are proxy, then the libcurl's version and the backend
  ;; in use. Without a bound such a transfer would wait for ever (ADR-0037,
  ;; decisions 7 and 10). A redirect's hop is refused as it is submitted.
  (define (check-tls-in-tls who scheme reading version)
    (when (and reading (equal? scheme "https") (string=? (cadr reading) "https"))
      (let ((libcurl (libcurl-info-version (loaded-libcurl)))
            (backend (loaded-tls-backend)))
        (when (tls-in-tls-stall? libcurl backend version)
          (raise (condition (make-curl-request-error 'proxy 'proxy 'proxy-tls-in-tls)
                            (make-who-condition who)
                            (make-message-condition
                             "an https:// URL through an https:// proxy, on a libcurl where TLS inside TLS stalls until the transfer's timeout: Ubuntu's 8.5.0 with GnuTLS, whatever is asked, and 7.85.0 unless the request asks http/1.1")
                            (make-irritants-condition (list 'proxy libcurl backend))))))))

  ;; check-userinfo : Symbol Credentials (List (U String #f) (U String #f)) -> Void
  ;; Refuses, as WHO, CREDENTIALS beside PARTS, the parsed URL's user and
  ;; password as userinfo-parts reads them: credentials-beside-userinfo,
  ;; field credentials, value the scheme, when either is present, "" among
  ;; them (ADR-0036, decision 1). One credentials source per request: with
  ;; both, libcurl sent the field's and dropped the URL's on every libcurl
  ;; measured. What a version reports for an empty user or password moves:
  ;; 7.85.0 reports neither part for http://@h/ and http://:@h/, which pass
  ;; there, and send the field's credentials, and no user for http://:p@h/
  ;; nor password for http://u:@h/, each refused by its other part; 8.5.0
  ;; and later report "", and refuse all four (tests/test-auth.sps pins
  ;; each URL by version). Checked at submit
  ;; alone, where the URL is parsed: a redirect's request is refused as it
  ;; is submitted.
  (define (check-userinfo who credentials parts)
    (when (or (car parts) (cadr parts))
      (refuse-credentials who (car credentials) 'credentials-beside-userinfo)))

  ;; check-prior-knowledge : Symbol (U Symbol #f) String -> Void
  ;; Refuses, as WHO, an http-version VERSION of http/2-prior-knowledge
  ;; beside SCHEME https, the parsed URL's, which libcurl writes in lower
  ;; case: prior-knowledge-over-https, field http-version (ADR-0034,
  ;; decision 2). Over https:// 8.20.0 and 8.23.0 offer ALPN h2 alone, so an
  ;; HTTP/1.1 origin refuses the handshake, 35, where 7.85.0 and 8.5.0 offer
  ;; h2 and http/1.1; http/2 gets h2 by ALPN on every libcurl. Checked at
  ;; submit alone, where the URL is parsed: a redirect's request is refused
  ;; as it is submitted.
  (define (check-prior-knowledge who version scheme)
    (when (and (eq? version 'http/2-prior-knowledge) (equal? scheme "https"))
      (refuse-field who 'http-version version 'prior-knowledge-over-https)))

  ;; curl-request-check : Request -> Void
  ;; Returns once REQUEST passes every check curl-submit makes of it on the
  ;; caller's thread, request-checks', and raises what a submit would
  ;; raise, its who curl-request-check where a submit's is curl-submit: so a
  ;; caller may check a batch before it submits any. It copies no body and
  ;; queues nothing, on no engine; the CURLU it parses is freed before it
  ;; returns. A refusal that depends on no state of an engine is all it can
  ;; make: a submit can still be refused by its engine's state. Its copies
  ;; are its own, dropped once it returns: a request shares its strings and
  ;; lists with its caller, so the check holds for them as they were then,
  ;; and a submit makes and checks copies of its own again.
  (define (curl-request-check request)
    (request-checks 'curl-request-check request)
    (if #f #f))

  ;; sends-body? : Symbol (U Bytevector 'stream #f) -> Boolean
  ;; Whether a transfer of METHOD with BODY sets the body's options: post,
  ;; put and patch always, empty with no body, and delete with one alone,
  ;; whole or streamed (M4 plan, section 3.2; the M6 plan, section 3.1).
  (define (sends-body? method body)
    (or (and (memq method '(post put patch)) #t)
        (and (eq? method 'delete) (or (bytevector? body) (eq? body 'stream)))))

  ;; header-line : (Pairof String String) -> String
  ;; "Name: value", or "Name;" for an empty value: libcurl's form for a
  ;; header sent with no value, where "Name:" would remove it.
  (define (header-line header)
    (if (string=? (cdr header) "")
        (string-append (car header) ";")
        (string-append (car header) ": " (cdr header))))

  ;; sent-header-lines : (Listof (Pairof String String)) Symbol (U Bytevector 'stream #f) -> (Listof String)
  ;; The lines a transfer of METHOD and BODY hands HTTPHEADER, in order:
  ;; header-line of each of HEADERS; then, when it sends a body, "Content-Type:"
  ;; and "Expect:", each unless HEADERS name one of that name, in any case.
  ;; "Name:" takes away libcurl's own header of that name, which it adds to
  ;; every body, its form type, and past 1 MiB, its Expect, after which it
  ;; waits a second for a server that never answers; a header the request
  ;; names replaces libcurl's (measured on five libcurls, the M4 plan,
  ;; section 4.1). tests/test-request.sps writes out its answers.
  (define (sent-header-lines headers method body)
    (define (named? name)
      (exists (lambda (header) (string-ci=? (car header) name)) headers))
    (append (map header-line headers)
            (if (sends-body? method body)
                (append (if (named? "Content-Type") '() '("Content-Type:"))
                        (if (named? "Expect") '() '("Expect:")))
                '())))

  ;; --- the transfer, on the engine's thread ---------------------------------------------

  ;; A live transfer: its plan, and each native object it holds, set in the
  ;; critical section that makes it and cleared in the one that frees it, #f
  ;; while not made: its key, registered for write-body and counted as
  ;; transfer, and its sink; its URL's CURLU handle; its error buffer; its
  ;; header list, 0 while it holds none; the string lists of its hatch
  ;; settings, each (SETTING . LIST), newest first, () while it holds none;
  ;; and its easy handle.
  (define-record-type (live-transfer make-live-transfer live-transfer?)
    (fields (immutable plan live-transfer-plan)
            (mutable key live-transfer-key live-transfer-key-set!)
            (mutable sink live-transfer-sink live-transfer-sink-set!)
            (mutable url live-transfer-url live-transfer-url-set!)
            (mutable buffer live-transfer-buffer live-transfer-buffer-set!)
            (mutable header-list live-transfer-header-list live-transfer-header-list-set!)
            (mutable lists live-transfer-lists live-transfer-lists-set!)
            (mutable easy live-transfer-easy live-transfer-easy-set!))
    ;; Opaque, as its plan is.
    (opaque #t))

  ;; live-transfer-easy : Live -> (U Positive-Integer #f)
  ;; The easy handle the engine adds to its multi handle, and finds again by
  ;; the address curl_multi_info_read answers.

  ;; live-transfer-chunks : Live -> (Listof (List Positive-Integer Integer Symbol))
  ;; write-body's log of LIVE's chunks, oldest first: each chunk's length,
  ;; the get-thread-id of the thread it ran on, and its verdict, accepted,
  ;; refused or raised (M3 plan, section 3.6).
  ;; For a streamed response it is the log of each verdict instead, in
  ;; stream-verdicts' order: (VERDICT COUNT THREADS), how many of the write
  ;; callable's calls had it and the get-thread-ids they ran on, newest
  ;; first, for each verdict any call had (the M6 plan, section 3.2).
  (define (live-transfer-chunks live)
    (let ((sink (live-transfer-sink live)))
      (cond ((not sink) '())
            ((sink-stream sink)
             (fold-right (lambda (verdict found)
                           (let ((entry (assq verdict (sink-log sink))))
                             (if entry (cons entry found) found)))
                         '() stream-verdicts))
            (else (reverse (sink-log sink))))))

  ;; live-transfer-stream : Live -> (U Stream #f)
  ;; LIVE's response stream, #f for a whole body.
  (define (live-transfer-stream live)
    (plan-stream (live-transfer-plan live)))

  ;; live-transfer-upload : Live -> (U Upload #f)
  ;; LIVE's request stream, #f for a body that does not stream.
  (define (live-transfer-upload live)
    (plan-upload (live-transfer-plan live)))

  ;; method-settings : Symbol (U Bytevector 'stream #f) (U Natural #f)
  ;;                   -> (Listof (Pairof String (U Integer String Bytevector)))
  ;; The settings METHOD and BODY make, in order, as data. For a whole body
  ;; or none: NOBODY at 1 for head; CUSTOMREQUEST at the method's name,
  ;; upcased, for put, patch and delete; then, when sends-body? says so,
  ;; POSTFIELDSIZE_LARGE at the body's length and COPYPOSTFIELDS at the
  ;; body, an empty one for #f. get makes none, and post none but the
  ;; body's: libcurl's own POST. For a streamed body, as measured (the M6
  ;; plan, section 3.3): post, POST at 1; put, UPLOAD at 1; patch and
  ;; delete, POST at 1 and CUSTOMREQUEST at the name; then the length,
  ;; LENGTH, or -1 for none, chunked: INFILESIZE_LARGE for put,
  ;; POSTFIELDSIZE_LARGE for the rest. The read callable gives the body;
  ;; set-transfer-options! sets it and its data apart, with the transfer's
  ;; key. tests/test-request.sps writes out a streamed body's answers.
  (define (method-settings method body length)
    (let ((method-names (field-options 'method))
          (body-names (field-options 'body)))
      (if (eq? body 'stream)
          (let ((size (or length -1)))
            (append (case method
                      ((put) (list (cons (list-ref method-names 3) 1)))
                      ((patch) (list (cons (list-ref method-names 2) 1) (cons (cadr method-names) "PATCH")))
                      ((delete) (list (cons (list-ref method-names 2) 1) (cons (cadr method-names) "DELETE")))
                      (else (list (cons (list-ref method-names 2) 1))))
                    (list (if (eq? method 'put)
                              (cons (field-option 'body-length) size)
                              (cons (car body-names) size)))))
          (append (case method
                    ((head) (list (cons (car method-names) 1)))
                    ((put) (list (cons (cadr method-names) "PUT")))
                    ((patch) (list (cons (cadr method-names) "PATCH")))
                    ((delete) (list (cons (cadr method-names) "DELETE")))
                    (else '()))
                  (if (sends-body? method body)
                      (let ((bytes (or body (make-bytevector 0))))
                        (list (cons (car body-names) (bytevector-length bytes))
                              (cons (cadr body-names) bytes)))
                      '())))))

  ;; set-transfer-options! : Positive-Integer Plan Positive-Integer Positive-Integer Natural (Listof (Pairof Hatch-Setting Positive-Integer)) Positive-Integer Boolean Boolean -> Void
  ;; Every setting PLAN's transfer makes on EASY, in order: the pins first,
  ;; QUICK_EXIT among them as QUICK-EXIT says, then ERRORBUFFER at BUFFER,
  ;; CURLU at URL, WRITEFUNCTION and WRITEDATA at KEY; for a streamed
  ;; response, HEADERFUNCTION and HEADERDATA at KEY; for a streamed body,
  ;; READFUNCTION and READDATA, SEEKFUNCTION and SEEKDATA, PREREQFUNCTION and
  ;; PREREQDATA at KEY, then FRESH_CONNECT at 1 unless FRESH is #f, an
  ;; engine's reusing seam (ADR-0032), or when the plan's tunnel settings,
  ;; unshared-tunnel-settings', ask it, once either way, then FORBID_REUSE
  ;; when they ask it (ADR-0037, amended 2026-11-03); then method-settings'
  ;; for the plan's method, body and body-length, a string through a C string and the
  ;; body through a counted copy, call-with-foreign-bytes'; and as the
  ;; request asks, HTTPHEADER at HEADER-LIST, USERAGENT, TIMEOUT_MS,
  ;; CONNECTTIMEOUT_MS, MAXFILESIZE_LARGE at the body limit plus one; then
  ;; proxy-settings' for the plan's proxy, proxy CA file and verification,
  ;; PROXY at "" for a proxy of #f, and for a URL PROXY, NOPROXY and the
  ;; proxy's TLS; then version-settings' for the plan's
  ;; http-version, HTTP_VERSION when it is not #f; then
  ;; credentials-settings' for the plan's credentials, HTTPAUTH, then
  ;; USERNAME and PASSWORD or XOAUTH2_BEARER, each string a counted UTF-8
  ;; copy, set-string-option!'s, when they are not #f; then, always,
  ;; tls-settings' for the plan's CA file and verification, through
  ;; set-tls-options!; then
  ;; FOLLOWLOCATION at 1 for the private follow field; then, last, the hatch's
  ;; settings, in the order they were attached, through set-hatch-option!,
  ;; a string list's from LISTS, the lists start-transfer! built (ADR-0009,
  ;; decision 2).
  (define (set-transfer-options! easy plan key buffer header-list lists url quick-exit fresh)
    (set-pinned-options! easy buffer quick-exit)
    (set-option! easy "ERRORBUFFER" buffer #f)
    (set-option! easy (field-option 'url) url buffer)
    (set-option! easy "WRITEFUNCTION" write-body-entry buffer)
    (set-option! easy "WRITEDATA" key buffer)
    (when (plan-stream plan)
      (set-option! easy "HEADERFUNCTION" read-head-entry buffer)
      (set-option! easy "HEADERDATA" key buffer))
    (when (plan-upload plan)
      (set-option! easy "READFUNCTION" read-body-entry buffer)
      (set-option! easy "READDATA" key buffer)
      (set-option! easy "SEEKFUNCTION" seek-body-entry buffer)
      (set-option! easy "SEEKDATA" key buffer)
      (set-option! easy "PREREQFUNCTION" prereq-body-entry buffer)
      (set-option! easy "PREREQDATA" key buffer))
    (when (or (and (plan-upload plan) fresh) (assoc "FRESH_CONNECT" (plan-tunnel plan)))
      (set-option! easy "FRESH_CONNECT" 1 buffer))
    (when (assoc "FORBID_REUSE" (plan-tunnel plan))
      (set-option! easy "FORBID_REUSE" 1 buffer))
    (for-each (lambda (setting)
                (let ((value (cdr setting)))
                  (cond ((string? value) (set-string-option! easy (car setting) value buffer))
                        ((bytevector? value)
                         (call-with-foreign-bytes value
                           (lambda (address) (set-option! easy (car setting) address buffer))))
                        (else (set-option! easy (car setting) value buffer)))))
              (method-settings (plan-method plan) (plan-body plan) (plan-body-length plan)))
    (unless (eqv? header-list 0)
      (set-option! easy (field-option 'headers) header-list buffer))
    (let ((agent (plan-agent plan)))
      (when agent
        (call-with-latin-1-c-string agent
          (lambda (address)
            (set-option! easy (field-option 'user-agent) address buffer)))))
    (let ((timeout (plan-timeout-ms plan)))
      (when timeout
        (set-option! easy (field-option 'timeout-ms) timeout buffer)))
    (let ((timeout (plan-connect-timeout-ms plan)))
      (when timeout
        (set-option! easy (field-option 'connect-timeout-ms) timeout buffer)))
    (let ((limit (plan-body-limit plan)))
      (when limit
        (set-option! easy (field-option 'body-limit) (+ limit 1) buffer)))
    (for-each (lambda (setting)
                (if (string? (cdr setting))
                    (set-string-option! easy (car setting) (cdr setting) buffer)
                    (set-option! easy (car setting) (cdr setting) buffer)))
              (proxy-settings (plan-proxy plan) (plan-proxy-ca-file plan) (plan-proxy-verify plan)))
    (for-each (lambda (setting) (set-option! easy (car setting) (cdr setting) buffer))
              (version-settings (plan-http-version plan)))
    (for-each (lambda (setting)
                (if (string? (cdr setting))
                    (set-string-option! easy (car setting) (cdr setting) buffer)
                    (set-option! easy (car setting) (cdr setting) buffer)))
              (credentials-settings (plan-credentials plan)))
    (set-tls-options! easy (plan-ca-file plan) (plan-verify plan) buffer)
    (when (plan-follow plan)
      (set-option! easy (field-option 'follow) 1 buffer))
    (for-each (lambda (setting)
                (set-hatch-option! easy setting
                                   (let ((held (assq setting lists))) (and held (cdr held)))
                                   buffer))
              (plan-settings plan)))

  ;; start-transfer! : Plan Boolean (Vector Natural) (Listof Any) -> Live
  ;; PLAN's transfer, made on this thread, the engine's, ready for its
  ;; multi handle: its key and sink, whose callables bump MOVES, the
  ;; engine's counter, and which take, from SEAMS, the engine's test seams,
  ;; rewinding, which lets the seek callable answer OK once bytes were
  ;; handed, reusing, which leaves FRESH_CONNECT off a streamed body, and
  ;; (prereq-hold . HOLD), which the prerequest callable calls at the first
  ;; attempt;
  ;; its URL parsed again and its scheme
  ;; checked again, its error buffer, zeroed, its header list, a string list
  ;; for each hatch setting of a non-empty list, of UTF-8 copies, counted as
  ;; slist (ADR-0009, decision 4), and its easy handle, set by
  ;; set-transfer-options!, with QUICK_EXIT where the libcurl knows it,
  ;; unless QUICK-EXIT is #f, an engine made without it. Each object is
  ;; made, and recorded in the live record, in one critical section. A raise
  ;; frees what was
  ;; made, by free-transfer!, then raises again: the URL's refusal, or a
  ;; &curl-transfer-error, setopt-failed, unknown-option or no-handle.
  (define (start-transfer! plan quick-exit moves seams)
    (let ((live (make-live-transfer plan #f #f #f #f 0 '() #f)))
      (guard (e (#t (free-transfer! live) (raise e)))
        (critical-section
         (let ((sink (make-sink (plan-body-limit plan) (plan-fault plan) 0 '() '() #f
                                (plan-stream plan) moves 0 #f #f 0 (plan-upload plan)
                                (and (memq 'rewinding seams) #t) 0
                                (let ((seam (find (lambda (seam) (and (pair? seam) (eq? (car seam) 'prereq-hold)))
                                                  seams)))
                                  (and seam (cdr seam))))))
           (locked sinks-lock
             (lambda ()
               (let ((key next-key))
                 (set! next-key (+ next-key 1))
                 (hashtable-set! sinks key sink)
                 (count-up! 'transfer)
                 (live-transfer-key-set! live key))))
           (live-transfer-sink-set! live sink)))
        (critical-section (live-transfer-url-set! live (parse-url (plan-url plan))))
        (require-http-scheme (live-transfer-url live) (plan-url plan))
        (critical-section (live-transfer-buffer-set! live (foreign-block curl-error-size)))
        (copy-bytevector->foreign! (make-bytevector curl-error-size 0) 0
                                   (live-transfer-buffer live) curl-error-size)
        (for-each
         (lambda (line)
           (call-with-latin-1-c-string line
             (lambda (address)
               ;; The list and its record, where free-transfer! frees it, in
               ;; one critical section.
               (critical-section
                (let ((appended (curl-slist-append (live-transfer-header-list live) address)))
                  (when (eqv? appended 0)
                    ;; No irritant: the line holds the header's value,
                    ;; which can be a secret.
                    (error 'start-transfer! "curl_slist_append returned NULL: no memory for a header"))
                  (live-transfer-header-list-set! live appended))))))
         (sent-header-lines (plan-headers plan) (plan-method plan) (plan-body plan)))
        (for-each
         (lambda (setting)
           (when (and (eq? (hatch-setting-type setting) 'slist)
                      (pair? (hatch-setting-value setting)))
             ;; The list's first element and its record in one critical
             ;; section, as the header list's; each later one appends to a
             ;; list the record holds already.
             (for-each
              (lambda (text)
                (call-with-c-string text
                  (lambda (address)
                    (critical-section
                     (let* ((held (assq setting (live-transfer-lists live)))
                            (list (if held (cdr held) 0))
                            (appended (curl-slist-append list address)))
                       (when (eqv? appended 0)
                         (error 'start-transfer! "curl_slist_append returned NULL: no memory for a string of a hatch setting"
                                (hatch-setting-name setting)))
                       (unless held
                         (live-transfer-lists-set! live (cons (cons setting appended)
                                                              (live-transfer-lists live)))))))))
              (hatch-setting-value setting))))
         (plan-settings plan))
        (critical-section
         (let ((easy (curl-easy-init)))
           (when (eqv? easy 0) (fail 'no-handle #f #f #f #f))
           (live-transfer-easy-set! live easy)
           (sink-easy-set! (live-transfer-sink live) easy)))
        (set-transfer-options! (live-transfer-easy live) plan (live-transfer-key live)
                               (live-transfer-buffer live) (live-transfer-header-list live)
                               (live-transfer-lists live) (live-transfer-url live) quick-exit
                               (not (memq 'reusing seams)))
        live)))

  ;; abandon-transfer-easy! : Live -> Void
  ;; LIVE's easy handle forgotten, and not freed, so that free-transfer!
  ;; frees everything but it: for a handle the engine could not take out of
  ;; its multi handle, whose curl_easy_cleanup would remove it there, a call
  ;; that can block. It stays counted as easy, so a suite sees it.
  (define (abandon-transfer-easy! live)
    (critical-section (live-transfer-easy-set! live #f)))

  ;; free-transfer! : Live -> Void
  ;; Closes LIVE's request stream, if it has one, so a later put takes
  ;; nothing; then frees what LIVE holds, the other way round from its making: the easy
  ;; handle, which the engine has taken out of its multi handle first, then
  ;; the hatch's string lists, the header list, the error buffer, the CURLU
  ;; and the key. Each free, and the clearing of its record, is one critical
  ;; section. A field never made holds #f, or 0 for the header list, or ()
  ;; for the hatch's lists, and is passed over, so a second call frees
  ;; nothing.
  (define (free-transfer! live)
    (let ((up (live-transfer-upload live)))
      (when up (upload-close! up)))
    (critical-section
     (let ((easy (live-transfer-easy live)))
       (when easy
         (curl-easy-cleanup easy)
         (live-transfer-easy-set! live #f))))
    (for-each
     (lambda (held)
       (critical-section
        (curl-slist-free-all (cdr held))
        (live-transfer-lists-set! live (remq held (live-transfer-lists live)))))
     (live-transfer-lists live))
    (critical-section
     (let ((header-list (live-transfer-header-list live)))
       (unless (eqv? header-list 0)
         (curl-slist-free-all header-list)
         (live-transfer-header-list-set! live 0))))
    (critical-section
     (let ((buffer (live-transfer-buffer live)))
       (when buffer
         (free-foreign-block! buffer)
         (live-transfer-buffer-set! live #f))))
    (critical-section
     (let ((url (live-transfer-url live)))
       (when url
         (free-parsed-url! url)
         (live-transfer-url-set! live #f))))
    (critical-section
     (let ((key (live-transfer-key live)))
       (when key
         (let ((removed (locked sinks-lock
                          (lambda ()
                            (and (hashtable-contains? sinks key)
                                 (begin (hashtable-delete! sinks key)
                                        (not (hashtable-contains? sinks key))))))))
           (when removed (count-down! 'transfer)))
         (live-transfer-key-set! live #f)))))

  ;; --- the response's parts -----------------------------------------------------------

  ;; info-long : Positive-Integer Integer -> Integer
  (define (info-long easy info)
    (let-values (((code value) (curl-easy-getinfo-long easy info)))
      (unless (eqv? code curle-ok)
        (error 'finish-transfer "curl_easy_getinfo refused a CURLINFO" info code))
      value))

  ;; info-off-t : Positive-Integer Integer -> Integer
  ;; The CURLINFO curl_off_t INFO, through native's off_t reader.
  (define (info-off-t easy info)
    (let-values (((code value) (curl-easy-getinfo-off-t easy info)))
      (unless (eqv? code curle-ok)
        (error 'finish-transfer "curl_easy_getinfo refused a CURLINFO" info code))
      value))

  ;; info-text : Positive-Integer Integer -> (U String #f)
  ;; The CURLINFO string INFO, read as UTF-8.
  (define (info-text easy info)
    (let-values (((code bytes) (curl-easy-getinfo-string easy info)))
      (unless (eqv? code curle-ok)
        (error 'finish-transfer "curl_easy_getinfo refused a CURLINFO" info code))
      (and bytes (utf8->string bytes))))

  ;; response-headers : Positive-Integer -> (Listof (Pairof String String))
  ;; Every header curl_easy_nextheader gives for CURLH_HEADER and the last
  ;; request, -1, in its order, name and value read as Latin-1.
  (define (response-headers easy)
    (let loop ((previous 0) (found '()))
      (let ((header (curl-easy-nextheader easy curlh-header -1 previous)))
        (if (eqv? header 0)
            (reverse found)
            (let ((bytes (curl-header-bytes header)))
              (loop header (cons (cons (bytes->latin-1 (car bytes)) (bytes->latin-1 (cdr bytes)))
                                 found)))))))

  ;; sink-body : Sink -> Bytevector
  ;; The chunks kept, joined in the order they came.
  (define (sink-body sink)
    (let* ((chunks (reverse (sink-chunks sink)))
           (body (make-bytevector (sink-received sink))))
      (let loop ((rest chunks) (at 0))
        (unless (null? rest)
          (bytevector-copy! (car rest) 0 body at (bytevector-length (car rest)))
          (loop (cdr rest) (+ at (bytevector-length (car rest))))))
      body))

  ;; reason-of : Sink -> (U (Pairof Symbol Any) #f)
  ;; What a transfer's outcome reports over libcurl's code, read as the
  ;; outcome is: what a callable recorded; else, for a streamed body, a put
  ;; refused past its length, body-length-mismatch, which the read callable
  ;; never records once libcurl has read the length whole and calls it no
  ;; more (the M6 plan, section 3.3); else #f. The request stream is closed
  ;; in the hold that reads the refusal, so a later put answers done, and a
  ;; refusal is the transfer's exactly when it came first.
  (define (reason-of sink)
    (let* ((up (sink-upload sink))
           (refused (and up (upload-close! up))))
      (or (sink-recorded sink)
          (and refused (cons 'body-length-mismatch #f)))))

  ;; finish-transfer : Live Integer -> (U Response Condition)
  ;; What LIVE's transfer ended with, CODE being the CURLcode
  ;; curl_multi_info_read gave for it, read on this thread, the engine's,
  ;; before anything is freed: what the callable recorded, or a put's
  ;; refusal past a streamed body's length, by reason-of, as a
  ;; &curl-transfer-error with that reason, the raised object for
  ;; callback-raised; else, for a CODE but CURLE_OK, perform-failed; each
  ;; failure of its class, with its request size, REQUEST_SIZE, or #f on a
  ;; libcurl whose answer to it is unreliable, ran-request-size's, and the
  ;; status a proxy refused its CONNECT with, ran-connect-status'; else the
  ;; response, with its timings, timing-infos', each read as a curl_off_t,
  ;; and its body, or #f for a streamed response, whose pieces the token
  ;; held. The answer is data: the engine completes the token with it, and
  ;; an awaiting thread raises a condition.
  (define (finish-transfer live code)
    (let* ((sink (live-transfer-sink live))
           (buffer (live-transfer-buffer live))
           (easy (live-transfer-easy live))
           (recorded (reason-of sink)))
      (cond
        (recorded
         (failure (car recorded) code #f buffer
                  (and (eq? (car recorded) 'callback-raised) (cdr recorded))
                  (ran-request-size easy) (ran-connect-status easy)))
        ((not (eqv? code curle-ok))
         (failure 'perform-failed code #f buffer #f (ran-request-size easy)
                  (ran-connect-status easy)))
        (else
         ;; let*: what each part reads, it reads in this order.
         (let* ((status (info-long easy curlinfo-response-code))
                (version (http-version-symbol (info-long easy curlinfo-http-version)))
                (effective (info-text easy curlinfo-effective-url))
                (headers (response-headers easy))
                (timings (map (lambda (timing) (cons (car timing) (info-off-t easy (cdr timing))))
                              timing-infos)))
           (make-curl-response status version effective headers
                               (and (not (sink-stream sink)) (sink-body sink)) timings))))))

  ;; resume-failure : Live Integer -> Condition
  ;; What LIVE's transfer fails with once curl_easy_pause answered CODE,
  ;; not 0, as the engine resumed it (the M6 plan, section 3.4): a reason a
  ;; callable recorded, inside the call or before it, or a put's refusal,
  ;; by reason-of, wins, as in finish-transfer, the raised object for
  ;; callback-raised; else
  ;; pause-failed, with CODE. Each with its request size, as a transfer that
  ;; ran: ran-request-size's. Read on the engine's thread, before anything
  ;; is freed.
  (define (resume-failure live code)
    (let* ((sink (live-transfer-sink live))
           (recorded (reason-of sink))
           (easy (live-transfer-easy live)))
      (if recorded
          (failure (car recorded) code #f (live-transfer-buffer live)
                   (and (eq? (car recorded) 'callback-raised) (cdr recorded))
                   (ran-request-size easy) (ran-connect-status easy))
          (failure 'pause-failed code #f (live-transfer-buffer live) #f (ran-request-size easy)
                   (ran-connect-status easy))))))
