;; C6. Is a dropped custom port ever closed or flushed: at a collection,
;; or at exit?
(import (chezscheme))

(define (say fmt . args)
  (apply printf fmt args)
  (newline)
  (flush-output-port (current-output-port)))

(define writes 0)
(define closes 0)

(define (make-out)
  (let ([p (make-custom-binary-output-port "c6-out"
             (lambda (bv start count) (set! writes (fx+ writes 1)) count)
             #f #f
             (lambda () (set! closes (fx+ closes 1))))])
    (put-bytevector p (make-bytevector 10 7))
    p))

(define (make-in)
  (make-custom-binary-input-port "c6-in"
    (lambda (bv start count) 0)
    #f #f
    (lambda () (set! closes (fx+ closes 1)))))

;; Control: the counters see an explicit close.
(let ([p (make-out)])
  (close-port p)
  (say "control: one explicit close-port of an output port with 10 buffered: write! calls ~s close calls ~s"
       writes closes))
(let ([p (make-in)])
  (close-port p)
  (say "control: one explicit close-port of an input port: close calls ~s" closes))
(set! writes 0)
(set! closes 0)

;; 1000 of each, held strongly and collected, then dropped and collected.
(define strong
  (let loop ([i 0] [acc '()])
    (if (fx= i 1000)
        acc
        (loop (fx+ i 1) (cons (make-out) (cons (make-in) acc))))))
(define weak (map (lambda (p) (weak-cons p #f)) strong))

(define (live) (let loop ([ls weak] [n 0])
                 (if (null? ls) n
                     (loop (cdr ls) (if (bwp-object? (car (car ls))) n (fx+ n 1))))))

(collect (collect-maximum-generation))
(say "made 2000 ports (1000 output with 10 bytes buffered each), held strongly, after a collection: live ~s; write! calls ~s close calls ~s"
     (live) writes closes)
(set! strong '())
(collect (collect-maximum-generation))
(collect (collect-maximum-generation))
(say "after two (collect (collect-maximum-generation)): live ~s of 2000; write! calls ~s close calls ~s"
     (live) writes closes)

;; At exit: a child program leaves ports open and exits three ways.
(define chez (or (getenv "CHEZ") "scheme"))
(for-each
  (lambda (how)
    (let-values ([(to-stdin from-stdout from-stderr pid)
                  (open-process-ports
                    (format "~a --program c6-child.sps ~a; echo child-exit-status=$?" chez how)
                    (buffer-mode block)
                    (native-transcoder))])
      (close-port to-stdin)
      (let* ([out (get-string-all from-stdout)]
             [err (get-string-all from-stderr)])
        (close-port from-stdout)
        (close-port from-stderr)
        (for-each
          (lambda (line) (say "child ~a stdout: ~a" how line))
          (let split ([s (if (eof-object? out) "" out)] [acc '()] [start 0] [i 0])
            (cond
              [(fx= i (string-length s))
               (reverse (if (fx< start i) (cons (substring s start i) acc) acc))]
              [(char=? (string-ref s i) #\newline)
               (split s (cons (substring s start i) acc) (fx+ i 1) (fx+ i 1))]
              [else (split s acc start (fx+ i 1))])))
        (say "child ~a stderr: ~s" how (if (eof-object? err) "" err)))))
  '(exit falloff raise))
(say "C6 done")
