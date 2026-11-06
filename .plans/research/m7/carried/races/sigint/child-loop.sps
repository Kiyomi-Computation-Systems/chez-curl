;; child-loop.sps N PROGRAM URL-KIND [ARG] [NAME=VALUE ...]: runs PROGRAM, a
;; SIGINT child, N times under build/carried-races/sigint/interrupt.sh (the
;; suites' interrupt script, 500 ms or CHILD_SIGINT_AFTER s, which then makes
;; the file CHILD_SENT names), with NAME=VALUE in its environment, against a
;; fresh origin: URL-KIND raw-pause is /raw/pause-mid-body?ms=10000 (the
;; http-client children's long drip), http-status /status/200 (the mailbox
;; child's), raw-drip /raw/drip?bytes=20&gap=100 (the engine child's). ARG,
;; when not of the form NAME=VALUE, comes before the URL (the mailbox child's
;; WAIT). Prints (RUN STATUS DATA STDERR) for each, DATA its output read.
(import (chezscheme) (curl-testing))
(define args (command-line-arguments))
(define n (string->number (car args)))
(define program (cadr args))
(define kind (caddr args))
(define rest (cdddr args))
(define (env-pair? s) (and (memv #\= (string->list s)) #t))
(define before (filter (lambda (s) (not (env-pair? s))) rest))
(define envs (filter env-pair? rest))
(define script (call-with-input-file (string-append (or (getenv "CHILD_LOOP_DIR") "build/carried-races/sigint") "/interrupt.sh") get-string-all))
(define (read-all text)
  (let ((port (open-string-input-port text)))
    (let loop ((found '()))
      (let ((datum (guard (e (#t '(unreadable))) (read port))))
        (cond ((eof-object? datum) (reverse found))
              ((equal? datum '(unreadable)) (reverse (cons datum found)))
              (else (loop (cons datum found))))))))
(call-with-origin
 (lambda (o)
   (define (url-of face path)
     (let ((f (origin-face o face)))
       (string-append "http://" (car f) ":" (number->string (cdr f)) path)))
   (define url
     (case (string->symbol kind)
       ((raw-pause) (url-of 'raw "/raw/pause-mid-body?ms=10000"))
       ((http-status) (url-of 'http "/status/200"))
       ((raw-drip) (url-of 'raw "/raw/drip?bytes=20&gap=100"))
       (else (error 'child-loop "no such URL kind" kind))))
   (let loop ((i 1))
     (when (<= i n)
       (let ((r (capture-command (append (list "env") envs
                                         (list "sh" "-c" script "sh" (getenv "CHEZ") "--libdirs" "src:tests:build/scheme-libs"
                                               "--program" program)
                                         before (list url)))))
         (write (list i (car r) (read-all (cadr r)) (caddr r))) (newline) (flush-output-port (current-output-port)))
       (loop (+ i 1))))))
