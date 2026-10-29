;; C9. A raise inside get-bytevector-n: read! gives 3 bytes, then raises,
;; then gives 3 more, then 0 for ever. The source's bytes are numbered
;; from 1, so a byte names the read! call that took it.
(import (chezscheme))

(define (say fmt . args)
  (apply printf fmt args)
  (newline)
  (flush-output-port (current-output-port)))

;; Returns the port and a thunk giving the bytes read! has taken from the
;; source so far.
(define (make-port)
  (let ([script '(3 raise 3)] [next 1] [taken '()])
    (define (read! bv start count)
      (let ([step (if (null? script) 0 (car script))])
        (unless (null? script) (set! script (cdr script)))
        (if (eq? step 'raise)
            (raise 'read!-raised)
            (let ([k (fxmin step count)])
              (do ([i 0 (fx+ i 1)]) ((fx= i k))
                (bytevector-u8-set! bv (fx+ start i) (fx+ next i))
                (set! taken (cons (fx+ next i) taken)))
              (set! next (fx+ next k))
              k))))
    (values (make-custom-binary-input-port "c9" read! #f #f #f)
            (lambda () (reverse taken)))))

(define (describe x)
  (cond
    [(bytevector? x) (format "~s" (bytevector->u8-list x))]
    [(eof-object? x) "eof"]
    [else (format "~s" x)]))

;; OP returns what the caller holds: a bytevector, eof, or (n . bytes).
(define (run label op . limit)
  (let-values ([(p taken) (make-port)])
    (let loop ([i 1] [delivered '()])
      (let* ([r (guard (c [#t (list 'raised c)]) (op p))]
             [got (cond
                    [(bytevector? r) (bytevector->u8-list r)]
                    [(and (pair? r) (fixnum? (car r))) (cdr r)]
                    [else '()])]
             [delivered (append delivered got)])
        (say "~a: call ~s -> ~a" label i
             (cond
               [(and (pair? r) (eq? (car r) 'raised)) (format "raised ~s" (cadr r))]
               [(and (pair? r) (fixnum? (car r))) (format "count ~s bytes ~s" (car r) (cdr r))]
               [else (describe r)]))
        (if (or (eof-object? r) (fx= i (if (null? limit) 4 (car limit))))
            (let* ([t (taken)]
                   [lost (filter (lambda (b) (not (memv b delivered))) t)])
              (say "~a: read! took ~s; caller was handed ~s; lost ~s"
                   label t delivered lost))
            (loop (fx+ i 1) delivered))))))

(run "get-bytevector-n 10" (lambda (p) (get-bytevector-n p 10)))
;; The n! and some! forms write into the caller's bytevector; what is
;; there after a raise is reported, but only a returned count hands bytes.
(let ([bv (make-bytevector 10 0)])
  (run "get-bytevector-n! 10"
       (lambda (p)
         (bytevector-fill! bv 0)
         (let ([n (guard (c [#t (say "get-bytevector-n! 10: after the raise the caller's bv holds ~s"
                                     (bytevector->u8-list bv))
                             (raise c)])
                    (get-bytevector-n! p bv 0 10))])
           (if (eof-object? n) n
               (cons n (list-head (bytevector->u8-list bv) n)))))))
(let ([bv (make-bytevector 10 0)])
  (run "get-bytevector-some! 10"
       (lambda (p)
         (let ([n (get-bytevector-some! p bv 0 10)])
           (if (eof-object? n) n
               (cons n (list-head (bytevector->u8-list bv) n)))))))
(run "get-bytevector-some" (lambda (p) (get-bytevector-some p)))
(run "get-bytevector-all" (lambda (p) (get-bytevector-all p)))
(run "get-u8"
     (lambda (p)
       (let ([b (get-u8 p)])
         (if (eof-object? b) b (bytevector b))))
     8)
(say "C9 done")
