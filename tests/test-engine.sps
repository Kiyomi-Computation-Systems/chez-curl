#!r6rs
;;; The suite for (curl private engine): one Chez thread that owns a multi
;;; handle and runs the transfers other threads submit (ADR-0012; M3 plan,
;;; sections 3 and 5.3). Each check was watched failing on a mutant before
;;; it counted (.plans/engine-mutation-log.md).
;;;
;;;   - concurrency: many transfers on one engine, their drips overlapping
;;;     in time, every chunk on the engine's thread; two caller threads
;;;     awaiting together, each returning on its own thread;
;;;   - a dead pooled connection: one drip after eight whose connections the
;;;     raw face closed unannounced, each libcurl's answer, by version, a
;;;     row of reuse-verdicts (ADR-0020, amended 2026-10-26). Checks that
;;;     run drips together each make an engine of their own, so the suite's
;;;     engine never pools more than one dead connection;
;;;   - submit: each refusal raised at submit, with nothing queued, nothing
;;;     started and the counts unchanged; a submit to a stopped engine;
;;;   - cancel, in each of its three states, and racing a completion;
;;;   - stop, with transfers queued and live, each completing as stopped,
;;;     a later submit refused, a second stop at once, the counts at zero;
;;;   - the thread rule: the engine's handle used from another thread
;;;     raises &curl-wrong-thread, with who, expected and actual;
;;;   - a request carrying a procedure is refused when it is made;
;;;   - a raise inside the loop, at each step a fault can be planted;
;;;   - in children, each under a bound: the collection bound, beside an
;;;     idle engine and beside a caller awaiting a slow transfer; four
;;;     caller threads awaiting at once while collections run; and Ctrl-C
;;;     while a caller awaits;
;;;   - a stalled name lookup (ADR-0019), on Linux: a child under a
;;;     stand-in getaddrinfo, tests/stall-getaddrinfo.c, compiled here and
;;;     preloaded, cancels, times out and stops transfers whose lookups
;;;     stall, beside a transfer that must go on. Each libcurl's verdicts,
;;;     by version, are a row of stall-verdicts, with a control for each
;;;     QUICK_EXIT setting, which an engine made without it shows stalling;
;;;     the floor, which has neither, stalls, the recorded limit. And the
;;;     engine's judgement of CURLMOPT_QUICK_EXIT's answer, over its domain.
;;;
;;; The plan's load check, a child whose first reference to the library is
;;; make-curl-engine, is not here: a top-level program invokes the
;;; libraries it imports, and theirs, before its first line, so no engine's
;;; thread can make a first reference, and that child passed with
;;; make-curl-engine's early reference removed, 20 runs of 20.
;;;
;;; Importing (curl) runs the load before this suite's first line, on this
;;; thread. Every expected value is one the code under test cannot produce
;;; by failing: SRFI-64 makes #f of a raise in the actual expression, so
;;; none is #f.
(import (rnrs)
        (srfi :64)
        (rnrs mutable-strings)
        (only (chezscheme) fork-thread make-mutex with-mutex sleep make-time current-time
              time-second time-nanosecond
              getenv get-thread-id library-directories make-list iota machine-type)
        (curl-testing)
        (only (libcurl-oracle) c-compiler)
        (curl)
        (curl private engine)
        (curl private transfer)
        (curl private conditions)
        (curl private counters)
        (curl private memory)
        (only (curl private native) curl-multi-perform curl-multi-poll curl-multi-info-read
              curl-multi-setopt-long)
        (only (curl private constants) curlmopt-max-total-connections))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; written : Any -> String
(define (written x) (call-with-string-output-port (lambda (p) (write x p))))

;; The simple runner names a failing test but not its values. Print both.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (display "  expected: ")
        (display (written (test-result-ref r 'expected-value)))
        (newline)
        (display "  actual:   ")
        (display (written (test-result-ref r 'actual-value)))
        (newline))
      ;; A suite killed at its bound never flushes: flush each verdict.
      (flush-output-port (current-output-port)))))

(test-begin "engine")

;; --- helpers --------------------------------------------------------------------------

(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0)))

;; The counts while the suite's engine runs: its multi handle and its slot,
;; and nothing else.
(define running-counts
  '((block . 1) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 1)))

;; The loaded libcurl, read here, on this thread, before any thread is
;; forked.
(define version
  (guard (e (#t (list 'no-version (describe e))))
    (libcurl-info-version (loaded-libcurl))))

;; now-ms : -> Integer
(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

;; pause-ms : Natural -> Unit
(define (pause-ms ms)
  (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))

;; latin-1 : Bytevector -> String
(define (latin-1 bytes)
  (list->string (map integer->char (bytevector->u8-list bytes))))

;; request : String . (Listof Any) -> Request
;; A GET of TARGET, no headers, no user agent, a 20 s timeout, no limit,
;; the system store, verification on; OPTIONS give headers, ca-file or
;; fault, keyword then value.
(define (request target . options)
  (let ((given (lambda (key default)
                 (let ((at (memq key options))) (if at (cadr at) default)))))
    (make-transfer-request target 'get (given 'headers '()) #f 20000 #f
                           (given 'ca-file #f) #t (given 'fault #f))))

;; outcome : (-> Response) -> Outcome
;; What THUNK answers, whole: (response STATUS BODY), the body as Latin-1;
;; (transfer-error REASON CODE RECORDED); (engine-error REASON CONDITION);
;; (request-refused FIELD REASON); (url-refused REASON);
;; (assertion-violation WHO); (raised TEXT) for anything else.
(define (outcome thunk)
  (guard (e ((curl-transfer-error? e)
             (list 'transfer-error (curl-transfer-error-reason e) (curl-transfer-error-code e)
                   (curl-transfer-error-recorded e)))
            ((curl-engine-error? e)
             (list 'engine-error (curl-engine-error-reason e) (curl-engine-error-condition e)))
            ((curl-request-error? e)
             (list 'request-refused (curl-request-error-field e) (curl-request-error-reason e)))
            ((curl-url-error? e) (list 'url-refused (curl-url-error-reason e)))
            ((and (assertion-violation? e) (who-condition? e))
             (list 'assertion-violation (condition-who e)))
            (#t (list 'raised (describe e))))
    (let ((r (thunk)))
      (list 'response (transfer-response-status r) (latin-1 (transfer-response-body r))))))

;; await-bounded : Token Natural -> Response
;; curl-token-await's answer for TOKEN, called once curl-token-done? says
;; it is done, polled every 1 ms for at most MS; a raise of
;; (never-completed) if it is not done by then. A token an engine never
;; completes, or a wait that deadlocks, would hang an await for good, and a
;; hang names no test: so every await in this suite is bounded, and the
;; children, each under a bound of its own, are where curl-token-await
;; waits.
(define (await-bounded token ms)
  (let ((deadline (+ (now-ms) ms)))
    (let wait ()
      (cond ((curl-token-done? token) (curl-token-await token))
            ((> (now-ms) deadline) (raise '(never-completed)))
            (else (pause-ms 1) (wait))))))

;; awaited-within : Token Natural -> Outcome
;; TOKEN's outcome, by await-bounded within MS; (never-completed) if it is
;; not done by then.
(define (awaited-within token ms)
  (guard (e ((equal? e '(never-completed)) e))
    (outcome (lambda () (await-bounded token ms)))))

;; awaited : Token -> Outcome
;; TOKEN's outcome, within 20 s.
(define (awaited token) (awaited-within token 20000))

;; reuse-outcome : Token -> Any
;; TOKEN's outcome within 20 s, as awaited names a response; a
;; &curl-transfer-error as (transfer-error REASON CODE ERROR-BUFFER), the
;; buffer's text naming how libcurl gave up; (never-completed), or
;; (raised TEXT) for anything else.
(define (reuse-outcome token)
  (guard (e ((curl-transfer-error? e)
             (list 'transfer-error (curl-transfer-error-reason e) (curl-transfer-error-code e)
                   (curl-transfer-error-error-buffer e)))
            ((equal? e '(never-completed)) e)
            (#t (list 'raised (describe e))))
    (let ((r (await-bounded token 20000)))
      (list 'response (transfer-response-status r) (latin-1 (transfer-response-body r))))))

;; stop-within : Engine . (List (-> Any)) -> Any
;; curl-engine-stop of ENGINE, run on a thread of its own, waited for here
;; for at most 20 s: a raise of (never-stopped) if it has not returned by
;; then, so a stop that hangs fails the check that made it, by name. THEN,
;; if given, runs on that thread the moment the stop returns, and its
;; answer is this one's: what a check reads then is what the stop left,
;; with no wait between.
(define (stop-within engine . then)
  (let ((mx (make-mutex)) (done #f) (answer #f) (deadline (+ (now-ms) 20000)))
    (fork-thread
     (lambda ()
       (guard (e (#t #f)) (curl-engine-stop engine))
       (let ((a (if (null? then) #t (guard (e (#t (list 'raised (describe e)))) ((car then))))))
         (with-mutex mx (set! answer a) (set! done #t)))))
    (let wait ()
      (cond ((with-mutex mx done) answer)
            ((> (now-ms) deadline) (raise '(never-stopped)))
            (else (pause-ms 1) (wait))))))

;; on-own-engine : (Engine -> Any) -> Any
;; What PROC answers, given an engine made for it alone and stopped by
;; stop-within once PROC returns, so a check on it starts with an empty
;; connection pool, whatever the suite's engine has pooled; (raised TEXT)
;; for anything raised, a stop that hangs among them.
(define (on-own-engine proc)
  (guard (e (#t (list 'raised (describe e))))
    (let* ((own (make-curl-engine))
           (answer (guard (e (#t (list 'raised (describe e)))) (proc own))))
      (stop-within own)
      answer)))

;; url-of : Origin Symbol String -> String
(define (url-of o face path)
  (let ((f (origin-face o face)))
    (string-append "http://" (car f) ":" (number->string (cdr f)) path)))

;; drip-body : Natural -> String
;; What /raw/drip?bytes=N answers: the alphabet, over and over, N bytes of it.
(define (drip-body n)
  (list->string (map (lambda (i) (integer->char (+ 97 (mod i 26)))) (iota n))))

;; library-path : -> String
;; This suite's library path, as --libdirs takes it.
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

;; child-script : Positive-Integer -> String
;; sh -c CHILD-SCRIPT sh COMMAND...: COMMAND, its stdin at its end, under
;; GNU timeout (gtimeout on macOS), killed with SIGKILL after BOUND
;; seconds, exit 137; exit 125 with neither found. The shell's own stderr
;; is /dev/null, so dash's "Killed" is not the command's (traps.md).
(define (child-script bound)
  (string-append
   "t=$(command -v timeout || command -v gtimeout) || { echo 'engine child: no timeout' >&2; exit 125; }\n"
   "exec 3>&2 2>/dev/null\n"
   "( exec \"$t\" -s KILL " (number->string bound) " \"$@\" </dev/null 2>&3 3>&- )\n"
   "exit $?\n"))

;; run-child : Positive-Integer String . (Listof String) -> (List Integer (Listof Any) String)
;; tests/PROGRAM with ARGS, in a child Chez, under child-script: its exit
;; status, what it printed, read as data, and its stderr.
(define (run-child bound program . args)
  (guard (e (#t (list 'raised (describe e) "")))
    (let ((r (capture-command (append (list "sh" "-c" (child-script bound) "sh" (getenv "CHEZ")
                                            "--libdirs" (library-path) "--program" program)
                                      args))))
      (list (car r) (read-all (cadr r)) (caddr r)))))

;; interrupt-script : String
;; sh -c INTERRUPT-SCRIPT sh COMMAND...: COMMAND under GNU timeout (gtimeout
;; on macOS), killed with SIGKILL after 60 s, its output in a file made
;; under TMPDIR; once it prints (ready PID), 500 ms later, SIGINT to PID,
;; the child Chez itself; then its exit status, and its output but the
;; ready line. Exit 125 with no timeout, 126 when the child never says it
;; is ready, within 20 s.
(define interrupt-script
  (string-append
   "t=$(command -v timeout || command -v gtimeout) || { echo 'engine-interrupt: no timeout' >&2; exit 125; }\n"
   "out=$(mktemp \"${TMPDIR:-/tmp}/engine-interrupt.XXXXXX\") || exit 125\n"
   "\"$t\" -s KILL 60 \"$@\" >\"$out\" 2>&1 </dev/null &\n"
   "waiter=$!\n"
   "n=0\n"
   "until grep -q '^(ready ' \"$out\" || [ \"$n\" -ge 400 ]; do sleep 0.05; n=$((n + 1)); done\n"
   "pid=$(sed -n 's/^(ready \\([0-9]*\\))$/\\1/p' \"$out\")\n"
   "if [ -z \"$pid\" ]; then kill \"$waiter\"; wait \"$waiter\"; cat \"$out\" >&2; rm -f \"$out\"; echo 'engine-interrupt: the child never said it was ready' >&2; exit 126; fi\n"
   "sleep 0.5\n"
   "kill -INT \"$pid\"\n"
   "wait \"$waiter\"\n"
   "status=$?\n"
   "grep -v '^(ready ' \"$out\"\n"
   "rm -f \"$out\"\n"
   "exit $status\n"))

;; run-interrupt-child : String -> (List Integer (Listof Any) String)
;; tests/engine-interrupt.sps for URL, under interrupt-script: its exit
;; status, what it printed but its ready line, read as data, and the
;; script's stderr.
(define (run-interrupt-child url)
  (guard (e (#t (list 'raised (describe e) "")))
    (let ((r (capture-command (list "sh" "-c" interrupt-script "sh" (getenv "CHEZ")
                                    "--libdirs" (library-path)
                                    "--program" "tests/engine-interrupt.sps" url))))
      (list (car r) (read-all (cadr r)) (caddr r)))))

;; --- the engine, made ------------------------------------------------------------------

(define main-thread (get-thread-id))

(define engine
  (guard (e (#t (list 'raised (describe e))))
    (make-curl-engine)))

(define engine-made? (curl-engine? engine))

(test-equal "make-curl-engine returns an engine running on a thread of its own, its multi handle made there"
  (list #t 'running #t #t)
  (if engine-made?
      (list #t (curl-engine-state engine)
            (not (eqv? (curl-engine-thread engine) main-thread))
            (and (curl-engine-multi engine) #t))
      engine))

(test-equal "a request carrying a procedure is refused when it is made: a fault is data, never a procedure (ADR-0012, decision 4)"
  '(assertion-violation make-transfer-request)
  (outcome (lambda () (make-transfer-request "http://127.0.0.1/" 'get '() #f #f #f #f #t
                                             (lambda (chunk) chunk)))))

;; --- the thread rule (ADR-0012, decision 3) ----------------------------------------------

;; wrong-thread : (-> Any) -> Any
;; THUNK's &curl-wrong-thread as (WHO EXPECTED ACTUAL), or what it did.
(define (wrong-thread thunk)
  (guard (e ((curl-wrong-thread? e)
             (list (curl-wrong-thread-who e) (curl-wrong-thread-expected e)
                   (curl-wrong-thread-actual e)))
            (#t (list 'raised (describe e))))
    (thunk)
    'no-raise))

(test-equal "the engine's multi handle, used from this thread, raises &curl-wrong-thread from curl-multi-perform, curl-multi-poll, curl-multi-info-read and curl-multi-setopt, each carrying the engine's thread as expected and this one as actual"
  (if engine-made?
      (map (lambda (who) (list who (curl-engine-thread engine) main-thread))
           '(curl-multi-perform curl-multi-poll curl-multi-info-read curl-multi-setopt))
      engine)
  ;; A slot of this suite's own: without the check, the calls would run, and
  ;; write through it.
  (if engine-made?
      (let ((multi (curl-engine-multi engine))
            (slot (foreign-block 8)))
        (let* ((perform (wrong-thread (lambda () (curl-multi-perform multi slot))))
               (poll (wrong-thread (lambda () (curl-multi-poll multi 0))))
               (read (wrong-thread (lambda () (curl-multi-info-read multi slot))))
               ;; 0 is the option's default: through, it would change nothing.
               (setopt (wrong-thread (lambda () (curl-multi-setopt-long multi curlmopt-max-total-connections 0)))))
          (free-foreign-block! slot)
          (list perform poll read setopt)))
      engine))

;; refused-at-submit : (-> Any) (Listof (Pairof String Integer)) -> (List Outcome Counts Natural Natural Natural)
;; What a submit of MAKE's request, with OPTIONS, answered, the counts
;; after, how many messages the engine queued and transfers it holds, and
;; how many transfers were started meanwhile.
(define (refused-at-submit make options)
  (let* ((started (transfers-started))
         (answer (outcome (lambda () (curl-engine-submit-with engine (make) options)))))
    (list answer (native-counts) (curl-engine-queued-count engine)
          (curl-engine-live-count engine) (- (transfers-started) started))))

;; --- against the origin ----------------------------------------------------------------

(define started-before (transfers-started))

;; --- a stalled name lookup: the stand-in, the child and the verdicts (ADR-0019) ----------

;; linux? : Boolean
;; Whether this Chez runs on Linux: its machine type ends in le, as ta6le
;; and tarm64le do. The stall checks need LD_PRELOAD, which macOS lacks
;; (ADR-0019, amended 2026-10-25).
(define linux?
  (let* ((m (symbol->string (machine-type))) (n (string-length m)))
    (and (> n 2) (string=? (substring m (- n 2) n) "le"))))

;; stall-ms : Positive-Integer
;; How long the stand-in stalls each lookup: well above every bound the
;; child judges by, 1000 and 2000 ms, so that a wait for the lookup looks
;; nothing like a prompt return.
(define stall-ms 3000)

;; stall-verdicts : (Listof (Pairof String (Listof Entry)))
;; Each recorded libcurl's verdicts, by version, measured (ADR-0019,
;; amended 2026-10-25). An Entry is (WITHOUT MULTI TRANSFER CANCEL OTHER
;; CANCEL-STOP TIMEOUT TIMEOUT-STOP STOP): the QUICK_EXIT setting the
;; child's engines leave out, none, transfer or multi; what
;; tests/engine-stall.sps must then print of the cancel engine's
;; CURLMOPT_QUICK_EXIT, set, unknown or off, and whether its transfers set
;; QUICK_EXIT, all four of them or none; then the verdict, prompt or
;; stalled, of the cancel, of the transfer beside it, of that engine's stop,
;; of a 500 ms timeout, of that engine's stop, and of a stop during the
;; lookup. A stop after an event that waited for the lookup comes after the
;; lookup, and is prompt.
;; With both settings kept, 7.87.0 on returns promptly, and the floor
;; stalls, the recorded limit. Each prompt row has a control that stalls:
;; 8.5.0 without each transfer's QUICK_EXIT; 8.20.0's three stops without
;; CURLMOPT_QUICK_EXIT. On 8.20.0 a transfer's QUICK_EXIT changes no stall,
;; so only the count holds it there. The floor knows neither option, so its switches
;; change nothing, and its row runs none alone.
(define stall-verdicts
  '(("7.85.0" (none unknown #f stalled stalled prompt stalled prompt stalled))
    ("8.5.0" (none unknown #t prompt prompt prompt prompt prompt prompt)
             (transfer unknown #f stalled stalled prompt stalled prompt stalled)
             (multi off #t prompt prompt prompt prompt prompt prompt))
    ("8.20.0" (none set #t prompt prompt prompt prompt prompt prompt)
              (transfer set #f prompt prompt prompt prompt prompt prompt)
              (multi off #t prompt prompt stalled prompt stalled stalled))
    ("8.23.0" (none set #t prompt prompt prompt prompt prompt prompt)
              (transfer set #f prompt prompt prompt prompt prompt prompt)
              (multi off #t prompt prompt stalled prompt stalled stalled))))

;; reuse-verdicts : (Listof (List String Outcome))
;; Each recorded libcurl's answer, by version, as reuse-outcome names it, to
;; one drip submitted the moment eight drips live together have ended, on
;; an engine of its own, the raw face having closed each of their
;; connections without saying so (ADR-0020, amended 2026-10-26). 7.85.0 to
;; 8.20.0 check an idle connection before reusing it, and drop the dead
;; ones. 8.23.0 checks one only when it went back to the pool, or was last
;; checked, 1 s or more before, however old it is: it reuses a dead one,
;; retries on the next as each dies, and after five retries gives up with
;; CURLE_SEND_ERROR, its error buffer saying so.
(define reuse-verdicts
  '(("7.85.0" (response 200 "abcd"))
    ("8.5.0" (response 200 "abcd"))
    ("8.20.0" (response 200 "abcd"))
    ("8.23.0" (transfer-error perform-failed 55 "Connection died, tried 5 times before giving up"))))

;; stall-expected : Entry -> (Listof Any)
;; All the child prints for ENTRY: each outcome as a transfer ends that way,
;; the three names stalled, and the counts zero.
(define (stall-expected entry)
  (let ((v (cdddr entry)))
    (list (list 'settings (cadr entry) (if (caddr entry) 4 0))
          (list 'cancel (list-ref v 0) '(transfer-error cancelled #f #f))
          (list 'other (list-ref v 1) '(response 200 "abcdefghij"))
          (list 'cancel-stop (list-ref v 2))
          (list 'timeout (list-ref v 3) '(transfer-error perform-failed 28 #f))
          (list 'timeout-stop (list-ref v 4))
          (list 'stop (list-ref v 5) '(transfer-error stopped #f #f))
          '(stalled "cancel.stall.invalid" "stop.stall.invalid" "timeout.stall.invalid")
          (list 'counts zero-counts))))

;; stall-entry-of : Symbol (Listof Any) -> (U Entry #f)
;; The Entry for WITHOUT that the child's printed DATA show, when they have
;; stall-expected's shape: for a libcurl with no row, the row it needs.
(define (stall-entry-of without data)
  (and (list? data) (= (length data) 9)
       (let ((entry (list without
                          (guard (e (#t #f)) (cadr (list-ref data 0)))
                          (guard (e (#t #f)) (eqv? (caddr (list-ref data 0)) 4))
                          (guard (e (#t #f)) (cadr (list-ref data 1)))
                          (guard (e (#t #f)) (cadr (list-ref data 2)))
                          (guard (e (#t #f)) (cadr (list-ref data 3)))
                          (guard (e (#t #f)) (cadr (list-ref data 4)))
                          (guard (e (#t #f)) (cadr (list-ref data 5)))
                          (guard (e (#t #f)) (cadr (list-ref data 6))))))
         (and (equal? (stall-expected entry) data) entry))))

;; stall-name : String Entry -> String
(define (stall-name version entry)
  (let ((v (cdddr entry)))
    (string-append
     "under the stand-in getaddrinfo, each lookup stalled " (number->string stall-ms)
     " ms, on libcurl " version ", engines "
     (case (car entry)
       ((none) "with both QUICK_EXIT settings")
       ((transfer) "without each transfer's QUICK_EXIT")
       (else "without CURLMOPT_QUICK_EXIT"))
     " (multi " (symbol->string (cadr entry)) ", transfer " (if (caddr entry) "set" "not set")
     "): the cancel is " (written (list-ref v 0)) ", the transfer beside it " (written (list-ref v 1))
     ", that engine's stop " (written (list-ref v 2)) ", a 500 ms timeout " (written (list-ref v 3))
     ", that engine's stop " (written (list-ref v 4)) " and a stop during the lookup " (written (list-ref v 5))
     "; every outcome whole, in a child bounded at 60 s, its counts zero")))

;; compile-stand-in : String -> (U String (List 'compile-failed Any))
;; tests/stall-getaddrinfo.c, compiled into DIR as a shared object: its
;; path, or what the compiler answered. Judged by exit status alone: Guix's
;; gcc warns on stderr at every link.
(define (compile-stand-in dir)
  (let* ((so (string-append dir "/stall-getaddrinfo.so"))
         (r (guard (e (#t (list 'raised (describe e) "")))
              (capture-command (append (c-compiler getenv)
                                       (list "-shared" "-fPIC" "-o" so "tests/stall-getaddrinfo.c" "-ldl"))))))
    (if (eqv? (car r) 0) so (list 'compile-failed r))))

;; run-stall-child : String String Symbol String -> (List Integer (Listof Any) String)
;; tests/engine-stall.sps WITHOUT URL, in a child Chez under child-script's
;; 60 s, with the stand-in at SO preloaded, stalling each name ending
;; .stall.invalid for stall-ms and logging to LOG: its exit status, what it
;; printed, read as data, and its stderr.
(define (run-stall-child so log without url)
  (guard (e (#t (list 'raised (describe e) "")))
    (let ((r (capture-command
              (list "sh" "-c" (child-script 60) "sh" "env"
                    (string-append "LD_PRELOAD=" so) "STALL_SUFFIX=.stall.invalid"
                    (string-append "STALL_MS=" (number->string stall-ms))
                    (string-append "STALL_LOG=" log)
                    (getenv "CHEZ") "--libdirs" (library-path)
                    "--program" "tests/engine-stall.sps" (symbol->string without) url))))
      (list (car r) (read-all (cadr r)) (caddr r)))))

;; linux? decides whether the stall checks run, so a wrong answer on Linux
;; would pass the suite with none run: it must agree with uname.
(test-equal "linux?, from Chez's machine type, agrees with uname -s: Linux, where the stall checks run, or another system, where none does"
  (let ((r (guard (e (#t (list 'raised (describe e) ""))) (capture-command '("uname" "-s")))))
    (list (car r) (if (equal? (cadr r) "Linux\n") 'linux 'other)))
  (list 0 (if linux? 'linux 'other)))

(test-equal "multi-quick-exit-verdict: CURLM_OK is set, CURLM_UNKNOWN_OPTION is unknown, and every other CURLMcode, -1 to 13, refuses the engine, #f"
  (list 'set 'unknown (make-list 13 #f))
  (list (multi-quick-exit-verdict 0) (multi-quick-exit-verdict 6)
        (map multi-quick-exit-verdict '(-1 1 2 3 4 5 7 8 9 10 11 12 13))))

;; answered : Integer -> Any
;; What make-curl-engine-answering-quick-exit CODE does: (running VERDICT),
;; the engine's CURLMOPT_QUICK_EXIT, once it is stopped again; or the
;; refusal it raised, (engine-error REASON MESSAGE CODE), from the condition
;; it carries.
(define (answered code)
  (guard (e ((curl-engine-error? e)
             (let ((c (curl-engine-error-condition e)))
               (list 'engine-error (curl-engine-error-reason e)
                     (and (message-condition? c) (condition-message c))
                     (and (irritants-condition? c) (pair? (condition-irritants c))
                          (car (condition-irritants c))))))
            (#t (list 'raised (describe e))))
    (let* ((e (make-curl-engine-answering-quick-exit code))
           (verdict (curl-engine-quick-exit e)))
      (stop-within e)
      (list 'running verdict))))

;; The refusal no libcurl gives (ADR-0019, decision 2): every recorded one
;; answers CURLMOPT_QUICK_EXIT with CURLM_OK or CURLM_UNKNOWN_OPTION.
(test-equal "an answer to CURLMOPT_QUICK_EXIT but CURLM_OK or CURLM_UNKNOWN_OPTION refuses the engine: make-curl-engine raises &curl-engine-error, reason failed, carrying curl_multi_setopt's code, for CURLM_BAD_HANDLE, 1, and CURLM_BAD_FUNCTION_ARGUMENT, 10, its multi handle and slot freed; given 0 or 6 it runs, set or unknown"
  (list '(engine-error failed "curl_multi_setopt answered a CURLMcode" 1)
        '(engine-error failed "curl_multi_setopt answered a CURLMcode" 10)
        '(running set) '(running unknown) running-counts)
  (let* ((one (answered 1)) (ten (answered 10)) (ok (answered 0)) (unknown (answered 6)))
    (list one ten ok unknown (native-counts))))

(test-equal "make-curl-engine-without-quick-exit refuses anything but a list of transfer and multi, an assertion violation from its name, before any engine is made"
  (list (make-list 4 '(assertion-violation make-curl-engine-without-quick-exit)) running-counts)
  (list (map (lambda (without) (outcome (lambda () (make-curl-engine-without-quick-exit without))))
             (list '(bogus) 'transfer '(transfer . multi) '(multi "transfer")))
        (native-counts)))

(call-with-origin
 (lambda (o)
   (define status (url-of o 'http "/status/200"))
   (define (drip bytes gap)
     (url-of o 'raw (string-append "/raw/drip?bytes=" (number->string bytes)
                                   "&gap=" (number->string gap))))

   ;; --- concurrency ---------------------------------------------------------------------

   (test-equal "a /status/200 submitted and awaited answers its response, its one chunk logged on the engine's thread"
     (list '(response 200 "status 200\n")
           (list (list (string-length "status 200\n") (curl-engine-thread engine) 'accepted)))
     (let ((t (curl-engine-submit engine (request status))))
       (list (awaited t) (curl-token-chunks t))))

   ;; Eight drips of 400 ms each, submitted together: overlapping, they end
   ;; in far less than eight times one, and every chunk ran on the engine's
   ;; thread. On an engine of their own: the raw face closes each drip's
   ;; connection unannounced, and libcurl 8.23.0 reuses, without checking
   ;; it, a connection that went back to its pool under 1 s before
   ;; (reuse-verdicts, below), so eight dead in the suite's engine's pool
   ;; would fail its next raw transfer.
   (let ((eight (on-own-engine
                 (lambda (own)
                   (let* ((one-ms (let ((t0 (now-ms)))
                                    (awaited (curl-engine-submit own (request (drip 40 10))))
                                    (- (now-ms) t0)))
                          (t0 (now-ms))
                          (tokens (map (lambda (i) (curl-engine-submit own (request (drip 40 10)))) (iota 8)))
                          (answers (map awaited tokens))
                          (all-ms (- (now-ms) t0))
                          (chunks (apply append (map curl-token-chunks tokens))))
                     (list answers
                           (for-all (lambda (c) (and (eqv? (cadr c) (curl-engine-thread own))
                                                     (eq? (caddr c) 'accepted)))
                                    chunks)
                           (if (< all-ms (* 3 one-ms)) 'under-three-times-one (list all-ms 'against one-ms))
                           (> (length chunks) 8)))))))
     (test-equal "eight drips on one engine each answer whole, and every chunk of theirs ran on the engine's thread, accepted"
       (list (make-list 8 (list 'response 200 (drip-body 40))) #t)
       (if (= (length eight) 4) (list (car eight) (cadr eight)) eight))
     (test-equal "the eight drips overlapped: together they took under three times one alone, where one after another would take eight"
       (list 'under-three-times-one #t)
       (if (= (length eight) 4) (list (caddr eight) (cadddr eight)) eight)))

   ;; Two caller threads, each awaiting its own transfer and one they share,
   ;; on an engine of their own, whose pool no other check has filled.
   ;; Whatever a thread raises is its answer, as (on-thread OUTCOME), and the
   ;; wait for both is bounded: a raise that escaped a thread once left this
   ;; wait hanging, and a hang names no test. Each thread's awaits end within
   ;; 40 s, so the bound is theirs.
   (test-equal "two caller threads awaiting together each get their own answer and the shared one, eq? to this thread's, and each await returns on the thread that awaited"
     (list (list '(response 200 "status 200\n") (list 'response 200 (drip-body 30)) #t #t)
           (list (list 'response 200 (drip-body 20)) (list 'response 200 (drip-body 30)) #t #t)
           #t)
     (on-own-engine
      (lambda (own-engine)
        (let* ((shared (curl-engine-submit own-engine (request (drip 30 10))))
               (mx (make-mutex)) (results '()))
          (for-each
           (lambda (i target)
             (fork-thread
              (lambda ()
                (let ((r (guard (e (#t (list i (list 'on-thread (outcome (lambda () (raise e)))) #f)))
                           (let* ((me (get-thread-id))
                                  (own (awaited (curl-engine-submit own-engine (request target))))
                                  (theirs (await-bounded shared 20000))
                                  (after (get-thread-id)))
                             (list i (list own (outcome (lambda () theirs))
                                           (eqv? me after)
                                           (not (eqv? after (curl-engine-thread own-engine))))
                                   theirs)))))
                  (with-mutex mx (set! results (cons r results)))))))
           '(0 1) (list status (drip 20 10)))
          (let* ((both (let ((deadline (+ (now-ms) 45000)))
                         (let w ()
                           (cond ((with-mutex mx (= (length results) 2)) #t)
                                 ((> (now-ms) deadline) #f)
                                 (else (pause-ms 1) (w))))))
                 (mine (guard (e (#t (list 'raised (describe e)))) (await-bounded shared 20000))))
            (if both
                (list (cadr (assv 0 results)) (cadr (assv 1 results))
                      (for-all (lambda (r) (eq? (caddr r) mine)) results))
                (list 'unanswered-within-45-s (with-mutex mx (map cadr results)))))))))

   ;; --- a dead pooled connection (ADR-0020, amended 2026-10-26) ------------------------------

   ;; The raw face closes after each script and never says so, so each
   ;; drip's connection goes back to the pool dead. Eight drips live
   ;; together hold eight connections, and leave eight; one more at once
   ;; shows how this libcurl picks from its pool. Each libcurl's answer is
   ;; its row of reuse-verdicts, and one with no row prints the row it would
   ;; need. On an engine of its own, whose pool starts empty. The drips last
   ;; about 200 ms, so they overlap unless their submits spread past that:
   ;; then they would share connections, and leave fewer dead (the review's
   ;; measurements, .plans/research/reuse/results). The check asserts that
   ;; all eight were live together, by the engine's live count.
   (let ((row (and (string? version) (assoc version reuse-verdicts)))
         (measured
          (on-own-engine
           (lambda (own)
             (let* ((tokens (map (lambda (i) (curl-engine-submit own (request (drip 4 50)))) (iota 8)))
                    (most-live (let watch ((most 0) (deadline (+ (now-ms) 20000)))
                                 (if (or (for-all curl-token-done? tokens) (> (now-ms) deadline))
                                     most
                                     (begin (pause-ms 1)
                                            (watch (max most (curl-engine-live-count own)) deadline)))))
                    (answers (map awaited tokens)))
               (list answers
                     (if (= most-live 8) 'live-together (list 'most-live-together most-live))
                     (reuse-outcome (curl-engine-submit own (request (drip 4 50))))))))))
     (test-equal (string-append "the reuse verdicts have a row for this libcurl, " (written version))
       (list version)
       (if row (list (car row)) (list 'no-row version)))
     (test-equal (string-append "on an engine of its own, eight 4-byte drips live together each answer whole, and one more at once, past eight connections the raw face closed unannounced, answers as "
                                (written version) "'s row of reuse-verdicts says")
       (list (make-list 8 (list 'response 200 (drip-body 4))) 'live-together
             (if row (cadr row) (list 'no-row version)))
       measured)
     (unless row
       (display "test-engine: no row of reuse-verdicts for this libcurl; measured, it would be:\n"
                (current-error-port))
       (write (list version (if (and (list? measured) (= (length measured) 3)) (caddr measured) measured))
              (current-error-port))
       (newline (current-error-port))))

   ;; --- submit ----------------------------------------------------------------------------

   (for-each
    (lambda (row)
      (test-equal (string-append "a submit refuses " (car row) " before anything is queued: "
                                 (written (cadr row)) ", nothing queued, live or started, the counts zero")
        (list (cadr row) running-counts 0 0 0)
        (refused-at-submit (caddr row) (cadddr row))))
    (list
     (list "a header name changed after the request was made, to hold a space"
           '(request-refused header-name not-a-token)
           (lambda () (let ((name (string-copy "X-A")))
                        (let ((r (request status 'headers (list (cons name "v")))))
                          (string-set! name 1 #\space)
                          r)))
           '())
     (list "a URL changed after the request was made, to hold U+0000"
           '(url-refused embedded-nul)
           (lambda () (let* ((url (string-copy status)) (r (request url)))
                        (string-set! url (- (string-length url) 1) #\nul)
                        r))
           '())
     (list "a URL whose scheme is not http or https"
           '(url-refused scheme-not-http)
           (lambda () (request "ftp://127.0.0.1/x"))
           '())
     (list "a CA file's path changed after the request was made, to hold U+0000"
           '(request-refused ca-file embedded-nul)
           (lambda () (let* ((path (string-copy "/tmp/ca.pem")) (r (request status 'ca-file path)))
                        (string-set! path 3 #\nul)
                        r))
           '())
     (list "the test seam's option this libcurl does not know"
           '(transfer-error unknown-option #f #f)
           (lambda () (request status))
           '(("NO_SUCH_OPTION_EVER" . 1)))
     (list "the test seam's owned option, URL"
           '(request-refused options owned-option)
           (lambda () (request status))
           '(("URL" . 1)))
     (list "the test seam's string option, COOKIE"
           '(request-refused options unsupported-type)
           (lambda () (request status))
           '(("COOKIE" . 1)))
     (list "what is not a request"
           '(assertion-violation curl-engine-submit)
           (lambda () 'not-a-request)
           '())))

   (test-equal "after every refusal the engine still runs, and its next transfer answers"
     (list 'running '(response 200 "status 200\n"))
     (list (curl-engine-state engine) (awaited (curl-engine-submit engine (request status)))))

   ;; --- cancel ----------------------------------------------------------------------------

   (test-equal "a cancel of a token still queued completes it as cancelled, on this thread, with nothing started and no chunk"
     (list '(transfer-error cancelled #f #f) '() 0 running-counts)
     (let* ((started (transfers-started))
            (t (call-with-engine-held engine
                 (lambda ()
                   (let ((t (curl-engine-submit engine (request status))))
                     (curl-token-cancel t)
                     t)))))
       (let ((answer (awaited t)))
         ;; One transfer after it, so the engine has taken the queue.
         (awaited (curl-engine-submit engine (request status)))
         (list answer (curl-token-chunks t) (- (transfers-started) started 1) (native-counts)))))

   (test-equal "a cancel of a live drip completes it as cancelled, with the chunks it had accepted, and the engine's table empty after"
     (list '(transfer-error cancelled #f #f) #t 0 running-counts)
     (let ((t (curl-engine-submit engine (request (drip 200 5)))))
       (pause-ms 200)
       (curl-token-cancel t)
       (let ((answer (awaited t)))
         (list answer
               (let ((chunks (curl-token-chunks t)))
                 (and (pair? chunks) (< (length chunks) 200)
                      (for-all (lambda (c) (eq? (caddr c) 'accepted)) chunks)))
               (curl-engine-live-count engine) (native-counts)))))

   (test-equal "a cancel of a done token leaves its outcome: await again answers the same response, eq?"
     (list '(response 200 "status 200\n") #t)
     (let* ((t (curl-engine-submit engine (request status)))
            (first (await-bounded t 20000)))
       (curl-token-cancel t)
       (list (outcome (lambda () first)) (eq? first (await-bounded t 20000)))))

   (test-equal "a cancel racing a completion, 60 times at growing delays, ends each as the response or cancelled, and nothing else, with the counts zero"
     (list '() running-counts 0)
     (let loop ((i 0) (strays '()))
       (if (= i 60)
           (list strays (native-counts) (curl-engine-live-count engine))
           (let ((t (curl-engine-submit engine (request status))))
             (pause-ms (div i 6))
             (curl-token-cancel t)
             (let ((a (awaited t)))
               (loop (+ i 1)
                     (if (member a '((response 200 "status 200\n") (transfer-error cancelled #f #f)))
                         strays
                         (cons a strays))))))))

   ;; A live token cancelled twice queues two messages: the second finds it
   ;; done, and must leave it so.
   (test-equal "a live drip cancelled twice while the engine is held: the first cancel ends it as cancelled, the second, finding it done, is counted stale and changes nothing"
     (list '(transfer-error cancelled #f #f) 1 0 running-counts)
     (let* ((t (curl-engine-submit engine (request (drip 100 10))))
            (stale (begin (pause-ms 150) (curl-engine-stale-cancels engine))))
       (call-with-engine-held engine
         (lambda () (curl-token-cancel t) (curl-token-cancel t)))
       (let ((answer (awaited-within t 10000)))
         ;; One transfer after it, so the engine has carried out both.
         (awaited (curl-engine-submit engine (request status)))
         (list answer (- (curl-engine-stale-cancels engine) stale)
               (curl-engine-live-count engine) (native-counts)))))

   ;; A token's first outcome stands: one cancelled while queued keeps it
   ;; through the stop that takes its submit.
   (test-equal "a token cancelled while queued, then stopped in the same batch, stays cancelled, and was never started"
     (list '(transfer-error cancelled #f #f) 0 'stopped)
     (let* ((stopping (make-curl-engine))
            (started (transfers-started))
            (t (call-with-engine-held stopping
                 (lambda ()
                   (let ((t (curl-engine-submit stopping (request status))))
                     (curl-token-cancel t)
                     (curl-engine-request-stop! stopping)
                     t)))))
       (stop-within stopping)
       (list (awaited-within t 10000) (- (transfers-started) started) (curl-engine-state stopping))))

   (test-equal "a submit while the engine is stopping is refused as stopped, and the stop then ends with nothing left"
     (list '(engine-error stopped #f) 'stopped running-counts)
     (let* ((stopping (make-curl-engine))
            (refused (call-with-engine-held stopping
                       (lambda ()
                         (curl-engine-request-stop! stopping)
                         (outcome (lambda () (curl-engine-submit stopping (request status))))))))
       (stop-within stopping)
       (list refused (curl-engine-state stopping) (native-counts))))

   ;; A cancel and a stop wake the engine: a drip 2 s between bytes leaves
   ;; libcurl's poll waiting its whole 1000 ms otherwise.
   (test-equal "a cancel of a drip idle between bytes ends it within 300 ms, and a stop of an engine holding one returns within 300 ms: each wakes the poll"
     (list '(transfer-error cancelled #f #f) 'within-bound 'within-bound)
     (let* ((t (curl-engine-submit engine (request (drip 3 2000))))
            (t0 (begin (pause-ms 300) (now-ms))))
       (curl-token-cancel t)
       (let* ((answer (awaited-within t 10000))
              (cancel-ms (- (now-ms) t0))
              (stopping (make-curl-engine))
              (s (curl-engine-submit stopping (request (drip 3 2000))))
              (t1 (begin (pause-ms 300) (now-ms)))
              (stop-ms (begin (stop-within stopping) (- (now-ms) t1))))
         (awaited-within s 10000)
         (list answer (if (< cancel-ms 300) 'within-bound cancel-ms)
               (if (< stop-ms 300) 'within-bound stop-ms)))))

   ;; --- a raise inside the loop (section 3.7) ---------------------------------------------

   ;; Each step: what reaches it, the token's outcome, the engine's state, a
   ;; later submit's, a stop's time, and the counts.
   (for-each
    (lambda (step)
      (test-equal (string-append "a fault planted at the loop's " (symbol->string step)
                                 " step fails the engine: its transfer completes as &curl-engine-error failed, carrying the fault; a later submit raises the same; stop returns at once; the table and counts are empty")
        (list (list 'engine-error 'failed (planted-engine-fault step))
              'failed
              (list 'engine-error 'failed (planted-engine-fault step))
              'at-once 0 #f running-counts)
        (let* ((faulty (make-faulty-curl-engine step))
               (t (curl-engine-submit faulty (request (if (memq step '(cancel poll)) (drip 100 10) status)))))
          (when (eq? step 'cancel)
            (pause-ms 100)
            (curl-token-cancel t))
          ;; The first stop waits for the engine's thread to end its
          ;; cleanup; the second must return at once.
          (let* ((answer (awaited-within t 10000))
                 (later (outcome (lambda () (curl-engine-submit faulty (request status)))))
                 (state (begin (stop-within faulty) (curl-engine-state faulty)))
                 (t0 (now-ms)))
            (stop-within faulty)
            (list answer state later (if (< (- (now-ms) t0) 50) 'at-once (- (now-ms) t0))
                  (curl-engine-live-count faulty) (curl-engine-multi faulty) (native-counts))))))
    (remq 'start engine-fault-steps))

   (test-equal "a fault planted at the engine's start fails it before its multi handle is made: make-faulty-curl-engine raises &curl-engine-error failed, carrying the fault, and nothing is left"
     (list (list 'engine-error 'failed (planted-engine-fault 'start)) running-counts)
     (let ((answer (outcome (lambda () (make-faulty-curl-engine 'start)))))
       (list answer (native-counts))))

   (test-equal "a fault at cancel with two transfers live and one set up in the same turn fails all three"
     (make-list 3 (list 'engine-error 'failed (planted-engine-fault 'cancel)))
     (let* ((faulty (make-faulty-curl-engine 'cancel))
            (a (curl-engine-submit faulty (request (drip 100 10))))
            (b (curl-engine-submit faulty (request (drip 100 10)))))
       (pause-ms 100)
       (let ((c (call-with-engine-held faulty
                  (lambda ()
                    (curl-token-cancel a)
                    (curl-engine-submit faulty (request status))))))
         (let ((answers (map (lambda (t) (awaited-within t 10000)) (list a b c))))
           (stop-within faulty)
           answers))))

   ;; Sixty live transfers make the failed engine's cleanup long enough to
   ;; see, and the state and counts are read on the stopping thread the
   ;; moment curl-engine-stop returns: a stop that returned before the
   ;; cleanup ended would read their counts.
   (test-equal "a fault while sixty transfers are live: the stop returns only once the engine's thread has freed them all, so its state is failed, and its table, its multi handle and the counts are empty, the moment it returns"
     (list 'failed 0 #f running-counts)
     (let* ((faulty (make-faulty-curl-engine 'cancel))
            (tokens (map (lambda (i) (curl-engine-submit faulty (request (drip 100 10)))) (iota 60))))
       (pause-ms 300)
       (curl-token-cancel (car tokens))
       (let ((after (stop-within faulty
                      (lambda ()
                        (list (curl-engine-state faulty) (curl-engine-live-count faulty)
                              (curl-engine-multi faulty) (native-counts))))))
         (for-each (lambda (t) (awaited-within t 10000)) tokens)
         after)))

   ;; --- stop ------------------------------------------------------------------------------

   (let* ((stopping (make-curl-engine))
          (live (map (lambda (i) (curl-engine-submit stopping (request (drip 100 10)))) '(0 1)))
          (started-live (begin (pause-ms 150) (transfers-started)))
          (queued (call-with-engine-held stopping
                    (lambda ()
                      (let ((q (map (lambda (i) (curl-engine-submit stopping (request status))) '(0 1))))
                        (curl-engine-request-stop! stopping)
                        q))))
          (stop-answer (guard (e (#t (list 'stop-raised e))) (stop-within stopping) 'returned)))
     (test-equal "a stop completes each live transfer as stopped, with the chunks it had, and each queued one as stopped, never started"
       (list (make-list 2 '(transfer-error stopped #f #f)) '(#t #t)
             (make-list 2 '(transfer-error stopped #f #f)) '(() ()) 0)
       (list (map (lambda (t) (awaited-within t 10000)) live)
             (map (lambda (t) (pair? (curl-token-chunks t))) live)
             (map (lambda (t) (awaited-within t 10000)) queued) (map curl-token-chunks queued)
             (- (transfers-started) started-live)))
     (test-equal "after a stop the engine is stopped, its table empty and its multi handle freed, a submit refused as stopped, and a second stop returns at once"
       (list 'returned 'stopped 0 #f '(engine-error stopped #f) 'at-once running-counts)
       (list stop-answer (curl-engine-state stopping) (curl-engine-live-count stopping)
             (curl-engine-multi stopping)
             (outcome (lambda () (curl-engine-submit stopping (request status))))
             (let ((t0 (now-ms))) (stop-within stopping)
               (if (< (- (now-ms) t0) 50) 'at-once (- (now-ms) t0)))
             (native-counts))))

   ;; --- the children ------------------------------------------------------------------------

   ;; The collection bound (section 3.2; ADR-0013, amended 2026-10-25): a
   ;; worker's 20 collections, back to back, beside an idle engine, and
   ;; beside a caller awaiting a slow transfer. A plain poll would hold each
   ;; up to about 500 polls of 1000 ms, and a wait that sleeps in a critical
   ;; section would hold it for good: so 20 must end within 500 ms.
   (for-each
    (lambda (mode)
      (test-equal (string-append "beside " (if (eq? mode 'idle) "an idle engine" "a caller awaiting a 1 s drip")
                                 ", a worker's 20 collections, back to back, end within 500 ms, in a child bounded at 60 s, whose counts are zero")
        (list 0 (list 'collections mode 'within-bound) (list 'counts zero-counts) "")
        (let ((r (run-child 60 "tests/engine-collect.sps" (symbol->string mode) (drip 10 100))))
          (if (and (pair? r) (= (length r) 3) (list? (cadr r)) (= (length (cadr r)) 2))
              (let ((c (car (cadr r))))
                (list (car r)
                      (if (and (list? c) (= (length c) 3) (number? (caddr c)) (< (caddr c) 500))
                          (list 'collections mode 'within-bound)
                          c)
                      (cadr (cadr r)) (caddr r)))
              r))))
    '(idle await))

   ;; Several awaiters at once, while collections run (ADR-0013, amended
   ;; 2026-10-25): a wait that held the engine's mutex deadlocked here within
   ;; 1 s, 3 runs of 3.
   (test-equal "four caller threads, each submitting and awaiting /status/200 for 2 s while their allocation collects, have hundreds of 200s, with collections among them, and end, in a child bounded at 60 s, whose counts are zero"
     (list 0 '(awaiters 4 hundreds collecting) (list 'counts zero-counts) "")
     (let ((r (run-child 60 "tests/engine-awaiters.sps" "together" "4" "2000" status)))
       (if (and (pair? r) (= (length r) 3) (list? (cadr r)) (= (length (cadr r)) 2))
           (let ((a (car (cadr r))))
             (list (car r)
                   (if (and (list? a) (= (length a) 4) (number? (caddr a)) (>= (caddr a) 100)
                            (number? (cadddr a)) (> (cadddr a) 0))
                       '(awaiters 4 hundreds collecting)
                       a)
                   (cadr (cadr r)) (caddr r)))
           r)))

   ;; The polling's cap (ADR-0013, amended 2026-10-25): a waiter wakes
   ;; within its current sleep, 10 ms at most, of its token's completion. A
   ;; watcher polling every 1 ms sees each completion; the await's return
   ;; must follow it within 30 ms, on five drips of 500 ms, each long
   ;; enough for the sleeps to reach their cap.
   (test-equal "five 500 ms drips awaited through curl-token-await each return within 30 ms of a watcher seeing them done: the polling's sleeps reach 10 ms and no more; in a child bounded at 60 s, its counts zero"
     (list 0 '(wake 5 within-cap) (list 'counts zero-counts) "")
     (let ((r (run-child 60 "tests/engine-awaiters.sps" "wake" "5" "0" (drip 5 100))))
       (if (and (pair? r) (= (length r) 3) (list? (cadr r)) (= (length (cadr r)) 2))
           (let ((a (car (cadr r))))
             (list (car r)
                   (if (and (list? a) (= (length a) 3) (number? (caddr a)) (< (caddr a) 30))
                       '(wake 5 within-cap)
                       a)
                   (cadr (cadr r)) (caddr r)))
           r)))

   ;; A wait with interrupts off would sleep with its thread active, and
   ;; deadlock with a collection the engine's thread joins: so it is refused
   ;; before it starts.
   (test-equal "an await, a stop and a make-curl-engine, each inside critical-section, are each refused before they start, as assertion violations from their own names, in a child bounded at 60 s, its counts zero"
     (list 0 '(critical curl-token-await curl-engine-stop make-curl-engine) (list 'counts zero-counts) "")
     (let ((r (run-child 60 "tests/engine-awaiters.sps" "critical" "1" "0" (drip 5 100))))
       (if (and (pair? r) (= (length r) 3) (list? (cadr r)))
           (list (car r) (if (pair? (cadr r)) (car (cadr r)) (cadr r))
                 (if (and (pair? (cadr r)) (pair? (cdr (cadr r)))) (cadr (cadr r)) 'none)
                 (caddr r))
           r)))

   ;; A completion wakes its awaiter at once: twenty awaits one after
   ;; another, through curl-token-await itself, in a child. A wait that woke
   ;; only every 100 ms would take about 2 s.
   (test-equal "twenty transfers submitted and awaited one after another, in a child bounded at 60 s, each wake their awaiter at once: all twenty within 1000 ms, and the counts zero"
     (list 0 '(latency 20 within-bound) (list 'counts zero-counts) "")
     (let ((r (run-child 60 "tests/engine-awaiters.sps" "latency" "20" "0" status)))
       (if (and (pair? r) (= (length r) 3) (list? (cadr r)) (= (length (cadr r)) 2))
           (let ((a (car (cadr r))))
             (list (car r)
                   (if (and (list? a) (= (length a) 3) (number? (caddr a)) (< (caddr a) 1000))
                       '(latency 20 within-bound)
                       a)
                   (cadr (cadr r)) (caddr r)))
           r)))

   ;; A wait sleeps between its reads, holding nothing: it does not spin.
   ;; cpu-time counts the whole process, the engine's thread too, which a
   ;; drip of a byte every 100 ms barely wakes.
   (test-equal "a child awaiting a 2 s drip through curl-token-await spends under 2% of the wait on the CPU: the waiter sleeps between its reads, waking at most 100 times a second; its counts zero"
     (list 0 '(cpu sleeping) (list 'counts zero-counts) "")
     (let ((r (run-child 60 "tests/engine-awaiters.sps" "cpu" "1" "0" (drip 20 100))))
       (if (and (pair? r) (= (length r) 3) (list? (cadr r)) (= (length (cadr r)) 2))
           (let ((a (car (cadr r))))
             (list (car r)
                   (if (and (list? a) (= (length a) 3) (number? (cadr a)) (number? (caddr a))
                            (> (caddr a) 1500) (< (* 50 (cadr a)) (caddr a)))
                       '(cpu sleeping)
                       a)
                   (cadr (cadr r)) (caddr r)))
           r)))

   ;; A stalled name lookup (ADR-0019, amended 2026-10-25): the stand-in,
   ;; compiled here, then tests/engine-stall.sps under it for each entry of
   ;; this libcurl's row of stall-verdicts. A libcurl with no row runs all
   ;; three, fails by name, and prints the row it would need. On macOS,
   ;; which has no LD_PRELOAD, nothing runs, and the suite says so.
   (if (not linux?)
       (begin
         (display "test-engine: the stalled-lookup checks run on Linux alone, so none ran here (ADR-0019, amended 2026-10-25)")
         (newline))
       (call-with-temp-directory
        (lambda (dir)
          (let ((so (compile-stand-in dir))
                (row (and (string? version) (assoc version stall-verdicts))))
            (test-equal "tests/stall-getaddrinfo.c compiles with $CC as a shared object, for LD_PRELOAD"
              (string-append dir "/stall-getaddrinfo.so")
              so)
            (test-equal (string-append "the stall verdicts have a row for this libcurl, " (written version))
              (list version)
              (if row (list (car row)) (list 'no-row version)))
            (if row
                (for-each
                 (lambda (entry)
                   (test-equal (stall-name version entry)
                     (list 0 (stall-expected entry) "")
                     (if (string? so)
                         (run-stall-child so (string-append dir "/" (symbol->string (car entry)) ".log")
                                          (car entry) (drip 10 100))
                         (list 'no-stand-in so))))
                 (cdr row))
                (when (string? so)
                  (let ((measured
                         (map (lambda (without)
                                (let ((r (run-stall-child so (string-append dir "/" (symbol->string without) ".log")
                                                          without (drip 10 100))))
                                  (or (and (eqv? (car r) 0) (equal? (caddr r) "")
                                           (stall-entry-of without (cadr r)))
                                      (list without 'unreadable r))))
                              '(none transfer multi))))
                    (display "test-engine: no row of stall-verdicts for this libcurl; measured, it would be:\n"
                             (current-error-port))
                    (write (cons version measured) (current-error-port))
                    (newline (current-error-port)))))))))

   ;; Ctrl-C (section 3.4): the child's main thread awaits a 2 s drip, and
   ;; gets SIGINT 500 ms after it says it is ready. Its handler must run
   ;; within one wait of the signal, long before the drip ends: a wait that
   ;; answers Ctrl-C only when it ends runs it at about 2000 ms.
   (test-equal "a caller awaiting a 2 s drip answers SIGINT, sent about 500 ms in, by 1000 ms, its await then answers the drip, and its counts are zero"
     (list 0 '(interrupt within-bound (response 200)) (list 'counts zero-counts) "")
     (let ((r (run-interrupt-child (drip 20 100))))
       (if (and (pair? r) (= (length r) 3) (list? (cadr r)) (= (length (cadr r)) 2))
           (let ((i (car (cadr r))))
             (list (car r)
                   (if (and (list? i) (= (length i) 4) (number? (cadr i)) (number? (caddr i))
                            (<= 450 (cadr i) 1000) (> (caddr i) 1500)
                            (equal? (cadddr i) '(response 200)))
                       '(interrupt within-bound (response 200))
                       i)
                   (cadr (cadr r)) (caddr r)))
           r)))))

(test-equal "the suite's engine stops, and every count is zero after"
  (list 'stopped 0 zero-counts 0)
  (if engine-made?
      (begin (stop-within engine)
             (list (curl-engine-state engine) (curl-engine-live-count engine) (native-counts)
                   (live-transfer-count)))
      engine))

(test-end "engine")

(exit (suite-exit-status runner))
