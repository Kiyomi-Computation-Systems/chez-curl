#!r6rs
;;; M7 slice 3's review: the hatch's CONNECT_TO beside a named proxy. The
;;; slice keeps CONNECT_TO the hatch's; does it change the CONNECT's target
;;; the proxy sees? An https:// URL for the https face through the origin's
;;; http face as the proxy, with and without CONNECT_TO naming the h2 face
;;; for the https face's host and port. Prints each outcome and the proxy's
;;; log lines.
(import (rnrs)
        (only (chezscheme) parameterize)
        (curl)
        (curl unsupported)
        (curl-testing))

(define (split-lines text)
  (let loop ((start 0) (i 0) (found '()))
    (cond ((= i (string-length text))
           (reverse (if (= start i) found (cons (substring text start i) found))))
          ((char=? (string-ref text i) #\newline) (loop (+ i 1) (+ i 1) (cons (substring text start i) found)))
          (else (loop start (+ i 1) found)))))

(define pki (make-test-pki))

(define (run o)
  (define (port face) (number->string (cdr (origin-face o face))))
  (define log-engine (make-curl-engine))
  (define (log-lines)
    (let* ((t (curl-submit log-engine (make-curl-request (string-append "http://127.0.0.1:" (port 'http) "/proxy-log?from=0")
                                                         'proxy #f 'timeout-ms 10000)))
           (r (curl-token-await t)))
      (cdr (split-lines (utf8->string (curl-response-body r))))))
  (define ca (string-append pki "/ca.pem"))
  (define url (string-append "https://127.0.0.1:" (port 'https) "/status/200"))
  (define proxy (string-append "http://127.0.0.1:" (port 'http)))
  (define (fetch request)
    (let* ((e (make-curl-engine))
           (mark (length (log-lines)))
           (t (curl-submit e request)))
      (curl-token-wait t 15000)
      (let ((x (curl-token-outcome t)))
        (curl-engine-stop e)
        (list (cond ((curl-response? x) (list 'response (curl-response-status x) (curl-response-http-version x)))
                    ((curl-transfer-error? x) (list 'failed (curl-transfer-error-code x)))
                    (else x))
              (list-tail (log-lines) mark)))))
  (display "libcurl ") (display (libcurl-info-version (loaded-libcurl))) (newline)
  (let ((base (make-curl-request url 'proxy proxy 'ca-file ca 'timeout-ms 10000)))
    (display "without CONNECT_TO: ") (write (fetch base)) (newline)
    (display "with CONNECT_TO 127.0.0.1:<https>:127.0.0.1:<h2>: ")
    (write (fetch (curl-request-with-options
                   base (list (cons "CONNECT_TO" (list (string-append "127.0.0.1:" (port 'https) ":127.0.0.1:" (port 'h2)))))))))
  (newline)
  (curl-engine-stop log-engine)
  'done)

(display (parameterize ((origin-pki pki)) (call-with-origin run)))
(newline)
