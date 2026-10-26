#!r6rs
;;; A child of tests/test-engine.sps: Ctrl-C while this thread, the main
;;; one, awaits a transfer (M3 plan, section 3.4).
;;;
;;;   engine-interrupt.sps URL
;;;
;;; It submits URL, a slow drip, prints (ready PID) and awaits it. The suite
;;; sends SIGINT to PID about 500 ms later. Prints (interrupt HANDLED
;;; AWAITED ANSWER): when the keyboard-interrupt handler ran and when the
;;; await returned, each in ms after ready, and what the await answered;
;;; then (counts COUNTS), once the engine has stopped. A wait that answers
;;; Ctrl-C only when it ends runs the handler when the drip does.
(import (chezscheme) (curl private engine) (curl private transfer) (curl private counters))

(define url (car (command-line-arguments)))

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

(define engine (make-curl-engine))
(define t0 (now-ms))
(define handled #f)
(keyboard-interrupt-handler (lambda () (unless handled (set! handled (- (now-ms) t0)))))
(define token (curl-engine-submit engine (make-curl-request url 'timeout-ms 20000)))
(set! t0 (now-ms))
(write (list 'ready (get-process-id)))
(newline)
(flush-output-port (current-output-port))
(define answer
  (guard (e (#t '(raised)))
    (let ((r (curl-token-await token))) (list 'response (curl-response-status r)))))
(define awaited (- (now-ms) t0))
(curl-engine-stop engine)
(write (list 'interrupt handled awaited answer))
(newline)
(write (list 'counts (native-counts)))
(newline)
