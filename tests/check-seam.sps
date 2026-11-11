#!r6rs
;;; make check-seam: reads every .sls file under the directory named on the
;;; command line (make passes src) as data, with Chez's reader, and evaluates
;;; nothing. It names, with the file and the import or the export, each
;;; library that breaks one of these rules (ADR-0007):
;;;
;;;   (a) a (curl ...) library imports an (http-client ...) library;
;;;   (b) an (http-client ...) library imports a (curl ...) library that is not
;;;       public. The public ones are public-curl: (curl) alone;
;;;   (c) a library imports (chezscheme) other than as (only (chezscheme)
;;;       name ...), or names in that list one that is not in
;;;       allowed-chez-names, or imports (rnrs eval). Those reach a library by
;;;       a route this check does not read: a body (import ...), include,
;;;       eval, load, $primitive. (scheme) is (chezscheme) under another name;
;;;   (d) a library belongs to neither family. Its name does not start with
;;;       curl or http-client, so rules (a) and (b) would never look at it,
;;;       and (curl x) could import (util), which imports (http-client);
;;;   (e) a library imports a library that is not on the import allowlist:
;;;       the (rnrs ...) libraries but (rnrs eval), (only (chezscheme) name
;;;       ...), and the (curl ...) and (http-client ...) libraries. Any other,
;;;       (chezscheme csv7) and a third-party library among them, could reach
;;;       a library by a route this check does not read;
;;;   (f) a library imports, from (chezscheme), a name that only some libraries
;;;       may import, and is not one of them. library-only-chez-names holds
;;;       each such name with the libraries that alone may import it. Among them
;;;       are define-ftype, for (curl private layouts) alone; foreign-alloc and
;;;       foreign-free, for (curl private memory) alone, foreign-procedure and
;;;       load-shared-object, for (curl private native) alone, and
;;;       foreign-callable, foreign-callable-entry-point and lock-object, for
;;;       (curl private transfer) alone. A function ftype, (define-ftype F
;;;       (function (int) int)), binds a C entry point or makes a callable
;;;       without foreign-procedure or foreign-callable, so it would dodge the
;;;       conventions table (tests/foreign-conventions.sls) and the load's
;;;       foreign-entry? check. define-ftype is the only way to one: an
;;;       anonymous (function ...) in make-ftype-pointer or ftype-ref is invalid
;;;       syntax, so those two need no rule. tests/test-constants.sps holds
;;;       (curl private layouts) to define-ftype forms of structs of
;;;       primitive-typed fields alone, exporting just their names, and requires
;;;       this rule's entry to name that library alone, so no function ftype,
;;;       and no macro that makes one, exists under src/;
;;;   (g) a library exports a name it imports from (chezscheme), as an
;;;       identifier or as the internal name of a (rename (internal
;;;       external)) spec. Otherwise a library rule (f) lets import a name
;;;       could hand it on to one that may not, and any library could hand
;;;       allowed-chez-names past the seam to a consumer. The names a library
;;;       imports from (chezscheme) are those of its (only (chezscheme) name
;;;       ...) import sets: rule (c) refuses every other import set of
;;;       (chezscheme), each wrapper among them, so no prefix or rename makes
;;;       a local name this rule does not see. An export spec that is neither
;;;       an identifier nor (rename (internal external) ...), the only two
;;;       Chez accepts, is an export it cannot read. This rule does not see a
;;;       macro that a library exports and whose template uses the name: for
;;;       define-ftype, tests/test-constants.sps leaves its one library no
;;;       macro;
;;;   (h) a library imports a (curl ...) or (http-client ...) library that no
;;;       library under the directory defines, an import rules (a) and (b)
;;;       do not refuse already. Chez would load it from another
;;;       directory on its library path, and the suites' path holds tests/:
;;;       a library there, which no rule here reads, could bind anything. A
;;;       library counts as defined wherever under the directory it stands:
;;;       rule (i) then fails any that is not at its name's path, alone in
;;;       its file;
;;;   (i) a file holds more than one library, or a library stands anywhere
;;;       but its name's path: (curl private extra) in curl/private/
;;;       extra.sls, (curl) in curl.sls. Chez looks for a library at that
;;;       path in each library directory in turn, so one defined elsewhere
;;;       under the directory could satisfy rule (h) while another directory
;;;       supplied the library Chez loads.
;;;   (j) a (curl ...) library imports (curl unsupported), the hatch
;;;       (ADR-0009). Rule (b) keeps it from every (http-client ...) library,
;;;       and this rule from every (curl ...) one. It closes that route
;;;       alone: the hatch's procedure is (curl private transfer)'s export
;;;       too, which any (curl ...) library may import, so
;;;       tests/test-unsupported.sps holds (curl)'s exports by what each is
;;;       bound to.
;;;
;;; The lists are allowlists: a name or a library that is not on one fails,
;;; so a route nobody thought of is closed until a reviewer opens it.
;;; allowed-chez-names holds exactly the names src/ imports from (chezscheme),
;;; library-only-chez-names the names among them that only some libraries may
;;; import, public-curl the (curl ...) libraries an (http-client ...) library
;;; may import, and rnrs-libraries the standard libraries.
;;; tests/test-check-seam.sps runs this program on a tree for each rule.
;;;
;;; A library is a (curl ...) library when the first identifier of its name is
;;; curl, so (curl) is one and (curl-testing) is not. Imports are found
;;; through the import-set wrappers for, only, except, prefix, rename and
;;; library, and a version reference after a name is dropped. Tests are
;;; exempt by never being read: they live in tests/, not under src/.
;;;
;;; It fails closed, because a check that passes on nothing is vacuous. It
;;; names, and exits 1 on, each of these:
;;;
;;;   - no .sls file under the directory;
;;;   - a symbolic link to a directory, which it does not follow;
;;;   - a file Chez could load as a library that it does not read: one ending
;;;     in an extension of (library-extensions) but .sls, source (.ss, .scm,
;;;     .sch, .chezscheme.sls) or compiled (.so, .chezscheme.so);
;;;   - a file it cannot read as data, or that holds an #!eof literal, which
;;;     would end the reading early;
;;;   - a datum that is not a (library <name> (export ...) (import ...) ...)
;;;     form, the file's first or any later one: every library form in a file
;;;     is checked;
;;;   - an import it cannot read, which includes one nested deeper than
;;;     max-depth;
;;;   - an export it cannot read.
;;;
;;; A name starting with .# is skipped when it is a dangling symbolic link:
;;; Emacs leaves one, a lock file, beside a source it has open. A regular file
;;; or a directory named .#..., or a link that resolves, is no lock file. Chez
;;; loads a library from .#g.sls as it does from g.sls, so each is read and
;;; checked like any other.
;;;
;;; It prints one verdict on a pass, to stdout, or each problem and then a
;;; count of them on a failure, to stderr. It exits 0 or 1, never a count.
(import (rnrs)
        (only (chezscheme) directory-list file-directory? file-symbolic-link?
              display-condition library-extensions parameterize print-graph))

;; public-curl : (Listof (Listof Symbol))
;; The (curl ...) libraries an (http-client ...) library may import. Adding
;; one is a reviewed change to the seam (ADR-0007).
(define public-curl '((curl)))

;; hatch : (Listof Symbol)
;; The escape hatch's library, which rule (j) keeps from every (curl ...)
;; library, and rule (b) from every (http-client ...) one (ADR-0009). Its
;; procedure is (curl private transfer)'s too: see rule (j).
(define hatch '(curl unsupported))

;; families : (Listof Symbol)
;; The first identifier of a library's name under src/: one of these.
(define families '(curl http-client))

;; chez-names : (Listof (Listof Symbol))
;; The names Chez knows its own library by. (scheme) is (chezscheme).
(define chez-names '((chezscheme) (scheme)))

;; allowed-chez-names : (Listof Symbol)
;; The only names a library under src/ may import from (chezscheme): exactly
;; those src/ imports today. Anything else in (chezscheme) can reach a library
;; this check does not read: import is a body form there, include pulls in a
;; file, eval, interpret, top-level-value and $primitive run code built at run
;; time, load a file. Adding a name is a reviewed change to the seam
;; (ADR-0007), as adding to public-curl is. tests/test-check-seam.sps requires
;; the list to equal the names src/ imports, so an unused name cannot stay.
;; critical-section, and dynamic-wind for its critical? argument, keep an
;; interrupt that escapes from falling between a native object's making and
;; its record, or its free and its record: they run no code built at run
;; time, and reach no library. current-time, time-second and time-nanosecond
;; read the monotonic clock, for a bounded wait's deadline, and run no code
;; either. foreign-entry answers an entry point's address, which native
;; finds in /proc/self/maps to read the loaded libcurl's file: it calls
;; nothing. ftype-sizeof and ftype-set! size and fill the struct curl_blob a
;; blob option takes: they write a field of a block, and run no code.
;; make-pseudo-random-generator and pseudo-random-generator-next! make and
;; draw from a session's jitter generator: they run no code and reach no
;; library, and Chez's random, which draws the same sequence in every
;; process, stays out. current-directory reads the working directory,
;; against which a multipart body's relative path is resolved as the request
;; is made (ADR-0039): read alone, it runs no code.
(define allowed-chez-names
  '(critical-section current-directory current-time define-ftype disable-interrupts display-condition
    dynamic-wind enable-interrupts file-regular? foreign-alloc foreign-callable
    foreign-callable-entry-point foreign-entry foreign-entry? foreign-free foreign-procedure
    foreign-ref foreign-sizeof fork-thread format format-condition? ftype-ref ftype-set!
    ftype-sizeof get-thread-id
    getenv load-shared-object lock-object machine-type make-ftype-pointer
    make-mutex make-pseudo-random-generator make-time pseudo-random-generator-next!
    scheme-version scheme-version-number sleep threaded? time-nanosecond time-second
    with-mutex))

;; library-only-chez-names : (Listof (Pairof Symbol (Listof (Listof Symbol))))
;; Rule (f). Each entry is a name in allowed-chez-names, then one or more
;; libraries that alone may import it from (chezscheme): any other library that
;; does fails.
;; define-ftype is the only way to a function ftype (see the header), so only
;; (curl private layouts), whose define-ftypes tests/test-constants.sps holds
;; to structs, may import it. foreign-alloc and foreign-free belong to (curl
;; private memory), whose blocks are counted: a block allocated anywhere else
;; is one the counters cannot see. foreign-procedure belongs to (curl private
;; native), the only library that calls into libcurl, and the one whose load
;; checks each entry point with foreign-entry? before binding it; and so does
;; foreign-entry, an entry point's address, so no other library reads where
;; libcurl's code lives; and so does load-shared-object, so no other library
;; can load a second libcurl, or anything else, into the process (ADR-0002);
;; and so does ftype-set!, which writes into foreign memory: native fills each
;; struct curl_blob, in a counted block it frees. foreign-callable,
;; foreign-callable-entry-point and lock-object belong to (curl private
;; transfer), whose callables, write-body, read-head, read-body, seek-body and
;; prereq-body, are each locked where it is defined and held to its row in
;; tests/foreign-conventions.sls: a callable made anywhere else is one no lock
;; and no row covers. fork-thread
;; belongs to (curl private engine), whose one thread runs every transfer
;; submitted to it: a thread started anywhere else is one no engine owns. So
;; do disable-interrupts and enable-interrupts, which the engine uses only to
;; ask whether a wait may start: interrupts held off elsewhere could hide
;; every Ctrl-C and collection request. make-pseudo-random-generator and
;; pseudo-random-generator-next! belong to (http-client private call), the
;; high level's library that holds the session: each session's generator is
;; made there and drawn from there alone, under the session's mutex.
;; current-directory belongs to (curl private transfer), where a multipart
;; body's path is resolved, once, as the request is made: a library that read
;; it elsewhere could resolve a path again, against a directory a later chdir
;; moved (ADR-0039). No library imports mutex-acquire, mutex-release,
;; make-condition, condition-wait or condition-broadcast at all: every hold of
;; a mutex is locked's, short and with interrupts off, and a wait polls,
;; sleeping between holds, since a wait that held a mutex deadlocked with a
;; collection (ADR-0013). Adding a name or a library is a reviewed change to
;; the seam (ADR-0007). tests/test-check-seam.sps requires each name to be in
;; allowed-chez-names, and each entry's libraries to be exactly the libraries
;; under src/ that import the name, so no permission stays unused.
(define library-only-chez-names
  '((define-ftype (curl private layouts))
    (foreign-alloc (curl private memory))
    (foreign-free (curl private memory))
    (foreign-procedure (curl private native))
    (foreign-entry (curl private native))
    (load-shared-object (curl private native))
    (ftype-set! (curl private native))
    (foreign-callable (curl private transfer))
    (foreign-callable-entry-point (curl private transfer))
    (lock-object (curl private transfer))
    (current-directory (curl private transfer))
    (fork-thread (curl private engine))
    (disable-interrupts (curl private engine))
    (enable-interrupts (curl private engine))
    (make-pseudo-random-generator (http-client private call))
    (pseudo-random-generator-next! (http-client private call))))

;; rnrs-libraries : (Listof (Listof Symbol))
;; The standard libraries a library under src/ may import: R6RS's, but for
;; (rnrs eval), which eval-libraries names. tests/test-check-seam.sps requires
;; the list to equal the (rnrs ...) libraries Chez has, but that one.
(define rnrs-libraries
  '((rnrs) (rnrs base) (rnrs arithmetic bitwise) (rnrs arithmetic fixnums)
    (rnrs arithmetic flonums) (rnrs bytevectors) (rnrs conditions)
    (rnrs control) (rnrs enums) (rnrs exceptions) (rnrs files)
    (rnrs hashtables) (rnrs io ports) (rnrs io simple) (rnrs lists)
    (rnrs mutable-pairs) (rnrs mutable-strings) (rnrs programs) (rnrs r5rs)
    (rnrs records inspection) (rnrs records procedural)
    (rnrs records syntactic) (rnrs sorting) (rnrs syntax-case) (rnrs unicode)))

;; eval-libraries : (Listof (Listof Symbol))
;; The standard libraries no library under src/ may import. They are named
;; apart from the others on the allowlist for a message of their own.
(define eval-libraries '((rnrs eval)))

;; unread-extensions : (Listof String)
;; The endings of a file Chez could load as a library, but this check does not
;; read. Chez's own list, (library-extensions), pairs each source extension
;; with its compiled one. All but .sls are here, and the longest comes first,
;; so a file is named for its longest ending.
(define unread-extensions
  (list-sort
   (lambda (a b) (> (string-length a) (string-length b)))
   (fold-left (lambda (found ext) (if (member ext found) found (cons ext found)))
              '()
              (remp (lambda (ext) (string=? ext ".sls"))
                    (apply append (map (lambda (pair) (list (car pair) (cdr pair)))
                                       (library-extensions)))))))

;; wrappers : (Listof Symbol)
;; The import-set forms that wrap one import set, in their second element.
;; (library <reference>) wraps a reference, and is handled apart.
(define wrappers '(for only except prefix rename))

;; max-depth : Natural
;; How deep wrappers may nest. A cyclic datum (#0=(only #0# x)) nests for ever.
(define max-depth 32)

;; family? : Symbol (Listof Symbol) -> Boolean
(define (family? first name)
  (and (pair? name) (eq? (car name) first)))

;; written : Any -> String
;; print-graph makes write label a cyclic datum, #0=(only #0# x), where it
;; would warn on stderr and then do the same.
(define (written datum)
  (call-with-string-output-port
    (lambda (p) (parameterize ((print-graph #t)) (write datum p)))))

;; abbreviated : Any -> String
;; DATUM written, cut to 57 characters and three dots when over 60.
(define (abbreviated datum)
  (let ((text (written datum)))
    (if (> (string-length text) 60)
        (string-append (substring text 0 57) "...")
        text)))

;; describe : Any -> String
(define (describe obj)
  (call-with-string-output-port
    (lambda (p) (if (condition? obj) (display-condition obj p) (write obj p)))))

;; suffix? : String String -> Boolean
(define (suffix? s suffix)
  (let ((n (string-length s)) (m (string-length suffix)))
    (and (>= n m) (string=? (substring s (- n m) n) suffix))))

;; prefix? : String String -> Boolean
(define (prefix? s prefix)
  (let ((n (string-length s)) (m (string-length prefix)))
    (and (>= n m) (string=? (substring s 0 m) prefix))))

;; joined : String (Pairof String (Listof String)) -> String
;; The strings, a separator between each two. There is always one.
(define (joined separator strings)
  (fold-left (lambda (text s) (string-append text separator s))
             (car strings)
             (cdr strings)))

;; unread-ending : String -> (U String #f)
;; The first of unread-extensions NAME ends with.
(define (unread-ending name)
  (find (lambda (ext) (suffix? name ext)) unread-extensions))

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

;; lock-file? : String String -> Boolean
;; Whether the entry NAME, at PATH, is an Emacs lock file: named .#..., and a
;; symbolic link to nothing. Chez cannot load a dangling link, so skipping it
;; hides no library.
(define (lock-file? path name)
  (and (prefix? name ".#")
       (file-symbolic-link? path)
       (not (file-exists? path))))

;; walk : String -> (List (Listof String) (Listof String) (Listof String))
;; Under DIR, as paths: the .sls files, the symbolic links to directories, and
;; the files with an unread-extensions ending. A lock-file? is skipped.
(define (walk dir)
  (let loop ((names (directory-list dir)) (files '()) (links '()) (unread '()))
    (if (null? names)
        (list files links unread)
        (let ((path (string-append dir "/" (car names))))
          (cond
            ((lock-file? path (car names))
             (loop (cdr names) files links unread))
            ((file-directory? path #f)
             (let ((below (walk path)))
               (loop (cdr names)
                     (append (car below) files)
                     (append (cadr below) links)
                     (append (caddr below) unread))))
            ((file-directory? path)
             (loop (cdr names) files (cons path links) unread))
            ((unread-ending (car names))
             (loop (cdr names) files links (cons path unread)))
            ((suffix? (car names) ".sls")
             (loop (cdr names) (cons path files) links unread))
            (else (loop (cdr names) files links unread)))))))

;; reference-name : Any -> (U (Listof Symbol) #f)
;; The name in a library reference: its leading identifiers, so a version
;; reference after them is dropped. #f when it has none.
(define (reference-name ref)
  (and (list? ref)
       (let loop ((rest ref) (found '()))
         (if (and (pair? rest) (symbol? (car rest)))
             (loop (cdr rest) (cons (car rest) found))
             (and (pair? found) (reverse found))))))

;; spec-name : Any Natural -> (U (Listof Symbol) #f)
;; The one library an import spec imports, looking through the wrappers. #f
;; when it is no import spec this check can read.
(define (spec-name spec depth)
  (cond
    ((or (not (list? spec)) (null? spec) (> depth max-depth)) #f)
    ((eq? (car spec) 'library)
     (and (= (length spec) 2) (reference-name (cadr spec))))
    ((memq (car spec) wrappers)
     (and (>= (length spec) 2) (spec-name (cadr spec) (+ depth 1))))
    (else (reference-name spec))))

;; headed? : Symbol Any -> Boolean
(define (headed? key form)
  (and (list? form) (pair? form) (eq? (car form) key)))

;; library-form? : Any -> Boolean
(define (library-form? datum)
  (and (list? datum)
       (>= (length datum) 4)
       (eq? (car datum) 'library)
       (reference-name (cadr datum))
       (headed? 'export (caddr datum))
       (headed? 'import (cadddr datum))
       #t))

;; chez-only-names : Import-Spec -> (U (Listof Any) #f)
;; The names in SPEC when it is (only (chezscheme) name ...), and #f for any
;; other import set. (only (scheme) ...) is another set, and so is an only
;; over a wrapper of (chezscheme). SPEC is one spec-name has read, so it is a
;; list, and an only has at least its import set.
(define (chez-only-names spec)
  (and (eq? (car spec) 'only)
       (equal? (reference-name (cadr spec)) '(chezscheme))
       (cddr spec)))

;; cannot-read : String (Listof Symbol) Any -> String
(define (cannot-read path name spec)
  (string-append path ": " (written name)
                 " has an import it cannot read: " (abbreviated spec)))

;; name-complaints : String (Listof Symbol) Symbol -> (Listof String)
;; What is wrong with the library NAME importing ID from (chezscheme): none, or
;; one. ID is not in allowed-chez-names, or it is in library-only-chez-names
;; and NAME is not among the libraries listed with it.
(define (name-complaints path name id)
  (let ((only (assq id library-only-chez-names)))
    (cond
      ((not (memq id allowed-chez-names))
       (list (string-append path ": " (written name) " imports "
                            (symbol->string id)
                            " from (chezscheme), but allowed-chez-names in"
                            " tests/check-seam.sps does not list it")))
      ((and only (not (member name (cdr only))))
       (list (string-append path ": " (written name) " imports "
                            (symbol->string id)
                            " from (chezscheme), but library-only-chez-names in"
                            " tests/check-seam.sps allows it only in "
                            (joined ", " (map written (cdr only))))))
      (else '()))))

;; chez-complaints : String (Listof Symbol) Any -> (Listof String)
;; What is wrong with SPEC, an import set of (chezscheme) or (scheme), in the
;; library NAME: its shape, or else each name in it that is not in
;; allowed-chez-names, or that library-only-chez-names keeps from NAME, in order.
(define (chez-complaints path name spec)
  (let ((names (chez-only-names spec)))
    (cond
      ((not names)
       (list (string-append path ": " (written name) " imports "
                            (abbreviated spec)
                            ", but (chezscheme), and its alias (scheme), may be"
                            " imported only as (only (chezscheme) name ...)")))
      ((not (for-all symbol? names))
       (list (cannot-read path name spec)))
      (else
       (apply append (map (lambda (id) (name-complaints path name id)) names))))))

;; undefined-complaints : String (Listof Symbol) (Listof Symbol) (Listof (Listof Symbol))
;;                        -> (Listof String)
;; Rule (h): the library NAME imports IMPORTED, a family library, and
;; DEFINED, the libraries defined under the directory, lacks it.
(define (undefined-complaints path name imported defined)
  (if (member imported defined)
      '()
      (list (string-append path ": " (written name) " imports " (written imported)
                           ", but no library under src/ defines it, so Chez would load it"
                           " from elsewhere on its library path, which this check does not read"))))

;; import-complaints : String (Listof Symbol) Any (Listof (Listof Symbol)) -> (Listof String)
;; What is wrong with the import set SPEC of the library NAME. DEFINED is
;; the libraries defined under the directory.
(define (import-complaints path name spec defined)
  (let ((imported (spec-name spec 0)))
    (cond
      ((not imported)
       (list (cannot-read path name spec)))
      ((member imported chez-names)
       (chez-complaints path name spec))
      ((member imported eval-libraries)
       (list (string-append path ": " (written name) " imports "
                            (written imported)
                            ", but no library under src/ may import "
                            (written imported))))
      ((member imported rnrs-libraries)
       '())
      ;; Rule (h) names an import no other rule refuses: one refused already
      ;; fails the seam, defined or not.
      ((family? 'curl imported)
       (cond ((and (family? 'http-client name) (not (member imported public-curl)))
              (list (string-append path ": " (written name) " imports "
                                   (written imported)
                                   ", but an (http-client ...) library may"
                                   " import only the public (curl ...)"
                                   " libraries " (written public-curl))))
             ((and (family? 'curl name) (equal? imported hatch))
              (list (string-append path ": " (written name) " imports "
                                   (written imported)
                                   ", the escape hatch, which no (curl ...) library may"
                                   " import, so none can re-export it")))
             (else (undefined-complaints path name imported defined))))
      ((family? 'http-client imported)
       (if (family? 'curl name)
           (list (string-append path ": " (written name) " imports "
                                (written imported)
                                ", but no (curl ...) library may import"
                                " an (http-client ...) library"))
           (undefined-complaints path name imported defined)))
      (else
       (list (string-append path ": " (written name) " imports "
                            (written imported)
                            ", but a library under src/ may import only the"
                            " (rnrs ...) libraries except (rnrs eval),"
                            " (only (chezscheme) name ...), and (curl ...)"
                            " and (http-client ...) libraries"))))))

;; chez-imported : (Listof Any) -> (Listof Symbol)
;; The names SPECS, a library's import sets, take from (chezscheme): each
;; identifier in each (only (chezscheme) name ...) among them. Rule (c)
;; refuses any other import set of (chezscheme), so these are the local
;; names (chezscheme) binds in the library.
(define (chez-imported specs)
  (apply append
         (map (lambda (spec)
                (let ((names (and (member (spec-name spec 0) chez-names)
                                  (chez-only-names spec))))
                  (if names (filter symbol? names) '())))
              specs)))

;; export-pairs : Any -> (U (Listof (Pair Symbol Symbol)) #f)
;; The (internal . external) names the export spec SPEC exports: an
;; identifier exports itself, and (rename (internal external) ...) each
;; pair. #f when SPEC is neither, the only two Chez accepts.
(define (export-pairs spec)
  (cond
    ((symbol? spec) (list (cons spec spec)))
    ((and (list? spec) (pair? spec) (eq? (car spec) 'rename)
          (for-all (lambda (pair)
                     (and (list? pair) (= (length pair) 2)
                          (symbol? (car pair)) (symbol? (cadr pair))))
                   (cdr spec)))
     (map (lambda (pair) (cons (car pair) (cadr pair))) (cdr spec)))
    (else #f)))

;; export-complaints : String (Listof Symbol) Any -> (Listof String)
;; Rule (g): what is wrong with the export clause of the library form FORM,
;; named NAME, in export order. Each spec it cannot read, and each name
;; exported that the library imports from (chezscheme).
(define (export-complaints path name form)
  (let ((chez (chez-imported (cdr (cadddr form)))))
    (apply append
           (map (lambda (spec)
                  (let ((pairs (export-pairs spec)))
                    (if (not pairs)
                        (list (string-append path ": " (written name)
                                             " has an export it cannot read: "
                                             (abbreviated spec)))
                        (apply append
                               (map (lambda (pair)
                                      (if (memq (car pair) chez)
                                          (list (string-append
                                                 path ": " (written name) " exports "
                                                 (symbol->string (car pair))
                                                 (if (eq? (car pair) (cdr pair))
                                                     ""
                                                     (string-append " as " (symbol->string (cdr pair))))
                                                 ", but it imports " (symbol->string (car pair))
                                                 " from (chezscheme), and no library under src/"
                                                 " may export a name it imports from (chezscheme)"))
                                          '()))
                                    pairs)))))
                (cdr (caddr form))))))

;; library-complaints : String Any (Listof (Listof Symbol)) -> (Listof String)
;; What is wrong with the library form FORM, read from PATH: its family, then
;; its imports, in import order, then its exports, in export order.
(define (library-complaints path form defined)
  (let ((name (reference-name (cadr form))))
    (append
     (if (memq (car name) families)
         '()
         (list (string-append path ": " (written name)
                              " belongs to neither family: the first identifier"
                              " of a library's name under src/ must be "
                              (joined " or " (map symbol->string families)))))
     (apply append
            (map (lambda (spec) (import-complaints path name spec defined))
                 (cdr (cadddr form))))
     (export-complaints path name form))))

;; data-complaints : String (Listof Any) (Listof (Listof Symbol)) -> (Listof String)
(define (data-complaints path data defined)
  (if (null? data)
      (list (string-append path ": it holds no datum, so it holds no library form"))
      (let loop ((rest data) (n 1))
        (if (null? rest)
            '()
            (append (if (library-form? (car rest))
                        (library-complaints path (car rest) defined)
                        (list (string-append path ": datum " (number->string n)
                                             " is " (abbreviated (car rest))
                                             ", not a library form")))
                    (loop (cdr rest) (+ n 1)))))))

;; defined-libraries : (Listof String) -> (Listof (Listof Symbol))
;; The name of every library form in FILES, those it can read.
(define (defined-libraries files)
  (apply append
         (map (lambda (path)
                (let ((found (read-data path)))
                  (if (eq? (car found) 'data)
                      (map (lambda (form) (reference-name (cadr form)))
                           (filter library-form? (cadr found)))
                      '())))
              files)))

;; library-path : String (Listof Any) -> String
;; Where Chez, given ROOT as its one library directory (--libdirs src),
;; looks for the library NAME: ROOT, then NAME's identifiers joined by /,
;; then a source ending of (library-extensions). Rule (e)'s companion check
;; refuses every ending but .sls under ROOT, so .sls is the one it loads.
(define (library-path root name)
  (string-append root "/"
                 (joined "/" (map (lambda (part) (if (symbol? part) (symbol->string part) (written part)))
                                  name))
                 ".sls"))

;; placement-complaints : String (Listof Any) String -> (Listof String)
;; Rule (i): the file at PATH holds exactly one library, LIBRARIES being
;; its library forms, and each stands at its name's path below ROOT.
(define (placement-complaints path libraries root)
  (append
   (if (> (length libraries) 1)
       (list (string-append path ": it holds " (number->string (length libraries))
                            " libraries, but Chez loads one library from a file, so each file"
                            " under src/ holds exactly one"))
       '())
   (apply append
          (map (lambda (form)
                 (let* ((name (reference-name (cadr form)))
                        (want (library-path root name)))
                   (if (string=? path want)
                       '()
                       (list (string-append path ": " (written name) " is defined here, but Chez"
                                            " loads it from " want ", its name's path")))))
               libraries))))

;; check-file : String (Listof (Listof Symbol)) String -> (Pair (Listof String) Natural)
;; The complaints about the file at PATH, and how many libraries it holds.
;; DEFINED is the libraries defined under ROOT, the directory.
(define (check-file path defined root)
  (let ((found (read-data path)))
    (if (eq? (car found) 'data)
        (cons (append (data-complaints path (cadr found) defined)
                      (placement-complaints path (filter library-form? (cadr found)) root))
              (length (filter library-form? (cadr found))))
        (cons (list (string-append path ": it cannot be read as data: " (cadr found)))
              0))))

;; say : Port String -> Unit
(define (say port text)
  (put-string port (string-append "check-seam: " text "\n")))

;; main : (Listof String) -> Unit
(define (main args)
  (if (not (= (length args) 1))
      (begin
        (say (current-error-port) "usage: scheme --program tests/check-seam.sps DIR")
        (exit 1))
      (let* ((root (car args))
             (found (if (file-directory? root) (walk root) (list '() '() '())))
             (files (list-sort string<? (car found)))
             (links (list-sort string<? (cadr found)))
             (unread (list-sort string<? (caddr found)))
             (defined (defined-libraries files))
             (results (map (lambda (path) (check-file path defined root)) files))
             (complaints
              (append
               (if (null? files)
                   (list (string-append "no libraries: " root
                                        " holds no .sls file, so there is no seam to check"))
                   '())
               (map (lambda (link)
                      (string-append link ": it is a symbolic link to a directory,"
                                     " which this check does not follow"))
                    links)
               (map (lambda (path)
                      (string-append path ": Chez could load a library from a file"
                                     " ending in " (unread-ending path)
                                     ", and this check does not read one;"
                                     " rename it or keep it out of src/"))
                    unread)
               (apply append (map car results)))))
        (cond
          ((null? complaints)
           (say (current-output-port)
                (string-append "the seam holds ("
                               (number->string (apply + (map cdr results)))
                               " libraries in "
                               (number->string (length files))
                               " files checked)"))
           (exit 0))
          (else
           (for-each (lambda (c) (say (current-error-port) c)) complaints)
           (say (current-error-port)
                (string-append "FAILED (problems: "
                               (number->string (length complaints)) ")"))
           (exit 1))))))

(main (cdr (command-line)))
