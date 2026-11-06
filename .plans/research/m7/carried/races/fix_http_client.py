#!/usr/bin/env python3
"""fix_http_client.py FILE: the carried races' fix to test-http-client's two
SIGINT children, as fix_group.py made test-group's (M7 slice 4's races):
child-hold spliced into each, a collect-rendezvous before the holder starts,
the hold kept until the suite has sent its SIGINT, and quiet in each line.
Applied once; each replacement must match exactly."""
import sys

path = sys.argv[1]
s = open(path).read()


def sub(old, new, count=1):
    global s
    n = s.count(old)
    if n != count:
        sys.exit(f"fix_http_client: {old[:70]!r} occurs {n} times, not {count}")
    s = s.replace(old, new)


CHILD_HOLD = r''';; child-hold : (Listof Datum)
;; The forms each SIGINT child below splices in after its import, for its
;; hold (M7's carried races, research/m7/carried/races), as
;; tests/test-group.sps's children have them:
;;   - (until-sent), which the holder sleeps in, holding the engine's
;;     mutex, until the suite has sent the SIGINT: interrupt-script makes
;;     the file HTTP_CLIENT_CHILD_SENT names once its kill has returned,
;;     polled every 10 ms, for 20 s at most. So no release comes before the
;;     SIGINT, however late the script runs.
;;   - held-collections, (collections) as the holder starts to hold, and
;;     handler-collections, as the Ctrl-C handler starts: (quiet) answers
;;     quiet when they are equal. A collection asked for while the holder
;;     sleeps in its critical section waits for the hold to end, and so does
;;     every thread that reaches an event check meanwhile: the main thread,
;;     met by one before its submit blocked, ran its handler after the
;;     release where it had stopped, in the call's request building. There
;;     the raise-child's raise was compounded with &http-exchange, 1 run of 5
;;     with a collection planted at ready, and the escape-child passed with
;;     no submit made, 5 runs of 5. Each child asks for a collection by
;;     collect-rendezvous before its holder starts, which leaves none due in
;;     the hold (collect-rendezvous, not collect, which refuses while the
;;     engine's thread is alive), and quiet shows none ran.
(define child-hold
  '((define child-sent (getenv "HTTP_CLIENT_CHILD_SENT"))
    (define (until-sent)
      (let wait ((n 0))
        (unless (or (and child-sent (file-exists? child-sent)) (>= n 2000))
          (sleep (make-time 'time-duration 10000000 0))
          (wait (+ n 1)))))
    (define held-collections #f)
    (define handler-collections #f)
    (define (quiet)
      (if (and held-collections (eqv? held-collections handler-collections))
          'quiet
          (list 'collected held-collections handler-collections)))))

'''

sub(''';; escape-child : (Listof Datum)
;; A program: it holds its session's engine's mutex from another thread
;; for 3 s, through the private call-with-engine-held, prints (ready PID),
;; and calls URL, its first argument, a 10 s drip, whose submit blocks on
;; that mutex inside the drive's critical section. The suite sends SIGINT
;; about 500 ms after ready: a keyboard interrupt made pending inside a
;; critical section runs as it ends (traps.md), so the handler, which
;; escapes, runs once the submit has returned.
''', CHILD_HOLD + ''';; escape-child : (Listof Datum)
;; A program: it asks for a collection, holds its session's engine's mutex
;; from another thread, through the private call-with-engine-held, until the
;; suite has sent its SIGINT (child-hold), prints (ready PID), and calls
;; URL, its first argument, a 10 s drip, whose submit blocks on that mutex
;; inside the drive's critical section. The suite sends SIGINT about 500 ms
;; after ready: a keyboard interrupt made pending inside a critical section
;; runs as it ends (traps.md), so the handler, which escapes, runs once the
;; submit has returned.
''')
sub(''';; Prints (escape HOW WHEN SETTLED), then (counts COUNTS), once the session
;; is closed.
(define escape-child
  '((import (chezscheme) (curl) (http-client)''', ''';; Prints (escape HOW WHEN QUIET SETTLED), QUIET quiet when no collection
;; ran in the hold (child-hold), then (counts COUNTS), once the session is
;; closed.
(define escape-child
  `((import (chezscheme) (curl) (http-client)''')
sub(''';; Prints (raise SAME COMPOUNDED WHEN SETTLED): SAME, whether the call
;; raised that very object; COMPOUNDED, whether what it raised carries an
;; &http-exchange; then (counts COUNTS), once the session is closed.
(define raise-child
  '((import (chezscheme) (curl) (http-client)''', ''';; Prints (raise SAME COMPOUNDED WHEN QUIET SETTLED): SAME, whether the
;; call raised that very object; COMPOUNDED, whether what it raised carries
;; an &http-exchange; QUIET as escape-child's; then (counts COUNTS), once
;; the session is closed.
(define raise-child
  `((import (chezscheme) (curl) (http-client)''')
# both children: child-hold after the import, the rendezvous, the hold
sub('''            (curl private counters))
    (define url (car (command-line-arguments)))''', '''            (curl private counters))
    ,@child-hold
    (define url (car (command-line-arguments)))''', 2)
sub('''    (define (flag get) (critical-section (with-mutex lock (get))))
    (fork-thread
     (lambda ()
       (call-with-engine-held engine
         (lambda ()
           (critical-section (with-mutex lock (set! holding #t)))
           (sleep (make-time 'time-duration 0 3))
           (critical-section (with-mutex lock (set! letting-go #t)))))''', '''    (define (flag get) (critical-section (with-mutex lock (get))))
    (collect-rendezvous)
    (fork-thread
     (lambda ()
       (call-with-engine-held engine
         (lambda ()
           (critical-section (with-mutex lock (set! held-collections (collections)) (set! holding #t)))
           (until-sent)
           (critical-section (with-mutex lock (set! letting-go #t)))))''', 2)
sub('''          (lambda ()
            (set! when-escaped''', '''          (lambda ()
            (set! handler-collections (collections))
            (set! when-escaped''')
sub('''         (lambda ()
           (set! when-raised''', '''         (lambda ()
           (set! handler-collections (collections))
           (set! when-raised''')
sub("    (write (list 'escape how when-escaped settled))", "    (write (list 'escape how when-escaped (quiet) settled))")
sub("""    (write (list 'raise (eq? caught planted) (and (condition? caught) (http-exchange? caught))
                 when-raised settled))""", """    (write (list 'raise (eq? caught planted) (and (condition? caught) (http-exchange? caught))
                 when-raised (quiet) settled))""")
# the interrupt script: the sent file
sub(''';; interrupt-script : String
;; sh -c INTERRUPT-SCRIPT sh COMMAND...: COMMAND under GNU timeout
;; (gtimeout on macOS), killed with SIGKILL after 60 s, its output in a
;; file made under TMPDIR; once it prints (ready PID), 500 ms later,
;; SIGINT to PID, the child Chez itself; then its exit status, and its
;; output but the ready line. Exit 125 with no timeout, 126 when the
;; child never says it is ready, within 20 s.''', ''';; interrupt-script : String
;; sh -c INTERRUPT-SCRIPT sh COMMAND...: COMMAND under GNU timeout
;; (gtimeout on macOS), killed with SIGKILL after 60 s, its output in a
;; file made under TMPDIR; once it prints (ready PID), 500 ms later,
;; SIGINT to PID, the child Chez itself, then the file the child's
;; HTTP_CLIENT_CHILD_SENT names, made once the kill has returned, which
;; lets the child's holder go (child-hold); then its exit status, and its
;; output but the ready line. Exit 125 with no timeout, 126 when the child
;; never says it is ready, within 20 s.''')
sub('''   "\\"$t\\" -s KILL 60 \\"$@\\" >\\"$out\\" 2>&1 </dev/null &\\n"
   "waiter=$!\\n"
   "n=0\\n"
   "until grep -q '^(ready ' \\"$out\\" || [ \\"$n\\" -ge 400 ]; do sleep 0.05; n=$((n + 1)); done\\n"
   "pid=$(sed -n 's/^(ready \\\\([0-9]*\\\\))$/\\\\1/p' \\"$out\\")\\n"
   "if [ -z \\"$pid\\" ]; then kill \\"$waiter\\"; wait \\"$waiter\\"; cat \\"$out\\" >&2; rm -f \\"$out\\"; echo 'http-client escape: the child never said it was ready' >&2; exit 126; fi\\n"
   "sleep 0.5\\n"
   "kill -INT \\"$pid\\"\\n"
   "wait \\"$waiter\\"\\n"
   "status=$?\\n"
   "grep -v '^(ready ' \\"$out\\"\\n"
   "rm -f \\"$out\\"\\n"''', '''   "HTTP_CLIENT_CHILD_SENT=\\"$out.sent\\" \\"$t\\" -s KILL 60 \\"$@\\" >\\"$out\\" 2>&1 </dev/null &\\n"
   "waiter=$!\\n"
   "n=0\\n"
   "until grep -q '^(ready ' \\"$out\\" || [ \\"$n\\" -ge 400 ]; do sleep 0.05; n=$((n + 1)); done\\n"
   "pid=$(sed -n 's/^(ready \\\\([0-9]*\\\\))$/\\\\1/p' \\"$out\\")\\n"
   "if [ -z \\"$pid\\" ]; then kill \\"$waiter\\"; wait \\"$waiter\\"; cat \\"$out\\" >&2; rm -f \\"$out\\"; echo 'http-client escape: the child never said it was ready' >&2; exit 126; fi\\n"
   "sleep 0.5\\n"
   "kill -INT \\"$pid\\"\\n"
   ": >\\"$out.sent\\"\\n"
   "wait \\"$waiter\\"\\n"
   "status=$?\\n"
   "grep -v '^(ready ' \\"$out\\"\\n"
   "rm -f \\"$out\\" \\"$out.sent\\"\\n"''')
# the tests
sub("""     (list 0 '((escape escaped after-release cancelled) (counts""", """     (list 0 '((escape escaped after-release quiet cancelled) (counts""")
sub("""     (list 0 '((raise #t #f after-release cancelled) (counts""", """     (list 0 '((raise #t #f after-release quiet cancelled) (counts""")
open(path, 'w').write(s)
print(f"fix_http_client: wrote {path}")
