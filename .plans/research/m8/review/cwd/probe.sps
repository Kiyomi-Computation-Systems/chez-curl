;;; The M8 plan's review, 2026-11-06: whether (current-directory) is the
;;; process's or a thread's, so whether a relative path re-resolved at a later
;;; submit (the plan, section 11, item 4) can meet another thread's chdir.
;;; A forked thread sets (current-directory "/tmp"); the main thread then reads
;;; its own. Usage: scheme --program probe.sps
(import (chezscheme))
(define before (current-directory))
(define m (make-mutex))
(define c (make-condition))
(define done #f)
(fork-thread
 (lambda ()
   (current-directory "/tmp")
   (with-mutex m (set! done #t) (condition-signal c))))
(with-mutex m (let loop () (unless done (condition-wait c m) (loop))))
(printf "main-thread before ~s after-another-thread-set-/tmp ~s\n" before (current-directory))
