#!r6rs
;; Does libcurl add its own Expect: 100-continue to a streamed request with a
;; body, and resend on the 417? PUT 5 bytes, PATCH 5 bytes, POST 5 bytes,
;; POST 1.5 MiB; each streamed, no caller Expect. Prints, per case, the head's
;; status, the body, the outcome.
(import (chezscheme) (curl))
(define (show d) (write d) (newline) (flush-output-port (current-output-port)))
(define port (car (command-line-arguments)))
(define url (string-append "http://127.0.0.1:" port "/x"))
(define engine (make-curl-engine))
(show (list 'version (libcurl-info-version (loaded-libcurl))))
(define (run name method body)
  (let* ((t (curl-submit engine (make-curl-request url 'method method 'body body 'proxy #f
                                                   'timeout-ms 10000 'stream-buffer 1024)))
         (waited (curl-token-head-wait t 10000))
         (head (curl-token-head t))
         (bytes (let loop ((acc '()))
                  (let ((p (curl-token-next-piece t 10000)))
                    (if (bytevector? p) (loop (append acc (bytevector->u8-list p))) acc))))
         (o (curl-token-outcome t)))
    (show (list name (list 'head (and head (curl-head-status head)))
                (list 'body (list->string (map integer->char bytes)))
                (list 'outcome (if (curl-response? o) (curl-response-status o) (condition-message o)))))))
(run 'put-5 'put (string->utf8 "hello"))
(run 'patch-5 'patch (string->utf8 "hello"))
(run 'post-5 'post (string->utf8 "hello"))
(run 'post-1.5MiB 'post (make-bytevector (* 3 512 1024) 65))
(curl-engine-stop engine)
