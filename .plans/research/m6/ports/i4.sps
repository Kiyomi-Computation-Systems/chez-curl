;; Item 4. A read! that blocks: each call sleep-polls, 5 ms at a time,
;; until 50 ms have passed since it was entered, then answers up to 3
;; bytes. After 9 bytes it answers 0, also after its 50 ms wait.
(import (chezscheme))

(define (say fmt . args)
  (apply printf fmt args)
  (newline)
  (flush-output-port (current-output-port)))

(define (now-ms)
  (let ([t (current-time 'time-monotonic)])
    (+ (* 1000 (time-second t)) (quotient (time-nanosecond t) 1000000))))

(define (make-blocking-port)
  (let ([pos 0] [calls 0] [waited 0] [polls 0])
    (define (read! bv start count)
      (set! calls (fx+ calls 1))
      (let ([t0 (now-ms)])
        (let loop ()
          (when (< (- (now-ms) t0) 50)
            (set! polls (fx+ polls 1))
            (sleep (make-time 'time-duration 5000000 0))
            (loop)))
        (set! waited (+ waited (- (now-ms) t0))))
      (let ([k (fxmin 3 count (fx- 9 pos))])
        (do ([i 0 (fx+ i 1)]) ((fx= i k))
          (bytevector-u8-set! bv (fx+ start i) (fx+ pos i 1)))
        (set! pos (fx+ pos k))
        k))
    (values (make-custom-binary-input-port "i4" read! #f #f #f)
            (lambda () (list calls waited polls)))))

(define (describe x)
  (cond
    [(bytevector? x) (format "~s" (bytevector->u8-list x))]
    [(eof-object? x) "eof"]
    [else (format "~s" x)]))

;; Calls OP on a fresh port until it returns eof, or LIMIT times.
(define (drive label op limit)
  (let-values ([(p stats) (make-blocking-port)])
    (let ([t0 (now-ms)])
      (let loop ([i 1] [results '()])
        (let* ([c0 (car (stats))]
               [t1 (now-ms)]
               [r (op p)]
               [t2 (now-ms)])
          (say "~a: op call ~s -> ~a; read! calls ~s; ~s ms"
               label i (describe r) (fx- (car (stats)) c0) (- t2 t1))
          (if (or (eof-object? r) (fx= i limit))
              (let ([s (stats)])
                (say "~a: totals: op calls ~s read! calls ~s read! wait ~s ms polls ~s wall ~s ms"
                     label i (car s) (cadr s) (caddr s) (- (now-ms) t0)))
              (loop (fx+ i 1) (cons r results))))))))

(drive "get-bytevector-n 10" (lambda (p) (get-bytevector-n p 10)) 10)
(drive "get-bytevector-some" (lambda (p) (get-bytevector-some p)) 10)
(drive "get-u8" (lambda (p) (get-u8 p)) 20)
(drive "get-bytevector-all" (lambda (p) (get-bytevector-all p)) 10)
(say "I4 done")
