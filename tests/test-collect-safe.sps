#!r6rs
;;; The suite for the calling conventions of chez-curl's foreign procedures
;;; and callables (ADR-0013, harness plan §3 item 3). (foreign-conventions)
;;; reads every source file under src/ as data, evaluating nothing, finds
;;; each foreign-procedure and foreign-callable, and holds its conventions
;;; against conventions-table, whose rows cite the decision records. So a
;;; call that blocks bound plain, such as curl_easy_perform in M2, fails here
;;; at once, as does memcpy bound __collect_safe.
;;;
;;; The reader fails closed. Every occurrence of the symbols
;;; foreign-procedure and foreign-callable must be accounted for: in an
;;; (only (chezscheme) ...) import, as the head of a form whose entry is a
;;; string literal, as the one foreign-procedure form in the template of a
;;; known wrapper, or, for a callable, as the whole right-hand side of a
;;; (define name ...). Anything else is named, with its file and form.
;;;
;;; Every rule has a fixture tree under tests/fixtures/conventions/<case>/,
;;; and each case asserts the reader's whole answer, the bindings it found
;;; and the violations, as data written by hand here. A violation list of ()
;;; is never asserted alone: the live scan of src/ must also find the six
;;; entries loading binds, so a reader that reads nothing fails.
;;;
;;; Each call into the library runs under `outcome`, so a raise is a value
;;; to compare, never a #f from SRFI-64 nor a suite that dies unnamed.
;;;
;;; make test runs every suite from the repository root, where src/, tests/
;;; and .plans/ are.
(import (rnrs)
        (srfi :64)
        (curl-testing)
        (foreign-conventions)
        (only (chezscheme) directory-list file-directory?))

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

;; outcome : (-> Any) -> (U (List 'returned Any) (List 'raised String))
(define (outcome thunk)
  (guard (e (#t (list 'raised (describe e))))
    (list 'returned (thunk))))

(define source-root "src")

(define fixtures "tests/fixtures/conventions")

;; at : String String -> String
;; The path the reader names for FILE in the fixture tree CASE.
(define (at case file) (string-append fixtures "/" case "/" file))

;; A citation the suite's seeded tables share: a record and a phrase it holds.
(define plain-record ".plans/decisions/0013-collect-safe-blocking-calls.md")
(define good-citation (string-append plain-record ": Calls that cannot block stay plain."))

;; Rows for the fixture trees alone: two conventions, to compare as sets, and
;; two callables. src/ has no callable yet, so the real table has no row for
;; one.
(define fixture-rows
  '(("fixture_two_conventions" (__collect_safe (__varargs_after 2)) "a fixture row")
    (on-write (__collect_safe) "a fixture row")
    (on-plain () "a fixture row")))

;; The real table and the fixture rows. A table that is no list cannot be
;; appended to; the suite's top level must not raise, so that is a sentinel.
(define fixture-table
  (guard (e (#t (list 'unbuildable (describe e))))
    (append conventions-table fixture-rows)))

;; The reasons a known wrapper cannot be read.
(define not-syntax-rules
  "it is not (syntax-rules (literal ...) (pattern template)), with one clause")
(define no-binding "its template holds no foreign-procedure form")
(define many-bindings "its template holds more than one foreign-procedure form")
(define malformed-binding "its foreign-procedure form is malformed")
(define unplaced-entry "its entry is not a pattern variable at a fixed place in its pattern")

;; cases : (Listof (List String String (Listof Symbol) (Listof Binding) (Listof Violation)))
;; The fixture directory, what it holds, the known wrappers to read it with,
;; and the whole answer: the bindings found, then the violations.
(define cases
  (let ((a (at "legal" "curl/a.sls"))
        (b (at "legal" "curl/b.sls"))
        (q (at "quoted" "curl/q.sls"))
        (r (at "quoted" "curl/r.sls"))
        (s (at "stray" "curl/s.sls"))
        (i (at "imports" "curl/i.sls"))
        (e (at "entry-not-string" "curl/e.sls"))
        (m (at "malformed" "curl/m.sls"))
        (c (at "callable-misplaced" "curl/c.sls"))
        (x (at "mismatch" "curl/x.sls"))
        (p (at "blocking-plain" "curl/p.sls"))
        (n (at "no-row" "curl/n.sls"))
        (ws (at "wrapper-safe" "curl/w.sls"))
        (wp (at "wrapper-pattern-conventions" "curl/w.sls"))
        (wu (at "wrapper-unreadable" "curl/w.sls"))
        (we (at "wrapper-entry-not-string" "curl/u.sls"))
        (wn (at "wrapper-undefined" "curl/u.sls"))
        (wa (at "wrapper-defined-again" "curl/a.sls"))
        (wb (at "wrapper-defined-again" "curl/b.sls"))
        (g (at "shared-structure" "curl/g.sls"))
        (ub (at "unreadable" "curl/broken.sls"))
        (ue (at "unreadable" "curl/eof.sls"))
        (ok (at "dir-symlink" "curl/ok.sls"))
        (la (at "lock-file" "curl/a.sls"))
        (lb (at "lock-file" "curl/.#b.sls"))
        (lg (at "lock-file" "curl/gone.sls")))
    (list
     (list "legal"
           "every accounted place: the import, the known wrapper and its uses in two files, direct bindings, two conventions as a set, a template that is no wrapper, callables, and look-alikes"
           known-wrappers
           `(("curl_easy_init" () ,a bind-required)
             ("curl_easy_perform" (__collect_safe) ,a foreign-procedure)
             ("memcpy" () ,a foreign-procedure)
             ("fixture_two_conventions" ((__varargs_after 2) __collect_safe) ,a foreign-procedure)
             ("curl_multi_poll" (__collect_safe) ,a foreign-procedure)
             (on-write (__collect_safe) ,a foreign-callable)
             ("curl_global_init" () ,b bind-required)
             ("curl_multi_perform" () ,b foreign-procedure)
             (on-plain () ,b foreign-callable))
           '())

     ;; --- occurrences that are not accounted for ---
     (list "quoted"
           "quoted occurrences: a symbol, a list, a quasiquote with an unquote, a syntax form, a vector literal holding a form, a box literal holding one"
           known-wrappers
           '()
           `((stray ,q "(quote foreign-procedure)")
             (stray ,q "(foreign-procedure \"curl_easy_init\" () uptr)")
             (stray ,q "(foreign-procedure \"curl_global_init\" (long) int)")
             (stray ,q "(syntax foreign-callable)")
             (stray ,q "#(foreign-callable (foreign-procedure \"curl_easy_perform\" (uptr) int))")
             (stray ,q "(foreign-procedure \"curl_easy_perform\" (uptr) int)")
             (stray ,r "(foreign-procedure \"curl_multi_poll\" (uptr uptr unsigned int uptr) int)")))
     (list "stray"
           "references that are no form's head: a define, a let binding, an improper tail, an identifier-syntax"
           known-wrappers
           '()
           `((stray ,s "(define fp foreign-procedure)")
             (stray ,s "(f foreign-callable)")
             (stray ,s "(rest . foreign-callable)")
             (stray ,s "(identifier-syntax foreign-procedure)")))
     (list "imports"
           "only (only (chezscheme) name ...) accounts for a name: not an export, an except, (scheme), nor an only inside a prefix"
           known-wrappers
           '()
           `((stray ,i "(export foreign-procedure)")
             (stray ,i "(except (chezscheme) foreign-callable)")
             (stray ,i "(only (scheme) foreign-procedure)")
             (stray ,i "(only (chezscheme) foreign-procedure)")))
     (list "entry-not-string"
           "an entry that is no string literal outside a known wrapper: a variable, an expression, a pattern variable"
           known-wrappers
           '()
           `((entry-not-string ,e "(foreign-procedure entry () uptr)")
             (entry-not-string ,e "(foreign-procedure (string-append \"curl_\" \"easy_init\") () uptr)")
             (entry-not-string ,e "(foreign-procedure e () int)")))
     (list "malformed"
           "forms too short, with no type list, improper, and a callable too short"
           known-wrappers
           '()
           `((malformed ,m "(foreign-procedure \"curl_easy_init\")")
             (malformed ,m "(foreign-procedure \"curl_easy_init\" uptr uptr)")
             (malformed ,m "(foreign-procedure . \"curl_easy_init\")")
             (malformed ,m "(foreign-callable (lambda () 0))")))
     (list "callable-misplaced"
           "a callable that is not the whole right-hand side of (define name ...)"
           known-wrappers
           '()
           `((callable-not-defined ,c "(foreign-callable (lambda (a) a) (int) int)")
             (callable-not-defined ,c "(foreign-callable (lambda (b) b) (int) int)")
             (callable-not-defined ,c "(foreign-callable (lambda (c) c) (int) int)")
             (callable-not-defined ,c "(foreign-callable (lambda (d) d) (int) int)")
             (callable-not-defined ,c "(foreign-callable (lambda (e) e) (int) int)")))

     ;; --- bindings against the table ---
     (list "mismatch"
           "a direct binding with a convention its row lacks, and a callable without the one its row requires"
           known-wrappers
           `(("curl_easy_init" (__collect_safe) ,x foreign-procedure)
             (on-write () ,x foreign-callable))
           `((mismatch "curl_easy_init" () (__collect_safe) ,x)
             (mismatch on-write (__collect_safe) () ,x)))
     (list "blocking-plain"
           "ADR-0013's rows: curl_easy_perform and curl_multi_poll bound plain, curl_multi_perform and memcpy bound __collect_safe"
           known-wrappers
           `(("curl_easy_perform" () ,p bind-required)
             ("curl_multi_poll" () ,p foreign-procedure)
             ("curl_multi_perform" (__collect_safe) ,p foreign-procedure)
             ("memcpy" (__collect_safe) ,p foreign-procedure))
           `((mismatch "curl_easy_perform" (__collect_safe) () ,p)
             (mismatch "curl_multi_poll" (__collect_safe) () ,p)
             (mismatch "curl_multi_perform" () (__collect_safe) ,p)
             (mismatch "memcpy" () (__collect_safe) ,p)))
     (list "no-row"
           "bindings with no row: an entry, a callable, and a callable named memcpy, a symbol"
           known-wrappers
           `(("curl_easy_reset" () ,n foreign-procedure)
             (on-unlisted () ,n foreign-callable)
             (memcpy () ,n foreign-callable))
           `((no-row "curl_easy_reset" ,n)
             (no-row on-unlisted ,n)
             (no-row memcpy ,n)))

     ;; --- the known wrapper ---
     (list "wrapper-safe"
           "__collect_safe in the known wrapper's template: every use gets it"
           known-wrappers
           `(("curl_easy_init" (__collect_safe) ,ws bind-required)
             ("curl_easy_perform" (__collect_safe) ,ws bind-required))
           `((mismatch "curl_easy_init" () (__collect_safe) ,ws)))
     (list "wrapper-pattern-conventions"
           "the known wrapper's conventions come from a pattern variable"
           known-wrappers
           '()
           `((wrapper-conventions-from-pattern ,wp bind-required (conv))))
     (list "wrapper-unreadable"
           "known wrappers the reader cannot read: syntax-case, two clauses, no binding, two, a nested entry, an ellipsis first, a string entry, a short form, an entry that is a literal"
           '(w-syntax-case w-two-clauses w-no-binding w-two-bindings w-nested-entry
             w-ellipsis-first w-entry-literal w-malformed w-literal-entry)
           '()
           `((wrapper-unreadable ,wu w-syntax-case ,not-syntax-rules)
             (entry-not-string ,wu "(foreign-procedure e () int)")
             (wrapper-unreadable ,wu w-two-clauses ,not-syntax-rules)
             (entry-not-string ,wu "(foreign-procedure e () long)")
             (wrapper-unreadable ,wu w-no-binding ,no-binding)
             (wrapper-unreadable ,wu w-two-bindings ,many-bindings)
             (entry-not-string ,wu "(foreign-procedure e () short)")
             (entry-not-string ,wu "(foreign-procedure e () double)")
             (wrapper-unreadable ,wu w-nested-entry ,unplaced-entry)
             (wrapper-unreadable ,wu w-ellipsis-first ,unplaced-entry)
             (wrapper-unreadable ,wu w-entry-literal ,unplaced-entry)
             (wrapper-unreadable ,wu w-malformed ,malformed-binding)
             (malformed ,wu "(foreign-procedure e)")
             (wrapper-unreadable ,wu w-literal-entry ,unplaced-entry)))
     (list "wrapper-entry-not-string"
           "uses of the known wrapper whose entry is no string literal: a variable, an expression, none at all"
           known-wrappers
           '()
           `((wrapper-entry-not-string ,we bind-required "(bind-required name () uptr #f)")
             (wrapper-entry-not-string ,we bind-required "(bind-required (string-append \"curl_\" \"easy_init\") () uptr #f)")
             (wrapper-entry-not-string ,we bind-required "(bind-required)")))
     (list "wrapper-undefined"
           "a use of the known wrapper that no file defines"
           known-wrappers
           '()
           `((wrapper-undefined ,wn bind-required "(bind-required \"curl_easy_init\" () uptr #f)")))
     (list "wrapper-defined-again"
           "the known wrapper defined in two files: no use is read against either"
           known-wrappers
           '()
           `((wrapper-defined-again ,wb bind-required)))

     ;; --- reading the tree ---
     (list "shared-structure"
           "a form labelled and referred to again: the datum holding it is named, and not read, binding included"
           known-wrappers
           '()
           `((shared-structure ,g "(foreign-procedure \"curl_easy_init\" () uptr)")))
     ;; After shared-structure: a reader that walked this datum would never
     ;; return, and the case above names that fault before this one hangs.
     (list "cyclic"
           "a cyclic datum is named, and the walk ends"
           known-wrappers
           '()
           `((shared-structure ,(at "cyclic" "curl/h.sls") "#0=(foreign-procedure . #0#)")))
     (list "unreadable"
           "a file that cannot be read as data, and one with an #!eof literal hiding a binding"
           known-wrappers
           '()
           `((unreadable ,ub ,(string-append "Exception in read: unexpected end-of-file reading list before file-position 48 of #<input port " ub ">; the character position might differ"))
             (unreadable ,ue "Exception in read: an #!eof literal ends the reading before the end of the file")))
     (list "extensions"
           "every source ending Chez loads a library from is read: .chezscheme.sls .ss .scm .sch; a .txt is not"
           known-wrappers
           '()
           `((stray ,(at "extensions" "curl/w.chezscheme.sls") "(quote foreign-procedure)")
             (stray ,(at "extensions" "curl/x.ss") "(quote foreign-procedure)")
             (stray ,(at "extensions" "curl/y.scm") "(quote foreign-procedure)")
             (stray ,(at "extensions" "curl/z.sch") "(quote foreign-procedure)")))
     (list "dir-symlink"
           "a symbolic link to a directory is named, not followed"
           known-wrappers
           `(("curl_easy_init" () ,ok foreign-procedure))
           `((directory-link ,(at "dir-symlink" "linked"))))
     (list "lock-file"
           "a .# dangling link, Emacs's lock file, is skipped; a .# regular file is read; another dangling link is named"
           known-wrappers
           `(("curl_easy_init" () ,la foreign-procedure))
           `((stray ,lb "(quote foreign-callable)")
             (unreadable ,lg ,(string-append "Exception in open-file-input-port: failed for " lg ": no such file or directory")))))))

;; seeded-tables : (Listof (List String Any (Listof Violation)))
;; A table holding one fault, and the whole answer table-problems gives.
(define seeded-tables
  (list
   (list "a citation naming no file"
         `(("x" () ".plans/decisions/9999-no-such-record.md: Calls that cannot block stay plain."))
         '((citation-not-a-record "x" ".plans/decisions/9999-no-such-record.md")))
   (list "a citation naming a file outside .plans/decisions/"
         '(("x" () "AGENTS.md: Project guidelines"))
         '((citation-not-a-record "x" "AGENTS.md")))
   (list "a citation climbing out of .plans/decisions/"
         '(("x" () ".plans/decisions/../progress.md: progress"))
         '((citation-not-a-record "x" ".plans/decisions/../progress.md")))
   (list "a phrase the record does not hold"
         `(("x" () ,(string-append plain-record ": Calls that can block stay plain.")))
         `((citation-phrase-missing "x" ,plain-record "Calls that can block stay plain.")))
   (list "a citation with no phrase"
         `(("x" () ,plain-record))
         `((citation-shape "x" ,plain-record)))
   (list "a citation with an empty phrase"
         `(("x" () ,(string-append plain-record ": ")))
         `((citation-shape "x" ,(string-append plain-record ": "))))
   (list "two rows for one key"
         `(("x" () ,good-citation) ("x" (__collect_safe) ,good-citation))
         '((duplicate-row "x")))
   (list "rows not shaped (key conventions citation)"
         `(("a" ()) (42 () ,good-citation) ("c" __collect_safe ,good-citation) ("d" () 13))
         `((row-shape ("a" ()))
           (row-shape (42 () ,good-citation))
           (row-shape ("c" __collect_safe ,good-citation))
           (row-shape ("d" () 13))))
   (list "a callable's row, keyed by a symbol, and a phrase across a line break"
         `((on-write (__collect_safe) ,good-citation)
           ("y" () ,(string-append plain-record ": It covers `curl_multi_perform` too, which curl documents as non-blocking, until E1 says otherwise.")))
         '())))

;; The six entries loading binds today (src/curl/private/native.sls).
(define loading-entries
  '("curl_version_info" "curl_global_init" "curl_easy_option_by_name"
    "curl_easy_init" "curl_easy_header" "curl_easy_cleanup"))

;; The live scan of src/, and the wrappers it read.
(define src-check
  (outcome (lambda () (check-conventions source-root known-wrappers conventions-table))))

(define src-wrappers
  (outcome (lambda () (scan-wrappers (scan-conventions source-root known-wrappers)))))

;; conventions-bound : String -> Any
;; The conventions of every binding of KEY that the scan of src/ found, in
;; order: (()) for one plain binding, () for none. A failed scan is itself.
(define (conventions-bound key)
  (guard (e (#t (list 'unreadable (describe e))))
    (if (eq? (car src-check) 'returned)
        (map cadr (filter (lambda (b) (equal? (car b) key)) (car (cadr src-check))))
        src-check)))

;; src-violations : Any
(define src-violations
  (guard (e (#t (list 'unreadable (describe e))))
    (if (eq? (car src-check) 'returned) (cadr (cadr src-check)) src-check)))

(test-begin "collect-safe")

;; --- the table ------------------------------------------------------------------

(test-equal "the table's citations each name a decision record that exists, and quote it"
  '(returned ())
  (outcome (lambda () (table-problems conventions-table "."))))

(for-each
 (lambda (seeded)
   (test-equal (string-append "table-problems, seeded: " (car seeded))
     (list 'returned (caddr seeded))
     (outcome (lambda () (table-problems (cadr seeded) ".")))))
 seeded-tables)

;; --- the reader, on a fixture tree per rule ----------------------------------------

(for-each
 (lambda (case)
   (test-equal (string-append (car case) ": " (cadr case))
     (list 'returned (list (list-ref case 3) (list-ref case 4)))
     (outcome (lambda ()
                (check-conventions (string-append fixtures "/" (car case))
                                   (caddr case) fixture-table)))))
 cases)

;; A fixture nothing runs guards nothing, and a case with no fixture runs on a
;; missing directory.
(test-equal "every fixture directory is a case above, and every case has its directory"
  (list-sort string<? (map car cases))
  (list-sort string<?
             (filter (lambda (name) (file-directory? (string-append fixtures "/" name)))
                     (directory-list fixtures))))

;; Git keeps no empty directory, and the reader is told a path that need not
;; exist.
(test-equal "an empty directory holds no source, and says so"
  'refused
  (call-with-temp-directory
   (lambda (dir)
     (let ((answer (outcome (lambda () (check-conventions dir known-wrappers conventions-table)))))
       (if (equal? answer `(returned (() ((no-sources ,dir))))) 'refused answer)))))

(test-equal "a directory that does not exist holds no source, and says so"
  'refused
  (call-with-temp-directory
   (lambda (dir)
     (let* ((missing (string-append dir "/no-such-directory"))
            (answer (outcome (lambda () (check-conventions missing known-wrappers conventions-table)))))
       (if (equal? answer `(returned (() ((no-sources ,missing))))) 'refused answer)))))

;; --- the live scan of src/ ---------------------------------------------------------

(test-equal "the scan of src/ finds the six entries loading binds, each bound once, plain"
  (map (lambda (key) (list key '(()))) loading-entries)
  (map (lambda (key) (list key (conventions-bound key))) loading-entries))

(test-equal "src/ holds to the table: no violation"
  '()
  src-violations)

(test-equal "known-wrappers is exactly the wrappers src/ defines"
  (list 'returned known-wrappers)
  src-wrappers)

(test-end "collect-safe")

(exit (suite-exit-status runner))
