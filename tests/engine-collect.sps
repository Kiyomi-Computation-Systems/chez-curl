#!r6rs
;;; A child of tests/test-engine.sps: a worker's 20 collections, back to
;;; back, beside an engine (M3 plan, section 3.2; ADR-0013, amended
;;; 2026-10-25).
;;;
;;;   engine-collect.sps MODE URL
;;;
;;; MODE is idle, an engine with nothing to do, or await, this thread
;;; awaiting a transfer of URL, a slow drip, meanwhile. The worker starts
;;; 200 ms in. Prints (collections MODE MS), how long the 20 took, then
;;; (counts COUNTS), the native counts once the engine has stopped. A plain
;;; poll holds each collection up to about 500 of its waits, and a caller's
;;; wait that sleeps inside a critical section holds it for good, so either
;;; takes far longer than the suite's bound.
(import (chezscheme) (curl private engine) (curl private transfer) (curl private counters))

(define args (command-line-arguments))
(define mode (string->symbol (car args)))
(define url (cadr args))

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

(define engine (make-curl-engine))
(define token
  (and (eq? mode 'await)
       (curl-submit engine (make-curl-request url 'timeout-ms 20000))))

(define mx (make-mutex))
(define cv (make-condition))
(define elapsed #f)
(fork-thread
 (lambda ()
   (sleep (make-time 'time-duration 200000000 0))
   (let ((t0 (now-ms)))
     (do ((i 0 (+ i 1))) ((= i 20))
       (make-bytevector 10000 1)
       (collect-rendezvous))
     (with-mutex mx (set! elapsed (- (now-ms) t0)) (condition-broadcast cv)))))

(when token (guard (e (#t #f)) (curl-token-await token)))
(with-mutex mx (let w () (unless elapsed (condition-wait cv mx) (w))))
(curl-engine-stop engine)
(write (list 'collections mode elapsed))
(newline)
(write (list 'counts (native-counts)))
(newline)
