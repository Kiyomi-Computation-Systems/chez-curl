#!r6rs
;;; Fixture for tests/test-check-seam.sps: fork-thread, disable-interrupts and
;;; enable-interrupts in (curl private engine), the one library
;;; library-only-chez-names lists for each, with make-mutex, with-mutex,
;;; critical-section, sleep and make-time beside it, which are allowed
;;; everywhere: a wait polls, holding no mutex while it sleeps (ADR-0013).
(library (curl private engine)
  (export start await)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) fork-thread make-mutex with-mutex critical-section sleep make-time
                disable-interrupts enable-interrupts))
  (define lock (make-mutex))
  (define done #f)
  (define (start) (fork-thread (lambda () (critical-section (with-mutex lock (set! done #t))))))
  (define (interrupts-on?)
    (let ((count (disable-interrupts))) (enable-interrupts) (= count 1)))
  (define (await)
    (unless (interrupts-on?) (error 'await "interrupts are off"))
    (let loop ()
      (unless (critical-section (with-mutex lock done))
        (sleep (make-time 'time-duration 50000 0))
        (loop)))))
