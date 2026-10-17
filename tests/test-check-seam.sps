#!r6rs
;;; The suite for tests/check-seam.sps, the program behind `make check-seam`
;;; (ADR-0007). Every rule it holds has a fixture tree under
;;; tests/fixtures/seam/<case>/, and this suite runs the program on each, in a
;;; fresh Chez, through capture-command. A case asserts the exit status, the
;;; whole of stdout and the whole of stderr, as text written by hand here,
;;; never read back from the program: a substring would pass whenever another
;;; rule produced the same words. Without this suite, deleting a rule would
;;; leave `make test` green: the real tree under src/ breaks none of them.
;;;
;;; Each case's tree is the one fault it names, in an otherwise legal setting,
;;; so that only that rule can make it fail. `legal` and the lock-file cases
;;; that must pass say so with the program's own pass line, counts included.
;;; The fixture trees are never suites: make test runs tests/test-*.sps only,
;;; which check-suites reads, and tests/test-require-threaded.sps scans src/
;;; alone, and a fixture tree only where one of its rows names it.
;;;
;;; make test runs every suite from the repository root, where tests/ is, with
;;; CHEZ exported. Without CHEZ nothing below can run: that fails here, by
;;; name, and never skips.
(import (rnrs)
        (srfi :64)
        (curl-testing)
        (only (chezscheme) getenv directory-list file-directory? library-list))

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

(define chez (getenv "CHEZ"))

(define program "tests/check-seam.sps")

(define fixtures "tests/fixtures/seam")

;; run : (Listof String) -> (List Integer String String)
;; tests/check-seam.sps in a fresh Chez with ARGS: its exit status, stdout and
;; stderr.
(define (run args)
  (capture-command (append (list chez "--program" program) args)))

;; at : String String -> String
;; The path check-seam names for FILE in the fixture tree CASE.
(define (at case file) (string-append fixtures "/" case "/" file))

;; holds : Natural Natural -> (List 0 String "")
;; What a pass prints: the libraries read, in how many files.
(define (holds libraries files)
  (list 0
        (string-append "check-seam: the seam holds (" (number->string libraries)
                       " libraries in " (number->string files) " files checked)\n")
        ""))

;; refused : Natural String ... -> (List 1 "" String)
;; What a failure prints: PROBLEMS, one line each, then the count. COUNT is
;; given, not counted, so a miscount in the program is not copied here.
(define (refused count . problems)
  (list 1
        ""
        (string-append
         (apply string-append
                (map (lambda (p) (string-append "check-seam: " p "\n")) problems))
         "check-seam: FAILED (problems: " (number->string count) ")\n")))

;; The words the program ends some complaints with.
(define chez-only
  "but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)")

(define (not-listed name)
  (string-append "imports " name " from (chezscheme), but allowed-chez-names in"
                 " tests/check-seam.sps does not list it"))

;; library-only : String -> String
;; The words the program ends a complaint about a library-only-chez-names entry with.
(define (library-only name where)
  (string-append "imports " name " from (chezscheme), but library-only-chez-names in"
                 " tests/check-seam.sps allows it only in " where))

;; re-exports : String String -> String
;; The words the program ends a complaint about an export with: WHAT is the
;; name, or the internal name and " as " the external one, and NAME the one
;; imported.
(define (re-exports what name)
  (string-append "exports " what ", but it imports " name " from (chezscheme), and no"
                 " library under src/ may export a name it imports from (chezscheme)"))

(define unlisted-tail
  (string-append "but a library under src/ may import only the (rnrs ...) libraries"
                 " except (rnrs eval), (only (chezscheme) name ...), and (curl ...)"
                 " and (http-client ...) libraries"))

(define not-read-tail
  ", and this check does not read one; rename it or keep it out of src/")

;; unread : String -> String
(define (unread ending)
  (string-append "Chez could load a library from a file ending in " ending not-read-tail))

(define seam-a "but no (curl ...) library may import an (http-client ...) library")

;; no-such-file : String String -> String
;; The complaint for FILE in the tree CASE, a symbolic link to nothing.
(define (no-such-file case file)
  (string-append (at case file)
                 ": it cannot be read as data: Exception in open-file-input-port: failed for "
                 (at case file) ": no such file or directory"))

;; cases : (Listof (List String String Expected))
;; The fixture directory, what it holds, and the program's whole answer for it.
(define cases
  (list
   (list "legal"
         "a legal tree: wrappers over (rnrs ...), (only (chezscheme) ...), a version reference, two libraries in a file, and files it passes by"
         (holds 5 4))

   ;; --- the seam itself: rules (a) and (b) ---
   (list "rule-a"
         "rule (a): a (curl ...) library importing an (http-client ...) library"
         (refused 1 (string-append (at "rule-a" "curl/x.sls") ": (curl x) imports (http-client y), " seam-a)))
   (list "rule-b"
         "rule (b): an (http-client ...) library importing a (curl ...) library that is not public"
         (refused 1 (string-append (at "rule-b" "http-client/z.sls")
                                   ": (http-client z) imports (curl private thing), but an (http-client ...) library may import only the public (curl ...) libraries ((curl))")))
   (list "second-library"
         "every library form in a file is checked, the second included"
         (refused 1 (string-append (at "second-library" "curl/two.sls")
                                   ": (curl two-b) imports (http-client target), " seam-a)))

   ;; --- rule (d): the families ---
   (list "neither-family"
         "rule (d): a library in neither family"
         (refused 1 (string-append (at "neither-family" "util.sls")
                                   ": (util) belongs to neither family: the first identifier of a library's name under src/ must be curl or http-client")))

   ;; --- rule (c): (chezscheme), (scheme) and (rnrs eval) ---
   (list "chez-whole"
         "(chezscheme) imported whole"
         (refused 1 (string-append (at "chez-whole" "curl/w.sls")
                                   ": (curl w) imports (chezscheme), " chez-only)))
   (list "scheme-alias"
         "(scheme), the alias, imported whole"
         (refused 1 (string-append (at "scheme-alias" "curl/s.sls")
                                   ": (curl s) imports (scheme), " chez-only)))
   (list "chez-wrapped"
         "(chezscheme) under except, prefix, rename, for, library, a nested only and (scheme)"
         (refused 10
                  (string-append (at "chez-wrapped" "curl/w1.sls")
                                 ": (curl w1) imports (except (chezscheme) car), " chez-only)
                  (string-append (at "chez-wrapped" "curl/w10.sls")
                                 ": (curl w10) imports (only (only (chezscheme) format car) format), " chez-only)
                  (string-append (at "chez-wrapped" "curl/w2.sls")
                                 ": (curl w2) imports (prefix (chezscheme) c:), " chez-only)
                  (string-append (at "chez-wrapped" "curl/w3.sls")
                                 ": (curl w3) imports (rename (chezscheme) (car kar)), " chez-only)
                  (string-append (at "chez-wrapped" "curl/w4.sls")
                                 ": (curl w4) imports (for (chezscheme) expand), " chez-only)
                  (string-append (at "chez-wrapped" "curl/w5.sls")
                                 ": (curl w5) imports (library (chezscheme)), " chez-only)
                  (string-append (at "chez-wrapped" "curl/w6.sls")
                                 ": (curl w6) imports (for (only (chezscheme) format) expand), " chez-only)
                  (string-append (at "chez-wrapped" "curl/w7.sls")
                                 ": (curl w7) imports (only (prefix (chezscheme) c:) c:format), " chez-only)
                  (string-append (at "chez-wrapped" "curl/w8.sls")
                                 ": (curl w8) imports (only (library (chezscheme)) format), " chez-only)
                  (string-append (at "chez-wrapped" "curl/w9.sls")
                                 ": (curl w9) imports (only (scheme) format), " chez-only)))
   (list "name-import-only"
         "a name outside allowed-chez-names: import-only, which opens an import in a body"
         (refused 1 (string-append (at "name-import-only" "curl/a.sls") ": (curl a) " (not-listed "import-only"))))
   (list "name-top-level-value"
         "a name outside allowed-chez-names: top-level-value, which reaches eval"
         (refused 1 (string-append (at "name-top-level-value" "curl/b.sls") ": (curl b) " (not-listed "top-level-value"))))
   (list "name-primitive"
         "a name outside allowed-chez-names: $primitive, which reaches eval"
         (refused 1 (string-append (at "name-primitive" "curl/d.sls") ": (curl d) " (not-listed "$primitive"))))
   (list "names-several"
         "several names, some listed and some not: each one outside is named, in order"
         (refused 2
                  (string-append (at "names-several" "curl/n.sls") ": (curl n) " (not-listed "eval"))
                  (string-append (at "names-several" "curl/n.sls") ": (curl n) " (not-listed "$primitive"))))
   (list "names-denylisted"
         "the names the old denylist held are outside the allowlist too"
         (apply refused 12
                (map (lambda (name)
                       (string-append (at "names-denylisted" "curl/n.sls") ": (curl n) " (not-listed name)))
                     '("import" "include" "include-library-declarations" "eval" "environment"
                       "interaction-environment" "load" "load-library" "library-directories"
                       "interpret" "compile" "load-program"))))
   (list "names-not-symbols"
         "an only over (chezscheme) with a name that is no identifier"
         (refused 1 (string-append (at "names-not-symbols" "curl/n.sls")
                                   ": (curl n) has an import it cannot read: (only (chezscheme) 42)")))
   (list "rnrs-eval"
         "(rnrs eval), plain and wrapped"
         (refused 2
                  (string-append (at "rnrs-eval" "curl/e1.sls")
                                 ": (curl e1) imports (rnrs eval), but no library under src/ may import (rnrs eval)")
                  (string-append (at "rnrs-eval" "curl/e2.sls")
                                 ": (curl e2) imports (rnrs eval), but no library under src/ may import (rnrs eval)")))

   ;; --- rule (f): names only some libraries may import ---
   (list "ftype-listed"
         "rule (f), passing: define-ftype imported by (curl private layouts), the one library library-only-chez-names lists for it"
         (holds 2 2))
   (list "ftype-elsewhere"
         "rule (f): define-ftype imported by a library that is not listed, in either family, or by names that only look like the listed one; the listed library beside them is not named"
         (refused 4
                  (string-append (at "ftype-elsewhere" "curl/f.sls") ": (curl f) "
                                 (library-only "define-ftype" "(curl private layouts)"))
                  (string-append (at "ftype-elsewhere" "curl/layouts.sls") ": (curl layouts) "
                                 (library-only "define-ftype" "(curl private layouts)"))
                  (string-append (at "ftype-elsewhere" "curl/private/layouts-extra.sls")
                                 ": (curl private layouts extra) "
                                 (library-only "define-ftype" "(curl private layouts)"))
                  (string-append (at "ftype-elsewhere" "http-client/h.sls") ": (http-client h) "
                                 (library-only "define-ftype" "(curl private layouts)"))))
   (list "ftype-with-unlisted"
         "rule (f) and rule (c) in one import set: each name outside its list is named, in the order the import set holds them"
         (refused 3
                  (string-append (at "ftype-with-unlisted" "curl/m.sls") ": (curl m) " (not-listed "eval"))
                  (string-append (at "ftype-with-unlisted" "curl/m.sls") ": (curl m) "
                                 (library-only "define-ftype" "(curl private layouts)"))
                  (string-append (at "ftype-with-unlisted" "curl/m.sls") ": (curl m) " (not-listed "$primitive"))))

   ;; --- rule (g): no library exports a name it imports from (chezscheme) ---
   (list "export-chez"
         "rule (g): a name imported from (chezscheme) exported, plain or as a rename spec's internal name, in either family, each in export order; a name from (rnrs), a rename of a library's own definition to a (chezscheme) name, and a definition named like a (chezscheme) binding are not named"
         (refused 4
                  (string-append (at "export-chez" "curl/private/layouts.sls") ": (curl private layouts) "
                                 (re-exports "define-ftype" "define-ftype"))
                  (string-append (at "export-chez" "curl/r.sls") ": (curl r) " (re-exports "format" "format"))
                  (string-append (at "export-chez" "curl/r.sls") ": (curl r) "
                                 (re-exports "getenv as curl-getenv" "getenv"))
                  (string-append (at "export-chez" "http-client/h.sls") ": (http-client h) "
                                 (re-exports "format" "format"))))
   (list "export-unreadable"
         "rule (g) fails closed: each export spec that is neither an identifier nor (rename (internal external) ...) is named, in order, a cyclic one included"
         (apply refused 9
                (append
                 (map (lambda (spec)
                        (string-append (at "export-unreadable" "curl/x.sls") ": (curl x) has an export it cannot read: " spec))
                      '("42" "\"s\"" "(car)" "(foo car)" "(rename car kar)" "(rename (car))"
                        "(rename (car kar kaar))" "(rename (car 1))"))
                 (list (string-append (at "export-unreadable" "curl/y.sls")
                                      ": (curl y) has an export it cannot read: (rename #0=(a #0#))")))))
   (list "export-wrapped-chez"
         "rule (g) and a wrapper over (only (chezscheme) ...): except, for, prefix and rename are each refused by rule (c), so none can rename a name imported from (chezscheme) unseen"
         (refused 4
                  (string-append (at "export-wrapped-chez" "curl/e.sls")
                                 ": (curl e) imports (except (only (chezscheme) format getenv) getenv), " chez-only)
                  (string-append (at "export-wrapped-chez" "curl/f.sls")
                                 ": (curl f) imports (for (only (chezscheme) format) run), " chez-only)
                  (string-append (at "export-wrapped-chez" "curl/p.sls")
                                 ": (curl p) imports (prefix (only (chezscheme) format) c:), " chez-only)
                  (string-append (at "export-wrapped-chez" "curl/r.sls")
                                 ": (curl r) imports (rename (only (chezscheme) format) (format fmt)), " chez-only)))

   ;; --- the import allowlist ---
   (list "unlisted-libraries"
         "a library not on the import allowlist: a third-party one, (chezscheme csv7), ($system), (scheme csv7), a test library, a near-family name, an (rnrs ...) name R6RS lacks"
         (refused 9
                  (string-append (at "unlisted-libraries" "curl/u1.sls") ": (curl u1) imports (srfi :1), " unlisted-tail)
                  (string-append (at "unlisted-libraries" "curl/u2.sls") ": (curl u2) imports (chezscheme csv7), " unlisted-tail)
                  (string-append (at "unlisted-libraries" "curl/u3.sls") ": (curl u3) imports ($system), " unlisted-tail)
                  (string-append (at "unlisted-libraries" "curl/u4.sls") ": (curl u4) imports (scheme csv7), " unlisted-tail)
                  (string-append (at "unlisted-libraries" "curl/u5.sls") ": (curl u5) imports (curl-testing), " unlisted-tail)
                  (string-append (at "unlisted-libraries" "curl/u6.sls") ": (curl u6) imports (http-client-extras), " unlisted-tail)
                  (string-append (at "unlisted-libraries" "curl/u7.sls") ": (curl u7) imports (rnrs foo), " unlisted-tail)
                  (string-append (at "unlisted-libraries" "curl/u8.sls") ": (curl u8) imports (libcurl-oracle), " unlisted-tail)
                  (string-append (at "unlisted-libraries" "curl/u9.sls") ": (curl u9) imports (srfi :64), " unlisted-tail)))

   ;; --- files Chez could load that the program does not read ---
   (list "unread-ss"
         "a .ss file, which Chez loads as a library and the program does not read"
         (refused 1 (string-append (at "unread-ss" "curl/hidden.ss") ": " (unread ".ss"))))
   (list "unread-so"
         "a lone .so, with no source beside it, whatever it holds"
         (refused 1 (string-append (at "unread-so" "curl/lone.so") ": " (unread ".so"))))
   (list "unread-extensions"
         "every unread ending, each named for its longest: .ss .scm .sch .chezscheme.sls .so .chezscheme.so"
         (refused 6
                  (string-append (at "unread-extensions" "curl/a.ss") ": " (unread ".ss"))
                  (string-append (at "unread-extensions" "curl/b.scm") ": " (unread ".scm"))
                  (string-append (at "unread-extensions" "curl/c.sch") ": " (unread ".sch"))
                  (string-append (at "unread-extensions" "curl/d.chezscheme.sls") ": " (unread ".chezscheme.sls"))
                  (string-append (at "unread-extensions" "curl/e.so") ": " (unread ".so"))
                  (string-append (at "unread-extensions" "curl/f.chezscheme.so") ": " (unread ".chezscheme.so"))))
   (list "dir-symlink"
         "a symbolic link to a directory, which the program does not follow"
         (refused 1 (string-append (at "dir-symlink" "linked")
                                   ": it is a symbolic link to a directory, which this check does not follow")))

   ;; --- Emacs lock files: .#name, a dangling symbolic link ---
   (list "lock-symlink"
         "a .# dangling symbolic link, which is Emacs's lock file, is skipped"
         (holds 1 1))
   (list "lock-regular"
         "a .# regular file is no lock file: it is read and checked"
         (refused 1 (string-append (at "lock-regular" "curl/.#g.sls")
                                   ": (curl \\x2E;\\x23;g) imports (http-client target), " seam-a)))
   (list "lock-directory"
         "a .# directory is no lock file: it is walked"
         (refused 1 (string-append (at "lock-directory" "curl/.#dir/bad.sls")
                                   ": (curl \\x2E;\\x23;dir bad) imports (http-client target), " seam-a)))
   (list "lock-symlink-live"
         "a .# symbolic link that resolves to a library is no lock file: it is read"
         (holds 2 2))
   (list "dangling-link"
         "a dangling symbolic link not named .# is no lock file: it is named, for it cannot be read"
         (refused 1 (no-such-file "dangling-link" "curl/dangling.sls")))
   (list "dangling-dot-link"
         "a dangling symbolic link named with a dot but not .# is no lock file"
         (refused 1 (no-such-file "dangling-dot-link" "curl/.dangling.sls")))
   (list "dangling-hash-link"
         "a dangling symbolic link with .# inside its name, not at its start, is no lock file"
         (refused 1 (no-such-file "dangling-hash-link" "curl/a.#b.sls")))

   ;; --- fails closed ---
   (list "no-datum"
         "a file that holds no datum"
         (refused 1 (string-append (at "no-datum" "curl.sls") ": it holds no datum, so it holds no library form")))
   (list "not-a-library"
         "a datum that is no library form, the first or a later one"
         (refused 2
                  (string-append (at "not-a-library" "curl/d1.sls") ": datum 1 is (define x 1), not a library form")
                  (string-append (at "not-a-library" "curl/d2.sls") ": datum 2 is (define y 2), not a library form")))
   (list "unreadable"
         "a file that cannot be read as data"
         (refused 1 (string-append (at "unreadable" "curl/broken.sls")
                                   ": it cannot be read as data: Exception in read: unexpected end-of-file reading list before file-position 48 of #<input port "
                                   (at "unreadable" "curl/broken.sls")
                                   ">; the character position might differ")))
   (list "eof-literal"
         "a file with an #!eof literal, which would end the reading early"
         (refused 1 (string-append (at "eof-literal" "curl/eof.sls")
                                   ": it cannot be read as data: Exception in read: an #!eof literal ends the reading before the end of the file")))
   (list "cannot-read-import"
         "an import it cannot read: a number, an empty list, a bare only, and a cyclic datum"
         (refused 4
                  (string-append (at "cannot-read-import" "curl/m1.sls")
                                 ": (curl m1) has an import it cannot read: 42")
                  (string-append (at "cannot-read-import" "curl/m2.sls")
                                 ": (curl m2) has an import it cannot read: ()")
                  (string-append (at "cannot-read-import" "curl/m3.sls")
                                 ": (curl m3) has an import it cannot read: (only)")
                  (string-append (at "cannot-read-import" "curl/m4.sls")
                                 ": (curl m4) has an import it cannot read: #0=(only #0# x)")))))

(test-begin "check-seam")

(test-equal "CHEZ names the Chez to spawn"
  'set
  (if (and chez (not (string=? chez ""))) 'set 'unset))

(unless (and chez (not (string=? chez "")))
  (exit 1))

(for-each
 (lambda (case)
   (test-equal (string-append (car case) ": " (cadr case))
     (caddr case)
     (run (list (string-append fixtures "/" (car case))))))
 cases)

;; A fixture nothing runs guards nothing, and a case with no fixture runs on a
;; missing directory.
(test-equal "every fixture directory is a case above, and every case has its directory"
  (list-sort string<? (map car cases))
  (list-sort string<?
             (filter (lambda (name) (file-directory? (string-append fixtures "/" name)))
                     (directory-list fixtures))))

;; --- the lists the program holds are exact ------------------------------------------------
;; allowed-chez-names is "exactly the names src/ imports from (chezscheme)": a
;; name in it that no library uses is a permission nobody exercises, and a
;; name a library uses that is not in it fails check-seam. Each entry of
;; library-only-chez-names is a name in allowed-chez-names and the libraries
;; that alone may import it: exactly the libraries under src/ that do, so a
;; library listed that no longer imports the name is a stale permission, and one
;; that imports it unlisted fails check-seam. rnrs-libraries is the standard
;; libraries but (rnrs eval). Each list is read from the program as data, never
;; from its output.

;; read-forms : String -> (Listof Any)
(define (read-forms path)
  (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                        (make-transcoder (utf-8-codec)))
    (lambda (port)
      (let loop ((found '()))
        (let ((datum (read port)))
          (if (eof-object? datum) (reverse found) (loop (cons datum found))))))))

;; declared : Symbol -> Any
;; What the program's (define NAME '(...)) lists.
(define (declared name)
  (guard (e (#t (list 'unreadable (describe e))))
    (let ((form (find (lambda (form)
                        (and (pair? form) (eq? (car form) 'define)
                             (pair? (cdr form)) (eq? (cadr form) name)))
                      (read-forms program))))
      (if form (cadr (caddr form)) '(not-defined)))))

(define declared-names (declared 'allowed-chez-names))

;; sls-files : String -> (Listof String)
(define (sls-files dir)
  (apply append
         (map (lambda (name)
                (let ((path (string-append dir "/" name)))
                  (cond ((file-directory? path) (sls-files path))
                        ((and (> (string-length name) 4)
                              (string=? (substring name (- (string-length name) 4)
                                                   (string-length name))
                                        ".sls"))
                         (list path))
                        (else '()))))
              (directory-list dir))))

;; chez-imports : -> (Listof (Pair (Listof Symbol) (Listof Symbol)))
;; Each library form under src/ as its name and the names it imports from
;; (chezscheme), through (only (chezscheme) name ...) in its import clause. No
;; duplicate name in a pair. A name that carries a version reference would not
;; equal its entry in library-only-chez-names, and fail the test below.
;; Raises when src/ cannot be read.
(define (chez-imports)
  (apply append
         (map (lambda (path)
                (map (lambda (form)
                       (cons (cadr form)
                             (fold-left
                              (lambda (found spec)
                                (if (and (pair? spec) (eq? (car spec) 'only)
                                         (pair? (cdr spec)) (equal? (cadr spec) '(chezscheme)))
                                    (fold-left (lambda (found id) (if (memq id found) found (cons id found)))
                                               found (cddr spec))
                                    found))
                              '() (cdr (cadddr form)))))
                     (filter (lambda (form)
                               (and (pair? form) (eq? (car form) 'library) (list? form) (> (length form) 3)))
                             (read-forms path))))
              (sls-files "src"))))

;; imported-names : (Listof Symbol)
;; The names the libraries under src/ import from (chezscheme). No duplicate.
(define imported-names
  (guard (e (#t (list 'unreadable (describe e))))
    (fold-left (lambda (found id) (if (memq id found) found (cons id found)))
               '() (apply append (map cdr (chez-imports))))))

(define (symbols<? a b) (string<? (symbol->string a) (symbol->string b)))

;; sorted : (Listof Any) -> (Listof Any)
;; NAMES sorted by name; (unsortable NAMES) when they are not all symbols, as
;; the (unreadable TEXT) a failed read leaves is not. SRFI-64 does not catch a
;; raise in an expected expression, so neither side may raise.
(define (sorted names)
  (guard (e (#t (list 'unsortable names)))
    (list-sort symbols<? names)))

(test-equal "the scan of src/ found names imported from (chezscheme)"
  'found
  (if (and (pair? imported-names) (not (eq? (car imported-names) 'unreadable))) 'found imported-names))

(test-equal "allowed-chez-names is exactly the names the libraries under src/ import from (chezscheme)"
  (sorted imported-names)
  (sorted declared-names))

;; written : Any -> String
(define (written x) (call-with-string-output-port (lambda (p) (write x p))))

;; sorted-libraries : Any -> Any
;; NAMES, a list of library names, sorted as written; (unsortable NAMES) when
;; it is no list of lists.
(define (sorted-libraries names)
  (guard (e (#t (list 'unsortable names)))
    (list-sort (lambda (a b) (string<? (written a) (written b))) names)))

(define declared-library-only (declared 'library-only-chez-names))

;; library-name? : Any -> Boolean
(define (library-name? x) (and (pair? x) (list? x) (for-all symbol? x)))

;; entry? : Any -> Boolean
;; Whether X is (name library-name ...), with at least one library: an entry
;; that lists none would let no library import the name, which leaving the name
;; out of allowed-chez-names does as well.
(define (entry? x)
  (and (pair? x) (list? x) (symbol? (car x)) (pair? (cdr x)) (for-all library-name? (cdr x))))

(test-equal "library-only-chez-names is a list of (name library ...) entries"
  'entries
  (if (and (list? declared-library-only) (for-all entry? declared-library-only))
      'entries
      declared-library-only))

(test-equal "every name in library-only-chez-names is in allowed-chez-names"
  '()
  (guard (e (#t (list 'unreadable (describe e))))
    (remp (lambda (id) (memq id declared-names))
          (map car declared-library-only))))

;; SRFI-64 does not catch a raise in the expected expression. Each side is
;; built under a guard of its own, with a sentinel of its own, so that a
;; malformed list or a src/ that cannot be read fails this test, and cannot
;; make the two sides equal.
(test-equal "each library-only-chez-names entry lists exactly the libraries under src/ that import its name"
  (guard (e (#t (list 'unreadable (describe e))))
    (let ((scan (chez-imports)))
      (map (lambda (entry)
             (cons (car entry)
                   (sorted-libraries
                    (map car (filter (lambda (library) (memq (car entry) (cdr library))) scan)))))
           declared-library-only)))
  (guard (e (#t (list 'malformed (describe e))))
    (map (lambda (entry) (cons (car entry) (sorted-libraries (cdr entry))))
         declared-library-only)))

(test-equal "rnrs-libraries is the (rnrs ...) libraries this Chez has, but (rnrs eval)"
  (sorted-libraries
   (filter (lambda (name)
             (and (pair? name) (eq? (car name) 'rnrs) (not (equal? name '(rnrs eval)))))
           (library-list)))
  (sorted-libraries (declared 'rnrs-libraries)))

;; --- the cases no fixture tree can hold ----------------------------------------------

;; Git keeps no empty directory, and the program is told a path that need not exist.
(test-equal "an empty directory holds no library"
  'refused
  (call-with-temp-directory
   (lambda (dir)
     (if (equal? (run (list dir))
                 (refused 1 (string-append "no libraries: " dir
                                           " holds no .sls file, so there is no seam to check")))
         'refused
         (run (list dir))))))

(test-equal "a directory that does not exist holds no library"
  'refused
  (call-with-temp-directory
   (lambda (dir)
     (let ((missing (string-append dir "/no-such-directory")))
       (if (equal? (run (list missing))
                   (refused 1 (string-append "no libraries: " missing
                                             " holds no .sls file, so there is no seam to check")))
           'refused
           (run (list missing)))))))

(define usage
  (list 1 "" "check-seam: usage: scheme --program tests/check-seam.sps DIR\n"))

(test-equal "no directory named: the usage line, exit 1" usage (run '()))

(test-equal "two directories named: the usage line, exit 1" usage (run '("a" "b")))

(test-end "check-seam")

(exit (suite-exit-status runner))
