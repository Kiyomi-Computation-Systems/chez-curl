#!r6rs
;;; A second request inside one streamed transfer that stream-with-rounds
;;; does not refuse (M6 slice 1's review): a post whose caller names
;;; "Expect: 100-continue", against expect417-server.mjs, which answers it
;;; 417; libcurl then resends the request without the Expect, inside the
;;; same transfer, and the server answers 200. Prints:
;;;
;;;   (version V)
;;;   (head STATUS)                the streamed head's status, or #f
;;;   (body TEXT)                  the pieces, as Latin-1
;;;   (outcome STATUS)             the response's status, or the failure
;;;   (whole STATUS BODY)          the same request with no stream-buffer
;;;
;;; With the server run as "expect417-server.mjs once", the 417 comes once
;;; per connection, and the resend is answered 200.
;;;
;;; Run from a tree's root, in the container:
;;;   scripts/guix-env sh -c 'node .plans/research/m6/slice1-review/expect417-server.mjs > $TMPDIR/p 2>$TMPDIR/s & sleep 1; $CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m6/slice1-review/expect417.sps $(cat $TMPDIR/p); cat $TMPDIR/s; kill %1' < /dev/null
(import (chezscheme) (curl))

(define (show d) (write d) (newline) (flush-output-port (current-output-port)))

(define port (car (command-line-arguments)))
(define url (string-append "http://127.0.0.1:" port "/x"))
(define (latin-1 bv) (list->string (map integer->char (bytevector->u8-list bv))))

(define engine (make-curl-engine))
(show (list 'version (libcurl-info-version (loaded-libcurl))))

(define (request . more)
  (apply make-curl-request url 'method 'post 'body (string->utf8 "hello")
         'headers '(("Expect" . "100-continue")) 'proxy #f 'timeout-ms 10000 more))

(let* ((t (curl-submit engine (request 'stream-buffer 1024)))
       (waited (curl-token-head-wait t 10000))
       (head (curl-token-head t))
       (body (let loop ((acc '()))
               (let ((p (curl-token-next-piece t 10000)))
                 (if (bytevector? p) (loop (append acc (bytevector->u8-list p))) acc))))
       (o (curl-token-outcome t)))
  (show (list 'head (and head (curl-head-status head))))
  (show (list 'body (list->string (map integer->char body))))
  (show (list 'outcome (if (curl-response? o) (curl-response-status o) (condition-message o)))))

(let ((r (guard (e (#t (list 'raised (condition-message e))))
           (curl-token-await (curl-submit engine (request))))))
  (show (if (curl-response? r)
            (list 'whole (curl-response-status r) (latin-1 (curl-response-body r)))
            r)))

(curl-engine-stop engine)
