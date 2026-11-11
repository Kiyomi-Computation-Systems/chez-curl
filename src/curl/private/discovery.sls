#!r6rs
;;; (curl private discovery): which libcurl to load (ADR-0002).
;;;
;;; Pure. It reads no file, calls no foreign code and reads no environment
;;; variable of its own: getenv, the machine type, the text of
;;; /proc/self/maps and an existence predicate all come in as arguments, so
;;; tests/test-discovery.sps can drive every rule with synthetic inputs.
;;;
;;;   1. CHEZ_CURL_LIBCURL, when set, must be an absolute path, and is
;;;      chosen as given: never checked with exists?, since loading decides,
;;;      and never a fallback. Anything else set, the empty string too, is
;;;      invalid-override.
;;;   2. Otherwise the platform comes from the machine type: a name ending
;;;      in le is Linux, one ending in osx is macOS, any other has no
;;;      candidates.
;;;   3. On Linux, the world is Guix when /proc/self/maps shows libc.so.6
;;;      mapped from under /gnu/store/, and FHS otherwise, unreadable
;;;      included. Each world has its own list, and the first candidate that
;;;      exists wins. None existing is not-found, listing every path checked.
;;;   4. On macOS, Apple's /usr/lib/libcurl.4.dylib is the one candidate. It
;;;      lives in the dyld shared cache with no file on disk, so it is
;;;      returned without asking exists?.
(library (curl private discovery)
  (export choose-libcurl libcurl-world linux-triple libcurl-candidates
          libcurl-sources mapped-file bytes-hold? backend-in-use)
  (import (curl private require-threaded)
          (rnrs)
          (curl private conditions))

  ;; libcurl-sources : (Listof Symbol)
  ;; Where a chosen path can come from, as a refusal or a report names it.
  ;;
  ;;   override            CHEZ_CURL_LIBCURL
  ;;   guix-environment    $GUIX_ENVIRONMENT, an active guix shell
  ;;   guix-profile        $GUIX_PROFILE
  ;;   guix-home           $HOME/.guix-home/profile
  ;;   guix-user-profile   $HOME/.guix-profile
  ;;   guix-system         /run/current-system/profile, Guix System's
  ;;   system              an FHS directory
  ;;   macos-system        Apple's /usr/lib
  (define libcurl-sources
    '(override guix-environment guix-profile guix-home guix-user-profile
      guix-system system macos-system))

  ;; choose-libcurl : (String -> (U String #f)) Symbol (U String #f)
  ;;                  (String -> Boolean) -> (Values String Symbol)
  ;; The path to load, and its source. GETENV reads the environment,
  ;; MACHINE-TYPE is Chez's (ta6le, tarm64osx, ...), MAPS-TEXT is the text of
  ;; /proc/self/maps or #f when it cannot be read, and EXISTS? says whether
  ;; a path exists. Raises &curl-library-unavailable with reason
  ;; invalid-override or not-found.
  (define (choose-libcurl getenv machine-type maps-text exists?)
    (let ((override (getenv "CHEZ_CURL_LIBCURL")))
      (cond
        ((not override)
         (let ((platform (machine-platform machine-type)))
           (case platform
             ((macos)
              (let ((apple (car (libcurl-candidates #f machine-type getenv))))
                (values (car apple) (cdr apple))))
             ((linux)
              (first-existing (libcurl-candidates (libcurl-world maps-text)
                                                  machine-type getenv)
                              exists?))
             (else (first-existing '() exists?)))))
        ((absolute? override) (values override 'override))
        (else
         (refuse 'invalid-override #f 'override override '()
                 "CHEZ_CURL_LIBCURL must be an absolute path to libcurl, which is loaded as given and never searched for; set one, or unset it to use discovery"
                 override)))))

  ;; first-existing : (Listof (Pairof String Symbol)) (String -> Boolean)
  ;;                  -> (Values String Symbol)
  ;; The first of CANDIDATES that EXISTS? says exists, asked one at a time,
  ;; in order, stopping there. None is not-found, listing them all.
  (define (first-existing candidates exists?)
    (let loop ((rest candidates))
      (cond
        ((null? rest)
         (let ((paths (map car candidates)))
           (refuse 'not-found #f #f #f paths
                   "no libcurl found among the candidates; name one with CHEZ_CURL_LIBCURL, an absolute path"
                   paths)))
        ((exists? (caar rest)) (values (caar rest) (cdar rest)))
        (else (loop (cdr rest))))))

  ;; refuse : Symbol (U String #f) (U Symbol #f) Any (Listof String) String
  ;;          Any -> Nothing
  (define (refuse reason path source detail candidates message irritant)
    (raise (condition (make-curl-library-unavailable reason path source detail
                                                     candidates #f)
                      (make-who-condition 'chez-curl)
                      (make-message-condition message)
                      (make-irritants-condition (list irritant)))))

  ;; machine-platform : Symbol -> (U 'linux 'macos #f)
  (define (machine-platform machine-type)
    (let ((name (symbol->string machine-type)))
      (cond ((string-suffix? "le" name) 'linux)
            ((string-suffix? "osx" name) 'macos)
            (else #f))))

  ;; linux-triple : Symbol -> (U String #f)
  ;; The Debian multiarch directory under /usr/lib for MACHINE-TYPE, or #f
  ;; for any machine type but these two.
  (define (linux-triple machine-type)
    (case machine-type
      ((ta6le) "x86_64-linux-gnu")
      ((tarm64le) "aarch64-linux-gnu")
      (else #f)))

  ;; libcurl-world : (U String #f) -> (U 'guix 'fhs)
  ;; guix when some line of MAPS-TEXT, the text of /proc/self/maps, names a
  ;; file whose basename is libc.so.6 under /gnu/store/; fhs otherwise, and
  ;; when MAPS-TEXT is #f.
  (define (libcurl-world maps-text)
    (if (and maps-text (exists guix-libc? (map line-path (lines maps-text))))
        'guix
        'fhs))

  ;; guix-libc? : (U String #f) -> Boolean
  (define (guix-libc? path)
    (and path
         (string-prefix? "/gnu/store/" path)
         (string=? (basename path) "libc.so.6")))

  ;; mapped-file : (U String #f) Natural -> (U String #f)
  ;; The pathname of the line of MAPS-TEXT, the text of /proc/self/maps,
  ;; whose range, START-END in hex, holds ADDRESS: the file the kernel maps
  ;; it from, every symlink resolved. #f when MAPS-TEXT is #f, when no line
  ;; holds ADDRESS, or when the line that does names no file. A line whose
  ;; range does not read as two hex numbers is skipped. The native layer
  ;; asks it for curl_version_info's entry point, so the answer is the file
  ;; of the libcurl it calls (ADR-0024).
  (define (mapped-file maps-text address)
    (and maps-text
         (let loop ((rest (lines maps-text)))
           (cond ((null? rest) #f)
                 ((range-holds? (car rest) address) (line-path (car rest)))
                 (else (loop (cdr rest)))))))

  ;; bytes-hold? : Bytevector Bytevector -> Boolean
  ;; Whether PATTERN, one byte or more, stands anywhere in BYTES. An empty
  ;; PATTERN is an assertion violation. The native layer asks it whether the
  ;; loaded libcurl's file holds Guix's patch's literal, SSL_CERT_FILE
  ;; (ADR-0024).
  (define (bytes-hold? bytes pattern)
    (let ((n (bytevector-length bytes)) (m (bytevector-length pattern)))
      (when (= m 0) (assertion-violation 'bytes-hold? "a pattern is one byte or more" pattern))
      (let ((first (bytevector-u8-ref pattern 0)))
        (let scan ((i 0))
          (cond ((> (+ i m) n) #f)
                ((and (= (bytevector-u8-ref bytes i) first)
                      (let match ((j 1))
                        (or (= j m)
                            (and (= (bytevector-u8-ref bytes (+ i j)) (bytevector-u8-ref pattern j))
                                 (match (+ j 1))))))
                 #t)
                (else (scan (+ i 1))))))))

  ;; backend-in-use : (U String #f) -> (U String #f)
  ;; The TLS backend in use, as curl_version_info's ssl_version names it:
  ;; TEXT with each parenthesised group taken out, an unclosed one to its
  ;; end, and the spaces left at its ends trimmed, its version after a /
  ;; kept. A MultiSSL libcurl puts every backend but the one in use in
  ;; parentheses, each a backend's own version text, which may hold spaces:
  ;; OpenSSL/1.1.1k FIPS. #f when TEXT is #f, or nothing is left. Before
  ;; curl_global_init a MultiSSL libcurl names its first backend so,
  ;; whatever the init will pick (lib/vtls/vtls.c, multissl_version): the
  ;; native layer asks it of the text read after (ADR-0024).
  (define (backend-in-use text)
    (and text
         (let* ((n (string-length text))
                (kept (let loop ((i 0) (depth 0) (found '()))
                        (cond ((= i n) (list->string (reverse found)))
                              ((char=? (string-ref text i) #\() (loop (+ i 1) (+ depth 1) found))
                              ((and (char=? (string-ref text i) #\)) (> depth 0))
                               (loop (+ i 1) (- depth 1) found))
                              ((> depth 0) (loop (+ i 1) depth found))
                              (else (loop (+ i 1) depth (cons (string-ref text i) found))))))
                (trimmed (trim-spaces kept)))
           (and (> (string-length trimmed) 0) trimmed))))

  ;; trim-spaces : String -> String
  ;; TEXT without the spaces at its ends, and with each run of spaces
  ;; inside it one space: a group taken out leaves its neighbours' spaces.
  (define (trim-spaces text)
    (let loop ((chars (string->list text)) (found '()) (space #f))
      (cond ((null? chars) (list->string (reverse found)))
            ((char=? (car chars) #\space) (loop (cdr chars) found (pair? found)))
            (else (loop (cdr chars)
                        (cons (car chars) (if space (cons #\space found) found))
                        #f)))))

  ;; range-holds? : String Natural -> Boolean
  ;; Whether LINE starts with START-END, two hex numbers, then a space, and
  ;; START <= ADDRESS < END.
  (define (range-holds? line address)
    (let* ((n (string-length line))
           (dash (let loop ((i 0))
                   (cond ((= i n) #f)
                         ((char=? (string-ref line i) #\-) i)
                         (else (loop (+ i 1))))))
           (space (and dash
                       (let loop ((i dash))
                         (cond ((= i n) #f)
                               ((char=? (string-ref line i) #\space) i)
                               (else (loop (+ i 1)))))))
           (start (and space (hex (substring line 0 dash))))
           (end (and start (hex (substring line (+ dash 1) space)))))
      (and end (<= start address) (< address end))))

  ;; hex : String -> (U Natural #f)
  ;; TEXT read as a hex natural: one or more hex digits, nothing else.
  (define (hex text)
    (and (> (string-length text) 0)
         (for-all (lambda (c) (or (char<=? #\0 c #\9) (char<=? #\a c #\f) (char<=? #\A c #\F)))
                  (string->list text))
         (string->number text 16)))

  ;; line-path : String -> (U String #f)
  ;; The pathname column of one line of /proc/self/maps: from its first /
  ;; to its end. No column before it holds a /.
  (define (line-path line)
    (let loop ((i 0))
      (cond ((= i (string-length line)) #f)
            ((char=? (string-ref line i) #\/) (substring line i (string-length line)))
            (else (loop (+ i 1))))))

  ;; libcurl-candidates : (U 'guix 'fhs #f) Symbol (String -> (U String #f))
  ;;                      -> (Listof (Pairof String Symbol))
  ;; Every candidate for WORLD and MACHINE-TYPE, in the order to probe, each
  ;; with its source. WORLD counts on Linux only: macOS has Apple's one
  ;; candidate, and any other platform none.
  (define (libcurl-candidates world machine-type getenv)
    (case (machine-platform machine-type)
      ((macos) (list (cons "/usr/lib/libcurl.4.dylib" 'macos-system)))
      ((linux)
       (case world
         ((guix) (guix-candidates getenv))
         ((fhs) (fhs-candidates (linux-triple machine-type)))
         (else (assertion-violation 'libcurl-candidates "not a world: guix or fhs"
                                    world))))
      (else '())))

  ;; guix-candidates : (String -> (U String #f)) -> (Listof (Pairof String Symbol))
  ;; lib/libcurl.so.4 under each Guix profile, in ADR-0002's order. A
  ;; variable unset or not absolute contributes nothing. Never a standard
  ;; directory.
  (define (guix-candidates getenv)
    (let* ((environment (absolute-or-false (getenv "GUIX_ENVIRONMENT")))
           (profile (absolute-or-false (getenv "GUIX_PROFILE")))
           (home (absolute-or-false (getenv "HOME"))))
      (append
       (profile-candidate environment 'guix-environment)
       (profile-candidate profile 'guix-profile)
       (profile-candidate (and home (string-append home "/.guix-home/profile"))
                          'guix-home)
       (profile-candidate (and home (string-append home "/.guix-profile"))
                          'guix-user-profile)
       (profile-candidate "/run/current-system/profile" 'guix-system))))

  ;; profile-candidate : (U String #f) Symbol -> (Listof (Pairof String Symbol))
  (define (profile-candidate profile source)
    (if profile
        (list (cons (string-append profile "/lib/libcurl.so.4") source))
        '()))

  ;; fhs-candidates : (U String #f) -> (Listof (Pairof String Symbol))
  ;; libcurl.so.4 in each standard directory, in ADR-0002's order, then
  ;; Debian's GnuTLS build. With no TRIPLE, neither triple directory. Never a
  ;; Guix profile.
  (define (fhs-candidates triple)
    (map (lambda (path) (cons path 'system))
         (append
          '("/usr/local/lib/libcurl.so.4")
          (if triple (list (string-append "/usr/lib/" triple "/libcurl.so.4")) '())
          '("/usr/lib64/libcurl.so.4"
            "/usr/lib/libcurl.so.4")
          (if triple
              (list (string-append "/usr/lib/" triple "/libcurl-gnutls.so.4"))
              '()))))

  ;; --- strings -----------------------------------------------------------------

  (define (absolute? s)
    (and (> (string-length s) 0) (char=? (string-ref s 0) #\/)))

  (define (absolute-or-false s)
    (and s (absolute? s) s))

  (define (string-prefix? prefix s)
    (let ((n (string-length s)) (m (string-length prefix)))
      (and (>= n m) (string=? (substring s 0 m) prefix))))

  (define (string-suffix? suffix s)
    (let ((n (string-length s)) (m (string-length suffix)))
      (and (>= n m) (string=? (substring s (- n m) n) suffix))))

  ;; basename : String -> String
  ;; What follows PATH's last /, or PATH when it holds none.
  (define (basename path)
    (let loop ((i (- (string-length path) 1)))
      (cond ((< i 0) path)
            ((char=? (string-ref path i) #\/)
             (substring path (+ i 1) (string-length path)))
            (else (loop (- i 1))))))

  ;; lines : String -> (Listof String)
  ;; TEXT split at each newline.
  (define (lines text)
    (let loop ((i 0) (start 0) (found '()))
      (cond ((= i (string-length text))
             (reverse (cons (substring text start i) found)))
            ((char=? (string-ref text i) #\newline)
             (loop (+ i 1) (+ i 1) (cons (substring text start i) found)))
            (else (loop (+ i 1) start found))))))
