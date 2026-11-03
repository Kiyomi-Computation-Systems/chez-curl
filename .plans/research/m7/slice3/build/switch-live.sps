#!r6rs
;;; M7 slice 3's fix round: what ADR-0037's decision 11 switch does to
;;; transfers already live on a multiplexed connection. Against the test
;;; origin: A1 and A2 stream https://localhost:<h2>/connection?delay=2500,
;;; each head in before the next, so they share one HTTP/2 connection
;;; where the engine multiplexes; then S, an https:// URL through the http
;;; face's proxy with alice's userinfo, awaited, which below 8.19.0 stops
;;; the engine's multiplexing; then B, https://localhost:<h2>/connection,
;;; direct, awaited while A1 and A2 are live. Each body names its HTTP/2
;;; session. The control runs the same without S. Prints the engine's
;;; multiplexing state before and after S, each outcome and body, and
;;; whether A1 and A2 were still live when B ended.
(import (rnrs)
        (only (chezscheme) parameterize)
        (curl)
        (only (curl private engine) curl-engine-multiplexing)
        (curl-testing))

(define pki (make-test-pki))
(define ca (string-append pki "/ca.pem"))

(define (latin-1 bv) (if (bytevector? bv) (list->string (map integer->char (bytevector->u8-list bv))) bv))

(define (outcome x)
  (cond ((curl-response? x) (list 'response (curl-response-status x) (latin-1 (curl-response-body x))))
        ((curl-transfer-error? x) (list 'failed (curl-transfer-error-code x) (curl-transfer-error-connect-code x)))
        ((condition? x) (list 'raised (describe x)))
        (else x)))

(define (pieces token)
  (let loop ((found '()))
    (let ((p (curl-token-next-piece token 20000)))
      (if (bytevector? p) (loop (append found (bytevector->u8-list p))) (list->string (map integer->char found))))))

(define (run o with-switch)
  (define (port face) (number->string (cdr (origin-face o face))))
  (define (h2 path) (string-append "https://localhost:" (port 'h2) path))
  (define e (make-curl-engine))
  (define (streamed path)
    (curl-submit e (make-curl-request (h2 path) 'proxy #f 'ca-file ca 'timeout-ms 20000 'stream-buffer 4096)))
  (let* ((before (curl-engine-multiplexing e))
         (a1 (streamed "/connection?delay=2500"))
         (h1 (curl-token-head-wait a1 20000))
         (a2 (streamed "/connection?delay=2500"))
         (h2-head (curl-token-head-wait a2 20000))
         (s (and with-switch
                 (outcome (curl-token-await
                           (curl-submit e (make-curl-request (string-append "https://localhost:" (port 'https) "/status/200")
                                                             'proxy (string-append "http://alice:s3cret@127.0.0.1:" (port 'http))
                                                             'ca-file ca 'timeout-ms 20000))))))
         (after (curl-engine-multiplexing e))
         (b (outcome (curl-token-await (curl-submit e (make-curl-request (h2 "/connection") 'proxy #f 'ca-file ca 'timeout-ms 20000)))))
         (live (list (curl-token-done? a1) (curl-token-done? a2)))
         (b1 (pieces a1))
         (b2 (pieces a2))
         (o1 (begin (curl-token-wait a1 20000) (outcome (curl-token-outcome a1))))
         (o2 (begin (curl-token-wait a2 20000) (outcome (curl-token-outcome a2)))))
    (curl-engine-stop e)
    (list (list 'heads (and h1 #t) (and h2-head #t))
          (list 'multiplexing before after)
          (list 's s)
          (list 'b b)
          (list 'a-done-when-b-ended live)
          (list 'a1 b1 o1)
          (list 'a2 b2 o2))))

(display "libcurl ") (display (libcurl-info-version (loaded-libcurl))) (newline)
(parameterize ((origin-pki pki))
  (call-with-origin
   (lambda (o)
     (for-each (lambda (with-switch)
                 (display (if with-switch "with S:" "control, no S:")) (newline)
                 (for-each (lambda (line) (display "  ") (write line) (newline)) (run o with-switch)))
               '(#t #f #t #f)))))
(display "done") (newline)
