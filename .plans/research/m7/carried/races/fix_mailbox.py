#!/usr/bin/env python3
"""fix_mailbox.py TESTS: the carried races' fix to test-mailbox's SIGINT
child, tests/mailbox-escape.sps, and the suite's interrupt script and test,
as test-group's children have it (M7 slice 4's races): a collect-rendezvous
before the holder starts, the hold kept until the suite has sent its
SIGINT, and quiet in the child's line. Applied once; each replacement must
match exactly."""
import sys

tests = sys.argv[1]


def fix(path, edits):
    s = open(path).read()
    for old, new in edits:
        n = s.count(old)
        if n != 1:
            sys.exit(f"fix_mailbox: {path}: {old[:70]!r} occurs {n} times, not once")
        s = s.replace(old, new)
    open(path, 'w').write(s)
    print(f"fix_mailbox: wrote {path}")


fix(f"{tests}/mailbox-escape.sps", [
    (""";;; WAIT is take or deliver. It submits URL with a mailbox and a callback
;;; that notes it ran, and waits for it until done, so its token is in the
;;; mailbox. A second thread then holds the mailbox's mutex, through the
;;; private call-with-mailbox-held, for 1 s. This thread prints (ready PID)
;;; and runs WAIT, bounded at 5 s, which blocks inside its critical section
;;; on that mutex. The suite sends SIGINT to PID about 500 ms later: a
;;; keyboard interrupt made pending inside a critical section runs as the
;;; section ends (.plans/research/m4/slice2/keyboard.ss), so the handler,
;;; which escapes, runs once WAIT has taken the token out, before it
;;; returns.
;;;
;;; Prints (escape CLASS CALLED DONE AWAITED): CLASS is returned, when WAIT
;;; returned the token; caller, when the handler escaped after it did;
;;; before, when it escaped with the token still in the mailbox; lost, when
;;; it escaped with the token out and never returned. CALLED is whether
;;; the callback ran; DONE whether the token is done; AWAITED what await
;;; answers. Then (counts COUNTS), once the engine has stopped.""",
     """;;; WAIT is take or deliver. It submits URL with a mailbox and a callback
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
;;; event check meanwhile (M7's carried races, research/m7/carried/races):
;;; with one planted at ready, this thread stopped before WAIT, and its
;;; handler ran there once the hold ended, the token still in the mailbox,
;;; or it stopped before its ready line, and WAIT returned the token, the
;;; signal coming after: before 3 runs of 10, returned 3. M5's floor lane
;;; read before once, under load. So the collection comes first, by
;;; collect-rendezvous (collect refuses while the engine's thread is
;;; alive), which leaves none due in the hold; and the hold ends only once
;;; the signal is sent.
;;;
;;; Prints (escape CLASS QUIET CALLED DONE AWAITED): CLASS is returned,
;;; when WAIT returned the token; caller, when the handler escaped after it
;;; did; before, when it escaped with the token still in the mailbox; lost,
;;; when it escaped with the token out and never returned. QUIET is quiet
;;; when (collections) read as the hold started is (collections) read as
;;; the handler started, else (collected HELD HANDLER). CALLED is whether
;;; the callback ran; DONE whether the token is done; AWAITED what await
;;; answers. Then (counts COUNTS), once the engine has stopped."""),
    ("""(define lock (make-mutex))
(define holding #f)
(define released #f)
(fork-thread
 (lambda ()
   (call-with-mailbox-held mailbox
     (lambda ()
       (with-mutex lock (set! holding #t))
       (sleep (make-time 'time-duration 0 1))))
   (critical-section (with-mutex lock (set! released #t)))))""",
     """(define lock (make-mutex))
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
   (critical-section (with-mutex lock (set! released #t)))))"""),
    ("""     (keyboard-interrupt-handler (lambda () (out 'escaped)))""",
     """     (keyboard-interrupt-handler (lambda () (set! handler-collections (collections)) (out 'escaped)))"""),
    ("""(write (list 'escape class called (curl-token-done? token) awaited))""",
     """(define quiet
  (if (and held-collections (eqv? held-collections handler-collections))
      'quiet
      (list 'collected held-collections handler-collections)))
(write (list 'escape class quiet called (curl-token-done? token) awaited))"""),
])

fix(f"{tests}/test-mailbox.sps", [
    (""";; interrupt-script : String
;; sh -c INTERRUPT-SCRIPT sh COMMAND...: COMMAND under GNU timeout (gtimeout
;; on macOS), killed with SIGKILL after 60 s, its output in a file made
;; under TMPDIR; once it prints (ready PID), 500 ms later, SIGINT to PID,
;; the child Chez itself; then its exit status, and its output but the
;; ready line. Exit 125 with no timeout, 126 when the child never says it
;; is ready, within 20 s.""",
     """;; interrupt-script : String
;; sh -c INTERRUPT-SCRIPT sh COMMAND...: COMMAND under GNU timeout (gtimeout
;; on macOS), killed with SIGKILL after 60 s, its output in a file made
;; under TMPDIR; once it prints (ready PID), 500 ms later, SIGINT to PID,
;; the child Chez itself, then the file the child's MAILBOX_CHILD_SENT
;; names, made once the kill has returned, which lets the child's holder
;; go; then its exit status, and its output but the ready line. Exit 125
;; with no timeout, 126 when the child never says it is ready, within 20 s."""),
    ("""   "\\"$t\\" -s KILL 60 \\"$@\\" >\\"$out\\" 2>&1 </dev/null &\\n\"""",
     """   "MAILBOX_CHILD_SENT=\\"$out.sent\\" \\"$t\\" -s KILL 60 \\"$@\\" >\\"$out\\" 2>&1 </dev/null &\\n\""""),
    ("""   "kill -INT \\"$pid\\"\\n"
   "wait \\"$waiter\\"\\n"
   "status=$?\\n"
   "grep -v '^(ready ' \\"$out\\"\\n"
   "rm -f \\"$out\\"\\n\"""",
     """   "kill -INT \\"$pid\\"\\n"
   ": >\\"$out.sent\\"\\n"
   "wait \\"$waiter\\"\\n"
   "status=$?\\n"
   "grep -v '^(ready ' \\"$out\\"\\n"
   "rm -f \\"$out\\" \\"$out.sent\\"\\n\""""),
    ("""   ;; The escape at the take (ADR-0021, amended): a second thread holds the
   ;; mailbox's mutex, so the take blocks inside its critical section, and
   ;; SIGINT arrives meanwhile. Its handler escapes as the section ends, the
   ;; token taken out and never returned: the notice is lost, and the
   ;; outcome is not.""",
     """   ;; The escape at the take (ADR-0021, amended): a second thread holds the
   ;; mailbox's mutex, so the take blocks inside its critical section, and
   ;; SIGINT arrives meanwhile. Its handler escapes as the section ends, the
   ;; token taken out and never returned: the notice is lost, and the
   ;; outcome is not. quiet: no collection ran between the hold's start and
   ;; the handler, which would have stopped this thread before the take
   ;; (tests/mailbox-escape.sps)."""),
    ("""        (list 0 '(escape lost #f #t (response 200)) (list 'counts zero-counts) "")""",
     """        (list 0 '(escape lost quiet #f #t (response 200)) (list 'counts zero-counts) "")"""),
])
