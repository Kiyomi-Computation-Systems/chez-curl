#!r6rs
;;; The suite for chez-curl's constants and struct layouts, each checked
;;; against libcurl's own headers by a C program compiled here, at test
;;; time (ADR-0001, decisions 3 and 4).
;;;
;;;   constants  src/curl/private/constants.sls, read as data for its
;;;              export list. Each export has a row in constant-rows,
;;;              naming the C expression its value must equal, and each
;;;              row is an export. A row's C name is the export's name
;;;              upcased, - as _, unless c-name-aliases names another. The
;;;              values come from (curl private constants) itself. A row
;;;              (each PREFIX) marks a list of (NAME . VALUE) entries, each
;;;              checked against PREFIX and NAME upcased, - as _: ntlm-wb is
;;;              CURL_VERSION_NTLM_WB. PREFIX is the export's name less its
;;;              last word, upcased, - as _, then _, unless c-name-aliases
;;;              names another: curl-version-features's is CURL_VERSION_.
;;;              Each alias must change what its row's export derives.
;;;   layouts    src/curl/private/layouts.sls, read as data. It is one
;;;              datum, the library (curl private layouts), whose imports
;;;              are exactly (curl private require-threaded), (rnrs) and
;;;              (only (chezscheme) define-ftype), whose body is
;;;              (define-ftype NAME (struct (FIELD TYPE) ...)) forms alone,
;;;              and whose exports are exactly those NAMEs. define-ftype
;;;              appears nowhere else in it, quoted or not. check-seam's
;;;              rule (f) lets this library alone import define-ftype, and
;;;              this suite reads that rule's entry from tests/check-seam.sps
;;;              and requires it to name this library alone. So no function
;;;              ftype, and no macro that makes one, exists under src/.
;;;              Each define-ftype has a row in layout-rows, naming its C
;;;              type, and each row is a define-ftype. Each must be a struct
;;;              of primitive-typed fields, each type one field-kinds holds;
;;;              any other shape fails by name. Every field's offset, size
;;;              and kind are compared with offsetof, sizeof and _Generic.
;;;              Offset alone misses an int written for C's long when
;;;              padding keeps the next field's offset; offset and size
;;;              miss a double written for C's char *. Total size is not
;;;              compared: an ftype may stop before the struct's end, as
;;;              curl-version-info-data does.
;;;   versions   the headers the program compiled against must be no newer
;;;              than the libcurl chez-curl itself loads, which this suite
;;;              loads in its own process through (curl). Headers newer than
;;;              the library vouch for fields and values the library may
;;;              not have: on CI's floor lane, a forgotten C_INCLUDE_PATH
;;;              would check the runner's headers, not 7.85.0's.
;;;
;;; The C program is compiled with $CC and no -I flag: the compiler's own
;;; search path, C_INCLUDE_PATH among it, must find curl/curl.h. Missing
;;; headers fail this suite, never skip it (ADR-0001). A compile is judged
;;; by its exit status alone: Guix's gcc warns on stderr at every link.
;;; The program prints one datum per question, read back here as data.
;;;
;;; Every computation that can raise runs under a guard, before the
;;; tests, with a sentinel of its own: SRFI-64 does not catch a raise in an
;;; expected expression, nor in a suite's top-level definitions, and makes
;;; #f of one in an actual expression. No expected value here is #f.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (only (chezscheme) getenv foreign-sizeof)
        (only (curl private conditions)
              curl-library-unavailable? curl-library-unavailable-reason
              curl-library-unavailable-path)
        (curl-testing)
        (libcurl-oracle))

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

;; --- the tables ---------------------------------------------------------------

(define constants-source "src/curl/private/constants.sls")
(define layouts-source "src/curl/private/layouts.sls")
(define check-seam-source "tests/check-seam.sps")

;; layouts-name : (Listof Symbol)
;; The library layouts.sls must hold, and the one library check-seam's rule
;; (f) may let import define-ftype.
(define layouts-name '(curl private layouts))

;; layouts-imports : (Listof Any)
;; layouts.sls's import specs, exactly: the refusal first (ADR-0001), and
;; define-ftype alone from (chezscheme).
(define layouts-imports
  '((curl private require-threaded) (rnrs) (only (chezscheme) define-ftype)))

;; constant-rows : (Listof (Pairof Symbol (U String (List 'each String))))
;; Each export of (curl private constants), with the C expression its value
;; must equal, or (each PREFIX) for a list of (NAME . VALUE) entries.
(define constant-rows
  '((curl-version-features . (each "CURL_VERSION_"))
    (curl-version-ssl . "CURL_VERSION_SSL")
    (curlhe-not-built-in . "CURLHE_NOT_BUILT_IN")
    (curlh-header . "CURLH_HEADER")
    (curl-global-default . "CURL_GLOBAL_DEFAULT")
    (curle-ok . "CURLE_OK")
    (curlversion-tenth . "CURLVERSION_TENTH")))

;; c-name-aliases : (Listof (Pairof Symbol String))
;; Each export whose row names a C constant other than the export's own
;; name upcased, - as _, or, for an (each PREFIX) row, a prefix other than
;; the one its name derives, with the one C name or prefix its row must
;; name instead. Each key is a row whose derived name its alias changes:
;; any other entry fails, as a stale permission. Empty: every row's C name
;; is derived. Adding an alias is a reviewed change, never a way to quiet a
;; failing test: a C name written as free text can name any constant whose
;; value happens to match, and a prefix such as "0|CURL_VERSION_" any C
;; expression.
(define c-name-aliases '())

;; layout-rows : (Listof (Pairof Symbol String))
;; Each define-ftype of (curl private layouts), with the C type it lays out.
(define layout-rows
  '((curl-version-info-data . "curl_version_info_data")))

;; field-kinds : (Listof (Pairof Symbol (Listof Kind)))
;; Each Chez primitive type a layout field may have, with the kinds of C
;; member it may lay out. A kind is the C program's answer for a member's
;; type, through _Generic: integer for each standard integer type, floating
;; for float, double and long double, other for anything else: pointers,
;; and arrays, which decay to pointers. uptr and void* lay out a pointer
;; alone, and iptr an integer: an integer member is written with an integer
;; type, size_t for a size, so a uptr written for C's long fails. Signedness
;; is not compared: features is unsigned-int against C's int on purpose
;; (layouts.sls). A field type absent here fails the shape test, by name:
;; add it here, with its kinds, first.
(define field-kinds
  (append
   (map (lambda (type) (cons type '(integer)))
        '(short unsigned-short int unsigned unsigned-int long unsigned-long
          long-long unsigned-long-long
          integer-8 unsigned-8 integer-16 unsigned-16 integer-24 unsigned-24
          integer-32 unsigned-32 integer-40 unsigned-40 integer-48 unsigned-48
          integer-56 unsigned-56 integer-64 unsigned-64
          size_t ssize_t ptrdiff_t iptr))
   (map (lambda (type) (cons type '(floating)))
        '(float double single-float double-float))
   '((uptr other)
     (void* other))))

(define kinds '(integer floating other))

;; --- helpers ------------------------------------------------------------------

;; written : Any -> String
(define (written x)
  (guard (e (#t "<unprintable>"))
    (call-with-string-output-port (lambda (p) (write x p)))))

;; underscored : String -> String
;; S with each - as _.
(define (underscored s)
  (list->string (map (lambda (c) (if (char=? c #\-) #\_ c)) (string->list s))))

;; text : Any -> String
;; X itself when it is a string, else X written.
(define (text x) (if (string? x) x (written x)))

;; each-row? : Row -> Boolean
;; Whether ROW is (NAME . (each PREFIX)), PREFIX a string.
(define (each-row? row)
  (let ((c (cdr row)))
    (and (list? c) (= (length c) 2) (eq? (car c) 'each) (string? (cadr c)))))

;; derived-prefix : Symbol -> (U String (List 'one-word Symbol))
;; The prefix NAME derives for an (each PREFIX) row: NAME less its last
;; hyphen-separated word, upcased, - as _, then _. curl-version-features
;; derives CURL_VERSION_. A name of one word derives none.
(define (derived-prefix name)
  (let ((s (symbol->string name)))
    (let loop ((i (- (string-length s) 1)))
      (cond ((< i 0) (list 'one-word name))
            ((char=? (string-ref s i) #\-)
             (string-append (underscored (string-upcase (substring s 0 i))) "_"))
            (else (loop (- i 1)))))))

;; derived-c-name : Row -> (U String (List 'one-word Symbol))
;; What ROW's export derives: for an (each PREFIX) row its prefix, for any
;; other its name upcased, - as _.
(define (derived-c-name row)
  (if (each-row? row)
      (derived-prefix (car row))
      (underscored (string-upcase (symbol->string (car row))))))

;; c-name-of : Row -> Any
;; The C name, or for an (each PREFIX) row the prefix, ROW must name: its
;; export's alias, else what its export derives. (malformed-aliases) when
;; c-name-aliases is no list of pairs, which the alias tests name.
(define (c-name-of row)
  (guard (e (#t '(malformed-aliases)))
    (cond ((assq (car row) c-name-aliases) => cdr)
          (else (derived-c-name row)))))

(define (natural? x) (and (integer? x) (exact? x) (>= x 0)))

;; hex : Natural -> String
;; N as LIBCURL_VERSION_NUM is written: 0x and at least six hex digits.
(define (hex n)
  (let ((digits (string-downcase (number->string n 16))))
    (string-append "0x" (make-string (max 0 (- 6 (string-length digits))) #\0) digits)))

;; symbol-before? : Symbol Symbol -> Boolean
(define (symbol-before? a b)
  (string<? (symbol->string a) (symbol->string b)))

;; read-data : String -> (U (List 'data (Listof Any)) (List 'unreadable String String)
;;                          (List 'eof-literal String))
;; Every datum in the file at PATH.
(define (read-data path)
  (guard (e (#t (list 'unreadable path (describe e))))
    (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                          (make-transcoder (utf-8-codec)))
      (lambda (port)
        (let loop ((found '()))
          (let ((datum (read port)))
            (cond ((not (eof-object? datum)) (loop (cons datum found)))
                  ((port-eof? port) (list 'data (reverse found)))
                  ;; An #!eof literal would end the reading early.
                  (else (list 'eof-literal path)))))))))

;; library-form? : Any -> Boolean
;; (library NAME (export ...) (import ...) BODY ...)
(define (library-form? d)
  (and (list? d) (>= (length d) 4) (eq? (car d) 'library)
       (list? (caddr d)) (pair? (caddr d)) (eq? (car (caddr d)) 'export)
       (list? (cadddr d)) (pair? (cadddr d)) (eq? (car (cadddr d)) 'import)))

;; read-library : String -> (U (List 'library Library-Form) Failure)
;; The first library form in the file at PATH.
(define (read-library path)
  (let ((found (read-data path)))
    (if (eq? (car found) 'data)
        (let ((form (find library-form? (cadr found))))
          (if form (list 'library form) (list 'no-library-form path)))
        found)))

;; --- constants.sls, read as data ------------------------------------------------

;; constants-read : (U (List 'read (Listof Symbol)) Failure)
;; The export list, when every export is an identifier. A (rename ...)
;; spec is not read, and fails here rather than going unchecked.
(define constants-read
  (guard (e (#t (list 'raised (describe e))))
    (let ((found (read-library constants-source)))
      (if (eq? (car found) 'library)
          (let* ((specs (cdr (caddr (cadr found))))
                 (odd (filter (lambda (spec) (not (symbol? spec))) specs)))
            (if (null? odd) (list 'read specs) (list 'exports-not-identifiers odd)))
          found))))

;; exports : (Listof Symbol)
(define exports
  (if (eq? (car constants-read) 'read) (cadr constants-read) '()))

;; constant-value : Symbol -> Any
;; NAME's value in (curl private constants), or (no-value TEXT).
(define (constant-value name)
  (guard (e (#t (list 'no-value (describe e))))
    (eval name (environment '(curl private constants)))))

;; entries? : Any -> Boolean
;; A non-empty list of (NAME . VALUE), each NAME a symbol.
(define (entries? x)
  (and (list? x) (pair? x)
       (for-all (lambda (entry) (and (pair? entry) (symbol? (car entry)))) x)))

;; --- layouts.sls, read as data --------------------------------------------------

;; ftype-forms-in : Any -> (Listof Pair)
;; Every list headed by define-ftype in X, at any depth, X's own elements
;; walked one by one. Each pair is walked once, so a cyclic datum ends.
(define (ftype-forms-in x)
  (let ((seen (make-eq-hashtable)))
    (let walk ((x x))
      (cond ((not (pair? x)) '())
            ((eq? (car x) 'define-ftype) (list x))
            (else (let loop ((rest x) (found '()))
                    (if (and (pair? rest) (not (hashtable-ref seen rest #f)))
                        (begin (hashtable-set! seen rest #t)
                               (loop (cdr rest) (append found (walk (car rest)))))
                        found)))))))

;; layouts-library : (U (List 'library Library-Form) Failure)
;; The one datum in layouts.sls, a library form. Any other datum beside it
;; fails here, as (data-count N), so every form Chez could load from the
;; file is one this suite reads.
(define layouts-library
  (guard (e (#t (list 'raised (describe e))))
    (let ((found (read-data layouts-source)))
      (cond ((not (eq? (car found) 'data)) found)
            ((not (= (length (cadr found)) 1)) (list 'data-count (length (cadr found))))
            ((library-form? (car (cadr found))) (list 'library (car (cadr found))))
            (else (list 'no-library-form (car (cadr found))))))))

;; layouts-form : (U Library-Form #f)
(define layouts-form
  (and (eq? (car layouts-library) 'library) (cadr layouts-library)))

;; layouts-body : (Listof Any)
(define layouts-body (if layouts-form (cddddr layouts-form) '()))

;; layouts-read : (U (List 'read (Listof Pair)) Failure)
;; Every define-ftype in the library's body, at any depth.
(define layouts-read
  (guard (e (#t (list 'raised (describe e))))
    (if layouts-form
        (list 'read (ftype-forms-in layouts-body))
        layouts-library)))

;; ftype-forms : (Listof Pair)
(define ftype-forms
  (if (eq? (car layouts-read) 'read) (cadr layouts-read) '()))

;; body-ftype? : Any -> Boolean
;; Whether FORM, a body form, is headed by define-ftype.
(define (body-ftype? form)
  (and (pair? form) (eq? (car form) 'define-ftype)))

;; or-no-library : (-> Any) -> Any
;; THUNK's answer when layouts.sls was read as one library form; else what
;; stopped the read, so a test of its shape cannot pass on nothing.
(define (or-no-library thunk)
  (if layouts-form (thunk) (list 'no-library layouts-library)))

;; body-ftype-names : (Listof Symbol)
;; The names the body's define-ftype forms define: the exports layouts.sls
;; must have, exactly. A form whose name is no symbol fails its shape test.
(define body-ftype-names
  (filter symbol? (map (lambda (form) (if (pair? (cdr form)) (cadr form) form))
                       (filter body-ftype? layouts-body))))

;; occurrences : Any -> Natural
;; How often the symbol define-ftype occurs in X, through pairs and
;; vectors: quote, quasiquote and syntax are lists, so quoted ones count.
;; A shared pair or vector is walked once, so a cyclic datum ends.
(define (occurrences x)
  (let ((seen (make-eq-hashtable)))
    (let walk ((x x))
      (cond ((eq? x 'define-ftype) 1)
            ((not (or (pair? x) (vector? x))) 0)
            ((hashtable-ref seen x #f) 0)
            (else (hashtable-set! seen x #t)
                  (if (pair? x)
                      (+ (walk (car x)) (walk (cdr x)))
                      (apply + (map walk (vector->list x)))))))))

;; chez-only? : Any -> Boolean
;; Whether SPEC is (only (chezscheme) name ...), unwrapped.
(define (chez-only? spec)
  (and (list? spec) (>= (length spec) 2) (eq? (car spec) 'only)
       (equal? (cadr spec) '(chezscheme))))

;; ftype-strays : (Listof Any)
;; Each part of layouts.sls's library form that holds define-ftype where it
;; does not belong: its name, its export clause, an import spec that is not
;; (only (chezscheme) ...), a body form not headed by define-ftype, or one
;; headed by it that holds it again. Its import and its body forms' heads
;; are the only places it belongs. A macro could carry it anywhere else, or
;; datum->syntax make it from a quoted symbol.
(define ftype-strays
  (if layouts-form
      (map car
           (filter
            (lambda (part) (> (occurrences (cdr part)) 0))
            (append
             (list (cons (cadr layouts-form) (cadr layouts-form))
                   (cons (caddr layouts-form) (caddr layouts-form)))
             (map (lambda (spec) (cons spec spec))
                  (remp chez-only? (cdr (cadddr layouts-form))))
             (map (lambda (form) (cons form (if (body-ftype? form) (cdr form) form)))
                  layouts-body))))
      '()))

;; --- tests/check-seam.sps, read as data ---------------------------------------

;; seam-ftype-entry : Any
;; library-only-chez-names' entry for define-ftype in tests/check-seam.sps,
;; read as data: (define-ftype LIBRARY ...), the libraries rule (f) lets
;; import it. Else what stopped the read: how many definitions of the list
;; there are when not one, a value that is no quoted list, or the entries
;; for define-ftype when there is not one.
(define seam-ftype-entry
  (guard (e (#t (list 'raised (describe e))))
    (let ((found (read-data check-seam-source)))
      (if (not (eq? (car found) 'data))
          found
          (let ((defs (filter (lambda (d)
                                (and (list? d) (= (length d) 3) (eq? (car d) 'define)
                                     (eq? (cadr d) 'library-only-chez-names)))
                              (cadr found))))
            (if (not (= (length defs) 1))
                (list 'definitions (length defs))
                (let ((value (caddr (car defs))))
                  (if (not (and (list? value) (= (length value) 2) (eq? (car value) 'quote)
                                (list? (cadr value))))
                      (list 'not-a-quoted-list value)
                      (let ((entries (filter (lambda (entry)
                                               (and (pair? entry) (eq? (car entry) 'define-ftype)))
                                             (cadr value))))
                        (if (= (length entries) 1) (car entries) (list 'entries entries)))))))))))

;; ftype-name : Pair -> Any
;; The name FORM defines: its second element when that is a symbol, else
;; the form itself, which no row names.
(define (ftype-name form)
  (if (and (pair? (cdr form)) (symbol? (cadr form))) (cadr form) form))

;; primitive? : Any -> Boolean
;; A type foreign-sizeof knows: int, uptr, ... and not an ftype's name.
(define (primitive? type)
  (and (symbol? type)
       (guard (e (#t #f)) (foreign-sizeof type) #t)))

;; ftype-shape : Pair -> (U (List 'struct (Listof (List Symbol Symbol)))
;;                          (List 'unhandled Any) (List 'no-kind Any))
;; FORM's fields, when it is (define-ftype NAME (struct (FIELD TYPE) ...)),
;; with at least one field and each TYPE primitive and in field-kinds; else
;; the part of it this suite does not handle, or the first field whose type
;; field-kinds lacks.
(define (ftype-shape form)
  (cond
    ((not (and (list? form) (= (length form) 3) (symbol? (cadr form))))
     (list 'unhandled form))
    ((not (let ((type (caddr form)))
            (and (list? type) (>= (length type) 2) (eq? (car type) 'struct))))
     (list 'unhandled (caddr form)))
    ((find (lambda (field)
             (not (and (list? field) (= (length field) 2) (symbol? (car field))
                       (primitive? (cadr field)))))
           (cdr (caddr form)))
     => (lambda (field) (list 'unhandled field)))
    ((find (lambda (field) (not (assq (cadr field) field-kinds)))
           (cdr (caddr form)))
     => (lambda (field) (list 'no-kind field)))
    (else (list 'struct (cdr (caddr form))))))

(define layouts-environment
  (guard (e (#t (list 'no-environment (describe e))))
    (environment '(chezscheme) '(curl private layouts))))

;; scheme-layout : Symbol Symbol Symbol -> (U (List 'offset Natural 'size Natural) (List 'no-value String))
;; FIELD's offset in FTYPE, from a pointer at address 0, and the size of
;; its TYPE.
(define (scheme-layout ftype field type)
  (guard (e (#t (list 'no-value (describe e))))
    (list 'offset
          (eval `(ftype-pointer-address
                  (ftype-&ref ,ftype (,field) (make-ftype-pointer ,ftype 0)))
                layouts-environment)
          'size
          (foreign-sizeof type))))

;; --- the checks -------------------------------------------------------------------

;; A check is (ROW NAME QUESTION ACTUAL TYPE): the table row it checks, the
;; test's name, what the C program is asked, the Scheme side's answer, and
;; for a field its Chez type (#f for a constant). A question is
;; (constant C-EXPRESSION) or (member C-TYPE C-MEMBER).

;; constant-checks : Row -> (Listof Check)
(define (constant-checks row)
  (let ((name (car row)) (c (cdr row)))
    (cond
      ((string? c)
       (list (list name (string-append (symbol->string name) " is " c)
                   (list 'constant c)
                   (constant-value name)
                   #f)))
      ((and (list? c) (= (length c) 2) (eq? (car c) 'each) (string? (cadr c)))
       (let ((entries (constant-value name)))
         (if (entries? entries)
             (map (lambda (entry)
                    (let ((c-name (string-append
                                   (cadr c)
                                   (underscored (string-upcase (symbol->string (car entry)))))))
                      (list name
                            (string-append (symbol->string name) ": "
                                           (symbol->string (car entry)) " is " c-name)
                            (list 'constant c-name)
                            (cdr entry)
                            #f)))
                  entries)
             '())))
      (else '()))))

;; layout-checks : Pair -> (Listof Check)
;; Every field's, when FORM is a struct this suite handles and a row names
;; its C type.
(define (layout-checks form)
  (let ((shape (ftype-shape form))
        (row (assq (ftype-name form) layout-rows)))
    (if (and (eq? (car shape) 'struct) row)
        (map (lambda (field)
               (let ((c-type (cdr row))
                     (c-member (underscored (symbol->string (car field)))))
                 (list (car row)
                       (string-append c-type "." c-member
                                      " has the header's offset, size and kind")
                       (list 'member c-type c-member)
                       (scheme-layout (car row) (car field) (cadr field))
                       (cadr field))))
             (cadr shape))
        '())))

;; checks : (U (Listof Check) (List 'raised String))
(define checks
  (guard (e (#t (list 'raised (describe e))))
    (append (apply append (map constant-checks constant-rows))
            (apply append (map layout-checks ftype-forms)))))

(define check-list (if (and (pair? checks) (eq? (car checks) 'raised)) '() checks))

;; questions : (Listof Question)
;; The headers' own version first, (header-version), then each check's.
(define questions (cons '(header-version) (map caddr check-list)))

;; --- the C program ----------------------------------------------------------------

;; c-line : Question -> String
(define (c-line question)
  (case (car question)
    ((header-version) "  HEADER_VERSION();\n")
    ((constant) (string-append "  CONSTANT(" (cadr question) ");\n"))
    (else (string-append "  MEMBER(" (cadr question) ", " (caddr question) ");\n"))))

;; c-program : (Listof Question) -> String
;; curl/curl.h comes first, so headers that are missing are named there.
;; #e and #m are not macro-expanded, so each answer carries the name asked.
;; KIND is C11's _Generic on the member, which it does not evaluate. Its
;; operand is converted as an rvalue: qualifiers drop, an array decays to a
;; pointer, and an enum matches its compatible integer type.
(define (c-program questions)
  (string-append
   "#include <curl/curl.h>\n"
   "#include <stddef.h>\n"
   "#include <stdio.h>\n"
   "\n"
   "#define KIND(x) _Generic((x), \\\n"
   "  _Bool: \"integer\", char: \"integer\", \\\n"
   "  signed char: \"integer\", unsigned char: \"integer\", \\\n"
   "  short: \"integer\", unsigned short: \"integer\", \\\n"
   "  int: \"integer\", unsigned int: \"integer\", \\\n"
   "  long: \"integer\", unsigned long: \"integer\", \\\n"
   "  long long: \"integer\", unsigned long long: \"integer\", \\\n"
   "  float: \"floating\", double: \"floating\", long double: \"floating\", \\\n"
   "  default: \"other\")\n"
   "#define HEADER_VERSION() \\\n"
   "  printf(\"(header-version %lld)\\n\", (long long)LIBCURL_VERSION_NUM)\n"
   "#define CONSTANT(e) printf(\"(constant \\\"%s\\\" %lld)\\n\", #e, (long long)(e))\n"
   "#define MEMBER(t, m) printf(\"(member \\\"%s\\\" \\\"%s\\\" %lld %lld %s)\\n\", #t, #m, \\\n"
   "  (long long)offsetof(t, m), (long long)sizeof(((t *)0)->m), KIND(((t *)0)->m))\n"
   "\n"
   "int main(void)\n"
   "{\n"
   (apply string-append (map c-line questions))
   "  return 0;\n"
   "}\n"))

;; answer? : Any -> Boolean
;; (header-version N), (constant NAME VALUE) or
;; (member TYPE MEMBER OFFSET SIZE KIND).
(define (answer? d)
  (and (list? d)
       (or (and (= (length d) 2) (eq? (car d) 'header-version) (natural? (cadr d)))
           (and (= (length d) 3) (eq? (car d) 'constant) (string? (cadr d))
                (integer? (caddr d)) (exact? (caddr d)))
           (and (= (length d) 6) (eq? (car d) 'member) (string? (cadr d))
                (string? (caddr d)) (natural? (cadddr d)) (natural? (car (cddddr d)))
                (memq (cadr (cddddr d)) kinds) #t))))

;; read-all : String -> (U (Listof Any) #f)
(define (read-all text)
  (guard (e (#t #f))
    (let ((port (open-string-input-port text)))
      (let loop ((data '()))
        (let ((datum (read port)))
          (if (eof-object? datum) (reverse data) (loop (cons datum data))))))))

(define (write-text path text)
  (call-with-port (open-file-output-port path (file-options) (buffer-mode block)
                                         (make-transcoder (utf-8-codec)))
    (lambda (port) (put-string port text))))

;; header-answers : (Listof Question)
;;                  -> (U (List 'answers (Listof Answer)) (Pairof Symbol Any))
;; Compiles and runs the program for QUESTIONS in a fresh directory, and
;; answers what it printed. Anything else names the step that went wrong:
;; compile or run (with the command's status, stdout and stderr), output
;; (what it printed, which is not answers), or raised.
(define (header-answers questions)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (let ((source (string-append dir "/headers.c"))
             (program (string-append dir "/headers")))
         (write-text source (c-program questions))
         (let ((compiled (capture-command
                          (append (c-compiler getenv) (list "-o" program source)))))
           (if (not (= (car compiled) 0))
               (cons 'compile compiled)
               (let ((ran (capture-command (list program))))
                 (if (not (= (car ran) 0))
                     (cons 'run ran)
                     (let ((data (read-all (cadr ran))))
                       (if (and data (for-all answer? data))
                           (list 'answers data)
                           (list 'output (cadr ran)))))))))))))

(define oracle (header-answers questions))

(define answers (if (eq? (car oracle) 'answers) (cadr oracle) '()))

;; answer-question : Answer -> Question
(define (answer-question a)
  (case (car a)
    ((header-version) (list (car a)))
    ((constant) (list (car a) (cadr a)))
    (else (list (car a) (cadr a) (caddr a)))))

;; header-answer : Question -> (U Answer #f)
(define (header-answer question)
  (find (lambda (a) (equal? (answer-question a) question)) answers))

;; header-value : Question -> Any
;; The program's answer: a constant's value, or (offset N size N kind K);
;; else (no-answer . QUESTION).
(define (header-value question)
  (let ((a (header-answer question)))
    (cond ((not a) (cons 'no-answer question))
          ((eq? (car a) 'constant) (caddr a))
          (else (list 'offset (cadddr a) 'size (car (cddddr a))
                      'kind (cadr (cddddr a)))))))

;; scheme-value : Check -> Any
;; The Scheme side, in the form header-value answers. A field's is
;; (offset N size N kind K), K being the kind the header answered when the
;; field's type may lay it out; else (TYPE may-be KINDS), the kinds it may.
(define (scheme-value check)
  (let ((question (caddr check)) (actual (cadddr check)) (type (car (cddddr check))))
    (if (and (eq? (car question) 'member) (pair? actual) (eq? (car actual) 'offset))
        (let ((may-be (cond ((assq type field-kinds) => cdr) (else '())))
              (a (header-answer question)))
          (append actual
                  (list 'kind
                        (if (and a (memq (cadr (cddddr a)) may-be))
                            (cadr (cddddr a))
                            (list type 'may-be may-be)))))
        actual)))

;; checked-rows : (Listof Symbol)
;; The rows the checks cover, each once.
(define checked-rows
  (fold-left (lambda (found check)
               (if (memq (car check) found) found (append found (list (car check)))))
             '() check-list))

;; --- the versions -------------------------------------------------------------------

;; header-version : (U (List 'version Natural) (List 'no-header-version Symbol))
;; LIBCURL_VERSION_NUM of the headers the program compiled against; else
;; the step the program stopped at (answers: it ran, but did not say).
(define header-version
  (let ((a (header-answer '(header-version))))
    (if a (list 'version (cadr a)) (list 'no-header-version (car oracle)))))

;; library-version : (U (List 'version Natural) (List 'refused Symbol Any)
;;                      (List 'raised String) (List 'not-a-version Any))
;; version_num of the libcurl chez-curl itself loads: (curl)'s
;; loaded-libcurl, run here, in this process. A refusal is named by its
;; reason and path, never raised. (curl private native) loads libcurl in its
;; library body, and a guard in a program catches a raise from there only
;; through eval (AGENTS.md).
(define library-version
  (guard (e ((curl-library-unavailable? e)
             (list 'refused (curl-library-unavailable-reason e)
                   (curl-library-unavailable-path e)))
            (#t (list 'raised (describe e))))
    (let ((n (eval '(libcurl-info-version-number (loaded-libcurl)) (environment '(curl)))))
      (if (natural? n) (list 'version n) (list 'not-a-version n)))))

;; version-verdict : Natural Natural -> (U 'no-newer (List 'headers String 'newer-than 'library String))
;; Whether headers at HEADERS are no newer than a library at LIBRARY, both
;; LIBCURL_VERSION_NUM; else both numbers, in hex.
(define (version-verdict headers library)
  (if (<= headers library)
      'no-newer
      (list 'headers (hex headers) 'newer-than 'library (hex library))))

;; headers-against-library : (U 'no-newer Any)
;; version-verdict of the two versions; else what each side answered, a
;; version in hex.
(define headers-against-library
  (let ((shown (lambda (v) (if (eq? (car v) 'version) (hex (cadr v)) v))))
    (if (and (eq? (car header-version) 'version) (eq? (car library-version) 'version))
        (version-verdict (cadr header-version) (cadr library-version))
        (list 'headers (shown header-version) 'library (shown library-version)))))

(test-begin "constants")

;; --- the reads are live ------------------------------------------------------------

(test-equal "constants.sls is read: a library whose exports are identifiers, at least one"
  'read
  (if (and (eq? (car constants-read) 'read) (pair? exports)) 'read constants-read))

(test-equal "layouts.sls is read: one datum, a library with a define-ftype, at least one"
  'read
  (if (and (eq? (car layouts-read) 'read) (pair? ftype-forms)) 'read layouts-read))

;; --- layouts.sls's shape: no route to a function ftype ------------------------------
;; check-seam's rule (f) lets (curl private layouts) alone import define-ftype.
;; These hold that library to plain struct definitions, so nothing in it can
;; hand define-ftype, or a form that uses it, to anything else: no export of
;; the keyword, no macro, exported or used in place, and no quoted symbol
;; for datum->syntax to bind.

;; Widening rule (f) to another library fails here, until this suite holds
;; that library to the same shape.
(test-equal "tests/check-seam.sps's library-only-chez-names lets (curl private layouts) alone import define-ftype"
  (list 'define-ftype layouts-name)
  seam-ftype-entry)

(test-equal "layouts.sls is the library (curl private layouts), the one rule (f) names"
  layouts-name
  (or-no-library (lambda () (cadr layouts-form))))

(test-equal "layouts.sls imports exactly (curl private require-threaded), (rnrs) and (only (chezscheme) define-ftype), in order, none wrapped"
  layouts-imports
  (or-no-library (lambda () (cdr (cadddr layouts-form)))))

(test-equal "layouts.sls's body is define-ftype forms alone: no define, define-syntax, begin, macro use or other form"
  '()
  (or-no-library (lambda () (remp body-ftype? layouts-body))))

(test-equal "layouts.sls exports exactly the names its define-ftype forms define, each a plain identifier, in any order"
  (list-sort symbol-before? body-ftype-names)
  (or-no-library
   (lambda ()
     (let* ((exports (cdr (caddr layouts-form)))
            (odd (remp symbol? exports)))
       (if (null? odd) (list-sort symbol-before? exports) (list 'not-identifiers odd))))))

(test-equal "layouts.sls holds define-ftype only in its (only (chezscheme) ...) import and at its body forms' heads, quoted ones counted"
  '()
  (or-no-library (lambda () ftype-strays)))

;; --- coverage, both ways ---------------------------------------------------------------

(for-each
 (lambda (name)
   (test-equal (string-append "constants.sls exports " (symbol->string name)
                              ", and constant-rows has a row for it")
     'row
     (if (assq name constant-rows) 'row 'no-row)))
 exports)

(for-each
 (lambda (row)
   (test-equal (string-append "constant-rows' row " (symbol->string (car row))
                              " is an export of constants.sls")
     'exported
     (if (memq (car row) exports) 'exported 'not-exported)))
 constant-rows)

(for-each
 (lambda (form)
   (test-equal (string-append "layouts.sls defines the ftype " (written (ftype-name form))
                              ", and layout-rows has a row for it")
     'row
     (if (assq (ftype-name form) layout-rows) 'row 'no-row)))
 ftype-forms)

(for-each
 (lambda (row)
   (test-equal (string-append "layout-rows' row " (symbol->string (car row))
                              " is a define-ftype in layouts.sls")
     'defined
     (if (memq (car row) (map ftype-name ftype-forms)) 'defined 'not-defined)))
 layout-rows)

;; --- names ---------------------------------------------------------------------------------

;; A row's C name is not free text: (curlh-header . "CURL_VERSION_IPV6")
;; would pass every value check, both being 1. Nor is an (each PREFIX)
;; row's prefix: "0|CURL_VERSION_" makes every entry's C expression another
;; of the same value.
(for-each
 (lambda (row)
   (let ((c-name (c-name-of row))
         (aliased (guard (e (#t #f)) (assq (car row) c-name-aliases))))
     (cond
       ((string? (cdr row))
        (test-equal (string-append "constant-rows' row " (symbol->string (car row))
                                   " names " (text c-name) ", "
                                   (if aliased
                                       "its entry in c-name-aliases"
                                       "its name upcased, - as _"))
          c-name
          (cdr row)))
       ((each-row? row)
        (test-equal (string-append "constant-rows' row " (symbol->string (car row))
                                   " has the prefix " (text c-name) ", "
                                   (if aliased
                                       "its entry in c-name-aliases"
                                       "its name less its last word, upcased, - as _, then _"))
          c-name
          (cadr (cdr row)))))))
 constant-rows)

;; An alias is a permission, and one that changes nothing, or names no row,
;; or is shadowed by an earlier entry for its row, is a stale one.
(for-each
 (lambda (alias)
   (test-equal (string-append "c-name-aliases' entry " (written alias)
                              " is its row's one alias, and changes what the row's name derives")
     'changes
     (cond
       ((not (and (pair? alias) (symbol? (car alias)) (string? (cdr alias))))
        'not-a-name-and-a-string)
       ((not (assq (car alias) constant-rows)) 'no-such-row)
       ((not (eq? (assq (car alias) c-name-aliases) alias)) 'not-its-rows-first-entry)
       ((equal? (cdr alias) (derived-c-name (assq (car alias) constant-rows)))
        (list 'derived-already (cdr alias)))
       (else 'changes))))
 (if (list? c-name-aliases) c-name-aliases (list c-name-aliases)))

;; --- shapes ------------------------------------------------------------------------------

(for-each
 (lambda (row)
   (when (pair? (cdr row))
     (test-equal (string-append "constants.sls: " (symbol->string (car row))
                                " is a non-empty list of (name . value), each name a symbol")
       'entries
       (let ((value (constant-value (car row))))
         (if (entries? value) 'entries value)))))
 constant-rows)

;; A type field-kinds misspells would fail closed, but name no cause.
(test-equal "field-kinds: each type is one foreign-sizeof knows, each kind integer, floating or other"
  '()
  (filter (lambda (entry)
            (not (and (primitive? (car entry)) (pair? (cdr entry))
                      (for-all (lambda (k) (memq k kinds)) (cdr entry)))))
          field-kinds))

(for-each
 (lambda (form)
   (test-equal (string-append "layouts.sls: " (written (ftype-name form))
                              " is a struct of primitive-typed fields, each type in field-kinds")
     'handled
     (let ((shape (ftype-shape form)))
       (if (eq? (car shape) 'struct) 'handled shape))))
 ftype-forms)

;; Every row of both tables has a check. A check list emptied, or a row's
;; checks dropped, would otherwise leave nothing below to fail. The checks
;; follow layouts.sls's order, not layout-rows', so both sides are sorted.
(test-equal "every row of constant-rows and layout-rows is checked"
  (list-sort symbol-before? (append (map car constant-rows) (map car layout-rows)))
  (if (and (pair? checks) (eq? (car checks) 'raised))
      checks
      (list-sort symbol-before? checked-rows)))

;; --- the C program ------------------------------------------------------------------------

(test-equal "the C program compiled against libcurl's headers and ran"
  'ran
  (if (eq? (car oracle) 'answers) 'ran oracle))

(test-equal "the C program answered every question, in order"
  questions
  (map answer-question answers))

;; --- the headers' version, against the library's ------------------------------------------

;; The rule itself, on fixed numbers: with the real headers and library
;; at one version, a comparison turned round would still pass below.
(test-equal "the version rule: headers 0x081400 are newer than a library 0x075500, both named in hex"
  '(headers "0x081400" newer-than library "0x075500")
  (version-verdict #x081400 #x075500))

(test-equal "the version rule: headers older than the library, or the same, are no newer"
  '(no-newer no-newer)
  (list (version-verdict #x075500 #x081400) (version-verdict #x081400 #x081400)))

(test-equal "the headers the C program compiled against are no newer than the libcurl chez-curl loads"
  'no-newer
  headers-against-library)

;; --- each constant and each field, against the headers -------------------------------------

(for-each
 (lambda (check)
   (test-equal (cadr check)
     (header-value (caddr check))
     (scheme-value check)))
 check-list)

(test-end "constants")

(exit (suite-exit-status runner))
