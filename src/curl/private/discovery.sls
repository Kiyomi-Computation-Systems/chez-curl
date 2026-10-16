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
          libcurl-sources)
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
