#!r6rs
;;; (curl private engine): an engine, one Chez thread that owns a multi
;;; handle, waits in curl_multi_poll, and runs the transfers other threads
;;; submit (ADR-0012; M3 plan, sections 3.1 to 3.8). (curl) exports the
;;; engine, the token, the waits and the mailbox (M4 plan, section 3.1);
;;; the rest is private: the counts, the seams and the planted faults.
;;;
;;; make-curl-engine references the load first, on the caller's thread,
;;; and only then forks the engine's thread: Chez locks no library's
;;; invocation, and two threads' first references together raise cyclic
;;; dependency (ADR-0002, amended 2026-10-24). The thread makes the multi
;;; handle and reports that it is ready, or the refusal that stopped it,
;;; which make-curl-engine raises.
;;;
;;; A stalled name lookup does not stall the engine (ADR-0019). The thread
;;; sets CURLMOPT_QUICK_EXIT to 1 on its multi handle as it makes it, so
;;; libcurl 8.20.0 and later do not join a resolver thread when the handle
;;; is cleaned up. CURLM_UNKNOWN_OPTION is taken: that libcurl predates the
;;; option. Any other answer refuses the engine, before it runs a transfer.
;;; Each transfer sets QUICK_EXIT, with the pins, where the libcurl knows
;;; it (transfer.sls), so 7.87.0 and later neither wait in the removal nor
;;; in a timed-out perform. The floor knows neither, and keeps the stall.
;;; make-curl-engine-without-quick-exit, a private test seam, leaves either
;;; out, so the test can show the stall each one prevents; and
;;; make-curl-engine-answering-quick-exit, another, takes a given answer for
;;; libcurl's, so the test can watch an answer no libcurl gives refuse the
;;; engine.
;;;
;;; Messages cross threads; handle calls don't. A submit, a cancel and a
;;; stop are queued under the engine's mutex, and then curl_multi_wakeup
;;; wakes the poll, still under the mutex: the one libcurl call a caller's
;;; thread makes on the engine's handle. The engine's thread marks itself
;;; stopping, stopped, failing or failed under the same mutex before it
;;; cleans the handle up, so no caller wakes a freed one.
;;;
;;; Each turn of the loop, on the engine's thread:
;;;
;;;   1. take   the queue, marking each submitted token live;
;;;   2. setup  each submitted transfer, by start-transfer!, added to the
;;;             multi handle, and recorded in the engine's table of live
;;;             transfers, by its easy handle's address;
;;;   3. cancel each live transfer a cancel names: taken out and completed
;;;             as cancelled; then a stop, which ends the loop;
;;;   4. perform curl_multi_perform;
;;;   5. read   each finished transfer, by curl_multi_info_read: what it
;;;             ended with, read by finish-transfer, then taken out and its
;;;             token completed;
;;;   6. poll   curl_multi_poll, for at most 1000 ms: libcurl shortens the
;;;             wait to its own timers, and a wakeup ends it.
;;;
;;; curl_multi_info_read reads none for a removed handle, and only
;;; curl_multi_perform makes its messages (M3 slice 2, measured on four
;;; libcurls). So a cancel, carried out before the perform, never races a
;;; message, and a transfer that ended in a perform completes before any
;;; cancel that came after: that cancel finds its token done, and is
;;; stale.
;;;
;;; A token holds one outcome: the response, or the condition the transfer
;;; failed with, cancelled and stopped among them, and write-body's log of
;;; its chunks (M3 plan, section 3.6). Any thread may await it, any number
;;; of times. A cancel of a token still queued completes it on the
;;; caller's thread, so nothing native is made for it; of a live one, it is
;;; a message; of a done one, nothing.
;;;
;;; A token submitted with a mailbox goes there as it becomes done, once,
;;; appended by the thread that completes it, holding the engine's mutex
;;; and then the mailbox's: the engine's thread, or a caller's that
;;; cancelled it queued (ADR-0021). The engine's is always taken first, and
;;; no hold of the mailbox's takes it. A caller's thread takes the token
;;; out, or delivers it, calling its callback there: the engine's thread
;;; never calls one, so caller code never runs on it (ADR-0012, decision
;;; 4). The outcome stays on the token, so a take that escapes loses a
;;; notice, never an outcome (ADR-0021, amended).
;;;
;;; Every wait, await's, a token's bounded wait, stop's, make-curl-engine's
;;; and a mailbox's take, polls: each read of what it waits for is a short
;;; hold of the engine's mutex, or the mailbox's, through locked, and
;;; between reads it sleeps, from 50 us doubling
;;; to 10 ms, holding nothing. Chez's sleep deactivates the thread when
;;; interrupts are on, so other threads' collections go on, and a pending
;;; Ctrl-C runs as it wakes; with them off it would not, so a wait refuses
;;; to start inside a critical section, which would deadlock with a
;;; collection the engine's thread joins. No
;;; hold of any mutex waits, and none has interrupts on, so a thread blocked
;;; on the mutex waits only for a holder that cannot join a collection: a
;;; waiter that held the mutex with interrupts on, as a condition variable
;;; needs, deadlocked against one (ADR-0013, amended 2026-10-25, after the
;;; slice's review).
;;;
;;; The loop runs under a guard. Something raised there, between libcurl
;;; calls, or at its start, fails the engine: it marks itself failing, so no caller wakes its
;;; handle again; every queued and live token completes with
;;; &curl-engine-error, reason failed, carrying it; the engine frees all it
;;; holds, cleans up its multi handle, and marks itself failed, its
;;; thread's last act. A later submit raises that failure, and stop waits
;;; for the last act, then returns (section 3.7). A planted fault, data
;;; naming a step, raises there, for the test.
;;;
;;; Stop (ADR-0012, amended 2026-10-24) completes every queued token as
;;; stopped, cancels every live one as stopped, frees all, cleans up the
;;; multi handle, checks the table of live transfers empty, and signals the
;;; stop as the thread's last act. The caller's stop returns once that
;;; signal arrives. A later stop returns at once.
;;;
;;; fork-thread is this library's alone (check-seam, rule (f)): one engine
;;; thread runs every transfer submitted to it.
;;;
;;; The engine's thread runs no caller code and sets no timer, so nothing
;;; escapes there but by a raise. Its records of a transfer, the token's
;;; and the table's, are therefore made after start-transfer! and cleared
;;; after free-transfer!, the table's in a critical section of its own, so a
;;; raise in the free leaves the transfer in the table, where the engine's
;;; failure completes its token. The limit,
;;; recorded: collect-request-handler is process-wide, so a caller's handler
;;; that escapes could run on this thread (M3 plan, section 3.6).
(library (curl private engine)
  (export make-curl-engine curl-engine? curl-submit curl-engine-submit-with
          curl-engine-stop curl-engine-request-stop! curl-engine-state curl-engine-thread
          curl-engine-multi curl-engine-live-count curl-engine-queued-count
          curl-engine-stale-cancels call-with-engine-held
          curl-token? curl-token-await curl-token-wait curl-token-cancel curl-token-done?
          curl-token-chunks
          make-curl-mailbox curl-mailbox? curl-mailbox-take curl-mailbox-deliver
          call-with-mailbox-held
          make-faulty-curl-engine engine-fault-steps planted-engine-fault
          make-curl-engine-without-quick-exit make-curl-engine-answering-quick-exit
          curl-engine-quick-exit multi-quick-exit-verdict)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) critical-section disable-interrupts enable-interrupts fork-thread
                get-thread-id make-mutex with-mutex make-time sleep foreign-sizeof
                current-time time-second time-nanosecond)
          (curl private conditions)
          (curl private constants)
          (curl private memory)
          (curl private native)
          (curl private transfer))

  ;; --- holding the mutex ---------------------------------------------------------------

  ;; locked : Mutex (-> Any) -> Any
  ;; THUNK's value, run holding LOCK, in a critical section. Chez's
  ;; with-mutex is a dynamic-wind whose before thunk takes the mutex, so an
  ;; interrupt that escapes between the take and the wind would leave it
  ;; held. Every hold of the mutex is locked's: short, with interrupts off,
  ;; and none waits (ADR-0013, amended 2026-10-25).
  (define (locked lock thunk)
    (critical-section (with-mutex lock (thunk))))

  ;; interrupts-on? : -> Boolean
  ;; Whether this thread runs with interrupts on: disable-interrupts answers
  ;; the disable count it makes, 1 when it was 0.
  (define (interrupts-on?)
    (let ((count (disable-interrupts)))
      (enable-interrupts)
      (= count 1)))

  ;; require-interrupts-on : Symbol -> Void
  ;; Returns when this thread runs with interrupts on; otherwise an
  ;; assertion violation from WHO. Each procedure that waits asks it first,
  ;; before it does anything, so a refusal leaves nothing behind.
  (define (require-interrupts-on who)
    (unless (interrupts-on?)
      (assertion-violation who
        "a wait needs interrupts on: inside a critical section it would hold every collection, and the engine's thread with them")))

  ;; wait-until : Symbol Mutex (-> Any) (U Integer #f) -> Any
  ;; READY's first true answer, each read a hold of LOCK through locked,
  ;; and between reads a sleep, holding nothing: 50 us, then twice the
  ;; last, up to 10 ms; or #f, once a read after DEADLINE, a monotonic time
  ;; in ns, answers #f. A sleep never runs past DEADLINE, and #f waits for
  ;; good. Chez's sleep deactivates this thread when
  ;; interrupts are on, so other threads' collections go on while it
  ;; sleeps, and sets its trap, so a pending Ctrl-C runs as it wakes
  ;; (ADR-0013, amended 2026-10-25). With interrupts off, a sleep keeps the
  ;; thread active: a collection would wait for it, the engine's thread
  ;; with it, and the wait would never end. So a wait inside a critical
  ;; section is an assertion violation from WHO, before it starts.
  (define (wait-until who lock ready deadline)
    (require-interrupts-on who)
    (let loop ((pause 50000))
      (or (locked lock ready)
          (let ((left (and deadline (- deadline (monotonic-ns)))))
            (and (or (not left) (> left 0))
                 (begin
                   (sleep (make-time 'time-duration (if left (min pause left) pause) 0))
                   (loop (min (* pause 2) 10000000))))))))

  ;; monotonic-ns : -> Integer
  (define (monotonic-ns)
    (let ((t (current-time 'time-monotonic)))
      (+ (* (time-second t) 1000000000) (time-nanosecond t))))

  ;; deadline-after : Symbol Any -> Integer
  ;; The monotonic time, in ns, MS milliseconds from now; MS is a natural
  ;; number, else an assertion violation from WHO.
  (define (deadline-after who ms)
    (unless (and (integer? ms) (exact? ms) (>= ms 0))
      (assertion-violation who "a bound is a natural number of milliseconds" ms))
    (+ (monotonic-ns) (* ms 1000000)))

  ;; --- the records -----------------------------------------------------------------------

  ;; An engine: its mutex; under the mutex, its queue of
  ;; messages, newest first, its state, starting, running, stopping,
  ;; stopped, failing or failed, its multi handle's address, #f once freed,
  ;; its thread's
  ;; get-thread-id, the &curl-engine-error it failed with, and its table of
  ;; live transfers, by easy handle, each (TOKEN . LIVE); its planted fault,
  ;; a step or #f; and, on its own thread alone, the batch of messages its
  ;; turn took, and its slot, the counted block curl_multi_perform and
  ;; curl_multi_info_read write their counts through, held while the multi
  ;; handle lives, so a running engine counts one block and one multi; and,
  ;; under the mutex, how many cancels found their token done; the
  ;; QUICK_EXIT settings it leaves out, a list of transfer and multi, empty
  ;; but for the test seam; and, under the mutex, what became of its multi
  ;; handle's CURLMOPT_QUICK_EXIT, #f until its thread sets it; and the
  ;; CURLMcode it takes in place of libcurl's answer to that, #f but for the
  ;; other test seam.
  (define-record-type (curl-engine make-engine-record curl-engine?)
    (fields (immutable lock curl-engine-lock)
            (mutable queue curl-engine-queue curl-engine-queue-set!)
            (mutable state engine-state engine-state-set!)
            (mutable multi engine-multi engine-multi-set!)
            (mutable thread engine-thread engine-thread-set!)
            (mutable failure engine-failure engine-failure-set!)
            (immutable live engine-live)
            (immutable fault engine-fault)
            (mutable batch engine-batch engine-batch-set!)
            (mutable slot engine-slot engine-slot-set!)
            (mutable stale engine-stale engine-stale-set!)
            (immutable without engine-without)
            (mutable quick-exit engine-quick-exit engine-quick-exit-set!)
            (immutable answer engine-answer)))

  ;; A token: its engine and its plan; under the engine's mutex, its state,
  ;; queued, live or done, its outcome, a response or a condition, and its
  ;; chunks, write-body's log; on the engine's thread alone, its live
  ;; transfer while it has one; and the mailbox it goes to when done, and
  ;; the callback a delivery calls, each #f for none (ADR-0021).
  (define-record-type (curl-token make-token curl-token?)
    (fields (immutable engine curl-token-engine)
            (immutable plan curl-token-plan)
            (mutable state token-state token-state-set!)
            (mutable outcome token-outcome token-outcome-set!)
            (mutable chunks token-chunks token-chunks-set!)
            (mutable live token-live token-live-set!)
            (immutable mailbox token-mailbox)
            (immutable callback token-callback)))

  ;; A mailbox (ADR-0021): its mutex, and under it, its finished tokens,
  ;; oldest first, as two lists: front, oldest first, and back, newest
  ;; first, which a take turns round once front is empty.
  (define-record-type (curl-mailbox make-mailbox-record curl-mailbox?)
    (fields (immutable lock mailbox-lock)
            (mutable front mailbox-front mailbox-front-set!)
            (mutable back mailbox-back mailbox-back-set!)))

  ;; curl-engine-state : Engine -> (U 'running 'stopping 'stopped 'failing 'failed)
  ;; stopping and failing last until the engine's thread has freed all it
  ;; held; a stop waits for them to end.
  (define (curl-engine-state engine)
    (check-engine 'curl-engine-state engine)
    (locked (curl-engine-lock engine) (lambda () (engine-state engine))))

  ;; curl-engine-thread : Engine -> Integer
  ;; The get-thread-id of ENGINE's thread.
  (define (curl-engine-thread engine)
    (check-engine 'curl-engine-thread engine)
    (locked (curl-engine-lock engine) (lambda () (engine-thread engine))))

  ;; curl-engine-multi : Engine -> (U Positive-Integer #f)
  ;; ENGINE's multi handle's address, #f once freed: a private accessor, for
  ;; the test that another thread's use of it raises &curl-wrong-thread.
  (define (curl-engine-multi engine)
    (check-engine 'curl-engine-multi engine)
    (locked (curl-engine-lock engine) (lambda () (engine-multi engine))))

  ;; curl-engine-quick-exit : Engine -> (U 'set 'unknown 'off)
  ;; What became of ENGINE's multi handle's CURLMOPT_QUICK_EXIT: set, at 1;
  ;; unknown, refused as CURLM_UNKNOWN_OPTION by a libcurl older than
  ;; 8.20.0; or off, left out by make-curl-engine-without-quick-exit. A
  ;; private accessor (ADR-0019). An engine returned running has set it.
  (define (curl-engine-quick-exit engine)
    (check-engine 'curl-engine-quick-exit engine)
    (locked (curl-engine-lock engine) (lambda () (engine-quick-exit engine))))

  ;; curl-engine-live-count : Engine -> Natural
  ;; How many transfers ENGINE's table holds now: a private accessor.
  (define (curl-engine-live-count engine)
    (check-engine 'curl-engine-live-count engine)
    (locked (curl-engine-lock engine) (lambda () (hashtable-size (engine-live engine)))))

  ;; curl-engine-queued-count : Engine -> Natural
  ;; How many messages ENGINE's queue holds now: a private accessor, for the
  ;; test that a refused submit queued nothing.
  (define (curl-engine-queued-count engine)
    (check-engine 'curl-engine-queued-count engine)
    (locked (curl-engine-lock engine) (lambda () (length (curl-engine-queue engine)))))

  ;; curl-engine-stale-cancels : Engine -> Natural
  ;; How many cancel messages ENGINE has carried out on a token already
  ;; done: its transfer ended in the turn the cancel came in, or an earlier
  ;; cancel of it was carried out first. A private accessor, for the test
  ;; that a stale cancel is passed over.
  (define (curl-engine-stale-cancels engine)
    (check-engine 'curl-engine-stale-cancels engine)
    (locked (curl-engine-lock engine) (lambda () (engine-stale engine))))

  ;; call-with-engine-held : Engine (-> Any) -> Any
  ;; THUNK's answer, run holding ENGINE's mutex, through locked, so the
  ;; engine's thread takes no message until it returns: a test seam,
  ;; private, so a token can be caught queued. Chez's mutexes are
  ;; recursive, so THUNK may submit, cancel and request a stop; it must not
  ;; wait, nor await, nor stop, which waits.
  (define (call-with-engine-held engine thunk)
    (check-engine 'call-with-engine-held engine)
    (locked (curl-engine-lock engine) thunk))

  ;; curl-token-done? : Token -> Boolean
  (define (curl-token-done? token)
    (check-token 'curl-token-done? token)
    (locked (curl-engine-lock (curl-token-engine token))
      (lambda () (eq? (token-state token) 'done))))

  ;; curl-token-chunks : Token -> (Listof (List Positive-Integer Integer Symbol))
  ;; write-body's log of TOKEN's chunks, oldest first, once it is done: each
  ;; chunk's length, the get-thread-id it ran on, and its verdict
  ;; (live-transfer-chunks); () before, and for a token never set up.
  (define (curl-token-chunks token)
    (check-token 'curl-token-chunks token)
    (locked (curl-engine-lock (curl-token-engine token)) (lambda () (token-chunks token))))

  (define (check-engine who x)
    (unless (curl-engine? x) (assertion-violation who "not an engine" x)))

  (define (check-token who x)
    (unless (curl-token? x) (assertion-violation who "not a token" x)))

  ;; --- the engine's conditions ---------------------------------------------------------

  ;; engine-error : Symbol Any -> Condition
  (define (engine-error reason raised)
    (condition (make-curl-engine-error reason raised)
               (make-who-condition 'curl-engine)
               (make-message-condition
                (if (eq? reason 'stopped)
                    "the engine was stopped, so it takes no more transfers"
                    "something raised inside the engine's loop, so the engine failed"))
               (make-irritants-condition (if raised (list raised) '()))))

  ;; engine-fault-steps : (Listof Symbol)
  ;; The steps a planted fault may name, each where the engine raises it:
  ;; start, on its thread, before its multi handle is made; take, when the
  ;; queue holds a message, before the turn takes it; setup, before a
  ;; transfer's start-transfer!; cancel, before a live transfer's cancel;
  ;; perform and poll, before curl_multi_perform and curl_multi_poll, while a
  ;; transfer is live; read, before a finished transfer's finish-transfer;
  ;; free, once a transfer is freed, its easy handle with it, and before
  ;; the table lets it go.
  (define engine-fault-steps '(start take setup cancel perform read poll free))

  ;; planted-engine-fault : Symbol -> (List 'planted-engine-fault Symbol)
  ;; What the loop raises at a planted fault's STEP: data, so a test can tell
  ;; it from every other raise.
  (define (planted-engine-fault step) (list 'planted-engine-fault step))

  ;; fault-at! : Engine Symbol -> Void
  (define (fault-at! engine step)
    (when (eq? (engine-fault engine) step)
      (raise (planted-engine-fault step))))

  ;; --- making an engine ------------------------------------------------------------------

  ;; make-curl-engine : -> Engine
  ;; A fresh engine, running on a thread of its own, its multi handle made
  ;; there. The load runs first, on this thread. A refusal raises here: the
  ;; load's, or the engine's &curl-engine-error, reason failed, when its
  ;; thread could make no multi handle.
  (define (make-curl-engine) (start-engine #f '() #f))

  ;; make-faulty-curl-engine : Symbol -> Engine
  ;; make-curl-engine's, with a fault planted at STEP, one of
  ;; engine-fault-steps: the engine raises (planted-engine-fault STEP) the
  ;; first time it reaches it, so a fault at start raises here, as the
  ;; refusal. A test seam, private (section 3.7).
  (define (make-faulty-curl-engine step)
    (unless (memq step engine-fault-steps)
      (assertion-violation 'make-faulty-curl-engine "not a step of the engine's loop" step))
    (start-engine step '() #f))

  ;; make-curl-engine-without-quick-exit : (Listof (U 'transfer 'multi)) -> Engine
  ;; make-curl-engine's, but for the QUICK_EXIT settings WITHOUT names, which
  ;; it leaves out: transfer, each transfer's QUICK_EXIT; multi, its multi
  ;; handle's CURLMOPT_QUICK_EXIT. A test seam, private, so the test can
  ;; show the stall each prevents (ADR-0019; M3 plan, section 6.2). No
  ;; request reaches it: QUICK_EXIT is owned (ADR-0009).
  (define (make-curl-engine-without-quick-exit without)
    ;; Checked as a copy, and the copy used: the caller's pairs may change.
    (let ((copy (and (list? without) (fold-right cons '() without))))
      (unless (and copy (for-all (lambda (x) (memq x '(transfer multi))) copy))
        (assertion-violation 'make-curl-engine-without-quick-exit
                             "a list of the QUICK_EXIT settings to leave out, transfer and multi" without))
      (start-engine #f copy #f)))

  ;; make-curl-engine-answering-quick-exit : Integer -> Engine
  ;; make-curl-engine's, but its thread takes CODE, a CURLMcode, as libcurl's
  ;; answer to CURLMOPT_QUICK_EXIT, after making the call: a test seam,
  ;; private, so the test can watch an answer no libcurl gives refuse the
  ;; engine, its multi handle freed, as multi-quick-exit-verdict says
  ;; (ADR-0019, decision 2). No request reaches it.
  (define (make-curl-engine-answering-quick-exit code)
    (unless (and (integer? code) (exact? code))
      (assertion-violation 'make-curl-engine-answering-quick-exit "a CURLMcode is an exact integer" code))
    (start-engine #f '() code))

  ;; start-engine : (U Symbol #f) (Listof (U 'transfer 'multi)) (U Integer #f) -> Engine
  (define (start-engine fault without answer)
    (require-interrupts-on 'make-curl-engine)
    (loaded-libcurl)
    (let ((engine (make-engine-record (make-mutex) '() 'starting #f #f #f
                                      (make-eqv-hashtable) fault '() #f 0 without #f answer)))
      (fork-thread (lambda () (run-engine engine)))
      (wait-until 'make-curl-engine (curl-engine-lock engine) (lambda () (memq (engine-state engine) '(running failed))) #f)
      (let ((failure (locked (curl-engine-lock engine)
                       (lambda () (and (eq? (engine-state engine) 'failed) (engine-failure engine))))))
        (when failure (raise failure)))
      engine))

  ;; --- the caller's side ---------------------------------------------------------------

  ;; curl-submit : Engine Request [(U Mailbox #f) [(U (Token -> Any) #f)]] -> Token
  ;; REQUEST's transfer, queued on ENGINE: its token, which goes to MAILBOX
  ;; when done, if one is given, for a delivery there to hand to CALLBACK,
  ;; if one is given (ADR-0021). On this thread, before anything is
  ;; queued, every refusal raises:
  ;;   - an ENGINE that is no engine, a MAILBOX neither a mailbox nor #f, a
  ;;     CALLBACK neither a procedure nor #f, or a callback without a
  ;;     mailbox, each an assertion violation;
  ;;   - the request's, or the URL's, as prepare-transfer takes and checks
  ;;     the plan, a private copy;
  ;;   - an engine stopping, stopped or failed: &curl-engine-error, reason
  ;;     stopped, or failed, with what it failed with.
  (define curl-submit
    (case-lambda
      ((engine request) (submit engine request '() #f #f))
      ((engine request mailbox) (submit engine request '() mailbox #f))
      ((engine request mailbox callback) (submit engine request '() mailbox callback))))

  ;; curl-engine-submit-with : Engine Request (Listof (Pairof String Integer)) [(U Mailbox #f)] -> Token
  ;; curl-submit's, with OPTIONS, the test seam's, and MAILBOX, #f unless
  ;; given: the seam's refusals raise beside the request's (ADR-0009,
  ;; amended 2026-10-23).
  (define curl-engine-submit-with
    (case-lambda
      ((engine request options) (submit engine request options #f #f))
      ((engine request options mailbox) (submit engine request options mailbox #f))))

  ;; submit : Engine Request (Listof (Pairof String Integer)) (U Mailbox #f) (U Procedure #f) -> Token
  (define (submit engine request options mailbox callback)
    (define who 'curl-submit)
    (check-engine who engine)
    (unless (or (not mailbox) (curl-mailbox? mailbox))
      (assertion-violation who "not a mailbox" mailbox))
    (unless (or (not callback) (procedure? callback))
      (assertion-violation who "a callback is a procedure of one argument, the token" callback))
    (when (and callback (not mailbox))
      (assertion-violation who "a callback needs a mailbox, which a delivery calls it from" callback))
    (let* ((plan (prepare-transfer request options))
           (token (make-token engine plan 'queued #f '() #f mailbox callback))
           (refusal
            (locked (curl-engine-lock engine)
              (lambda ()
                (case (engine-state engine)
                  ((running)
                   (curl-engine-queue-set! engine (cons (cons 'submit token) (curl-engine-queue engine)))
                   (curl-multi-wakeup (engine-multi engine))
                   #f)
                  ((failing failed) (engine-failure engine))
                  (else (engine-error 'stopped #f)))))))
      (when refusal (raise refusal))
      token))

  ;; curl-token-await : Token -> Response
  ;; TOKEN's response, once its transfer is done, or a raise of the
  ;; condition it ended with, on this thread. Any thread may await a token,
  ;; any number of times: the outcome is kept. It polls, by wait-until, so
  ;; Ctrl-C runs as its sleep ends, and an escape from it leaves the
  ;; transfer running: await again for its outcome (section 3.4). It must
  ;; run with interrupts on: inside a critical section it is refused.
  (define (curl-token-await token)
    (check-token 'curl-token-await token)
    (require-interrupts-on 'curl-token-await)
    (let ((outcome (wait-until 'curl-token-await (curl-engine-lock (curl-token-engine token))
                               (lambda ()
                                 (and (eq? (token-state token) 'done)
                                      (list (token-outcome token))))
                               #f)))
      (if (curl-response? (car outcome))
          (car outcome)
          (raise (car outcome)))))

  ;; curl-token-wait : Token Natural -> Boolean
  ;; Whether TOKEN is done within MS milliseconds, waiting as await does,
  ;; and leaving its transfer running either way.
  (define (curl-token-wait token ms)
    (check-token 'curl-token-wait token)
    (let ((deadline (deadline-after 'curl-token-wait ms)))
      (wait-until 'curl-token-wait (curl-engine-lock (curl-token-engine token))
                  (lambda () (eq? (token-state token) 'done))
                  deadline)))

  ;; --- the mailbox (ADR-0021) ------------------------------------------------------------

  ;; make-curl-mailbox : -> Mailbox
  ;; An empty mailbox, which collects the tokens submitted to it, from any
  ;; number of engines, as each is done.
  (define (make-curl-mailbox) (make-mailbox-record (make-mutex) '() '()))

  (define (check-mailbox who x)
    (unless (curl-mailbox? x) (assertion-violation who "not a mailbox" x)))

  ;; call-with-mailbox-held : Mailbox (-> Any) -> Any
  ;; THUNK's answer, run holding MAILBOX's mutex, through locked, so a take
  ;; from another thread blocks inside its critical section until THUNK
  ;; returns: a test seam, private, as call-with-engine-held is. A token
  ;; completing to MAILBOX meanwhile holds its engine's mutex until then,
  ;; so THUNK must not touch an engine or a token, which would take that
  ;; mutex second. It runs in a critical section, so it holds up every
  ;; collection while it runs.
  (define (call-with-mailbox-held mailbox thunk)
    (check-mailbox 'call-with-mailbox-held mailbox)
    (locked (mailbox-lock mailbox) thunk))

  ;; mailbox-append! : Mailbox Token -> Void
  ;; TOKEN at MAILBOX's back, under its mutex. Its one caller,
  ;; complete-locked!, holds the engine's mutex: the engine's is taken
  ;; first, and the mailbox's never waits.
  (define (mailbox-append! mailbox token)
    (locked (mailbox-lock mailbox)
      (lambda () (mailbox-back-set! mailbox (cons token (mailbox-back mailbox))))))

  ;; mailbox-pop! : Mailbox -> (U Token #f)
  ;; MAILBOX's oldest token, taken out, or #f for none. The caller holds its
  ;; mutex.
  (define (mailbox-pop! mailbox)
    (when (null? (mailbox-front mailbox))
      (mailbox-front-set! mailbox (reverse (mailbox-back mailbox)))
      (mailbox-back-set! mailbox '()))
    (let ((front (mailbox-front mailbox)))
      (and (pair? front)
           (begin
             (mailbox-front-set! mailbox (cdr front))
             (car front)))))

  ;; take : Symbol Mailbox Any -> (U Token #f)
  (define (take who mailbox ms)
    (check-mailbox who mailbox)
    (let ((deadline (deadline-after who ms)))
      (wait-until who (mailbox-lock mailbox) (lambda () (mailbox-pop! mailbox)) deadline)))

  ;; curl-mailbox-take : Mailbox Natural -> (U Token #f)
  ;; MAILBOX's next finished token, taken out, waiting up to MS
  ;; milliseconds for one, or #f once they pass. It waits as await does,
  ;; and never calls a callback. A take that escapes, by an interrupt
  ;; handler as it ends, loses its token's notice, never its outcome,
  ;; which the token keeps (ADR-0021, amended).
  (define (curl-mailbox-take mailbox ms)
    (take 'curl-mailbox-take mailbox ms))

  ;; curl-mailbox-deliver : Mailbox Natural -> (U Token #f)
  ;; As curl-mailbox-take, and then the token's callback, if it has one,
  ;; called with the token on this thread: the token, or #f once MS
  ;; milliseconds pass, never what the callback answered. The callback's
  ;; raise leaves through here.
  (define (curl-mailbox-deliver mailbox ms)
    (let ((token (take 'curl-mailbox-deliver mailbox ms)))
      (when token
        (let ((callback (token-callback token)))
          (when callback (callback token))))
      token))

  ;; curl-token-cancel : Token -> Void
  ;; Returns at once. A token still queued completes as cancelled, here,
  ;; with nothing native made, whatever its engine's state; a live one is a
  ;; message, and the engine takes its transfer out and completes it as
  ;; cancelled, unless the engine is stopping or failing, which completes it
  ;; as stopped or failed; a done one is left as it is (section 3.5).
  (define (curl-token-cancel token)
    (check-token 'curl-token-cancel token)
    (let ((engine (curl-token-engine token)))
      (locked (curl-engine-lock engine)
        (lambda ()
          (case (token-state token)
            ((queued)
             (complete-locked! engine token (transfer-ended 'cancelled) '()))
            ((live)
             (when (eq? (engine-state engine) 'running)
               (curl-engine-queue-set! engine (cons (cons 'cancel token) (curl-engine-queue engine)))
               (curl-multi-wakeup (engine-multi engine))))
            (else #f))))))

  ;; curl-engine-request-stop! : Engine -> Void
  ;; Queues ENGINE's stop and returns at once: from now on a submit is
  ;; refused as stopped. An engine stopping, stopped or failed already is
  ;; left as it is.
  (define (curl-engine-request-stop! engine)
    (check-engine 'curl-engine-request-stop! engine)
    (locked (curl-engine-lock engine)
      (lambda ()
        (when (eq? (engine-state engine) 'running)
          (engine-state-set! engine 'stopping)
          (curl-engine-queue-set! engine (cons (list 'stop) (curl-engine-queue engine)))
          (curl-multi-wakeup (engine-multi engine))))))

  ;; curl-engine-stop : Engine -> Void
  ;; Stops ENGINE: curl-engine-request-stop!, then a wait for the engine's
  ;; thread to signal its end, which it does once every token it held is
  ;; completed, as stopped, and everything it held is freed. A stop of an
  ;; engine stopped or failed already returns at once; one while another
  ;; stop runs, or while the engine is failing, waits for its end.
  (define (curl-engine-stop engine)
    (check-engine 'curl-engine-stop engine)
    (require-interrupts-on 'curl-engine-stop)
    (curl-engine-request-stop! engine)
    (wait-until 'curl-engine-stop (curl-engine-lock engine) (lambda () (memq (engine-state engine) '(stopped failed))) #f)
    (if #f #f))

  ;; --- completing a token ----------------------------------------------------------------

  ;; complete-locked! : Engine Token Any (Listof Any) -> Void
  ;; TOKEN done with OUTCOME and CHUNKS, unless it is done already: the first
  ;; outcome stands. The caller holds ENGINE's mutex. A waiter sees it at its
  ;; next read. A token with a mailbox goes there as it becomes done, once.
  (define (complete-locked! engine token outcome chunks)
    (unless (eq? (token-state token) 'done)
      (token-outcome-set! token outcome)
      (token-chunks-set! token chunks)
      (token-state-set! token 'done)
      (let ((mailbox (token-mailbox token)))
        (when mailbox (mailbox-append! mailbox token)))))

  ;; complete! : Engine Token Any (Listof Any) -> Void
  (define (complete! engine token outcome chunks)
    (locked (curl-engine-lock engine)
      (lambda () (complete-locked! engine token outcome chunks))))

  ;; --- the engine's thread ---------------------------------------------------------------

  ;; multi-quick-exit-verdict : Integer -> (U 'set 'unknown #f)
  ;; What curl_multi_setopt's CODE for CURLMOPT_QUICK_EXIT at 1 says: set,
  ;; for CURLM_OK; unknown, for CURLM_UNKNOWN_OPTION, from a libcurl older
  ;; than the option; #f for any other, which refuses the engine (ADR-0019,
  ;; decision 2).
  (define (multi-quick-exit-verdict code)
    (cond ((eqv? code curlm-ok) 'set)
          ((eqv? code curlm-unknown-option) 'unknown)
          (else #f)))

  ;; run-engine : Engine -> Void
  ;; The engine's thread: its multi handle, made and recorded in one
  ;; critical section, its CURLMOPT_QUICK_EXIT set and judged, unless left
  ;; out, then its slot, made and recorded in one critical section, then
  ;; the loop, under a guard whose handler fails the engine.
  (define (run-engine engine)
    (guard (e (#t (fail-engine! engine e)))
      (fault-at! engine 'start)
      (critical-section
       (let ((multi (curl-multi-init)))
         (when (eqv? multi 0)
           (error 'make-curl-engine "curl_multi_init returned NULL: no memory for a multi handle"))
         (locked (curl-engine-lock engine) (lambda () (engine-multi-set! engine multi)))))
      (let ((verdict (if (memq 'multi (engine-without engine))
                         'off
                         (let* ((answer (curl-multi-setopt-long (engine-multi engine) curlmopt-quick-exit 1))
                                (code (or (engine-answer engine) answer)))
                           (or (multi-quick-exit-verdict code)
                               (multi-failed 'curl_multi_setopt code))))))
        (locked (curl-engine-lock engine) (lambda () (engine-quick-exit-set! engine verdict))))
      (critical-section (engine-slot-set! engine (foreign-block (foreign-sizeof 'int))))
      (locked (curl-engine-lock engine)
        (lambda ()
          (engine-thread-set! engine (get-thread-id))
          (engine-state-set! engine 'running)))
      (turns engine (engine-multi engine))))

  ;; free-slot! : Engine -> Void
  ;; The slot freed, and its record cleared, in one critical section; none
  ;; made, nothing freed.
  (define (free-slot! engine)
    (critical-section
     (let ((slot (engine-slot engine)))
       (when slot
         (free-foreign-block! slot)
         (engine-slot-set! engine #f)))))

  ;; turns : Engine Positive-Integer -> Void
  ;; The loop, steps 1 to 6, until a stop.
  (define (turns engine multi)
    (let turn ()
      (let ((messages (take-queue! engine)))
        (if (assq 'stop messages)
            (shut-down! engine multi messages)
            (begin
              (for-each (lambda (message)
                          (when (eq? (car message) 'submit) (set-up! engine multi (cdr message))))
                        messages)
              (for-each (lambda (message)
                          (when (eq? (car message) 'cancel) (cancel! engine multi (cdr message))))
                        messages)
              (engine-batch-set! engine '())
              (unless (live-empty? engine) (fault-at! engine 'perform))
              (let-values (((code running) (curl-multi-perform multi (engine-slot engine))))
                (unless (eqv? code curlm-ok) (multi-failed 'curl_multi_perform code)))
              (read-finished! engine multi)
              (unless (live-empty? engine) (fault-at! engine 'poll))
              (let ((code (curl-multi-poll multi 1000)))
                (unless (eqv? code curlm-ok) (multi-failed 'curl_multi_poll code)))
              (turn))))))

  ;; multi-failed : Symbol Integer -> Nothing
  (define (multi-failed entry code)
    (error 'curl-engine (string-append (symbol->string entry) " answered a CURLMcode")
           code (curl-multi-strerror code)))

  ;; take-queue! : Engine -> (Listof Message)
  ;; Step 1: the queue, oldest first, emptied, each submitted token not done
  ;; yet marked live, under the mutex. The batch is kept, on this thread,
  ;; until the turn has dealt with it. A fault planted at take raises in the
  ;; same hold, when the queue holds a message, before it is taken: so those
  ;; messages stay queued, for the failure to complete.
  (define (take-queue! engine)
    (let ((messages
           (locked (curl-engine-lock engine)
             (lambda ()
               (unless (null? (curl-engine-queue engine)) (fault-at! engine 'take))
               (let ((messages (reverse (curl-engine-queue engine))))
                 (curl-engine-queue-set! engine '())
                 (for-each (lambda (message)
                             (when (and (eq? (car message) 'submit)
                                        (eq? (token-state (cdr message)) 'queued))
                               (token-state-set! (cdr message) 'live)))
                           messages)
                 messages)))))
      (engine-batch-set! engine messages)
      messages))

  ;; live-empty? : Engine -> Boolean
  (define (live-empty? engine)
    (locked (curl-engine-lock engine) (lambda () (= (hashtable-size (engine-live engine)) 0))))

  ;; set-up! : Engine Positive-Integer Token -> Void
  ;; Step 2: TOKEN's transfer started, recorded in the table, and added to
  ;; MULTI. A token already done, cancelled while queued, is passed over. A
  ;; raise from start-transfer!, which has freed what it made, completes the
  ;; token with it: the transfer's own failure, not the engine's.
  (define (set-up! engine multi token)
    (unless (curl-token-done? token)
      (fault-at! engine 'setup)
      (let ((live (guard (e (#t (complete! engine token e '()) #f))
                    (start-transfer! (curl-token-plan token)
                                     (not (memq 'transfer (engine-without engine)))))))
        (when live
          (token-live-set! token live)
          (locked (curl-engine-lock engine)
            (lambda () (hashtable-set! (engine-live engine) (live-transfer-easy live) (cons token live))))
          (let ((code (curl-multi-add-handle multi (live-transfer-easy live))))
            (unless (eqv? code curlm-ok) (multi-failed 'curl_multi_add_handle code)))))))

  ;; take-out! : Engine Positive-Integer Token -> (Listof Any)
  ;; TOKEN's live transfer removed from MULTI, freed, then taken out of the
  ;; table: its chunks, read first. The table lets the transfer go last, so a
  ;; raise on the way leaves it there, and the engine's failure completes
  ;; its token.
  (define (take-out! engine multi token)
    (let* ((live (token-live token))
           (easy (live-transfer-easy live))
           (chunks (live-transfer-chunks live))
           (code (curl-multi-remove-handle multi easy)))
      (unless (eqv? code curlm-ok) (multi-failed 'curl_multi_remove_handle code))
      (free-transfer! live)
      (fault-at! engine 'free)
      (locked (curl-engine-lock engine) (lambda () (hashtable-delete! (engine-live engine) easy)))
      (token-live-set! token #f)
      chunks))

  ;; cancel! : Engine Positive-Integer Token -> Void
  ;; Step 3: TOKEN's transfer, while it is live, taken out, and TOKEN
  ;; completed as cancelled. A token done since, its transfer having ended
  ;; in the turn the cancel came in, is left, and counted as stale.
  (define (cancel! engine multi token)
    (if (token-live token)
        (begin
          (fault-at! engine 'cancel)
          (let ((chunks (take-out! engine multi token)))
            (complete! engine token (transfer-ended 'cancelled) chunks)))
        (locked (curl-engine-lock engine)
          (lambda () (engine-stale-set! engine (+ (engine-stale engine) 1))))))

  ;; read-finished! : Engine Positive-Integer -> Void
  ;; Step 5: every message curl_multi_info_read holds; for each transfer
  ;; done, what it ended with, read before anything is freed, then taken
  ;; out, and its token completed with that and its chunks. A raise while
  ;; reading is the transfer's outcome.
  (define (read-finished! engine multi)
    (let drain ()
      (let ((message (curl-multi-info-read multi (engine-slot engine))))
        (when message
          (when (eqv? (car message) curlmsg-done)
            (let ((entry (locked (curl-engine-lock engine)
                           (lambda () (hashtable-ref (engine-live engine) (cadr message) #f)))))
              (when entry
                (fault-at! engine 'read)
                (let* ((token (car entry))
                       (outcome (guard (e (#t e)) (finish-transfer (cdr entry) (caddr message))))
                       (chunks (take-out! engine multi token)))
                  (complete! engine token outcome chunks)))))
          (drain)))))

  ;; shut-down! : Engine Positive-Integer (Listof Message) -> Void
  ;; A stop: every token MESSAGES submitted completed as stopped, unset up;
  ;; each cancel carried out; every live transfer taken out and completed as
  ;; stopped; the table checked empty; the multi handle cleaned up; and the
  ;; stop signalled, the thread's last act.
  (define (shut-down! engine multi messages)
    (for-each (lambda (message)
                (when (eq? (car message) 'submit)
                  (complete! engine (cdr message) (transfer-ended 'stopped) '())))
              messages)
    (for-each (lambda (message)
                (when (eq? (car message) 'cancel) (cancel! engine multi (cdr message))))
              messages)
    (engine-batch-set! engine '())
    (for-each (lambda (keyed)
                (let* ((token (cadr keyed))
                       (chunks (take-out! engine multi token)))
                  (complete! engine token (transfer-ended 'stopped) chunks)))
              (live-entries engine))
    (unless (live-empty? engine)
      (error 'curl-engine-stop "the table of live transfers is not empty after a stop"))
    (let ((code (curl-multi-cleanup multi)))
      (locked (curl-engine-lock engine) (lambda () (engine-multi-set! engine #f)))
      (unless (eqv? code curlm-ok) (multi-failed 'curl_multi_cleanup code)))
    (free-slot! engine)
    (locked (curl-engine-lock engine)
      (lambda ()
        (engine-state-set! engine 'stopped))))

  ;; live-entries : Engine -> (Listof (Pairof Positive-Integer (Pairof Token Live)))
  ;; The table's entries, each with its key, the easy handle's address it was
  ;; recorded under: a key that stays right after the live record's easy
  ;; field is cleared.
  (define (live-entries engine)
    (locked (curl-engine-lock engine)
      (lambda ()
        (let-values (((easies entries) (hashtable-entries (engine-live engine))))
          (map cons (vector->list easies) (vector->list entries))))))

  ;; fail-engine! : Engine Any -> Void
  ;; RAISED fails ENGINE (section 3.7): it is marked failing under the
  ;; mutex first, so no caller wakes its multi handle again and a submit
  ;; raises the failure; then every token queued, in the turn's batch, or
  ;; live completes with &curl-engine-error, reason failed, carrying RAISED;
  ;; every live transfer is taken out and freed, but an easy handle whose
  ;; removal failed, which stays counted, and the multi handle cleaned up,
  ;; each as far as it goes, so a free that fails leaves its count up; and
  ;; last, the engine is marked failed.
  ;; Nothing raised here leaves the thread.
  (define (fail-engine! engine raised)
    (let* ((failure (engine-error 'failed raised))
           (lock (curl-engine-lock engine))
           (queued (locked lock
                     (lambda ()
                       (engine-state-set! engine 'failing)
                       (engine-failure-set! engine failure)
                       (let ((messages (curl-engine-queue engine)))
                         (curl-engine-queue-set! engine '())
                         messages))))
           (multi (locked lock (lambda () (engine-multi engine)))))
      (for-each (lambda (message)
                  (when (eq? (car message) 'submit)
                    (complete! engine (cdr message) failure '())))
                (append (engine-batch engine) queued))
      (engine-batch-set! engine '())
      (for-each (lambda (keyed)
                  (let ((key (car keyed)) (token (cadr keyed)) (live (cddr keyed)))
                    (let* ((chunks (guard (e (#t '())) (live-transfer-chunks live)))
                           (easy (live-transfer-easy live))
                           (removed (and multi easy
                                         (guard (e (#t #f))
                                           (eqv? (curl-multi-remove-handle multi easy) curlm-ok)))))
                      ;; A handle still in the multi handle is not freed:
                      ;; curl_easy_cleanup would remove it, which can
                      ;; block. It stays counted, so a suite sees it.
                      (unless removed (abandon-transfer-easy! live))
                      (guard (e (#t #f)) (free-transfer! live))
                      (locked lock (lambda () (hashtable-delete! (engine-live engine) key)))
                      (token-live-set! token #f)
                      (complete! engine token failure chunks))))
                (live-entries engine))
      (when multi
        (guard (e (#t #f)) (curl-multi-cleanup multi)))
      (guard (e (#t #f)) (free-slot! engine))
      (locked lock
        (lambda ()
          (engine-multi-set! engine #f)
          (engine-state-set! engine 'failed))))))
