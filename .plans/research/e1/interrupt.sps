;;; Spike E1: does Ctrl-C reach a caller that waits for a completion
;;; (ADR-0012, amended)? The main thread waits about 3 s, for a condition a
;;; second thread signals once its own 3 s wait ends, and the runner sends
;;; SIGINT about 1 s in.
;;;
;;;   interrupt.sps CASE TARGET OTHER
;;;
;;; CASE is how the main thread waits:
;;;   wait       condition-wait, with no timeout;
;;;   timed      condition-wait with a timeout of 100 ms, in a loop;
;;;   sectioned  the same, each wait inside its own critical-section;
;;;   poll       a __collect_safe curl_multi_poll of 3 s.
;;; TARGET names where the runner sends the signal, main or other (the
;;; second thread's id in /proc), and is only printed.
;;; OTHER is how the second thread waits its 3 s:
;;;   sleep      Chez's sleep;
;;;   wait       condition-wait, on a condition nothing signals, with a
;;;              timeout of 3 s;
;;;   poll       a __collect_safe curl_multi_poll of 3 s, as an engine waits.
;;;
;;; Prints "ready PID" once it waits, then one line: when the main thread's
;;; wait ended, when the second thread's did, and when the
;;; keyboard-interrupt handler ran, or never.
(import (chezscheme) (curl private native))

(define args (command-line-arguments))
(define case-name (string->symbol (car args)))
(define target (cadr args))
(define other (string->symbol (caddr args)))
(loaded-libcurl)
(define multi-init (foreign-procedure "curl_multi_init" () uptr))
(define poll
  (foreign-procedure __collect_safe "curl_multi_poll" (uptr uptr unsigned-int int uptr) int))
(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* 1000.0 (time-second t)) (/ (time-nanosecond t) 1e6))))
(define t0 (now-ms))
(define handled #f)
(keyboard-interrupt-handler (lambda () (set! handled (- (now-ms) t0))))

(define mx (make-mutex))
(define cv (make-condition))
(define ready #f)
(define other-ended #f)
(define hundred-ms (make-time 'time-duration 100000000 0))
(fork-thread
 (lambda ()
   (case other
     ((sleep) (sleep (make-time 'time-duration 0 3)))
     ((wait) (let ((m (make-mutex)) (c (make-condition)))
               (with-mutex m (condition-wait c m (make-time 'time-duration 0 3)))))
     ((poll) (let ((m (multi-init)) (n (foreign-alloc 8)))
               (poll m 0 0 3000 n))))
   (with-mutex mx
     (set! other-ended (- (now-ms) t0))
     (set! ready #t)
     (condition-broadcast cv))))

(printf "ready ~a\n" (get-process-id))
(flush-output-port (current-output-port))
(case case-name
  ((wait) (with-mutex mx (let w () (unless ready (condition-wait cv mx) (w)))))
  ((timed) (with-mutex mx (let w () (unless ready (condition-wait cv mx hundred-ms) (w)))))
  ((sectioned)
   (let w ()
     (unless (critical-section
              (with-mutex mx
                (or ready (begin (condition-wait cv mx hundred-ms) ready))))
       (w))))
  ((poll)
   (let ((m (multi-init)) (n (foreign-alloc 8)))
     (poll m 0 0 3000 n))))
(define waited (- (now-ms) t0))
(let spin ((i 0)) (when (< i 100000) (spin (+ i 1))))   ; event checks after the wait
(with-mutex mx (let w () (unless ready (condition-wait cv mx) (w))))
(printf "interrupt ~a, signal to ~a, other in ~a: wait ended at ~a ms, other's at ~a ms, handler ran ~a\n"
        case-name target other (exact (round waited)) (exact (round other-ended))
        (if handled (format "at ~a ms" (exact (round handled))) "never"))
