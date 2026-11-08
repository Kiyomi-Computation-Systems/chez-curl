#!r6rs
;;; multipart.sps: a multipart/form-data POST of a string, bytes and a file.
;;; The origin's /parts reports each part it got; this prints those lines.
;;; Run it from the repository's root, URL the test server's base URL with no
;;; trailing / (docs/README.md says how to start one):
;;;   scheme --libdirs src --program examples/multipart.sps URL
(import (rnrs) (http-client))

(define base (cadr (command-line)))

;; lines : String -> (Listof String)
(define (lines text)
  (let loop ((chars (string->list text)) (line '()) (found '()))
    (let ((ended (lambda () (cons (list->string (reverse line)) found))))
      (cond ((null? chars) (reverse (ended)))
            ((char=? (car chars) #\newline) (loop (cdr chars) '() (ended)))
            (else (loop (cdr chars) (cons (car chars) line) found))))))

;; starts-with? : String String -> Boolean
(define (starts-with? prefix text)
  (and (<= (string-length prefix) (string-length text))
       (string=? prefix (substring text 0 (string-length prefix)))))

(call-with-http-session 'timeout-ms 10000
  (lambda (session)
    (let ((response
           (http-post session (string-append base "/parts?key=example-multipart")
                      'multipart
                      '(("title" "Holiday")
                        ("notes" #vu8(104 105) filename "notes.txt")
                        ("doc" (file "examples/data/hello.txt"))
                        ("blob" #vu8(1 2 3) type "application/x-thing")))))
      (display (http-response-status response))
      (newline)
      ;; The report's first line holds the boundary, which changes every
      ;; time: print the part lines alone.
      (for-each (lambda (line)
                  (when (starts-with? "part " line)
                    (display line)
                    (newline)))
                (lines (http-response-text response))))))
