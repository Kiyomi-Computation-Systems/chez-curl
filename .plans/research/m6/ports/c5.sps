;; C5. A write! that raises: are bytes sent twice, and does close-port
;; still call close?
(import (chezscheme))

(define (say fmt . args)
  (apply printf fmt args)
  (newline)
  (flush-output-port (current-output-port)))

(define nothing-raised (string->symbol "nothing-raised"))

;; write! raises when (RAISE? count) holds, else accepts every byte and
;; appends it to SENT. The bytes are 1.. for the first put, 101.. for the
;; second, so a byte names its put.
(define (make-port)
  (let ([sent '()] [calls '()] [raise? (lambda (count) #f)] [closes 0]
        [close-raises? #f])
    (define (write! bv start count)
      (set! calls (cons count calls))
      (if (raise? count)
          (raise 'write!-raised)
          (begin
            (do ([i 0 (fx+ i 1)]) ((fx= i count))
              (set! sent (cons (bytevector-u8-ref bv (fx+ start i)) sent)))
            count)))
    (values (make-custom-binary-output-port "c5" write! #f #f
              (lambda ()
                (set! closes (fx+ closes 1))
                (when close-raises? (raise 'close-raised))))
            (lambda () (reverse sent))
            (lambda () (reverse calls))
            (lambda (f) (set! raise? f))
            (lambda () closes)
            (lambda (b) (set! close-raises? b)))))

(define (fill n first)
  (let ([bv (make-bytevector n)])
    (do ([i 0 (fx+ i 1)]) ((fx= i n) bv)
      (bytevector-u8-set! bv i (fxand (fx+ first i) 255)))))

(define (attempt thunk)
  (guard (c [#t (list 'raised c)]) (thunk) nothing-raised))

;; Summarise SENT as runs: (first-byte . length) for each run of
;; consecutive bytes.
(define (runs ls)
  (if (null? ls) '()
      (let loop ([ls (cdr ls)] [first (car ls)] [prev (car ls)] [len 1] [acc '()])
        (cond
          [(null? ls) (reverse (cons (cons first len) acc))]
          [(fx= (car ls) (fxand (fx+ prev 1) 255)) (loop (cdr ls) first (car ls) (fx+ len 1) acc)]
          [else (loop (cdr ls) (car ls) (car ls) 1 (cons (cons first len) acc))]))))

;; 1. 50 bytes buffered, then a 300-byte put whose write! raises on 300.
(let-values ([(p sent calls set-raise! closes set-close-raises!) (make-port)])
  (put-bytevector p (fill 50 1))
  (say "put 50: write! calls ~s output-index ~s" (calls) (binary-port-output-index p))
  (set-raise! (lambda (count) (fx= count 300)))
  (say "put 300, write! raises on 300: ~s" (attempt (lambda () (put-bytevector p (fill 300 101)))))
  (say "after the raise: write! calls ~s output-index ~s sent so far ~s bytes, runs ~s"
       (calls) (binary-port-output-index p) (length (sent)) (runs (sent)))
  (set-raise! (lambda (count) #f))
  (say "flush with a write! that succeeds: ~s" (attempt (lambda () (flush-output-port p))))
  (say "after the flush: write! calls ~s output-index ~s sent ~s bytes, runs (first . length) ~s"
       (calls) (binary-port-output-index p) (length (sent)) (runs (sent)))
  (let* ([s (sent)] [a (list-head s 50)] [b (list-head (list-tail s 50) 50)])
    (say "the first 50 sent equal the second 50 sent: ~s" (equal? a b))))

;; 2. close-port after a raising flush.
(let-values ([(p sent calls set-raise! closes set-close-raises!) (make-port)])
  (put-bytevector p (fill 10 1))
  (set-raise! (lambda (count) #t))
  (say "10 buffered, flush with a raising write!: ~s" (attempt (lambda () (flush-output-port p))))
  (say "close-port, write! still raising: ~s; close calls ~s port-closed? ~s"
       (attempt (lambda () (close-port p))) (closes) (port-closed? p))
  (say "  write! calls so far ~s; output-index ~s" (calls) (binary-port-output-index p))
  (set-raise! (lambda (count) #f))
  (say "close-port, write! now succeeds: ~s; close calls ~s port-closed? ~s"
       (attempt (lambda () (close-port p))) (closes) (port-closed? p))
  (say "  write! calls ~s sent ~s" (calls) (sent)))

;; 3. A close that raises.
(let-values ([(p sent calls set-raise! closes set-close-raises!) (make-port)])
  (put-bytevector p (fill 5 1))
  (set-close-raises! #t)
  (say "close raises: close-port ~s; close calls ~s port-closed? ~s write! calls ~s"
       (attempt (lambda () (close-port p))) (closes) (port-closed? p) (calls))
  (set-close-raises! #f)
  (say "close-port again: ~s; close calls ~s port-closed? ~s write! calls ~s sent ~s"
       (attempt (lambda () (close-port p))) (closes) (port-closed? p) (calls) (sent)))
(say "C5 done")
