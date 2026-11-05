#!/usr/bin/env python3
"""fix_group.py PATH: M7 slice 4's race fix to tests/test-group.sps, in place.

Every SIGINT child holds its mutex until the suite has sent the SIGINT
(interrupt-script makes the file GROUP_CHILD_SENT names once its kill has
returned), asks for a collection by collect-rendezvous before its holder
starts, and reports quiet when no collection ran between its hold's start
and its Ctrl-C handler; each test expects quiet."""
import sys

path = sys.argv[1]
s = open(path).read()


def once(old, new, text=None):
    global s
    n = s.count(old)
    if n != 1:
        sys.exit(f"fix_group: {old[:100]!r} occurs {n} times, not 1")
    s = s.replace(old, new)


# --- the interrupt script ------------------------------------------------------
once(""";; interrupt-script : String
;; sh -c INTERRUPT-SCRIPT sh COMMAND...: COMMAND under GNU timeout
;; (gtimeout on macOS), killed with SIGKILL after 60 s, its output in a
;; file made under TMPDIR; once it prints (ready PID), 500 ms later,
;; SIGINT to PID, the child Chez itself; then its exit status, and its
;; output but the ready line. Exit 125 with no timeout, 126 when the
;; child never says it is ready, within 20 s.
(define interrupt-script
  (string-append
   "t=$(command -v timeout || command -v gtimeout) || { echo 'group child: no timeout' >&2; exit 125; }\\n"
   "out=$(mktemp \\"${TMPDIR:-/tmp}/group-child.XXXXXX\\") || exit 125\\n"
   "\\"$t\\" -s KILL 60 \\"$@\\" >\\"$out\\" 2>&1 </dev/null &\\n"
""", """;; interrupt-script : String
;; sh -c INTERRUPT-SCRIPT sh COMMAND...: COMMAND under GNU timeout
;; (gtimeout on macOS), killed with SIGKILL after 60 s, its output in a
;; file made under TMPDIR; once it prints (ready PID), 500 ms later,
;; SIGINT to PID, the child Chez itself, then the file the child's
;; GROUP_CHILD_SENT names, made once the kill has returned, which lets the
;; child's holder go (child-hold); then its exit status, and its output but
;; the ready line. Exit 125 with no timeout, 126 when the child never says
;; it is ready, within 20 s.
(define interrupt-script
  (string-append
   "t=$(command -v timeout || command -v gtimeout) || { echo 'group child: no timeout' >&2; exit 125; }\\n"
   "out=$(mktemp \\"${TMPDIR:-/tmp}/group-child.XXXXXX\\") || exit 125\\n"
   "GROUP_CHILD_SENT=\\"$out.sent\\" \\"$t\\" -s KILL 60 \\"$@\\" >\\"$out\\" 2>&1 </dev/null &\\n"
""")
once("""cat \\"$out\\" >&2; rm -f \\"$out\\"; echo 'group child: the child never said it was ready' >&2; exit 126; fi\\n"
   "sleep 0.5\\n"
   "kill -INT \\"$pid\\"\\n"
   "wait \\"$waiter\\"\\n"
   "status=$?\\n"
   "grep -v '^(ready ' \\"$out\\"\\n"
   "rm -f \\"$out\\"\\n"
   "exit $status\\n"))
""", """cat \\"$out\\" >&2; rm -f \\"$out\\"; echo 'group child: the child never said it was ready' >&2; exit 126; fi\\n"
   "sleep 0.5\\n"
   "kill -INT \\"$pid\\"\\n"
   ": >\\"$out.sent\\"\\n"
   "wait \\"$waiter\\"\\n"
   "status=$?\\n"
   "grep -v '^(ready ' \\"$out\\"\\n"
   "rm -f \\"$out\\" \\"$out.sent\\"\\n"
   "exit $status\\n"))

;; child-hold : (Listof Datum)
;; The forms every SIGINT child below splices in after its import, for its
;; hold (M7 slice 4's races, research/m7/slice4/races):
;;   - (until-sent), which the holder sleeps in, holding its mutex, until
;;     the suite has sent the SIGINT: interrupt-script makes the file
;;     GROUP_CHILD_SENT names once its kill has returned, polled every 10 ms,
;;     for 20 s at most. So no release comes before the SIGINT, however late
;;     the script runs; the signal is then pending on the main thread, which
;;     runs Chez's C handler before it can take the mutex.
;;   - held-collections, (collections) as the holder starts to hold, and
;;     handler-collections, as the Ctrl-C handler starts: (quiet) answers
;;     quiet when they are equal. A collection asked for while the holder
;;     sleeps in its critical section waits for the hold to end, and so does
;;     every thread that reaches an event check meanwhile: a main thread
;;     that met one before its call blocked ran its handler only after the
;;     release, where it had stopped, in go's checks, whose guard read the
;;     handler's raise as the call's (measured: the CI failure of PR #45,
;;     reproduced by a trip planted at ready); and a submit-child so ended
;;     passed, its submit never made. Each child asks for a collection by
;;     collect-rendezvous before its holder starts, which leaves none due in
;;     the hold (collect-rendezvous, not collect, which refuses while the
;;     engines' threads are alive), and quiet shows none ran.
(define child-hold
  '((define child-sent (getenv "GROUP_CHILD_SENT"))
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
""")

# --- lost-child -----------------------------------------------------------------
once(""";; second thread then holds that mailbox's mutex, through the seam and the
;; private call-with-mailbox-held, for 1 s, and this thread prints (ready
;; PID) and awaits the call, inside the group's procedure, under a Ctrl-C
;; handler that escapes.""", """;; second thread then holds that mailbox's mutex, through the seam and the
;; private call-with-mailbox-held, until the suite has sent its SIGINT
;; (child-hold), and this thread prints (ready PID) and awaits the call,
;; inside the group's procedure, under a Ctrl-C handler that escapes.""")
once(""";; Prints (lost HOW TAKEN AGAIN): HOW, escaped or returned; TAKEN, taken
;; when the mailbox no longer holds the notice, else still-there; AGAIN,""",
     """;; Prints (lost HOW QUIET TAKEN AGAIN): HOW, escaped or returned; QUIET,
;; quiet when no collection ran in the hold (child-hold); TAKEN, taken
;; when the mailbox no longer holds the notice, else still-there; AGAIN,""")
once("""(define lost-child
  '((import (chezscheme) (curl) (http-client)
            (only (http-client private drive) http-pending-mailbox http-pending-token)
            (only (curl private engine) call-with-mailbox-held)
            (curl private counters))
""", """(define lost-child
  `((import (chezscheme) (curl) (http-client)
            (only (http-client private drive) http-pending-mailbox http-pending-token)
            (only (curl private engine) call-with-mailbox-held)
            (curl private counters))
    ,@child-hold
""")
once("""              (unless (or (curl-token-wait token 100) (> n 100)) (wait (+ n 1))))
            (fork-thread
             (lambda ()
               (call-with-mailbox-held (http-pending-mailbox p)
                 (lambda ()
                   (with-mutex lock (set! holding #t))
                   (sleep (make-time 'time-duration 0 1))))""", """              (unless (or (curl-token-wait token 100) (> n 100)) (wait (+ n 1))))
            (collect-rendezvous)
            (fork-thread
             (lambda ()
               (call-with-mailbox-held (http-pending-mailbox p)
                 (lambda ()
                   (with-mutex lock (set! held-collections (collections)) (set! holding #t))
                   (until-sent)))""")
once("""                          (keyboard-interrupt-handler (lambda () (out 'escaped)))""",
     """                          (keyboard-interrupt-handler
                           (lambda () (set! handler-collections (collections)) (out 'escaped)))""")
once("""                (write (list 'lost how taken second))""", """                (write (list 'lost how (quiet) taken second))""")

# --- submit-child and raise-child ---------------------------------------------------
once(""";; A program: it holds its session's engine's mutex from another thread
;; for 3 s, through the private call-with-engine-held, prints (ready PID),""",
     """;; A program: it holds its session's engine's mutex from another thread
;; until the suite has sent its SIGINT (child-hold), through the private
;; call-with-engine-held, prints (ready PID),""")
once(""";; Prints (submit HOW WHEN HOLDS), then (counts COUNTS), once the session
;; is closed.""", """;; Prints (submit HOW WHEN QUIET HOLDS), QUIET quiet when no collection
;; ran in the hold (child-hold), then (counts COUNTS), once the session is
;; closed.""")
once(""";; Prints (raise SAME COMPOUNDED WHEN HOLDS): SAME, whether what left the""",
     """;; Prints (raise SAME COMPOUNDED WHEN QUIET HOLDS): SAME, whether what left the""")
HOLDER3 = """    (fork-thread
     (lambda ()
       (call-with-engine-held engine
         (lambda ()
           (critical-section (with-mutex lock (set! holding #t)))
           (sleep (make-time 'time-duration 0 3))
           (critical-section (with-mutex lock (set! letting-go #t)))))
       (critical-section (with-mutex lock (set! released #t)))))
"""
FIXED3 = """    (collect-rendezvous)
    (fork-thread
     (lambda ()
       (call-with-engine-held engine
         (lambda ()
           (critical-section (with-mutex lock (set! held-collections (collections)) (set! holding #t)))
           (until-sent)
           (critical-section (with-mutex lock (set! letting-go #t)))))
       (critical-section (with-mutex lock (set! released #t)))))
"""
if s.count(HOLDER3) != 2:
    sys.exit(f"fix_group: submit and raise holders: {s.count(HOLDER3)}")
s = s.replace(HOLDER3, FIXED3)
for name in ('submit', 'raise'):
    once(f"""(define {name}-child
  '((import (chezscheme) (curl) (http-client)
            (only (http-client private call) http-session-engine http-session-draw
              http-session-generator)
            (only (curl private engine) call-with-engine-held curl-engine-live-count
                  curl-engine-queued-count)
""", f"""(define {name}-child
  `((import (chezscheme) (curl) (http-client)
            (only (http-client private call) http-session-engine http-session-draw
              http-session-generator)
            (only (curl private engine) call-with-engine-held curl-engine-live-count
                  curl-engine-queued-count)
""")
# the splice after each one's import: the counters import ends both
once("""                  curl-engine-queued-count)
            (curl private counters))
    (define url (car (command-line-arguments)))
    (define session (make-http-session 'timeout-ms 30000))
    (define engine (http-session-engine session))
    (define lock (make-mutex))
    (define holding #f)
    (define letting-go #f)
    (define released #f)
    (define (flag get) (critical-section (with-mutex lock (get))))
    (collect-rendezvous)""", """                  curl-engine-queued-count)
            (curl private counters))
    ,@child-hold
    (define url (car (command-line-arguments)))
    (define session (make-http-session 'timeout-ms 30000))
    (define engine (http-session-engine session))
    (define lock (make-mutex))
    (define holding #f)
    (define letting-go #f)
    (define released #f)
    (define (flag get) (critical-section (with-mutex lock (get))))
    (collect-rendezvous)""")
once("""            (only (curl private conditions) make-curl-engine-error)
            (curl private counters))
    (define url (car (command-line-arguments)))
    (define session (make-http-session 'timeout-ms 30000))""", """            (only (curl private conditions) make-curl-engine-error)
            (curl private counters))
    ,@child-hold
    (define url (car (command-line-arguments)))
    (define session (make-http-session 'timeout-ms 30000))""")
once("""         (keyboard-interrupt-handler
          (lambda ()
            (set! when-escaped (if (flag (lambda () letting-go)) 'after-release 'before-release))
            (out 'escaped)))""", """         (keyboard-interrupt-handler
          (lambda ()
            (set! handler-collections (collections))
            (set! when-escaped (if (flag (lambda () letting-go)) 'after-release 'before-release))
            (out 'escaped)))""")
once("""    (write (list 'submit how when-escaped holds))""", """    (write (list 'submit how when-escaped (quiet) holds))""")
once("""        (keyboard-interrupt-handler
         (lambda ()
           (set! when-raised (if (flag (lambda () letting-go)) 'after-release 'before-release))
           (raise planted)))""", """        (keyboard-interrupt-handler
         (lambda ()
           (set! handler-collections (collections))
           (set! when-raised (if (flag (lambda () letting-go)) 'after-release 'before-release))
           (raise planted)))""")
once("""                 when-raised holds))""", """                 when-raised (quiet) holds))""")

# --- turn-child -------------------------------------------------------------------
once(""";; turn's first hold of the engine's mutex. 800 ms into the wait another
;; thread takes that mutex, through call-with-engine-held, for 3 s, and this
;; thread prints (ready PID) and awaits the call, under a Ctrl-C handler""",
     """;; turn's first hold of the engine's mutex. 800 ms into the wait another
;; thread takes that mutex, through call-with-engine-held, until the suite
;; has sent its SIGINT (child-hold), and this thread prints (ready PID) and
;; awaits the call, under a Ctrl-C handler""")
once(""";; unrecorded. A collection asked for before the holder starts leaves none
;; due in the window: the holder sleeps in a critical section, where a
;; collection waits for it (traps.md). collect-rendezvous, not collect,
;; which refuses while the engines' threads are alive.""", """;; unrecorded. A collection asked for before the holder starts leaves none
;; due in the window (child-hold).""")
once(""";; Prints (turn HOW WHEN HOLDS PHASE), HOLDS the engine's live and queued""",
     """;; Prints (turn HOW WHEN QUIET HOLDS PHASE), QUIET as child-hold reads it,
;; HOLDS the engine's live and queued""")
once("""(define turn-child
  '((import (chezscheme) (curl) (http-client)
            (only (http-client private call) http-session-engine)
            (only (http-client private drive) http-pending-phase)
            (only (curl private engine) call-with-engine-held curl-engine-live-count
                  curl-engine-queued-count)
            (only (curl private conditions) make-curl-engine-error)
            (curl private counters))
""", """(define turn-child
  `((import (chezscheme) (curl) (http-client)
            (only (http-client private call) http-session-engine)
            (only (http-client private drive) http-pending-phase)
            (only (curl private engine) call-with-engine-held curl-engine-live-count
                  curl-engine-queued-count)
            (only (curl private conditions) make-curl-engine-error)
            (curl private counters))
    ,@child-hold
""")
once("""                (call-with-engine-held engine
                  (lambda ()
                    (critical-section (with-mutex lock (set! holding #t)))
                    (sleep (make-time 'time-duration 0 3))
                    (critical-section (with-mutex lock (set! letting-go #t)))))""", """                (call-with-engine-held engine
                  (lambda ()
                    (critical-section (with-mutex lock (set! held-collections (collections)) (set! holding #t)))
                    (until-sent)
                    (critical-section (with-mutex lock (set! letting-go #t)))))""")
once("""             (keyboard-interrupt-handler
              (lambda ()
                (set! when-escaped (if (flag (lambda () letting-go)) 'after-release 'before-release))
                (if (eq? mode 'raise) (raise planted) (out 'escaped))))""", """             (keyboard-interrupt-handler
              (lambda ()
                (set! handler-collections (collections))
                (set! when-escaped (if (flag (lambda () letting-go)) 'after-release 'before-release))
                (if (eq? mode 'raise) (raise planted) (out 'escaped))))""")
once("""    (write (list 'turn how when-escaped holds (http-pending-phase pending)))""",
     """    (write (list 'turn how when-escaped (quiet) holds (http-pending-phase pending)))""")

# --- sections-child and admissions-child --------------------------------------------
once(""";; first argument, is the raw face. Another thread holds the session's
;; engine's mutex for 2 s; this thread prints ready, then calls""", """;; first argument, is the raw face. Another thread holds the session's
;; engine's mutex until the suite has sent its SIGINT (child-hold); this
;; thread prints ready, then calls""")
once(""";; Prints (sections RAISED), RAISED (raised REASON URL TRANSFERS), then
;; (counts COUNTS).""", """;; Prints (sections QUIET RAISED), QUIET as child-hold reads it, RAISED
;; (raised REASON URL TRANSFERS), then (counts COUNTS).""")
once("""(define sections-child
  '((import (chezscheme) (curl) (http-client)
            (only (http-client private call) http-session-engine)
            (only (curl private engine) call-with-engine-held)
            (curl private counters))
""", """(define sections-child
  `((import (chezscheme) (curl) (http-client)
            (only (http-client private call) http-session-engine)
            (only (curl private engine) call-with-engine-held)
            (curl private counters))
    ,@child-hold
""")
once("""       (call-with-engine-held engine
         (lambda ()
           (critical-section (with-mutex lock (set! holding #t)))
           (sleep (make-time 'time-duration 0 2))))))
    (let spin ()
      (unless (flag (lambda () holding))
        (sleep (make-time 'time-duration 1000000 0))
        (spin)))
    (keyboard-interrupt-handler (lambda () (http-session-close session)))""", """       (call-with-engine-held engine
         (lambda ()
           (critical-section (with-mutex lock (set! held-collections (collections)) (set! holding #t)))
           (until-sent)))))
    (let spin ()
      (unless (flag (lambda () holding))
        (sleep (make-time 'time-duration 1000000 0))
        (spin)))
    (keyboard-interrupt-handler
     (lambda () (set! handler-collections (collections)) (http-session-close session)))""")
once("""    (write (list 'sections raised))""", """    (write (list 'sections (quiet) raised))""")
once(""";; two more queued behind them. Another thread then holds the engine's
;; mutex for 2 s; this thread prints ready, cancels the two waiting calls,""", """;; two more queued behind them. Another thread then holds the engine's
;; mutex until the suite has sent its SIGINT (child-hold); this thread
;; prints ready, cancels the two waiting calls,""")
once(""";; Prints (admissions FIRST SECOND), each ((KIND REASON) TRANSFERS) of what""",
     """;; Prints (admissions QUIET FIRST SECOND), QUIET as child-hold reads it,
;; each ((KIND REASON) TRANSFERS) of what""")
once("""(define admissions-child
  '((import (chezscheme) (curl) (http-client)
            (only (http-client private call) http-session-engine)
            (only (http-client private drive) http-pending-phase)
            (only (curl private engine) call-with-engine-held)
            (curl private counters))
""", """(define admissions-child
  `((import (chezscheme) (curl) (http-client)
            (only (http-client private call) http-session-engine)
            (only (http-client private drive) http-pending-phase)
            (only (curl private engine) call-with-engine-held)
            (curl private counters))
    ,@child-hold
""")
once("""               (call-with-engine-held engine
                 (lambda ()
                   (critical-section (with-mutex lock (set! holding #t)))
                   (sleep (make-time 'time-duration 0 2))))))
            (let spin ()
              (unless (flag (lambda () holding))
                (sleep (make-time 'time-duration 1000000 0))
                (spin)))
            (keyboard-interrupt-handler (lambda () (http-session-close session)))""", """               (call-with-engine-held engine
                 (lambda ()
                   (critical-section (with-mutex lock (set! held-collections (collections)) (set! holding #t)))
                   (until-sent)))))
            (let spin ()
              (unless (flag (lambda () holding))
                (sleep (make-time 'time-duration 1000000 0))
                (spin)))
            (keyboard-interrupt-handler
             (lambda () (set! handler-collections (collections)) (http-session-close session)))""")
once("""    (write (cons 'admissions outcome))""", """    (write (cons* 'admissions (quiet) outcome))""")

# --- resume-child -------------------------------------------------------------------
once(""";; the case. Another thread holds a mutex, the gate, for 2 s, inside a
;; critical section; this thread prints (ready PID) and runs the case,""", """;; the case. Another thread holds a mutex, the gate, inside a critical
;; section, until the suite has sent its SIGINT (child-hold); this thread
;; prints (ready PID) and runs the case,""")
once(""";; Prints (resume CASE RESULT SUBMITS SUSPENSIONS STARTED-AFTER
;; SUBMITS-AFTER): RESULT (raised REASON WHO INDEX), INDEX the URL's in the""",
     """;; Prints (resume CASE QUIET RESULT SUBMITS SUSPENSIONS STARTED-AFTER
;; SUBMITS-AFTER): QUIET as child-hold reads it at the first suspension;
;; RESULT (raised REASON WHO INDEX), INDEX the URL's in the""")
once("""(define resume-child
  '((import (chezscheme) (curl) (http-client)
            (only (http-client private call) http-session-engine call-request)
            (only (http-client private drive) call-with-group run-parallel monotonic-ns)
            (only (http-client private exchange) make-exchange)
            (only (curl private transfer) transfers-started)
            (curl private counters))
""", """(define resume-child
  `((import (chezscheme) (curl) (http-client)
            (only (http-client private call) http-session-engine call-request)
            (only (http-client private drive) call-with-group run-parallel monotonic-ns)
            (only (http-client private exchange) make-exchange)
            (only (curl private transfer) transfers-started)
            (curl private counters))
    ,@child-hold
""")
once("""        (with-mutex gate
          (critical-section (with-mutex lock (set! holding #t)))
          (sleep (make-time 'time-duration 0 2))))))""", """        (with-mutex gate
          (critical-section (with-mutex lock (set! held-collections (collections)) (set! holding #t)))
          (until-sent)))))""")
once("""    (keyboard-interrupt-handler
     (lambda ()
       (set! suspensions (+ suspensions 1))""", """    (keyboard-interrupt-handler
     (lambda ()
       (unless handler-collections (set! handler-collections (collections)))
       (set! suspensions (+ suspensions 1))""")
once("""    (write (list 'resume which result submits-at suspensions""", """    (write (list 'resume which (quiet) result submits-at suspensions""")

# --- the tests' expected values ----------------------------------------------------------
once("""     (list 0 (list 'lost 'escaped 'taken '(answered 200 "status 200\\n")) (list 'counts zero-counts) "")""",
     """     (list 0 (list 'lost 'escaped 'quiet 'taken '(answered 200 "status 200\\n")) (list 'counts zero-counts) "")""")
once("""     (list 0 '(submit escaped after-release (0 0 0)) (list 'counts zero-counts) "")""",
     """     (list 0 '(submit escaped after-release quiet (0 0 0)) (list 'counts zero-counts) "")""")
once("""     (list 0 '(raise #t #f after-release (0 0 0)) (list 'counts zero-counts) "")""",
     """     (list 0 '(raise #t #f after-release quiet (0 0 0)) (list 'counts zero-counts) "")""")
once("""     (list 0 '(turn escaped after-release (0 0 0) ended) (list 'counts zero-counts) "")""",
     """     (list 0 '(turn escaped after-release quiet (0 0 0) ended) (list 'counts zero-counts) "")""")
once("""     (list 0 '(turn (raise #t #f) after-release (0 0 0) ended) (list 'counts zero-counts) "")""",
     """     (list 0 '(turn (raise #t #f) after-release quiet (0 0 0) ended) (list 'counts zero-counts) "")""")
once("""     (list 0 (list 'sections (list 'raised 'stopped (url-of 'raw "/raw/hold?key=sections-1&ms=1000") 0))""",
     """     (list 0 (list 'sections 'quiet (list 'raised 'stopped (url-of 'raw "/raw/hold?key=sections-1&ms=1000") 0))""")
once("""     (list 0 '(admissions ((transfer stopped) 1) ((engine stopped) 0)) (list 'counts zero-counts) "")""",
     """     (list 0 '(admissions quiet ((transfer stopped) 1) ((engine stopped) 0)) (list 'counts zero-counts) "")""")
once("""    '((resume P1 (raised cancelled http-await 0) 2 1 0 0)
      (resume P3 (raised cancelled http-await 1) 3 1 0 0)
      (resume G (value (#t (cancelled http-await 0) (closed go #f))) 1 1 0 0)))""",
     """    '((resume P1 quiet (raised cancelled http-await 0) 2 1 0 0)
      (resume P3 quiet (raised cancelled http-await 1) 3 1 0 0)
      (resume G quiet (value (#t (cancelled http-await 0) (closed go #f))) 1 1 0 0)))""")

# The titles that name a hold's length.
open(path, 'w').write(s)
print('fix_group: done')
