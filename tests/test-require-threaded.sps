#!r6rs
;;; The suite for (curl private require-threaded): chez-curl needs a threaded
;;; Chez of at least 10.4.0, and refuses any other by name (ADR-0001).
;;;
;;; Chez builds make-mutex, fork-thread and the rest of its thread system
;;; only into threaded builds, so on a --nothreads Chez a library importing
;;; them dies at import with a bare "missing import for make-mutex". The
;;; refusal raises a readable message instead, while it is being expanded.
;;; That helps only if it is expanded first: Chez processes a library's
;;; imports in order (measured by chez-libuv on a --nothreads 10.4.1). So
;;; every library under src/ but the refusal itself imports
;;; (curl private require-threaded) first among its imports. An
;;; (http-client ...) library may not import it (ADR-0007's seam), so it
;;; imports (curl) first instead, and (curl) imports the refusal first. This
;;; suite reads each library's import form as data and holds that order.
;;;
;;; It also holds the refusal itself, on this Chez: it expands a copy of the
;;; refusal's source in which each call (threaded?) answers #f, as a
;;; --nothreads Chez's does, and requires the refusal's message. It does the
;;; same with each call (scheme-version-number) answering a version and each
;;; call (scheme-version #t) answering the version's text, for a release or
;;; for a pre-release, in rows on each side of the floor, 10.4.0. A
;;; pre-release comes before the release it is numbered for, so
;;; 10.4.0-pre-release.N is below the floor and 10.5.0-pre-release.N is not.
;;;
;;; The floor is held to packaging/floors.sexp, the one file that writes it.
;;; Each expected message takes the floor's text from that file, and further
;;; rows are built from it: Chez at the floor loads, a pre-release of the
;;; floor itself is refused naming it, and the versions on each side of the
;;; floor load or are refused. A file and a refusal that disagree fail here,
;;; by name. The literal rows stay: they name 10.4.0 and its neighbours, so
;;; a floor changed in both places at once is a decision a reader of this
;;; suite sees.
;;;
;;; make test runs every suite from the repository root, where src/ is. An
;;; empty or missing src/ fails here by name, never passes for want of rows.
;;;
;;; Each expected value is a symbol the code under test cannot produce by
;;; failing. SRFI-64 turns a raise in the actual expression into #f.
(import (rnrs)
        (srfi :64)
        (curl-testing)
        (floors)
        (only (chezscheme) directory-list file-directory? file-symbolic-link? eval
              interaction-environment))

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

(define refusal-library '(curl private require-threaded))

;; The Chez floor of packaging/floors.sexp, computed under a guard: a raise at
;; top level would end the suite with no test named, and one in an expected
;; expression would escape SRFI-64. Each is a symbol when the file cannot give
;; the floor, so the rows built from it fail by name.

;; chez-floor : (U (List Natural Natural Natural) Symbol)
(define chez-floor
  (guard (e (#t 'floors-file-unreadable))
    (let ((parts (floor-numbers (read-floors) 'chez)))
      (if (= (length parts) 3) parts 'not-three-numbers))))

;; chez-floor-text : (U String Symbol)
(define chez-floor-text
  (guard (e (#t 'floors-file-unreadable))
    (floor-text (read-floors) 'chez)))

;; --- reading the tree -----------------------------------------------------------

;; sls-file? : String -> Boolean
;; A library source by its name: *.sls, with something before the suffix.
(define (sls-file? name)
  (let ((n (string-length name)))
    (and (> n 4)
         (string=? (substring name (- n 4) n) ".sls"))))

;; lock-file? : String String -> Boolean
;; Whether the entry NAME, at PATH, is an Emacs lock file: named .#..., and a
;; symbolic link to nothing, which Chez cannot load. It is the rule of
;; tests/check-seam.sps. A regular file or a directory named .#... is no lock
;; file: Chez loads a library from .#g.sls as it does from g.sls, so the scan
;; reads it. Nor is a link that resolves.
(define (lock-file? path name)
  (and (> (string-length name) 1)
       (char=? (string-ref name 0) #\.)
       (char=? (string-ref name 1) #\#)
       (file-symbolic-link? path)
       (not (file-exists? path))))

;; sls-files : String -> (Listof String)
;; Every library source under DIR, depth first, sorted; none when DIR is
;; not a directory. A lock-file? is skipped: reading one would stop the suite.
(define (sls-files dir)
  (if (file-directory? dir)
      (apply append
             (map (lambda (name)
                    (let ((path (string-append dir "/" name)))
                      (cond ((lock-file? path name) '())
                            ((file-directory? path) (sls-files path))
                            ((sls-file? name) (list path))
                            (else '()))))
                  (list-sort string<? (directory-list dir))))
      '()))

;; first-datum : String -> Any
;; The first datum in the file at PATH (Chez's reader skips #!r6rs), or
;; (unreadable TEXT).
(define (first-datum path)
  (guard (e (#t (list 'unreadable (describe e))))
    (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                          (make-transcoder (utf-8-codec)))
      read)))

;; library-form? : Any -> Boolean
;; (library NAME (export ...) (import ...) body ...).
(define (library-form? form)
  (and (list? form)
       (>= (length form) 4)
       (eq? (car form) 'library)
       (pair? (cadddr form))
       (eq? (car (cadddr form)) 'import)))

(define (form-name form)
  (and (library-form? form) (cadr form)))

(define (form-exports form)
  (and (library-form? form)
       (pair? (caddr form))
       (eq? (car (caddr form)) 'export)
       (cdr (caddr form))))

;; spec-library : Import-Spec -> Library-Reference
;; The library an import spec draws on, seen through only, except, prefix,
;; rename and for, and the (library ...) escape.
(define (spec-library spec)
  (if (and (pair? spec)
           (memq (car spec) '(only except prefix rename for library))
           (pair? (cdr spec))
           (pair? (cadr spec)))
      (spec-library (cadr spec))
      spec))

;; library-name : Library-Reference -> (Listof Symbol)
;; The reference without its optional version: (curl private x (1)).
(define (library-name ref)
  (if (or (not (pair? ref)) (pair? (car ref)))
      '()
      (cons (car ref) (library-name (cdr ref)))))

;; first-order : (Listof Import-Spec) (Listof Symbol) -> (U 'first 'not-first 'absent)
;; Where the library REQUIRED stands among SPECS.
(define (first-order specs required)
  (let ((names (map (lambda (spec) (library-name (spec-library spec))) specs)))
    (cond ((null? names) 'absent)
          ((equal? (car names) required) 'first)
          ((member required (cdr names)) 'not-first)
          (else 'absent))))

;; import-order : (Listof Import-Spec) -> (U 'first 'not-first 'absent)
;; Where the refusal stands among SPECS.
(define (import-order specs)
  (first-order specs refusal-library))

;; required-first : Any -> (Listof Symbol)
;; The library a library named NAME must import first: (curl) for an
;; (http-client ...) library, which may not import the refusal itself and
;; reaches it through (curl); the refusal for any other.
(define (required-first name)
  (if (and (pair? name) (eq? (car name) 'http-client))
      '(curl)
      refusal-library))

;; verdict : Any -> (U 'first 'not-first 'absent 'not-a-library)
(define (verdict form)
  (if (library-form? form)
      (first-order (cdr (cadddr form)) (required-first (cadr form)))
      'not-a-library))

;; written : Any -> String
(define (written x)
  (call-with-string-output-port (lambda (p) (write x p))))

(test-begin "require-threaded")

;; --- the checker, on seeded import forms -------------------------------------------
;; A checker that never reported anything would pass every row on the real
;; tree, so first it must tell each of these apart.

(test-equal "the refusal first among the imports is first"
  'first
  (import-order '((curl private require-threaded) (rnrs) (only (chezscheme) make-mutex))))

(test-equal "the refusal after (rnrs) is not first"
  'not-first
  (import-order '((rnrs) (curl private require-threaded))))

(test-equal "no refusal among the imports is absent"
  'absent
  (import-order '((rnrs) (curl private conditions))))

(test-equal "no imports at all is absent"
  'absent
  (import-order '()))

(test-equal "a wrapped or versioned refusal is the same library"
  '(first first first)
  (map (lambda (spec) (import-order (list spec '(rnrs))))
       '((only (curl private require-threaded))
         (library (curl private require-threaded))
         (curl private require-threaded (1)))))

(test-equal "a file whose first datum is no library form is not a library"
  'not-a-library
  (verdict '(import (rnrs))))

;; --- the order rule for an (http-client ...) library, on seeded library forms ------
;; src/ holds no (http-client ...) library yet, and these rows hold without
;; one. An (http-client ...) library satisfies the rule by importing (curl)
;; first. The refusal does not satisfy it: check-seam forbids that import.

(test-equal "an (http-client ...) library importing (curl) first is first"
  'first
  (verdict '(library (http-client session) (export) (import (curl) (rnrs)))))

(test-equal "an (http-client) library is held to the same rule"
  'first
  (verdict '(library (http-client) (export) (import (curl) (rnrs)))))

(test-equal "an (http-client ...) library importing (rnrs) before (curl) is not first"
  'not-first
  (verdict '(library (http-client session) (export) (import (rnrs) (curl)))))

(test-equal "an (http-client ...) library without (curl) is absent, even with the refusal first"
  '(absent absent)
  (map verdict
       '((library (http-client session) (export) (import (rnrs) (only (chezscheme) format)))
         (library (http-client session) (export)
           (import (curl private require-threaded) (rnrs))))))

(test-equal "a wrapped or versioned (curl) is the same library"
  '(first first first)
  (map verdict
       '((library (http-client a) (export) (import (only (curl) x) (rnrs)))
         (library (http-client b) (export) (import (library (curl)) (rnrs)))
         (library (http-client c) (export) (import (curl (1)) (rnrs))))))

(test-equal "a (curl ...) library is not excused by importing (curl) first"
  '(absent not-first)
  (map verdict
       '((library (curl private y) (export) (import (curl) (rnrs)))
         (library (curl private z) (export)
           (import (curl) (curl private require-threaded))))))

(test-equal "a library in neither family needs the refusal first"
  '(absent absent first first)
  (map verdict
       '((library (util) (export) (import (curl) (rnrs)))
         (library (foo http-client) (export) (import (curl) (rnrs)))
         (library (util) (export) (import (curl private require-threaded) (rnrs)))
         (library (foo http-client) (export)
           (import (curl private require-threaded) (rnrs))))))

(test-equal "http-client-extras is no (http-client ...) library"
  '(absent first)
  (map verdict
       '((library (http-client-extras) (export) (import (curl) (rnrs)))
         (library (http-client-extras) (export)
           (import (curl private require-threaded) (rnrs))))))

(test-equal "the scan reads a name ending in .sls, a dotfile included, and no other"
  '(read read skipped skipped skipped skipped)
  (map (lambda (name) (if (sls-file? name) 'read 'skipped))
       '("native.sls" "._native.sls" "native.sls~" "#native.sls#" ".sls" "native.ss")))

;; The fixture trees of tests/test-check-seam.sps, which holds each .# case. The
;; scan is handed one directly: the real tree below is src/ alone, and no
;; fixture is a suite or a library under src/.
(define lock-trees "tests/fixtures/seam")

(test-equal "the scan skips a .# dangling symbolic link, an Emacs lock file, and reads what it lies beside"
  (list (string-append lock-trees "/lock-symlink/curl/legal.sls"))
  (sls-files (string-append lock-trees "/lock-symlink")))

(test-equal "the scan reads a .# regular file, which Chez loads as a library"
  (list (string-append lock-trees "/lock-regular/curl/.#g.sls")
        (string-append lock-trees "/lock-regular/http-client/target.sls"))
  (sls-files (string-append lock-trees "/lock-regular")))

(test-equal "the scan reads a .# link that resolves, and a .# directory"
  (list (string-append lock-trees "/lock-symlink-live/curl/.#real.sls")
        (string-append lock-trees "/lock-symlink-live/curl/real.sls")
        (string-append lock-trees "/lock-directory/curl/.#dir/bad.sls"))
  (append (sls-files (string-append lock-trees "/lock-symlink-live"))
          (sls-files (string-append lock-trees "/lock-directory"))))

;; --- the real tree ------------------------------------------------------------------

;; libraries : (Listof (Pairof String Any))
;; Each source under src/, with its first datum.
(define libraries
  (map (lambda (path) (cons path (first-datum path))) (sls-files "src")))

(define library-names (map (lambda (entry) (form-name (cdr entry))) libraries))

(test-equal "src/ defines (curl private require-threaded)"
  'defined
  (if (member refusal-library library-names) 'defined 'absent))

;; The libraries named here. A scan of the wrong directory, or of an empty one,
;; finds none of them. (curl) lies in src/ itself, outside src/curl/private, so
;; a scan rooted there misses it.
(test-equal "the scan read src/: (curl), conditions, constants, discovery, libcurl-info, load-state, native and verify"
  '(read read read read read read read read)
  (map (lambda (name) (if (member name library-names) 'read 'missed))
       '((curl) (curl private conditions) (curl private constants)
         (curl private discovery) (curl private libcurl-info) (curl private load-state)
         (curl private native) (curl private verify))))

;; Every library but the refusal itself.
(define covered
  (filter (lambda (entry) (not (equal? (form-name (cdr entry)) refusal-library)))
          libraries))

(test-equal "the order rows are live: src/ holds a library besides the refusal"
  'live
  (if (null? covered) 'no-rows 'live))

(for-each
 (lambda (entry)
   (test-equal (string-append (car entry) " imports "
                              (written (required-first (form-name (cdr entry))))
                              " first")
     'first
     (verdict (cdr entry))))
 covered)

;; --- the refusal, as a --nothreads or an older Chez would expand it ------------------
;; No Chez here takes a refusing branch, so a refusal that stopped asking
;; (threaded?) or (scheme-version-number), asked it backwards, only printed,
;; or lost its message would pass every row above. These expand the refusal's
;; own source with eval: once as it is, once with each call (threaded?)
;; replaced by #f, and once for each version with each call
;; (scheme-version-number) replaced by that version's three numbers.

(define refusal-marker "chez-curl needs a threaded Chez Scheme")

(define refusal-form
  (let ((entry (find (lambda (entry) (equal? (form-name (cdr entry)) refusal-library))
                     libraries)))
    (and entry (cdr entry))))

;; as-nonthreaded : Any -> Any
;; Replaces each element (threaded?) with #f. A call is always an element;
;; (only (chezscheme) threaded?) merely ends in a tail of the same shape.
(define (as-nonthreaded x)
  (if (list? x)
      (map (lambda (e) (if (equal? e '(threaded?)) #f (as-nonthreaded e))) x)
      x))

(define (threaded-calls x)
  (if (list? x)
      (fold-left + 0 (map (lambda (e)
                            (if (equal? e '(threaded?)) 1 (threaded-calls e)))
                          x))
      0))

;; as-version : Any (Listof Natural) (U Natural #f) -> Any
;; Replaces each element (scheme-version-number) with (values MAJOR MINOR
;; PATCH), what that procedure answers, and each element (scheme-version #t)
;; with the text it answers for that version: for a pre-release, PRE is its
;; number, else #f.
(define (as-version x version pre)
  (if (list? x)
      (map (lambda (e)
             (cond ((equal? e '(scheme-version-number)) (cons 'values version))
                   ((equal? e '(scheme-version #t)) (version-text version pre))
                   (else (as-version e version pre))))
           x)
      x))

;; version-text : (Listof Natural) (U Natural #f) -> String
;; What (scheme-version #t) answers.
(define (version-text version pre)
  (string-append "Chez Scheme Version "
                 (number->string (car version)) "."
                 (number->string (cadr version)) "."
                 (number->string (caddr version))
                 (if pre (string-append "-pre-release." (number->string pre)) "")))

;; calls-of : Any Any -> Natural
;; How many elements equal to CALL X holds, at any depth.
(define (calls-of call x)
  (if (list? x)
      (fold-left + 0 (map (lambda (e) (if (equal? e call) 1 (calls-of call e))) x))
      0))

(define (starts-with? prefix s)
  (and (string? s)
       (<= (string-length prefix) (string-length s))
       (string=? prefix (substring s 0 (string-length prefix)))))

;; expand-under : (U Any #f) (Listof Symbol) -> (U Symbol String)
;; Evaluates FORM, a library form, under the fresh NAME: loaded, or
;; refused-by-name for a syntax violation from chez-curl whose message
;; starts with the marker, or else the text of what was raised.
(define (expand-under form name)
  (if (library-form? form)
      (guard (e ((and (syntax-violation? e)
                      (who-condition? e) (eq? (condition-who e) 'chez-curl)
                      (message-condition? e)
                      (starts-with? refusal-marker (condition-message e)))
                 'refused-by-name)
                (#t (describe e)))
        (eval (cons 'library (cons name (cddr form))) (interaction-environment))
        'loaded)
      'no-refusal-source))

;; expand-refusal : (U Any #f) (Listof Symbol) -> Any
;; Evaluates FORM, a library form, under the fresh NAME: loaded, or
;; (refused WHO MESSAGE) for a syntax violation, or else the text of what
;; was raised.
(define (expand-refusal form name)
  (if (library-form? form)
      (guard (e ((and (syntax-violation? e) (who-condition? e) (message-condition? e))
                 (list 'refused (condition-who e) (condition-message e)))
                (#t (describe e)))
        (eval (cons 'library (cons name (cddr form))) (interaction-environment))
        'loaded)
      'no-refusal-source))

(test-equal "the refusal exports nothing"
  '()
  (if (library-form? refusal-form) (form-exports refusal-form) 'no-refusal-source))

(test-equal "the refusal asks (threaded?)"
  'asks
  (if (and refusal-form (> (threaded-calls refusal-form) 0)) 'asks 'never-asks))

(test-equal "on this threaded Chez, the refusal lets its library load"
  'loaded
  (expand-under refusal-form '(require-threaded as-it-is)))

(test-equal "where (threaded?) is #f, the refusal raises its message at expansion"
  'refused-by-name
  (expand-under (and refusal-form (as-nonthreaded refusal-form))
                '(require-threaded as-nonthreaded)))

;; The floor is Chez 10.4.0, threaded (ADR-0001), written in
;; packaging/floors.sexp. Each expected message is the whole text, naming the
;; floor, as that file writes it, and the version that was refused.
;; refused-below-floor : String -> (List 'refused Symbol (U String Symbol))
;; What expand-refusal answers for a Chez whose version reads FOUND. The
;; message is a symbol when the floors file cannot give the floor: the row
;; fails by name, and nothing raises in an expected expression.
(define (refused-below-floor found)
  (list 'refused 'chez-curl
        (if (and (string? chez-floor-text) (string? found))
            (string-append "chez-curl needs Chez Scheme " chez-floor-text
                           " or later, and this one is " found)
            'floors-file-unreadable)))

(test-equal "the refusal asks (scheme-version-number)"
  'asks
  (if (and refusal-form (> (calls-of '(scheme-version-number) refusal-form) 0)) 'asks 'never-asks))

(test-equal "the refusal asks (scheme-version #t), which says whether this Chez is a pre-release"
  'asks
  (if (and refusal-form (> (calls-of '(scheme-version #t) refusal-form) 0)) 'asks 'never-asks))

;; A row is the version, the pre-release number or #f, and what the message
;; says this Chez is. A pre-release is named only at the floor, where it
;; decides the matter: below it, the version refuses on its own.
(for-each
 (lambda (row)
   (let ((version (car row)) (pre (cadr row)) (said (caddr row)))
     (test-equal (string-append "where Chez is " (version-text version pre)
                                ", the refusal raises its message naming the floor")
       (refused-below-floor said)
       (expand-refusal (and refusal-form (as-version refusal-form version pre))
                       '(require-threaded below-floor)))))
 '(((10 3 0) #f "10.3.0")
   ((9 5 9) #f "9.5.9")
   ((10 3 9) #f "10.3.9")
   ((10 3 0) 2 "10.3.0")
   ;; A pre-release is before its own release, so before the floor.
   ((10 4 0) 1 "10.4.0-pre-release.1")
   ((10 4 0) 7 "10.4.0-pre-release.7")
   ((10 4 0) 12 "10.4.0-pre-release.12")))

(for-each
 (lambda (row)
   (let ((version (car row)) (pre (cadr row)))
     (test-equal (string-append "where Chez is " (version-text version pre)
                                ", the refusal lets its library load")
       'loaded
       (expand-refusal (and refusal-form (as-version refusal-form version pre))
                       '(require-threaded at-floor)))))
 '(((10 4 0) #f)
   ((10 5 1) #f)
   ((11 0 0) #f)
   ;; The numbers are compared as numbers: as text, "10.10.0" sorts before "10.4.0".
   ((10 10 0) #f)
   ;; A pre-release of a later version is after the floor.
   ((10 4 1) 1)
   ((10 5 0) 1)
   ((11 0 0) 3)))

;; --- the floor of packaging/floors.sexp -----------------------------------------------
;; These rows take the floor from the file, so they move with it, and a refusal
;; that still holds another floor fails them. The rows above name 10.4.0.

;; dotted : (Listof Natural) -> String
(define (dotted version)
  (let loop ((rest (cdr version)) (text (number->string (car version))))
    (if (null? rest)
        text
        (loop (cdr rest) (string-append text "." (number->string (car rest)))))))

;; floor-after : Natural -> (U (Listof Natural) Symbol)
;; The floor with its number at INDEX one higher and the numbers after it
;; zero: the nearest version after the floor that changes that number. A
;; symbol when the floors file is unreadable.
(define (floor-after index)
  (if (list? chez-floor)
      (let loop ((rest chez-floor) (i 0))
        (cond ((null? rest) '())
              ((< i index) (cons (car rest) (loop (cdr rest) (+ i 1))))
              ((= i index) (cons (+ (car rest) 1) (loop (cdr rest) (+ i 1))))
              (else (cons 0 (loop (cdr rest) (+ i 1))))))
      'floors-file-unreadable))

;; floor-major-below : (U (Listof Natural) Symbol)
;; The floor with its major number one lower, and the rest as it is. A symbol
;; when the floors file is unreadable, or the major number is zero.
(define floor-major-below
  (if (and (list? chez-floor) (> (car chez-floor) 0))
      (cons (- (car chez-floor) 1) (cdr chez-floor))
      'no-version-below))

;; expand-at : (U (Listof Natural) Symbol) (U Natural #f) (Listof Symbol) -> Any
;; expand-refusal for a Chez that reports VERSION, or a symbol when VERSION is
;; no version.
(define (expand-at version pre name)
  (if (and (list? version) (= (length version) 3) (for-all integer? version))
      (expand-refusal (and refusal-form (as-version refusal-form version pre)) name)
      'no-such-version))

(test-equal "where Chez is the floor of packaging/floors.sexp, the refusal lets its library load"
  'loaded
  (expand-at chez-floor #f '(require-threaded at-file-floor)))

(for-each
 (lambda (pre)
   (test-equal (string-append "where Chez is a pre-release of the floor of packaging/floors.sexp, number "
                              (number->string pre) ", the refusal raises its message naming the floor")
     (refused-below-floor
      (if (string? chez-floor-text)
          (string-append chez-floor-text "-pre-release." (number->string pre))
          'floors-file-unreadable))
     (expand-at chez-floor pre '(require-threaded pre-release-of-file-floor))))
 '(1 7 12))

(for-each
 (lambda (row)
   (test-equal (string-append "where Chez is one step after the floor of packaging/floors.sexp, in its "
                              (cadr row) " number, the refusal lets its library load")
     'loaded
     (expand-at (floor-after (car row)) #f '(require-threaded after-file-floor))))
 '((0 "major") (1 "minor") (2 "patch")))

(test-equal "where Chez's major number is one below the floor of packaging/floors.sexp, the refusal raises its message naming the floor"
  (refused-below-floor
   (if (list? floor-major-below) (dotted floor-major-below) 'no-such-version))
  (expand-at floor-major-below #f '(require-threaded below-file-floor)))

(test-end "require-threaded")

(exit (suite-exit-status runner))
