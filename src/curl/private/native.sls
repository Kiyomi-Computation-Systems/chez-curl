#!r6rs
;;; (curl private native): loads libcurl, once, and binds it (ADR-0001,
;;; ADR-0002, ADR-0003). The only library that calls into libcurl.
;;;
;;; Its body is the load, written as definitions in the order they must
;;; run. A library body evaluates its definitions in order, so the order
;;; below is the order at run time. Nothing binds lazily:
;;;
;;;   0. once     a failure recorded by an earlier run of this body is
;;;               raised again, before anything else runs
;;;   1. choose   (curl private discovery) picks the path and its source
;;;   2. load     load-shared-object, once. A raise is load-failed, and no
;;;               other candidate is ever tried: a library once loaded
;;;               cannot be unloaded, and Chez binds each name to the most
;;;               recently loaded object (ADR-0002)
;;;   3. version  curl_version_info, the first entry point bound. Then
;;;               libc's memcpy, bound once each way, and strlen: not
;;;               libcurl's, and present once it is loaded, so they refuse
;;;               nothing a check below would name. They read
;;;               curl_version_info_data's strings, through the checked
;;;               copies, into the libcurl-info record, and its protocol
;;;               list, which loaded-protocols answers
;;;   4. check    the floor and CURL_VERSION_SSL: check-version
;;;   5. init     curl_global_init, exactly once
;;;   6. bind     every other entry point, eagerly
;;;   7. probe    the options API and the header API, then check-apis
;;;
;;; Every native object it makes is counted, in (curl private counters):
;;; each foreign block, through (curl private memory), each easy handle,
;;; each CURLU handle, and each string curl_url_get hands back. The load's
;;; own, the header probe's handle and its slot, are freed before it
;;; returns, so every count is zero after it.
;;;
;;; Two copies own every move of bytes between a bytevector and foreign
;;; memory (ADR-0001, amended 2026-10-16): copy-foreign->bytevector! and
;;; copy-bytevector->foreign!. Each asserts its span fits the bytevector
;;; before any C runs, since Valgrind cannot see an overrun into Chez's
;;; heap. memcpy's two bindings are theirs alone, and not exported. Chez's
;;; u8* hands C a bytevector's first byte, with no offset, so a span that
;;; starts past the first byte goes through a fresh bytevector of its own
;;; length, and bytevector-copy!.
;;;
;;; C strings go through them too (M2 plan, section 3.3): call-with-c-string
;;; hands C a counted, NUL-terminated UTF-8 copy, refusing a string that
;;; holds U+0000, which C would read as its end; c-string->bytevector reads
;;; one back as bytes.
;;;
;;; The load runs once per process, whatever it decides. Chez runs a
;;; library body that raised again at every later reference, so each step
;;; from 1 on runs inside load-step, from (curl private load-state), which
;;; records the first failure there and raises it, made serious. Step 0
;;; raises that recorded failure at every later reference: nothing is
;;; loaded, initialised or probed twice, and a CHEZ_CURL_LIBCURL changed in
;;; between is never read (ADR-0002, decision 3).
;;;
;;; foreign-procedure resolves its entry point when it is evaluated, so a
;;; binding must follow the load, and an entry point the library lacks
;;; fails with Chez's bare "no entry for". So every required entry point is
;;; asked of foreign-entry? first, and an absent one is missing-api, naming
;;; it. curl_version_info is one, so a library that is not libcurl at all is
;;; refused by name.
;;;
;;; Every refusal is a &curl-library-unavailable carrying the path and its
;;; source, with a who and a message for the default handler to print. One
;;; made after step 3 also carries the report, the libcurl-info built there.
;;; The reasons raised here, beside those of discovery and verify:
;;;
;;;   load-failed  the loader refused the path (detail: its message);
;;;                curl_version_info or curl_easy_init answered NULL,
;;;                curl_version_info's version was NULL, or
;;;                curl_global_init failed (detail: what happened)
;;;   missing-api  a required entry point is absent (detail: its C name)
(library (curl private native)
  (export loaded-libcurl curl-easy-option
          curl-easy-init curl-easy-cleanup
          curl-easy-setopt-long curl-easy-setopt-pointer curl-easy-setopt-off-t
          curl-easy-getinfo
          copy-foreign->bytevector! copy-bytevector->foreign!
          call-with-c-string c-string->bytevector
          curl-url curl-url-cleanup curl-url-set curl-url-get curl-url-strerror
          curl-free loaded-protocols)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) ftype-ref make-ftype-pointer
                foreign-procedure foreign-entry? load-shared-object
                foreign-ref foreign-sizeof
                format format-condition? display-condition
                getenv machine-type file-regular?)
          (curl private load-state)
          (curl private libcurl-info)
          (curl private conditions)
          (curl private constants)
          (curl private layouts)
          (curl private counters)
          (curl private memory)
          (curl private discovery)
          (curl private verify))

  ;; --- 0. once ---------------------------------------------------------------

  ;; The first definition: an earlier run of this body failed, and that
  ;; failure is raised again. The steps below never run twice.
  (define earlier-failure
    (let ((failure (load-failure)))
      (when failure (raise failure))
      #f))

  ;; --- helpers -----------------------------------------------------------------

  ;; refuse : Symbol String Symbol (U Libcurl-Info #f) Any String -> Nothing
  ;; LIBRARY is the report, once step 3 has built it, else #f.
  (define (refuse reason path source library detail message)
    (raise (condition (make-curl-library-unavailable reason path source detail '()
                                                     library)
                      (make-who-condition 'chez-curl)
                      (make-message-condition message)
                      (make-irritants-condition (list path)))))

  ;; linux-machine? : Symbol -> Boolean
  ;; Chez's Linux machine types end in le: ta6le, tarm64le.
  (define (linux-machine? type)
    (let* ((name (symbol->string type)) (n (string-length name)))
      (and (>= n 2) (string=? (substring name (- n 2) n) "le"))))

  ;; maps-text : -> (U String #f)
  ;; /proc/self/maps, read whole, on Linux; #f on any failure, and on any
  ;; other platform. Discovery reads the world from it.
  (define (maps-text)
    (and (linux-machine? (machine-type))
         (guard (e (#t #f))
           (let ((text (call-with-port
                        (open-file-input-port "/proc/self/maps" (file-options)
                                              (buffer-mode block)
                                              (make-transcoder (utf-8-codec)))
                        get-string-all)))
             (and (string? text) text)))))

  ;; regular-file? : String -> Boolean
  ;; A regular file, symlinks followed: Guix's libcurl.so.4 is a symlink.
  (define (regular-file? path)
    (guard (e (#t #f))
      (file-regular? path)))

  ;; loader-message : Condition -> String
  ;; What the loader said, as Chez would print it after "Exception: ".
  (define (loader-message e)
    (if (and (format-condition? e) (message-condition? e) (irritants-condition? e))
        (apply format (condition-message e) (condition-irritants e))
        (call-with-string-output-port (lambda (p) (display-condition e p)))))

  ;; required-entry : String (U Libcurl-Info #f) -> Void
  ;; Raises missing-api, naming NAME and carrying LIBRARY, unless the loaded
  ;; library has it.
  (define (required-entry name library)
    (unless (foreign-entry? name)
      (refuse 'missing-api libcurl-path libcurl-source library name
              (string-append "the library has no " name
                             ", so it is not a libcurl chez-curl can use; name another with CHEZ_CURL_LIBCURL"))))

  ;; (bind-required ENTRY (ARG-TYPE ...) RESULT-TYPE LIBRARY): ENTRY bound
  ;; with foreign-procedure, after required-entry has found it.
  (define-syntax bind-required
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (required-entry entry library)
         (foreign-procedure entry (arg ...) result)))))

  ;; (bind-variadic ENTRY (ARG-TYPE ...) RESULT-TYPE LIBRARY): ENTRY, a C
  ;; function whose arguments after the first two are variadic, bound with
  ;; foreign-procedure and (__varargs_after 2), after required-entry has
  ;; found it. One binding per value type (ADR-0001, decision 1). The
  ;; convention is the template's own, never a use's: Apple arm64 passes
  ;; variadic arguments on the stack, and a binding without it hands C
  ;; garbage there, while x86-64 and Linux arm64 work either way.
  ;; tests/foreign-conventions.sls holds every use to its row, and make
  ;; check-variadic removes the convention here, in a copy, to watch that
  ;; fail.
  (define-syntax bind-variadic
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (required-entry entry library)
         (foreign-procedure (__varargs_after 2) entry (arg ...) result)))))

  ;; --- the checked copies (ADR-0001, amended 2026-10-16) -------------------------
  ;; Their memcpy bindings, memcpy->bytevector and memcpy->foreign, are bound
  ;; in step 3, and referenced nowhere but here.

  ;; exact-natural? : Any -> Boolean
  (define (exact-natural? x)
    (and (integer? x) (exact? x) (>= x 0)))

  ;; check-copy : Symbol Any Any Any Any -> Void
  ;; WHO's span, N bytes at OFFSET in BYTEVECTOR, and ADDRESS, the foreign
  ;; side. Raises an assertion violation from WHO, naming the first fault,
  ;; unless ADDRESS is a positive exact integer, BYTEVECTOR a bytevector,
  ;; OFFSET and N exact non-negative integers, and OFFSET + N at most its
  ;; length.
  (define (check-copy who address bytevector offset n)
    (unless (and (integer? address) (exact? address) (positive? address))
      (assertion-violation who "the foreign address is not a positive exact integer" address))
    (unless (bytevector? bytevector)
      (assertion-violation who "not a bytevector" bytevector))
    (unless (exact-natural? offset)
      (assertion-violation who "the offset is not an exact non-negative integer" offset))
    (unless (exact-natural? n)
      (assertion-violation who "the count is not an exact non-negative integer" n))
    (unless (<= (+ offset n) (bytevector-length bytevector))
      (assertion-violation who "the span runs past the bytevector's end"
                           offset n (bytevector-length bytevector))))

  ;; copy-foreign->bytevector! : Positive-Integer Bytevector Natural Natural -> Void
  ;; Copies N bytes from foreign memory at ADDRESS into BYTEVECTOR, from
  ;; OFFSET, with memcpy, after check-copy. N = 0 calls nothing. ADDRESS's
  ;; side is left to Valgrind: a counted block is malloc'd, and a pointer
  ;; libcurl hands chez-curl comes with its length.
  (define (copy-foreign->bytevector! address bytevector offset n)
    (check-copy 'copy-foreign->bytevector! address bytevector offset n)
    (cond ((= n 0))
          ((= offset 0) (memcpy->bytevector bytevector address n))
          (else
           (let ((bounce (make-bytevector n)))
             (memcpy->bytevector bounce address n)
             (bytevector-copy! bounce 0 bytevector offset n)))))

  ;; copy-bytevector->foreign! : Bytevector Natural Positive-Integer Natural -> Void
  ;; Copies N bytes of BYTEVECTOR, from OFFSET, into foreign memory at
  ;; ADDRESS, with memcpy, after check-copy. N = 0 calls nothing.
  (define (copy-bytevector->foreign! bytevector offset address n)
    (check-copy 'copy-bytevector->foreign! address bytevector offset n)
    (cond ((= n 0))
          ((= offset 0) (memcpy->foreign address bytevector n))
          (else
           (let ((bounce (make-bytevector n)))
             (bytevector-copy! bytevector offset bounce 0 n)
             (memcpy->foreign address bounce n)))))

  ;; --- C strings (M2 plan, section 3.3) ---------------------------------------------

  ;; c-string->bytevector : Natural -> (U Bytevector #f)
  ;; The bytes of the NUL-terminated string at ADDRESS, up to the NUL,
  ;; copied; #f for NULL. Whoever reads them decodes them.
  (define (c-string->bytevector address)
    (and (not (eqv? address 0))
         (let* ((n (strlen address))
                (bytes (make-bytevector n)))
           (copy-foreign->bytevector! address bytes 0 n)
           bytes)))

  ;; c-text : Natural -> (U String #f)
  ;; The UTF-8 string at ADDRESS; #f for NULL.
  (define (c-text address)
    (let ((bytes (c-string->bytevector address)))
      (and bytes (utf8->string bytes))))

  ;; holds-nul? : String -> Boolean
  (define (holds-nul? s)
    (let loop ((i 0))
      (and (< i (string-length s))
           (or (char=? (string-ref s i) #\nul) (loop (+ i 1))))))

  ;; call-with-c-string : String (Positive-Integer -> Any) -> Any
  ;; PROC's answer, PROC given the address of STRING as C reads it: its
  ;; UTF-8 bytes and a NUL, in a counted block freed once PROC returns,
  ;; raises or escapes. A STRING that holds U+0000 raises
  ;; &curl-embedded-nul, before anything is allocated: C would read the
  ;; NUL as the string's end, as Chez's string type does without a word.
  ;; Re-entering PROC through a continuation, once the block is freed,
  ;; raises an assertion violation, so the address is never used after.
  (define (call-with-c-string string proc)
    (unless (string? string)
      (assertion-violation 'call-with-c-string "not a string" string))
    (unless (procedure? proc)
      (assertion-violation 'call-with-c-string "not a procedure" proc))
    (when (holds-nul? string)
      (raise (condition (make-curl-embedded-nul string)
                        (make-who-condition 'call-with-c-string)
                        (make-message-condition "a string C reads ends at its first NUL, and this one holds one"))))
    (let* ((utf8 (string->utf8 string))
           (n (+ (bytevector-length utf8) 1))
           (bytes (make-bytevector n 0))
           (block #f)
           (freed #f))
      (bytevector-copy! utf8 0 bytes 0 (- n 1))
      (dynamic-wind
        (lambda ()
          (when freed
            (assertion-violation 'call-with-c-string
                                 "re-entered after its string was freed" string))
          (set! block (foreign-block n)))
        (lambda ()
          (copy-bytevector->foreign! bytes 0 block n)
          (proc block))
        (lambda ()
          (set! freed #t)
          (free-foreign-block! block)))))

  ;; --- 1. choose -----------------------------------------------------------------

  (define chosen
    (load-step
     (call-with-values
      (lambda () (choose-libcurl getenv (machine-type) (maps-text) regular-file?))
      cons)))

  (define libcurl-path (car chosen))
  (define libcurl-source (cdr chosen))

  ;; --- 2. load, once ---------------------------------------------------------------

  (define libcurl-loaded
    (load-step
     (guard (e (#t (refuse 'load-failed libcurl-path libcurl-source #f (loader-message e)
                           "the loader refused this libcurl; name one this Chez can load with CHEZ_CURL_LIBCURL, an absolute path")))
       (load-shared-object libcurl-path)
       #t)))

  ;; --- 3. curl_version_info, first -------------------------------------------------

  ;; curl_version_info_data *curl_version_info(CURLversion age)
  (define curl-version-info (load-step (bind-required "curl_version_info" (int) uptr #f)))

  (define version-data
    (load-step
     (let ((address (curl-version-info curlversion-tenth)))
       (when (zero? address)
         (refuse 'load-failed libcurl-path libcurl-source #f "curl_version_info returned NULL"
                 "curl_version_info returned NULL, so this libcurl cannot say what it is; name another with CHEZ_CURL_LIBCURL"))
       (make-ftype-pointer curl-version-info-data address))))

  ;; libc's, not libcurl's: present once libcurl is loaded, and not before
  ;; (ADR-0001, decision 5), so bound here, after it. They read
  ;; curl_version_info_data's strings, below, before the floor is checked,
  ;; and they refuse nothing a later check would name. Plain calls: a call
  ;; that is not __collect_safe keeps the thread active, so no collection
  ;; moves a bytevector mid-copy. The checked copies alone use the two
  ;; memcpy bindings, which are not exported.

  ;; void *memcpy(void *dest, const void *src, size_t n), into a bytevector
  (define memcpy->bytevector
    (load-step (bind-required "memcpy" (u8* uptr size_t) uptr #f)))

  ;; the same, out of a bytevector
  (define memcpy->foreign
    (load-step (bind-required "memcpy" (uptr u8* size_t) uptr #f)))

  ;; size_t strlen(const char *s)
  (define strlen (load-step (bind-required "strlen" (uptr) size_t #f)))

  ;; The record's version is a string, and the floor's refusal names it.
  (define version-string
    (load-step
     (or (c-text (ftype-ref curl-version-info-data (version) version-data))
         (refuse 'load-failed libcurl-path libcurl-source #f "curl_version_info returned no version"
                 "curl_version_info returned no version string, so this libcurl cannot say what it is; name another with CHEZ_CURL_LIBCURL"))))

  (define info
    (load-step
     (let ((features (ftype-ref curl-version-info-data (features) version-data)))
       (make-libcurl-info
        libcurl-path
        libcurl-source
        version-string
        (ftype-ref curl-version-info-data (version-num) version-data)
        features
        (feature-names features)
        (c-text (ftype-ref curl-version-info-data (ssl-version) version-data))
        (c-text (ftype-ref curl-version-info-data (host) version-data))))))

  ;; The protocols the library supports, from curl_version_info_data's
  ;; protocols: an array of C strings that ends at NULL, or NULL itself.
  ;; Not a libcurl-info field: (curl) adds nothing public in M2. tests/test-url.sps
  ;; holds the scheme check against every one of them. Its place in step 3
  ;; is no rule: it reads data curl_version_info has already answered,
  ;; makes no call, and refuses nothing, so reading it later would change
  ;; nothing.
  (define protocol-list
    (load-step
     (let ((array (ftype-ref curl-version-info-data (protocols) version-data))
           (step (foreign-sizeof 'uptr)))
       (if (eqv? array 0)
           '()
           (let loop ((i 0) (found '()))
             (let ((entry (foreign-ref 'uptr array (* i step))))
               (if (eqv? entry 0)
                   (reverse found)
                   (loop (+ i 1) (cons (c-text entry) found)))))))))

  ;; --- 4. the floor and SSL ----------------------------------------------------------

  (define version-checked
    (load-step
     (check-version (libcurl-info-version info) (libcurl-info-version-number info)
                    (libcurl-info-features info) libcurl-path libcurl-source info)))

  ;; --- 5. curl_global_init, exactly once ---------------------------------------------

  ;; CURLcode curl_global_init(long flags)
  (define curl-global-init (load-step (bind-required "curl_global_init" (long) int info)))

  (define global-initialized
    (load-step
     (let ((code (curl-global-init curl-global-default)))
       (unless (= code curle-ok)
         (refuse 'load-failed libcurl-path libcurl-source info
                 (string-append "curl_global_init returned " (number->string code))
                 "curl_global_init failed, so this libcurl cannot be used; name another with CHEZ_CURL_LIBCURL"))
       #t)))

  ;; --- 6. every other entry point, eagerly ---------------------------------------------

  ;; const struct curl_easyoption *curl_easy_option_by_name(const char *name)
  (define curl-easy-option-by-name
    (load-step (bind-required "curl_easy_option_by_name" (string) uptr info)))

  ;; CURL *curl_easy_init(void)
  (define raw-curl-easy-init (load-step (bind-required "curl_easy_init" () uptr info)))

  ;; CURLHcode curl_easy_header(CURL *easy, const char *name, size_t index,
  ;;                            unsigned int origin, int request,
  ;;                            struct curl_header **hout)
  (define curl-easy-header
    (load-step
     (bind-required "curl_easy_header" (uptr string size_t unsigned-int int uptr) int info)))

  ;; void curl_easy_cleanup(CURL *easy)
  (define raw-curl-easy-cleanup
    (load-step (bind-required "curl_easy_cleanup" (uptr) void info)))

  ;; The URL API (ADR-0008), 7.62.0; curl_url_strerror 7.80.0. All below
  ;; the floor, and required.

  ;; CURLU *curl_url(void)
  (define raw-curl-url (load-step (bind-required "curl_url" () uptr info)))

  ;; void curl_url_cleanup(CURLU *handle)
  (define raw-curl-url-cleanup (load-step (bind-required "curl_url_cleanup" (uptr) void info)))

  ;; CURLUcode curl_url_set(CURLU *handle, CURLUPart what, const char *part,
  ;;                        unsigned int flags)
  ;; curl-url-set : Natural Integer Natural Natural -> Integer
  ;; HANDLE, a CURLUPART_* code, the address of a C string, as
  ;; call-with-c-string hands it, and flags: the CURLUcode. libcurl keeps
  ;; no pointer to the string: "does not have to keep content around after
  ;; a successful call" (curl_url_set(3), 7.85.0).
  (define curl-url-set
    (load-step (bind-required "curl_url_set" (uptr int uptr unsigned-int) int info)))

  ;; CURLUcode curl_url_get(const CURLU *handle, CURLUPart what, char **part,
  ;;                        unsigned int flags)
  (define raw-curl-url-get
    (load-step (bind-required "curl_url_get" (uptr int uptr unsigned-int) int info)))

  ;; const char *curl_url_strerror(CURLUcode error)
  (define raw-curl-url-strerror
    (load-step (bind-required "curl_url_strerror" (int) uptr info)))

  ;; void curl_free(void *p)
  (define raw-curl-free (load-step (bind-required "curl_free" (uptr) void info)))

  ;; CURLcode curl_easy_setopt(CURL *handle, CURLoption option, ...),
  ;; variadic after option: bound once per value type. curl_off_t is 64
  ;; bits on every platform chez-curl supports. Bound last, so a library
  ;; that lacks an earlier entry point is refused naming that one.
  ;;
  ;; curl-easy-setopt-long : Natural Integer Integer -> Integer
  ;; curl-easy-setopt-pointer : Natural Integer Natural -> Integer
  ;; curl-easy-setopt-off-t : Natural Integer Integer -> Integer
  ;; HANDLE, an option's id from curl-easy-option, and a long, a pointer
  ;; or a curl_off_t: the CURLcode.
  (define curl-easy-setopt-long
    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))

  (define curl-easy-setopt-pointer
    (load-step (bind-variadic "curl_easy_setopt" (uptr int uptr) int info)))

  (define curl-easy-setopt-off-t
    (load-step (bind-variadic "curl_easy_setopt" (uptr int integer-64) int info)))

  ;; CURLcode curl_easy_getinfo(CURL *handle, CURLINFO info, ...), variadic
  ;; after info: its one argument there is where to write the answer.
  ;; curl-easy-getinfo : Natural Integer Natural -> Integer
  ;; HANDLE, a CURLINFO_* code from (curl private constants), and the
  ;; address libcurl writes the answer to: the CURLcode.
  (define curl-easy-getinfo
    (load-step (bind-variadic "curl_easy_getinfo" (uptr int uptr) int info)))

  ;; --- the counted wrappers, exported: step 7 counts its handle through them ------

  ;; curl-easy-init : -> Natural
  ;; A fresh easy handle's address, counted as easy; 0, counted as
  ;; nothing, when libcurl could make none.
  (define (curl-easy-init)
    (let ((easy (raw-curl-easy-init)))
      (unless (eqv? easy 0)
        (count-up! 'easy))
      easy))

  ;; curl-easy-cleanup : Positive-Integer -> Void
  ;; Frees the easy handle EASY, counting it down first: a count already
  ;; at zero raises there, before C, as a double free.
  (define (curl-easy-cleanup easy)
    (count-down! 'easy)
    (raw-curl-easy-cleanup easy))

  ;; curl-url : -> Natural
  ;; A fresh CURLU handle's address, counted as url; 0, counted as
  ;; nothing, when libcurl could make none.
  (define (curl-url)
    (let ((handle (raw-curl-url)))
      (unless (eqv? handle 0)
        (count-up! 'url))
      handle))

  ;; curl-url-cleanup : Positive-Integer -> Void
  ;; Frees the CURLU handle HANDLE, counting it down first, as
  ;; curl-easy-cleanup does.
  (define (curl-url-cleanup handle)
    (count-down! 'url)
    (raw-curl-url-cleanup handle))

  ;; curl-url-get : Positive-Integer Integer Natural -> (Values Integer Natural)
  ;; The CURLUcode, and the address of the string curl_url_get wrote for
  ;; PART of HANDLE: counted as curl-string, for curl-free; 0 unless the
  ;; code is CURLUE_OK. The slot it writes through is a counted block,
  ;; freed before this returns.
  (define (curl-url-get handle part flags)
    (let ((slot (foreign-block (foreign-sizeof 'void*))))
      (dynamic-wind
        (lambda () #f)
        (lambda ()
          (let ((code (raw-curl-url-get handle part slot flags)))
            (if (eqv? code curlue-ok)
                (let ((address (foreign-ref 'uptr slot 0)))
                  (unless (eqv? address 0)
                    (count-up! 'curl-string))
                  (values code address))
                (values code 0))))
        (lambda () (free-foreign-block! slot)))))

  ;; curl-free : Positive-Integer -> Void
  ;; Frees ADDRESS, a string curl-url-get answered, counting it down first.
  (define (curl-free address)
    (count-down! 'curl-string)
    (raw-curl-free address))

  ;; curl-url-strerror : Integer -> (U String #f)
  ;; libcurl's text for the CURLUcode CODE, copied; #f for NULL.
  (define (curl-url-strerror code)
    (c-text (raw-curl-url-strerror code)))


  ;; --- 7. the two API probes, then check-apis --------------------------------------------

  ;; Whether the options API knows URL. A boolean, never the pointer:
  ;; check-apis refuses anything else, since NULL as 0 would be true.
  (define option-found?
    (load-step (not (zero? (curl-easy-option-by-name "URL")))))

  ;; What curl_easy_header answers on a fresh handle: CURLHE_NOHEADERS
  ;; with the API built in, CURLHE_NOT_BUILT_IN without (ADR-0003). hout
  ;; points at a counted block of our own, freed with the handle, so the
  ;; counts are zero once the load returns.
  (define header-code
    (load-step
     (let ((easy (curl-easy-init)))
       (when (zero? easy)
         (refuse 'load-failed libcurl-path libcurl-source info "curl_easy_init returned NULL"
                 "curl_easy_init returned NULL, so the header API could not be probed; name another libcurl with CHEZ_CURL_LIBCURL"))
       (let* ((hout (foreign-block (foreign-sizeof 'void*)))
              (code (curl-easy-header easy "Content-Type" 0 curlh-header -1 hout)))
         (free-foreign-block! hout)
         (curl-easy-cleanup easy)
         code))))

  (define apis-checked
    (load-step
     (check-apis option-found? header-code libcurl-path libcurl-source info)))

  ;; --- the exports ---------------------------------------------------------------------------

  ;; loaded-libcurl : -> Libcurl-Info
  ;; The libcurl this process loaded and accepted. Reaching this binding
  ;; runs the load above, once; a refusal raises from there instead, at
  ;; this reference and every later one.
  (define (loaded-libcurl) info)

  ;; loaded-protocols : -> (Listof String)
  ;; The protocols the loaded libcurl lists, as curl_version_info gives
  ;; them, in its order: lower-case scheme names, http and https among them.
  ;; Private: (curl) does not export it.
  (define (loaded-protocols) protocol-list)

  ;; curl-easy-option : String -> (U #f (Pairof Integer Natural))
  ;; The option NAME (without CURLOPT_) as the loaded libcurl knows it: its
  ;; id and its CURLOT type code, read through curl-easyoption from what
  ;; curl_easy_option_by_name answers; #f when that is NULL, a name this
  ;; libcurl does not know. Raw codes: (curl private constants)'s
  ;; curlot-types names them. Ids come from here alone, never from Scheme
  ;; (ADR-0001, decision 2).
  (define (curl-easy-option name)
    (let ((address (curl-easy-option-by-name name)))
      (and (not (zero? address))
           (let ((option (make-ftype-pointer curl-easyoption address)))
             (cons (ftype-ref curl-easyoption (id) option)
                   (ftype-ref curl-easyoption (type) option)))))))
