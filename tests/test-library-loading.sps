#!r6rs
;;; The suite for loading libcurl end to end: (curl private native), (curl),
;;; tests/refusal-probe.sps and tests/preflight.sps (ADR-0001, ADR-0002,
;;; ADR-0003).
;;;
;;; (curl private native) loads libcurl in its library body, once per
;;; process, and Chez runs that body before a program's own, so a refusal
;;; cannot be caught in this process, nor a second library tried in it.
;;; Every case therefore runs tests/refusal-probe.sps in a fresh Chez,
;;; through `env`, and reads back what it printed, as data:
;;;
;;;   - decoys: tests/decoy-libcurl.c, compiled here once per case with $CC
;;;     (else cc), each answering one load-time check wrongly. Each case
;;;     asserts the whole outcome, the decoy's call log included, so the log
;;;     holds ADR-0001's load order: curl_version_info first, the floor
;;;     before curl_global_init, curl_global_init exactly once, and nothing
;;;     after a refusal. A failed compile fails its case, never skips it;
;;;   - the load runs once: the probe references loaded-libcurl three times,
;;;     and the later two must answer what the first did;
;;;   - the real libcurl: the one the probe loads in this environment, then
;;;     through the override and by discovery. What it reports must equal
;;;     what tests/libcurl-oracle.c reads from the same file, field by
;;;     field. Its path comes from the probe, so these cases hold with
;;;     CHEZ_CURL_LIBCURL set or unset;
;;;   - the refusals no decoy can reach: invalid-override, load-failed and
;;;     not-found;
;;;   - make build's preflight, its exit status and its output.
;;;
;;; This process itself never loads libcurl: (curl)'s exports and
;;; re-exports are read through environment and library-exports, which
;;; expand (curl) without running its body (measured).
;;;
;;; Each expected value is one the code under test cannot produce by
;;; failing, and none is #f: SRFI-64 makes #f of a raise in the actual
;;; expression. An expected value that can raise is computed first, under a
;;; guard with a sentinel: SRFI-64 does not catch a raise there.
(import (rnrs)
        (srfi :64)
        (curl-testing)
        (libcurl-oracle)
        (only (chezscheme) getenv putenv format format-condition? load-shared-object
              environment eval library-exports file-directory? foreign-entry?
              machine-type directory-list)
        (curl private discovery)
        (curl private verify))

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

;; --- strings -----------------------------------------------------------------

(define (string-prefix? prefix s)
  (let ((n (string-length s)) (m (string-length prefix)))
    (and (>= n m) (string=? (substring s 0 m) prefix))))

(define (string-suffix? suffix s)
  (let ((n (string-length s)) (m (string-length suffix)))
    (and (>= n m) (string=? (substring s (- n m) n) suffix))))

(define (absolute? s)
  (and (string? s) (string-prefix? "/" s)))

;; join : (Listof String) -> String
;; ENTRIES with one space between: a decoy's call log.
(define (join entries)
  (if (null? entries)
      ""
      (fold-left (lambda (all entry) (string-append all " " entry))
                 (car entries) (cdr entries))))

;; words : (Listof Any) -> String
;; Each displayed, one space between: the preflight's features line.
(define (words items)
  (call-with-string-output-port
   (lambda (p)
     (let loop ((items items) (first? #t))
       (unless (null? items)
         (unless first? (put-char p #\space))
         (display (car items) p)
         (loop (cdr items) #f))))))

(define (set? value) (and (string? value) (not (string=? value ""))))

;; --- the processes it spawns ---------------------------------------------------

(define chez (getenv "CHEZ"))

(test-begin "library-loading")

;; The Makefile exports CHEZ, so this suite spawns the Chez that runs it.
;; Without it nothing below can run: fail, never skip.
(test-equal "CHEZ names the Chez to spawn"
  'set
  (if (set? chez) 'set 'unset))

(unless (set? chez)
  (exit 1))

;; Every compile here, the decoys' and the oracle's, runs $CC's words.
(test-equal "CC is cut at whitespace, so CC='ccache gcc' runs ccache, with gcc as its argument"
  '(("ccache" "gcc") ("gcc" "-m64") ("cc") ("cc"))
  (map (lambda (value)
         (c-compiler (lambda (name) (and (string=? name "CC") value))))
       '(" ccache\tgcc " "gcc -m64" "  " #f)))

;; read-data : String -> (U (Listof Any) (List 'unreadable String))
;; TEXT read as a sequence of data.
(define (read-data text)
  (guard (e (#t (list 'unreadable text)))
    (let ((port (open-string-input-port text)))
      (let loop ((data '()))
        (let ((datum (read port)))
          (if (eof-object? datum)
              (reverse data)
              (loop (cons datum data))))))))

;; spawn-in : String (Listof String) String (Listof String)
;;            -> (U (List Integer String String) (List 'raised String))
;; Runs PROGRAM with ARGS in a fresh Chez with LIBDIRS as its library path,
;; through env with ENV-ARGS (NAME=VALUE to set, -u NAME to unset): its
;; exit status, stdout and stderr.
(define (spawn-in libdirs env-args program args)
  (guard (e (#t (list 'raised (describe e))))
    (capture-command (append '("env") env-args
                             (list chez "--libdirs" libdirs "--program" program)
                             args))))

(define (spawn env-args program args) (spawn-in "src" env-args program args))

;; as-data : (U (List Integer String String) (List 'raised String))
;;           -> (U (List Integer (Listof Any) String) (List 'raised String))
;; A probe's answer, with what it printed read as data.
(define (as-data answer)
  (if (eq? (car answer) 'raised)
      answer
      (list (car answer) (read-data (cadr answer)) (caddr answer))))

;; probe-with : (Listof String) (Listof String)
;;              -> (U (List Integer (Listof Any) String) (List 'raised String))
;; tests/refusal-probe.sps under ENV-ARGS, with ARGS: its exit status, what
;; it printed, read as data, and its stderr.
(define (probe-with env-args args)
  (as-data (spawn env-args "tests/refusal-probe.sps" args)))

(define (probe env-args) (probe-with env-args '()))

(define (override path) (string-append "CHEZ_CURL_LIBCURL=" path))

;; The probe references loaded-libcurl three times. A load runs once per
;; process, whatever it decided, so the two later references answer the
;; very object the first did: the info record, or the refusal raised again.
(define once '(again . (same same)))

;; What the probe prints next: its native counts, every one zero, whatever
;; the load decided (tests/refusal-probe.sps). The counters gate counts per
;; process, and this suite's own never loads libcurl.
(define no-native-objects
  '(counts . ((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0))))

;; A report is what a loaded library says about itself: (FIELD . VALUE) for
;; each of oracle-fields, in order, as the probe prints them after the path
;; and source, and as tests/libcurl-oracle.c prints them.

;; The control decoy's features: IPV6, SSL, LIBZ, HTTP2 and THREADSAFE,
;; curl/curl.h's 1<<0, 1<<2, 1<<3, 1<<16 and 1<<30.
(define decoy-features (+ #x1 #x4 #x8 #x10000 #x40000000))

;; decoy-report* : String Natural Natural (U String #f) (U String #f) -> Report
(define (decoy-report* version version-num features ssl-version host)
  (list (cons 'version version)
        (cons 'version-num version-num)
        (cons 'features features)
        (cons 'ssl-version ssl-version)
        (cons 'host host)))

;; decoy-report : (U String #f) (U String #f) -> Report
;; The control decoy's: 7.85.0, with decoy-features, SSL-VERSION and HOST.
(define (decoy-report ssl-version host)
  (decoy-report* "7.85.0" #x075500 decoy-features ssl-version host))

;; report-of : String Symbol Report -> (Listof Any)
;; What the probe prints as a refusal's library, the report read before
;; the refusal: its path, its source, then the report's values.
(define (report-of path source report)
  (cons* path source (map cdr report)))

;; control : String -> (Listof Any)
;; report-of for a decoy at PATH that reports what the control does.
(define (control path)
  (report-of path 'override (decoy-report "DecoyTLS/1.0" "decoy-host")))

;; loaded : String Symbol Report (Listof String) (U (Listof String) #f) -> Expected
;; The probe's whole answer when it loads PATH. PROTOCOLS is what
;; loaded-protocols answers there: () for a decoy whose array is NULL.
;; CALLS is the decoy's call log, as entries, or #f for a library without
;; one.
(define (loaded path source report protocols calls)
  (list 0
        (append (list (cons 'loaded path) (cons 'source source))
                report
                (list (cons 'protocols protocols) once no-native-objects)
                (if calls (list (cons 'calls (join calls))) '()))
        ""))

;; refused : Symbol (U String #f) (U Symbol #f) Any (Listof String)
;;           (U (Listof Any) #f) (U (Listof String) #f) -> Expected
;; LIBRARY is report-of's list for a refusal made after the version was
;; read, else #f.
(define (refused reason path source detail candidates library calls)
  (list 1
        (append (list (cons 'reason reason) (cons 'path path) (cons 'source source)
                      (cons 'detail detail) (cons 'candidates candidates)
                      (cons 'library library)
                      once no-native-objects)
                (if calls (list (cons 'calls (join calls))) '()))
        ""))

;; --- the scratch directory ---------------------------------------------------------

;; scratch : (U String #f)
;; A fresh directory for the decoys, the fake profile, the text file and the
;; empty HOME. This suite is flat top-level forms, so (curl-testing) removes
;; the directory when the process ends, by exit or by a raise nothing guards;
;; the last forms remove it earlier, and the tests below require that.
(define scratch
  (guard (e (#t #f))
    (make-process-temp-directory)))

(test-equal "mktemp -d made a scratch directory"
  'made
  (if (and (absolute? scratch) (file-directory? scratch)) 'made 'not-made))

(unless (and (absolute? scratch) (file-directory? scratch))
  (exit 1))

(define (in-scratch name) (string-append scratch "/" name))

(define (write-text-file path text)
  (call-with-port (open-file-output-port path (file-options no-fail)
                                         (buffer-mode block)
                                         (make-transcoder (utf-8-codec)))
    (lambda (p) (put-string p text))))

;; --- decoys ----------------------------------------------------------------------

(define decoy-source "tests/decoy-libcurl.c")

;; compile-decoy : String (Listof String) -> (U Integer (List 'raised String))
;; Compiles the decoy as NAME.so in the scratch directory under SWITCHES:
;; the compiler's exit status.
(define (compile-decoy name switches)
  (guard (e (#t (list 'raised (describe e))))
    (car (capture-command
          (append (c-compiler getenv)
                  (list "-shared" "-fPIC" "-o" (in-scratch (string-append name ".so"))
                        decoy-source)
                  switches)))))

;; The call log's entries, as tests/decoy-libcurl.c writes them. The
;; arguments are the header's values: CURLVERSION_TENTH is 9,
;; CURL_GLOBAL_DEFAULT is 3, CURLH_HEADER is 1. backend-call is
;; curl_version_info again, once the init has run: a MultiSSL libcurl
;; names the backend the init put in use only then (ADR-0024).
(define version-call "curl_version_info(9)")
(define init-call "curl_global_init(3)")
(define backend-call "curl_version_info(9)")
(define option-call "curl_easy_option_by_name(URL)")
(define easy-init-call "curl_easy_init()")
(define header-call "curl_easy_header(handle,Content-Type,0,1,-1,hout)")
(define cleanup-call "curl_easy_cleanup(handle)")

;; api-calls : (Listof String)
;; The load's calls up to check-apis: a refusal there stops the load before
;; the mime probe.
(define api-calls
  (list version-call init-call backend-call option-call easy-init-call header-call cleanup-call))

;; The mime probe's calls, after check-apis (ADR-0039): curl_formadd, its
;; options as the decoy was handed them, CURLFORM_COPYNAME 1 with
;; chez-curl, CURLFORM_COPYCONTENTS 4 with probe, then CURLFORM_END 17;
;; curl_formfree of the post it made, NULL when it made none; then
;; curl_mime_init with NULL, and curl_mime_free of the mime it made.
(define formadd-call "curl_formadd(post,last,1:chez-curl,4:probe,17)")
(define formfree-call "curl_formfree(post)")
(define formfree-null-call "curl_formfree(NULL)")
(define mime-init-call "curl_mime_init(NULL)")
(define mime-free-call "curl_mime_free(mime)")

;; every-call : (Listof String)
;; A whole load's calls, the control's.
(define every-call
  (append api-calls (list formadd-call formfree-call mime-init-call mime-free-call)))

;; decoy-case : String (Listof String) String (String -> Expected) -> Void
;; The test DESCRIPTION: compiles the decoy NAME under SWITCHES, runs the
;; probe with it as the override, and requires the compiler's exit status
;; 0, then EXPECTED of the decoy's path.
(define (decoy-case name switches description expected)
  (let ((so (in-scratch (string-append name ".so"))))
    (test-equal (string-append "decoy " name ": " description)
      (cons 0 (expected so))
      (let ((compiled (compile-decoy name switches)))
        (cons compiled (probe (list (override so))))))))

(decoy-case "accepted" '()
  "the control loads, calling curl_global_init exactly once, after the version"
  (lambda (so) (loaded so 'override (decoy-report "DecoyTLS/1.0" "decoy-host") '() every-call)))

(decoy-case "ssl-null" '("-DDECOY_SSL_VERSION_NULL")
  "a NULL ssl_version is reported as #f"
  (lambda (so) (loaded so 'override (decoy-report #f "decoy-host") '() every-call)))

(decoy-case "host-null" '("-DDECOY_HOST_NULL")
  "a NULL host is reported as #f"
  (lambda (so) (loaded so 'override (decoy-report "DecoyTLS/1.0" #f) '() every-call)))

;; curl_version_info_data's strings are UTF-8: é is two bytes, λ two and €
;; three, and a reading as Latin-1 would report seven characters for them.
(decoy-case "host-utf8" '("-DDECOY_HOST_UTF8")
  "a host past ASCII is read as UTF-8: d\xE9;coy-\x3BB;\x20AC;"
  (lambda (so) (loaded so 'override (decoy-report "DecoyTLS/1.0" "d\xE9;coy-\x3BB;\x20AC;") '() every-call)))

;; The protocol list, read entry by entry, in its order: every other decoy's
;; array is NULL, and answers ().
(decoy-case "protocols" '("-DDECOY_PROTOCOLS")
  "a protocol list is read whole, in its order: https, dict, http"
  (lambda (so) (loaded so 'override (decoy-report "DecoyTLS/1.0" "decoy-host")
                       '("https" "dict" "http") every-call)))

;; The record's version is a string, and the floor's refusal names it: a
;; NULL there is refused before the floor is checked.
;; A MultiSSL libcurl names its first backend as the one in use until
;; curl_global_init picks one (lib/vtls/vtls.c, multissl_version): Apple's
;; 8.7.1 names SecureTransport before it and LibreSSL after. The decoy built
;; with DECOY_MULTISSL names DecoyFirst before the init and DecoyTLS after.
;; The report keeps the text read before; loaded-tls-backend must be the
;; backend after, read by curl_version_info again (ADR-0024). The control
;; decoy names one backend throughout. The same second call answers
;; loaded-features: the decoy's selector, as Apple's 8.7.1's, lacks
;; CURL_VERSION_HTTPS_PROXY until the init, which the report, read before it,
;; keeps, so a check of a backend's support reads the word after (measured on
;; macOS): curl/curl.h's 1<<21, #x200000.
(let ((so (in-scratch "multissl.so")))
  (test-equal "decoy multissl: the report keeps ssl_version as curl_version_info named it before the init, and loaded-tls-backend is the backend in use after it, DecoyTLS, read by a second call"
    (list 0 (list 0
                  (append (list (cons 'loaded so) (cons 'source 'override))
                          (decoy-report "DecoyFirst/1.0 (DecoyTLS/1.0)" "decoy-host")
                          (list (cons 'protocols '()) once no-native-objects
                                (cons 'backend "DecoyTLS/1.0")
                                (cons 'features-after (+ decoy-features #x200000))
                                (cons 'calls (join every-call))))
                  ""))
    (let ((compiled (compile-decoy "multissl" '("-DDECOY_MULTISSL"))))
      (list compiled (probe-with (list (override so)) '("--backend" "yes"))))))

(test-equal "decoy accepted, with --backend: one backend, named alike before and after the init"
  (list 0
        (append (list (cons 'loaded (in-scratch "accepted.so")) (cons 'source 'override))
                (decoy-report "DecoyTLS/1.0" "decoy-host")
                (list (cons 'protocols '()) once no-native-objects
                      (cons 'backend "DecoyTLS/1.0") (cons 'features-after decoy-features)
                      (cons 'calls (join every-call))))
        "")
  (probe-with (list (override (in-scratch "accepted.so"))) '("--backend" "yes")))

(decoy-case "version-null" '("-DDECOY_VERSION_NULL")
  "a NULL version is load-failed, and nothing runs after curl_version_info"
  (lambda (so) (refused 'load-failed so 'override "curl_version_info returned no version" '()
                        #f (list version-call))))

;; The report travels with every refusal made after the version was read
;; (ADR-0002).
(decoy-case "below-floor" '("-DDECOY_BELOW_FLOOR")
  "7.84.0 is below-floor, and nothing runs after curl_version_info"
  (lambda (so) (refused 'below-floor so 'override "7.84.0" '()
                        (report-of so 'override
                                   (decoy-report* "7.84.0" #x075400 decoy-features
                                                  "DecoyTLS/1.0" "decoy-host"))
                        (list version-call))))

(decoy-case "no-ssl" '("-DDECOY_NO_SSL")
  "no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info"
  (lambda (so) (refused 'no-ssl so 'override "7.85.0" '()
                        (report-of so 'override
                                   (decoy-report* "7.85.0" #x075500 (+ #x1 #x8)
                                                  "DecoyTLS/1.0" "decoy-host"))
                        (list version-call))))

(decoy-case "version-info-null" '("-DDECOY_VERSION_INFO_NULL")
  "curl_version_info answering NULL is load-failed, and nothing runs after it"
  (lambda (so) (refused 'load-failed so 'override "curl_version_info returned NULL" '()
                        #f (list version-call))))

(decoy-case "init-fails" '("-DDECOY_INIT_FAILS")
  "curl_global_init failing is load-failed, naming its code, and no probe runs"
  (lambda (so) (refused 'load-failed so 'override "curl_global_init returned 2" '()
                        (control so) (list version-call init-call))))

(decoy-case "options-off" '("-DDECOY_OPTIONS_OFF")
  "no option by name is missing-api, naming curl_easy_option_by_name, and the mime probe never runs"
  (lambda (so) (refused 'missing-api so 'override "curl_easy_option_by_name" '()
                        (control so) api-calls)))

(decoy-case "headers-off" '("-DDECOY_HEADERS_OFF")
  "CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header, and the mime probe never runs"
  (lambda (so) (refused 'missing-api so 'override "curl_easy_header" '()
                        (control so) api-calls)))

(decoy-case "easy-init-null" '("-DDECOY_EASY_INIT_NULL")
  "curl_easy_init answering NULL is load-failed, and curl_easy_header never runs"
  (lambda (so) (refused 'load-failed so 'override "curl_easy_init returned NULL" '()
                        (control so) (list version-call init-call backend-call option-call easy-init-call))))

(decoy-case "not-curl" '("-DDECOY_NOT_CURL")
  "a library with no curl_* function is missing-api, naming curl_version_info"
  (lambda (so) (refused 'missing-api so 'override "curl_version_info" '() #f '())))

;; A refusal sticks. The options-off decoy is refused at the last check,
;; after curl_global_init. Then CHEZ_CURL_LIBCURL names the control, built
;; with a marker, and the probe references loaded-libcurl twice more. Both
;; raise the first refusal again: nothing is loaded, initialised or probed
;; a second time, and the second library never enters the process
;; (ADR-0002).
(let ((first (in-scratch "sticks.so"))
      (second (in-scratch "sticks-then.so")))
  (test-equal "a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new"
    (list 0 0 1
          (list (cons 'reason 'missing-api) (cons 'path first) (cons 'source 'override)
                (cons 'detail "curl_easy_option_by_name") (cons 'candidates '())
                (cons 'library (control first))
                (cons 'then-override second)
                once no-native-objects (cons 'marker 'absent) (cons 'calls (join api-calls)))
          "")
    (let* ((compiled-first (compile-decoy "sticks" '("-DDECOY_OPTIONS_OFF")))
           (compiled-second (compile-decoy "sticks-then" '("-DDECOY_MARKER"))))
      (cons* compiled-first compiled-second
             (probe-with (list (override first))
                         (list "--then-override" second "--marker" "decoy_marker"))))))

;; The control for the marker: loaded, the build with DECOY_MARKER is seen.
(let ((marked (in-scratch "marked.so")))
  (test-equal "decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?"
    (list 0 (cons* (cons 'loaded marked) (cons 'source 'override)
                   (append (decoy-report "DecoyTLS/1.0" "decoy-host")
                           (list (cons 'protocols '()) once no-native-objects
                                 (cons 'marker 'present) (cons 'calls (join every-call)))))
          "")
    (let ((compiled (compile-decoy "marked" '("-DDECOY_MARKER"))))
      (if (eqv? compiled 0)
          (probe-with (list (override marked)) (list "--marker" "decoy_marker"))
          (list 'compile compiled)))))

;; Each entry point bound after curl_global_init, and curl_global_init
;; itself, left out one at a time: refused by name, never "no entry for".
(for-each
 (lambda (entry)
   (let ((name (car entry)) (calls (cdr entry)))
     (decoy-case (string-append "lacks-" name)
                 (list (string-append "-DDECOY_LACKS_" name))
                 (string-append "a library without " name " is missing-api, naming it")
                 (lambda (so) (refused 'missing-api so 'override name '() (control so) calls)))))
 (list (cons "curl_global_init" (list version-call))
       (cons "curl_easy_option_by_name" (list version-call init-call backend-call))
       (cons "curl_easy_init" (list version-call init-call backend-call))
       (cons "curl_easy_header" (list version-call init-call backend-call))
       (cons "curl_easy_cleanup" (list version-call init-call backend-call))
       (cons "curl_url" (list version-call init-call backend-call))
       (cons "curl_url_cleanup" (list version-call init-call backend-call))
       (cons "curl_url_set" (list version-call init-call backend-call))
       (cons "curl_url_get" (list version-call init-call backend-call))
       (cons "curl_url_strerror" (list version-call init-call backend-call))
       (cons "curl_free" (list version-call init-call backend-call))
       (cons "curl_easy_setopt" (list version-call init-call backend-call))
       (cons "curl_easy_getinfo" (list version-call init-call backend-call))
       (cons "curl_easy_strerror" (list version-call init-call backend-call))
       (cons "curl_easy_nextheader" (list version-call init-call backend-call))
       (cons "curl_slist_append" (list version-call init-call backend-call))
       (cons "curl_slist_free_all" (list version-call init-call backend-call))
       (cons "curl_multi_init" (list version-call init-call backend-call))
       (cons "curl_multi_cleanup" (list version-call init-call backend-call))
       (cons "curl_multi_add_handle" (list version-call init-call backend-call))
       (cons "curl_multi_remove_handle" (list version-call init-call backend-call))
       (cons "curl_multi_perform" (list version-call init-call backend-call))
       (cons "curl_multi_poll" (list version-call init-call backend-call))
       (cons "curl_multi_wakeup" (list version-call init-call backend-call))
       (cons "curl_multi_info_read" (list version-call init-call backend-call))
       (cons "curl_multi_strerror" (list version-call init-call backend-call))
       (cons "curl_easy_pause" (list version-call init-call backend-call))
       (cons "curl_share_init" (list version-call init-call backend-call))
       (cons "curl_share_cleanup" (list version-call init-call backend-call))
       (cons "curl_multi_setopt" (list version-call init-call backend-call))
       (cons "curl_share_setopt" (list version-call init-call backend-call))
       (cons "curl_mime_init" (list version-call init-call backend-call))
       (cons "curl_mime_free" (list version-call init-call backend-call))
       (cons "curl_mime_addpart" (list version-call init-call backend-call))
       (cons "curl_mime_name" (list version-call init-call backend-call))
       (cons "curl_mime_data" (list version-call init-call backend-call))
       (cons "curl_mime_filedata" (list version-call init-call backend-call))
       (cons "curl_mime_filename" (list version-call init-call backend-call))
       (cons "curl_mime_type" (list version-call init-call backend-call))
       (cons "curl_formfree" (list version-call init-call backend-call))
       (cons "curl_formadd" (list version-call init-call backend-call))))

;; --- the mime probe's no (ADR-0039) -------------------------------------------------
;; Each switch makes one of the probe's two calls say no, as a libcurl built
;; without mime does: curl_formadd's 7, a code no build answers the form,
;; and curl_mime_init's NULL. Each load still loads, every other request
;; with it, and a multipart body is refused at its check, naming what the
;; probe found; the control, beside them, passes the multipart rule, and
;; fails as a whole body does, where the decoy's curl_url answers NULL. So
;; a switch the probe did not read, or a no read as yes, fails its row.

;; whole-check : List
;; What curl-request-check answers on every decoy, past the multipart rule:
;; the decoy's curl_url answers NULL.
(define whole-check '(raised call-with-parsed-url "curl_url returned NULL: no memory for a handle"))

;; multipart-loaded : String (Listof Pair) Any (Listof String) -> Expected
;; The probe's whole answer with --multipart, for a decoy at SO that loads:
;; PROBE, what loaded-mime-probe answers; MULTIPART, the multipart body's
;; check; CALLS, the load's calls, then the checks' curl_url calls.
(define (multipart-loaded so probe multipart calls)
  (list 0
        (append (list (cons 'loaded so) (cons 'source 'override))
                (decoy-report "DecoyTLS/1.0" "decoy-host")
                (list (cons 'protocols '()) once (cons 'mime probe) (cons 'multipart multipart)
                      (cons 'whole whole-check) no-native-objects (cons 'calls (join calls))))
        ""))

(for-each
 (lambda (row)
   (let ((name (list-ref row 0)) (switches (list-ref row 1)) (description (list-ref row 2))
         (probe (list-ref row 3)) (multipart (list-ref row 4)) (calls (list-ref row 5)))
     (let ((so (in-scratch (string-append name ".so"))))
       (test-equal (string-append "decoy " name ", with --multipart: " description)
         (list 0 (multipart-loaded so probe multipart calls))
         (let ((compiled (compile-decoy name switches)))
           (list compiled (probe-with (list (override so)) '("--multipart" "yes"))))))))
 (list
  (list "mime-control" '()
        "curl_formadd answers 0 and curl_mime_init a mime: mime is there, and a multipart check passes the rule, failing where a whole body's does"
        '((formadd . 0) (mime-init . made)) whole-check
        (append every-call (list "curl_url()" "curl_url()")))
  (list "formadd-disabled" '("-DDECOY_FORMADD_DISABLED")
        "curl_formadd's CURL_FORMADD_DISABLED, 7, and no post: the load loads, and a multipart body is multipart-unsupported, naming the probe's answers"
        '((formadd . 7) (mime-init . made))
        '(refused multipart-unsupported body multipart (multipart ((formadd . 7) (mime-init . made))))
        (append api-calls (list formadd-call formfree-null-call mime-init-call mime-free-call "curl_url()")))
  (list "formadd-other" '("-DDECOY_FORMADD_OTHER")
        "curl_formadd's CURL_FORMADD_INCOMPLETE, 5, a code no build answers the load's form: counted as no"
        '((formadd . 5) (mime-init . made))
        '(refused multipart-unsupported body multipart (multipart ((formadd . 5) (mime-init . made))))
        (append api-calls (list formadd-call formfree-null-call mime-init-call mime-free-call "curl_url()")))
  (list "mime-init-null" '("-DDECOY_MIME_INIT_NULL")
        "curl_mime_init's NULL, with curl_formadd's 0: no mime, nothing to free, and a multipart body is multipart-unsupported"
        '((formadd . 0) (mime-init . null))
        '(refused multipart-unsupported body multipart (multipart ((formadd . 0) (mime-init . null))))
        (append api-calls (list formadd-call formfree-call mime-init-call "curl_url()")))))

;; --- the real libcurl ---------------------------------------------------------------

;; oracle-of : (U String #f) -> (U Report (List 'no-oracle Symbol Any))
;; What tests/libcurl-oracle.c reads from the library at PATH.
(define (oracle-of path)
  (if (string? path)
      (libcurl-oracle getenv path)
      (list 'no-oracle 'no-path path)))

;; protocols-of : (U String #f) -> (U (Listof String) (List 'no-oracle Symbol Any))
;; The protocol list tests/libcurl-oracle.c reads from the library at PATH.
(define (protocols-of path)
  (if (string? path)
      (libcurl-protocols-oracle getenv path)
      (list 'no-oracle 'no-path path)))

;; The probe, in this process's own environment: the libcurl a program here
;; would load, through the override when it is set, by discovery when not.
(define ambient (probe '()))

;; field : Any Symbol -> Any
;; The (KEY . VALUE) the probe printed for KEY, or (KEY . absent).
(define (field answer key)
  (or (and (pair? answer) (pair? (cdr answer)) (list? (cadr answer))
           (assq key (cadr answer)))
      (cons key 'absent)))

;; real-libcurl : (U String #f)
;; The path the probe loaded here.
(define real-libcurl
  (let ((path (cdr (field ambient 'loaded))))
    (and (absolute? path) path)))

(test-equal "the real libcurl: the probe, in this environment, loads one by absolute path"
  'loaded
  (if (and (pair? ambient) (eqv? (car ambient) 0) real-libcurl) 'loaded ambient))

;; real-report : (U Report (List 'no-oracle Symbol Any))
(define real-report (oracle-of real-libcurl))

;; report-field : (U Report (List 'no-oracle Symbol Any)) Symbol -> Pair
;; REPORT's (KEY . VALUE), or (KEY no-oracle) when the oracle failed.
(define (report-field report key)
  (or (and (list? report) (for-all pair? report) (assq key report))
      (list key 'no-oracle)))

(test-equal "the C oracle read the real libcurl"
  'read
  (if (eq? (car real-report) 'no-oracle) real-report 'read))

;; Field by field, so a failure names the field. Each side is (KEY .
;; VALUE): a raise is #f, never a match for a NULL field's (KEY . #f).
(for-each
 (lambda (key)
   (test-equal (string-append "the real libcurl: the probe's " (symbol->string key)
                              " is the C oracle's")
     (report-field real-report key)
     (field ambient key)))
 oracle-fields)

;; --- the oracle's temporary directory ----------------------------------------------
;; The oracle compiles into a directory from `mktemp -d` and removes it. The
;; path mktemp prints may hold a space (TMPDIR="/tmp/a b"), or a newline. It
;; was cut at the first whitespace, so the oracle compiled into "/tmp/a" and
;; then ran rm -rf on it. Each row keeps a canary directory beside the one
;; mktemp makes, and requires it to survive.

;; call-with-tmpdir : String (-> Any) -> Any
;; THUNK with TMPDIR set to DIR. Afterwards TMPDIR is put back to its old
;; value, or to /tmp when it was unset: putenv cannot unset, and /tmp is where
;; mktemp and capture-command go for an unset TMPDIR.
(define (call-with-tmpdir dir thunk)
  (let ((old (getenv "TMPDIR")))
    (dynamic-wind
      (lambda () (putenv "TMPDIR" dir))
      thunk
      (lambda () (putenv "TMPDIR" (or old "/tmp"))))))

(test-equal "the oracle, with TMPDIR holding a space: the same report, the directory beside it kept, its own removed"
  '(same kept removed)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (base)
       (let ((canary (string-append base "/can"))
             (spaced (string-append base "/can ary")))
         (capture-command (list "mkdir" canary spaced))
         (write-text-file (string-append canary "/keep") "keep\n")
         (let ((answer (call-with-tmpdir spaced (lambda () (oracle-of real-libcurl)))))
           (list (if (equal? answer real-report) 'same answer)
                 (if (file-exists? (string-append canary "/keep")) 'kept 'destroyed)
                 (if (null? (directory-list spaced)) 'removed 'left))))))))

(test-equal "the oracle, with a newline in TMPDIR: no oracle, and the directory named by the first line kept"
  '(no-oracle kept)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (base)
       (let ((canary (string-append base "/can"))
             (newlined (string-append base "/can\nary")))
         (capture-command (list "mkdir" canary newlined))
         (write-text-file (string-append canary "/keep") "keep\n")
         (let ((answer (call-with-tmpdir newlined (lambda () (oracle-of real-libcurl)))))
           (list (car answer)
                 (if (file-exists? (string-append canary "/keep")) 'kept 'destroyed))))))))

;; The oracle never raises, and removes its directory when something inside it
;; raises. Here the getenv it is handed does, once the directory exists.
(test-equal "the oracle, when a raise comes inside its directory: it answers no-oracle, and has removed the directory"
  '(no-oracle raised 1 ())
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (base)
       (let* ((seen '())
              (answer (call-with-tmpdir base
                        (lambda ()
                          (libcurl-oracle (lambda (name)
                                            (set! seen (directory-list base))
                                            (raise 'getenv-raised))
                                          "/unused")))))
         (list (car answer) (cadr answer) (length seen) (directory-list base)))))))

(test-equal "the real libcurl through the override: loaded, with the C oracle's report"
  (loaded real-libcurl 'override real-report (protocols-of real-libcurl) #f)
  (probe (list (override (or real-libcurl "/the-probe-loaded-nothing")))))

;; --- refusals no decoy reaches ---------------------------------------------------------

(test-equal "a bare name in the override is invalid-override, carrying it"
  (refused 'invalid-override #f 'override "libcurl.so.4" '() #f #f)
  (probe (list (override "libcurl.so.4"))))

;; loader-text : String -> (U String (List Symbol Any))
;; What Chez's loader says when it refuses PATH, formatted as the native
;; layer formats it: the oracle for load-failed's detail.
(define (loader-text path)
  (guard (e ((and (format-condition? e) (message-condition? e) (irritants-condition? e))
             (apply format (condition-message e) (condition-irritants e)))
            (#t (list 'unexpected-raise (describe e))))
    (load-shared-object path)
    (list 'loaded path)))

(define text-file (in-scratch "not-a-library.so"))
(write-text-file text-file "not a shared object\n")
(define text-file-refusal (loader-text text-file))

(test-equal "a text file is load-failed, with the loader's message"
  (refused 'load-failed text-file 'override text-file-refusal '() #f #f)
  (probe (list (override text-file))))

(define no-such-file (in-scratch "no-such-dir/libcurl.so.4"))
(define no-such-file-refusal (loader-text no-such-file))

(test-equal "a path that does not exist is load-failed, with the loader's message"
  (refused 'load-failed no-such-file 'override no-such-file-refusal '() #f #f)
  (probe (list (override no-such-file))))

;; --- a raise that is not a refusal ------------------------------------------------------
;; tests/fixtures/raising/curl.sls shadows src/'s (curl): its loaded-libcurl
;; raises a plain error. That is a bug, not a refusal, and the probe must
;; report it as a raise.

(define raising-libdirs "tests/fixtures/raising:src")

(define fixture-raise "Exception in loaded-libcurl: the raising fixture raises a plain error, not a refusal")

(test-equal "a raise that is not a refusal: the probe prints it as raised, and exits 2"
  (list 2 (list (cons 'raised fixture-raise)
                (cons 'again (list (list 'raised fixture-raise) (list 'raised fixture-raise)))
                no-native-objects)
        "")
  (as-data (spawn-in raising-libdirs '() "tests/refusal-probe.sps" '())))

;; --- discovery, with the override unset -------------------------------------------------
;; By platform first, then, on Linux, by world. Every branch asserts what
;; discovery must find there.

;; platform : (U 'linux 'macos 'other)
;; From the machine type, as ADR-0002 reads it: a name ending in le is
;; Linux, one ending in osx is macOS.
(define platform
  (let ((name (symbol->string (machine-type))))
    (cond ((string-suffix? "le" name) 'linux)
          ((string-suffix? "osx" name) 'macos)
          (else 'other))))

;; real-maps : (U String #f)
;; This process's /proc/self/maps, as the native layer reads it. A probe
;; runs the same Chez, so it lives in the same world.
(define real-maps
  (guard (e (#t #f))
    (call-with-port (open-file-input-port "/proc/self/maps" (file-options)
                                          (buffer-mode block)
                                          (make-transcoder (utf-8-codec)))
      get-string-all)))

(define world (libcurl-world (if (string? real-maps) real-maps #f)))

(define empty-home (in-scratch "home"))
(capture-command (list "mkdir" empty-home))

(define unset-override '("-u" "CHEZ_CURL_LIBCURL"))

(case platform
  ((macos)
   ;; Apple's, the one candidate, lives in the dyld shared cache.
   (test-equal "macos: with the override unset, discovery loads Apple's /usr/lib/libcurl.4.dylib"
     (loaded "/usr/lib/libcurl.4.dylib" 'macos-system (oracle-of "/usr/lib/libcurl.4.dylib")
             (protocols-of "/usr/lib/libcurl.4.dylib") #f)
     (probe unset-override)))
  ((linux)
   (case world
     ((guix)
      (let ((environment-libcurl
             (string-append (or (getenv "GUIX_ENVIRONMENT") "<GUIX_ENVIRONMENT unset>")
                            "/lib/libcurl.so.4")))
        (test-equal "guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4"
          (loaded environment-libcurl 'guix-environment (oracle-of environment-libcurl)
                  (protocols-of environment-libcurl) #f)
          (probe unset-override))

        ;; Only the three candidates no variable names are left, and none
        ;; of them exists here: the container has no /run/current-system.
        (test-equal "guix: with no profile to search, not-found lists every candidate checked"
          (refused 'not-found #f #f #f
                   (list (string-append empty-home "/.guix-home/profile/lib/libcurl.so.4")
                         (string-append empty-home "/.guix-profile/lib/libcurl.so.4")
                         "/run/current-system/profile/lib/libcurl.so.4")
                   #f #f)
          (probe (append unset-override
                         (list "-u" "GUIX_ENVIRONMENT" "-u" "GUIX_PROFILE"
                               (string-append "HOME=" empty-home)))))

        ;; GUIX_ENVIRONMENT's candidate exists, so it is chosen, but it is
        ;; a text file. GUIX_PROFILE's, next in line, is a real libcurl,
        ;; and must never be tried (ADR-0002).
        (let* ((broken-profile (in-scratch "broken-profile"))
               (broken-libcurl (string-append broken-profile "/lib/libcurl.so.4")))
          (capture-command (list "mkdir" "-p" (string-append broken-profile "/lib")))
          (write-text-file broken-libcurl "not a shared object\n")
          (let ((refusal (loader-text broken-libcurl)))
            (test-equal "guix: a candidate that fails to load is load-failed, and the next is never tried"
              (refused 'load-failed broken-libcurl 'guix-environment refusal '() #f #f)
              (probe (append unset-override
                             (list (string-append "GUIX_ENVIRONMENT=" broken-profile)
                                   (string-append "GUIX_PROFILE="
                                                  (or (getenv "GUIX_ENVIRONMENT") "/nonexistent"))
                                   (string-append "HOME=" empty-home)))))))))
     (else
      ;; No Guix profile is a candidate here, and the standard directories
      ;; cannot be emptied, so not-found cannot be built: discovery must
      ;; load the first standard candidate that exists.
      (let ((first-standard
             (find file-exists? (map car (libcurl-candidates 'fhs (machine-type) getenv)))))
        (test-equal "fhs: with the override unset, discovery loads the first standard candidate that exists, source system"
          (loaded first-standard 'system (oracle-of first-standard) (protocols-of first-standard) #f)
          (probe unset-override))))))
  (else
   (test-equal "another platform: with the override unset, not-found, having no candidate"
     (refused 'not-found #f #f #f '() #f #f)
     (probe unset-override))))

;; --- make build's preflight -------------------------------------------------------------
;; The preflight's output is its contract: what make build tells a person
;; installing chez-curl. So these tests assert all of it, message text
;; included. Every refusal test above asserts the reason symbol and the
;; fields, never a message (ADR-0002): keep it that way.

;; preflight : (Listof String) -> (U (List Integer String String) (List 'raised String))
(define (preflight env-args)
  (spawn env-args "tests/preflight.sps" '()))

;; accepted-text : String Symbol Report -> (U String (List 'unbuildable String))
;; What the preflight prints on stdout when it accepts the library at PATH,
;; which reports REPORT. The feature names come from (curl private
;; verify), which tests/test-verify.sps holds to curl.h.
(define (accepted-text path source report)
  (guard (e (#t (list 'unbuildable (describe e))))
    (let ((value (lambda (key) (cdr (assq key report))))
          (or-none (lambda (s) (or s "none"))))
      (string-append "chez-curl: libcurl loaded and accepted\n"
                     "  path:     " path " (" (symbol->string source) ")\n"
                     "  version:  " (value 'version) "\n"
                     "  TLS:      " (or-none (value 'ssl-version)) "\n"
                     "  features: " (words (feature-names (value 'features))) "\n"
                     "  host:     " (or-none (value 'host)) "\n"))))

(let ((so (in-scratch "accepted.so")))
  (test-equal "preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host"
    (list 0
          (string-append "chez-curl: libcurl loaded and accepted\n"
                         "  path:     " so " (override)\n"
                         "  version:  7.85.0\n"
                         "  TLS:      DecoyTLS/1.0\n"
                         "  features: ipv6 ssl libz http2 threadsafe\n"
                         "  host:     decoy-host\n")
          "")
    (preflight (list (override so)))))

(test-equal "preflight, the real libcurl: exit 0, with the C oracle's report"
  (list 0 (accepted-text (or real-libcurl "?") 'override real-report) "")
  (preflight (list (override (or real-libcurl "/the-probe-loaded-nothing")))))

(test-equal "preflight, a bare name: exit 1, refused as invalid-override, with the remedy"
  (list 1 ""
        (string-append "chez-curl: libcurl refused\n"
                       "(reason . invalid-override)\n"
                       "  path:       none\n"
                       "  source:     override\n"
                       "  detail:     libcurl.so.4\n"
                       "  candidates: none\n"
                       "  remedy:     CHEZ_CURL_LIBCURL must be an absolute path to libcurl, which is loaded as given and never searched for; set one, or unset it to use discovery\n"))
  (preflight (list (override "libcurl.so.4"))))

(let ((so (in-scratch "below-floor.so")))
  (test-equal "preflight, the below-floor decoy: exit 1, naming the version, TLS and features it read"
    (list 1 ""
          (string-append "chez-curl: libcurl refused\n"
                         "(reason . below-floor)\n"
                         "  path:       " so "\n"
                         "  source:     override\n"
                         "  detail:     7.84.0\n"
                         "  version:    7.84.0\n"
                         "  TLS:        DecoyTLS/1.0\n"
                         "  features:   ipv6 ssl libz http2 threadsafe\n"
                         "  candidates: none\n"
                         "  remedy:     libcurl 7.84.0 is older than chez-curl's floor, 7.85.0; name a newer one with CHEZ_CURL_LIBCURL\n"))
    (preflight (list (override so)))))

(test-equal "preflight, a raise that is not a refusal: Chez's default handler, exit 255, and no reason line"
  (list 255 "" (string-append fixture-raise "\n"))
  (spawn-in raising-libdirs '() "tests/preflight.sps" '()))

(when (and (eq? platform 'linux) (eq? world 'guix))
  (test-equal "preflight, guix, no profile to search: exit 1, not-found, every candidate on its own line"
    (list 1 ""
          (string-append "chez-curl: libcurl refused\n"
                         "(reason . not-found)\n"
                         "  path:       none\n"
                         "  source:     none\n"
                         "  detail:     none\n"
                         "  candidates:\n"
                         "    " empty-home "/.guix-home/profile/lib/libcurl.so.4\n"
                         "    " empty-home "/.guix-profile/lib/libcurl.so.4\n"
                         "    /run/current-system/profile/lib/libcurl.so.4\n"
                         "  remedy:     no libcurl found among the candidates; name one with CHEZ_CURL_LIBCURL, an absolute path\n"))
    (preflight (append unset-override
                       (list "-u" "GUIX_ENVIRONMENT" "-u" "GUIX_PROFILE"
                             (string-append "HOME=" empty-home))))))

;; --- (curl) itself, expanded here, never invoked ------------------------------------------

(define (symbol<? a b) (string<? (symbol->string a) (symbol->string b)))

;; curl-exports : (U (Listof Symbol) (List 'not-expanded String))
(define curl-exports
  (guard (e (#t (list 'not-expanded (describe e))))
    (environment '(curl))
    (list-sort symbol<? (library-exports '(curl)))))

(test-equal "(curl) exports loaded-libcurl, the info record's accessors, the request, four URL functions and the response, the engine, the submit's checks alone, the cookie jar, the token, its streamed response's head, pieces and port, its streamed body's room, puts, end and count, and the mailbox, and the conditions, a failed transfer's classes and the engine's among them; none of their constructors, nor the request's private fields, nor the engine's seams, counts and faults"
  (list-sort symbol<?
             '(loaded-libcurl
               libcurl-info? libcurl-info-path libcurl-info-source libcurl-info-version
               libcurl-info-version-number libcurl-info-features libcurl-info-feature-names
               libcurl-info-ssl-version libcurl-info-host
               &curl-error curl-error?
               &curl-library-unavailable curl-library-unavailable?
               curl-library-unavailable-reason curl-library-unavailable-path
               curl-library-unavailable-source curl-library-unavailable-detail
               curl-library-unavailable-candidates curl-library-unavailable-library
               curl-library-unavailable-reasons
               &curl-wrong-thread curl-wrong-thread?
               curl-wrong-thread-who curl-wrong-thread-expected curl-wrong-thread-actual
               make-curl-request curl-request-with curl-request?
               curl-request-url curl-request-method curl-request-headers curl-request-body
               curl-request-user-agent curl-request-timeout-ms curl-request-connect-timeout-ms
               curl-request-body-limit curl-request-ca-file curl-request-verify curl-request-proxy
               curl-request-stream-buffer curl-request-body-length curl-request-http-version
               curl-request-credentials curl-request-proxy-ca-file curl-request-proxy-verify
               curl-request-cookie-jar
               curl-url-part curl-url-append-query curl-url-resolve curl-url-with-fragment
               curl-response? curl-response-status curl-response-http-version
               curl-response-effective-url curl-response-headers curl-response-body
               curl-response-timings
               make-curl-engine curl-engine? curl-engine-stop curl-submit curl-request-check
               make-curl-cookie-jar curl-cookie-jar? curl-cookie-jar-cookies curl-cookie-jar-load!
               curl-cookie-jar-close!
               curl-token? curl-token-await curl-token-wait curl-token-cancel curl-token-done?
               curl-token-outcome
               curl-token-head-wait curl-token-head curl-head? curl-head-status
               curl-head-http-version curl-head-headers curl-head-body-asked? curl-token-next-piece
               curl-token-body-port
               curl-token-room-wait curl-token-put-piece! curl-token-end-body! curl-token-body-count
               make-curl-mailbox curl-mailbox? curl-mailbox-take curl-mailbox-deliver
               &curl-embedded-nul curl-embedded-nul? curl-embedded-nul-string
               &curl-url-error curl-url-error? curl-url-error-input curl-url-error-reason
               curl-url-error-code curl-url-error-message
               &curl-request-error curl-request-error? curl-request-error-field
               curl-request-error-value curl-request-error-reason curl-request-error-reasons
               &curl-transfer-error curl-transfer-error? curl-transfer-error-reason
               curl-transfer-error-code curl-transfer-error-option curl-transfer-error-strerror
               curl-transfer-error-error-buffer curl-transfer-error-recorded
               curl-transfer-error-request-size curl-transfer-error-connect-code
               curl-transfer-error-reasons
               &curl-timeout curl-timeout? &curl-connect-error curl-connect-error?
               &curl-send-receive-error curl-send-receive-error? &curl-tls-error curl-tls-error?
               &curl-protocol-error curl-protocol-error? &curl-too-large curl-too-large?
               &curl-engine-error curl-engine-error? curl-engine-error-reason
               curl-engine-error-condition curl-engine-error-reasons))
  curl-exports)

;; Re-exported, not redefined: each is (curl private conditions)'s own, so
;; a guard in a caller of (curl) catches what (curl private ...) raises.
(define re-exported
  '(curl-error? curl-library-unavailable? curl-library-unavailable-reason
    curl-library-unavailable-path curl-library-unavailable-source
    curl-library-unavailable-detail curl-library-unavailable-candidates
    curl-library-unavailable-library
    curl-library-unavailable-reasons curl-wrong-thread? curl-wrong-thread-who
    curl-wrong-thread-expected curl-wrong-thread-actual
    curl-embedded-nul? curl-embedded-nul-string curl-url-error? curl-url-error-reason
    curl-request-error? curl-request-error-reason curl-request-error-reasons
    curl-transfer-error? curl-transfer-error-reason curl-transfer-error-request-size
    curl-transfer-error-connect-code
    curl-timeout? curl-connect-error? curl-send-receive-error? curl-tls-error?
    curl-protocol-error? curl-too-large?
    curl-engine-error? curl-engine-error-reason curl-engine-error-condition
    curl-engine-error-reasons
    (record-type-descriptor &curl-error)
    (record-type-descriptor &curl-library-unavailable)
    (record-type-descriptor &curl-wrong-thread)
    (record-type-descriptor &curl-embedded-nul)
    (record-type-descriptor &curl-url-error)
    (record-type-descriptor &curl-request-error)
    (record-type-descriptor &curl-transfer-error)
    (record-type-descriptor &curl-timeout)
    (record-type-descriptor &curl-too-large)
    (record-type-descriptor &curl-engine-error)))

(test-equal "(curl)'s conditions are (curl private conditions)'s own"
  (map (lambda (form) 'same) re-exported)
  (guard (e (#t (list 'raised (describe e))))
    (let ((public (environment '(rnrs) '(curl)))
          (private (environment '(rnrs) '(curl private conditions))))
      (map (lambda (form)
             (if (eq? (eval form public) (eval form private)) 'same 'different))
           re-exported))))

;; The report's accessors are (curl private libcurl-info)'s own, a library
;; whose body cannot raise. Were they (curl private native)'s, reading a
;; refusal's report would reference native and raise that refusal again.
(define report-accessors
  '(libcurl-info? libcurl-info-path libcurl-info-source libcurl-info-version
    libcurl-info-version-number libcurl-info-features libcurl-info-feature-names
    libcurl-info-ssl-version libcurl-info-host))

(test-equal "(curl)'s report accessors are (curl private libcurl-info)'s own"
  (map (lambda (name) 'same) report-accessors)
  (guard (e (#t (list 'raised (describe e))))
    (let ((public (environment '(rnrs) '(curl)))
          (private (environment '(rnrs) '(curl private libcurl-info))))
      (map (lambda (name)
             (if (eq? (eval name public) (eval name private)) 'same 'different))
           report-accessors))))

(test-equal "this suite's own process never loaded libcurl"
  'not-loaded
  (if (foreign-entry? "curl_version_info") 'loaded 'not-loaded))

;; --- cleaning up ------------------------------------------------------------------------

(remove-temp-directory scratch)

(test-equal "the scratch directory is removed"
  'removed
  (if (file-directory? scratch) 'left 'removed))

(test-end "library-loading")

(exit (suite-exit-status runner))
