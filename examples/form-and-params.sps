#!r6rs
;;; form-and-params.sps: params on a GET's query, and a form as a POST's body.
;;; The origin's /echo answers with the request it got; this prints a few lines.
;;; Run it from the repository's root, URL the test server's base URL with no
;;; trailing / (docs/README.md says how to start one):
;;;   scheme --libdirs src --program examples/form-and-params.sps URL
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
    ;; params are encoded and appended to the URL's query.
    (let ((echo (lines (http-response-text
                        (http-get session (string-append base "/echo")
                                  'params '(("q" . "chez scheme") ("page" . "2")))))))
      (display (car echo))
      (newline))
    ;; form is sent as application/x-www-form-urlencoded.
    (let ((echo (lines (http-response-text
                        (http-post session (string-append base "/echo")
                                   'form '(("name" . "Ada Lovelace") ("lang" . "Scheme")))))))
      (display (car echo))
      (newline)
      (for-each (lambda (line)
                  (when (starts-with? "Content-Type:" line)
                    (display line)
                    (newline)))
                echo)
      (display (car (reverse echo)))
      (newline))))
