;; C10. A timer expiring as read! returns. A run arms (set-timer T) and
;; makes one read on a fresh port; the timer handler records where it
;; landed and escapes (or, in the control, returns). Where:
;;
;;   before      between set-timer and read!'s first line
;;   in-read!    inside read!, before it takes bytes from the source
;;   after-read! after read! took them: its last lines hold no call and no
;;               loop, so no event check, so this is Chez's code between
;;               read!'s return and the operation's return
;;   after-op    after the operation returned (the caller's straight-line
;;               store of the result comes first), in a 300-turn loop
;;   not-fired   the timer had ticks left when disarmed
;;
;; taken is the bytes read! took from the source; received is what the
;; operation returned to the caller; buffered is what the port's buffer
;; still holds; lost = taken - received - buffered. For get-bytevector-some!
;; in-bv says whether the taken bytes sit in the caller's bytevector.
(import (chezscheme))

(define (say fmt . args)
  (apply printf fmt args)
  (newline)
  (flush-output-port (current-output-port)))

(define src-pos 0)
(define phase 'idle)
(define landed #f)
(define escape #f)
(define escaping #t)
(define no-result (string->symbol "no-result"))
(define op-result no-result)
(define per-call 5)

(define (spin n) (let loop ([i 0]) (unless (fx= i n) (loop (fx+ i 1)))))

;; MODE: 'plain; 'sleepy, which sleep-polls twice before the take; or
;; 'planted, the positive control, which runs a 3-turn loop after the take
;; so that an expiry can land after-read! there.
(define (make-c10-port mode)
  (make-custom-binary-input-port "c10"
    (lambda (bv start count)
      (set! phase 'in-read!)
      (when (eq? mode 'sleepy)
        ;; Two sleep-polls of 1 ms, as a waiting read! would make.
        (sleep (make-time 'time-duration 1000000 0))
        (sleep (make-time 'time-duration 1000000 0)))
      (let ([k (fxmin count per-call)])
        (do ([i 0 (fx+ i 1)]) ((fx= i k))
          (bytevector-u8-set! bv (fx+ start i) (fxand (fx+ src-pos i 1) 255)))
        ;; From here to the return: no call, no loop.
        (set! src-pos (fx+ src-pos k))
        (set! phase 'after-read!)
        (when (eq? mode 'planted) (spin 3))
        k))
    #f #f #f))

(timer-interrupt-handler
  (lambda ()
    (set! landed phase)
    (when escaping (escape 'escaped))))

(define (op-of kind)
  (case kind
    [(some) (lambda (p bv) (get-bytevector-some p))]
    [(some!) (lambda (p bv) (get-bytevector-some! p bv 0 100))]
    [(get-u8) (lambda (p bv) (get-u8 p))]))

(define (received-of kind r)
  (cond
    [(eq? r no-result) 0]
    [(eof-object? r) 0]
    [(eq? kind 'some) (bytevector-length r)]
    [(eq? kind 'some!) r]
    [(eq? kind 'get-u8) 1]))

(define (bv-holds? bv n)
  (let loop ([i 0])
    (or (fx= i n)
        (and (fx= (bytevector-u8-ref bv i) (fxand (fx+ i 1) 255)) (loop (fx+ i 1))))))

;; One run: #(T landed how taken received buffered lost in-bv left).
(define (run-once kind t mode)
  (let* ([p (make-c10-port mode)]
         [bv (make-bytevector 100 0)]
         [op (op-of kind)])
    (set! src-pos 0)
    (set! landed #f)
    (set! op-result no-result)
    (let ([how (call/cc
                 (lambda (k)
                   (set! escape k)
                   (set! phase 'before)
                   (set-timer t)
                   (let ([r (op p bv)])
                     (set! op-result r)
                     (set! phase 'after-op)
                     (spin 300)
                     'returned)))])
      (let ([left (set-timer 0)])
        (set! phase 'idle)
        (let* ([taken src-pos]
               [received (received-of kind op-result)]
               [buffered (binary-port-input-count p)]
               [lost (fx- taken (fx+ received buffered))]
               [in-bv (if (and (eq? kind 'some!) (fx> taken 0)) (bv-holds? bv taken) '-)])
          (vector t (or landed 'not-fired) how taken received buffered lost in-bv left))))))

(define (key r) (list (vector-ref r 1) (vector-ref r 2) (vector-ref r 3) (vector-ref r 4)
                      (vector-ref r 5) (vector-ref r 6) (vector-ref r 7)))

(define (show-key k)
  (format "landed ~a ~a taken ~s received ~s buffered ~s lost ~s in-bv ~a"
          (list-ref k 0) (list-ref k 1) (list-ref k 2) (list-ref k 3)
          (list-ref k 4) (list-ref k 5) (list-ref k 6)))

;; Prints the runs as bands of consecutive runs with one key.
(define (bands label runs)
  (let loop ([rs runs] [cur #f] [from #f] [to #f] [n 0])
    (define (flush) (when cur (say "~a: T ~s..~s (~s runs): ~a" label from to n (show-key cur))))
    (cond
      [(null? rs) (flush)]
      [(equal? (key (car rs)) cur) (loop (cdr rs) cur from (vector-ref (car rs) 0) (fx+ n 1))]
      [else (flush)
            (loop (cdr rs) (key (car rs)) (vector-ref (car rs) 0) (vector-ref (car rs) 0) 1)])))

(define (sweep kind mode from to step)
  (let loop ([t from] [acc '()])
    (if (> t to) (reverse acc)
        (loop (+ t step) (cons (run-once kind t mode) acc)))))

(define (totals label runs)
  (let ([count (lambda (pred) (length (filter pred runs)))])
    (say "~a: runs ~s; landed before ~s in-read! ~s after-read! ~s after-op ~s not-fired ~s; runs that lost bytes ~s, bytes lost ~s"
         label (length runs)
         (count (lambda (r) (eq? (vector-ref r 1) 'before)))
         (count (lambda (r) (eq? (vector-ref r 1) 'in-read!)))
         (count (lambda (r) (eq? (vector-ref r 1) 'after-read!)))
         (count (lambda (r) (eq? (vector-ref r 1) 'after-op)))
         (count (lambda (r) (eq? (vector-ref r 1) 'not-fired)))
         (count (lambda (r) (fx> (vector-ref r 6) 0)))
         (apply + (map (lambda (r) (vector-ref r 6)) runs)))))

;; The first coarse tick at which the expiry landed past read!'s take:
;; after-read!, after-op or not at all.
(define (boundary runs)
  (let loop ([rs runs])
    (cond
      [(null? rs) #f]
      [(memq (vector-ref (car rs) 1) '(after-read! after-op not-fired)) (vector-ref (car rs) 0)]
      [else (loop (cdr rs))])))

;; Warm up each path without a timer.
(for-each (lambda (kind) (do ([i 0 (fx+ i 1)]) ((fx= i 50)) (set! escaping #f) (run-once kind 100000000 'plain)))
          '(some some! get-u8))

(define (study kind mode per-run?)
  (let* ([label (format "~a~a"
                  (case kind [(some) "get-bytevector-some"] [(some!) "get-bytevector-some!"] [else "get-u8"])
                  (case mode [(sleepy) ", sleepy read!"] [(planted) ", planted read!"] [else ""]))]
         [g0 (collections)])
    (set! escaping #t)
    (let* ([coarse (sweep kind mode 1 4001 20)]
           [b (boundary coarse)])
      (bands (string-append label " coarse") coarse)
      (totals (string-append label " coarse") coarse)
      (if (not b)
          (say "~a: the coarse sweep never landed past read!'s take" label)
          (let* ([from (max 1 (- b 150))] [to (max (+ b 100) (+ from 250))])
            (say "~a: first coarse tick landing past read!'s take ~s; fine sweep ~s..~s a tick at a time" label b from to)
            (let ([fine (sweep kind mode from to 1)])
              (when per-run?
                (for-each
                  (lambda (r) (say "~a fine: T ~s ~a" label (vector-ref r 0) (show-key (key r))))
                  fine))
              (bands (string-append label " fine") fine)
              (totals (string-append label " fine") fine))
            ;; The same ticks again, to see whether a band moves.
            (let ([fine2 (sweep kind mode from to 1)])
              (bands (string-append label " fine pass 2") fine2)
              (totals (string-append label " fine pass 2") fine2))
            ;; Control: a handler that records and returns.
            (set! escaping #f)
            (let ([ctl (sweep kind mode from to 1)])
              (bands (string-append label " control, no escape") ctl)
              (totals (string-append label " control, no escape") ctl))
            (set! escaping #t))))
    (say "~a: collections during its sweeps ~s" label (- (collections) g0))))

(study 'some 'plain #t)
(study 'some! 'plain #t)
(study 'get-u8 'plain #f)
(study 'some 'planted #f)
(study 'some! 'planted #f)
(study 'get-u8 'planted #f)
(study 'some 'sleepy #f)
(study 'some! 'sleepy #f)
(study 'get-u8 'sleepy #f)
(say "C10 done")
