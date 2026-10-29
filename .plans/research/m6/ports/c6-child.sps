;; C6's child: opens custom ports, leaves them open, and ends the way its
;; argument names: exit, falloff (the program's end) or raise (an
;; uncaught raise). Any write! or close call prints a line on stdout,
;; through a file descriptor port so that no custom port carries it.
(import (chezscheme))

(define out (standard-output-port (buffer-mode none) (native-transcoder)))

(define (note s) (put-string out s) (put-string out "\n"))

(define held-out
  (let ([p (make-custom-binary-output-port "child-out"
             (lambda (bv start count) (note (format "write! called with ~s bytes" count)) count)
             #f #f
             (lambda () (note "output close called")))])
    (put-bytevector p (make-bytevector 10 7))
    p))

(define held-in
  (make-custom-binary-input-port "child-in"
    (lambda (bv start count) 0) #f #f
    (lambda () (note "input close called"))))

(define how (let ([args (command-line-arguments)]) (if (null? args) "exit" (car args))))

(note (format "child: 10 bytes buffered in ~a; ending by ~a" (port-name held-out) how))
(cond
  [(string=? how "exit") (exit 0)]
  [(string=? how "raise") (raise 'child-raised)]
  [else (void)])
