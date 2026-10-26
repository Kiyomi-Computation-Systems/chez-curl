;;; M4 slice 2's third measurement (the M4 plan, section 5.1): an interrupt
;;; handler that escapes from a take, as the take's critical section ends,
;;; before the contract is built on it (ADR-0021, amended): a take that
;;; escapes loses a notice, never an outcome.
;;;
;;;   escape.sps timer WAIT URL FROM TO
;;;   escape.sps held WAIT URL
;;;   escape.sps unheld WAIT URL
;;;
;;; WAIT is take or deliver, each bounded at 5 s. Each transfer of URL is
;;; submitted with a mailbox and a callback that notes it ran.
;;;
;;; timer: for each K from FROM to TO, the transfer is waited for until done,
;;; so its token is in the mailbox; then WAIT, with Chez's timer set to K
;;; ticks and a timer-interrupt handler that escapes, through a continuation
;;; taken before; then a call of 20 ticks, and the timer disarmed. A timer
;;; that runs out inside a critical section runs its handler at a later
;;; event check, not as the section ends, and a keyboard interrupt made
;;; pending there runs as it ends (timer.ss and keyboard.ss, here).
;;;
;;; held: the transfer is waited for until done; a second thread holds the
;;; mailbox's mutex, through call-with-mailbox-held, for 1 s; this thread
;;; prints (ready PID) and runs WAIT, which blocks inside its critical
;;; section on the mutex. The runner sends SIGINT 500 ms after ready, and
;;; the keyboard-interrupt handler, which escapes, runs as that section
;;; ends: a pending keyboard interrupt runs there at once.
;;;
;;; unheld, the control: URL is a transfer that is live for about 2 s, and
;;; this thread prints (ready PID) and runs WAIT, which sleeps between its
;;; reads of the empty mailbox; the runner's SIGINT, 500 ms in, runs the
;;; handler as a sleep ends, before any token is there to take.
;;;
;;; Each run is one of:
;;;   returned   WAIT returned the token, and no handler ran;
;;;   before     a handler escaped, and the token reached the mailbox, and
;;;              stayed there;
;;;   lost       a handler escaped with the token taken out of the mailbox,
;;;              and WAIT never returned it: the notice lost;
;;;   caller     it escaped after WAIT returned, at the caller's next call;
;;; and, for deliver, whether the callback ran. Then, for every run,
;;; whether the token is done and what await answers.
;;;
;;; Prints (escape MODE WAIT RUNS), then (classes (CLASS CALLED FROM-K TO-K)
;;; ...), each run of K's alike, 0 for a single run, then (outcomes
;;; (OUTCOME COUNT) ...), then (counts ...) once the engine has stopped.
(import (chezscheme) (curl private engine) (curl private transfer) (curl private counters))

(define args (command-line-arguments))
(define mode (string->symbol (car args)))
(define wait-name (string->symbol (cadr args)))
(define url (caddr args))

(define engine (make-curl-engine))

(define (f n) (if (= n 0) 0 (+ 1 (f (- n 1)))))

(define (wait-on mailbox)
  (case wait-name
    ((take) (curl-mailbox-take mailbox 5000))
    ((deliver) (curl-mailbox-deliver mailbox 5000))
    (else (error 'escape.sps "no such wait" wait-name))))

(define (ready!)
  (write (list 'ready (get-process-id)))
  (newline)
  (flush-output-port (current-output-port)))

;; attempt : Natural -> (List Natural Symbol Boolean (List Boolean Any))
(define (attempt k)
  (let* ((mailbox (make-curl-mailbox))
         (called #f)
         (token (curl-submit engine (make-curl-request url 'timeout-ms 10000) mailbox
                             (lambda (t) (set! called #t))))
         (returned #f)
         (released #f))
    (unless (eq? mode 'unheld)
      (unless (curl-token-wait token 10000) (error 'escape.sps "the transfer never ended" k)))
    (when (eq? mode 'held)
      (let ((holding #f))
        (fork-thread
         (lambda ()
           (call-with-mailbox-held mailbox
             (lambda ()
               (set! holding #t)
               (sleep (make-time 'time-duration 0 1))))
           (set! released #t)))
        (let spin () (unless holding (sleep (make-time 'time-duration 1000000 0)) (spin)))))
    (let ((how (call/cc
                (lambda (out)
                  (case mode
                    ((timer)
                     (timer-interrupt-handler (lambda () (out 'escaped)))
                     (set-timer k))
                    (else
                     (keyboard-interrupt-handler (lambda () (out 'escaped)))
                     (ready!)))
                  (let ((t (wait-on mailbox)))
                    (set! returned t)
                    (f 20)
                    (set-timer 0)
                    'returned)))))
      (set-timer 0)
      (keyboard-interrupt-handler void)
      (unless (curl-token-wait token 10000) (error 'escape.sps "the transfer never ended" k))
      (let spin () (when (and (eq? mode 'held) (not released)) (sleep (make-time 'time-duration 1000000 0)) (spin)))
      (let* ((class (cond ((eq? how 'returned) (if (eq? returned token) 'returned 'wrong-token))
                          (returned 'caller)
                          ((eq? (curl-mailbox-take mailbox 0) token) 'before)
                          (else 'lost)))
             (outcome (list (curl-token-done? token)
                            (guard (e (#t 'raised))
                              (curl-response-status (curl-token-await token))))))
        (list k class called outcome)))))

(define results
  (case mode
    ((timer)
     (let ((from (string->number (list-ref args 3))) (to (string->number (list-ref args 4))))
       (let loop ((k from) (acc '()))
         (if (> k to) (reverse acc) (loop (+ k 1) (cons (attempt k) acc))))))
    ((held unheld) (list (attempt 0)))
    (else (error 'escape.sps "no such mode" mode))))
(curl-engine-stop engine)

;; runs of K's with the same class and callback
(define (runs rs)
  (let loop ((rs rs) (acc '()))
    (if (null? rs)
        (reverse acc)
        (let* ((r (car rs)) (key (list (cadr r) (caddr r))))
          (if (and (pair? acc) (equal? (list (car (car acc)) (cadr (car acc))) key))
              (loop (cdr rs) (cons (list (car key) (cadr key) (caddr (car acc)) (car r)) (cdr acc)))
              (loop (cdr rs) (cons (list (car key) (cadr key) (car r) (car r)) acc)))))))

(define (tally xs)
  (let loop ((xs xs) (acc '()))
    (if (null? xs)
        (reverse acc)
        (let ((hit (assoc (car xs) acc)))
          (if hit
              (begin (set-car! (cdr hit) (+ (cadr hit) 1)) (loop (cdr xs) acc))
              (loop (cdr xs) (cons (list (car xs) 1) acc)))))))

(write (list 'escape mode wait-name (length results)))
(newline)
(write (cons 'classes (runs results)))
(newline)
(write (cons 'outcomes (tally (map cadddr results))))
(newline)
(write (list 'counts (native-counts)))
(newline)
