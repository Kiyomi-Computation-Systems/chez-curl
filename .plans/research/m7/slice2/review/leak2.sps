#!r6rs
;;; A token's irritant prints its engine, and the engine holds other
;;; requests' tokens: does an assertion on a token with no credentials
;;; print another request's password? Needs a server that holds a
;;; connection open on 127.0.0.1:$HOLD_PORT (see leak2.sh).
(import (rnrs) (only (chezscheme) display-condition format getenv) (curl))
(define secret "s3cretOther")
(define (holds? text)
  (let ((n (string-length text)) (k (string-length secret)))
    (let loop ((i 0))
      (and (<= (+ i k) n)
           (or (string=? (substring text i (+ i k)) secret) (loop (+ i 1)))))))
(define port (getenv "HOLD_PORT"))
(define e (make-curl-engine))
(define other (curl-submit e (make-curl-request (string-append "http://127.0.0.1:" port "/") 'proxy #f
                                                'timeout-ms 5000 'credentials (list 'bearer secret))))
(define mine (curl-submit e (make-curl-request (string-append "http://127.0.0.1:" port "/x") 'proxy #f
                                               'timeout-ms 5000)))
(let ((text (guard (c (#t (call-with-string-output-port (lambda (p) (display-condition c p) (newline p) (display "write of the irritants: " p) (write (condition-irritants c) p)))))
              (curl-token-next-piece mine 10) "no-raise")))
  (display (format "full display-condition, ~a chars; another request's secret in it: ~a~%~a~%"
                   (string-length text) (if (holds? text) "YES" "no") text)))
(curl-token-cancel other) (curl-token-cancel mine)
(curl-token-wait other 5000) (curl-token-wait mine 5000)
(curl-engine-stop e)
