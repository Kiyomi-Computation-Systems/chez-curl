;; C8. The interrupt state inside read!, and a collection another thread
;; asks for while read! sleeps.
;;
;; Part 1: read! returns (let ([n (disable-interrupts)]) (enable-interrupts) n)
;; under get-u8 called plainly and inside each wrapper.
;; Part 2: the main thread's read! sleep-polls, 10 ms at a time, until the
;; collector thread answers or a bound passes; the collector thread, 100 ms
;; in, calls (collect) or (collect-rendezvous). Every wait is bounded; a
;; thread's raise is its answer.
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
(define (cell-ref c) (locked (lambda () (unbox c))))
(define (cell-set! c v) (locked (lambda () (set-box! c v))))

(define (msg c)
  (if (message-condition? c)
      (list (and (who-condition? c) (condition-who c)) (condition-message c))
      c))

;; Part 1.
(define seen #f)
(define p1
  (make-custom-binary-input-port "c8-state"
    (lambda (bv start count)
      (set! seen (let ([n (disable-interrupts)]) (enable-interrupts) n))
      (bytevector-u8-set! bv start 1)
      1)
    #f #f #f))
(define m1 (make-mutex))
(define (state label thunk)
  (set! seen 'read!-not-called)
  (thunk)
  (say "part 1: ~a: read! saw disable-count ~s" label seen))
(state "get-u8 plainly" (lambda () (get-u8 p1)))
(state "get-u8 inside critical-section" (lambda () (critical-section (get-u8 p1))))
(state "get-u8 inside two critical-sections"
       (lambda () (critical-section (critical-section (get-u8 p1)))))
(state "get-u8 inside with-interrupts-disabled" (lambda () (with-interrupts-disabled (get-u8 p1))))
(state "get-u8 inside with-mutex" (lambda () (with-mutex m1 (get-u8 p1))))
(state "get-u8 plainly, again" (lambda () (get-u8 p1)))

;; Part 2. KIND is 'collect or 'rendezvous; SECTION? puts the main
;; thread's get-u8 inside critical-section. read! waits at most LIMIT ms.
(define (collect-during-read label kind section? limit)
  (let* ([in-read (box #f)]
         [answer (box #f)]
         [read!-saw (box #f)]
         [p (make-custom-binary-input-port "c8"
              (lambda (bv start count)
                (cell-set! in-read #t)
                (let ([t0 (now-ms)])
                  (let loop ([polls 0])
                    (cond
                      [(cell-ref answer)
                       (cell-set! read!-saw (list 'collector-answered-after (- (now-ms) t0) 'ms polls 'polls))]
                      [(> (- (now-ms) t0) limit)
                       (cell-set! read!-saw (list 'bound-passed-after (- (now-ms) t0) 'ms polls 'polls))]
                      [else (sleep-ms 10) (loop (fx+ polls 1))])))
                (cell-set! in-read #f)
                (bytevector-u8-set! bv start 1)
                1)
              #f #f #f)])
    (fork-thread
      (lambda ()
        (cell-set! answer
          (guard (c [#t (list 'raised (msg c))])
            (sleep-ms 100)
            (let* ([g0 (collections)]
                   [r0 (cell-ref in-read)]
                   [t0 (now-ms)])
              (if (eq? kind 'collect) (collect) (collect-rendezvous))
              (let* ([t1 (now-ms)] [g1 (collections)] [r1 (cell-ref in-read)])
                (list 'ok (- t1 t0) 'ms 'collections (- g1 g0)
                      'main-in-read!-before r0 'after r1)))))))
    (let* ([t0 (now-ms)]
           [r (guard (c [#t (list 'raised (msg c))])
                (if section? (critical-section (get-u8 p)) (get-u8 p)))]
           [t1 (now-ms)]
           [a (let loop ()
                (cond
                  [(cell-ref answer) => (lambda (v) v)]
                  [(> (- (now-ms) t0) 5000) 'HUNG:no-answer-in-5-s]
                  [else (sleep-ms 5) (loop)]))])
      (say "part 2: ~a: get-u8 -> ~s after ~s ms; read! -> ~s" label r (- t1 t0) (cell-ref read!-saw))
      (say "part 2: ~a: collector thread -> ~s" label a))))

(collect-during-read "plain, (collect)" 'collect #f 1000)
(collect-during-read "plain, (collect-rendezvous)" 'rendezvous #f 1000)
(collect-during-read "critical-section, (collect)" 'collect #t 500)
(collect-during-read "critical-section, (collect-rendezvous)" 'rendezvous #t 500)

;; Part 2 again, 20 times each plainly: does (collect) ever find the
;; sleep-polling thread active?
(define (repeat kind n)
  (let loop ([i 0] [ok 0] [raised '()] [hung 0] [ms '()])
    (if (fx= i n)
        (say "part 2 x~s: plain, ~s: ok ~s raised ~s hung ~s; collector ms ~s"
             n kind ok raised hung (reverse ms))
        (let* ([in-read (box #f)]
               [answer (box #f)]
               [p (make-custom-binary-input-port "c8r"
                    (lambda (bv start count)
                      (cell-set! in-read #t)
                      (let ([t0 (now-ms)])
                        (let poll ()
                          (unless (or (cell-ref answer) (> (- (now-ms) t0) 1000))
                            (sleep-ms 10) (poll))))
                      (bytevector-u8-set! bv start 1)
                      1)
                    #f #f #f)])
          (fork-thread
            (lambda ()
              (cell-set! answer
                (guard (c [#t (list 'raised (msg c))])
                  (sleep-ms (fx+ 50 (fx* 3 i)))
                  (let ([t0 (now-ms)])
                    (if (eq? kind 'collect) (collect) (collect-rendezvous))
                    (list 'ok (- (now-ms) t0)))))))
          (get-u8 p)
          (let* ([t0 (now-ms)]
                 [a (let w ()
                      (cond
                        [(cell-ref answer) => (lambda (v) v)]
                        [(> (- (now-ms) t0) 5000) 'hung]
                        [else (sleep-ms 5) (w)]))])
            (cond
              [(eq? a 'hung) (loop (fx+ i 1) ok raised (fx+ hung 1) ms)]
              [(eq? (car a) 'ok) (loop (fx+ i 1) (fx+ ok 1) raised hung (cons (cadr a) ms))]
              [else (loop (fx+ i 1) ok (cons (cadr a) raised) hung ms)]))))))
(repeat 'collect 20)
(repeat 'rendezvous 20)
(say "C8 done")
