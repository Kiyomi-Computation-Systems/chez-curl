#!r6rs
;;; What a Bearer token whose first char is LF sends, when the bytes rule
;;; lets it through: run against a mutant tree's src, e.g.
;;;   scripts/guix-env sh -c '$CHEZ --libdirs build/m7s2-review/mut/scan-skips-first/src:tests:build/scheme-libs --program build/m7s2-review/inject.sps' < /dev/null
(import (rnrs) (only (chezscheme) format) (curl-testing) (curl))
(define (latin-1 bytes) (list->string (map integer->char (bytevector->u8-list bytes))))
(call-with-origin
 (lambda (o)
   (let* ((raw (origin-face o 'raw))
          (url (string-append "http://" (car raw) ":" (number->string (cdr raw)) "/raw/echo"))
          (e (make-curl-engine))
          (made (guard (c ((curl-request-error? c) (list 'refused (curl-request-error-reason c))))
                  (make-curl-request url 'proxy #f 'timeout-ms 10000
                                     'credentials (list 'bearer (string #\newline #\X #\- #\I #\n #\j #\: #\space #\1))))))
     (if (curl-request? made)
         (let ((t (curl-submit e made)))
           (curl-token-wait t 15000)
           (let ((r (curl-token-outcome t)))
             (display (format "sent; the raw face echoed:~%~a~%"
                              (if (curl-response? r) (latin-1 (curl-response-body r)) r)))))
         (display (format "~s~%" made)))
     (curl-engine-stop e))))
