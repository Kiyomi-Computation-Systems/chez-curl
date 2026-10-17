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
;;;   (no-row KEY FILE)                      a binding the table lacks
;;;   (mismatch KEY EXPECTED ACTUAL FILE)    conventions that differ, as sets
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

  ;; conventions-table : (Listof (List (U String Symbol) (Listof Convention) String))
  ;; One row per C entry point, keyed by its name, a string, or per
  ;; callable, keyed by the name it is defined as, a symbol. A convention is
  ;; a symbol, __collect_safe, or a list, (__varargs_after 2). Rows for
  ;; entries not bound yet hold M2 to ADR-0013 the moment it binds them.
  ;; ADR-0013 is Proposed: spike E1 (M3) may move a row.
  (define conventions-table
    (list (list "curl_version_info" '() cannot-block)
          (list "curl_global_init" '() cannot-block)
          (list "curl_easy_option_by_name" '() cannot-block)
          (list "curl_easy_init" '() cannot-block)
          (list "curl_easy_header" '() cannot-block)
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

  ;; A Binding is (List (U String Symbol) (Listof Convention) String Symbol):
  ;; its key, its conventions as written, its file, and how it was bound:
  ;; foreign-procedure, foreign-callable, or the known wrapper's name.
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

  ;; procedure-parts : Any -> (U (List (Listof Any) Any) #f)
  ;; FORM as (head convention ... entry-or-procedure (type ...) type): its
  ;; conventions and its entry, or #f when it has not that shape.
  (define (procedure-parts form)
    (and (list? form)
         (>= (length form) 4)
         (let ((n (length form)))
           (and (list? (list-ref form (- n 2)))
                (list (take (cdr form) (- n 4)) (list-ref form (- n 3)))))))

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

  ;; pattern-variables : Pair (Listof Symbol) -> (Listof Symbol)
  ;; Element 0 of a syntax-rules pattern is ignored, so it binds nothing.
  (define (pattern-variables pattern literals)
    (filter (lambda (s) (not (or (memq s '(_ ...)) (memq s literals))))
            (symbols-in (cdr pattern))))

  ;; entry-index : Pair Any (Listof Symbol) -> (U Natural #f)
  ;; Where ENTRY stands among PATTERN's elements, when a use's element there
  ;; is always ENTRY's: ENTRY is a pattern variable, PATTERN is a list
  ;; holding it at index 1 or later, and no ellipsis stands at or before the
  ;; element after it.
  (define (entry-index pattern entry variables)
    (and (memq entry variables)
         (list? pattern)
         (let loop ((rest (cdr pattern)) (i 1))
           (cond ((null? rest) #f)
                 ((eq? (car rest) entry)
                  (and (not (memq '... (take pattern (min (length pattern) (+ i 2)))))
                       i))
                 (else (loop (cdr rest) (+ i 1)))))))

  ;; read-wrapper : Pair -> (U (List 'ok Pair Natural (Listof Convention))
  ;;                           (List 'conventions-from-pattern Pair (Listof Any))
  ;;                           (List 'unreadable String (U Pair #f)))
  ;; A known wrapper's definition: its foreign-procedure form, the index of
  ;; the entry in a use, and its conventions. Or why it cannot be read, and
  ;; its one foreign-procedure form when there is one, which the reason
  ;; covers.
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
                         (else (list 'ok fp index (car parts)))))))))))))

  ;; --- the walk --------------------------------------------------------------------

  ;; A Finding is one of
  ;;   (binding KEY CONVENTIONS FILE VIA)
  ;;   (violation VIOLATION)
  ;;   (use NAME FILE FORM)                  a known wrapper's use, read later
  ;;   (wrapper NAME FILE (U (List INDEX CONVENTIONS) #f))
  ;;                                         a definition; #f when unreadable

  ;; datum-findings : String Any (Listof Symbol) -> (Listof Finding)
  ;; What one datum of the file PATH holds, in the order written.
  (define (datum-findings path datum wrappers)
    (let ((shared (shared-part datum))
          (found '())
          (accounted '()))

      (define (emit! finding) (set! found (cons finding found)))

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
             (emit! (list 'use head path form))
             (walk-elements form 1 #f))
            (else (walk-elements form 0 #f)))))

      (define (procedure-form! form)
        (let ((parts (procedure-parts form)))
          (cond ((not parts) (violation! 'malformed path (abbreviated form)))
                ((string? (cadr parts))
                 (emit! (list 'binding (cadr parts) (car parts) path 'foreign-procedure)))
                (else (violation! 'entry-not-string path (abbreviated form))))))

      (define (callable-definition! form)
        (let ((name (cadr form)) (callable (caddr form)))
          (walk name form #f)
          (let ((parts (procedure-parts callable)))
            (if parts
                (emit! (list 'binding name (car parts) path 'foreign-callable))
                (violation! 'malformed path (abbreviated callable))))
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

  ;; file-findings : String (Listof Symbol) -> (Listof Finding)
  (define (file-findings path wrappers)
    (let ((data (read-data path)))
      (if (eq? (car data) 'unreadable)
          (list (list 'violation (list 'unreadable path (cadr data))))
          (fold-left (lambda (found datum) (append found (datum-findings path datum wrappers)))
                     '() (cadr data)))))

  ;; resolve : (Listof Finding) -> (List (Listof Binding) (Listof Violation) (Listof Symbol))
  ;; Each use read against its wrapper's one definition, in place. A use with
  ;; no definition is named. A wrapper defined twice is named at its second
  ;; definition, and none of its uses is read; nor is a use of a wrapper
  ;; whose definition was unreadable, which is named already.
  (define (resolve findings)
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
                            (conventions (cadr (cadddr (car ds)))))
                        (if (and (list? form)
                                 (> (length form) index)
                                 (string? (list-ref form index)))
                            (loop (cdr rest)
                                  (cons (list (list-ref form index) conventions file name) bindings)
                                  violations defined)
                            (loop (cdr rest) bindings
                                  (cons (list 'wrapper-entry-not-string file name (abbreviated form))
                                        violations)
                                  defined)))))))))))))

  ;; scan-conventions : String (Listof Symbol) -> Scan
  ;; Every source file under ROOT, read as data, with WRAPPERS as the known
  ;; wrappers. Files are read in sorted order, and each one's forms in the
  ;; order written, so the answer is the same on every run.
  (define (scan-conventions root wrappers)
    (let* ((found (if (file-directory? root) (tree root) (list '() '())))
           (files (list-sort string<? (car found)))
           (links (list-sort string<? (cadr found)))
           (findings (fold-left (lambda (all path) (append all (file-findings path wrappers)))
                                '() files))
           (resolved (resolve findings)))
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

  ;; table-violations : (Listof Binding) Table -> (Listof Violation)
  ;; Each binding against its row, found by key with equal?, so the string
  ;; "memcpy" and the symbol memcpy are two keys. Conventions are compared
  ;; as sets.
  (define (table-violations bindings table)
    (fold-left
     (lambda (found binding)
       (let* ((key (car binding))
              (conventions (cadr binding))
              (file (caddr binding))
              (row (find (lambda (row) (and (pair? row) (equal? (car row) key))) table)))
         (append found
                 (cond ((not row) (list (list 'no-row key file)))
                       ((same-set? (cadr row) conventions) '())
                       (else (list (list 'mismatch key (cadr row) conventions file)))))))
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
  (define (row-shaped? row)
    (and (list? row)
         (= (length row) 3)
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

  ;; table-problems : Table String -> (Listof Violation)
  ;; What is wrong with TABLE, whose citations are paths under ROOT, in row
  ;; order:
  ;;   (row-shape ROW)                          not (key conventions citation)
  ;;   (duplicate-row KEY)                      a second row for KEY
  ;;   (citation-shape KEY CITATION)            not "RECORD: PHRASE"
  ;;   (citation-not-a-record KEY RECORD)       no file in .plans/decisions/
  ;;   (citation-phrase-missing KEY RECORD PHRASE)
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
               (let* ((key (car row))
                      (citation (caddr row))
                      (parts (citation-parts citation)))
                 (loop (cdr rows) (cons key keys)
                       (append found
                               (cond
                                 ((not parts) (list (list 'citation-shape key citation)))
                                 ((not (decision-record? (car parts) root))
                                  (list (list 'citation-not-a-record key (car parts))))
                                 ((not (holds-phrase? (string-append root "/" (car parts)) (cdr parts)))
                                  (list (list 'citation-phrase-missing key (car parts) (cdr parts))))
                                 (else '()))))))))))))
