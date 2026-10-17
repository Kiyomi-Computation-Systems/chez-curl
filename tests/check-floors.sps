#!r6rs
;;; make check-floors: reads the floors file and the README named on the
;;; command line (make passes packaging/floors.sexp and README.org) and fails,
;;; naming each problem, unless README.org's Requirements section states the
;;; floors in packaging/floors.sexp: the lines (floors)'s requirement-lines
;;; writes from the file, whole, as one list. The rules are in (floors); this
;;; program reads two files, prints, and exits. tests/test-check-floors.sps
;;; holds each rule on texts and runs this program on fixture directories.
;;;
;;; It fails closed, because a check that passes on nothing is vacuous. It
;;; names, and exits 1 on, a file it cannot read, a floors file with a
;;; problem, and a README with no "** Requirements" section or the wrong list
;;; in it.
;;;
;;; It prints one line on a pass, to stdout, naming the floors it found, or
;;; each problem and then a count of them on a failure, to stderr. It exits 0
;;; or 1, never a count.
(import (rnrs)
        (floors)
        (only (chezscheme) display-condition))

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

;; problems : String String -> (Listof String)
;; What is wrong with the floors file at FPATH and the README at RPATH. A file
;; that cannot be read is a problem of its own, and the README is held to the
;; floors file only when both can be read.
(define (problems fpath rpath)
  (let ((f (read-text fpath))
        (r (read-text rpath)))
    (if (and (eq? (car f) 'text) (eq? (car r) 'text))
        (check-floors fpath (cadr f) rpath (cadr r))
        (append (if (eq? (car f) 'text)
                    (floors-problems fpath (cadr f))
                    (list (cadr f)))
                (if (eq? (car r) 'text)
                    '()
                    (list (cadr r)))))))

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
  (if (not (= (length args) 2))
      (begin
        (say (current-error-port)
             "usage: scheme --libdirs tests --program tests/check-floors.sps FLOORS README")
        (exit 1))
      (let* ((fpath (car args))
             (rpath (cadr args))
             (found (problems fpath rpath)))
        (cond
          ((null? found)
           (say (current-output-port)
                (string-append rpath " states the floors in " fpath " ("
                               (summary (file-text fpath)) ")"))
           (exit 0))
          (else
           (for-each (lambda (p) (say (current-error-port) p)) found)
           (say (current-error-port)
                (string-append "FAILED (problems: " (number->string (length found)) ")"))
           (exit 1))))))

(main (cdr (command-line)))
