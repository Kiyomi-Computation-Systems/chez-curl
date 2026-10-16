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
;;;   3. version  curl_version_info, the first entry point bound, and its
;;;               curl_version_info_data, read into the libcurl-info record
;;;   4. check    the floor and CURL_VERSION_SSL: check-version
;;;   5. init     curl_global_init, exactly once
;;;   6. bind     every other entry point, eagerly
;;;   7. probe    the options API and the header API, then check-apis
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
  (export loaded-libcurl)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) define-ftype ftype-ref make-ftype-pointer
                foreign-procedure foreign-entry? load-shared-object
                foreign-alloc foreign-free foreign-ref foreign-sizeof
                format format-condition? display-condition
                getenv machine-type file-regular?)
          (curl private load-state)
          (curl private libcurl-info)
          (curl private conditions)
          (curl private constants)
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

  ;; c-string : Natural -> (U String #f)
  ;; The NUL-terminated UTF-8 string at ADDRESS, copied; #f for NULL.
  (define (c-string address)
    (and (not (zero? address))
         (let ((n (let count ((n 0))
                    (if (zero? (foreign-ref 'unsigned-8 address n)) n (count (+ n 1))))))
           (let ((bytes (make-bytevector n)))
             (do ((i 0 (+ i 1))) ((= i n))
               (bytevector-u8-set! bytes i (foreign-ref 'unsigned-8 address i)))
             (utf8->string bytes)))))

  ;; curl_version_info_data, curl/curl.h, through the last field
  ;; CURLVERSION_TENTH fills, gsasl_version: the age asked for at the floor
  ;; (constants.sls). C's padding and alignment apply, as in a C struct.
  ;; Slice 4 checks the offsets against the headers (ADR-0001, decision 4).
  ;; features is an int in C. It is read as unsigned, the same size: a bit
  ;; 31 in a later libcurl would make an int negative, and feature-names
  ;; takes a natural number.
  (define-ftype curl-version-info-data
    (struct
      (age int)
      (version uptr)
      (version-num unsigned-int)
      (host uptr)
      (features unsigned-int)
      (ssl-version uptr)
      (ssl-version-num long)
      (libz-version uptr)
      (protocols uptr)
      (ares uptr)
      (ares-num int)
      (libidn uptr)
      (iconv-ver-num int)
      (libssh-version uptr)
      (brotli-ver-num unsigned-int)
      (brotli-version uptr)
      (nghttp2-ver-num unsigned-int)
      (nghttp2-version uptr)
      (quic-version uptr)
      (cainfo uptr)
      (capath uptr)
      (zstd-ver-num unsigned-int)
      (zstd-version uptr)
      (hyper-version uptr)
      (gsasl-version uptr)))

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

  ;; The record's version is a string, and the floor's refusal names it.
  (define version-string
    (load-step
     (or (c-string (ftype-ref curl-version-info-data (version) version-data))
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
        (c-string (ftype-ref curl-version-info-data (ssl-version) version-data))
        (c-string (ftype-ref curl-version-info-data (host) version-data))))))

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
  (define curl-easy-init (load-step (bind-required "curl_easy_init" () uptr info)))

  ;; CURLHcode curl_easy_header(CURL *easy, const char *name, size_t index,
  ;;                            unsigned int origin, int request,
  ;;                            struct curl_header **hout)
  (define curl-easy-header
    (load-step
     (bind-required "curl_easy_header" (uptr string size_t unsigned-int int uptr) int info)))

  ;; void curl_easy_cleanup(CURL *easy)
  (define curl-easy-cleanup (load-step (bind-required "curl_easy_cleanup" (uptr) void info)))

  ;; --- 7. the two API probes, then check-apis --------------------------------------------

  ;; Whether the options API knows URL. A boolean, never the pointer:
  ;; check-apis refuses anything else, since NULL as 0 would be true.
  (define option-found?
    (load-step (not (zero? (curl-easy-option-by-name "URL")))))

  ;; What curl_easy_header answers on a fresh handle: CURLHE_NOHEADERS
  ;; with the API built in, CURLHE_NOT_BUILT_IN without (ADR-0003). hout
  ;; points at a slot of our own, freed with the handle.
  (define header-code
    (load-step
     (let ((easy (curl-easy-init)))
       (when (zero? easy)
         (refuse 'load-failed libcurl-path libcurl-source info "curl_easy_init returned NULL"
                 "curl_easy_init returned NULL, so the header API could not be probed; name another libcurl with CHEZ_CURL_LIBCURL"))
       (let* ((hout (foreign-alloc (foreign-sizeof 'void*)))
              (code (curl-easy-header easy "Content-Type" 0 curlh-header -1 hout)))
         (foreign-free hout)
         (curl-easy-cleanup easy)
         code))))

  (define apis-checked
    (load-step
     (check-apis option-found? header-code libcurl-path libcurl-source info)))

  ;; --- the export ---------------------------------------------------------------------------

  ;; loaded-libcurl : -> Libcurl-Info
  ;; The libcurl this process loaded and accepted. Reaching this binding
  ;; runs the load above, once; a refusal raises from there instead, at
  ;; this reference and every later one.
  (define (loaded-libcurl) info))
