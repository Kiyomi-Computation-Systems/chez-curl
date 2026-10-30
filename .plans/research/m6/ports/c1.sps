;; C1. What read! is handed: count, start, the bytevector's length, and
;; which object the bytevector is.
(import (chezscheme))

(define (say fmt . args)
  (apply printf fmt args)
  (newline)
  (flush-output-port (current-output-port)))

;; A port over TOTAL bytes, byte i being (i mod 256); each read! hands over
;; at most PER-CALL. Returns the port and a thunk giving the calls so far,
;; oldest first, each #(count start bv returned).
(define (make-source-port total per-call)
  (let ([pos 0] [calls '()])
    (define (read! bv start count)
      (let ([k (fxmin count per-call (fx- total pos))])
        (do ([i 0 (fx+ i 1)]) ((fx= i k))
          (bytevector-u8-set! bv (fx+ start i) (fxand (fx+ pos i) 255)))
        (set! pos (fx+ pos k))
        (set! calls (cons (vector count start bv k) calls))
        k))
    (values (make-custom-binary-input-port "c1" read! #f #f #f)
            (lambda () (reverse calls)))))

;; Names a bytevector a read! call saw. FRESH holds the unnamed ones seen
;; so far in this report, in order.
(define (namer p caller result)
  (let ([fresh '()])
    (lambda (bv)
      (cond
        [(eq? bv (binary-port-input-buffer p)) "port-buffer"]
        [(and caller (eq? bv caller)) "caller-bv"]
        [(and (bytevector? result) (eq? bv result)) "the-result"]
        [else
         (let loop ([ls fresh] [i 1])
           (cond
             [(null? ls) (set! fresh (append fresh (list bv)))
                         (format "fresh-~s" i)]
             [(eq? (car ls) bv) (format "fresh-~s" i)]
             [else (loop (cdr ls) (fx+ i 1))]))]))))

(define (report label p calls-before calls caller result)
  (let ([name (namer p caller result)]
        [mine (list-tail calls calls-before)])
    (say "~a: read! calls ~s" label (length mine))
    (let loop ([ls mine] [i 1])
      (unless (null? ls)
        (let ([c (car ls)])
          (say "~a: call ~s count ~s start ~s bvlen ~s bv ~a returned ~s"
               label i (vector-ref c 0) (vector-ref c 1)
               (bytevector-length (vector-ref c 2)) (name (vector-ref c 2))
               (vector-ref c 3)))
        (loop (cdr ls) (fx+ i 1))))))

(define (describe x)
  (cond
    [(bytevector? x) (format "bytevector of ~s" (bytevector-length x))]
    [(eof-object? x) "eof"]
    [else (format "~s" x)]))

;; Does BV[start, start+n) hold bytes FIRST.. of the source?
(define (content-ok? bv start n first)
  (let loop ([i 0])
    (or (fx= i n)
        (and (fx= (bytevector-u8-ref bv (fx+ start i)) (fxand (fx+ first i) 255))
             (loop (fx+ i 1))))))

(say "file-buffer-size ~s custom-port-buffer-size ~s"
     (file-buffer-size) (custom-port-buffer-size))

;; get-u8: two calls, then 127 more.
(let-values ([(p calls) (make-source-port 1000 1000000)])
  (let* ([a (get-u8 p)] [b (get-u8 p)])
    (report "get-u8 x2" p 0 (calls) #f #f)
    (say "get-u8 x2: values ~s ~s" a b)
    (do ([i 0 (fx+ i 1)]) ((fx= i 127)) (get-u8 p))
    (report "get-u8 x129" p 0 (calls) #f #f)))

(let-values ([(p calls) (make-source-port 1000 1000000)])
  (let ([r (lookahead-u8 p)])
    (report "lookahead-u8" p 0 (calls) #f #f)
    (say "lookahead-u8: value ~s" r)))

(let-values ([(p calls) (make-source-port 100000 1000000)])
  (let ([r (get-bytevector-some p)])
    (report "get-bytevector-some" p 0 (calls) #f r)
    (say "get-bytevector-some: result ~a content-ok ~s" (describe r)
         (content-ok? r 0 (bytevector-length r) 0))))

;; get-bytevector-some with bytes already in the port buffer.
(let-values ([(p calls) (make-source-port 100000 1000000)])
  (let* ([a (get-u8 p)] [n0 (length (calls))] [r (get-bytevector-some p)])
    (report "get-u8 then get-bytevector-some" p n0 (calls) #f r)
    (say "get-u8 then get-bytevector-some: get-u8 ~s, result ~a content-ok ~s"
         a (describe r) (content-ok? r 0 (bytevector-length r) 1))))

(let-values ([(p calls) (make-source-port 100000 1000000)])
  (let* ([bv (make-bytevector 1000 0)] [r (get-bytevector-some! p bv 0 1000)])
    (report "get-bytevector-some! 0 1000" p 0 (calls) bv #f)
    (say "get-bytevector-some! 0 1000: result ~s content-ok ~s" r (content-ok? bv 0 r 0))))

(let-values ([(p calls) (make-source-port 100000 1000000)])
  (let* ([bv (make-bytevector 1010 0)] [r (get-bytevector-some! p bv 10 1000)])
    (report "get-bytevector-some! 10 1000" p 0 (calls) bv #f)
    (say "get-bytevector-some! 10 1000: result ~s content-ok ~s" r (content-ok? bv 10 r 0))))

(let-values ([(p calls) (make-source-port 1000 1)])
  (let ([r (get-bytevector-n p 10)])
    (report "get-bytevector-n 10 (1 per read!)" p 0 (calls) #f r)
    (say "get-bytevector-n 10 (1 per read!): result ~a content-ok ~s"
         (describe r) (content-ok? r 0 (bytevector-length r) 0))))

(let-values ([(p calls) (make-source-port 1000 3)])
  (let ([r (get-bytevector-n p 10)])
    (report "get-bytevector-n 10 (3 per read!)" p 0 (calls) #f r)
    (say "get-bytevector-n 10 (3 per read!): result ~a content-ok ~s"
         (describe r) (content-ok? r 0 (bytevector-length r) 0))))

(let-values ([(p calls) (make-source-port 1000 3)])
  (let* ([bv (make-bytevector 10 0)] [r (get-bytevector-n! p bv 0 10)])
    (report "get-bytevector-n! 0 10 (3 per read!)" p 0 (calls) bv #f)
    (say "get-bytevector-n! 0 10 (3 per read!): result ~s content-ok ~s" r (content-ok? bv 0 r 0))))

(let-values ([(p calls) (make-source-port 100000 5000)])
  (let ([r (get-bytevector-n p 20000)])
    (report "get-bytevector-n 20000 (5000 per read!)" p 0 (calls) #f r)
    (say "get-bytevector-n 20000 (5000 per read!): result ~a content-ok ~s"
         (describe r) (content-ok? r 0 (bytevector-length r) 0))))

(let-values ([(p calls) (make-source-port 20000 5000)])
  (let ([r (get-bytevector-all p)])
    (report "get-bytevector-all (20000 bytes, 5000 per read!)" p 0 (calls) #f r)
    (say "get-bytevector-all (20000 bytes, 5000 per read!): result ~a content-ok ~s"
         (describe r) (content-ok? r 0 (bytevector-length r) 0))))

;; When each size is read: the port's buffer when the port is made, the
;; get-bytevector-* size at each call.
(let-values ([(p calls) (parameterize ([custom-port-buffer-size 16])
                          (make-source-port 1000 1000000))])
  (let ([r (get-u8 p)])
    (report "made under custom-port-buffer-size 16, get-u8 outside" p 0 (calls) #f #f)
    (say "made under custom-port-buffer-size 16: (custom-port-buffer-size) now ~s"
         (custom-port-buffer-size))))

(let-values ([(p calls) (make-source-port 100000 1000000)])
  (let ([r (parameterize ([file-buffer-size 100]) (get-bytevector-some p))])
    (report "get-bytevector-some under file-buffer-size 100" p 0 (calls) #f r)
    (say "get-bytevector-some under file-buffer-size 100: result ~a" (describe r))))

(say "C1 done")
