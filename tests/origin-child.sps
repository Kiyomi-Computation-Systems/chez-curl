#!r6rs
;;; Not a suite: tests/test-origin.sps runs this as a child Chez, for the
;;; checks on how long the origin outlives a suite killed with SIGKILL (M1
;;; plan, section 7), which runs none of call-with-origin's cleanup. It starts
;;; an origin with call-with-origin and prints one line, (ORIGIN-PID HTTP-PORT
;;; RAW-PORT H2C-PORT). Then:
;;;
;;;   with no argument   it waits to be killed;
;;;   with "probe"       it runs a probe on stall-before-head, idle bound
;;;                      20000 ms, under a wire-probe-deadline of 2000 ms,
;;;                      and is killed during it. The probe's shell and its
;;;                      node, children of system, hold the origin's stdin
;;;                      until the deadline ends them.
;;;
;;; It cannot linger either: should its own stdin end first, because the
;;; suite died, it exits, and so it does after 30 s by the monotonic clock,
;;; checked before every look at stdin.
(import (rnrs)
        (curl-testing)
        (only (chezscheme) current-time input-port-ready? make-time parameterize sleep
              time-nanosecond time-second))

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

(define deadline (+ (now-ms) 30000))

(define mode (cdr (command-line)))

(call-with-origin
 (lambda (origin)
   (write (list (origin-pid origin)
                (cdr (origin-face origin 'http))
                (cdr (origin-face origin 'raw))
                (cdr (origin-face origin 'h2c))))
   (newline)
   (flush-output-port (current-output-port))
   (when (equal? mode '("probe"))
     (parameterize ((wire-probe-deadline 2000))
       (wire-probe origin 'raw
                   (string->utf8 "GET /raw/stall-before-head HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
                   20000)))
   (let ((stdin (standard-input-port)))
     (let wait ()
       (cond ((> (now-ms) deadline) (exit 0))
             ((and (input-port-ready? stdin) (eof-object? (get-u8 stdin))) (exit 0))
             (else (sleep (make-time 'time-duration 50000000 0))
                   (wait)))))))
