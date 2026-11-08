#!r6rs
;;; cookie-jar.sps: with (curl), a cookie jar that keeps what a server sets,
;;; sends it back, and takes lines loaded into it. The origin's /cookies
;;; sets the cookies its set= names, and /echo answers the request it got.
;;; Run it from the repository's root, URL the test server's base URL with no
;;; trailing / (docs/README.md says how to start one):
;;;   scheme --libdirs src --program examples/cookie-jar.sps URL
(import (rnrs) (curl))

(define base (cadr (command-line)))

;; starts-with? : String String -> Boolean
(define (starts-with? prefix text)
  (and (<= (string-length prefix) (string-length text))
       (string=? prefix (substring text 0 (string-length prefix)))))

;; lines : String -> (Listof String)
(define (lines text)
  (let loop ((chars (string->list text)) (line '()) (found '()))
    (let ((ended (lambda () (cons (list->string (reverse line)) found))))
      (cond ((null? chars) (reverse (ended)))
            ((char=? (car chars) #\newline) (loop (cdr chars) '() (ended)))
            (else (loop (cdr chars) (cons (car chars) line) found))))))

(define engine (make-curl-engine))
(define jar (make-curl-cookie-jar engine))

;; fetch : String -> Response
(define (fetch path)
  (curl-token-await
   (curl-submit engine (make-curl-request (string-append base path)
                                          'cookie-jar jar 'timeout-ms 10000))))

;; The server sets flavour=oat; Path=/. The jar keeps it.
(display (curl-response-status (fetch "/cookies?key=example-jar&set=flavour%3Doat%3B%20Path%3D%2F")))
(newline)

;; A read-out is a list of Netscape lines, in no fixed order: sort them.
(for-each (lambda (line) (write line) (newline))
          (list-sort string<? (curl-cookie-jar-cookies jar)))

;; The next request through the jar sends the cookie back.
(for-each (lambda (line)
            (when (starts-with? "Cookie:" line)
              (display line)
              (newline)))
          (lines (utf8->string (curl-response-body (fetch "/echo")))))

;; A load takes lines in the form a read-out gives them.
(curl-cookie-jar-load! jar '("127.0.0.1\tFALSE\t/\tFALSE\t0\tsize\tlarge"))
(for-each (lambda (line) (write line) (newline))
          (list-sort string<? (curl-cookie-jar-cookies jar)))

(curl-cookie-jar-close! jar)
(curl-engine-stop engine)
