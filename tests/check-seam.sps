#!r6rs
;;; make check-seam: reads every .sls file under the directory named on the
;;; command line (make passes src) as data, with Chez's reader, and evaluates
;;; nothing. It names, with the file and the import, each library that breaks
;;; one of these rules (ADR-0007):
;;;
;;;   (a) a (curl ...) library imports an (http-client ...) library;
;;;   (b) an (http-client ...) library imports a (curl ...) library that is not
;;;       public. The public ones are public-curl: at first, (curl) alone;
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
;;;       a library by a route this check does not read.
;;;
;;; The lists are allowlists: a name or a library that is not on one fails,
;;; so a route nobody thought of is closed until a reviewer opens it.
;;; allowed-chez-names holds exactly the names src/ imports from (chezscheme),
;;; public-curl the (curl ...) libraries an (http-client ...) library may
;;; import, and rnrs-libraries the standard libraries. tests/test-check-seam.sps
;;; runs this program on a tree for each rule.
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
;;;     max-depth.
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
(define allowed-chez-names
  '(define-ftype display-condition file-regular? foreign-alloc foreign-entry?
    foreign-free foreign-procedure foreign-ref foreign-sizeof format
    format-condition? ftype-ref getenv load-shared-object machine-type
    make-ftype-pointer scheme-version scheme-version-number threaded?))

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

;; chez-complaints : String (Listof Symbol) Any -> (Listof String)
;; What is wrong with SPEC, an import set of (chezscheme) or (scheme), in the
;; library NAME: its shape, or else each name in it that is not in
;; allowed-chez-names, in order.
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
       (map (lambda (id)
              (string-append path ": " (written name) " imports "
                             (symbol->string id)
                             " from (chezscheme), but allowed-chez-names in"
                             " tests/check-seam.sps does not list it"))
            (remp (lambda (id) (memq id allowed-chez-names)) names))))))

;; import-complaints : String (Listof Symbol) Any -> (Listof String)
;; What is wrong with the import set SPEC of the library NAME.
(define (import-complaints path name spec)
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
      ((family? 'curl imported)
       (if (and (family? 'http-client name) (not (member imported public-curl)))
           (list (string-append path ": " (written name) " imports "
                                (written imported)
                                ", but an (http-client ...) library may"
                                " import only the public (curl ...)"
                                " libraries " (written public-curl)))
           '()))
      ((family? 'http-client imported)
       (if (family? 'curl name)
           (list (string-append path ": " (written name) " imports "
                                (written imported)
                                ", but no (curl ...) library may import"
                                " an (http-client ...) library"))
           '()))
      (else
       (list (string-append path ": " (written name) " imports "
                            (written imported)
                            ", but a library under src/ may import only the"
                            " (rnrs ...) libraries except (rnrs eval),"
                            " (only (chezscheme) name ...), and (curl ...)"
                            " and (http-client ...) libraries"))))))

;; library-complaints : String Any -> (Listof String)
;; What is wrong with the library form FORM, read from PATH: its family, then
;; its imports, in import order.
(define (library-complaints path form)
  (let ((name (reference-name (cadr form))))
    (append
     (if (memq (car name) families)
         '()
         (list (string-append path ": " (written name)
                              " belongs to neither family: the first identifier"
                              " of a library's name under src/ must be "
                              (joined " or " (map symbol->string families)))))
     (apply append
            (map (lambda (spec) (import-complaints path name spec))
                 (cdr (cadddr form)))))))

;; data-complaints : String (Listof Any) -> (Listof String)
(define (data-complaints path data)
  (if (null? data)
      (list (string-append path ": it holds no datum, so it holds no library form"))
      (let loop ((rest data) (n 1))
        (if (null? rest)
            '()
            (append (if (library-form? (car rest))
                        (library-complaints path (car rest))
                        (list (string-append path ": datum " (number->string n)
                                             " is " (abbreviated (car rest))
                                             ", not a library form")))
                    (loop (cdr rest) (+ n 1)))))))

;; check-file : String -> (Pair (Listof String) Natural)
;; The complaints about the file at PATH, and how many libraries it holds.
(define (check-file path)
  (let ((found (read-data path)))
    (if (eq? (car found) 'data)
        (cons (data-complaints path (cadr found))
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
             (results (map check-file files))
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
