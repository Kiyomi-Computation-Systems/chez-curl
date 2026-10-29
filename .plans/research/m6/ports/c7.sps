;; C7. close-port from another thread while read! waits.
;;
;; A and B: the main thread's read! sleep-polls until the closer thread
;; has closed the port, then answers 5 bytes (10..14). A reads with
;; get-u8, B with get-bytevector-some.
;; C: a race on the port's flag word: one thread toggles the eof flag
;; (lookahead-u8 then get-u8, read! answering 0) while the main thread
;; closes the port. A lost closed bit would leave port-closed? #f.
;;
;; Every wait is bounded; a thread's raise is its answer.
(import (chezscheme))

(define (say fmt . args)
  (apply printf fmt args)
  (newline)
  (flush-output-port (current-output-port)))

(define (now-ms)
  (let ([t (current-time 'time-monotonic)])
    (+ (* 1000 (time-second t)) (quotient (time-nanosecond t) 1000000))))

(define (sleep-ms n) (sleep (make-time 'time-duration (* n 1000000) 0)))

(define m (make-mutex))
(define (locked thunk)
  (mutex-acquire m)
  (let ([v (thunk)]) (mutex-release m) v))

;; A cell read and written under M.
(define (make-cell v) (box v))
(define (cell-ref c) (locked (lambda () (unbox c))))
(define (cell-set! c v) (locked (lambda () (set-box! c v))))

;; Polls (cell-ref C) every 5 ms until it is true or LIMIT ms pass.
;; Returns the value, or 'timeout.
(define (await c limit)
  (let ([t0 (now-ms)])
    (let loop ()
      (cond
        [(cell-ref c) => (lambda (v) v)]
        [(> (- (now-ms) t0) limit) 'timeout]
        [else (sleep-ms 5) (loop)]))))

(define (msg c)
  (cond
    [(message-condition? c)
     (list (and (who-condition? c) (condition-who c)) (condition-message c))]
    [else c]))

(define (try thunk)
  (guard (c [#t (list 'raised (msg c))]) (thunk)))

;; One run of A or B. OP is the main thread's first read.
(define (close-during-read label op)
  (let* ([in-read (make-cell #f)]
         [released (make-cell #f)]
         [closer-answer (make-cell #f)]
         [close-saw (make-cell #f)]
         [read!-saw (make-cell #f)]
         [p (make-custom-binary-input-port "c7"
              (lambda (bv start count)
                (cell-set! in-read #t)
                (let ([r (await released 2000)])
                  (cell-set! read!-saw (list 'release r 'port-closed? (port-closed? p-ref))))
                (do ([i 0 (fx+ i 1)]) ((fx= i 5))
                  (bytevector-u8-set! bv (fx+ start i) (fx+ 10 i)))
                (cell-set! in-read #f)
                5)
              #f #f
              (lambda () (cell-set! close-saw (list 'close-called 'read!-running? (cell-ref in-read)))))]
         [_ (set! p-ref p)])
    (fork-thread
      (lambda ()
        (cell-set! closer-answer
          (guard (c [#t (cell-set! released #t) (list 'raised (msg c))])
            (let ([r (await in-read 2000)])
              (if (eq? r 'timeout)
                  (begin (cell-set! released #t) 'never-saw-read!)
                  (begin
                    (close-port p)
                    (let ([closed (port-closed? p)])
                      (cell-set! released #t)
                      (list 'closed 'port-closed? closed)))))))))
    (let* ([r0 (try (lambda () (op p)))]
           [a (await closer-answer 3000)])
      (say "~a: first read -> ~s" label r0)
      (say "~a: closer thread -> ~s" label a)
      (say "~a: close handler -> ~s" label (cell-ref close-saw))
      (say "~a: read! after its wait -> ~s" label (cell-ref read!-saw))
      (say "~a: port-closed? ~s binary-port-input-count ~s" label (port-closed? p)
           (binary-port-input-count p))
      p)))

(define p-ref #f)

;; A: get-u8.
(let ([p (close-during-read "A get-u8" (lambda (p) (get-u8 p)))])
  (let loop ([i 2])
    (unless (fx> i 6)
      (say "A get-u8: get-u8 #~s on the closed port -> ~s" i (try (lambda () (get-u8 p))))
      (loop (fx+ i 1))))
  (say "A get-u8: lookahead-u8 -> ~s" (try (lambda () (lookahead-u8 p))))
  (say "A get-u8: get-bytevector-some -> ~s" (try (lambda () (get-bytevector-some p)))))

;; A': get-u8, then get-bytevector-some while bytes are still buffered.
(let ([p (close-during-read "A' get-u8" (lambda (p) (get-u8 p)))])
  (say "A' get-u8: get-bytevector-some with ~s buffered -> ~s" (binary-port-input-count p)
       (try (lambda () (get-bytevector-some p))))
  (say "A' get-u8: then get-u8 -> ~s" (try (lambda () (get-u8 p)))))

;; B: get-bytevector-some.
(let ([p (close-during-read "B get-bytevector-some"
           (lambda (p) (let ([r (get-bytevector-some p)])
                         (if (bytevector? r) (bytevector->u8-list r) r))))])
  (say "B get-bytevector-some: second get-bytevector-some -> ~s"
       (try (lambda () (get-bytevector-some p))))
  (say "B get-bytevector-some: get-u8 -> ~s" (try (lambda () (get-u8 p)))))

;; C: the flag-word race. MODE 'toggle runs lookahead-u8 then get-u8, so
;; the reader sets and clears the eof flag (a read-modify-write of the
;; port's flag word) each turn. MODE 'get-only runs get-u8 alone: read!
;; answers 0 and get-u8 never sets the eof flag, so the reader never
;; writes the flag word. That is the control.
(define trials 2000)
(define limit 100000)
(define closed-msgs
  '((get-u8 "not permitted on closed port ~s")
    (lookahead-u8 "not permitted on closed port ~s")))
(define (race mode)
  (let loop ([t 0] [lost 0] [raised 0] [other '()] [ran-out 0] [timeouts 0] [lens '()]
             [final-open 0] [close-calls '()])
    (if (fx= t trials)
        (begin
          (say "C race ~s: trials ~s; port-closed? #f right after close-port returned: ~s" mode trials lost)
          (say "C race ~s: reader raised on the closed port ~s; ran ~s iterations with no raise ~s; no answer in 5 s ~s"
               mode raised limit ran-out timeouts)
          (say "C race ~s: reader raised something else: ~s" mode other)
          (say "C race ~s: port-closed? #f once the reader stopped: ~s" mode final-open)
          (say "C race ~s: close calls per trial after a second close-port, counts: ~s" mode
               (let count ([vals '(0 1 2 3)])
                 (if (null? vals) '()
                     (cons (cons (car vals) (length (filter (lambda (x) (eqv? x (car vals))) close-calls)))
                           (count (cdr vals))))))
          (say "C race ~s: reader iterations before the close, min ~s max ~s; closes after the reader had finished ~s"
               mode (apply min lens) (apply max lens)
               (length (filter (lambda (n) (fx= n limit)) lens))))
        (let* ([iters (box 0)]
               [answer (make-cell #f)]
               [closes (box 0)]
               [p (make-custom-binary-input-port "c7-race" (lambda (bv start count) 0) #f #f
                    (lambda () (set-box! closes (fx+ (unbox closes) 1))))])
          (fork-thread
            (lambda ()
              (cell-set! answer
                (guard (c [#t (list 'raised (unbox iters) (msg c))])
                  (let spin ([i 0])
                    (if (fx= i limit)
                        (list 'ran-out i)
                        (begin
                          (when (eq? mode 'toggle) (lookahead-u8 p))
                          (get-u8 p)
                          (set-box! iters (fx+ i 1))
                          (spin (fx+ i 1)))))))))
          ;; Wait, unlocked, for the reader to start, then a varying spin.
          (let wait ([j 0])
            (when (and (fx= (unbox iters) 0) (fx< j 100000000)) (wait (fx+ j 1))))
          (let spin ([j (fx* 37 (fxmodulo t 50))]) (unless (fx= j 0) (spin (fx- j 1))))
          (let* ([before (unbox iters)]
                 [_ (close-port p)]
                 [closed (port-closed? p)]
                 [a (await answer 5000)]
                 [closed-at-end (port-closed? p)])
            (close-port p)
            (let ([raised? (and (pair? a) (eq? (car a) 'raised))])
              (loop (fx+ t 1)
                    (if closed lost (fx+ lost 1))
                    (if (and raised? (member (caddr a) closed-msgs)) (fx+ raised 1) raised)
                    (if (and raised? (not (member (caddr a) closed-msgs))) (cons a other) other)
                    (if (and (pair? a) (eq? (car a) 'ran-out)) (fx+ ran-out 1) ran-out)
                    (if (eq? a 'timeout) (fx+ timeouts 1) timeouts)
                    (cons before lens)
                    (if closed-at-end final-open (fx+ final-open 1))
                    (cons (unbox closes) close-calls))))))))
(race 'get-only)
(race 'toggle)
(say "C7 done")
