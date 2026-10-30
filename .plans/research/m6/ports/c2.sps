;; C2. EOF is not sticky: read! answers 0, then 3 bytes, then 0, then 3
;; bytes, then 0 for ever. Each operation runs six times on a fresh port;
;; each line names what one operation call returned and the read! answers
;; it took.
(import (chezscheme))

(define (say fmt . args)
  (apply printf fmt args)
  (newline)
  (flush-output-port (current-output-port)))

(define script '(0 3 0 3 0))

;; Returns the port and a thunk giving the answers read! has given so far,
;; oldest first. Data bytes are numbered from 1.
(define (make-scripted-port)
  (let ([left script] [answers '()] [next 1])
    (define (read! bv start count)
      (let* ([want (if (null? left) 0 (car left))]
             [k (fxmin want count)])
        (unless (null? left) (set! left (cdr left)))
        (do ([i 0 (fx+ i 1)]) ((fx= i k))
          (bytevector-u8-set! bv (fx+ start i) (fxand (fx+ next i) 255)))
        (set! next (fx+ next k))
        (set! answers (cons k answers))
        k))
    (values (make-custom-binary-input-port "c2" read! #f #f #f)
            (lambda () (reverse answers)))))

(define (describe x)
  (cond
    [(bytevector? x) (format "bytevector ~s" (bytevector->u8-list x))]
    [(eof-object? x) "eof"]
    [else (format "~s" x)]))

;; Runs the operations NAMES (a list of (name . proc)) in order on one
;; fresh port, one line each.
(define (run-sequence label ops)
  (let-values ([(p answers) (make-scripted-port)])
    (let loop ([ops ops] [i 1] [seen 0])
      (if (null? ops)
          (say "~a: total read! calls ~s" label (length (answers)))
          (let* ([op (car ops)]
                 [r (guard (c [#t (list 'raised (condition-message c))])
                      ((cdr op) p))]
                 [all (answers)]
                 [mine (list-tail all seen)])
            (say "~a: #~s ~a -> ~a; read! answered ~s" label i (car op) (describe r) mine)
            (loop (cdr ops) (fx+ i 1) (length all)))))))

(define (times n op) (if (fx= n 0) '() (cons op (times (fx- n 1) op))))

(define op-get-u8 (cons "get-u8" (lambda (p) (get-u8 p))))
(define op-lookahead (cons "lookahead-u8" (lambda (p) (lookahead-u8 p))))
(define op-port-eof (cons "port-eof?" (lambda (p) (port-eof? p))))
(define op-some (cons "get-bytevector-some" (lambda (p) (get-bytevector-some p))))
(define op-some!
  (cons "get-bytevector-some! 10"
        (lambda (p)
          (let* ([bv (make-bytevector 10 0)] [n (get-bytevector-some! p bv 0 10)])
            (if (eof-object? n) n (list n (bytevector->u8-list bv)))))))
(define op-n10 (cons "get-bytevector-n 10" (lambda (p) (get-bytevector-n p 10))))
(define op-n!10
  (cons "get-bytevector-n! 10"
        (lambda (p)
          (let* ([bv (make-bytevector 10 0)] [n (get-bytevector-n! p bv 0 10)])
            (if (eof-object? n) n (list n (bytevector->u8-list bv)))))))
(define op-n20000 (cons "get-bytevector-n 20000" (lambda (p) (get-bytevector-n p 20000))))
(define op-all (cons "get-bytevector-all" (lambda (p) (get-bytevector-all p))))

(say "script ~s, then 0 for ever" script)
(run-sequence "get-u8" (times 6 op-get-u8))
(run-sequence "lookahead-u8" (times 6 op-lookahead))
(run-sequence "port-eof?" (times 6 op-port-eof))
(run-sequence "lookahead-u8/get-u8"
  (list op-lookahead op-lookahead op-get-u8 op-get-u8 op-lookahead op-get-u8 op-get-u8 op-get-u8 op-get-u8 op-get-u8))
(run-sequence "get-bytevector-some" (times 6 op-some))
(run-sequence "get-bytevector-some!" (times 6 op-some!))
(run-sequence "get-bytevector-n 10" (times 6 op-n10))
(run-sequence "get-bytevector-n! 10" (times 6 op-n!10))
(run-sequence "get-bytevector-n 20000" (times 6 op-n20000))
(run-sequence "get-bytevector-all" (times 6 op-all))
(say "C2 done")
