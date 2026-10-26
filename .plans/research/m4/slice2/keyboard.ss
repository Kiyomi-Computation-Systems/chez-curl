;;; M4 slice 2: where Chez runs a keyboard interrupt that a SIGINT, sent to
;;; this process from inside a critical section, makes pending. Linux only:
;;; it loads libc.so.6. Run: scheme -q --script keyboard.ss. Its output is
;;; results/interrupts.log.
(load-shared-object "libc.so.6")
(define stage 'start)
(define fired '())
(define (f n) (if (= n 0) 0 (+ 1 (f (- n 1)))))
(define kill (foreign-procedure "kill" (int int) int))
(define getpid (foreign-procedure "getpid" () int))
(keyboard-interrupt-handler (lambda () (set! fired (cons stage fired))))
(define (try label body)
  (set! fired '())
  (set! stage 'before) (f 5)
  (body)
  (set! stage 'after1) (f 5)
  (set! stage 'after2) (f 2000)
  (set! stage 'after3) (f 20000)
  (printf "~a: fired ~a\n" label (reverse fired)))
(try "kill inside a critical section, nothing after it inside"
     (lambda () (critical-section (set! stage 'inside) (kill (getpid) 2) (f 50) (set! stage 'in-end))))
(try "kill inside a critical section, then a primitive set! after it"
     (lambda () (critical-section (set! stage 'inside) (kill (getpid) 2) (f 50) (set! stage 'in-end)) (set! stage 'right-after)))
(try "kill outside any section"
     (lambda () (set! stage 'outside) (kill (getpid) 2) (set! stage 'outside-2) (f 3) (set! stage 'outside-3)))
