#!r6rs
;;; (foreign-conventions): the calling conventions chez-curl's foreign
;;; procedures and callables must carry, and a reader that finds the ones
;;; they do carry (ADR-0013, harness plan §3 item 3). Test-only: it lives in
;;; tests/, and tests/test-collect-safe.sps is its suite.
;;;
;;;   conventions-table   one row per C entry point or callable: its key,
;;;                       its required conventions, and a citation
;;;   known-macros        every macro src/ may define: its name, its kind,
;;;                       and the file whose library body defines it
;;;   known-wrappers      its binders, the macros whose template binds an
;;;                       entry point
;;;   scan-conventions    every binding under a directory, read as data, and
;;;                       every occurrence the reader cannot account for;
;;;                       scan-signatures gives each binding's types, which
;;;                       tests/test-constants.sps holds to the headers'
;;;                       prototypes
;;;   table-violations    each binding held against the table
;;;   check-conventions   both: what a suite asserts
;;;   table-problems      the table's own shape, and its citations checked
;;;                       against the decision records
;;;   readable-types      every type the reader reads, for a tree whose
;;;                       layouts define the given ftypes: what a binding
;;;                       can write, the universe tests/test-constants.sps
;;;                       holds its map against
;;;
;;; The reader evaluates nothing, and it fails closed. Every occurrence of
;;; the symbols foreign-procedure and foreign-callable in a source file must
;;; be one of these:
;;;
;;;   - a name in an (only (chezscheme) name ...) import of a library form;
;;;   - the head of (foreign-procedure convention ... entry (type ...) type)
;;;     whose entry is a string literal. The form is read from its end, so
;;;     whatever precedes the entry is a convention;
;;;   - the one foreign-procedure form in the template of a known wrapper.
;;;     The wrapper must be (define-syntax name (syntax-rules (literal ...)
;;;     (pattern template))), its entry a pattern variable at a fixed place
;;;     in the pattern, and its conventions free of pattern variables. Each
;;;     use, anywhere under the directory, must give the entry there as a
;;;     string literal, and binds it with the template's conventions;
;;;   - the head of a foreign-callable form that is the whole right-hand side
;;;     of (define name ...). Its row is keyed by NAME, a symbol.
;;;
;;; A known wrapper's name is an occurrence too, held to two places:
;;;
;;;   - the head of a use in code. Code is outside data, and outside every
;;;     macro: a transformer, its templates, patterns and literals, and the
;;;     syntax objects it builds (template-forms). A head in a macro can
;;;     still be reached as data: a syntax-case can take its own template
;;;     apart, and a syntax-rules template can hand a use to a head that
;;;     its own use names;
;;;   - the name its one define-syntax defines.
;;;
;;; So a wrapper's name is stray as an argument of any form, in data, in a
;;; macro, as a name a binding form binds, and in an export or an import.
;;; With no export, no library reaches a wrapper another defines, under any
;;; name.
;;;
;;; define-syntax, let-syntax and letrec-syntax are occurrences too
;;; (macro-keywords). Each stands only at the head of a form written in
;;; code: as an operand, in data, or at a head in a macro's template, it is
;;; stray, since there a macro, not the source, decides what it defines.
;;;
;;; The macros a tree may define are a table's, known-macros for src/, which
;;; each scan is given: rows (NAME KIND FILE), FILE below the root. A macro
;;; can take apart a form it is handed, a known wrapper's use or a
;;; foreign-procedure form, and bind what it rebuilds, while the reader
;;; reads the form as written. So:
;;;
;;;   - a define-syntax at a library body's top level must name a row, and
;;;     stand in its FILE;
;;;   - every other define-syntax, nested in any form, and every let-syntax
;;;     and letrec-syntax, is named;
;;;   - in a binder's or a plain macro's templates, each a syntax-rules
;;;     clause's or identifier-syntax's set! clause's, no pattern variable
;;;     heads a form: there a use could hand in any keyword, define-syntax,
;;;     import or another, and the macro would write the form it heads. A
;;;     foreign-procedure form's parameter list is types, not a form, so a
;;;     binder's (arg ...) there is allowed;
;;;   - a binder is a known wrapper, read as above. Its pattern takes no
;;;     operand apart: every element but its parameter list is neither a
;;;     list nor a vector;
;;;   - a plain macro neither builds a binding nor takes its operands apart.
;;;     Its definition holds no foreign-procedure, foreign-callable or known
;;;     wrapper's name, and none of syntax-case, with-syntax, syntax->datum
;;;     and datum->syntax. Every pattern in it, a syntax-rules clause's and
;;;     identifier-syntax's set! clause's, is (_ id ...) or (set! id id),
;;;     identifiers only. A procedural one is exactly (lambda (ID) BODY
;;;     ...), one identifier. In BODY, ID stands only as the last argument
;;;     of a syntax-violation call, and syntax-violation only at the head of
;;;     a call in tail position: through if's branches, cond's and case's
;;;     clauses, and the last form of when, unless, begin, and, or and the
;;;     let forms. Its library imports only whole (rnrs ...) libraries but
;;;     (rnrs eval), and (only (chezscheme) name ...), with (rnrs) or (rnrs
;;;     syntax-case) among them. So its output cannot depend on its input,
;;;     whose one way out is the condition a tail raise hands the expander,
;;;     and no procedure of another library, which could take the input
;;;     apart or build a binding from strings, is in its reach;
;;;   - any is a fixture tree's kind, for a macro the tree uses to test
;;;     another rule: it is held to its row and its place, and to neither
;;;     kind's rules. known-macros names none.
;;;
;;; Anything else is a violation naming the file and the form: a quoted
;;; occurrence among them. Data is what quote and quasiquote (unquote
;;; included) hold, vector and box literals, a library's name, its export
;;; and import clauses, an import or export form anywhere, a case clause's
;;; datum list, and what define, define-values, lambda, case-lambda, the
;;; let forms, fluid-let, do and guard bind. So is a file it cannot read, a datum with shared structure
;;; (which it does not walk), a symbolic link to a directory (which it does
;;; not follow), and a directory with no source file. A source file is one
;;; Chez could load a library from, by the source endings of
;;; (library-extensions); a dangling symbolic link named .#..., an Emacs
;;; lock file, is skipped.
;;;
;;; Its limits. The rules for plain macros rest on what they do not read:
;;;
;;;   - two facts of Chez, each measured. It refuses a raw symbol in a
;;;     transformer's output, from a list or a quasisyntax alike ("encountered
;;;     raw symbol"), so a name built by string->symbol reaches code only
;;;     through datum->syntax. And with (rnrs) imported whole, it refuses any
;;;     other binding of syntax-violation in the library, imported or
;;;     defined ("multiple definitions");
;;;   - R6RS's handlers: one sees a raise only from within its own extent,
;;;     so a raise in tail position reaches the expander's alone;
;;;   - check-seam's allowlist of (chezscheme) names, which keeps eval,
;;;     expand and interpret out of src/; its rules (h) and (i), which
;;;     require every family library src/ imports to be defined under src/,
;;;     alone in the file its name's path gives, so the one Chez loads for
;;;     it, with src/ first on the suites' library path, is the one this
;;;     reader reads; and test-constants, which holds define-ftype to
;;;     structs.
;;;
;;; And it reads a use as written. A plain macro's template may put an
;;; operand in data, by quote: the reader then counts a binding the operand
;;; writes that Chez never makes. Measured, such a phantom held
;;; test-collect-safe's counts while test-variadic failed on the binding
;;; that was not there. A phantom hides no binding by itself, but could
;;; keep a count while another route did, and no route that hides one is
;;; known open.
;;;
;;; A fixture tree's any macros are held to neither kind's rules.
;;;
;;; Types, read as an allowlist (ADR-0013, amended). Every parameter and
;;; result type of every binding must be one of these, else the binding is
;;; a type the reader cannot read, and a violation:
;;;
;;;   - an immediate or address type Chez 10.4.0 documents (immediate-types),
;;;     and void as a result: C gets a value, never a pointer into Chez's
;;;     heap;
;;;   - (* NAME) or (& NAME), where NAME is an ftype the tree's (curl private
;;;     layouts) defines, read as data from ROOT/curl/private/layouts.sls;
;;;   - a crossing type, of one of three kinds, below.
;;;
;;; A macro's pattern variable is on no list, so a macro that is no known
;;; wrapper cannot take a type from its use. Nor can one whose pattern
;;; variable is spelt as a type, uptr say: inside a syntax-rules,
;;; syntax-case, with-syntax or identifier-syntax form, every symbol of its
;;; patterns is a pattern variable, and a binding's type that is one is
;;; unreadable; a convention that is one is conventions-from-pattern. A
;;; known wrapper's use is never inside a macro. The reader reads the types
;;; of direct forms, and of a known wrapper's uses: a template's parameter
;;; list is its own types, or (arg ...), a pattern element at a fixed
;;; place, which each use then gives; its result is its own type, or a
;;; pattern variable at a fixed place, likewise.
;;;
;;; Crossings. Valgrind cannot see Chez's heap: a copy one byte past a
;;; bytevector's end passes the memory gate. Chez hands C a pointer into
;;; its heap for these types, as a foreign procedure's parameter or a
;;; callable's result, and each binding carries them, in order, as its
;;; crossings:
;;;
;;;   - a bytevector's data, u8*, u16* or u32*. One checked wrapper (M2)
;;;     owns every copy between a bytevector and foreign memory, so only a
;;;     row marked (bytevector-crossing CITATION) may have one;
;;;   - a string, Chez's copy in its own heap: string, utf-8, utf-16le,
;;;     utf-16be, utf-32le, utf-32be, wstring. A callee that kept it would
;;;     read garbage once the collector moved it, so only a row marked
;;;     (string-not-kept CITATION) may have one;
;;;   - a Scheme object itself, scheme-object, which no row may have, as a
;;;     parameter or a result of either.
;;;
;;; The other way, a procedure's u8* or string result, or a callable's u8*
;;; or string parameter, Chez copies C's bytes into a fresh bytevector or
;;; string, and hands C none.
;;;
;;; A violation is a list, a symbol first:
;;;
;;;   (no-sources ROOT)                      no source file under ROOT
;;;   (directory-link PATH)                  a link to a directory
;;;   (unreadable FILE TEXT)                 FILE cannot be read as data
;;;   (shared-structure FILE FORM)           FORM is reached twice in a datum
;;;   (stray FILE FORM)                      an occurrence in FORM, unaccounted
;;;   (malformed FILE FORM)                  a form that is no binding's shape
;;;   (entry-not-string FILE FORM)           an entry that is no string literal
;;;   (callable-not-defined FILE FORM)       a callable not under a define
;;;   (wrapper-unreadable FILE NAME REASON)
;;;   (wrapper-conventions-from-pattern FILE NAME CONVENTIONS)
;;;   (wrapper-entry-not-string FILE NAME FORM)
;;;   (wrapper-undefined FILE NAME FORM)     a use with no definition
;;;   (wrapper-defined-again FILE NAME)      a second definition
;;;   (macro-unlisted FILE NAME)             a define-syntax at a library
;;;                                          body's top level that names no
;;;                                          row of the macro table
;;;   (macro-elsewhere FILE NAME LISTED)     a row's macro defined in FILE,
;;;                                          not in LISTED, its row's file
;;;   (macro-nested FILE FORM)               a define-syntax anywhere but a
;;;                                          library body's top level
;;;   (macro-local FILE FORM)                a let-syntax or letrec-syntax
;;;   (plain-macro-binds FILE NAME SYMBOL)   a plain macro's definition holds
;;;                                          foreign-procedure,
;;;                                          foreign-callable or a known
;;;                                          wrapper's name, once a symbol
;;;   (plain-macro-takes-apart FILE NAME SYMBOL)
;;;                                          it holds one of syntax-case,
;;;                                          with-syntax, syntax->datum and
;;;                                          datum->syntax, once a symbol
;;;   (plain-macro-pattern FILE NAME PATTERN)
;;;                                          a pattern in it that is not
;;;                                          (_ id ...) or (set! id id)
;;;   (plain-macro-transformer FILE NAME FORM)
;;;                                          a procedural transformer that is
;;;                                          not (lambda (ID) BODY ...)
;;;   (plain-macro-import FILE NAME)         its library imports more than
;;;                                          whole (rnrs ...) libraries and
;;;                                          (only (chezscheme) ...), or
;;;                                          neither (rnrs) nor (rnrs
;;;                                          syntax-case) whole
;;;   (plain-macro-input FILE NAME FORM)     its input stands in FORM, not as
;;;                                          a syntax-violation call's last
;;;                                          argument
;;;   (plain-macro-raise FILE NAME FORM)     syntax-violation stands in FORM,
;;;                                          not at the head of a call in
;;;                                          tail position
;;;   (macro-pattern-head FILE NAME FORM)    a binder's or plain macro's
;;;                                          template holds FORM, headed by
;;;                                          one of its pattern variables
;;;   (types-unreadable FILE FORM)           a type it cannot read, or one on
;;;                                          no allowlist; FORM is a callable's
;;;                                          define
;;;   (wrapper-types-unreadable FILE NAME FORM)
;;;   (conventions-from-pattern FILE FORM)   a convention that is a macro's
;;;                                          pattern variable
;;;   (no-row KEY FILE)                      a binding the table lacks
;;;   (mismatch KEY EXPECTED ACTUAL FILE)    conventions that differ, as sets
;;;   (wrong-binder KEY EXPECTED ACTUAL FILE)
;;;                                          a binding made otherwise than its
;;;                                          row's (bound-by EXPECTED): ACTUAL
;;;                                          is foreign-procedure,
;;;                                          foreign-callable or a known
;;;                                          wrapper's name
;;;   (bytevector-crossing KEY TYPES FILE)   bytevector crossings its row does
;;;                                          not mark
;;;   (string-crossing KEY TYPES FILE)       string crossings its row does not
;;;                                          mark string-not-kept
;;;   (scheme-object KEY TYPES FILE)         scheme-object, marked or not
;;;
;;; A FORM is the datum written, cut to 100 characters. Paths are ROOT
;;; joined to the names below it.
(library (foreign-conventions)
  (export conventions-table known-macros known-wrappers
          scan-conventions scan? scan-bindings scan-violations scan-wrappers
          scan-macros scan-signatures table-violations check-conventions
          table-problems readable-types)
  (import (rnrs)
          (only (chezscheme) box? unbox directory-list display-condition
                file-directory? file-regular? file-symbolic-link?
                library-extensions parameterize print-graph))

  ;; --- the table -------------------------------------------------------------

  (define adr-0001 ".plans/decisions/0001-bind-libcurl-directly.md")
  (define adr-0013 ".plans/decisions/0013-collect-safe-blocking-calls.md")

  ;; A citation is "RECORD: PHRASE": table-problems checks that RECORD is a
  ;; decision record and that it holds PHRASE, whitespace aside.
  (define (cite record phrase) (string-append record ": " phrase))

  (define cannot-block (cite adr-0013 "Calls that cannot block stay plain."))
  (define can-block (cite adr-0013 "`curl_multi_poll` is the engine's wait, so it is `__collect_safe`."))
  ;; What spike E1 measured (M3 slice 1; ADR-0013, accepted): the multi
  ;; calls that waited 9 to 10 s while a name lookup stalled, and those that
  ;; never took a millisecond. curl_easy_cleanup is plain for a handle taken
  ;; out of the engine's multi handle, and for the load's header probe's,
  ;; which never ran a transfer. After curl_easy_perform it waited about 9 s
  ;; on 8.20.0; slice 2 deleted that path, and the binding with it.
  (define e1-can-block
    (cite adr-0013 "`curl_multi_perform`, `curl_multi_remove_handle` and `curl_multi_cleanup` can block, so each is `__collect_safe`."))
  (define e1-plain
    (cite adr-0013 "These stay plain: `curl_multi_init`, `curl_multi_add_handle`, `curl_multi_wakeup`, `curl_multi_info_read`, and `curl_easy_cleanup` of a handle removed from a multi handle the caller made."))
  (define memcpy-plain
    (cite adr-0001 "Bulk byte moves use libc's `memcpy`, bound directly, as a plain call."))
  ;; memcpy's two bindings hand C a bytevector's data: the checked copies'
  ;; own, in (curl private native), which assert the span first.
  (define one-checked-wrapper
    (cite adr-0001 "One checked wrapper owns every copy between a bytevector and foreign memory."))
  (define name-not-kept
    (cite adr-0013 "`curl_easy_option_by_name` and `curl_easy_header` read their name argument during the call, and keep no pointer to it."))
  ;; The four variadic entries, each bound once per value type with
  ;; (__varargs_after 2): their first two parameters are named, the rest
  ;; variadic. Apple arm64 passes those on the stack, so the convention is
  ;; what makes them arrive there.
  (define variadic-after-2
    (cite adr-0001 "Variadic entry points are bound once per value type, with `(__varargs_after 2)`."))
  ;; write-body, (curl private transfer)'s one callable, is invoked from
  ;; inside curl_multi_perform, a __collect_safe call, so it reactivates the
  ;; thread (CSUG). Spike E1 saw it fire there and nowhere else.
  (define callback-in-perform
    (cite adr-0013 "So the engine's write callable is `__collect_safe`, as its perform is."))

  ;; conventions-table : (Listof Row)
  ;; A Row is (List (U String Symbol) (Listof Convention) String), then
  ;; optionally a Mark, (bytevector-crossing CITATION) or (string-not-kept
  ;; CITATION), then optionally a Binder, (bound-by BINDER), its last
  ;; element.
  ;; One row per C entry point, keyed by its name, a string, or per
  ;; callable, keyed by the name it is defined as, a symbol. A convention is
  ;; a symbol, __collect_safe, or a list, (__varargs_after 2). Rows for
  ;; entries not bound yet hold M2 to ADR-0013 the moment it binds them,
  ;; and M3 to ADR-0001 for curl_multi_setopt and curl_share_setopt, and
  ;; to ADR-0013's acceptance for the multi calls spike E1 measured.
  ;;
  ;; A mark clears the row's bindings of one kind of crossing: a
  ;; bytevector's data, or a string its callee keeps no pointer to. Its
  ;; citation quotes a decision record, checked as the row's own is, and a
  ;; marked row is never __collect_safe (ADR-0013's decision 4). A row has
  ;; one mark at most. Two rows are marked string-not-kept, and memcpy's,
  ;; the checked copies', bytevector-crossing.
  ;;
  ;; A binder names the one way the row's entry may be bound: a known
  ;; wrapper, foreign-procedure or foreign-callable. The four variadic rows
  ;; name bind-variadic, whose template carries the convention, so a
  ;; binding made any other way, directly with the convention included, is
  ;; the wrong binder, and make check-variadic's mutation of that template
  ;; reaches every binding of them. The four multi calls that can block
  ;; name bind-blocking, whose template carries __collect_safe, likewise.
  (define conventions-table
    (list (list "curl_version_info" '() cannot-block)
          (list "curl_global_init" '() cannot-block)
          (list "curl_easy_option_by_name" '() cannot-block (list 'string-not-kept name-not-kept))
          (list "curl_easy_init" '() cannot-block)
          (list "curl_easy_header" '() cannot-block (list 'string-not-kept name-not-kept))
          (list "curl_easy_cleanup" '() e1-plain)
          (list "curl_easy_setopt" '((__varargs_after 2)) variadic-after-2 '(bound-by bind-variadic))
          (list "curl_easy_getinfo" '((__varargs_after 2)) variadic-after-2 '(bound-by bind-variadic))
          (list "curl_multi_setopt" '((__varargs_after 2)) variadic-after-2 '(bound-by bind-variadic))
          (list "curl_share_setopt" '((__varargs_after 2)) variadic-after-2 '(bound-by bind-variadic))
          (list "curl_multi_poll" '(__collect_safe) can-block '(bound-by bind-blocking))
          (list "curl_multi_perform" '(__collect_safe) e1-can-block '(bound-by bind-blocking))
          (list "curl_multi_remove_handle" '(__collect_safe) e1-can-block '(bound-by bind-blocking))
          (list "curl_multi_cleanup" '(__collect_safe) e1-can-block '(bound-by bind-blocking))
          (list "curl_multi_init" '() e1-plain)
          (list "curl_multi_add_handle" '() e1-plain)
          (list "curl_multi_wakeup" '() e1-plain)
          (list "curl_multi_info_read" '() e1-plain)
          (list "curl_multi_strerror" '() cannot-block)
          (list "memcpy" '() memcpy-plain (list 'bytevector-crossing one-checked-wrapper))
          (list "strlen" '() cannot-block)
          (list "curl_url" '() cannot-block)
          (list "curl_url_cleanup" '() cannot-block)
          (list "curl_url_set" '() cannot-block)
          (list "curl_url_get" '() cannot-block)
          (list "curl_url_strerror" '() cannot-block)
          (list "curl_free" '() cannot-block)
          (list "curl_easy_strerror" '() cannot-block)
          (list "curl_easy_nextheader" '() cannot-block)
          (list "curl_slist_append" '() cannot-block)
          (list "curl_slist_free_all" '() cannot-block)
          (list 'write-body '(__collect_safe) callback-in-perform)))

  ;; known-macros : (Listof (List Symbol Kind String))
  ;; Every macro src/ may define: its name, its kind, and the file below
  ;; src/ whose library body defines it, at its top level. A Kind is binder,
  ;; a known wrapper; plain, a macro that neither builds a binding nor takes
  ;; its operands apart; or any, which only a fixture tree's table may name.
  ;; The suite holds it equal, both ways, to what src/ defines, and to
  ;; these five rows written out by hand.
  (define known-macros
    '((bind-required binder "curl/private/native.sls")
      (bind-variadic binder "curl/private/native.sls")
      (bind-blocking binder "curl/private/native.sls")
      (load-step plain "curl/private/load-state.sls")
      (require-supported-chez plain "curl/private/require-threaded.sls")))

  ;; binders : (Listof (List Symbol Kind String)) -> (Listof Symbol)
  ;; The names of MACROS' binder rows, in order: the known wrappers.
  (define (binders macros)
    (map car (filter (lambda (row) (and (pair? row) (pair? (cdr row)) (eq? (cadr row) 'binder)))
                     macros)))

  ;; known-wrappers : (Listof Symbol)
  ;; The macros whose template binds an entry point: known-macros' binders,
  ;; src/curl/private/native.sls's bind-required, bind-variadic and
  ;; bind-blocking. The suite holds it equal to the wrappers src/ defines.
  (define known-wrappers (binders known-macros))

  ;; --- the scan's answer ----------------------------------------------------------

  ;; A Binding is (List (U String Symbol) (Listof Convention) String Symbol
  ;; (Listof Symbol)): its key, its conventions as written, its file, how it
  ;; was bound (foreign-procedure, foreign-callable, or the known wrapper's
  ;; name), and its crossings: its types of the three crossing kinds, in
  ;; order, parameters then result, where they are crossings.
  ;;
  ;; scan? : Any -> Boolean
  ;; scan-bindings : Scan -> (Listof Binding)
  ;; scan-violations : Scan -> (Listof Violation)
  ;; scan-wrappers : Scan -> (Listof Symbol)
  ;;   the known wrappers defined once, and read, in the order defined
  ;; scan-macros : Scan -> (Listof (List Symbol String))
  ;;   each define-syntax at a library body's top level: its name, and its
  ;;   file below the root, in the order read
  ;; scan-signatures : Scan -> (Listof Signature)
  ;;   each binding's types, in the order of scan-bindings. A Signature is
  ;;   (List (U String Symbol) Symbol (Listof Any) Any String): its key, how
  ;;   it was bound, its parameter types and its result type as written, a
  ;;   known wrapper's use's as its template and the use give them, and its
  ;;   file
  (define-record-type scan
    (fields bindings violations wrappers macros signatures))

  ;; --- text ------------------------------------------------------------------------

  (define limit 100)

  ;; written : Any -> String
  ;; print-graph labels shared structure, so even a cyclic datum prints.
  (define (written datum)
    (call-with-string-output-port
      (lambda (p) (parameterize ((print-graph #t)) (write datum p)))))

  ;; abbreviated : Any -> String
  (define (abbreviated datum)
    (let ((text (written datum)))
      (if (> (string-length text) limit)
          (string-append (substring text 0 (- limit 3)) "...")
          text)))

  ;; describe : Any -> String
  (define (describe obj)
    (guard (e (#t "<the raised object could not be printed>"))
      (call-with-string-output-port
        (lambda (p) (if (condition? obj) (display-condition obj p) (write obj p))))))

  (define (suffix? s suffix)
    (let ((n (string-length s)) (m (string-length suffix)))
      (and (>= n m) (string=? (substring s (- n m) n) suffix))))

  (define (prefix? s prefix)
    (let ((n (string-length s)) (m (string-length prefix)))
      (and (>= n m) (string=? (substring s 0 m) prefix))))

  ;; search : String String -> (U Natural #f)
  ;; Where NEEDLE first starts in HAYSTACK.
  (define (search haystack needle)
    (let ((n (string-length haystack)) (m (string-length needle)))
      (let loop ((i 0))
        (cond ((> (+ i m) n) #f)
              ((string=? (substring haystack i (+ i m)) needle) i)
              (else (loop (+ i 1)))))))

  ;; squeezed : String -> String
  ;; TEXT with each run of whitespace made one space, so a phrase matches
  ;; across a line break.
  (define (squeezed text)
    (call-with-string-output-port
      (lambda (p)
        (let loop ((chars (string->list text)) (space? #f))
          (cond ((null? chars) #f)
                ((char-whitespace? (car chars))
                 (unless space? (put-char p #\space))
                 (loop (cdr chars) #t))
                (else (put-char p (car chars)) (loop (cdr chars) #f)))))))

  ;; --- the tree --------------------------------------------------------------------

  ;; source-endings : (Listof String)
  ;; The endings Chez loads a library's source from: .chezscheme.sls .ss
  ;; .sls .scm .sch at 10.4.0.
  (define source-endings (map car (library-extensions)))

  (define (source-name? name)
    (exists (lambda (ending) (suffix? name ending)) source-endings))

  ;; lock-file? : String String -> Boolean
  ;; NAME, at PATH, is Emacs's lock file: .#..., a symbolic link to nothing.
  (define (lock-file? path name)
    (and (prefix? name ".#")
         (file-symbolic-link? path)
         (not (file-exists? path))))

  ;; tree : String -> (List (Listof String) (Listof String))
  ;; Under DIR: the source files, and the symbolic links to directories.
  (define (tree dir)
    (fold-left
     (lambda (found name)
       (let ((path (string-append dir "/" name)))
         (cond ((lock-file? path name) found)
               ((file-directory? path #f)
                (let ((below (tree path)))
                  (list (append (car found) (car below))
                        (append (cadr found) (cadr below)))))
               ((file-directory? path)
                (list (car found) (append (cadr found) (list path))))
               ((source-name? name)
                (list (append (car found) (list path)) (cadr found)))
               (else found))))
     (list '() '())
     (directory-list dir)))

  ;; read-data : String -> (U (List 'data (Listof Any)) (List 'unreadable String))
  (define (read-data path)
    (guard (e (#t (list 'unreadable (describe e))))
      (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                            (make-transcoder (utf-8-codec)))
        (lambda (port)
          (let loop ((found '()))
            (let ((datum (read port)))
              (cond ((not (eof-object? datum)) (loop (cons datum found)))
                    ((port-eof? port) (list 'data (reverse found)))
                    (else (error 'read "an #!eof literal ends the reading before the end of the file")))))))))

  ;; --- reading forms ---------------------------------------------------------------

  ;; occurrence? : Any -> Boolean
  ;; X is foreign-procedure or foreign-callable. A known wrapper's name is an
  ;; occurrence too, which datum-findings adds.
  (define (occurrence? x)
    (and (memq x '(foreign-procedure foreign-callable)) #t))

  ;; shared-part : Any -> (U Pair Vector Box #f)
  ;; The first pair, non-empty vector or box that X reaches twice, through
  ;; cars, cdrs, elements and contents; #f when none is. Two empty vector
  ;; literals read as one object, so an empty vector is never shared.
  (define (shared-part x)
    (let ((seen (make-eq-hashtable)))
      (let walk ((x x))
        (cond ((or (pair? x) (box? x) (and (vector? x) (> (vector-length x) 0)))
               (if (hashtable-ref seen x #f)
                   x
                   (begin
                     (hashtable-set! seen x #t)
                     (cond ((pair? x) (or (walk (car x)) (walk (cdr x))))
                           ((box? x) (walk (unbox x)))
                           (else (walk (vector->list x)))))))
              (else #f)))))

  (define (take lst n)
    (if (= n 0) '() (cons (car lst) (take (cdr lst) (- n 1)))))

  ;; elements : Any -> (Listof Any)
  ;; FORM's elements; an improper tail is one more.
  (define (elements form)
    (cond ((pair? form) (cons (car form) (elements (cdr form))))
          ((null? form) '())
          (else (list form))))

  ;; procedure-parts : Any -> (U (List (Listof Any) Any (Listof Any) Any) #f)
  ;; FORM as (head convention ... entry-or-procedure (type ...) type): its
  ;; conventions, its entry, its parameter types and its result, or #f when
  ;; it has not that shape.
  (define (procedure-parts form)
    (and (list? form)
         (>= (length form) 4)
         (let ((n (length form)))
           (and (list? (list-ref form (- n 2)))
                (list (take (cdr form) (- n 4)) (list-ref form (- n 3))
                      (list-ref form (- n 2)) (list-ref form (- n 1)))))))

  ;; --- types ---------------------------------------------------------------------

  ;; immediate-types : (Listof Symbol)
  ;; The parameter and result types Chez 10.4.0 documents that convert a
  ;; value, so hand C no pointer into its heap: CSUG 10.4.0 section 4.2's
  ;; integer, unsigned, floating, char, boolean, fixnum, pointer-sized and
  ;; size families. Chez also takes integer-24 to integer-56 and their
  ;; unsigned kin, which CSUG lists for neither, and ptr, utf-16, utf-32,
  ;; ftype-pointer and ftype-scheme-object-pointer, which hand C its heap
  ;; or may; each is on no list here, so unreadable.
  (define immediate-types
    '(integer-8 unsigned-8 integer-16 unsigned-16 integer-32 unsigned-32
      integer-64 unsigned-64 double-float single-float double float
      short unsigned-short int unsigned unsigned-int long unsigned-long
      long-long unsigned-long-long ptrdiff_t size_t ssize_t iptr uptr void*
      fixnum boolean stdbool char wchar_t wchar))

  ;; The crossing kinds (ADR-0013, amended): a bytevector's data (Chez
  ;; 10.4.0 refuses u64* and bytevector as types), a string Chez copies into
  ;; its heap, and a Scheme object itself.
  (define bytevector-types '(u8* u16* u32*))
  (define string-types '(string utf-8 utf-16le utf-16be utf-32le utf-32be wstring))
  (define object-types '(scheme-object))

  ;; readable-types : (Listof Symbol) -> (Listof Any)
  ;; Every type type-kind reads, for a tree whose layouts define FTYPES: the
  ;; immediate types, void, the crossing types of each kind, and (* NAME)
  ;; and (& NAME) for each NAME in FTYPES. Any other type is unreadable, so
  ;; this is the whole set a binding can write.
  (define (readable-types ftypes)
    (append immediate-types '(void) bytevector-types string-types object-types
            (map (lambda (name) (list '* name)) ftypes)
            (map (lambda (name) (list '& name)) ftypes)))

  ;; type-shaped? : Any -> Boolean
  ;; A symbol, or (* name) or (& name): what a known wrapper's template may
  ;; write for a type, held to the allowlist at each use.
  (define (type-shaped? type)
    (or (symbol? type)
        (and (list? type)
             (= (length type) 2)
             (memq (car type) '(* &))
             (symbol? (cadr type))
             #t)))

  ;; types-shaped? : Any -> Boolean
  (define (types-shaped? types)
    (and (list? types) (for-all type-shaped? types)))

  ;; type-kind : Any (Listof Symbol) Boolean
  ;;             -> (U 'value 'bytevector 'string 'object #f)
  ;; What TYPE hands across: a value, or a crossing of a kind; #f when it is
  ;; on no allowlist. FTYPES are the names layouts defines; RESULT? holds
  ;; for a result, which alone may be void.
  (define (type-kind type ftypes result?)
    (cond ((memq type immediate-types) 'value)
          ((and result? (eq? type 'void)) 'value)
          ((memq type bytevector-types) 'bytevector)
          ((memq type string-types) 'string)
          ((memq type object-types) 'object)
          ((and (list? type)
                (= (length type) 2)
                (memq (car type) '(* &))
                (memq (cadr type) ftypes))
           'value)
          (else #f)))

  ;; signature-crossings : (Listof Any) Any (Listof Symbol) Boolean
  ;;                       -> (U (Listof Symbol) 'unreadable)
  ;; The crossings of PARAMETERS and RESULT, in order, or 'unreadable when
  ;; one is on no allowlist. A foreign procedure hands C its parameters and
  ;; a callable (CALLABLE?) its result; scheme-object is a crossing either
  ;; way.
  (define (signature-crossings parameters result ftypes callable?)
    (let ((typed (append (map (lambda (type)
                                (list type (type-kind type ftypes #f) (not callable?)))
                              parameters)
                         (list (list result (type-kind result ftypes #t) callable?)))))
      (if (exists (lambda (t) (not (cadr t))) typed)
          'unreadable
          (map car
               (filter (lambda (t)
                         (or (eq? (cadr t) 'object)
                             (and (caddr t) (memq (cadr t) '(bytevector string)) #t)))
                       typed)))))

  ;; library-form? : Any -> Boolean
  (define (library-form? datum)
    (and (list? datum)
         (>= (length datum) 4)
         (eq? (car datum) 'library)
         (pair? (caddr datum))
         (eq? (car (caddr datum)) 'export)
         (list? (cadddr datum))
         (pair? (cadddr datum))
         (eq? (car (cadddr datum)) 'import)))

  ;; layouts-file : String
  ;; Where a tree's ftypes are defined, below its root.
  (define layouts-file "curl/private/layouts.sls")

  ;; layout-ftypes : String -> (Listof Symbol)
  ;; The ftypes ROOT's (curl private layouts) defines: each
  ;; (define-ftype NAME TYPE) in its library body, read as data. () when the
  ;; file is absent or cannot be read, which the scan names as it reads the
  ;; tree, and from a datum with shared structure, which it names too.
  (define (layout-ftypes root)
    (let ((data (read-data (string-append root "/" layouts-file))))
      (if (eq? (car data) 'unreadable)
          '()
          (fold-left
           (lambda (names datum)
             (if (and (not (shared-part datum))
                      (library-form? datum)
                      (equal? (cadr datum) '(curl private layouts)))
                 (append names
                         (map cadr
                              (filter (lambda (form)
                                        (and (list? form)
                                             (= (length form) 3)
                                             (eq? (car form) 'define-ftype)
                                             (symbol? (cadr form))))
                                      (cddddr datum))))
                 names))
           '() (cadr data)))))

  ;; chez-only? : Any -> Boolean
  ;; SPEC is (only (chezscheme) name ...), the one import that accounts
  ;; for a name.
  (define (chez-only? spec)
    (and (list? spec)
         (>= (length spec) 2)
         (eq? (car spec) 'only)
         (equal? (cadr spec) '(chezscheme))))

  ;; callable-definition? : Pair -> Boolean
  ;; (define name (foreign-callable ...)).
  (define (callable-definition? form)
    (and (eq? (car form) 'define)
         (list? form)
         (= (length form) 3)
         (symbol? (cadr form))
         (pair? (caddr form))
         (eq? (car (caddr form)) 'foreign-callable)))

  ;; --- known wrappers --------------------------------------------------------------

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

  ;; pattern-takes-apart? : Pair (U (List 'types (Listof Any)) (List 'at Natural)) -> Boolean
  ;; PATTERN, a list, holds a list or a vector where a use gives an operand,
  ;; but for the parameter list a use gives at the place READING names: the
  ;; template could then rebuild what a use hands it, a use among them.
  (define (pattern-takes-apart? pattern reading)
    (let loop ((rest (cdr pattern)) (i 1))
      (cond ((null? rest) #f)
            ((and (eq? (car reading) 'at) (= i (cadr reading))) (loop (cdr rest) (+ i 1)))
            ((or (pair? (car rest)) (vector? (car rest))) #t)
            (else (loop (cdr rest) (+ i 1))))))

  ;; one-clause-rules? : Any -> Boolean
  (define (one-clause-rules? rules)
    (and (list? rules)
         (= (length rules) 3)
         (eq? (car rules) 'syntax-rules)
         (list? (cadr rules))
         (for-all symbol? (cadr rules))
         (list? (caddr rules))
         (= (length (caddr rules)) 2)
         (pair? (car (caddr rules)))))

  ;; procedure-heads : Any -> (Listof Pair)
  ;; The forms headed by foreign-procedure in a template, outside quote and
  ;; quasiquote, in order.
  (define (procedure-heads x)
    (if (and (pair? x) (not (memq (car x) '(quote quasiquote))))
        (append (if (eq? (car x) 'foreign-procedure) (list x) '())
                (fold-left (lambda (found e) (append found (procedure-heads e)))
                           '() (elements x)))
        '()))

  ;; symbols-in : Any -> (Listof Symbol)
  (define (symbols-in x)
    (cond ((symbol? x) (list x))
          ((pair? x) (append (symbols-in (car x)) (symbols-in (cdr x))))
          ((vector? x) (symbols-in (vector->list x)))
          (else '())))

  ;; macro-forms : (Listof Symbol)
  ;; The forms whose clauses bind pattern variables in their templates.
  (define macro-forms '(syntax-rules syntax-case with-syntax identifier-syntax))

  ;; template-forms : (Listof Symbol)
  ;; The forms whose parts are a macro's to place: a transformer, its
  ;; templates, patterns and literals, and the syntax objects it builds.
  ;; macro-forms are among them. A head there with a literal entry can still
  ;; be reached as data: a syntax-case can take its template apart, and a
  ;; syntax-rules template can hand a form to a head its own use names. So
  ;; a known wrapper's name in one is stray, never a use.
  (define template-forms
    (append '(define-syntax let-syntax letrec-syntax syntax quasisyntax) macro-forms))

  ;; macro-keywords : (Listof Symbol)
  ;; The forms that define a macro. Each is an occurrence: it stands only at
  ;; the head of a form written in code. Handed to a macro, as an operand,
  ;; or written in its template, the macro would decide what it defines.
  (define macro-keywords '(define-syntax let-syntax letrec-syntax))

  ;; data-forms : (Listof Symbol)
  ;; The forms read as data whole: quote and quasiquote, unquote included,
  ;; and import and export, whose parts name bindings and bind none.
  (define data-forms '(quote quasiquote import export))

  ;; macro-variables : Pair -> (Listof Symbol)
  ;; The pattern variables FORM, headed by one of macro-forms, may bind,
  ;; over-approximated: every symbol of every clause's head but _ and ...,
  ;; the literals and the keyword included. A clause is a pair after
  ;; syntax-rules' literals, after syntax-case's expression and literals,
  ;; among with-syntax's bindings, or after identifier-syntax.
  (define (macro-variables form)
    (let ((clauses (case (car form)
                     ((syntax-rules) (if (pair? (cdr form)) (cddr form) '()))
                     ((syntax-case)
                      (if (and (pair? (cdr form)) (pair? (cddr form))) (cdddr form) '()))
                     ((with-syntax) (if (pair? (cdr form)) (cadr form) '()))
                     (else (cdr form)))))
      (filter (lambda (s) (not (memq s '(_ ...))))
              (symbols-in (map car (filter pair? (elements clauses)))))))

  ;; pattern-variables : Pair (Listof Symbol) -> (Listof Symbol)
  ;; Element 0 of a syntax-rules pattern is ignored, so it binds nothing.
  (define (pattern-variables pattern literals)
    (filter (lambda (s) (not (or (memq s '(_ ...)) (memq s literals))))
            (symbols-in (cdr pattern))))

  ;; fixed-index : Pair Any -> (U Natural #f)
  ;; Where ELEMENT first stands among PATTERN's elements, when a use's
  ;; element there is always the one ELEMENT matches: PATTERN is a list
  ;; holding it at index 1 or later, and no ellipsis stands at or before
  ;; the element after it.
  (define (fixed-index pattern element)
    (and (list? pattern)
         (let loop ((rest (cdr pattern)) (i 1))
           (cond ((null? rest) #f)
                 ((equal? (car rest) element)
                  (and (not (memq '... (take pattern (min (length pattern) (+ i 2)))))
                       i))
                 (else (loop (cdr rest) (+ i 1)))))))

  ;; entry-index : Pair Any (Listof Symbol) -> (U Natural #f)
  ;; Where the entry stands in a use: ENTRY is a pattern variable at a fixed
  ;; place.
  (define (entry-index pattern entry variables)
    (and (memq entry variables) (fixed-index pattern entry)))

  ;; parameters-reading : Pair (Listof Any) (Listof Symbol)
  ;;                      -> (U (List 'types (Listof Any)) (List 'at Natural) #f)
  ;; Where a use's parameter types come from: PARAMETERS, a template's
  ;; parameter list holding no pattern variable, is the types themselves;
  ;; one that is (variable ...) stands for the use's element at the place
  ;; PATTERN holds (variable ...), when that place is fixed. Anything else
  ;; is #f. A parameter list that is one variable is no list, so
  ;; procedure-parts has already found its form malformed.
  (define (parameters-reading pattern parameters variables)
    (cond ((not (exists (lambda (s) (or (memq s variables) (eq? s '...)))
                        (symbols-in parameters)))
           (and (types-shaped? parameters) (list 'types parameters)))
          ((and (= (length parameters) 2)
                (symbol? (car parameters))
                (memq (car parameters) variables)
                (eq? (cadr parameters) '...))
           (let ((index (fixed-index pattern parameters)))
             (and index (list 'at index))))
          (else #f)))

  ;; result-reading : Pair Any (Listof Symbol)
  ;;                  -> (U (List 'type Any) (List 'at Natural) #f)
  ;; Where a use's result type comes from: RESULT, a template's result
  ;; holding no pattern variable, is the type itself; one that is a pattern
  ;; variable stands for the use's element at the place PATTERN holds it,
  ;; when that place is fixed. Anything else is #f.
  (define (result-reading pattern result variables)
    (cond ((not (exists (lambda (s) (or (memq s variables) (eq? s '...)))
                        (symbols-in result)))
           (and (type-shaped? result) (list 'type result)))
          ((and (symbol? result) (memq result variables))
           (let ((index (fixed-index pattern result)))
             (and index (list 'at index))))
          (else #f)))

  ;; read-wrapper : Pair -> (U (List 'ok Pair Natural (Listof Convention) Reading Reading)
  ;;                           (List 'conventions-from-pattern Pair (Listof Any))
  ;;                           (List 'unreadable String (U Pair #f)))
  ;; A known wrapper's definition: its foreign-procedure form, the index of
  ;; the entry in a use, its conventions, and where a use's parameter types
  ;; and result come from (parameters-reading, result-reading). Or why it
  ;; cannot be read, and its one foreign-procedure form when there is one,
  ;; which the reason covers.
  (define (read-wrapper form)
    (let ((rules (and (list? form) (= (length form) 3) (caddr form))))
      (if (not (one-clause-rules? rules))
          (list 'unreadable not-syntax-rules #f)
          (let* ((literals (cadr rules))
                 (pattern (car (caddr rules)))
                 (template (cadr (caddr rules)))
                 (heads (procedure-heads template)))
            (cond
              ((null? heads) (list 'unreadable no-binding #f))
              ((pair? (cdr heads)) (list 'unreadable many-bindings #f))
              (else
               (let* ((fp (car heads))
                      (parts (procedure-parts fp)))
                 (if (not parts)
                     (list 'unreadable malformed-binding #f)
                     (let* ((variables (pattern-variables pattern literals))
                            (index (entry-index pattern (cadr parts) variables)))
                       (cond
                         ((not index) (list 'unreadable unplaced-entry fp))
                         ((exists (lambda (s) (or (memq s variables) (eq? s '...)))
                                  (symbols-in (car parts)))
                          (list 'conventions-from-pattern fp (car parts)))
                         (else
                          (let ((reading (parameters-reading pattern (caddr parts) variables))
                                (result (result-reading pattern (cadddr parts) variables)))
                            (cond ((not reading) (list 'unreadable unplaced-parameters fp))
                                  ((not result) (list 'unreadable unplaced-result fp))
                                  ((pattern-takes-apart? pattern reading)
                                   (list 'unreadable takes-apart fp))
                                  (else (list 'ok fp index (car parts) reading result)))))))))))))))

  ;; --- the walk --------------------------------------------------------------------

  ;; A Finding is one of
  ;;   (binding KEY CONVENTIONS FILE VIA CROSSINGS)
  ;;   (violation VIOLATION)
  ;;   (use NAME FILE FORM)                  a known wrapper's use, read later
  ;;   (wrapper NAME FILE (U (List INDEX CONVENTIONS READING RESULT) #f))
  ;;                                         a definition; #f when unreadable

  ;; take-apart-names : (Listof Symbol)
  ;; The (rnrs) names a transformer takes a syntax object apart, or builds
  ;; one from data, with. A plain macro's definition holds none.
  (define take-apart-names '(syntax-case with-syntax syntax->datum datum->syntax))

  ;; distinct : (Listof Any) -> (Listof Any)
  ;; LST without repeats, each where it first stands.
  (define (distinct lst)
    (reverse (fold-left (lambda (seen x) (if (memq x seen) seen (cons x seen))) '() lst)))

  ;; forms-headed : (Listof Symbol) Any -> (Listof Pair)
  ;; Every list in X headed by one of HEADS, at any depth, in order.
  (define (forms-headed heads x)
    (cond ((pair? x)
           (append (if (memq (car x) heads) (list x) '())
                   (forms-headed heads (car x))
                   (forms-headed heads (cdr x))))
          ((vector? x) (forms-headed heads (vector->list x)))
          (else '())))

  ;; flat-pattern? : Any Symbol -> Boolean
  ;; PATTERN takes no operand apart: a syntax-rules clause's (_ id ...), or
  ;; identifier-syntax's (set! id id), identifiers only.
  (define (flat-pattern? pattern head)
    (and (list? pattern)
         (if (eq? head 'syntax-rules)
             (and (pair? pattern) (eq? (car pattern) '_) (for-all symbol? (cdr pattern)))
             (and (= (length pattern) 3)
                  (eq? (car pattern) 'set!)
                  (for-all symbol? (cdr pattern))))))

  ;; clause-patterns : Pair -> (Listof Any)
  ;; The patterns of a syntax-rules or identifier-syntax FORM: each clause's
  ;; head after syntax-rules' literals, and identifier-syntax's set! clause.
  (define (clause-patterns form)
    (if (eq? (car form) 'syntax-rules)
        (if (pair? (cdr form)) (map car (filter pair? (elements (cddr form)))) '())
        (map car (filter (lambda (clause) (and (pair? clause) (pair? (car clause))))
                         (elements (cdr form))))))

  ;; unflat-patterns : Any -> (Listof Any)
  ;; Every pattern in X that takes an operand apart.
  (define (unflat-patterns x)
    (fold-left (lambda (found form)
                 (append found
                         (filter (lambda (pattern) (not (flat-pattern? pattern (car form))))
                                 (clause-patterns form))))
               '() (forms-headed '(syntax-rules identifier-syntax) x)))

  ;; pattern-transformer? : Any -> Boolean
  ;; RHS, a define-syntax's transformer, is pattern-based: a syntax-rules
  ;; or identifier-syntax form. Any other is procedural.
  (define (pattern-transformer? rhs)
    (and (pair? rhs) (memq (car rhs) '(syntax-rules identifier-syntax)) #t))

  ;; lambda-transformer-input : Any -> (U Symbol #f)
  ;; ID, when RHS is exactly (lambda (ID) BODY ...): one identifier
  ;; parameter, no rest, and a body.
  (define (lambda-transformer-input rhs)
    (and (list? rhs)
         (>= (length rhs) 3)
         (eq? (car rhs) 'lambda)
         (list? (cadr rhs))
         (= (length (cadr rhs)) 1)
         (symbol? (car (cadr rhs)))
         (car (cadr rhs))))

  ;; input-leaks : Symbol Any -> (Listof Any)
  ;; The forms in X where ID stands other than as the last argument of a
  ;; syntax-violation call: each the list, vector or box holding it. In data,
  ;; what quote, quasiquote, syntax and quasisyntax hold, no place is
  ;; allowed. A rebinding of ID is a place too, so shadowing it is named.
  (define (input-leaks id x)
    (let walk ((x x) (data? #f))
      (cond
        ((pair? x)
         (let* ((data? (or data? (and (memq (car x) '(quote quasiquote syntax quasisyntax)) #t)))
                (reported? (and (not data?) (eq? (car x) 'syntax-violation) (list? x))))
           (let loop ((rest x) (found '()))
             (cond ((pair? rest)
                    (loop (cdr rest)
                          (append found
                                  (cond ((not (eq? (car rest) id)) (walk (car rest) data?))
                                        ((and reported? (null? (cdr rest)) (not (eq? rest x))) '())
                                        (else (list x))))))
                   ((null? rest) found)
                   ((eq? rest id) (append found (list x)))
                   (else (append found (walk rest data?)))))))
        ((vector? x)
         (fold-left (lambda (found e)
                      (append found (if (eq? e id) (list x) (walk e #t))))
                    '() (vector->list x)))
        ((box? x) (if (eq? (unbox x) id) (list x) (walk (unbox x) #t)))
        (else '()))))

  ;; tail-raises : Any -> (Listof Pair)
  ;; The syntax-violation calls in tail position of FORM, itself in tail
  ;; position of a transformer's body: reached through if's branches, the
  ;; last form of cond's and case's clauses (no =>), and the last form of
  ;; when, unless, begin, and, or and the let forms. A handler a transformer
  ;; sets up, by guard or with-exception-handler, never surrounds one, so
  ;; the condition, which holds the input, goes to the expander alone.
  (define (tail-raises form)
    (define (last-of forms)
      (if (pair? forms) (tail-raises (list-ref forms (- (length forms) 1))) '()))
    (define (clauses-of clauses)
      (fold-left (lambda (found clause)
                   (append found
                           (if (and (list? clause) (>= (length clause) 2)
                                    (not (eq? (cadr clause) '=>)))
                               (last-of (cdr clause))
                               '())))
                 '() clauses))
    (if (not (and (list? form) (pair? form)))
        '()
        (let ((n (length form)))
          (case (car form)
            ((syntax-violation) (list form))
            ((if) (append (if (>= n 3) (tail-raises (caddr form)) '())
                          (if (>= n 4) (tail-raises (cadddr form)) '())))
            ((cond) (clauses-of (cdr form)))
            ((case) (if (>= n 2) (clauses-of (cddr form)) '()))
            ((when unless) (if (>= n 3) (last-of (cddr form)) '()))
            ((begin and or) (last-of (cdr form)))
            ((let) (cond ((and (>= n 4) (symbol? (cadr form))) (last-of (cdddr form)))
                         ((>= n 3) (last-of (cddr form)))
                         (else '())))
            ((let* letrec letrec* let-values let*-values) (if (>= n 3) (last-of (cddr form)) '()))
            (else '())))))

  ;; raise-places : Any (Listof Pair) -> (Listof Any)
  ;; The places in X where syntax-violation stands other than at the head of
  ;; one of TAILS: a binding of the name, a call elsewhere, data.
  (define (raise-places x tails)
    (cond
      ((pair? x)
       (let loop ((rest x) (found '()))
         (cond ((pair? rest)
                (loop (cdr rest)
                      (append found
                              (cond ((not (eq? (car rest) 'syntax-violation)) (raise-places (car rest) tails))
                                    ((and (eq? rest x) (memq x tails)) '())
                                    (else (list x))))))
               ((null? rest) found)
               ((eq? rest 'syntax-violation) (append found (list x)))
               (else (append found (raise-places rest tails))))))
      ((vector? x)
       (fold-left (lambda (found e)
                    (append found (if (eq? e 'syntax-violation) (list x) (raise-places e tails))))
                  '() (vector->list x)))
      ((box? x) (if (eq? (unbox x) 'syntax-violation) (list x) (raise-places (unbox x) tails)))
      (else '())))

  ;; whole-rnrs : (Listof Any)
  ;; The import specs that bring (rnrs)'s syntax-violation in unwrapped.
  ;; With one, Chez refuses any other binding of the name in the library,
  ;; imported or defined: measured, "multiple definitions for
  ;; syntax-violation".
  (define whole-rnrs '((rnrs) (rnrs syntax-case)))

  ;; plain-imports? : (Listof Any) -> Boolean
  ;; IMPORTS, a library's import specs, let a procedural plain macro there
  ;; reach no procedure of another library: each is a whole (rnrs ...)
  ;; library but (rnrs eval), or (only (chezscheme) name ...), whose names
  ;; check-seam holds to its allowlist; and (rnrs) or (rnrs syntax-case) is
  ;; among them, unwrapped. A procedure another library exports could take
  ;; the input apart, or build a binding from strings with datum->syntax,
  ;; where no rule reads it: measured, both bound the entry it chose.
  (define (plain-imports? imports)
    (and (for-all (lambda (spec)
                    (or (and (list? spec) (pair? spec) (eq? (car spec) 'rnrs)
                             (for-all symbol? spec)
                             (not (equal? spec '(rnrs eval))))
                        (chez-only? spec)))
                  imports)
         (exists (lambda (spec) (member spec whole-rnrs)) imports)
         #t))

  ;; pattern-heads : (Listof Symbol) Any -> (Listof Pair)
  ;; Every form in X whose head is one of VARS, a macro's pattern variables,
  ;; at any depth, data included, in order. A foreign-procedure form's
  ;; parameter list is types, which Chez never evaluates, so it is skipped:
  ;; a binder's (arg ...) there is no form.
  (define (pattern-heads vars x)
    (cond
      ((pair? x)
       (let ((types (and (eq? (car x) 'foreign-procedure) (list? x) (>= (length x) 4)
                         (list? (list-ref x (- (length x) 2)))
                         (list-ref x (- (length x) 2)))))
         (append (if (and (symbol? (car x)) (memq (car x) vars)) (list x) '())
                 (let loop ((rest x) (found '()))
                   (if (pair? rest)
                       (loop (cdr rest)
                             (append found (if (and types (eq? (car rest) types))
                                               '()
                                               (pattern-heads vars (car rest)))))
                       found)))))
      ((vector? x) (fold-left (lambda (found e) (append found (pattern-heads vars e)))
                              '() (vector->list x)))
      (else '())))

  ;; template-heads : Any -> (Listof Pair)
  ;; The forms in FORM's templates, each a syntax-rules clause's or
  ;; identifier-syntax's set! clause's, headed by one of that clause's
  ;; pattern variables: there a use can hand in any keyword, define-syntax,
  ;; import or another, and the macro writes the form it heads.
  (define (template-heads form)
    (append
     (fold-left
      (lambda (found rules)
        (let ((literals (if (and (pair? (cdr rules)) (list? (cadr rules))) (cadr rules) '())))
          (append found
                  (if (pair? (cdr rules))
                      (fold-left (lambda (found clause)
                                   (append found
                                           (if (and (list? clause) (= (length clause) 2) (pair? (car clause)))
                                               (pattern-heads (pattern-variables (car clause) literals)
                                                              (cadr clause))
                                               '())))
                                 '() (elements (cddr rules)))
                      '()))))
      '() (forms-headed '(syntax-rules) form))
     (fold-left
      (lambda (found syntax)
        (append found
                (fold-left (lambda (found clause)
                             (append found
                                     (if (and (list? clause) (= (length clause) 2) (pair? (car clause)))
                                         (pattern-heads (filter (lambda (s) (not (memq s '(set! _ ...))))
                                                                (symbols-in (car clause)))
                                                        (cadr clause))
                                         '())))
                           '() (elements (cdr syntax)))))
      '() (forms-headed '(identifier-syntax) form))))

  ;; macro-row : (Listof Any) Symbol -> (U (List Symbol Symbol String) #f)
  ;; NAME's row in MACROS, when it is (NAME KIND FILE).
  (define (macro-row macros name)
    (find (lambda (row)
            (and (list? row) (= (length row) 3) (eq? (car row) name)
                 (symbol? (cadr row)) (string? (caddr row))))
          macros))

  ;; datum-findings : String String String Any (Listof Symbol) (Listof Symbol) Table
  ;;                  -> (Listof Finding)
  ;; What one datum of the file PATH holds, in the order written. PATH is
  ;; ROOT joined to REL. FTYPES are the names layouts defines; MACROS is the
  ;; table of the macros the tree may define.
  (define (datum-findings root path rel datum wrappers ftypes macros)
    (let ((shared (shared-part datum))
          (found '())
          (accounted '())
          (bound '())
          (in-macro? #f)
          (top-form #f)
          (imports '()))

      (define (emit! finding) (set! found (cons finding found)))

      ;; binding-name? : Any -> Boolean
      ;; X binds an entry point: foreign-procedure, foreign-callable, or a
      ;; known wrapper's name.
      (define (binding-name? x) (or (occurrence? x) (and (memq x wrappers) #t)))

      ;; name? : Any -> Boolean
      ;; X is an occurrence the reader must account for: a binding name, or
      ;; one of macro-keywords.
      (define (name? x) (or (binding-name? x) (and (memq x macro-keywords) #t)))

      ;; within-macro : (-> Unit) -> Unit
      ;; THUNK, run with in-macro? set: inside one of template-forms.
      (define (within-macro thunk)
        (let ((outer in-macro?))
          (set! in-macro? #t)
          (thunk)
          (set! in-macro? outer)))

      ;; from-pattern? : Any -> Boolean
      ;; X holds a pattern variable of a macro form around it.
      (define (from-pattern? x)
        (exists (lambda (s) (memq s bound)) (symbols-in x)))

      (define (violation! . v) (emit! (list 'violation v)))

      ;; walk : Any Any Boolean -> Unit
      ;; X, an element of PARENT. QUOTED? holds inside data-forms, in a
      ;; vector or box literal, and for what a binding form binds: data, not
      ;; code.
      (define (walk x parent quoted?)
        (cond ((name? x) (violation! 'stray path (abbreviated parent)))
              ((pair? x) (walk-pair x quoted?))
              ((vector? x) (for-each (lambda (e) (walk e x #t)) (vector->list x)))
              ((box? x) (walk (unbox x) x #t))
              (else #f)))

      ;; walk-elements : Pair Natural Boolean -> Unit
      ;; FORM's elements from index START, and an improper tail.
      (define (walk-elements form start quoted?)
        (let loop ((rest form) (i 0))
          (cond ((pair? rest)
                 (when (>= i start) (walk (car rest) form quoted?))
                 (loop (cdr rest) (+ i 1)))
                ((null? rest) #f)
                (else (walk rest form quoted?)))))

      ;; A known wrapper's name is a use only at a head outside every one of
      ;; template-forms; anywhere else walk finds it, and it is stray.
      (define (walk-pair form quoted?)
        (let ((head (car form)))
          (when (and (not quoted?) in-macro? (memq head macro-keywords))
            (violation! 'stray path (abbreviated form)))
          (unless quoted? (placement! form))
          (cond
            (quoted? (walk-elements form 0 #t))
            ((memq head data-forms) (walk-elements form 0 #t))
            ((memq form accounted) (walk-elements form 1 #f))
            ((eq? head 'foreign-procedure)
             (procedure-form! form)
             (walk-elements form 1 #f))
            ((eq? head 'foreign-callable)
             (violation! 'callable-not-defined path (abbreviated form))
             (walk-elements form 1 #f))
            ((callable-definition? form) (callable-definition! form))
            ((and (eq? head 'define-syntax) (pair? (cdr form)) (memq (cadr form) wrappers))
             (wrapper-definition! form))
            ((and (memq head wrappers) (not in-macro?))
             (emit! (list 'use head path form))
             (walk-elements form 1 #f))
            ((memq head template-forms)
             (let ((outer bound))
               (when (memq head macro-forms)
                 (set! bound (append (macro-variables form) bound)))
               (within-macro (lambda () (walk-elements form 1 #f)))
               (set! bound outer)))
            ((and (eq? head 'case) (list? form) (>= (length form) 2))
             (case-form! form))
            ((binding-form! form))
            (else (walk-elements form 0 #f)))))

      ;; placement! : Pair -> Unit
      ;; A define-syntax anywhere but a library body's top level, by name, is
      ;; named; so is every let-syntax and letrec-syntax.
      (define (placement! form)
        (case (car form)
          ((define-syntax)
           (unless (eq? form top-form) (violation! 'macro-nested path (abbreviated form))))
          ((let-syntax letrec-syntax) (violation! 'macro-local path (abbreviated form)))
          (else #f)))

      ;; top-macro! : Pair -> Unit
      ;; FORM, (define-syntax NAME ...) at a library body's top level, held
      ;; to its row in MACROS: listed, defined in its file, and, unless a
      ;; binder or any, held as plain.
      (define (top-macro! form)
        (let* ((name (cadr form)) (row (macro-row macros name)))
          (emit! (list 'macro name rel))
          (cond
            ((not row) (violation! 'macro-unlisted path name))
            (else
             (unless (string=? (caddr row) rel)
               (violation! 'macro-elsewhere path name (string-append root "/" (caddr row))))
             (unless (memq (cadr row) '(binder any))
               (plain! form name))
             (unless (eq? (cadr row) 'any)
               (for-each (lambda (place) (violation! 'macro-pattern-head path name (abbreviated place)))
                         (template-heads form)))))))

      ;; plain! : Pair Symbol -> Unit
      ;; A plain macro's definition builds no binding and takes no operand
      ;; apart: it holds no name that binds, none of take-apart-names, and
      ;; no pattern but a flat one. A procedural one is exactly
      ;; (lambda (ID) BODY ...), and its input goes nowhere but to
      ;; syntax-violation, so its output cannot depend on it.
      (define (plain! form name)
        (let ((symbols (distinct (symbols-in form)))
              (rhs (and (list? form) (= (length form) 3) (caddr form))))
          (for-each (lambda (s) (when (binding-name? s) (violation! 'plain-macro-binds path name s)))
                    symbols)
          (for-each (lambda (s)
                      (when (memq s take-apart-names) (violation! 'plain-macro-takes-apart path name s)))
                    symbols)
          (for-each (lambda (pattern) (violation! 'plain-macro-pattern path name (abbreviated pattern)))
                    (unflat-patterns form))
          (unless (pattern-transformer? rhs)
            (let ((id (lambda-transformer-input rhs)))
              (if (not id)
                  (violation! 'plain-macro-transformer path name (abbreviated rhs))
                  (let* ((body (cddr rhs))
                         (tails (tail-raises (list-ref body (- (length body) 1)))))
                    (unless (plain-imports? imports)
                      (violation! 'plain-macro-import path name))
                    (for-each (lambda (place) (violation! 'plain-macro-input path name (abbreviated place)))
                              (fold-left (lambda (found form)
                                           (append found (if (eq? form id) (list rhs) (input-leaks id form))))
                                         '() body))
                    (for-each (lambda (place) (violation! 'plain-macro-raise path name (abbreviated place)))
                              (raise-places body tails))))))))

      ;; case-form! : Pair -> Unit
      ;; (case KEY (DATUMS EXPR ...) ...): the key and each clause's
      ;; expressions are code, and each DATUMS data, which Chez compares the
      ;; key with and never evaluates.
      (define (case-form! form)
        (walk (cadr form) form #f)
        (for-each (lambda (clause)
                    (cond ((not (pair? clause)) (walk clause form #f))
                          (else
                           (unless (eq? (car clause) 'else) (walk (car clause) clause #t))
                           (walk-elements clause 1 #f))))
                  (cddr form)))

      ;; names! : Any Any -> Unit
      ;; X, part of PARENT, names what a binding form binds, so it is data:
      ;; every occurrence in it is stray, and no form in it is read.
      (define (names! x parent) (walk x parent #t))

      ;; bindings! : Any Any -> Unit
      ;; ((NAMES EXPR ...) ...), part of PARENT: each NAMES as names!, the
      ;; rest as code. Anything else is data.
      (define (bindings! bindings parent)
        (if (list? bindings)
            (for-each (lambda (binding)
                        (if (pair? binding)
                            (begin (names! (car binding) binding)
                                   (walk-elements binding 1 #f))
                            (names! binding bindings)))
                      bindings)
            (names! bindings parent)))

      ;; binding-form! : Pair -> Boolean
      ;; FORM, when it is a binding form of a shape the reader knows: what
      ;; it binds read by names!, the rest as code; #t. #f for any other
      ;; form, which walk-pair reads whole as code.
      (define (binding-form! form)
        (let ((n (if (list? form) (length form) 0)))
          (case (car form)
            ((define define-values lambda)
             (and (>= n 2)
                  (begin (names! (cadr form) form) (walk-elements form 2 #f) #t)))
            ((case-lambda)
             (and (>= n 1)
                  (begin (for-each (lambda (clause)
                                     (if (pair? clause)
                                         (begin (names! (car clause) clause)
                                                (walk-elements clause 1 #f))
                                         (names! clause form)))
                                   (cdr form))
                         #t)))
            ((let)
             (cond ((and (>= n 3) (symbol? (cadr form)))
                    (names! (cadr form) form)
                    (bindings! (caddr form) form)
                    (walk-elements form 3 #f)
                    #t)
                   ((>= n 2) (bindings! (cadr form) form) (walk-elements form 2 #f) #t)
                   (else #f)))
            ((let* letrec letrec* let-values let*-values fluid-let do)
             (and (>= n 2)
                  (begin (bindings! (cadr form) form) (walk-elements form 2 #f) #t)))
            ((guard)
             (and (>= n 2)
                  (pair? (cadr form))
                  (begin (names! (car (cadr form)) (cadr form))
                         (walk-elements (cadr form) 1 #f)
                         (walk-elements form 2 #f)
                         #t)))
            (else #f))))

      (define (procedure-form! form)
        (let ((parts (procedure-parts form)))
          (cond ((not parts) (violation! 'malformed path (abbreviated form)))
                ((not (string? (cadr parts)))
                 (violation! 'entry-not-string path (abbreviated form)))
                ((from-pattern? (car parts))
                 (violation! 'conventions-from-pattern path (abbreviated form)))
                ((from-pattern? (cddr parts))
                 (violation! 'types-unreadable path (abbreviated form)))
                (else
                 (let ((crossings (signature-crossings (caddr parts) (cadddr parts) ftypes #f)))
                   (if (eq? crossings 'unreadable)
                       (violation! 'types-unreadable path (abbreviated form))
                       (emit! (list 'binding (cadr parts) (car parts) path 'foreign-procedure
                                    crossings (caddr parts) (cadddr parts)))))))))

      ;; A callable's result is what it hands C; its parameters it is handed.
      ;; A type it cannot read names the define, so the binding.
      (define (callable-definition! form)
        (let ((name (cadr form)) (callable (caddr form)))
          (walk name form #f)
          (let ((parts (procedure-parts callable)))
            (cond ((not parts) (violation! 'malformed path (abbreviated callable)))
                  ((from-pattern? (car parts))
                   (violation! 'conventions-from-pattern path (abbreviated form)))
                  ((from-pattern? (cddr parts))
                   (violation! 'types-unreadable path (abbreviated form)))
                  (else
                   (let ((crossings (signature-crossings (caddr parts) (cadddr parts) ftypes #t)))
                     (if (eq? crossings 'unreadable)
                         (violation! 'types-unreadable path (abbreviated form))
                         (emit! (list 'binding name (car parts) path 'foreign-callable
                                      crossings (caddr parts) (cadddr parts))))))))
          (walk-elements callable 1 #f)))

      (define (wrapper-definition! form)
        (let ((name (cadr form)) (reading (read-wrapper form)))
          (case (car reading)
            ((ok)
             (emit! (list 'wrapper name path (cddr reading)))
             (set! accounted (cons (cadr reading) accounted)))
            ((conventions-from-pattern)
             (emit! (list 'wrapper name path #f))
             (violation! 'wrapper-conventions-from-pattern path name (caddr reading))
             (set! accounted (cons (cadr reading) accounted)))
            (else
             (emit! (list 'wrapper name path #f))
             (violation! 'wrapper-unreadable path name (cadr reading))
             (when (caddr reading)
               (set! accounted (cons (caddr reading) accounted)))))
          ;; The name is the one place a wrapper's name stands for itself.
          (within-macro (lambda () (walk-elements form 2 #f)))))

      ;; The name, export and import clauses are data. In the import clause,
      ;; an (only (chezscheme) ...) accounts for foreign-procedure and
      ;; foreign-callable, and for no known wrapper's name. The body is code.
      (define (walk-library form)
        (set! imports (cdr (cadddr form)))
        (walk (cadr form) form #t)
        (walk (caddr form) form #t)
        (for-each (lambda (spec)
                    (if (chez-only? spec)
                        (for-each (lambda (id) (unless (occurrence? id) (walk id spec #t)))
                                  (cddr spec))
                        (walk spec (cadddr form) #t)))
                  (cdr (cadddr form)))
        (for-each (lambda (body)
                    (when (and (pair? body) (eq? (car body) 'define-syntax)
                               (pair? (cdr body)) (symbol? (cadr body)))
                      (set! top-form body)
                      (top-macro! body))
                    (walk body form #f)
                    (set! top-form #f))
                  (cddddr form)))

      (cond (shared (violation! 'shared-structure path (abbreviated shared)))
            ((library-form? datum) (walk-library datum))
            (else (walk datum datum #f)))
      (reverse found)))

  ;; file-findings : String String (Listof Symbol) (Listof Symbol) Table -> (Listof Finding)
  ;; PATH is ROOT joined to the names below it.
  (define (file-findings root path wrappers ftypes macros)
    (let ((data (read-data path))
          (rel (substring path (+ (string-length root) 1) (string-length path))))
      (if (eq? (car data) 'unreadable)
          (list (list 'violation (list 'unreadable path (cadr data))))
          (fold-left (lambda (found datum)
                       (append found (datum-findings root path rel datum wrappers ftypes macros)))
                     '() (cadr data)))))

  ;; use-types : Pair (U (List 'types (Listof Any)) (List 'at Natural)) -> Any
  ;; A use's parameter types, as its wrapper's reading finds them; #f when
  ;; the use is too short to hold them.
  (define (use-types form reading)
    (if (eq? (car reading) 'types)
        (cadr reading)
        (and (> (length form) (cadr reading)) (list-ref form (cadr reading)))))

  ;; use-result : Pair (U (List 'type Any) (List 'at Natural)) -> Any
  ;; A use's result type, likewise; #f, on no allowlist, when the use is too
  ;; short to hold it.
  (define (use-result form reading)
    (if (eq? (car reading) 'type)
        (cadr reading)
        (and (> (length form) (cadr reading)) (list-ref form (cadr reading)))))

  ;; use-crossings : Pair Reading Reading (Listof Symbol)
  ;;                 -> (U (Listof Symbol) 'unreadable)
  ;; A use's crossings, or 'unreadable when its types are no list or on no
  ;; allowlist. A type its wrapper's template writes is the template's own.
  ;; A use is never inside a macro, so no type it writes is a pattern
  ;; variable.
  (define (use-crossings form reading result ftypes)
    (let ((types (use-types form reading)))
      (if (list? types)
          (signature-crossings types (use-result form result) ftypes #f)
          'unreadable)))

  ;; resolve : (Listof Finding) (Listof Symbol)
  ;;           -> (List (Listof Binding) (Listof Violation) (Listof Symbol))
  ;; Each use read against its wrapper's one definition, in place. A use with
  ;; no definition is named. A wrapper defined twice is named at its second
  ;; definition, and none of its uses is read; nor is a use of a wrapper
  ;; whose definition was unreadable, which is named already.
  (define (resolve findings ftypes)
    (let ((definitions (filter (lambda (f) (eq? (car f) 'wrapper)) findings)))
      (define (definitions-of name)
        (filter (lambda (d) (eq? (cadr d) name)) definitions))
      (let loop ((rest findings) (bindings '()) (violations '()) (defined '()))
        (if (null? rest)
            (list (reverse bindings)
                  (reverse violations)
                  (filter (lambda (name)
                            (let ((ds (definitions-of name)))
                              (and (= (length ds) 1) (cadddr (car ds)) #t)))
                          (reverse defined)))
            (let ((f (car rest)))
              (case (car f)
                ((binding)
                 (loop (cdr rest) (cons (cdr f) bindings) violations defined))
                ((violation)
                 (loop (cdr rest) bindings (cons (cadr f) violations) defined))
                ((wrapper)
                 (if (memq (cadr f) defined)
                     (loop (cdr rest) bindings
                           (cons (list 'wrapper-defined-again (caddr f) (cadr f)) violations)
                           defined)
                     (loop (cdr rest) bindings violations (cons (cadr f) defined))))
                (else
                 (let ((name (cadr f)) (file (caddr f)) (form (cadddr f))
                       (ds (definitions-of (cadr f))))
                   (cond
                     ((null? ds)
                      (loop (cdr rest) bindings
                            (cons (list 'wrapper-undefined file name (abbreviated form)) violations)
                            defined))
                     ((or (pair? (cdr ds)) (not (cadddr (car ds))))
                      (loop (cdr rest) bindings violations defined))
                     (else
                      (let ((index (car (cadddr (car ds))))
                            (conventions (cadr (cadddr (car ds))))
                            (reading (caddr (cadddr (car ds))))
                            (result (cadddr (cadddr (car ds)))))
                        (cond
                          ((not (and (list? form)
                                     (> (length form) index)
                                     (string? (list-ref form index))))
                           (loop (cdr rest) bindings
                                 (cons (list 'wrapper-entry-not-string file name (abbreviated form))
                                       violations)
                                 defined))
                          ((eq? (use-crossings form reading result ftypes) 'unreadable)
                           (loop (cdr rest) bindings
                                 (cons (list 'wrapper-types-unreadable file name (abbreviated form))
                                       violations)
                                 defined))
                          (else
                           (loop (cdr rest)
                                 (cons (list (list-ref form index) conventions file name
                                             (use-crossings form reading result ftypes)
                                             (use-types form reading)
                                             (use-result form result))
                                       bindings)
                                 violations defined))))))))))))))

  ;; scan-conventions : String Macros -> Scan
  ;; Every source file under ROOT, read as data, with MACROS as the table
  ;; of the macros it may define, its binders the known wrappers, and the
  ;; ftypes ROOT's layouts defines. Files are read in sorted order, and each
  ;; one's forms in the order written, so the answer is the same on every
  ;; run.
  (define (scan-conventions root macros)
    (let* ((found (if (file-directory? root) (tree root) (list '() '())))
           (files (list-sort string<? (car found)))
           (links (list-sort string<? (cadr found)))
           (ftypes (layout-ftypes root))
           (wrappers (binders macros))
           (all (fold-left (lambda (all path)
                             (append all (file-findings root path wrappers ftypes macros)))
                           '() files))
           (findings (filter (lambda (f) (not (eq? (car f) 'macro))) all))
           (resolved (resolve findings ftypes)))
      ;; Each binding resolve answers carries its types after its five
      ;; fields: scan-bindings drops them, and scan-signatures keeps them.
      (make-scan (map (lambda (b) (list (list-ref b 0) (list-ref b 1) (list-ref b 2)
                                        (list-ref b 3) (list-ref b 4)))
                      (car resolved))
                 (append (if (null? files) (list (list 'no-sources root)) '())
                         (map (lambda (link) (list 'directory-link link)) links)
                         (cadr resolved))
                 (caddr resolved)
                 (map cdr (filter (lambda (f) (eq? (car f) 'macro)) all))
                 (map (lambda (b) (list (list-ref b 0) (list-ref b 3) (list-ref b 5)
                                        (list-ref b 6) (list-ref b 2)))
                      (car resolved)))))

  ;; --- the table's verdicts ----------------------------------------------------------

  ;; same-set? : (Listof Any) (Listof Any) -> Boolean
  (define (same-set? a b)
    (and (for-all (lambda (x) (member x b)) a)
         (for-all (lambda (x) (member x a)) b)
         #t))

  ;; mark-kinds : (Listof Symbol)
  (define mark-kinds '(bytevector-crossing string-not-kept))

  ;; mark? : Any -> Boolean
  ;; (KIND CITATION), KIND one of mark-kinds and CITATION a string; that the
  ;; citation quotes a record is table-problems' to check.
  (define (mark? x)
    (and (list? x)
         (= (length x) 2)
         (memq (car x) mark-kinds)
         (string? (cadr x))
         #t))

  ;; row-mark : Any -> (U (List Symbol String) #f)
  ;; ROW's fourth element, when it is a mark.
  (define (row-mark row)
    (and (list? row)
         (<= 4 (length row) 5)
         (mark? (cadddr row))
         (cadddr row)))

  ;; binder-tagged? : Any -> Boolean
  ;; X is (bound-by ...), whatever follows.
  (define (binder-tagged? x)
    (and (pair? x) (eq? (car x) 'bound-by)))

  ;; binder-shaped? : Any -> Boolean
  ;; X is (bound-by BINDER), BINDER a symbol.
  (define (binder-shaped? x)
    (and (binder-tagged? x) (list? x) (= (length x) 2) (symbol? (cadr x))))

  ;; row-binder : Any -> (U Symbol #f)
  ;; The BINDER of ROW's last element, when ROW has four or five and that
  ;; is (bound-by BINDER).
  (define (row-binder row)
    (and (list? row)
         (<= 4 (length row) 5)
         (let ((last (list-ref row (- (length row) 1))))
           (and (binder-shaped? last) (cadr last)))))

  ;; marked? : Any Symbol -> Boolean
  (define (marked? row kind)
    (let ((mark (row-mark row)))
      (and mark (eq? (car mark) kind))))

  ;; kind-violation : Symbol (Listof Symbol) (Listof Symbol) Boolean Any String
  ;;                  -> (Listof Violation)
  ;; (NAME KEY TYPES FILE) for the crossings of PASSED among KIND, unless
  ;; CLEARED.
  (define (kind-violation name kind passed cleared? key file)
    (let ((types (filter (lambda (type) (memq type kind)) passed)))
      (if (and (pair? types) (not cleared?))
          (list (list name key types file))
          '())))

  ;; table-violations : (Listof Binding) Table -> (Listof Violation)
  ;; Each binding against its row, found by key with equal?, so the string
  ;; "memcpy" and the symbol memcpy are two keys. Conventions are compared
  ;; as sets. A row's binder must be how the binding was made. A bytevector
  ;; crossing needs a row marked bytevector-crossing, a string one marked
  ;; string-not-kept, and scheme-object fails whatever the row.
  (define (table-violations bindings table)
    (fold-left
     (lambda (found binding)
       (let* ((key (car binding))
              (conventions (cadr binding))
              (file (caddr binding))
              (via (list-ref binding 3))
              (passed (list-ref binding 4))
              (row (find (lambda (row) (and (pair? row) (equal? (car row) key))) table))
              (binder (and row (row-binder row))))
         (append found
                 (cond ((not row) (list (list 'no-row key file)))
                       ((same-set? (cadr row) conventions) '())
                       (else (list (list 'mismatch key (cadr row) conventions file))))
                 (if (and binder (not (eq? binder via)))
                     (list (list 'wrong-binder key binder via file))
                     '())
                 (kind-violation 'bytevector-crossing bytevector-types passed
                                 (and row (marked? row 'bytevector-crossing)) key file)
                 (kind-violation 'string-crossing string-types passed
                                 (and row (marked? row 'string-not-kept)) key file)
                 (kind-violation 'scheme-object object-types passed #f key file))))
     '() bindings))

  ;; check-conventions : String Macros Table
  ;;                     -> (List (Listof Binding) (Listof Violation))
  ;; The bindings under ROOT, and every violation: the scan's, then the
  ;; table's. MACROS is the table of macros the tree may define.
  (define (check-conventions root macros table)
    (let* ((scanned (scan-conventions root macros))
           (bindings (scan-bindings scanned)))
      (list bindings
            (append (scan-violations scanned) (table-violations bindings table)))))

  ;; --- the table's own checks -----------------------------------------------------

  (define records ".plans/decisions/")

  ;; row-shaped? : Any -> Boolean
  ;; (key conventions citation), then at most two elements: a fourth, and a
  ;; fifth tagged bound-by. table-problems holds a last element tagged
  ;; bound-by to a binder's shape, and any other fourth to a mark's.
  (define (row-shaped? row)
    (and (list? row)
         (<= 3 (length row) 5)
         (or (string? (car row)) (symbol? (car row)))
         (list? (cadr row))
         (string? (caddr row))
         (or (< (length row) 5) (binder-tagged? (list-ref row 4)))))

  ;; citation-parts : String -> (U (Pair String String) #f)
  ;; "RECORD: PHRASE" as (RECORD . PHRASE); #f with no ": " or no phrase.
  (define (citation-parts citation)
    (let ((at (search citation ": ")))
      (and at
           (< (+ at 2) (string-length citation))
           (cons (substring citation 0 at)
                 (substring citation (+ at 2) (string-length citation))))))

  ;; decision-record? : String String -> Boolean
  ;; PATH names a regular file directly in .plans/decisions/, under ROOT.
  (define (decision-record? path root)
    (and (prefix? path records)
         (let ((name (substring path (string-length records) (string-length path))))
           (and (> (string-length name) 0)
                (not (memv #\/ (string->list name)))))
         (file-regular? (string-append root "/" path))))

  ;; holds-phrase? : String String -> Boolean
  (define (holds-phrase? file phrase)
    (guard (e (#t #f))
      (let ((text (call-with-port (open-file-input-port file (file-options) (buffer-mode block)
                                                        (make-transcoder (utf-8-codec)))
                    get-string-all)))
        (and (string? text) (search (squeezed text) (squeezed phrase)) #t))))

  ;; citation-problems : (U String Symbol) String String (List Symbol Symbol Symbol)
  ;;                     -> (Listof Violation)
  ;; CITATION's fault, if any, named by KINDS: its shape, its record, its
  ;; phrase.
  (define (citation-problems key citation root kinds)
    (let ((parts (citation-parts citation)))
      (cond
        ((not parts) (list (list (car kinds) key citation)))
        ((not (decision-record? (car parts) root))
         (list (list (cadr kinds) key (car parts))))
        ((not (holds-phrase? (string-append root "/" (car parts)) (cdr parts)))
         (list (list (caddr kinds) key (car parts) (cdr parts))))
        (else '()))))

  (define row-citation '(citation-shape citation-not-a-record citation-phrase-missing))
  (define mark-citation
    '(crossing-citation-shape crossing-citation-not-a-record crossing-citation-phrase-missing))

  ;; extra-problems : Row String -> (Listof Violation)
  ;; What follows a shaped row's citation: a binder, when the last element
  ;; is tagged bound-by, and a mark, when anything precedes it. The mark's
  ;; shape, its citation, and its row's conventions, which may not be
  ;; __collect_safe; then the binder's shape.
  (define (extra-problems row root)
    (let* ((extras (cdddr row))
           (last (and (pair? extras) (list-ref extras (- (length extras) 1))))
           (binder (and last (binder-tagged? last) last))
           (marks (if binder (filter (lambda (x) (not (eq? x binder))) extras) extras)))
      (append
       (cond
         ((null? marks) '())
         ((not (mark? (car marks))) (list (list 'crossing-mark-shape (car row) (car marks))))
         (else
          (append (citation-problems (car row) (cadr (car marks)) root mark-citation)
                  (if (member '__collect_safe (cadr row))
                      (list (list 'crossing-collect-safe (car row)))
                      '()))))
       (if (and binder (not (binder-shaped? binder)))
           (list (list 'binder-shape (car row) binder))
           '()))))

  ;; table-problems : Table String -> (Listof Violation)
  ;; What is wrong with TABLE, whose citations are paths under ROOT, in row
  ;; order:
  ;;   (row-shape ROW)                          not (key conventions citation),
  ;;                                            then a fourth element, a fifth
  ;;                                            tagged bound-by, or neither
  ;;   (duplicate-row KEY)                      a second row for KEY
  ;;   (citation-shape KEY CITATION)            not "RECORD: PHRASE"
  ;;   (citation-not-a-record KEY RECORD)       no file in .plans/decisions/
  ;;   (citation-phrase-missing KEY RECORD PHRASE)
  ;;   (crossing-mark-shape KEY MARK)           a fourth element that is not
  ;;                                            (bytevector-crossing CITATION)
  ;;                                            nor (string-not-kept CITATION)
  ;;   (crossing-citation-shape KEY CITATION)   the mark's citation, as above
  ;;   (crossing-citation-not-a-record KEY RECORD)
  ;;   (crossing-citation-phrase-missing KEY RECORD PHRASE)
  ;;   (crossing-collect-safe KEY)              a marked row __collect_safe
  ;;   (binder-shape KEY BINDER)                a last element tagged bound-by
  ;;                                            that is not (bound-by SYMBOL)
  (define (table-problems table root)
    (let loop ((rows table) (keys '()) (found '()))
      (if (null? rows)
          found
          (let ((row (car rows)))
            (cond
              ((not (row-shaped? row))
               (loop (cdr rows) keys (append found (list (list 'row-shape row)))))
              ((member (car row) keys)
               (loop (cdr rows) keys (append found (list (list 'duplicate-row (car row))))))
              (else
               (loop (cdr rows) (cons (car row) keys)
                     (append found
                             (citation-problems (car row) (caddr row) root row-citation)
                             (extra-problems row root))))))))))
