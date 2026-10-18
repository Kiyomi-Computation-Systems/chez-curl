#!r6rs
;;; make check-floors: reads the floors file, the README and every file under
;;; the workflow directory named on the command line (make passes
;;; packaging/floors.sexp, README.org and .github/workflows) and fails, naming
;;; each problem, unless README.org's Requirements section states the floors in
;;; packaging/floors.sexp (the lines (floors)'s requirement-lines writes from
;;; the file, whole, as one list), and no line of any file in the workflow
;;; directory contains either floor's version text, names the keys
;;; CHEZ_VERSION or CURL_FLOOR_VERSION, names node-version, in any case, but
;;; as "node-version: ${{ steps.ID.outputs.NAME }}", or holds a double-quoted
;;; key with an escape: CI states no floor, the build scripts read theirs from
;;; the file, and the Node floor reaches setup-node from a step that runs
;;; scripts/ci/floor.sh node. The rules are in (floors); this program reads
;;; the files, prints, and exits.
;;; tests/test-check-floors.sps holds each rule on texts and runs this program
;;; on fixture directories.
;;;
;;; The workflow directory is read whole: every file in it and in its
;;; subdirectories, whatever its name, in the order of their paths. A symbolic
;;; link to a directory is not followed: it is read as a file, which fails.
;;;
;;; It fails closed, because a check that passes on nothing is vacuous. It
;;; names, and exits 1 on, a file or directory it cannot read, a floors file
;;; with a problem, a README with no "** Requirements" section or the wrong list
;;; in it, a workflow directory that holds no file or no ci.yml, a floor or
;;; one of the two keys written anywhere in it, and a node-version that is no
;;; step's output. A file it cannot read does not stop it comparing the
;;; others.
;;;
;;; It prints one line on a pass, to stdout, naming the files it read under the
;;; workflow directory and the floors it found, or each problem and then a
;;; count of them on a failure, to stderr. It exits 0 or 1, never a count.
(import (rnrs)
        (floors)
        (only (chezscheme) directory-list display-condition file-directory?))

;; describe : Any -> String
(define (describe obj)
  (call-with-string-output-port
    (lambda (p) (if (condition? obj) (display-condition obj p) (write obj p)))))

;; say : Port String -> Unit
(define (say port text)
  (put-string port (string-append "check-floors: " text "\n")))

;; read-text : String -> (U (List 'text String) (List 'unreadable String))
;; The text of the file at PATH, or the problem with reading it.
(define (read-text path)
  (guard (e (#t (list 'unreadable
                      (string-append path ": it cannot be read: " (describe e)))))
    (list 'text (file-text path))))

;; text-or-false : (U (List 'text String) (List 'unreadable String)) -> (U String #f)
(define (text-or-false read)
  (and (eq? (car read) 'text) (cadr read)))

;; walk : String -> (Listof String)
;; Every file under DIR, as a path, in subdirectories too, in no set order.
;; A subdirectory is entered only when it is a directory itself, not a
;; symbolic link to one, which is a file here. It raises when a directory
;; cannot be listed.
(define (walk dir)
  (apply append
         (map (lambda (name)
                (let ((path (string-append dir "/" name)))
                  (if (file-directory? path #f) (walk path) (list path))))
              (directory-list dir))))

;; read-workflows : String
;;   -> (U (List 'files (Listof (List String (U (List 'text String) (List 'unreadable String)))))
;;         (List 'unreadable String))
;; Every file under the workflow directory WDIR, in the order of its path,
;; with its text or the problem with reading it, or the problem with listing
;; the directory.
(define (read-workflows wdir)
  (guard (e (#t (list 'unreadable (string-append wdir ": it cannot be read: " (describe e)))))
    (list 'files
          (map (lambda (path) (list path (read-text path)))
               (list-sort string<? (walk wdir))))))

;; problems : String String String Read Read Workflows -> (Listof String)
;; What is wrong with the floors file at FPATH, the README at RPATH and the
;; files under the workflow directory WDIR, given F, R and W, what reading
;; them found: a Read is what read-text answers, and Workflows what
;; read-workflows answers. A file or directory that cannot be read is a
;; problem of its own, named after the others', the floors file's first, then
;; the README's, then the directory's or its files', in path order. The README
;; and the workflows are each held to the floors file whenever it and they can
;; be read.
(define (problems fpath rpath wdir f r w)
  (let ((files (and (eq? (car w) 'files) (cadr w))))
    (append (if (eq? (car f) 'text)
                (check-floors fpath (cadr f) rpath (text-or-false r) wdir
                              (and files
                                   (map (lambda (file) (list (car file) (text-or-false (cadr file))))
                                        files)))
                (list (cadr f)))
            (if (eq? (car r) 'text) '() (list (cadr r)))
            (if files
                (apply append
                       (map (lambda (file)
                              (if (eq? (car (cadr file)) 'text) '() (list (cadr (cadr file)))))
                            files))
                (list (cadr w))))))

;; read-names : String Workflows -> (Listof String)
;; The paths of the files W found under WDIR, relative to it, in order.
(define (read-names wdir w)
  (let ((skip (+ (string-length wdir) 1)))
    (map (lambda (file) (substring (car file) skip (string-length (car file))))
         (cadr w))))

;; joined : (Listof String) -> String
;; NAMES with ", " between them.
(define (joined names)
  (fold-left (lambda (text name) (if (string=? text "") name (string-append text ", " name)))
             ""
             names))

;; summary : String -> String
;; The floors in the file text FTEXT, which floors-problems accepts: "chez
;; 10.4.0, libcurl 7.85.0, node 20".
(define (summary ftext)
  (let ((floors (parse-floors ftext)))
    (let loop ((rest floors) (text ""))
      (if (null? rest)
          text
          (loop (cdr rest)
                (string-append text (if (string=? text "") "" ", ")
                               (symbol->string (caar rest)) " "
                               (cadar rest)))))))

;; main : (Listof String) -> Unit
(define (main args)
  (if (not (= (length args) 3))
      (begin
        (say (current-error-port)
             "usage: scheme --libdirs tests --program tests/check-floors.sps FLOORS README WORKFLOWS")
        (exit 1))
      (let* ((fpath (car args))
             (rpath (cadr args))
             (wdir (caddr args))
             (f (read-text fpath))
             (r (read-text rpath))
             (w (read-workflows wdir))
             (found (problems fpath rpath wdir f r w)))
        (cond
          ((null? found)
           (say (current-output-port)
                (string-append rpath " and " wdir " (" (joined (read-names wdir w)) ")"
                               " hold the floors in " fpath " (" (summary (cadr f)) ")"))
           (exit 0))
          (else
           (for-each (lambda (p) (say (current-error-port) p)) found)
           (say (current-error-port)
                (string-append "FAILED (problems: " (number->string (length found)) ")"))
           (exit 1))))))

(main (cdr (command-line)))
