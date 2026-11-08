#!r6rs
;;; The suite for a call's checks and steps, their critical sections
;;; (ADR-0025, amended 2026-11-05, and after the branch's review):
;;; (http-client)'s call-state, which every entry reaches, http-request,
;;; call-with-response-port, a group's go and http-parallel, runs its
;;; checks in one critical section, its guard inside it, each raise there
;;; answered as data and raised once the section has ended. At each entry:
;;;
;;;   - Ctrl-C, in a child: the checks blocked at their start, through the
;;;     private gate, on a mutex another thread holds until the suite has
;;;     sent SIGINT, so the keyboard interrupt is made pending inside the
;;;     section (traps.md). A handler's own &curl-error leaves as raised,
;;;     that very object, not compounded with &http-exchange, the handler
;;;     run after the checks' end, nothing submitted; a continuable
;;;     &warning the caller's handler returns from resumes the call, which
;;;     answers 200. The guard around the checks with interrupts on
;;;     compounded the first and turned the second &non-continuable;
;;;   - a timer, set to 1 tick at the checks' start: the same two, in
;;;     process. A timer cannot show where a guard sits relative to the
;;;     section, whose end a timer never meets (traps.md): the Ctrl-C
;;;     children hold that;
;;;   - a Chez engine's expiry, swept a tick at a time from fuel 1 until
;;;     the first expiry seen after the checks' end: none lands between the
;;;     checks' start and end, no resumed call raises (curl)'s refusal to
;;;     re-enter a URL's parse, and the sweep's evidence, an expiry before
;;;     the start at the fuel just before the first after the end;
;;;   - a refusal the checks make, the high level's, make-curl-request's,
;;;     and curl-request-check's for http-parallel: compounded with
;;;     &http-exchange, raised once the section has ended, so the caller's
;;;     handler runs with interrupts on.
;;;
;;; A redirect's step, whose follow parses URLs through (curl)'s critical
;;; winds, runs in a critical section of its own too, at every entry (as
;;; amended after the branch's review, research/m7/carried/review, M1):
;;; the same Ctrl-C children and timers at the first step's start, through
;;; the step gate; an engine's expiry swept a tick at a time across the
;;; first step, none landing inside a step and no resumed call raising
;;; (curl)'s refusal to re-enter a parse; a timer set 1 to 300 ticks past
;;; the step's start whose handler raises continuably, every call resuming;
;;; and a raise made inside the step, through the gate, leaving with
;;; interrupts on. A group's step ran in its turn's section before, and
;;; passes as it did. A direct caller's curl-submit through a proxy URL
;;; parses its URLs in sections of their own (m1): swept by an engine and
;;; by a timer, a tick at a time, no submit raises a re-entry refusal. And
;;; a URL past libcurl's 8,000,000-byte cap is refused at the checks'
;;; start (M2): as libcurl refuses it, malformed-input, before the keys,
;;; and in under a tenth of the time a URL at the cap takes to reach
;;; libcurl's own refusal.
;;;
;;; Every wait here is bounded: a child by its script's 60 s, the suite's
;;; calls by their sessions' timeout-ms. Every expected value is one the
;;; code under test cannot produce by failing: SRFI-64 makes #f of a raise
;;; in the actual expression, so none is #f.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) sleep make-time current-time time-second time-nanosecond getenv
              library-directories set-timer timer-interrupt-handler make-engine)
        (curl-testing)
        (curl)
        (http-client)
        (only (http-client private drive) drive-checks-gate-set! drive-step-gate-set!)
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

(test-begin "call-checks")

;; --- helpers --------------------------------------------------------------------------

(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)))

;; entries : (Listof Symbol)
;; The four entries that reach call-state.
(define entries '(request port go parallel))

;; in-order : (Any -> Any) (Listof Any) -> (Listof Any)
;; PROC of each of ITEMS, first to last: map calls its procedure in no
;; fixed order (traps.md).
(define (in-order proc items)
  (let loop ((rest items) (answers '()))
    (if (null? rest)
        (reverse answers)
        (let ((answer (proc (car rest))))
          (loop (cdr rest) (cons answer answers))))))

;; take-up-to : List Natural -> List
;; LIST's first N elements, or all of them.
(define (take-up-to list n)
  (if (or (null? list) (= n 0)) '() (cons (car list) (take-up-to (cdr list) (- n 1)))))

;; call-of : Symbol Session String -> (-> Any)
;; A get of URL by ENTRY on SESSION, answering its status: request,
;; http-request; port, call-with-response-port, its body read to its end;
;; go, a group's go, then its await; parallel, http-parallel of one spec.
(define (call-of entry session url)
  (case entry
    ((request) (lambda () (http-response-status (http-get session url))))
    ((port)
     (lambda ()
       (call-with-response-port session 'get url
         (lambda (r p)
           (let loop ()
             (unless (eof-object? (get-bytevector-some p)) (loop)))
           (http-response-status r)))))
    ((go)
     (lambda ()
       (call-with-request-group session
         (lambda (go) (http-response-status (http-await (go 'get url)))))))
    ((parallel)
     (lambda () (car (map http-response-status (http-parallel session (list (list 'get url)))))))
    (else (lambda () (assertion-violation 'call-of "no entry" entry)))))

;; re-entry? : Any -> Boolean
;; Whether E is (curl)'s refusal to re-enter a URL's parse: an assertion
;; violation whose who is call-with-parsed-url.
(define (re-entry? e)
  (and (condition? e) (assertion-violation? e) (who-condition? e)
       (eq? (condition-who e) 'call-with-parsed-url)))

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
;; CHECKS_CHILD_SENT names, made once the kill has returned, which lets the
;; child's holder go (child-hold); then its exit status, and its output but
;; the ready line. Exit 125 with no timeout, 126 when the child never says
;; it is ready, within 20 s.
(define interrupt-script
  (string-append
   "t=$(command -v timeout || command -v gtimeout) || { echo 'checks child: no timeout' >&2; exit 125; }\n"
   "out=$(mktemp \"${TMPDIR:-/tmp}/checks-child.XXXXXX\") || exit 125\n"
   "CHECKS_CHILD_SENT=\"$out.sent\" \"$t\" -s KILL 60 \"$@\" >\"$out\" 2>&1 </dev/null &\n"
   "waiter=$!\n"
   "n=0\n"
   "until grep -q '^(ready ' \"$out\" || [ \"$n\" -ge 400 ]; do sleep 0.05; n=$((n + 1)); done\n"
   "pid=$(sed -n 's/^(ready \\([0-9]*\\))$/\\1/p' \"$out\")\n"
   "if [ -z \"$pid\" ]; then kill \"$waiter\"; wait \"$waiter\"; cat \"$out\" >&2; rm -f \"$out\"; echo 'checks child: the child never said it was ready' >&2; exit 126; fi\n"
   "sleep 0.5\n"
   "kill -INT \"$pid\"\n"
   ": >\"$out.sent\"\n"
   "wait \"$waiter\"\n"
   "status=$?\n"
   "grep -v '^(ready ' \"$out\"\n"
   "rm -f \"$out\" \"$out.sent\"\n"
   "exit $status\n"))

;; child-hold : (Listof Datum)
;; The forms the child splices in after its import, for its hold, as
;; test-group's children hold theirs (M7 slice 4's races,
;; research/m7/slice4/races):
;;   - (until-sent), which the holder sleeps in, holding its mutex, until
;;     the suite has sent the SIGINT: interrupt-script makes the file
;;     CHECKS_CHILD_SENT names once its kill has returned, polled every
;;     10 ms, for 20 s at most. So no release comes before the SIGINT,
;;     however late the script runs; the signal is then pending on the main
;;     thread, blocked on the mutex inside the checks' section;
;;   - held-collections, (collections) as the holder starts to hold, and
;;     handler-collections, as the Ctrl-C handler starts: (quiet) answers
;;     quiet when they are equal. A collection asked for while the holder
;;     sleeps in its critical section waits for the hold to end, and so
;;     does every thread that reaches an event check meanwhile, which would
;;     move where the handler runs. The child asks for one by
;;     collect-rendezvous before its holder starts, which leaves none due
;;     in the hold, and quiet shows none ran.
(define child-hold
  '((define child-sent (getenv "CHECKS_CHILD_SENT"))
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

;; checks-child : (Listof Datum)
;; A program, run on URL ENTRY ACTION WHERE: a call of ENTRY, call-of's, to
;; URL, on a session of its own; or, for ENTRY submit, curl-submit on that
;; session's engine of a get of http://127.0.0.1:9/never through URL as its
;; proxy, awaited. A second thread holds a mutex until the suite has sent
;; its SIGINT (child-hold); the private gate WHERE names, checks, step or
;; submit, armed, blocks at its first start on that mutex, once, inside the
;; checks' critical section, the first step's, or the submit's first URL
;; parse's, the proxy URL's; every call of that gate is marked. This thread prints
;; (ready PID) and makes the call, under a Ctrl-C handler that, by ACTION:
;; raise, raises a &curl-engine-error of the child's own making; resume,
;; raises a &warning continuably, which the caller's with-exception-handler
;; returns from when the condition it is handed is a warning, as
;; test-http-client's M5 timer test's does.
;;
;; Prints (checks ENTRY WHERE ACTION OUTCOME MARKS QUIET HOLDS STARTED RETURNED):
;; OUTCOME (returned STATUS), or (raised SAME COMPOUNDED), SAME whether it
;; raised the planted object itself, COMPOUNDED whether what it raised
;; carries an &http-exchange, or (raised other DESCRIPTION); MARKS the
;; gate's marks before the handler ran, or never; QUIET as child-hold
;; reads it; HOLDS the engine's live and queued counts and the transfer
;; count, 500 ms after the release; STARTED the transfers the process
;; started; RETURNED how many times the caller's handler returned. Then
;; (counts COUNTS), once the session is closed.
(define checks-child
  `((import (chezscheme) (curl) (http-client)
            (only (http-client private call) http-session-engine)
            (only (http-client private drive) drive-checks-gate-set! drive-step-gate-set!)
            (only (curl private engine) curl-engine-live-count curl-engine-queued-count)
            (only (curl private transfer) transfers-started transfer-parse-gate-set!)
            (only (curl private conditions) make-curl-engine-error)
            (curl private counters))
    ,@child-hold
    (define args (command-line-arguments))
    (define url (list-ref args 0))
    (define entry (string->symbol (list-ref args 1)))
    (define action (string->symbol (list-ref args 2)))
    (define where (string->symbol (list-ref args 3)))
    (define gate-set! (case where
                        ((step) drive-step-gate-set!)
                        ((submit) transfer-parse-gate-set!)
                        (else drive-checks-gate-set!)))
    (define session (make-http-session 'timeout-ms 20000))
    (define engine (http-session-engine session))
    (define gate-lock (make-mutex))
    (define flag-lock (make-mutex))
    (define holding #f)
    (define released #f)
    (define (flag get) (critical-section (with-mutex flag-lock (get))))
    (define marks '())
    (define handler-marks 'never)
    (define armed #t)
    (define returned 0)
    (define planted (condition (make-curl-engine-error 'stopped #f)
                               (make-message-condition "planted by the child's Ctrl-C handler")))
    (define planted-warning (condition (make-warning) (make-message-condition "planted warning")))
    (collect-rendezvous)
    (fork-thread
     (lambda ()
       (critical-section
        (with-mutex gate-lock
          (critical-section (with-mutex flag-lock (set! held-collections (collections)) (set! holding #t)))
          (until-sent)))
       (critical-section (with-mutex flag-lock (set! released #t)))))
    (let spin ()
      (unless (flag (lambda () holding))
        (sleep (make-time 'time-duration 1000000 0))
        (spin)))
    (gate-set!
     (lambda (at)
       (set! marks (cons at marks))
       (when (and armed (eq? at 'start))
         (set! armed #f)
         (critical-section (with-mutex gate-lock #t)))))
    (define (run)
      (case entry
        ((submit)
         (let ((token (curl-submit engine (make-curl-request "http://127.0.0.1:9/never" 'proxy url
                                                             'timeout-ms 5000))))
           (curl-token-wait token 5000)
           'submitted))
        ((request) (http-response-status (http-get session url)))
        ((port)
         (call-with-response-port session 'get url
           (lambda (r p)
             (let loop ()
               (unless (eof-object? (get-bytevector-some p)) (loop)))
             (http-response-status r))))
        ((go)
         (call-with-request-group session
           (lambda (go) (http-response-status (http-await (go 'get url))))))
        ((parallel) (car (map http-response-status (http-parallel session (list (list 'get url))))))
        (else (error 'checks-child "no entry" entry))))
    (define outcome
      (guard (e (#t (if (or (eq? e planted) (and (condition? e) (http-exchange? e)))
                        (list 'raised (eq? e planted) (and (condition? e) (http-exchange? e)))
                        (list 'raised 'other
                              (if (condition? e)
                                  (list (and (who-condition? e) (condition-who e))
                                        (and (message-condition? e) (condition-message e))
                                        (non-continuable-violation? e))
                                  e)))))
        (with-exception-handler
          (lambda (c)
            (if (and (eq? action 'resume) (condition? c) (warning? c))
                (begin (set! returned (+ returned 1)) 'ignored)
                (raise-continuable c)))
          (lambda ()
            (keyboard-interrupt-handler
             (lambda ()
               (set! handler-collections (collections))
               (set! handler-marks (reverse marks))
               (if (eq? action 'raise)
                   (raise planted)
                   (raise-continuable planted-warning))))
            (write (list 'ready (get-process-id)))
            (newline)
            (flush-output-port (current-output-port))
            (list 'returned (run))))))
    (keyboard-interrupt-handler void)
    (gate-set! #f)
    (let spin ()
      (unless (flag (lambda () released))
        (sleep (make-time 'time-duration 1000000 0))
        (spin)))
    (sleep (make-time 'time-duration 500000000 0))
    (define holds (list (curl-engine-live-count engine) (curl-engine-queued-count engine)
                        (cdr (assq 'transfer (native-counts)))))
    (write (list 'checks entry where action outcome handler-marks (quiet) holds (transfers-started) returned))
    (newline)
    (http-session-close session)
    (write (list 'counts (native-counts)))
    (newline)))

;; run-child : String Symbol Symbol Symbol -> (List Integer (Listof Any) String)
;; checks-child, written to a directory of its own, run on URL, ENTRY,
;; ACTION and WHERE under interrupt-script: its exit status, what it
;; printed but its ready line, read as data, and the script's stderr.
(define (run-child url entry action where)
  (guard (e (#t (list 'raised (describe e) "")))
    (call-with-temp-directory
     (lambda (dir)
       (let ((path (string-append dir "/checks-child.sps")))
         (call-with-output-file path
           (lambda (port) (for-each (lambda (form) (write form port) (newline port)) checks-child)))
         (let ((r (capture-command (list "sh" "-c" interrupt-script "sh" (getenv "CHEZ")
                                         "--libdirs" (library-path) "--program" path url
                                         (symbol->string entry) (symbol->string action)
                                         (symbol->string where)))))
           (list (car r) (read-all (cadr r)) (caddr r))))))))

;; timer-row : Session Symbol Symbol String [Symbol] -> (List Any Any Natural)
;; ENTRY's call to URL on SESSION, the private gate WHERE names, checks by
;; default or step, setting the timer to 1 tick at its first start, once; the timer's handler raises, by
;; ACTION, raise, a &curl-engine-error of its own, or resume, a &warning
;; continuably, which the caller's handler returns from. Answers what the
;; call answered or raised, as checks-child reads it, the gate's marks
;; before the handler ran, and how many times the caller's handler
;; returned.
(define (timer-row session entry action url . more)
  (let* ((gate-set! (if (and (pair? more) (eq? (car more) 'step)) drive-step-gate-set! drive-checks-gate-set!))
         (planted (condition (make-curl-engine-error 'stopped #f)
                             (make-message-condition "planted by the timer's handler")))
         (planted-warning (condition (make-warning) (make-message-condition "planted warning")))
         (marks '())
         (handler-marks 'never)
         (armed #t)
         (returned 0)
         (previous (timer-interrupt-handler)))
    (gate-set!
     (lambda (where)
       (set! marks (cons where marks))
       (when (and armed (eq? where 'start))
         (set! armed #f)
         (set-timer 1))))
    (let ((outcome
           (guard (e (#t (if (or (eq? e planted) (and (condition? e) (http-exchange? e)))
                             (list 'raised (eq? e planted) (and (condition? e) (http-exchange? e)))
                             (list 'raised 'other (if (condition? e) (describe e) e)))))
             (with-exception-handler
               (lambda (c)
                 (if (and (eq? action 'resume) (condition? c) (warning? c))
                     (begin (set! returned (+ returned 1)) 'ignored)
                     (raise-continuable c)))
               (lambda ()
                 (timer-interrupt-handler
                  (lambda ()
                    (set! handler-marks (reverse marks))
                    (if (eq? action 'raise)
                        (raise planted)
                        (raise-continuable planted-warning))))
                 (list 'returned ((call-of entry session url))))))))
      (set-timer 0)
      (timer-interrupt-handler previous)
      (gate-set! #f)
      (list outcome handler-marks returned))))

;; sweep : Session Symbol String -> (List (Listof Natural) (Listof Natural) Any)
;; ENTRY's call to URL on SESSION inside a Chez engine of FUEL ticks, for
;; FUEL from 1 up, a tick at a time, each expiry resumed with 10^8 ticks;
;; the private gate marks the checks' start and end. It stops 10 fuels
;; past the first whose expiry came after the end, or at 4000. Answers the
;; fuels whose expiry came after the start and before the end; those whose
;; resumed call raised (curl)'s refusal to re-enter a URL's parse; and the
;; evidence: (crossed F AT BEFORE), F the first fuel whose expiry came after
;; the end, or whose call completed, AT the marks the expiry at F saw, or
;; completed, and BEFORE those at F - 1; or (never-crossed). A sweep that
;; crossed the checks reads AT (start end): a call that completed unexpired,
;; or one whose gate was never called, reads completed or ().
(define (sweep session entry url)
  (let loop ((fuel 1) (inside '()) (re-entries '()) (crossed #f) (last-marks #f) (left #f))
    (if (or (> fuel 4000) (and left (= left 0)))
        (list (reverse inside) (reverse re-entries)
              (if crossed crossed '(never-crossed)))
        (let* ((marks '())
               (ignored (drive-checks-gate-set! (lambda (where) (set! marks (cons where marks)))))
               (eng (make-engine
                     (lambda ()
                       (guard (e (#t (if (re-entry? e) 're-entry 'raised)))
                         ((call-of entry session url))
                         'answered))))
               (row (eng fuel
                         (lambda (ticks value) (list 'completed value))
                         (lambda (next)
                           (let ((at (reverse marks)))
                             (list at (next 100000000
                                            (lambda (ticks value) value)
                                            (lambda (next) 'expired-again)))))))
               (at (car row))
               (seen (if (eq? at 'completed) 'completed at)))
          (drive-checks-gate-set! #f)
          (let* ((in? (and (list? seen) (memq 'start seen) (not (memq 'end seen)) #t))
                 (after? (or (eq? seen 'completed) (and (memq 'end seen) #t)))
                 (now-crossed (or crossed (and after? (list 'crossed fuel seen last-marks)))))
            (loop (+ fuel 1)
                  (if in? (cons fuel inside) inside)
                  (if (eq? (cadr row) 're-entry) (cons fuel re-entries) re-entries)
                  now-crossed
                  seen
                  (cond (left (- left 1)) (after? 10) (else #f))))))))

;; interrupts-on? : -> Boolean
;; Whether this thread runs with interrupts on: a take of no time from a
;; fresh mailbox raises its refusal inside a critical section, and answers
;; #f at once outside one, as the drive's own interrupts-on? judges it.
(define (interrupts-on?)
  (guard (e ((and (assertion-violation? e) (who-condition? e)
                  (eq? (condition-who e) 'curl-mailbox-take))
             #f))
    (curl-mailbox-take (make-curl-mailbox) 0)
    #t))

;; refusal-row : Session Symbol Symbol -> (List Any Any)
;; ENTRY's call, refused in its checks for REFUSAL: unknown-key, a key the
;; call does not take, the high level's; header, a header name with a
;; space, make-curl-request's; prior-knowledge, http/2-prior-knowledge on
;; an https URL, which curl-request-check refuses in http-parallel's
;; checks. The caller's with-exception-handler records whether interrupts
;; were on where it ran, then hands the condition on. Answers that, and
;; what left: (compounded REASON) or anything else as found.
(define (refusal-row session entry refusal)
  (let* ((url (if (eq? refusal 'prior-knowledge) "https://127.0.0.1:9/never" "http://127.0.0.1:9/never"))
         (keys (case refusal
                 ((unknown-key) '(bogus 1))
                 ((header) '(headers (("Bad Name" . "v"))))
                 (else '(http-version http/2-prior-knowledge))))
         (seen 'handler-not-run)
         (left (guard (e (#t (if (and (condition? e) (http-exchange? e))
                                 (list 'compounded
                                       (cond ((http-request-error? e) (http-request-error-reason e))
                                             ((curl-request-error? e) (curl-request-error-reason e))
                                             (else 'other)))
                                 (list 'not-compounded (if (condition? e) (describe e) e)))))
                 (with-exception-handler
                   (lambda (c) (set! seen (interrupts-on?)) (raise-continuable c))
                   (lambda ()
                     (case entry
                       ((request) (apply http-get session url keys))
                       ((port) (apply call-with-response-port session 'get url
                                      (append keys (list (lambda (r p) 'proc-called)))))
                       ((go) (call-with-request-group session (lambda (go) (apply go 'get url keys))))
                       (else (http-parallel session (list (cons 'get (cons url keys))))))
                     'no-refusal)))))
    (list (list 'interrupts-on seen) left)))


;; --- a redirect's step, a submit's checks and the URL's cap --------------------------

;; any-re-entry? : Any -> Boolean
;; Whether E is any of (curl)'s refusals to re-enter a critical wind once
;; its handle or its string was freed: an assertion violation whose message
;; begins "re-entered after", call-with-parsed-url's, proxy-url-reading's,
;; get-part's and a C string's alike.
(define (any-re-entry? e)
  (and (condition? e) (assertion-violation? e) (message-condition? e)
       (let ((m (condition-message e)))
         (and (>= (string-length m) 16) (string=? (substring m 0 16) "re-entered after")))))

;; counted : (Listof Symbol) Symbol -> Natural
(define (counted marks mark)
  (length (filter (lambda (m) (eq? m mark)) marks)))

;; step-sweep : Session Symbol String -> (List (Listof Natural) (Listof Natural) (List Boolean Boolean Boolean))
;; ENTRY's call to URL, a redirect, on SESSION inside a Chez engine of FUEL
;; ticks, each expiry resumed with 10^8 ticks, the checks gate marking
;; start and end and the step gate step-start and step-end. Fuel goes up by
;; 25 to the first whose expiry came after a step's end, F; then a tick at a
;; time from F - 400 to F + 200, across the first step: where it lands moves
;; between runs with the await's polls, the more under Valgrind. Answers, of
;; every fuel run, the coarse ones too, the ones whose expiry came inside a
;; step, a step-start not yet
;; ended; those whose resumed call raised (curl)'s refusal to re-enter; and
;; the evidence: whether F was found, and whether some expiry came after
;; the checks and before any step, and some after a step, outside every
;; step, before the call ended. A streamed hop steps twice, at its head,
;; whether it steps past it, then once read.
(define (step-sweep session entry url)
  (define (run-at fuel)
    (let ((marks '()))
      (drive-checks-gate-set! (lambda (w) (set! marks (cons w marks))))
      (drive-step-gate-set! (lambda (w) (set! marks (cons (if (eq? w 'start) 'step-start 'step-end) marks))))
      (let* ((eng (make-engine
                   (lambda ()
                     (guard (e (#t (if (any-re-entry? e) 're-entry 'raised)))
                       ((call-of entry session url))
                       'answered))))
             (row (eng fuel
                       (lambda (ticks value) (list 'completed value))
                       (lambda (next)
                         (let ((at (reverse marks)))
                           (list at (next 100000000
                                          (lambda (ticks value) value)
                                          (lambda (next) 'expired-again))))))))
        (drive-checks-gate-set! #f)
        (drive-step-gate-set! #f)
        row)))
  (define (inside? at) (and (list? at) (> (counted at 'step-start) (counted at 'step-end))))
  (define (before-step? at) (and (list? at) (memq 'end at) (= (counted at 'step-start) 0) #t))
  (define (after-a-step? at)
    (and (list? at) (>= (counted at 'step-end) 1) (= (counted at 'step-start) (counted at 'step-end))))
  (let* ((coarse '())
         (first-end (let loop ((fuel 25))
                      (if (> fuel 20000)
                          #f
                          (let ((row (run-at fuel)))
                            (set! coarse (cons (cons fuel row) coarse))
                            (if (let ((at (car row))) (and (list? at) (memq 'step-end at)))
                                fuel
                                (loop (+ fuel 25)))))))
         (fine (if first-end
                   (let loop ((fuel (max 1 (- first-end 400))) (acc '()))
                     (if (> fuel (+ first-end 200))
                         (reverse acc)
                         (loop (+ fuel 1) (cons (cons fuel (run-at fuel)) acc))))
                   '()))
         (rows (append (reverse coarse) fine)))
    (list (map car (filter (lambda (r) (inside? (cadr r))) rows))
          (map car (filter (lambda (r) (eq? (caddr r) 're-entry)) rows))
          (list (and first-end #t)
                (and (exists (lambda (r) (before-step? (cadr r))) rows) #t)
                (and (exists (lambda (r) (after-a-step? (cadr r))) rows) #t)))))

;; step-timer-sweep : Session Symbol String Natural -> (List (Listof Any) (Listof Natural) Boolean)
;; ENTRY's call to URL, a redirect, on SESSION, for N from 1 to K: the step
;; gate sets the timer to N ticks at the first step's start; the timer's
;; handler raises the symbol tick continuably, which the caller's handler
;; returns from, so the call should resume and answer 200. Answers the Ns
;; whose call answered anything else, with what it answered; those whose
;; handler ran inside a step, its marks a step-start not yet ended; and
;; whether the handler ran for some N.
(define (step-timer-sweep session entry url k)
  (let loop ((n 1) (bad '()) (inside '()) (ran #f))
    (if (> n k)
        (list (reverse bad) (reverse inside) ran)
        (let ((marks '()) (handler-marks #f) (armed #t) (previous (timer-interrupt-handler)))
          (drive-step-gate-set!
           (lambda (w)
             (set! marks (cons w marks))
             (when (and armed (eq? w 'start))
               (set! armed #f)
               (set-timer n))))
          (let ((outcome
                 (guard (e (#t (list 'raised (cond ((any-re-entry? e) 're-entry)
                                                   ((condition? e) (describe e))
                                                   (else e)))))
                   (with-exception-handler
                     (lambda (c) (if (eq? c 'tick) 'ignored (raise-continuable c)))
                     (lambda ()
                       (timer-interrupt-handler
                        (lambda ()
                          (unless handler-marks (set! handler-marks (reverse marks)))
                          (raise-continuable 'tick)))
                       (list 'returned ((call-of entry session url))))))))
            (set-timer 0)
            (timer-interrupt-handler previous)
            (drive-step-gate-set! #f)
            (loop (+ n 1)
                  (if (equal? outcome '(returned 200)) bad (cons (list n outcome) bad))
                  (if (and handler-marks (> (counted handler-marks 'start) (counted handler-marks 'end)))
                      (cons n inside)
                      inside)
                  (or ran (and handler-marks #t))))))))

;; step-raise-row : Session Symbol String -> (List Any Any)
;; ENTRY's call to URL, a redirect, its first step raising, through the
;; step gate at its start, inside the step's section, a &curl-engine-error
;; of the suite's own: the caller's with-exception-handler records whether
;; interrupts were on where it ran, then hands it on. Answers that, and
;; what left: the-planted-condition, compounded, or (other E).
(define (step-raise-row session entry url)
  (let* ((planted (condition (make-curl-engine-error 'stopped #f)
                             (make-message-condition "planted at the step's start")))
         (armed #t)
         (seen 'handler-not-run))
    (drive-step-gate-set!
     (lambda (w)
       (when (and armed (eq? w 'start))
         (set! armed #f)
         (raise planted))))
    (let ((left (guard (e (#t (cond ((eq? e planted) 'the-planted-condition)
                                    ((and (condition? e) (http-exchange? e)) 'compounded)
                                    (else (list 'other (if (condition? e) (describe e) e))))))
                  (with-exception-handler
                    (lambda (c) (set! seen (interrupts-on?)) (raise-continuable c))
                    (lambda () ((call-of entry session url)) 'no-raise)))))
      (drive-step-gate-set! #f)
      (list (list 'interrupts-on seen) left))))

;; submit-sweep : Engine String String -> (List Natural (Listof Natural) (List Boolean Boolean))
;; curl-submit on ENGINE of a request for TARGET through PROXY, a proxy
;; URL, inside a Chez engine of FUEL ticks, for FUEL from 1 up, a tick at a
;; time, each expiry resumed with 10^8 ticks, each token cancelled and
;; awaited after; it stops 20 fuels past the first whose submit completed
;; unexpired, or at 8000. Answers how many resumed submits raised (curl)'s
;; refusal to re-enter, the first five such fuels, and the evidence: whether
;; a submit completed unexpired, and whether some expired.
(define (submit-sweep engine proxy target)
  (let ((request (make-curl-request target 'proxy proxy 'timeout-ms 5000)))
    (let loop ((fuel 1) (re-entries '()) (completed #f) (left #f) (expired #f))
      (if (or (> fuel 8000) (and left (= left 0)))
          (list (length re-entries) (take-up-to (reverse re-entries) 5) (list completed expired))
          (let* ((token #f)
                 (eng (make-engine
                       (lambda ()
                         (guard (e (#t (if (any-re-entry? e) 're-entry 'raised)))
                           (set! token (curl-submit engine request))
                           'submitted))))
                 (row (eng fuel
                           (lambda (ticks value) (list 'completed value))
                           (lambda (next)
                             (list 'expired (next 100000000
                                                  (lambda (ticks value) value)
                                                  (lambda (next) 'expired-again)))))))
            (when token
              (curl-token-cancel token)
              (curl-token-wait token 5000))
            (loop (+ fuel 1)
                  (if (eq? (cadr row) 're-entry) (cons fuel re-entries) re-entries)
                  (or completed (eq? (car row) 'completed))
                  (cond (left (- left 1)) ((eq? (car row) 'completed) 20) (else #f))
                  (or expired (eq? (car row) 'expired))))))))

;; submit-timer-sweep : Engine String String Natural -> (List Natural (Listof Natural) Boolean)
;; curl-submit as submit-sweep makes it, the timer set to N ticks just
;; before it, for N from 1 to K; the timer's handler raises the symbol tick
;; continuably, which the caller's handler returns from, so the submit
;; should resume and answer its token. Answers how many submits raised
;; (curl)'s refusal to re-enter, the first five such Ns, and whether the
;; handler ran for some N.
(define (submit-timer-sweep engine proxy target k)
  (let ((request (make-curl-request target 'proxy proxy 'timeout-ms 5000)))
    (let loop ((n 1) (re-entries '()) (ran #f))
      (if (> n k)
          (list (length re-entries) (take-up-to (reverse re-entries) 5) ran)
          (let* ((token #f)
                 (handled #f)
                 (previous (timer-interrupt-handler))
                 (outcome
                  (guard (e (#t (if (any-re-entry? e) 're-entry 'raised)))
                    (with-exception-handler
                      (lambda (c) (if (eq? c 'tick) 'ignored (raise-continuable c)))
                      (lambda ()
                        (timer-interrupt-handler (lambda () (set! handled #t) (raise-continuable 'tick)))
                        (set-timer n)
                        (set! token (curl-submit engine request))
                        'submitted)))))
            (set-timer 0)
            (timer-interrupt-handler previous)
            (when token
              (curl-token-cancel token)
              (curl-token-wait token 5000))
            (loop (+ n 1) (if (eq? outcome 're-entry) (cons n re-entries) re-entries) (or ran handled)))))))

;; long-url : Natural -> String
;; http://127.0.0.1:9/ then a's, N chars in all.
(define (long-url n)
  (let ((head "http://127.0.0.1:9/"))
    (string-append head (make-string (- n (string-length head)) #\a))))

;; cap-row : Session Symbol String List -> (List Any Any Integer)
;; ENTRY's get of URL, with the keys KEYS, on SESSION, its checks gate
;; marking: the gate's marks, what it raised, as its fields, and the ns
;; from the checks' start to the raise.
(define (cap-row session entry url keys)
  (let ((marks '()) (start #f))
    (drive-checks-gate-set!
     (lambda (w)
       (set! marks (cons w marks))
       (when (and (eq? w 'start) (not start)) (set! start (monotonic-ns)))))
    (let* ((left (guard (e (#t (let ((at (monotonic-ns)))
                                 (list at
                                       (if (condition? e)
                                           (list (and (curl-url-error? e)
                                                      (list (curl-url-error-reason e) (curl-url-error-code e)
                                                            (curl-url-error-message e)
                                                            (equal? (curl-url-error-input e) url)))
                                                 (and (http-request-error? e) (list 'request-error (http-request-error-reason e)))
                                                 (and (who-condition? e) (condition-who e))
                                                 (and (message-condition? e) (condition-message e))
                                                 (and (irritants-condition? e) (condition-irritants e))
                                                 (and (http-exchange? e)
                                                      (list (http-exchange-method e) (equal? (http-exchange-url e) url)
                                                            (http-exchange-history e) (http-exchange-transfers e))))
                                           (list 'non-condition e))))))
                   (case entry
                     ((request) (apply http-get session url keys))
                     ((port) (apply call-with-response-port session 'get url
                                    (append keys (list (lambda (r p) 'proc-called)))))
                     ((go) (call-with-request-group session (lambda (go) (apply go 'get url keys))))
                     (else (http-parallel session (list (cons 'get (cons url keys))))))
                   (list (monotonic-ns) 'no-raise))))
      (drive-checks-gate-set! #f)
      (list (reverse marks) (cadr left) (if start (- (car left) start) #f)))))

;; monotonic-ns : -> Integer
(define (monotonic-ns)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000000000) (time-nanosecond t))))

(call-with-origin
 (lambda (o)
   (define url
     (let ((f (origin-face o 'http)))
       (string-append "http://" (car f) ":" (number->string (cdr f)) "/status/200")))

   ;; url-of-face : Origin Symbol String -> String
   (define (url-of-face o face path)
     (let ((f (origin-face o face)))
       (string-append "http://" (car f) ":" (number->string (cdr f)) path)))

   ;; --- Ctrl-C, in a child ------------------------------------------------------------

   (for-each
    (lambda (entry)
      (test-equal (string-append
                   "SIGINT while " (symbol->string entry)
                   "'s checks block at their start, inside their critical section, whose Ctrl-C handler raises a &curl-error of its own: the call raises that very object, not compounded with &http-exchange, the handler run after the checks' end, as the section ended; nothing was submitted; the hold quiet, the child's counts zero")
        (list 0 (list (list 'checks entry 'checks 'raise '(raised #t #f) '(start end) 'quiet '(0 0 0) 0 0)
                      (list 'counts zero-counts))
              "")
        (run-child url entry 'raise 'checks)))
    entries)

   (for-each
    (lambda (entry)
      (test-equal (string-append
                   "SIGINT while " (symbol->string entry)
                   "'s checks block at their start, whose Ctrl-C handler raises a &warning continuably, which the caller's handler returns from: the call resumes and answers 200, the caller's handler returned once, the handler run after the checks' end; one transfer; the child's counts zero")
        (list 0 (list (list 'checks entry 'checks 'resume '(returned 200) '(start end) 'quiet '(0 0 0) 1 1)
                      (list 'counts zero-counts))
              "")
        (run-child url entry 'resume 'checks)))
    entries)

   ;; --- a timer -----------------------------------------------------------------------

   (let ((session (make-http-session 'timeout-ms 20000)))
     (for-each
      (lambda (entry)
        (test-equal (string-append
                     "a timer that runs out at " (symbol->string entry)
                     "'s checks' start, inside their critical section, fires after their end: its handler's own &curl-error leaves as raised, not compounded; a continuable &warning its caller's handler returns from resumes the call, which answers 200")
          (list (list '(raised #t #f) '(start end) 0)
                (list '(returned 200) '(start end) 1))
          (list (timer-row session entry 'raise url)
                (timer-row session entry 'resume url))))
      entries)
     (http-session-close session))

   ;; --- a Chez engine's expiry ----------------------------------------------------------

   (let ((session (make-http-session 'timeout-ms 20000)))
     (for-each
      (lambda (entry)
        (let ((swept (guard (e (#t (list 'raised (describe e) '()))) (sweep session entry url))))
          (test-equal (string-append
                       "an engine's expiry swept a tick at a time across " (symbol->string entry)
                       "'s checks: none lands between their start and end, and no resumed call raises (curl)'s refusal to re-enter a URL's parse; the fuels that did, counted, and their first five")
            '((0 ()) (0 ()))
            (list (list (length (car swept)) (take-up-to (car swept) 5))
                  (list (length (cadr swept)) (take-up-to (cadr swept) 5))))
          (test-equal (string-append
                       "the " (symbol->string entry)
                       " sweep's evidence: it crossed the checks a tick at a time, the first expiry after their end having seen both marks, start and end, and the one at the fuel before it neither")
            '(crossed (start end) ())
            (let ((c (caddr swept)))
              (if (eq? (car c) 'crossed) (list 'crossed (caddr c) (cadddr c)) c)))))
      entries)
     (http-session-close session))

   ;; --- a redirect's step ----------------------------------------------------------------

   ;; A group, go's and parallel's, submits the next hop inside the step's
   ;; own section, before the handler runs, and the raise cancels it: the
   ;; engine's thread can start that transfer first. On the 8.5.0 OpenSSL
   ;; lane's make test it did, once: 2 transfers started. With the child's
   ;; handler made to sleep 100 ms before its raise, go and parallel started
   ;; 2 in 10 of 10 runs each, request and port 1 in 10 of 10; without the
   ;; sleep, every run started 1: 40 of each entry natively, and on that
   ;; lane 40 each of request, port and go and 60 of parallel
   ;; (research/m7/carried/guard/, the fix round's step-raise tallies). So a
   ;; group's row reads 1 or 2 as one-or-two; a single call's, which
   ;; submits after its step's section, is 1.
   (let ((redirect (url-of-face o 'http "/redirect/302?to=/status/200"))
         (group-started
          (lambda (r)
            (guard (e (#t r))
              (let* ((row (car (cadr r)))
                     (n (list-ref row 8)))
                (list (car r)
                      (cons (append (take-up-to row 8)
                                    (cons (if (memv n '(1 2)) 'one-or-two n) (list-tail row 9)))
                            (cdr (cadr r)))
                      (caddr r)))))))
     (for-each
      (lambda (entry)
        (let ((group? (memq entry '(go parallel))))
          (test-equal (string-append
                       "SIGINT while " (symbol->string entry)
                       "'s first step, a redirect's, blocks at its start, inside its critical section, whose Ctrl-C handler raises a &curl-error of its own: the call raises that very object, the handler run after the step's end, as the section ended; "
                       (if group?
                           "the first transfer made, and the next hop's, which the group submits inside the step's section, started or not as the cancel and the engine's thread meet"
                           "the first transfer alone made")
                       "; the child's counts zero")
            (list 0 (list (list 'checks entry 'step 'raise '(raised #t #f) '(start end) 'quiet '(0 0 0)
                                (if group? 'one-or-two 1) 0)
                          (list 'counts zero-counts))
                  "")
            (let ((r (run-child redirect entry 'raise 'step)))
              (if group? (group-started r) r)))))
      entries)

     (for-each
      (lambda (entry)
        (test-equal (string-append
                     "SIGINT while " (symbol->string entry)
                     "'s first step, a redirect's, blocks at its start, whose Ctrl-C handler raises a &warning continuably, which the caller's handler returns from: the call resumes, follows the redirect, and answers 200, the caller's handler returned once; two transfers; the child's counts zero")
          (list 0 (list (list 'checks entry 'step 'resume '(returned 200) '(start end) 'quiet '(0 0 0) 2 1)
                        (list 'counts zero-counts))
                "")
          (run-child redirect entry 'resume 'step)))
      entries)

     (let ((session (make-http-session 'timeout-ms 20000)))
       (for-each
        (lambda (entry)
          (test-equal (string-append
                       "a timer that runs out at " (symbol->string entry)
                       "'s first step's start, a redirect's, inside its critical section, fires after its end: its handler's own &curl-error leaves as raised; a continuable &warning its caller's handler returns from resumes the call, which answers 200")
            (list (list '(raised #t #f) '(start end) 0)
                  (list '(returned 200) '(start end) 1))
            (list (timer-row session entry 'raise redirect 'step)
                  (timer-row session entry 'resume redirect 'step))))
        entries)

       (for-each
        (lambda (entry)
          (let ((swept (guard (e (#t (list (list 'raised (describe e)) '() '()))) (step-sweep session entry redirect))))
            (test-equal (string-append
                         "an engine's expiry swept a tick at a time across " (symbol->string entry)
                         "'s first step, a redirect's: none lands inside a step, and no resumed call raises (curl)'s refusal to re-enter a URL's parse; the fuels that did, counted, and their first five; and the sweep's evidence, the first expiry after a step's end found, some expiry after the checks and before any step, and some after a step, outside every step")
              '((0 ()) (0 ()) (#t #t #t))
              (list (list (length (car swept)) (take-up-to (car swept) 5))
                    (list (length (cadr swept)) (take-up-to (cadr swept) 5))
                    (caddr swept)))))
        '(request port go))

       (for-each
        (lambda (entry)
          (let ((swept (guard (e (#t (list (list 'raised (describe e)) '() #f)))
                         (step-timer-sweep session entry redirect 300))))
            (test-equal (string-append
                         "a timer set 1 to 300 ticks past " (symbol->string entry)
                         "'s first step's start, a redirect's, whose handler raises a symbol continuably, which the caller's handler returns from: every call resumes and answers 200, no handler runs inside a step, and the handler ran; the counts that did not, and their first five")
              '((0 ()) (0 ()) #t)
              (list (list (length (car swept)) (take-up-to (car swept) 5))
                    (list (length (cadr swept)) (take-up-to (cadr swept) 5))
                    (caddr swept)))))
        '(request port go))

       (test-equal "a raise made inside a redirect's step, through the step gate at its start, leaves http-request and call-with-response-port as raised, once the step's critical section has ended, so the caller's handler runs with interrupts on; a group's call fails with it, compounded, and its await raises it, interrupts on"
         '((request ((interrupts-on #t) the-planted-condition))
           (port ((interrupts-on #t) the-planted-condition))
           (go ((interrupts-on #t) compounded)))
         (in-order (lambda (entry) (list entry (step-raise-row session entry redirect))) '(request port go)))
       (http-session-close session)))

   ;; --- a submit's checks, with a proxy URL --------------------------------------------------

   (let ((engine (make-curl-engine))
         (proxy (url-of-face o 'http "/"))
         (target "http://127.0.0.1:9/never"))
     (let ((swept (guard (e (#t (list 'raised (describe e) '()))) (submit-sweep engine proxy target))))
       (test-equal "an engine's expiry swept a tick at a time across curl-submit of a request through a proxy URL, a direct caller's, with interrupts on: no resumed submit raises (curl)'s refusal to re-enter the proxy URL's parse or the URL's; the count, its first five fuels, and the sweep's evidence, a submit that completed unexpired and some that expired"
         '(0 () (#t #t))
         swept))
     (let ((swept (guard (e (#t (list 'raised (describe e) #f))) (submit-timer-sweep engine proxy target 3000))))
       (test-equal "a timer set 1 to 3000 ticks before curl-submit of a request through a proxy URL, whose handler raises a symbol continuably, which the caller's handler returns from: no submit raises (curl)'s refusal to re-enter a parse; the count, its first five, and whether the handler ran"
         '(0 () #t)
         swept))
     (let ((seen 'handler-not-run))
       (test-equal "a direct caller's curl-submit refused by its URL's parse, an ftp URL, raises it once the parse's critical section has ended: the caller's handler runs with interrupts on"
         '((interrupts-on #t) (curl-url-error scheme-not-http))
         (let ((left (guard (e (#t (if (curl-url-error? e) (list 'curl-url-error (curl-url-error-reason e)) (list 'other (describe e)))))
                       (with-exception-handler
                         (lambda (c) (set! seen (interrupts-on?)) (raise-continuable c))
                         (lambda () (curl-submit engine (make-curl-request "ftp://127.0.0.1/x")) 'no-refusal)))))
           (list (list 'interrupts-on seen) left))))
     (curl-engine-stop engine))

   (test-equal "SIGINT while a direct caller's curl-submit, through a proxy URL, blocks at the start of its proxy URL's parse, inside its critical section, whose Ctrl-C handler raises a &curl-error of its own: the submit raises that very object, nothing submitted; the child's counts zero"
     (list 0 (list (list 'checks 'submit 'submit 'raise '(raised #t #f) '(start) 'quiet '(0 0 0) 0 0)
                   (list 'counts zero-counts))
           "")
     (run-child (url-of-face o 'http "/") 'submit 'raise 'submit))

   (test-equal "SIGINT while a direct caller's curl-submit, through a proxy URL, blocks at the start of its proxy URL's parse, whose Ctrl-C handler raises a &warning continuably, which the caller's handler returns from: the submit resumes and answers its token, whose transfer ends; the caller's handler returned once; the child's counts zero"
     (list 0 (list (list 'checks 'submit 'submit 'resume '(returned submitted) '(start) 'quiet '(0 0 0) 1 1)
                   (list 'counts zero-counts))
           "")
     (run-child (url-of-face o 'http "/") 'submit 'resume 'submit))

   ;; --- the URL's cap --------------------------------------------------------------------------

   (let ((session (make-http-session 'timeout-ms 20000 'proxy #f))
         (over (long-url 8000001))
         (at-cap (long-url 8000000)))
     (test-equal "a URL of 8,000,001 chars, past libcurl's 8,000,000-byte cap, at each entry: refused at the checks' start, the gate's end never reached, as libcurl refuses it on every libcurl measured, &curl-url-error malformed-input, code 3, libcurl's message, its input the URL, who chez-curl, irritants (url), compounded with the call's &http-exchange, no transfer"
       (map (lambda (entry)
              (list entry '(start)
                    (list '(malformed-input 3 "Malformed input to a URL function" #t) #f 'chez-curl
                          "Malformed input to a URL function" '(url) '(get #t () 0))))
            entries)
       (in-order (lambda (entry)
                   (let ((row (cap-row session entry over '())))
                     (list entry (car row) (cadr row))))
                 entries))
     (test-equal "the cap comes first: a URL of 8,000,001 chars beside an unknown key is refused for its length, before the keys; one of 8,000,000, the cap itself, goes to the checks in their order, the key refused first, the URL left to libcurl"
       '((over malformed-input) (at-cap (request-error unknown-key)))
       (list (list 'over (let ((d (cadr (cap-row session 'request over '(bogus 1))))) (if (car d) (caar d) d)))
             (list 'at-cap (let ((d (cadr (cap-row session 'request at-cap '(bogus 1))))) (if (car d) d (cadr d))))))
     (test-equal "a URL past the cap is refused before anything reads it: from the checks' start to its raise, under a tenth of the time a URL of 8,000,000 chars takes to reach libcurl's own refusal, the URL copied, scanned, encoded and parsed"
       '(#t)
       (let ((fast (caddr (cap-row session 'request over '())))
             (slow (caddr (cap-row session 'request at-cap '()))))
         (list (and fast slow (< (* fast 10) slow)))))
     (http-session-close session))

   ;; --- the checks' refusals --------------------------------------------------------------

   (let ((session (make-http-session 'timeout-ms 5000)))
     (test-equal "a refusal the checks make, at each entry, leaves compounded with &http-exchange, raised once their critical section has ended: the caller's handler runs with interrupts on, for the high level's unknown-key, make-curl-request's not-a-token, and curl-request-check's prior-knowledge-over-https in http-parallel"
       '((request unknown-key ((interrupts-on #t) (compounded unknown-key)))
         (request header ((interrupts-on #t) (compounded not-a-token)))
         (port unknown-key ((interrupts-on #t) (compounded unknown-key)))
         (port header ((interrupts-on #t) (compounded not-a-token)))
         (go unknown-key ((interrupts-on #t) (compounded unknown-key)))
         (go header ((interrupts-on #t) (compounded not-a-token)))
         (parallel unknown-key ((interrupts-on #t) (compounded unknown-key)))
         (parallel header ((interrupts-on #t) (compounded not-a-token)))
         (parallel prior-knowledge ((interrupts-on #t) (compounded prior-knowledge-over-https))))
       (in-order (lambda (row) (list (car row) (cadr row) (refusal-row session (car row) (cadr row))))
                 '((request unknown-key) (request header) (port unknown-key) (port header)
                   (go unknown-key) (go header) (parallel unknown-key) (parallel header)
                   (parallel prior-knowledge))))
     (http-session-close session))))

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "call-checks")

(exit (suite-exit-status runner))
