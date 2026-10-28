;; child-loop.sps N PROGRAM: runs PROGRAM, a SIGINT child of
;; tests/test-http-client.sps, N times under interrupt.sh against a
;; 10 s drip on a fresh origin, and prints (RUN STATUS STDOUT STDERR) for each.
(import (chezscheme) (curl-testing))
(define args (command-line-arguments))
(define n (string->number (car args)))
(define program (cadr args))
(define script (call-with-input-file "build/m5s1-builder/kept/witness/interrupt.sh" get-string-all))
(call-with-origin
 (lambda (o)
   (define f (origin-face o 'raw))
   (define url (string-append "http://" (car f) ":" (number->string (cdr f)) "/raw/pause-mid-body?ms=10000"))
   (let loop ((i 0))
     (when (< i n)
       (let ((r (capture-command (list "sh" "-c" script "sh" (getenv "CHEZ") "--libdirs" "src:tests:build/scheme-libs"
                                       "--program" program url))))
         (write (list i (car r) (cadr r) (caddr r))) (newline) (flush-output-port (current-output-port)))
       (loop (+ i 1))))))
