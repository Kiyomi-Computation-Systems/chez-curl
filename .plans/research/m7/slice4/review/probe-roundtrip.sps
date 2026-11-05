#!r6rs
;;; M7 slice 4's review: a jar's own read-out, loaded back into a fresh jar,
;;; for server cookies whose names start with a cookie prefix in a case not
;;; its own. libcurl reads a Set-Cookie's prefix in one case and a loaded
;;; line's in another on some versions (read in source: 7.85.0 cookie.c:602
;;; and :962, 8.20.0 :499 and :742, 8.23.0 the same case both ways). One
;;; line each, "probe: CASE RESULT".
;;;
;;;   set     the server's cookies, then the read-out, sorted;
;;;   again   that read-out loaded into a fresh jar, which the rule takes or
;;;           refuses, then the fresh jar's read-out, sorted;
;;;   same    whether the two read-outs are equal.
;;;
;;; Run from a tree's root with src, tests and the SRFI libraries on the
;;; library path (README.md here).
(import (rnrs)
        (only (chezscheme) list-sort)
        (curl)
        (curl-testing)
        (only (curl private counters) native-counts))

(define (say tag x)
  (display "probe: ") (display tag) (display " ") (write x) (newline)
  (flush-output-port (current-output-port)))

(define (refusal e)
  (cond ((curl-request-error? e) (list 'request-refused (curl-request-error-reason e) (curl-request-error-value e)))
        ((curl-transfer-error? e) (list 'transfer-failed (curl-transfer-error-reason e)))
        ((curl-engine-error? e) (list 'engine-error (curl-engine-error-reason e)))
        (else (list 'other (condition? e)))))

(say 'libcurl (libcurl-info-version (loaded-libcurl)))

(call-with-origin
 (lambda (o)
   (let* ((port (number->string (cdr (origin-face o 'http))))
          (e (make-curl-engine)))
     (dynamic-wind
       (lambda () #f)
       (lambda ()
         (let ((jar (make-curl-cookie-jar e))
               (fresh (make-curl-cookie-jar e)))
           (curl-token-await
            (curl-submit e (make-curl-request
                            (string-append "http://a.localhost:" port "/cookies?key=rt"
                                           "&set=__secure-a%3D1" "&set=__SECURE-b%3D1"
                                           "&set=__host-c%3D1%3B%20Path%3D%2F" "&set=__HOST-d%3D1"
                                           "&set=plain%3D1")
                            'proxy #f 'cookie-jar jar 'timeout-ms 20000)))
           (let ((out (list-sort string<? (curl-cookie-jar-cookies jar))))
             (say 'set out)
             (say 'again (guard (x (#t (refusal x)))
                           (curl-cookie-jar-load! fresh out)
                           (list-sort string<? (curl-cookie-jar-cookies fresh))))
             (say 'same (guard (x (#t (refusal x)))
                          (equal? out (list-sort string<? (curl-cookie-jar-cookies fresh))))))))
       (lambda () (curl-engine-stop e))))))
(say 'counts (native-counts))
