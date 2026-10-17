#!r6rs
;;; The suite for tests/check-nothreads.sps, the program behind `make
;;; check-nothreads` (harness plan, section 4; ADR-0001). On a --nothreads Chez
;;; every public library must be refused at import, by name; the program
;;; imports each and requires (curl private require-threaded)'s refusal. CI runs
;;; it on a Chez built with --nothreads, the one place the refusal meets a real
;;; non-threaded Chez. Everything else is held here, on the Chez that runs the
;;; suites, which is threaded, so the real src/ must FAIL the program, naming
;;; each public library it could import. That failure is the program's red run.
;;; Without this suite, deleting a rule would leave `make test` green: nothing
;;; else runs the program.
;;;
;;; Every rule has a fixture tree under tests/fixtures/nothreads/<case>/, whose
;;; require-threaded behaves as the case says whatever Chez runs it. This suite
;;; runs the program on each in a fresh Chez, through capture-command. A case
;;; asserts the exit status, the whole of stdout and the whole of stderr, as
;;; text written by hand here, never read back from the program: a substring
;;; would pass whenever another rule produced the same words.
;;;
;;; Each tree is the one fault it names, in an otherwise legal setting, so that
;;; only that rule can make it fail. `refusing` is the legal tree: three public
;;; libraries that import the refusal, and a private library that does not and
;;; would load, so a check that wrongly imports private libraries fails it.
;;;
;;; make test runs every suite from the repository root, where tests/ and src/
;;; are, with CHEZ exported. Without CHEZ nothing below can run: that fails
;;; here, by name, and never skips.
(import (rnrs)
        (srfi :64)
        (curl-testing)
        (only (chezscheme) getenv directory-list file-directory?))

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

(define program "tests/check-nothreads.sps")

(define fixtures "tests/fixtures/nothreads")

;; outcome : (-> Any) -> (U (List 'returned Any) (List 'raised String))
;; What THUNK did: returned a value, or raised, and what.
(define (outcome thunk)
  (guard (e (#t (list 'raised (describe e))))
    (list 'returned (thunk))))

;; run : (Listof String) -> (U (List Integer String String) (List 'raised String))
;; tests/check-nothreads.sps in a fresh Chez with ARGS: its exit status, stdout
;; and stderr. No --libdirs: the program finds the libraries it scans itself.
(define (run args)
  (guard (e (#t (list 'raised (describe e))))
    (capture-command (append (list chez "--program" program) args))))

;; at : String -> String
;; The directory argument for the fixture tree CASE.
(define (at case) (string-append fixtures "/" case))

;; --- the words the lines are made of, written by hand ------------------------------

;; line : String -> String
(define (line text) (string-append "check-nothreads: " text "\n"))

;; refused-line : String -> String
;; What a library that is refused by name gets, on stdout.
(define (refused-line name)
  (line (string-append name " is refused by name")))

;; loaded-line : String -> String
(define (loaded-line name)
  (line (string-append name " loaded, but a non-threaded Chez must refuse it")))

;; other-line : String String -> String
(define (other-line name what)
  (line (string-append name " raised something other than the refusal: " what)))

;; failed : Natural -> String
;; The last line of a failure. COUNT is given, not counted, so a miscount in the
;; program is not copied here.
(define (failed count)
  (line (string-append "FAILED (problems: " (number->string count) ")")))

;; passes : String ... -> (List 0 String "")
;; What a pass prints: one line for each library, in order.
(define (passes . names)
  (list 0 (apply string-append (map refused-line names)) ""))

;; fails : String Natural String ... -> (List 1 String String)
;; What a failure prints: STDOUT as given, then on stderr each problem line as
;; given, and the count.
(define (fails stdout count . problem-lines)
  (list 1 stdout (string-append (apply string-append problem-lines) (failed count))))

;; none : String -> String
;; The line for a tree with no public library to import.
(define (none dir)
  (line (string-append "no public library under " dir ", so there is nothing to refuse")))

(define usage
  (list 1 "" (line "usage: scheme --program tests/check-nothreads.sps DIR")))

;; The text Chez shows for a raise at expansion in a fixture's refusal: the
;; condition, the form, and where, as display-condition writes them.
(define (raised-at case what form where)
  (string-append what " (" form ") at " where " of "
                 (at case) "/curl/private/require-threaded.sls"))

(define threads-message
  "chez-curl needs a threaded Chez Scheme, and (threaded?) is #f in this one")

;; --- the fixture trees ---------------------------------------------------------------

;; cases : (Listof (List String String Expected))
;; The fixture directory, what it holds, and the program's whole answer.
(define cases
  (list
   (list "refusing"
         "every public library imports the refusal, which refuses; a private library that would load is not imported"
         (passes "(curl)" "(curl unsupported)" "(http-client)"))
   (list "mixed"
         "one public library does not import the refusal: it loads, and is named, and the others are still refused"
         (fails (string-append (refused-line "(curl)") (refused-line "(http-client)"))
                1
                (loaded-line "(curl unsupported)")))
   (list "raises-other"
         "the refusal raises, but a plain error, not the refusal"
         (fails "" 1
                (other-line "(curl)" "Exception in fixture: boom")))
   (list "wrong-message"
         "a syntax violation from chez-curl whose message is not the threads refusal's"
         (fails "" 1
                (other-line "(curl)"
                            (raised-at "wrong-message"
                                       "Exception in chez-curl: chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0"
                                       "refuse" "line 13, char 3"))))
   (list "wrong-who"
         "the threads refusal's message in a syntax violation from someone else"
         (fails "" 1
                (other-line "(curl)"
                            (raised-at "wrong-who"
                                       (string-append "Exception in someone-else: " threads-message)
                                       "refuse" "line 13, char 3"))))
   (list "not-syntax"
         "the threads refusal's who and message in an assertion violation, not a syntax violation"
         (fails "" 1
                (other-line "(curl)"
                            (string-append "Exception in chez-curl: " threads-message))))
   (list "private-only"
         "private libraries alone: the program imports none, so it has nothing to refuse"
         (fails "" 1 (none (at "private-only"))))
   (list "empty"
         "a tree with no library source in it"
         (fails "" 1 (none (at "empty"))))
   (list "unreadable"
         "a source that cannot be read as data is named, and the libraries beside it are still checked"
         (fails (refused-line "(curl)") 1
                (line (string-append
                       (at "unreadable") "/curl/broken.sls"
                       ": it cannot be read as data: Exception in read: unexpected end-of-file reading list before file-position 48 of #<input port "
                       (at "unreadable") "/curl/broken.sls"
                       ">; the character position might differ"))))
   (list "dir-symlink"
         "a symbolic link to a directory is named, not followed"
         (fails (refused-line "(curl)") 1
                (line (string-append (at "dir-symlink") "/linked"
                                     ": it is a symbolic link to a directory, which this check does not follow"))))))

(test-begin "check-nothreads")

(test-equal "CHEZ names the Chez to spawn"
  'set
  (if (and chez (not (string=? chez ""))) 'set 'unset))

(unless (and chez (not (string=? chez "")))
  (exit 1))

(for-each
 (lambda (case)
   (test-equal (string-append (car case) ": " (cadr case))
     (caddr case)
     (run (list (at (car case))))))
 cases)

;; A fixture nothing runs guards nothing, and a case with no fixture runs on a
;; missing directory.
(test-equal "every fixture directory is a case above, and every case has its directory"
  (list-sort string<? (map car cases))
  (list-sort string<?
             (filter (lambda (name) (file-directory? (string-append fixtures "/" name)))
                     (directory-list fixtures))))

;; --- arguments ---------------------------------------------------------------------------

(test-equal "a directory that does not exist holds no public library"
  (fails "" 1 (none (at "no-such-tree")))
  (run (list (at "no-such-tree"))))

(test-equal "no arguments: the usage line, exit 1"
  usage
  (run '()))

(test-equal "two arguments: the usage line, exit 1"
  usage
  (run (list (at "refusing") (at "mixed"))))

;; --- the real tree --------------------------------------------------------------------------
;; This Chez is threaded, so nothing refuses (curl) here: the program must fail
;; on src/, naming every public library it finds. The expected names come from
;; a scan written out in this suite, so that a library a later slice adds is
;; named without editing the row, and a scan of the wrong directory finds no
;; (curl) and fails the row below it.

;; sls-files : String -> (Listof String)
;; Every .sls under DIR, depth first, sorted by path.
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
              (list-sort string<? (directory-list dir)))))

;; library-name : String -> (U (Listof Symbol) Symbol)
;; The name of the library form that opens the file at PATH, or a symbol when
;; it holds none.
(define (library-name path)
  (guard (e (#t 'unreadable))
    (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                          (make-transcoder (utf-8-codec)))
      (lambda (port)
        (let ((form (read port)))
          (if (and (pair? form) (eq? (car form) 'library) (pair? (cdr form)))
              (cadr form)
              'no-library))))))

;; written : Any -> String
(define (written datum)
  (call-with-string-output-port (lambda (p) (write datum p))))

;; public-names : (Listof String)
;; The public libraries under src/, as the program writes them, in path order.
;; None when src/ cannot be listed: a raise at top level would end the suite
;; with no test named, and the rows below then fail by name.
(define public-names
  (guard (e (#t '()))
    (let loop ((names (map library-name (sls-files "src"))) (found '()))
      (cond ((null? names) (reverse found))
            ((and (pair? (car names)) (not (memq 'private (car names))))
             (loop (cdr names) (cons (written (car names)) found)))
            (else (loop (cdr names) found))))))

(test-equal "src/ holds the public library (curl)"
  'found
  (if (member "(curl)" public-names) 'found 'not-found))

(test-equal "src/: on a threaded Chez nothing is refused, so the program names every public library it could import"
  (apply fails "" (length public-names) (map loaded-line public-names))
  (run (list "src")))

(test-end "check-nothreads")

(exit (suite-exit-status runner))
