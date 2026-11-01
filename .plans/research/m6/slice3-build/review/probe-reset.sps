#!r6rs
;;; Review probe: a failure with no head after the drive called the producer.
;;; http-post with a producer, sized 1 MiB in 64 KiB pieces, a retry policy
;;; that retries a post's send-receive failure, to a server that reads 64 KiB
;;; of the body and ends the connection with nothing written. Prints the
;;; call's outcome, the producer's calls, and the uploads the server saw.
(import (chezscheme) (curl) (http-client))
(define (show d) (write d) (newline) (flush-output-port (current-output-port)))
(define (described e)
  (if (condition? e)
      (list (and (who-condition? e) (condition-who e))
            (and (curl-transfer-error? e) (list (curl-transfer-error-reason e) (curl-transfer-error-code e)))
            (and (http-exchange? e) (list 'transfers (http-exchange-transfers e)))
            (and (message-condition? e) (condition-message e)))
      (list 'non-condition e)))
(let-values (((to from err pid) (open-process-ports "exec node build/m6s3r/probe-reset/server.mjs 65536" 'line (native-transcoder))))
  (let* ((port (read from))
         (base (string-append "http://127.0.0.1:" (number->string port)))
         (s (make-http-session 'proxy #f 'timeout-ms 10000
                               'retry (make-http-retry 'attempts 3 'backoff-ms 10 'jitter #f 'methods '(post))))
         (calls 0) (given 0)
         (producer (lambda ()
                     (set! calls (+ calls 1))
                     (if (>= given 1048576) (eof-object)
                         (begin (set! given (+ given 65536)) (make-bytevector 65536 7)))))
         (got (guard (e (#t (list 'raised (described e))))
                (list 'returned (http-response-status (http-post s (string-append base "/up") 'body producer 'body-length 1048576)))))
         (count (utf8->string (http-response-body (http-get s (string-append base "/count"))))))
    (show (list 'outcome got 'producer-calls calls 'server-uploads count))
    (guard (e (#t #f)) (http-get s (string-append base "/quit")))
    (http-session-close s)))
