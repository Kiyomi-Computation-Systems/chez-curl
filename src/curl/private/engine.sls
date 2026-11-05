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
;;; Messages cross threads; handle calls don't. A submit, a cancel, a
;;; resume, a cookie jar's message and a stop are queued under the engine's
;;; mutex, and then curl_multi_wakeup
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
;;;             transfers, by its easy handle's address; and each cookie
;;;             jar's message carried out, submits and jar messages alike in
;;;             the order queued;
;;;   3. cancel each live transfer a cancel names: taken out and completed
;;;             as cancelled; then a stop, which ends the loop;
;;;   4. resume each live streamed transfer a resume names, the fourth
;;;             message (ADR-0012, amended 2026-10-29): its pause state
;;;             cleared, then curl_easy_pause, holding no mutex and outside
;;;             any critical section; an answer but 0 fails it; a resume
;;;             for a token taken out since is passed over;
;;;   5. perform curl_multi_perform;
;;;   6. read   each finished transfer, by curl_multi_info_read: what it
;;;             ended with, read by finish-transfer, then taken out and its
;;;             token completed;
;;;   7. look   at the queue, under the mutex: a message queued skips the
;;;             poll, and the next turn begins (ADR-0012, amended
;;;             2026-10-30);
;;;   8. poll   curl_multi_poll, for at most 1000 ms: libcurl shortens the
;;;             wait to its own timers, and a wakeup ends it; a poll under
;;;             1 ms, in a turn that took no message and moved no byte,
;;;             while a transfer is paused, is followed by a sleep of 1 ms,
;;;             the paced poll (ADR-0012, amended 2026-10-29).
;;;
;;; A streamed response (ADR-0030; the M6 plan, sections 3.2 to 3.5) is
;;; the token's: its head, published by the header callable, its pieces,
;;; taken by curl-token-next-piece or read through curl-token-body-port.
;;; Every look at the stream decides the resume, and queues one when the
;;; transfer is paused, none is queued, and the buffer is at half its
;;; stream-buffer or less. The lock order is the engine's mutex, then a
;;; stream's, as the engine's, then a mailbox's. On libcurl 8.7.0 and
;;; 8.7.1 the multi handle multiplexes nothing (ADR-0030, amended
;;; 2026-10-29); before 8.19.0 it stops multiplexing, for good, at its
;;; first transfer through a proxy URL that holds userinfo (ADR-0037,
;;; decision 11; ADR-0030, amended 2026-11-03).
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
;;; The cookie jar (ADR-0035, amended twice; the M7 plan, section 3.5): a
;;; curl_share of cookies, made, used and freed on this thread, by message:
;;; make, read out, load and close, each a message queued beside submits,
;;; taken with them in the order queued, and answered through a reply the
;;; caller waits on, as curl-engine-stop waits, with no bound: the engine
;;; answers every jar message, at its turn, at a stop, or at its failure.
;;; A jar's share and its own easy handle, the one its messages use,
;;; attached to the share, are each made, and freed, in one critical
;;; section with its count and its record; the handle is freed first, since
;;; curl_share_cleanup answers CURLSHE_IN_USE while any handle holds the
;;; share. A transfer holds the jar from the hold that records it live,
;;; once start-transfer! has returned, to its take-out, counted in the
;;; jar's holders and kept in the engine's table of holds, so it is let go
;;; once: a start-transfer! that raises has freed its handle, and held
;;; nothing. A close sets a live jar closing, and frees it at once when no
;;; transfer holds it; otherwise the last to let it go frees it, the jar
;;; marked closed in the share's section. set-up! checks the jar on this
;;; thread, and a jar not live, or another engine's, fails the token, as
;;; cookie-jar-closed or cookie-jar-engine: the submit's check of the same
;;; is an early refusal only, since a close and a submit on two threads can
;;; cross. A stop frees every jar, live or closing, once every live
;;; transfer is taken out; a failure lets go of each transfer it frees, and
;;; keeps the hold of each handle it abandons, whose share stays in use and
;;; counted.
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
  (export make-curl-engine curl-engine? curl-submit
          curl-engine-stop curl-engine-request-stop! curl-engine-state curl-engine-thread
          curl-engine-multi curl-engine-live-count curl-engine-queued-count
          curl-engine-stale-cancels call-with-engine-held
          curl-token? curl-token-await curl-token-wait curl-token-cancel curl-token-done?
          curl-token-outcome curl-token-chunks
          make-curl-mailbox curl-mailbox? curl-mailbox-take curl-mailbox-deliver
          call-with-mailbox-held
          make-faulty-curl-engine engine-fault-steps planted-engine-fault
          make-curl-engine-without-quick-exit make-curl-engine-answering-quick-exit
          curl-engine-quick-exit multi-quick-exit-verdict
          curl-token-head-wait curl-token-head curl-token-next-piece curl-token-body-port
          make-curl-engine-unpaced make-curl-engine-unmultiplexed
          make-curl-engine-answering-pause curl-engine-multiplexing multiplexing-off?
          unmultiplexed-versions curl-engine-paced-sleeps curl-engine-passed-resumes
          curl-engine-arm-late-message! curl-engine-late-message
          curl-token-stream-stats call-with-stream-held curl-token-plant! curl-token-gate
          curl-token-open-gate! curl-token-plant-stall! curl-token-stall-state
          curl-engine-probe-turns! curl-engine-probe
          curl-token-room-wait curl-token-put-piece! curl-token-end-body! curl-token-body-count
          curl-token-upload-stats call-with-upload-held make-curl-engine-reusing
          make-curl-engine-rewinding curl-token-plant-put! make-curl-engine-stalling-completion
          make-curl-engine-holding-prereq curl-engine-prereq-holds
          make-curl-cookie-jar curl-cookie-jar-cookies curl-cookie-jar-load! curl-cookie-jar-close!
          curl-cookie-jar-post! curl-cookie-jar-await curl-cookie-jar-state curl-cookie-jar-holders
          curl-engine-jar-count make-curl-engine-answering-jar make-curl-engine-delaying-take
          make-curl-engine-abandoning make-curl-cookie-jar-sharing)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) critical-section disable-interrupts enable-interrupts fork-thread
                get-thread-id make-mutex with-mutex make-time sleep foreign-sizeof
                current-time time-second time-nanosecond)
          (curl private conditions)
          (curl private constants)
          (curl private memory)
          (curl private native)
          (only (curl private libcurl-info) libcurl-info-version)
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
      (assertion-violation who "a bound is a natural number of milliseconds" (shown-value ms)))
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
  ;; other test seam. Then, from M6 (the plan's section 3.4): its seams, a
  ;; list, empty but for a test seam's, of unpaced, which turns the paced
  ;; poll off, unmultiplexed, which sets CURLMOPT_PIPELINING to 0 on any
  ;; libcurl, (pause-answer . CODE), a CURLcode its thread takes in
  ;; place of curl_easy_pause's answer, reusing, which leaves FRESH_CONNECT
  ;; off a streamed body, rewinding, which lets its seek callable
  ;; answer OK once bytes were handed, (completion-stall . MS), a
  ;; sleep between a finished transfer's outcome and its completion, and
  ;; (prereq-hold . HOLD) beside (prereq-holds . COUNT), the hold a
  ;; streamed body's prerequest callable makes at its first attempt and
  ;; the count of those made; its counter of callables' calls that
  ;; took bytes, a vector of one natural its thread alone writes and reads;
  ;; and, under the mutex, whether its multi handle multiplexes, default or
  ;; off, #f until its thread decides; the paced sleeps it has made; the
  ;; resumes it has passed over; the late message's state, #f but for
  ;; the look's test seam; and the paced poll's probe, #f but for its test
  ;; seam, a vector of the turns it has left, whether it marks them, and
  ;; the polls, fast polls, fast polls in turns that moved bytes, and
  ;; paced sleeps it has seen. Then, from M7 slice 4, under the mutex: its
  ;; cookie jars, each made and not yet freed, live or closing; and its
  ;; table of holds, by token, each the jar a live transfer holds.
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
            (immutable answer engine-answer)
            (immutable seams engine-seams)
            (immutable moves engine-moves)
            (mutable multiplexing engine-multiplexing engine-multiplexing-set!)
            (mutable paced engine-paced engine-paced-set!)
            (mutable passed engine-passed engine-passed-set!)
            (mutable late engine-late engine-late-set!)
            (mutable probe engine-probe engine-probe-set!)
            (mutable jars engine-jars engine-jars-set!)
            (immutable holds engine-holds))
    ;; Opaque: Chez prints a record's every field, and an engine's queue and
    ;; table hold its tokens, so a printed engine, or a token's assertion
    ;; that printed its engine, showed another request's credentials (the
    ;; review of M7 slice 2). An engine prints as #<curl-engine>.
    (opaque #t))

  ;; A token: its engine and its plan; under the engine's mutex, its state,
  ;; queued, live or done, its outcome, a response or a condition, and its
  ;; chunks, write-body's log; on the engine's thread alone, its live
  ;; transfer while it has one; and the mailbox it goes to when done, and
  ;; the callback a delivery calls, each #f for none (ADR-0021). For a
  ;; streamed response (the M6 plan, section 3.5), under the engine's
  ;; mutex: whether its port has been made; and the plant a test seam sets
  ;; in its takes, #f, spin, or a gate, a vector of its one phase, armed,
  ;; waiting or open: data, never a procedure.
  (define-record-type (curl-token make-token curl-token?)
    (fields (immutable engine curl-token-engine)
            (immutable plan curl-token-plan)
            (mutable state token-state token-state-set!)
            (mutable outcome token-outcome token-outcome-set!)
            (mutable chunks token-chunks token-chunks-set!)
            (mutable live token-live token-live-set!)
            (immutable mailbox token-mailbox)
            (immutable callback token-callback)
            (mutable port token-port token-port-set!)
            (mutable plant token-plant token-plant-set!))
    ;; Opaque: a token holds its plan, which holds its credentials, and its
    ;; engine; the token's own assertions hand it over whole as their
    ;; irritant. A token prints as #<curl-token>.
    (opaque #t))

  ;; A mailbox (ADR-0021): its mutex, and under it, its finished tokens,
  ;; oldest first, as two lists: front, oldest first, and back, newest
  ;; first, which a take turns round once front is empty.
  (define-record-type (curl-mailbox make-mailbox-record curl-mailbox?)
    (fields (immutable lock mailbox-lock)
            (mutable front mailbox-front mailbox-front-set!)
            (mutable back mailbox-back mailbox-back-set!))
    ;; Opaque, as the tokens it holds are.
    (opaque #t))

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

  ;; unmultiplexed-versions : (Listof String)
  ;; The libcurl versions on which the engine multiplexes nothing: 8.7.0 and
  ;; 8.7.1. On Apple's 8.7.1 a paused HTTP/2 stream beside an active one
  ;; filled libcurl's 64 MiB cap and failed the connection, and a write
  ;; callback's error on one stream failed its sibling (ADR-0030, amended
  ;; 2026-10-29). tests/test-stream.sps holds it to its own copy.
  (define unmultiplexed-versions '("8.7.0" "8.7.1"))

  ;; multiplexing-off? : String -> Boolean
  ;; Whether an engine on the libcurl at VERSION sets CURLMOPT_PIPELINING
  ;; to 0 as it makes its multi handle, so every HTTP/2 transfer has a
  ;; connection of its own: where unmultiplexed-versions names VERSION.
  ;; Pure.
  (define (multiplexing-off? version)
    (and (member version unmultiplexed-versions) #t))

  ;; curl-engine-multiplexing : Engine -> (U 'default 'off 'switched)
  ;; What ENGINE's thread did with CURLMOPT_PIPELINING: default, left as
  ;; libcurl has it; off, set to 0 as it made its multi handle, as
  ;; multiplexing-off? says, or the test seam make-curl-engine-unmultiplexed
  ;; forces; or switched, set to 0 later, at the first transfer whose plan
  ;; stops multiplexing (stop-multiplexing!), never back. A private
  ;; accessor. An engine returned running has decided whether it starts.
  (define (curl-engine-multiplexing engine)
    (check-engine 'curl-engine-multiplexing engine)
    (locked (curl-engine-lock engine) (lambda () (engine-multiplexing engine))))

  ;; curl-engine-paced-sleeps : Engine -> Natural
  ;; How many 1 ms sleeps ENGINE's paced poll has made: a private accessor.
  (define (curl-engine-paced-sleeps engine)
    (check-engine 'curl-engine-paced-sleeps engine)
    (locked (curl-engine-lock engine) (lambda () (engine-paced engine))))

  ;; curl-engine-passed-resumes : Engine -> Natural
  ;; How many resume messages ENGINE has passed over, their token taken out
  ;; since they were queued: a private accessor (the M6 plan, section 3.4).
  (define (curl-engine-passed-resumes engine)
    (check-engine 'curl-engine-passed-resumes engine)
    (locked (curl-engine-lock engine) (lambda () (engine-passed engine))))

  ;; curl-engine-arm-late-message! : Engine -> Void
  ;; The look's test seam, private (ADR-0012, amended 2026-10-30): the next
  ;; turn of ENGINE's that carries out a resume queues a message of its
  ;; own, a mark, from its own thread, with its wakeup, between its resume
  ;; step and its perform, as a caller's thread could at that moment; and
  ;; the turn that takes it records when. Guix's 8.20.0 reads that wakeup
  ;; back inside the perform: without the look, the poll then waits for
  ;; libcurl alone.
  (define (curl-engine-arm-late-message! engine)
    (check-engine 'curl-engine-arm-late-message! engine)
    (locked (curl-engine-lock engine) (lambda () (engine-late-set! engine 'armed))))

  ;; curl-engine-late-message : Engine -> (U #f 'armed (List 'queued Integer) (List 'taken Integer Integer))
  ;; Where the late message stands: #f, never armed; armed; queued at a
  ;; monotonic time in ns; or taken, queued at the first and taken by a
  ;; turn at the second. A private accessor.
  (define (curl-engine-late-message engine)
    (check-engine 'curl-engine-late-message engine)
    (locked (curl-engine-lock engine) (lambda () (engine-late engine))))

  ;; curl-engine-probe-turns! : Engine Positive-Integer Boolean -> Void
  ;; The paced poll's test seam, private: ENGINE's next N turns that reach
  ;; the poll each wake it first, from the engine's own thread, so it
  ;; returns at once, and record whether it returned in under 1 ms, whether
  ;; a callable took bytes in the turn, and whether the turn then paced;
  ;; with MARK, each such turn's batch also
  ;; carries a message of the seam's own, (probe), which nothing carries
  ;; out. Armed in a hold of the mutex, with a wakeup while the engine runs,
  ;; as every caller's wakeup is: a stopping or failing engine cleans its
  ;; multi handle up before it clears its record; the counts start from 0.
  (define (curl-engine-probe-turns! engine n mark)
    (check-engine 'curl-engine-probe-turns! engine)
    (unless (and (integer? n) (exact? n) (positive? n))
      (assertion-violation 'curl-engine-probe-turns! "turns are a positive exact integer" n))
    (locked (curl-engine-lock engine)
      (lambda ()
        (engine-probe-set! engine (vector n (and mark #t) 0 0 0 0))
        (when (eq? (engine-state engine) 'running)
          (curl-multi-wakeup (engine-multi engine))))))

  ;; curl-engine-probe : Engine -> (U #f (List Natural Natural Natural Natural Natural))
  ;; The probe's (LEFT POLLS FAST MOVED PACED): the turns it has left, and
  ;; the polls, the polls that returned in under 1 ms, those of them in
  ;; turns whose callables took bytes, and the paced sleeps, of the turns
  ;; it has seen; #f, never armed. A private accessor.
  (define (curl-engine-probe engine)
    (check-engine 'curl-engine-probe engine)
    (locked (curl-engine-lock engine)
      (lambda ()
        (let ((probe (engine-probe engine)))
          (and probe (list (vector-ref probe 0) (vector-ref probe 2) (vector-ref probe 3)
                           (vector-ref probe 4) (vector-ref probe 5)))))))

  ;; probing? : Engine -> Boolean
  ;; Whether the probe has a turn left, read in a hold.
  (define (probing? engine)
    (locked (curl-engine-lock engine)
      (lambda () (let ((probe (engine-probe engine))) (and probe (> (vector-ref probe 0) 0))))))

  ;; probe-turn! : Engine Boolean Boolean Boolean -> Void
  ;; One probed turn seen, its poll FAST or not, its callables having MOVED
  ;; bytes or not, PACED or not, in one hold.
  (define (probe-turn! engine fast moved paced)
    (locked (curl-engine-lock engine)
      (lambda ()
        (let ((probe (engine-probe engine)))
          (vector-set! probe 0 (- (vector-ref probe 0) 1))
          (vector-set! probe 2 (+ (vector-ref probe 2) 1))
          (when fast (vector-set! probe 3 (+ (vector-ref probe 3) 1)))
          (when (and fast moved) (vector-set! probe 4 (+ (vector-ref probe 4) 1)))
          (when paced (vector-set! probe 5 (+ (vector-ref probe 5) 1)))))))

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

  ;; curl-token-outcome : Token -> (U Response Condition #f)
  ;; TOKEN's outcome once it is done, as data: the response curl-token-await
  ;; answers, or the condition it raises, the same object; #f while it is
  ;; not done. It never waits and never raises the outcome, so it may run
  ;; inside a critical section, and a caller that waits with curl-token-wait
  ;; reads a failure with no guard around the wait, where a handler's own
  ;; raise could be taken for the transfer's (M5 slice 3's review).
  (define (curl-token-outcome token)
    (check-token 'curl-token-outcome token)
    (locked (curl-engine-lock (curl-token-engine token))
      (lambda () (and (eq? (token-state token) 'done) (token-outcome token)))))

  ;; curl-token-chunks : Token -> (U (Listof (List Positive-Integer Integer Symbol))
  ;;                                 (Listof (List Symbol Positive-Integer (Listof Integer))))
  ;; write-body's log of TOKEN's chunks, oldest first, once it is done: each
  ;; chunk's length, the get-thread-id it ran on, and its verdict
  ;; (live-transfer-chunks); () before, and for a token never set up. For a
  ;; streamed response, each verdict the write callable gave, with how many
  ;; calls gave it and the threads they ran on.
  (define (curl-token-chunks token)
    (check-token 'curl-token-chunks token)
    (locked (curl-engine-lock (curl-token-engine token)) (lambda () (token-chunks token))))

  (define (check-engine who x)
    (unless (curl-engine? x) (assertion-violation who "not an engine" (shown-value x))))

  (define (check-token who x)
    (unless (curl-token? x) (assertion-violation who "not a token" (shown-value x))))

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
  ;; resume, before a live streamed transfer's curl_easy_pause (the M6
  ;; plan, section 3.4); perform and poll, before curl_multi_perform and
  ;; curl_multi_poll, while a transfer is live; read, before a finished
  ;; transfer's finish-transfer; free, once a transfer is freed, its easy
  ;; handle with it, and before the table lets it go.
  (define engine-fault-steps '(start take setup cancel resume perform read poll free))

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
  (define (make-curl-engine) (start-engine #f '() #f '()))

  ;; make-faulty-curl-engine : Symbol -> Engine
  ;; make-curl-engine's, with a fault planted at STEP, one of
  ;; engine-fault-steps: the engine raises (planted-engine-fault STEP) the
  ;; first time it reaches it, so a fault at start raises here, as the
  ;; refusal. A test seam, private (section 3.7).
  (define (make-faulty-curl-engine step)
    (unless (memq step engine-fault-steps)
      (assertion-violation 'make-faulty-curl-engine "not a step of the engine's loop" step))
    (start-engine step '() #f '()))

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
      (start-engine #f copy #f '())))

  ;; make-curl-engine-answering-quick-exit : Integer -> Engine
  ;; make-curl-engine's, but its thread takes CODE, a CURLMcode, as libcurl's
  ;; answer to CURLMOPT_QUICK_EXIT, after making the call: a test seam,
  ;; private, so the test can watch an answer no libcurl gives refuse the
  ;; engine, its multi handle freed, as multi-quick-exit-verdict says
  ;; (ADR-0019, decision 2). No request reaches it.
  (define (make-curl-engine-answering-quick-exit code)
    (unless (and (integer? code) (exact? code))
      (assertion-violation 'make-curl-engine-answering-quick-exit "a CURLMcode is an exact integer" code))
    (start-engine #f '() code '()))

  ;; make-curl-engine-unpaced : -> Engine
  ;; make-curl-engine's, with its paced poll turned off: a test seam,
  ;; private, so the test can show the spin the pacing ends, on Ubuntu's
  ;; 8.5.0 (ADR-0012, amended 2026-10-29).
  (define (make-curl-engine-unpaced) (start-engine #f '() #f '(unpaced)))

  ;; make-curl-engine-unmultiplexed : -> Engine
  ;; make-curl-engine's, with CURLMOPT_PIPELINING at 0 whatever the libcurl,
  ;; as on 8.7.0 and 8.7.1: a test seam, private, so a Linux lane can watch
  ;; the setting by behaviour (ADR-0030, amended 2026-10-29).
  (define (make-curl-engine-unmultiplexed) (start-engine #f '() #f '(unmultiplexed)))

  ;; make-curl-engine-reusing : -> Engine
  ;; make-curl-engine's, but a streamed body's transfer leaves FRESH_CONNECT
  ;; off, so it may go on a pooled connection: a test seam, private, so the
  ;; test can watch the seek callable refuse libcurl's resend on a dead one
  ;; (ADR-0032, amended). No request reaches it: FRESH_CONNECT is owned.
  (define (make-curl-engine-reusing) (start-engine #f '() #f '(reusing)))

  ;; make-curl-engine-rewinding : -> Engine
  ;; make-curl-engine-reusing's, and its seek callable answers OK for an
  ;; offset of 0 from SEEK_SET once bytes were handed too: a test seam,
  ;; private, which puts libcurl's resend in front of the prerequest
  ;; callable on every libcurl (ADR-0032, amended).
  (define (make-curl-engine-rewinding) (start-engine #f '() #f '(reusing rewinding)))

  ;; make-curl-engine-stalling-completion : Positive-Integer -> Engine
  ;; make-curl-engine's, but its thread sleeps MS milliseconds between
  ;; reading each finished transfer's outcome and completing its token: a
  ;; test seam, private, so a test can put on a token whose request stream
  ;; has closed but which is not yet done (completion-stall!).
  (define (make-curl-engine-stalling-completion ms)
    (unless (and (integer? ms) (exact? ms) (positive? ms))
      (assertion-violation 'make-curl-engine-stalling-completion "a stall is a positive exact integer of milliseconds" ms))
    (start-engine #f '() #f (list (cons 'completion-stall ms))))

  ;; make-curl-engine-holding-prereq : Positive-Integer -> Engine
  ;; make-curl-engine's, but a streamed body's prerequest callable, at its
  ;; transfer's first attempt, once connected and before the request is
  ;; sent, sleeps MS milliseconds, then answers as it would: a test seam,
  ;; private, which stands for this thread paused there, by a collection
  ;; say, so that an answer written as the connection is accepted lands
  ;; before the request leaves; the head's body-asked bit then reads #f on
  ;; 7.85.0 and 8.5.0, which stop sending once they read it (M6 slice 2's
  ;; measurement). The sleep is HOLD, (prereq-hold . HOLD) in its seams,
  ;; which the callable calls outside its upload's hold. It is safe there:
  ;; the callable runs on this engine's thread, inside curl_multi_perform,
  ;; which the engine's turn calls outside every critical section and hold;
  ;; so it holds no mutex, and no caller's put, take or await waits on it,
  ;; for each polls in holds of its own; and with interrupts on, which HOLD
  ;; checks first, Chez's sleep deactivates the thread, so other threads'
  ;; collections go on meanwhile. The thread takes no message while it
  ;; sleeps, as completion-stall! does, and runs no caller code. Each hold
  ;; made is counted, under a mutex of its own taken after the sleep, for
  ;; curl-engine-prereq-holds.
  (define (make-curl-engine-holding-prereq ms)
    (unless (and (integer? ms) (exact? ms) (positive? ms))
      (assertion-violation 'make-curl-engine-holding-prereq "a hold is a positive exact integer of milliseconds" ms))
    (let ((count (vector (make-mutex) 0)))
      (start-engine #f '() #f
                    (list (cons 'prereq-hold
                                (lambda ()
                                  (require-interrupts-on 'make-curl-engine-holding-prereq)
                                  (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000)))
                                  (locked (vector-ref count 0)
                                    (lambda () (vector-set! count 1 (+ (vector-ref count 1) 1))))))
                          (cons 'prereq-holds count)))))

  ;; curl-engine-prereq-holds : Engine -> Natural
  ;; How many holds ENGINE's prerequest seam has made: 0 for an engine
  ;; without it. A private accessor, so a test sees the hold was made where
  ;; it holds, and never on a caller's engine.
  (define (curl-engine-prereq-holds engine)
    (let ((seam (find (lambda (seam) (and (pair? seam) (eq? (car seam) 'prereq-holds)))
                      (engine-seams engine))))
      (if seam
          (let ((count (cdr seam))) (locked (vector-ref count 0) (lambda () (vector-ref count 1))))
          0)))

  ;; make-curl-engine-answering-pause : Integer -> Engine
  ;; make-curl-engine's, but its thread takes CODE, a CURLcode, in place of
  ;; curl_easy_pause's answer at every resume, after making the call: a test
  ;; seam, private, so the test can watch an answer but 0 fail a transfer as
  ;; pause-failed on every libcurl (the M6 plan, section 3.4).
  (define (make-curl-engine-answering-pause code)
    (unless (and (integer? code) (exact? code))
      (assertion-violation 'make-curl-engine-answering-pause "a CURLcode is an exact integer" code))
    (start-engine #f '() #f (list (cons 'pause-answer code))))

  ;; make-curl-engine-answering-jar : (U 'make 'load 'read) Integer -> Engine
  ;; make-curl-engine's, but its thread takes CODE in place of libcurl's
  ;; answer, after making the call, at each of WHICH's: make,
  ;; curl_share_setopt's at a jar's make; load, CURLOPT_COOKIELIST's at each
  ;; line of a load; read, CURLINFO_COOKIELIST's at a read-out. A test seam,
  ;; private, so the test can watch an answer no libcurl gives here fail the
  ;; message, every answer read (ADR-0035; the M7 plan, section 3.5).
  (define (make-curl-engine-answering-jar which code)
    (unless (memq which '(make load read))
      (assertion-violation 'make-curl-engine-answering-jar "the call is make, load or read" which))
    (unless (and (integer? code) (exact? code))
      (assertion-violation 'make-curl-engine-answering-jar "an answer is an exact integer" code))
    (start-engine #f '() #f (list (cons 'jar-answer (cons which code)))))

  ;; make-curl-engine-delaying-take : Positive-Integer -> Engine
  ;; make-curl-engine's, but its thread sleeps MS milliseconds, holding
  ;; nothing, before each turn takes its queue: a test seam, private, which
  ;; widens the time between a message's queueing and its being carried out,
  ;; so a close and a submit that cross land in each of their three outcomes
  ;; on purpose, under Valgrind too, whose threads run one at a time.
  (define (make-curl-engine-delaying-take ms)
    (unless (and (integer? ms) (exact? ms) (positive? ms))
      (assertion-violation 'make-curl-engine-delaying-take "a delay is a positive exact integer of milliseconds" ms))
    (start-engine #f '() #f (list (cons 'take-delay ms))))

  ;; make-curl-engine-abandoning : Symbol -> Engine
  ;; make-faulty-curl-engine's, the fault planted at STEP, and its failure
  ;; abandons the easy handle of every live transfer, as for one whose
  ;; removal from the multi handle failed: a test seam, private, so a test
  ;; can watch an abandoned handle keep its jar's share in use, and both
  ;; stay counted (the M7 plan, section 3.5). Its process keeps them for
  ;; good: a child runs it, and prints its counts.
  (define (make-curl-engine-abandoning step)
    (unless (memq step engine-fault-steps)
      (assertion-violation 'make-curl-engine-abandoning "not a step of the engine's loop" step))
    (start-engine step '() #f '(abandoning)))

  ;; start-engine : (U Symbol #f) (Listof (U 'transfer 'multi)) (U Integer #f) (Listof Seam) -> Engine
  (define (start-engine fault without answer seams)
    (require-interrupts-on 'make-curl-engine)
    (loaded-libcurl)
    (let ((engine (make-engine-record (make-mutex) '() 'starting #f #f #f
                                      (make-eqv-hashtable) fault '() #f 0 without #f answer
                                      seams (make-vector 1 0) #f 0 0 #f #f '() (make-eq-hashtable))))
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
  ;;     stopped, or failed, with what it failed with;
  ;;   - then, in the hold that would queue it, a request whose cookie-jar
  ;;     is another engine's, cookie-jar-engine, or not live,
  ;;     cookie-jar-closed: &curl-request-error, field cookie-jar. An early
  ;;     refusal only: set-up! checks the jar again, on the engine's thread,
  ;;     where a close that crossed this submit fails its token so.
  (define curl-submit
    (case-lambda
      ((engine request) (submit engine request #f #f))
      ((engine request mailbox) (submit engine request mailbox #f))
      ((engine request mailbox callback) (submit engine request mailbox callback))))

  ;; submit : Engine Request (U Mailbox #f) (U Procedure #f) -> Token
  (define (submit engine request mailbox callback)
    (define who 'curl-submit)
    (check-engine who engine)
    (unless (or (not mailbox) (curl-mailbox? mailbox))
      (assertion-violation who "not a mailbox" (shown-value mailbox)))
    (unless (or (not callback) (procedure? callback))
      (assertion-violation who "a callback is a procedure of one argument, the token" (shown-value callback)))
    (when (and callback (not mailbox))
      (assertion-violation who "a callback needs a mailbox, which a delivery calls it from" (shown-value callback)))
    (let* ((plan (prepare-transfer request))
           (jar (plan-jar plan))
           (token (make-token engine plan 'queued #f '() #f mailbox callback #f #f))
           (refusal
            (locked (curl-engine-lock engine)
              (lambda ()
                (case (engine-state engine)
                  ((running)
                   (cond ((and jar (not (eq? (cookie-jar-engine jar) engine)))
                          (jar-refusal who 'cookie-jar-engine))
                         ((and jar (not (eq? (cookie-jar-state jar) 'live)))
                          (jar-refusal who 'cookie-jar-closed))
                         (else
                          (curl-engine-queue-set! engine (cons (cons 'submit token) (curl-engine-queue engine)))
                          (curl-multi-wakeup (engine-multi engine))
                          #f)))
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

  ;; --- the response stream (ADR-0030; the M6 plan, sections 3.2 to 3.5) ------------------

  ;; token-stream : Symbol Any -> Stream
  ;; TOKEN's response stream; a token whose request does not stream its
  ;; response is an assertion violation from WHO, as is what is no token.
  (define (token-stream who token)
    (check-token who token)
    (or (plan-stream (curl-token-plan token))
        (assertion-violation who "the token's request does not stream its response: give it a stream-buffer"
                             token)))

  ;; look : Token Stream -> (List Boolean (U Pair #f) (U Bytevector #f))
  ;; One look at TOKEN's STREAM, in one critical section of three holds,
  ;; one after the other, never nested: the engine's mutex, whether TOKEN
  ;; is done, read first, so the last piece is never taken for the end;
  ;; then the stream's, the next piece, left in place, and whether this
  ;; look queues a resume, stream-look!'s rule, its flag set there; then,
  ;; when it does, the engine's again, the resume queued, while TOKEN is
  ;; live and its engine running. An escape cannot fall between the flag
  ;; and the message (the M6 plan, section 3.4). Every look decides the
  ;; resume, a take's and a wait's alike (section 3.5).
  (define (look token stream)
    (let ((engine (curl-token-engine token)))
      (critical-section
       (let* ((done (locked (curl-engine-lock engine) (lambda () (eq? (token-state token) 'done))))
              (seen (stream-look! stream (monotonic-ns))))
         (when (caddr seen)
           (locked (curl-engine-lock engine)
             (lambda ()
               (when (and (eq? (token-state token) 'live) (eq? (engine-state engine) 'running))
                 (curl-engine-queue-set! engine (cons (cons 'resume token) (curl-engine-queue engine)))
                 (curl-multi-wakeup (engine-multi engine))))))
         (list done (car seen) (cadr seen))))))

  ;; remove-taken! : Token Stream Pair Bytevector -> Void
  ;; The take's removal of PIECE, at NODE, after its look's section: the
  ;; last thing a take does before it returns PIECE (the M6 plan, section
  ;; 3.5). A plant, a test seam's, holds it up here: a gate waits, between
  ;; the look and the removal, until the test opens it; spin runs a loop
  ;; after the removal, where an expiry can land, the timer sweep's planted
  ;; control. Without one, the removal is the last call.
  (define (remove-taken! token stream node piece)
    (let ((plant (token-plant token)))
      (if (not plant)
          (stream-remove! stream node piece)
          (planted-removal! token stream node piece plant))))

  ;; planted-removal! : Token Stream Pair Bytevector (U 'spin Vector) -> Void
  (define (planted-removal! token stream node piece plant)
    (if (eq? plant 'spin)
        (begin
          (stream-remove! stream node piece)
          (let loop ((i 0)) (unless (= i 3) (loop (+ i 1)))))
        (let ((lock (curl-token-engine-lock token)))
          (locked lock (lambda () (vector-set! plant 0 'waiting)))
          (let wait ()
            (unless (locked lock (lambda () (eq? (vector-ref plant 0) 'open)))
              (sleep (make-time 'time-duration 1000000 0))
              (wait)))
          (locked lock (lambda () (token-plant-set! token #f)))
          (stream-remove! stream node piece))))

  ;; curl-token-engine-lock : Token -> Mutex
  (define (curl-token-engine-lock token) (curl-engine-lock (curl-token-engine token)))

  ;; curl-token-next-piece : Token Natural -> (U Bytevector Eof #f)
  ;; TOKEN's next piece, a bytevector of a byte or more that the caller
  ;; owns; the eof object once every piece has been taken and TOKEN is
  ;; done, however its transfer ended, which curl-token-outcome then tells;
  ;; or #f once MS milliseconds pass with neither (ADR-0030, decision 4). It
  ;; never raises the transfer's failure. Each look decides the resume; the
  ;; take leaves the piece in the stream through its look's critical
  ;; section, and removes it the last thing before it returns, so a Ctrl-C
  ;; handler that escapes as that section ends leaves it for the next take
  ;; (the M6 plan, section 3.5). It waits as await does, polling, and a wait
  ;; inside a critical section is an assertion violation, before it sleeps.
  ;; A token whose request does not stream its response is an assertion
  ;; violation. A token has one taker at a time: the removal writes the
  ;; taker's own fields, outside any hold, so two threads taking from one
  ;; token at once could each be given the same piece.
  (define (curl-token-next-piece token ms)
    (let ((stream (token-stream 'curl-token-next-piece token))
          (deadline (deadline-after 'curl-token-next-piece ms)))
      (let loop ((pause 50000))
        (let* ((seen (look token stream)) (node (cadr seen)) (piece (caddr seen)))
          (cond
            (piece (remove-taken! token stream node piece) piece)
            ((car seen) (eof-object))
            (else
             (let ((left (- deadline (monotonic-ns))))
               (and (> left 0)
                    (begin
                      (require-interrupts-on 'curl-token-next-piece)
                      (sleep (make-time 'time-duration (min pause left) 0))
                      (loop (min (* pause 2) 10000000)))))))))))

  ;; curl-token-body-port : Token -> Binary-Input-Port
  ;; A custom binary input port over TOKEN's pieces, made once per token
  ;; (the M6 plan, section 3.5). A read copies from the piece at hand, or
  ;; takes the next as curl-token-next-piece does, the piece at hand set
  ;; after the removal; with none ready it waits, polling, a wait inside a
  ;; critical section an assertion violation, before it sleeps. Its ends
  ;; stick: 0, the end, once every piece is read and the transfer ended
  ;; with a response, every time after; the outcome's condition raised
  ;; once it ended with a failure, every time after. A raise from a read
  ;; loses the bytes earlier reads gave inside one get-bytevector-n, -n! or
  ;; -all, never inside get-bytevector-some, -some! or get-u8. The port
  ;; belongs to the thread that made it: a read from another that reaches
  ;; read!, and a close from another, raise &curl-wrong-thread, and a close
  ;; that raises leaves it open; but bytes Chez's port already buffered,
  ;; which a read takes without calling read!, it serves to any thread, and
  ;; a get-bytevector-n, -n! or -all from another thread that takes them,
  ;; then reaches read! and raises, loses them (slice 1's second review). Its
  ;; close cancels TOKEN, if it is not done. No collection, and no exit,
  ;; closes it. A second port of TOKEN, and a token whose request does not
  ;; stream its response, are assertion violations.
  (define (curl-token-body-port token)
    (let* ((who 'curl-token-body-port)
           (stream (token-stream who token))
           (owner (get-thread-id))
           (made (locked (curl-token-engine-lock token)
                   (lambda ()
                     (and (not (token-port token)) (begin (token-port-set! token #t) #t))))))
      (unless made
        (assertion-violation who "a token's port is made once" token))
      (let ((at-hand #f) (offset 0))
        (define (own)
          (let ((thread (get-thread-id)))
            (unless (eqv? thread owner)
              (raise (condition (make-curl-wrong-thread who owner thread)
                                (make-who-condition who)
                                (make-message-condition
                                 "a token's port is read and closed only on the thread that made it: a close from another races a read")
                                (make-irritants-condition (list token)))))))
        (define (read! bv start count)
          (own)
          (if (and at-hand (< offset (bytevector-length at-hand)))
              (let ((k (min count (- (bytevector-length at-hand) offset))))
                (bytevector-copy! at-hand offset bv start k)
                (set! offset (+ offset k))
                k)
              (let loop ((pause 50000))
                (let* ((seen (look token stream)) (node (cadr seen)) (piece (caddr seen)))
                  (cond
                    (piece
                     (let ((k (min count (bytevector-length piece))))
                       (bytevector-copy! piece 0 bv start k)
                       (remove-taken! token stream node piece)
                       (set! at-hand piece)
                       (set! offset k)
                       k))
                    ((car seen)
                     (let ((outcome (curl-token-outcome token)))
                       (if (curl-response? outcome) 0 (raise outcome))))
                    (else
                     (require-interrupts-on who)
                     (sleep (make-time 'time-duration pause 0))
                     (loop (min (* pause 2) 10000000))))))))
        (make-custom-binary-input-port "curl-token-body" read! #f #f
                                       (lambda () (own) (curl-token-cancel token))))))

  ;; curl-token-head : Token -> (U Head #f)
  ;; TOKEN's final head once the header callable has published it: #f
  ;; before, and for a transfer that ended with none. It never waits. A
  ;; token whose request does not stream its response is an assertion
  ;; violation.
  (define (curl-token-head token)
    (stream-head (token-stream 'curl-token-head token)))

  ;; curl-token-head-wait : Token Natural -> Boolean
  ;; Whether TOKEN's head has arrived, or TOKEN is done, within MS
  ;; milliseconds, waiting as await does; each read holds the engine's
  ;; mutex, then the stream's, the lock order (the M6 plan, section 3.4). A
  ;; token whose request does not stream its response is an assertion
  ;; violation.
  (define (curl-token-head-wait token ms)
    (let ((stream (token-stream 'curl-token-head-wait token))
          (deadline (deadline-after 'curl-token-head-wait ms)))
      (and (wait-until 'curl-token-head-wait (curl-token-engine-lock token)
                       (lambda () (or (eq? (token-state token) 'done) (stream-head stream)))
                       deadline)
           #t)))

  ;; curl-token-stream-stats : Token -> (Listof (Pairof Symbol Any))
  ;; stream-stats of TOKEN's stream: a private accessor.
  (define (curl-token-stream-stats token)
    (stream-stats (token-stream 'curl-token-stream-stats token)))

  ;; call-with-stream-held : Token (-> Any) -> Any
  ;; THUNK's answer, run holding TOKEN's stream's mutex, through locked, so
  ;; a take on another thread blocks inside its look's critical section: a
  ;; test seam, private, as call-with-engine-held is. THUNK must not touch
  ;; TOKEN's engine, whose mutex comes before the stream's.
  (define (call-with-stream-held token thunk)
    (locked (stream-lock (token-stream 'call-with-stream-held token)) thunk))

  ;; curl-token-plant! : Token (U #f 'spin 'gate) -> Void
  ;; A test seam, private: the plant TOKEN's next takes meet (remove-taken!):
  ;; spin, a loop after every removal; gate, one take held between its look
  ;; and its removal until curl-token-open-gate!; #f, none.
  (define (curl-token-plant! token plant)
    (token-stream 'curl-token-plant! token)
    (unless (memq plant '(#f spin gate))
      (assertion-violation 'curl-token-plant! "a plant is #f, spin or gate" plant))
    (locked (curl-token-engine-lock token)
      (lambda () (token-plant-set! token (if (eq? plant 'gate) (vector 'armed) plant)))))

  ;; curl-token-gate : Token -> (U #f 'armed 'waiting 'open)
  ;; The gate's phase, #f with none: waiting once a take is held there.
  (define (curl-token-gate token)
    (token-stream 'curl-token-gate token)
    (locked (curl-token-engine-lock token)
      (lambda () (let ((plant (token-plant token))) (and (vector? plant) (vector-ref plant 0))))))

  ;; curl-token-open-gate! : Token -> Void
  ;; Lets the take held at the gate go on.
  (define (curl-token-open-gate! token)
    (token-stream 'curl-token-open-gate! token)
    (locked (curl-token-engine-lock token)
      (lambda () (let ((plant (token-plant token))) (when (vector? plant) (vector-set! plant 0 'open))))))

  ;; curl-token-plant-stall! : Token Positive-Integer -> Void
  ;; A test seam, private: the write callable's next call for TOKEN's
  ;; stream sleeps MS milliseconds first, holding nothing
  ;; (stream-plant-stall!). Armed while the transfer is paused, that call
  ;; is the replay inside the resume step's curl_easy_pause.
  (define (curl-token-plant-stall! token ms)
    (stream-plant-stall! (token-stream 'curl-token-plant-stall! token) ms))

  ;; curl-token-stall-state : Token -> (U #f 'armed 'stalling 'done)
  ;; The stall's phase: stalling while the callable sleeps.
  (define (curl-token-stall-state token)
    (stream-stall-state (token-stream 'curl-token-stall-state token)))

  ;; --- the request stream (ADR-0030; the M6 plan, sections 3.3 to 3.5) -------------------

  ;; token-upload : Symbol Any -> Upload
  ;; TOKEN's request stream; a token whose request does not stream its body
  ;; is an assertion violation from WHO, as is what is no token.
  (define (token-upload who token)
    (check-token who token)
    (or (plan-upload (curl-token-plan token))
        (assertion-violation who "the token's request does not stream its body: give it body stream"
                             token)))

  ;; token-done? : Engine Token -> Boolean
  ;; Whether TOKEN is done, read in a hold of ENGINE's mutex.
  (define (token-done? engine token)
    (locked (curl-engine-lock engine) (lambda () (eq? (token-state token) 'done))))

  ;; queue-resume! : Engine Token -> Void
  ;; The queueing hold: a resume for TOKEN, while it is live and its engine
  ;; runs, with the wakeup, in one hold of ENGINE's mutex. Its callers make
  ;; it inside the critical section of the stream hold that decided it, one
  ;; hold after the other, never nested (the M6 plan, section 3.4).
  (define (queue-resume! engine token)
    (locked (curl-engine-lock engine)
      (lambda ()
        (when (and (eq? (token-state token) 'live) (eq? (engine-state engine) 'running))
          (curl-engine-queue-set! engine (cons (cons 'resume token) (curl-engine-queue engine)))
          (curl-multi-wakeup (engine-multi engine))))))

  ;; curl-token-room-wait : Token Natural -> (U #t #f 'done)
  ;; #t once libcurl has asked for TOKEN's body and the request's buffer
  ;; has room; done once TOKEN is done, read first; #f once MS milliseconds
  ;; pass (the M6 plan, section 3.1). It waits as await does, polling, and
  ;; refuses to wait inside a critical section; each read holds the
  ;; engine's mutex, then the stream's, the lock order. A token whose
  ;; request does not stream its body is an assertion violation.
  (define (curl-token-room-wait token ms)
    (let* ((who 'curl-token-room-wait)
           (up (token-upload who token))
           (deadline (deadline-after who ms)))
      (wait-until who (curl-token-engine-lock token)
                  (lambda ()
                    (cond ((eq? (token-state token) 'done) 'done)
                          ((upload-room? up) #t)
                          (else #f)))
                  deadline)))

  ;; curl-token-put-piece! : Token Bytevector [Natural] -> (U #t #f 'done)
  ;; PIECE, a bytevector of a byte or more, copied first, so the caller
  ;; keeps it, then put into TOKEN's request buffer, waiting while that
  ;; holds upload-buffer-limit bytes or more, at most MS milliseconds when
  ;; given: #t once taken; #f once MS pass; done once TOKEN is done, the
  ;; piece not taken (the M6 plan, sections 3.1 and 3.3). Each try is one
  ;; critical section of up to three holds, one after another: the
  ;; engine's, whether TOKEN is done; the stream's, which commits the piece
  ;; with its resume decision, so a handler that escapes as the section
  ;; ends leaves it committed, and curl-token-body-count counts it (section
  ;; 3.5); and the engine's again, to queue the resume. A piece that would
  ;; take the body past its body-length raises &curl-request-error,
  ;; body-length-mismatch, naming body-length and the length, the piece
  ;; not taken, once the refusal is set and a resume queued, so the read
  ;; callable fails the transfer with that reason, or, once libcurl reads
  ;; no more, the transfer's outcome does (reason-of), unless another reason
  ;; came first; it is checked before the room. Once the engine's thread
  ;; has read the outcome, or freed the transfer, a put takes nothing: it
  ;; waits, as for room, until TOKEN is done, and answers done, or #f once
  ;; MS pass, so a done always finds TOKEN's outcome there. A put after
  ;; curl-token-end-body! on a live token is an assertion violation; on a
  ;; token done it answers done, and on a closed request stream it waits,
  ;; then answers done.
  ;; A wait sleeps between tries, refused inside a critical section, as
  ;; every wait. A token whose request does not stream its body, and what
  ;; is no piece, are assertion violations, before anything.
  (define curl-token-put-piece!
    (case-lambda
      ((token piece) (put-piece token piece #f))
      ((token piece ms) (put-piece token piece ms))))

  ;; put-piece : Token Any (U Natural #f) -> (U #t #f 'done)
  (define (put-piece token piece ms)
    (let* ((who 'curl-token-put-piece!)
           (up (token-upload who token))
           (deadline (and ms (deadline-after who ms))))
      (unless (and (bytevector? piece) (> (bytevector-length piece) 0))
        (assertion-violation who "a piece is a bytevector of a byte or more" (shown-value piece)))
      (let ((copy (bytevector-copy piece)) (engine (curl-token-engine token)))
        (let loop ((pause 50000))
          (let* ((answer (critical-section
                          (if (token-done? engine token)
                              '(done #f)
                              (let ((answer (upload-put! up copy (monotonic-ns))))
                                (when (cadr answer) (queue-resume! engine token))
                                answer))))
                 (seen (car answer)))
            ;; The split plant's commit, a test seam's, after the section.
            (when (pair? (cddr answer)) (upload-split-commit! up (caddr answer) copy))
            (case seen
              ((taken) #t)
              ((done) 'done)
              ((refused)
               (let ((length (plan-body-length (curl-token-plan token))))
                 (raise (condition (make-curl-request-error 'body-length length 'body-length-mismatch)
                                   (make-who-condition who)
                                   (make-message-condition
                                    "a piece past the streamed body's body-length, not taken: the transfer fails, with body-length-mismatch unless another reason came first")
                                   (make-irritants-condition (list length (bytevector-length copy)))))))
              ((ended)
               (assertion-violation who "the token's body has ended: curl-token-end-body! was called" token))
              (else
               ;; full, or closed: the request stream closed as the engine's
               ;; thread read the outcome, the token not yet done; either
               ;; waits, and the next try that finds TOKEN done answers done.
               (let ((left (and deadline (- deadline (monotonic-ns)))))
                 (if (and left (<= left 0))
                     #f
                     (begin
                       (require-interrupts-on who)
                       (sleep (make-time 'time-duration (if left (min pause left) pause) 0))
                       (loop (min (* pause 2) 10000000))))))))))))

  ;; curl-token-end-body! : Token -> Void
  ;; TOKEN's body's end, in one critical section: nothing on a token done,
  ;; or a second time; else the end set, and a resume queued when the
  ;; transfer is paused for sending and none is (the M6 plan, section 3.3).
  ;; The read callable then answers the end, or, short of the body-length,
  ;; fails the transfer with body-length-mismatch. A token whose request
  ;; does not stream its body is an assertion violation.
  (define (curl-token-end-body! token)
    (let* ((up (token-upload 'curl-token-end-body! token)) (engine (curl-token-engine token)))
      (critical-section
       (unless (token-done? engine token)
         (when (upload-end! up (monotonic-ns)) (queue-resume! engine token))))
      (if #f #f)))

  ;; curl-token-body-count : Token -> Natural
  ;; The bytes TOKEN's puts have committed (the M6 plan, section 3.5): a
  ;; caller that caught an escape from a put reads here whether it was
  ;; taken. A token whose request does not stream its body is an
  ;; assertion violation.
  (define (curl-token-body-count token)
    (upload-count (token-upload 'curl-token-body-count token)))

  ;; curl-token-upload-stats : Token -> (Listof (Pairof Symbol Any))
  ;; upload-stats of TOKEN's request stream: a private accessor.
  (define (curl-token-upload-stats token)
    (upload-stats (token-upload 'curl-token-upload-stats token)))

  ;; curl-token-plant-put! : Token (U #f 'split) -> Void
  ;; A test seam, private: the plant TOKEN's next puts meet: split, a put
  ;; that commits its piece after its section, in two plain writes with a
  ;; loop between, the timer sweep's planted control (the M6 plan, section
  ;; 3.5); #f, none, the put's own path.
  (define (curl-token-plant-put! token plant)
    (let ((up (token-upload 'curl-token-plant-put! token)))
      (unless (memq plant '(#f split))
        (assertion-violation 'curl-token-plant-put! "a put's plant is #f or split" plant))
      (upload-plant-split! up (eq? plant 'split))))

  ;; call-with-upload-held : Token (-> Any) -> Any
  ;; THUNK's answer, run holding TOKEN's request stream's mutex, through
  ;; locked, so a put on another thread blocks inside its critical
  ;; section: a test seam, private, as call-with-stream-held is the take's.
  ;; THUNK must not touch TOKEN's engine, whose mutex comes first.
  (define (call-with-upload-held token thunk)
    (locked (upload-lock (token-upload 'call-with-upload-held token)) thunk))

  ;; --- the mailbox (ADR-0021) ------------------------------------------------------------

  ;; make-curl-mailbox : -> Mailbox
  ;; An empty mailbox, which collects the tokens submitted to it, from any
  ;; number of engines, as each is done.
  (define (make-curl-mailbox) (make-mailbox-record (make-mutex) '() '()))

  (define (check-mailbox who x)
    (unless (curl-mailbox? x) (assertion-violation who "not a mailbox" (shown-value x))))

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

  ;; --- the cookie jar (ADR-0035, amended twice; the M7 plan, section 3.5) ---------------
  ;; A jar's message is (jar KIND JAR REPLY ARG), KIND make, read, load or
  ;; close, ARG a load's lines, as bytes, checked, or #f. REPLY is a vector,
  ;; #(STATE ANSWER), STATE pending until the engine's thread answers it,
  ;; then done, both written under the engine's mutex; ANSWER is (ok VALUE)
  ;; or (raise CONDITION), CONDITION raised on the waiting caller's thread.

  ;; jar-refusal : Symbol Symbol -> Condition
  ;; WHO's refusal of a request's cookie-jar for REASON, cookie-jar-engine
  ;; or cookie-jar-closed: &curl-request-error, field cookie-jar, value the
  ;; symbol cookie-jar; and a read-out's or a load's of a jar not live.
  (define (jar-refusal who reason)
    (condition (make-curl-request-error 'cookie-jar 'cookie-jar reason)
               (make-who-condition who)
               (make-message-condition
                (if (eq? reason 'cookie-jar-engine)
                    "a cookie jar is its engine's alone, and this one is another engine's"
                    "the cookie jar is closed, or closing: it takes no transfer, read-out or load more"))
               (make-irritants-condition (list 'cookie-jar))))

  (define (check-jar who x)
    (unless (curl-cookie-jar? x) (assertion-violation who "not a cookie jar" (shown-value x))))

  ;; post-jar! : Engine Symbol Jar Any -> Reply
  ;; KIND's message for JAR, with ARG, queued with its wakeup in one hold of
  ;; ENGINE's mutex, and its reply; an engine not running refuses it, as a
  ;; submit is refused: &curl-engine-error, stopped, or what it failed with.
  (define (post-jar! engine kind jar arg)
    (let* ((reply (vector 'pending #f))
           (refusal
            (locked (curl-engine-lock engine)
              (lambda ()
                (case (engine-state engine)
                  ((running)
                   (curl-engine-queue-set! engine
                                           (cons (list 'jar kind jar reply arg) (curl-engine-queue engine)))
                   (curl-multi-wakeup (engine-multi engine))
                   #f)
                  ((failing failed) (engine-failure engine))
                  (else (engine-error 'stopped #f)))))))
      (when refusal (raise refusal))
      reply))

  ;; reply-of : Symbol Engine Reply -> Any
  ;; REPLY's answer, once ENGINE's thread has written it, waiting as
  ;; curl-engine-stop waits, by wait-until, polling, with no bound: the
  ;; engine answers every jar message, at its turn, at its stop or at its
  ;; failure, and a fixed bound would fail a load slow by libcurl's own
  ;; cost (ADR-0035, decision 9). (ok VALUE) answers VALUE; (raise
  ;; CONDITION) raises CONDITION here. An escape from the wait leaves the
  ;; message to be carried out: the engine answers it all the same.
  (define (reply-of who engine reply)
    (let ((answer (wait-until who (curl-engine-lock engine)
                              (lambda () (and (eq? (vector-ref reply 0) 'done) (vector-ref reply 1)))
                              #f)))
      (if (eq? (car answer) 'ok) (cadr answer) (raise (cadr answer)))))

  ;; make-curl-cookie-jar : Engine -> Jar
  ;; A fresh, empty jar of ENGINE's, made on its thread, as its make
  ;; message is carried out: a curl_share of cookies alone, share-settings'
  ;; (ADR-0035, decision 1), and the easy handle the engine keeps for the
  ;; jar's read-outs and loads, attached to it. What is no engine is an
  ;; assertion violation; inside a critical section, where it could not
  ;; wait, one too, before anything; an engine stopping, stopped or failed
  ;; refuses it as a submit is refused; a make libcurl refuses, curl_share_init or
  ;; curl_easy_init answering NULL, or a curl_share_setopt answering but
  ;; CURLSHE_OK, raises, what it made freed.
  (define (make-curl-cookie-jar engine)
    (define who 'make-curl-cookie-jar)
    (check-engine who engine)
    (require-interrupts-on who)
    (reply-of who engine (post-jar! engine 'make (new-cookie-jar engine) #f)))

  ;; curl-cookie-jar-cookies : Jar -> (Listof String)
  ;; JAR's cookies, read out on its engine's thread through
  ;; CURLINFO_COOKIELIST, as Netscape lines, each a Latin-1 string, each byte
  ;; one char (ADR-0035, decision 8): DOMAIN TAILMATCH PATH SECURE EXPIRY
  ;; NAME VALUE, tab-separated, #HttpOnly_ before an HttpOnly cookie's
  ;; domain, in libcurl's order, which moves with its hash table. libcurl's
  ;; lines as they are: by version, some are lines a load refuses (the M7
  ;; plan, section 3.7). Refused as make-curl-cookie-jar refuses, and a jar
  ;; not live as cookie-jar-closed.
  (define (curl-cookie-jar-cookies jar)
    (define who 'curl-cookie-jar-cookies)
    (check-jar who jar)
    (require-interrupts-on who)
    (let ((engine (cookie-jar-engine jar)))
      (map bytes->latin-1 (reply-of who engine (post-jar! engine 'read jar #f)))))

  ;; curl-cookie-jar-load! : Jar (Listof String) -> Void
  ;; LINES loaded into JAR, in order, on its engine's thread, each through
  ;; CURLOPT_COOKIELIST, once every line is checked on this thread, on a
  ;; copy of the list and of each string, by cookie-line-bytes: a line not
  ;; in the form a read-out writes is refused as cookie-line, naming its
  ;; index, never its text, and nothing is loaded (ADR-0035, decision 7).
  ;; Every answer of libcurl's is read: one but 0 fails the load there,
  ;; naming the line's index and the code, the lines before it loaded. A
  ;; load costs about n^2 on the engine's thread, whose other transfers wait
  ;; meanwhile: 10,000 lines 0.24 to 0.50 s, 50,000 up to 27 s (decision
  ;; 9). Refused as curl-cookie-jar-cookies refuses.
  (define (curl-cookie-jar-load! jar lines)
    (define who 'curl-cookie-jar-load!)
    (check-jar who jar)
    (require-interrupts-on who)
    (let ((bytes (cookie-line-bytes who lines))
          (engine (cookie-jar-engine jar)))
      (reply-of who engine (post-jar! engine 'load jar bytes))
      (if #f #f)))

  ;; curl-cookie-jar-close! : Jar -> Void
  ;; JAR closed, on its engine's thread: a live jar is set closing, and its
  ;; share freed at once when no transfer holds it, or else as the last
  ;; that holds it is taken out; one closing or closed is left as it is. It
  ;; returns once the engine has carried the close out, never waiting for a
  ;; transfer. A transfer submitted after it is refused, cookie-jar-closed.
  ;; Refused as make-curl-cookie-jar refuses.
  (define (curl-cookie-jar-close! jar)
    (define who 'curl-cookie-jar-close!)
    (check-jar who jar)
    (require-interrupts-on who)
    (reply-of who (cookie-jar-engine jar) (post-jar! (cookie-jar-engine jar) 'close jar #f))
    (if #f #f))

  ;; make-curl-cookie-jar-sharing : Engine (Listof (Pairof Integer Integer)) -> (Values Jar (Listof Integer))
  ;; make-curl-cookie-jar's, but its share is made by OPS' curl_share_setopt
  ;; calls, in order, each (OPTION . VALUE), in place of share-settings',
  ;; and every answer taken, none refusing it: the jar, live, and each
  ;; call's CURLSHcode, in order. A test seam, private, so
  ;; tests/test-variadic.sps can watch curl_share_setopt's int arrive by
  ;; behaviour, no answer alone telling 2 from 3 (the slice's measurement).
  (define (make-curl-cookie-jar-sharing engine ops)
    (define who 'make-curl-cookie-jar-sharing)
    (check-engine who engine)
    (unless (and (list? ops)
                 (for-all (lambda (op) (and (pair? op) (integer? (car op)) (exact? (car op))
                                            (integer? (cdr op)) (exact? (cdr op))))
                          ops))
      (assertion-violation who "the calls are a list of (OPTION . VALUE), exact integers" ops))
    (require-interrupts-on who)
    (let ((made (reply-of who engine (post-jar! engine 'make (new-cookie-jar engine)
                                                (map (lambda (op) (cons (car op) (cdr op))) ops)))))
      (values (car made) (cdr made))))

  ;; curl-cookie-jar-post! : Jar (U 'read 'load 'close) (Listof String) -> Reply
  ;; JAR's KIND message, queued with its wakeup, and not waited for: a load
  ;; of LINES, checked first as curl-cookie-jar-load! checks them, a
  ;; read-out or a close, LINES () for those. A test seam, private, which
  ;; may run inside call-with-engine-held, so jar messages and submits can
  ;; be queued in the order a test chooses; curl-cookie-jar-await answers
  ;; the reply.
  (define (curl-cookie-jar-post! jar kind lines)
    (define who 'curl-cookie-jar-post!)
    (check-jar who jar)
    (unless (memq kind '(read load close))
      (assertion-violation who "a jar's message is read, load or close" kind))
    (post-jar! (cookie-jar-engine jar) kind jar
               (and (eq? kind 'load) (cookie-line-bytes who lines))))

  ;; curl-cookie-jar-await : Jar Reply -> Any
  ;; REPLY's answer, as the public procedures answer: a read-out's lines,
  ;; Latin-1 strings, as data, never raised; a load's and a close's #t; or
  ;; (raised CONDITION), what the message raised.
  (define (curl-cookie-jar-await jar reply)
    (check-jar 'curl-cookie-jar-await jar)
    (guard (e (#t (list 'raised e)))
      (let ((answer (reply-of 'curl-cookie-jar-await (cookie-jar-engine jar) reply)))
        (if (list? answer) (map bytes->latin-1 answer) #t))))

  ;; curl-cookie-jar-state : Jar -> (U 'pending 'live 'closing 'closed)
  ;; curl-cookie-jar-holders : Jar -> Natural
  ;; curl-engine-jar-count : Engine -> Natural
  ;; A jar's state, how many transfers hold it, and an engine's jars made
  ;; and not yet freed, each read in a hold of the engine's mutex: private
  ;; accessors.
  (define (curl-cookie-jar-state jar)
    (check-jar 'curl-cookie-jar-state jar)
    (locked (curl-engine-lock (cookie-jar-engine jar)) (lambda () (cookie-jar-state jar))))
  (define (curl-cookie-jar-holders jar)
    (check-jar 'curl-cookie-jar-holders jar)
    (locked (curl-engine-lock (cookie-jar-engine jar)) (lambda () (cookie-jar-holders jar))))
  (define (curl-engine-jar-count engine)
    (check-engine 'curl-engine-jar-count engine)
    (locked (curl-engine-lock engine) (lambda () (length (engine-jars engine)))))

  ;; answer! : Engine Reply Any -> Void
  ;; REPLY answered ANSWER, in one hold of ENGINE's mutex, unless it is
  ;; answered already: the first answer stands.
  (define (answer! engine reply answer)
    (locked (curl-engine-lock engine)
      (lambda ()
        (when (eq? (vector-ref reply 0) 'pending)
          (vector-set! reply 1 answer)
          (vector-set! reply 0 'done)))))

  ;; answer-jar-messages! : Engine (Listof Message) Condition -> Void
  ;; Every jar message of MESSAGES answered with a raise of CONDITION: a
  ;; stop's or a failure's, for the messages it never carried out.
  (define (answer-jar-messages! engine messages condition)
    (for-each (lambda (message)
                (when (eq? (car message) 'jar)
                  (answer! engine (list-ref message 3) (list 'raise condition))))
              messages))

  ;; jar-answer-seam : Engine Symbol -> (U Integer #f)
  ;; The answer ENGINE's (jar-answer WHICH . CODE) seam takes in place of
  ;; libcurl's at WHICH's calls, or #f.
  (define (jar-answer-seam engine which)
    (let ((seam (find (lambda (seam) (and (pair? seam) (eq? (car seam) 'jar-answer)
                                           (eq? (cadr seam) which)))
                      (engine-seams engine))))
      (and seam (cddr seam))))

  ;; jar-message! : Engine (List 'jar Symbol Jar Reply Any) -> Void
  ;; One jar message, carried out on this thread, and answered: a raise
  ;; there is its answer, never the engine's failure. A read-out and a load
  ;; of a jar not live are refused, cookie-jar-closed; each runs through the
  ;; jar's own handle.
  (define (jar-message! engine message)
    (let ((kind (list-ref message 1)) (jar (list-ref message 2)) (reply (list-ref message 3))
          (arg (list-ref message 4)))
      (answer! engine reply
               (guard (e (#t (list 'raise e)))
                 (list 'ok
                       (case kind
                         ((make) (make-jar! engine jar arg))
                         ((read)
                          (live-jar! engine jar 'curl-cookie-jar-cookies)
                          (jar-read-lines 'curl-cookie-jar-cookies (cookie-jar-handle jar)
                                          (jar-answer-seam engine 'read)))
                         ((load)
                          (live-jar! engine jar 'curl-cookie-jar-load!)
                          (jar-load-lines! 'curl-cookie-jar-load! (cookie-jar-handle jar) arg
                                           (jar-answer-seam engine 'load)))
                         (else (close-jar! engine jar))))))))

  ;; live-jar! : Engine Jar Symbol -> Void
  ;; Returns when JAR is live, read in a hold; else raises WHO's
  ;; cookie-jar-closed.
  (define (live-jar! engine jar who)
    (unless (locked (curl-engine-lock engine) (lambda () (eq? (cookie-jar-state jar) 'live)))
      (raise (jar-refusal who 'cookie-jar-closed))))

  ;; make-jar! : Engine Jar (U (Listof (Pairof Integer Integer)) #f) -> (U Jar (Pairof Jar (Listof Integer)))
  ;; JAR made on this thread: its share, made and recorded in one critical
  ;; section with its count, then share-settings' calls, an answer but
  ;; CURLSHE_OK, or the seam's, refusing it; or with OPS, a test seam's,
  ;; OPS' calls in their place, every answer kept and none refusing it;
  ;; then its handle, made and recorded likewise, and attached to the share,
  ;; jar-attach!'s; then, in one hold, live, and among ENGINE's jars. A
  ;; refusal frees what was made, by free-jar!, then raises again. Answers
  ;; JAR, or with OPS JAR and the answers.
  (define (make-jar! engine jar ops)
    (let ((lock (curl-engine-lock engine)))
      (guard (e (#t (free-jar! engine jar) (raise e)))
        (critical-section
         (let ((share (curl-share-init)))
           (when (eqv? share 0)
             (error 'make-curl-cookie-jar "curl_share_init returned NULL: no memory for a share"))
           (locked lock (lambda () (cookie-jar-share-set! jar share)))))
        ;; In order, a loop: map's order is no order (traps.md).
        (let ((codes
               (let loop ((rest (or ops share-settings)) (found '()))
                 (if (null? rest)
                     (reverse found)
                     (let* ((setting (car rest))
                            (given (curl-share-setopt-int (cookie-jar-share jar) (car setting) (cdr setting)))
                            (code (or (jar-answer-seam engine 'make) given)))
                       (unless (or ops (eqv? code curlshe-ok))
                         (error 'make-curl-cookie-jar "curl_share_setopt answered a CURLSHcode"
                                (car setting) (cdr setting) code))
                       (loop (cdr rest) (cons code found)))))))
        (critical-section
         (let ((easy (curl-easy-init)))
           (when (eqv? easy 0)
             (error 'make-curl-cookie-jar "curl_easy_init returned NULL: no memory for the jar's handle"))
           (locked lock (lambda () (cookie-jar-handle-set! jar easy)))))
        (jar-attach! (cookie-jar-handle jar) (cookie-jar-share jar))
        (locked lock
          (lambda ()
            (cookie-jar-state-set! jar 'live)
            (engine-jars-set! engine (cons jar (engine-jars engine)))))
        (if ops (cons jar codes) jar)))))

  ;; free-jar! : Engine Jar -> Integer
  ;; JAR's handle freed, then its share, each in one critical section with
  ;; its record: the handle first, since curl_share_cleanup answers
  ;; CURLSHE_IN_USE while any handle holds the share, the jar's own among
  ;; them; then the share, and on CURLSHE_OK the jar marked closed and let
  ;; go of ENGINE's jars, in the same section. Answers the cleanup's
  ;; CURLSHcode, CURLSHE_OK for a jar with no share; any other leaves the
  ;; share counted, and the jar's record of it.
  (define (free-jar! engine jar)
    (let ((lock (curl-engine-lock engine)))
      (critical-section
       (let ((easy (cookie-jar-handle jar)))
         (when easy
           (curl-easy-cleanup easy)
           (locked lock (lambda () (cookie-jar-handle-set! jar #f))))))
      (critical-section
       (let* ((share (cookie-jar-share jar))
              (code (if share (curl-share-cleanup share) curlshe-ok)))
         (when (eqv? code curlshe-ok)
           (locked lock
             (lambda ()
               (cookie-jar-share-set! jar #f)
               (cookie-jar-state-set! jar 'closed)
               (engine-jars-set! engine (remq jar (engine-jars engine))))))
         code))))

  ;; close-jar! : Engine Jar -> Void
  ;; A live JAR set closing, in one hold, and freed at once when no
  ;; transfer holds it; one closing or closed left as it is.
  (define (close-jar! engine jar)
    (when (locked (curl-engine-lock engine)
            (lambda ()
              (and (eq? (cookie-jar-state jar) 'live)
                   (begin (cookie-jar-state-set! jar 'closing)
                          (= (cookie-jar-holders jar) 0)))))
      (free-jar! engine jar))
    (if #f #f))

  ;; release! : Engine Token -> Void
  ;; TOKEN's hold on its jar let go, once, in one hold: its entry in the
  ;; table of holds removed, and the jar's count lowered; then a closing
  ;; jar the count leaves at zero freed, by free-jar!, marked closed in its
  ;; share's section. A token that holds none, never set up with a jar or
  ;; let go already, changes nothing.
  (define (release! engine token)
    (let ((jar (locked (curl-engine-lock engine)
                 (lambda ()
                   (let ((jar (hashtable-ref (engine-holds engine) token #f)))
                     (and jar
                          (begin
                            (hashtable-delete! (engine-holds engine) token)
                            (cookie-jar-holders-set! jar (- (cookie-jar-holders jar) 1))
                            (and (eq? (cookie-jar-state jar) 'closing) (= (cookie-jar-holders jar) 0)
                                 jar))))))))
      (when jar (free-jar! engine jar))))

  ;; jar-usable? : Engine Jar -> Boolean
  ;; Whether JAR is ENGINE's and live, its state read in a hold.
  (define (jar-usable? engine jar)
    (and (eq? (cookie-jar-engine jar) engine)
         (locked (curl-engine-lock engine) (lambda () (eq? (cookie-jar-state jar) 'live)))))

  ;; free-jars! : Engine -> (Listof Jar)
  ;; Each of ENGINE's jars freed, by free-jar!: those whose share stays in
  ;; use, held by a handle a failure abandoned.
  (define (free-jars! engine)
    (filter (lambda (jar) (not (eqv? (free-jar! engine jar) curlshe-ok)))
            (locked (curl-engine-lock engine) (lambda () (engine-jars engine)))))

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
  ;; out, its CURLMOPT_PIPELINING set to 0 where multiplexing-off? says so
  ;; for the loaded libcurl, or the test seam forces it, any answer but
  ;; CURLM_OK failing the engine, then its slot, made and recorded in one
  ;; critical section, then the loop, under a guard whose handler fails the
  ;; engine.
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
      (let ((off (or (and (memq 'unmultiplexed (engine-seams engine)) #t)
                     (multiplexing-off? (libcurl-info-version (loaded-libcurl))))))
        (when off
          (let ((code (curl-multi-setopt-long (engine-multi engine) curlmopt-pipelining curlpipe-nothing)))
            (unless (eqv? code curlm-ok) (multi-failed 'curl_multi_setopt code))))
        (locked (curl-engine-lock engine)
          (lambda () (engine-multiplexing-set! engine (if off 'off 'default)))))
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
  ;; The loop, until a stop: take, set up, cancel, resume, perform, read,
  ;; look, poll (the M6 plan, section 3.4), a cookie jar's messages carried
  ;; out with the set-ups, in the order queued (the M7 plan, section 3.5). The look reads the queue under
  ;; the mutex, and a message queued skips the poll: Guix's 8.20.0 reads
  ;; back, inside the perform, a wakeup made before it, and the poll would
  ;; then wait for libcurl alone (ADR-0012, amended 2026-10-30). The paced
  ;; poll: a poll that returned in under 1 ms, in a turn that took no
  ;; message, while a transfer is paused and no callable took a byte since
  ;; the turn began, is followed by a sleep of 1 ms, unless the test seam
  ;; turned it off. Ubuntu's 8.5.0 spins otherwise (ADR-0012, amended
  ;; 2026-10-29). While the probe, a test seam, has turns left as a turn
  ;; begins, that turn wakes its poll first, if it reaches it, and records
  ;; what it decided.
  (define (turns engine multi)
    (let turn ()
      (take-delay! engine)
      (let* ((moved (vector-ref (engine-moves engine) 0))
             ;; Read before the take: a probe armed after it would count
             ;; a turn whose batch took no mark of the seam's.
             (probed (probing? engine))
             (messages (take-queue! engine)))
        (if (assq 'stop messages)
            (shut-down! engine multi messages)
            (begin
              (for-each (lambda (message)
                          (case (car message)
                            ((submit) (set-up! engine multi (cdr message)))
                            ((jar) (jar-message! engine message))
                            (else #f)))
                        messages)
              (for-each (lambda (message)
                          (when (eq? (car message) 'cancel) (cancel! engine multi (cdr message))))
                        messages)
              (let resumes ((rest messages) (resumed #f))
                (cond ((pair? rest)
                       (resumes (cdr rest)
                                (or (and (eq? (car (car rest)) 'resume)
                                         (resume! engine multi (cdr (car rest))))
                                    resumed)))
                      (resumed (queue-late! engine))))
              (engine-batch-set! engine '())
              (unless (live-empty? engine) (fault-at! engine 'perform))
              (let-values (((code running) (curl-multi-perform multi (engine-slot engine))))
                (unless (eqv? code curlm-ok) (multi-failed 'curl_multi_perform code)))
              (read-finished! engine multi)
              (unless (locked (curl-engine-lock engine) (lambda () (pair? (curl-engine-queue engine))))
                (unless (live-empty? engine) (fault-at! engine 'poll))
                (let* ((woken (and probed (begin (curl-multi-wakeup multi) #t)))
                       (before (monotonic-ns))
                       (code (curl-multi-poll multi 1000))
                       (after (monotonic-ns))
                       (fast (< (- after before) 1000000))
                       (still (= moved (vector-ref (engine-moves engine) 0)))
                       (pace (and fast
                                  (null? messages)
                                  still
                                  (not (memq 'unpaced (engine-seams engine)))
                                  (any-paused? engine))))
                  (unless (eqv? code curlm-ok) (multi-failed 'curl_multi_poll code))
                  (when probed (probe-turn! engine fast (not still) pace))
                  (when pace
                    (locked (curl-engine-lock engine)
                      (lambda () (engine-paced-set! engine (+ (engine-paced engine) 1))))
                    (sleep (make-time 'time-duration 1000000 0)))))
              (turn))))))

  ;; take-delay! : Engine -> Void
  ;; The take's test seam: with ENGINE's (take-delay . MS), its thread
  ;; sleeps MS milliseconds, holding nothing, before a turn takes its
  ;; queue. Without it, nothing.
  (define (take-delay! engine)
    (let ((seam (find (lambda (seam) (and (pair? seam) (eq? (car seam) 'take-delay)))
                      (engine-seams engine))))
      (when seam
        (let ((ms (cdr seam)))
          (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000)))))))

  ;; any-paused? : Engine -> Boolean
  ;; Whether a live transfer of ENGINE's is paused, for receiving or for
  ;; sending: each transfer's bits read in a hold of its own, after the
  ;; table's (the M6 plan, section 3.4).
  (define (any-paused? engine)
    (exists (lambda (keyed) (live-transfer-paused? (cddr keyed)))
            (live-entries engine)))

  ;; resume! : Engine Positive-Integer Token -> Boolean
  ;; The resume step for TOKEN, while it is live (the M6 plan, section
  ;; 3.4; ADR-0012, amended 2026-10-29): in one hold of its streams' one
  ;; mutex, both bits, the receive bit and the send bit, and the resume's
  ;; flag cleared; then, holding no mutex
  ;; and outside any critical section, curl_easy_pause with CURLPAUSE_CONT,
  ;; inside which the callables take what libcurl held, and pause again,
  ;; setting the bit, for what they cannot take; the read callable runs at
  ;; the next perform, never inside the call (the M6 plan, section 2.2). An answer but 0, or the
  ;; test seam's in its place, fails the transfer by resume-failure, a
  ;; reason a callable recorded winning over pause-failed, and takes it out.
  ;; #t once carried out. A token taken out since its resume was queued,
  ;; its easy handle freed in the turn it ended, is passed over, counted,
  ;; #f.
  (define (resume! engine multi token)
    (let* ((live (token-live token))
           (easy (and live (live-transfer-easy live))))
      (if (not (and easy (or (live-transfer-stream live) (live-transfer-upload live))))
          (begin
            (locked (curl-engine-lock engine)
              (lambda () (engine-passed-set! engine (+ (engine-passed engine) 1))))
            #f)
          (begin
            (fault-at! engine 'resume)
            (let* ((queued (clear-pauses! live))
                   (called (monotonic-ns))
                   (answer (curl-easy-pause easy curlpause-cont))
                   (seam (pause-answer-seam engine))
                   (code (if seam (cdr seam) answer)))
              (resumed! live queued called)
              (unless (eqv? code curle-ok)
                (let* ((outcome (guard (e (#t e)) (resume-failure live code)))
                       (chunks (take-out! engine multi token)))
                  (complete! engine token outcome chunks)))
              #t)))))

  ;; completion-stall! : Engine -> Void
  ;; The completion's test seam: with ENGINE's (completion-stall . MS), its
  ;; thread sleeps MS milliseconds between reading a finished transfer's
  ;; outcome and completing its token, holding nothing, so a test can catch
  ;; a token whose outcome is read, its request stream closed, and not yet
  ;; done. Without it, nothing.
  (define (completion-stall! engine)
    (let ((seam (find (lambda (seam) (and (pair? seam) (eq? (car seam) 'completion-stall)))
                      (engine-seams engine))))
      (when seam
        (let ((ms (cdr seam)))
          (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000)))))))

  ;; pause-answer-seam : Engine -> (U (Pairof 'pause-answer Integer) #f)
  ;; ENGINE's (pause-answer . CODE) seam, or #f. Its seams hold symbols
  ;; and pairs alike, unpaced and unmultiplexed beside it, so each is
  ;; looked at as what it is: assq raised "improperly formed alist" on a
  ;; bare symbol, and those engines failed at their first resume (M6 slice
  ;; 2's measurement).
  (define (pause-answer-seam engine)
    (find (lambda (seam) (and (pair? seam) (eq? (car seam) 'pause-answer)))
          (engine-seams engine)))

  ;; queue-late! : Engine -> Void
  ;; The look's test seam: once armed, a mark queued from this thread, with
  ;; its wakeup, its time recorded, in one hold of the mutex.
  (define (queue-late! engine)
    (locked (curl-engine-lock engine)
      (lambda ()
        (when (eq? (engine-late engine) 'armed)
          (engine-late-set! engine (list 'queued (monotonic-ns)))
          (curl-engine-queue-set! engine (cons (list 'mark) (curl-engine-queue engine)))
          (curl-multi-wakeup (engine-multi engine))))))

  ;; multi-failed : Symbol Integer -> Nothing
  (define (multi-failed entry code)
    (error 'curl-engine (string-append (symbol->string entry) " answered a CURLMcode")
           code (curl-multi-strerror code)))

  ;; take-queue! : Engine -> (Listof Message)
  ;; Step 1: the queue, oldest first, emptied, each submitted token not done
  ;; yet marked live, and a mark, the look's test seam's, recorded as taken,
  ;; under the mutex. The batch is kept, on this thread,
  ;; until the turn has dealt with it. A fault planted at take raises in the
  ;; same hold, when the queue holds a message, before it is taken: so those
  ;; messages stay queued, for the failure to complete.
  (define (take-queue! engine)
    (let ((messages
           (locked (curl-engine-lock engine)
             (lambda ()
               (unless (null? (curl-engine-queue engine)) (fault-at! engine 'take))
               (let ((messages (let ((probe (engine-probe engine)))
                                 (if (and probe (> (vector-ref probe 0) 0) (vector-ref probe 1))
                                     (append (reverse (curl-engine-queue engine)) (list (list 'probe)))
                                     (reverse (curl-engine-queue engine))))))
                 (curl-engine-queue-set! engine '())
                 (for-each (lambda (message)
                             (when (and (eq? (car message) 'submit)
                                        (eq? (token-state (cdr message)) 'queued))
                               (token-state-set! (cdr message) 'live))
                             (when (eq? (car message) 'mark)
                               (let ((late (engine-late engine)))
                                 (when (and (pair? late) (eq? (car late) 'queued))
                                   (engine-late-set! engine (list 'taken (cadr late) (monotonic-ns)))))))
                           messages)
                 messages)))))
      (engine-batch-set! engine messages)
      messages))

  ;; live-empty? : Engine -> Boolean
  (define (live-empty? engine)
    (locked (curl-engine-lock engine) (lambda () (= (hashtable-size (engine-live engine)) 0))))

  ;; stop-multiplexing! : Engine Positive-Integer -> Void
  ;; MULTI's CURLMOPT_PIPELINING set to 0 on ENGINE's thread, for good, and
  ;; recorded as switched, where the engine multiplexes: a plan whose
  ;; stops-multiplexing? held, ADR-0037's decision 11. An engine already off
  ;; or switched is left. A libcurl answer but CURLM_OK fails the engine, as
  ;; the setting at its start does. The handles MULTI holds keep their
  ;; connections: libcurl reads the option as a later transfer looks for one.
  (define (stop-multiplexing! engine multi)
    (when (eq? (locked (curl-engine-lock engine) (lambda () (engine-multiplexing engine))) 'default)
      (let ((code (curl-multi-setopt-long multi curlmopt-pipelining curlpipe-nothing)))
        (unless (eqv? code curlm-ok) (multi-failed 'curl_multi_setopt code)))
      (locked (curl-engine-lock engine) (lambda () (engine-multiplexing-set! engine 'switched)))))

  ;; set-up! : Engine Positive-Integer Token -> Void
  ;; Step 2: TOKEN's transfer started, recorded in the table, and added to
  ;; MULTI; first, where its plan stops multiplexing, the engine's
  ;; multiplexing stopped, so it is the first transfer no other joins. A
  ;; token already done, cancelled while queued, is passed over. A raise
  ;; from start-transfer!, which has freed what it made, completes the
  ;; token with it: the transfer's own failure, not the engine's. A plan
  ;; with a cookie jar is checked first, on this thread: a jar another
  ;; engine's, or not live, a close having crossed the submit, completes the
  ;; token with cookie-jar-engine or cookie-jar-closed, and nothing is made;
  ;; a live one is held from the hold that records the transfer live, its
  ;; count raised and the hold kept in the table, so a start-transfer! that
  ;; raises holds nothing.
  (define (set-up! engine multi token)
    (unless (curl-token-done? token)
      (fault-at! engine 'setup)
      (let ((jar (plan-jar (curl-token-plan token))))
        (if (and jar (not (jar-usable? engine jar)))
            (complete! engine token
                       (jar-refusal 'curl-submit
                                    (if (eq? (cookie-jar-engine jar) engine) 'cookie-jar-closed 'cookie-jar-engine))
                       '())
            (begin
              (when (plan-unmultiplex (curl-token-plan token)) (stop-multiplexing! engine multi))
              (let ((live (guard (e (#t (complete! engine token e '()) #f))
                            (start-transfer! (curl-token-plan token)
                                             (not (memq 'transfer (engine-without engine)))
                                             (engine-moves engine)
                                             (engine-seams engine)))))
                (when live
                  (token-live-set! token live)
                  (locked (curl-engine-lock engine)
                    (lambda ()
                      (hashtable-set! (engine-live engine) (live-transfer-easy live) (cons token live))
                      (when jar
                        (hashtable-set! (engine-holds engine) token jar)
                        (cookie-jar-holders-set! jar (+ (cookie-jar-holders jar) 1)))))
                  (let ((code (curl-multi-add-handle multi (live-transfer-easy live))))
                    (unless (eqv? code curlm-ok) (multi-failed 'curl_multi_add_handle code))))))))))

  ;; take-out! : Engine Positive-Integer Token -> (Listof Any)
  ;; TOKEN's live transfer removed from MULTI, freed, its hold on a cookie
  ;; jar let go once its handle is, by release!, then taken out of the
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
      (release! engine token)
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
                       (_ (completion-stall! engine))
                       (chunks (take-out! engine multi token)))
                  (complete! engine token outcome chunks)))))
          (drain)))))

  ;; shut-down! : Engine Positive-Integer (Listof Message) -> Void
  ;; A stop: every token MESSAGES submitted completed as stopped, unset up;
  ;; every jar message they hold answered stopped; each cancel carried out;
  ;; every live transfer taken out and completed as stopped, each letting go
  ;; of its jar; the table checked empty; every jar, live or closing, freed,
  ;; and checked freed; the multi handle cleaned up; and the stop
  ;; signalled, the thread's last act.
  (define (shut-down! engine multi messages)
    (for-each (lambda (message)
                (when (eq? (car message) 'submit)
                  (complete! engine (cdr message) (transfer-ended 'stopped) '())))
              messages)
    (answer-jar-messages! engine messages (engine-error 'stopped #f))
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
    (unless (null? (free-jars! engine))
      (error 'curl-engine-stop "a cookie jar's share is still in use after a stop"))
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
  ;; live completes with &curl-engine-error, reason failed, carrying RAISED,
  ;; and every jar message queued or in the batch is answered with it;
  ;; every live transfer is taken out and freed, but an easy handle whose
  ;; removal failed, which stays counted, each freed one letting go of its
  ;; jar, and an abandoned one keeping its hold; then every jar is freed,
  ;; one whose share an abandoned handle holds kept, counted, as closing;
  ;; and the multi handle cleaned up, each as far as it goes, so a free that
  ;; fails leaves its count up; and last, the engine is marked failed.
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
      (answer-jar-messages! engine (append (engine-batch engine) queued) failure)
      (engine-batch-set! engine '())
      (for-each (lambda (keyed)
                  (let ((key (car keyed)) (token (cadr keyed)) (live (cddr keyed)))
                    (let* ((chunks (guard (e (#t '())) (live-transfer-chunks live)))
                           (easy (live-transfer-easy live))
                           (removed (and multi easy (not (memq 'abandoning (engine-seams engine)))
                                         (guard (e (#t #f))
                                           (eqv? (curl-multi-remove-handle multi easy) curlm-ok)))))
                      ;; A handle still in the multi handle is not freed:
                      ;; curl_easy_cleanup would remove it, which can
                      ;; block. It stays counted, so a suite sees it, and
                      ;; keeps its hold on a jar, whose share stays in use.
                      (unless removed (abandon-transfer-easy! live))
                      (guard (e (#t #f)) (free-transfer! live))
                      (when (or removed (not easy)) (guard (e (#t #f)) (release! engine token)))
                      (locked lock (lambda () (hashtable-delete! (engine-live engine) key)))
                      (token-live-set! token #f)
                      (complete! engine token failure chunks))))
                (live-entries engine))
      ;; A jar whose share an abandoned handle holds stays counted, closing.
      (guard (e (#t #f))
        (for-each (lambda (jar) (locked lock (lambda () (cookie-jar-state-set! jar 'closing))))
                  (free-jars! engine)))
      (when multi
        (guard (e (#t #f)) (curl-multi-cleanup multi)))
      (guard (e (#t #f)) (free-slot! engine))
      (locked lock
        (lambda ()
          (engine-multi-set! engine #f)
          (engine-state-set! engine 'failed))))))
