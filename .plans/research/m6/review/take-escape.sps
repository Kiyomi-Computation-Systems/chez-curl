;; M6 plan review (2026-10-29): does a Ctrl-C made pending while a port's
;; read! takes a piece under a mutex, as the plan's read! and next-piece
;; must (section 3.5: a take is a short hold through locked), lose that
;; piece when its handler escapes?
;;
;; The take is (critical-section (with-mutex m ...)), as `locked` is. Another
;; thread holds m, so the read! blocks inside the section; that thread then
;; sends SIGINT to the process (Linux offers it to the main thread) and
;; releases m: the traps.md recipe for planting an escape at a section's end.
;; The keyboard-interrupt handler raises 'interrupted, or, in the control,
;; returns. Each case reads with OP, then reads again with get-bytevector-some
;; until the end, and reports which pieces the source gave and which the
;; caller received.
;;
;; Run from the repository's root:
;;   scripts/guix-env sh -c '$CHEZ --program .plans/research/m6/review/take-escape.sps' < /dev/null
(import (chezscheme))

(load-shared-object "libc.so.6")
(define kill (foreign-procedure "kill" (int int) int))
(define getpid (foreign-procedure "getpid" () int))
(define sigint 2)

(define (say . xs) (for-each display xs) (newline) (flush-output-port (current-output-port)))

(define (ms n) (make-time 'time-duration (* n 1000000) 0))

;; one-case : Symbol Boolean -> Void
(define (one-case op escaping)
  (let* ([m (make-mutex)]
         [source (list (make-bytevector 5 1) (make-bytevector 5 2) (make-bytevector 5 3))]
         [given '()]
         [ready #f]
         [in-take #f]
         [take! (lambda ()
                  ;; locked: critical-section around with-mutex
                  (critical-section
                   (with-mutex m
                     (if (null? source)
                         #f
                         (let ([p (car source)])
                           (set! source (cdr source))
                           (set! given (cons (bytevector-u8-ref p 0) given))
                           p)))))]
         [port (make-custom-binary-input-port "take-escape"
                 (lambda (bv start count)
                   (set! in-take #t)
                   (let ([p (take!)])
                     (if p
                         (begin (bytevector-copy! p 0 bv start 5) 5)
                         0)))
                 #f #f #f)]
         [received '()]
         [note! (lambda (r)
                  (when (bytevector? r)
                    (set! received (append received (list (bytevector-u8-ref r 0))))))]
         [read-op (case op
                    [(some) (lambda () (get-bytevector-some port))]
                    [(u8) (lambda () (let ([b (get-u8 port)]) (if (eof-object? b) b (make-bytevector 1 b))))])])
    (keyboard-interrupt-handler
      (lambda () (if escaping (raise 'interrupted) (void))))
    ;; the other thread: hold m, wait until the main thread is inside read!,
    ;; signal, then release.
    (fork-thread
      (lambda ()
        (mutex-acquire m)
        (set! ready #t)
        (let loop () (unless in-take (sleep (ms 1)) (loop)))
        (sleep (ms 100))
        (kill (getpid) sigint)
        (sleep (ms 100))
        (mutex-release m)))
    (let loop () (unless ready (sleep (ms 1)) (loop)))
    (let ([first (guard (e [(eq? e 'interrupted) 'escaped])
                   (let ([r (read-op)]) (note! r) 'returned))])
      (set! in-take #t)
      (let loop ()
        (let ([r (get-bytevector-some port)])
          (unless (eof-object? r)
            (set! received (append received (list (bytevector-u8-ref r 0))))
            (loop))))
      (say "case op=" op " handler=" (if escaping "escapes" "returns")
           ": first read " first
           "; source gave pieces " (reverse given)
           "; caller received pieces " received
           "; lost " (filter (lambda (x) (not (memv x received))) (reverse given))))))

(one-case 'some #f)
(one-case 'some #t)
(one-case 'u8 #f)
(one-case 'u8 #t)
(say "take-escape done")
