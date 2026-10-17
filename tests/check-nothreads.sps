#!r6rs
;;; make check-nothreads: imports every public library under the directory named
;;; on the command line (make passes src) and requires each import to be refused
;;; by name, as (curl private require-threaded) refuses a Chez that is not
;;; threaded (ADR-0001, harness plan section 4). It is run by CI on a Chez built
;;; with --nothreads, the one place a refusal meets a real non-threaded Chez.
;;; On a threaded Chez every import loads, so it FAILS there, naming each
;;; library: that failure is its red run, and it is why make test does not run
;;; it. tests/test-check-nothreads.sps holds each rule on a fixture tree.
;;;
;;; A public library is any library form, in any .sls file under the directory,
;;; whose name has no private part: (curl) and (http-client) are, (curl private
;;; native) is not. The program finds them by reading the files as data, so a
;;; library a later slice adds is imported with no edit here. It puts the
;;; directory on Chez's library path itself, so one argument says both where to
;;; look and where Chez finds the libraries.
;;;
;;; For each, it evaluates (environment '(rnrs) NAME) inside a guard. That
;;; imports the library without running its body (a body runs only when one of
;;; its bindings is referenced), so it cannot load libcurl, and it raises where
;;; Chez raises an import: while expanding the libraries the import reaches. The
;;; refusal is what that raise must be: a syntax violation, from who chez-curl,
;;; whose message starts with refusal-marker. Anything else, a different message
;;; or who included, is not the refusal and fails, and so does an import that
;;; loads. (curl private require-threaded) refuses at expansion from that exact
;;; condition, and tests/test-require-threaded.sps expands it with (threaded?)
;;; answering #f.
;;;
;;; It fails closed, because a check that passes on nothing is vacuous. It names,
;;; and exits 1 on, each of these:
;;;
;;;   - a public library whose import loaded, or raised something but the
;;;     refusal, with what was raised;
;;;   - no public library under the directory, or no such directory;
;;;   - a .sls file it cannot read as data, a dangling symbolic link among them;
;;;   - a symbolic link to a directory, which it does not follow.
;;;
;;; It prints one line for each public library on stdout when it is refused, and
;;; each problem on stderr and then a count of them on a failure. It exits 0 or
;;; 1, never a count.
(import (rnrs)
        (only (chezscheme) directory-list file-directory? display-condition
              environment library-directories))

;; refusal-marker : String
;; The start of the message of the refusal of a non-threaded Chez. The same text
;; as tests/test-require-threaded.sps's marker.
(define refusal-marker "chez-curl needs a threaded Chez Scheme")

;; refusal-who : Symbol
;; Who raises the refusal: the first argument of its syntax-violation.
(define refusal-who 'chez-curl)

;; describe : Any -> String
(define (describe obj)
  (call-with-string-output-port
    (lambda (p) (if (condition? obj) (display-condition obj p) (write obj p)))))

;; written : Any -> String
(define (written datum)
  (call-with-string-output-port (lambda (p) (write datum p))))

;; starts-with? : String Any -> Boolean
(define (starts-with? prefix s)
  (and (string? s)
       (<= (string-length prefix) (string-length s))
       (string=? prefix (substring s 0 (string-length prefix)))))

;; suffix? : String String -> Boolean
(define (suffix? s suffix)
  (let ((n (string-length s)) (m (string-length suffix)))
    (and (>= n m) (string=? (substring s (- n m) n) suffix))))

;; refusal? : Any -> Boolean
;; Whether E is the refusal of a non-threaded Chez: a syntax violation, from
;; refusal-who, whose message starts with refusal-marker.
(define (refusal? e)
  (and (syntax-violation? e)
       (who-condition? e)
       (eq? (condition-who e) refusal-who)
       (message-condition? e)
       (starts-with? refusal-marker (condition-message e))))

;; import-verdict : (Listof Symbol) -> (U 'refused 'loaded (List 'raised String))
;; What importing the library NAME does: raises the refusal, loads, or raises
;; something else, and what.
(define (import-verdict name)
  (guard (e ((refusal? e) 'refused)
            (#t (list 'raised (describe e))))
    (environment '(rnrs) name)
    'loaded))

;; --- reading the tree -------------------------------------------------------------

;; walk : String -> (List (Listof String) (Listof String))
;; Under DIR, as paths: the .sls files, and the symbolic links to directories.
(define (walk dir)
  (let loop ((names (directory-list dir)) (files '()) (links '()))
    (if (null? names)
        (list files links)
        (let ((path (string-append dir "/" (car names))))
          (cond
            ((file-directory? path #f)
             (let ((below (walk path)))
               (loop (cdr names)
                     (append (car below) files)
                     (append (cadr below) links))))
            ((file-directory? path)
             (loop (cdr names) files (cons path links)))
            ((suffix? (car names) ".sls")
             (loop (cdr names) (cons path files) links))
            (else (loop (cdr names) files links)))))))

;; read-data : String -> (U (List 'data (Listof Any)) (List 'unreadable String))
;; Every datum in the file at PATH, read with Chez's reader.
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

;; reference-name : Any -> (U (Listof Symbol) #f)
;; The name in a library reference: its leading identifiers, so a version
;; reference after them is dropped. #f when it has none.
(define (reference-name ref)
  (and (list? ref)
       (let loop ((rest ref) (found '()))
         (if (and (pair? rest) (symbol? (car rest)))
             (loop (cdr rest) (cons (car rest) found))
             (and (pair? found) (reverse found))))))

;; library-name : Any -> (U (Listof Symbol) #f)
;; The name of DATUM when it is a library form, (library NAME ...), else #f.
(define (library-name datum)
  (and (list? datum)
       (>= (length datum) 2)
       (eq? (car datum) 'library)
       (reference-name (cadr datum))))

;; public? : (Listof Symbol) -> Boolean
;; Whether a library is public: no part of its name is private.
(define (public? name)
  (not (memq 'private name)))

;; public-names : (Listof Any) -> (Listof (Listof Symbol))
;; The names of the public libraries among DATA, in order.
(define (public-names data)
  (filter (lambda (name) (and name (public? name)))
          (map library-name data)))

;; say : Port String -> Unit
(define (say port text)
  (put-string port (string-append "check-nothreads: " text "\n")))

;; main : (Listof String) -> Unit
(define (main args)
  (if (not (= (length args) 1))
      (begin
        (say (current-error-port) "usage: scheme --program tests/check-nothreads.sps DIR")
        (exit 1))
      (let* ((root (car args))
             (found (if (file-directory? root) (walk root) (list '() '())))
             (files (list-sort string<? (car found)))
             (links (list-sort string<? (cadr found)))
             (reads (map (lambda (path) (cons path (read-data path))) files))
             (names (apply append
                           (map (lambda (read)
                                  (if (eq? (cadr read) 'data) (public-names (caddr read)) '()))
                                reads))))
        (library-directories (list root))
        (let* ((verdicts (map (lambda (name) (cons name (import-verdict name))) names))
               (problems
                (append
                 (map (lambda (link)
                        (string-append link ": it is a symbolic link to a directory,"
                                       " which this check does not follow"))
                      links)
                 (apply append
                        (map (lambda (read)
                               (if (eq? (cadr read) 'unreadable)
                                   (list (string-append (car read) ": it cannot be read as data: "
                                                        (caddr read)))
                                   '()))
                             reads))
                 (if (null? names)
                     (list (string-append "no public library under " root
                                          ", so there is nothing to refuse"))
                     '())
                 (apply append
                        (map (lambda (verdict)
                               (let ((name (written (car verdict))) (what (cdr verdict)))
                                 (cond
                                   ((eq? what 'refused) '())
                                   ((eq? what 'loaded)
                                    (list (string-append name " loaded, but a non-threaded"
                                                         " Chez must refuse it")))
                                   (else
                                    (list (string-append name " raised something other than"
                                                         " the refusal: " (cadr what)))))))
                             verdicts)))))
          (for-each (lambda (verdict)
                      (when (eq? (cdr verdict) 'refused)
                        (say (current-output-port)
                             (string-append (written (car verdict)) " is refused by name"))))
                    verdicts)
          (cond
            ((null? problems) (exit 0))
            (else
             (for-each (lambda (p) (say (current-error-port) p)) problems)
             (say (current-error-port)
                  (string-append "FAILED (problems: " (number->string (length problems)) ")"))
             (exit 1)))))))

(main (cdr (command-line)))
