#!r6rs
;;; (foreign-conventions): the calling conventions chez-curl's foreign
;;; procedures and callables must carry, and a reader that finds the ones
;;; they do carry (ADR-0013, harness plan §3 item 3). Test-only: it lives in
;;; tests/, and tests/test-collect-safe.sps is its suite.
;;;
;;;   conventions-table   one row per C entry point or callable: its key,
;;;                       its required conventions, and a citation
;;;   known-wrappers      the macros whose template binds an entry point
;;;   scan-conventions    every binding under a directory, read as data, and
;;;                       every occurrence the reader cannot account for
;;;   table-violations    each binding held against the table
;;;   check-conventions   both: what a suite asserts
;;;   table-problems      the table's own shape, and its citations checked
;;;                       against the decision records
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
;;; Anything else is a violation naming the file and the form: a quoted
;;; occurrence among them, since quote and quasiquote (unquote included) and
;;; vector and box literals are data. So is a file it cannot read, a datum
;;; with shared structure (which it does not walk), a symbolic link to a
;;; directory (which it does not follow), and a directory with no source
;;; file. A source file is one Chez could load a library from, by the source
;;; endings of (library-extensions); a dangling symbolic link named .#..., an
;;; Emacs lock file, is skipped.
;;;
;;; Its limit: a name built at expansion time, by string->symbol or
;;; datum->syntax, is out of any reader's reach. check-seam keeps those out
;;; of src/ by admitting only the (chezscheme) names on its allowlist.
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
;;; patterns is a pattern variable, and a binding's type (or a wrapper
;;; use's) that is one is unreadable; a convention that is one is
;;; conventions-from-pattern. The reader reads the types of
;;; direct forms, and of a known wrapper's uses: a template's parameter
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
;;;   (types-unreadable FILE FORM)           a type it cannot read, or one on
;;;                                          no allowlist; FORM is a callable's
;;;                                          define
;;;   (wrapper-types-unreadable FILE NAME FORM)
;;;   (conventions-from-pattern FILE FORM)   a convention that is a macro's
;;;                                          pattern variable
;;;   (no-row KEY FILE)                      a binding the table lacks
;;;   (mismatch KEY EXPECTED ACTUAL FILE)    conventions that differ, as sets
;;;   (bytevector-crossing KEY TYPES FILE)   bytevector crossings its row does
;;;                                          not mark
;;;   (string-crossing KEY TYPES FILE)       string crossings its row does not
;;;                                          mark string-not-kept
;;;   (scheme-object KEY TYPES FILE)         scheme-object, marked or not
;;;
;;; A FORM is the datum written, cut to 100 characters. Paths are ROOT
;;; joined to the names below it.
(library (foreign-conventions)
  (export conventions-table known-wrappers
          scan-conventions scan? scan-bindings scan-violations scan-wrappers
          table-violations check-conventions table-problems)
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
  (define can-block (cite adr-0013 "Known now: `curl_multi_poll` and `curl_easy_perform`."))
  (define multi-perform-plain
    (cite adr-0013 "It covers `curl_multi_perform` too, which curl documents as non-blocking, until E1 says otherwise."))
  ;; curl_easy_cleanup is bound plain for the load's header probe, which
  ;; cleans up a fresh handle that never made a connection. Whether cleanup
  ;; can block is E1's to settle (M3).
  (define cleanup-open
    (cite adr-0013 "E1 classifies the rest, starting with the cleanup paths `CURLOPT_QUICK_EXIT` describes: `curl_multi_remove_handle` and `curl_easy_cleanup`."))
  (define memcpy-plain
    (cite adr-0001 "Bulk byte moves use libc's `memcpy`, bound directly, as a plain call."))
  (define name-not-kept
    (cite adr-0013 "`curl_easy_option_by_name` and `curl_easy_header` read their name argument during the call, and keep no pointer to it."))

  ;; conventions-table : (Listof Row)
  ;; A Row is (List (U String Symbol) (Listof Convention) String), or that
  ;; and a fourth element, a Mark: (bytevector-crossing CITATION) or
  ;; (string-not-kept CITATION).
  ;; One row per C entry point, keyed by its name, a string, or per
  ;; callable, keyed by the name it is defined as, a symbol. A convention is
  ;; a symbol, __collect_safe, or a list, (__varargs_after 2). Rows for
  ;; entries not bound yet hold M2 to ADR-0013 the moment it binds them.
  ;; ADR-0013 is Proposed: spike E1 (M3) may move a row.
  ;;
  ;; A mark clears the row's bindings of one kind of crossing: a
  ;; bytevector's data, or a string its callee keeps no pointer to. Its
  ;; citation quotes a decision record, checked as the row's own is, and a
  ;; marked row is never __collect_safe (ADR-0013's decision 4). A row has
  ;; one mark at most. Two rows are marked string-not-kept; M2's checked
  ;; wrapper adds the first bytevector-crossing.
  (define conventions-table
    (list (list "curl_version_info" '() cannot-block)
          (list "curl_global_init" '() cannot-block)
          (list "curl_easy_option_by_name" '() cannot-block (list 'string-not-kept name-not-kept))
          (list "curl_easy_init" '() cannot-block)
          (list "curl_easy_header" '() cannot-block (list 'string-not-kept name-not-kept))
          (list "curl_easy_cleanup" '() cleanup-open)
          (list "curl_easy_perform" '(__collect_safe) can-block)
          (list "curl_multi_poll" '(__collect_safe) can-block)
          (list "curl_multi_perform" '() multi-perform-plain)
          (list "memcpy" '() memcpy-plain)))

  ;; known-wrappers : (Listof Symbol)
  ;; The macros whose template binds an entry point: src/curl/private/
  ;; native.sls's bind-required. The suite holds it equal to the wrappers
  ;; src/ defines.
  (define known-wrappers '(bind-required))

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
  (define-record-type scan
    (fields bindings violations wrappers))

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
                                  (else (list 'ok fp index (car parts) reading result)))))))))))))))

  ;; --- the walk --------------------------------------------------------------------

  ;; A Finding is one of
  ;;   (binding KEY CONVENTIONS FILE VIA CROSSINGS)
  ;;   (violation VIOLATION)
  ;;   (use NAME FILE FORM BOUND)            a known wrapper's use, read later,
  ;;                                         and the pattern variables around it
  ;;   (wrapper NAME FILE (U (List INDEX CONVENTIONS READING RESULT) #f))
  ;;                                         a definition; #f when unreadable

  ;; datum-findings : String Any (Listof Symbol) (Listof Symbol) -> (Listof Finding)
  ;; What one datum of the file PATH holds, in the order written. FTYPES are
  ;; the names layouts defines.
  (define (datum-findings path datum wrappers ftypes)
    (let ((shared (shared-part datum))
          (found '())
          (accounted '())
          (bound '()))

      (define (emit! finding) (set! found (cons finding found)))

      ;; from-pattern? : Any -> Boolean
      ;; X holds a pattern variable of a macro form around it.
      (define (from-pattern? x)
        (exists (lambda (s) (memq s bound)) (symbols-in x)))

      (define (violation! . v) (emit! (list 'violation v)))

      ;; walk : Any Any Boolean -> Unit
      ;; X, an element of PARENT. QUOTED? holds inside quote and quasiquote,
      ;; and in a vector or box literal: data, not code.
      (define (walk x parent quoted?)
        (cond ((occurrence? x) (violation! 'stray path (abbreviated parent)))
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

      (define (walk-pair form quoted?)
        (let ((head (car form)))
          (cond
            (quoted? (walk-elements form 0 #t))
            ((memq head '(quote quasiquote)) (walk-elements form 0 #t))
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
            ((memq head wrappers)
             (emit! (list 'use head path form bound))
             (walk-elements form 1 #f))
            ((memq head macro-forms)
             (let ((outer bound))
               (set! bound (append (macro-variables form) bound))
               (walk-elements form 0 #f)
               (set! bound outer)))
            (else (walk-elements form 0 #f)))))

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
                                    crossings))))))))

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
                                      crossings)))))))
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
          (walk-elements form 0 #f)))

      ;; The import clause: an (only (chezscheme) ...) accounts for the two
      ;; names. Every other part of a library form is walked as code.
      (define (walk-library form)
        (walk (cadr form) form #f)
        (walk (caddr form) form #f)
        (for-each (lambda (spec)
                    (if (chez-only? spec)
                        (for-each (lambda (id) (unless (occurrence? id) (walk id spec #f)))
                                  (cddr spec))
                        (walk spec (cadddr form) #f)))
                  (cdr (cadddr form)))
        (for-each (lambda (body) (walk body form #f)) (cddddr form)))

      (cond (shared (violation! 'shared-structure path (abbreviated shared)))
            ((library-form? datum) (walk-library datum))
            (else (walk datum datum #f)))
      (reverse found)))

  ;; file-findings : String (Listof Symbol) (Listof Symbol) -> (Listof Finding)
  (define (file-findings path wrappers ftypes)
    (let ((data (read-data path)))
      (if (eq? (car data) 'unreadable)
          (list (list 'violation (list 'unreadable path (cadr data))))
          (fold-left (lambda (found datum)
                       (append found (datum-findings path datum wrappers ftypes)))
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

  ;; use-crossings : Pair Reading Reading (Listof Symbol) (Listof Symbol)
  ;;                 -> (U (Listof Symbol) 'unreadable)
  ;; A use's crossings, or 'unreadable when a type it writes is one of
  ;; BOUND, the pattern variables around it. A type its wrapper's template
  ;; writes is the template's own.
  (define (use-crossings form reading result ftypes bound)
    (let ((types (use-types form reading))
          (written (append (if (eq? (car reading) 'at) (list (use-types form reading)) '())
                           (if (eq? (car result) 'at) (list (use-result form result)) '()))))
      (if (and (list? types)
               (not (exists (lambda (s) (memq s bound)) (symbols-in written))))
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
                          ((eq? (use-crossings form reading result ftypes (list-ref f 4)) 'unreadable)
                           (loop (cdr rest) bindings
                                 (cons (list 'wrapper-types-unreadable file name (abbreviated form))
                                       violations)
                                 defined))
                          (else
                           (loop (cdr rest)
                                 (cons (list (list-ref form index) conventions file name
                                             (use-crossings form reading result ftypes (list-ref f 4)))
                                       bindings)
                                 violations defined))))))))))))))

  ;; scan-conventions : String (Listof Symbol) -> Scan
  ;; Every source file under ROOT, read as data, with WRAPPERS as the known
  ;; wrappers, and the ftypes ROOT's layouts defines. Files are read in
  ;; sorted order, and each one's forms in the order written, so the answer
  ;; is the same on every run.
  (define (scan-conventions root wrappers)
    (let* ((found (if (file-directory? root) (tree root) (list '() '())))
           (files (list-sort string<? (car found)))
           (links (list-sort string<? (cadr found)))
           (ftypes (layout-ftypes root))
           (findings (fold-left (lambda (all path)
                                  (append all (file-findings path wrappers ftypes)))
                                '() files))
           (resolved (resolve findings ftypes)))
      (make-scan (car resolved)
                 (append (if (null? files) (list (list 'no-sources root)) '())
                         (map (lambda (link) (list 'directory-link link)) links)
                         (cadr resolved))
                 (caddr resolved))))

  ;; --- the table's verdicts ----------------------------------------------------------

  ;; same-set? : (Listof Any) (Listof Any) -> Boolean
  (define (same-set? a b)
    (and (for-all (lambda (x) (member x b)) a)
         (for-all (lambda (x) (member x a)) b)
         #t))

  ;; mark-kinds : (Listof Symbol)
  (define mark-kinds '(bytevector-crossing string-not-kept))

  ;; row-mark : Any -> (U (List Symbol String) #f)
  ;; ROW's fourth element, when it is a mark: (KIND CITATION), KIND one of
  ;; mark-kinds and CITATION a string; that the citation quotes a record is
  ;; table-problems' to check.
  (define (row-mark row)
    (and (list? row)
         (= (length row) 4)
         (let ((mark (cadddr row)))
           (and (list? mark)
                (= (length mark) 2)
                (memq (car mark) mark-kinds)
                (string? (cadr mark))
                mark))))

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
  ;; as sets. A bytevector crossing needs a row marked bytevector-crossing,
  ;; a string one marked string-not-kept, and scheme-object fails whatever
  ;; the row.
  (define (table-violations bindings table)
    (fold-left
     (lambda (found binding)
       (let* ((key (car binding))
              (conventions (cadr binding))
              (file (caddr binding))
              (passed (list-ref binding 4))
              (row (find (lambda (row) (and (pair? row) (equal? (car row) key))) table)))
         (append found
                 (cond ((not row) (list (list 'no-row key file)))
                       ((same-set? (cadr row) conventions) '())
                       (else (list (list 'mismatch key (cadr row) conventions file))))
                 (kind-violation 'bytevector-crossing bytevector-types passed
                                 (and row (marked? row 'bytevector-crossing)) key file)
                 (kind-violation 'string-crossing string-types passed
                                 (and row (marked? row 'string-not-kept)) key file)
                 (kind-violation 'scheme-object object-types passed #f key file))))
     '() bindings))

  ;; check-conventions : String (Listof Symbol) Table
  ;;                     -> (List (Listof Binding) (Listof Violation))
  ;; The bindings under ROOT, and every violation: the scan's, then the
  ;; table's.
  (define (check-conventions root wrappers table)
    (let* ((scanned (scan-conventions root wrappers))
           (bindings (scan-bindings scanned)))
      (list bindings
            (append (scan-violations scanned) (table-violations bindings table)))))

  ;; --- the table's own checks -----------------------------------------------------

  (define records ".plans/decisions/")

  ;; row-shaped? : Any -> Boolean
  ;; (key conventions citation), with or without a fourth element, which
  ;; table-problems holds to a mark's shape.
  (define (row-shaped? row)
    (and (list? row)
         (<= 3 (length row) 4)
         (or (string? (car row)) (symbol? (car row)))
         (list? (cadr row))
         (string? (caddr row))))

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

  ;; mark-problems : Row String -> (Listof Violation)
  ;; A shaped row's mark, when it has one: its shape, its citation, and its
  ;; conventions, which may not be __collect_safe.
  (define (mark-problems row root)
    (cond
      ((= (length row) 3) '())
      ((not (row-mark row)) (list (list 'crossing-mark-shape (car row) (cadddr row))))
      (else
       (append (citation-problems (car row) (cadr (row-mark row)) root mark-citation)
               (if (member '__collect_safe (cadr row))
                   (list (list 'crossing-collect-safe (car row)))
                   '())))))

  ;; table-problems : Table String -> (Listof Violation)
  ;; What is wrong with TABLE, whose citations are paths under ROOT, in row
  ;; order:
  ;;   (row-shape ROW)                          not (key conventions citation),
  ;;                                            with or without a fourth element
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
                             (mark-problems row root))))))))))
