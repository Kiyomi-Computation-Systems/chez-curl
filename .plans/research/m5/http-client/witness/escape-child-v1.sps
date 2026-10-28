;; The SIGINT child as the suite first had it, its witness read from the
;; engine's counts: (escape HOW HELD SETTLED). Kept to show that witness's
;; window: HELD reads 0 for a submit the engine has taken from its queue
;; and not yet entered in its live table.
(import (chezscheme) (curl) (http-client)
        (only (http-client private call) http-session-engine)
        (only (curl private engine) call-with-engine-held curl-engine-live-count
              curl-engine-queued-count)
        (curl private counters))
(define url (car (command-line-arguments)))
(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))
(define (held engine) (+ (curl-engine-queued-count engine) (curl-engine-live-count engine)))
(define session (make-http-session 'timeout-ms 30000))
(define engine (http-session-engine session))
(define lock (make-mutex))
(define holding #f)
(define released #f)
(fork-thread
 (lambda ()
   (call-with-engine-held engine
     (lambda ()
       (critical-section (with-mutex lock (set! holding #t)))
       (sleep (make-time 'time-duration 500000000 1))))
   (critical-section (with-mutex lock (set! released #t)))))
(let spin ()
  (unless (critical-section (with-mutex lock holding))
    (sleep (make-time 'time-duration 1000000 0))
    (spin)))
(define at-escape #f)
(define how
  (call/cc
   (lambda (out)
     (keyboard-interrupt-handler
      (lambda () (set! at-escape (held engine)) (out 'escaped)))
     (write (list 'ready (get-process-id)))
     (newline)
     (flush-output-port (current-output-port))
     (http-get session url)
     'returned)))
(keyboard-interrupt-handler void)
(let spin ()
  (unless (critical-section (with-mutex lock released))
    (sleep (make-time 'time-duration 1000000 0))
    (spin)))
(define settled
  (let ((deadline (+ (now-ms) 3000)))
    (let loop ()
      (cond ((= (held engine) 0) 'cancelled)
            ((> (now-ms) deadline) 'still-live)
            (else (sleep (make-time 'time-duration 10000000 0)) (loop))))))
(write (list 'escape how at-escape settled))
(newline)
(http-session-close session)
(write (list 'counts (native-counts)))
(newline)
