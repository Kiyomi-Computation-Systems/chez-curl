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
;;;               list, which loaded-protocols answers. Then the file the
;;;               kernel maps curl_version_info's entry point from, which
;;;               loaded-libcurl-file answers, and whether that file holds
;;;               Guix's patch's literal, which loaded-libcurl-patched?
;;;               answers
;;;   4. check    the floor and CURL_VERSION_SSL: check-version
;;;   5. init     SSL_CERT_FILE and SSL_CERT_DIR, read and recorded, which
;;;               loaded-ca-variables answers; then curl_global_init, exactly
;;;               once; then the TLS backend it put in use, which
;;;               loaded-tls-backend answers, the features word it then
;;;               reports, which loaded-features answers, and whether this is
;;;               macOS, loaded-on-macos?
;;;   6. bind     every other entry point, eagerly
;;;   7. probe    the options API and the header API, then check-apis; then
;;;               mime, which refuses no load: loaded-mime-probe answers what
;;;               it found, and loaded-mime? whether a multipart body can go
;;;
;;; An interrupt that escapes, an engine's expiry, a timer or keyboard
;;; handler that invokes a continuation, may land at any safe point. So
;;; making a native object and recording it where its free will find it, its
;;; count and the variable an after thunk reads, happen in one critical
;;; section, with no safe point between, and so does freeing it: each counted
;;; wrapper's call and count share a critical-section, and each extent is a
;;; dynamic-wind whose critical? argument is #t, which runs its before thunk,
;;; and its after thunk, in one critical section with the record that the
;;; extent was entered, or left (M2 fix round 2).
;;;
;;; Every native object it makes is counted, in (curl private counters):
;;; each foreign block, through (curl private memory), each easy handle,
;;; each CURLU handle, each string curl_url_get hands back, each string
;;; list curl_slist_append starts, and each mime curl_mime_init makes
;;; (M8 slice 3), its parts the mime's own. The load's own, the header
;;; probe's handle and its slot, and the mime probe's slots and strings, are
;;; freed before it returns, and the form post and the mime that probe makes
;;; are never counted, so every count is zero after it.
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
;;; one back as bytes. Header strings and the user agent are the one
;;; exception (ADR-0001, amended 2026-10-23): call-with-latin-1-c-string
;;; hands C one byte per char, refusing U+0000 and any char above U+00FF.
;;; A blob the hatch sets goes through call-with-curl-blob: a counted copy
;;; of its bytes, and a counted struct curl_blob, filled with ftype-set!,
;;; which check-seam lets this library alone import, flagged
;;; CURL_BLOB_COPY, so libcurl copies the bytes as setopt runs and both
;;; blocks are freed once it returns (ADR-0009, decision 4; the M4 plan,
;;; section 3.7).
;;;
;;; The transfer's bindings (M2 plan, section 5.2) are step 6's:
;;; curl_easy_strerror, curl_easy_nextheader, curl_slist_append and
;;; curl_slist_free_all, plain. Their counted wrappers count a string list
;;; as slist while it is not NULL. So are the engine's, the multi interface
;;; (M3 plan, section 3.2): curl_multi_poll, curl_multi_perform,
;;; curl_multi_remove_handle and curl_multi_cleanup, which can block, through
;;; bind-blocking, whose template carries __collect_safe (ADR-0013, accepted
;;; 2026-10-24); the rest plain. A multi handle is counted as multi.
;;; curl_multi_setopt is bound once, for a long, through bind-variadic,
;;; last, with the easy setopts (ADR-0019; ADR-0001, amended 2026-10-25).
;;; curl_easy_pause, the engine's resume (the M6 plan, section 3.4), is
;;; bound through bind-blocking too: it never waits on the network, but it
;;; hands what it held to the callables before it returns, decoding it on
;;; the way, and its replay of a gzip body ran 21.647 ms, holding another
;;; thread's collection while it ran, when the call was plain (the plan's
;;; section 4.1, as measured).
;;;
;;; A multipart body's (ADR-0039, amended; the M8 plan, section 3.4), step 6's
;;; too: curl_mime_init, curl_mime_free, curl_mime_addpart, curl_mime_name,
;;; curl_mime_data, curl_mime_filename, curl_mime_type and curl_formfree,
;;; plain; curl_mime_filedata, which stats its path, and on 7.85.0 and 8.5.0
;;; accesses it, through bind-blocking; and curl_formadd, variadic, bound
;;; once, last, for the load's probe and tests/test-variadic.sps alone. Every
;;; string they take is a counted copy, call-with-c-string's, and the data a
;;; counted copy, call-with-foreign-bytes': libcurl copies both as the call
;;; runs. A mime is counted as mime and owned by its maker's thread, in the
;;; critical section that makes it; curl-mime-add-part! adds a whole part to
;;; one, checking its owner, so no part's address leaves this library.
;;;
;;; The cookie jar's (ADR-0035; the M7 plan, section 3.5): curl_share_init
;;; and curl_share_cleanup, plain, a share counted as share; and
;;; curl_share_setopt, variadic, bound once, for an int, through
;;; bind-variadic, last, with the other variadics: libcurl reads its value
;;; for SHARE and UNSHARE with va_arg(param, int), 7.85.0 lib/share.c:74 and
;;; :127, 8.20.0 lib/curl_share.c:215 and :283, 8.23.0 :218 and :286, Apple's
;;; 8.7.1 lib/share.c:76 and :141 (read in source). CURLINFO_COOKIELIST's
;;; answer, a struct curl_slist libcurl made, is counted as slist and owned
;;; by the thread that read it, in the critical section of the call, and
;;; walked by (curl private layouts)' curl-slist.
;;;
;;; Each handle's thread (ADR-0012, decision 3; M3 plan, section 3.3). Each
;;; easy, multi, share, mime and CURLU handle and each string list native makes is
;;; recorded with its kind and the thread that made it, in the critical
;;; section that counts it, and forgotten in the one that frees it. Every
;;; exported procedure that takes one checks it first, by check-owner: a
;;; handle another thread made raises &curl-wrong-thread, carrying who, the
;;; maker's get-thread-id and the caller's, and an address that holds no
;;; live handle of that kind, an assertion violation, each before C sees it.
;;; curl_multi_wakeup alone may be called from any thread, on a live multi
;;; handle; the engine that owns the handle keeps it alive while a caller
;;; may wake it. The header probe's handle is checked as every other is.
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
  (export loaded-libcurl loaded-libcurl-file loaded-libcurl-patched? loaded-ca-variables
          loaded-tls-backend loaded-features loaded-on-macos?
          curl-easy-option
          curl-easy-init curl-easy-cleanup
          curl-easy-setopt-long curl-easy-setopt-pointer curl-easy-setopt-off-t
          curl-easy-getinfo curl-easy-getinfo-long curl-easy-getinfo-off-t curl-easy-getinfo-string
          copy-foreign->bytevector! copy-bytevector->foreign!
          call-with-c-string call-with-latin-1-c-string call-with-foreign-bytes
          call-with-curl-blob c-string->bytevector
          curl-url curl-url-cleanup curl-url-set curl-url-get curl-url-strerror
          curl-free loaded-protocols
          curl-easy-strerror curl-easy-nextheader curl-header-bytes
          curl-slist-append curl-slist-free-all
          curl-multi-init curl-multi-cleanup curl-multi-add-handle curl-multi-remove-handle
          curl-multi-perform curl-multi-poll curl-multi-wakeup curl-multi-info-read
          curl-multi-strerror curl-multi-setopt-long
          curl-easy-pause
          curl-share-init curl-share-setopt-int curl-share-cleanup
          curl-easy-getinfo-cookielist curl-slist-strings
          loaded-mime-probe loaded-mime? curl-mime-init curl-mime-free curl-mime-add-part!
          curl-formadd-code)
  (import (curl private require-threaded)
          (except (rnrs) dynamic-wind)
          (only (chezscheme) critical-section dynamic-wind ftype-ref ftype-set! ftype-sizeof
                make-ftype-pointer foreign-procedure foreign-entry foreign-entry? load-shared-object
                foreign-ref foreign-sizeof
                format format-condition? display-condition
                getenv machine-type file-regular? get-thread-id make-mutex with-mutex)
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

  ;; --- each handle's thread (ADR-0012, decision 3) --------------------------------

  ;; locked : Mutex (-> Any) -> Any
  ;; THUNK's value, run holding LOCK, in a critical section. Chez's
  ;; with-mutex is a dynamic-wind whose before thunk takes the mutex, so an
  ;; interrupt that escapes between the take and the wind would leave it
  ;; held. Every mutex here is held through locked, and no hold waits.
  (define (locked lock thunk)
    (critical-section (with-mutex lock (thunk))))

  ;; The live handles native made, by address, each with its kind, easy,
  ;; multi, share, mime, url or slist, and the get-thread-id of the thread that
  ;; made it:
  ;; (KIND . THREAD). Read and written under the mutex.
  (define owners (make-eqv-hashtable))
  (define owners-lock (make-mutex))

  ;; own! : Positive-Integer Symbol -> Void
  ;; HANDLE recorded as a live KIND handle this thread made. Its caller
  ;; holds the critical section that counts it.
  (define (own! handle kind)
    (let ((thread (get-thread-id)))
      (locked owners-lock (lambda () (hashtable-set! owners handle (cons kind thread))))))

  ;; disown! : Positive-Integer -> Void
  ;; HANDLE forgotten, in its caller's critical section that frees it.
  (define (disown! handle)
    (locked owners-lock (lambda () (hashtable-delete! owners handle))))

  ;; live-handle : Symbol Any Symbol -> (Pairof Symbol Integer)
  ;; HANDLE's record, when it is a live KIND handle native made; otherwise
  ;; an assertion violation from WHO, before C sees it: an address freed
  ;; already, never made here, or made as another kind.
  (define (live-handle who handle kind)
    (let ((entry (locked owners-lock (lambda () (hashtable-ref owners handle #f)))))
      (unless (and entry (eq? (car entry) kind))
        (assertion-violation who
                             (string-append "not a live " (symbol->string kind)
                                            " handle chez-curl made")
                             handle))
      entry))

  ;; check-owner : Symbol Any Symbol -> Void
  ;; Returns when HANDLE is a live KIND handle this thread made. One another
  ;; thread made raises &curl-wrong-thread from WHO, carrying WHO, the
  ;; maker's get-thread-id and this thread's (ADR-0012); anything else is
  ;; live-handle's assertion violation. Both before C sees it.
  (define (check-owner who handle kind)
    (let* ((entry (live-handle who handle kind))
           (thread (get-thread-id)))
      (unless (eqv? (cdr entry) thread)
        (raise (condition (make-curl-wrong-thread who (cdr entry) thread)
                          (make-who-condition who)
                          (make-message-condition
                           "a handle is used only on the thread that made it: an engine's on the engine's own thread (ADR-0012)")
                          (make-irritants-condition (list handle)))))))

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

  ;; (bind-blocking ENTRY (ARG-TYPE ...) RESULT-TYPE LIBRARY): ENTRY, a C
  ;; function that can block, bound with foreign-procedure and
  ;; __collect_safe, after required-entry has found it (ADR-0013, decision
  ;; 1). The convention is the template's own, never a use's: a thread
  ;; blocked in a plain call stays active, and every other thread's
  ;; collection waits for it. tests/foreign-conventions.sls holds the rows
  ;; of the multi calls that can block to this binder.
  (define-syntax bind-blocking
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (required-entry entry library)
         (foreign-procedure __collect_safe entry (arg ...) result)))))

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

  ;; refuse-nul : Symbol String -> Nothing
  ;; WHO's refusal of STRING, which holds U+0000.
  (define (refuse-nul who string)
    (raise (condition (make-curl-embedded-nul string)
                      (make-who-condition who)
                      (make-message-condition "a string C reads ends at its first NUL, and this one holds one"))))

  ;; call-with-c-bytes : Symbol String Bytevector (Positive-Integer -> Any) -> Any
  ;; PROC's answer, PROC given the address of a counted block holding
  ;; BYTES, which end in the NUL, the copy of STRING that WHO makes. The
  ;; block is freed once PROC returns, raises or escapes, and re-entering
  ;; PROC through a continuation after that raises an assertion violation
  ;; from WHO, so the address is never used after.
  (define (call-with-c-bytes who string bytes proc)
    (let ((n (bytevector-length bytes))
          (block #f)
          (freed #f))
      (dynamic-wind #t
        (lambda ()
          (when freed
            (assertion-violation who "re-entered after its string was freed" string))
          (set! block (foreign-block n)))
        (lambda ()
          (copy-bytevector->foreign! bytes 0 block n)
          (proc block))
        (lambda ()
          (set! freed #t)
          (free-foreign-block! block)))))

  ;; call-with-foreign-bytes : Bytevector (Positive-Integer -> Any) -> Any
  ;; PROC's answer, PROC given the address of a counted block holding
  ;; BYTES, freed once PROC returns, raises or escapes, as call-with-c-bytes
  ;; frees it: for a body libcurl copies when it is set (the M4 plan,
  ;; section 3.2). The address is never NULL: an empty BYTES gets a block
  ;; of one byte, 0, which libcurl copies none of. BYTES is read once, by
  ;; the checked copy, so no check comes between a read and a use.
  (define (call-with-foreign-bytes bytes proc)
    (unless (bytevector? bytes)
      (assertion-violation 'call-with-foreign-bytes "not a bytevector" bytes))
    (unless (procedure? proc)
      (assertion-violation 'call-with-foreign-bytes "not a procedure" proc))
    (call-with-c-bytes 'call-with-foreign-bytes bytes
                       (if (= (bytevector-length bytes) 0) (make-bytevector 1 0) bytes)
                       proc))

  ;; call-with-curl-blob : Bytevector (Positive-Integer -> Any) -> Any
  ;; PROC's answer, PROC given the address of a struct curl_blob, in a
  ;; counted block: its data the address of a counted copy of BYTES, which
  ;; call-with-foreign-bytes makes, never NULL; its len BYTES' length; its
  ;; flags CURL_BLOB_COPY. libcurl copies the bytes when a blob option is
  ;; set (ADR-0009; measured on five Linux libcurls, the M4 plan, section
  ;; 7.1), so both blocks are freed once PROC returns, raises or escapes,
  ;; as call-with-c-bytes frees its block, and PROC is never re-entered
  ;; after.
  (define (call-with-curl-blob bytes proc)
    (unless (bytevector? bytes)
      (assertion-violation 'call-with-curl-blob "not a bytevector" bytes))
    (unless (procedure? proc)
      (assertion-violation 'call-with-curl-blob "not a procedure" proc))
    (call-with-foreign-bytes bytes
      (lambda (data)
        (call-with-c-bytes 'call-with-curl-blob bytes (make-bytevector (ftype-sizeof curl-blob) 0)
          (lambda (address)
            (let ((blob (make-ftype-pointer curl-blob address)))
              (ftype-set! curl-blob (data) blob data)
              (ftype-set! curl-blob (len) blob (bytevector-length bytes))
              (ftype-set! curl-blob (flags) blob curl-blob-copy)
              (proc address)))))))

  ;; call-with-c-string : String (Positive-Integer -> Any) -> Any
  ;; PROC's answer, PROC given the address of STRING as C reads it: its
  ;; UTF-8 bytes and a NUL, in a counted block freed once PROC returns,
  ;; raises or escapes. A STRING that holds U+0000 raises
  ;; &curl-embedded-nul, before anything is allocated: C would read the
  ;; NUL as the string's end, as Chez's string type does without a word.
  ;; STRING is the caller's, and mutable, so it is copied first, and the
  ;; copy alone is checked and encoded: a check of STRING, then an encoding
  ;; of it, would let another thread change it between the two.
  ;; Re-entering PROC through a continuation, once the block is freed,
  ;; raises an assertion violation, so the address is never used after.
  (define (call-with-c-string string proc)
    (unless (string? string)
      (assertion-violation 'call-with-c-string "not a string" string))
    (unless (procedure? proc)
      (assertion-violation 'call-with-c-string "not a procedure" proc))
    (let ((copy (string-copy string)))
      (when (holds-nul? copy)
        (refuse-nul 'call-with-c-string copy))
      (let* ((utf8 (string->utf8 copy))
             (n (+ (bytevector-length utf8) 1))
             (bytes (make-bytevector n 0)))
        (bytevector-copy! utf8 0 bytes 0 (- n 1))
        (call-with-c-bytes 'call-with-c-string copy bytes proc))))

  ;; call-with-latin-1-c-string : String (Positive-Integer -> Any) -> Any
  ;; call-with-c-string's twin for header strings and the user agent
  ;; (ADR-0001, amended 2026-10-23): PROC given the address of STRING as one
  ;; byte per char, U+00nn as the byte nn, and a NUL, in a counted block
  ;; freed once PROC returns, raises or escapes. STRING is scanned left to
  ;; right, before anything is allocated, and its first offending char
  ;; decides: U+0000 raises &curl-embedded-nul, and a char above U+00FF,
  ;; which has no byte, an assertion violation. A request's validation
  ;; refuses both before this is reached; this is the backstop. As
  ;; call-with-c-string does, it copies STRING first, and checks and
  ;; encodes the copy alone. Re-entering PROC through a continuation, once
  ;; the block is freed, raises an assertion violation.
  (define (call-with-latin-1-c-string string proc)
    (unless (string? string)
      (assertion-violation 'call-with-latin-1-c-string "not a string" string))
    (unless (procedure? proc)
      (assertion-violation 'call-with-latin-1-c-string "not a procedure" proc))
    (let* ((string (string-copy string))
           (n (string-length string)))
      (let scan ((i 0))
        (when (< i n)
          (let ((code (char->integer (string-ref string i))))
            (cond ((= code 0) (refuse-nul 'call-with-latin-1-c-string string))
                  ((> code 255)
                   (assertion-violation 'call-with-latin-1-c-string
                                        "a char above U+00FF has no Latin-1 byte" string))
                  (else (scan (+ i 1)))))))
      (let ((bytes (make-bytevector (+ n 1) 0)))
        (let fill ((i 0))
          (when (< i n)
            (bytevector-u8-set! bytes i (char->integer (string-ref string i)))
            (fill (+ i 1))))
        (call-with-c-bytes 'call-with-latin-1-c-string string bytes proc))))

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

  ;; The file the kernel maps the libcurl native calls from: the pathname of
  ;; the /proc/self/maps line that holds curl_version_info's entry point,
  ;; every symlink resolved, through discovery's mapped-file; #f off Linux,
  ;; or when the maps cannot be read. foreign-entry answers the address
  ;; native's own binding calls, the most recently loaded object's. Whether
  ;; a libcurl is Guix's is read from this file, not from ADR-0002's world,
  ;; which is libc's: spike E1's Chez, built on Ubuntu, loads Guix's 8.20.0,
  ;; which still writes SSL_CERT_FILE over a CA file (ADR-0024, amended
  ;; 2026-10-26).
  (define libcurl-file
    (load-step (mapped-file (maps-text) (foreign-entry "curl_version_info"))))

  ;; Whether the libcurl's file, the mapped one, or the path as loaded where
  ;; none was read, holds the literal SSL_CERT_FILE: Guix's patch's own
  ;; string, which Guix's 8.20.0 and 8.6.0 hold once each and none of six
  ;; stock builds holds (ADR-0024, amended 2026-10-26: the key). So a Guix
  ;; libcurl copied out of the store is still Guix's. Read once, whole; a
  ;; file that cannot be read, Apple's in the dyld cache among them, holds
  ;; nothing.
  (define libcurl-patched
    (load-step
     (let ((bytes (guard (e (#t #f))
                    (call-with-port (open-file-input-port (or libcurl-file libcurl-path))
                      get-bytevector-all))))
       (and (bytevector? bytes) (bytes-hold? bytes (string->utf8 "SSL_CERT_FILE"))))))

  ;; --- 4. the floor and SSL ----------------------------------------------------------

  (define version-checked
    (load-step
     (check-version (libcurl-info-version info) (libcurl-info-version-number info)
                    (libcurl-info-features info) libcurl-path libcurl-source info)))

  ;; --- 5. curl_global_init, exactly once ---------------------------------------------

  ;; CURLcode curl_global_init(long flags)
  (define curl-global-init (load-step (bind-required "curl_global_init" (long) int info)))

  ;; SSL_CERT_FILE and SSL_CERT_DIR, each with its value, or #f when it is
  ;; unset or empty, read immediately before curl_global_init below: Guix's
  ;; patch reads both there, through curl_getenv, which answers an empty
  ;; value as NULL, and never again, so a variable set after the load
  ;; changes no transfer, and one unset after it still does (ADR-0024,
  ;; amended 2026-10-26). Another library's earlier curl_global_init in
  ;; this process would have read them first, and libcurl's source makes
  ;; this one a count alone: the record could then differ, unseen.
  (define ca-variables
    (load-step
     (map (lambda (name)
            (let ((value (getenv name)))
              (cons name (and value (not (string=? value "")) value))))
          '("SSL_CERT_FILE" "SSL_CERT_DIR"))))

  (define global-initialized
    (load-step
     (let ((code (curl-global-init curl-global-default)))
       (unless (= code curle-ok)
         (refuse 'load-failed libcurl-path libcurl-source info
                 (string-append "curl_global_init returned " (number->string code))
                 "curl_global_init failed, so this libcurl cannot be used; name another with CHEZ_CURL_LIBCURL"))
       #t)))

  ;; The TLS backend in use, read from curl_version_info after the init,
  ;; through discovery's backend-in-use: before it, a MultiSSL libcurl
  ;; names its first backend whatever the init picks, so the record step 3
  ;; built, info, says SecureTransport on Apple's 8.7.1, where the init
  ;; puts LibreSSL in use (ADR-0024, amended 2026-10-27). curl_version_info
  ;; writes the names into a buffer of its own, so it is called again; #f
  ;; when it answers NULL or no one backend is bare.
  ;;
  ;; The same call answers the features word, after-init's cdr: a MultiSSL
  ;; libcurl computes the word at each call from the backend in use, and
  ;; before the init that is its selector, which supports nothing, so the
  ;; bits a backend sets read clear in info: CURL_VERSION_HTTPS_PROXY among
  ;; them, on Apple's 8.7.1, whose init puts a backend that supports it in
  ;; use (8.7.1 lib/version.c:424-428 and 671-680, lib/vtls/vtls.c:1306-1308;
  ;; the Mac's run of M7 slice 3). info keeps the word it read; step 3's
  ;; word stands where the call answers NULL.
  (define after-init
    (load-step
     (let ((address (curl-version-info curlversion-tenth)))
       (if (zero? address)
           (cons #f (libcurl-info-features info))
           (let ((data (make-ftype-pointer curl-version-info-data address)))
             (cons (backend-in-use (c-text (ftype-ref curl-version-info-data (ssl-version) data)))
                   (ftype-ref curl-version-info-data (features) data)))))))
  (define tls-backend (car after-init))
  (define features-after-init (cdr after-init))

  ;; Whether this is macOS: Chez's machine types for it end in osx.
  (define on-macos
    (let* ((name (symbol->string (machine-type))) (n (string-length name)))
      (and (>= n 3) (string=? (substring name (- n 3) n) "osx"))))

  ;; --- 6. every other entry point, eagerly ---------------------------------------------

  ;; const struct curl_easyoption *curl_easy_option_by_name(const char *name)
  (define curl-easy-option-by-name
    (load-step (bind-required "curl_easy_option_by_name" (string) uptr info)))

  ;; CURL *curl_easy_init(void)
  (define raw-curl-easy-init (load-step (bind-required "curl_easy_init" () uptr info)))

  ;; CURLHcode curl_easy_header(CURL *easy, const char *name, size_t index,
  ;;                            unsigned int origin, int request,
  ;;                            struct curl_header **hout)
  (define raw-curl-easy-header
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
  ;; libcurl keeps no pointer to the string: "does not have to keep content
  ;; around after a successful call" (curl_url_set(3), 7.85.0).
  (define raw-curl-url-set
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

  ;; The transfer's (M2 plan, section 5.2). curl_easy_nextheader is
  ;; 7.83.0, below the floor; the rest are older still. All required.

  ;; const char *curl_easy_strerror(CURLcode error)
  (define raw-curl-easy-strerror
    (load-step (bind-required "curl_easy_strerror" (int) uptr info)))

  ;; struct curl_header *curl_easy_nextheader(CURL *curl, unsigned int origin,
  ;;                                          int request, struct curl_header *prev)
  (define raw-curl-easy-nextheader
    (load-step (bind-required "curl_easy_nextheader" (uptr unsigned-int int uptr) uptr info)))

  ;; struct curl_slist *curl_slist_append(struct curl_slist *list, const char *data)
  (define raw-curl-slist-append
    (load-step (bind-required "curl_slist_append" (uptr uptr) uptr info)))

  ;; void curl_slist_free_all(struct curl_slist *list)
  (define raw-curl-slist-free-all
    (load-step (bind-required "curl_slist_free_all" (uptr) void info)))

  ;; The engine's (M3 plan, section 3.2): the multi interface, all below the
  ;; floor, curl_multi_poll 7.66.0 and curl_multi_wakeup 7.68.0, and all
  ;; required. The four that can block are __collect_safe, through
  ;; bind-blocking (ADR-0013, accepted 2026-10-24).

  ;; CURLM *curl_multi_init(void)
  (define raw-curl-multi-init (load-step (bind-required "curl_multi_init" () uptr info)))

  ;; CURLMcode curl_multi_cleanup(CURLM *multi_handle)
  (define raw-curl-multi-cleanup
    (load-step (bind-blocking "curl_multi_cleanup" (uptr) int info)))

  ;; CURLMcode curl_multi_add_handle(CURLM *multi_handle, CURL *curl_handle)
  (define raw-curl-multi-add-handle
    (load-step (bind-required "curl_multi_add_handle" (uptr uptr) int info)))

  ;; CURLMcode curl_multi_remove_handle(CURLM *multi_handle, CURL *curl_handle)
  (define raw-curl-multi-remove-handle
    (load-step (bind-blocking "curl_multi_remove_handle" (uptr uptr) int info)))

  ;; CURLMcode curl_multi_perform(CURLM *multi_handle, int *running_handles)
  (define raw-curl-multi-perform
    (load-step (bind-blocking "curl_multi_perform" (uptr uptr) int info)))

  ;; CURLMcode curl_multi_poll(CURLM *multi_handle, struct curl_waitfd extra_fds[],
  ;;                           unsigned int extra_nfds, int timeout_ms, int *ret)
  (define raw-curl-multi-poll
    (load-step (bind-blocking "curl_multi_poll" (uptr uptr unsigned-int int uptr) int info)))

  ;; CURLMcode curl_multi_wakeup(CURLM *multi_handle)
  (define raw-curl-multi-wakeup
    (load-step (bind-required "curl_multi_wakeup" (uptr) int info)))

  ;; CURLMsg *curl_multi_info_read(CURLM *multi_handle, int *msgs_in_queue)
  (define raw-curl-multi-info-read
    (load-step (bind-required "curl_multi_info_read" (uptr uptr) uptr info)))

  ;; const char *curl_multi_strerror(CURLMcode)
  (define raw-curl-multi-strerror
    (load-step (bind-required "curl_multi_strerror" (int) uptr info)))

  ;; CURLcode curl_easy_pause(CURL *handle, int action), 7.18.0: the
  ;; engine's resume, __collect_safe, since the callables run inside it
  ;; (the M6 plan, section 3.4).
  (define raw-curl-easy-pause
    (load-step (bind-blocking "curl_easy_pause" (uptr int) int info)))

  ;; The cookie jar's (ADR-0035): the share interface, 7.10.3, below the
  ;; floor, and required. Neither call waits on anything: plain.

  ;; CURLSH *curl_share_init(void)
  (define raw-curl-share-init (load-step (bind-required "curl_share_init" () uptr info)))

  ;; CURLSHcode curl_share_cleanup(CURLSH *share)
  (define raw-curl-share-cleanup
    (load-step (bind-required "curl_share_cleanup" (uptr) int info)))

  ;; A multipart body's (ADR-0039; the M8 plan, section 3.4): the mime API,
  ;; 7.56.0, and curl_formfree, below the floor, and required. Plain, but
  ;; curl_mime_filedata, which stats its path, and on 7.85.0 and 8.5.0
  ;; accesses it: a stat of a hung network mount waits, so it is
  ;; __collect_safe, through bind-blocking. None takes a Scheme string:
  ;; each is handed a counted foreign copy (ADR-0013, amended 2026-10-23).

  ;; curl_mime *curl_mime_init(CURL *easy)
  (define raw-curl-mime-init (load-step (bind-required "curl_mime_init" (uptr) uptr info)))

  ;; void curl_mime_free(curl_mime *mime)
  (define raw-curl-mime-free (load-step (bind-required "curl_mime_free" (uptr) void info)))

  ;; curl_mimepart *curl_mime_addpart(curl_mime *mime)
  (define raw-curl-mime-addpart
    (load-step (bind-required "curl_mime_addpart" (uptr) uptr info)))

  ;; CURLcode curl_mime_name(curl_mimepart *part, const char *name)
  (define raw-curl-mime-name (load-step (bind-required "curl_mime_name" (uptr uptr) int info)))

  ;; CURLcode curl_mime_data(curl_mimepart *part, const char *data, size_t datasize)
  (define raw-curl-mime-data
    (load-step (bind-required "curl_mime_data" (uptr uptr size_t) int info)))

  ;; CURLcode curl_mime_filedata(curl_mimepart *part, const char *filename)
  (define raw-curl-mime-filedata
    (load-step (bind-blocking "curl_mime_filedata" (uptr uptr) int info)))

  ;; CURLcode curl_mime_filename(curl_mimepart *part, const char *filename)
  (define raw-curl-mime-filename
    (load-step (bind-required "curl_mime_filename" (uptr uptr) int info)))

  ;; CURLcode curl_mime_type(curl_mimepart *part, const char *mimetype)
  (define raw-curl-mime-type (load-step (bind-required "curl_mime_type" (uptr uptr) int info)))

  ;; void curl_formfree(struct curl_httppost *form)
  (define raw-curl-formfree (load-step (bind-required "curl_formfree" (uptr) void info)))

  ;; CURLcode curl_easy_setopt(CURL *handle, CURLoption option, ...),
  ;; variadic after option: bound once per value type. curl_off_t is 64
  ;; bits on every platform chez-curl supports. Bound last, so a library
  ;; that lacks an earlier entry point is refused naming that one.
  ;;
  (define raw-curl-easy-setopt-long
    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))

  (define raw-curl-easy-setopt-pointer
    (load-step (bind-variadic "curl_easy_setopt" (uptr int uptr) int info)))

  (define raw-curl-easy-setopt-off-t
    (load-step (bind-variadic "curl_easy_setopt" (uptr int integer-64) int info)))

  ;; CURLcode curl_easy_getinfo(CURL *handle, CURLINFO info, ...), variadic
  ;; after info: its one argument there is where to write the answer.
  (define raw-curl-easy-getinfo
    (load-step (bind-variadic "curl_easy_getinfo" (uptr int uptr) int info)))

  ;; CURLMcode curl_multi_setopt(CURLM *multi_handle, CURLMoption option, ...),
  ;; variadic after option: bound once, for a long, the type of every option
  ;; chez-curl sets, CURLMOPT_QUICK_EXIT (ADR-0019; ADR-0001, amended
  ;; 2026-10-25).
  (define raw-curl-multi-setopt-long
    (load-step (bind-variadic "curl_multi_setopt" (uptr int long) int info)))

  ;; CURLSHcode curl_share_setopt(CURLSH *share, CURLSHoption option, ...),
  ;; variadic after option: bound once, for an int, the type libcurl reads
  ;; for SHARE and UNSHARE, va_arg(param, int) (above), the one option
  ;; chez-curl sets, CURLSHOPT_SHARE at CURL_LOCK_DATA_COOKIE (ADR-0035,
  ;; decision 1). tests/test-variadic.sps watches the value arrive by
  ;; behaviour.
  (define raw-curl-share-setopt-int
    (load-step (bind-variadic "curl_share_setopt" (uptr int int) int info)))

  ;; CURLFORMcode curl_formadd(struct curl_httppost **httppost,
  ;;                           struct curl_httppost **last_post, ...),
  ;; variadic after last_post: bound once, for the one call the load's mime
  ;; probe makes, and tests/test-variadic.sps through curl-formadd-code:
  ;; an option, a string, an option, a string, then CURLFORM_END, each
  ;; option an int, as libcurl's va_arg reads a CURLformoption, each string
  ;; a char * (ADR-0039, amended 2026-11-06; the M8 plan, section 3.9).
  (define raw-curl-formadd
    (load-step (bind-variadic "curl_formadd" (uptr uptr int uptr int uptr int) int info)))

  ;; --- the counted wrappers, exported: step 7 counts its handle through them ------

  ;; curl-easy-init : -> Natural
  ;; A fresh easy handle's address, counted as easy; 0, counted as
  ;; nothing, when libcurl could make none.
  ;; A fresh easy handle's address, counted as easy and owned by this
  ;; thread; 0, counted as nothing, when libcurl could make none.
  (define (curl-easy-init)
    (critical-section
     (let ((easy (raw-curl-easy-init)))
       (unless (eqv? easy 0)
         (count-up! 'easy)
         (own! easy 'easy))
       easy)))

  ;; curl-easy-cleanup : Positive-Integer -> Void
  ;; Frees the easy handle EASY, this thread's, counting it down and
  ;; forgetting it first: a handle freed already is no live handle, and
  ;; raises there, before C, as a double free.
  (define (curl-easy-cleanup easy)
    (check-owner 'curl-easy-cleanup easy 'easy)
    (critical-section
     (count-down! 'easy)
     (disown! easy)
     (raw-curl-easy-cleanup easy)))

  ;; curl-easy-setopt-long : Positive-Integer Integer Integer -> Integer
  ;; curl-easy-setopt-pointer : Positive-Integer Integer Natural -> Integer
  ;; curl-easy-setopt-off-t : Positive-Integer Integer Integer -> Integer
  ;; EASY, this thread's, an option's id from curl-easy-option, and a long,
  ;; a pointer or a curl_off_t: the CURLcode.
  (define (curl-easy-setopt-long easy option value)
    (check-owner 'curl-easy-setopt easy 'easy)
    (raw-curl-easy-setopt-long easy option value))

  (define (curl-easy-setopt-pointer easy option value)
    (check-owner 'curl-easy-setopt easy 'easy)
    (raw-curl-easy-setopt-pointer easy option value))

  (define (curl-easy-setopt-off-t easy option value)
    (check-owner 'curl-easy-setopt easy 'easy)
    (raw-curl-easy-setopt-off-t easy option value))

  ;; curl-easy-getinfo : Positive-Integer Integer Positive-Integer -> Integer
  ;; EASY, this thread's, a CURLINFO_* code from (curl private constants),
  ;; and the address libcurl writes the answer to: the CURLcode.
  (define (curl-easy-getinfo easy info address)
    (check-owner 'curl-easy-getinfo easy 'easy)
    (raw-curl-easy-getinfo easy info address))

  ;; curl-easy-nextheader : Positive-Integer Natural Integer Natural -> Natural
  ;; The header after PREV, or the first for 0, of EASY's response REQUEST
  ;; (-1, the last), among those whose origin is in ORIGIN's CURLH_ bits: a
  ;; struct curl_header libcurl owns until the handle is reused or cleaned
  ;; up, or 0 when there is none. curl-header-bytes reads it. EASY is this
  ;; thread's.
  (define (curl-easy-nextheader easy origin request previous)
    (check-owner 'curl-easy-nextheader easy 'easy)
    (raw-curl-easy-nextheader easy origin request previous))

  ;; curl-easy-header : Positive-Integer String Natural Natural Integer Positive-Integer -> Integer
  ;; The header probe's call, on its own handle, which this thread made.
  (define (curl-easy-header easy name index origin request hout)
    (check-owner 'curl-easy-header easy 'easy)
    (raw-curl-easy-header easy name index origin request hout))

  ;; curl-url : -> Natural
  ;; A fresh CURLU handle's address, counted as url and owned by this
  ;; thread; 0, counted as nothing, when libcurl could make none.
  (define (curl-url)
    (critical-section
     (let ((handle (raw-curl-url)))
       (unless (eqv? handle 0)
         (count-up! 'url)
         (own! handle 'url))
       handle)))

  ;; curl-url-cleanup : Positive-Integer -> Void
  ;; Frees the CURLU handle HANDLE, this thread's, as curl-easy-cleanup
  ;; does.
  (define (curl-url-cleanup handle)
    (check-owner 'curl-url-cleanup handle 'url)
    (critical-section
     (count-down! 'url)
     (disown! handle)
     (raw-curl-url-cleanup handle)))

  ;; curl-url-set : Positive-Integer Integer Positive-Integer Natural -> Integer
  ;; HANDLE, this thread's, a CURLUPART_* code, the address of a C string,
  ;; as call-with-c-string hands it, and flags: the CURLUcode.
  (define (curl-url-set handle part address flags)
    (check-owner 'curl-url-set handle 'url)
    (raw-curl-url-set handle part address flags))

  ;; curl-url-get : Positive-Integer Integer Natural -> (Values Integer Natural)
  ;; The CURLUcode, and the address of the string curl_url_get wrote for
  ;; PART of HANDLE: counted as curl-string, for curl-free; 0 unless the
  ;; code is CURLUE_OK. The slot it writes through is a counted block,
  ;; freed before this returns. libcurl's string and its count come in one
  ;; critical section; a caller records the address in its own, as url's
  ;; get-part does.
  (define (curl-url-get handle part flags)
    (check-owner 'curl-url-get handle 'url)
    (let ((slot #f))
      (dynamic-wind #t
        (lambda () (set! slot (foreign-block (foreign-sizeof 'void*))))
        (lambda ()
          (critical-section
           (let ((code (raw-curl-url-get handle part slot flags)))
             (if (eqv? code curlue-ok)
                 (let ((address (foreign-ref 'uptr slot 0)))
                   (unless (eqv? address 0)
                     (count-up! 'curl-string))
                   (values code address))
                 (values code 0)))))
        (lambda () (free-foreign-block! slot)))))

  ;; curl-free : Positive-Integer -> Void
  ;; Frees ADDRESS, a string curl-url-get answered, counting it down first.
  (define (curl-free address)
    (critical-section
     (count-down! 'curl-string)
     (raw-curl-free address)))

  ;; curl-url-strerror : Integer -> (U String #f)
  ;; libcurl's text for the CURLUcode CODE, copied; #f for NULL.
  (define (curl-url-strerror code)
    (c-text (raw-curl-url-strerror code)))

  ;; curl-easy-strerror : Integer -> (U String #f)
  ;; libcurl's text for the CURLcode CODE, read as bytes and copied, as
  ;; curl-url-strerror's is; #f for NULL.
  (define (curl-easy-strerror code)
    (c-text (raw-curl-easy-strerror code)))

  ;; curl-easy-getinfo-long : Positive-Integer Integer -> (Values Integer Integer)
  ;; The CURLcode of curl_easy_getinfo of INFO, a CURLINFO_ long, on EASY,
  ;; and the long it wrote; 0 unless the code is CURLE_OK. The slot it
  ;; writes through is a counted block, freed before this returns.
  (define (curl-easy-getinfo-long easy info)
    (let ((slot #f))
      (dynamic-wind #t
        (lambda () (set! slot (foreign-block (foreign-sizeof 'long))))
        (lambda ()
          (let ((code (curl-easy-getinfo easy info slot)))
            (values code (if (eqv? code curle-ok) (foreign-ref 'long slot 0) 0))))
        (lambda () (free-foreign-block! slot)))))

  ;; curl-easy-getinfo-off-t : Positive-Integer Integer -> (Values Integer Integer)
  ;; The CURLcode of curl_easy_getinfo of INFO, a CURLINFO_ curl_off_t, on
  ;; EASY, and the curl_off_t it wrote, 64 bits on every platform chez-curl
  ;; supports; 0 unless the code is CURLE_OK. Never the long reader: a long
  ;; is 64 bits only on LP64. The slot is a counted block, freed before
  ;; this returns.
  (define (curl-easy-getinfo-off-t easy info)
    (let ((slot #f))
      (dynamic-wind #t
        (lambda () (set! slot (foreign-block (foreign-sizeof 'integer-64))))
        (lambda ()
          (let ((code (curl-easy-getinfo easy info slot)))
            (values code (if (eqv? code curle-ok) (foreign-ref 'integer-64 slot 0) 0))))
        (lambda () (free-foreign-block! slot)))))

  ;; curl-easy-getinfo-string : Positive-Integer Integer -> (Values Integer (U Bytevector #f))
  ;; The CURLcode of curl_easy_getinfo of INFO, a CURLINFO_ string, on
  ;; EASY, and the bytes of the string it wrote, copied, which libcurl owns;
  ;; #f for NULL, or unless the code is CURLE_OK. Whoever reads them
  ;; decodes them. The slot is a counted block, freed before this returns.
  (define (curl-easy-getinfo-string easy info)
    (let ((slot #f))
      (dynamic-wind #t
        (lambda () (set! slot (foreign-block (foreign-sizeof 'void*))))
        (lambda ()
          (let ((code (curl-easy-getinfo easy info slot)))
            (values code (and (eqv? code curle-ok)
                              (c-string->bytevector (foreign-ref 'uptr slot 0))))))
        (lambda () (free-foreign-block! slot)))))

  ;; curl-header-bytes : Positive-Integer -> (Pairof Bytevector Bytevector)
  ;; The name's bytes and the value's, copied, of the struct curl_header at
  ;; ADDRESS, as curl-easy-nextheader answered it. curl_easy_nextheader
  ;; never hands back a NUL inside either (ADR-0001, amended 2026-10-23), so
  ;; each string's strlen is the whole of it. Whoever reads them decodes
  ;; them.
  (define (curl-header-bytes address)
    (let ((header (make-ftype-pointer curl-header address)))
      (cons (or (c-string->bytevector (ftype-ref curl-header (name) header)) (make-bytevector 0))
            (or (c-string->bytevector (ftype-ref curl-header (value) header)) (make-bytevector 0)))))

  ;; curl-slist-append : Natural Positive-Integer -> Natural
  ;; LIST, a string list or 0 for none, with a copy of the C string at
  ;; ADDRESS appended: curl_slist_append "copies the string", so ADDRESS may
  ;; be freed once this returns. Its answer is the list, counted as slist
  ;; when it was 0 before. 0 means libcurl could not append: LIST is left as
  ;; it was, still valid, and still the caller's to free, and nothing is
  ;; counted.
  ;; A LIST that is not 0 is this thread's. A new list is owned by this
  ;; thread, and keeps its address: libcurl appends at the end.
  (define (curl-slist-append list address)
    (unless (eqv? list 0)
      (check-owner 'curl-slist-append list 'slist))
    (critical-section
     (let ((appended (raw-curl-slist-append list address)))
       (when (and (eqv? list 0) (not (eqv? appended 0)))
         (count-up! 'slist)
         (own! appended 'slist))
       appended)))

  ;; curl-slist-free-all : Positive-Integer -> Void
  ;; Frees the string list LIST, this thread's, and every string in it,
  ;; counting it down and forgetting it first: a list freed already is no
  ;; live handle, and raises there, before C, as a double free.
  (define (curl-slist-free-all list)
    (check-owner 'curl-slist-free-all list 'slist)
    (critical-section
     (count-down! 'slist)
     (disown! list)
     (raw-curl-slist-free-all list)))

  ;; --- the multi interface's wrappers (M3 plan, section 3.2) --------------------------

  ;; curl-multi-init : -> Natural
  ;; A fresh multi handle's address, counted as multi and owned by this
  ;; thread; 0, counted as nothing, when libcurl could make none.
  (define (curl-multi-init)
    (critical-section
     (let ((multi (raw-curl-multi-init)))
       (unless (eqv? multi 0)
         (count-up! 'multi)
         (own! multi 'multi))
       multi)))

  ;; curl-multi-cleanup : Positive-Integer -> Integer
  ;; Frees MULTI, this thread's, which must hold no easy handle: the
  ;; CURLMcode. On CURLM_OK it is counted down and forgotten, in the
  ;; critical section of the call, which is __collect_safe: the thread is
  ;; inactive while it waits, critical section or not, so other threads'
  ;; collections go on. Any other code leaves it counted, and live.
  (define (curl-multi-cleanup multi)
    (check-owner 'curl-multi-cleanup multi 'multi)
    (critical-section
     (let ((code (raw-curl-multi-cleanup multi)))
       (when (eqv? code curlm-ok)
         (count-down! 'multi)
         (disown! multi))
       code)))

  ;; curl-multi-add-handle : Positive-Integer Positive-Integer -> Integer
  ;; curl-multi-remove-handle : Positive-Integer Positive-Integer -> Integer
  ;; EASY added to, or removed from, MULTI, both this thread's: the
  ;; CURLMcode. Removal can block, and is __collect_safe.
  (define (curl-multi-add-handle multi easy)
    (check-owner 'curl-multi-add-handle multi 'multi)
    (check-owner 'curl-multi-add-handle easy 'easy)
    (raw-curl-multi-add-handle multi easy))

  (define (curl-multi-remove-handle multi easy)
    (check-owner 'curl-multi-remove-handle multi 'multi)
    (check-owner 'curl-multi-remove-handle easy 'easy)
    (raw-curl-multi-remove-handle multi easy))

  ;; check-slot : Symbol Any -> Void
  ;; SLOT is a positive exact integer: the address of its caller's counted
  ;; block, an int's size at least, where libcurl writes a count. The
  ;; caller holds it for as long as its multi handle, so a call makes and
  ;; frees nothing, and the counts read the same before and after it.
  (define (check-slot who slot)
    (unless (and (integer? slot) (exact? slot) (positive? slot))
      (assertion-violation who "a slot is the address of a counted block" slot)))

  ;; curl-multi-perform : Positive-Integer Positive-Integer -> (Values Integer Natural)
  ;; Runs what MULTI, this thread's, can run now, write callbacks included:
  ;; the CURLMcode, and how many transfers still run, 0 unless CURLM_OK,
  ;; written through SLOT, check-slot's.
  (define (curl-multi-perform multi slot)
    (check-owner 'curl-multi-perform multi 'multi)
    (check-slot 'curl-multi-perform slot)
    (let ((code (raw-curl-multi-perform multi slot)))
      (values code (if (eqv? code curlm-ok) (foreign-ref 'int slot 0) 0))))

  ;; curl-multi-poll : Positive-Integer Natural -> Integer
  ;; Waits on MULTI, this thread's, for activity, for at most TIMEOUT-MS, or
  ;; less when libcurl's own timers say so, or until curl-multi-wakeup: the
  ;; CURLMcode. No extra file descriptors, and no count back.
  (define (curl-multi-poll multi timeout-ms)
    (check-owner 'curl-multi-poll multi 'multi)
    (raw-curl-multi-poll multi 0 0 timeout-ms 0))

  ;; curl-multi-wakeup : Positive-Integer -> Integer
  ;; Wakes MULTI's poll, or the next one: the CURLMcode. Any thread may call
  ;; it on a live multi handle (ADR-0012); its owner must keep the handle
  ;; alive while another thread may.
  (define (curl-multi-wakeup multi)
    (live-handle 'curl-multi-wakeup multi 'multi)
    (raw-curl-multi-wakeup multi))

  ;; curl-multi-info-read : Positive-Integer Positive-Integer -> (U #f (List Integer Natural Integer))
  ;; The next message MULTI, this thread's, holds, read from its CURLMsg: its
  ;; msg, its easy handle's address, and data.result, which is the
  ;; transfer's CURLcode when msg is CURLMSG_DONE; #f when none is left.
  ;; libcurl writes the queue's count through SLOT, check-slot's.
  (define (curl-multi-info-read multi slot)
    (check-owner 'curl-multi-info-read multi 'multi)
    (check-slot 'curl-multi-info-read slot)
    (let ((address (raw-curl-multi-info-read multi slot)))
      (and (not (eqv? address 0))
           (let ((message (make-ftype-pointer curl-msg address)))
             (list (ftype-ref curl-msg (msg) message)
                   (ftype-ref curl-msg (easy-handle) message)
                   (ftype-ref curl-msg (data.result) message))))))

  ;; curl-multi-setopt-long : Positive-Integer Integer Integer -> Integer
  ;; MULTI, this thread's, a CURLMOPT_* long option from (curl private
  ;; constants), and a long: the CURLMcode. A libcurl older than the option
  ;; answers CURLM_UNKNOWN_OPTION.
  (define (curl-multi-setopt-long multi option value)
    (check-owner 'curl-multi-setopt multi 'multi)
    (raw-curl-multi-setopt-long multi option value))

  ;; curl-multi-strerror : Integer -> (U String #f)
  ;; libcurl's text for the CURLMcode CODE, copied; #f for NULL.
  (define (curl-multi-strerror code)
    (c-text (raw-curl-multi-strerror code)))

  ;; --- the share interface's wrappers (ADR-0035; the M7 plan, section 3.5) ----

  ;; curl-share-init : -> Natural
  ;; A fresh share's address, counted as share and owned by this thread, in
  ;; one critical section; 0, counted as nothing, when libcurl made none.
  (define (curl-share-init)
    (critical-section
     (let ((share (raw-curl-share-init)))
       (unless (eqv? share 0)
         (count-up! 'share)
         (own! share 'share))
       share)))

  ;; curl-share-setopt-int : Positive-Integer Integer Integer -> Integer
  ;; SHARE, this thread's, a CURLSHoption from (curl private constants), and
  ;; an int: the CURLSHcode.
  (define (curl-share-setopt-int share option value)
    (check-owner 'curl-share-setopt share 'share)
    (raw-curl-share-setopt-int share option value))

  ;; curl-share-cleanup : Positive-Integer -> Integer
  ;; Frees SHARE, this thread's: the CURLSHcode. On CURLSHE_OK it is counted
  ;; down and forgotten, in the critical section of the call; any other
  ;; code, CURLSHE_IN_USE while a handle holds it, leaves it counted, and
  ;; live, as curl-multi-cleanup does.
  (define (curl-share-cleanup share)
    (check-owner 'curl-share-cleanup share 'share)
    (critical-section
     (let ((code (raw-curl-share-cleanup share)))
       (when (eqv? code curlshe-ok)
         (count-down! 'share)
         (disown! share))
       code)))

  ;; curl-easy-getinfo-cookielist : Positive-Integer -> (Values Integer Natural)
  ;; The CURLcode of CURLINFO_COOKIELIST on EASY, this thread's, and the
  ;; struct curl_slist * it wrote, the jar's lines, which libcurl made and
  ;; the caller owns: counted as slist and owned by this thread in the
  ;; critical section of the call, so an escape cannot leave it made and
  ;; unrecorded; 0, counted as nothing, for an empty jar, or unless the code
  ;; is CURLE_OK. The caller frees it with curl-slist-free-all. The slot it
  ;; writes through is a counted block, freed before this returns.
  (define (curl-easy-getinfo-cookielist easy)
    (check-owner 'curl-easy-getinfo easy 'easy)
    (let ((slot #f))
      (dynamic-wind #t
        (lambda () (set! slot (foreign-block (foreign-sizeof 'void*))))
        (lambda ()
          (critical-section
           (let ((code (raw-curl-easy-getinfo easy curlinfo-cookielist slot)))
             (if (eqv? code curle-ok)
                 (let ((head (foreign-ref 'uptr slot 0)))
                   (unless (eqv? head 0)
                     (count-up! 'slist)
                     (own! head 'slist))
                   (values code head))
                 (values code 0)))))
        (lambda () (free-foreign-block! slot)))))

  ;; curl-slist-strings : Positive-Integer -> (Listof Bytevector)
  ;; Each string of the string list LIST, this thread's, in its order, as
  ;; its bytes up to its NUL, copied by the checked copy: the walk of struct
  ;; curl_slist by data and next, (curl private layouts)' curl-slist. A NULL
  ;; data reads as no bytes. Whoever reads them decodes them.
  (define (curl-slist-strings list)
    (check-owner 'curl-slist-strings list 'slist)
    (let walk ((node list) (found '()))
      (if (eqv? node 0)
          (reverse found)
          (let* ((cell (make-ftype-pointer curl-slist node))
                 (bytes (or (c-string->bytevector (ftype-ref curl-slist (data) cell))
                            (make-bytevector 0))))
            (walk (ftype-ref curl-slist (next) cell) (cons bytes found))))))

  ;; curl-easy-pause : Positive-Integer Integer -> Integer
  ;; EASY, this thread's, given the new pause state ACTION, a CURLPAUSE_*
  ;; mask from (curl private constants): the CURLcode. Resuming, libcurl
  ;; hands the bytes it held to the transfer's callables before it returns,
  ;; on this thread. It takes the whole state: CURLPAUSE_CONT unpauses both
  ;; directions (ADR-0012, amended 2026-10-29).
  (define (curl-easy-pause easy action)
    (check-owner 'curl-easy-pause easy 'easy)
    (raw-curl-easy-pause easy action))


  ;; --- a multipart body's wrappers (ADR-0039; the M8 plan, section 3.4) ----------------

  ;; curl-mime-init : Positive-Integer -> Natural
  ;; A fresh mime of EASY's, this thread's: counted as mime and owned by
  ;; this thread, in one critical section; 0, counted as nothing, when
  ;; libcurl made none. A mime belongs to the easy handle it was made with:
  ;; 7.85.0 refuses one made with another (the M8 plan, section 2).
  (define (curl-mime-init easy)
    (check-owner 'curl-mime-init easy 'easy)
    (critical-section
     (let ((mime (raw-curl-mime-init easy)))
       (unless (eqv? mime 0)
         (count-up! 'mime)
         (own! mime 'mime))
       mime)))

  ;; curl-mime-free : Positive-Integer -> Void
  ;; Frees MIME, this thread's, and its parts, counting it down and
  ;; forgetting it first: a mime freed already is no live handle, and
  ;; raises there, before C, as a double free.
  (define (curl-mime-free mime)
    (check-owner 'curl-mime-free mime 'mime)
    (critical-section
     (count-down! 'mime)
     (disown! mime)
     (raw-curl-mime-free mime)))

  ;; curl-mime-add-part! : Positive-Integer String (U 'data 'file) (U Bytevector String)
  ;;                       (U String #f) (U String #f) -> (U #f (Pairof Symbol (U Integer #f)))
  ;; One whole part added to MIME, this thread's: its NAME, then its data,
  ;; the bytevector PAYLOAD for data, or the file at the path PAYLOAD for
  ;; file, by curl_mime_filedata, then FILENAME and TYPE, each when not #f.
  ;; The filename comes after the data, since curl_mime_filedata sets one of
  ;; its own, the path's last component. Each string is a counted UTF-8
  ;; copy, and the data a counted copy, each freed once its call returns:
  ;; libcurl copies them. #f once every call answered 0; else the first call
  ;; that did not, and its CURLcode: (addpart . #f) for a NULL part,
  ;; (name . C), (data . C), (filedata . C), (filename . C) or (type . C).
  ;; The part's address never leaves this procedure, so none leaves this
  ;; library.
  (define (curl-mime-add-part! mime name kind payload filename type)
    (check-owner 'curl-mime-add-part! mime 'mime)
    (let ((part (raw-curl-mime-addpart mime)))
      (define (step label code rest) (if (eqv? code curle-ok) (rest) (cons label code)))
      (if (eqv? part 0)
          (cons 'addpart #f)
          (step 'name (call-with-c-string name (lambda (a) (raw-curl-mime-name part a)))
                (lambda ()
                  (step (if (eq? kind 'data) 'data 'filedata)
                        (if (eq? kind 'data)
                            (call-with-foreign-bytes payload
                              (lambda (a) (raw-curl-mime-data part a (bytevector-length payload))))
                            (call-with-c-string payload (lambda (a) (raw-curl-mime-filedata part a))))
                        (lambda ()
                          (step 'filename
                                (if filename
                                    (call-with-c-string filename
                                      (lambda (a) (raw-curl-mime-filename part a)))
                                    curle-ok)
                                (lambda ()
                                  (step 'type
                                        (if type
                                            (call-with-c-string type
                                              (lambda (a) (raw-curl-mime-type part a)))
                                            curle-ok)
                                        (lambda () #f)))))))))))

  ;; formadd-code : Integer String Integer String -> Integer
  ;; What curl_formadd answers for a form of one field, FIRST and its
  ;; string A, SECOND and its string B, then CURLFORM_END, its post freed by
  ;; curl_formfree, NULL when nothing was made. The two slots and the two
  ;; strings are counted blocks freed before it returns; the post is never
  ;; counted, and never outlives the call.
  (define (formadd-code first a second b)
    (let* ((width (foreign-sizeof 'void*))
           (slots (foreign-block (* 2 width))))
      (dynamic-wind
        (lambda () #f)
        (lambda ()
          (copy-bytevector->foreign! (make-bytevector (* 2 width) 0) 0 slots (* 2 width))
          (let ((code (call-with-c-string a
                        (lambda (first-string)
                          (call-with-c-string b
                            (lambda (second-string)
                              (raw-curl-formadd slots (+ slots width) first first-string
                                                second second-string curlform-end)))))))
            (raw-curl-formfree (foreign-ref 'uptr slots 0))
            code))
        (lambda () (free-foreign-block! slots)))))

  ;; curl-formadd-code : Integer String Integer String -> Integer
  ;; formadd-code's answer, in one critical section: tests/test-variadic.sps
  ;; holds the binding to a valid form's 0 and an unknown option's
  ;; CURL_FORMADD_UNKNOWN_OPTION, which only a binding that delivers its
  ;; variadic arguments gives. Private: (curl) does not export it.
  (define (curl-formadd-code first a second b)
    (unless (and (integer? first) (exact? first) (integer? second) (exact? second)
                 (string? a) (string? b))
      (assertion-violation 'curl-formadd-code "two options, each an exact integer, each with a string"
                           first second))
    (critical-section (formadd-code first a second b)))

  ;; --- 7. the two API probes, then check-apis --------------------------------------------

  ;; Whether the options API knows URL. A boolean, never the pointer:
  ;; check-apis refuses anything else, since NULL as 0 would be true.
  (define option-found?
    (load-step (not (zero? (curl-easy-option-by-name "URL")))))

  ;; What curl_easy_header answers on a fresh handle: CURLHE_NOHEADERS
  ;; with the API built in, CURLHE_NOT_BUILT_IN without (ADR-0003). hout
  ;; points at a counted block of our own, freed with the handle, so the
  ;; counts are zero once the load returns. The whole probe is one critical
  ;; section, so no escape leaves either made.
  (define header-code
    (load-step
     (critical-section
      (let ((easy (curl-easy-init)))
        (when (zero? easy)
          (refuse 'load-failed libcurl-path libcurl-source info "curl_easy_init returned NULL"
                  "curl_easy_init returned NULL, so the header API could not be probed; name another libcurl with CHEZ_CURL_LIBCURL"))
        (let* ((hout (foreign-block (foreign-sizeof 'void*)))
               (code (curl-easy-header easy "Content-Type" 0 curlh-header -1 hout)))
          (free-foreign-block! hout)
          (curl-easy-cleanup easy)
          code)))))

  (define apis-checked
    (load-step
     (check-apis option-found? header-code libcurl-path libcurl-source info)))

  ;; The mime probe (ADR-0039, amended 2026-11-06, decision 4 made exact;
  ;; the M8 plan, section 3.4), after the APIs are checked, in one critical
  ;; section, through the raw bindings: curl_formadd with CURLFORM_COPYNAME,
  ;; CURLFORM_COPYCONTENTS and CURLFORM_END, then curl_formfree of the post
  ;; it made, NULL when none; then curl_mime_init with NULL, then
  ;; curl_mime_free of the mime it made. Neither the post nor the mime is
  ;; counted, and neither outlives the section. It refuses no load: its
  ;; answer is data, ((formadd . CODE) (mime-init . made)), or (mime-init .
  ;; null), the code named by its key whatever it is. 7.85.0 built without
  ;; mime answers curl_formadd 7 and makes a mime that sends nothing; 8.23.0
  ;; built so answers 7 and NULL (the M8 plan, section 2).
  (define mime-probe
    (load-step
     (critical-section
      (let* ((code (formadd-code curlform-copyname "chez-curl" curlform-copycontents "probe"))
             (mime (raw-curl-mime-init 0)))
        (unless (eqv? mime 0) (raw-curl-mime-free mime))
        (list (cons 'formadd code) (cons 'mime-init (if (eqv? mime 0) 'null 'made)))))))

  ;; --- the exports ---------------------------------------------------------------------------

  ;; loaded-mime-probe : -> (List (Pairof 'formadd Integer) (Pairof 'mime-init (U 'made 'null)))
  ;; What the load's mime probe answered: curl_formadd's code, and whether
  ;; curl_mime_init made a mime. Kept as data beside the libcurl-info
  ;; record, as loaded-tls-backend is: a load the probe says no to still
  ;; loads. Fresh pairs. Private: (curl) does not export it.
  (define (loaded-mime-probe) (map (lambda (entry) (cons (car entry) (cdr entry))) mime-probe))

  ;; loaded-mime? : -> Boolean
  ;; Whether a multipart body can go on the loaded libcurl: curl_formadd
  ;; answered CURL_FORMADD_OK and curl_mime_init made a mime. Any other code,
  ;; CURL_FORMADD_DISABLED or one no build answers, counts as no (ADR-0039,
  ;; amended 2026-11-06). Private.
  (define (loaded-mime?)
    (and (eqv? (cdr (assq 'formadd mime-probe)) curl-formadd-ok)
         (eq? (cdr (assq 'mime-init mime-probe)) 'made)))

  ;; loaded-libcurl : -> Libcurl-Info
  ;; The libcurl this process loaded and accepted. Reaching this binding
  ;; runs the load above, once; a refusal raises from there instead, at
  ;; this reference and every later one.
  (define (loaded-libcurl) info)

  ;; loaded-libcurl-file : -> (U String #f)
  ;; The file the loaded libcurl is mapped from, symlinks resolved, step 3's
  ;; libcurl-file: a fresh string, or #f where it could not be read. Private:
  ;; (curl) does not export it.
  (define (loaded-libcurl-file) (and libcurl-file (string-copy libcurl-file)))

  ;; loaded-tls-backend : -> (U String #f)
  ;; The TLS backend libcurl put in use at its init, as curl_version_info
  ;; then named it, LibreSSL/3.3.6 say: a fresh string, or #f. Private:
  ;; (curl) does not export it.
  (define (loaded-tls-backend) (and tls-backend (string-copy tls-backend)))

  ;; loaded-features : -> Natural
  ;; The features word libcurl reports after its init, features-after-init:
  ;; the one a check of a backend's support reads. Private: (curl) does not
  ;; export it; libcurl-info-features answers the word read before the init.
  (define (loaded-features) features-after-init)

  ;; loaded-on-macos? : -> Boolean
  ;; Whether this process runs on macOS, by Chez's machine type. Private.
  (define (loaded-on-macos?) on-macos)

  ;; loaded-libcurl-patched? : -> Boolean
  ;; Whether the loaded libcurl's file holds Guix's patch's literal, step 3's
  ;; libcurl-patched. Private: (curl) does not export it.
  (define (loaded-libcurl-patched?) libcurl-patched)

  ;; loaded-ca-variables : -> (List (Pairof String (U String #f)) (Pairof String (U String #f)))
  ;; ("SSL_CERT_FILE" . VALUE) and ("SSL_CERT_DIR" . VALUE), as step 5 read
  ;; them before curl_global_init, an empty value as #f: fresh pairs and
  ;; fresh strings. Private: (curl) does not export it.
  (define (loaded-ca-variables)
    (map (lambda (entry)
           (cons (string-copy (car entry)) (and (cdr entry) (string-copy (cdr entry)))))
         ca-variables))

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
  ;; (ADR-0001, decision 2). NAME is copied, the copy checked, and the copy
  ;; passed: Chez's string type would cut a name at U+0000, so "URL" then
  ;; anything would find URL, and a caller's string could change between a
  ;; check and the call. A NAME holding U+0000 is an assertion violation.
  (define (curl-easy-option name)
    (unless (string? name)
      (assertion-violation 'curl-easy-option "an option's name is a string" name))
    (let* ((name (string-copy name))
           (address (begin
                      (when (memv #\nul (string->list name))
                        (assertion-violation 'curl-easy-option "an option's name holds U+0000" name))
                      (curl-easy-option-by-name name))))
      (and (not (zero? address))
           (let ((option (make-ftype-pointer curl-easyoption address)))
             (cons (ftype-ref curl-easyoption (id) option)
                   (ftype-ref curl-easyoption (type) option)))))))
