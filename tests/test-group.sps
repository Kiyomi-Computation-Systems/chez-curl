#!r6rs
;;; The suite for the request group and http-parallel, the high level's
;;; fourth slice (the M5 plan, sections 3.7 and 7): call-with-request-group,
;;; go, http-await, http-pending-done?, http-pending-cancel and
;;; http-parallel, and &http-group-error.
;;;
;;;   - the condition, its reasons written out, and the limit key's
;;;     refusals, by name and by value, before any call;
;;;   - each refusal inside a critical section, before anything else, and
;;;     go and http-pending-cancel, which refuse nothing there;
;;;   - go's checks, made at go, its refusal raised from it with no call
;;;     made, and a submit's refusal, past the first, the call's own;
;;;   - confinement: wrong-thread from another thread for each of the four,
;;;     before anything else, and closed after the group returns or escapes;
;;;   - the join on a return, which waits for every call, answers every
;;;     value, and raises the first failure no await answered, a cancelled
;;;     call exempt, in either order of the cancel and the turn that saw it
;;;     fail, failures one look finds numbered in submit order; on a raise,
;;;     three times, which cancels every call and waits for every transfer
;;;     to end, read through the engine's own counts; on an escape from the
;;;     join's own wait; and a second escape swept over the first's unwind,
;;;     which cannot skip the cancel;
;;;   - a raise inside a call's own section, the draw's in the look's step,
;;;     a submit's at a due retry, at an admission, at a turn's admission
;;;     and at one of run-parallel's, through the private call-with-group
;;;     and run-parallel: that call's failure alone; one after its call has
;;;     ended, raised again; a refused submit's step, drawing once; a step's
;;;     clocks, read after its draw;
;;;   - a Chez engine's expiry, swept over its fuel, in http-parallel and in
;;;     go: every outcome one the docs name, and no transfer started after
;;;     the expiry once the group exists, with the sweeps' evidence that
;;;     some expiry landed before a group and some inside one; and one
;;;     placed in go's checks by engine-block, its recheck raising closed
;;;     once its entry's section has ended, to a handler with interrupts on;
;;;   - a run suspended and resumed at chosen places, by a SIGINT handler
;;;     that escapes out of the group and is re-entered, in a child:
;;;     http-parallel raising its first unfinished call's cancel, in SPECS'
;;;     order, and go answering its pending after its entry;
;;;   - each token stepped once: a lost notice, its notice taken out
;;;     through the seam to the group's mailbox before any look; an escape
;;;     planted at the take by SIGINT, in a child, the notice its look had
;;;     stepped taken out; and a late notice, a token found done by a look
;;;     after a take that answered #f, the redirect it makes counted once at
;;;     the origin;
;;;   - a submit and its record, SIGINT while a submit blocks on the
;;;     engine's mutex, in a child, the group's escape still ending the
;;;     transfer; and a Ctrl-C handler's own &curl-error raised there,
;;;     which leaves go as raised, no refusal of the submit's; the same two
;;;     for a turn's own submit, a call's due retry, in a child; and each
;;;     admission a section of its own, http-parallel's and a turn's, a
;;;     SIGINT handler's close as the first ends refusing the second;
;;;   - a redirect and a retry of one call proceeding while another is
;;;     awaited; a redirect keeping its call's slot, ahead of the queue;
;;;     admission first in, first out, a group's and http-parallel's; a
;;;     deferred submit that raises, the session closed, as that call's
;;;     failure alone; http-pending-done? moving the group on, with no wait;
;;;   - the limit held, counted at the origin's hold script, and the time
;;;     of 20 calls of 500 ms on one session: within 2 s with no limit, 5 s
;;;     at least with a limit of 2, its control;
;;;   - a queued call's deadline, kept to within 50 ms over every phase of
;;;     the take's bound, a retry's wait ending at its due time, the
;;;     session's draw, an await answering twice, a cancel of an ended call;
;;;   - http-parallel: its order, its checks before any submit, seen with
;;;     the engine held, where a submit would wait, a timer's raise while it
;;;     judges SPECS left as raised, the scheme's refusal curl-request-check's
;;;     and no step's, its first failure raised with the rest ended
;;;     before any unwinding, three times, and a stopped engine's refusals
;;;     in SPECS' order.
;;;
;;; A group's own thread alone may await its calls, so each test's session
;;; is bounded by a timer's escape, 40 s: a mutant that hangs fails by name.
;;;
;;; Every check on the raw face makes its own session: the raw face closes
;;; after each script without saying so, and curl 8.23.0 resends on each
;;; dead pooled connection (traps.md). The hold, retry and location scripts
;;; say Connection: close. Every wait here is bounded. Every expected value
;;; is one the code under test cannot produce by failing: SRFI-64 makes #f
;;; of a raise in the actual expression, so none is #f.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) sleep make-time current-time time-second time-nanosecond getenv
              library-directories set-timer timer-interrupt-handler fork-thread make-mutex
              with-mutex critical-section get-thread-id iota make-list collect-rendezvous
              pseudo-random-generator->vector vector->pseudo-random-generator
              pseudo-random-generator-next! make-engine engine-block disable-interrupts
              enable-interrupts)
        (curl-testing)
        (curl)
        (http-client)
        (only (http-client private conditions) make-http-group-error)
        (only (http-client private call) http-session-engine http-session-draw
              http-session-generator call-request)
        (only (http-client private drive) http-pending-mailbox http-pending-token
              http-pending-phase http-pending-census call-with-group run-parallel monotonic-ns)
        (only (http-client private exchange) make-exchange)
        (only (curl private engine) curl-engine-live-count curl-engine-queued-count
              call-with-engine-held)
        (only (curl private transfer) transfers-started)
        (only (curl private conditions) make-curl-engine-error)
        (curl private counters))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; written : Any -> String
(define (written x) (call-with-string-output-port (lambda (p) (write x p))))

;; shown : Any -> String
;; X written, cut to 3000 characters.
(define (shown x)
  (let ((text (written x)))
    (if (> (string-length text) 3000)
        (string-append (substring text 0 3000) "...")
        text)))

;; The simple runner names a failing test but not its values. Print both.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (display "  expected: ")
        (display (shown (test-result-ref r 'expected-value)))
        (newline)
        (display "  actual:   ")
        (display (shown (test-result-ref r 'actual-value)))
        (newline))
      ;; A suite killed at its bound never flushes: flush each verdict.
      (flush-output-port (current-output-port)))))

(test-begin "group")

;; --- helpers --------------------------------------------------------------------------

(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)))

;; now-ms : -> Integer
(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

;; pause-ms : Natural -> Unit
(define (pause-ms ms)
  (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))

;; count-of : Symbol -> Natural
(define (count-of kind) (cdr (assq kind (native-counts))))

;; latin-1 : Bytevector -> String
(define (latin-1 bytes)
  (list->string (map integer->char (bytevector->u8-list bytes))))

;; hex2 : Natural -> String
(define (hex2 b)
  (string #\% (string-ref "0123456789ABCDEF" (div b 16)) (string-ref "0123456789ABCDEF" (mod b 16))))

;; pct : String -> String
;; S, ASCII, each char kept when a letter or a digit, -, ., _ or ~, else
;; %XX: a query value the raw face decodes back to its bytes.
(define (pct s)
  (apply string-append
         (map (lambda (ch)
                (let ((b (char->integer ch)))
                  (if (or (<= 48 b 57) (<= 65 b 90) (<= 97 b 122) (memv b '(45 46 95 126)))
                      (string ch)
                      (hex2 b))))
              (string->list s))))

;; class-of : Condition -> Symbol
(define (class-of e)
  (cond ((curl-timeout? e) 'timeout)
        ((curl-connect-error? e) 'connect)
        ((curl-send-receive-error? e) 'send-receive)
        (else 'other)))

;; summary : Response -> (List Integer String Natural)
;; Its status, URL and history's length.
(define (summary r)
  (if (http-response? r)
      (list (http-response-status r) (http-response-url r) (length (http-response-history r)))
      (list 'not-a-response r)))

;; described : Any -> (Listof Any)
;; What a raised object is, whole: for a condition, each of these it is, in
;; this order, with its fields; for anything else, (non-condition X).
(define (described e)
  (if (condition? e)
      (filter
       (lambda (x) x)
       (list (and (http-error? e) '(http-error))
             (and (http-group-error? e)
                  (list 'http-group-error (http-group-error-reason e)
                        (and (who-condition? e) (condition-who e))))
             (and (http-request-error? e)
                  (list 'http-request-error (http-request-error-field e) (http-request-error-value e)
                        (http-request-error-reason e)
                        (and (who-condition? e) (condition-who e))))
             (and (http-timeout? e) (list 'http-timeout (http-timeout-timeout-ms e)))
             (and (curl-url-error? e) (list 'curl-url-error (curl-url-error-reason e)))
             (and (curl-engine-error? e) (list 'curl-engine-error (curl-engine-error-reason e)))
             (and (curl-transfer-error? e)
                  (list 'curl-transfer-error (class-of e) (curl-transfer-error-reason e)
                        (curl-transfer-error-code e)))
             (and (assertion-violation? e)
                  (list 'assertion (and (who-condition? e) (condition-who e))))
             (and (http-exchange? e)
                  (list 'exchange (http-exchange-method e) (http-exchange-url e)
                        (length (http-exchange-history e)) (http-exchange-transfers e)))))
      (list 'non-condition e)))

;; outcome : (-> Any) -> (Pairof Symbol Any)
;; (returned VALUE), or (raised . DESCRIBED).
(define (outcome thunk)
  (guard (e (#t (cons 'raised (described e))))
    (list 'returned (thunk))))

;; answer : (-> Response) -> Any
;; (answered STATUS URL BODY HISTORY-LENGTH), the body as Latin-1, or what
;; THUNK raised.
(define (answer thunk)
  (guard (e (#t (cons 'raised (described e))))
    (let ((r (thunk)))
      (if (http-response? r)
          (list 'answered (http-response-status r) (http-response-url r)
                (latin-1 (http-response-body r)) (length (http-response-history r)))
          (list 'not-a-response r)))))

;; in-order : (Any -> Any) (Listof Any) -> (Listof Any)
;; PROC of each of ITEMS, first to last: map calls its procedure in no
;; fixed order (traps.md).
(define (in-order proc items)
  (let loop ((rest items) (answers '()))
    (if (null? rest)
        (reverse answers)
        (let ((answer (proc (car rest))))
          (loop (cdr rest) (cons answer answers))))))

;; with-session : (Listof Any) (Session -> Any) -> Any
;; PROC's answer, on a session of its own made from PLIST, closed after;
;; or (hung 40000) once 40 s pass, by escape-after.
(define (with-session plist proc)
  (let ((session (apply make-http-session plist)))
    (dynamic-wind
      (lambda () #f)
      (lambda () (escape-after 40000 (lambda () (proc session))))
      (lambda () (http-session-close session)))))

;; engine-holds : Session -> (List Natural Natural Natural)
;; SESSION's engine's live and queued counts, read through the private
;; accessors, then this process's transfer count.
(define (engine-holds s)
  (let* ((engine (http-session-engine s))
         (live (curl-engine-live-count engine))
         (queued (curl-engine-queued-count engine)))
    (list live queued (count-of 'transfer))))

;; escape-after : Natural (-> Any) -> Any
;; THUNK's answer, or (hung MS) once MS ms pass: a timer's handler escapes
;; from it. Bounds a wait on the group's own thread, which no other thread
;; may await, so a mutant that hangs fails by name. It restores the handler
;; and the ticks left of any bound around it: set-timer answers them.
(define (escape-after ms thunk)
  (let* ((t0 (now-ms))
         (previous (timer-interrupt-handler))
         (left #f)
         (r (call/cc
             (lambda (k)
               (timer-interrupt-handler
                (lambda () (if (> (- (now-ms) t0) ms) (k (list 'hung ms)) (set-timer 2000))))
               (set! left (set-timer 2000))
               (thunk)))))
    (set-timer 0)
    (timer-interrupt-handler previous)
    (when (and left (> left 0)) (set-timer left))
    r))

;; iota-from : Integer Natural -> (Listof Integer)
;; N integers, from START up.
(define (iota-from start n) (map (lambda (i) (+ start i)) (iota n)))

;; poll-until : Natural (-> Boolean) -> (U 'reached 'timed-out)
;; READY? asked every 10 ms until it holds, or MS pass.
(define (poll-until ms ready?)
  (let ((deadline (+ (now-ms) ms)))
    (let loop ()
      (cond ((ready?) 'reached)
            ((> (now-ms) deadline) 'timed-out)
            (else (pause-ms 10) (loop))))))

;; ended-within : Natural -> Symbol
;; ended once no transfer is live, polled every 10 ms, or still-live once
;; MS ms pass.
(define (ended-within ms)
  (let ((deadline (+ (now-ms) ms)))
    (let loop ()
      (cond ((= (count-of 'transfer) 0) 'ended)
            ((> (now-ms) deadline) 'still-live)
            (else (pause-ms 10) (loop))))))

;; escape-twice : String Natural -> (List Natural Symbol Symbol)
;; A group on a session of its own, whose procedure calls URL, a long
;; drip, and awaits it, escaped from that await by a timer's handler once
;; the transfer is live and 100 ms have passed. That handler sets the timer
;; again, for TICKS, before it escapes, so a second escape lands TICKS
;; ticks into the unwind: in the group's inner after thunk, for some TICKS,
;; if its interrupts were on. The second handler notes whether the call
;; had ended by then, as the inner after thunk's cancel ends it: before,
;; or after. Answers TICKS, what the second handler saw, or none when it
;; never ran, and whether no transfer is live within 3 s, ended, or
;; still-live.
(define (escape-twice url ticks)
  (let* ((own (make-http-session 'timeout-ms 30000))
         (t0 (now-ms))
         (phase 'first)
         (pending #f)
         (seen 'none)
         (previous (timer-interrupt-handler)))
    (call/cc
     (lambda (twice)
       (call/cc
        (lambda (once)
          (timer-interrupt-handler
           (lambda ()
             (case phase
               ((first)
                (if (and (>= (- (now-ms) t0) 100) (= (count-of 'transfer) 1))
                    (begin (set! phase 'second) (set-timer ticks) (once 'once))
                    (set-timer 200)))
               ((second)
                (set! phase 'done)
                (set! seen (if (and pending (eq? (http-pending-phase pending) 'ended)) 'after 'before))
                (twice 'twice))
               (else #f))))
          (set-timer 200)
          (call-with-request-group own
            (lambda (go)
              (set! pending (go 'get url))
              (http-await pending)))))
       (set-timer 0)))
    (set-timer 0)
    (set! phase 'done)
    (timer-interrupt-handler previous)
    (let ((ended (ended-within 3000)))
      (http-session-close own)
      (list ticks seen ended))))

;; before-then-after : (Listof Symbol) -> (U 'before-then-after (Listof Symbol))
;; before-then-after when SEENS is before once or more, then after once or
;; more, with none anywhere among them; else SEENS, to show.
(define (before-then-after seens)
  (let loop ((rest seens) (before? #f))
    (cond ((null? rest) seens)
          ((eq? (car rest) 'none) (loop (cdr rest) before?))
          ((eq? (car rest) 'before) (if before? (loop (cdr rest) #t) (loop (cdr rest) #t)))
          ((and before? (for-all (lambda (s) (memq s '(after none))) rest)) 'before-then-after)
          (else seens))))

;; engine-run : Natural (-> Any) -> (List Boolean Any (U Integer #f))
;; THUNK in a Chez engine of FUEL ticks, resumed once, with fuel enough to
;; finish, if it expired: whether it expired, its answer, and how many
;; transfers started after the expiry, #f with none.
(define (engine-run fuel thunk)
  (let* ((expired #f)
         (at #f)
         (result '(never-answered))
         (eng (make-engine thunk)))
    (eng fuel
         (lambda (left v) (set! result v))
         (lambda (next)
           (set! expired #t)
           (set! at (transfers-started))
           (next 1000000000
                 (lambda (left v) (set! result v))
                 (lambda (again) (set! result '(expired-twice))))))
    (list expired result (and at (- (transfers-started) at)))))

;; expiry-class : Any -> Any
;; What a raise out of a group under an engine is: cancelled, closed or
;; another reason of &http-group-error; re-entry, (curl)'s refusal to
;; re-enter a URL's parse, an assertion violation from
;; call-with-parsed-url, which the sweeps refuse; failure, a call's failure, with its
;; &http-exchange; or (other ...).
(define (expiry-class e)
  (cond ((and (condition? e) (http-group-error? e)) (http-group-error-reason e))
        ((and (condition? e) (assertion-violation? e) (who-condition? e)
              (eq? (condition-who e) 'call-with-parsed-url))
         're-entry)
        ((and (condition? e) (http-exchange? e)) 'failure)
        (else (list 'other (described e)))))

;; --- children ----------------------------------------------------------------------------

;; library-path : -> String
(define (library-path)
  (let loop ((dirs (map car (library-directories))) (text ""))
    (cond ((null? dirs) text)
          ((string=? text "") (loop (cdr dirs) (car dirs)))
          (else (loop (cdr dirs) (string-append text ":" (car dirs)))))))

;; read-all : String -> (Listof Any)
(define (read-all text)
  (let ((port (open-string-input-port text)))
    (let loop ((found '()))
      (let ((datum (guard (e (#t '(unreadable))) (read port))))
        (cond ((eof-object? datum) (reverse found))
              ((equal? datum '(unreadable)) (reverse (cons datum found)))
              (else (loop (cons datum found))))))))

;; interrupt-script : String
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
   "t=$(command -v timeout || command -v gtimeout) || { echo 'group child: no timeout' >&2; exit 125; }\n"
   "out=$(mktemp \"${TMPDIR:-/tmp}/group-child.XXXXXX\") || exit 125\n"
   "GROUP_CHILD_SENT=\"$out.sent\" \"$t\" -s KILL 60 \"$@\" >\"$out\" 2>&1 </dev/null &\n"
   "waiter=$!\n"
   "n=0\n"
   "until grep -q '^(ready ' \"$out\" || [ \"$n\" -ge 400 ]; do sleep 0.05; n=$((n + 1)); done\n"
   "pid=$(sed -n 's/^(ready \\([0-9]*\\))$/\\1/p' \"$out\")\n"
   "if [ -z \"$pid\" ]; then kill \"$waiter\"; wait \"$waiter\"; cat \"$out\" >&2; rm -f \"$out\"; echo 'group child: the child never said it was ready' >&2; exit 126; fi\n"
   "sleep 0.5\n"
   "kill -INT \"$pid\"\n"
   ": >\"$out.sent\"\n"
   "wait \"$waiter\"\n"
   "status=$?\n"
   "grep -v '^(ready ' \"$out\"\n"
   "rm -f \"$out\" \"$out.sent\"\n"
   "exit $status\n"))

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

;; run-child : (Listof Datum) String String ... -> (List Integer (Listof Any) String)
;; PROGRAM, written to a directory of its own, run on URL and MORE under
;; interrupt-script: its exit status, what it printed but its ready line,
;; read as data, and the script's stderr.
(define (run-child program url . more)
  (guard (e (#t (list 'raised (describe e) "")))
    (call-with-temp-directory
     (lambda (dir)
       (let ((path (string-append dir "/group-child.sps")))
         (call-with-output-file path
           (lambda (port) (for-each (lambda (form) (write form port) (newline port)) program)))
         (let ((r (capture-command (append (list "sh" "-c" interrupt-script "sh" (getenv "CHEZ")
                                                 "--libdirs" (library-path) "--program" path url)
                                           more))))
           (list (car r) (read-all (cadr r)) (caddr r))))))))

;; lost-child : (Listof Datum)
;; A program: in a group on a session of its own, a call to URL, its
;; first argument, a fast 200. It waits for the call's token to be done,
;; with no turn run, so the token's notice is in the group's mailbox. A
;; second thread then holds that mailbox's mutex, through the seam and the
;; private call-with-mailbox-held, until the suite has sent its SIGINT
;; (child-hold), and this thread prints (ready PID) and awaits the call,
;; inside the group's procedure, under a Ctrl-C handler that escapes. The
;; await's turn looks first: the token is done, so the look steps the
;; call, which ends, before the turn's take. The take then blocks inside
;; its critical section on the held mutex; the
;; suite sends SIGINT meanwhile, so the handler escapes as the take's
;; section ends, once it has taken the notice out (traps.md: a Chez timer
;; cannot plant it there). So what this shows is an escape at a take that
;; took out a notice the look had already stepped, and a second await then
;; answering: the notice lost is a late one. A notice lost while its call
;; is unstepped is the seam test's, which takes it out by hand. The escape
;; is caught inside the procedure, which then awaits the call again,
;; bounded by 5 s.
;;
;; Prints (lost HOW QUIET TAKEN AGAIN): HOW, escaped or returned; QUIET,
;; quiet when no collection ran in the hold (child-hold); TAKEN, taken
;; when the mailbox no longer holds the notice, else still-there; AGAIN,
;; the second await's (answered STATUS BODY), (raised ...) or (hung). Then
;; (counts COUNTS), once the group has returned and the session is closed.
(define lost-child
  `((import (chezscheme) (curl) (http-client)
            (only (http-client private drive) http-pending-mailbox http-pending-token)
            (only (curl private engine) call-with-mailbox-held)
            (curl private counters))
    ,@child-hold
    (define url (car (command-line-arguments)))
    (define (now-ms)
      (let ((t (current-time 'time-monotonic)))
        (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))
    (define (latin-1 bytes) (list->string (map integer->char (bytevector->u8-list bytes))))
    (define session (make-http-session 'timeout-ms 20000))
    (define lock (make-mutex))
    (define holding #f)
    (define released #f)
    (define (flag get) (critical-section (with-mutex lock (get))))
    (define (again p)
      (let* ((t0 (now-ms))
             (previous (timer-interrupt-handler))
             (r (call/cc
                 (lambda (k)
                   (timer-interrupt-handler
                    (lambda () (if (> (- (now-ms) t0) 5000) (k '(hung)) (set-timer 2000))))
                   (set-timer 2000)
                   (guard (e (#t (list 'raised (condition? e))))
                     (let ((r (http-await p)))
                       (list 'answered (http-response-status r) (latin-1 (http-response-body r)))))))))
        (set-timer 0)
        (timer-interrupt-handler previous)
        r))
    (define result
      (call-with-request-group session
        (lambda (go)
          (let* ((p (go 'get url))
                 (token (http-pending-token p)))
            (let wait ((n 0))
              (unless (or (curl-token-wait token 100) (> n 100)) (wait (+ n 1))))
            (collect-rendezvous)
            (fork-thread
             (lambda ()
               (call-with-mailbox-held (http-pending-mailbox p)
                 (lambda ()
                   (with-mutex lock (set! held-collections (collections)) (set! holding #t))
                   (until-sent)))
               (critical-section (with-mutex lock (set! released #t)))))
            (let spin ()
              (unless (flag (lambda () holding))
                (sleep (make-time 'time-duration 1000000 0))
                (spin)))
            (let ((how (call/cc
                        (lambda (out)
                          (keyboard-interrupt-handler
                           (lambda () (set! handler-collections (collections)) (out 'escaped)))
                          (write (list 'ready (get-process-id)))
                          (newline)
                          (flush-output-port (current-output-port))
                          (http-await p)
                          'returned))))
              (keyboard-interrupt-handler void)
              (let spin ()
                (unless (flag (lambda () released))
                  (sleep (make-time 'time-duration 1000000 0))
                  (spin)))
              (let* ((taken (if (curl-mailbox-take (http-pending-mailbox p) 0) 'still-there 'taken))
                     (second (again p)))
                (write (list 'lost how (quiet) taken second))
                (newline)
                (flush-output-port (current-output-port))
                (when (equal? second '(hung)) (exit 1))
                'done))))))
    (http-session-close session)
    (write (list 'counts (native-counts)))
    (newline)))

;; submit-child : (Listof Datum)
;; A program: it holds its session's engine's mutex from another thread
;; until the suite has sent its SIGINT (child-hold), through the private
;; call-with-engine-held, prints (ready PID), and enters a group whose
;; procedure calls go on URL, its first argument, a 10 s drip, under a
;; Ctrl-C handler that escapes from outside the group.
;; go's submit blocks on that mutex inside its critical section; the suite
;; sends SIGINT meanwhile, so the handler escapes as the section ends, once
;; the submit has taken the mutex (traps.md). The group's winds then
;; cancel what the group recorded and wait for it to end. The handler
;; records whether the holder had begun to let go, a flag it sets just
;; before it does: after-release shows the escape came once the submit
;; could take the mutex.
;;
;; The witness is the engine's own: its live and queued counts and the
;; transfer count, read 500 ms after the holder let go, when the engine
;; has set up anything it took (traps.md: a token it is setting up is in
;; neither count). A transfer the group did not record would run on there,
;; its 10 s drip.
;;
;; Prints (submit HOW WHEN QUIET HOLDS), QUIET quiet when no collection
;; ran in the hold (child-hold), then (counts COUNTS), once the session is
;; closed.
(define submit-child
  `((import (chezscheme) (curl) (http-client)
            (only (http-client private call) http-session-engine http-session-draw
              http-session-generator)
            (only (curl private engine) call-with-engine-held curl-engine-live-count
                  curl-engine-queued-count)
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
    (collect-rendezvous)
    (fork-thread
     (lambda ()
       (call-with-engine-held engine
         (lambda ()
           (critical-section (with-mutex lock (set! held-collections (collections)) (set! holding #t)))
           (until-sent)
           (critical-section (with-mutex lock (set! letting-go #t)))))
       (critical-section (with-mutex lock (set! released #t)))))
    (let spin ()
      (unless (flag (lambda () holding))
        (sleep (make-time 'time-duration 1000000 0))
        (spin)))
    (define when-escaped #f)
    (define how
      (call/cc
       (lambda (out)
         (keyboard-interrupt-handler
          (lambda ()
            (set! handler-collections (collections))
            (set! when-escaped (if (flag (lambda () letting-go)) 'after-release 'before-release))
            (out 'escaped)))
         (write (list 'ready (get-process-id)))
         (newline)
         (flush-output-port (current-output-port))
         (call-with-request-group session (lambda (go) (go 'get url) 'returned)))))
    (keyboard-interrupt-handler void)
    (let spin ()
      (unless (flag (lambda () released))
        (sleep (make-time 'time-duration 1000000 0))
        (spin)))
    (sleep (make-time 'time-duration 500000000 0))
    (define holds
      (let* ((live (curl-engine-live-count engine))
             (queued (curl-engine-queued-count engine)))
        (list live queued (cdr (assq 'transfer (native-counts))))))
    (write (list 'submit how when-escaped (quiet) holds))
    (newline)
    (http-session-close session)
    (write (list 'counts (native-counts)))
    (newline)))

;; raise-child : (Listof Datum)
;; submit-child's program, but its Ctrl-C handler raises a &curl-error of
;; its own making where submit-child's escapes, from outside the group:
;; the handler runs as go's submit's critical section ends, once the submit
;; has taken the mutex, and its raise is no refusal of the submit's (the
;; guard that reads one sits inside the section), so it leaves go as
;; raised, and the group's winds cancel the transfer it recorded.
;;
;; Prints (raise SAME COMPOUNDED WHEN QUIET HOLDS): SAME, whether what left
;; the group is that very object; COMPOUNDED, whether it carries an
;; &http-exchange; then (counts COUNTS), once the session is closed.
(define raise-child
  `((import (chezscheme) (curl) (http-client)
            (only (http-client private call) http-session-engine http-session-draw
              http-session-generator)
            (only (curl private engine) call-with-engine-held curl-engine-live-count
                  curl-engine-queued-count)
            (only (curl private conditions) make-curl-engine-error)
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
    (collect-rendezvous)
    (fork-thread
     (lambda ()
       (call-with-engine-held engine
         (lambda ()
           (critical-section (with-mutex lock (set! held-collections (collections)) (set! holding #t)))
           (until-sent)
           (critical-section (with-mutex lock (set! letting-go #t)))))
       (critical-section (with-mutex lock (set! released #t)))))
    (let spin ()
      (unless (flag (lambda () holding))
        (sleep (make-time 'time-duration 1000000 0))
        (spin)))
    (define planted (condition (make-curl-engine-error 'stopped #f)
                               (make-message-condition "planted by the child's Ctrl-C handler")))
    (define when-raised #f)
    (define caught
      (guard (e (#t e))
        (keyboard-interrupt-handler
         (lambda ()
           (set! handler-collections (collections))
           (set! when-raised (if (flag (lambda () letting-go)) 'after-release 'before-release))
           (raise planted)))
        (write (list 'ready (get-process-id)))
        (newline)
        (flush-output-port (current-output-port))
        (call-with-request-group session (lambda (go) (go 'get url) 'returned))))
    (keyboard-interrupt-handler void)
    (let spin ()
      (unless (flag (lambda () released))
        (sleep (make-time 'time-duration 1000000 0))
        (spin)))
    (sleep (make-time 'time-duration 500000000 0))
    (define holds
      (let* ((live (curl-engine-live-count engine))
             (queued (curl-engine-queued-count engine)))
        (list live queued (cdr (assq 'transfer (native-counts))))))
    (write (list 'raise (eq? caught planted) (and (condition? caught) (http-exchange? caught))
                 when-raised (quiet) holds))
    (newline)
    (http-session-close session)
    (write (list 'counts (native-counts)))
    (newline)))

;; turn-child : (Listof Datum)
;; A program, from the review's probe: a turn's own submit and its record,
;; the due submit of a call in a retry's wait, planted as submit-child plants
;; go's. URL, its first argument, closes the first attempt and stalls the
;; retry; the call waits 1000 ms to retry. With the call waiting, the
;; group's live and draining sets are empty, so the due submit is the
;; turn's first hold of the engine's mutex. 800 ms into the wait another
;; thread takes that mutex, through call-with-engine-held, until the suite
;; has sent its SIGINT (child-hold), and this thread prints (ready PID) and
;; awaits the call, under a Ctrl-C handler that escapes from outside the
;; group. The await's turn reaches the due submit about 200 ms later and
;; blocks there, inside its critical section;
;; the suite sends SIGINT 500 ms after ready, so the handler escapes as the
;; section ends, once the submit has taken the mutex. With the submit and
;; its record in one section, the group's winds cancel the retry; without,
;; the escape lands between them, and the stalled retry runs on,
;; unrecorded. A collection asked for before the holder starts leaves none
;; due in the window (child-hold).
;;
;; Its second argument is its mode: escape, as above; or raise, where the
;; handler raises a &curl-error of its own making instead, caught outside
;; the group: the guard that makes a raise inside the section its call's
;; failure sits inside the section, where no handler runs, so the raise
;; leaves the await as raised, that very object, and the group's winds
;; cancel the retry; a guard outside the section would read it as the
;; call's failure. HOW is then (raise SAME COMPOUNDED): whether what left
;; the group is that object, and whether it carries an &http-exchange.
;;
;; Prints (turn HOW WHEN QUIET HOLDS PHASE), QUIET as child-hold reads it,
;; HOLDS the engine's live and queued counts and the transfer count 500 ms
;; after the holder let go, once the engine's queue has settled, for up to 2
;; s more: a token the winds cancelled while it was still queued is
;; completed on this thread, and its submit stays in the engine's queue
;; until the engine's next turn, which a poll of up to 1000 ms can put off.
;; Then (counts COUNTS), once the session is closed.
(define turn-child
  `((import (chezscheme) (curl) (http-client)
            (only (http-client private call) http-session-engine)
            (only (http-client private drive) http-pending-phase)
            (only (curl private engine) call-with-engine-held curl-engine-live-count
                  curl-engine-queued-count)
            (only (curl private conditions) make-curl-engine-error)
            (curl private counters))
    ,@child-hold
    (define url (car (command-line-arguments)))
    (define mode (string->symbol (cadr (command-line-arguments))))
    (define planted (condition (make-curl-engine-error 'stopped #f)
                               (make-message-condition "planted by the child's Ctrl-C handler")))
    (define (pause-ms ms) (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))
    (define session (make-http-session 'timeout-ms 30000))
    (define engine (http-session-engine session))
    (define lock (make-mutex))
    (define holding #f)
    (define letting-go #f)
    (define released #f)
    (define (flag get) (critical-section (with-mutex lock (get))))
    (define when-escaped #f)
    (define pending #f)
    (define how
      (call/cc
       (lambda (out)
        (guard (e (#t (list 'raise (eq? e planted) (and (condition? e) (http-exchange? e)))))
         (call-with-request-group session
           (lambda (go)
             (set! pending (go 'get url 'retry (make-http-retry 'backoff-ms 1000 'jitter #f)))
             (let wait ((n 0))
               (unless (or (eq? (http-pending-phase pending) 'waiting) (> n 500))
                 (http-pending-done? pending)
                 (pause-ms 10)
                 (wait (+ n 1))))
             (pause-ms 800)
             (collect-rendezvous)
             (fork-thread
              (lambda ()
                (call-with-engine-held engine
                  (lambda ()
                    (critical-section (with-mutex lock (set! held-collections (collections)) (set! holding #t)))
                    (until-sent)
                    (critical-section (with-mutex lock (set! letting-go #t)))))
                (critical-section (with-mutex lock (set! released #t)))))
             (let spin ()
               (unless (flag (lambda () holding))
                 (sleep (make-time 'time-duration 1000000 0))
                 (spin)))
             (keyboard-interrupt-handler
              (lambda ()
                (set! handler-collections (collections))
                (set! when-escaped (if (flag (lambda () letting-go)) 'after-release 'before-release))
                (if (eq? mode 'raise) (raise planted) (out 'escaped))))
             (write (list 'ready (get-process-id)))
             (newline)
             (flush-output-port (current-output-port))
             (http-await pending)
             'returned))))))
    (keyboard-interrupt-handler void)
    (let spin ()
      (unless (flag (lambda () released))
        (sleep (make-time 'time-duration 1000000 0))
        (spin)))
    (pause-ms 500)
    (let settle ((n 0))
      (unless (or (= (curl-engine-queued-count engine) 0) (> n 200))
        (pause-ms 10)
        (settle (+ n 1))))
    (define holds
      (let* ((live (curl-engine-live-count engine))
             (queued (curl-engine-queued-count engine)))
        (list live queued (cdr (assq 'transfer (native-counts))))))
    (write (list 'turn how when-escaped (quiet) holds (http-pending-phase pending)))
    (newline)
    (http-session-close session)
    (write (list 'counts (native-counts)))
    (newline)))

;; sections-child : (Listof Datum)
;; A program, from the slice's second review: http-parallel's admissions,
;; one critical section a call, watched by a pending keyboard interrupt,
;; which runs as the section it was made in ends (traps.md). BASE, its
;; first argument, is the raw face. Another thread holds the session's
;; engine's mutex until the suite has sent its SIGINT (child-hold); this
;; thread prints ready, then calls http-parallel with three 1 s holds. The
;; checks take no engine's mutex, so the first admission's submit is the
;; first to, and blocks there, inside its section; the suite sends SIGINT
;; meanwhile. The handler does
;; not escape: it closes the session, so every submit after it is refused
;; as stopped, in its own section, its call a failure with no transfer,
;; before any turn. With a section an admission, it runs as the first
;; ends: the first failure is the second call's, refused, with no
;; transfer. With every call in one section, it runs after the third, each
;; token ends stopped, and a turn's look finds them in submit order: the
;; first failure is the first call's, with its transfer counted.
;;
;; Prints (sections QUIET RAISED), QUIET as child-hold reads it, RAISED
;; (raised REASON URL TRANSFERS), then (counts COUNTS).
(define sections-child
  `((import (chezscheme) (curl) (http-client)
            (only (http-client private call) http-session-engine)
            (only (curl private engine) call-with-engine-held)
            (curl private counters))
    ,@child-hold
    (define base (car (command-line-arguments)))
    (define (hold i) (string-append base "/raw/hold?key=sections-" (number->string i) "&ms=1000"))
    (define session (make-http-session 'timeout-ms 30000))
    (define engine (http-session-engine session))
    (define lock (make-mutex))
    (define holding #f)
    (define (flag get) (critical-section (with-mutex lock (get))))
    (collect-rendezvous)
    (fork-thread
     (lambda ()
       (call-with-engine-held engine
         (lambda ()
           (critical-section (with-mutex lock (set! held-collections (collections)) (set! holding #t)))
           (until-sent)))))
    (let spin ()
      (unless (flag (lambda () holding))
        (sleep (make-time 'time-duration 1000000 0))
        (spin)))
    (keyboard-interrupt-handler
     (lambda () (set! handler-collections (collections)) (http-session-close session)))
    (write (list 'ready (get-process-id)))
    (newline)
    (flush-output-port (current-output-port))
    (define raised
      (guard (e ((and (condition? e) (http-exchange? e))
                 (list 'raised (and (curl-engine-error? e) (curl-engine-error-reason e))
                       (http-exchange-url e) (http-exchange-transfers e)))
                (#t (list 'raised-other (condition? e))))
        (map http-response-status
             (http-parallel session (list (list 'get (hold 0)) (list 'get (hold 1)) (list 'get (hold 2)))))))
    (keyboard-interrupt-handler void)
    (write (list 'sections (quiet) raised))
    (newline)
    (http-session-close session)
    (write (list 'counts (native-counts)))
    (newline)))

;; admissions-child : (Listof Datum)
;; The same for a turn's admissions, each a section of its own (the slice's
;; second review). BASE, its first argument, is the raw face. At a limit
;; of 2, two calls are put in retry waits of 5 s, holding both slots, and
;; two more queued behind them. Another thread then holds the engine's mutex
;; until the suite has sent its SIGINT (child-hold); this thread prints
;; ready, cancels the two waiting calls, which frees their slots and takes
;; no engine's mutex, and runs a turn, by http-pending-done?. The turn has
;; no live token to look at, so its
;; first admission's submit is its first hold of the engine's mutex, and
;; blocks there, inside its section; SIGINT arrives meanwhile, and its
;; handler closes the session. With a section an admission, it runs as the
;; first ends: the second queued call's submit is refused, stopped, with no
;; transfer, an engine's refusal. With the admissions in one section, it
;; runs after both were submitted, and the second's token ends stopped, a
;; transfer's own failure, its transfer counted, as the first's always is.
;;
;; Prints (admissions QUIET FIRST SECOND), QUIET as child-hold reads it,
;; each ((KIND REASON) TRANSFERS) of what its await raised, KIND engine for
;; a &curl-engine-error, transfer for a &curl-transfer-error, then (counts
;; COUNTS).
(define admissions-child
  `((import (chezscheme) (curl) (http-client)
            (only (http-client private call) http-session-engine)
            (only (http-client private drive) http-pending-phase)
            (only (curl private engine) call-with-engine-held)
            (curl private counters))
    ,@child-hold
    (define base (car (command-line-arguments)))
    (define (url path) (string-append base path))
    (define session (make-http-session 'timeout-ms 30000))
    (define engine (http-session-engine session))
    (define lock (make-mutex))
    (define holding #f)
    (define (flag get) (critical-section (with-mutex lock (get))))
    (define (raised p)
      (guard (e ((and (condition? e) (http-exchange? e))
                 (list (cond ((curl-engine-error? e) (list 'engine (curl-engine-error-reason e)))
                             ((curl-transfer-error? e) (list 'transfer (curl-transfer-error-reason e)))
                             (else 'other))
                       (http-exchange-transfers e)))
                (#t (list 'other (condition? e))))
        (http-await p)
        'no-raise))
    (define outcome
      (call-with-request-group session 'limit 2
        (lambda (go)
          (let* ((retry (make-http-retry 'backoff-ms 5000 'jitter #f))
                 (c1 (go 'get (url "/raw/retry?key=admissions-c1&fail=1&how=close") 'retry retry))
                 (c2 (go 'get (url "/raw/retry?key=admissions-c2&fail=1&how=close") 'retry retry))
                 (b1 (go 'get (url "/raw/hold?key=admissions-b1&ms=1000")))
                 (b2 (go 'get (url "/raw/hold?key=admissions-b2&ms=1000"))))
            (let wait ((n 0))
              (unless (or (and (eq? (http-pending-phase c1) 'waiting) (eq? (http-pending-phase c2) 'waiting))
                          (> n 500))
                (http-pending-done? c1)
                (sleep (make-time 'time-duration 10000000 0))
                (wait (+ n 1))))
            (collect-rendezvous)
            (fork-thread
             (lambda ()
               (call-with-engine-held engine
                 (lambda ()
                   (critical-section (with-mutex lock (set! held-collections (collections)) (set! holding #t)))
                   (until-sent)))))
            (let spin ()
              (unless (flag (lambda () holding))
                (sleep (make-time 'time-duration 1000000 0))
                (spin)))
            (keyboard-interrupt-handler
             (lambda () (set! handler-collections (collections)) (http-session-close session)))
            (write (list 'ready (get-process-id)))
            (newline)
            (flush-output-port (current-output-port))
            (http-pending-cancel c1)
            (http-pending-cancel c2)
            (http-pending-done? b1)
            (keyboard-interrupt-handler void)
            (list (raised b1) (raised b2))))))
    (write (cons* 'admissions (quiet) outcome))
    (newline)
    (http-session-close session)
    (write (list 'counts (native-counts)))
    (newline)))

;; resume-child : (Listof Datum)
;; A program: a group suspended at a chosen place and resumed, as a Chez
;; engine's expiry and resume do, but placed where a timer cannot be: a
;; keyboard interrupt made pending inside a section runs as it ends
;; (traps.md). BASE, its first argument, is the raw face; CASE, its second,
;; the case. Another thread holds a mutex, the gate, inside a critical
;; section, until the suite has sent its SIGINT (child-hold); this thread
;; prints (ready PID) and runs the case, whose seam blocks on the gate
;; inside a section of the group's; SIGINT arrives meanwhile, and its
;; handler, run as the section ends, captures
;; its continuation and escapes out of the group: the winds run, closing
;; the group, cancelling every call and waiting for each transfer to end.
;; The program then re-enters the continuation, once: the run resumes
;; where the handler ran, outside the section.
;;   P1: http-parallel's run of four 200s, the gate at call 1's submit, so
;;       the suspension comes after call 1's admission: resumed, it enters
;;       no call more, and raises call 0's cancel, the first not done in
;;       SPECS' order, not call 1's, the last entered.
;;   P3: a 200 and two 3 s holds, the gate at the first draw, in the step
;;       of call 0's 200, so the suspension comes after the first step:
;;       call 0 done, it raises call 1's cancel, not call 2's.
;;   G:  a group's go of a 3 s hold, the gate at its admission's submit,
;;       so the suspension comes in go's admissions, after its entry:
;;       resumed, go answers its pending, whose await raises cancelled;
;;       a go after it raises closed.
;;
;; Prints (resume CASE QUIET RESULT SUBMITS SUSPENSIONS STARTED-AFTER
;; SUBMITS-AFTER): QUIET as child-hold reads it at the first suspension;
;; RESULT (raised REASON WHO INDEX), INDEX the URL's in the case's list, or
;; (value ...); SUBMITS, the submits made before the suspension; the
;; transfers started and submits made after it. Then (counts COUNTS), once
;; the session is closed.
(define resume-child
  `((import (chezscheme) (curl) (http-client)
            (only (http-client private call) http-session-engine call-request)
            (only (http-client private drive) call-with-group run-parallel monotonic-ns)
            (only (http-client private exchange) make-exchange)
            (only (curl private transfer) transfers-started)
            (curl private counters))
    ,@child-hold
    (define base (car (command-line-arguments)))
    (define which (string->symbol (cadr (command-line-arguments))))
    (define (ok k) (string-append base "/raw/retry?key=resume-" k "&fail=0&how=close"))
    (define (hold k) (string-append base "/raw/hold?key=resume-" k "&ms=3000"))
    (define session (make-http-session 'timeout-ms 30000))
    (define engine (http-session-engine session))
    (define (prepare method url plist)
      (let-values (((request redirects allow-downgrade retry) (call-request session method url plist)))
        (make-exchange method url request (curl-request-timeout-ms request)
                       (monotonic-ns) redirects allow-downgrade retry)))
    (define lock (make-mutex))
    (define gate (make-mutex))
    (define holding #f)
    (define (flag get) (critical-section (with-mutex lock (get))))
    (define blocked #f)
    (define (block!)
      (unless blocked
        (set! blocked #t)
        (with-mutex gate #t)))
    (define submits 0)
    (define (submit-blocking-on url)
      (lambda (engine request mailbox)
        (set! submits (+ submits 1))
        (when (equal? (curl-request-url request) url) (block!))
        (curl-submit engine request mailbox)))
    (define urls
      (case which
        ((P1) (list (ok "a0") (ok "a1") (ok "a2") (ok "a3")))
        ((P3) (list (ok "c0") (hold "c1") (hold "c2")))
        (else (list (hold "g0") (hold "g1")))))
    (define (index-of u)
      (let loop ((i 0) (us urls))
        (cond ((null? us) #f) ((equal? (car us) u) i) (else (loop (+ i 1) (cdr us))))))
    (define (shown e)
      (if (condition? e)
          (list (and (http-group-error? e) (http-group-error-reason e))
                (and (who-condition? e) (condition-who e))
                (and (http-exchange? e) (index-of (http-exchange-url e))))
          (list 'non-condition e)))
    (define (run)
      (case which
        ((P1) (map http-response-status
                   (run-parallel engine #f (lambda () 0.5)
                                 (map (lambda (u) (prepare 'get u '())) urls)
                                 (submit-blocking-on (list-ref urls 1)))))
        ((P3) (map http-response-status
                   (run-parallel engine #f (lambda () (block!) 0.5)
                                 (map (lambda (u) (prepare 'get u '())) urls)
                                 (submit-blocking-on #f))))
        (else
         (call-with-group engine #f (lambda () 0.5) prepare
           (lambda (go)
             (let* ((p0 (go 'get (car urls)))
                    (r0 (guard (e (#t (shown e))) (http-await p0) 'answered))
                    (r1 (guard (e (#t (shown e))) (go 'get (cadr urls)) 'answered-a-pending)))
               (list (http-pending? p0) r0 r1)))
           (submit-blocking-on (car urls))))))
    (collect-rendezvous)
    (fork-thread
     (lambda ()
       (critical-section
        (with-mutex gate
          (critical-section (with-mutex lock (set! held-collections (collections)) (set! holding #t)))
          (until-sent)))))
    (let spin ()
      (unless (flag (lambda () holding))
        (sleep (make-time 'time-duration 1000000 0))
        (spin)))
    (define escape-k #f)
    (define suspended #f)
    (define suspensions 0)
    (define at #f)
    (define submits-at #f)
    (keyboard-interrupt-handler
     (lambda ()
       (unless handler-collections (set! handler-collections (collections)))
       (set! suspensions (+ suspensions 1))
       (call/cc (lambda (k) (set! suspended k) (escape-k 'suspended)))))
    (write (list 'ready (get-process-id)))
    (newline)
    (flush-output-port (current-output-port))
    (define result
      (let ((r (call/cc
                (lambda (k)
                  (set! escape-k k)
                  (guard (e (#t (cons 'raised (shown e))))
                    (list 'value (run)))))))
        (if (and (eq? r 'suspended) (= suspensions 1))
            (begin
              (set! at (transfers-started))
              (set! submits-at submits)
              (suspended #f))
            r)))
    (keyboard-interrupt-handler void)
    (write (list 'resume which (quiet) result submits-at suspensions
                 (and at (- (transfers-started) at)) (and submits-at (- submits submits-at))))
    (newline)
    (http-session-close session)
    (write (list 'counts (native-counts)))
    (newline)))

;; --- the condition and the keys ---------------------------------------------------------

(test-equal "http-group-error-reasons, written out"
  '(wrong-thread closed cancelled)
  http-group-error-reasons)

(test-equal "&http-group-error is under &http-error, &curl-error and &error, each reason made; a reason it does not know is an assertion violation from make-http-group-error"
  (list '((#t #t #t #t wrong-thread) (#t #t #t #t closed) (#t #t #t #t cancelled))
        '(raised (assertion make-http-group-error)))
  (list (in-order (lambda (reason)
                    (let ((c (make-http-group-error reason)))
                      (list (error? c) (curl-error? c) (http-error? c) (http-group-error? c)
                            (http-group-error-reason c))))
                  '(wrong-thread closed cancelled))
        (outcome (lambda () (make-http-group-error 'canceled)))))

;; Before any session is made here: no engine runs.

(test-equal "call-with-request-group refuses its keys by name and its limit by value, as &http-request-error from call-with-request-group, before its procedure is called: an unknown key, a repeated one, one with no value; a limit of 0, -1, 2.0, 1/2, a symbol, a string; #f and 1 are taken"
  (list '(raised (http-error) (http-request-error key limits unknown-key call-with-request-group))
        '(raised (http-error) (http-request-error key limit repeated-key call-with-request-group))
        '(raised (http-error) (http-request-error key limit missing-value call-with-request-group))
        '(raised (http-error) (http-request-error limit 0 not-a-limit call-with-request-group))
        '(raised (http-error) (http-request-error limit -1 not-a-limit call-with-request-group))
        '(raised (http-error) (http-request-error limit 2.0 not-a-limit call-with-request-group))
        '(raised (http-error) (http-request-error limit 1/2 not-a-limit call-with-request-group))
        '(raised (http-error) (http-request-error limit two not-a-limit call-with-request-group))
        '(raised (http-error) (http-request-error limit (kind string) not-a-limit call-with-request-group))
        '(returned called) '(returned called)
        0)
  (with-session '()
    (lambda (s)
      (let* ((called 0)
             (proc (lambda (go) (set! called (+ called 1)) 'called))
             (rows (in-order (lambda (plist)
                               (outcome (lambda () (apply call-with-request-group s
                                                          (append plist (list proc))))))
                             '((limits 2) (limit 2 limit 3) (limit) (limit 0) (limit -1) (limit 2.0)
                               (limit 1/2) (limit two) (limit "2")))))
        ;; let*: a count read as an argument beside the calls that move it
        ;; would be read in no fixed order (traps.md).
        (let* ((taken-false (outcome (lambda () (call-with-request-group s 'limit #f proc))))
               (taken-one (outcome (lambda () (call-with-request-group s 'limit 1 proc))))
               (extra (- called 2)))
          (append rows (list taken-false taken-one extra)))))))

(test-equal "call-with-request-group refuses its arguments as assertion violations from call-with-request-group: none, a session alone, something no session, a last argument no procedure"
  '((raised (assertion call-with-request-group)) (raised (assertion call-with-request-group))
    (raised (assertion call-with-request-group)) (raised (assertion call-with-request-group)))
  (with-session '()
    (lambda (s)
      (list (outcome (lambda () (call-with-request-group)))
            (outcome (lambda () (call-with-request-group s)))
            (outcome (lambda () (call-with-request-group 'session (lambda (go) 'x))))
            (outcome (lambda () (call-with-request-group s 'limit 2)))))))

(test-equal "http-parallel refuses its keys and its limit as call-with-request-group does, from http-parallel; SPECS that are no list, an improper list, a spec no list, a spec of one element, or an improper spec, as assertion violations from http-parallel; an empty SPECS answers ()"
  (list '(raised (http-error) (http-request-error key limits unknown-key http-parallel))
        '(raised (http-error) (http-request-error limit 0 not-a-limit http-parallel))
        '(raised (assertion http-parallel)) '(raised (assertion http-parallel))
        '(raised (assertion http-parallel)) '(raised (assertion http-parallel))
        '(raised (assertion http-parallel))
        '(returned ()))
  (with-session '()
    (lambda (s)
      (list (outcome (lambda () (http-parallel s '() 'limits 2)))
            (outcome (lambda () (http-parallel s '() 'limit 0)))
            (outcome (lambda () (http-parallel s 'specs)))
            (outcome (lambda () (http-parallel s (cons '(get "http://127.0.0.1:1/") 'tail))))
            (outcome (lambda () (http-parallel s '((get "http://127.0.0.1:1/") get))))
            (outcome (lambda () (http-parallel s '((get)))))
            (outcome (lambda () (http-parallel s (list (cons 'get "http://127.0.0.1:1/")))))
            (outcome (lambda () (http-parallel s '())))))))

;; --- critical sections ---------------------------------------------------------------------

(test-equal "inside a critical section, call-with-request-group and http-parallel refuse before anything else, assertion violations naming each, its procedure never called and no transfer made"
  (list '(raised (assertion call-with-request-group)) '(raised (assertion http-parallel)) 0 0)
  (with-session '()
    (lambda (s)
      (let* ((called 0)
             (started (transfers-started))
             (a (outcome (lambda () (critical-section
                                     (call-with-request-group s (lambda (go) (set! called 1) 'x))))))
             (b (outcome (lambda () (critical-section
                                     (http-parallel s '((get "http://127.0.0.1:1/x"))))))))
        (list a b called (- (transfers-started) started))))))

;; --- against the origin --------------------------------------------------------------------

;; environment-variables : (Listof String)
(define environment-variables
  '("http_proxy" "HTTP_PROXY" "https_proxy" "HTTPS_PROXY" "all_proxy" "ALL_PROXY"))

(test-equal "hermetic: none of the proxy variables is set"
  '()
  (filter (lambda (name) (getenv name)) environment-variables))

(call-with-origin
 (lambda (o)
   ;; url-of : Symbol String -> String
   (define (url-of face path)
     (guard (e (#t (string-append "http://no-" (symbol->string face) "-face" path)))
       (let ((f (origin-face o face)))
         (string-append "http://" (car f) ":" (number->string (cdr f)) path))))

   ;; hold-url : String Natural -> String
   (define (hold-url key ms)
     (url-of 'raw (string-append "/raw/hold?key=" key "&ms=" (number->string ms))))

   ;; retry-url : String Natural String -> String
   (define (retry-url key fail how)
     (url-of 'raw (string-append "/raw/retry?key=" key "&fail=" (number->string fail) "&how=" how)))

   ;; location-url : Natural Natural String -> String
   ;; The raw face's location script: CODE after MS ms, to TARGET.
   (define (location-url code ms target)
     (url-of 'raw (string-append "/raw/location?code=" (number->string code) "&ms="
                                 (number->string ms) "&to=" (pct target))))

   ;; read-body : String -> String
   ;; URL's body, on a session of its own.
   (define (read-body url)
     (guard (e (#t (list 'raised (described e))))
       (with-session '(timeout-ms 20000)
         (lambda (own) (latin-1 (http-response-body (http-get own url)))))))

   ;; most-of : String -> String
   (define (most-of key) (read-body (url-of 'raw (string-append "/raw/most?key=" key))))

   ;; attempts-of : String -> String
   (define (attempts-of key) (read-body (url-of 'raw (string-append "/raw/attempts?key=" key))))

   (define ok (url-of 'http "/status/200"))
   (define refused "http://127.0.0.1:1/refused")

   ;; --- critical sections, inside the group

   (test-equal "inside a critical section, in a group: http-await and http-pending-done? refuse, assertion violations naming each, the call untouched; go answers a pending and http-pending-cancel ends one, neither refusing"
     (list '(raised (assertion http-await)) '(raised (assertion http-pending-done?))
           '(#t live) '(cancelled ended)
           '(answered 200 "status 200\n"))
     (with-session '(timeout-ms 20000)
       (lambda (s)
         (call-with-request-group s
           (lambda (go)
             (let* ((p (go 'get ok))
                    (a (outcome (lambda () (critical-section (http-await p)))))
                    (b (outcome (lambda () (critical-section (http-pending-done? p)))))
                    (q (critical-section (go 'get ok)))
                    (q-state (list (http-pending? q) (http-pending-phase q)))
                    (cancelled (begin (critical-section (http-pending-cancel q))
                                      (list 'cancelled (http-pending-phase q))))
                    (r (guard (e (#t (list 'raised (described e))))
                         (let ((r (http-await p)))
                           (list 'answered (http-response-status r) (latin-1 (http-response-body r)))))))
               (list a b q-state cancelled r)))))))

   ;; --- go's checks

   (test-equal "go checks the call first, as http-request does: an unknown key, a method the low level refuses and a URL curl_url refuses each raise from go, compounded with &http-exchange and no transfer; no call is made, so the group holds the one valid call alone"
     (list (list 'raised '(http-error) '(http-request-error key bogus unknown-key http-request)
                 (list 'exchange 'get ok 0 0))
           (list 'raised '(assertion make-curl-request) (list 'exchange 'options ok 0 0))
           (list 'raised '(curl-url-error bad-port-number) (list 'exchange 'get "http://h:99999/" 0 0))
           1 1 '(answered 200 "status 200\n"))
     (with-session '(timeout-ms 20000)
       (lambda (s)
         (call-with-request-group s
           (lambda (go)
             (let* ((started (transfers-started))
                    (p (go 'get ok))
                    (a (outcome (lambda () (go 'get ok 'bogus 1))))
                    (b (outcome (lambda () (go 'options ok))))
                    (c (outcome (lambda () (go 'get "http://h:99999/"))))
                    (unended (cdr (assq 'unended (http-pending-census p))))
                    (r (guard (e (#t (list 'raised (described e))))
                         (let ((r (http-await p)))
                           (list 'answered (http-response-status r) (latin-1 (http-response-body r)))))))
               (list a b c unended (- (transfers-started) started) r)))))))

   ;; --- confinement

   (test-equal "a group is its thread's: go, http-await, http-pending-done? and http-pending-cancel from another thread each raise &http-group-error, wrong-thread, naming itself, its irritants the group's thread and the other, before anything else: go with a bad key, and a cancel of a live call, are not looked at; the call then answers"
     (list (list '(wrong-thread go) '(wrong-thread http-await) '(wrong-thread http-pending-done?)
                 '(wrong-thread http-pending-cancel) '(wrong-thread go))
           'irritants-name-both-threads
           '(live)
           '(answered 200 "held\n"))
     (with-session '(timeout-ms 20000)
       (lambda (s)
         (call-with-request-group s
           (lambda (go)
             (let* ((p (go 'get (hold-url "conf" 300)))
                    (here (get-thread-id))
                    (lock (make-mutex))
                    (found #f)
                    (got (lambda () (critical-section (with-mutex lock found)))))
               (fork-thread
                (lambda ()
                  (let* ((there (get-thread-id))
                         (try (lambda (thunk)
                                (guard (e ((http-group-error? e)
                                           (list (http-group-error-reason e) (condition-who e)
                                                 (condition-irritants e)))
                                          (#t (list 'other (described e))))
                                  (thunk)
                                  '(no-raise))))
                         (rows (in-order try
                                         (list (lambda () (go 'get ok))
                                               (lambda () (http-await p))
                                               (lambda () (http-pending-done? p))
                                               (lambda () (http-pending-cancel p))
                                               (lambda () (go 'get ok 'bogus 1))))))
                    (critical-section (with-mutex lock (set! found (cons there rows)))))))
               (let ((waited (poll-until 10000 (lambda () (got)))))
                 (let* ((result (got))
                        (rows (if (pair? result) (cdr result) (list waited)))
                        (phase (list (http-pending-phase p)))
                        (r (guard (e (#t (list 'raised (described e))))
                             (let ((r (http-await p)))
                               (list 'answered (http-response-status r) (latin-1 (http-response-body r)))))))
                   (list (map (lambda (row) (if (and (pair? row) (pair? (cdr row)))
                                                (list (car row) (cadr row))
                                                row))
                              rows)
                         (if (and (pair? result)
                                  (for-all (lambda (row)
                                             (and (= (length row) 3)
                                                  (equal? (caddr row) (list here (car result)))))
                                           rows)
                                  (not (eqv? here (car result))))
                             'irritants-name-both-threads
                             (list 'irritants here result))
                         phase r)))))))))

   (test-equal "go once the group's procedure has returned raises &http-group-error, closed, from go, before its checks; and so once the procedure has escaped"
     (list '(raised (http-error) (http-group-error closed go)) '(raised (http-error) (http-group-error closed go))
           '(raised (http-error) (http-group-error closed go)) 'escaped)
     (with-session '(timeout-ms 20000)
       (lambda (s)
         (let* ((kept (call-with-request-group s (lambda (go) go)))
                (escaped-go #f)
                (how (call/cc
                      (lambda (k)
                        (call-with-request-group s
                          (lambda (go) (set! escaped-go go) (k 'escaped)))))))
           (list (outcome (lambda () (kept 'get ok)))
                 (outcome (lambda () (kept 'get ok 'bogus 1)))
                 (outcome (lambda () (escaped-go 'get ok)))
                 how)))))

   ;; --- the join on a return

   (test-equal "the join on a return: a procedure that starts three holds of 500 ms and returns two values without awaiting gets both back only once all three have ended, the engine then holding nothing and no transfer counted; three held at once at the origin, and each call answers after the group has returned"
     (list '(a b) 'waited '(0 0 0) "held 0 most 3\n"
           (make-list 3 (list 'answered 200 (hold-url "join-ret" 500) "held\n" 0)))
     (with-session '(timeout-ms 20000)
       (lambda (s)
         (let* ((t0 (now-ms))
                (pendings '())
                (values-back (call-with-values
                               (lambda ()
                                 (call-with-request-group s
                                   (lambda (go)
                                     (for-each (lambda (i)
                                                 (set! pendings (cons (go 'get (hold-url "join-ret" 500))
                                                                      pendings)))
                                               '(1 2 3))
                                     (values 'a 'b))))
                               list))
                (took (- (now-ms) t0))
                (holds (engine-holds s))
                (most (most-of "join-ret"))
                (answers (in-order (lambda (p) (answer (lambda () (http-await p)))) (reverse pendings))))
           (list values-back (if (>= took 500) 'waited (list 'took took)) holds most answers)))))

   (test-equal "the join raises the first call to fail that no await answered, as the call raised it, the same object its await raises after: a refused connect before a 300 ms bound's &http-timeout; once the first is awaited, the second; once both are, the procedure's value"
     (list (list 'raised '(curl-transfer-error connect perform-failed 7) (list 'exchange 'get refused 0 1))
           'the-await-s-own
           (list 'raised '(http-error) '(http-timeout 300) '(curl-transfer-error timeout perform-failed 28)
                 (list 'exchange 'get (hold-url "join-fail" 3000) 0 1))
           '(returned done))
     (with-session '(timeout-ms 20000)
       (lambda (s)
         (let* ((first-p #f)
                (first-raised (guard (e (#t e))
                                (call-with-request-group s
                                  (lambda (go)
                                    (set! first-p (go 'get refused))
                                    (go 'get (hold-url "join-fail" 3000) 'timeout-ms 300)
                                    'done))))
                (same (guard (e ((eq? e first-raised) 'the-await-s-own)
                                (#t (list 'another (described e))))
                        (http-await first-p)
                        'no-raise))
                (second (outcome
                         (lambda ()
                           (call-with-request-group s
                             (lambda (go)
                               (let ((a (go 'get refused)))
                                 (go 'get (hold-url "join-fail" 3000) 'timeout-ms 300)
                                 (guard (e (#t 'caught)) (http-await a))
                                 'done))))))
                (both (outcome
                       (lambda ()
                         (call-with-request-group s
                           (lambda (go)
                             (let* ((a (go 'get refused))
                                    (b (go 'get (hold-url "join-fail" 3000) 'timeout-ms 300)))
                               (guard (e (#t 'caught)) (http-await a))
                               (guard (e (#t 'caught)) (http-await b))
                               'done)))))))
           (list (cons 'raised (described first-raised)) same second both)))))

   ;; Both refused connects end within a few ms; the procedure sleeps 300 ms
   ;; with no turn, so the join's first look finds both done, and steps
   ;; them oldest submit first.
   (test-equal "two failures found in one look are numbered in the order their calls were submitted: the join raises the first submitted's"
     (list 'raised '(curl-transfer-error connect perform-failed 7)
           (list 'exchange 'get "http://127.0.0.1:1/first" 0 1))
     (with-session '(timeout-ms 20000)
       (lambda (s)
         (outcome (lambda ()
                    (call-with-request-group s
                      (lambda (go)
                        (go 'get "http://127.0.0.1:1/first")
                        (go 'get "http://127.0.0.1:1/second")
                        (pause-ms 300)
                        'done)))))))

   ;; --- a raise inside a call's own section

   ;; Through the private call-with-group, with the session's engine, a
   ;; prepare of the call's state as http-request makes it but uncompounded,
   ;; and a draw and a submit that each raise once, where the test plants
   ;; it: the draw in the look's step of one call, whose token is done
   ;; before any turn runs; the submit at one call's due retry, a symbol, and
   ;; at another call's admission, a condition. Each such call must end
   ;; failed with that raise, a condition compounded with its &http-exchange
   ;; and anything else as raised, and no other call is touched: a raise
   ;; that stranded its call, outside every set and holding its slot, hung
   ;; the join and every await (the slice's review, limbo-probe).
   (let* ((look-url (url-of 'http "/status/201"))
          (due-url (retry-url "strand-due" 1 "close"))
          (admit-url (url-of 'http "/status/202"))
          (planted-draw (condition (make-error) (make-message-condition "planted in the draw")))
          (planted-submit (condition (make-error) (make-message-condition "planted in a submit"))))
     (test-equal "a raise inside a call's own section is that call's failure alone: a draw that raises in the look's step, a submit that raises a symbol at a due retry and one that raises a condition at an admission each end their call failed with it, a condition compounded with the call's &http-exchange, a symbol as raised; the group's other call answers its 200, the group holds nothing, and the join returns; the due retry never reached the origin"
       (list (list 'look 'the-planted-draw (list 'exchange 'get look-url 0 0))
             (list 'due 'planted-submit)
             (list 'admit 'the-planted-submit (list 'exchange 'get admit-url 0 0))
             '(other 200)
             '((unended . 0) (queued . 0) (waiting . 0) (live . 0) (draining . 0) (slots . 0) (failed . 3))
             '(returned joined)
             "attempts 1\n")
       (with-session '(timeout-ms 20000)
         (lambda (s)
           (let* ((prepare (lambda (method url plist)
                             (let-values (((request redirects allow-downgrade retry)
                                           (call-request s method url plist)))
                               (make-exchange method url request (curl-request-timeout-ms request)
                                              (monotonic-ns) redirects allow-downgrade retry))))
                  (draws 0)
                  (look-pending #f)
                  (draw (lambda ()
                          (set! draws (+ draws 1))
                          (if (and look-pending (= draws 1)) (raise planted-draw) 0.5)))
                  (due-submits 0)
                  (submit (lambda (engine request mailbox)
                            (let ((url (curl-request-url request)))
                              (cond ((string=? url admit-url) (raise planted-submit))
                                    ((string=? url due-url)
                                     (set! due-submits (+ due-submits 1))
                                     (if (= due-submits 2)
                                         (raise 'planted-submit)
                                         (curl-submit engine request mailbox)))
                                    (else (curl-submit engine request mailbox))))))
                  (fields (lambda (e)
                            (cond ((eq? e planted-draw) 'bare-draw)
                                  ((eq? e planted-submit) 'bare-submit)
                                  ((and (condition? e) (http-exchange? e) (message-condition? e)
                                        (equal? (condition-message e) "planted in the draw"))
                                   (list 'the-planted-draw (list 'exchange (http-exchange-method e) (http-exchange-url e)
                                                                 (length (http-exchange-history e))
                                                                 (http-exchange-transfers e))))
                                  ((and (condition? e) (http-exchange? e) (message-condition? e)
                                        (equal? (condition-message e) "planted in a submit"))
                                   (list 'the-planted-submit (list 'exchange (http-exchange-method e) (http-exchange-url e)
                                                                   (length (http-exchange-history e))
                                                                   (http-exchange-transfers e))))
                                  (else (list 'other (described e))))))
                  (rows #f)
                  (joined
                   (outcome
                    (lambda ()
                      (call-with-group (http-session-engine s) #f draw prepare
                        (lambda (go)
                          (let* ((look (go 'get look-url))
                                 (done (curl-token-wait (http-pending-token look) 5000))
                                 (armed (set! look-pending look))
                                 (look-raised (guard (e (#t (fields e))) (http-await look) 'no-raise))
                                 (due (go 'get due-url 'retry (make-http-retry 'backoff-ms 100 'jitter #f)))
                                 (due-raised (guard (e ((eq? e 'planted-submit) 'planted-submit)
                                                       (#t (list 'other (described e))))
                                               (http-await due)
                                               'no-raise))
                                 (admit (go 'get admit-url))
                                 (admit-raised (guard (e (#t (fields e))) (http-await admit) 'no-raise))
                                 (other (go 'get ok))
                                 (other-status (guard (e (#t (list 'raised (described e))))
                                                 (http-response-status (http-await other))))
                                 (census (http-pending-census other)))
                            (set! rows (list (cons 'look (if (pair? look-raised) look-raised (list look-raised)))
                                             (list 'due due-raised)
                                             (cons 'admit (if (pair? admit-raised) admit-raised (list admit-raised)))
                                             (list 'other other-status)
                                             census))
                            'joined))
                        submit)))))
             (append (or rows (list 'no-rows)) (list joined (attempts-of "strand-due"))))))))

   ;; --- the join on a raise

      ;; Four live holds of 5 s, a call in a retry's wait of 5 s, and a sixth
   ;; queued behind them at a limit of 5: the procedure raises once the
   ;; fifth is waiting. The engine's counts are read as the raise arrives,
   ;; with no wait: the group's outer wind must have waited for each
   ;; cancelled transfer to end. Four live ones give the engine work to do
   ;; after the cancels are sent, so a group that did not wait is seen
   ;; holding them.
   (let ((live (list 'raised '(http-error) '(http-group-error cancelled http-await)
                     '(curl-transfer-error other cancelled #f)
                     (list 'exchange 'get (hold-url "raise-live" 5000) 0 0))))
     (test-equal "the join on a raise, three times: four live holds, a call in a retry's wait and a queued one, at a limit of 5, are each ended as cancelled once the procedure raises, the raise leaving within 2 s where the holds run 5; the engine holds nothing and no transfer is counted as it arrives; each await then raises cancelled, the live ones compounded with their transfer's cancel; the waiting call was never resent, and the queued one never sent"
       (map (lambda (run)
              (list 'boom 'promptly '(0 0 0)
                    (list live live live live
                          (list 'raised '(http-error) '(http-group-error cancelled http-await)
                                (list 'exchange 'get (retry-url (string-append "raise-wait-" run) 1 "close") 0 1))
                          (list 'raised '(http-error) '(http-group-error cancelled http-await)
                                (list 'exchange 'get (hold-url "raise-queued" 100) 0 0)))
                    "attempts 1\n" "held 0 most 0\n"))
            '("1" "2" "3"))
       (in-order
        (lambda (run)
         (with-session (list 'timeout-ms 20000)
         (lambda (s)
           (let* ((pendings '())
                  (t0 #f)
                  (raised (guard (e ((eq? e 'boom) 'boom) (#t (list 'other (described e))))
                            (call-with-request-group s 'limit 5
                              (lambda (go)
                                (let* ((holds (let loop ((i 0) (made '()))
                                                (if (= i 4)
                                                    (reverse made)
                                                    (loop (+ i 1)
                                                          (cons (go 'get (hold-url "raise-live" 5000)) made)))))
                                       (c (go 'get (retry-url (string-append "raise-wait-" run) 1 "close")
                                              'retry (make-http-retry 'backoff-ms 5000 'jitter #f)))
                                       (d (go 'get (hold-url "raise-queued" 100))))
                                  (set! pendings (append holds (list c d)))
                                  (poll-until 5000 (lambda ()
                                                     (http-pending-done? c)
                                                     (eq? (http-pending-phase c) 'waiting)))
                                  (pause-ms 200)
                                  (set! t0 (now-ms))
                                  (raise 'boom))))))
                  (holds (engine-holds s))
                  (took (and t0 (- (now-ms) t0)))
                  (awaits (in-order (lambda (p) (outcome (lambda () (http-await p)))) pendings)))
             (list raised (if (and took (< took 2000)) 'promptly (list 'took took)) holds awaits
                   (attempts-of (string-append "raise-wait-" run)) (most-of "raise-queued"))))))
        '("1" "2" "3"))))

   ;; A second escape, landing as the first unwinds: swept over its ticks,
   ;; 1 to 40, one at a time. Measured (.plans/research/m5/group/sweep/): with
   ;; the inner wind critical, ticks 1 to 3 land before its after thunk, the
   ;; call still live, and 4 on are held off past it, the call ended by its
   ;; cancel; with it plain, ticks 20 and 21 landed inside it, before the
   ;; cancel, and the transfer ran on. Both kinds seen, before then after,
   ;; are the sweep's evidence that it crossed the after thunk.
   (test-equal "a second escape that lands as a group's first unwinds, at each of ticks 1 to 40, still leaves no transfer live within 3 s: the inner wind's cancel cannot be skipped; the early ticks land before it, the call live, then the rest after it, the call ended"
     (list (map (lambda (ticks) (list ticks 'ended)) (iota-from 1 40)) 'before-then-after)
     (let ((rows (in-order (lambda (ticks) (escape-twice (url-of 'raw "/raw/pause-mid-body?ms=10000") ticks))
                           (iota-from 1 40))))
       (list (map (lambda (row) (list (car row) (caddr row))) rows)
             (before-then-after (map cadr rows)))))

   ;; An escape from the join's own wait, after the procedure has returned:
   ;; it starts a 10 s drip and returns without awaiting it, and a timer's
   ;; handler escapes 300 ms into the join. The group must still cancel the
   ;; call and wait for it to end, so the escape leaves at once and the
   ;; engine then holds nothing; a group that skipped the cancel once closed
   ;; waited out the drip in its outer wind, 9.7 s (the review's probe).
   (test-equal "an escape from the join's own wait, 300 ms after the procedure returned with a 10 s drip live, still cancels the call and ends it: the escape leaves within 2 s, the engine then holding nothing"
     (list 'escaped 'promptly '(0 0 0))
     (with-session '(timeout-ms 30000)
       (lambda (s)
         (let* ((t0 #f)
                (joined #f)
                (previous (timer-interrupt-handler))
                (left #f)
                (how (call/cc
                      (lambda (k)
                        (timer-interrupt-handler
                         (lambda ()
                           (if (and joined (> (- (now-ms) joined) 300))
                               (begin (set! t0 (now-ms)) (k 'escaped))
                               (set-timer 2000))))
                        (set! left (set-timer 2000))
                        (call-with-request-group s
                          (lambda (go)
                            (go 'get (url-of 'raw "/raw/pause-mid-body?ms=10000"))
                            (set! joined (now-ms))
                            'returned)))))
                (took (and t0 (- (now-ms) t0)))
                (holds (engine-holds s)))
           (set-timer 0)
           (timer-interrupt-handler previous)
           (when (and left (> left 0)) (set-timer left))
           (list how (if (and took (< took 2000)) 'promptly (list 'took took)) holds)))))

   ;; --- a Chez engine's expiry, swept over its fuel

   ;; Fuel is ticks, not time, so Valgrind does not stretch it; but a Chez
   ;; build can move where a tick lands, so each assertion is an invariant
   ;; that holds wherever the expiry lands: in the calls' checks, in the
   ;; entries, between them, or in the run loop or the awaits (measured,
   ;; .plans/research/m5/group/engine/engine-sweep-probe.sps: on this build
   ;; the checks take up to about 4500 ticks for four calls). The expiry is an escape: it closes
   ;; the group and cancels its calls, and the engine, resumed, must start
   ;; no transfer after it, but for a group made only after it; each outcome
   ;; must be one the docs name; and nothing native is left. The review
   ;; found a resumed http-parallel entering calls into its closed group, and
   ;; reading their cancels as responses (the slice's second review).
   ;; The window between two entries is narrow, about 20 ticks for four
   ;; calls on this build (.plans/research/m5/group/traps/entry-window-probe.sps),
   ;; where a resumed run that entered calls into its closed group was
   ;; caught, so a coarse sweep can step over it; and the window inside the
   ;; group before its first entry, where the cancel raised is a never-
   ;; entered call's, is 3 ticks (.plans/research/m5/group/engine/
   ;; unentered-window.out), and moved between runs, so a sweep by 2 hit it
   ;; once or not at all; why it moves was not measured. The sweep
   ;; finds its own band: the first coarse fuel whose outcome is a cancel
   ;; lies just past the entries, wherever a build puts them, and a fine
   ;; sweep of every tick for 100 either side of it covers them.
   ;;
   ;; Each run is guarded: a raise out of it, its session's making or
   ;; closing among it, becomes a row of its own, a vector, which every
   ;; invariant rejects, so the suite names the sweep's test and goes on.
   ;; A run that hangs has no bound but make's timeout: the engine owns the
   ;; timer, so escape-after cannot bound it.
   (let* ((specs (lambda () (in-order (lambda (i) (list 'get (retry-url (string-append "eng-par-" (number->string i)) 0 "close")))
                                      '(0 1 2 3))))
          (run-at (lambda (fuel)
                    (guard (e (#t (vector 'sweep-raised (described e))))
                      (let* ((s (make-http-session 'timeout-ms 20000))
                             (r (guard (e (#t (vector 'sweep-raised (described e))))
                                  (engine-run fuel
                                              (lambda ()
                                                (guard (e (#t (if (and (condition? e) (http-group-error? e)
                                                                       (eq? (http-group-error-reason e) 'cancelled)
                                                                       (who-condition? e)
                                                                       (eq? (condition-who e) 'http-parallel))
                                                                  'unentered
                                                                  (expiry-class e))))
                                                  (let ((rs (http-parallel s (specs))))
                                                    (if (and (= (length rs) 4)
                                                             (for-all (lambda (r) (= (http-response-status r) 200)) rs))
                                                        'responses
                                                        (list 'odd-responses (map http-response-status rs))))))))))
                        (http-session-close s)
                        r))))
          (coarse (map (lambda (i) (* 100 i)) (iota-from 2 89)))
          (coarse-rows (in-order run-at coarse))
          (first-cancel (let loop ((fs coarse) (rs coarse-rows))
                          (cond ((null? fs) #f)
                                ((and (list? (car rs)) (eq? (cadr (car rs)) 'cancelled)) (car fs))
                                (else (loop (cdr fs) (cdr rs))))))
          (fine (if first-cancel
                    (map (lambda (i) (+ (- first-cancel 100) i)) (iota 201))
                    '()))
          (fine-rows (in-order run-at fine))
          (fuels (append coarse fine))
          (rows (append coarse-rows fine-rows)))
     ;; Four responses after an expiry mean the expiry landed before the
     ;; group, every transfer started after it, or after the last transfer
     ;; had started, none after it; anything else raises with none started
     ;; after it: its first call's cancel, or unentered, the cancel of a call
     ;; never entered, its group closed before its first entry. Never
     ;; (curl)'s refusal to re-enter a parse: each call's checks are one
     ;; critical section, which no expiry lands inside (ADR-0025, amended
     ;; 2026-11-05). A run that never expired answers its responses. No
     ;; call here can fail, so a failure is no outcome: none was seen from
     ;; 200 to 40000 ticks (the slice's third review).
     (test-equal "an engine's expiry anywhere in http-parallel, swept from 200 to 9000 ticks by 100, then by 1 for 100 ticks either side of its first cancel, across its entries: the outcome is all four responses, with every transfer started after the expiry, its group made after it, or none, or with no expiry; or the cancel of its first call or a never-entered call's cancel, with no transfer started after the expiry; never (curl)'s refusal to re-enter a URL's parse"
       '()
       (filter (lambda (row) row)
               (map (lambda (fuel row)
                      (and (not (or (equal? row '(#f responses #f))
                                    (and (list? row) (= (length row) 3)
                                         (let ((expired (car row)) (class (cadr row)) (after (caddr row)))
                                           (and (eq? expired #t)
                                                (if (eq? class 'responses)
                                                    (memv after '(0 4))
                                                    (and (memq class '(cancelled unentered)) (eqv? after 0))))))))
                           (list fuel row)))
                    fuels rows)))
     (test-equal "the http-parallel sweep's evidence: some expiry landed before its group, its four responses answered with all four transfers started after the expiry; some inside it before its first entry, a never-entered call's cancel raised; and some after an entry, its first call's cancel raised"
       '(#t #t #t)
       (list (and (exists (lambda (row) (equal? row '(#t responses 4))) rows) #t)
             (and (exists (lambda (row) (equal? row '(#t unentered 0))) rows) #t)
             (and (exists (lambda (row) (and (list? row) (eq? (cadr row) 'cancelled))) rows) #t))))

   ;; Each run is guarded, as the http-parallel sweep's is; a hang, too,
   ;; has no bound but make's timeout.
   (let* ((fuels (map (lambda (i) (* 100 i)) (iota-from 2 59)))
          (rows (in-order
                 (lambda (fuel)
                   (guard (e (#t (vector 'sweep-raised (described e))))
                     (let* ((s (make-http-session 'timeout-ms 20000))
                            (r (guard (e (#t (vector 'sweep-raised (described e))))
                                 (engine-run
                                  fuel
                                  (lambda ()
                                    (guard (e (#t (list 'group-raised (expiry-class e))))
                                      (call-with-request-group s
                                        (lambda (go)
                                          (let ((made (in-order (lambda (i)
                                                                  (guard (e (#t (expiry-class e)))
                                                                    (go 'get (retry-url (string-append "eng-go-" (number->string i)) 0 "close"))))
                                                                '(0 1 2 3))))
                                            (in-order (lambda (p)
                                                        (if (http-pending? p)
                                                            (guard (e (#t (expiry-class e)))
                                                              (if (= (http-response-status (http-await p)) 200) 'answered 'odd))
                                                            p))
                                                      made))))))))))
                       (http-session-close s)
                       r)))
                 fuels)))
     (test-equal "an engine's expiry anywhere in a group of four calls of go, swept from 200 to 6000 ticks by 100: each call answers, or raises cancelled or closed, never (curl)'s refusal to re-enter a URL's parse; and with any call not answered, no transfer starts after the expiry"
       '()
       (filter (lambda (row) row)
               (map (lambda (fuel row)
                      (let* ((shaped (and (list? row) (= (length row) 3)))
                             (expired (and shaped (car row)))
                             (calls (and shaped (cadr row)))
                             (after (and shaped (caddr row)))
                             (known (and shaped (list? calls) (= (length calls) 4)
                                         (for-all (lambda (c) (memq c '(answered cancelled closed))) calls))))
                        (and (not (and known
                                       (or (not expired) (for-all (lambda (c) (eq? c 'answered)) calls)
                                           (eqv? after 0))))
                             (list fuel row))))
                    fuels rows)))
     (test-equal "the go sweep's evidence: some expiry landed inside the group, a call's await raising cancelled, and some in a go's checks or before its entry, that go raising closed"
       '(#t #t)
       (let ((calls (apply append (map (lambda (row) (if (and (list? row) (list? (cadr row))) (cadr row) '())) rows))))
         (list (and (memq 'cancelled calls) #t) (and (memq 'closed calls) #t)))))

   ;; go's recheck after an engine's expiry, placed by engine-block in
   ;; PREPARE, outside every section of the group's, where a real expiry
   ;; can land: in or just after the call's checks, whose own critical
   ;; section an expiry that runs out in them lands after, before go's
   ;; entry (engine-block inside a section suspends there at once, the
   ;; slice's third review). The first go enters its call; the second's
   ;; checks block the engine, whose expiry closes the group and cancels
   ;; the first. Resumed, the second go asks again inside its entry's
   ;; section, and raises closed once that section has ended: a handler
   ;; installed around go by with-exception-handler runs with interrupts on,
   ;; disable-interrupts answering 1, and sees the recheck's message. A
   ;; hang here has no bound but make's timeout: the engine owns the timer.
   (test-equal "go's recheck, after an engine's expiry in or just after its checks, raises closed once its entry's section has ended: a handler around go runs with interrupts on and sees the recheck's message; the call entered before the expiry raises cancelled; no transfer starts after the expiry"
     (list #t
           (list (list 'handler #t 'closed 'go "the request group was closed while go checked the call: go starts no call")
                 '(cancelled http-await))
           0)
     (let* ((s (make-http-session 'timeout-ms 20000))
            (u0 (url-of 'raw "/raw/hold?key=recheck-0&ms=3000"))
            (u1 (url-of 'raw "/raw/hold?key=recheck-1&ms=3000"))
            (blocked #f)
            (prepare (lambda (method url plist)
                       (when (and (equal? url u1) (not blocked))
                         (set! blocked #t)
                         (engine-block))
                       (let-values (((request redirects allow-downgrade retry) (call-request s method url plist)))
                         (make-exchange method url request (curl-request-timeout-ms request)
                                        (monotonic-ns) redirects allow-downgrade retry))))
            (interrupts-on? (lambda () (let ((n (disable-interrupts))) (enable-interrupts) (= n 1))))
            (r (guard (e (#t (vector 'raised (described e))))
                 (engine-run
                  100000000
                  (lambda ()
                    (guard (e (#t (list 'group-raised (described e))))
                      (call-with-group (http-session-engine s) #f (lambda () 0.5) prepare
                        (lambda (go)
                          (let* ((p0 (go 'get u0))
                                 (seen (call/cc
                                        (lambda (k)
                                          (with-exception-handler
                                           (lambda (e)
                                             (k (list 'handler (interrupts-on?)
                                                      (and (http-group-error? e) (http-group-error-reason e))
                                                      (and (who-condition? e) (condition-who e))
                                                      (and (message-condition? e) (condition-message e)))))
                                           (lambda () (go 'get u1) 'answered-a-pending))))))
                            (list seen
                                  (guard (e (#t (if (http-group-error? e)
                                                    (list (http-group-error-reason e) (condition-who e))
                                                    (described e))))
                                    (http-await p0)
                                    'answered)))))))))))
       (http-session-close s)
       r))

   (test-equal "the counts are zero after the engine sweeps, every session closed"
     zero-counts
     (native-counts))

   ;; --- a refused submit's step, and a step's clocks, through the seams

   (let* ((prepare-in (lambda (s)
                        (lambda (method url plist)
                          (let-values (((request redirects allow-downgrade retry)
                                        (call-request s method url plist)))
                            (make-exchange method url request (curl-request-timeout-ms request)
                                           (monotonic-ns) redirects allow-downgrade retry))))))
     ;; A refusal is the core's (refused C), stepped, and a step draws once
     ;; whether a retry reads it or not; a group that let the refusal reach
     ;; the per-call guard instead would end the call with no step, no draw.
     (test-equal "a submit's refusal is stepped by the core, which draws once: a planted &curl-engine-error at an admission, its await raising it compounded with the call's &http-exchange, no transfer, one draw"
       (list 1 '(planted (exchange get 0 0)))
       (with-session '(timeout-ms 20000)
         (lambda (s)
           (let* ((url (retry-url "seam-refused" 0 "close"))
                  (draws 0)
                  (planted (condition (make-curl-engine-error 'stopped #f) (make-message-condition "planted refusal")))
                  (raised (call-with-group (http-session-engine s) #f
                            (lambda () (set! draws (+ draws 1)) 0.5)
                            (prepare-in s)
                            (lambda (go)
                              (let ((p (go 'get url)))
                                (guard (e ((and (condition? e) (curl-engine-error? e) (http-exchange? e))
                                           (list 'planted (list 'exchange (http-exchange-method e)
                                                                (length (http-exchange-history e))
                                                                (http-exchange-transfers e))))
                                          (#t (list 'other (described e))))
                                  (http-await p)
                                  'no-raise)))
                            (lambda (engine request mailbox)
                              (if (string=? (curl-request-url request) url)
                                  (raise planted)
                                  (curl-submit engine request mailbox))))))
             (list draws raised)))))

     ;; A step reads the draw, then the clocks, so a wait runs from the
     ;; draw's end: with a first draw of 300 ms and a retry 100 ms after the
     ;; step, the retry is submitted 100 ms after the draw ends; read the
     ;; monotonic clock first and the wait would run from before the draw,
     ;; and be over when the step ends.
     (test-equal "a step reads its clocks after its draw: a first draw of 300 ms, then a retry due 100 ms after the step, is submitted at least 50 ms after the draw ended, and answers"
       (list 'after-the-draw 200)
       (with-session '(timeout-ms 20000)
         (lambda (s)
           (let* ((url (retry-url "seam-clock" 1 "close"))
                  (draws 0)
                  (draw-ended #f)
                  (submits '())
                  (status (call-with-group (http-session-engine s) #f
                            (lambda ()
                              (set! draws (+ draws 1))
                              (when (= draws 1)
                                (pause-ms 300)
                                (set! draw-ended (now-ms)))
                              0.5)
                            (prepare-in s)
                            (lambda (go)
                              (let ((p (go 'get url 'retry (make-http-retry 'backoff-ms 100 'jitter #f))))
                                (guard (e (#t (list 'raised (described e))))
                                  (http-response-status (http-await p)))))
                            (lambda (engine request mailbox)
                              (set! submits (cons (now-ms) submits))
                              (curl-submit engine request mailbox)))))
             (list (if (and draw-ended (= (length submits) 2) (>= (- (car submits) draw-ended) 50))
                       'after-the-draw
                       (list 'gap (and draw-ended (pair? submits) (- (car submits) draw-ended)) 'submits (length submits)))
                   status)))))

     ;; The turn's admission, and run-parallel's admissions, each with a raise
     ;; planted through the submit seam. A queued call's expiry has a guard
     ;; too, which no seam reaches: it is held by reading alone.
     (test-equal "a raise planted at a turn's admission is that call's failure alone: at a limit of 1, a call let in as the first ends has its submit raise a symbol; its await raises that symbol, the first answers its 200, and the join returns"
       (list 200 'planted-turn '(returned joined))
       (with-session '(timeout-ms 20000)
         (lambda (s)
           (let* ((queued-url (url-of 'http "/status/203"))
                  (rows #f)
                  (joined
                   (outcome
                    (lambda ()
                      (call-with-group (http-session-engine s) 1 (lambda () 0.5) (prepare-in s)
                        (lambda (go)
                          (let* ((a (go 'get ok))
                                 (b (go 'get queued-url))
                                 (first (guard (e (#t (list 'raised (described e))))
                                          (http-response-status (http-await a))))
                                 (second (guard (e ((eq? e 'planted-turn) 'planted-turn)
                                                   (#t (list 'other (described e))))
                                           (http-await b)
                                           'no-raise)))
                            (set! rows (list first second))
                            'joined))
                        (lambda (engine request mailbox)
                          (if (string=? (curl-request-url request) queued-url)
                              (raise 'planted-turn)
                              (curl-submit engine request mailbox))))))))
             (append (or rows '(no-rows no-rows)) (list joined))))))

     (test-equal "a raise planted at one of run-parallel's admissions is that call's failure, raised as http-parallel's first: the planted condition compounded with the second call's &http-exchange, no transfer"
       (list 'the-planted (list 'exchange 'get (url-of 'http "/status/202") 0 0))
       (with-session '(timeout-ms 20000)
         (lambda (s)
           (let* ((prepare (prepare-in s))
                  (urls (list (url-of 'http "/status/201") (url-of 'http "/status/202") (url-of 'http "/status/203")))
                  (planted (condition (make-error) (make-message-condition "planted in an admission")))
                  (states (in-order (lambda (u) (prepare 'get u '())) urls)))
             (guard (e ((and (condition? e) (http-exchange? e) (message-condition? e)
                             (equal? (condition-message e) "planted in an admission"))
                        (list 'the-planted (list 'exchange (http-exchange-method e) (http-exchange-url e)
                                                 (length (http-exchange-history e)) (http-exchange-transfers e))))
                       (#t (list 'other (described e))))
               (run-parallel (http-session-engine s) #f (lambda () 0.5) states
                             (lambda (engine request mailbox)
                               (if (string=? (curl-request-url request) (cadr urls))
                                   (raise planted)
                                   (curl-submit engine request mailbox))))
               'no-raise)))))

     ;; A raise inside a section after its call has ended is no call's
     ;; failure. The planted submit cancels its own call, queued still,
     ;; which ends it, then raises: the guard must raise that again, out of
     ;; the turn, never drop it. The first call's token is waited for first,
     ;; so its await's first look steps it and that turn lets the second in.
     (test-equal "a raise inside a call's section after the call has ended is raised again, never dropped: a planted submit that cancels its own call, then raises, makes the await that ran the turn raise it; the cancelled call's await raises cancelled"
       (list 'raised-again '(raised (http-error) (http-group-error cancelled http-await)))
       (with-session '(timeout-ms 20000)
         (lambda (s)
           (let* ((queued-url (url-of 'http "/status/204"))
                  (b #f))
             (call-with-group (http-session-engine s) 1 (lambda () 0.5) (prepare-in s)
               (lambda (go)
                 (let* ((a (go 'get ok))
                        (queued (begin (set! b (go 'get queued-url)) b))
                        (done (curl-token-wait (http-pending-token a) 5000))
                        (first (guard (e ((eq? e 'after-ended) 'raised-again)
                                         (#t (list 'other (described e))))
                                 (http-await a)
                                 'no-raise))
                        (second (let ((o (outcome (lambda () (http-await b)))))
                                  (if (and (pair? o) (eq? (car o) 'raised))
                                      (list 'raised (car (cdr o)) (cadr (cdr o)))
                                      o))))
                   (list first second)))
               (lambda (engine request mailbox)
                 (if (string=? (curl-request-url request) queued-url)
                     (begin (http-pending-cancel b) (raise 'after-ended))
                     (curl-submit engine request mailbox)))))))))

   ;; --- each token stepped once

   (test-equal "an escape at the take, in a child: SIGINT's handler escapes from the await's take as its critical section ends, the token's notice, which the look had stepped first, taken out of the group's mailbox; caught inside the procedure, the call awaited again answers its 200; no collection ran in the hold; the child's counts zero"
     (list 0 (list 'lost 'escaped 'quiet 'taken '(answered 200 "status 200\n")) (list 'counts zero-counts) "")
     (let ((r (run-child lost-child ok)))
       (if (and (pair? r) (= (length r) 3) (list? (cadr r)) (= (length (cadr r)) 2))
           (list (car r) (car (cadr r)) (cadr (cadr r)) (caddr r))
           r)))

   ;; The notice taken out through the seam, as an escaping take would lose
   ;; it, while the call is unstepped: its token waited for with no turn,
   ;; then its notice taken from the group's mailbox here. The await must
   ;; find the token by the next turn's look; with no look it waits for
   ;; good, bounded here by 5 s.
   (test-equal "a lost notice, through the seam: a call's notice taken out of the group's mailbox before any turn stepped it, the call still live; its await finds the token by the next look, and raises its refused connect"
     (list #t #t 'live '(raised 7))
     (with-session '(timeout-ms 20000)
       (lambda (s)
         (call-with-request-group s
           (lambda (go)
             (let* ((p (go 'get refused))
                    (token (http-pending-token p))
                    (done (curl-token-wait token 5000))
                    (taken (eq? (curl-mailbox-take (http-pending-mailbox p) 1000) token))
                    (phase (http-pending-phase p))
                    (awaited (escape-after 5000
                                           (lambda ()
                                             (guard (e ((curl-transfer-error? e)
                                                        (list 'raised (curl-transfer-error-code e))))
                                               (http-await p)
                                               'no-raise)))))
               (list done taken phase awaited)))))))

   ;; The first look answers #f: the location script waits 300 ms. Then the
   ;; token is waited for, outside any turn, so the next turn's look finds
   ;; it done and steps it, submitting the redirect, and that turn's take
   ;; then finds its notice, late, and must drop it.
   (let ((url (location-url 302 300 "/raw/retry?key=late&fail=0&how=close")))
     (test-equal "a late notice: a token found done by a look after a take had answered #f is stepped once, its redirect's request counted once at the origin, though the turn's take then found its notice"
       (list #f #t '(#f live) (list 'answered 200 (retry-url "late" 0 "close") "attempt 1\n" 1)
             "attempts 1\n")
       (let ((r (guard (e (#t (list 'raised (described e))))
                  (with-session '(timeout-ms 20000)
                    (lambda (s)
                      (call-with-request-group s
                        (lambda (go)
                          (let* ((p (go 'get url))
                                 (first (http-pending-done? p))
                                 (ended (curl-token-wait (http-pending-token p) 5000))
                                 (second (http-pending-done? p))
                                 (phase (http-pending-phase p))
                                 (a (answer (lambda () (http-await p)))))
                            (list first ended (list second phase) a)))))))))
         (append (if (and (list? r) (= (length r) 4)) r (list r 'x 'x 'x))
                 (list (attempts-of "late"))))))

   ;; --- a submit and its record

   (test-equal "SIGINT while go's submit blocks on the engine's mutex inside its critical section escapes as the section ends, after the submit took the mutex, out of the group; its winds still cancel the transfer, so the engine holds nothing 500 ms after the release, where the drip runs 10 s; no collection ran in the hold; the child's counts zero"
     (list 0 '(submit escaped after-release quiet (0 0 0)) (list 'counts zero-counts) "")
     (let ((r (run-child submit-child (url-of 'raw "/raw/pause-mid-body?ms=10000"))))
       (if (and (pair? r) (= (length r) 3) (list? (cadr r)) (= (length (cadr r)) 2))
           (list (car r) (car (cadr r)) (cadr (cadr r)) (caddr r))
           r)))

   (test-equal "SIGINT while go's submit blocks on the engine's mutex, whose handler raises a &curl-error of its own, reaches the caller as raised, that very object, not compounded, as the section ends, after the submit took the mutex: no refusal of the submit's; the group's winds still cancel the transfer, so the engine holds nothing 500 ms after the release; no collection ran in the hold; the child's counts zero"
     (list 0 '(raise #t #f after-release quiet (0 0 0)) (list 'counts zero-counts) "")
     (let ((r (run-child raise-child (url-of 'raw "/raw/pause-mid-body?ms=10000"))))
       (if (and (pair? r) (= (length r) 3) (list? (cadr r)) (= (length (cadr r)) 2))
           (list (car r) (car (cadr r)) (cadr (cadr r)) (caddr r))
           r)))

   (test-equal "SIGINT while a turn's due submit, a call's retry, blocks on the engine's mutex inside its critical section escapes as the section ends, after the submit took the mutex, out of the group; the retry is recorded with its submit, so the group's winds cancel it and the engine holds nothing 500 ms after the release, the call ended; no collection ran in the hold; the child's counts zero"
     (list 0 '(turn escaped after-release quiet (0 0 0) ended) (list 'counts zero-counts) "")
     (let ((r (run-child turn-child (url-of 'raw "/raw/retry?key=turn-submit&fail=1&how=close&then=stall")
                         "escape")))
       (if (and (pair? r) (= (length r) 3) (list? (cadr r)) (= (length (cadr r)) 2))
           (list (car r) (car (cadr r)) (cadr (cadr r)) (caddr r))
           r)))

   (test-equal "SIGINT while a turn's due submit blocks on the engine's mutex, whose handler raises a &curl-error of its own, reaches the caller as raised, that very object, not compounded, as the section ends: the guard that makes a call's own raise its failure sits inside the section, and reads none of a handler's; the group's winds cancel the retry, the engine holding nothing, the call ended; no collection ran in the hold; the child's counts zero"
     (list 0 '(turn (raise #t #f) after-release quiet (0 0 0) ended) (list 'counts zero-counts) "")
     (let ((r (run-child turn-child (url-of 'raw "/raw/retry?key=turn-raise&fail=1&how=close&then=stall")
                         "raise")))
       (if (and (pair? r) (= (length r) 3) (list? (cadr r)) (= (length (cadr r)) 2))
           (list (car r) (car (cadr r)) (cadr (cadr r)) (caddr r))
           r)))

   (test-equal "http-parallel lets each call in in a critical section of its own: SIGINT while its first admission's submit blocks on the engine's mutex runs as that section ends, and its handler's close refuses the second call's submit, stopped, with no transfer, the first failure; no collection ran in the hold; the child's counts zero"
     (list 0 (list 'sections 'quiet (list 'raised 'stopped (url-of 'raw "/raw/hold?key=sections-1&ms=1000") 0))
           (list 'counts zero-counts) "")
     (let ((r (run-child sections-child (url-of 'raw ""))))
       (if (and (pair? r) (= (length r) 3) (list? (cadr r)) (= (length (cadr r)) 2))
           (list (car r) (car (cadr r)) (cadr (cadr r)) (caddr r))
           r)))

   (test-equal "a turn lets each queued call in in a critical section of its own: SIGINT while its first admission's submit blocks on the engine's mutex runs as that section ends, and its handler's close refuses the second admission's submit, stopped, with no transfer, where the first's token ends stopped, its transfer counted; no collection ran in the hold; the child's counts zero"
     (list 0 '(admissions quiet ((transfer stopped) 1) ((engine stopped) 0)) (list 'counts zero-counts) "")
     (let ((r (run-child admissions-child (url-of 'raw ""))))
       (if (and (pair? r) (= (length r) 3) (list? (cadr r)) (= (length (cadr r)) 2))
           (list (car r) (car (cadr r)) (cadr (cadr r)) (caddr r))
           r)))

   (for-each
    (lambda (which expected)
      (test-equal (string-append "a run suspended by an escape out of its group and resumed, as an engine's expiry and resume do, placed by SIGINT as a section ends, in a child, case " (symbol->string which) ": "
                                 (case which
                                   ((P1) "http-parallel suspended after call 1's admission raises call 0's cancel, the first in SPECS' order not done, enters no call more and submits nothing after")
                                   ((P3) "http-parallel suspended after its first step, call 0 done, raises call 1's cancel, the first not done, not call 2's")
                                   (else "go suspended in its admissions, after its entry, answers its pending, whose await raises cancelled; a go after it raises closed"))
                                 "; no transfer starts after the suspension, no collection ran in the hold, and the child's counts zero")
        (list 0 expected (list 'counts zero-counts) "")
        (let ((r (run-child resume-child (url-of 'raw "") (symbol->string which))))
          (if (and (pair? r) (= (length r) 3) (list? (cadr r)) (= (length (cadr r)) 2))
              (list (car r) (car (cadr r)) (cadr (cadr r)) (caddr r))
              r))))
    '(P1 P3 G)
    '((resume P1 quiet (raised cancelled http-await 0) 2 1 0 0)
      (resume P3 quiet (raised cancelled http-await 1) 3 1 0 0)
      (resume G quiet (value (#t (cancelled http-await 0) (closed go #f))) 1 1 0 0)))

   ;; --- one call proceeds while another is awaited

   (let ((b-url (location-url 302 0 "/raw/retry?key=meanwhile&fail=1&how=close")))
     (test-equal "a redirect and a retry of one call proceed while another is awaited: by the end of a 1500 ms hold's await, the other call has followed its 302 and retried its close, two attempts at the origin, and ended, with no turn of its own; it then answers its 200, after one redirect"
       (list '(answered 200 "held\n") "attempts 2\n" 'ended
             (list 'answered 200 (retry-url "meanwhile" 1 "close") "attempt 2\n" 1))
       (with-session '(timeout-ms 20000)
         (lambda (s)
           (call-with-request-group s
             (lambda (go)
               (let* ((a (go 'get (hold-url "meanwhile-a" 1500)))
                      (b (go 'get b-url 'retry (make-http-retry 'backoff-ms 50 'jitter #f)))
                      (first (guard (e (#t (list 'raised (described e))))
                               (let ((r (http-await a)))
                                 (list 'answered (http-response-status r) (latin-1 (http-response-body r))))))
                      (count (attempts-of "meanwhile"))
                      (phase (http-pending-phase b)))
                 (list first count phase (answer (lambda () (http-await b)))))))))))

   ;; At a limit of 1, a 302's follow-up is submitted from the call's own
   ;; step, on its slot, ahead of a call queued behind it: so its await ends
   ;; long before the queued 1000 ms hold could, and the queued call is let
   ;; in as the first ends.
   (let ((a-url (location-url 302 0 "/raw/retry?key=slot-a&fail=0&how=close")))
     (test-equal "a redirect keeps its call's slot: at a limit of 1, a 302's follow-up is submitted at once, ahead of a call queued behind it, its await ending within 800 ms where the queued call holds 1000; the queued call is let in after, and answers"
       (list (list 'answered 200 (retry-url "slot-a" 0 "close") "attempt 1\n" 1) 'ahead
             '(answered 200 "held\n"))
       (with-session '(timeout-ms 20000)
         (lambda (s)
           (call-with-request-group s 'limit 1
             (lambda (go)
               (let* ((t0 (now-ms))
                      (a (go 'get a-url))
                      (b (go 'get (hold-url "slot-b" 1000)))
                      (first (answer (lambda () (http-await a))))
                      (took (- (now-ms) t0))
                      (second (guard (e (#t (list 'raised (described e))))
                                (let ((r (http-await b)))
                                  (list 'answered (http-response-status r) (latin-1 (http-response-body r)))))))
                 (list first (if (< took 800) 'ahead (list 'took took)) second))))))))

   ;; At a limit of 1 each call is let in as the one before it ends, so the
   ;; retry script's count, which names each request's place in its arrival,
   ;; shows the order the calls were let in: first in, first out, in go's
   ;; order and in SPECS'.
   (test-equal "queued calls are let in first in, first out: at a limit of 1, four of go's calls reach the origin in go's order, and three of http-parallel's in SPECS' order"
     (list '("attempt 1\n" "attempt 2\n" "attempt 3\n" "attempt 4\n")
           '("attempt 1\n" "attempt 2\n" "attempt 3\n"))
     (with-session '(timeout-ms 20000)
       (lambda (s)
         (list (call-with-request-group s 'limit 1
                 (lambda (go)
                   (let ((pendings (in-order (lambda (i) (go 'get (retry-url "fifo-go" 0 "close")))
                                             '(1 2 3 4))))
                     (in-order (lambda (p)
                                 (guard (e (#t (list 'raised (described e))))
                                   (latin-1 (http-response-body (http-await p)))))
                               pendings))))
               (guard (e (#t (list 'raised (described e))))
                 (in-order (lambda (r) (latin-1 (http-response-body r)))
                           (http-parallel s (in-order (lambda (i) (list 'get (retry-url "fifo-parallel" 0 "close")))
                                                      '(1 2 3))
                                          'limit 1)))))))

   ;; --- a deferred submit that raises

   (test-equal "a deferred submit that raises is that call's failure alone: at a limit of 1, a call queued behind a done one, the session then closed, is let in by the first's await, whose submit the stopped engine refuses; the first's await answers its 200, and the second's raises the engine's stopped, with no transfer; nothing reached the origin for it"
     (list '(answered 200 "status 200\n")
           (list 'raised '(curl-engine-error stopped) (list 'exchange 'get (retry-url "deferred" 0 "close") 0 0))
           '(returned done)
           "attempts 0\n")
     (let* ((s (make-http-session 'timeout-ms 20000))
            (rows '())
            (group (outcome
                    (lambda ()
                      (escape-after 20000 (lambda () (call-with-request-group s 'limit 1
                        (lambda (go)
                          (let* ((a (go 'get ok))
                                 (b (go 'get (retry-url "deferred" 0 "close"))))
                            (curl-token-wait (http-pending-token a) 5000)
                            (http-session-close s)
                            (let* ((first (guard (e (#t (list 'raised (described e))))
                                            (let ((r (http-await a)))
                                              (list 'answered (http-response-status r)
                                                    (latin-1 (http-response-body r))))))
                                   (second (outcome (lambda () (http-await b)))))
                              (set! rows (list first second))
                              'done))))))))))
       (http-session-close s)
       (append rows (list group (attempts-of "deferred")))))

   ;; --- http-pending-done? and the cancel

   (let ((url (location-url 302 0 "/raw/retry?key=polled&fail=0&how=close")))
     (test-equal "http-pending-done? moves the group on: polled alone, never awaited, a call follows its 302 and ends, its follow-up counted at the origin before any await; the group then returns, and the call answers after it"
       (list 'reached "attempts 1\n" '(returned polled)
             (list 'answered 200 (retry-url "polled" 0 "close") "attempt 1\n" 1))
       (with-session '(timeout-ms 20000)
         (lambda (s)
           (let* ((p #f)
                  (reached #f)
                  (count #f)
                  (group (outcome
                          (lambda ()
                            (call-with-request-group s
                              (lambda (go)
                                (set! p (go 'get url))
                                (set! reached (poll-until 5000 (lambda () (http-pending-done? p))))
                                (set! count (attempts-of "polled"))
                                'polled))))))
             (list reached count group (answer (lambda () (http-await p)))))))))

   ;; The live one is awaited inside the procedure at once, before its
   ;; engine has carried the cancel out: the await waits for the token to
   ;; end, so its raise is compounded with the transfer's cancel, and a
   ;; second await raises that same object.
   (let ((live-raise (list 'raised '(http-error) '(http-group-error cancelled http-await)
                           '(curl-transfer-error other cancelled #f)
                           (list 'exchange 'get (hold-url "exempt" 3000) 0 0))))
     (test-equal "a cancelled call is exempt from the join's raise: a live 3 s hold, a queued call and a waiting one, each cancelled, and the procedure returns its value within 2 s, the engine then holding nothing; the live one's await raises cancelled compounded with its transfer's cancel, at once inside the procedure and twice the same object, the others' with none"
       (list '(returned fine) 'promptly '(0 0 0)
             (list live-raise 'same-object)
             live-raise
             (list 'raised '(http-error) '(http-group-error cancelled http-await)
                   (list 'exchange 'get (retry-url "exempt-wait" 1 "close") 0 1))
             (list 'raised '(http-error) '(http-group-error cancelled http-await)
                   (list 'exchange 'get (hold-url "exempt-queued" 100) 0 0)))
       (with-session '(timeout-ms 20000)
         (lambda (s)
           (let* ((t0 (now-ms))
                  (pendings '())
                  (inside #f)
                  (group (outcome
                          (lambda ()
                            (call-with-request-group s 'limit 2
                              (lambda (go)
                                (let* ((a (go 'get (hold-url "exempt" 3000)))
                                       (c (go 'get (retry-url "exempt-wait" 1 "close")
                                              'retry (make-http-retry 'backoff-ms 5000 'jitter #f)))
                                       (d (go 'get (hold-url "exempt-queued" 100))))
                                  (set! pendings (list a c d))
                                  (poll-until 5000 (lambda ()
                                                     (http-pending-done? c)
                                                     (eq? (http-pending-phase c) 'waiting)))
                                  (http-pending-cancel d)
                                  (http-pending-cancel c)
                                  (http-pending-cancel a)
                                  (let* ((once (guard (e (#t e)) (http-await a) 'no-raise))
                                         (twice (guard (e (#t e)) (http-await a) 'no-raise)))
                                    (set! inside (list (cons 'raised (described once))
                                                       (if (and (condition? once) (eq? once twice))
                                                           'same-object
                                                           (list 'differs twice)))))
                                  'fine))))))
                  (took (- (now-ms) t0))
                  (holds (engine-holds s)))
             (append (list group (if (< took 2000) 'promptly (list 'took took)) holds inside)
                     (in-order (lambda (p) (outcome (lambda () (http-await p)))) pendings)))))))

   ;; A cancel exempts a call from the join's raise whatever the turns did:
   ;; A and B, two refused connects, are waited for on their tokens, with no
   ;; turn, until each is done;
   ;; then A is cancelled, with no turn first, while it is unstepped, or
   ;; after a turn, a look of B's, has seen it fail. Either way the join
   ;; raises nothing for A, B's failure being awaited; A's await then
   ;; answers what its cancel left: cancelled, compounded with the refused
   ;; connect, when it was unstepped; its own failure when it had failed.
   (let ((a-url "http://127.0.0.1:1/a"))
     (test-equal "a caller's cancel exempts a call from the join's raise in either order: cancelled before any turn stepped its failure, its await raises cancelled with that failure; cancelled after a turn saw it fail, it keeps its answer, the failure its await raises; the join raises nothing in both"
       (list (list '(returned no-turn) (list 'raised '(http-error) '(http-group-error cancelled http-await)
                                             '(curl-transfer-error connect perform-failed 7)
                                             (list 'exchange 'get a-url 0 0)))
             (list '(returned a-turn) (list 'raised '(curl-transfer-error connect perform-failed 7)
                                            (list 'exchange 'get a-url 0 1))))
       (with-session '(timeout-ms 20000)
         (lambda (s)
           (in-order (lambda (turn?)
                       (let* ((a #f)
                              (group (outcome
                                      (lambda ()
                                        (call-with-request-group s
                                          (lambda (go)
                                            (set! a (go 'get a-url))
                                            (let ((b (go 'get "http://127.0.0.1:1/b")))
                                              (curl-token-wait (http-pending-token a) 5000)
                                              (curl-token-wait (http-pending-token b) 5000)
                                              (when turn? (http-pending-done? b))
                                              (http-pending-cancel a)
                                              (guard (e (#t #f)) (http-await b))
                                              (if turn? 'a-turn 'no-turn))))))))
                         (list group (outcome (lambda () (http-await a))))))
                     '(#f #t))))))

   ;; Five looks at a live 3 s hold: a turn with no wait takes no time from
   ;; the mailbox, where a turn with a wait would take up to 100 ms each.
   (test-equal "http-pending-done? never waits: five calls on a live 3 s hold each answer #f, all five within 300 ms"
     (list '(#f #f #f #f #f) 'at-once)
     (with-session '(timeout-ms 20000)
       (lambda (s)
         (call-with-request-group s
           (lambda (go)
             (let* ((p (go 'get (hold-url "no-wait" 3000)))
                    (t0 (now-ms))
                    (looks (in-order (lambda (i) (http-pending-done? p)) '(1 2 3 4 5)))
                    (took (- (now-ms) t0)))
               (http-pending-cancel p)
               (list looks (if (< took 300) 'at-once (list 'took took)))))))))

   (test-equal "a cancel of an ended call does nothing: its await answers its response, the same object, before and after the cancel; and an await answers twice the same, a failure's raise the same object, after the group has returned too"
     (list 'same-response 'same-condition 'same-after-the-group 'same-raise-after-the-group)
     (with-session '(timeout-ms 20000)
       (lambda (s)
         (let* ((kept #f)
                (rows (call-with-request-group s
                        (lambda (go)
                          (let* ((p (go 'get ok))
                                 (f (go 'get refused))
                                 (r1 (http-await p))
                                 (cancel-p (http-pending-cancel p))
                                 (r2 (http-await p))
                                 (c1 (guard (e (#t e)) (http-await f) 'no-raise))
                                 (cancel-f (http-pending-cancel f))
                                 (c2 (guard (e (#t e)) (http-await f) 'no-raise)))
                            (set! kept (list p r1 f c1))
                            (list (if (and (http-response? r1) (eq? r1 r2)) 'same-response (list r1 r2))
                                  (if (and (condition? c1) (eq? c1 c2)) 'same-condition (list c1 c2))))))))
           (append rows
                   (list (if (eq? (http-await (car kept)) (cadr kept)) 'same-after-the-group 'other)
                         (guard (e ((eq? e (cadddr kept)) 'same-raise-after-the-group)
                                   (#t (list 'other (described e))))
                           (http-await (caddr kept))
                           'no-raise)))))))

   ;; --- a queued call's deadline

   (test-equal "a queued call is on its clock: at a limit of 1, behind a 1500 ms hold, a call bounded by 300 ms fails with &http-timeout, no transfer made, within 1200 ms, never submitted; the hold still answers"
     (list (list 'raised '(http-error) '(http-timeout 300) (list 'exchange 'get (hold-url "deadline-b" 100) 0 0))
           'before-the-hold "held 0 most 0\n" '(answered 200 "held\n"))
     (with-session '(timeout-ms 20000)
       (lambda (s)
         (call-with-request-group s 'limit 1
           (lambda (go)
             (let* ((a (go 'get (hold-url "deadline-a" 1500)))
                    (t0 (now-ms))
                    (b (go 'get (hold-url "deadline-b" 100) 'timeout-ms 300))
                    (raised (outcome (lambda () (http-await b))))
                    (took (- (now-ms) t0))
                    (most (most-of "deadline-b"))
                    (first (guard (e (#t (list 'raised (described e))))
                             (let ((r (http-await a)))
                               (list 'answered (http-response-status r) (latin-1 (http-response-body r)))))))
               (list raised (if (< took 1200) 'before-the-hold (list 'took took)) most first)))))))

   ;; Ten retries of a close, each after a wait of 10 ms, beside the same
   ;; ten after waits of 0, which submit at once: the transfers cost alike,
   ;; so the difference is the waits' own. A take bounded by the next due
   ;; time ends each at its 10 ms; one bounded by 100 ms alone overshoots
   ;; each to 100, with nothing else in flight to wake it: 900 ms more.
   (test-equal "a retry's wait in a group ends at its due time, not at the take's 100 ms: ten waits of 10 ms take less than 500 ms more than ten of 0; both calls answer the eleventh attempt's 200"
     (list '(answered 200 "attempt 11\n") '(answered 200 "attempt 11\n") 'on-time)
     (let ((run (lambda (key backoff)
                  (with-session (list 'timeout-ms 20000
                                      'retry (make-http-retry 'attempts 11 'backoff-ms backoff
                                                              'max-backoff-ms backoff 'jitter #f))
                    (lambda (s)
                      (let* ((t0 (now-ms))
                             (a (call-with-request-group s
                                  (lambda (go)
                                    (let ((p (go 'get (retry-url key 10 "close"))))
                                      (guard (e (#t (list 'raised (described e))))
                                        (let ((r (http-await p)))
                                          (list 'answered (http-response-status r)
                                                (latin-1 (http-response-body r)))))))))
                             (took (- (now-ms) t0)))
                        (list a took)))))))
       (let* ((zero (run "precise-0" 0))
              (ten (run "precise-10" 10)))
         (list (car zero) (car ten)
               (if (and (integer? (cadr zero)) (integer? (cadr ten)) (< (- (cadr ten) (cadr zero)) 500))
                   'on-time
                   (list 'zero (cadr zero) 'ten (cadr ten)))))))

   ;; Ten queued calls behind a 3 s hold at a limit of 1, bounded by 200 to
   ;; 290 ms, 10 ms apart, so their deadlines fall over every phase of the
   ;; take's 100 ms (traps.md: a waiter's polling sleeps keep the phase of
   ;; its start). Each is awaited in turn, and its lateness read where its
   ;; await answers: a take bounded by the next deadline wakes at it; one
   ;; bounded by 100 ms alone, with nothing else to wake it, overshoots most
   ;; of them, up to 100 ms.
   (test-equal "a queued call's deadline wakes the take: ten queued calls, bounded 200 to 290 ms apart by 10, each fail with &http-timeout within 50 ms of their deadline"
     (list (make-list 10 'timed-out) 'on-time)
     (with-session '(timeout-ms 20000)
       (lambda (s)
         (call-with-request-group s 'limit 1
           (lambda (go)
             (let* ((a (go 'get (hold-url "late-queue-a" 3000)))
                    (calls (in-order (lambda (i)
                                       (let* ((bound (+ 200 (* 10 i)))
                                              (t0 (now-ms))
                                              (p (go 'get (hold-url "late-queue-b" 100) 'timeout-ms bound)))
                                         (list p (+ t0 bound))))
                                     (iota 10)))
                    (rows (in-order (lambda (call)
                                      (let* ((raised (guard (e ((http-timeout? e) 'timed-out)
                                                               (#t (list 'other (described e))))
                                                       (http-await (car call))
                                                       'no-raise))
                                             (late (- (now-ms) (cadr call))))
                                        (list raised late)))
                                    calls)))
               (http-pending-cancel a)
               (list (map car rows)
                     (if (for-all (lambda (row) (< (cadr row) 50)) rows)
                         'on-time
                         (list 'late (map cadr rows))))))))))

   ;; --- the limit, and the time

   ;; 20 calls of 500 ms on one session: with no limit all are held at once
   ;; and end within 2 s; at a limit of 2 at most 2 are, which takes 5 s at
   ;; least, the control. The research measured the same through (curl)
   ;; alone on five libcurls, and under the memory gate's Valgrind
   ;; (.plans/research/m5/group/).
   (let ((twenty (lambda (key limit)
                   (with-session '(timeout-ms 30000)
                     (lambda (s)
                       (let* ((t0 (now-ms))
                              (answers
                               (apply call-with-request-group s
                                      (append (if limit (list 'limit limit) '())
                                              (list
                                               (lambda (go)
                                                 (let ((pendings (let loop ((i 0) (made '()))
                                                                   (if (= i 20)
                                                                       (reverse made)
                                                                       (loop (+ i 1)
                                                                             (cons (go 'get (hold-url key 500))
                                                                                   made))))))
                                                   (in-order (lambda (p)
                                                               (guard (e (#t 'raised))
                                                                 (http-response-status (http-await p))))
                                                             pendings)))))))
                              (took (- (now-ms) t0)))
                         (list (length (filter (lambda (x) (eqv? x 200)) answers)) took (most-of key))))))))
     (let ((all (guard (e (#t (list 'raised (described e) 0 ""))) (twenty "twenty-all" #f))))
       (test-equal "20 calls of 500 ms in one group with no limit: all 20 held at once at the origin, every one a 200, all ended within 2 s"
         (list 20 'within-2-s "held 0 most 20\n")
         (list (car all) (if (and (integer? (cadr all)) (< (cadr all) 2000)) 'within-2-s (list 'took (cadr all)))
               (caddr all))))
     (let ((two (guard (e (#t (list 'raised (described e) 0 ""))) (twenty "twenty-two" 2))))
       (test-equal "the control, 20 calls of 500 ms at a limit of 2: at most 2 held at once at the origin, every one a 200, which takes 5 s at least"
         (list 20 'at-least-5-s "held 0 most 2\n")
         (list (car two) (if (and (integer? (cadr two)) (>= (cadr two) 5000)) 'at-least-5-s (list 'took (cadr two)))
               (caddr two)))))

   ;; --- http-parallel

   (test-equal "http-parallel answers the responses in SPECS' order, whatever order they end in: holds of 600, 300 and 0 ms; at a limit of 1, one at a time, still in order"
     (list (list (list 200 (hold-url "par-a" 600) 0) (list 200 (hold-url "par-b" 300) 0)
                 (list 200 (hold-url "par-c" 0) 0))
           (list (list 200 (hold-url "par-one" 300) 0) (list 200 (hold-url "par-one" 200) 0)
                 (list 200 (hold-url "par-one" 0) 0))
           "held 0 most 1\n")
     (with-session '(timeout-ms 20000)
       (lambda (s)
         (let* ((a (guard (e (#t (list 'raised (described e))))
                     (map summary (http-parallel s (list (list 'get (hold-url "par-a" 600))
                                                         (list 'get (hold-url "par-b" 300))
                                                         (list 'get (hold-url "par-c" 0)))))))
                (b (guard (e (#t (list 'raised (described e))))
                     (map summary (http-parallel s (list (list 'get (hold-url "par-one" 300))
                                                         (list 'get (hold-url "par-one" 200))
                                                         (list 'get (hold-url "par-one" 0)))
                                                 'limit 1)))))
           (list a b (most-of "par-one"))))))

   (test-equal "http-parallel checks every spec before any is submitted: a later spec's unknown key, its method the low level refuses, and its ftp URL each raise, compounded with &http-exchange, and nothing reached the origin for the first spec"
     (list (list 'raised '(http-error) '(http-request-error key bogus unknown-key http-request)
                 (list 'exchange 'get ok 0 0))
           (list 'raised '(assertion make-curl-request) (list 'exchange 'options ok 0 0))
           (list 'raised '(curl-url-error scheme-not-http) (list 'exchange 'get "ftp://h.example/x" 0 0))
           0
           "held 0 most 0\n")
     (with-session '(timeout-ms 20000)
       (lambda (s)
         (let* ((started (transfers-started))
                (first (list 'get (hold-url "par-checks" 100)))
                (rows (in-order (lambda (spec) (outcome (lambda () (http-parallel s (list first spec)))))
                                (list (list 'get ok 'bogus 1) (list 'options ok)
                                      (list 'get "ftp://h.example/x")))))
           ;; let*: most-of makes a transfer of its own, so the count is read
           ;; before it, in a fixed order (traps.md).
           (let* ((made (- (transfers-started) started))
                  (most (most-of "par-checks")))
             (append rows (list made most)))))))

   ;; A submit takes the engine's mutex; another thread holds it here for
   ;; 3 s, so a submit made before a refusal would hold the call up until
   ;; then, while checks made before any submit raise at once. A collection
   ;; just before the holder starts leaves none due in the window: the holder
   ;; sleeps in a critical section, where a collection would wait for it
   ;; (traps.md). collect-rendezvous, since collect refuses while another
   ;; thread is active, an engine's among them.
   (test-equal "http-parallel's checks come before any submit: with the session's engine held by another thread for 3 s, where a submit would wait, a later spec's unknown key, refused method and ftp URL each raise within 500 ms"
     (list (list '(http-request-error key bogus unknown-key http-request) 'at-once)
           (list '(assertion make-curl-request) 'at-once)
           (list '(curl-url-error scheme-not-http) 'at-once)
           'released)
     (with-session '(timeout-ms 20000)
       (lambda (s)
         (let* ((lock (make-mutex))
                (holding #f)
                (released #f)
                (flag (lambda (get) (critical-section (with-mutex lock (get))))))
           (collect-rendezvous)
           (fork-thread
            (lambda ()
              (guard (e (#t #f))
                (call-with-engine-held (http-session-engine s)
                  (lambda ()
                    (critical-section (with-mutex lock (set! holding #t)))
                    (sleep (make-time 'time-duration 0 3)))))
              (critical-section (with-mutex lock (set! released #t)))))
           (poll-until 5000 (lambda () (flag (lambda () holding))))
           (let* ((first (list 'get (hold-url "par-held" 100)))
                  (rows (in-order (lambda (spec)
                                    (let* ((t0 (now-ms))
                                           (raised (guard (e (#t (described e)))
                                                     (http-parallel s (list first spec))
                                                     '(no-raise)))
                                           (took (- (now-ms) t0)))
                                      (list (find (lambda (x) (and (pair? x)
                                                                   (memq (car x) '(http-request-error assertion curl-url-error no-raise))))
                                                  raised)
                                            (if (< took 500) 'at-once (list 'took took)))))
                                  (list (list 'get ok 'bogus 1) (list 'options ok)
                                        (list 'get "ftp://h.example/x")))))
             (append rows
                     (list (if (eq? (poll-until 10000 (lambda () (flag (lambda () released)))) 'reached)
                               'released
                               'still-held))))))))

   ;; A timer's raise landing while http-parallel judges SPECS, a list of
   ;; 400000 specs so that judging it takes long enough, swept over the
   ;; timer's first 400 ticks, by 3: list? raises nothing, so no guard sits
   ;; there, and the raise must leave as raised, never be read as "the
   ;; specs are a list", as a guarded length read it from tick 25 (the
   ;; slice's second review).
   (test-equal "a timer's raise landing while http-parallel judges its specs leaves as raised, at every one of its first 400 ticks by 3, never read as the specs' refusal"
     '(raised-as-raised)
     (let* ((s (make-http-session 'timeout-ms 20000))
            (planted (condition (make-assertion-violation) (make-who-condition 'planted)
                                (make-message-condition "planted by the timer")))
            (specs (make-list 400000 (list 'get "http://127.0.0.1:1/x")))
            (previous (timer-interrupt-handler))
            (seen (let loop ((ticks 1) (seen '()))
                    (if (> ticks 400)
                        seen
                        (let ((c (guard (e ((eq? e planted) 'raw)
                                           ((and (condition? e) (who-condition? e)
                                                 (eq? (condition-who e) 'http-parallel))
                                            'refusal)
                                           (#t 'other))
                                   (timer-interrupt-handler (lambda () (raise planted)))
                                   (set-timer ticks)
                                   (http-parallel s specs)
                                   'returned)))
                          (set-timer 0)
                          (loop (+ ticks 3) (if (memq c seen) seen (cons c seen))))))))
       (timer-interrupt-handler previous)
       (http-session-close s)
       (if (equal? seen '(raw)) '(raised-as-raised) seen)))

   ;; http-parallel's checks before any submit are (curl)'s own,
   ;; curl-request-check's, the submit's checks (ADR-0023, amended
   ;; 2026-10-28): its refusal of an ftp URL is the check's of the same
   ;; first request, made before any submit. A submit of the ftp request
   ;; would be refused too, alike, by the same checks, with no transfer
   ;; either way; what tells a check before any submit from a refused
   ;; submit is the core's step of the refusal, which draws once from the
   ;; session's generator (the slice's second review): so the generator's
   ;; state must be as it was. Its refusal of an ftp URL is the check's of the same
   ;; first request, whole, and a submit's but for nothing, a URL's refusal
   ;; naming chez-curl as its who in all three; compounded, in
   ;; http-parallel's, with the call's &http-exchange.
   (test-equal "http-parallel's scheme refusal is curl-request-check's of the call's first request: &curl-url-error, scheme-not-http, its input, code, message, who and irritants as the check raises them, and as a submit does; compounded with the call's &http-exchange, no transfer made; and made before any submit: a refused submit's step would have drawn from the session's generator, which no step drew from"
     (list 'the-check-s 'a-submit-s '(exchange get "FTP://h.example/a/../x" 0 0) 'no-step-drew)
     (with-session '()
       (lambda (s)
         (let* ((drawn-before (pseudo-random-generator->vector (http-session-generator s)))
                (fields (lambda (e)
                          (list (curl-url-error? e) (curl-url-error-reason e) (curl-url-error-input e)
                                (curl-url-error-code e) (curl-url-error-message e)
                                (and (who-condition? e) (condition-who e))
                                (and (irritants-condition? e) (condition-irritants e))
                                (and (message-condition? e) (condition-message e)))))
                (url "FTP://h.example/a/../x")
                (request (make-curl-request (curl-url-part url 'url)))
                (drawn-after #f)
                (exchange #f)
                (ours (guard (e ((curl-url-error? e)
                                 (set! drawn-after (pseudo-random-generator->vector (http-session-generator s)))
                                 (when (http-exchange? e)
                                   (set! exchange (list 'exchange (http-exchange-method e) (http-exchange-url e)
                                                        (length (http-exchange-history e))
                                                        (http-exchange-transfers e))))
                                 (fields e))
                                (#t (list 'other (described e))))
                        (http-parallel s (list (list 'get url)))
                        'no-raise))
                (checks (guard (e ((curl-url-error? e) (fields e)) (#t (list 'other (described e))))
                          (curl-request-check request)
                          'no-raise))
                (submits (guard (e ((curl-url-error? e) (fields e)) (#t (list 'other (described e))))
                           (curl-submit (http-session-engine s) request)
                           'no-raise)))
           (list (if (and (pair? ours) (eq? (car ours) #t) (equal? ours checks)) 'the-check-s (list ours checks))
                 (if (equal? checks submits) 'a-submit-s (list checks submits))
                 exchange
                 (if (equal? drawn-before drawn-after) 'no-step-drew (list 'drew drawn-after)))))))

   ;; The handler runs before any unwinding, inside http-parallel's
   ;; extent: the rest are cancelled and ended by then, not by the winds.
   (test-equal "http-parallel raises its first failure, as the call raised it, once the rest are cancelled and ended, three times: a refused connect beside a 5 s hold, raised within 2 s, the engine holding nothing as the raise reaches a handler, before any unwinding, and after"
     (make-list 3 (list (list 'raised '(curl-transfer-error connect perform-failed 7) (list 'exchange 'get refused 0 1))
                        'promptly '(0 0 0) '(0 0 0)))
     (in-order
      (lambda (run)
       (with-session '(timeout-ms 20000)
       (lambda (s)
         (let* ((t0 (now-ms))
                (at-raise #f)
                (raised (call/cc
                         (lambda (k)
                           (with-exception-handler
                            (lambda (e)
                              (set! at-raise (engine-holds s))
                              (k (cons 'raised (described e))))
                            (lambda ()
                              (http-parallel s (list (list 'get (hold-url "par-fail" 5000))
                                                     (list 'get refused)))
                              'returned)))))
                (took (- (now-ms) t0))
                (holds (engine-holds s)))
           (list raised (if (< took 2000) 'promptly (list 'took took)) at-raise holds)))))
      '(1 2 3)))

   ;; With the engine stopped, every submit is refused as it is made, in
   ;; SPECS' order, a refusal only a submit makes: each is a failure among
   ;; the calls, and the first raises.
   (test-equal "http-parallel on a session closed: every submit is refused, a refusal only a submit makes, each its call's failure, in SPECS' order, and the first raises: the engine's stopped, compounded with the first call's &http-exchange"
     (list 'raised '(curl-engine-error stopped) (list 'exchange 'get (url-of 'http "/status/201") 0 0))
     (let ((s (make-http-session 'timeout-ms 20000)))
       (http-session-close s)
       (escape-after 20000
                     (lambda ()
                       (outcome (lambda ()
                                  (http-parallel s (list (list 'get (url-of 'http "/status/201"))
                                                         (list 'get (url-of 'http "/status/202"))
                                                         (list 'get (url-of 'http "/status/203"))))))))))

   ;; The session's generator is copied, by its state, to see its next draw
   ;; without taking it, as test-retry does: draws are taken until the next
   ;; lies in [0.3, 0.5], so the wait it sets, of a 2000 ms backoff, is 600
   ;; to 1000 ms. The call makes two steps, the close and the 200, and draws
   ;; once in each.
   (let ((url (retry-url "jitter-group" 1 "close")))
     (test-equal "a group's call draws from its session's generator, once per step: its retry's wait is that draw times the backoff, predicted from a copy of the generator, and two steps draw twice"
       (list (list 'answered 200 url "attempt 2\n" 0) 'as-drawn 'two-draws)
       (with-session (list 'timeout-ms 20000
                           'retry (make-http-retry 'backoff-ms 2000 'max-backoff-ms 2000 'jitter #t))
         (lambda (s)
           (let* ((g (http-session-generator s))
                  (copy (lambda () (vector->pseudo-random-generator (pseudo-random-generator->vector g))))
                  (skipped (let loop ((k 0))
                             (let ((d (pseudo-random-generator-next! (copy))))
                               (if (or (and (>= d 0.3) (<= d 0.5)) (> k 1000))
                                   k
                                   (begin (http-session-draw s) (loop (+ k 1)))))))
                  (ahead (copy))
                  (d1 (pseudo-random-generator-next! ahead))
                  (d2 (pseudo-random-generator-next! ahead))
                  (predicted (floor (* (exact d1) 2000)))
                  (t0 (now-ms))
                  (a (call-with-request-group s
                       (lambda (go)
                         (let ((p (go 'get url)))
                           (answer (lambda () (http-await p)))))))
                  (took (- (now-ms) t0)))
             (list a
                   (if (and (>= took predicted) (< took (+ predicted 900)))
                       'as-drawn
                       (list 'took took 'predicted predicted 'skipped skipped))
                   (if (equal? (pseudo-random-generator->vector g) (pseudo-random-generator->vector ahead))
                       'two-draws
                       'other-draws)))))))

   (test-equal "every count is zero once the suite's sessions have closed"
     zero-counts
     (native-counts))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "group")

(exit (suite-exit-status runner))
