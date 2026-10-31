;;; The head's body-asked bit when the answer is in the socket before
;;; libcurl sends its request's head (round 3's brief): the raw face,
;;; armed by /raw/arm, answers its next connection as it accepts it, before
;;; reading a byte. For STATUS 200 and 413, each framing, sized (1,000) and
;;; chunked, RUNS times, each on an engine of its own: the arm, then a
;;; streamed post with a stream-buffer, waited for its head with nothing
;;; put; the bit; then, while the token is not done, the body put and
;;; ended; the outcome; and whether the read callable was ever called.
(import (chezscheme) (curl-testing) (curl) (curl private engine) (curl private counters))
(define runs (string->number (car (command-line-arguments))))
(define (url o path)
  (let ((f (origin-face o 'raw))) (string-append "http://" (car f) ":" (number->string (cdr f)) path)))
(printf "asked2 libcurl ~a ~a~%" (libcurl-info-version (loaded-libcurl)) (libcurl-info-ssl-version (loaded-libcurl)))
(call-with-origin
 (lambda (o)
   (for-each
    (lambda (status)
      (for-each
       (lambda (framing)
         (do ((r 1 (+ r 1))) ((> r runs))
           (let* ((own (make-curl-engine))
                  (armed (curl-token-await
                          (curl-submit own (make-curl-request (url o (string-append "/raw/arm?status=" (number->string status)))
                                                              'proxy #f 'timeout-ms 10000))))
                  (t (curl-submit own (make-curl-request (url o "/raw/content-length") 'method 'post 'proxy #f
                                                         'timeout-ms 10000 'stream-buffer 1024 'body 'stream
                                                         'body-length (and (eq? framing 'sized) 1000))))
                  (waited (curl-token-head-wait t 5000))
                  (head (curl-token-head t))
                  (bit (if head (curl-head-body-asked? head) 'no-head))
                  (asked-at-head (cdr (assq 'asked (curl-token-upload-stats t)))))
             (unless (curl-token-done? t)
               (curl-token-put-piece! t (make-bytevector 1000 7) 1000)
               (unless (curl-token-done? t) (curl-token-end-body! t)))
             (let drain () (when (bytevector? (curl-token-next-piece t 2000)) (drain)))
             (curl-token-wait t 10000)
             (let ((x (curl-token-outcome t)) (stats (curl-token-upload-stats t)))
               (printf "asked2 status=~a framing=~a run=~a armed=~a head=~a bit=~a asked-by-head-wait=~a ever-asked=~a handed=~a outcome=~a~%"
                       status framing r (curl-response-status armed) (and head (curl-head-status head)) bit asked-at-head
                       (cdr (assq 'asked stats)) (cdr (assq 'handed stats))
                       (cond ((curl-response? x) (curl-response-status x))
                             ((curl-transfer-error? x) (list (curl-transfer-error-reason x) (curl-transfer-error-code x)))
                             (else x))))
             (curl-engine-stop own))))
       '(sized chunked)))
    '(200 413))))
(printf "asked2 counts ~a~%" (native-counts))
