;; Whether each name the README's nine blocks use is bound in an environment
;; of (rnrs), (curl), (curl unsupported) and (http-client); then which library
;; of the three exports it, by its own environment.
(import (rnrs) (only (chezscheme) environment eval))
(define names
  '((1 make-curl-request) (2 make-curl-request) (3 make-curl-request)
    (4 make-curl-engine make-curl-cookie-jar curl-token-await curl-submit make-curl-request
       curl-cookie-jar-cookies curl-cookie-jar-load! curl-cookie-jar-close! saved-lines)
    (5 curl-request-with-options make-curl-request)
    (6 make-curl-engine curl-submit make-curl-request curl-token-head-wait curl-head-status
       curl-token-head curl-token-next-piece bytevector? curl-token-outcome)
    (7 make-curl-engine curl-submit make-curl-request curl-token-room-wait curl-token-put-piece!
       string->utf8 curl-token-end-body! curl-token-await)
    (8 call-with-http-session call-with-response-port http-response-status get-bytevector-some
       eof-object?)
    (9 call-with-http-session open-file-input-port http-put get-bytevector-some)))
(define libs '((rnrs) (curl) (curl unsupported) (http-client)))
(define (bound-in lib name)
  (guard (e (#t #f)) (eval name (environment lib)) #t))
(for-each
 (lambda (row)
   (for-each
    (lambda (name)
      (let ((where (filter (lambda (lib) (bound-in lib name)) libs)))
        (display "block ") (display (car row)) (display " ") (display name) (display ": ")
        (write (if (null? where) 'UNBOUND where)) (newline)))
    (cdr row)))
 names)
(display "ok bound check done") (newline)
