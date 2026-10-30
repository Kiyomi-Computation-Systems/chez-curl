#!r6rs
;; Which Expect values make libcurl wait for a 100 before a POST's body:
;; each value, a whole body, against waits-server.mjs, which answers
;; "waited" or "sent". Prints (VALUE ANSWER) per value.
(import (chezscheme) (curl))
(define (show d) (write d) (newline) (flush-output-port (current-output-port)))
(define port (car (command-line-arguments)))
(define url (string-append "http://127.0.0.1:" port "/x"))
(define engine (make-curl-engine))
(show (list 'version (libcurl-info-version (loaded-libcurl))))
(for-each
 (lambda (value)
   (let ((r (guard (e (#t (list 'raised (condition-message e))))
              (curl-token-await
               (curl-submit engine (make-curl-request url 'method 'post 'body (string->utf8 "hello")
                                                      'headers (list (cons "Expect" value))
                                                      'proxy #f 'timeout-ms 10000))))))
     (show (list value (if (curl-response? r) (utf8->string (curl-response-body r)) r)))))
 '("100-continue" "100-Continue" "x100-continue" "100-continues" "a,100-continue" "a 100-continue"
   "100-continue;q=1" "foo" "100-continu" "1oo-continue" "y100-continuez" "100-continue-x"))
(curl-engine-stop engine)
