;;; M4 slice 2: where Chez runs a timer interrupt that runs out inside a
;;; critical section. STAGE names the code running; the handler notes it.
;;; Run: scheme -q --script timer.ss. Its output is results/interrupts.log.
(define stage 'start)
(define fired '())
(define (f n) (if (= n 0) 0 (+ 1 (f (- n 1)))))
(timer-interrupt-handler (lambda () (set! fired (cons stage fired))))
(define (try k inside)
  (set! fired '())
  (set-timer k)
  (set! stage 'before) (f 5)
  (set! stage 'inside) (critical-section (f inside) (set! stage 'in-end))
  (set! stage 'after1) (f 5)
  (set! stage 'after2) (f 2000)
  (set! stage 'after3) (f 20000)
  (set-timer 0)
  (printf "k ~a inside ~a: fired ~a\n" k inside (reverse fired)))
(for-each (lambda (k) (try k 50)) '(1 3 6 10 20 40 60 100 200 1000 5000))
(for-each (lambda (k) (try k 5000)) '(10 100 1000 3000))
