;;; Whether two threads' calls of Chez's `system` run at once (2026-11-01): each runs
;;; `sleep 1`, one on a forked thread, one on the main thread, started together. Side
;;; by side they end in about 1 s; serialized, as Apple's libc may make `system()`, in
;;; about 2 s. Run from the repository's root:
;;;   chez --program .plans/research/m6/slice3-build/mac-system.sps      (the Mac)
;;;   scripts/guix-env sh -c '$CHEZ --program .plans/research/m6/slice3-build/mac-system.sps' < /dev/null
(import (chezscheme))
(define (ms-since t0)
  (let ((d (time-difference (current-time 'time-monotonic) t0)))
    (+ (* 1000 (time-second d)) (quotient (time-nanosecond d) 1000000))))
(define (run-once)
  (let ((mx (make-mutex)) (done #f) (t0 (current-time 'time-monotonic)))
    (fork-thread (lambda () (system "sleep 1") (with-mutex mx (set! done (ms-since t0)))))
    (system "sleep 1")
    (let ((main-ms (ms-since t0)))
      (let wait ()
        (unless (with-mutex mx done) (sleep (make-time 'time-duration 10000000 0)) (wait)))
      (list 'main-ms main-ms 'thread-ms (with-mutex mx done) 'both-ms (ms-since t0)))))
(printf "mac-system ~a~%" (machine-type))
(flush-output-port (current-output-port))
(system "uname -sr")
(do ((i 0 (+ i 1))) ((= i 3)) (write (run-once)) (newline))
