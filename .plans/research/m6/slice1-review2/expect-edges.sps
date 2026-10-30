#!r6rs
;;; M6 slice 1's second review: the Expect rule's edges, against
;;; ../slice1-review/expect417-server.mjs (no argument: a 417 for every
;;; request whose Expect is 100-continue, a 200 "second\n" otherwise; it
;;; logs each request's first line on stderr). Each case has a path of its
;;; own, so the server's log names it. Prints, per case:
;;;
;;;   (CASE refused REASON)                     the request was refused
;;;   (CASE stream HEAD BODY OUTCOME)           a streamed response
;;;   (CASE whole STATUS-OR-RAISE)              a whole body
;;;
;;; Run from the repository's root, in the container:
;;;   scripts/guix-env sh -c 'node .plans/research/m6/slice1-review/expect417-server.mjs > $TMPDIR/p 2> $TMPDIR/s & pid=$!; sleep 1; $CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m6/slice1-review2/expect-edges.sps $(cat $TMPDIR/p); sleep 0.2; cat $TMPDIR/s; kill $pid' < /dev/null
(import (chezscheme) (curl))

(define (show d) (write d) (newline) (flush-output-port (current-output-port)))
(define port (car (command-line-arguments)))
(define (url-for name) (string-append "http://127.0.0.1:" port "/" (symbol->string name)))
(define engine (make-curl-engine))
(show (list 'version (libcurl-info-version (loaded-libcurl))))

(define (stream-case name method body headers)
  (let ((r (guard (e ((curl-request-error? e) (list 'refused (curl-request-error-reason e))))
             (apply make-curl-request (url-for name) 'method method 'headers headers 'proxy #f
                    'timeout-ms 10000 'stream-buffer 1024 (if body (list 'body body) '())))))
    (if (and (pair? r) (eq? (car r) 'refused))
        (show (cons name r))
        (let* ((t (curl-submit engine r))
               (waited (curl-token-head-wait t 10000))
               (head (curl-token-head t))
               (bytes (let loop ((acc '()))
                        (let ((p (curl-token-next-piece t 10000)))
                          (if (bytevector? p) (loop (append acc (bytevector->u8-list p))) acc))))
               (o (curl-token-outcome t)))
          (show (list name 'stream (and head (curl-head-status head))
                      (list->string (map integer->char bytes))
                      (if (curl-response? o) (curl-response-status o) (condition-message o))))))))

(define (whole-case name method body headers)
  (let ((r (guard (e (#t (list 'raised (if (message-condition? e) (condition-message e) e))))
             (curl-response-status
              (curl-token-await
               (curl-submit engine (apply make-curl-request (url-for name) 'method method 'headers headers
                                          'proxy #f 'timeout-ms 10000
                                          (if body (list 'body body) '()))))))))
    (show (list name 'whole r))))

(define small (string->utf8 "hello"))
(define big (make-bytevector (* 3 512 1024) 65))

;; The request's own empty Expect, sent as "Expect;": libcurl must neither
;; wait nor add its own, on a small body and past 1 MiB.
(stream-case 'empty-small 'post small '(("Expect" . "")))
(stream-case 'empty-big 'post big '(("Expect" . "")))
;; No caller Expect: the request's "Expect:" keeps libcurl's away.
(stream-case 'none-big-post 'post big '())
(stream-case 'none-big-put 'put big '())
(stream-case 'none-small-put 'put small '())
;; Sanity: the rule refuses.
(stream-case 'refused 'post small '(("Expect" . "100-continue")))
;; Does libcurl resend a request with no body on a 417? The rule refuses a
;; streamed get, head and bodiless delete too, as "libcurl waits for a 100,
;; and resends the request inside the transfer on a 417, whatever the
;; method" (test-stream's test name).
(whole-case 'get-whole 'get #f '(("Expect" . "100-continue")))
(whole-case 'delete-whole 'delete #f '(("Expect" . "100-continue")))
(whole-case 'post-whole 'post small '(("Expect" . "100-continue")))

(curl-engine-stop engine)
