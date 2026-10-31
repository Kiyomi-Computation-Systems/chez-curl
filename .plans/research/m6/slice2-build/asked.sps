;;; The head's body-asked bit, measured before rows are written (the fix
;;; round's brief): for each case, RUNS times, each on an engine of its
;;; own, a request that streams its response (stream-buffer 1024), waited
;;; for its head with nothing put, then the bit, then the body put and
;;; ended, then the outcome. One line a run.
(import (chezscheme) (curl-testing) (curl) (curl private engine) (curl private counters))
(define runs (string->number (car (command-line-arguments))))
(define pki (make-test-pki))
(define ca (string-append pki "/ca.pem"))
(define (url o face path)
  (let ((f (origin-face o face)))
    (string-append (if (memq face '(https h2)) "https://" "http://") (car f) ":" (number->string (cdr f)) path)))
(define (piece n) (make-bytevector n 7))
(printf "asked libcurl ~a ~a~%" (libcurl-info-version (loaded-libcurl)) (libcurl-info-ssl-version (loaded-libcurl)))
(define cases
  ;; NAME FACE PATH BODY LENGTH
  '((raw-answer-200-close raw "/raw/answer?status=200&close=1" stream #f)
    (raw-answer-413-keep raw "/raw/answer?status=413&close=0" stream #f)
    (h2-answer-200 h2 "/answer?status=200" stream #f)
    (h2-answer-413 h2 "/answer?status=413" stream #f)
    (raw-sink raw "/raw/sink?key=asked-raw" stream 1000)
    (http-sink http "/sink?key=asked-http" stream #f)
    (h2-sink h2 "/sink?key=asked-h2" stream 1000)
    (http-whole http "/sink?key=asked-whole" whole #f)
    (http-zero http "/sink?key=asked-zero" stream 0)
    (http-get http "/seen?key=asked-get" none #f)))
(parameterize ((origin-pki pki))
  (call-with-origin
   (lambda (o)
     (for-each
      (lambda (c)
        (do ((r 1 (+ r 1))) ((> r runs))
          (let* ((own (make-curl-engine))
                 (face (cadr c)) (body (cadddr c)) (length (car (cddddr c)))
                 (base (make-curl-request (url o face (caddr c)) 'proxy #f 'timeout-ms 10000 'stream-buffer 1024
                                          'method (if (eq? body 'none) 'get 'post)))
                 (req (case body
                        ((stream) (curl-request-with base 'body 'stream 'body-length length))
                        ((whole) (curl-request-with base 'body (piece 1000)))
                        (else base)))
                 (req (if (memq face '(https h2)) (curl-request-with req 'ca-file ca) req))
                 (t (curl-submit own req))
                 ;; The sinks answer once the body is in, so feed them first.
                 (fed (and (eq? body 'stream) (memq (car c) '(raw-sink http-sink h2-sink))
                           (begin (curl-token-room-wait t 5000)
                                  (curl-token-put-piece! t (piece (or length 1000)) 5000)
                                  (curl-token-end-body! t) #t)))
                 (waited (curl-token-head-wait t 5000))
                 (head (curl-token-head t))
                 (asked (and head (curl-head-body-asked? head))))
            (when (and (eq? body 'stream) (not fed) (not (eqv? length 0)) (not (curl-token-done? t)))
              (curl-token-put-piece! t (piece 1000) 1000)
              (curl-token-end-body! t))
            (let drain () (when (bytevector? (curl-token-next-piece t 2000)) (drain)))
            (curl-token-wait t 10000)
            (printf "asked case=~a run=~a head=~a asked=~a outcome=~a~%" (car c) r
                    (and head (curl-head-status head)) asked
                    (let ((x (curl-token-outcome t)))
                      (cond ((curl-response? x) (curl-response-status x))
                            ((curl-transfer-error? x) (list (curl-transfer-error-reason x) (curl-transfer-error-code x)))
                            (else x))))
            (curl-engine-stop own))))
      cases))))
(printf "asked counts ~a~%" (native-counts))
