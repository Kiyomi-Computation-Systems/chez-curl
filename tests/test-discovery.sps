#!r6rs
;;; The suite for (curl private discovery): ADR-0002's search for libcurl,
;;; as a pure function, on synthetic inputs. Each rule has a test that fails
;;; by name when the rule is relaxed:
;;;
;;;   - the override: an absolute CHEZ_CURL_LIBCURL is taken as given, never
;;;     checked with exists?, on every platform; anything else set, the empty
;;;     string too, is invalid-override, with no fallback;
;;;   - the platform comes from the machine type: ...le is Linux, ...osx is
;;;     macOS, any other has no candidates;
;;;   - the world: Guix when some line of /proc/self/maps names a libc.so.6
;;;     under /gnu/store/, FHS otherwise, and only on Linux;
;;;   - a Guix world never yields a standard directory, and an FHS world never
;;;     a Guix profile, even when one exists;
;;;   - each world's list, in order, and the first that exists wins;
;;;   - an unset or relative GUIX_ENVIRONMENT, GUIX_PROFILE or HOME
;;;     contributes nothing;
;;;   - the GnuTLS build only when no libcurl.so.4 exists;
;;;   - the triple table: ta6le and tarm64le;
;;;   - macOS's one candidate, without exists?;
;;;   - not-found lists every path it checked, in order.
;;;
;;; Then the real /proc/self/maps: the world it gives must agree with
;;; whether this Chez's own binary lies under /gnu/store/, which holds in the
;;; Guix container and on an FHS CI runner alike.
;;;
;;; Each expected value is one the code under test cannot produce by failing.
;;; SRFI-64 turns a raise in the actual expression into #f, so no expected
;;; value here is #f: every call goes through `outcome`, which names what
;;; was raised or returned.
(import (rnrs)
        (srfi :64)
        (curl-testing)
        (only (chezscheme) get-process-id machine-type)
        (curl private conditions)
        (curl private discovery))

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

;; outcome : (-> Any ...) -> (U (Cons 'chose (Listof Any))
;;                              (List 'refused Symbol Any Any Any Any)
;;                              (List 'assertion-violation Any)
;;                              (List 'other-raise String))
;; What THUNK did: returned its values, raised &curl-library-unavailable
;; (its reason, path, source, detail and candidates), raised an assertion
;; violation (its who), or raised something else.
(define (outcome thunk)
  (guard (e ((curl-library-unavailable? e)
             (list 'refused
                   (curl-library-unavailable-reason e)
                   (curl-library-unavailable-path e)
                   (curl-library-unavailable-source e)
                   (curl-library-unavailable-detail e)
                   (curl-library-unavailable-candidates e)))
            ((and (assertion-violation? e) (who-condition? e))
             (list 'assertion-violation (condition-who e)))
            (#t (list 'other-raise (describe e))))
    (call-with-values thunk (lambda results (cons 'chose results)))))

;; env : (Listof (Pairof String String)) -> (String -> (U String #f))
;; A getenv that knows only BINDINGS.
(define (env bindings)
  (lambda (name)
    (let ((binding (assoc name bindings)))
      (and binding (cdr binding)))))

;; present : String ... -> (String -> Boolean)
;; An exists? for which only PATHS exist.
(define (present . paths)
  (lambda (path) (and (member path paths) #t)))

(define nothing (present))
(define (everything path) #t)

;; choose : Bindings Symbol (U String #f) (String -> Boolean) -> Outcome
(define (choose bindings machine maps exists?)
  (outcome (lambda () (choose-libcurl (env bindings) machine maps exists?))))

;; choose/asked : Bindings Symbol (U String #f) (String -> Boolean)
;;                -> (List Outcome (Listof String))
;; choose's outcome, then every path it asked EXISTS? about, in order.
(define (choose/asked bindings machine maps exists?)
  (let* ((asked '())
         (probe (lambda (path) (set! asked (cons path asked)) (exists? path)))
         (result (choose bindings machine maps probe)))
    (list result (reverse asked))))

;; --- fixtures ------------------------------------------------------------------

;; A Guix user's environment: every variable discovery may read is set, each
;; to its own value.
(define guix-vars
  '(("GUIX_ENVIRONMENT" . "/gnu/store/aaa-profile")
    ("GUIX_PROFILE" . "/home/ana/work/profile")
    ("HOME" . "/home/ana")))

(define g-env     "/gnu/store/aaa-profile/lib/libcurl.so.4")
(define g-profile "/home/ana/work/profile/lib/libcurl.so.4")
(define g-home    "/home/ana/.guix-home/profile/lib/libcurl.so.4")
(define g-user    "/home/ana/.guix-profile/lib/libcurl.so.4")
(define g-system  "/run/current-system/profile/lib/libcurl.so.4")

(define guix-list
  (list (cons g-env 'guix-environment)
        (cons g-profile 'guix-profile)
        (cons g-home 'guix-home)
        (cons g-user 'guix-user-profile)
        (cons g-system 'guix-system)))

(define f-local  "/usr/local/lib/libcurl.so.4")
(define f-triple "/usr/lib/x86_64-linux-gnu/libcurl.so.4")
(define f-lib64  "/usr/lib64/libcurl.so.4")
(define f-lib    "/usr/lib/libcurl.so.4")
(define f-gnutls "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4")

(define fhs-list
  (list (cons f-local 'system)
        (cons f-triple 'system)
        (cons f-lib64 'system)
        (cons f-lib 'system)
        (cons f-gnutls 'system)))

(define override "/opt/curl/lib/libcurl.so.4")

(define (with-override value)
  (cons (cons "CHEZ_CURL_LIBCURL" value) guix-vars))

;; Guix Chez's maps, cut down: libc is on the third line, after the binary,
;; itself under /gnu/store/.
(define guix-maps
  (string-append
   "00400000-00409000 r--p 00000000 fc:01 9450589                            /gnu/store/nrl-chez-scheme-10.4.0/lib/csv10.4.0/ta6le/scheme\n"
   "14b8c000-14bad000 rw-p 00000000 00:00 0                                  [heap]\n"
   "71486b199000-71486b1c1000 r--p 00000000 fc:01 5153215                    /gnu/store/m31-glibc-2.41/lib/libc.so.6\n"
   "7ffd5a3e2000-7ffd5a403000 rw-p 00000000 00:00 0                          [stack]\n"))

;; A host-built Chez's maps, cut down.
(define fhs-maps
  (string-append
   "55d0c0a00000-55d0c0a09000 r--p 00000000 08:02 1234                       /usr/local/bin/scheme\n"
   "7f1e2a000000-7f1e2a028000 r--p 00000000 08:02 5678                       /usr/lib/x86_64-linux-gnu/libc.so.6\n"
   "7ffd5a3e2000-7ffd5a403000 rw-p 00000000 00:00 0                          [stack]\n"))

;; maps-line : String -> String
;; One line of /proc/self/maps naming PATH.
(define (maps-line path)
  (string-append "7f1e2b000000-7f1e2b028000 r--p 00000000 08:02 9999                       "
                 path "\n"))

(test-begin "discovery")

;; --- the override -------------------------------------------------------------

;; Every Guix candidate exists, so only the override can be chosen.
(test-equal "override: an absolute CHEZ_CURL_LIBCURL is chosen as given, with source override"
  `(chose ,override override)
  (choose (with-override override) 'ta6le guix-maps everything))

(test-equal "override: it is never checked with exists?, since loading decides"
  `((chose ,override override) ())
  (choose/asked (with-override override) 'ta6le guix-maps nothing))

(test-equal "override: a relative path is invalid-override, carrying the value, with no fallback"
  '(refused invalid-override #f override "lib/libcurl.so.4" ())
  (choose (with-override "lib/libcurl.so.4") 'ta6le guix-maps everything))

(test-equal "override: a bare name is invalid-override"
  '(refused invalid-override #f override "libcurl.so.4" ())
  (choose (with-override "libcurl.so.4") 'ta6le guix-maps everything))

(test-equal "override: set but empty is invalid-override"
  '(refused invalid-override #f override "" ())
  (choose (with-override "") 'ta6le guix-maps everything))

(test-equal "override: chosen on macOS, over Apple's"
  `(chose ,override override)
  (choose (with-override override) 'tarm64osx #f everything))

(test-equal "override: chosen on a platform with no list"
  `(chose ,override override)
  (choose (with-override override) 'ta6fb #f everything))

;; --- the platform, from the machine type ----------------------------------------

;; trv64le has no triple, so its list is the three plain directories.
(test-equal "platform: a machine type ending in le is Linux"
  `(chose ,f-lib system)
  (choose guix-vars 'trv64le fhs-maps (present f-lib)))

(test-equal "platform: a machine type ending in osx is macOS, on both architectures"
  '((chose "/usr/lib/libcurl.4.dylib" macos-system)
    (chose "/usr/lib/libcurl.4.dylib" macos-system))
  (list (choose guix-vars 'ta6osx #f everything)
        (choose guix-vars 'tarm64osx #f everything)))

;; The Guix maps text and a world where everything exists: neither may
;; produce a candidate on these platforms.
(test-equal "platform: any other has no candidates, so not-found with an empty list"
  '((refused not-found #f #f #f ())
    (refused not-found #f #f #f ())
    (refused not-found #f #f #f ()))
  (map (lambda (machine) (choose guix-vars machine guix-maps everything))
       '(ta6fb ta6nt ta6s2)))

;; --- macOS --------------------------------------------------------------------

(test-equal "macos: Apple's /usr/lib/libcurl.4.dylib, returned without asking exists?"
  '((chose "/usr/lib/libcurl.4.dylib" macos-system) ())
  (choose/asked guix-vars 'tarm64osx #f nothing))

(test-equal "macos: the world is not consulted, so a Guix maps text changes nothing"
  '(chose "/usr/lib/libcurl.4.dylib" macos-system)
  (choose guix-vars 'tarm64osx guix-maps everything))

;; --- the world ----------------------------------------------------------------

(test-equal "world: libc.so.6 under /gnu/store/, on any line, is guix"
  'guix
  (libcurl-world guix-maps))

(test-equal "world: libc.so.6 under /usr/lib is fhs"
  'fhs
  (libcurl-world fhs-maps))

(test-equal "world: an unreadable /proc/self/maps, #f, is fhs"
  'fhs
  (libcurl-world #f))

(test-equal "world: other libraries from /gnu/store/ in an FHS process are fhs"
  'fhs
  (libcurl-world (string-append fhs-maps
                                (maps-line "/gnu/store/xyz-curl-8.20.0/lib/libcurl.so.4.8.0")
                                (maps-line "/gnu/store/m31-glibc-2.41/lib/libm.so.6"))))

(test-equal "world: a basename that only resembles libc.so.6 is fhs"
  'fhs
  (libcurl-world (string-append fhs-maps
                                (maps-line "/gnu/store/aaa-libc.so.6/lib/libm.so.6")
                                (maps-line "/gnu/store/bbb-glibc/lib/libc.so.6.1")
                                (maps-line "/gnu/store/ccc-glibc/lib/xlibc.so.6"))))

(test-equal "world: libc.so.6 under a /gnu/store/ that is not at the root is fhs"
  'fhs
  (libcurl-world (string-append fhs-maps
                                (maps-line "/opt/gnu/store/ddd-glibc/lib/libc.so.6"))))

;; --- the loaded library's file (ADR-0024) ----------------------------------------

;; curl-maps : String
;; Two libcurl mappings, its text and its data, beside libc's, a heap with
;; no file, and a line whose range is no hex.
(define curl-maps
  (string-append
   "7f1e2a000000-7f1e2a028000 r--p 00000000 08:02 5678                       /usr/lib/x86_64-linux-gnu/libc.so.6\n"
   "7f1e2c000000-7f1e2c0a0000 r-xp 00010000 fc:01 7777                       /gnu/store/abc-curl-8.20.0/lib/libcurl.so.4.8.0\n"
   "7f1e2c0a0000-7f1e2c0b0000 rw-p 000a0000 fc:01 7777                       /gnu/store/abc-curl-8.20.0/lib/libcurl.so.4.8.0\n"
   "14b8c000-14bad000 rw-p 00000000 00:00 0                                  [heap]\n"
   "7f1e2dzz0000-7f1e2e000000 r--p 00000000 08:02 1 /not/hex\n"))

(test-equal "mapped-file: the line whose range holds the address names the file, at the range's first byte and its last, in its data as in its text; the libc line its own"
  '("/gnu/store/abc-curl-8.20.0/lib/libcurl.so.4.8.0" "/gnu/store/abc-curl-8.20.0/lib/libcurl.so.4.8.0"
    "/gnu/store/abc-curl-8.20.0/lib/libcurl.so.4.8.0" "/gnu/store/abc-curl-8.20.0/lib/libcurl.so.4.8.0"
    "/usr/lib/x86_64-linux-gnu/libc.so.6")
  (map (lambda (address) (mapped-file curl-maps address))
       (list #x7f1e2c000000 #x7f1e2c09ffff #x7f1e2c0a0000 #x7f1e2c0affff #x7f1e2a000010)))

(test-equal "mapped-file: #f for an address past a range's end, which is not its own, below every range, in a mapping with no file, in a line that is no hex, and for an unreadable maps, #f"
  '(#f #f #f #f #f)
  (list (mapped-file curl-maps #x7f1e2c0b0000)
        (mapped-file curl-maps #x1000)
        (mapped-file curl-maps #x14b8c010)
        (mapped-file curl-maps #x7f1e2df00000)
        (mapped-file #f #x7f1e2c000000)))

(test-equal "mapped-file: upper-case hex is read too, and the last line needs no newline"
  "/x/libcurl.so.4"
  (mapped-file "7F1E2C000000-7F1E2C0A0000 r-xp 00000000 fc:01 1 /x/libcurl.so.4" #x7f1e2c000001))

(test-equal "bytes-hold?: a pattern at the start, inside, and at the very end, after a partial match that breaks off; not one cut short at the end, nor one absent, nor in an empty bytevector"
  '(#t #t #t #f #f #f)
  (map (lambda (text) (bytes-hold? (string->utf8 text) (string->utf8 "SSL_CERT_FILE")))
       (list "SSL_CERT_FILE\x0;rest" "x\x0;SSL_CERT_FILE\x0;y" "SSL_CERT_FILSSL_CERT_FILE"
             "abc SSL_CERT_FIL" "SSL_CERT_DIR SSL_CERT_FIL3" "")))

(test-equal "bytes-hold?: an empty pattern is an assertion violation"
  'assertion-violation
  (guard (e ((assertion-violation? e) 'assertion-violation) (#t (list 'raised e)))
    (bytes-hold? (string->utf8 "abc") (make-bytevector 0))
    'no-raise))

(test-equal "backend-in-use: the text outside parentheses, trimmed, its version kept: Apple's 8.7.1 after the init and before it, a single backend's, OpenSSL's; a version with spaces, alone and beside a group, a group with spaces, a group between two, nested and unclosed groups; #f for groups alone, the empty string, spaces alone and #f"
  '("LibreSSL/3.3.6" "SecureTransport" "GnuTLS/3.8.13" "OpenSSL/3.0.13"
    "OpenSSL/1.1.1k FIPS" "OpenSSL/1.1.1k FIPS" "OpenSSL/3.0.13" "B/2" "A/1" "A/1"
    #f #f #f #f)
  (map backend-in-use
       (list "(SecureTransport) LibreSSL/3.3.6" "SecureTransport (LibreSSL/3.3.6)" "GnuTLS/3.8.13"
             "OpenSSL/3.0.13" "OpenSSL/1.1.1k FIPS" "(x/1) OpenSSL/1.1.1k FIPS"
             "(NSS/3.21 Basic ECC) OpenSSL/3.0.13" "(A/1) B/2 (C/3)" "A/1 ((B/2) C/3)" "A/1 (B/2"
             "(a) (b)" "" "   " #f)))

;; --- the Guix world -------------------------------------------------------------

(test-equal "guix: the candidate list, in ADR-0002's order"
  guix-list
  (libcurl-candidates 'guix 'ta6le (env guix-vars)))

(test-equal "guix: GUIX_ENVIRONMENT unset contributes nothing"
  (cdr guix-list)
  (libcurl-candidates 'guix 'ta6le
                      (env '(("GUIX_PROFILE" . "/home/ana/work/profile")
                             ("HOME" . "/home/ana")))))

(test-equal "guix: GUIX_ENVIRONMENT set but empty contributes nothing"
  (cdr guix-list)
  (libcurl-candidates 'guix 'ta6le
                      (env (cons '("GUIX_ENVIRONMENT" . "") (cdr guix-vars)))))

(test-equal "guix: a relative GUIX_PROFILE contributes nothing"
  (list (cons g-env 'guix-environment)
        (cons g-home 'guix-home)
        (cons g-user 'guix-user-profile)
        (cons g-system 'guix-system))
  (libcurl-candidates 'guix 'ta6le
                      (env '(("GUIX_ENVIRONMENT" . "/gnu/store/aaa-profile")
                             ("GUIX_PROFILE" . "work/profile")
                             ("HOME" . "/home/ana")))))

(test-equal "guix: HOME unset contributes neither home candidate"
  (list (cons g-env 'guix-environment)
        (cons g-profile 'guix-profile)
        (cons g-system 'guix-system))
  (libcurl-candidates 'guix 'ta6le
                      (env '(("GUIX_ENVIRONMENT" . "/gnu/store/aaa-profile")
                             ("GUIX_PROFILE" . "/home/ana/work/profile")))))

(test-equal "guix: a relative HOME contributes neither home candidate"
  (list (cons g-env 'guix-environment)
        (cons g-profile 'guix-profile)
        (cons g-system 'guix-system))
  (libcurl-candidates 'guix 'ta6le
                      (env '(("GUIX_ENVIRONMENT" . "/gnu/store/aaa-profile")
                             ("GUIX_PROFILE" . "/home/ana/work/profile")
                             ("HOME" . "home/ana")))))

(test-equal "guix: a standard directory is never chosen, even when every one exists"
  `(refused not-found #f #f #f ,(map car guix-list))
  (choose guix-vars 'ta6le guix-maps (apply present (map car fhs-list))))

;; tails : (Listof A) -> (Listof (Listof A))
;; Each nonempty tail of XS, longest first.
(define (tails xs)
  (if (null? xs) '() (cons xs (tails (cdr xs)))))

;; Candidate i and every one after it exist: candidate i must win.
(test-equal "guix: precedence: each candidate wins over every one after it"
  (map (lambda (c) (list 'chose (car c) (cdr c))) guix-list)
  (map (lambda (tail) (choose guix-vars 'ta6le guix-maps (apply present (map car tail))))
       (tails guix-list)))

(test-equal "guix: probing asks in order, and stops at the first that exists"
  `((chose ,g-home guix-home) (,g-env ,g-profile ,g-home))
  (choose/asked guix-vars 'ta6le guix-maps (present g-home g-system)))

;; --- the FHS world --------------------------------------------------------------

(test-equal "fhs: the candidate list for ta6le, in ADR-0002's order"
  fhs-list
  (libcurl-candidates 'fhs 'ta6le (env guix-vars)))

(test-equal "fhs: the candidate list for tarm64le, under aarch64-linux-gnu"
  '(("/usr/local/lib/libcurl.so.4" . system)
    ("/usr/lib/aarch64-linux-gnu/libcurl.so.4" . system)
    ("/usr/lib64/libcurl.so.4" . system)
    ("/usr/lib/libcurl.so.4" . system)
    ("/usr/lib/aarch64-linux-gnu/libcurl-gnutls.so.4" . system))
  (libcurl-candidates 'fhs 'tarm64le (env guix-vars)))

(test-equal "fhs: an unknown Linux machine type has no triple directory"
  '(("/usr/local/lib/libcurl.so.4" . system)
    ("/usr/lib64/libcurl.so.4" . system)
    ("/usr/lib/libcurl.so.4" . system))
  (libcurl-candidates 'fhs 'trv64le (env guix-vars)))

(test-equal "fhs: a Guix profile is never chosen, even when every one exists"
  `(refused not-found #f #f #f ,(map car fhs-list))
  (choose guix-vars 'ta6le fhs-maps (apply present (map car guix-list))))

(test-equal "fhs: precedence: each candidate wins over every one after it"
  (map (lambda (c) (list 'chose (car c) (cdr c))) fhs-list)
  (map (lambda (tail) (choose guix-vars 'ta6le fhs-maps (apply present (map car tail))))
       (tails fhs-list)))

(test-equal "fhs: the GnuTLS build is chosen only when no libcurl.so.4 exists"
  `((chose ,f-lib system) (chose ,f-gnutls system))
  (list (choose guix-vars 'ta6le fhs-maps (present f-lib f-gnutls))
        (choose guix-vars 'ta6le fhs-maps (present f-gnutls))))

(test-equal "libcurl-candidates refuses a Linux world that is neither guix nor fhs"
  '(assertion-violation libcurl-candidates)
  (outcome (lambda () (libcurl-candidates 'nix 'ta6le (env guix-vars)))))

(test-equal "triple table: ta6le and tarm64le, and no other machine type"
  '("x86_64-linux-gnu" "aarch64-linux-gnu" #f #f #f #f)
  (map linux-triple '(ta6le tarm64le a6le arm64le ti3le tarm64osx)))

;; --- not-found, and what discovery reads -------------------------------------------

(test-equal "not-found lists every path it checked, in order, with no path, source or detail"
  `((refused not-found #f #f #f ,(map car fhs-list)) ,(map car fhs-list))
  (choose/asked guix-vars 'ta6le fhs-maps nothing))

(test-equal "choose-libcurl: every refusal carries a who and a message, for the default handler"
  '(readable readable)
  (map (lambda (thunk)
         (guard (e ((curl-library-unavailable? e)
                    (if (and (who-condition? e) (message-condition? e)) 'readable 'bare))
                   (#t 'other-raise))
           (thunk)
           'no-raise))
       (list (lambda () (choose-libcurl (env (with-override "libcurl.so.4")) 'ta6le #f nothing))
             (lambda () (choose-libcurl (env guix-vars) 'ta6le #f nothing)))))

;; ADR-0002: nothing reads LD_LIBRARY_PATH or DYLD_* on chez-curl's behalf.
(test-equal "discovery reads no variable but CHEZ_CURL_LIBCURL, GUIX_ENVIRONMENT, GUIX_PROFILE and HOME"
  '("CHEZ_CURL_LIBCURL" "GUIX_ENVIRONMENT" "GUIX_PROFILE" "HOME")
  (let* ((names '())
         (getenv (lambda (name)
                   (unless (member name names) (set! names (cons name names)))
                   ((env (append guix-vars
                                 '(("LD_LIBRARY_PATH" . "/opt/curl/lib")
                                   ("DYLD_LIBRARY_PATH" . "/opt/curl/lib")))) name))))
    (for-each (lambda (machine maps)
                (outcome (lambda () (choose-libcurl getenv machine maps nothing))))
              '(ta6le ta6le tarm64osx)
              (list guix-maps fhs-maps #f))
    (list-sort string<? names)))

(test-equal "libcurl-sources: exactly the eight sources, in order"
  '(override guix-environment guix-profile guix-home guix-user-profile guix-system
    system macos-system)
  libcurl-sources)

;; --- the real /proc/self/maps ----------------------------------------------------

(define (string-suffix? suffix s)
  (let ((n (string-length s)) (m (string-length suffix)))
    (and (>= n m) (string=? (substring s (- n m) n) suffix))))

(define (string-prefix? prefix s)
  (let ((n (string-length s)) (m (string-length prefix)))
    (and (>= n m) (string=? (substring s 0 m) prefix))))

(define linux? (string-suffix? "le" (symbol->string (machine-type))))

;; real-maps : (U String #f)
;; This process's /proc/self/maps, or #f when it cannot be read: what the
;; native layer will hand discovery.
(define real-maps
  (guard (e (#t #f))
    (call-with-port (open-file-input-port "/proc/self/maps" (file-options)
                                          (buffer-mode block)
                                          (make-transcoder (utf-8-codec)))
      get-string-all)))

;; binary-world : (U 'guix 'fhs (List 'unknown Any))
;; guix when this Chez's own binary, its symlinks resolved, lies under
;; /gnu/store/; fhs when it does not, or off Linux, where /proc is not read.
;; Anything else is a sentinel no world can equal.
(define binary-world
  (if linux?
      (guard (e (#t (list 'unknown (describe e))))
        (let ((answer (capture-command
                       (list "readlink" "-f"
                             (string-append "/proc/" (number->string (get-process-id))
                                            "/exe")))))
          (if (and (= (car answer) 0) (string-prefix? "/" (cadr answer)))
              (begin
                ;; readlink's line, newline and all.
                (display (string-append "this Chez's binary: " (cadr answer)))
                (if (string-prefix? "/gnu/store/" (cadr answer)) 'guix 'fhs))
              (list 'unknown answer))))
      'fhs))

(test-equal "the real /proc/self/maps is read on Linux, and only there"
  (if linux? 'read 'unread)
  (if (string? real-maps) 'read 'unread))

(test-equal "the real /proc/self/maps: guix exactly when this Chez's binary lies under /gnu/store/"
  binary-world
  (libcurl-world real-maps))

(test-end "discovery")

(exit (suite-exit-status runner))
