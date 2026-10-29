;; C3. A bad result from read!: count+1, then -1, then 1.0, then 'x, each
;; under get-u8; then one valid answer. Prints what each raised and the
;; port's state after it.
(import (chezscheme))

(define (say fmt . args)
  (apply printf fmt args)
  (newline)
  (flush-output-port (current-output-port)))

(define nothing-raised (string->symbol "nothing-raised"))

;; ANSWER is a procedure of count giving what read! returns. Each valid
;; answer puts byte 42 at start.
(define answer #f)
(define read!-calls 0)
(define (read! bv start count)
  (set! read!-calls (fx+ read!-calls 1))
  (let ([a (answer count)])
    (when (and (fixnum? a) (fx> a 0) (fx<= a count))
      (bytevector-u8-set! bv start 42))
    a))

(define p (make-custom-binary-input-port "c3" read! #f #f #f))

(define (kind c)
  (list (if (assertion-violation? c) '&assertion 'not-&assertion)
        (if (error? c) '&error 'not-&error)
        (if (violation? c) '&violation 'not-&violation)
        (if (non-continuable-violation? c) '&non-continuable 'not-&non-continuable)))

(define (show label thunk)
  (let* ([before read!-calls]
         [r (guard (c [#t (list 'raised
                                (and (who-condition? c) (condition-who c))
                                (and (message-condition? c) (condition-message c))
                                (and (irritants-condition? c)
                                     (map (lambda (x) (if (port? x) 'the-port x))
                                          (condition-irritants c)))
                                (kind c))])
              (thunk)
              nothing-raised)])
    (say "~a: ~s; read! calls ~s; port-closed? ~s input-size ~s"
         label r (fx- read!-calls before) (port-closed? p) (binary-port-input-size p))))

(define (show-value label thunk)
  (let* ([before read!-calls]
         [r (guard (c [#t (list 'raised (condition-message c))]) (thunk))])
    (say "~a: returned ~s; read! calls ~s; port-closed? ~s"
         label r (fx- read!-calls before) (port-closed? p))))

(set! answer (lambda (count) (fx+ count 1)))
(show "get-u8, read! returns count+1" (lambda () (get-u8 p)))
(set! answer (lambda (count) -1))
(show "get-u8, read! returns -1" (lambda () (get-u8 p)))
(set! answer (lambda (count) 1.0))
(show "get-u8, read! returns 1.0" (lambda () (get-u8 p)))
(set! answer (lambda (count) 'x))
(show "get-u8, read! returns 'x" (lambda () (get-u8 p)))
(set! answer (lambda (count) (fx+ count 1)))
(show "get-bytevector-some, read! returns count+1" (lambda () (get-bytevector-some p)))

;; Continuable? A handler that returns: a non-continuable raise then
;; raises a second condition.
(set! answer (lambda (count) (fx+ count 1)))
(let ([r (guard (c2 [#t (list 'outer-saw
                              (and (message-condition? c2) (condition-message c2))
                              (kind c2))])
           (with-exception-handler
             (lambda (c) 'handler-returned)
             (lambda () (list 'get-u8-returned (get-u8 p)))))])
  (say "handler returns from the count+1 raise: ~s" r))

(set! answer (lambda (count) 1))
(show-value "then read! returns 1 (byte 42)" (lambda () (get-u8 p)))
(set! answer (lambda (count) 0))
(show-value "then read! returns 0" (lambda () (get-u8 p)))
(say "C3 done")
