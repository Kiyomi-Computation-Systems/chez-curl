#!r6rs
;;; (curl private transfer): one blocking request, run on the calling
;;; thread through curl_easy_perform (M2 plan, sections 3 and 5). Private:
;;; (curl) exports nothing of it in M2, and M3's engine reuses it.
;;;
;;; A request is a record whose fields are checked when it is made, before
;;; anything native: wrong types are assertion violations, and a header or
;;; a user agent libcurl would send otherwise than asked, or a CA file's
;;; path holding U+0000, is a &curl-request-error. Header strings are
;;; Latin-1, both ways (ADR-0001, amended 2026-10-23); a CA file's path is
;;; UTF-8, as every other string. The URL is checked when the transfer
;;; runs, by call-with-parsed-url and require-http-scheme (ADR-0008).
;;;
;;; A request holds the caller's strings and lists, which stay mutable. So
;;; perform-transfer checks nothing it does not own: it first takes a
;;; snapshot, fresh pairs and fresh strings for the headers, the user agent
;;; and the CA file, checks the snapshot by the constructor's rules, and
;;; sends only the snapshot. A request changed after it was made is refused
;;; then, before anything native; a change it takes is sent as changed. The
;;; URL takes the same path inside call-with-parsed-url, and every C string
;;; inside native.
;;;
;;; perform-transfer makes, on this thread, and frees before it returns,
;;; raises or escapes, under dynamic-wind (plan, section 3.1), but for the
;;; easy handle of a perform left without its return (below):
;;;
;;;   - the CURLU handle, call-with-parsed-url's;
;;;   - the transfer's key, registered in a table write-body reads, counted
;;;     as transfer;
;;;   - the error buffer, a counted block of CURL_ERROR_SIZE bytes, zeroed
;;;     through the checked copy;
;;;   - the header list, a string list of Latin-1 copies, counted as slist;
;;;   - the easy handle.
;;;
;;; They nest in that order, so they are freed the other way round: the easy
;;; handle is cleaned up before the header list, the error buffer and the
;;; CURLU it used are freed. Re-entering any of them through a continuation,
;;; once freed, raises an assertion violation.
;;;
;;; Asynchronous escapes (ADR-0013, amended 2026-10-23). An interrupt
;;; handler may invoke a continuation at any safe point: an engine's
;;; expiry, a timer-interrupt-handler, a keyboard interrupt and reset, a
;;; collect-request-handler. Escapes are allowed, and counted:
;;;
;;;   - curl_easy_perform runs outside any critical section, so this thread
;;;     answers its interrupts and its own collect requests while a
;;;     transfer runs. A handler may then escape from write-body, abandoning
;;;     perform's C frames;
;;;   - the easy handle carries a performing mark, set just before
;;;     curl_easy_perform and cleared just after it returns, each in a
;;;     critical section. When the easy extent's after thunk finds it still
;;;     set, control left perform without its return, and curl_easy_cleanup
;;;     is never called: libcurl must never be called on a handle whose
;;;     call is still running. That handle stays counted as easy. The other
;;;     extents, the header list, the error buffer, the CURLU and the key,
;;;     are freed as ever, since libcurl never runs on that handle again;
;;;   - each extent is a dynamic-wind whose critical? argument is #t: making
;;;     its native object, and recording it where the after thunk frees it,
;;;     happen in one critical section, and so does the free;
;;;   - each mutex is held through locked, in a critical section: Chez's
;;;     with-mutex takes its mutex in a dynamic-wind's before thunk, so an
;;;     escape between the take and the wind would leave the mutex held,
;;;     and every other thread's transfer blocked on it.
;;;
;;; The limits, stated rather than fixed:
;;;
;;;   - an escape from perform leaks libcurl's connection, about 8 KB and
;;;     its connection's sockets, how many is libcurl's, and leaves one easy
;;;     counted, so a suite fails on it;
;;;   - a transfer cannot be paused by an engine and resumed: its extents
;;;     refuse re-entry once freed;
;;;   - an escape during (curl private native)'s load wedges that library
;;;     for the process, since load-step records raises, not escapes;
;;;   - an escape from inside CHUNK-HOOK, the test seam, meets the hook's
;;;     refusal below: the transfer raises callback-raised, and an engine
;;;     that expired there cannot finish ("no engine active").
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
;;; tls-settings computes from its snapshot's CA file and verification, as
;;; data, by one call, set-tls-options!, after the request's other settings
;;; and before the test seam's: SSL_VERIFYPEER and SSL_VERIFYHOST at 1 and
;;; 2, or both 0 with verification off; then, with a CA file, CAINFO at its
;;; path and CAPATH cleared, so the CA file is the request's only trust
;;; anchor, whatever CA directory the build defaults to. A backend with no
;;; CA directory answers the clear CURLE_NOT_BUILT_IN, which is taken. A CA
;;; file of #f is libcurl's system store, as built, and sets neither. The
;;; four names stand in this file only in request-field-options. Guix's
;;; libcurl writes SSL_CERT_FILE and SSL_CERT_DIR over CAINFO and CAPATH
;;; when a transfer starts, after every setopt; what chez-curl does about
;;; that is M4's.
;;;
;;; write-body is the one callable (plan, section 3.5): __collect_safe,
;;; since curl_easy_perform is (ADR-0013), locked where it is defined and
;;; never unlocked, and handed the transfer's key, an integer, as its
;;; WRITEDATA, so no Scheme object crosses into C. No raise leaves it: its
;;; whole body runs under a guard that records anything raised against the
;;; key and returns 0. CHUNK-HOOK, the one caller code it runs, runs in a
;;; dynamic-wind that turns an exit by continuation, or a re-entry, into a
;;; raise there. libcurl then answers CURLE_WRITE_ERROR, 23, and the
;;; transfer raises what was recorded. So caller code leaves it only by
;;; its return. An interrupt handler can still escape from it, abandoning
;;; curl_easy_perform's C frames and libcurl's connection: the performing
;;; mark covers that (above). The body limit takes the same path:
;;; CURLOPT_MAXFILESIZE_LARGE is the limit plus one (plan, section 5.3), so
;;; a declared length past that is refused before its body, and the
;;; callable refuses the first byte past the limit itself, on every libcurl.
;;;
;;; perform-transfer-with is a test seam held to ADR-0009's rules, narrowed
;;; (ADR-0009, amended 2026-10-23): long, enumerated-value and off_t options
;;; alone, none chez-curl owns, nor an owned setting's twin, the CA file's
;;; CAINFO_BLOB and SSL_OPTIONS among them (amended 2026-10-24), compared by
;;; id.
;;;
;;; The pins, ADR-0003's PROTOCOLS_STR and REDIR_PROTOCOLS_STR at
;;; "http,https" and NOSIGNAL at 1, are pinned-options, set by one call,
;;; set-pinned-options!, the first form of the easy handle's extent, before
;;; curl_easy_perform. Their names, and the deprecated bitmasks', stand in
;;; this file only as data, in pinned-options and owned-option-names.
;;;
;;; It imports foreign-callable, foreign-callable-entry-point and
;;; lock-object, which check-seam lets this library alone import (ADR-0007,
;;; plan, section 3.6).
(library (curl private transfer)
  (export make-transfer-request transfer-request?
          transfer-request-url transfer-request-method transfer-request-headers
          transfer-request-user-agent transfer-request-timeout-ms transfer-request-body-limit
          transfer-request-ca-file transfer-request-verify transfer-request-chunk-hook
          perform-transfer perform-transfer-with
          transfer-response? transfer-response-status transfer-response-http-version
          transfer-response-effective-url transfer-response-headers transfer-response-body
          option-bindings option-binding option-setter http-version-symbol bytes->latin-1 pinned-options
          request-field-options owned-option-names live-transfer-count cached-option-names
          tls-settings setopt-accepted?)
  (import (curl private require-threaded)
          (except (rnrs) dynamic-wind)
          (rnrs mutable-strings)
          (only (chezscheme) critical-section dynamic-wind foreign-callable
                foreign-callable-entry-point lock-object make-mutex with-mutex foreign-sizeof)
          (curl private conditions)
          (curl private constants)
          (curl private counters)
          (curl private memory)
          (curl private native)
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
                         ((framing-header) "a Content-Length or Transfer-Encoding header: libcurl frames the message, and M2 sends no body")
                         ((owned-option) "chez-curl sets this option, or its twin, itself")
                         (else "the test seam takes long, enumerated-value and off_t options alone")))
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
  ;; in any case, framing-header: M2 sends no body, and libcurl frames the
  ;; message itself.
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

  ;; refuse-ca-file : Symbol String -> Nothing
  ;; The refusal of a CA file whose path PATH holds U+0000, as WHO.
  (define (refuse-ca-file who path)
    (raise (condition (make-curl-request-error 'ca-file path 'embedded-nul)
                      (make-who-condition who)
                      (make-message-condition
                       "a CA file's path holds U+0000, where C would end it, and libcurl would open another file")
                      (make-irritants-condition (list path)))))

  ;; ca-file-copy : Symbol (U String #f) -> (U String #f)
  ;; CA-FILE, a ca-file?, as a fresh string, checked: what WHO may send as
  ;; CAINFO; #f for #f. A path holding U+0000 is refused as embedded-nul, a
  ;; &curl-request-error naming ca-file. No other char is refused: a path
  ;; may hold CR or LF. The copy is made before the check, so what is
  ;; checked is what is sent. It is scanned by index, allocating nothing:
  ;; a path may be megabytes long, and libcurl refuses one past 8000000
  ;; bytes itself.
  (define (ca-file-copy who ca-file)
    (and ca-file
         (let ((copy (string-copy ca-file)))
           (let scan ((i 0))
             (when (< i (string-length copy))
               (when (char=? (string-ref copy i) #\nul)
                 (refuse-ca-file who copy))
               (scan (+ i 1))))
           copy)))

  ;; body-limit-bound : Positive-Integer
  ;; A body limit is below 2^63 - 1, so the limit plus one, which
  ;; MAXFILESIZE_LARGE gets, is a curl_off_t.
  (define body-limit-bound (- (expt 2 63) 1))

  ;; make-transfer-request : String (U 'get 'head) (Listof (Pairof String String))
  ;;                         (U String #f) (U Positive-Integer #f) (U Natural #f)
  ;;                         (U String #f) Boolean (U (Bytevector -> Any) #f) -> Request
  ;; transfer-request? : Any -> Boolean
  ;; transfer-request-url : Request -> String
  ;; transfer-request-method : Request -> (U 'get 'head)
  ;; transfer-request-headers : Request -> (Listof (Pairof String String))
  ;; transfer-request-user-agent : Request -> (U String #f)
  ;; transfer-request-timeout-ms : Request -> (U Positive-Integer #f)
  ;; transfer-request-body-limit : Request -> (U Natural #f)
  ;; transfer-request-ca-file : Request -> (U String #f)
  ;; transfer-request-verify : Request -> Boolean
  ;; transfer-request-chunk-hook : Request -> (U (Bytevector -> Any) #f)
  ;;
  ;; URL, a string, parsed when the transfer runs. METHOD, get or head.
  ;; HEADERS, (NAME . VALUE) strings, in the order sent, repeats kept, but
  ;; for Host: libcurl sends a Host header in place of its own, first,
  ;; before every other header, and spelt Host, whatever its case here; and
  ;; a second Host header, in any case, is refused as duplicates-field
  ;; (RFC 9112, section 3.2, has a server answer 400 to more than one); and
  ;; a Content-Length or Transfer-Encoding header, in any case, as
  ;; framing-header: a server would wait for a body M2 never sends.
  ;; USER-AGENT, a non-empty string, or #f for none. TIMEOUT-MS, a positive
  ;; exact integer a long holds, or #f for libcurl's default, none.
  ;; BODY-LIMIT, an exact natural below 2^63 - 1, or #f for none.
  ;; CA-FILE, a CA file's path, a non-empty string, sent as given, relative
  ;; or absolute: the request's only trust anchor (ADR-0018); or #f for
  ;; libcurl's system store, as built. VERIFY, #t to verify the peer's
  ;; chain and its name, #f to verify neither: libcurl then reads no CA.
  ;; CHUNK-HOOK, #f, or a procedure handed a fresh copy of each chunk,
  ;; inside the callable, after the limit check: a test seam, private. It
  ;; must return: an exit any other way is refused, as a raise.
  ;;
  ;; A wrong type is an assertion violation, the empty string as a CA file
  ;; among them. Then, in order, snapshot's rules for the headers and the
  ;; user agent, and ca-file-copy's for the CA file, each refusal a
  ;; &curl-request-error naming the field. The record keeps the caller's
  ;; objects; perform-transfer checks them again, as a snapshot.
  (define-record-type (transfer-request make-transfer-request transfer-request?)
    (fields (immutable url transfer-request-url)
            (immutable method transfer-request-method)
            (immutable headers transfer-request-headers)
            (immutable user-agent transfer-request-user-agent)
            (immutable timeout-ms transfer-request-timeout-ms)
            (immutable body-limit transfer-request-body-limit)
            (immutable ca-file transfer-request-ca-file)
            (immutable verify transfer-request-verify)
            (immutable chunk-hook transfer-request-chunk-hook))
    (protocol
     (lambda (new)
       (lambda (url method headers user-agent timeout-ms body-limit ca-file verify chunk-hook)
         (define (wrong message irritant)
           (assertion-violation 'make-transfer-request message irritant))
         (unless (string? url) (wrong "a URL is a string" url))
         (unless (memq method '(get head)) (wrong "a method is get or head" method))
         (unless (or (not timeout-ms) (and (long? timeout-ms) (positive? timeout-ms)))
           (wrong "a timeout is a positive exact integer a long holds, or #f" timeout-ms))
         (unless (or (not body-limit)
                     (and (integer? body-limit) (exact? body-limit) (<= 0 body-limit)
                          (< body-limit body-limit-bound)))
           (wrong "a body limit is an exact natural below 2^63 - 1, or #f" body-limit))
         (unless (ca-file? ca-file)
           (wrong "a CA file is a non-empty string, its path, or #f" ca-file))
         (unless (boolean? verify) (wrong "verify is #t or #f" verify))
         (unless (or (not chunk-hook) (procedure? chunk-hook))
           (wrong "a chunk hook is a procedure or #f" chunk-hook))
         (snapshot 'make-transfer-request headers user-agent)
         (ca-file-copy 'make-transfer-request ca-file)
         (new url method headers user-agent timeout-ms body-limit ca-file verify chunk-hook)))))

  ;; --- the response -----------------------------------------------------------------

  ;; transfer-response? : Any -> Boolean
  ;; transfer-response-status : Response -> Integer
  ;; transfer-response-http-version : Response -> (U Symbol Integer #f)
  ;; transfer-response-effective-url : Response -> (U String #f)
  ;; transfer-response-headers : Response -> (Listof (Pairof String String))
  ;; transfer-response-body : Response -> Bytevector
  ;; What a transfer answered: RESPONSE_CODE; HTTP_VERSION, by
  ;; http-version-symbol; EFFECTIVE_URL, read as UTF-8; every header of the
  ;; last request, CURLH_HEADER's, as Latin-1 strings in libcurl's order;
  ;; and the body.
  (define-record-type (transfer-response make-transfer-response transfer-response?)
    (fields (immutable status transfer-response-status)
            (immutable http-version transfer-response-http-version)
            (immutable effective-url transfer-response-effective-url)
            (immutable headers transfer-response-headers)
            (immutable body transfer-response-body)))

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

  ;; fail : Symbol (U Integer #f) (U String #f) (U Positive-Integer #f) Any -> Nothing
  ;; Raises &curl-transfer-error for REASON, with CODE's strerror and the
  ;; error buffer's text, read now, while the buffer lives.
  (define (fail reason code option buffer recorded)
    (let ((strerror (and code (curl-easy-strerror code))))
      (raise (condition (make-curl-transfer-error reason code option strerror
                                                  (error-buffer-text buffer) recorded)
                        (make-who-condition 'perform-transfer)
                        (make-message-condition
                         (or strerror
                             (case reason
                               ((unknown-option) "the loaded libcurl does not know this option")
                               ((no-handle) "curl_easy_init returned NULL")
                               (else "the transfer failed"))))
                        (make-irritants-condition (if option (list option) '()))))))

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
  ;; being a field's (ADR-0009, consequences). The TLS fields set two each,
  ;; in the order tls-settings makes them: ca-file CAINFO, its path, then
  ;; CAPATH, cleared; verify SSL_VERIFYPEER, then SSL_VERIFYHOST (ADR-0018).
  (define request-field-options
    '((url "CURLU") (method "NOBODY") (headers "HTTPHEADER") (user-agent "USERAGENT")
      (timeout-ms "TIMEOUT_MS") (body-limit "MAXFILESIZE_LARGE") (ca-file "CAINFO" "CAPATH")
      (verify "SSL_VERIFYPEER" "SSL_VERIFYHOST")))

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

  ;; owned-option-names : (Listof String)
  ;; The options the test seam refuses, by name (ADR-0009, amended
  ;; 2026-10-23 and 2026-10-24): those the transfer always sets, and the
  ;; protocol pins' deprecated bitmasks; then every option of each request
  ;; field; then each owned setting's twin, an option with an id of its own
  ;; that sets the same thing: the CA file's are CAINFO_BLOB, which adds a
  ;; CA, and SSL_OPTIONS, whose NATIVE_CA adds the system store. They are
  ;; compared by id, so an alias name is refused too.
  (define owned-option-names
    (append '("URL" "PROTOCOLS_STR" "REDIR_PROTOCOLS_STR" "PROTOCOLS" "REDIR_PROTOCOLS"
              "NOSIGNAL" "WRITEFUNCTION" "WRITEDATA" "ERRORBUFFER")
            (apply append (map cdr request-field-options))
            '("TIMEOUT" "MAXFILESIZE" "HTTPGET" "POST" "UPLOAD" "PUT" "CAINFO_BLOB" "SSL_OPTIONS")))

  ;; pinned-options : (Listof (Pairof String (U String Integer)))
  ;; The settings every transfer makes, before its own: ADR-0003's protocol
  ;; pins, PROTOCOLS_STR and REDIR_PROTOCOLS_STR at "http,https", and
  ;; NOSIGNAL at 1, so that no signal handler is installed in a process that
  ;; runs threads. tests/test-transfer.sps writes it out.
  (define pinned-options
    '(("PROTOCOLS_STR" . "http,https") ("REDIR_PROTOCOLS_STR" . "http,https") ("NOSIGNAL" . 1)))

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

  ;; set-pinned-options! : Positive-Integer (U Positive-Integer #f) -> Void
  ;; Each of pinned-options set on EASY, in order: a string through a C
  ;; string, a number as it is.
  (define (set-pinned-options! easy buffer)
    (for-each (lambda (pin)
                (if (string? (cdr pin))
                    (set-string-option! easy (car pin) (cdr pin) buffer)
                    (set-option! easy (car pin) (cdr pin) buffer)))
              pinned-options))

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
    (define (wrong message irritant) (assertion-violation 'perform-transfer-with message irritant))
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
                 (refuse-field 'perform-transfer-with 'options name 'owned-option))
               (unless (and type (memq (car type) '(long values off-t)))
                 (refuse-field 'perform-transfer-with 'options name 'unsupported-type))
               (unless (if (eq? (car type) 'off-t) (off-t? value) (long? value))
                 (wrong "the value does not fit the option's type" (cons name value)))
               (loop (cdr rest) (- left 1) (cons (cons name value) found)))))))

  ;; --- the transfers write-body serves ------------------------------------------------

  ;; A sink is what one transfer's callable writes to: its limit and hook,
  ;; the bytes received, the chunks kept, newest first, and what was
  ;; recorded, #f or (REASON . OBJECT).
  (define-record-type sink
    (fields (immutable limit) (immutable hook)
            (mutable received) (mutable chunks) (mutable recorded)))

  ;; The live transfers, by key, and the next key, under the mutex.
  (define sinks (make-eqv-hashtable))
  (define sinks-lock (make-mutex))
  (define next-key 1)

  ;; live-transfer-count : -> Natural
  ;; How many transfers the table holds now: a private accessor, for the
  ;; test that it is empty once they have ended.
  (define (live-transfer-count)
    (locked sinks-lock (lambda () (hashtable-size sinks))))

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

  ;; hook-refusal : Symbol -> Condition
  ;; What write-body records when CHUNK-HOOK left otherwise than by
  ;; returning: escaped through a continuation, or re-entered through one.
  (define (hook-refusal how)
    (condition (make-assertion-violation)
               (make-who-condition 'write-body)
               (make-message-condition
                "CHUNK-HOOK must return: control may leave the write callable only by its return")
               (make-irritants-condition (list how))))

  ;; call-hook : (Bytevector -> Any) Bytevector -> Void
  ;; HOOK on CHUNK, in a dynamic-wind, so caller code leaves it only by its
  ;; return or a raise, which goes on to write-body's guard. Its after thunk
  ;; turns an exit through a continuation into a raise of
  ;; (hook-refusal 'escaped), and its before thunk refuses a re-entry, so
  ;; neither abandons curl_easy_perform's C frames. An interrupt handler's
  ;; escape from inside HOOK meets the same refusal: the after thunk cannot
  ;; tell the two apart.
  (define (call-hook hook chunk)
    (let ((state 'ready) (raised #f))
      (dynamic-wind
        (lambda ()
          (unless (eq? state 'ready)
            (set! state 'refused)
            (raise (hook-refusal 're-entered))))
        (lambda ()
          (set! state 'running)
          (guard (e (#t (set! raised e) (set! state 'raised)))
            (hook chunk)
            (set! state 'returned)))
        (lambda ()
          (when (eq? state 'running)
            (set! state 'escaped)
            (raise (hook-refusal 'escaped)))))
      (when (eq? state 'raised) (raise raised))))

  ;; write-body : Code
  ;; libcurl's curl_write_callback for every transfer: DATA, SIZE times
  ;; NMEMB bytes of body, for the transfer KEY names. If they would take it
  ;; past its limit, it records body-limit and answers 0. Otherwise it
  ;; copies them with the checked copy, hands the hook a fresh copy through
  ;; call-hook, keeps the chunk, and answers their count. No raise leaves
  ;; it: its whole body runs under a guard, which records anything raised
  ;; as callback-raised and answers 0. An interrupt handler may escape from
  ;; it; the easy handle's performing mark covers that. An empty chunk,
  ;; which libcurl hands an empty body, is kept as nothing.
  (define write-body
    (foreign-callable __collect_safe
      (lambda (data size nmemb key)
        (guard (e (#t (record! key 'callback-raised e) 0))
          (let ((sink (sink-of key)) (n (* size nmemb)))
            (cond
              ((not sink) 0)
              ((= n 0) 0)
              ((and (sink-limit sink) (> (+ (sink-received sink) n) (sink-limit sink)))
               (record! key 'body-limit #f)
               0)
              (else
               (let ((chunk (make-bytevector n)))
                 (copy-foreign->bytevector! data chunk 0 n)
                 (when (sink-hook sink)
                   (call-hook (sink-hook sink) (bytevector-copy chunk)))
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

  ;; --- extents ----------------------------------------------------------------------

  ;; within : Symbol (-> A) (A -> Any) (A -> B) -> B
  ;; PROC's answer, given what MAKE made, which FREE frees once PROC
  ;; returns, raises or escapes. When MAKE raises, nothing was made, and
  ;; nothing is freed. Re-entering PROC through a continuation, once freed,
  ;; raises an assertion violation from WHO, the extent's name: the
  ;; outermost extent's refusal comes first, so a test that re-enters sees
  ;; which extent is outermost. The dynamic-wind is critical: MAKE and the
  ;; record of what it made run in one critical section with the record of
  ;; entry, and FREE with the record of exit, so no interrupt that escapes
  ;; falls between.
  (define (within who make free proc)
    (let ((made #f) (freed #f))
      (dynamic-wind #t
        (lambda ()
          (when freed
            (assertion-violation who "re-entered after its native object was freed"))
          (set! made (make)))
        (lambda () (proc made))
        (lambda ()
          (set! freed #t)
          (free made)))))

  ;; call-with-sink : Request (Natural Sink -> Any) -> Any
  ;; PROC given a fresh key and its sink, registered while PROC runs, and
  ;; counted as transfer. The count falls only when the key is removed, so
  ;; the count is the table's.
  (define (call-with-sink request proc)
    (within 'call-with-sink
            (lambda ()
              (let ((sink (make-sink (transfer-request-body-limit request)
                                     (transfer-request-chunk-hook request) 0 '() #f)))
                (locked sinks-lock
                  (lambda ()
                    (let ((key next-key))
                      (set! next-key (+ next-key 1))
                      (hashtable-set! sinks key sink)
                      (count-up! 'transfer)
                      (cons key sink))))))
            (lambda (registered)
              (let ((removed (locked sinks-lock
                               (lambda ()
                                 (and (hashtable-contains? sinks (car registered))
                                      (begin (hashtable-delete! sinks (car registered))
                                             (not (hashtable-contains? sinks (car registered)))))))))
                (when removed (count-down! 'transfer))))
            (lambda (registered) (proc (car registered) (cdr registered)))))

  ;; call-with-error-buffer : (Positive-Integer -> Any) -> Any
  ;; PROC given a counted block of CURL_ERROR_SIZE bytes, zeroed.
  (define (call-with-error-buffer proc)
    (within 'call-with-error-buffer
            (lambda () (foreign-block curl-error-size))
            free-foreign-block!
            (lambda (buffer)
              (copy-bytevector->foreign! (make-bytevector curl-error-size 0) 0 buffer curl-error-size)
              (proc buffer))))

  ;; header-line : (Pairof String String) -> String
  ;; "Name: value", or "Name;" for an empty value: libcurl's form for a
  ;; header sent with no value, where "Name:" would remove it.
  (define (header-line header)
    (if (string=? (cdr header) "")
        (string-append (car header) ";")
        (string-append (car header) ": " (cdr header))))

  ;; call-with-header-list : (Listof (Pairof String String)) (Natural -> Any) -> Any
  ;; PROC given a string list of HEADERS' lines, each a Latin-1 copy, or 0
  ;; for none. curl_slist_append copies its string, so each copy is freed
  ;; as soon as it returns. When it answers NULL, the list built so far is
  ;; still freed.
  (define (call-with-header-list headers proc)
    (within 'call-with-header-list
            (lambda () (vector 0))
            (lambda (held)
              (unless (eqv? (vector-ref held 0) 0)
                (curl-slist-free-all (vector-ref held 0))))
            (lambda (held)
              (for-each
               (lambda (header)
                 (call-with-latin-1-c-string (header-line header)
                   (lambda (address)
                     ;; The list and its record, where the after thunk
                     ;; frees it, in one critical section.
                     (critical-section
                      (let ((appended (curl-slist-append (vector-ref held 0) address)))
                        (when (eqv? appended 0)
                          (error 'perform-transfer "curl_slist_append returned NULL: no memory for a header"
                                 (car header)))
                        (vector-set! held 0 appended))))))
               headers)
              (proc (vector-ref held 0)))))

  ;; An easy handle, and whether curl_easy_perform is running on it: the
  ;; performing mark.
  (define-record-type easy-state
    (fields (immutable address) (mutable performing)))

  ;; call-with-easy : (Positive-Integer (-> Integer) -> Any) -> Any
  ;; PROC given a fresh easy handle and PERFORM, which runs
  ;; curl_easy_perform on it and answers its code; no-handle when
  ;; curl_easy_init answers NULL. PERFORM sets the handle's performing mark
  ;; just before the call, and clears it just after the call returns, each
  ;; in a critical section. When control left the call without its return,
  ;; an interrupt handler escaping from write-body, the mark is still set,
  ;; and the after thunk never calls curl_easy_cleanup: libcurl must never
  ;; be called on a handle whose call is still running. That handle stays
  ;; counted as easy, and its connection is leaked.
  (define (call-with-easy proc)
    (within 'call-with-easy
            (lambda ()
              (let ((easy (curl-easy-init)))
                (when (eqv? easy 0) (fail 'no-handle #f #f #f #f))
                (make-easy-state easy #f)))
            (lambda (state)
              (unless (easy-state-performing state)
                (curl-easy-cleanup (easy-state-address state))))
            (lambda (state)
              (let ((easy (easy-state-address state)))
                (proc easy
                      (lambda ()
                        (critical-section (easy-state-performing-set! state #t))
                        (let ((code (curl-easy-perform easy)))
                          (critical-section (easy-state-performing-set! state #f))
                          code)))))))

  ;; --- the response's parts -----------------------------------------------------------

  ;; info-long : Positive-Integer Integer -> Integer
  (define (info-long easy info)
    (let-values (((code value) (curl-easy-getinfo-long easy info)))
      (unless (eqv? code curle-ok)
        (error 'perform-transfer "curl_easy_getinfo refused a CURLINFO" info code))
      value))

  ;; info-text : Positive-Integer Integer -> (U String #f)
  ;; The CURLINFO string INFO, read as UTF-8.
  (define (info-text easy info)
    (let-values (((code bytes) (curl-easy-getinfo-string easy info)))
      (unless (eqv? code curle-ok)
        (error 'perform-transfer "curl_easy_getinfo refused a CURLINFO" info code))
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

  ;; --- the transfer -------------------------------------------------------------------

  ;; perform-transfer : Request -> Response
  ;; REQUEST's transfer, run on this thread, as perform-transfer-with with
  ;; no options.
  (define (perform-transfer request)
    (perform-transfer-with request '()))

  ;; perform-transfer-with : Request (Listof (Pairof String Integer)) -> Response
  ;; REQUEST's transfer, run on this thread, with OPTIONS, each (NAME .
  ;; VALUE), checked by checked-settings: a test seam, private, held to
  ;; ADR-0009's rules, narrowed (amended 2026-10-23 and 2026-10-24), so no
  ;; option it takes is one the transfer sets, nor such an option's twin.
  ;; Before anything native, it takes the request's snapshot, the headers,
  ;; the user agent and the CA file, and checks it, and checks OPTIONS. Then
  ;; it always sets pinned-options first, then ERRORBUFFER, CURLU,
  ;; WRITEFUNCTION and WRITEDATA; and as the request asks, NOBODY for head,
  ;; HTTPHEADER, USERAGENT, TIMEOUT_MS and MAXFILESIZE_LARGE at the body
  ;; limit plus one; then, always, tls-settings' for the snapshot's CA file
  ;; and verification, through set-tls-options!; then OPTIONS. It follows
  ;; no redirect unless OPTIONS say so. A non-zero code, or anything the
  ;; callable recorded, raises &curl-transfer-error: the recorded reason,
  ;; else perform-failed. Every native object it made is freed before it
  ;; returns, raises or escapes, but the easy handle of a perform left
  ;; without its return, which stays counted (call-with-easy).
  (define (perform-transfer-with request options)
    (unless (transfer-request? request)
      (assertion-violation 'perform-transfer "not a transfer request" request))
    (let* ((fields (snapshot 'perform-transfer (transfer-request-headers request)
                             (transfer-request-user-agent request)))
           (headers (car fields))
           (agent (cdr fields))
           (ca-file (ca-file-copy 'perform-transfer (transfer-request-ca-file request)))
           (verify (transfer-request-verify request))
           (settings (checked-settings options)))
      (call-with-parsed-url (transfer-request-url request)
        (lambda (url)
          (require-http-scheme url)
          (call-with-sink request
            (lambda (key sink)
              (call-with-error-buffer
                (lambda (buffer)
                  (call-with-header-list headers
                    (lambda (header-list)
                      (call-with-easy
                        (lambda (easy perform)
                          (set-pinned-options! easy buffer)
                          (set-option! easy "ERRORBUFFER" buffer #f)
                          (set-option! easy (field-option 'url) url buffer)
                          (set-option! easy "WRITEFUNCTION" write-body-entry buffer)
                          (set-option! easy "WRITEDATA" key buffer)
                          (when (eq? (transfer-request-method request) 'head)
                            (set-option! easy (field-option 'method) 1 buffer))
                          (unless (eqv? header-list 0)
                            (set-option! easy (field-option 'headers) header-list buffer))
                          (when agent
                            (call-with-latin-1-c-string agent
                              (lambda (address)
                                (set-option! easy (field-option 'user-agent) address buffer))))
                          (let ((timeout (transfer-request-timeout-ms request)))
                            (when timeout
                              (set-option! easy (field-option 'timeout-ms) timeout buffer)))
                          (let ((limit (transfer-request-body-limit request)))
                            (when limit
                              (set-option! easy (field-option 'body-limit) (+ limit 1) buffer)))
                          (set-tls-options! easy ca-file verify buffer)
                          (for-each (lambda (setting)
                                      (set-option! easy (car setting) (cdr setting) buffer))
                                    settings)
                          ;; let*, not let: Chez may evaluate a let's inits in
                          ;; any order, and what was recorded is read after the
                          ;; transfer has run.
                          (let* ((code (perform))
                                 (recorded (sink-recorded sink)))
                            (cond
                              (recorded
                               (fail (car recorded) code #f buffer
                                     (and (eq? (car recorded) 'callback-raised) (cdr recorded))))
                              ((not (eqv? code curle-ok))
                               (fail 'perform-failed code #f buffer #f))
                              (else
                               (make-transfer-response
                                (info-long easy curlinfo-response-code)
                                (http-version-symbol (info-long easy curlinfo-http-version))
                                (info-text easy curlinfo-effective-url)
                                (response-headers easy)
                                (sink-body sink))))))))))))))))))
