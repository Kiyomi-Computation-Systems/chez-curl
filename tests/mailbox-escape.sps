#!r6rs
;;; A child of tests/test-mailbox.sps: an interrupt handler that escapes
;;; from a take as its critical section ends (ADR-0021, amended; M4 plan,
;;; section 3.5).
;;;
;;;   mailbox-escape.sps WAIT URL
;;;
;;; WAIT is take or deliver. It submits URL with a mailbox and a callback
;;; that notes it ran, and waits for it until done, so its token is in the
;;; mailbox. It asks for a collection, and a second thread then holds the
;;; mailbox's mutex, through the private call-with-mailbox-held, until the
;;; suite has sent its SIGINT: the suite makes the file MAILBOX_CHILD_SENT
;;; names once its kill has returned, polled every 10 ms, for 20 s at most.
;;; This thread prints (ready PID) and runs WAIT, bounded at 5 s, which
;;; blocks inside its critical section on that mutex. The suite sends
;;; SIGINT to PID about 500 ms later: a keyboard interrupt made pending
;;; inside a critical section runs as the section ends
;;; (.plans/research/m4/slice2/keyboard.ss), so the handler, which escapes,
;;; runs once WAIT has taken the token out, before it returns.
;;;
;;; A collection asked for while the holder sleeps in its critical section
;;; waits for the hold to end, and so does every thread that reaches an
;;; event check meanwhile (M7's carried races, research/m7/carried/races).
;;; With one planted at ready, under the 1 s hold this child had, 9 runs of
;;; 20 failed: before 5 times, this thread stopped short of WAIT and its
;;; handler run there once the hold ended; returned 4, this thread stopped
;;; short of its ready line, so that WAIT took the token before the signal
;;; came. M5's floor lane read before once, under load. So the collection
;;; comes first, by collect-rendezvous (collect refuses while the engine's
;;; thread is alive), which leaves none due in the hold, about 87 KiB
;;; allocated there of the 8 MiB trip; and the hold ends only once the
;;; signal is sent.
;;;
;;; Prints (escape CLASS QUIET CALLED DONE AWAITED): CLASS is returned,
;;; when WAIT returned the token; caller, when the handler escaped after it
;;; did; before, when it escaped with the token still in the mailbox; lost,
;;; when it escaped with the token out and never returned. QUIET is quiet
;;; when (collections) read as the hold started is (collections) read as
;;; the handler started, else (collected HELD HANDLER). CALLED is whether
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
(define child-sent (getenv "MAILBOX_CHILD_SENT"))
(define (until-sent)
  (let wait ((n 0))
    (unless (or (and child-sent (file-exists? child-sent)) (>= n 2000))
      (sleep (make-time 'time-duration 10000000 0))
      (wait (+ n 1)))))
(define held-collections #f)
(define handler-collections #f)
(collect-rendezvous)
(fork-thread
 (lambda ()
   (call-with-mailbox-held mailbox
     (lambda ()
       (with-mutex lock (set! held-collections (collections)) (set! holding #t))
       (until-sent)))
   (critical-section (with-mutex lock (set! released #t)))))
(let spin ()
  (unless (critical-section (with-mutex lock holding))
    (sleep (make-time 'time-duration 1000000 0))
    (spin)))

(define returned #f)
(define how
  (call/cc
   (lambda (out)
     (keyboard-interrupt-handler (lambda () (set! handler-collections (collections)) (out 'escaped)))
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
(define quiet
  (if (and held-collections (eqv? held-collections handler-collections))
      'quiet
      (list 'collected held-collections handler-collections)))
(write (list 'escape class quiet called (curl-token-done? token) awaited))
(newline)
(curl-engine-stop engine)
(write (list 'counts (native-counts)))
(newline)
