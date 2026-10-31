#!r6rs
;;; The suite for the calling conventions of chez-curl's foreign procedures
;;; and callables (ADR-0013, harness plan §3 item 3). (foreign-conventions)
;;; reads every source file under src/ as data, evaluating nothing, finds
;;; each foreign-procedure and foreign-callable, and holds its conventions
;;; against conventions-table, whose rows cite the decision records. So a
;;; call that blocks bound plain, such as curl_easy_perform in M2, fails here
;;; at once, as does memcpy bound __collect_safe.
;;;
;;; It also holds every type to an allowlist (ADR-0013, amended): Chez's
;;; immediate and address types, and (* NAME) or (& NAME) for an ftype
;;; (curl private layouts) defines. Anything else, a macro's pattern
;;; variable included, is unreadable. The other types hand C a pointer into
;;; Chez's heap, where Valgrind sees nothing, and come in three kinds: a
;;; bytevector's data (u8*, u16*, u32*) needs a row marked
;;; (bytevector-crossing CITATION), which M2's checked wrapper adds first; a
;;; string Chez copied into its heap needs a row marked (string-not-kept
;;; CITATION), which the two loading bindings that take a name carry; and
;;; scheme-object is never allowed.
;;;
;;; The reader fails closed. Every occurrence of the symbols
;;; foreign-procedure and foreign-callable must be accounted for: in an
;;; (only (chezscheme) ...) import, as the head of a form whose entry is a
;;; string literal, as the one foreign-procedure form in the template of a
;;; known wrapper, or, for a callable, as the whole right-hand side of a
;;; (define name ...). So must every occurrence of a known wrapper's name:
;;; as the head of a use in code, outside every macro, or as the name its
;;; one define-syntax defines. Anything else is named, with its file and
;;; form: the review's three routes to a plain curl_easy_setopt, a quoted
;;; use, an alias and an argument, among them.
;;;
;;; A row may name the one way its entry must be bound, (bound-by BINDER).
;;; ADR-0001's four variadic rows name bind-variadic, so a binding of one
;;; made any other way is the wrong binder, its convention right or not.
;;;
;;; Every macro a tree may define is a row of a table, known-macros for
;;; src/: a binder, a known wrapper, or plain, which neither builds a
;;; binding nor takes its operands apart. Written as a procedure, a plain
;;; macro hands its input to nothing but a syntax-violation call in tail
;;; position, and its library imports no procedure that could take the
;;; input apart, or build a binding from strings: A6, A9, A10 and A12 did.
;;; A macro can take apart a form it is handed, or its own template, and
;;; bind what it rebuilds while the reader reads the form as written: A5
;;; and FPA4 did. So any other
;;; define-syntax, and every let-syntax and letrec-syntax, is named. Those
;;; three keywords stand only at the head of a form written in code, and no
;;; listed macro's template puts a pattern variable at a form's head: the
;;; review's load-step clause, handed define-syntax, defined a macro there.
;;; A case clause's datum list is data, so it names no binding Chez never
;;; makes. Each fixture tree has its own table, whose third kind, any,
;;; holds a macro the tree uses to test another rule; known-macros has
;;; none.
;;;
;;; Every rule has a fixture tree under tests/fixtures/conventions/<case>/,
;;; and each case asserts the reader's whole answer, the bindings it found
;;; and the violations, as data written by hand here. A violation list of ()
;;; is never asserted alone: the live scan of src/ must also find the six
;;; entries loading binds, and the variadic ones bound through bind-variadic,
;;; so a reader that reads nothing fails.
;;;
;;; ADR-0001's variadic entries, curl_easy_setopt, curl_easy_getinfo,
;;; curl_multi_setopt and curl_share_setopt, must carry (__varargs_after 2).
;;; x86-64 and Linux arm64 pass variadic arguments as they pass named ones,
;;; so a binding without it works there; only Apple arm64 shows it failing.
;;; This suite is what fails on every platform: make check-variadic removes
;;; the convention from bind-variadic's template, in a copy, and requires
;;; this suite to name each of its five uses as a mismatch, curl_easy_setopt
;;; three times, curl_easy_getinfo and curl_multi_setopt once each; then
;;; from each use alone, bound through bind-required, and requires it to
;;; name that one binding, a mismatch and a wrong binder. curl_share_setopt
;;; is not bound yet.
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

;; Rows for the fixture trees alone: two conventions, to compare as sets, two
;; callables, entries the crossing and type trees bind, rows marked as the
;; reviewed bytevector crossing or string-not-kept, marks that quote
;; nothing, and rows that name their binder. The real table's one callable
;; row is write-body's.
(define fixture-rows
  '(("fixture_two_conventions" (__collect_safe (__varargs_after 2)) "a fixture row")
    ("fixture_blocking" (__collect_safe) "a fixture row")
    ("fixture_polled" (__collect_safe) "a fixture row")
    (on-write (__collect_safe) "a fixture row")
    (on-plain () "a fixture row")
    ("fixture_wide" () "a fixture row")
    ("fixture_result" () "a fixture row")
    ("fixture_bytes" () "a fixture row")
    ("fixture_copy" () "a fixture row")
    (on-bytes () "a fixture row")
    (on-copy () "a fixture row")
    ("fixture_object" () "a fixture row")
    (on-object () "a fixture row")
    ("fixture_object_result" () "a fixture row")
    (on-handed () "a fixture row")
    ("fixture_object_marked" () "a fixture row" (bytevector-crossing "a fixture mark"))
    ("fixture_object_not_kept" () "a fixture row" (string-not-kept "a fixture mark"))
    ("fixture_crossing" () "a fixture row" (bytevector-crossing "a fixture mark"))
    ("fixture_crossing_uncited" () "a fixture row" (bytevector-crossing))
    ("fixture_string" () "a fixture row")
    ("fixture_strings" () "a fixture row")
    ("fixture_string_result" () "a fixture row")
    (on-name () "a fixture row")
    (on-named () "a fixture row")
    ("fixture_string_not_kept" () "a fixture row" (string-not-kept "a fixture mark"))
    (on-kept () "a fixture row" (string-not-kept "a fixture mark"))
    ("fixture_string_uncited" () "a fixture row" (string-not-kept))
    ("fixture_string_as_bytes" () "a fixture row" (bytevector-crossing "a fixture mark"))
    ("fixture_bytes_not_kept" () "a fixture row" (string-not-kept "a fixture mark"))
    ("fixture_immediate" () "a fixture row")
    (on-every () "a fixture row")
    ("fixture_layout" () "a fixture row")
    (on-pointed () "a fixture row")
    ("fixture_direct" () "a fixture row" (bound-by foreign-procedure))
    (on-direct () "a fixture row" (bound-by foreign-procedure))
    ("fixture_marked_bound" () "a fixture row" (string-not-kept "a fixture mark") (bound-by bind-required))))

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
(define unplaced-parameters
  "its parameter list is neither types nor a pattern element at a fixed place in its pattern")
(define unplaced-result
  "its result is neither a type nor a pattern variable at a fixed place in its pattern")
(define takes-apart
  "its pattern takes an operand apart: an element other than its parameter list is a list or a vector")

;; listed : Symbol String Symbol ... -> (Listof (List Symbol Symbol String))
;; Rows of a fixture tree's macro table: each NAME, of KIND, defined in FILE
;; below the tree's root. A binder a tree does not define is listed too,
;; where its name must read as a known wrapper's.
(define (listed kind file . names)
  (map (lambda (name) (list name kind file)) names))

;; cases : (Listof (List String String Macros (Listof Binding) (Listof Violation)))
;; The fixture directory, what it holds, the table of the macros it may
;; define, its binders the known wrappers, and the whole answer: the
;; bindings found, then the violations.
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
        (lg (at "lock-file" "curl/gone.sls"))
        (cu (at "crossing-unmarked" "curl/c.sls"))
        (cw (at "crossing-wrapper" "curl/w.sls"))
        (cm (at "crossing-marked" "curl/m.sls"))
        (co (at "crossing-object" "curl/o.sls"))
        (tu (at "types-unreadable" "curl/t.sls"))
        (tz (at "types-macro-argument" "curl/z.sls"))
        (tp (at "types-pattern-variable" "curl/p.sls"))
        (tl (at "types-layouts" "curl/u.sls"))
        (ta (at "types-allowed" "curl/a.sls"))
        (su (at "string-unmarked" "curl/s.sls"))
        (sm (at "string-marked" "curl/m.sls"))
        (va (at "variadic" "curl/v.sls"))
        (vu (at "variadic-unannotated" "curl/w.sls"))
        (bw (at "wrong-binder" "curl/w.sls"))
        (a1 (at "wrapper-unquoted" "curl/n.sls"))
        (a2 (at "wrapper-aliased" "curl/n.sls"))
        (a3 (at "wrapper-passed" "curl/n.sls"))
        (xg (at "wrapper-argument" "curl/g.sls"))
        (xq (at "wrapper-data" "curl/q.sls"))
        (xr (at "wrapper-data" "curl/r.sls"))
        (xt (at "wrapper-template" "curl/t.sls"))
        (xb (at "wrapper-binding" "curl/b.sls"))
        (xe (at "wrapper-import-export" "curl/e.sls"))
        (xi (at "wrapper-import-export" "curl/i.sls"))
        (ms (at "macro-swap-entry" "curl/n.sls"))
        (mr (at "macro-rebind" "curl/n.sls"))
        (mu (at "macro-unlisted" "curl/u.sls"))
        (mn (at "macro-nested" "curl/n.sls"))
        (ml (at "macro-local" "curl/l.sls"))
        (mea (at "macro-elsewhere" "curl/a.sls"))
        (meb (at "macro-elsewhere" "curl/b.sls"))
        (pb (at "plain-binds" "curl/p.sls"))
        (pt (at "plain-takes-apart" "curl/t.sls"))
        (pp (at "plain-pattern" "curl/p.sls"))
        (bt (at "binder-takes-apart" "curl/b.sls"))
        (pe (at "plain-input-elsewhere" "curl/m.sls"))
        (pib (at "plain-input-bound" "curl/b.sls"))
        (pil (at "plain-input-local" "curl/l.sls"))
        (ptr (at "plain-transformer-rest" "curl/r.sls"))
        (ptc (at "plain-transformer-case-lambda" "curl/c.sls"))
        (pis (at "plain-input-shadowed" "curl/s.sls"))
        (prg (at "plain-raise-guarded" "curl/g.sls"))
        (prs (at "plain-raise-shadowed" "curl/s.sls"))
        (pri (at "plain-raise-imported" "curl/i.sls"))
        (pbe (at "plain-built-elsewhere" "curl/m.sls"))
        (kp (at "keyword-places" "curl/k.sls"))
        (rr (at "review-route" "curl/n.sls"))
        (ph (at "pattern-head" "curl/h.sls"))
        (cd (at "case-data" "curl/c.sls")))
    (list
     (list "legal"
           "every accounted place: the import, the known wrapper's one definition and its uses in code, a let's initial value and a plain macro's operand among them, two plain macros, direct bindings in two files, two conventions as a set, a template that is no wrapper in a fixture's macro, callables, and look-alikes"
           (append (listed 'binder "curl/a.sls" 'bind-required)
                   (listed 'plain "curl/a.sls" 'step 'checked)
                   (listed 'any "curl/a.sls" 'bind-poll))
           `(("curl_easy_init" () ,a bind-required ())
             ("curl_global_init" () ,a bind-required ())
             ("curl_easy_cleanup" () ,a bind-required ())
             ("fixture_blocking" (__collect_safe) ,a foreign-procedure ())
             ("memcpy" () ,a foreign-procedure ())
             ("fixture_two_conventions" ((__varargs_after 2) __collect_safe) ,a foreign-procedure ())
             ("fixture_polled" (__collect_safe) ,a foreign-procedure ())
             (on-write (__collect_safe) ,a foreign-callable ())
             ("curl_multi_wakeup" () ,b foreign-procedure ())
             (on-plain () ,b foreign-callable ()))
           '())

     ;; --- occurrences that are not accounted for ---
     (list "quoted"
           "quoted occurrences: a symbol, a list, a quasiquote with an unquote, a syntax form, a vector literal holding a form, a box literal holding one"
           '()
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
           (listed 'any "curl/s.sls" 'alias)
           '()
           `((stray ,s "(define fp foreign-procedure)")
             (stray ,s "(f foreign-callable)")
             (stray ,s "(rest . foreign-callable)")
             (stray ,s "(identifier-syntax foreign-procedure)")))
     (list "imports"
           "only (only (chezscheme) name ...) accounts for a name: not an export, an except, (scheme), nor an only inside a prefix"
           '()
           '()
           `((stray ,i "(export foreign-procedure)")
             (stray ,i "(except (chezscheme) foreign-callable)")
             (stray ,i "(only (scheme) foreign-procedure)")
             (stray ,i "(only (chezscheme) foreign-procedure)")))
     (list "entry-not-string"
           "an entry that is no string literal outside a known wrapper: a variable, an expression, a pattern variable"
           (listed 'any "curl/e.sls" 'bind)
           '()
           `((entry-not-string ,e "(foreign-procedure entry () uptr)")
             (entry-not-string ,e "(foreign-procedure (string-append \"curl_\" \"easy_init\") () uptr)")
             (entry-not-string ,e "(foreign-procedure e () int)")))
     (list "malformed"
           "forms too short, with no type list, improper, and a callable too short"
           '()
           '()
           `((malformed ,m "(foreign-procedure \"curl_easy_init\")")
             (malformed ,m "(foreign-procedure \"curl_easy_init\" uptr uptr)")
             (malformed ,m "(foreign-procedure . \"curl_easy_init\")")
             (malformed ,m "(foreign-callable (lambda () 0))")))
     (list "callable-misplaced"
           "a callable that is not the whole right-hand side of (define name ...)"
           '()
           '()
           `((callable-not-defined ,c "(foreign-callable (lambda (a) a) (int) int)")
             (callable-not-defined ,c "(foreign-callable (lambda (b) b) (int) int)")
             (callable-not-defined ,c "(foreign-callable (lambda (c) c) (int) int)")
             (callable-not-defined ,c "(foreign-callable (lambda (d) d) (int) int)")
             (callable-not-defined ,c "(foreign-callable (lambda (e) e) (int) int)")))

     ;; --- a known wrapper's name, unaccounted ---
     ;; The review's three routes to a plain curl_easy_setopt, each with an
     ;; unused use of bind-variadic that keeps the count, then each place.
     (list "wrapper-unquoted"
           "the review's A1: bind-required under an unquote, in a quasiquote, which is data"
           (listed 'binder "curl/n.sls" 'bind-required 'bind-variadic)
           `(("curl_easy_setopt" ((__varargs_after 2)) ,a1 bind-variadic ()))
           `((stray ,a1 "(bind-required \"curl_easy_setopt\" (uptr int long) int #f)")))
     (list "wrapper-aliased"
           "the review's A2: bind-required in identifier-syntax's template, so bind-plain is another name for it"
           (append (listed 'binder "curl/n.sls" 'bind-required 'bind-variadic)
                   (listed 'any "curl/n.sls" 'bind-plain))
           `(("curl_easy_setopt" ((__varargs_after 2)) ,a2 bind-variadic ()))
           `((stray ,a2 "(identifier-syntax bind-required)")))
     (list "wrapper-passed"
           "the review's A3: bind-required an argument of a macro that puts it at a head, binding curl_easy_setopt plain and curl_easy_perform with an unmarked u8*"
           (append (listed 'binder "curl/n.sls" 'bind-required 'bind-variadic)
                   (listed 'any "curl/n.sls" 'apply-binder))
           `(("curl_easy_setopt" ((__varargs_after 2)) ,a3 bind-variadic ()))
           `((stray ,a3 "(apply-binder bind-required \"curl_easy_setopt\" (uptr int long) int #f)")
             (stray ,a3 "(apply-binder bind-required \"curl_easy_perform\" (u8*) int #f)")))
     (list "wrapper-argument"
           "a known wrapper's name as an argument: the other wrapper, under a call, and an improper tail"
           (append (listed 'binder "curl/g.sls" 'bind-required 'bind-variadic)
                   (listed 'any "curl/g.sls" 'again 'tail))
           '()
           `((stray ,xg "(again bind-variadic \"curl_easy_getinfo\" (uptr int uptr) int #f)")
             (stray ,xg "(again bind-required \"curl_easy_init\" () uptr #f)")
             (stray ,xg "(tail . bind-required)")))
     (list "wrapper-data"
           "a known wrapper's name in data: a quoted symbol, a quoted use, a use under an unquote, a vector literal, a box literal"
           (listed 'binder "curl/q.sls" 'bind-required 'bind-variadic)
           '()
           `((stray ,xq "(quote bind-required)")
             (stray ,xq "(bind-variadic \"curl_easy_setopt\" (uptr int long) int #f)")
             (stray ,xq "(bind-required \"curl_easy_init\" () uptr #f)")
             (stray ,xq "#(bind-variadic \"curl_easy_getinfo\" (uptr int uptr) int #f)")
             (stray ,xr "(bind-required \"curl_easy_init\" () uptr #f)")))
     (list "wrapper-template"
           "a known wrapper's name in a macro, a head with a literal entry too: syntax-rules templates, one handing the use to a pattern variable, a syntax-case taking its template apart, with-syntax, quasisyntax and syntax in procedures, transformers by define-syntax and let-syntax, identifier-syntax's set! clause, a literal and a pattern, and each known wrapper defined through the other, one by a transformer that is no template"
           (append (listed 'binder "curl/t.sls" 'bind-required 'bind-variadic)
                   (listed 'any "curl/t.sls" 'bind-easy 'via 'rebind 'named 'at-expand 'on-set 'literal))
           '()
           `((stray ,xt "(bind-required \"curl_easy_init\" () uptr #f)")
             (stray ,xt "(bind-variadic \"curl_easy_setopt\" (uptr int long) int #f)")
             (stray ,xt "(bind-required \"memcpy\" (uptr int long) int #f)")
             (stray ,xt "(syntax bind-required)")
             (stray ,xt "(bind-variadic \"curl_easy_getinfo\" (uptr int uptr) int #f)")
             (stray ,xt "(bind-variadic \"curl_easy_setopt\" (uptr int long) int #f)")
             (stray ,xt "(bind-required \"curl_easy_init\" () uptr #f)")
             (macro-local ,xt "(let-syntax ((m (lambda (x) (bind-required \"curl_global_init\" (long) int #f)))) 0)")
             (stray ,xt "(bind-required \"curl_global_init\" (long) int #f)")
             (stray ,xt "(bind-required \"curl_easy_init\" () uptr #f)")
             (stray ,xt "(bind-required)")
             (stray ,xt "(_ bind-required)")
             (macro-pattern-head ,xt bind-variadic "(arg ...)")
             (wrapper-unreadable ,xt bind-variadic ,no-binding)
             (stray ,xt "(bind-required entry (arg ...) result library)")
             (wrapper-unreadable ,xt bind-required ,not-syntax-rules)
             (stray ,xt "(bind-variadic \"curl_easy_init\" () uptr #f)")))
     (list "wrapper-binding"
           "a known wrapper's name bound as a variable: define, a define's formals, lambda's, a rest list, case-lambda's, let, let*, letrec, a named let, let-values, do and guard; none is read as a use"
           (listed 'binder "curl/b.sls" 'bind-required 'bind-variadic)
           '()
           `((stray ,xb "(define bind-required 0)")
             (stray ,xb "(bind-variadic . args)")
             (stray ,xb "(formal bind-required)")
             (stray ,xb "(bind-required)")
             (stray ,xb "(lambda bind-variadic 0)")
             (stray ,xb "(bind-required)")
             (stray ,xb "(x . bind-variadic)")
             (stray ,xb "(bind-required \"curl_easy_setopt\")")
             (stray ,xb "(bind-variadic x)")
             (stray ,xb "(bind-required (lambda () 0))")
             (stray ,xb "(let bind-variadic ((i 0)) i)")
             (stray ,xb "(bind-required)")
             (stray ,xb "(bind-variadic 0 1)")
             (stray ,xb "(bind-required (#t 0))")))
     (list "wrapper-import-export"
           "a known wrapper's name exported, by name and renamed, and imported by only, rename, except, prefix, for, (only (chezscheme) ...) and a body import"
           (listed 'binder "curl/e.sls" 'bind-required 'bind-variadic)
           '()
           `((stray ,xe "(export bind-required (rename (bind-variadic bind-v)))")
             (stray ,xe "(bind-variadic bind-v)")
             (stray ,xi "(only (curl e) bind-required)")
             (stray ,xi "(bind-required b)")
             (stray ,xi "(bind-v bind-variadic)")
             (stray ,xi "(except (curl e) bind-required)")
             (stray ,xi "(only (curl e) bind-required)")
             (stray ,xi "(only (curl e) bind-variadic)")
             (stray ,xi "(only (chezscheme) foreign-procedure bind-variadic import)")
             (stray ,xi "(bind-required c)")))

     ;; --- the macros a tree may define ---
     ;; A macro can take apart a form it is handed and bind what it rebuilds,
     ;; while the reader reads the form as written: A5 and FPA4, each with
     ;; an unused use of bind-variadic that keeps the count.
     (list "macro-swap-entry"
           "A5: a macro on no row takes apart a use it is handed, which the reader reads as memcpy, and rebuilds it with curl_easy_setopt"
           (listed 'binder "curl/n.sls" 'bind-required 'bind-variadic)
           `(("curl_easy_setopt" ((__varargs_after 2)) ,ms bind-variadic ())
             ("memcpy" () ,ms bind-required ()))
           `((macro-unlisted ,ms swap-entry)))
     (list "macro-rebind"
           "FPA4: a syntax-case on no row takes apart its own template, a foreign-procedure form the reader reads as memcpy, and binds curl_easy_setopt"
           (listed 'binder "curl/n.sls" 'bind-variadic)
           `(("memcpy" () ,mr foreign-procedure ())
             ("curl_easy_setopt" ((__varargs_after 2)) ,mr bind-variadic ()))
           `((macro-unlisted ,mr rebind)))
     (list "macro-unlisted"
           "a macro at a library body's top level that names no row, though it holds nothing a plain macro may not; one beside it that does"
           (listed 'plain "curl/u.sls" 'checked)
           '()
           `((macro-unlisted ,mu step)))
     (list "macro-nested"
           "define-syntax anywhere but a library body's top level: in a procedure's body, in a begin, and in a listed macro's template"
           (listed 'any "curl/n.sls" 'maker)
           '()
           `((macro-nested ,mn "(define-syntax inner (syntax-rules () ((_) 0)))")
             (macro-nested ,mn "(define-syntax in-begin (syntax-rules () ((_) 0)))")
             (stray ,mn "(define-syntax name (syntax-rules () ((_) 0)))")
             (macro-nested ,mn "(define-syntax name (syntax-rules () ((_) 0)))")))
     (list "macro-local"
           "local macros, by let-syntax and letrec-syntax"
           '()
           '()
           `((macro-local ,ml "(let-syntax ((m (syntax-rules () ((_) 0)))) (m))")
             (macro-local ,ml "(letrec-syntax ((m (syntax-rules () ((_) 0)))) (m))")))
     (list "macro-elsewhere"
           "a listed macro defined in a file other than its row's"
           (listed 'plain "curl/a.sls" 'step)
           '()
           `((macro-elsewhere ,meb step ,mea)))
     (list "plain-binds"
           "plain macros that would build a binding: a foreign-procedure form, a foreign-callable, a known wrapper's use"
           (append (listed 'binder "curl/p.sls" 'bind-required)
                   (listed 'plain "curl/p.sls" 'bind-poll 'on-callable 'via-wrapper))
           `(("curl_multi_poll" (__collect_safe) ,pb foreign-procedure ()))
           `((plain-macro-binds ,pb bind-poll foreign-procedure)
             (plain-macro-binds ,pb on-callable foreign-callable)
             (callable-not-defined ,pb "(foreign-callable (lambda (n) n) (int) int)")
             (plain-macro-binds ,pb via-wrapper bind-required)
             (stray ,pb "(bind-required \"curl_easy_init\" () uptr #f)")
             (wrong-binder "curl_multi_poll" bind-blocking foreign-procedure ,pb)))
     (list "plain-takes-apart"
           "plain macros that can take their operands apart: syntax-case, with-syntax, syntax->datum and datum->syntax, two of them handed the input too"
           (listed 'plain "curl/t.sls" 'by-case 'by-with 'by-datum)
           '()
           `((plain-macro-takes-apart ,pt by-case syntax-case)
             (plain-macro-input ,pt by-case "(syntax-case x () ((_ e) (syntax e)))")
             (plain-macro-takes-apart ,pt by-with with-syntax)
             (plain-macro-takes-apart ,pt by-datum datum->syntax)
             (plain-macro-takes-apart ,pt by-datum syntax->datum)
             (plain-macro-input ,pt by-datum "(datum->syntax x (cadr (syntax->datum x)))")
             (plain-macro-input ,pt by-datum "(syntax->datum x)")))
     (list "plain-pattern"
           "plain macros whose patterns take an operand apart: nested, improper, a vector, not headed by _, and identifier-syntax's set! clause; two with identifiers only, an ellipsis among them, pass"
           (listed 'plain "curl/p.sls" 'swap 'tail 'vec 'named 'setter 'flat 'counter)
           '()
           `((plain-macro-pattern ,pp swap "(_ (w e . rest))")
             (macro-pattern-head ,pp swap "(w \"curl_easy_setopt\" . rest)")
             (plain-macro-pattern ,pp tail "(_ a . rest)")
             (plain-macro-pattern ,pp vec "(_ #(a b))")
             (plain-macro-pattern ,pp named "(named a)")
             (plain-macro-pattern ,pp setter "(set! id (w e))")
             (macro-pattern-head ,pp setter "(w e)")))
     ;; A plain transformer's input goes only to syntax-violation, so what it
     ;; builds cannot depend on what it is handed.
     (list "plain-input-elsewhere"
           "A6: a plain transformer hands its input to a procedure another library exports, which takes it apart and rebuilds it; the reader reads memcpy"
           (listed 'plain "curl/m.sls" 'm)
           `(("memcpy" () ,pe foreign-procedure ()))
           `((plain-macro-import ,pe m)
             (plain-macro-input ,pe m "(rebuild x)")))
     (list "plain-input-bound"
           "plain transformers whose input goes elsewhere than as syntax-violation's last argument: bound to another name, by let, define and set!; the message; quoted; in quoted data"
           (listed 'plain "curl/b.sls" 'by-let 'by-define 'by-set 'by-message 'by-quote 'by-data)
           '()
           `((plain-macro-input ,pib by-let "(form x)")
             (plain-macro-input ,pib by-define "(define form x)")
             (plain-macro-input ,pib by-set "(set! form x)")
             (plain-macro-input ,pib by-message "(syntax-violation (quote by-message) x #f)")
             (plain-macro-input ,pib by-quote "(quote x)")
             (plain-macro-input ,pib by-data "(syntax-violation by-data \"refused\" x)")
             (plain-macro-raise ,pib by-data "(syntax-violation by-data \"refused\" x)")))
     (list "plain-input-local"
           "plain transformers that hand their input to a procedure of the same library: the library's own, and the transformer's"
           (listed 'plain "curl/l.sls" 'by-library 'by-body)
           '()
           `((plain-macro-input ,pil by-library "(keep x)")
             (plain-macro-input ,pil by-body "(hold x)")))
     (list "plain-transformer-rest"
           "plain transformers whose parameters are not one identifier: a rest list, an identifier and a rest, two identifiers"
           (listed 'plain "curl/r.sls" 'all-rest 'some-rest 'two)
           '()
           `((plain-macro-transformer ,ptr all-rest "(lambda args (syntax-violation (quote all-rest) \"refused\" (car args)))")
             (plain-macro-transformer ,ptr some-rest "(lambda (x . more) (syntax-violation (quote some-rest) \"refused\" x))")
             (plain-macro-transformer ,ptr two "(lambda (x y) (syntax-violation (quote two) \"refused\" x))")))
     (list "plain-transformer-case-lambda"
           "plain transformers that are procedures but no lambda of one identifier: a case-lambda, and make-variable-transformer's"
           (listed 'plain "curl/c.sls" 'by-cases 'by-variable)
           '()
           `((plain-macro-transformer ,ptc by-cases "(case-lambda ((x) (syntax-violation (quote by-cases) \"refused\" x)))")
             (plain-macro-transformer ,ptc by-variable "(make-variable-transformer (lambda (x) (syntax-violation (quote by-variable) \"refused\" x)))")))
     (list "plain-input-shadowed"
           "plain transformers that shadow their input, so syntax-violation is handed something else: by let, an inner lambda, whose call is then no tail call, an internal define"
           (listed 'plain "curl/s.sls" 'by-let 'by-lambda 'by-define)
           '()
           `((plain-macro-input ,pis by-let "(x 0)")
             (plain-macro-input ,pis by-lambda "(x)")
             (plain-macro-raise ,pis by-lambda "(syntax-violation (quote by-lambda) \"refused\" x)")
             (plain-macro-input ,pis by-define "(define x 0)")))
     ;; syntax-violation's condition holds the input: the call must be the
     ;; transformer's last act, and the name (rnrs)'s.
     (list "plain-raise-guarded"
           "A9: plain transformers whose input goes only to syntax-violation, with a handler around the call that takes it back from the condition: by guard, and by with-exception-handler"
           (listed 'plain "curl/g.sls" 'by-guard 'by-handler)
           '()
           `((plain-macro-import ,prg by-guard)
             (plain-macro-raise ,prg by-guard "(syntax-violation (quote by-guard) \"never\" x)")
             (plain-macro-import ,prg by-handler)
             (plain-macro-raise ,prg by-handler "(syntax-violation (quote by-handler) \"never\" x)")))
     (list "plain-raise-shadowed"
           "A11: plain transformers that rebind syntax-violation, by let and by an internal define"
           (listed 'plain "curl/s.sls" 'by-let 'by-define)
           '()
           `((plain-macro-raise ,prs by-let "(syntax-violation (lambda (who message form) form))")
             (plain-macro-raise ,prs by-define "(syntax-violation who message form)")))
     (list "plain-raise-imported"
           "A10: a plain transformer in a library that takes syntax-violation from another, with (rnrs)'s excepted"
           (listed 'plain "curl/i.sls" 'm)
           '()
           `((plain-macro-import ,pri m)))
     (list "plain-built-elsewhere"
           "A12: a plain transformer whose input goes nowhere, and whose output a procedure another library exports builds from strings"
           (listed 'plain "curl/m.sls" 'm)
           '()
           `((plain-macro-import ,pbe m)))

     ;; --- a keyword a use could hand in ---
     (list "review-route"
           "the review's route: load-step's flat second clause puts its first operand at a head, and is handed define-syntax, defining a macro that builds a foreign-procedure form from strings"
           (append (listed 'binder "curl/n.sls" 'bind-variadic)
                   (listed 'plain "curl/n.sls" 'load-step))
           `(("curl_easy_setopt" ((__varargs_after 2)) ,rr bind-variadic ()))
           `((macro-pattern-head ,rr load-step "(head operand ...)")
             (stray ,rr "(load-step define-syntax bind-quietly (lambda (x) (syntax-case x () ((k entry types result) (datu...")))
     (list "keyword-places"
           "define-syntax, let-syntax and letrec-syntax anywhere but the head of a form written in code: an operand, data, a template"
           (listed 'plain "curl/k.sls" 'step 'maker)
           '()
           `((stray ,kp "(step define-syntax)")
             (stray ,kp "(let-syntax ((m 0)) m)")
             (stray ,kp "(list letrec-syntax)")
             (stray ,kp "(define-syntax name (syntax-rules () ((_) 0)))")
             (macro-nested ,kp "(define-syntax name (syntax-rules () ((_) 0)))")))
     (list "pattern-head"
           "listed macros whose templates put a pattern variable at a form's head: two binders, a syntax-rules plain macro, a spliced one and identifier-syntax's; a binder's foreign-procedure parameter list is types, not a form; any is held to none"
           (append (listed 'binder "curl/h.sls" 'bind-required 'bind-listed)
                   (listed 'plain "curl/h.sls" 'apply-head 'spliced 'setter 'fine)
                   (listed 'any "curl/h.sls" 'any-head))
           '()
           `((macro-pattern-head ,ph bind-required "(library entry)")
             (macro-pattern-head ,ph bind-listed "(arg ...)")
             (macro-pattern-head ,ph apply-head "(k a)")
             (macro-pattern-head ,ph spliced "(k ...)")
             (macro-pattern-head ,ph setter "(e)")))
     (list "case-data"
           "a case clause's datum list is data, so a foreign-procedure form or a wrapper's use there is stray; a clause's body is code"
           (listed 'binder "curl/c.sls" 'bind-required)
           `(("curl_global_init" () ,cd foreign-procedure ()))
           `((stray ,cd "(foreign-procedure \"curl_easy_init\" () uptr)")
             (stray ,cd "(bind-required \"curl_easy_init\" () uptr #f)")))
     (list "binder-takes-apart"
           "a binder whose pattern takes its library operand apart, so its template could rebuild a use it is handed: unreadable, and none of its uses read"
           (listed 'binder "curl/b.sls" 'bind-required)
           '()
           `((macro-pattern-head ,bt bind-required "(w \"curl_easy_setopt\" . rest)")
             (wrapper-unreadable ,bt bind-required ,takes-apart)))

     ;; --- bindings against the table ---
     (list "mismatch"
           "a direct binding with a convention its row lacks, and a callable without the one its row requires"
           '()
           `(("curl_easy_init" (__collect_safe) ,x foreign-procedure ())
             (on-write () ,x foreign-callable ()))
           `((mismatch "curl_easy_init" () (__collect_safe) ,x)
             (mismatch on-write (__collect_safe) () ,x)))
     (list "blocking-plain"
           "ADR-0013's rows: curl_multi_remove_handle, curl_multi_poll and curl_multi_perform bound plain, the first through bind-required and the others directly, none through their rows' bind-blocking, and memcpy bound __collect_safe; memcpy's u8*, which its row marks, is no crossing violation, and its convention mismatches"
           (listed 'binder "curl/p.sls" 'bind-required)
           `(("curl_multi_remove_handle" () ,p bind-required ())
             ("curl_multi_poll" () ,p foreign-procedure ())
             ("curl_multi_perform" () ,p foreign-procedure ())
             ("memcpy" (__collect_safe) ,p foreign-procedure (u8*)))
           `((mismatch "curl_multi_remove_handle" (__collect_safe) () ,p)
             (wrong-binder "curl_multi_remove_handle" bind-blocking bind-required ,p)
             (mismatch "curl_multi_poll" (__collect_safe) () ,p)
             (wrong-binder "curl_multi_poll" bind-blocking foreign-procedure ,p)
             (mismatch "curl_multi_perform" (__collect_safe) () ,p)
             (wrong-binder "curl_multi_perform" bind-blocking foreign-procedure ,p)
             (mismatch "memcpy" () (__collect_safe) ,p)))
     (list "variadic"
           "ADR-0001's variadic rows: (__varargs_after 2) through the variadic wrapper holds; directly, with it, is the wrong binder; through the plain wrapper, with no convention, (__varargs_after 1) and __varargs alone each mismatch, and is the wrong binder"
           (listed 'binder "curl/v.sls" 'bind-required 'bind-variadic)
           `(("curl_easy_setopt" ((__varargs_after 2)) ,va bind-variadic ())
             ("curl_easy_getinfo" ((__varargs_after 2)) ,va bind-variadic ())
             ("curl_easy_setopt" () ,va bind-required ())
             ("curl_multi_setopt" ((__varargs_after 2)) ,va foreign-procedure ())
             ("curl_share_setopt" () ,va foreign-procedure ())
             ("curl_multi_setopt" ((__varargs_after 1)) ,va foreign-procedure ())
             ("curl_share_setopt" (__varargs) ,va foreign-procedure ()))
           `((mismatch "curl_easy_setopt" ((__varargs_after 2)) () ,va)
             (wrong-binder "curl_easy_setopt" bind-variadic bind-required ,va)
             (wrong-binder "curl_multi_setopt" bind-variadic foreign-procedure ,va)
             (mismatch "curl_share_setopt" ((__varargs_after 2)) () ,va)
             (wrong-binder "curl_share_setopt" bind-variadic foreign-procedure ,va)
             (mismatch "curl_multi_setopt" ((__varargs_after 2)) ((__varargs_after 1)) ,va)
             (wrong-binder "curl_multi_setopt" bind-variadic foreign-procedure ,va)
             (mismatch "curl_share_setopt" ((__varargs_after 2)) (__varargs) ,va)
             (wrong-binder "curl_share_setopt" bind-variadic foreign-procedure ,va)))
     (list "wrong-binder"
           "rows that name their binder: a variadic entry through another wrapper that carries its convention, and directly with it; an entry whose row names foreign-procedure, bound so and through a wrapper; a callable whose row names foreign-procedure; a marked row's binder, the mark clearing its string either way"
           (listed 'binder "curl/w.sls" 'bind-required 'bind-varargs)
           `(("curl_share_setopt" ((__varargs_after 2)) ,bw bind-varargs ())
             ("curl_share_setopt" ((__varargs_after 2)) ,bw foreign-procedure ())
             ("fixture_direct" () ,bw foreign-procedure ())
             ("fixture_direct" () ,bw bind-required ())
             (on-direct () ,bw foreign-callable ())
             ("fixture_marked_bound" () ,bw bind-required (string))
             ("fixture_marked_bound" () ,bw foreign-procedure (string)))
           `((wrong-binder "curl_share_setopt" bind-variadic bind-varargs ,bw)
             (wrong-binder "curl_share_setopt" bind-variadic foreign-procedure ,bw)
             (wrong-binder "fixture_direct" foreign-procedure bind-required ,bw)
             (wrong-binder on-direct foreign-procedure foreign-callable ,bw)
             (wrong-binder "fixture_marked_bound" bind-required foreign-procedure ,bw)))
     (list "variadic-unannotated"
           "make check-variadic's mutant: the variadic wrapper's template without (__varargs_after 2), so each of its uses mismatches"
           (listed 'binder "curl/w.sls" 'bind-variadic)
           `(("curl_easy_setopt" () ,vu bind-variadic ())
             ("curl_easy_setopt" () ,vu bind-variadic ())
             ("curl_easy_setopt" () ,vu bind-variadic ())
             ("curl_easy_getinfo" () ,vu bind-variadic ()))
           `((mismatch "curl_easy_setopt" ((__varargs_after 2)) () ,vu)
             (mismatch "curl_easy_setopt" ((__varargs_after 2)) () ,vu)
             (mismatch "curl_easy_setopt" ((__varargs_after 2)) () ,vu)
             (mismatch "curl_easy_getinfo" ((__varargs_after 2)) () ,vu)))
     (list "no-row"
           "bindings with no row: an entry, a callable, and a callable named memcpy, a symbol"
           '()
           `(("curl_easy_reset" () ,n foreign-procedure ())
             (on-unlisted () ,n foreign-callable ())
             (memcpy () ,n foreign-callable ()))
           `((no-row "curl_easy_reset" ,n)
             (no-row on-unlisted ,n)
             (no-row memcpy ,n)))

     ;; --- the bytevector crossing ---
     (list "crossing-unmarked"
           "bindings that hand C a bytevector's data, none marked: u8*, u16* and u32* parameters, and a callable's u8* result; a procedure's u8* result and a callable's u8* parameter hand C none"
           '()
           `(("fixture_copy" () ,cu foreign-procedure (u8*))
             ("fixture_wide" () ,cu foreign-procedure (u16* u32*))
             ("fixture_result" () ,cu foreign-procedure ())
             (on-bytes () ,cu foreign-callable (u8*))
             (on-copy () ,cu foreign-callable ()))
           `((bytevector-crossing "fixture_copy" (u8*) ,cu)
             (bytevector-crossing "fixture_wide" (u16* u32*) ,cu)
             (bytevector-crossing on-bytes (u8*) ,cu)))
     (list "crossing-object"
           "scheme-object, never allowed: a procedure's parameter and result, a callable's result and parameter, and a parameter under each kind of mark"
           '()
           `(("fixture_object" () ,co foreign-procedure (scheme-object))
             (on-object () ,co foreign-callable (scheme-object))
             ("fixture_object_result" () ,co foreign-procedure (scheme-object))
             (on-handed () ,co foreign-callable (scheme-object))
             ("fixture_object_marked" () ,co foreign-procedure (scheme-object))
             ("fixture_object_not_kept" () ,co foreign-procedure (scheme-object)))
           `((scheme-object "fixture_object" (scheme-object) ,co)
             (scheme-object on-object (scheme-object) ,co)
             (scheme-object "fixture_object_result" (scheme-object) ,co)
             (scheme-object on-handed (scheme-object) ,co)
             (scheme-object "fixture_object_marked" (scheme-object) ,co)
             (scheme-object "fixture_object_not_kept" (scheme-object) ,co)))
     (list "crossing-wrapper"
           "crossings through known wrappers: a use's parameter list, a template's own, and a use's result; a use's u8* result hands C none, and its scheme-object result is never allowed"
           (listed 'binder "curl/w.sls" 'bind-required 'bind-bytes)
           `(("fixture_copy" () ,cw bind-required (u8*))
             ("fixture_result" () ,cw bind-required ())
             ("fixture_bytes" () ,cw bind-bytes (u8*))
             ("fixture_object_result" () ,cw bind-required (scheme-object)))
           `((bytevector-crossing "fixture_copy" (u8*) ,cw)
             (bytevector-crossing "fixture_bytes" (u8*) ,cw)
             (scheme-object "fixture_object_result" (scheme-object) ,cw)))
     (list "crossing-marked"
           "a row marked as the reviewed crossing clears its bindings, direct and wrapped; a mark that quotes nothing clears none"
           (listed 'binder "curl/m.sls" 'bind-required)
           `(("fixture_crossing" () ,cm foreign-procedure (u8*))
             ("fixture_crossing" () ,cm bind-required (u8*))
             ("fixture_crossing_uncited" () ,cm foreign-procedure (u8*)))
           `((bytevector-crossing "fixture_crossing_uncited" (u8*) ,cm)))
     (list "types-unreadable"
           "types the reader cannot read: a string, a list that is no (* name), a callable's result, a wrapper use's parameter list that is a variable, improper, or missing; and types on no allowlist: a name that is no Chez type, void as a parameter, ptr, utf-16, a procedure's result, a callable's parameter, a wrapper use's result"
           (listed 'binder "curl/t.sls" 'bind-required)
           '()
           `((types-unreadable ,tu "(foreign-procedure \"fixture_wide\" (uptr \"u8*\") int)")
             (types-unreadable ,tu "(foreign-procedure \"fixture_wide\" ((u8*)) int)")
             (types-unreadable ,tu "(define on-bytes (foreign-callable (lambda () 0) () (u8*)))")
             (wrapper-types-unreadable ,tu bind-required "(bind-required \"memcpy\" args uptr #f)")
             (wrapper-types-unreadable ,tu bind-required "(bind-required \"memcpy\" (uptr . u8*) uptr #f)")
             (wrapper-types-unreadable ,tu bind-required "(bind-required \"memcpy\")")
             (types-unreadable ,tu "(foreign-procedure \"fixture_wide\" (uint32_t) int)")
             (types-unreadable ,tu "(foreign-procedure \"fixture_wide\" (void) int)")
             (types-unreadable ,tu "(foreign-procedure \"fixture_wide\" (ptr) int)")
             (types-unreadable ,tu "(foreign-procedure \"fixture_wide\" (utf-16) int)")
             (types-unreadable ,tu "(foreign-procedure \"fixture_result\" (uptr) uint32_t)")
             (types-unreadable ,tu "(define on-unknown (foreign-callable (lambda (n) 0) (uint32_t) int))")
             (wrapper-types-unreadable ,tu bind-required "(bind-required \"fixture_result\" (uptr) ptr #f)")))
     (list "types-macro-argument"
           "the third review's tree: a type that is a pattern variable, in a macro that is no known wrapper, whose use supplies u8*"
           (listed 'any "curl/z.sls" 'bind-memcpy)
           '()
           `((types-unreadable ,tz "(foreign-procedure \"memcpy\" (buffer uptr size_t) uptr)")))
     (list "types-pattern-variable"
           "pattern variables spelt as types or a convention, in macros that are no known wrapper: syntax-rules, with-syntax, identifier-syntax, a callable's result, and a convention; a wrapper's use in a syntax-case template is stray; a macro whose pattern binds no type stays readable"
           (append (listed 'binder "curl/p.sls" 'bind-required)
                   (listed 'any "curl/p.sls" 'bind-memcpy 'bind-through 'bind-with 'bind-on-set
                           'bind-callable 'bind-perform 'bind-poll))
           `(("curl_multi_poll" (__collect_safe) ,tp foreign-procedure ()))
           `((types-unreadable ,tp "(foreign-procedure \"memcpy\" (uptr uptr size_t) uptr)")
             (stray ,tp "(bind-required \"memcpy\" (size_t) uptr #f)")
             (types-unreadable ,tp "(foreign-procedure \"memcpy\" (uptr uptr size_t) int)")
             (types-unreadable ,tp "(foreign-procedure \"memcpy\" (uptr) int)")
             (types-unreadable ,tp "(define name (foreign-callable (lambda () 0) () int))")
             (conventions-from-pattern ,tp "(foreign-procedure __collect_safe \"curl_easy_perform\" (uptr) int)")
             (wrong-binder "curl_multi_poll" bind-blocking foreign-procedure ,tp)))
     (list "types-layouts"
           "(* NAME) and (& NAME), read when NAME is an ftype the tree's (curl private layouts) defines, as parameters, a result and a callable's; an ftype defined elsewhere, a variable of layouts, and none, unreadable"
           '()
           `(("fixture_layout" () ,tl foreign-procedure ())
             ("fixture_layout" () ,tl foreign-procedure ())
             (on-pointed () ,tl foreign-callable ()))
           `((types-unreadable ,tl "(foreign-procedure \"fixture_layout\" ((* other-struct)) int)")
             (types-unreadable ,tl "(foreign-procedure \"fixture_layout\" ((* not-an-ftype)) int)")
             (types-unreadable ,tl "(foreign-procedure \"fixture_layout\" (uptr) (& no-such-struct))")))
     (list "types-allowed"
           "every immediate and address type Chez 10.4.0 documents, written out from CSUG, as parameters of a procedure and of a callable, with void their result: each read, none a crossing"
           '()
           `(("fixture_immediate" () ,ta foreign-procedure ())
             (on-every () ,ta foreign-callable ()))
           '())

     ;; --- the string crossing ---
     (list "string-unmarked"
           "bindings that hand C a string from Chez's heap, none marked: a string parameter, one of each other string type, one through the known wrapper, and a callable's utf-8 result; a procedure's utf-8 result and a callable's string parameter hand C none"
           (listed 'binder "curl/s.sls" 'bind-required)
           `(("fixture_string" () ,su foreign-procedure (string))
             ("fixture_strings" () ,su foreign-procedure (utf-8 utf-16le utf-16be utf-32le utf-32be wstring))
             ("fixture_string" () ,su bind-required (string))
             ("fixture_string_result" () ,su foreign-procedure ())
             (on-name () ,su foreign-callable (utf-8))
             (on-named () ,su foreign-callable ()))
           `((string-crossing "fixture_string" (string) ,su)
             (string-crossing "fixture_strings" (utf-8 utf-16le utf-16be utf-32le utf-32be wstring) ,su)
             (string-crossing "fixture_string" (string) ,su)
             (string-crossing on-name (utf-8) ,su)))
     (list "string-marked"
           "a row marked string-not-kept clears its strings, direct, wrapped and a callable's result; a mark that quotes nothing clears none, and each mark clears its own kind alone"
           (listed 'binder "curl/m.sls" 'bind-required)
           `(("fixture_string_not_kept" () ,sm foreign-procedure (string))
             ("fixture_string_not_kept" () ,sm bind-required (string))
             (on-kept () ,sm foreign-callable (utf-8))
             ("fixture_string_uncited" () ,sm foreign-procedure (string))
             ("fixture_string_as_bytes" () ,sm foreign-procedure (string))
             ("fixture_bytes_not_kept" () ,sm foreign-procedure (u8*)))
           `((string-crossing "fixture_string_uncited" (string) ,sm)
             (string-crossing "fixture_string_as_bytes" (string) ,sm)
             (bytevector-crossing "fixture_bytes_not_kept" (u8*) ,sm)))

     ;; --- the known wrapper ---
     (list "wrapper-safe"
           "__collect_safe in the known wrapper's template: every use gets it"
           (listed 'binder "curl/w.sls" 'bind-required)
           `(("curl_easy_init" (__collect_safe) ,ws bind-required ())
             ("curl_multi_poll" (__collect_safe) ,ws bind-required ()))
           `((mismatch "curl_easy_init" () (__collect_safe) ,ws)
             (wrong-binder "curl_multi_poll" bind-blocking bind-required ,ws)))
     (list "wrapper-pattern-conventions"
           "the known wrapper's conventions come from a pattern variable"
           (listed 'binder "curl/w.sls" 'bind-required)
           '()
           `((wrapper-conventions-from-pattern ,wp bind-required (conv))))
     (list "wrapper-unreadable"
           "known wrappers the reader cannot read: syntax-case, two clauses, no binding, two, a nested entry, an ellipsis first, a string entry, a short form, an entry that is a literal, parameters mixed, literal but no types, a nested result, and a result that holds a variable"
           (listed 'binder "curl/w.sls"
                   'w-syntax-case 'w-two-clauses 'w-no-binding 'w-two-bindings 'w-nested-entry
                   'w-ellipsis-first 'w-entry-literal 'w-malformed 'w-literal-entry
                   'w-mixed-parameters 'w-literal-parameters 'w-nested-result 'w-pointer-result)
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
             (wrapper-unreadable ,wu w-literal-entry ,unplaced-entry)
             (wrapper-unreadable ,wu w-mixed-parameters ,unplaced-parameters)
             (wrapper-unreadable ,wu w-literal-parameters ,unplaced-parameters)
             (wrapper-unreadable ,wu w-nested-result ,unplaced-result)
             (wrapper-unreadable ,wu w-pointer-result ,unplaced-result)))
     (list "wrapper-entry-not-string"
           "uses of the known wrapper whose entry is no string literal: a variable, an expression, none at all"
           (listed 'binder "curl/u.sls" 'bind-required)
           '()
           `((wrapper-entry-not-string ,we bind-required "(bind-required name () uptr #f)")
             (wrapper-entry-not-string ,we bind-required "(bind-required (string-append \"curl_\" \"easy_init\") () uptr #f)")
             (wrapper-entry-not-string ,we bind-required "(bind-required)")))
     (list "wrapper-undefined"
           "a use of the known wrapper that no file defines"
           (listed 'binder "curl/u.sls" 'bind-required)
           '()
           `((wrapper-undefined ,wn bind-required "(bind-required \"curl_easy_init\" () uptr #f)")))
     (list "wrapper-defined-again"
           "the known wrapper defined in two files: the second stands where its row does not say, and no use is read against either"
           (listed 'binder "curl/a.sls" 'bind-required)
           '()
           `((macro-elsewhere ,wb bind-required ,wa)
             (wrapper-defined-again ,wb bind-required)))

     ;; --- reading the tree ---
     (list "shared-structure"
           "a form labelled and referred to again: the datum holding it is named, and not read, binding included"
           '()
           '()
           `((shared-structure ,g "(foreign-procedure \"curl_easy_init\" () uptr)")))
     ;; After shared-structure: a reader that walked this datum would never
     ;; return, and the case above names that fault before this one hangs.
     (list "cyclic"
           "a cyclic datum is named, and the walk ends"
           '()
           '()
           `((shared-structure ,(at "cyclic" "curl/h.sls") "#0=(foreign-procedure . #0#)")))
     (list "unreadable"
           "a file that cannot be read as data, and one with an #!eof literal hiding a binding"
           '()
           '()
           `((unreadable ,ub ,(string-append "Exception in read: unexpected end-of-file reading list before file-position 48 of #<input port " ub ">; the character position might differ"))
             (unreadable ,ue "Exception in read: an #!eof literal ends the reading before the end of the file")))
     (list "extensions"
           "every source ending Chez loads a library from is read: .chezscheme.sls .ss .scm .sch; a .txt is not"
           '()
           '()
           `((stray ,(at "extensions" "curl/w.chezscheme.sls") "(quote foreign-procedure)")
             (stray ,(at "extensions" "curl/x.ss") "(quote foreign-procedure)")
             (stray ,(at "extensions" "curl/y.scm") "(quote foreign-procedure)")
             (stray ,(at "extensions" "curl/z.sch") "(quote foreign-procedure)")))
     (list "dir-symlink"
           "a symbolic link to a directory is named, not followed"
           '()
           `(("curl_easy_init" () ,ok foreign-procedure ()))
           `((directory-link ,(at "dir-symlink" "linked"))))
     (list "lock-file"
           "a .# dangling link, Emacs's lock file, is skipped; a .# regular file is read; another dangling link is named"
           '()
           `(("curl_easy_init" () ,la foreign-procedure ()))
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
   (list "a row with a fifth element"
         `(("x" () ,good-citation (bytevector-crossing ,good-citation) #f))
         `((row-shape ("x" () ,good-citation (bytevector-crossing ,good-citation) #f))))
   (list "a row marked as the bytevector crossing, its mark quoting a record"
         `(("x" () ,good-citation (bytevector-crossing ,good-citation)))
         '())
   (list "a crossing mark that quotes nothing"
         `(("x" () ,good-citation (bytevector-crossing)))
         '((crossing-mark-shape "x" (bytevector-crossing))))
   (list "a fourth element that is no crossing mark"
         `(("x" () ,good-citation 42) ("y" () ,good-citation (crossing ,good-citation)))
         `((crossing-mark-shape "x" 42) (crossing-mark-shape "y" (crossing ,good-citation))))
   (list "a crossing mark citing no record"
         `(("x" () ,good-citation (bytevector-crossing ".plans/decisions/9999-no-such-record.md: Calls that cannot block stay plain.")))
         '((crossing-citation-not-a-record "x" ".plans/decisions/9999-no-such-record.md")))
   (list "a crossing mark quoting a phrase the record does not hold"
         `(("x" () ,good-citation (bytevector-crossing ,(string-append plain-record ": Bytevectors cross anywhere."))))
         `((crossing-citation-phrase-missing "x" ,plain-record "Bytevectors cross anywhere.")))
   (list "a crossing mark whose citation has no phrase"
         `(("x" () ,good-citation (bytevector-crossing ,plain-record)))
         `((crossing-citation-shape "x" ,plain-record)))
   (list "a crossing marked on a __collect_safe row: ADR-0013's decision 4"
         `(("x" (__collect_safe) ,good-citation (bytevector-crossing ,good-citation)))
         '((crossing-collect-safe "x")))
   (list "a row marked string-not-kept, its mark quoting a record"
         `(("x" () ,good-citation (string-not-kept ,good-citation)))
         '())
   (list "a string-not-kept mark that quotes nothing"
         `(("x" () ,good-citation (string-not-kept)))
         '((crossing-mark-shape "x" (string-not-kept))))
   (list "a string-not-kept mark quoting a phrase the record does not hold"
         `(("x" () ,good-citation (string-not-kept ,(string-append plain-record ": Strings are never kept."))))
         `((crossing-citation-phrase-missing "x" ,plain-record "Strings are never kept.")))
   (list "a string-not-kept mark on a __collect_safe row: ADR-0013's decision 4"
         `(("x" (__collect_safe) ,good-citation (string-not-kept ,good-citation)))
         '((crossing-collect-safe "x")))
   (list "a callable's row, keyed by a symbol, and a phrase across a line break"
         `((on-write (__collect_safe) ,good-citation)
           ("y" () ,(string-append plain-record ": It covers `curl_multi_perform` too, which curl documents as non-blocking, until E1 says otherwise.")))
         '())
   (list "a row naming its binder, and one marked that names its binder"
         `(("x" () ,good-citation (bound-by bind-variadic))
           ("y" () ,good-citation (string-not-kept ,good-citation) (bound-by foreign-procedure)))
         '())
   (list "binders that name no one symbol: a string, two, none, and a number"
         `(("w" () ,good-citation (bound-by "bind-variadic"))
           ("x" () ,good-citation (bound-by bind-variadic bind-required))
           ("y" () ,good-citation (bound-by))
           ("z" () ,good-citation (string-not-kept ,good-citation) (bound-by 7)))
         '((binder-shape "w" (bound-by "bind-variadic"))
           (binder-shape "x" (bound-by bind-variadic bind-required))
           (binder-shape "y" (bound-by))
           (binder-shape "z" (bound-by 7))))
   (list "a binder before a mark: the binder is a row's last element"
         `(("x" () ,good-citation (bound-by bind-variadic) (string-not-kept ,good-citation)))
         `((row-shape ("x" () ,good-citation (bound-by bind-variadic) (string-not-kept ,good-citation)))))
   (list "a binder on a row whose mark quotes nothing: the mark is named, the binder read"
         `(("x" () ,good-citation (string-not-kept) (bound-by bind-variadic)))
         '((crossing-mark-shape "x" (string-not-kept))))))

;; The six entries loading binds today (src/curl/private/native.sls).
(define loading-entries
  '("curl_version_info" "curl_global_init" "curl_easy_option_by_name"
    "curl_easy_init" "curl_easy_header" "curl_easy_cleanup"))

;; The live scan of src/, and the wrappers it read.
(define src-check
  (outcome (lambda () (check-conventions source-root known-macros conventions-table))))

(define src-wrappers
  (outcome (lambda () (scan-wrappers (scan-conventions source-root known-macros)))))

(define src-macros
  (outcome (lambda () (scan-macros (scan-conventions source-root known-macros)))))

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
     (let ((answer (outcome (lambda () (check-conventions dir known-macros conventions-table)))))
       (if (equal? answer `(returned (() ((no-sources ,dir))))) 'refused answer)))))

(test-equal "a directory that does not exist holds no source, and says so"
  'refused
  (call-with-temp-directory
   (lambda (dir)
     (let* ((missing (string-append dir "/no-such-directory"))
            (answer (outcome (lambda () (check-conventions missing known-macros conventions-table)))))
       (if (equal? answer `(returned (() ((no-sources ,missing))))) 'refused answer)))))

;; --- the live scan of src/ ---------------------------------------------------------

(test-equal "the scan of src/ finds the six entries loading binds, each bound once, plain"
  (map (lambda (key) (list key '(()))) loading-entries)
  (map (lambda (key) (list key (conventions-bound key))) loading-entries))

;; bound-via : String -> Any
;; The conventions and the binder of every binding of KEY that the scan of
;; src/ found, in order. A failed scan is itself.
(define (bound-via key)
  (guard (e (#t (list 'unreadable (describe e))))
    (if (eq? (car src-check) 'returned)
        (map (lambda (b) (list (cadr b) (list-ref b 3)))
             (filter (lambda (b) (equal? (car b) key)) (car (cadr src-check))))
        src-check)))

;; ADR-0001, decision 1: once per value type, each through bind-variadic,
;; whose template carries the convention; curl_multi_setopt for a long
;; alone (ADR-0001, amended 2026-10-25). make check-variadic removes it
;; there, and requires this suite to fail.
(test-equal "the scan of src/ finds curl_easy_setopt bound three times, once per value type, curl_easy_getinfo once, and curl_multi_setopt once, for a long, each through bind-variadic with (__varargs_after 2)"
  '(("curl_easy_setopt" ((((__varargs_after 2)) bind-variadic)
                         (((__varargs_after 2)) bind-variadic)
                         (((__varargs_after 2)) bind-variadic)))
    ("curl_easy_getinfo" ((((__varargs_after 2)) bind-variadic)))
    ("curl_multi_setopt" ((((__varargs_after 2)) bind-variadic))))
  (map (lambda (key) (list key (bound-via key)))
       '("curl_easy_setopt" "curl_easy_getinfo" "curl_multi_setopt")))

(test-equal "src/ holds to the table: no violation"
  '()
  src-violations)

;; ADR-0001's sentence on the checked copies, written out here, not read
;; from the table.
(define one-wrapper-citation
  ".plans/decisions/0001-bind-libcurl-directly.md: One checked wrapper owns every copy between a bytevector and foreign memory.")

;; scan-signatures: each binding's types, as tests/test-constants.sps reads
;; them for its prototype check. The legal tree binds through a known
;; wrapper, directly, and as callables, so each way of reading types is
;; here, and a reader that dropped or mixed them fails by name.
(test-equal "scan-signatures: the legal tree's bindings, each with how it was bound, its parameter and result types as written, and its file, in scan order"
  (let ((a (at "legal" "curl/a.sls")) (b (at "legal" "curl/b.sls")))
    `(returned
      (("curl_easy_init" bind-required () uptr ,a)
       ("curl_global_init" bind-required (long) int ,a)
       ("curl_easy_cleanup" bind-required (uptr) void ,a)
       ("fixture_blocking" foreign-procedure (uptr) int ,a)
       ("memcpy" foreign-procedure (uptr uptr size_t) uptr ,a)
       ("fixture_two_conventions" foreign-procedure (uptr int long) int ,a)
       ("fixture_polled" foreign-procedure (uptr uptr unsigned int uptr) int ,a)
       (on-write foreign-callable (uptr size_t size_t uptr) size_t ,a)
       ("curl_multi_wakeup" foreign-procedure (uptr) int ,b)
       (on-plain foreign-callable (int) int ,b))))
  (outcome (lambda ()
             (scan-signatures
              (scan-conventions (string-append fixtures "/legal")
                                (append (listed 'binder "curl/a.sls" 'bind-required)
                                        (listed 'plain "curl/a.sls" 'step 'checked)
                                        (listed 'any "curl/a.sls" 'bind-poll)))))))

;; A known wrapper's template may write its own types, or take the use's,
;; for its parameters and for its result: each place read where it is.
(test-equal "scan-signatures: through known wrappers, a use's parameter list and result, and a template's own parameter list, each read from where it is written"
  (let ((w (at "crossing-wrapper" "curl/w.sls")))
    `(returned
      (("fixture_copy" bind-required (u8* uptr size_t) uptr ,w)
       ("fixture_result" bind-required (uptr) u8* ,w)
       ("fixture_bytes" bind-bytes (u8* uptr size_t) uptr ,w)
       ("fixture_object_result" bind-required (uptr) scheme-object ,w))))
  (outcome (lambda ()
             (scan-signatures
              (scan-conventions (string-append fixtures "/crossing-wrapper")
                                (listed 'binder "curl/w.sls" 'bind-required 'bind-bytes))))))

;; readable-types: the universe tests/test-constants.sps holds its map
;; against. Written out, so the reader's allowlist and this list move
;; together or fail.
(test-equal "readable-types: CSUG's 33 immediate types, void, the three bytevector types, the seven string types, scheme-object, and (* F) and (& F) for each ftype given"
  (list 'returned
        '(integer-8 unsigned-8 integer-16 unsigned-16 integer-32 unsigned-32
          integer-64 unsigned-64 double-float single-float double float
          short unsigned-short int unsigned unsigned-int long unsigned-long
          long-long unsigned-long-long ptrdiff_t size_t ssize_t iptr uptr void*
          fixnum boolean stdbool char wchar_t wchar
          void u8* u16* u32* string utf-8 utf-16le utf-16be utf-32le utf-32be wstring
          scheme-object (* f) (* g) (& f) (& g)))
  (outcome (lambda () (readable-types '(f g)))))

;; The rows this slice adds, written out here, not read from the table: a
;; row loosened along with its binding, curl_url_set made __collect_safe or
;; memcpy's mark removed, would otherwise pass.
(define cannot-block-citation
  ".plans/decisions/0013-collect-safe-blocking-calls.md: Calls that cannot block stay plain.")

(test-equal "the table's rows for strlen and the URL API are each plain, citing ADR-0013's cannot-block sentence, with no mark and no binder; memcpy's is plain, cites ADR-0001's decision 5, and is marked as the one checked wrapper's crossing"
  (append
   (map (lambda (key) (list key '() cannot-block-citation))
        '("strlen" "curl_url" "curl_url_cleanup" "curl_url_set" "curl_url_get"
          "curl_url_strerror" "curl_free"))
   (list (list "memcpy" '()
               ".plans/decisions/0001-bind-libcurl-directly.md: Bulk byte moves use libc's `memcpy`, bound directly, as a plain call."
               (list 'bytevector-crossing one-wrapper-citation))))
  (guard (e (#t (list 'unreadable (describe e))))
    (map (lambda (key) (find (lambda (row) (equal? (car row) key)) conventions-table))
         '("strlen" "curl_url" "curl_url_cleanup" "curl_url_set" "curl_url_get"
           "curl_url_strerror" "curl_free" "memcpy"))))

;; ADR-0001's decision 1, written out here, not read from the table: a row
;; loosened along with the binding it holds would otherwise pass.
(define variadic-citation
  ".plans/decisions/0001-bind-libcurl-directly.md: Variadic entry points are bound once per value type, with `(__varargs_after 2)`.")

(define variadic-entries
  '("curl_easy_setopt" "curl_easy_getinfo" "curl_multi_setopt" "curl_share_setopt"))

;; tagged? : Symbol -> Any -> Boolean
;; X is a list headed by TAG: a row's mark, or its binder.
(define (tagged? tag)
  (lambda (x) (and (pair? x) (eq? (car x) tag))))

;; Each binding of these four must also be made through bind-variadic,
;; whose template carries the convention: a direct binding with it is the
;; wrong binder, and make check-variadic's mutation reaches only the
;; template.
(test-equal "the table requires exactly (__varargs_after 2) of the four variadic entries ADR-0001 names, citing its decision 1, each bound through bind-variadic, and of no other entry, nor names bind-variadic for any other"
  (map (lambda (key) (list key '((__varargs_after 2)) variadic-citation '(bound-by bind-variadic)))
       variadic-entries)
  (guard (e (#t (list 'unreadable (describe e))))
    (filter (lambda (row)
              (or (member (car row) variadic-entries)
                  (exists (tagged? '__varargs_after) (cadr row))
                  (memq '__varargs (cadr row))
                  (member '(bound-by bind-variadic) (cdddr row))))
            conventions-table)))

;; ADR-0013's decision 1, and spike E1's finding, written out here, not
;; read from the table: a row loosened along with its binding, a call that
;; can block made plain or its binder dropped, would otherwise pass.
(define can-block-citation
  ".plans/decisions/0013-collect-safe-blocking-calls.md: `curl_multi_poll` is the engine's wait, so it is `__collect_safe`.")
(define e1-can-block-citation
  ".plans/decisions/0013-collect-safe-blocking-calls.md: `curl_multi_perform`, `curl_multi_remove_handle` and `curl_multi_cleanup` can block, so each is `__collect_safe`.")
(define e1-plain-citation
  ".plans/decisions/0013-collect-safe-blocking-calls.md: These stay plain: `curl_multi_init`, `curl_multi_add_handle`, `curl_multi_wakeup`, `curl_multi_info_read`, and `curl_easy_cleanup` of a handle removed from a multi handle the caller made.")
;; curl_easy_pause, the engine's resume (the M6 plan, section 3.4): its
;; replay runs the callables inside it, as a perform does, and a replay of
;; a gzip body ran 21.647 ms, holding another thread's collection when the
;; call was plain (the plan's section 4.1, as measured).
(define pause-citation
  ".plans/decisions/0012-engine-thread-owns-every-handle.md: so the callbacks run on the engine's thread, inside that call, as inside a perform.")

;; The calls that can block (M3 plan, section 3.2), each bound through
;; bind-blocking.
(define blocking-entries
  '("curl_multi_poll" "curl_multi_perform" "curl_multi_remove_handle" "curl_multi_cleanup"))

(test-equal "the table's rows that name a binder are the four variadic ones, through bind-variadic, the four multi calls that can block, __collect_safe, each citing what showed it can block, and curl_easy_pause, __collect_safe, citing its replay of the callables, each through bind-blocking"
  (append (map (lambda (key) (list key '(bound-by bind-variadic))) variadic-entries)
          (list (list "curl_multi_poll" '(__collect_safe) can-block-citation '(bound-by bind-blocking))
                (list "curl_multi_perform" '(__collect_safe) e1-can-block-citation '(bound-by bind-blocking))
                (list "curl_multi_remove_handle" '(__collect_safe) e1-can-block-citation '(bound-by bind-blocking))
                (list "curl_multi_cleanup" '(__collect_safe) e1-can-block-citation '(bound-by bind-blocking))
                (list "curl_easy_pause" '(__collect_safe) pause-citation '(bound-by bind-blocking))))
  (guard (e (#t (list 'unreadable (describe e))))
    (append
     (map (lambda (row) (list (car row) (list-ref row (- (length row) 1))))
          (filter (lambda (row) (and (member (car row) variadic-entries)
                                     (exists (tagged? 'bound-by) (cdddr row))))
                  conventions-table))
     (filter (lambda (row) (and (not (member (car row) variadic-entries))
                                (exists (tagged? 'bound-by) (cdddr row))))
             conventions-table))))

(test-equal "the scan of src/ finds each of the four multi calls that can block, and curl_easy_pause, bound once, through bind-blocking, with __collect_safe, and curl_easy_perform bound nowhere"
  (append (map (lambda (key) (list key '(((__collect_safe) bind-blocking))))
               (append blocking-entries '("curl_easy_pause")))
          (list (list "curl_easy_perform" '())))
  (map (lambda (key) (list key (bound-via key)))
       (append blocking-entries '("curl_easy_pause" "curl_easy_perform"))))

;; ADR-0013's decision 2, as spike E1 held it, written out here.
(define callback-citation
  ".plans/decisions/0013-collect-safe-blocking-calls.md: So the engine's write callable is `__collect_safe`, as its perform is.")

(define header-callable-citation
  ".plans/decisions/0030-streams-are-request-keys-and-token-operations.md: beside `write-body`, and the seek and prerequest callables ADR-0032 adds, each `__collect_safe` and locked, in `(curl private transfer)` alone (ADR-0013).")

(test-equal "the table's five callable rows are write-body's, citing ADR-0013's decision 2 as spike E1 held it, and read-head's, the header callable, read-body's, the read callable, seek-body's and prereq-body's, each citing ADR-0030's callables, each __collect_safe, with no mark and no binder"
  `((write-body (__collect_safe) ,callback-citation)
    (read-head (__collect_safe) ,header-callable-citation)
    (read-body (__collect_safe) ,header-callable-citation)
    (seek-body (__collect_safe) ,header-callable-citation)
    (prereq-body (__collect_safe) ,header-callable-citation))
  (guard (e (#t (list 'unreadable (describe e))))
    (filter (lambda (row) (symbol? (car row))) conventions-table)))

(test-equal "the scan of src/ finds write-body, read-head, read-body, seek-body and prereq-body each defined once, a foreign-callable with __collect_safe, in (curl private transfer)"
  '((write-body ((__collect_safe) foreign-callable "src/curl/private/transfer.sls"))
    (read-head ((__collect_safe) foreign-callable "src/curl/private/transfer.sls"))
    (read-body ((__collect_safe) foreign-callable "src/curl/private/transfer.sls"))
    (seek-body ((__collect_safe) foreign-callable "src/curl/private/transfer.sls"))
    (prereq-body ((__collect_safe) foreign-callable "src/curl/private/transfer.sls")))
  (guard (e (#t (list 'unreadable (describe e))))
    (if (eq? (car src-check) 'returned)
        (map (lambda (name)
               (cons name
                     (map (lambda (b) (list (cadr b) (list-ref b 3) (caddr b)))
                          (filter (lambda (b) (eq? (car b) name)) (car (cadr src-check))))))
             '(write-body read-head read-body seek-body prereq-body))
        src-check)))

(test-equal "the table's rows for slice 2's other entries, curl_easy_strerror, curl_easy_nextheader, curl_slist_append and curl_slist_free_all, are each plain, citing ADR-0013's cannot-block sentence, with no mark and no binder"
  (map (lambda (key) (list key '() cannot-block-citation))
       '("curl_easy_strerror" "curl_easy_nextheader" "curl_slist_append" "curl_slist_free_all"))
  (guard (e (#t (list 'unreadable (describe e))))
    (map (lambda (key) (find (lambda (row) (equal? (car row) key)) conventions-table))
         '("curl_easy_strerror" "curl_easy_nextheader" "curl_slist_append" "curl_slist_free_all"))))

(test-equal "the scan of src/ finds slice 2's plain entries each bound once, through bind-required, with no convention"
  (map (lambda (key) (list key '((() bind-required))))
       '("curl_easy_strerror" "curl_easy_nextheader" "curl_slist_append" "curl_slist_free_all"))
  (map (lambda (key) (list key (bound-via key)))
       '("curl_easy_strerror" "curl_easy_nextheader" "curl_slist_append" "curl_slist_free_all")))

;; Spike E1's plain rows (M3 slice 1; ADR-0013, accepted), written out
;; here, not read from the table: a row loosened along with its binding
;; would otherwise pass.
(test-equal "the table's rows for what spike E1 measured: curl_multi_perform, curl_multi_remove_handle and curl_multi_cleanup __collect_safe, through bind-blocking, and curl_multi_init, curl_multi_add_handle, curl_multi_wakeup, curl_multi_info_read and curl_easy_cleanup plain, each citing ADR-0013's acceptance, with no mark"
  (append (map (lambda (key) (list key '(__collect_safe) e1-can-block-citation '(bound-by bind-blocking)))
               '("curl_multi_perform" "curl_multi_remove_handle" "curl_multi_cleanup"))
          (map (lambda (key) (list key '() e1-plain-citation))
               '("curl_multi_init" "curl_multi_add_handle" "curl_multi_wakeup"
                 "curl_multi_info_read" "curl_easy_cleanup")))
  (guard (e (#t (list 'unreadable (describe e))))
    (map (lambda (key) (find (lambda (row) (equal? (car row) key)) conventions-table))
         '("curl_multi_perform" "curl_multi_remove_handle" "curl_multi_cleanup"
           "curl_multi_init" "curl_multi_add_handle" "curl_multi_wakeup"
           "curl_multi_info_read" "curl_easy_cleanup"))))

(test-equal "the scan of src/ finds the plain multi entries, and curl_multi_strerror, each bound once, through bind-required, with no convention"
  (map (lambda (key) (list key '((() bind-required))))
       '("curl_multi_init" "curl_multi_add_handle" "curl_multi_wakeup" "curl_multi_info_read"
         "curl_multi_strerror"))
  (map (lambda (key) (list key (bound-via key)))
       '("curl_multi_init" "curl_multi_add_handle" "curl_multi_wakeup" "curl_multi_info_read"
         "curl_multi_strerror")))

(test-equal "the table's row for curl_multi_strerror is plain, citing ADR-0013's cannot-block sentence, with no mark and no binder"
  (list (list "curl_multi_strerror" '() cannot-block-citation))
  (guard (e (#t (list 'unreadable (describe e))))
    (filter (lambda (row) (equal? (car row) "curl_multi_strerror")) conventions-table)))

(test-equal "the table's __collect_safe entries are exactly the calls that can block, curl_multi_poll and the three E1 measured, and curl_easy_pause, whose replay runs the callables"
  (list-sort string<? '("curl_multi_poll" "curl_multi_perform"
                        "curl_multi_remove_handle" "curl_multi_cleanup" "curl_easy_pause"))
  (guard (e (#t (list 'unreadable (describe e))))
    (list-sort string<?
               (map car (filter (lambda (row) (and (string? (car row))
                                                   (memq '__collect_safe (cadr row))))
                                conventions-table)))))

;; ADR-0013's sentence on what the two callees keep, written out here, not
;; read from the table.
(define not-kept-citation
  ".plans/decisions/0013-collect-safe-blocking-calls.md: `curl_easy_option_by_name` and `curl_easy_header` read their name argument during the call, and keep no pointer to it.")

;; M2's checked copies add the first bytevector-crossing mark, memcpy's.
(test-equal "the table marks exactly curl_easy_option_by_name and curl_easy_header, each string-not-kept, citing what their callees keep, and memcpy, the bytevector crossing, citing the one checked wrapper"
  `(("curl_easy_option_by_name" (string-not-kept ,not-kept-citation))
    ("curl_easy_header" (string-not-kept ,not-kept-citation))
    ("memcpy" (bytevector-crossing ,one-wrapper-citation)))
  (guard (e (#t (list 'unreadable (describe e))))
    (fold-left (lambda (found row)
                 (append found
                         (map (lambda (mark) (list (car row) mark))
                              (filter (lambda (x)
                                        (or ((tagged? 'bytevector-crossing) x)
                                            ((tagged? 'string-not-kept) x)))
                                      (cdddr row)))))
               '() conventions-table)))

(test-equal "the scan of src/ finds four crossings: memcpy's bytevector, once in each binding, then a string each, curl_easy_option_by_name's name and curl_easy_header's"
  '(("memcpy" (u8*)) ("memcpy" (u8*))
    ("curl_easy_option_by_name" (string)) ("curl_easy_header" (string)))
  (guard (e (#t (list 'unreadable (describe e))))
    (if (eq? (car src-check) 'returned)
        (map (lambda (b) (list (car b) (list-ref b 4)))
             (filter (lambda (b) (pair? (list-ref b 4))) (car (cadr src-check))))
        src-check)))

(test-equal "known-wrappers is exactly the wrappers src/ defines"
  (list 'returned known-wrappers)
  src-wrappers)

;; Written out here, not read from the table: a row loosened along with the
;; macro it holds, say load-step made any, would otherwise pass.
(test-equal "known-macros is src/'s five macros: three binders in native.sls, and load-step and require-supported-chez, plain, each in its own library"
  '((bind-required binder "curl/private/native.sls")
    (bind-variadic binder "curl/private/native.sls")
    (bind-blocking binder "curl/private/native.sls")
    (load-step plain "curl/private/load-state.sls")
    (require-supported-chez plain "curl/private/require-threaded.sls"))
  known-macros)

;; by-name : (Listof (Pairof Symbol Any)) -> (Listof (Pairof Symbol Any))
(define (by-name rows)
  (list-sort (lambda (a b) (string<? (symbol->string (car a)) (symbol->string (car b)))) rows))

;; Both ways: no row the scan does not find, and no macro the table lacks.
(test-equal "the scan of src/ finds every macro known-macros names, each defined once at a library body's top level in its row's file, and no other"
  (list 'returned (by-name (map (lambda (row) (list (car row) (caddr row))) known-macros)))
  (guard (e (#t (list 'unreadable (describe e))))
    (if (eq? (car src-macros) 'returned) (list 'returned (by-name (cadr src-macros))) src-macros)))

(test-end "collect-safe")

(exit (suite-exit-status runner))
