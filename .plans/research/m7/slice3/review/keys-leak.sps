#!r6rs
;;; M7 slice 3's review: a proxy URL handed where a key belongs. Each case
;;; gives a request or a session a proxy URL whose password is SECRET in a
;;; plist's key position (the key 'proxy left out, or one value too many),
;;; and prints whether the condition raised, as write, display and
;;; display-condition print it, holds SECRET. Controls: the same mistakes
;;; with a value that is no secret, and the slice's own fixed case.
(import (rnrs)
        (only (chezscheme) display-condition)
        (curl)
        (http-client))

(define secret "Pr0xyS3cr3t")
(define url (string-append "http://alice:" secret "@127.0.0.1:3128/"))
(define nowhere "http://127.0.0.1:1/")

(define (contains? text part)
  (let ((n (string-length text)) (k (string-length part)))
    (let loop ((i 0))
      (and (<= (+ i k) n)
           (or (string=? (substring text i (+ i k)) part) (loop (+ i 1)))))))

(define (printed x)
  (call-with-string-output-port
   (lambda (p)
     (write x p) (newline p) (display x p) (newline p)
     (when (condition? x) (display-condition x p)))))

(define (raised thunk) (guard (e (#t e)) (thunk) 'no-raise))

(define (report name thunk)
  (let* ((c (raised thunk))
         (text (printed c)))
    (display name)
    (display ": ")
    (display (cond ((eq? c 'no-raise) "no raise")
                   ((curl-request-error? c)
                    (call-with-string-output-port
                     (lambda (p) (write (list 'curl-request-error (curl-request-error-field c)
                                              (curl-request-error-reason c)) p))))
                   ((http-request-error? c)
                    (call-with-string-output-port
                     (lambda (p) (write (list 'http-request-error (http-request-error-field c)
                                              (http-request-error-reason c)) p))))
                   (else "another condition")))
    (display (if (contains? text secret) "; secret printed: YES" "; secret printed: no"))
    (newline)
    (when (contains? text secret)
      (display "  printed: ")
      (write (substring text 0 (min 300 (string-length text))))
      (newline))))

(report "make-curl-request, the proxy URL with no key"
        (lambda () (make-curl-request nowhere url)))
(report "make-curl-request, a key, its value, then the proxy URL with no key"
        (lambda () (make-curl-request nowhere 'timeout-ms 5000 url 'x)))
(report "curl-request-with, the proxy URL with no key"
        (lambda () (curl-request-with (make-curl-request nowhere) url "x")))
(report "make-http-session, the proxy URL with no key"
        (lambda () (make-http-session url)))
(report "make-http-session, the proxy URL as a key, a value after it"
        (lambda () (make-http-session url 'x)))
(report "call-with-http-session, the proxy URL with no key, then a procedure"
        (lambda () (call-with-http-session url (lambda (s) 'ran))))
(report "http-get, the proxy URL with no key"
        (lambda ()
          (let ((s (make-http-session)))
            (dynamic-wind (lambda () #f)
                          (lambda () (http-get s nowhere url))
                          (lambda () (http-session-close s))))))
(report "slice 2's credentials, a list with no key, at make-curl-request"
        (lambda () (make-curl-request nowhere (list 'basic "alice" secret))))
(report "slice 2's credentials, a list with no key, at make-http-session"
        (lambda () (make-http-session (list 'basic "alice" secret))))
(report "control: make-curl-request, a symbol with no key"
        (lambda () (make-curl-request nowhere 'proxyy url)))
(report "control: make-curl-request, proxy given twice"
        (lambda () (make-curl-request nowhere 'proxy url 'proxy url)))
(report "control: call-with-http-session, its procedure missing, the URL last (the slice's fix)"
        (lambda () (call-with-http-session 'proxy url)))
