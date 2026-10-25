;;; Spike E1, for the harness (M3 plan, section 4.2): does Chez's `system`
;;; hold other threads' collections? A second thread runs `sleep 1` through
;;; system, plainly or inside a critical-section, while the main thread, 100 ms
;;; later, allocates as collect.sps's worker does.
;;;
;;;   system.sps MODE
;;;
;;; MODE is plain or section. Prints one line: the worker's time and its
;;; collections.
(import (chezscheme))

(define mode (string->symbol (car (command-line-arguments))))
(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* 1000.0 (time-second t)) (/ (time-nanosecond t) 1e6))))

(define mx (make-mutex))
(define cv (make-condition))
(define started #f)
(define done #f)
(fork-thread
 (lambda ()
   (with-mutex mx (set! started #t) (condition-broadcast cv))
   (if (eq? mode 'section)
       (critical-section (system "sleep 1"))
       (system "sleep 1"))
   (with-mutex mx (set! done #t) (condition-broadcast cv))))
(with-mutex mx (let wait () (unless started (condition-wait cv mx) (wait))))
(sleep (make-time 'time-duration 100000000 0))

(define-values (worker-ms worker-collections)
  (let ((c0 (collections)) (t0 (now-ms)))
    (let loop ((i 0) (keep '()))
      (unless (= i 60)
        (let ((l (make-list 100000 i)))
          (loop (+ i 1) (if (zero? (mod i 10)) (cons l keep) keep)))))
    (values (- (now-ms) t0) (- (collections) c0))))
(with-mutex mx (let wait () (unless done (condition-wait cv mx) (wait))))
(printf "system ~a: worker ~,1f ms, ~a collections\n" mode worker-ms worker-collections)
