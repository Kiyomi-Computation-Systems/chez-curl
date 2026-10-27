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
;;; copy of the body, checks the plan by the constructor's rules, checks
;;; the test seam's settings, and parses the plan's URL and checks its
;;; scheme, freeing that CURLU before it returns (ADR-0008, amended
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
;;; and before the test seam's: SSL_VERIFYPEER and SSL_VERIFYHOST at 1 and
;;; 2, or both 0 with verification off; then, with a CA file, CAINFO at its
;;; path and CAPATH cleared, so the CA file is the request's only trust
;;; anchor, whatever CA directory the build defaults to. A backend with no
;;; CA directory answers the clear CURLE_NOT_BUILT_IN, which is taken. A CA
;;; file of #f is libcurl's system store, as built, and sets neither. The
;;; four names stand in this file only in request-field-options.
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
;;; PROXY to "", which reads none of them, and a proxy's TLS stays
;;; libcurl's verified default, its options owned.
;;;
;;; write-body is the one callable (M2 plan, section 3.5): __collect_safe,
;;; since curl_multi_perform, where it fires, is (ADR-0013, accepted
;;; 2026-10-24), locked where it is defined and never unlocked, and handed
;;; the transfer's key, an integer, as its WRITEDATA, so no Scheme object
;;; crosses into C. It runs no procedure a caller supplied (ADR-0012,
;;; decision 4). It logs each chunk libcurl hands it, its length, the thread
;;; it ran on and what became of it, as data the engine hands the token. No
;;; raise leaves it: its whole body runs under a guard that records
;;; anything raised against the key and returns 0. libcurl then answers
;;; CURLE_WRITE_ERROR, 23, and the transfer fails with what was recorded. A
;;; request's fault plants such a raise, at the chunk it names. The body
;;; limit takes the same path: CURLOPT_MAXFILESIZE_LARGE is the limit plus
;;; one (M2 plan, section 5.3), so a declared length past that is refused
;;; before its body, and the callable refuses the first byte past the limit
;;; itself, on every libcurl.
;;;
;;; The test seam, curl-engine-submit-with, hands prepare-transfer its
;;; settings, held to ADR-0009's rules, narrowed (ADR-0009, amended
;;; 2026-10-23): long, enumerated-value and off_t options alone, none
;;; chez-curl owns, nor an owned setting's twin, the CA file's CAINFO_BLOB
;;; and SSL_OPTIONS among them (amended 2026-10-24), compared by id.
;;;
;;; The pins, ADR-0003's PROTOCOLS_STR and REDIR_PROTOCOLS_STR at
;;; "http,https" and NOSIGNAL at 1, are pinned-options, set by one call,
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
          curl-request-fault curl-request-follow curl-request-with-fault curl-request-following
          request-keys request-methods sent-header-lines timing-infos
          prepare-transfer start-transfer! finish-transfer free-transfer!
          live-transfer-easy live-transfer-chunks transfer-ended planted-fault transfers-started
          abandon-transfer-easy!
          curl-response? curl-response-status curl-response-http-version
          curl-response-effective-url curl-response-headers curl-response-body
          curl-response-timings
          option-bindings option-binding option-setter http-version-symbol bytes->latin-1 pinned-options
          request-field-options owned-option-names live-transfer-count cached-option-names
          tls-settings setopt-accepted? quick-exit-pin pinned-settings quick-exit-known?
          quick-exits-set guix-ca-overrides ca-overridden? pkcs11-prefix? overriding-variables
          keychain-fallback? request-size-unreliable reported-request-size)
  (import (curl private require-threaded)
          (rnrs)
          (rnrs mutable-strings)
          (only (chezscheme) critical-section foreign-callable foreign-callable-entry-point
                lock-object make-mutex with-mutex foreign-sizeof get-thread-id)
          (curl private conditions)
          (curl private constants)
          (curl private counters)
          (curl private memory)
          (curl private native)
          (only (curl private libcurl-info) libcurl-info-path libcurl-info-version)
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
                         ((owned-option) "chez-curl sets this option, or its twin, itself")
                         ((unsupported-type) "the test seam takes long, enumerated-value and off_t options alone")
                         ((unknown-key) "not a key a request takes")
                         ((repeated-key) "a key given twice")
                         ((missing-value) "a key given last, with no value after it")
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
  ;; it is handed.
  ;; Then the user agent, value-problem's rules. Each refusal is a
  ;; &curl-request-error naming the field. The copies are made before any
  ;; check, so what is checked is what is sent, whatever the caller's
  ;; objects become after.
  (define (snapshot who headers user-agent)
    (define (wrong message irritant) (assertion-violation who message irritant))
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
                    (let ((problem (value-problem (cdr header))))
                      (when problem (refuse-field who 'header-value (cdr header) problem)))
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

  ;; refuse-ca-file : Symbol String Symbol String (Listof Any) -> Nothing
  ;; The refusal of the CA file PATH for REASON, as WHO, with MESSAGE, and
  ;; IRRITANTS after PATH.
  (define (refuse-ca-file who path reason message irritants)
    (raise (condition (make-curl-request-error 'ca-file path reason)
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
  ;; CAINFO; #f for #f. A path holding U+0000 is refused as embedded-nul;
  ;; then one that begins pkcs11:, in any ASCII case, as pkcs11-url, on
  ;; every backend, so the field always names a file, and a file really
  ;; named so is reached as ./pkcs11:... (ADR-0024, decision 4). Each is a
  ;; &curl-request-error naming ca-file. No other char is refused: a path
  ;; may hold CR or LF. The copy is made before the checks, so what is
  ;; checked is what is sent. It is scanned by index, allocating nothing:
  ;; a path may be megabytes long, and libcurl refuses one past 8000000
  ;; bytes itself.
  (define (ca-file-copy who ca-file)
    (and ca-file
         (let ((copy (string-copy ca-file)))
           (let scan ((i 0))
             (when (< i (string-length copy))
               (when (char=? (string-ref copy i) #\nul)
                 (refuse-ca-file who copy 'embedded-nul
                                 "a CA file's path holds U+0000, where C would end it, and libcurl would open another file"
                                 '()))
               (scan (+ i 1))))
           (when (pkcs11-prefix? copy)
             (refuse-ca-file who copy 'pkcs11-url
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

  ;; check-ca-environment : Symbol (U String #f) Boolean -> Void
  ;; Refuses CA-FILE, a checked copy, with VERIFY, as WHO, when
  ;; overriding-variables names any for the loaded libcurl and what the
  ;; native layer recorded at its load: environment-override, a
  ;; &curl-request-error naming ca-file, whose irritants are the path, then
  ;; each variable's name, in that order; and when keychain-fallback? says
  ;; so for the loaded libcurl and the backend its init put in use:
  ;; keychain-fallback, whose irritants are the path, then that backend.
  (define (check-ca-environment who ca-file verify)
    (let* ((info (loaded-libcurl))
           (names (overriding-variables ca-file verify (loaded-libcurl-file) (libcurl-info-path info)
                                        (loaded-libcurl-patched?) (libcurl-info-version info)
                                        (loaded-ca-variables)))
           (backend (loaded-tls-backend)))
      (unless (null? names)
        (refuse-ca-file who ca-file 'environment-override
                        (string-append
                         "Guix's libcurl writes SSL_CERT_FILE over a CA file, and adds SSL_CERT_DIR beside it, as they were when it loaded; unset "
                         (fold-right (lambda (name rest) (if (string=? rest "") name (string-append name " and " rest)))
                                     "" names)
                         " before the program starts, or trust the store it names with no CA file")
                        names))
      (when (keychain-fallback? ca-file verify (loaded-on-macos?) (libcurl-info-path info) backend)
        (refuse-ca-file who ca-file 'keychain-fallback
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
    '(method headers body user-agent timeout-ms connect-timeout-ms body-limit ca-file verify proxy))

  ;; timeout? : Any -> Boolean
  ;; X is a timeout: #f, none, or a positive exact integer a long holds.
  (define (timeout? x)
    (or (not x) (and (long? x) (positive? x))))

  ;; request-settings : Symbol List -> (Listof (Pairof Symbol Any))
  ;; PLIST, KEY VALUE ..., as (KEY . VALUE) pairs, in its order, each key
  ;; refused by name, as WHO, before anything else is checked: one
  ;; request-keys lacks, unknown-key; one with no value after it,
  ;; missing-value; one given twice, repeated-key. Each is a
  ;; &curl-request-error, field key, whose value is the key as given.
  (define (request-settings who plist)
    (let loop ((rest plist) (found '()))
      (if (null? rest)
          (reverse found)
          (let ((key (car rest)))
            (unless (memq key request-keys) (refuse-field who 'key key 'unknown-key))
            (when (null? (cdr rest)) (refuse-field who 'key key 'missing-value))
            (when (assq key found) (refuse-field who 'key key 'repeated-key))
            (loop (cddr rest) (cons (cons key (cadr rest)) found))))))

  ;; make-curl-request : String Symbol Any ... -> Request
  ;; curl-request-with : Request Symbol Any ... -> Request
  ;; curl-request? : Any -> Boolean
  ;; curl-request-url : Request -> String
  ;; curl-request-method : Request -> (U 'get 'head 'post 'put 'patch 'delete)
  ;; curl-request-headers : Request -> (Listof (Pairof String String))
  ;; curl-request-body : Request -> (U Bytevector #f)
  ;; curl-request-user-agent : Request -> (U String #f)
  ;; curl-request-timeout-ms : Request -> (U Positive-Integer #f)
  ;; curl-request-connect-timeout-ms : Request -> (U Positive-Integer #f)
  ;; curl-request-body-limit : Request -> (U Natural #f)
  ;; curl-request-ca-file : Request -> (U String #f)
  ;; curl-request-verify : Request -> Boolean
  ;; curl-request-proxy : Request -> (U 'environment #f)
  ;; curl-request-fault : Request -> (U Positive-Integer #f)   private
  ;; curl-request-follow : Request -> Boolean                  private
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
  ;;   body                a bytevector, sent whole, or #f, none, the default.
  ;;                       With get or head it is refused as body-not-allowed.
  ;;                       post, put and patch send an empty one when it is
  ;;                       #f; delete sends none
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
  ;;                       (ADR-0024, decision 1). A proxy's TLS is libcurl's
  ;;                       verified default, against its system store: neither
  ;;                       ca-file nor verify reaches it
  ;;
  ;; The defaults set no policy: libcurl's own stand (ADR-0023, decision 3).
  ;; The keys are refused first, by request-settings' rules, then a URL
  ;; that is not a string, then a wrong type for method, body, timeout-ms,
  ;; connect-timeout-ms, body-limit, ca-file, verify or proxy, each an
  ;; assertion violation, the empty string as a CA file among them; then a
  ;; body with get or head, body-not-allowed; then snapshot's rules for the
  ;; headers and the user agent, their types first, as assertion
  ;; violations; then ca-file-copy's for the CA file. Each refusal of a value is a
  ;; &curl-request-error naming the field. The record keeps the caller's
  ;; objects; a submit checks them again, as a plan.
  ;;
  ;; (curl-request-with REQUEST KEY VALUE ...): a new request, with the
  ;; keys given replaced and the rest kept, its private fields among them,
  ;; checked as make-curl-request checks a new one.
  ;;
  ;; The private fields are no keys, and (curl) exports neither: FAULT, #f,
  ;; or a positive exact integer, a planted fault that makes the callable
  ;; raise (planted-fault FAULT) at the chunk of that number, counting from
  ;; 1, before its limit check (M3 plan, section 3.6); and FOLLOW, a
  ;; boolean, FOLLOWLOCATION at 1 when #t, for the tests that follow a
  ;; redirect, which nothing public may (M4 plan, section 3.2). Each is
  ;; data, never a procedure: a request holds no caller code (ADR-0012,
  ;; decision 4).
  (define-record-type (curl-request new-curl-request curl-request?)
    (fields (immutable url curl-request-url)
            (immutable method curl-request-method)
            (immutable headers curl-request-headers)
            (immutable body curl-request-body)
            (immutable user-agent curl-request-user-agent)
            (immutable timeout-ms curl-request-timeout-ms)
            (immutable connect-timeout-ms curl-request-connect-timeout-ms)
            (immutable body-limit curl-request-body-limit)
            (immutable ca-file curl-request-ca-file)
            (immutable verify curl-request-verify)
            (immutable proxy curl-request-proxy)
            (immutable fault curl-request-fault)
            (immutable follow curl-request-follow)))

  ;; checked-request : Symbol Any Any Any Any Any Any Any Any Any Any Any Any Any -> Request
  ;; A request of these fields, checked as WHO by make-curl-request's rules,
  ;; after the keys.
  (define (checked-request who url method headers body user-agent timeout-ms
                           connect-timeout-ms body-limit ca-file verify proxy fault follow)
    (define (wrong message irritant) (assertion-violation who message irritant))
    (unless (string? url) (wrong "a URL is a string" url))
    (unless (memq method request-methods)
      (wrong "a method is get, head, post, put, patch or delete" method))
    (unless (or (not body) (bytevector? body)) (wrong "a body is a bytevector or #f" body))
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
    (unless (or (eq? proxy 'environment) (not proxy))
      (wrong "a proxy is environment, the environment's, or #f, none" proxy))
    (unless (or (not fault) (and (integer? fault) (exact? fault) (positive? fault)))
      (wrong "a fault is a positive exact integer, the chunk it raises at, or #f: a request holds no procedure"
             fault))
    (unless (boolean? follow) (wrong "follow is #t or #f" follow))
    (when (and body (memq method '(get head)))
      (refuse-field who 'body method 'body-not-allowed))
    (snapshot who headers user-agent)
    (ca-file-copy who ca-file)
    (new-curl-request url method headers body user-agent timeout-ms connect-timeout-ms
                      body-limit ca-file verify proxy fault follow))

  ;; request-like : Symbol Request (Listof (Pairof Symbol Any)) String Any Any -> Request
  ;; REQUEST with SETTINGS' keys replaced, URL, FAULT and FOLLOW given, the
  ;; rest kept, checked as WHO.
  (define (request-like who request settings url fault follow)
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
                     (given 'proxy curl-request-proxy)
                     fault follow))

  ;; default-request : Request
  ;; Every key at its default, for a URL nothing reads: what
  ;; make-curl-request replaces keys in.
  (define default-request
    (new-curl-request "" 'get '() #f #f #f #f #f #f #t 'environment #f #f))

  (define (make-curl-request url . plist)
    (request-like 'make-curl-request default-request
                  (request-settings 'make-curl-request plist) url #f #f))

  (define (curl-request-with request . plist)
    (unless (curl-request? request)
      (assertion-violation 'curl-request-with "not a request" request))
    (request-like 'curl-request-with request (request-settings 'curl-request-with plist)
                  (curl-request-url request) (curl-request-fault request)
                  (curl-request-follow request)))

  ;; curl-request-with-fault : Request (U Positive-Integer #f) -> Request
  ;; REQUEST with its private fault FAULT, the test seam's (M3 plan, section
  ;; 3.6). (curl) does not export it.
  (define (curl-request-with-fault request fault)
    (unless (curl-request? request)
      (assertion-violation 'curl-request-with-fault "not a request" request))
    (request-like 'curl-request-with-fault request '() (curl-request-url request) fault
                  (curl-request-follow request)))

  ;; curl-request-following : Request -> Request
  ;; REQUEST, following redirects: FOLLOWLOCATION at 1, for the tests of a
  ;; followed redirect and of ADR-0003's redirect pin. Nothing public
  ;; follows one: through a 301, 302 or 303, libcurl resends a custom
  ;; method without its body (ADR-0023, amended 2026-10-26). (curl) does
  ;; not export it.
  (define (curl-request-following request)
    (unless (curl-request? request)
      (assertion-violation 'curl-request-following "not a request" request))
    (request-like 'curl-request-following request '() (curl-request-url request)
                  (curl-request-fault request) #t))

  ;; --- the response -----------------------------------------------------------------

  ;; curl-response? : Any -> Boolean
  ;; curl-response-status : Response -> Integer
  ;; curl-response-http-version : Response -> (U Symbol Integer #f)
  ;; curl-response-effective-url : Response -> (U String #f)
  ;; curl-response-headers : Response -> (Listof (Pairof String String))
  ;; curl-response-body : Response -> Bytevector
  ;; curl-response-timings : Response -> (Listof (Pairof Symbol Natural))
  ;; What a transfer answered: RESPONSE_CODE; HTTP_VERSION, by
  ;; http-version-symbol; EFFECTIVE_URL, read as UTF-8; every header of the
  ;; last request, CURLH_HEADER's, as Latin-1 strings in libcurl's order;
  ;; the body; and its timings, timing-infos' names in its order, each the
  ;; microseconds from the transfer's start to that phase's end, as libcurl
  ;; reports them (M4 plan, section 3.3).
  (define-record-type (curl-response make-curl-response curl-response?)
    (fields (immutable status curl-response-status)
            (immutable http-version curl-response-http-version)
            (immutable effective-url curl-response-effective-url)
            (immutable headers curl-response-headers)
            (immutable body curl-response-body)
            (immutable timings curl-response-timings)))

  ;; timing-infos : (Listof (Pairof Symbol Positive-Integer))
  ;; Each timing a response carries, in its order, with the CURLINFO_ it is
  ;; read from, a curl_off_t of microseconds: name-lookup, NAMELOOKUP_TIME_T;
  ;; connect, CONNECT_TIME_T; tls-handshake, APPCONNECT_TIME_T, 0 without
  ;; TLS; first-byte, STARTTRANSFER_TIME_T; total, TOTAL_TIME_T. On a
  ;; success every libcurl measured reports them in that order (M4 plan,
  ;; section 4.1), and a phase the transfer skipped as 0: on a connection
  ;; reused, name-lookup, connect and tls-handshake are all 0 (8.20.0, the
  ;; slice's review). tests/test-request.sps writes it out.
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
  ;;           -> Condition
  ;; What a transfer that failed for REASON raises: the class of CODE, by
  ;; make-classed-transfer-error's rule (ADR-0022, amended 2026-10-26), with
  ;; CODE's strerror, the error buffer's text, read now, while the buffer
  ;; lives, and REQUEST-SIZE, the bytes of request sent.
  (define (failure reason code option buffer recorded request-size)
    (let ((strerror (and code (curl-easy-strerror code))))
      (condition (make-classed-transfer-error reason code option strerror
                                              (error-buffer-text buffer) recorded request-size)
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

  ;; ran-request-size : Positive-Integer -> (U Natural #f)
  ;; reported-request-size for EASY's transfer, which ran, on the loaded
  ;; libcurl.
  (define (ran-request-size easy)
    (reported-request-size (libcurl-info-version (loaded-libcurl))
                           (info-long easy curlinfo-request-size)))

  ;; fail : Symbol (U Integer #f) (U String #f) (U Positive-Integer #f) Any -> Nothing
  ;; Raises failure's condition for a transfer refused while it was set up,
  ;; before anything was sent: its request size is 0, which chez-curl knows
  ;; itself, on every libcurl.
  (define (fail reason code option buffer recorded)
    (raise (failure reason code option buffer recorded 0)))

  ;; transfer-ended : (U 'cancelled 'stopped) -> Condition
  ;; The outcome of a transfer cancelled, or whose engine stopped, before
  ;; it ended: &curl-transfer-error with that reason, no code, and no
  ;; request size: it is taken apart unread.
  (define (transfer-ended reason)
    (unless (memq reason '(cancelled stopped))
      (assertion-violation 'transfer-ended "a transfer ends early cancelled or stopped" reason))
    (failure reason #f #f #f #f #f))

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
  ;; owned-option-names, so a field's options are closed to the test seam by
  ;; being a field's (ADR-0009, consequences). method sets NOBODY for head
  ;; and CUSTOMREQUEST for put, patch and delete; body, POSTFIELDSIZE_LARGE
  ;; then COPYPOSTFIELDS, in that order, since libcurl copies the size the
  ;; first set. The TLS fields set two each, in the order tls-settings makes
  ;; them: ca-file CAINFO, its path, then CAPATH, cleared; verify
  ;; SSL_VERIFYPEER, then SSL_VERIFYHOST (ADR-0018). proxy sets PROXY, to ""
  ;; when it is #f (ADR-0024, decision 1). follow is the private field's (M4
  ;; plan, section 3.2).
  (define request-field-options
    '((url "CURLU") (method "NOBODY" "CUSTOMREQUEST") (headers "HTTPHEADER")
      (body "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS") (user-agent "USERAGENT")
      (timeout-ms "TIMEOUT_MS") (connect-timeout-ms "CONNECTTIMEOUT_MS")
      (body-limit "MAXFILESIZE_LARGE") (ca-file "CAINFO" "CAPATH")
      (verify "SSL_VERIFYPEER" "SSL_VERIFYHOST") (proxy "PROXY") (follow "FOLLOWLOCATION")))

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
  ;; Every option that sets a proxy's TLS, in the options tables of the five
  ;; libcurls the M4 plan measured, 7.85.0 to 8.23.0: each PROXY_SSL_* and
  ;; PROXY_CA* option, and the rest of the PROXY_ TLS settings, which could
  ;; loosen it too, its version, ciphers and TLS-SRP among them. A proxy's
  ;; TLS stays libcurl's verified default until M7 (ADR-0024, amended
  ;; 2026-10-26, decided by the maintainer).
  (define proxy-tls-option-names
    '("PROXY_SSL_VERIFYPEER" "PROXY_SSL_VERIFYHOST" "PROXY_SSL_OPTIONS" "PROXY_SSL_CIPHER_LIST"
      "PROXY_CAINFO" "PROXY_CAINFO_BLOB" "PROXY_CAPATH" "PROXY_CRLFILE" "PROXY_ISSUERCERT"
      "PROXY_ISSUERCERT_BLOB" "PROXY_PINNEDPUBLICKEY" "PROXY_SSLVERSION" "PROXY_TLS13_CIPHERS"
      "PROXY_SSLCERT" "PROXY_SSLCERT_BLOB" "PROXY_SSLCERTTYPE" "PROXY_SSLKEY" "PROXY_SSLKEY_BLOB"
      "PROXY_SSLKEYTYPE" "PROXY_KEYPASSWD" "PROXY_TLSAUTH_TYPE" "PROXY_TLSAUTH_USERNAME"
      "PROXY_TLSAUTH_PASSWORD"))

  ;; owned-option-names : (Listof String)
  ;; The options the test seam refuses, by name (ADR-0009, amended
  ;; 2026-10-23 to 2026-10-26): those the transfer always sets, QUICK_EXIT
  ;; among them where the libcurl knows it, and the protocol pins'
  ;; deprecated bitmasks; then every option of each request field; then
  ;; each owned setting's twin, an option with an id of its own that sets
  ;; the same thing:
  ;;   - the timeouts' and the body limit's: TIMEOUT, CONNECTTIMEOUT and
  ;;     MAXFILESIZE, in seconds or as a long;
  ;;   - the method's and the body's: HTTPGET, POST, PUT and UPLOAD, which
  ;;     set the method; POSTFIELDS, POSTFIELDSIZE, HTTPPOST and MIMEPOST,
  ;;     another body, size or form; INFILESIZE and INFILESIZE_LARGE, an
  ;;     upload's size;
  ;;   - the URL's: PORT, which replaces its port, and REQUEST_TARGET, its
  ;;     target on the request line (the options tables, M4 slice 1);
  ;;   - the body's and the response's, found by the slice's review: CRLF,
  ;;     which rewrites each LF in what libcurl sends as CRLF, the body's too,
  ;;     and HEADER, which hands the response's head to WRITEFUNCTION with
  ;;     its body, against the body limit;
  ;;   - the CA file's: CAINFO_BLOB, which adds a CA, and SSL_OPTIONS, whose
  ;;     NATIVE_CA adds the system store;
  ;;   - the proxy field's (ADR-0024, decision 1): NOPROXY, whose "*" turns
  ;;     the environment's proxy off as PROXY "" does; PRE_PROXY, a SOCKS
  ;;     proxy before it; PROXYPORT and PROXYTYPE, its port and its kind,
  ;;     parts of the proxy PROXY names, as PORT is of the URL;
  ;; then proxy-tls-option-names. They are compared by id, so an alias name
  ;; is refused too.
  (define owned-option-names
    (append '("URL" "PROTOCOLS_STR" "REDIR_PROTOCOLS_STR" "PROTOCOLS" "REDIR_PROTOCOLS"
              "NOSIGNAL" "QUICK_EXIT" "WRITEFUNCTION" "WRITEDATA" "ERRORBUFFER")
            (apply append (map cdr request-field-options))
            '("TIMEOUT" "CONNECTTIMEOUT" "MAXFILESIZE" "HTTPGET" "POST" "PUT" "UPLOAD"
              "POSTFIELDS" "POSTFIELDSIZE" "HTTPPOST" "MIMEPOST" "INFILESIZE" "INFILESIZE_LARGE"
              "PORT" "REQUEST_TARGET" "CRLF" "HEADER" "CAINFO_BLOB" "SSL_OPTIONS"
              "NOPROXY" "PRE_PROXY" "PROXYPORT" "PROXYTYPE")
            proxy-tls-option-names))

  ;; pinned-options : (Listof (Pairof String (U String Integer)))
  ;; The settings every transfer makes, before its own: ADR-0003's protocol
  ;; pins, PROTOCOLS_STR and REDIR_PROTOCOLS_STR at "http,https", and
  ;; NOSIGNAL at 1, so that no signal handler is installed in a process that
  ;; runs threads. tests/test-transfer.sps writes it out.
  (define pinned-options
    '(("PROTOCOLS_STR" . "http,https") ("REDIR_PROTOCOLS_STR" . "http,https") ("NOSIGNAL" . 1)))

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

  ;; option-named : String -> (Pairof Integer Natural)
  ;; NAME's id and CURLOT type in the loaded libcurl; unknown-option,
  ;; naming it, when it does not know NAME. NAME is copied first: the copy
  ;; is the cache's key, and what is looked up, so the caller's string may
  ;; change after. A NAME holding U+0000 is an assertion violation:
  ;; curl_easy_option_by_name would read it short.
  (define (option-named name)
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
        (if (eq? found 'unknown)
            (fail 'unknown-option #f name #f #f)
            found))))

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
        (assertion-violation 'set-option! "the value does not fit the option's type" name value))
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

  ;; checked-settings : Any -> (Listof (Pairof String Integer))
  ;; OPTIONS, the test seam's (NAME . VALUE) pairs, as fresh pairs, in
  ;; order, each checked before anything native (ADR-0009, amended
  ;; 2026-10-23): a name the loaded libcurl does not know raises
  ;; unknown-option; an option whose id is an owned option's, owned-option;
  ;; a type but long, enumerated values or off_t, unsupported-type, each a
  ;; &curl-request-error, field options. A value out of its type's range,
  ;; and OPTIONS of any other shape, are assertion violations.
  (define (checked-settings options)
    (define (wrong message irritant) (assertion-violation 'curl-engine-submit-with message irritant))
    (unless (list? options) (wrong "options are a list of (NAME . VALUE)" options))
    (let loop ((rest options) (left (length options)) (found '()))
      (cond ((and (null? rest) (= left 0)) (reverse found))
            ((or (= left 0) (not (pair? rest)) (not (pair? (car rest))) (not (string? (caar rest))))
             (wrong "options are a list of (NAME . VALUE)" options))
            (else
             (let* ((name (string-copy (caar rest)))
                    (value (cdar rest))
                    (option (option-named name))
                    (type (find (lambda (entry) (eqv? (cdr entry) (cdr option))) curlot-types)))
               (when (memv (car option) (owned-option-ids))
                 (refuse-field 'curl-engine-submit-with 'options name 'owned-option))
               (unless (and type (memq (car type) '(long values off-t)))
                 (refuse-field 'curl-engine-submit-with 'options name 'unsupported-type))
               (unless (if (eq? (car type) 'off-t) (off-t? value) (long? value))
                 (wrong "the value does not fit the option's type" (cons name value)))
               (loop (cdr rest) (- left 1) (cons (cons name value) found)))))))

  ;; --- the transfers write-body serves ------------------------------------------------

  ;; A sink is what one transfer's callable writes to: its limit and its
  ;; planted fault, the bytes received, the chunks kept, newest first, the
  ;; log of every chunk libcurl handed it, newest first, and what was
  ;; recorded, #f or (REASON . OBJECT).
  (define-record-type sink
    (fields (immutable limit) (immutable fault)
            (mutable received) (mutable chunks) (mutable log) (mutable recorded)))

  ;; The live transfers, by key, and the next key, under the mutex. Every
  ;; engine's thread reads it: one callable serves them all.
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
  ;; recorded already. It never raises: write-body's guard calls it.
  (define (record! key reason object)
    (guard (e (#t #f))
      (let ((sink (sink-of key)))
        (when (and sink (not (sink-recorded sink)))
          (sink-recorded-set! sink (cons reason object))))))

  ;; planted-fault : Positive-Integer -> (List 'planted-fault Positive-Integer)
  ;; What write-body raises at the chunk N a request's fault names: data, so
  ;; a test can tell it from every other raise.
  (define (planted-fault n) (list 'planted-fault n))

  ;; write-body : Code
  ;; libcurl's curl_write_callback for every transfer: DATA, SIZE times
  ;; NMEMB bytes of body, for the transfer KEY names. It logs each chunk,
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
              ((and (sink-fault sink) (= (+ (length (sink-log sink)) 1) (sink-fault sink)))
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
                 n))))))
      (uptr size_t size_t uptr)
      size_t))

  ;; Locked where it is defined, and never unlocked: libcurl holds its entry
  ;; point for as long as the process runs, and a collection would move it.
  (define write-body-locked
    (begin (lock-object write-body) #t))

  ;; write-body-entry : Positive-Integer
  (define write-body-entry (foreign-callable-entry-point write-body))

  ;; --- the plan, on the caller's thread -------------------------------------------------

  ;; A plan is what a submit checked: fresh copies of the request's URL,
  ;; headers, user agent, CA file and body, its other fields, the test
  ;; seam's settings, and its private fields.
  (define-record-type plan
    (fields (immutable url) (immutable method) (immutable headers) (immutable agent)
            (immutable body) (immutable timeout-ms) (immutable connect-timeout-ms)
            (immutable body-limit) (immutable ca-file) (immutable verify) (immutable proxy)
            (immutable settings) (immutable fault) (immutable follow)))

  ;; prepare-transfer : Request (Listof (Pairof String Integer)) -> Plan
  ;; REQUEST's plan, with OPTIONS, the test seam's (NAME . VALUE) pairs,
  ;; each checked by checked-settings, on the caller's thread, before
  ;; anything is queued (M3 plan, section 3.4). In order: the snapshot of
  ;; the headers and the user agent, the CA file's copy, OPTIONS, the CA
  ;; file against the environment the libcurl loaded with, by
  ;; check-ca-environment, then the URL's copy, parsed by
  ;; call-with-parsed-url and checked by
  ;; require-http-scheme, its CURLU freed before this returns (ADR-0008,
  ;; amended 2026-10-24). Each refusal raises here. The body is copied, so
  ;; the caller's bytevector may change once this returns (ADR-0023,
  ;; decision 4); a request's method and the presence of its body cannot
  ;; change, so body-not-allowed needs no second check.
  (define (prepare-transfer request options)
    (unless (curl-request? request)
      (assertion-violation 'curl-submit "not a request" request))
    (let* ((url (string-copy (curl-request-url request)))
           (fields (snapshot 'curl-submit (curl-request-headers request)
                             (curl-request-user-agent request)))
           (ca-file (ca-file-copy 'curl-submit (curl-request-ca-file request)))
           (body (let ((body (curl-request-body request))) (and body (bytevector-copy body))))
           (settings (checked-settings options)))
      (check-ca-environment 'curl-submit ca-file (curl-request-verify request))
      (call-with-parsed-url url require-http-scheme)
      (make-plan url (curl-request-method request) (car fields) (cdr fields) body
                 (curl-request-timeout-ms request) (curl-request-connect-timeout-ms request)
                 (curl-request-body-limit request) ca-file (curl-request-verify request)
                 (curl-request-proxy request)
                 settings (curl-request-fault request) (curl-request-follow request))))

  ;; sends-body? : Symbol (U Bytevector #f) -> Boolean
  ;; Whether a transfer of METHOD with BODY sets the body's options: post,
  ;; put and patch always, empty with no body, and delete with one alone
  ;; (M4 plan, section 3.2).
  (define (sends-body? method body)
    (or (and (memq method '(post put patch)) #t)
        (and (eq? method 'delete) (bytevector? body))))

  ;; header-line : (Pairof String String) -> String
  ;; "Name: value", or "Name;" for an empty value: libcurl's form for a
  ;; header sent with no value, where "Name:" would remove it.
  (define (header-line header)
    (if (string=? (cdr header) "")
        (string-append (car header) ";")
        (string-append (car header) ": " (cdr header))))

  ;; sent-header-lines : (Listof (Pairof String String)) Symbol (U Bytevector #f) -> (Listof String)
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
  ;; header list, 0 while it holds none; and its easy handle.
  (define-record-type (live-transfer make-live-transfer live-transfer?)
    (fields (immutable plan live-transfer-plan)
            (mutable key live-transfer-key live-transfer-key-set!)
            (mutable sink live-transfer-sink live-transfer-sink-set!)
            (mutable url live-transfer-url live-transfer-url-set!)
            (mutable buffer live-transfer-buffer live-transfer-buffer-set!)
            (mutable header-list live-transfer-header-list live-transfer-header-list-set!)
            (mutable easy live-transfer-easy live-transfer-easy-set!)))

  ;; live-transfer-easy : Live -> (U Positive-Integer #f)
  ;; The easy handle the engine adds to its multi handle, and finds again by
  ;; the address curl_multi_info_read answers.

  ;; live-transfer-chunks : Live -> (Listof (List Positive-Integer Integer Symbol))
  ;; write-body's log of LIVE's chunks, oldest first: each chunk's length,
  ;; the get-thread-id of the thread it ran on, and its verdict, accepted,
  ;; refused or raised (M3 plan, section 3.6).
  (define (live-transfer-chunks live)
    (let ((sink (live-transfer-sink live)))
      (if sink (reverse (sink-log sink)) '())))

  ;; method-settings : Symbol (U Bytevector #f) -> (Listof (Pairof String (U Integer String Bytevector)))
  ;; The settings METHOD and BODY make, in order, as data: NOBODY at 1 for
  ;; head; CUSTOMREQUEST at the method's name, upcased, for put, patch and
  ;; delete; then, when sends-body? says so, POSTFIELDSIZE_LARGE at the
  ;; body's length and COPYPOSTFIELDS at the body, an empty one for #f. get
  ;; makes none, and post none but the body's: libcurl's own POST.
  ;; tests/test-request.sps reads each method's head and body as the origin
  ;; received them.
  (define (method-settings method body)
    (let ((method-names (field-options 'method))
          (body-names (field-options 'body)))
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
                  '()))))

  ;; set-transfer-options! : Positive-Integer Plan Positive-Integer Positive-Integer Natural Positive-Integer Boolean -> Void
  ;; Every setting PLAN's transfer makes on EASY, in order: the pins first,
  ;; QUICK_EXIT among them as QUICK-EXIT says, then ERRORBUFFER at BUFFER,
  ;; CURLU at URL, WRITEFUNCTION and WRITEDATA at KEY; then method-settings'
  ;; for the plan's method and body, a string through a C string and the
  ;; body through a counted copy, call-with-foreign-bytes'; and as the
  ;; request asks, HTTPHEADER at HEADER-LIST, USERAGENT, TIMEOUT_MS,
  ;; CONNECTTIMEOUT_MS, MAXFILESIZE_LARGE at the body limit plus one, and
  ;; PROXY at "" for a proxy of #f; then, always, tls-settings' for the
  ;; plan's CA file and verification, through set-tls-options!; then
  ;; FOLLOWLOCATION at 1 for the private follow field; then the test seam's
  ;; settings.
  (define (set-transfer-options! easy plan key buffer header-list url quick-exit)
    (set-pinned-options! easy buffer quick-exit)
    (set-option! easy "ERRORBUFFER" buffer #f)
    (set-option! easy (field-option 'url) url buffer)
    (set-option! easy "WRITEFUNCTION" write-body-entry buffer)
    (set-option! easy "WRITEDATA" key buffer)
    (for-each (lambda (setting)
                (let ((value (cdr setting)))
                  (cond ((string? value) (set-string-option! easy (car setting) value buffer))
                        ((bytevector? value)
                         (call-with-foreign-bytes value
                           (lambda (address) (set-option! easy (car setting) address buffer))))
                        (else (set-option! easy (car setting) value buffer)))))
              (method-settings (plan-method plan) (plan-body plan)))
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
    (unless (plan-proxy plan)
      (set-string-option! easy (field-option 'proxy) "" buffer))
    (set-tls-options! easy (plan-ca-file plan) (plan-verify plan) buffer)
    (when (plan-follow plan)
      (set-option! easy (field-option 'follow) 1 buffer))
    (for-each (lambda (setting)
                (set-option! easy (car setting) (cdr setting) buffer))
              (plan-settings plan)))

  ;; start-transfer! : Plan Boolean -> Live
  ;; PLAN's transfer, made on this thread, the engine's, ready for its
  ;; multi handle: its key and sink, its URL parsed again and its scheme
  ;; checked again, its error buffer, zeroed, its header list, and its easy
  ;; handle, set by set-transfer-options!, with QUICK_EXIT where the libcurl
  ;; knows it, unless QUICK-EXIT is #f, an engine made without it. Each object is made, and recorded
  ;; in the live record, in one critical section. A raise frees what was
  ;; made, by free-transfer!, then raises again: the URL's refusal, or a
  ;; &curl-transfer-error, setopt-failed, unknown-option or no-handle.
  (define (start-transfer! plan quick-exit)
    (let ((live (make-live-transfer plan #f #f #f #f 0 #f)))
      (guard (e (#t (free-transfer! live) (raise e)))
        (critical-section
         (let ((sink (make-sink (plan-body-limit plan) (plan-fault plan) 0 '() '() #f)))
           (locked sinks-lock
             (lambda ()
               (let ((key next-key))
                 (set! next-key (+ next-key 1))
                 (hashtable-set! sinks key sink)
                 (count-up! 'transfer)
                 (live-transfer-key-set! live key))))
           (live-transfer-sink-set! live sink)))
        (critical-section (live-transfer-url-set! live (parse-url (plan-url plan))))
        (require-http-scheme (live-transfer-url live))
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
                    (error 'start-transfer! "curl_slist_append returned NULL: no memory for a header"
                           line))
                  (live-transfer-header-list-set! live appended))))))
         (sent-header-lines (plan-headers plan) (plan-method plan) (plan-body plan)))
        (critical-section
         (let ((easy (curl-easy-init)))
           (when (eqv? easy 0) (fail 'no-handle #f #f #f #f))
           (live-transfer-easy-set! live easy)))
        (set-transfer-options! (live-transfer-easy live) plan (live-transfer-key live)
                               (live-transfer-buffer live) (live-transfer-header-list live)
                               (live-transfer-url live) quick-exit)
        live)))

  ;; abandon-transfer-easy! : Live -> Void
  ;; LIVE's easy handle forgotten, and not freed, so that free-transfer!
  ;; frees everything but it: for a handle the engine could not take out of
  ;; its multi handle, whose curl_easy_cleanup would remove it there, a call
  ;; that can block. It stays counted as easy, so a suite sees it.
  (define (abandon-transfer-easy! live)
    (critical-section (live-transfer-easy-set! live #f)))

  ;; free-transfer! : Live -> Void
  ;; Frees what LIVE holds, the other way round from its making: the easy
  ;; handle, which the engine has taken out of its multi handle first, then
  ;; the header list, the error buffer, the CURLU and the key. Each free,
  ;; and the clearing of its record, is one critical section. A field never
  ;; made holds #f, or 0 for the header list, and is passed over, so a second
  ;; call frees nothing.
  (define (free-transfer! live)
    (critical-section
     (let ((easy (live-transfer-easy live)))
       (when easy
         (curl-easy-cleanup easy)
         (live-transfer-easy-set! live #f))))
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

  ;; finish-transfer : Live Integer -> (U Response Condition)
  ;; What LIVE's transfer ended with, CODE being the CURLcode
  ;; curl_multi_info_read gave for it, read on this thread, the engine's,
  ;; before anything is freed: what the callable recorded, as a
  ;; &curl-transfer-error with that reason, the raised object for
  ;; callback-raised; else, for a CODE but CURLE_OK, perform-failed; each
  ;; failure of its class, with its request size, REQUEST_SIZE, or #f on a
  ;; libcurl whose answer to it is unreliable, ran-request-size's; else the
  ;; response, with its timings, timing-infos', each read as a curl_off_t.
  ;; The answer is data: the engine completes the token with it, and an
  ;; awaiting thread raises a condition.
  (define (finish-transfer live code)
    (let* ((sink (live-transfer-sink live))
           (buffer (live-transfer-buffer live))
           (easy (live-transfer-easy live))
           (recorded (sink-recorded sink)))
      (cond
        (recorded
         (failure (car recorded) code #f buffer
                  (and (eq? (car recorded) 'callback-raised) (cdr recorded))
                  (ran-request-size easy)))
        ((not (eqv? code curle-ok))
         (failure 'perform-failed code #f buffer #f (ran-request-size easy)))
        (else
         ;; let*: what each part reads, it reads in this order.
         (let* ((status (info-long easy curlinfo-response-code))
                (version (http-version-symbol (info-long easy curlinfo-http-version)))
                (effective (info-text easy curlinfo-effective-url))
                (headers (response-headers easy))
                (timings (map (lambda (timing) (cons (car timing) (info-off-t easy (cdr timing))))
                              timing-infos)))
           (make-curl-response status version effective headers (sink-body sink) timings)))))))
