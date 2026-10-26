;;; The steps test-engine takes before "two caller threads awaiting together",
;;; on one engine, each transfer with VERBOSE 1, so libcurl's own account of
;;; each connection goes to stderr. Then the check's three transfers,
;;; submitted together from this thread. Prints each outcome, by step.
;;;   scheme --libdirs src:tests:SRFI --program .plans/research/reuse/reuse.sps [GAP-MS [N]]
;;; GAP-MS, default 0: a pause before the last step; N, default 8: how many
;;; drips step 3 runs together.
(import (rnrs)
        (only (chezscheme) sleep make-time command-line-arguments iota)
        (curl-testing)
        (curl)
        (curl private engine)
        (curl private transfer)
        (curl private conditions))

(define (request url) (make-transfer-request url 'get '() #f 20000 #f #f #t #f))
(define verbose '(("VERBOSE" . 1)))
(define (outcome token)
  (guard (e ((curl-transfer-error? e)
             (list 'transfer-error (curl-transfer-error-reason e) (curl-transfer-error-code e)))
            (#t (list 'raised)))
    (let ((r (curl-token-await token)))
      (list 'response (transfer-response-status r) (bytevector-length (transfer-response-body r))))))
(define (say . xs) (for-each display xs) (newline) (flush-output-port (current-output-port)))
(define args (command-line-arguments))
(define gap (if (pair? args) (string->number (car args)) 0))
(define n (if (and (pair? args) (pair? (cdr args))) (string->number (cadr args)) 8))

(define engine (make-curl-engine))
(call-with-origin
 (lambda (o)
   (define (url-of face path)
     (let ((f (origin-face o face)))
       (string-append "http://" (car f) ":" (number->string (cdr f)) path)))
   (define status (url-of 'http "/status/200"))
   (define (drip bytes gap)
     (url-of 'raw (string-append "/raw/drip?bytes=" (number->string bytes) "&gap=" (number->string gap))))
   (define (submit url) (curl-engine-submit-with engine (request url) verbose))
   (say "step 1, status: " (outcome (submit status)))
   (say "step 2, one drip: " (outcome (submit (drip 40 10))))
   (let ((ts (map (lambda (i) (submit (drip 40 10))) (iota n))))
     (say "step 3, " n " drips: " (map outcome ts)))
   (when (> gap 0) (sleep (make-time 'time-duration (* 1000000 (mod gap 1000)) (div gap 1000))))
   (let* ((shared (submit (drip 30 10)))
          (own0 (submit status))
          (own1 (submit (drip 20 10))))
     (say "step 4, shared: " (outcome shared) ", status: " (outcome own0) ", drip 20: " (outcome own1)))))
(curl-engine-stop engine)
