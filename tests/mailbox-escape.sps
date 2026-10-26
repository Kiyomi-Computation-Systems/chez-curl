#!r6rs
;;; A child of tests/test-mailbox.sps: an interrupt handler that escapes
;;; from a take as its critical section ends (ADR-0021, amended; M4 plan,
;;; section 3.5).
;;;
;;;   mailbox-escape.sps WAIT URL
;;;
;;; WAIT is take or deliver. It submits URL with a mailbox and a callback
;;; that notes it ran, and waits for it until done, so its token is in the
;;; mailbox. A second thread then holds the mailbox's mutex, through the
;;; private call-with-mailbox-held, for 1 s. This thread prints (ready PID)
;;; and runs WAIT, bounded at 5 s, which blocks inside its critical section
;;; on that mutex. The suite sends SIGINT to PID about 500 ms later: a
;;; keyboard interrupt made pending inside a critical section runs as the
;;; section ends (.plans/research/m4/slice2/keyboard.ss), so the handler,
;;; which escapes, runs once WAIT has taken the token out, before it
;;; returns.
;;;
;;; Prints (escape CLASS CALLED DONE AWAITED): CLASS is returned, when WAIT
;;; returned the token; caller, when the handler escaped after it did;
;;; before, when it escaped with the token still in the mailbox; lost, when
;;; it escaped with the token out and never returned. CALLED is whether
;;; the callback ran; DONE whether the token is done; AWAITED what await
;;; answers. Then (counts COUNTS), once the engine has stopped.
(import (chezscheme) (curl) (curl private engine) (curl private counters))

(define args (command-line-arguments))
(define wait-name (string->symbol (car args)))
(define url (cadr args))

(define engine (make-curl-engine))
(define mailbox (make-curl-mailbox))
(define called #f)
(define token (curl-submit engine (make-curl-request url 'timeout-ms 10000) mailbox
                           (lambda (t) (set! called #t))))
(unless (curl-token-wait token 10000) (error 'mailbox-escape.sps "the transfer never ended"))

;; Every hold of LOCK is in a critical section, as (curl private engine)'s
;; locked holds its mutexes: a holder with interrupts on could join a
;; collection while a thread blocked on LOCK with interrupts off stayed
;; active, a deadlock (traps.md).
(define lock (make-mutex))
(define holding #f)
(define released #f)
(fork-thread
 (lambda ()
   (call-with-mailbox-held mailbox
     (lambda ()
       (with-mutex lock (set! holding #t))
       (sleep (make-time 'time-duration 0 1))))
   (critical-section (with-mutex lock (set! released #t)))))
(let spin ()
  (unless (critical-section (with-mutex lock holding))
    (sleep (make-time 'time-duration 1000000 0))
    (spin)))

(define returned #f)
(define how
  (call/cc
   (lambda (out)
     (keyboard-interrupt-handler (lambda () (out 'escaped)))
     (write (list 'ready (get-process-id)))
     (newline)
     (flush-output-port (current-output-port))
     (let ((t (if (eq? wait-name 'take)
                  (curl-mailbox-take mailbox 5000)
                  (curl-mailbox-deliver mailbox 5000))))
       (set! returned t)
       'returned))))
(keyboard-interrupt-handler void)
(let spin ()
  (unless (critical-section (with-mutex lock released))
    (sleep (make-time 'time-duration 1000000 0))
    (spin)))

(define class
  (cond ((eq? how 'returned) (if (eq? returned token) 'returned 'wrong-token))
        (returned 'caller)
        ((eq? (curl-mailbox-take mailbox 0) token) 'before)
        (else 'lost)))
(define awaited
  (guard (e ((curl-transfer-error? e) (list 'transfer-error (curl-transfer-error-reason e)))
            (#t '(raised)))
    (list 'response (curl-response-status (curl-token-await token)))))
(write (list 'escape class called (curl-token-done? token) awaited))
(newline)
(curl-engine-stop engine)
(write (list 'counts (native-counts)))
(newline)
