#!r6rs
;;; (curl private transfer): a request, and its transfer on an engine's
;;; thread (M2 plan, sections 3 and 5; M3 plan, sections 3.1 and 5.2).
;;; Private: (curl) exports nothing of it, and (curl private engine) runs
;;; it.
;;;
;;; A request is a record whose fields are checked when it is made, before
;;; anything native: wrong types are assertion violations, and a header or
;;; a user agent libcurl would send otherwise than asked, or a CA file's
;;; path holding U+0000, is a &curl-request-error. Header strings are
;;; Latin-1, both ways (ADR-0001, amended 2026-10-23); a CA file's path is
;;; UTF-8, as every other string. A request holds no procedure: its last
;;; field, a private fault, is data (M3 plan, section 3.6).
;;;
;;; A request holds the caller's strings and lists, which stay mutable. So
;;; a submit, on the caller's thread, checks nothing it does not own:
;;; prepare-transfer takes a plan, fresh pairs and fresh strings for the
;;; URL, the headers, the user agent and the CA file, checks the plan by
;;; the constructor's rules, checks the test seam's settings, and parses
;;; the plan's URL and checks its scheme, freeing that CURLU before it
;;; returns (ADR-0008, amended 2026-10-24). Every refusal raises there,
;;; before anything is queued. A request changed after it was made is
;;; refused then; a change it takes is sent as changed. The engine sends
;;; only the plan.
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
;;; four names stand in this file only in request-field-options. Guix's
;;; libcurl writes SSL_CERT_FILE and SSL_CERT_DIR over CAINFO and CAPATH
;;; when a transfer starts, after every setopt; what chez-curl does about
;;; that is M4's.
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
;;; set-pinned-options!, the first form of set-transfer-options!. Their
;;; names, and the deprecated bitmasks', stand in this file only as data,
;;; in pinned-options and owned-option-names.
;;;
;;; It imports foreign-callable, foreign-callable-entry-point and
;;; lock-object, which check-seam lets this library alone import (ADR-0007,
;;; M2 plan, section 3.6).
(library (curl private transfer)
  (export make-transfer-request transfer-request?
          transfer-request-url transfer-request-method transfer-request-headers
          transfer-request-user-agent transfer-request-timeout-ms transfer-request-body-limit
          transfer-request-ca-file transfer-request-verify transfer-request-fault
          prepare-transfer start-transfer! finish-transfer free-transfer!
          live-transfer-easy live-transfer-chunks transfer-ended planted-fault transfers-started
          abandon-transfer-easy!
          transfer-response? transfer-response-status transfer-response-http-version
          transfer-response-effective-url transfer-response-headers transfer-response-body
          option-bindings option-binding option-setter http-version-symbol bytes->latin-1 pinned-options
          request-field-options owned-option-names live-transfer-count cached-option-names
          tls-settings setopt-accepted?)
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
  ;;                         (U String #f) Boolean (U Positive-Integer #f) -> Request
  ;; transfer-request? : Any -> Boolean
  ;; transfer-request-url : Request -> String
  ;; transfer-request-method : Request -> (U 'get 'head)
  ;; transfer-request-headers : Request -> (Listof (Pairof String String))
  ;; transfer-request-user-agent : Request -> (U String #f)
  ;; transfer-request-timeout-ms : Request -> (U Positive-Integer #f)
  ;; transfer-request-body-limit : Request -> (U Natural #f)
  ;; transfer-request-ca-file : Request -> (U String #f)
  ;; transfer-request-verify : Request -> Boolean
  ;; transfer-request-fault : Request -> (U Positive-Integer #f)
  ;;
  ;; URL, a string, parsed at submit, and again on the engine's thread. METHOD, get or head.
  ;; HEADERS, (NAME . VALUE) strings, in the order sent, repeats kept, but
  ;; for Host: libcurl sends a Host header in place of its own, first,
  ;; before every other header, and spelt Host, whatever its case here; and
  ;; a second Host header, in any case, is refused as duplicates-field
  ;; (RFC 9112, section 3.2, has a server answer 400 to more than one); and
  ;; a Content-Length or Transfer-Encoding header, in any case, as
  ;; framing-header: a server would wait for a body chez-curl never sends.
  ;; USER-AGENT, a non-empty string, or #f for none. TIMEOUT-MS, a positive
  ;; exact integer a long holds, or #f for libcurl's default, none.
  ;; BODY-LIMIT, an exact natural below 2^63 - 1, or #f for none.
  ;; CA-FILE, a CA file's path, a non-empty string, sent as given, relative
  ;; or absolute: the request's only trust anchor (ADR-0018); or #f for
  ;; libcurl's system store, as built. VERIFY, #t to verify the peer's
  ;; chain and its name, #f to verify neither: libcurl then reads no CA.
  ;; FAULT, #f, or a positive exact integer: a planted fault, private, the
  ;; test seam's, that makes the callable raise (planted-fault FAULT) at the
  ;; chunk of that number, counting from 1, before its limit check (M3
  ;; plan, section 3.6). It is data, never a procedure: a request holds no
  ;; caller code (ADR-0012, decision 4).
  ;;
  ;; A wrong type is an assertion violation, the empty string as a CA file
  ;; among them. Then, in order, snapshot's rules for the headers and the
  ;; user agent, and ca-file-copy's for the CA file, each refusal a
  ;; &curl-request-error naming the field. The record keeps the caller's
  ;; objects; a submit checks them again, as a plan.
  (define-record-type (transfer-request make-transfer-request transfer-request?)
    (fields (immutable url transfer-request-url)
            (immutable method transfer-request-method)
            (immutable headers transfer-request-headers)
            (immutable user-agent transfer-request-user-agent)
            (immutable timeout-ms transfer-request-timeout-ms)
            (immutable body-limit transfer-request-body-limit)
            (immutable ca-file transfer-request-ca-file)
            (immutable verify transfer-request-verify)
            (immutable fault transfer-request-fault))
    (protocol
     (lambda (new)
       (lambda (url method headers user-agent timeout-ms body-limit ca-file verify fault)
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
         (unless (or (not fault) (and (integer? fault) (exact? fault) (positive? fault)))
           (wrong "a fault is a positive exact integer, the chunk it raises at, or #f: a request holds no procedure"
                  fault))
         (snapshot 'make-transfer-request headers user-agent)
         (ca-file-copy 'make-transfer-request ca-file)
         (new url method headers user-agent timeout-ms body-limit ca-file verify fault)))))

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

  ;; failure : Symbol (U Integer #f) (U String #f) (U Positive-Integer #f) Any -> Condition
  ;; &curl-transfer-error for REASON, with CODE's strerror and the error
  ;; buffer's text, read now, while the buffer lives.
  (define (failure reason code option buffer recorded)
    (let ((strerror (and code (curl-easy-strerror code))))
      (condition (make-curl-transfer-error reason code option strerror
                                           (error-buffer-text buffer) recorded)
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

  ;; fail : Symbol (U Integer #f) (U String #f) (U Positive-Integer #f) Any -> Nothing
  ;; Raises failure's condition.
  (define (fail reason code option buffer recorded)
    (raise (failure reason code option buffer recorded)))

  ;; transfer-ended : (U 'cancelled 'stopped) -> Condition
  ;; The outcome of a transfer cancelled, or whose engine stopped, before
  ;; it ended: &curl-transfer-error with that reason and no code.
  (define (transfer-ended reason)
    (unless (memq reason '(cancelled stopped))
      (assertion-violation 'transfer-ended "a transfer ends early cancelled or stopped" reason))
    (failure reason #f #f #f #f))

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
  ;; headers, user agent and CA file, its other fields, the test seam's
  ;; settings, and its fault.
  (define-record-type plan
    (fields (immutable url) (immutable method) (immutable headers) (immutable agent)
            (immutable timeout-ms) (immutable body-limit) (immutable ca-file)
            (immutable verify) (immutable settings) (immutable fault)))

  ;; prepare-transfer : Request (Listof (Pairof String Integer)) -> Plan
  ;; REQUEST's plan, with OPTIONS, the test seam's (NAME . VALUE) pairs,
  ;; each checked by checked-settings, on the caller's thread, before
  ;; anything is queued (M3 plan, section 3.4). In order: the snapshot of
  ;; the headers and the user agent, the CA file's copy, OPTIONS, then the
  ;; URL's copy, parsed by call-with-parsed-url and checked by
  ;; require-http-scheme, its CURLU freed before this returns (ADR-0008,
  ;; amended 2026-10-24). Each refusal raises here.
  (define (prepare-transfer request options)
    (unless (transfer-request? request)
      (assertion-violation 'curl-engine-submit "not a transfer request" request))
    (let* ((url (string-copy (transfer-request-url request)))
           (fields (snapshot 'curl-engine-submit (transfer-request-headers request)
                             (transfer-request-user-agent request)))
           (ca-file (ca-file-copy 'curl-engine-submit (transfer-request-ca-file request)))
           (settings (checked-settings options)))
      (call-with-parsed-url url require-http-scheme)
      (make-plan url (transfer-request-method request) (car fields) (cdr fields)
                 (transfer-request-timeout-ms request) (transfer-request-body-limit request)
                 ca-file (transfer-request-verify request) settings
                 (transfer-request-fault request))))

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

  ;; header-line : (Pairof String String) -> String
  ;; "Name: value", or "Name;" for an empty value: libcurl's form for a
  ;; header sent with no value, where "Name:" would remove it.
  (define (header-line header)
    (if (string=? (cdr header) "")
        (string-append (car header) ";")
        (string-append (car header) ": " (cdr header))))

  ;; set-transfer-options! : Positive-Integer Plan Positive-Integer Positive-Integer Natural Positive-Integer -> Void
  ;; Every setting PLAN's transfer makes on EASY, in order: pinned-options
  ;; first, then ERRORBUFFER at BUFFER, CURLU at URL, WRITEFUNCTION and
  ;; WRITEDATA at KEY; and as the request asks, NOBODY for head, HTTPHEADER
  ;; at HEADER-LIST, USERAGENT, TIMEOUT_MS and MAXFILESIZE_LARGE at the body
  ;; limit plus one; then, always, tls-settings' for the plan's CA file and
  ;; verification, through set-tls-options!; then the test seam's settings.
  ;; It follows no redirect unless they say so.
  (define (set-transfer-options! easy plan key buffer header-list url)
    (set-pinned-options! easy buffer)
    (set-option! easy "ERRORBUFFER" buffer #f)
    (set-option! easy (field-option 'url) url buffer)
    (set-option! easy "WRITEFUNCTION" write-body-entry buffer)
    (set-option! easy "WRITEDATA" key buffer)
    (when (eq? (plan-method plan) 'head)
      (set-option! easy (field-option 'method) 1 buffer))
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
    (let ((limit (plan-body-limit plan)))
      (when limit
        (set-option! easy (field-option 'body-limit) (+ limit 1) buffer)))
    (set-tls-options! easy (plan-ca-file plan) (plan-verify plan) buffer)
    (for-each (lambda (setting)
                (set-option! easy (car setting) (cdr setting) buffer))
              (plan-settings plan)))

  ;; start-transfer! : Plan -> Live
  ;; PLAN's transfer, made on this thread, the engine's, ready for its
  ;; multi handle: its key and sink, its URL parsed again and its scheme
  ;; checked again, its error buffer, zeroed, its header list, and its easy
  ;; handle, set by set-transfer-options!. Each object is made, and recorded
  ;; in the live record, in one critical section. A raise frees what was
  ;; made, by free-transfer!, then raises again: the URL's refusal, or a
  ;; &curl-transfer-error, setopt-failed, unknown-option or no-handle.
  (define (start-transfer! plan)
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
         (lambda (header)
           (call-with-latin-1-c-string (header-line header)
             (lambda (address)
               ;; The list and its record, where free-transfer! frees it, in
               ;; one critical section.
               (critical-section
                (let ((appended (curl-slist-append (live-transfer-header-list live) address)))
                  (when (eqv? appended 0)
                    (error 'start-transfer! "curl_slist_append returned NULL: no memory for a header"
                           (car header)))
                  (live-transfer-header-list-set! live appended))))))
         (plan-headers plan))
        (critical-section
         (let ((easy (curl-easy-init)))
           (when (eqv? easy 0) (fail 'no-handle #f #f #f #f))
           (live-transfer-easy-set! live easy)))
        (set-transfer-options! (live-transfer-easy live) plan (live-transfer-key live)
                               (live-transfer-buffer live) (live-transfer-header-list live)
                               (live-transfer-url live))
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
  ;; callback-raised; else, for a CODE but CURLE_OK, perform-failed; else
  ;; the response. The answer is data: the engine completes the token with
  ;; it, and an awaiting thread raises a condition.
  (define (finish-transfer live code)
    (let* ((sink (live-transfer-sink live))
           (buffer (live-transfer-buffer live))
           (easy (live-transfer-easy live))
           (recorded (sink-recorded sink)))
      (cond
        (recorded
         (failure (car recorded) code #f buffer
                  (and (eq? (car recorded) 'callback-raised) (cdr recorded))))
        ((not (eqv? code curle-ok))
         (failure 'perform-failed code #f buffer #f))
        (else
         ;; let*: what each part reads, it reads in this order.
         (let* ((status (info-long easy curlinfo-response-code))
                (version (http-version-symbol (info-long easy curlinfo-http-version)))
                (effective (info-text easy curlinfo-effective-url))
                (headers (response-headers easy)))
           (make-transfer-response status version effective headers (sink-body sink))))))))
