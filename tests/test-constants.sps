#!r6rs
;;; The suite for chez-curl's constants and struct layouts, each checked
;;; against libcurl's own headers by a C program compiled here, at test
;;; time (ADR-0001, decisions 3 and 4).
;;;
;;;   constants  src/curl/private/constants.sls, read as data for its
;;;              export list. Each export has a row in constant-rows,
;;;              naming the C expression its value must equal, and each
;;;              row is an export. A row's C name is the export's name
;;;              upcased, - as _, unless c-name-aliases names another. The
;;;              values come from (curl private constants) itself. A row
;;;              (each PREFIX) marks a list of (NAME . VALUE) entries, each
;;;              checked against PREFIX and NAME upcased, - as _: ntlm-wb is
;;;              CURL_VERSION_NTLM_WB. PREFIX is the export's name less its
;;;              last word, upcased, - as _, then _, unless c-name-aliases
;;;              names another: curl-version-features's is CURL_VERSION_.
;;;              Each alias must change what its row's export derives.
;;;   gates      a constant newer than the libcurl floor, which older
;;;              headers lack, has a row in gated-rows: the curl release
;;;              that added it, as text and as LIBCURL_VERSION_NUM, newer
;;;              than packaging/floors.sexp's floor. An enum member is no
;;;              macro, so the C program reads it only under #if
;;;              LIBCURL_VERSION_NUM >= that gate, and else answers
;;;              (unchecked NAME); against those older headers the suite
;;;              names it unchecked, and checks its value everywhere else.
;;;              A compile of the constant alone, beside a control that must
;;;              compile and one that must not, says whether the headers
;;;              declare it: they must exactly when they are at or above its
;;;              gate, so a gate set too high fails where the headers have
;;;              it, and one too low fails where they lack it.
;;;   layouts    src/curl/private/layouts.sls, read as data. It is one
;;;              datum, the library (curl private layouts), whose imports
;;;              are exactly (curl private require-threaded), (rnrs) and
;;;              (only (chezscheme) define-ftype), whose body is
;;;              (define-ftype NAME (struct (FIELD TYPE) ...)) forms alone,
;;;              and whose exports are exactly those NAMEs. define-ftype
;;;              appears nowhere else in it, quoted or not. check-seam's
;;;              rule (f) lets this library alone import define-ftype, and
;;;              this suite reads that rule's entry from tests/check-seam.sps
;;;              and requires it to name this library alone. So no function
;;;              ftype, and no macro that makes one, exists under src/.
;;;              Each define-ftype has a row in layout-rows, naming its C
;;;              type, and each row is a define-ftype. Each must be a struct
;;;              of primitive-typed fields, each type one field-kinds holds;
;;;              any other shape fails by name. Every field's offset, size
;;;              and kind are compared with offsetof, sizeof and _Generic.
;;;              Offset alone misses an int written for C's long when
;;;              padding keeps the next field's offset; offset and size
;;;              miss a double written for C's char *. A row says whether
;;;              its ftype is the whole struct or a prefix of it. A whole
;;;              one's ftype-sizeof must equal sizeof, so a field dropped
;;;              from its end fails; a prefix, as curl-version-info-data
;;;              is, stops before the struct's end on purpose.
;;;   curlot-types
;;;              complete: the CURLOT_ names in $CC -E of curl/curl.h,
;;;              which includes curl/options.h, must be exactly
;;;              curlot-types' names, prefixed and upcased, - as _. Its
;;;              values are checked as a list row's are; this check sees a
;;;              type the list leaves out (ADR-0001, amended 2026-10-17).
;;;   prototypes every entry point src/ binds has a row in prototype-rows,
;;;              and every row is bound: the header's declaration, its
;;;              result and parameter types in the header's own spelling.
;;;              The C side: a program asserts, for each row, that the
;;;              entry has one of the row's types, with
;;;              _Static_assert(_Generic(...)), compiled with no link. A
;;;              type the header writes otherwise, an enum written int
;;;              among them, fails the compile. The Scheme side: each
;;;              binding's Chez types, read by (foreign-conventions)'
;;;              scan of src/, must be ones c-type-map allows for the
;;;              row's C types. A variadic declaration ends in "...", and
;;;              names the Chez types a binding may pass there.
;;;   versions   the headers the program compiled against must be no newer
;;;              than the libcurl chez-curl itself loads, which this suite
;;;              loads in its own process through (curl). Headers newer than
;;;              the library vouch for fields and values the library may
;;;              not have: on CI's floor lane, a forgotten C_INCLUDE_PATH
;;;              would check the runner's headers, not 7.85.0's.
;;;
;;; The C program is compiled with $CC and no -I flag: the compiler's own
;;; search path, C_INCLUDE_PATH among it, must find curl/curl.h. Missing
;;; headers fail this suite, never skip it (ADR-0001). A compile is judged
;;; by its exit status alone: Guix's gcc warns on stderr at every link.
;;; The program prints one datum per question, read back here as data.
;;;
;;; Every computation that can raise runs under a guard, before the
;;; tests, with a sentinel of its own: SRFI-64 does not catch a raise in an
;;; expected expression, nor in a suite's top-level definitions, and makes
;;; #f of one in an actual expression. No expected value here is #f.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) getenv foreign-sizeof list-head)
        (foreign-conventions)
        (only (curl private conditions)
              curl-library-unavailable? curl-library-unavailable-reason
              curl-library-unavailable-path)
        (curl-testing)
        (only (floors) read-floors floor-numbers)
        (libcurl-oracle))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; The simple runner names a failing test but not its values. Print both.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (display "  expected: ")
        (write (test-result-ref r 'expected-value))
        (newline)
        (display "  actual:   ")
        (write (test-result-ref r 'actual-value))
        (newline)))))

;; --- the tables ---------------------------------------------------------------

(define constants-source "src/curl/private/constants.sls")
(define layouts-source "src/curl/private/layouts.sls")
(define check-seam-source "tests/check-seam.sps")

;; layouts-name : (Listof Symbol)
;; The library layouts.sls must hold, and the one library check-seam's rule
;; (f) may let import define-ftype.
(define layouts-name '(curl private layouts))

;; layouts-imports : (Listof Any)
;; layouts.sls's import specs, exactly: the refusal first (ADR-0001), and
;; define-ftype alone from (chezscheme).
(define layouts-imports
  '((curl private require-threaded) (rnrs) (only (chezscheme) define-ftype)))

;; constant-rows : (Listof (Pairof Symbol (U String (List 'each String))))
;; Each export of (curl private constants), with the C expression its value
;; must equal, or (each PREFIX) for a list of (NAME . VALUE) entries.
(define constant-rows
  '((curl-version-features . (each "CURL_VERSION_"))
    (curl-version-ssl . "CURL_VERSION_SSL")
    (curl-version-https-proxy . "CURL_VERSION_HTTPS_PROXY")
    (curlhe-not-built-in . "CURLHE_NOT_BUILT_IN")
    (curlh-header . "CURLH_HEADER")
    (curl-global-default . "CURL_GLOBAL_DEFAULT")
    (curle-ok . "CURLE_OK")
    (curle-bad-function-argument . "CURLE_BAD_FUNCTION_ARGUMENT")
    (curle-not-built-in . "CURLE_NOT_BUILT_IN")
    (curlversion-tenth . "CURLVERSION_TENTH")
    (curlinfo-private . "CURLINFO_PRIVATE")
    (curlinfo-rtsp-client-cseq . "CURLINFO_RTSP_CLIENT_CSEQ")
    (curlot-types . (each "CURLOT_"))
    (curlue-ok . "CURLUE_OK")
    (curlue-codes . (each "CURLUE_"))
    (curlupart-url . "CURLUPART_URL")
    (curlupart-scheme . "CURLUPART_SCHEME")
    (curlupart-user . "CURLUPART_USER")
    (curlupart-password . "CURLUPART_PASSWORD")
    (curlupart-host . "CURLUPART_HOST")
    (curlupart-port . "CURLUPART_PORT")
    (curlupart-path . "CURLUPART_PATH")
    (curlupart-query . "CURLUPART_QUERY")
    (curlupart-fragment . "CURLUPART_FRAGMENT")
    (curlupart-zoneid . "CURLUPART_ZONEID")
    (curlu-default-port . "CURLU_DEFAULT_PORT")
    (curlu-non-support-scheme . "CURLU_NON_SUPPORT_SCHEME")
    (curlinfo-response-code . "CURLINFO_RESPONSE_CODE")
    (curlinfo-http-version . "CURLINFO_HTTP_VERSION")
    (curlinfo-effective-url . "CURLINFO_EFFECTIVE_URL")
    (curlinfo-http-connectcode . "CURLINFO_HTTP_CONNECTCODE")
    (curl-error-size . "CURL_ERROR_SIZE")
    (curl-blob-copy . "CURL_BLOB_COPY")
    (curl-http-version-1-0 . "CURL_HTTP_VERSION_1_0")
    (curl-http-version-1-1 . "CURL_HTTP_VERSION_1_1")
    (curl-http-version-2-0 . "CURL_HTTP_VERSION_2_0")
    (curl-http-version-3 . "CURL_HTTP_VERSION_3")
    (curl-http-version-2tls . "CURL_HTTP_VERSION_2TLS")
    (curl-http-version-2-prior-knowledge . "CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE")
    (curlauth-basic . "CURLAUTH_BASIC")
    (curlauth-digest . "CURLAUTH_DIGEST")
    (curlauth-bearer . "CURLAUTH_BEARER")
    (curle-write-error . "CURLE_WRITE_ERROR")
    (curle-out-of-memory . "CURLE_OUT_OF_MEMORY")
    (curle-operation-timedout . "CURLE_OPERATION_TIMEDOUT")
    (curle-couldnt-resolve-proxy . "CURLE_COULDNT_RESOLVE_PROXY")
    (curle-couldnt-resolve-host . "CURLE_COULDNT_RESOLVE_HOST")
    (curle-couldnt-connect . "CURLE_COULDNT_CONNECT")
    (curle-interface-failed . "CURLE_INTERFACE_FAILED")
    (curle-quic-connect-error . "CURLE_QUIC_CONNECT_ERROR")
    (curle-proxy . "CURLE_PROXY")
    (curle-partial-file . "CURLE_PARTIAL_FILE")
    (curle-got-nothing . "CURLE_GOT_NOTHING")
    (curle-send-error . "CURLE_SEND_ERROR")
    (curle-recv-error . "CURLE_RECV_ERROR")
    (curle-ssl-connect-error . "CURLE_SSL_CONNECT_ERROR")
    (curle-ssl-engine-notfound . "CURLE_SSL_ENGINE_NOTFOUND")
    (curle-ssl-engine-setfailed . "CURLE_SSL_ENGINE_SETFAILED")
    (curle-ssl-certproblem . "CURLE_SSL_CERTPROBLEM")
    (curle-ssl-cipher . "CURLE_SSL_CIPHER")
    (curle-peer-failed-verification . "CURLE_PEER_FAILED_VERIFICATION")
    (curle-use-ssl-failed . "CURLE_USE_SSL_FAILED")
    (curle-ssl-engine-initfailed . "CURLE_SSL_ENGINE_INITFAILED")
    (curle-ssl-cacert-badfile . "CURLE_SSL_CACERT_BADFILE")
    (curle-ssl-shutdown-failed . "CURLE_SSL_SHUTDOWN_FAILED")
    (curle-ssl-crl-badfile . "CURLE_SSL_CRL_BADFILE")
    (curle-ssl-issuer-error . "CURLE_SSL_ISSUER_ERROR")
    (curle-ssl-pinnedpubkeynotmatch . "CURLE_SSL_PINNEDPUBKEYNOTMATCH")
    (curle-ssl-invalidcertstatus . "CURLE_SSL_INVALIDCERTSTATUS")
    (curle-ssl-clientcert . "CURLE_SSL_CLIENTCERT")
    (curle-ech-required . "CURLE_ECH_REQUIRED")
    (curle-unsupported-protocol . "CURLE_UNSUPPORTED_PROTOCOL")
    (curle-weird-server-reply . "CURLE_WEIRD_SERVER_REPLY")
    (curle-http2 . "CURLE_HTTP2")
    (curle-bad-content-encoding . "CURLE_BAD_CONTENT_ENCODING")
    (curle-http2-stream . "CURLE_HTTP2_STREAM")
    (curle-http3 . "CURLE_HTTP3")
    (curle-filesize-exceeded . "CURLE_FILESIZE_EXCEEDED")
    (curle-too-large . "CURLE_TOO_LARGE")
    (curlinfo-namelookup-time-t . "CURLINFO_NAMELOOKUP_TIME_T")
    (curlinfo-connect-time-t . "CURLINFO_CONNECT_TIME_T")
    (curlinfo-appconnect-time-t . "CURLINFO_APPCONNECT_TIME_T")
    (curlinfo-starttransfer-time-t . "CURLINFO_STARTTRANSFER_TIME_T")
    (curlinfo-total-time-t . "CURLINFO_TOTAL_TIME_T")
    (curlinfo-request-size . "CURLINFO_REQUEST_SIZE")
    (curlm-ok . "CURLM_OK")
    (curlm-unknown-option . "CURLM_UNKNOWN_OPTION")
    (curlmsg-done . "CURLMSG_DONE")
    (curlmopt-max-total-connections . "CURLMOPT_MAX_TOTAL_CONNECTIONS")
    (curlmopt-quick-exit . "CURLMOPT_QUICK_EXIT")
    (curlmopt-pipelining . "CURLMOPT_PIPELINING")
    (curlpipe-nothing . "CURLPIPE_NOTHING")
    (curl-writefunc-pause . "CURL_WRITEFUNC_PAUSE")
    (curlpause-cont . "CURLPAUSE_CONT")
    (curl-readfunc-pause . "CURL_READFUNC_PAUSE")
    (curl-readfunc-abort . "CURL_READFUNC_ABORT")
    (curl-seekfunc-ok . "CURL_SEEKFUNC_OK")
    (curl-seekfunc-cantseek . "CURL_SEEKFUNC_CANTSEEK")
    (curl-prereqfunc-ok . "CURL_PREREQFUNC_OK")
    (curl-prereqfunc-abort . "CURL_PREREQFUNC_ABORT")
    (seek-set . "SEEK_SET")
    (curlshopt-share . "CURLSHOPT_SHARE")
    (curlshopt-unshare . "CURLSHOPT_UNSHARE")
    (curl-lock-data-cookie . "CURL_LOCK_DATA_COOKIE")
    (curlshe-ok . "CURLSHE_OK")
    (curlshe-bad-option . "CURLSHE_BAD_OPTION")
    (curlshe-in-use . "CURLSHE_IN_USE")
    (curlinfo-cookielist . "CURLINFO_COOKIELIST")
    (curlform-copyname . "CURLFORM_COPYNAME")
    (curlform-copycontents . "CURLFORM_COPYCONTENTS")
    (curlform-end . "CURLFORM_END")
    (curl-formadd-ok . "CURL_FORMADD_OK")
    (curl-formadd-unknown-option . "CURL_FORMADD_UNKNOWN_OPTION")
    (curl-formadd-disabled . "CURL_FORMADD_DISABLED")))

;; c-name-aliases : (Listof (Pairof Symbol String))
;; Each export whose row names a C constant other than the export's own
;; name upcased, - as _, or, for an (each PREFIX) row, a prefix other than
;; the one its name derives, with the one C name or prefix its row must
;; name instead. Each key is a row whose derived name its alias changes:
;; any other entry fails, as a stale permission. Empty: every row's C name
;; is derived. Adding an alias is a reviewed change, never a way to quiet a
;; failing test: a C name written as free text can name any constant whose
;; value happens to match, and a prefix such as "0|CURL_VERSION_" any C
;; expression.
(define c-name-aliases '())

;; gated-rows : (Listof (List Symbol String Natural))
;; Each constant-rows row whose constant came after the libcurl floor, with
;; the curl release that added it, as text and as LIBCURL_VERSION_NUM: its
;; gate. Headers older than the gate lack the constant, and the C program
;; reads it only from headers at or above it. A released constant's value
;; never changes, so the check where the headers have it holds it.
;; CURLMOPT_QUICK_EXIT came in 8.20.0, per its man page; the container's
;; headers are 8.20.0's, and the floor's, 7.85.0's, lack it. CURLE_TOO_LARGE came in
;; 8.6.0 and CURLE_ECH_REQUIRED in 8.8.0, per curl's symbols-in-versions; the
;; floor's headers lack both, and the container's have both.
(define gated-rows
  '((curlmopt-quick-exit "8.20.0" #x081400)
    (curle-too-large "8.6.0" #x080600)
    (curle-ech-required "8.8.0" #x080800)))

;; layout-rows : (Listof (List Symbol String Extent))
;; Each define-ftype of (curl private layouts), with the C type it lays
;; out, and its extent: whole, when it lays out every field, so its
;; ftype-sizeof must be the struct's sizeof; prefix, when it stops before
;; the struct's end on purpose.
(define layout-rows
  '((curl-version-info-data "curl_version_info_data" prefix)
    (curl-easyoption "struct curl_easyoption" whole)
    (curl-header "struct curl_header" whole)
    (curl-msg "struct CURLMsg" whole)
    (curl-blob "struct curl_blob" whole)
    (curl-slist "struct curl_slist" whole)))

(define extents '(whole prefix))

;; field-kinds : (Listof (Pairof Symbol (Listof Kind)))
;; Each Chez primitive type a layout field may have, with the kinds of C
;; member it may lay out. A kind is the C program's answer for a member's
;; type, through _Generic: integer for each standard integer type, floating
;; for float, double and long double, other for anything else: pointers,
;; and arrays, which decay to pointers. uptr and void* lay out a pointer
;; alone, and iptr an integer: an integer member is written with an integer
;; type, size_t for a size, so a uptr written for C's long fails. Signedness
;; is not compared: features is unsigned-int against C's int on purpose
;; (layouts.sls). A field type absent here fails the shape test, by name:
;; add it here, with its kinds, first.
(define field-kinds
  (append
   (map (lambda (type) (cons type '(integer)))
        '(short unsigned-short int unsigned unsigned-int long unsigned-long
          long-long unsigned-long-long
          integer-8 unsigned-8 integer-16 unsigned-16 integer-24 unsigned-24
          integer-32 unsigned-32 integer-40 unsigned-40 integer-48 unsigned-48
          integer-56 unsigned-56 integer-64 unsigned-64
          size_t ssize_t ptrdiff_t iptr))
   (map (lambda (type) (cons type '(floating)))
        '(float double single-float double-float))
   '((uptr other)
     (void* other))))

(define kinds '(integer floating other))

;; --- helpers ------------------------------------------------------------------

;; written : Any -> String
(define (written x)
  (guard (e (#t "<unprintable>"))
    (call-with-string-output-port (lambda (p) (write x p)))))

;; underscored : String -> String
;; S with each - as _.
(define (underscored s)
  (list->string (map (lambda (c) (if (char=? c #\-) #\_ c)) (string->list s))))

;; text : Any -> String
;; X itself when it is a string, else X written.
(define (text x) (if (string? x) x (written x)))

;; each-row? : Row -> Boolean
;; Whether ROW is (NAME . (each PREFIX)), PREFIX a string.
(define (each-row? row)
  (let ((c (cdr row)))
    (and (list? c) (= (length c) 2) (eq? (car c) 'each) (string? (cadr c)))))

;; derived-prefix : Symbol -> (U String (List 'one-word Symbol))
;; The prefix NAME derives for an (each PREFIX) row: NAME less its last
;; hyphen-separated word, upcased, - as _, then _. curl-version-features
;; derives CURL_VERSION_. A name of one word derives none.
(define (derived-prefix name)
  (let ((s (symbol->string name)))
    (let loop ((i (- (string-length s) 1)))
      (cond ((< i 0) (list 'one-word name))
            ((char=? (string-ref s i) #\-)
             (string-append (underscored (string-upcase (substring s 0 i))) "_"))
            (else (loop (- i 1)))))))

;; derived-c-name : Row -> (U String (List 'one-word Symbol))
;; What ROW's export derives: for an (each PREFIX) row its prefix, for any
;; other its name upcased, - as _.
(define (derived-c-name row)
  (if (each-row? row)
      (derived-prefix (car row))
      (underscored (string-upcase (symbol->string (car row))))))

;; c-name-of : Row -> Any
;; The C name, or for an (each PREFIX) row the prefix, ROW must name: its
;; export's alias, else what its export derives. (malformed-aliases) when
;; c-name-aliases is no list of pairs, which the alias tests name.
(define (c-name-of row)
  (guard (e (#t '(malformed-aliases)))
    (cond ((assq (car row) c-name-aliases) => cdr)
          (else (derived-c-name row)))))

(define (natural? x) (and (integer? x) (exact? x) (>= x 0)))

;; hex : Natural -> String
;; N as LIBCURL_VERSION_NUM is written: 0x and at least six hex digits.
(define (hex n)
  (let ((digits (string-downcase (number->string n 16))))
    (string-append "0x" (make-string (max 0 (- 6 (string-length digits))) #\0) digits)))

;; symbol-before? : Symbol Symbol -> Boolean
(define (symbol-before? a b)
  (string<? (symbol->string a) (symbol->string b)))

;; read-data : String -> (U (List 'data (Listof Any)) (List 'unreadable String String)
;;                          (List 'eof-literal String))
;; Every datum in the file at PATH.
(define (read-data path)
  (guard (e (#t (list 'unreadable path (describe e))))
    (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                          (make-transcoder (utf-8-codec)))
      (lambda (port)
        (let loop ((found '()))
          (let ((datum (read port)))
            (cond ((not (eof-object? datum)) (loop (cons datum found)))
                  ((port-eof? port) (list 'data (reverse found)))
                  ;; An #!eof literal would end the reading early.
                  (else (list 'eof-literal path)))))))))

;; library-form? : Any -> Boolean
;; (library NAME (export ...) (import ...) BODY ...)
(define (library-form? d)
  (and (list? d) (>= (length d) 4) (eq? (car d) 'library)
       (list? (caddr d)) (pair? (caddr d)) (eq? (car (caddr d)) 'export)
       (list? (cadddr d)) (pair? (cadddr d)) (eq? (car (cadddr d)) 'import)))

;; read-library : String -> (U (List 'library Library-Form) Failure)
;; The first library form in the file at PATH.
(define (read-library path)
  (let ((found (read-data path)))
    (if (eq? (car found) 'data)
        (let ((form (find library-form? (cadr found))))
          (if form (list 'library form) (list 'no-library-form path)))
        found)))

;; --- constants.sls, read as data ------------------------------------------------

;; constants-read : (U (List 'read (Listof Symbol)) Failure)
;; The export list, when every export is an identifier. A (rename ...)
;; spec is not read, and fails here rather than going unchecked.
(define constants-read
  (guard (e (#t (list 'raised (describe e))))
    (let ((found (read-library constants-source)))
      (if (eq? (car found) 'library)
          (let* ((specs (cdr (caddr (cadr found))))
                 (odd (filter (lambda (spec) (not (symbol? spec))) specs)))
            (if (null? odd) (list 'read specs) (list 'exports-not-identifiers odd)))
          found))))

;; exports : (Listof Symbol)
(define exports
  (if (eq? (car constants-read) 'read) (cadr constants-read) '()))

;; constant-value : Symbol -> Any
;; NAME's value in (curl private constants), or (no-value TEXT).
(define (constant-value name)
  (guard (e (#t (list 'no-value (describe e))))
    (eval name (environment '(curl private constants)))))

;; entries? : Any -> Boolean
;; A non-empty list of (NAME . VALUE), each NAME a symbol.
(define (entries? x)
  (and (list? x) (pair? x)
       (for-all (lambda (entry) (and (pair? entry) (symbol? (car entry)))) x)))

;; --- the gates: constants newer than the floor ----------------------------------

;; dot-split : String -> (Listof String)
;; S cut at each ., empty parts kept.
(define (dot-split s)
  (let loop ((i 0) (start 0) (found '()))
    (cond ((= i (string-length s)) (reverse (cons (substring s start i) found)))
          ((char=? (string-ref s i) #\.)
           (loop (+ i 1) (+ i 1) (cons (substring s start i) found)))
          (else (loop (+ i 1) start found)))))

;; version-num-of-text : String -> (U Natural (List 'not-a-version Any))
;; TEXT, "M.m.p", as LIBCURL_VERSION_NUM writes it, #xMMmmpp: three
;; naturals in ASCII digits, each at most 255.
(define (version-num-of-text text)
  (guard (e (#t (list 'not-a-version text)))
    (let ((parts (dot-split text)))
      (if (and (= (length parts) 3)
               (for-all (lambda (p)
                          (and (> (string-length p) 0)
                               (for-all (lambda (c) (and (char<=? #\0 c) (char<=? c #\9)))
                                        (string->list p))))
                        parts)
               (for-all (lambda (p) (<= (string->number p) 255)) parts))
          (let ((ns (map string->number parts)))
            (+ (* 65536 (car ns)) (* 256 (cadr ns)) (caddr ns)))
          (list 'not-a-version text)))))

;; gated-row-shaped? : Any -> Boolean
;; (NAME TEXT N): a symbol, a release as text, and that release as
;; LIBCURL_VERSION_NUM.
(define (gated-row-shaped? g)
  (and (list? g) (= (length g) 3) (symbol? (car g)) (string? (cadr g)) (natural? (caddr g))
       (eqv? (version-num-of-text (cadr g)) (caddr g))))

;; gated-row-text : Any -> String
;; G as a test names it: its name, its text and its gate in hex, when G has
;; three parts and a natural gate; else G written.
(define (gated-row-text g)
  (if (and (list? g) (= (length g) 3) (natural? (caddr g)))
      (string-append (written (car g)) " " (written (cadr g)) " " (hex (caddr g)))
      (written g)))

;; libcurl-floor-num : (U Natural Symbol)
;; packaging/floors.sexp's libcurl floor, read through (floors) as
;; tests/test-verify.sps reads it, as LIBCURL_VERSION_NUM writes it; a
;; symbol when the file cannot give it.
(define libcurl-floor-num
  (guard (e (#t 'floors-file-unreadable))
    (let ((parts (floor-numbers (read-floors) 'libcurl)))
      (if (and (= (length parts) 3) (for-all (lambda (n) (<= n 255)) parts))
          (+ (* 65536 (car parts)) (* 256 (cadr parts)) (caddr parts))
          'not-a-version-num))))

;; c-name-gates : (Listof (Pairof String GatedRow))
;; Each gated row that is well shaped and names a constant-rows row of one
;; C constant, keyed by that C name, each name once. The C program reads
;; that constant only from headers at or above the row's gate, and the
;; suite checks its value only there. Any other gated row gates nothing,
;; and fails its tests by name.
(define c-name-gates
  (guard (e (#t '()))
    (fold-left (lambda (found g)
                 (let ((row (and (gated-row-shaped? g) (assq (car g) constant-rows))))
                   (if (and row (string? (cdr row)) (not (assoc (cdr row) found)))
                       (append found (list (cons (cdr row) g)))
                       found)))
               '()
               gated-rows)))

;; gate-of : String -> (U GatedRow #f)
;; The gated row of the constant C-NAME, when it has one.
(define (gate-of c-name)
  (cond ((assoc c-name c-name-gates) => cdr) (else #f)))

;; --- layouts.sls, read as data --------------------------------------------------

;; ftype-forms-in : Any -> (Listof Pair)
;; Every list headed by define-ftype in X, at any depth, X's own elements
;; walked one by one. Each pair is walked once, so a cyclic datum ends.
(define (ftype-forms-in x)
  (let ((seen (make-eq-hashtable)))
    (let walk ((x x))
      (cond ((not (pair? x)) '())
            ((eq? (car x) 'define-ftype) (list x))
            (else (let loop ((rest x) (found '()))
                    (if (and (pair? rest) (not (hashtable-ref seen rest #f)))
                        (begin (hashtable-set! seen rest #t)
                               (loop (cdr rest) (append found (walk (car rest)))))
                        found)))))))

;; layouts-library : (U (List 'library Library-Form) Failure)
;; The one datum in layouts.sls, a library form. Any other datum beside it
;; fails here, as (data-count N), so every form Chez could load from the
;; file is one this suite reads.
(define layouts-library
  (guard (e (#t (list 'raised (describe e))))
    (let ((found (read-data layouts-source)))
      (cond ((not (eq? (car found) 'data)) found)
            ((not (= (length (cadr found)) 1)) (list 'data-count (length (cadr found))))
            ((library-form? (car (cadr found))) (list 'library (car (cadr found))))
            (else (list 'no-library-form (car (cadr found))))))))

;; layouts-form : (U Library-Form #f)
(define layouts-form
  (and (eq? (car layouts-library) 'library) (cadr layouts-library)))

;; layouts-body : (Listof Any)
(define layouts-body (if layouts-form (cddddr layouts-form) '()))

;; layouts-read : (U (List 'read (Listof Pair)) Failure)
;; Every define-ftype in the library's body, at any depth.
(define layouts-read
  (guard (e (#t (list 'raised (describe e))))
    (if layouts-form
        (list 'read (ftype-forms-in layouts-body))
        layouts-library)))

;; ftype-forms : (Listof Pair)
(define ftype-forms
  (if (eq? (car layouts-read) 'read) (cadr layouts-read) '()))

;; body-ftype? : Any -> Boolean
;; Whether FORM, a body form, is headed by define-ftype.
(define (body-ftype? form)
  (and (pair? form) (eq? (car form) 'define-ftype)))

;; or-no-library : (-> Any) -> Any
;; THUNK's answer when layouts.sls was read as one library form; else what
;; stopped the read, so a test of its shape cannot pass on nothing.
(define (or-no-library thunk)
  (if layouts-form (thunk) (list 'no-library layouts-library)))

;; body-ftype-names : (Listof Symbol)
;; The names the body's define-ftype forms define: the exports layouts.sls
;; must have, exactly. A form whose name is no symbol fails its shape test.
(define body-ftype-names
  (filter symbol? (map (lambda (form) (if (pair? (cdr form)) (cadr form) form))
                       (filter body-ftype? layouts-body))))

;; occurrences : Any -> Natural
;; How often the symbol define-ftype occurs in X, through pairs and
;; vectors: quote, quasiquote and syntax are lists, so quoted ones count.
;; A shared pair or vector is walked once, so a cyclic datum ends.
(define (occurrences x)
  (let ((seen (make-eq-hashtable)))
    (let walk ((x x))
      (cond ((eq? x 'define-ftype) 1)
            ((not (or (pair? x) (vector? x))) 0)
            ((hashtable-ref seen x #f) 0)
            (else (hashtable-set! seen x #t)
                  (if (pair? x)
                      (+ (walk (car x)) (walk (cdr x)))
                      (apply + (map walk (vector->list x)))))))))

;; chez-only? : Any -> Boolean
;; Whether SPEC is (only (chezscheme) name ...), unwrapped.
(define (chez-only? spec)
  (and (list? spec) (>= (length spec) 2) (eq? (car spec) 'only)
       (equal? (cadr spec) '(chezscheme))))

;; ftype-strays : (Listof Any)
;; Each part of layouts.sls's library form that holds define-ftype where it
;; does not belong: its name, its export clause, an import spec that is not
;; (only (chezscheme) ...), a body form not headed by define-ftype, or one
;; headed by it that holds it again. Its import and its body forms' heads
;; are the only places it belongs. A macro could carry it anywhere else, or
;; datum->syntax make it from a quoted symbol.
(define ftype-strays
  (if layouts-form
      (map car
           (filter
            (lambda (part) (> (occurrences (cdr part)) 0))
            (append
             (list (cons (cadr layouts-form) (cadr layouts-form))
                   (cons (caddr layouts-form) (caddr layouts-form)))
             (map (lambda (spec) (cons spec spec))
                  (remp chez-only? (cdr (cadddr layouts-form))))
             (map (lambda (form) (cons form (if (body-ftype? form) (cdr form) form)))
                  layouts-body))))
      '()))

;; --- tests/check-seam.sps, read as data ---------------------------------------

;; seam-ftype-entry : Any
;; library-only-chez-names' entry for define-ftype in tests/check-seam.sps,
;; read as data: (define-ftype LIBRARY ...), the libraries rule (f) lets
;; import it. Else what stopped the read: how many definitions of the list
;; there are when not one, a value that is no quoted list, or the entries
;; for define-ftype when there is not one.
(define seam-ftype-entry
  (guard (e (#t (list 'raised (describe e))))
    (let ((found (read-data check-seam-source)))
      (if (not (eq? (car found) 'data))
          found
          (let ((defs (filter (lambda (d)
                                (and (list? d) (= (length d) 3) (eq? (car d) 'define)
                                     (eq? (cadr d) 'library-only-chez-names)))
                              (cadr found))))
            (if (not (= (length defs) 1))
                (list 'definitions (length defs))
                (let ((value (caddr (car defs))))
                  (if (not (and (list? value) (= (length value) 2) (eq? (car value) 'quote)
                                (list? (cadr value))))
                      (list 'not-a-quoted-list value)
                      (let ((entries (filter (lambda (entry)
                                               (and (pair? entry) (eq? (car entry) 'define-ftype)))
                                             (cadr value))))
                        (if (= (length entries) 1) (car entries) (list 'entries entries)))))))))))

;; ftype-name : Pair -> Any
;; The name FORM defines: its second element when that is a symbol, else
;; the form itself, which no row names.
(define (ftype-name form)
  (if (and (pair? (cdr form)) (symbol? (cadr form))) (cadr form) form))

;; primitive? : Any -> Boolean
;; A type foreign-sizeof knows: int, uptr, ... and not an ftype's name.
(define (primitive? type)
  (and (symbol? type)
       (guard (e (#t #f)) (foreign-sizeof type) #t)))

;; ftype-shape : Pair -> (U (List 'struct (Listof (List Symbol Symbol)))
;;                          (List 'unhandled Any) (List 'no-kind Any))
;; FORM's fields, when it is (define-ftype NAME (struct (FIELD TYPE) ...)),
;; with at least one field and each TYPE primitive and in field-kinds; else
;; the part of it this suite does not handle, or the first field whose type
;; field-kinds lacks.
(define (ftype-shape form)
  (cond
    ((not (and (list? form) (= (length form) 3) (symbol? (cadr form))))
     (list 'unhandled form))
    ((not (let ((type (caddr form)))
            (and (list? type) (>= (length type) 2) (eq? (car type) 'struct))))
     (list 'unhandled (caddr form)))
    ((find (lambda (field)
             (not (and (list? field) (= (length field) 2) (symbol? (car field))
                       (primitive? (cadr field)))))
           (cdr (caddr form)))
     => (lambda (field) (list 'unhandled field)))
    ((find (lambda (field) (not (assq (cadr field) field-kinds)))
           (cdr (caddr form)))
     => (lambda (field) (list 'no-kind field)))
    (else (list 'struct (cdr (caddr form))))))

(define layouts-environment
  (guard (e (#t (list 'no-environment (describe e))))
    (environment '(chezscheme) '(curl private layouts))))

;; scheme-layout : Symbol Symbol Symbol -> (U (List 'offset Natural 'size Natural) (List 'no-value String))
;; FIELD's offset in FTYPE, from a pointer at address 0, and the size of
;; its TYPE.
(define (scheme-layout ftype field type)
  (guard (e (#t (list 'no-value (describe e))))
    (list 'offset
          (eval `(ftype-pointer-address
                  (ftype-&ref ,ftype (,field) (make-ftype-pointer ,ftype 0)))
                layouts-environment)
          'size
          (foreign-sizeof type))))

;; --- the checks -------------------------------------------------------------------

;; A check is (ROW NAME QUESTION ACTUAL TYPE): the table row it checks, the
;; test's name, what the C program is asked, the Scheme side's answer, and
;; for a field its Chez type (#f for a constant). A question is
;; (constant C-EXPRESSION) or (member C-TYPE C-MEMBER).

;; constant-checks : Row -> (Listof Check)
(define (constant-checks row)
  (let ((name (car row)) (c (cdr row)))
    (cond
      ((string? c)
       (list (list name (string-append (symbol->string name) " is " c)
                   (list 'constant c)
                   (constant-value name)
                   #f)))
      ((and (list? c) (= (length c) 2) (eq? (car c) 'each) (string? (cadr c)))
       (let ((entries (constant-value name)))
         (if (entries? entries)
             (map (lambda (entry)
                    (let ((c-name (string-append
                                   (cadr c)
                                   (underscored (string-upcase (symbol->string (car entry)))))))
                      (list name
                            (string-append (symbol->string name) ": "
                                           (symbol->string (car entry)) " is " c-name)
                            (list 'constant c-name)
                            (cdr entry)
                            #f)))
                  entries)
             '())))
      (else '()))))

;; scheme-size : Symbol -> (U Natural (List 'no-value String))
;; FTYPE's ftype-sizeof.
(define (scheme-size ftype)
  (guard (e (#t (list 'no-value (describe e))))
    (eval `(ftype-sizeof ,ftype) layouts-environment)))

;; layout-checks : Pair -> (Listof Check)
;; Every field's, when FORM is a struct this suite handles and a row names
;; its C type; then, for a row whose extent is whole, the struct's size.
(define (layout-checks form)
  (let ((shape (ftype-shape form))
        (row (assq (ftype-name form) layout-rows)))
    (if (and (eq? (car shape) 'struct) row (list? row) (= (length row) 3))
        (append
         (map (lambda (field)
                (let ((c-type (cadr row))
                      (c-member (underscored (symbol->string (car field)))))
                  (list (car row)
                        (string-append c-type "." c-member
                                       " has the header's offset, size and kind")
                        (list 'member c-type c-member)
                        (scheme-layout (car row) (car field) (cadr field))
                        (cadr field))))
              (cadr shape))
         (if (eq? (caddr row) 'whole)
             (list (list (car row)
                         (string-append (symbol->string (car row)) " is the whole of "
                                        (cadr row) ": its ftype-sizeof is sizeof("
                                        (cadr row) ")")
                         (list 'sizeof (cadr row))
                         (scheme-size (car row))
                         #f))
             '()))
        '())))

;; checks : (U (Listof Check) (List 'raised String))
(define checks
  (guard (e (#t (list 'raised (describe e))))
    (append (apply append (map constant-checks constant-rows))
            (apply append (map layout-checks ftype-forms)))))

(define check-list (if (and (pair? checks) (eq? (car checks) 'raised)) '() checks))

;; questions : (Listof Question)
;; The headers' own version first, (header-version), then each check's.
(define questions (cons '(header-version) (map caddr check-list)))

;; --- the C program ----------------------------------------------------------------

;; c-line : Question -> String
;; A gated constant is read only under #if, from headers at or above its
;; gate; below it, the program answers (unchecked NAME).
(define (c-line question)
  (case (car question)
    ((header-version) "  HEADER_VERSION();\n")
    ((constant)
     (let ((gate (gate-of (cadr question))))
       (if gate
           (string-append "#if LIBCURL_VERSION_NUM >= " (hex (caddr gate)) "\n"
                          "  CONSTANT(" (cadr question) ");\n"
                          "#else\n"
                          "  UNCHECKED(" (cadr question) ");\n"
                          "#endif\n")
           (string-append "  CONSTANT(" (cadr question) ");\n"))))
    ((sizeof) (string-append "  SIZEOF(" (cadr question) ");\n"))
    (else (string-append "  MEMBER(" (cadr question) ", " (caddr question) ");\n"))))

;; c-program : (Listof Question) -> String
;; curl/curl.h comes first, so headers that are missing are named there.
;; #e and #m are not macro-expanded, so each answer carries the name asked.
;; KIND is C11's _Generic on the member, which it does not evaluate. Its
;; operand is converted as an rvalue: qualifiers drop, an array decays to a
;; pointer, and an enum matches its compatible integer type.
(define (c-program questions)
  (string-append
   "#include <curl/curl.h>\n"
   "#include <stddef.h>\n"
   "#include <stdio.h>\n"
   "\n"
   "#define KIND(x) _Generic((x), \\\n"
   "  _Bool: \"integer\", char: \"integer\", \\\n"
   "  signed char: \"integer\", unsigned char: \"integer\", \\\n"
   "  short: \"integer\", unsigned short: \"integer\", \\\n"
   "  int: \"integer\", unsigned int: \"integer\", \\\n"
   "  long: \"integer\", unsigned long: \"integer\", \\\n"
   "  long long: \"integer\", unsigned long long: \"integer\", \\\n"
   "  float: \"floating\", double: \"floating\", long double: \"floating\", \\\n"
   "  default: \"other\")\n"
   "#define HEADER_VERSION() \\\n"
   "  printf(\"(header-version %lld)\\n\", (long long)LIBCURL_VERSION_NUM)\n"
   "#define CONSTANT(e) printf(\"(constant \\\"%s\\\" %lld)\\n\", #e, (long long)(e))\n"
   "#define UNCHECKED(e) printf(\"(unchecked \\\"%s\\\")\\n\", #e)\n"
   "#define SIZEOF(t) printf(\"(sizeof \\\"%s\\\" %lld)\\n\", #t, (long long)sizeof(t))\n"
   "#define MEMBER(t, m) printf(\"(member \\\"%s\\\" \\\"%s\\\" %lld %lld %s)\\n\", #t, #m, \\\n"
   "  (long long)offsetof(t, m), (long long)sizeof(((t *)0)->m), KIND(((t *)0)->m))\n"
   "\n"
   "int main(void)\n"
   "{\n"
   (apply string-append (map c-line questions))
   "  return 0;\n"
   "}\n"))

;; answer? : Any -> Boolean
;; (header-version N), (constant NAME VALUE), (unchecked NAME), (sizeof
;; TYPE N) or (member TYPE MEMBER OFFSET SIZE KIND).
(define (answer? d)
  (and (list? d)
       (or (and (= (length d) 2) (eq? (car d) 'header-version) (natural? (cadr d)))
           (and (= (length d) 2) (eq? (car d) 'unchecked) (string? (cadr d)))
           (and (= (length d) 3) (eq? (car d) 'sizeof) (string? (cadr d))
                (natural? (caddr d)))
           (and (= (length d) 3) (eq? (car d) 'constant) (string? (cadr d))
                (integer? (caddr d)) (exact? (caddr d)))
           (and (= (length d) 6) (eq? (car d) 'member) (string? (cadr d))
                (string? (caddr d)) (natural? (cadddr d)) (natural? (car (cddddr d)))
                (memq (cadr (cddddr d)) kinds) #t))))

;; read-all : String -> (U (Listof Any) #f)
(define (read-all text)
  (guard (e (#t #f))
    (let ((port (open-string-input-port text)))
      (let loop ((data '()))
        (let ((datum (read port)))
          (if (eof-object? datum) (reverse data) (loop (cons datum data))))))))

(define (write-text path text)
  (call-with-port (open-file-output-port path (file-options) (buffer-mode block)
                                         (make-transcoder (utf-8-codec)))
    (lambda (port) (put-string port text))))

;; header-answers : (Listof Question)
;;                  -> (U (List 'answers (Listof Answer)) (Pairof Symbol Any))
;; Compiles and runs the program for QUESTIONS in a fresh directory, and
;; answers what it printed. Anything else names the step that went wrong:
;; compile or run (with the command's status, stdout and stderr), output
;; (what it printed, which is not answers), or raised.
(define (header-answers questions)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (let ((source (string-append dir "/headers.c"))
             (program (string-append dir "/headers")))
         (write-text source (c-program questions))
         (let ((compiled (capture-command
                          (append (c-compiler getenv) (list "-o" program source)))))
           (if (not (= (car compiled) 0))
               (cons 'compile compiled)
               (let ((ran (capture-command (list program))))
                 (if (not (= (car ran) 0))
                     (cons 'run ran)
                     (let ((data (read-all (cadr ran))))
                       (if (and data (for-all answer? data))
                           (list 'answers data)
                           (list 'output (cadr ran)))))))))))))

(define oracle (header-answers questions))

(define answers (if (eq? (car oracle) 'answers) (cadr oracle) '()))

;; answer-question : Answer -> Question
;; (unchecked NAME) answers (constant NAME): the headers are older than
;; its gate.
(define (answer-question a)
  (case (car a)
    ((header-version) (list (car a)))
    ((constant sizeof) (list (car a) (cadr a)))
    ((unchecked) (list 'constant (cadr a)))
    (else (list (car a) (cadr a) (caddr a)))))

;; header-answer : Question -> (U Answer #f)
(define (header-answer question)
  (find (lambda (a) (equal? (answer-question a) question)) answers))

;; header-value : Question -> Any
;; The program's answer: a constant's value, a struct's size, or
;; (offset N size N kind K); (unchecked NAME) itself, which equals no
;; value; else (no-answer . QUESTION).
(define (header-value question)
  (let ((a (header-answer question)))
    (cond ((not a) (cons 'no-answer question))
          ((eq? (car a) 'unchecked) a)
          ((memq (car a) '(constant sizeof)) (caddr a))
          (else (list 'offset (cadddr a) 'size (car (cddddr a))
                      'kind (cadr (cddddr a)))))))

;; scheme-value : Check -> Any
;; The Scheme side, in the form header-value answers. A field's is
;; (offset N size N kind K), K being the kind the header answered when the
;; field's type may lay it out; else (TYPE may-be KINDS), the kinds it may.
(define (scheme-value check)
  (let ((question (caddr check)) (actual (cadddr check)) (type (car (cddddr check))))
    (if (and (eq? (car question) 'member) (pair? actual) (eq? (car actual) 'offset))
        (let ((may-be (cond ((assq type field-kinds) => cdr) (else '())))
              (a (header-answer question)))
          (append actual
                  (list 'kind
                        (if (and a (memq (cadr (cddddr a)) may-be))
                            (cadr (cddddr a))
                            (list type 'may-be may-be)))))
        actual)))

;; checked-rows : (Listof Symbol)
;; The rows the checks cover, each once.
(define checked-rows
  (fold-left (lambda (found check)
               (if (memq (car check) found) found (append found (list (car check)))))
             '() check-list))

;; --- the versions -------------------------------------------------------------------

;; header-version : (U (List 'version Natural) (List 'no-header-version Symbol))
;; LIBCURL_VERSION_NUM of the headers the program compiled against; else
;; the step the program stopped at (answers: it ran, but did not say).
(define header-version
  (let ((a (header-answer '(header-version))))
    (if a (list 'version (cadr a)) (list 'no-header-version (car oracle)))))

;; library-version : (U (List 'version Natural) (List 'refused Symbol Any)
;;                      (List 'raised String) (List 'not-a-version Any))
;; version_num of the libcurl chez-curl itself loads: (curl)'s
;; loaded-libcurl, run here, in this process. A refusal is named by its
;; reason and path, never raised. (curl private native) loads libcurl in its
;; library body, and a guard in a program catches a raise from there only
;; through eval (AGENTS.md).
(define library-version
  (guard (e ((curl-library-unavailable? e)
             (list 'refused (curl-library-unavailable-reason e)
                   (curl-library-unavailable-path e)))
            (#t (list 'raised (describe e))))
    (let ((n (eval '(libcurl-info-version-number (loaded-libcurl)) (environment '(curl)))))
      (if (natural? n) (list 'version n) (list 'not-a-version n)))))

;; version-verdict : Natural Natural -> (U 'no-newer (List 'headers String 'newer-than 'library String))
;; Whether headers at HEADERS are no newer than a library at LIBRARY, both
;; LIBCURL_VERSION_NUM; else both numbers, in hex.
(define (version-verdict headers library)
  (if (<= headers library)
      'no-newer
      (list 'headers (hex headers) 'newer-than 'library (hex library))))

;; headers-against-library : (U 'no-newer Any)
;; version-verdict of the two versions; else what each side answered, a
;; version in hex.
(define headers-against-library
  (let ((shown (lambda (v) (if (eq? (car v) 'version) (hex (cadr v)) v))))
    (if (and (eq? (car header-version) 'version) (eq? (car library-version) 'version))
        (version-verdict (cadr header-version) (cadr library-version))
        (list 'headers (shown header-version) 'library (shown library-version)))))

;; --- the gates, against the headers ------------------------------------------------

;; shown-version : Any -> Any
;; A (version N) as N in hex; anything else as it is.
(define (shown-version v)
  (if (and (pair? v) (eq? (car v) 'version) (pair? (cdr v)) (natural? (cadr v)))
      (hex (cadr v))
      v))

;; below-gate? : GatedRow -> Boolean
;; Whether the headers the C program compiled against are older than
;; GATED's gate: never when their version is unknown, so the value check
;; stands, and fails, there.
(define (below-gate? gated)
  (and (eq? (car header-version) 'version) (< (cadr header-version) (caddr gated))))

;; probe-program : String -> String
;; A file that compiles exactly when the headers declare C-NAME.
(define (probe-program c-name)
  (string-append "#include <curl/curl.h>\n\nint probe = " c-name ";\n"))

;; probe : String -> (U 'declared 'undeclared (List 'raised String))
;; Whether PROBE-PROGRAM of C-NAME compiles, with $CC -c and no link, in a
;; fresh directory: judged by its exit status alone, since Guix's gcc warns
;; on stderr.
(define (probe c-name)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (let ((source (string-append dir "/probe.c")))
         (write-text source (probe-program c-name))
         (let ((compiled (capture-command
                          (append (c-compiler getenv)
                                  (list "-c" "-o" (string-append dir "/probe.o") source)))))
           (if (= (car compiled) 0) 'declared 'undeclared)))))))

;; The probe's controls, written out: CURLMOPT_MAX_TOTAL_CONNECTIONS, since
;; 7.30.0, below the floor, every supported header declares; no header
;; declares CURLMOPT_NO_SUCH_OPTION. The probe's answer counts only when the
;; first compiles and the second does not, so a probe that fails for
;; another reason never passes as undeclared, nor one that ignores its name
;; as declared.
(define probe-present-control "CURLMOPT_MAX_TOTAL_CONNECTIONS")
(define probe-absent-control "CURLMOPT_NO_SUCH_OPTION")

(define probe-controls
  (let* ((present (probe probe-present-control))
         (absent (probe probe-absent-control)))
    (list present absent)))

;; presence : String -> (U 'declared 'undeclared (List 'controls Any))
(define (presence c-name)
  (if (equal? probe-controls '(declared undeclared))
      (probe c-name)
      (list 'controls probe-controls)))

;; presences : (Listof (Pairof String Any))
;; Each gated constant's C name, with its presence in the headers.
(define presences
  (fold-left (lambda (found entry)
               (append found (list (cons (car entry) (presence (car entry))))))
             '() c-name-gates))

;; --- curlot-types, complete ---------------------------------------------------------

;; c-identifiers : String String -> (Listof String)
;; Each distinct identifier in TEXT that starts with PREFIX, in the order
;; first met: a C identifier is letters, digits and _.
(define (c-identifiers text prefix)
  (let ((n (string-length text)) (m (string-length prefix)))
    (define (ident-char? c) (or (char-alphabetic? c) (char-numeric? c) (char=? c #\_)))
    (let loop ((i 0) (found '()))
      (cond
        ((>= i n) (reverse found))
        ((and (or (= i 0) (not (ident-char? (string-ref text (- i 1)))))
              (<= (+ i m) n)
              (string=? (substring text i (+ i m)) prefix))
         (let scan ((j (+ i m)))
           (if (and (< j n) (ident-char? (string-ref text j)))
               (scan (+ j 1))
               (let ((word (substring text i j)))
                 (loop j (if (member word found) found (cons word found)))))))
        (else (loop (+ i 1) found))))))

;; preprocessed : (U (List 'text String) (Pairof Symbol Any))
;; $CC -E of a file that includes curl/curl.h, which includes
;; curl/options.h, and string.h: the headers as the compiler reads them,
;; comments and macros gone, so CURLOT_FLAG_ALIAS, a macro, is not there.
;; The curlot check and the spelling check both read it.
(define preprocessed
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (let ((source (string-append dir "/options.c")))
         (write-text source "#include <curl/curl.h>\n#include <string.h>\n")
         (let ((ran (capture-command (append (c-compiler getenv) (list "-E" source)))))
           (if (= (car ran) 0)
               (list 'text (cadr ran))
               (cons 'preprocess ran))))))))

;; curlot-names-in-headers : (U (Listof String) (List 'no-text Any))
(define curlot-names-in-headers
  (if (eq? (car preprocessed) 'text)
      (c-identifiers (cadr preprocessed) "CURLOT_")
      (list 'no-text preprocessed)))

;; curlot-names-in-scheme : (Listof String)
;; curlot-types' names as C writes them: CURLOT_, then the name upcased, -
;; as _. Not a list of entries: (malformed VALUE), which no header holds.
(define curlot-names-in-scheme
  (let ((value (constant-value 'curlot-types)))
    (if (entries? value)
        (map (lambda (entry)
               (string-append "CURLOT_" (underscored (string-upcase (symbol->string (car entry))))))
             value)
        (list 'malformed value))))

;; --- prototypes -------------------------------------------------------------------------

;; prototype-rows : (Listof (Pairof String (Listof Declaration)))
;; One row per entry point src/ binds: its C name, then the declarations
;; of it the headers may hold, in the headers' own spelling. A Declaration
;; is (RESULT (PARAMETER ...)), or (RESULT (PARAMETER ... "...")
;; (variadic CHEZ-TYPE ...)) for a variadic entry, naming the Chez types a
;; binding may pass after its named parameters, one of them; or, for
;; curl_formadd, (variadic-run CHEZ-TYPE ...), the one run of Chez types its
;; binding passes there, a form of one field: two options, each an int,
;; each with a string, then CURLFORM_END. Most entries have one
;; declaration. curl_url_get has two: 7.85.0's curl/urlapi.h takes a
;; CURLU *, and 8.x's a const CURLU *, and the floor lane compiles against
;; the first. Every row's declarations are checked against the headers,
;; by the C program, and every binding's types against them, by
;; c-type-map.
(define prototype-rows
  '(("curl_version_info" ("curl_version_info_data *" ("CURLversion")))
    ("curl_global_init" ("CURLcode" ("long")))
    ("curl_easy_option_by_name" ("const struct curl_easyoption *" ("const char *")))
    ("curl_easy_init" ("CURL *" ()))
    ("curl_easy_header"
     ("CURLHcode" ("CURL *" "const char *" "size_t" "unsigned int" "int" "struct curl_header **")))
    ("curl_easy_cleanup" ("void" ("CURL *")))
    ("curl_easy_setopt" ("CURLcode" ("CURL *" "CURLoption" "...") (variadic long integer-64 uptr)))
    ("curl_easy_getinfo" ("CURLcode" ("CURL *" "CURLINFO" "...") (variadic uptr)))
    ("curl_multi_setopt" ("CURLMcode" ("CURLM *" "CURLMoption" "...") (variadic long)))
    ("curl_url" ("CURLU *" ()))
    ("curl_url_cleanup" ("void" ("CURLU *")))
    ("curl_url_set" ("CURLUcode" ("CURLU *" "CURLUPart" "const char *" "unsigned int")))
    ("curl_url_get"
     ("CURLUcode" ("CURLU *" "CURLUPart" "char **" "unsigned int"))
     ("CURLUcode" ("const CURLU *" "CURLUPart" "char **" "unsigned int")))
    ("curl_url_strerror" ("const char *" ("CURLUcode")))
    ("curl_free" ("void" ("void *")))
    ("curl_easy_strerror" ("const char *" ("CURLcode")))
    ("curl_easy_nextheader"
     ("struct curl_header *" ("CURL *" "unsigned int" "int" "struct curl_header *")))
    ("curl_slist_append" ("struct curl_slist *" ("struct curl_slist *" "const char *")))
    ("curl_slist_free_all" ("void" ("struct curl_slist *")))
    ("curl_multi_init" ("CURLM *" ()))
    ("curl_multi_cleanup" ("CURLMcode" ("CURLM *")))
    ("curl_multi_add_handle" ("CURLMcode" ("CURLM *" "CURL *")))
    ("curl_multi_remove_handle" ("CURLMcode" ("CURLM *" "CURL *")))
    ("curl_multi_perform" ("CURLMcode" ("CURLM *" "int *")))
    ("curl_multi_poll"
     ("CURLMcode" ("CURLM *" "struct curl_waitfd []" "unsigned int" "int" "int *")))
    ("curl_multi_wakeup" ("CURLMcode" ("CURLM *")))
    ("curl_multi_info_read" ("CURLMsg *" ("CURLM *" "int *")))
    ("curl_multi_strerror" ("const char *" ("CURLMcode")))
    ("curl_easy_pause" ("CURLcode" ("CURL *" "int")))
    ("curl_share_init" ("CURLSH *" ()))
    ("curl_share_cleanup" ("CURLSHcode" ("CURLSH *")))
    ("curl_share_setopt" ("CURLSHcode" ("CURLSH *" "CURLSHoption" "...") (variadic int)))
    ("curl_mime_init" ("curl_mime *" ("CURL *")))
    ("curl_mime_free" ("void" ("curl_mime *")))
    ("curl_mime_addpart" ("curl_mimepart *" ("curl_mime *")))
    ("curl_mime_name" ("CURLcode" ("curl_mimepart *" "const char *")))
    ("curl_mime_data" ("CURLcode" ("curl_mimepart *" "const char *" "size_t")))
    ("curl_mime_filedata" ("CURLcode" ("curl_mimepart *" "const char *")))
    ("curl_mime_filename" ("CURLcode" ("curl_mimepart *" "const char *")))
    ("curl_mime_type" ("CURLcode" ("curl_mimepart *" "const char *")))
    ("curl_formadd" ("CURLFORMcode" ("struct curl_httppost **" "struct curl_httppost **" "...")
                     (variadic-run int uptr int uptr int)))
    ("curl_formfree" ("void" ("struct curl_httppost *")))
    ("memcpy" ("void *" ("void *" "const void *" "size_t")))
    ("strlen" ("size_t" ("const char *")))))

;; callable-rows : (Listof (List Symbol String Declaration))
;; One row per callable src/ defines: the name it is defined as, the typedef
;; of the function pointer libcurl calls it through, and that typedef's
;; declaration, in the header's own spelling, as a prototype row gives one.
;; The C side asserts the typedef is that function pointer type, with the
;; same _Static_assert(_Generic(...)) as an entry's; the Scheme side holds
;; the callable's Chez types to it through c-type-map, as a binding's.
(define callable-rows
  '((write-body "curl_write_callback" ("size_t" ("char *" "size_t" "size_t" "void *")))
    (read-head "curl_write_callback" ("size_t" ("char *" "size_t" "size_t" "void *")))
    (read-body "curl_read_callback" ("size_t" ("char *" "size_t" "size_t" "void *")))
    (seek-body "curl_seek_callback" ("int" ("void *" "curl_off_t" "int")))
    (prereq-body "curl_prereq_callback" ("int" ("void *" "char *" "char *" "int" "int")))))

;; c-type-map : (Listof (Pairof String (Listof Symbol)))
;; The one fixed map from a C type, as a header spells it, to the Chez types
;; a binding may write for it. An enum is int, never unsigned-int: gcc and
;; clang take an enum's compatible type to be unsigned int, so the C side
;; would pass a row that wrote one so; the rows must spell each enum as the
;; header does, which the spelling check holds. A pointer, any type ending
;; in *, is uptr or void*; (* F) only where F's layout-rows C type, then
;; " *", is that pointer type; and u8* only on the checked copies' row,
;; memcpy's (bytevector-rows). A const char * may also be Chez's string,
;; which hands C a NUL-terminated copy: test-collect-safe holds each such
;; binding to a string-not-kept mark. curl_off_t is 64 bits on every platform
;; chez-curl supports. A C type in no entry here, and no pointer, fails its
;; row by name.
(define c-type-map
  '(("void" void)
    ("int" int)
    ("unsigned int" unsigned-int)
    ("long" long)
    ("size_t" size_t)
    ("curl_off_t" integer-64)
    ("CURLcode" int)
    ("CURLversion" int)
    ("CURLoption" int)
    ("CURLINFO" int)
    ("CURLHcode" int)
    ("CURLUcode" int)
    ("CURLUPart" int)
    ("CURLMcode" int)
    ("CURLMoption" int)
    ("CURLSHcode" int)
    ("CURLSHoption" int)
    ("CURLFORMcode" int)))

;; bytevector-rows : (Listof String)
;; The rows whose pointers may be bound u8*: the checked copies' memcpy.
(define bytevector-rows '("memcpy"))

;; pointer-type? : String -> Boolean
;; A type ending in *, or an array parameter's, ending in [], which C
;; adjusts to a pointer: curl_multi_poll's struct curl_waitfd extra_fds[].
(define (pointer-type? c-type)
  (let ((n (string-length c-type)))
    (and (> n 0)
         (or (char=? (string-ref c-type (- n 1)) #\*)
             (and (>= n 2) (string=? (substring c-type (- n 2) n) "[]"))))))

;; ftype-pointer-fits? : Any String -> Boolean
;; Whether CHEZ is (* F) for an F whose layout-rows C type, then " *", is
;; C-TYPE: (* curl-version-info-data) for curl_version_info_data *, and for
;; no other pointer.
(define (ftype-pointer-fits? chez c-type)
  (and (list? chez) (= (length chez) 2) (eq? (car chez) '*)
       (let ((row (assq (cadr chez) layout-rows)))
         (and row (pair? (cdr row)) (string? (cadr row))
              (string=? (string-append (cadr row) " *") c-type)))))

;; chez-fits? : String Any String -> Boolean
;; Whether the Chez type CHEZ may stand for the C type C-TYPE in the row
;; for ENTRY.
(define (chez-fits? entry chez c-type)
  (cond ((pointer-type? c-type)
         (or (and (memq chez '(uptr void*)) #t)
             (and (eq? chez 'u8*) (member entry bytevector-rows) #t)
             (and (eq? chez 'string) (string=? c-type "const char *"))
             (ftype-pointer-fits? chez c-type)))
        ((assoc c-type c-type-map) => (lambda (entry) (and (memq chez (cdr entry)) #t)))
        (else #f)))

;; declaration-fits? : String Declaration (Listof Any) Any -> Boolean
;; Whether a binding of ENTRY with PARAMETERS and RESULT fits DECLARATION:
;; its result, and each named parameter, by chez-fits?; for a variadic
;; declaration, exactly one more parameter, one of the Chez types it names,
;; or, for a variadic-run, exactly the run it names.
(define (declaration-fits? entry declaration parameters result)
  (let* ((c-result (car declaration))
         (c-params (cadr declaration))
         (variadic? (and (pair? c-params) (equal? (list-ref c-params (- (length c-params) 1)) "...")))
         (named (if variadic? (reverse (cdr (reverse c-params))) c-params))
         (run? (and (= (length declaration) 3) (eq? (car (caddr declaration)) 'variadic-run)))
         (extra (if (= (length declaration) 3) (cdr (caddr declaration)) '()))
         (tail (cond ((not variadic?) 0) (run? (length extra)) (else 1))))
    (and (list? parameters)
         (chez-fits? entry result c-result)
         (= (length parameters) (+ (length named) tail))
         (for-all (lambda (chez c-type) (chez-fits? entry chez c-type))
                  (list-head parameters (length named))
                  named)
         (or (not variadic?)
             (if run?
                 (equal? (list-tail parameters (length named)) extra)
                 (and (memq (list-ref parameters (- (length parameters) 1)) extra) #t))))))

;; declaration-shaped? : Any -> Boolean
(define (declaration-shaped? d)
  (and (list? d)
       (memv (length d) '(2 3))
       (string? (car d))
       (list? (cadr d))
       (for-all string? (cadr d))
       (let* ((ps (cadr d))
              (variadic? (and (pair? ps) (equal? (list-ref ps (- (length ps) 1)) "..."))))
         (if variadic?
             (and (= (length d) 3)
                  (let ((v (caddr d)))
                    (and (list? v) (pair? v) (memq (car v) '(variadic variadic-run)) (pair? (cdr v))
                         (for-all symbol? (cdr v)))))
             (= (length d) 2)))
       (not (member "..." (if (pair? (cadr d)) (reverse (cdr (reverse (cadr d)))) '())))
       #t))

;; row-shaped? : Any -> Boolean
(define (prototype-row-shaped? row)
  (and (list? row) (>= (length row) 2) (string? (car row))
       (for-all declaration-shaped? (cdr row))))

;; c-function-type : Declaration -> String
;; DECLARATION as a C pointer-to-function type: RESULT (*)(PARAMETERS), void
;; for none.
(define (c-function-type declaration)
  (let ((params (cadr declaration)))
    (string-append (car declaration) " (*)("
                   (if (null? params)
                       "void"
                       (fold-left (lambda (acc p) (string-append acc ", " p)) (car params) (cdr params)))
                   ")")))

;; prototype-assertion : Row -> String
;; The C line that holds ENTRY to its row's declarations: a static
;; assertion that _Generic finds the entry's type among them. _Generic
;; does not evaluate its operand, so nothing is referenced, and the program
;; needs no -l. The entry is written in parentheses, so a function-like
;; macro of its name, such as gcc's curl_easy_setopt, is not expanded.
(define (prototype-assertion row)
  (string-append
   "_Static_assert(_Generic((" (car row) "), "
   (apply string-append (map (lambda (d) (string-append (c-function-type d) ": 1, ")) (cdr row)))
   "default: 0), \"" (car row) ": the headers declare it otherwise than each declaration its row gives\");\n"))

;; callable-assertion : CallableRow -> String
;; The C line that holds a callable's typedef to its row's declaration: the
;; same static assertion, on a null pointer of the typedef's type, which
;; _Generic does not evaluate.
(define (callable-assertion row)
  (string-append
   "_Static_assert(_Generic(((" (cadr row) ")0), " (c-function-type (caddr row)) ": 1, "
   "default: 0), \"" (symbol->string (car row)) ": the headers declare " (cadr row)
   " otherwise than its row gives\");\n"))

;; prototype-program : (Listof Row) (Listof CallableRow) -> String
(define (prototype-program rows callables)
  (string-append
   "#include <curl/curl.h>\n"
   "#include <string.h>\n"
   "\n"
   (apply string-append (map prototype-assertion rows))
   (apply string-append (map callable-assertion callables))))

;; compile-prototypes : (Listof Row) [(Listof CallableRow)] -> (U 'compiled (Pairof Symbol Any))
;; Compiles PROTOTYPE-PROGRAM of ROWS and CALLABLES, none by default, with
;; $CC -c, in a fresh directory: compiled, or (compile STATUS STDOUT
;; STDERR), or (raised TEXT).
(define (compile-prototypes rows . callables)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (let ((source (string-append dir "/prototypes.c")))
         (write-text source (prototype-program rows (if (null? callables) '() (car callables))))
         (let ((compiled (capture-command
                          (append (c-compiler getenv)
                                  (list "-c" "-o" (string-append dir "/prototypes.o") source)))))
           (if (= (car compiled) 0) 'compiled (cons 'compile compiled))))))))

;; callable-row-shaped? : Any -> Boolean
;; (NAME TYPEDEF DECLARATION): a symbol, a string, and a declaration with
;; no variadic part.
(define (callable-row-shaped? row)
  (and (list? row) (= (length row) 3) (symbol? (car row)) (string? (cadr row))
       (declaration-shaped? (caddr row)) (= (length (caddr row)) 2)))

(define prototypes-compiled
  (if (and (for-all prototype-row-shaped? prototype-rows)
           (for-all callable-row-shaped? callable-rows))
      (compile-prototypes prototype-rows callable-rows)
      '(rows-malformed)))

;; signatures : (U (Listof Signature) (List 'raised String))
;; Every binding under src/, with its types, from (foreign-conventions)'
;; scan: (KEY VIA PARAMETERS RESULT FILE).
(define signatures
  (guard (e (#t (list 'raised (describe e))))
    (scan-signatures (scan-conventions "src" known-macros))))

(define signature-list
  (if (and (pair? signatures) (eq? (car signatures) 'raised)) '() signatures))

;; bound-entries : (Listof String)
;; The entries src/ binds, each once, in scan order. A callable has a
;; symbol key, and no prototype.
(define bound-entries
  (fold-left (lambda (found sig)
               (if (and (string? (car sig)) (not (member (car sig) found)))
                   (append found (list (car sig)))
                   found))
             '() signature-list))

;; bound-callables : (Listof Symbol)
;; The callables src/ defines, each once, in scan order: the signatures
;; with a symbol key.
(define bound-callables
  (fold-left (lambda (found sig)
               (if (and (symbol? (car sig)) (not (memq (car sig) found)))
                   (append found (list (car sig)))
                   found))
             '() signature-list))

;; string-sorted : (Listof String) -> (Listof String)
(define (string-sorted strings) (list-sort string<? strings))

;; --- the headers' own spelling ------------------------------------------------------------
;; The C side cannot tell an enum from unsigned int, its compatible type, so
;; a row that wrote unsigned int for CURLUPart would compile. This reads each
;; entry's declaration from the preprocessed headers, as text, and requires
;; the row to spell its result and parameters as the header does.

;; c-tokens : String -> (Listof String)
;; TEXT as C tokens: identifiers, numbers, "...", and each other character
;; that is not white space alone. A string literal is one token.
(define (c-tokens text)
  (let ((n (string-length text)))
    (define (ident-char? c) (or (char-alphabetic? c) (char-numeric? c) (char=? c #\_)))
    (let loop ((i 0) (found '()))
      (cond
        ((>= i n) (reverse found))
        ((char-whitespace? (string-ref text i)) (loop (+ i 1) found))
        ((ident-char? (string-ref text i))
         (let scan ((j i))
           (if (and (< j n) (ident-char? (string-ref text j)))
               (scan (+ j 1))
               (loop j (cons (substring text i j) found)))))
        ((and (<= (+ i 3) n) (string=? (substring text i (+ i 3)) "..."))
         (loop (+ i 3) (cons "..." found)))
        ((char=? (string-ref text i) #\")
         (let scan ((j (+ i 1)))
           (cond ((>= j n) (loop n (cons (substring text i n) found)))
                 ((char=? (string-ref text j) #\\) (scan (+ j 2)))
                 ((char=? (string-ref text j) #\") (loop (+ j 1) (cons (substring text i (+ j 1)) found)))
                 (else (scan (+ j 1))))))
        (else (loop (+ i 1) (cons (string (string-ref text i)) found)))))))

;; without-directives : String -> String
;; TEXT less the lines $CC -E writes for the preprocessor: those that start
;; with #.
(define (without-directives text)
  (call-with-string-output-port
    (lambda (p)
      (let loop ((lines (split-lines text)))
        (unless (null? lines)
          (let ((line (car lines)))
            (unless (and (> (string-length line) 0) (char=? (string-ref line 0) #\#))
              (put-string p line)
              (put-char p #\newline)))
          (loop (cdr lines)))))))

;; split-lines : String -> (Listof String)
(define (split-lines text)
  (let loop ((i 0) (start 0) (found '()))
    (cond ((= i (string-length text)) (reverse (cons (substring text start i) found)))
          ((char=? (string-ref text i) #\newline)
           (loop (+ i 1) (+ i 1) (cons (substring text start i) found)))
          (else (loop (+ i 1) start found)))))

;; balanced-end : (Listof String) -> (U (Pairof (Listof String) (Listof String)) #f)
;; TOKENS, which start with "(", cut after the ")" that closes it: the group,
;; and what follows.
(define (balanced-end tokens)
  (let loop ((rest tokens) (depth 0) (taken '()))
    (cond ((null? rest) #f)
          ((string=? (car rest) "(") (loop (cdr rest) (+ depth 1) (cons (car rest) taken)))
          ((string=? (car rest) ")")
           (if (= depth 1)
               (cons (reverse (cons (car rest) taken)) (cdr rest))
               (loop (cdr rest) (- depth 1) (cons (car rest) taken))))
          (else (loop (cdr rest) depth (cons (car rest) taken))))))

;; without-attributes : (Listof String) -> (Listof String)
;; TOKENS less each __attribute__, __attribute, __asm__ or __asm and the
;; group after it.
(define (without-attributes tokens)
  (let loop ((rest tokens) (found '()))
    (cond ((null? rest) (reverse found))
          ((and (member (car rest) '("__attribute__" "__attribute" "__asm__" "__asm"))
                (pair? (cdr rest)) (string=? (cadr rest) "(")
                (balanced-end (cdr rest)))
           => (lambda (cut) (loop (cdr cut) found)))
          (else (loop (cdr rest) (cons (car rest) found))))))

;; qualifier-noise : (Listof String)
;; Words a header's declaration may hold that name no type: storage;
;; restrict, which glibc writes as __restrict; and Clang's nullability
;; qualifiers, which Apple's SDK headers write on pointers, in both
;; spellings.
(define qualifier-noise
  '("extern" "__extension__" "__inline" "inline" "restrict" "__restrict" "__restrict__"
    "_Nonnull" "_Nullable" "_Null_unspecified" "__nonnull" "__nullable" "__null_unspecified"))

(define type-keywords
  '("void" "char" "short" "int" "long" "float" "double" "signed" "unsigned" "_Bool"
    "const" "volatile" "struct" "union" "enum"))

(define (c-identifier? token)
  (and (> (string-length token) 0)
       (let ((c (string-ref token 0))) (or (char-alphabetic? c) (char=? c #\_)))))

;; spelled : (Listof String) -> String
;; TOKENS of a type as the rows write it: words one space apart, and each
;; * after a space, or after another *: "const char *", "char **".
(define (spelled tokens)
  (let loop ((rest tokens) (previous #f) (text ""))
    (cond ((null? rest) text)
          ((string=? text "") (loop (cdr rest) (car rest) (car rest)))
          ((and (string=? (car rest) "*") previous (string=? previous "*"))
           (loop (cdr rest) (car rest) (string-append text "*")))
          (else (loop (cdr rest) (car rest) (string-append text " " (car rest)))))))

;; parameter-type : (Listof String) -> String
;; A parameter's tokens, its name dropped, spelled: the last token, when it
;; is an identifier that is no type keyword, follows another token, and
;; does not follow struct, union or enum, is the name.
(define (parameter-type tokens)
  (let* ((tokens (remp (lambda (t) (member t qualifier-noise)) tokens))
         (n (length tokens)))
    (cond
      ;; An array parameter, TYPE NAME [ ]: its name dropped, so it reads
      ;; TYPE [ ], spelled as a row writes "TYPE []".
      ((and (>= n 4)
            (string=? (list-ref tokens (- n 2)) "[")
            (string=? (list-ref tokens (- n 1)) "]")
            (c-identifier? (list-ref tokens (- n 3)))
            (not (member (list-ref tokens (- n 3)) type-keywords))
            (not (member (list-ref tokens (- n 4)) '("struct" "union" "enum"))))
       (spelled (append (list-head tokens (- n 3)) '("[" "]"))))
      (else
       (spelled
        (if (and (>= n 2)
                 (c-identifier? (list-ref tokens (- n 1)))
                 (not (member (list-ref tokens (- n 1)) type-keywords))
                 (not (member (list-ref tokens (- n 2)) '("struct" "union" "enum"))))
            (reverse (cdr (reverse tokens)))
            tokens))))))

;; split-parameters : (Listof String) -> (Listof (Listof String))
;; The tokens between a parameter list's parentheses, cut at each comma at
;; depth 0.
(define (split-parameters tokens)
  (let loop ((rest tokens) (depth 0) (current '()) (found '()))
    (cond ((null? rest) (reverse (if (null? current) found (cons (reverse current) found))))
          ((and (string=? (car rest) ",") (= depth 0))
           (loop (cdr rest) depth '() (cons (reverse current) found)))
          ((string=? (car rest) "(") (loop (cdr rest) (+ depth 1) (cons (car rest) current) found))
          ((string=? (car rest) ")") (loop (cdr rest) (- depth 1) (cons (car rest) current) found))
          (else (loop (cdr rest) depth (cons (car rest) current) found)))))

;; header-tokens : (U (Listof String) (List 'no-text Any))
;; The preprocessed headers as tokens, attributes gone.
(define header-tokens
  (if (eq? (car preprocessed) 'text)
      (without-attributes (c-tokens (without-directives (cadr preprocessed))))
      (list 'no-text preprocessed)))

;; header-tokens-read? : Boolean
;; Whether the headers gave tokens to read: none from a $CC -E that printed
;; nothing, and a failure's sentinel is no token list. Every reader below
;; asks this first, so neither kills the suite before a test is named.
(define header-tokens-read?
  (and (pair? header-tokens) (string? (car header-tokens))))

;; declaration-in : (Listof String) String -> (U (List String (Listof String)) (List 'no-declaration String))
;; NAME's first declaration in TOKENS: a statement, from after the last ;,
;; { or } before NAME, whose NAME is followed by a parameter list and then
;; ;. Its result and its parameters, spelled; () for (void).
(define (declaration-in tokens name)
  (let loop ((rest tokens) (statement '()))
    (cond
      ((null? rest) (list 'no-declaration name))
      ((member (car rest) '(";" "{" "}")) (loop (cdr rest) '()))
      ((and (string=? (car rest) name) (pair? (cdr rest)) (string=? (cadr rest) "(")
            (balanced-end (cdr rest)))
       => (lambda (cut)
            (if (and (pair? (cdr cut)) (string=? (cadr cut) ";"))
                (let* ((inner (reverse (cdr (reverse (cdr (car cut))))))
                       (parameters (map parameter-type (split-parameters inner))))
                  (list (spelled (remp (lambda (t) (member t qualifier-noise)) (reverse statement)))
                        (if (equal? parameters '("void")) '() parameters)))
                (loop (cdr rest) (cons (car rest) statement)))))
      (else (loop (cdr rest) (cons (car rest) statement))))))

;; header-declaration : String -> (U (List String (Listof String)) (List 'no-declaration String))
;; NAME's first declaration in the preprocessed headers.
(define (header-declaration name)
  (declaration-in (if header-tokens-read? header-tokens '()) name))

;; typedef-in : (Listof String) String -> (U (List String (Listof String)) (List 'no-declaration String))
;; NAME's first typedef of a function pointer in TOKENS: typedef RESULT
;; (*NAME)(PARAMETERS); its result and its parameters, spelled, as
;; declaration-in answers.
(define (typedef-in tokens name)
  (let loop ((rest tokens) (statement '()))
    (cond
      ((null? rest) (list 'no-declaration name))
      ((member (car rest) '(";" "{" "}")) (loop (cdr rest) '()))
      ((and (string=? (car rest) "(")
            (pair? (cdr rest)) (string=? (cadr rest) "*")
            (pair? (cddr rest)) (string=? (caddr rest) name)
            (pair? (cdddr rest)) (string=? (cadddr rest) ")")
            (pair? (cddddr rest)) (string=? (car (cddddr rest)) "(")
            (balanced-end (cddddr rest)))
       => (lambda (cut)
            (let ((head (reverse statement)))
              (if (and (pair? (cdr cut)) (string=? (cadr cut) ";")
                       (pair? head) (string=? (car head) "typedef"))
                  (let* ((inner (reverse (cdr (reverse (cdr (car cut))))))
                         (parameters (map parameter-type (split-parameters inner))))
                    (list (spelled (remp (lambda (t) (member t qualifier-noise)) (cdr head)))
                          (if (equal? parameters '("void")) '() parameters)))
                  (loop (cdr rest) (cons (car rest) statement))))))
      (else (loop (cdr rest) (cons (car rest) statement))))))

;; header-typedef : String -> (U (List String (Listof String)) (List 'no-declaration String))
(define (header-typedef name)
  (typedef-in (if header-tokens-read? header-tokens '()) name))

;; row-spelling : Declaration -> (List String (Listof String))
;; A row's declaration as the spelling check compares it: its result and
;; parameters, each respelled from its tokens, so spacing does not count.
(define (row-spelling declaration)
  (list (spelled (c-tokens (car declaration)))
        (map (lambda (p) (spelled (c-tokens p))) (cadr declaration))))

;; --- enums ----------------------------------------------------------------------------------

;; enum-names : (Listof String)
;; Written out: every enum a prototype row names, each a typedef the headers
;; define with typedef enum. c-type-map maps each to int, and nothing else.
(define enum-names
  '("CURLcode" "CURLversion" "CURLoption" "CURLINFO" "CURLHcode" "CURLUcode" "CURLUPart"
    "CURLMcode" "CURLMoption" "CURLSHcode" "CURLSHoption" "CURLFORMcode"))

;; enums-in : (Listof String) -> (Listof String)
;; The names TOKENS give a typedef enum: typedef enum [TAG] { ... } NAME ;
(define (enums-in tokens)
      (let loop ((rest tokens) (found '()))
        (cond
          ((null? rest) (reverse found))
          ((and (string=? (car rest) "typedef") (pair? (cdr rest)) (string=? (cadr rest) "enum"))
           (let* ((after (cddr rest))
                  (after (if (and (pair? after) (c-identifier? (car after))) (cdr after) after)))
             (if (and (pair? after) (string=? (car after) "{"))
                 (let skip ((r (cdr after)) (depth 1))
                   (cond ((null? r) (reverse found))
                         ((string=? (car r) "{") (skip (cdr r) (+ depth 1)))
                         ((string=? (car r) "}")
                          (if (= depth 1)
                              (if (and (pair? (cdr r)) (c-identifier? (cadr r)))
                                  (loop (cddr r) (cons (cadr r) found))
                                  (loop (cdr r) found))
                              (skip (cdr r) (- depth 1))))
                         (else (skip (cdr r) depth))))
                 (loop (cdr rest) found))))
          (else (loop (cdr rest) found)))))

;; header-enums : (U (Listof String) (List 'no-text Any))
;; The names the preprocessed headers give a typedef enum.
(define header-enums
  (if header-tokens-read? (enums-in header-tokens) (list 'no-tokens header-tokens)))

;; prototype-c-types : (Listof String)
;; Every C type a row writes, a callable row's among them, each once, in row
;; order, "..." aside.
(define prototype-c-types
  (fold-left (lambda (found type) (if (or (member type found) (string=? type "...")) found (append found (list type))))
             '()
             (append
              (apply append
                     (map (lambda (row)
                            (apply append (map (lambda (d) (cons (car d) (cadr d))) (cdr row))))
                          prototype-rows))
              (apply append
                     (map (lambda (row) (cons (car (caddr row)) (cadr (caddr row))))
                          callable-rows)))))

;; --- the map, against every type a binding can write --------------------------------------

;; universe : (Listof Any)
;; Every type the conventions reader reads, for src/'s layouts: what a
;; binding can write at all. Plus (* not-a-layout), an ftype layouts does
;; not define, which no row may take.
(define universe
  (append (readable-types (map car layout-rows)) '((* not-a-layout))))

;; fits : String String -> (Listof Any)
;; The types of the universe chez-fits? lets stand for C-TYPE in ENTRY's row.
(define (fits entry c-type)
  (filter (lambda (chez) (chez-fits? entry chez c-type)) universe))

(test-begin "constants")

;; --- the reads are live ------------------------------------------------------------

(test-equal "constants.sls is read: a library whose exports are identifiers, at least one"
  'read
  (if (and (eq? (car constants-read) 'read) (pair? exports)) 'read constants-read))

(test-equal "layouts.sls is read: one datum, a library with a define-ftype, at least one"
  'read
  (if (and (eq? (car layouts-read) 'read) (pair? ftype-forms)) 'read layouts-read))

;; --- layouts.sls's shape: no route to a function ftype ------------------------------
;; check-seam's rule (f) lets (curl private layouts) alone import define-ftype.
;; These hold that library to plain struct definitions, so nothing in it can
;; hand define-ftype, or a form that uses it, to anything else: no export of
;; the keyword, no macro, exported or used in place, and no quoted symbol
;; for datum->syntax to bind.

;; Widening rule (f) to another library fails here, until this suite holds
;; that library to the same shape.
(test-equal "tests/check-seam.sps's library-only-chez-names lets (curl private layouts) alone import define-ftype"
  (list 'define-ftype layouts-name)
  seam-ftype-entry)

(test-equal "layouts.sls is the library (curl private layouts), the one rule (f) names"
  layouts-name
  (or-no-library (lambda () (cadr layouts-form))))

(test-equal "layouts.sls imports exactly (curl private require-threaded), (rnrs) and (only (chezscheme) define-ftype), in order, none wrapped"
  layouts-imports
  (or-no-library (lambda () (cdr (cadddr layouts-form)))))

(test-equal "layouts.sls's body is define-ftype forms alone: no define, define-syntax, begin, macro use or other form"
  '()
  (or-no-library (lambda () (remp body-ftype? layouts-body))))

(test-equal "layouts.sls exports exactly the names its define-ftype forms define, each a plain identifier, in any order"
  (list-sort symbol-before? body-ftype-names)
  (or-no-library
   (lambda ()
     (let* ((exports (cdr (caddr layouts-form)))
            (odd (remp symbol? exports)))
       (if (null? odd) (list-sort symbol-before? exports) (list 'not-identifiers odd))))))

(test-equal "layouts.sls holds define-ftype only in its (only (chezscheme) ...) import and at its body forms' heads, quoted ones counted"
  '()
  (or-no-library (lambda () ftype-strays)))

;; --- coverage, both ways ---------------------------------------------------------------

(for-each
 (lambda (name)
   (test-equal (string-append "constants.sls exports " (symbol->string name)
                              ", and constant-rows has a row for it")
     'row
     (if (assq name constant-rows) 'row 'no-row)))
 exports)

(for-each
 (lambda (row)
   (test-equal (string-append "constant-rows' row " (symbol->string (car row))
                              " is an export of constants.sls")
     'exported
     (if (memq (car row) exports) 'exported 'not-exported)))
 constant-rows)

(for-each
 (lambda (form)
   (test-equal (string-append "layouts.sls defines the ftype " (written (ftype-name form))
                              ", and layout-rows has a row for it")
     'row
     (if (assq (ftype-name form) layout-rows) 'row 'no-row)))
 ftype-forms)

(for-each
 (lambda (row)
   (test-equal (string-append "layout-rows' row " (symbol->string (car row))
                              " is a define-ftype in layouts.sls")
     'defined
     (if (memq (car row) (map ftype-name ftype-forms)) 'defined 'not-defined)))
 layout-rows)

;; --- names ---------------------------------------------------------------------------------

;; A row's C name is not free text: (curlh-header . "CURL_VERSION_IPV6")
;; would pass every value check, both being 1. Nor is an (each PREFIX)
;; row's prefix: "0|CURL_VERSION_" makes every entry's C expression another
;; of the same value.
(for-each
 (lambda (row)
   (let ((c-name (c-name-of row))
         (aliased (guard (e (#t #f)) (assq (car row) c-name-aliases))))
     (cond
       ((string? (cdr row))
        (test-equal (string-append "constant-rows' row " (symbol->string (car row))
                                   " names " (text c-name) ", "
                                   (if aliased
                                       "its entry in c-name-aliases"
                                       "its name upcased, - as _"))
          c-name
          (cdr row)))
       ((each-row? row)
        (test-equal (string-append "constant-rows' row " (symbol->string (car row))
                                   " has the prefix " (text c-name) ", "
                                   (if aliased
                                       "its entry in c-name-aliases"
                                       "its name less its last word, upcased, - as _, then _"))
          c-name
          (cadr (cdr row)))))))
 constant-rows)

;; An alias is a permission, and one that changes nothing, or names no row,
;; or is shadowed by an earlier entry for its row, is a stale one.
(for-each
 (lambda (alias)
   (test-equal (string-append "c-name-aliases' entry " (written alias)
                              " is its row's one alias, and changes what the row's name derives")
     'changes
     (cond
       ((not (and (pair? alias) (symbol? (car alias)) (string? (cdr alias))))
        'not-a-name-and-a-string)
       ((not (assq (car alias) constant-rows)) 'no-such-row)
       ((not (eq? (assq (car alias) c-name-aliases) alias)) 'not-its-rows-first-entry)
       ((equal? (cdr alias) (derived-c-name (assq (car alias) constant-rows)))
        (list 'derived-already (cdr alias)))
       (else 'changes))))
 (if (list? c-name-aliases) c-name-aliases (list c-name-aliases)))

;; --- shapes ------------------------------------------------------------------------------

(for-each
 (lambda (row)
   (when (pair? (cdr row))
     (test-equal (string-append "constants.sls: " (symbol->string (car row))
                                " is a non-empty list of (name . value), each name a symbol")
       'entries
       (let ((value (constant-value (car row))))
         (if (entries? value) 'entries value)))))
 constant-rows)

;; A type field-kinds misspells would fail closed, but name no cause.
(test-equal "field-kinds: each type is one foreign-sizeof knows, each kind integer, floating or other"
  '()
  (filter (lambda (entry)
            (not (and (primitive? (car entry)) (pair? (cdr entry))
                      (for-all (lambda (k) (memq k kinds)) (cdr entry)))))
          field-kinds))

(for-each
 (lambda (form)
   (test-equal (string-append "layouts.sls: " (written (ftype-name form))
                              " is a struct of primitive-typed fields, each type in field-kinds")
     'handled
     (let ((shape (ftype-shape form)))
       (if (eq? (car shape) 'struct) 'handled shape))))
 ftype-forms)

;; Every row of both tables has a check. A check list emptied, or a row's
;; checks dropped, would otherwise leave nothing below to fail. The checks
;; follow layouts.sls's order, not layout-rows', so both sides are sorted.
(test-equal "every row of constant-rows and layout-rows is checked"
  (list-sort symbol-before? (append (map car constant-rows) (map car layout-rows)))
  (if (and (pair? checks) (eq? (car checks) 'raised))
      checks
      (list-sort symbol-before? checked-rows)))

;; --- the C program ------------------------------------------------------------------------

(test-equal "the C program compiled against libcurl's headers and ran"
  'ran
  (if (eq? (car oracle) 'answers) 'ran oracle))

(test-equal "the C program answered every question, in order"
  questions
  (map answer-question answers))

;; --- the headers' version, against the library's ------------------------------------------

;; The rule itself, on fixed numbers: with the real headers and library
;; at one version, a comparison turned round would still pass below.
(test-equal "the version rule: headers 0x081400 are newer than a library 0x075500, both named in hex"
  '(headers "0x081400" newer-than library "0x075500")
  (version-verdict #x081400 #x075500))

(test-equal "the version rule: headers older than the library, or the same, are no newer"
  '(no-newer no-newer)
  (list (version-verdict #x075500 #x081400) (version-verdict #x081400 #x081400)))

(test-equal "the headers the C program compiled against are no newer than the libcurl chez-curl loads"
  'no-newer
  headers-against-library)

;; --- the gates: constants newer than the floor ------------------------------------------

(test-equal "the libcurl floor is read from packaging/floors.sexp, as a LIBCURL_VERSION_NUM"
  'read
  (if (natural? libcurl-floor-num) 'read libcurl-floor-num))

;; Written out here, not read from the table: a gate moved, or a constant
;; gated, drops a value check on some lane, and only a lane whose headers
;; fall between the old gate and the new would see it.
(test-equal "gated-rows is exactly, written out here: curlmopt-quick-exit, since curl 8.20.0, 0x081400; curle-too-large, since 8.6.0, 0x080600; curle-ech-required, since 8.8.0, 0x080800"
  '((curlmopt-quick-exit "8.20.0" #x081400) (curle-too-large "8.6.0" #x080600)
    (curle-ech-required "8.8.0" #x080800))
  gated-rows)

(for-each
 (lambda (g)
   (test-equal (string-append "gated-rows' row " (gated-row-text g)
                              " is (name \"M.m.p\" N), N that release as LIBCURL_VERSION_NUM")
     'shaped
     (if (gated-row-shaped? g) 'shaped (list 'malformed g))))
 (if (list? gated-rows) gated-rows (list gated-rows)))

(for-each
 (lambda (g)
   (test-equal (string-append "gated-rows' row " (written (if (pair? g) (car g) g))
                              " is a constant-rows row that names one C constant, and its one gate")
     'gates
     (let ((row (and (pair? g) (assq (car g) constant-rows))))
       (cond ((not row) 'no-such-row)
             ((not (string? (cdr row))) (list 'not-one-constant row))
             ((not (eq? (assq (car g) gated-rows) g)) 'not-its-first-gate)
             (else 'gates)))))
 (if (list? gated-rows) gated-rows (list gated-rows)))

;; A gate at or below the floor would leave the constant unchecked against
;; headers that have it: such a row belongs among the ordinary ones.
(for-each
 (lambda (g)
   (test-equal (string-append "gated-rows' row " (written (if (pair? g) (car g) g))
                              " came after the libcurl floor: "
                              (if (gated-row-shaped? g)
                                  (string-append (cadr g) ", " (hex (caddr g)))
                                  (gated-row-text g))
                              ", is newer than packaging/floors.sexp's "
                              (if (natural? libcurl-floor-num)
                                  (hex libcurl-floor-num)
                                  (written libcurl-floor-num)))
     'newer
     (cond ((not (gated-row-shaped? g)) (list 'malformed g))
           ((not (natural? libcurl-floor-num)) (list 'no-floor libcurl-floor-num))
           ((> (caddr g) libcurl-floor-num) 'newer)
           (else (list 'not-newer (hex (caddr g)) 'floor (hex libcurl-floor-num))))))
 (if (list? gated-rows) gated-rows (list gated-rows)))

;; The generated program on fixed questions, whole: a gated constant is read
;; under #if, and answers unchecked else; an ungated one is read plainly.
(test-equal "c-line: CURLMOPT_QUICK_EXIT is read under #if LIBCURL_VERSION_NUM >= 0x081400, else answers unchecked; CURLMOPT_MAX_TOTAL_CONNECTIONS is read plainly"
  (list (string-append "#if LIBCURL_VERSION_NUM >= 0x081400\n"
                       "  CONSTANT(CURLMOPT_QUICK_EXIT);\n"
                       "#else\n"
                       "  UNCHECKED(CURLMOPT_QUICK_EXIT);\n"
                       "#endif\n")
        "  CONSTANT(CURLMOPT_MAX_TOTAL_CONNECTIONS);\n")
  (let* ((gated (c-line '(constant "CURLMOPT_QUICK_EXIT")))
         (plain (c-line '(constant "CURLMOPT_MAX_TOTAL_CONNECTIONS"))))
    (list gated plain)))

;; No other question is gated: each constant question's line is the plain
;; one, but for the gated constants, written out.
(test-equal "the C program reads CURLMOPT_QUICK_EXIT, CURLE_TOO_LARGE and CURLE_ECH_REQUIRED alone under a gate, every other constant plainly"
  '("CURLE_ECH_REQUIRED" "CURLE_TOO_LARGE" "CURLMOPT_QUICK_EXIT")
  (map cadr
       (filter (lambda (q)
                 (and (eq? (car q) 'constant)
                      (not (string=? (c-line q) (string-append "  CONSTANT(" (cadr q) ");\n")))))
               questions)))

;; The probe's controls: positive evidence that it can say each answer.
(test-equal "the presence probe tells declared from undeclared: CURLMOPT_MAX_TOTAL_CONNECTIONS, since 7.30.0, compiles alone, and CURLMOPT_NO_SUCH_OPTION does not"
  '(declared undeclared)
  probe-controls)

;; The gate, tied to the headers: too high fails where the headers declare
;; the constant, too low where they lack it.
(for-each
 (lambda (entry)
   (let ((g (gate-of (car entry))))
     (test-equal (string-append "the headers, " (text (shown-version header-version)) ", declare "
                                (car entry) " exactly when they are at or above its gate, "
                                (cadr g) ", " (hex (caddr g))
                                ": a compile of it alone, beside the controls, says")
       (cond ((not (eq? (car header-version) 'version)) header-version)
             ((>= (cadr header-version) (caddr g)) 'declared)
             (else 'undeclared))
       (cdr entry))))
 presences)

;; --- complete layouts --------------------------------------------------------------------

(for-each
 (lambda (row)
   (test-equal (string-append "layout-rows' row " (written (if (pair? row) (car row) row))
                              " is (name C-type extent), its extent whole or prefix")
     'shaped
     (if (and (list? row) (= (length row) 3) (symbol? (car row)) (string? (cadr row))
              (memq (caddr row) extents))
         'shaped
         row)))
 layout-rows)

;; Written out here, not read from the table: a row turned to prefix would
;; drop its size check with it.
(test-equal "curl-easyoption, curl-header, curl-msg, curl-blob and curl-slist are laid out whole, and curl-version-info-data as a prefix"
  '((curl-version-info-data prefix) (curl-easyoption whole) (curl-header whole) (curl-msg whole)
    (curl-blob whole) (curl-slist whole))
  (map (lambda (row) (list (car row) (caddr row))) layout-rows))

;; --- curlot-types is complete ---------------------------------------------------------------

(test-equal "curl/options.h, preprocessed with $CC -E, names CURLOT_ types"
  'found
  (if (and (pair? curlot-names-in-headers) (string? (car curlot-names-in-headers)))
      'found
      curlot-names-in-headers))

(test-equal "curlot-types names exactly the CURLOT_ names in the preprocessed headers, each once"
  (if (for-all string? curlot-names-in-headers)
      (string-sorted curlot-names-in-headers)
      curlot-names-in-headers)
  (if (for-all string? curlot-names-in-scheme)
      (let ((sorted (string-sorted curlot-names-in-scheme)))
        (if (= (length sorted) (length (c-identifiers (fold-left (lambda (a b) (string-append a " " b)) "" sorted) "CURLOT_")))
            sorted
            (list 'duplicates sorted)))
      curlot-names-in-scheme))

;; The reader on fixed text: a check that found nothing would agree with an
;; empty list.
(test-equal "c-identifiers: whole identifiers with the prefix, each once, in order, the text's first and last word among them; one inside another word is not one"
  '("CURLOT_FIRST" "CURLOT_LONG" "CURLOT_OFF_T" "CURLOT_FLAG" "CURLOT_LAST")
  (c-identifiers "CURLOT_FIRST typedef enum { CURLOT_LONG, CURLOT_OFF_T, XCURLOT_NO, CURLOT_LONG } t; int CURLOT_FLAG;CURLOT_LAST" "CURLOT_"))

;; --- prototypes -----------------------------------------------------------------------------

(test-equal "prototype-rows: each row is an entry's C name and its declarations, each well formed"
  '()
  (remp prototype-row-shaped? prototype-rows))

(test-equal "the scan of src/ read the bindings' types"
  'read
  (if (and (pair? signature-list) (pair? bound-entries)) 'read signatures))

(test-equal "prototype-rows has a row for every entry point src/ binds, and src/ binds every row's entry"
  (string-sorted bound-entries)
  (string-sorted (map car prototype-rows)))

(test-equal "prototype-rows has one row per entry"
  (length prototype-rows)
  (length (fold-left (lambda (found row) (if (member (car row) found) found (cons (car row) found)))
                     '() prototype-rows)))

(test-equal "the headers declare each entry as one of its row's declarations, and each callable's typedef as its row's: the C program's static assertions compile, with no link"
  'compiled
  prototypes-compiled)

;; The C side's control: the same program, with one type written as the
;; measurements showed gcc refuses, an enum written int, must not compile;
;; and with it written right, it must. Only that type differs, so only the
;; assertion can refuse it.
(test-equal "the prototype check refuses a row that writes an enum as int: curl_url_set's CURLUPart written int fails to compile, and written CURLUPart compiles"
  '(compiled refused)
  (let ((right '("curl_url_set" ("CURLUcode" ("CURLU *" "CURLUPart" "const char *" "unsigned int"))))
        (wrong '("curl_url_set" ("CURLUcode" ("CURLU *" "int" "const char *" "unsigned int")))))
    (list (compile-prototypes (list right))
          (let ((answer (compile-prototypes (list wrong))))
            (if (and (pair? answer) (eq? (car answer) 'compile)) 'refused answer)))))

;; The callable's control, likewise: curl_write_callback written with void *
;; for its char * must not compile, and written right, it must.
(test-equal "the prototype check refuses a callable row that writes curl_write_callback's char * as void *, and compiles it written right"
  '(compiled refused)
  (let ((right '(write-body "curl_write_callback" ("size_t" ("char *" "size_t" "size_t" "void *"))))
        (wrong '(write-body "curl_write_callback" ("size_t" ("void *" "size_t" "size_t" "void *")))))
    (list (compile-prototypes '() (list right))
          (let ((answer (compile-prototypes '() (list wrong))))
            (if (and (pair? answer) (eq? (car answer) 'compile)) 'refused answer)))))

(test-equal "callable-rows: each row is a callable's name, its typedef, and the typedef's declaration, well formed"
  '()
  (remp callable-row-shaped? callable-rows))

(test-equal "callable-rows has a row for every callable src/ defines, and src/ defines every row's callable"
  (list-sort symbol-before? bound-callables)
  (list-sort symbol-before? (map car callable-rows)))

;; Written out here, not read from the table: a row loosened along with the
;; callable it holds would otherwise pass.
(test-equal "callable-rows is exactly write-body and read-head, the header callable, each held to curl_write_callback: size_t (char *, size_t, size_t, void *), the typedef CURLOPT_HEADERFUNCTION's callback has too; read-body, the read callable, to curl_read_callback, the same shape; seek-body to curl_seek_callback, int (void *, curl_off_t, int); and prereq-body to curl_prereq_callback, int (void *, char *, char *, int, int)"
  '((write-body "curl_write_callback" ("size_t" ("char *" "size_t" "size_t" "void *")))
    (read-head "curl_write_callback" ("size_t" ("char *" "size_t" "size_t" "void *")))
    (read-body "curl_read_callback" ("size_t" ("char *" "size_t" "size_t" "void *")))
    (seek-body "curl_seek_callback" ("int" ("void *" "curl_off_t" "int")))
    (prereq-body "curl_prereq_callback" ("int" ("void *" "char *" "char *" "int" "int"))))
  callable-rows)

(for-each
 (lambda (sig)
   (let ((row (assq (car sig) callable-rows)))
     (test-equal (string-append "callable: " (written (car sig)) " defined through "
                                (symbol->string (cadr sig)) " as " (written (caddr sig)) " -> "
                                (written (cadddr sig)) " fits its typedef's declaration")
       'fits
       (cond ((not row) 'no-row)
             ((declaration-fits? (cadr row) (caddr row) (caddr sig) (cadddr sig)) 'fits)
             (else (list 'fits-not (caddr row)))))))
 (filter (lambda (sig) (symbol? (car sig))) signature-list))

(for-each
 (lambda (sig)
   (let ((row (assoc (car sig) prototype-rows)))
     (test-equal (string-append "prototype: " (written (car sig)) " bound through "
                                (symbol->string (cadr sig)) " as " (written (caddr sig)) " -> "
                                (written (cadddr sig)) " fits a declaration its row gives")
       'fits
       (cond ((not row) 'no-row)
             ((exists (lambda (d) (declaration-fits? (car sig) d (caddr sig) (cadddr sig)))
                      (cdr row))
              'fits)
             (else (list 'fits-none-of (cdr row)))))))
 (filter (lambda (sig) (string? (car sig))) signature-list))

;; --- the map and the rows, pinned as written-out data ------------------------------------
;; A table loosened together with the binding it holds passes every live
;; check above: getinfo's row taking int with getinfo bound int, long mapped
;; to int with curl_global_init bound int. So each table is written out
;; here, and held both ways.

(define (type<? a b) (string<? (written a) (written b)))
(define (type-sorted types) (list-sort type<? types))

(test-equal "c-type-map is exactly, written out here: void, int, unsigned int, long, size_t and curl_off_t each to its one Chez type, and each of the twelve enums to int"
  '(("void" void) ("int" int) ("unsigned int" unsigned-int) ("long" long) ("size_t" size_t)
    ("curl_off_t" integer-64)
    ("CURLcode" int) ("CURLversion" int) ("CURLoption" int) ("CURLINFO" int)
    ("CURLHcode" int) ("CURLUcode" int) ("CURLUPart" int) ("CURLMcode" int)
    ("CURLMoption" int) ("CURLSHcode" int) ("CURLSHoption" int) ("CURLFORMcode" int))
  c-type-map)

;; expected-fits : (Listof (Pairof (List String String) (Listof Type)))
;; For an entry and a C type, every type a binding may write there, out of
;; everything the reader reads: exactly these, and every other type of the
;; universe refused. "x" is any entry but memcpy.
(define expected-fits
  '((("x" "void") void)
    (("x" "int") int)
    (("x" "unsigned int") unsigned-int)
    (("x" "long") long)
    (("x" "size_t") size_t)
    (("x" "curl_off_t") integer-64)
    (("x" "CURLcode") int)
    (("x" "CURLversion") int)
    (("x" "CURLoption") int)
    (("x" "CURLINFO") int)
    (("x" "CURLHcode") int)
    (("x" "CURLUcode") int)
    (("x" "CURLUPart") int)
    (("x" "CURLMcode") int)
    (("x" "CURLMoption") int)
    (("x" "CURLSHcode") int)
    (("x" "CURLSHoption") int)
    (("x" "CURLFORMcode") int)
    (("x" "double"))
    (("x" "CURL *") uptr void*)
    (("x" "CURLU *") uptr void*)
    (("x" "const CURLU *") uptr void*)
    (("x" "char **") uptr void*)
    (("x" "void *") uptr void*)
    (("x" "const void *") uptr void*)
    (("x" "struct curl_header **") uptr void*)
    (("x" "struct curl_header *") uptr void* (* curl-header))
    (("x" "struct curl_slist *") uptr void* (* curl-slist))
    (("x" "char *") uptr void*)
    (("x" "const char *") uptr void* string)
    (("x" "curl_version_info_data *") uptr void* (* curl-version-info-data))
    (("x" "struct curl_easyoption *") uptr void* (* curl-easyoption))
    (("x" "const struct curl_easyoption *") uptr void*)
    (("x" "CURLM *") uptr void*)
    (("x" "CURLSH *") uptr void*)
    (("x" "int *") uptr void*)
    (("x" "struct curl_waitfd []") uptr void*)
    (("x" "CURLMsg *") uptr void*)
    (("x" "struct CURLMsg *") uptr void* (* curl-msg))
    (("x" "curl_mime *") uptr void*)
    (("x" "curl_mimepart *") uptr void*)
    (("x" "struct curl_httppost *") uptr void*)
    (("x" "struct curl_httppost **") uptr void*)
    (("memcpy" "void *") uptr void* u8*)
    (("memcpy" "const void *") uptr void* u8*)
    (("memcpy" "const char *") uptr void* u8* string)))

(test-equal "the universe the map is held against: every type the conventions reader reads, for src/'s six layouts, and an ftype no layout defines"
  (+ 33 1 3 7 1 12 1)
  (length universe))

(for-each
 (lambda (entry)
   (let ((key (car entry)))
     (test-equal (string-append "the map, in " (car key) "'s row: for " (cadr key)
                                " exactly " (written (cdr entry)) " fit, and every other type a binding can write is refused")
       (type-sorted (cdr entry))
       (type-sorted (fits (car key) (cadr key))))))
 expected-fits)

(test-equal "every C type a prototype row writes is one expected-fits pins"
  '()
  (filter (lambda (type) (not (assoc (list "x" type) expected-fits))) prototype-c-types))

;; The variadic rows: which types each may pass after its named parameters.
(define (variadic-list row)
  (let ((d (cadr row)))
    (and (= (length d) 3) (caddr d))))

(test-equal "the variadic rows are curl_easy_setopt's, curl_easy_getinfo's, curl_multi_setopt's, curl_share_setopt's and curl_formadd's alone: setopt passes exactly long, integer-64 and uptr, getinfo exactly uptr, its destination, never int, multi_setopt exactly long, share_setopt exactly int, the type libcurl's va_arg reads for SHARE, and formadd exactly the run int, uptr, int, uptr, int, two options with a string each, then CURLFORM_END, each option an int, as libcurl's va_arg reads a CURLformoption"
  '(("curl_easy_setopt" (variadic long integer-64 uptr)) ("curl_easy_getinfo" (variadic uptr))
    ("curl_multi_setopt" (variadic long)) ("curl_share_setopt" (variadic int))
    ("curl_formadd" (variadic-run int uptr int uptr int)))
  (map (lambda (row) (list (car row) (variadic-list row)))
       (filter (lambda (row) (and (pair? (cdr row)) (variadic-list row))) prototype-rows)))

(test-equal "only curl_url_get's row gives more than one declaration, and it gives two"
  '(("curl_url_get" 2))
  (map (lambda (row) (list (car row) (length (cdr row))))
       (filter (lambda (row) (> (length (cdr row)) 1)) prototype-rows)))

;; declaration-fits-sets : String Declaration -> (Listof (Listof Type))
;; What may stand at each place of DECLARATION, its result first.
(define (declaration-fits-sets entry declaration)
  (map (lambda (c-type) (type-sorted (fits entry c-type)))
       (cons (car declaration) (cadr declaration))))

(test-equal "curl_url_get's two declarations, CURLU * and const CURLU *, let a binding write the same Chez types at every place"
  'same
  (let ((row (assoc "curl_url_get" prototype-rows)))
    (if (and row (= (length (cdr row)) 2))
        (let ((a (declaration-fits-sets (car row) (cadr row)))
              (b (declaration-fits-sets (car row) (caddr row))))
          (if (equal? a b) 'same (list a b)))
        (list 'no-two-declarations row))))

;; --- the enums --------------------------------------------------------------------------------

(test-equal "the headers, preprocessed, define typedef enums"
  'found
  (if (and (list? header-enums) (pair? header-enums) (string? (car header-enums))) 'found header-enums))

(test-equal "the enum names, written out, are exactly c-type-map's C types that map to int, but int itself"
  (string-sorted enum-names)
  (string-sorted (map car (filter (lambda (entry) (and (equal? (cdr entry) '(int))
                                                       (not (string=? (car entry) "int"))))
                                  c-type-map))))

(test-equal "each enum name is a typedef enum in the headers, and every C type a row writes that the headers define so is one of them"
  (list '() '())
  (if (and (list? header-enums) (for-all string? header-enums))
      (list (filter (lambda (name) (not (member name header-enums))) enum-names)
            (filter (lambda (type) (and (member type header-enums) (not (member type enum-names))))
                    prototype-c-types))
      header-enums))

;; The reader on fixed text, at each place a scan can miss: the first
;; statement, a tag, braces inside, the last statement, and a struct and an
;; enum with no typedef, which name no enum type.
(test-equal "enums-in: typedef enum, with a tag or without, its braces nested or not, first and last in the text; a typedef struct and an untyped enum are none"
  '("A" "B" "C" "D")
  (enums-in (c-tokens (string-append
                       "typedef enum { A1, A2 } A;"
                       "typedef struct { int x; } S;"
                       "typedef enum tag { B1 = (1 << 2) } B;"
                       "enum untyped { U1 };"
                       "typedef enum { C1 = sizeof(struct { int y; }) } C;"
                       "typedef enum { D1 } D;"))))

;; --- the headers' own spelling -------------------------------------------------------------

(test-equal "the preprocessed headers hold tokens to read"
  'tokens
  (if header-tokens-read? 'tokens (list 'no-tokens header-tokens)))

;; Positive evidence for the comparison below, apart from it: each row's
;; entry is declared in the headers it compiles against.
(test-equal "the preprocessed headers declare every entry a prototype row names"
  '()
  (filter (lambda (row) (eq? (car (header-declaration (car row))) 'no-declaration))
          prototype-rows))

(for-each
 (lambda (row)
   (test-equal (string-append "prototype: the headers declare " (car row)
                              " in one of its row's spellings, an enum by its own name")
     'spelled-so
     (let ((header (header-declaration (car row))))
       (cond ((eq? (car header) 'no-declaration) header)
             ((member header (map row-spelling (cdr row))) 'spelled-so)
             (else (list 'header-spells header 'row-spells (map row-spelling (cdr row))))))))
 prototype-rows)

(for-each
 (lambda (row)
   (test-equal (string-append "callable: the headers declare " (cadr row)
                              ", " (symbol->string (car row)) "'s typedef, in its row's spelling")
     'spelled-so
     (let ((header (header-typedef (cadr row))))
       (cond ((eq? (car header) 'no-declaration) header)
             ((equal? header (row-spelling (caddr row))) 'spelled-so)
             (else (list 'header-spells header 'row-spells (row-spelling (caddr row))))))))
 callable-rows)

;; The typedef reader on fixed text: a decoy whose name only begins like
;; the one asked for, a struct with no pointer, the typedef itself, and a
;; second typedef of the name after it, which is never read.
(test-equal "typedef-in: the first typedef of a function pointer by its whole name, its parameter names dropped; a longer name, a non-typedef and a later one are passed over"
  '(("size_t" ("char *" "size_t" "size_t" "void *"))
    ("int" ())
    (no-declaration "absent"))
  (let ((tokens (without-attributes
                 (c-tokens (string-append
                            "typedef int (*cb_longer)(void);\n"
                            "struct s { int (*cb)(char *); };\n"
                            "size_t (*cb)(int);\n"
                            "typedef size_t (*cb)(char *buffer, size_t size, size_t nitems, void *outstream);\n"
                            "typedef int (*cb)(void);\n"
                            "typedef int (*other)(void);\n")))))
    (list (typedef-in tokens "cb") (typedef-in tokens "other") (typedef-in tokens "absent"))))

;; The reader on fixed text, at each place a scan can miss: the first
;; statement, one after a brace, a parameter list of void, names dropped
;; and kept, restrict, an attribute before and after, and a definition
;; skipped for the declaration after it.
(test-equal "header-declaration's reading: names dropped, type keywords and struct and enum tags kept, restrict, nullability and attributes ignored, (void) empty, a definition passed over, a statement just after {"
  '(("CURLUcode" ("CURLU *" "CURLUPart" "const char *" "unsigned int"))
    ("void *" ("void *" "const void *" "size_t"))
    ("CURL *" ())
    ("CURLHcode" ("CURL *" "struct curl_header **" "unsigned int"))
    ("int" ("int"))
    ("int" ("enum CURLUPart"))
    ("const char *" ("void *" "const char *" "CURL *"))
    ("int" ("char *")))
  (let ((tokens (without-attributes
                 (c-tokens (string-append
                            "CURLUcode first(CURLU *u, CURLUPart what, const char *part, unsigned int flags);\n"
                            "struct s { int x; };\n"
                            "extern void *second (void *__restrict __dest, const void *__restrict __src, size_t __n) __attribute__ ((__nothrow__ , __leaf__));\n"
                            "__attribute__ ((visibility (\"default\"))) CURL *third(void);\n"
                            "CURLHcode fourth(CURL *easy, struct curl_header **, unsigned int);\n"
                            "int fifth(int a) { return a; }\n"
                            "int fifth(int);\n"
                            "{int sixth(enum CURLUPart);}\n"
                            "const char * _Nullable seventh(void * _Nonnull p, const char *__nullable s, CURL * _Null_unspecified e) __attribute((availability(macos,introduced=10.0)));\n"
                            "__attribute((visibility(\"default\"))) int eighth(char *__nonnull __null_unspecified);\n")))))
    (map (lambda (name) (declaration-in tokens name))
         '("first" "second" "third" "fourth" "fifth" "sixth" "seventh" "eighth"))))

(test-equal "a variadic declaration: its named parameters by the map, then exactly one of the types it names; getinfo's destination is a pointer, never int"
  '(#t #t #t #f #f #f)
  (let ((setopt '("CURLcode" ("CURL *" "CURLoption" "...") (variadic long integer-64 uptr)))
        (getinfo '("CURLcode" ("CURL *" "CURLINFO" "...") (variadic uptr))))
    (list (declaration-fits? "curl_easy_setopt" setopt '(uptr int long) 'int)
          (declaration-fits? "curl_easy_setopt" setopt '(uptr int integer-64) 'int)
          (declaration-fits? "curl_easy_getinfo" getinfo '(uptr int uptr) 'int)
          (declaration-fits? "curl_easy_getinfo" getinfo '(uptr int int) 'int)
          (declaration-fits? "curl_easy_setopt" setopt '(uptr int) 'int)
          (declaration-fits? "curl_easy_setopt" setopt '(uptr int long long) 'int))))

;; curl_formadd's run: the binding's whole variadic tail must be the run,
;; neither one of its types alone, nor the run cut short or grown, nor a
;; type changed at any of its five places.
(test-equal "a variadic-run declaration: its named parameters by the map, then exactly the run it names, each of its five places checked; one type of it alone fails"
  '(#t #f #f #f #f #f #f #f #f #f)
  (let ((formadd '("CURLFORMcode" ("struct curl_httppost **" "struct curl_httppost **" "...")
                   (variadic-run int uptr int uptr int))))
    (map (lambda (parameters) (declaration-fits? "curl_formadd" formadd parameters 'int))
         '((uptr uptr int uptr int uptr int)
           (uptr uptr int)
           (uptr uptr int uptr int uptr)
           (uptr uptr int uptr int uptr int int)
           (long uptr int uptr int uptr int)
           (uptr uptr long uptr int uptr int)
           (uptr uptr int int int uptr int)
           (uptr uptr int uptr long uptr int)
           (uptr uptr int uptr int int int)
           (uptr uptr int uptr int uptr long)))))

;; --- each constant and each field, against the headers -------------------------------------

;; A gated constant, against headers older than its gate, is named
;; unchecked: the test passes only when the program answered so and the
;; headers are below the gate. Everywhere else its value is checked.
(for-each
 (lambda (check)
   (let* ((question (caddr check))
          (gated (and (eq? (car question) 'constant) (gate-of (cadr question)))))
     (if (and gated (below-gate? gated))
         (test-equal (string-append (symbol->string (car check))
                                    " is unchecked against these headers: " (cadr question)
                                    " came in curl " (cadr gated) ", " (hex (caddr gated))
                                    ", and these headers are "
                                    (text (shown-version header-version)))
           'unchecked
           (let ((a (header-answer question)))
             (if (and (equal? a (list 'unchecked (cadr question))) (below-gate? gated))
                 'unchecked
                 (list 'answered a 'headers (shown-version header-version)
                       'gate (hex (caddr gated))))))
         (test-equal (cadr check)
           (header-value question)
           (scheme-value check)))))
 check-list)

(test-end "constants")

(exit (suite-exit-status runner))
