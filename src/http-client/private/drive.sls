#!r6rs
;;; (http-client private drive): the shell for one call, on its caller's
;;; thread. It reads the clocks, draws, submits, awaits, and hands each
;;; outcome to the core, (http-client private exchange), which answers what
;;; comes next: a next, a redirect's or a retry's, whose request goes
;;; through the core's submission, with the time left, as the first did,
;;; once its wait has passed: at once for a wait of 0.
;;;
;;; A wait above 0 is a take from an empty private mailbox, bounded by the
;;; wait: curl-mailbox-take polls, sleeping up to 10 ms between its looks,
;;; with interrupts on, so Ctrl-C and a timer reach it, and refuses to start
;;; inside a critical section, as every wait of (curl)'s does (ADR-0013).
;;; Each step draws one number from the session's generator, through DRAW,
;;; whether a retry reads it or not.
;;;
;;; The await is curl-token-wait in a loop, with no guard around it, then
;;; curl-token-outcome once the token is done: its response, as (response
;;; R), or its condition, as (failed C), read as data, never raised. So a
;;; step reads only a done token's own outcome, and nothing is live through
;;; a wait: the token the step read is done, and the next submit comes after
;;; the wait. Whatever the caller's interrupt handler or timer raises
;;; during the await, a &curl-error of a call the handler makes, #f, or any
;;; other object, is no outcome: it leaves as raised, and a handler that
;;; returns from a continuable raise resumes the wait. A guard around the
;;; await read such a raise as the transfer's failure, and retried it while
;;; the first transfer ran on, a post's among them; one that re-awaited the
;;; done token to tell them apart lost a raise landing there, and leaked the
;;; token's own condition raw.
;;;
;;; A call needs interrupts on: its await sleeps between its looks, and
;;; inside a critical section that sleep would hold every other thread's
;;; collections, the engine's with them, so (curl) refuses the wait. The
;;; drive asks first, before anything is submitted, by a take of no time
;;; from an empty mailbox, which (curl) refuses the same way and otherwise
;;; answers at once; that refusal alone, an assertion violation from
;;; curl-mailbox-take, is the call's, an assertion violation from
;;; http-request, with the call's &http-exchange and no transfer made.
;;; Anything else raised there, an interrupt handler's own raise among it,
;;; passes through as raised.
;;;
;;; One dynamic-wind spans the whole loop, every transfer of the call. Its
;;; after thunk cancels the token it recorded last, when that token is not
;;; done; every earlier one was done before the next submit. An escape
;;; from the await, by
;;; an interrupt handler, a timer, a Chez engine's expiry or a
;;; continuation, ends the transfer rather than leave it running with no
;;; one to await it. The wind is Chez's critical one, (dynamic-wind #t
;;; ...), whose before and after thunks run with interrupts off, as (curl
;;; private url)'s are: a second escape, a timer or a keyboard interrupt
;;; landing in the after thunk itself, waits until the cancel is made, so
;;; it cannot skip it. The cancel never waits. The submit and the set! that
;;; records its token run in one critical section, so an interrupt handler
;;; that escapes cannot fall between them, nor between the record and the
;;; protection: a keyboard interrupt made pending inside the section runs as
;;; it ends, once the token is recorded. Each submit of a call, a redirect's
;;; as the first, shares its section with its record. A submit never waits
;;; but for the engine's mutex; it does copy the request's body inside the
;;; section, as its private copy: about 50 ms for 64 MB, and 207 to 227 ms
;;; for 256 MB, which Ctrl-C then waits out.
;;;
;;; A call compounds its own failures with its &http-exchange: a &curl-error
;;; curl-submit raises is the core's (refused C), caught inside the submit's
;;; critical section, so a keyboard interrupt made pending there runs after
;;; the guard has gone, and its handler's raise is not read as the submit's;
;;; and a done token's condition, read as data, is its (failed C). Any other
;;; raise is the caller's own, an interrupt handler's or a timer's landing
;;; in the submit's end or the await, and leaves unchanged: no guard there
;;; takes it, and a handler that returns from a continuable raise resumes
;;; the call. A raise that leaves the call does so after the after thunk
;;; has cancelled.
;;;
;;; Each step, exchange-step's, and drive-stream's exchange-steps-past?,
;;; runs in a critical section of its own, its guard inside it, every raise
;;; answered as data and raised once the section has ended, as a group's
;;; turn steps its calls (section-step; ADR-0025): a redirect's step parses
;;; URLs through (curl)'s critical winds, and with interrupts on an expiry
;;; or a handler's raise there came out as call-with-parsed-url's refusal to
;;; re-enter one. So what a handler raises during a step comes once it has
;;; ended, as raised, and an expiry lands after it.
;;;
;;; --- the streamed call ---
;;;
;;; drive-stream drives a call whose responses stream, call-with-response-
;;; port's and http-request's with a producer: the same core, the same
;;; critical wind, and every wait a bounded poll, unguarded, read as data.
;;; Its two sides alternate: the response side, a head, a piece or the end;
;;; the request side, room, then the producer's next piece put. Each waits
;;; 10 ms, or 0 while the other side has just moved bytes, the flag cleared
;;; at a wait that finds nothing. The producer is fed wherever this thread
;;; waits, inside the port's read too, and only while no head is published
;;; or the head is the final one. At each head the draw and the clocks are
;;; read once, with the head's body-asked bit, for the core's predicate and
;;; for the hop's step alike.
;;;
;;; --- the request group ---
;;;
;;; A group drives many calls on its one thread, through one mailbox that
;;; every token it submits goes to (ADR-0021), on its session's engine: the
;;; thread that awaits drives them all, so a redirect or a retry of one call
;;; proceeds while another is awaited. Its record holds, on that thread
;;; alone:
;;;
;;;   - its calls, each a pending, in one of four phases: queued, waiting
;;;     its turn for a slot, on its clock; live, its token submitted and
;;;     not yet stepped; waiting, a retry's wait, keeping its slot, until a
;;;     due time; or ended, with its answer: done, fail or cancelled;
;;;   - the live set: each live token, mapped to its call, with the order
;;;     it was submitted in. A token is stepped only while it is in the
;;;     set, and taken out in the step, so a notice for a token outside it,
;;;     one a look found done first, or a cancelled one, is dropped: each
;;;     token is stepped once, and a notice an escape loses, from a take
;;;     that took it out (ADR-0021), is found by the next turn's
;;;     look;
;;;   - its draining tokens: those it cancelled, until each has ended;
;;;   - its slots: a call holds one from its first submit until it ends,
;;;     through every redirect's and retry's submit and through a retry's
;;;     wait, none of which waits for one. With a limit, a call that finds
;;;     none free queues, first in, first out, and is let in as one frees;
;;;   - its failures, in the order they came, and whether an await answered
;;;     each.
;;;
;;; A step is drive-exchange's: the done token's outcome read as data, by
;;; curl-token-outcome; then the draw, the UTC clock and the monotonic one,
;;; in that order; then exchange-step. done and fail end the call, and free
;;; its slot; a next with a wait of 0 submits at once, and one above 0
;;; waits until its due time. Each submit is exchange-submission's request,
;;; with the time left, and records its token in the live set in the same
;;; critical section, with the guard that reads the submit's own &curl-error
;;; inside it, as the core's (refused C) for that call alone: the engine
;;; stopped, a URL refused or the environment's refusal fails that call,
;;; and never leaves the await of another.
;;;
;;; Every change to the record is made inside a critical section that
;;; leaves it whole: a step, with whatever it submits; a due call's
;;; submit; a queued call's expiry; each admission; a cancel; and go's
;;; entry of a call, and http-parallel's of each of its calls, one section
;;; a call. None of them waits for a transfer: each holds a mutex briefly,
;;; the engine's for a submit, which copies the body there, for a step's
;;; read of its token's outcome, and for every cancel of a token; the
;;; mailbox's nested inside the engine's, for a cancel of a token still
;;; queued in the engine, not yet taken in by its thread, which completes
;;; it on this thread, into that mailbox; and the session's for a step's
;;; draw, a refused submit's among them. A cancel of
;;; a call waiting for a slot, or in a retry's wait, has no token, and holds
;;; no mutex. So an interrupt handler or a timer runs between them, never
;;; inside one, and an escape there leaves every call in exactly one phase,
;;; and every token where the group can find it.
;;;
;;; Inside each section that steps or submits one call, a guard takes
;;; anything that call's own code raises, the core's, a URL function's,
;;; the draw's, or a raise of curl-submit's that is no &curl-error, and ends
;;; the call with it as its failure: compounded with its &http-exchange when
;;; it is a condition that has none, as raised otherwise, its token, if one
;;; is live, cancelled and draining. So no raise strands a call outside
;;; every set, unended and holding its slot, where the join and every await
;;; would wait for good, and none leaves the await of another call. No
;;; interrupt handler runs inside the section, so the guard reads the
;;; code's own raises alone; a handler's comes as the section ends, outside
;;; it, and leaves as raised.
;;;
;;; A turn, run by an await, by http-pending-done? and by the join:
;;;   1. steps every token of the live set that curl-token-done? finds
;;;      done, oldest submit first, from a snapshot of the set;
;;;   2. drops each draining token that has ended;
;;;   3. submits every waiting call whose due time has passed;
;;;   4. fails every queued call whose deadline has passed, through
;;;      exchange-submission, which answers its &http-timeout, with no slot
;;;      taken;
;;;   5. lets queued calls in while slots are free, first in, first out;
;;;   6. takes once from the mailbox, bounded by the next due time, a
;;;      waiting call's or a queued call's deadline, rounded up to a whole
;;;      ms, and by 100 ms; or by 0 in a turn with no wait, or once what
;;;      its caller waits for has come. A token it takes that is in the set
;;;      is stepped; any other is dropped.
;;; No guard surrounds a wait or a take: whatever a caller's interrupt
;;; handler raises there leaves as raised, from the group operation that
;;; was running, and a handler that returns resumes it.
;;;
;;; The join is two winds around the group's procedure and the join itself.
;;; The body calls the procedure with go, marks the group closed, runs turns
;;; until no call is unended and no token live or draining, then raises the
;;; first failure no await answered, or answers the procedure's values: the
;;; first the group saw fail, ties a look found together in the order of
;;; their latest submits, a redirect's or a retry's among them, so a call
;;; that redirected sorts after one started later; a call its caller
;;; cancelled exempt, as one an await answered is. The
;;; inner wind is Chez's critical one, (dynamic-wind #t ...): its after
;;; thunk marks the group closed, cancels every live token, which joins the
;;; draining ones, and ends every unended call as cancelled; it never
;;; waits, and a second escape cannot skip it. The outer wind is a plain
;;; one, whose after thunk waits, with interrupts on, by curl-token-wait in
;;; a loop, unguarded, for every live and draining token to end. On a
;;; normal exit both find nothing to do. On an escape, from the procedure or
;;; from the join's own waits, a raise caught outside or a continuation
;;; alike, the cancel is made with interrupts off, then the wait. A second
;;; escape during that wait abandons it, and leaves those tokens live:
;;; documented, not prevented, as is the wait itself, which a stalled lookup
;;; on 7.85.0 to 7.86.x holds up to glibc's resolver timeout (ADR-0019). A
;;; handler installed outside the group by with-exception-handler runs where
;;; the raise is made, inside the group's extent, before either wind has
;;; run: it sees every call as it was. And a Chez engine's expiry is an
;;; escape: around a group, the first expiry ends the whole group, each call
;;; cancelled, and closes it, and once resumed the procedure's await raises
;;; cancelled, as any escape's would. A go resumed before it had entered its
;;; call raises closed: it asks again inside its entry's section, after its
;;; checks, and raises once that section has ended, so a handler around go
;;; runs with interrupts on. A go resumed after its entry, in its
;;; admissions, answers its pending, whose await raises cancelled. A resumed
;;; http-parallel enters no call more, and raises its first failure, if any,
;;; or else the cancel of its first call not done. A call's checks, go's and
;;; http-parallel's among them, run in one critical section of
;;; (http-client)'s call-state, so no expiry lands inside them: one that
;;; runs out there lands after them, once the section has ended (ADR-0025).
;;;
;;; A group is its thread's, by get-thread-id: go, http-await,
;;; http-pending-done? and http-pending-cancel from any other raise
;;; &http-group-error, wrong-thread, before anything else, and go once the
;;; procedure has returned or escaped, closed. http-await,
;;; http-pending-done?, and the group's and http-parallel's entries, which
;;; run turns, refuse inside a critical section, as an assertion violation
;;; naming the procedure; go and http-pending-cancel wait for no transfer,
;;; only for the brief holds of mutexes a section makes, above, and go
;;; copies its call's body, and neither refuses for it.
;;;
;;; The seams, for the tests alone, which (http-client) does not export:
;;; drive-stream-waits, the streamed drive's count of its response side's
;;; waits by their bound; drive-produce-gate-set! and drive-before-gate-set!,
;;; each a thunk run once in the producer's critical after thunk, and in its
;;; critical before thunk, inside the port's read; drive-last-token, once
;;; drive-last-token-arm! arms it, the latest streamed call's token, until
;;; that call ends; http-pending-mailbox, the group's mailbox;
;;; http-pending-token, a call's live token; http-pending-phase, its phase;
;;; http-pending-census, the group's counts; none runs a turn;
;;; drive-checks-gate-set!, a procedure (http-client)'s call-state calls
;;; with start and with end, the first and last forms of a call's checks,
;;; inside their critical section, until it is disarmed;
;;; drive-step-gate-set!, its twin, called with start and end around each
;;; step, inside the step's section, a group's too. And
;;; call-with-group, the group's own entry, takes an optional submit in
;;; place of curl-submit, so a test can plant a raise in one submit.
(library (http-client private drive)
  (export drive-exchange drive-stream drive-stream-waits drive-produce-gate-set! drive-last-token
          drive-last-token-arm! drive-before-gate-set! drive-checks-gate-set! run-checks-gate!
          drive-step-gate-set!
          monotonic-ns utc-seconds take-refusal?
          require-interrupts call-with-group run-parallel
          http-pending? http-await http-pending-done? http-pending-cancel
          http-pending-mailbox http-pending-token http-pending-phase http-pending-census)
  (import (curl)
          (except (rnrs) dynamic-wind)
          (only (chezscheme) critical-section current-time dynamic-wind get-thread-id time-second
                time-nanosecond)
          (http-client private conditions)
          (http-client private exchange))

  ;; monotonic-ns : -> Integer
  ;; The monotonic clock, in ns.
  (define (monotonic-ns)
    (let ((t (current-time 'time-monotonic)))
      (+ (* (time-second t) 1000000000) (time-nanosecond t))))

  ;; utc-seconds : -> Integer
  ;; The UTC clock, in whole seconds since 1970.
  (define (utc-seconds)
    (time-second (current-time 'time-utc)))

  ;; take-refusal? : Any -> Boolean
  ;; Whether E is the refusal a take makes inside a critical section: an
  ;; assertion violation whose who is curl-mailbox-take. A fresh mailbox and
  ;; a bound of 0 give the take no other refusal to make.
  (define (take-refusal? e)
    (and (assertion-violation? e) (who-condition? e) (eq? (condition-who e) 'curl-mailbox-take)))

  ;; interrupts-on? : -> Boolean
  ;; Whether this thread runs with interrupts on, as (curl) judges it for a
  ;; wait: a take of no time from a fresh mailbox raises its refusal inside
  ;; a critical section before it does anything, and answers #f at once
  ;; outside one. Anything else the take meets, an interrupt handler's raise
  ;; landing in it, passes through.
  (define (interrupts-on?)
    (guard (e ((take-refusal? e) #f))
      (curl-mailbox-take (make-curl-mailbox) 0)
      #t))

  ;; refuse-without-interrupts : State [Symbol] -> Nothing
  ;; The call's refusal inside a critical section: an assertion violation
  ;; from WHO, http-request unless given, compounded with STATE's
  ;; &http-exchange.
  (define (refuse-without-interrupts state . who)
    (raise (condition (make-assertion-violation)
                      (make-who-condition (if (pair? who) (car who) 'http-request))
                      (make-message-condition
                       "a call needs interrupts on: inside a critical section its await would hold every collection, so nothing was submitted")
                      (make-irritants-condition '())
                      (exchange-condition state))))

  ;; pause : Natural -> Void
  ;; Waits MS ms, by a take from an empty mailbox no one else holds, which
  ;; answers #f once they pass.
  (define (pause ms)
    (when (curl-mailbox-take (make-curl-mailbox) ms)
      (assertion-violation 'drive-exchange "a take from an empty private mailbox found a token" ms)))

  ;; outcome-of : Token -> (U (List 'response Response) (List 'failed Condition))
  ;; TOKEN's outcome once its transfer has ended: curl-token-wait in a loop,
  ;; a second at a time, with no guard, so whatever an interrupt handler
  ;; raises there leaves as raised, and a resumed raise goes on waiting;
  ;; then curl-token-outcome, read as data, never raised.
  (define (outcome-of token)
    (let wait ()
      (unless (curl-token-wait token 1000) (wait)))
    (let ((outcome (curl-token-outcome token)))
      (if (curl-response? outcome)
          (list 'response outcome)
          (list 'failed outcome))))

  ;; section-step : State Outcome Integer Integer Real -> Step
  ;; exchange-step's answer for STATE and OUTCOME at NOW-NS, UTC-S and DRAW,
  ;; made in a critical section of its own, whose guard takes every raise
  ;; there and answers it as data, raised once the section has ended, as a
  ;; group's turn steps its calls (ADR-0025). A redirect's step parses its
  ;; Location and the URLs it compares through (curl)'s critical winds, some
  ;; under a guard of &curl-url-error alone: with interrupts on, an engine's
  ;; expiry inside a parse left it behind, and a handler's raise there that
  ;; the guard declined was re-raised back inside it, each coming out as
  ;; call-with-parsed-url's refusal to re-enter it, in place of the call's
  ;; answer. Inside the section no handler runs and no expiry lands: a
  ;; Ctrl-C made pending there runs as it ends, a timer and an expiry at a
  ;; later event check, after the step. A step waits for nothing and calls
  ;; no caller code; it holds Ctrl-C and other threads' collections for its
  ;; length, under 0.5 ms for an ordinary redirect, and as its inputs grow,
  ;; to what libcurl lets in: 124 to 181 ms for the largest step 7.85.0,
  ;; 8.20.0 and 8.23.0 let one make, a requested URL of about 1,048,500
  ;; chars, within the 1 MiB they send a request in, a Location of 102,387
  ;; bytes, the most each takes under its 100 KiB cap on a header, and the
  ;; most headers each takes, 5,000, or 100,003 on 7.85.0, which caps none;
  ;; 11 to 17 ms on 8.5.0, which sent no URL past 131,041 chars, a longer
  ;; request stalling to its timeout; the headers alone under 0.5 ms.
  (define (section-step state outcome now-ns utc-s draw)
    (in-step-section (lambda () (exchange-step state outcome now-ns utc-s draw))))

  ;; sectioned-step : State Outcome Integer Real -> Step
  ;; section-step's answer, the monotonic clock read inside the section,
  ;; after UTC-S and DRAW, as the step reads its clocks last.
  (define (sectioned-step state outcome utc-s draw)
    (in-step-section (lambda () (exchange-step state outcome (monotonic-ns) utc-s draw))))

  ;; section-steps-past? : State Response Integer Integer Real -> Boolean
  ;; exchange-steps-past?'s answer, made in a critical section of its own,
  ;; as section-step makes a step's.
  (define (section-steps-past? state response now-ns utc-s draw)
    (in-step-section (lambda () (exchange-steps-past? state response now-ns utc-s draw))))

  ;; in-step-section : (-> Any) -> Any
  ;; THUNK's value, a step's, run in a critical section of its own whose
  ;; guard takes every raise there and answers it as data, raised once the
  ;; section has ended: so the caller's handler for it runs with interrupts
  ;; on. The test seam's step gate is called with start and end inside the
  ;; section, around THUNK.
  (define (in-step-section thunk)
    (let ((r (critical-section
              (guard (e (#t (list 'raised e)))
                (run-step-gate! 'start)
                (let ((v (thunk)))
                  (run-step-gate! 'end)
                  (list 'value v))))))
      (if (eq? (car r) 'raised)
          (raise (cadr r))
          (cadr r))))

  ;; drive-exchange : Engine State (-> Real) -> Response
  ;; STATE's call, driven on ENGINE until the core answers done, whose
  ;; response it answers, or fail, whose condition it raises; a next is
  ;; submitted from its state once its wait has passed, at once for 0; a
  ;; submission's own done or fail, a retry's time run out, ends it. Each
  ;; step draws from DRAW, a number in [0, 1), then reads the UTC clock and
  ;; the monotonic clock, in that order, so the bound's clock is read last.
  ;; With interrupts off it refuses, before the first submit.
  (define (drive-exchange engine state draw)
    (unless (interrupts-on?)
      (refuse-without-interrupts state))
    (let ((token #f))
      (dynamic-wind #t
        (lambda () #f)
        (lambda ()
          (let loop ((state state))
            (let ((submission (exchange-submission state (monotonic-ns))))
              (case (car submission)
                ((fail) (raise (cadr submission)))
                ((done) (cadr submission))
                (else
                 (let* ((state (cadr submission))
                        (request (caddr submission))
                        (refusal (critical-section
                                  (guard (e ((curl-error? e) (list 'refused e)))
                                    (set! token (curl-submit engine request))
                                    #f)))
                        (outcome (or refusal (outcome-of token)))
                        (drawn (draw))
                        (utc (utc-seconds))
                        (step (sectioned-step state outcome utc drawn)))
                   (case (car step)
                     ((done) (cadr step))
                     ((fail) (raise (cadr step)))
                     ((next)
                      (let ((wait (cadddr step)))
                        (unless (and (integer? wait) (exact? wait) (>= wait 0))
                          (assertion-violation 'drive-exchange
                                               "the core answered a next whose wait is no natural"
                                               step))
                        (when (> wait 0) (pause wait))
                        (loop (cadr step))))
                     (else
                      (assertion-violation 'drive-exchange
                                           "the core answered a step this shell does not know"
                                           step)))))))))
        (lambda ()
          (when (and token (not (curl-token-done? token)))
            (curl-token-cancel token))))))

  ;; --- the streamed call (ADR-0031, ADR-0032) ------------------------------------------

  ;; side-ms : Natural
  ;; The bound of a side's wait while the other side has not just moved
  ;; bytes: 10 ms, as measured.
  (define side-ms 10)

  ;; A streamed call's record beside its exchange: its producer, or #f;
  ;; WHO, the call's name in what it refuses; whether the producer has been
  ;; called; whether it runs now, which a read of the port it feeds meets;
  ;; and the producer's failure inside the port's read, the call's for good,
  ;; or #f.
  (define-record-type (stream-call make-stream-call stream-call?)
    (fields (immutable producer call-producer)
            (immutable who call-who)
            (mutable called call-called? call-called-set!)
            (mutable producing call-producing? call-producing-set!)
            (mutable stuck call-stuck call-stuck-set!))
    (sealed #t)
    (opaque #t))

  ;; A leg: one transfer of a streamed call, and its two sides. Its token;
  ;; its call; its body's length, or #f; its request side's phase: none for
  ;; a transfer whose body does not stream, feeding, ending once the
  ;; producer answered the eof object, until curl-token-end-body! has
  ;; returned, ended then, or stopped; the producer's answer, (ANSWER), as
  ;; produce! holds it, not yet taken; the piece taken from it, held until
  ;; a put takes it; the bytes put; whether its head is known final, and so
  ;; fed; and each side's flag, whether it has just moved bytes, which
  ;; bounds the other side's wait by 0 ms. A keyboard interrupt whose
  ;; handler escapes as a critical section ends, and which PROC catches,
  ;; finds each of the producer's answer, the end and the held piece where
  ;; the next feed! takes it up: none is lost, none given twice, and the
  ;; producer never called after its eof.
  (define-record-type (leg make-leg leg?)
    (fields (immutable token leg-token)
            (immutable call leg-call)
            (immutable length leg-length)
            (mutable phase leg-phase leg-phase-set!)
            (mutable answer leg-answer leg-answer-set!)
            (mutable held leg-held leg-held-set!)
            (mutable put leg-put leg-put-set!)
            (mutable final leg-final? leg-final-set!)
            (mutable req-moved leg-req-moved? leg-req-moved-set!)
            (mutable resp-moved leg-resp-moved? leg-resp-moved-set!))
    (sealed #t)
    (opaque #t))

  ;; resp-bound, req-bound : Leg -> Natural
  ;; A side's wait: 0 ms while the other side has just moved bytes, else
  ;; side-ms. Strict alternation, a whole bound on each side every turn,
  ;; cost one bound per piece: 9.64 to 12.7 MB/s at 10 ms, where this ran at
  ;; 24.1 to 212.6.
  (define (resp-bound leg)
    (let ((ms (if (leg-req-moved? leg) 0 side-ms)))
      (vector-set! wait-counts (if (= ms 0) 0 1) (+ 1 (vector-ref wait-counts (if (= ms 0) 0 1))))
      ms))
  (define (req-bound leg) (if (leg-resp-moved? leg) 0 side-ms))

  ;; wait-counts : (Vector Natural Natural)
  ;; The response side's waits, every streamed call's since the library was
  ;; loaded: those bounded by 0 ms, then those by side-ms. A seam for the
  ;; suites alone, read by drive-stream-waits; threads that stream at once
  ;; may lose a count, which no rule reads.
  (define wait-counts (vector 0 0))

  ;; drive-stream-waits : -> (List Natural Natural)
  ;; wait-counts now: the response side's waits bounded by 0 ms, and by
  ;; side-ms. A test seam, which (http-client) does not export.
  (define (drive-stream-waits)
    (list (vector-ref wait-counts 0) (vector-ref wait-counts 1)))

  ;; resp-waited! : Leg Boolean -> Void
  ;; LEG's response side has waited, GOT whether it found a piece, a head
  ;; or the end: its own flag set to that; and a wait that found nothing
  ;; clears the request side's, so a request side that moves no more, its
  ;; body ended, is never waited for at 0 ms again. A drive that kept it
  ;; polled at 0 ms for good, millions of times, and under Valgrind starved
  ;; the engine's thread.
  (define (resp-waited! leg got)
    (leg-resp-moved-set! leg got)
    (unless got (leg-req-moved-set! leg #f)))

  ;; req-waited! : Leg Boolean Boolean -> Void
  ;; LEG's request side has stepped: MOVED, whether it moved bytes, a put
  ;; taken or the body's end, is its own flag; and EMPTY, a wait that found
  ;; nothing, clears the response side's.
  (define (req-waited! leg moved empty)
    (leg-req-moved-set! leg moved)
    (when empty (leg-resp-moved-set! leg #f)))

  ;; feed! : Leg Boolean State -> Void
  ;; One step of LEG's request side, while it feeds, bounded by req-bound:
  ;; the piece it holds put; or room waited for, then, with room, the head
  ;; read, and the producer called only while no head is published or the
  ;; head is known final. A head published before libcurl's first ask, then
  ;; followed by one, a hop's or one still to be read, is never fed; the
  ;; final head is fed whenever libcurl asks, its bit #f among them. A token
  ;; done stops it. Once the puts have taken the body-length whole, the
  ;; producer is asked for its end at once, by end-at-length!, never waiting
  ;; for room. A body-length of 0, which libcurl never asks for, never calls
  ;; the producer. STICKY? is the port's: a producer's failure there is the
  ;; call's for good. STATE is the transfer's, for what a refusal compounds.
  ;; Each wait is a bounded poll, unguarded, read as data.
  (define (feed! leg sticky? state)
    (case (leg-phase leg)
      ((feeding)
       (let ((token (leg-token leg)) (ms (req-bound leg)))
         (cond
           ((leg-answer leg) (take-answer! leg ms sticky? state))
           ((leg-held leg) (put-held! leg ms sticky? state))
           ((at-length? leg)
            (if (unfed-head? leg) (req-waited! leg #f #f) (produce-and-put! leg ms sticky? state)))
           (else
            (let ((room (curl-token-room-wait token ms)))
              (cond ((eq? room 'done) (leg-phase-set! leg 'stopped) (req-waited! leg #f #f))
                    ((not room) (req-waited! leg #f #t))
                    ((unfed-head? leg) (req-waited! leg #f #f))
                    (else (produce-and-put! leg ms sticky? state))))))))
      ((ending) (end-body-now! leg))
      (else #f)))

  ;; at-length? : Leg -> Boolean
  ;; Whether LEG still feeds, holds no piece, and its puts have taken a
  ;; body-length above 0 whole.
  (define (at-length? leg)
    (let ((length (leg-length leg)))
      (and (eq? (leg-phase leg) 'feeding) (not (leg-answer leg)) (not (leg-held leg)) length
           (> (leg-put leg) 0) (= (leg-put leg) length))))

  ;; end-at-length! : Leg Natural Boolean State -> Void
  ;; Once LEG's puts have taken its body-length whole, the producer asked
  ;; for its end at once, room or none, unless a head not known final is
  ;; published: libcurl asks for nothing more, and whether the producer ends
  ;; there or gives more is the producer's to tell. Waiting for room, the
  ;; drive was answered done whenever the server's answer ended the transfer
  ;; first, and never asked: a producer that gave more than its length then
  ;; passed as a 200, on a drive whose waits were 10 ms. Asked here, a piece
  ;; past the length fails the call alike however quickly the server answers
  ;; (ADR-0031). It is made after the put that took the length, in that
  ;; step, and again at the final head.
  (define (end-at-length! leg ms sticky? state)
    (when (and (at-length? leg) (not (unfed-head? leg)))
      (produce-and-put! leg ms sticky? state)))

  ;; unfed-head? : Leg -> Boolean
  ;; Whether LEG's token has published a head not yet known final: a hop's,
  ;; or one its drive has still to read, which is never fed.
  (define (unfed-head? leg)
    (and (curl-token-head (leg-token leg)) (not (leg-final? leg)) #t))

  ;; produce-and-put! : Leg Natural Boolean State -> Void
  ;; The producer's next answer, called once libcurl has room for it, held
  ;; by produce!, then taken and checked by take-answer! before anything is
  ;; put: the eof object ends the body, which the low level fails as
  ;; body-length-mismatch when it is short of the body-length, alike on
  ;; every libcurl (ADR-0031); a bytevector of a byte or more is held, then
  ;; put, bounded by MS, unless it would take the body past its body-length;
  ;; anything else, and a piece past the body-length, is the call's refusal,
  ;; by refuse!, before any of it reaches libcurl. A producer is never
  ;; called after it answered the eof object: the request side is ending or
  ;; has ended.
  (define (produce-and-put! leg ms sticky? state)
    (produce! leg sticky?)
    (take-answer! leg ms sticky? state))

  ;; take-answer! : Leg Natural Boolean State -> Void
  ;; The producer's answer that produce! holds in LEG, taken and checked:
  ;; the eof object ends the body, LEG ending first, in one critical section
  ;; with the answer's removal, so an escape as curl-token-end-body!'s
  ;; section ends leaves it ending, and the next feed! ends it again, never
  ;; calling the producer; a bytevector of a byte or more becomes the held
  ;; piece, in one section with the answer's removal, then is put, unless
  ;; it would take the body past its body-length, which is refused,
  ;; &http-request-error, body-length-mismatch (ADR-0031); anything else is
  ;; refused, an assertion violation.
  (define (take-answer! leg ms sticky? state)
    (let ((answer (car (leg-answer leg))))
      (cond
        ((eof-object? answer)
         (critical-section
          (leg-answer-set! leg #f)
          (leg-phase-set! leg 'ending))
         (end-body-now! leg))
        ((and (bytevector? answer) (> (bytevector-length answer) 0))
         (let ((length (leg-length leg)))
           (if (and length (> (+ (leg-put leg) (bytevector-length answer)) length))
               (refuse! leg sticky?
                        (condition (make-http-request-error 'body (call-producer (leg-call leg))
                                                            'body-length-mismatch)
                                   (make-who-condition (call-who (leg-call leg)))
                                   (make-message-condition
                                    "a producer gave more than its body-length: the transfer is cancelled, and nothing past the length was put")
                                   ;; As the low level's put orders them.
                                   (make-irritants-condition (list length (bytevector-length answer)))
                                   (exchange-live-condition state)))
               (begin
                 (critical-section
                  (leg-answer-set! leg #f)
                  (leg-held-set! leg answer))
                 (put-held! leg ms sticky? state)))))
        (else
         (refuse! leg sticky?
                  (condition (make-assertion-violation)
                             (make-who-condition (call-who (leg-call leg)))
                             (make-message-condition
                              "a producer answers a bytevector of a byte or more, or the eof object at its body's end")
                             (make-irritants-condition (list (shown-value answer)))
                             (exchange-live-condition state)))))))

  ;; end-body-now! : Leg -> Void
  ;; LEG's body ended, which curl-token-end-body! does once, nothing a
  ;; second time, then LEG ended.
  (define (end-body-now! leg)
    (curl-token-end-body! (leg-token leg))
    (leg-phase-set! leg 'ended)
    (req-waited! leg #t #f))

  ;; put-held! : Leg Natural Boolean State -> Void
  ;; LEG's held piece put, bounded by MS, unless curl-token-body-count says
  ;; an earlier put of it committed it before an escape: taken, counted and
  ;; let go, and, the body-length then taken whole, the producer asked for
  ;; its end at once; done, the token done, the request side stopped; or the
  ;; bound passed, the piece still held. It is within the body-length,
  ;; checked before the hold, and the body has not ended, so the put raises
  ;; nothing of its own, and no guard is around it.
  (define (put-held! leg ms sticky? state)
    (let ((answer (if (= (curl-token-body-count (leg-token leg))
                         (+ (leg-put leg) (bytevector-length (leg-held leg))))
                      ;; Committed already, by a put an interrupt handler
                      ;; escaped from as its hold ended, and caught in PROC:
                      ;; taken, never put twice.
                      #t
                      (curl-token-put-piece! (leg-token leg) (leg-held leg) ms))))
      (cond ((eq? answer #t)
             (leg-put-set! leg (+ (leg-put leg) (bytevector-length (leg-held leg))))
             (leg-held-set! leg #f)
             (req-waited! leg #t #f)
             (end-at-length! leg ms sticky? state))
            ((eq? answer 'done)
             (leg-held-set! leg #f)
             (leg-phase-set! leg 'stopped)
             (req-waited! leg #f #f))
            (else (req-waited! leg #f #t)))))

  ;; refuse! : Leg Boolean Condition -> Nothing
  ;; The call's refusal C of a producer's answer, in one critical section:
  ;; inside the port's read, STICKY?, C recorded first as the call's failure
  ;; for good; LEG stopped, its answer and its held piece dropped; then its
  ;; transfer cancelled. C is raised once the section has ended, so a
  ;; keyboard interrupt whose handler escapes there finds everything
  ;; recorded, and the next read raises C.
  (define (refuse! leg sticky? c)
    (critical-section
     (when (and sticky? (not (call-stuck (leg-call leg))))
       (call-stuck-set! (leg-call leg) c))
     (leg-phase-set! leg 'stopped)
     (leg-answer-set! leg #f)
     (leg-held-set! leg #f)
     (curl-token-cancel (leg-token leg)))
    (raise c))

  ;; produce! : Leg Boolean -> Void
  ;; The producer called on this thread, the call marked called, and
  ;; producing while it runs, so a read of the port it feeds is refused;
  ;; its answer, once it returns, held in LEG in the critical after thunk,
  ;; so an escape as that thunk's section ends finds it there, for the next
  ;; feed! to take (take-answer!). With STICKY?, inside the port's read, a
  ;; raise that leaves the producer is the call's failure for good: seen as
  ;; it passes, by a handler that hands it on, continuably, then, once it
  ;; has left the producer, recorded and the transfer cancelled, in the
  ;; after thunk of a critical wind; it leaves as raised, and one an outer
  ;; handler returns from resumes the producer, and is then no failure. The
  ;; record and the cancel are made only once the producer was entered, a
  ;; flag set as the first form inside the handler's thunk: a keyboard
  ;; interrupt that escapes as the before thunk's section ends leaves
  ;; before it, and neither is made, so PROC, catching it, reads on, and the
  ;; producer is called again.
  ;; Without STICKY?, a raise leaves the call as raised, and the call's own
  ;; wind cancels the transfer.
  (define (produce! leg sticky?)
    (let ((call (leg-call leg)) (seen #f) (got #f) (entered #f))
      (call-called-set! call #t)
      (dynamic-wind #t
        (lambda () (call-producing-set! call #t) (when sticky? (run-before-gate!)))
        (lambda ()
          (set! got (list (if sticky?
                              (with-exception-handler
                                (lambda (e)
                                  (set! seen (list e))
                                  (let ((v (raise-continuable e)))
                                    (set! seen #f)
                                    v))
                                (lambda ()
                                  (set! entered #t)
                                  ((call-producer call))))
                              ((call-producer call))))))
        (lambda ()
          (call-producing-set! call #f)
          (if got
              (leg-answer-set! leg got)
              (when (and sticky? entered)
                (when (and seen (not (call-stuck call))) (call-stuck-set! call (car seen)))
                (curl-token-cancel (leg-token leg))))
          (when sticky? (run-produce-gate!))))))

  ;; produce-gate : (Vector (U (-> Any) #f))
  ;; A test seam's thunk, run once, inside the port's read, in produce!'s
  ;; critical after thunk, then dropped: a test blocks there on a mutex
  ;; another thread holds while that thread sends SIGINT, so a keyboard
  ;; interrupt runs as the after thunk's section ends.
  (define produce-gate (vector #f))

  ;; drive-produce-gate-set! : (U (-> Any) #f) -> Void
  ;; Arms the gate, the test seam above, which (http-client) does not export.
  (define (drive-produce-gate-set! thunk) (vector-set! produce-gate 0 thunk))

  ;; run-produce-gate! : -> Void
  (define (run-produce-gate!)
    (let ((g (vector-ref produce-gate 0)))
      (when g
        (vector-set! produce-gate 0 #f)
        (g))))

  ;; before-gate : (Vector (U (-> Any) #f))
  ;; The produce gate's twin, a test seam's thunk run once, inside the
  ;; port's read, in produce!'s critical before thunk, then dropped, so a
  ;; keyboard interrupt runs as the before thunk's section ends, before the
  ;; producer is entered.
  (define before-gate (vector #f))

  ;; drive-before-gate-set! : (U (-> Any) #f) -> Void
  ;; Arms the before gate, which (http-client) does not export.
  (define (drive-before-gate-set! thunk) (vector-set! before-gate 0 thunk))

  ;; run-before-gate! : -> Void
  (define (run-before-gate!)
    (let ((g (vector-ref before-gate 0)))
      (when g
        (vector-set! before-gate 0 #f)
        (g))))

  ;; checks-gate : (Vector (U (Symbol -> Any) #f))
  ;; A test seam's procedure, kept until disarmed, which call-state calls
  ;; with start and with end, the first and last forms of a call's checks,
  ;; inside their critical section: a test blocks at start on a mutex
  ;; another thread holds while that thread sends SIGINT, so a keyboard
  ;; interrupt is made pending inside the section, and an engine's sweep
  ;; reads where its expiry landed. #f, unarmed, by default.
  (define checks-gate (vector #f))

  ;; drive-checks-gate-set! : (U (Symbol -> Any) #f) -> Void
  ;; Arms the gate, the test seam above, or disarms it with #f: a test
  ;; seam, which (http-client) does not export.
  (define (drive-checks-gate-set! proc) (vector-set! checks-gate 0 proc))

  ;; run-checks-gate! : Symbol -> Void
  ;; The gate's procedure called with WHERE, start or end, when armed.
  (define (run-checks-gate! where)
    (let ((g (vector-ref checks-gate 0)))
      (when g (g where))))

  ;; step-gate : (Vector (U (Symbol -> Any) #f))
  ;; The checks gate's twin for a step: a test seam's procedure, kept until
  ;; disarmed, called with start and with end around each exchange-step and
  ;; exchange-steps-past?, inside its critical section, the single-call
  ;; drives' and a group's alike. #f, unarmed, by default.
  (define step-gate (vector #f))

  ;; drive-step-gate-set! : (U (Symbol -> Any) #f) -> Void
  ;; Arms the step gate, or disarms it with #f: a test seam, which
  ;; (http-client) does not export.
  (define (drive-step-gate-set! proc) (vector-set! step-gate 0 proc))

  ;; run-step-gate! : Symbol -> Void
  (define (run-step-gate! where)
    (let ((g (vector-ref step-gate 0)))
      (when g (g where))))

  ;; last-token : (Vector Boolean (U Token #f))
  ;; The test seam's record: whether a test has armed it; then the token the
  ;; latest streamed call submitted while armed, held only until that call
  ;; ends, when its own after thunk lets it go. Unarmed, it records nothing,
  ;; so no call's token, nor the private copy of a whole body its plan
  ;; holds, outlives the call through the seam: held for good, a 64 MiB
  ;; body's call kept 64.1 MB until the next.
  (define last-token (vector #f #f))

  ;; drive-last-token-arm! : Boolean -> Void
  ;; Arms the seam, or, with #f, disarms it and drops what it holds: a
  ;; test seam, which (http-client) does not export.
  (define (drive-last-token-arm! on?)
    (vector-set! last-token 0 (and on? #t))
    (unless on? (vector-set! last-token 1 #f)))

  ;; drive-last-token : -> (U Token #f)
  ;; While the seam is armed, the token the latest streamed call submitted,
  ;; until that call ends; else #f: a test seam, read only, which
  ;; (http-client) does not export, so a test can hold that token's request
  ;; stream by the low level's own seam.
  (define (drive-last-token) (vector-ref last-token 1))

  ;; wait-head! : Leg State -> Void
  ;; Waits until LEG's head is published or its token done, its response
  ;; side and its request side in turn.
  (define (wait-head! leg state)
    (let loop ()
      (let ((got (curl-token-head-wait (leg-token leg) (resp-bound leg))))
        (resp-waited! leg got)
        (unless got
          (feed! leg #f state)
          (loop)))))

  ;; read-whole! : Leg State
  ;;               -> (U (List 'response Curl-Response Bytevector) (List 'failed Condition))
  ;; LEG's body read whole, piece by piece, its request side fed in turn:
  ;; once the token is done and every piece taken, the transfer's response
  ;; and the bytes, or its failure, read as data. The low level holds a
  ;; stream to its body-limit, failing the transfer past it.
  (define (read-whole! leg state)
    (let loop ((pieces '()))
      (let ((p (curl-token-next-piece (leg-token leg) (resp-bound leg))))
        (resp-waited! leg (bytevector? p))
        (cond ((bytevector? p) (loop (cons p pieces)))
              ((eof-object? p)
               (let ((o (curl-token-outcome (leg-token leg))))
                 (if (curl-response? o)
                     (list 'response o (joined (reverse pieces)))
                     (list 'failed o))))
              (else (feed! leg #f state) (loop pieces))))))

  ;; joined : (Listof Bytevector) -> Bytevector
  ;; PIECES' bytes, in order, in one fresh bytevector.
  (define (joined pieces)
    (let ((out (make-bytevector (fold-left (lambda (n p) (+ n (bytevector-length p))) 0 pieces))))
      (let loop ((rest pieces) (at 0))
        (if (null? rest)
            out
            (let ((n (bytevector-length (car rest))))
              (bytevector-copy! (car rest) 0 out at n)
              (loop (cdr rest) (+ at n)))))))

  ;; end-hop! : Token -> Void
  ;; A hop's transfer cancelled at its head, and waited for, a second at a
  ;; time, unguarded, so the next submit comes once it has ended, and the
  ;; call's wind has one live token to cancel (ADR-0031).
  (define (end-hop! token)
    (curl-token-cancel token)
    (let wait () (unless (curl-token-wait token 1000) (wait))))

  ;; head-response : Integer (U Symbol Integer #f) (Listof (Pairof String String)) -> Response
  ;; A head's response, as the core reads it: its status, version and
  ;; headers, a body and timings of #f; the core gives it the URL in flight
  ;; and the history.
  (define (head-response status version headers)
    (make-http-response status version "" headers #f #f '()))

  ;; call-port : Leg State -> Binary-Input-Port
  ;; The call's port over LEG's body, the high level's own: a read copies
  ;; from the piece at hand, or takes the next by curl-token-next-piece,
  ;; feeding the producer between its waits, as the drive does, so a
  ;; full-duplex server is never left without a body. Its ends stick: 0 once
  ;; the transfer ended with a response and every piece is read; for a
  ;; failure, the low level's condition compounded with the call's
  ;; &http-exchange, and with &http-timeout when it is the call's bound's
  ;; 28, raised every time after; and once the producer failed inside a
  ;; read, that failure, raised by every read after. A read from the
  ;; producer, while it runs, and a read or a close from another thread are
  ;; assertion violations from the call; so is a read that must wait inside
  ;; a critical section, before it waits. Its close cancels a live transfer.
  ;; Bytes Chez's port has already buffered are served to any thread with no
  ;; read reaching it, as the low level's port's are.
  (define (call-port leg state)
    (let* ((call (leg-call leg))
           (who (call-who call))
           (token (leg-token leg))
           (owner (get-thread-id))
           (at-hand #f)
           (offset 0)
           (end #f))
      (define (own)
        (let ((here (get-thread-id)))
          (unless (eqv? here owner)
            (assertion-violation who "a call's port is read and closed on the call's thread alone"
                                 owner here))))
      (define (give! bv start count)
        (let ((k (min count (- (bytevector-length at-hand) offset))))
          (bytevector-copy! at-hand offset bv start k)
          (set! offset (+ offset k))
          k))
      (define (read! bv start count)
        (own)
        (when (call-producing? call)
          (assertion-violation who "a producer read the port it feeds"))
        (let ((stuck (call-stuck call)))
          (when stuck (raise stuck)))
        (cond
          ((and at-hand (< offset (bytevector-length at-hand))) (give! bv start count))
          ((eq? end 'eof) 0)
          (end (raise end))
          (else
           (unless (interrupts-on?)
             (assertion-violation who "a call's port waits for its body, which needs interrupts on"))
           (let loop ()
             (let ((p (curl-token-next-piece token (resp-bound leg))))
               ;; A piece taken is held at once, before any call, so an
               ;; escape caught in PROC loses none of it.
               (when (bytevector? p) (set! at-hand p) (set! offset 0))
               (resp-waited! leg (bytevector? p))
               (cond
                 ((bytevector? p) (give! bv start count))
                 ((eof-object? p)
                  (let ((o (curl-token-outcome token)))
                    (if (curl-response? o)
                        (begin (set! end 'eof) 0)
                        (let ((c (exchange-raised state o (monotonic-ns))))
                          (set! end c)
                          (raise c)))))
                 (else (feed! leg #t state) (loop))))))))
      (make-custom-binary-input-port "http-response-body" read! #f #f
                                     (lambda () (own) (curl-token-cancel token)))))

  ;; drive-stream : Engine State (-> Real) (U Procedure #f) (U 'port 'whole)
  ;;                (U (Response Binary-Input-Port -> Any) #f) Symbol -> Any
  ;; STATE's call, every transfer's response streamed, on ENGINE (ADR-0031,
  ;; ADR-0032): its requests carry a stream-buffer, and, with PRODUCER, body
  ;; stream. Each transfer's head is waited for, PRODUCER fed meanwhile;
  ;; then the draw, the UTC clock and the monotonic clock are read, and the
  ;; head's body-asked bit, once, the producer counted as called when
  ;; libcurl had asked by the head, or the drive called it; then
  ;; exchange-steps-past? answers whether the call steps past the head:
  ;;   - a hop, a redirect followed or a retry taken: one whose request
  ;;     sends a body, a producer's or a whole one, is cancelled at its
  ;;     head and stepped by exchange-step with those same values, its
  ;;     history entry's body and timings #f; one whose request sends none
  ;;     has its body read whole, up to body-limit, then is stepped the
  ;;     same way, or, failing during that read, stepped with the clocks
  ;;     read at the failure, the head's draw kept. No hop is fed. A wait
  ;;     the step answers is measured from the time it was decided;
  ;;   - the final head: MODE port hands PROC the response, its body and
  ;;     timings #f, and the call's port over the body, and the call
  ;;     answers PROC's values; MODE whole, http-request's with a producer,
  ;;     reads the body whole, up to body-limit, and answers the response
  ;;     with it and the transfer's timings, a failure there stepped with
  ;;     the clocks read at it. The final head is fed whenever libcurl
  ;;     asks.
  ;; A call that ends with a response read before, a retry run out of time,
  ;; hands PROC that response and a port over its body in memory. A retry
  ;; that runs out after its hop was cancelled at its head, whose body was
  ;; never read, at its submission or at the bound's 28 with nothing sent,
  ;; the core fails with &http-timeout instead, as with no time left for any
  ;; request. One critical wind spans the call, as drive-exchange's does:
  ;; its after thunk closes the port, cancels the live token, and lets the
  ;; test seam's record of it go. Once it has run, a producer's failure
  ;; inside the port's read is raised in place of PROC's values. WHO names
  ;; the call in its refusals; with interrupts off it refuses before
  ;; anything is submitted.
  (define (drive-stream engine state draw producer mode proc who)
    (unless (interrupts-on?)
      (refuse-without-interrupts state who))
    (let ((token #f) (port #f) (call (make-stream-call producer who #f #f #f)))
      (define (run state)
        (let ((submission (exchange-submission state (monotonic-ns))))
          (case (car submission)
            ((fail) (raise (cadr submission)))
            ((done) (ended-with (cadr submission)))
            ((submit)
             (when (and (eq? (curl-request-body (caddr submission)) 'stream) (call-called? call))
               ;; The core never asks this: a producer counted as called is
               ;; never sent again (ADR-0032). Checked before the submit, so
               ;; no second transfer of its body is ever made.
               (assertion-violation 'drive-stream "a producer's body was asked for by a second transfer"
                                    (caddr submission)))
             (let* ((state (cadr submission))
                    (request (caddr submission))
                    (refusal (critical-section
                              (guard (e ((curl-error? e) (list 'refused e)))
                                (set! token (curl-submit engine request))
                                (when (vector-ref last-token 0) (vector-set! last-token 1 token))
                                #f))))
               (if refusal
                   (let* ((drawn (draw)) (utc (utc-seconds)) (now (monotonic-ns)))
                     (stepped (section-step state refusal now utc drawn) now))
                   (leg! state request))))
            (else
             (assertion-violation 'drive-stream "the core answered a submission this shell does not know"
                                  submission)))))
      (define (leg! state request)
        (let* ((streams (eq? (curl-request-body request) 'stream))
               (leg (make-leg token call (and streams (curl-request-body-length request))
                              (if streams 'feeding 'none) #f #f 0 #f #f #f)))
          (wait-head! leg state)
          (let* ((head (curl-token-head token))
                 (ended (and (not head) (outcome-of token)))
                 (drawn (draw))
                 (utc (utc-seconds))
                 (now (monotonic-ns))
                 (asked (and head (curl-head-body-asked? head)))
                 (state (if (or asked (call-called? call)) (exchange-mark-called state) state)))
            (if (and ended (eq? (car ended) 'failed))
                (stepped (section-step state ended now utc drawn) now)
                (let ((response
                       (if head
                           (head-response (curl-head-status head) (curl-head-http-version head)
                                          (curl-head-headers head))
                           (let ((r (cadr ended)))
                             (head-response (curl-response-status r) (curl-response-http-version r)
                                            (curl-response-headers r))))))
                  (if (section-steps-past? state response now utc drawn)
                      (hop! leg state request response now utc drawn)
                      (final! leg state response now utc drawn)))))))
      (define (hop! leg state request response now utc drawn)
        (if (curl-request-body request)
            (begin
              (end-hop! token)
              (stepped (section-step state (list 'response response) now utc drawn) now))
            (let ((read (read-whole! leg state)))
              (if (eq? (car read) 'response)
                  (stepped (section-step state
                                         (list 'response
                                               (http-response-with response (caddr read)
                                                                   (curl-response-timings (cadr read))))
                                         now utc drawn)
                           now)
                  (let* ((utc (utc-seconds)) (now (monotonic-ns)))
                    (stepped (section-step state read now utc drawn) now))))))
      (define (final! leg state response now utc drawn)
        (let ((step (section-step state (list 'response response) now utc drawn)))
          (case (car step)
            ((fail) (raise (cadr step)))
            ((done)
             (leg-final-set! leg #t)
             (end-at-length! leg 0 #f state)
             (let ((r (cadr step)))
               (if (eq? mode 'port)
                   (let ((p (call-port leg state)))
                     (set! port p)
                     (proc r p))
                   (let ((read (read-whole! leg state)))
                     (if (eq? (car read) 'response)
                         (http-response-with r (caddr read) (curl-response-timings (cadr read)))
                         ;; The final head is fed, so the producer may have
                         ;; been called first during the read: marked again,
                         ;; no retry takes it (ADR-0032).
                         (let* ((utc (utc-seconds)) (now (monotonic-ns))
                                (state (if (call-called? call) (exchange-mark-called state) state)))
                           (stepped (section-step state read now utc drawn) now)))))))
            (else
             (assertion-violation 'drive-stream "the head's predicate and exchange-step disagree" step)))))
      (define (ended-with r)
        (if (eq? mode 'port)
            (let ((p (open-bytevector-input-port (http-response-body r))))
              (set! port p)
              (proc r p))
            r))
      (define (stepped step at)
        (case (car step)
          ((done) (ended-with (cadr step)))
          ((fail) (raise (cadr step)))
          ((next)
           (let ((wait (cadddr step)))
             (unless (and (integer? wait) (exact? wait) (>= wait 0))
               (assertion-violation 'drive-stream "the core answered a next whose wait is no natural" step))
             (let ((left (- (+ at (* wait 1000000)) (monotonic-ns))))
               (when (> left 0) (pause (div (+ left 999999) 1000000))))
             (run (cadr step))))
          (else
           (assertion-violation 'drive-stream "the core answered a step this shell does not know" step))))
      (call-with-values
        (lambda ()
          (dynamic-wind #t
            (lambda () #f)
            (lambda () (run state))
            (lambda ()
              (when port (close-port port))
              (when (and token (not (curl-token-done? token)))
                (curl-token-cancel token))
              (when (and token (eq? (vector-ref last-token 1) token))
                (vector-set! last-token 1 #f)))))
        (lambda answers
          (let ((stuck (call-stuck call)))
            (if stuck (raise stuck) (apply values answers)))))))

  ;; --- the request group ---------------------------------------------------------------

  ;; require-interrupts : Symbol -> Void
  ;; Returns when this thread runs with interrupts on, as interrupts-on?
  ;; judges it; otherwise an assertion violation from WHO, before anything
  ;; else is done: a group's turns wait, and inside a critical section a
  ;; wait would hold every collection.
  (define (require-interrupts who)
    (unless (interrupts-on?)
      (assertion-violation who
        "a group's waits need interrupts on: inside a critical section a wait would hold every collection, so nothing was done")))

  ;; A group: its session's engine, the draw its steps take, the submit its
  ;; calls are submitted by, curl-submit but for a test's, its mailbox, the
  ;; thread that made it, and its limit, a positive integer or #f;
  ;; whether it is closed; the slots its calls hold; its queue, oldest
  ;; first; its waiting calls; its live set, each token to (SEQ . PENDING),
  ;; SEQ the order of its submit, and the next SEQ; its draining tokens; its
  ;; failed calls, newest first; and how many of its calls are unended.
  (define-record-type (group make-group group?)
    (fields (immutable engine group-engine)
            (immutable draw group-draw)
            (immutable submit group-submit)
            (immutable mailbox group-mailbox)
            (immutable thread group-thread)
            (immutable limit group-limit)
            (mutable closed group-closed? group-closed-set!)
            (mutable used group-used group-used-set!)
            (mutable queue group-queue group-queue-set!)
            (mutable waiting group-waiting group-waiting-set!)
            (immutable live group-live)
            (mutable seq group-seq group-seq-set!)
            (mutable draining group-draining group-draining-set!)
            (mutable failed group-failed group-failed-set!)
            (mutable unended group-unended group-unended-set!))
    (sealed #t)
    (opaque #t))

  ;; new-group : Engine (-> Real) (U Positive-Integer #f) (Engine Request Mailbox -> Token) -> Group
  ;; A group of this thread's, open, with a fresh mailbox and no calls.
  (define (new-group engine draw limit submit)
    (make-group engine draw submit (make-curl-mailbox) (get-thread-id) limit #f 0 '() '()
                (make-eq-hashtable) 0 '() '() 0))

  ;; A pending, one call of a group: its group; its exchange's state; its
  ;; phase, queued, live, waiting or ended; its live token, or #f; its due
  ;; time, a monotonic time in ns: a waiting call's end of wait, or a
  ;; queued call's deadline, #f with no bound; whether it holds a slot; its
  ;; answer once ended, (done RESPONSE), (fail CONDITION) or (cancelled);
  ;; the token that was live when it was cancelled, or #f; the condition
  ;; its await raises for a cancel, once made; whether an await has
  ;; answered it; and whether its caller cancelled it once it had failed,
  ;; which exempts its failure from the join's raise.
  ;; http-pending? : Any -> Boolean
  (define-record-type (http-pending make-pending http-pending?)
    (fields (immutable group pending-group)
            (mutable state pending-state pending-state-set!)
            (mutable phase pending-phase pending-phase-set!)
            (mutable token pending-token pending-token-set!)
            (mutable due pending-due pending-due-set!)
            (mutable slot pending-slot? pending-slot-set!)
            (mutable answer pending-answer pending-answer-set!)
            (mutable cancelled-token pending-cancelled-token pending-cancelled-token-set!)
            (mutable raised pending-raised pending-raised-set!)
            (mutable awaited pending-awaited? pending-awaited-set!)
            (mutable exempt pending-exempt? pending-exempt-set!))
    (sealed #t)
    (opaque #t))

  ;; group-refusal : Symbol Symbol String (Listof Any) -> Condition
  ;; &http-group-error REASON, as WHO, with MESSAGE and IRRITANTS.
  (define (group-refusal reason who message irritants)
    (condition (make-http-group-error reason)
               (make-who-condition who)
               (make-message-condition message)
               (make-irritants-condition irritants)))

  ;; check-pending : Symbol Any -> Void
  (define (check-pending who x)
    (unless (http-pending? x)
      (assertion-violation who "not a pending call, which go answers" (shown-value x))))

  ;; check-thread : Symbol Group -> Void
  ;; Returns on GROUP's own thread; on any other, raises &http-group-error,
  ;; wrong-thread, as WHO, its irritants the group's thread and this one.
  (define (check-thread who group)
    (let ((here (get-thread-id)))
      (unless (eqv? here (group-thread group))
        (raise (group-refusal 'wrong-thread who
                              "a request group is its thread's: this is another thread"
                              (list (group-thread group) here))))))

  ;; --- the record's changes, each made inside a critical section --------------------

  ;; end! : Group Pending (U (List 'done Response) (List 'fail Condition) (List 'cancelled)) -> Void
  ;; PENDING ended with ANSWER: its slot freed, if it held one, and a
  ;; failure numbered, by its place in GROUP's failures.
  (define (end! group pending answer)
    (when (eq? (pending-phase pending) 'ended)
      (assertion-violation 'drive-group "a call ended twice" answer))
    (pending-answer-set! pending answer)
    (pending-phase-set! pending 'ended)
    (pending-token-set! pending #f)
    (pending-due-set! pending #f)
    (when (pending-slot? pending)
      (pending-slot-set! pending #f)
      (group-used-set! group (- (group-used group) 1)))
    (group-unended-set! group (- (group-unended group) 1))
    (when (eq? (car answer) 'fail)
      (group-failed-set! group (cons pending (group-failed group)))))

  ;; record! : Group Pending Token -> Void
  ;; TOKEN, just submitted for PENDING, in the live set: PENDING is live.
  (define (record! group pending token)
    (hashtable-set! (group-live group) token (cons (group-seq group) pending))
    (group-seq-set! group (+ (group-seq group) 1))
    (pending-token-set! pending token)
    (pending-phase-set! pending 'live))

  ;; submit! : Group Pending -> Void
  ;; PENDING's step request, through exchange-submission at the monotonic
  ;; time now: a fail or a done, no time left, ends it; a submit is made on
  ;; the group's engine, to its mailbox, and its token recorded, the guard
  ;; that reads the submit's own &curl-error inside the caller's critical
  ;; section, so a Ctrl-C handler's raise as that section ends is no
  ;; refusal. A refusal is the core's (refused C), stepped, for this call
  ;; alone.
  (define (submit! group pending)
    (let ((submission (exchange-submission (pending-state pending) (monotonic-ns))))
      (case (car submission)
        ((fail) (end! group pending (list 'fail (cadr submission))))
        ((done) (end! group pending (list 'done (cadr submission))))
        ((submit)
         (pending-state-set! pending (cadr submission))
         (let ((refusal (guard (e ((curl-error? e) (list 'refused e)))
                          (record! group pending
                                   ((group-submit group) (group-engine group) (caddr submission)
                                                         (group-mailbox group)))
                          #f)))
           (when refusal (step! group pending refusal))))
        (else
         (assertion-violation 'drive-group "the core answered a submission this shell does not know"
                              submission)))))

  ;; step! : Group Pending Outcome -> Void
  ;; PENDING stepped with OUTCOME, as drive-exchange steps a call: the draw,
  ;; then the UTC clock, then the monotonic one, then exchange-step. done
  ;; and fail end it; a next with a wait of 0 submits at once, and one above
  ;; 0 waits until that many ms past the step's monotonic time, keeping its
  ;; slot. An answer the shell does not know is an assertion violation.
  (define (step! group pending outcome)
    (let* ((drawn ((group-draw group)))
           (utc (utc-seconds))
           (now (monotonic-ns))
           (step (begin
                   (run-step-gate! 'start)
                   (let ((s (exchange-step (pending-state pending) outcome now utc drawn)))
                     (run-step-gate! 'end)
                     s))))
      (case (car step)
        ((done) (end! group pending (list 'done (cadr step))))
        ((fail) (end! group pending (list 'fail (cadr step))))
        ((next)
         (let ((wait (cadddr step)))
           (unless (and (integer? wait) (exact? wait) (>= wait 0))
             (assertion-violation 'drive-group "the core answered a next whose wait is no natural"
                                  step))
           (pending-state-set! pending (cadr step))
           (if (= wait 0)
               (submit! group pending)
               (begin
                 (pending-phase-set! pending 'waiting)
                 (pending-due-set! pending (+ now (* wait 1000000)))
                 (group-waiting-set! group (cons pending (group-waiting group)))))))
        (else
         (assertion-violation 'drive-group "the core answered a step this shell does not know"
                              step)))))

  ;; step-token! : Group Token -> Void
  ;; TOKEN stepped, when it is in GROUP's live set: taken out, then its
  ;; call stepped with its outcome, read as data. A token outside the set
  ;; is left: its notice is dropped. TOKEN is done.
  (define (step-token! group token)
    (let ((entry (hashtable-ref (group-live group) token #f)))
      (when entry
        (let ((pending (cdr entry)))
          (hashtable-delete! (group-live group) token)
          (pending-token-set! pending #f)
          (guarded! group pending
            (lambda ()
              (let ((outcome (curl-token-outcome token)))
                (unless outcome
                  (assertion-violation 'drive-group "a token stepped before it was done" token))
                (step! group pending (if (curl-response? outcome)
                                         (list 'response outcome)
                                         (list 'failed outcome))))))))))

  ;; with-exchange : Any State -> Any
  ;; X as a call's failure: compounded with STATE's &http-exchange when X is
  ;; a condition that has none, else X as it was raised.
  (define (with-exchange x state)
    (if (and (condition? x) (not (http-exchange? x)))
        (condition x (exchange-condition state))
        x))

  ;; strand! : Group Pending Any -> Void
  ;; PENDING ended as a failure with X, something its own step or submit
  ;; raised inside its critical section: the core's, a URL function's, the
  ;; draw's, or a raise of curl-submit's that is no &curl-error. It is taken
  ;; out of every set that holds it, and a token of its still live is
  ;; cancelled and kept draining, so no call is left in no set, unended,
  ;; holding its slot, where the join and every await would wait for good.
  ;; On a call that has ended already, X is raised again: it is no call's
  ;; failure, and end!'s check of a call ended twice among such raises must
  ;; not be dropped.
  (define (strand! group pending x)
    (when (ended? pending)
      (raise x))
    (let ((token (pending-token pending)))
      (when (and token (hashtable-contains? (group-live group) token))
        (hashtable-delete! (group-live group) token)
        (curl-token-cancel token)
        (group-draining-set! group (cons token (group-draining group)))))
    (group-waiting-set! group (remq pending (group-waiting group)))
    (group-queue-set! group (remq pending (group-queue group)))
    (end! group pending (list 'fail (with-exchange x (pending-state pending)))))

  ;; guarded! : Group Pending (-> Any) -> Void
  ;; THUNK, PENDING's step or submit, with any raise from it made
  ;; PENDING's failure, by strand!. Its caller runs it inside the call's
  ;; critical section, where no interrupt handler runs, so the guard reads
  ;; only the code's own raises: a handler's raise comes as the section
  ;; ends, outside the guard, and leaves as raised.
  (define (guarded! group pending thunk)
    (guard (x (#t (strand! group pending x)))
      (thunk)))

  ;; expire! : Group Pending -> Void
  ;; PENDING, queued past its deadline, through exchange-submission, which
  ;; answers its &http-timeout: ended, with no slot taken.
  (define (expire! group pending)
    (let ((submission (exchange-submission (pending-state pending) (monotonic-ns))))
      (case (car submission)
        ((fail) (end! group pending (list 'fail (cadr submission))))
        ((done) (end! group pending (list 'done (cadr submission))))
        (else
         (assertion-violation 'drive-group "the core answered a submission past the call's deadline"
                              submission)))))

  ;; admit! : Group -> Void
  ;; Queued calls let in, first in, first out, while GROUP has a slot free:
  ;; each takes one, and is submitted, each admission a critical section of
  ;; its own, by admit-one!. Its caller is in no critical section of the
  ;; group's: go and run-parallel call it after an entry's section, and a
  ;; turn between its other sections.
  (define (admit! group)
    (let loop ()
      (when (critical-section (admit-one! group))
        (loop))))

  ;; admit-one! : Group -> Boolean
  ;; The queue's first call let in, when GROUP has a slot free: it takes
  ;; one, and is submitted, guarded; #t when one was let in. Its caller,
  ;; admit!, makes each admission a critical section of its own, so no
  ;; section copies more than one call's body while collections wait.
  (define (admit-one! group)
    (let ((queue (group-queue group))
          (limit (group-limit group)))
      (and (pair? queue)
           (or (not limit) (< (group-used group) limit))
           (let ((pending (car queue)))
             (group-queue-set! group (cdr queue))
             (pending-slot-set! pending #t)
             (group-used-set! group (+ (group-used group) 1))
             (pending-due-set! pending #f)
             (guarded! group pending (lambda () (submit! group pending)))
             #t))))

  ;; cancel! : Group Pending -> Void
  ;; PENDING, unended, ended as cancelled: a queued or waiting one is taken
  ;; out; a live one's token is taken out of the set, cancelled, which
  ;; never waits but for the engine's mutex, and kept among the draining
  ;; tokens. An ended call is no case of it: http-pending-cancel handles
  ;; one itself, and cancel-all! hands it unended calls alone, so one here
  ;; is an assertion violation.
  (define (cancel! group pending)
    (case (pending-phase pending)
      ((queued)
       (group-queue-set! group (remq pending (group-queue group)))
       (end! group pending (list 'cancelled)))
      ((waiting)
       (group-waiting-set! group (remq pending (group-waiting group)))
       (end! group pending (list 'cancelled)))
      ((live)
       (let ((token (pending-token pending)))
         (hashtable-delete! (group-live group) token)
         (curl-token-cancel token)
         (group-draining-set! group (cons token (group-draining group)))
         (pending-cancelled-token-set! pending token)
         (end! group pending (list 'cancelled))))
      (else
       (assertion-violation 'drive-group "cancel! of an ended call" pending))))

  ;; live-snapshot : Group -> (Listof Token)
  ;; GROUP's live tokens now, oldest submit first.
  (define (live-snapshot group)
    (let-values (((tokens entries) (hashtable-entries (group-live group))))
      (let loop ((i 0) (pairs '()))
        (if (= i (vector-length tokens))
            (map cdr (list-sort (lambda (a b) (< (car a) (car b))) pairs))
            (loop (+ i 1)
                  (cons (cons (car (vector-ref entries i)) (vector-ref tokens i)) pairs))))))

  ;; cancel-all! : Group -> Void
  ;; The inner wind's after thunk, with interrupts off: GROUP closed, and
  ;; every unended call ended as cancelled, live ones' tokens cancelled
  ;; and draining. It never waits.
  (define (cancel-all! group)
    (group-closed-set! group #t)
    (for-each (lambda (token)
                (let ((entry (hashtable-ref (group-live group) token #f)))
                  (when entry (cancel! group (cdr entry)))))
              (live-snapshot group))
    (for-each (lambda (pending) (cancel! group pending)) (group-queue group))
    (for-each (lambda (pending) (cancel! group pending)) (group-waiting group)))

  ;; prune! : Group -> Void
  ;; GROUP's draining tokens, those not yet ended alone.
  (define (prune! group)
    (group-draining-set! group
                         (filter (lambda (token) (not (curl-token-done? token)))
                                 (group-draining group))))

  ;; drain-all! : Group -> Void
  ;; The outer wind's after thunk, with interrupts on: a wait for every
  ;; live and draining token of GROUP to end, by curl-token-wait in a loop,
  ;; a second at a time, unguarded, so an interrupt handler's raise leaves
  ;; as raised, and abandons the wait.
  (define (drain-all! group)
    (for-each (lambda (token)
                (let wait ()
                  (unless (curl-token-wait token 1000) (wait))))
              (append (live-snapshot group) (group-draining group)))
    (critical-section (prune! group)))

  ;; --- the turn ------------------------------------------------------------------------

  ;; by-due : (Listof Pending) -> (Listof Pending)
  (define (by-due pendings)
    (list-sort (lambda (a b) (< (pending-due a) (pending-due b))) pendings))

  ;; take-bound : Group -> Natural
  ;; The ms until GROUP's next due time, a waiting call's or a queued
  ;; call's deadline, rounded up, at most 100, at least 0; 100 with none.
  (define (take-bound group)
    (let* ((now (monotonic-ns))
           (dues (filter (lambda (due) due)
                         (map pending-due (append (group-waiting group) (group-queue group))))))
      (if (null? dues)
          100
          (max 0 (min 100 (div (+ (- (apply min dues) now) 999999) 1000000))))))

  ;; turn! : Group Boolean (-> Boolean) -> Void
  ;; One turn of GROUP's loop (the header): the done tokens stepped, the
  ;; draining tokens pruned, the due waits submitted, the queued calls past
  ;; their deadline failed, the queue let in, then one take, bounded by
  ;; take-bound when WAIT? and STOP? answers #f just before it, else by 0.
  ;; Each change is a critical section of its own; the take is none, and
  ;; nothing guards it.
  (define (turn! group wait? stop?)
    (for-each (lambda (token)
                (critical-section
                 (when (and (hashtable-contains? (group-live group) token) (curl-token-done? token))
                   (step-token! group token))))
              (live-snapshot group))
    (critical-section (prune! group))
    (for-each (lambda (pending)
                (critical-section
                 (when (and (eq? (pending-phase pending) 'waiting)
                            (<= (pending-due pending) (monotonic-ns)))
                   (group-waiting-set! group (remq pending (group-waiting group)))
                   (guarded! group pending (lambda () (submit! group pending))))))
              (by-due (group-waiting group)))
    (for-each (lambda (pending)
                (critical-section
                 (when (and (eq? (pending-phase pending) 'queued) (pending-due pending)
                            (<= (pending-due pending) (monotonic-ns)))
                   (group-queue-set! group (remq pending (group-queue group)))
                   (guarded! group pending (lambda () (expire! group pending))))))
              (group-queue group))
    (admit! group)
    (let ((token (curl-mailbox-take (group-mailbox group)
                                    (if (and wait? (not (stop?))) (take-bound group) 0))))
      (when token
        (critical-section (step-token! group token)))))

  ;; settled? : Group -> Boolean
  ;; Whether every call of GROUP has ended, and no token is live or
  ;; draining.
  (define (settled? group)
    (and (= (group-unended group) 0)
         (= (hashtable-size (group-live group)) 0)
         (null? (group-draining group))))

  ;; ended? : Pending -> Boolean
  (define (ended? pending) (eq? (pending-phase pending) 'ended))

  ;; first-failure : Group -> (U Pending #f)
  ;; GROUP's first call to fail, the first the group saw fail, ties found
  ;; in one look in the order of their latest submits, that no await has
  ;; answered and its caller has not cancelled, or #f.
  (define (first-failure group)
    (find (lambda (pending) (not (or (pending-awaited? pending) (pending-exempt? pending))))
          (reverse (group-failed group))))

  ;; with-group : Group (-> Any) -> Any
  ;; THUNK's values, inside the two winds (the header): the inner, Chez's
  ;; critical one, whose after thunk cancels; the outer, a plain one, whose
  ;; after thunk waits.
  (define (with-group group thunk)
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (dynamic-wind #t
          (lambda () #f)
          thunk
          (lambda () (cancel-all! group))))
      (lambda () (drain-all! group))))

  ;; call-with-group : Engine (U Positive-Integer #f) (-> Real)
  ;;                   (Any Any List -> State) ((Any Any Any ... -> Pending) -> Any)
  ;;                   [(Engine Request Mailbox -> Token)] -> Any
  ;; PROC's values, called with go, on a group of this thread's on ENGINE,
  ;; with LIMIT, its steps drawing from DRAW, once every call has ended
  ;; and no token is live or draining; or the first failure no await
  ;; answered, raised. (go METHOD URL KEY VALUE ...): wrong-thread from
  ;; another thread, then closed once PROC has returned or escaped, then
  ;; PREPARE's state for the call, whose refusal raises from go, with no
  ;; call made; then the call, queued last and let in at once when a slot
  ;; is free, which go answers, its pending: from its first submit on,
  ;; what becomes of it is its own answer, never raised by go. go waits for
  ;; no transfer, only for the brief holds of mutexes its sections make (the
  ;; header), and copies the call's body. It asks whether the group is
  ;; closed again inside its entry's section, after PREPARE, which an
  ;; engine's expiry or an interrupt handler can close it during, and
  ;; raises closed once that section has ended, with interrupts on. Its
  ;; calls are submitted by SUBMIT, curl-submit when none is given: a test
  ;; seam, so a test can plant a raise in one submit. The caller has refused
  ;; a critical section first.
  (define call-with-group
    (case-lambda
      ((engine limit draw prepare proc)
       (run-group engine limit draw prepare proc curl-submit))
      ((engine limit draw prepare proc submit)
       (run-group engine limit draw prepare proc submit))))

  ;; run-group : Engine (U Positive-Integer #f) (-> Real) (Any Any List -> State)
  ;;             ((Any Any Any ... -> Pending) -> Any) (Engine Request Mailbox -> Token) -> Any
  ;; call-with-group's, its calls submitted by SUBMIT.
  (define (run-group engine limit draw prepare proc submit)
    (let ((group (new-group engine draw limit submit)))
      (define (go method url . plist)
        (check-thread 'go group)
        (when (group-closed? group)
          (raise (group-refusal 'closed 'go
                                "the request group's procedure has returned or escaped: go starts no call"
                                (list method url))))
        (let* ((state (prepare method url plist))
               (pending
                (critical-section
                 (and (not (group-closed? group))
                      (let ((pending (make-pending group state 'queued #f (exchange-deadline state)
                                                   #f #f #f #f #f #f)))
                        (group-unended-set! group (+ (group-unended group) 1))
                        (group-queue-set! group (append (group-queue group) (list pending)))
                        pending)))))
          (unless pending
            (raise (group-refusal 'closed 'go
                                  "the request group was closed while go checked the call: go starts no call"
                                  (list method url))))
          (admit! group)
          pending))
      (with-group group
        (lambda ()
          (call-with-values
            (lambda () (proc go))
            (lambda answers
              (group-closed-set! group #t)
              (let join ()
                (unless (settled? group)
                  (turn! group #t (lambda () (settled? group)))
                  (join)))
              (let ((failed (first-failure group)))
                (if failed
                    (raise (cadr (pending-answer failed)))
                    (apply values answers)))))))))

  ;; run-parallel : Engine (U Positive-Integer #f) (-> Real) (Listof State)
  ;;                [(Engine Request Mailbox -> Token)] -> (Listof Response)
  ;; http-parallel's run: STATES' calls, checked already, entered in one
  ;; group of LIMIT in their order, each entered in a critical section of
  ;; its own, then let in by admit!, each admission a section of its own,
  ;; so no section copies more than one call's body while collections wait
  ;; (101 to 108 ms of held collections for 32 posts of 4 MB in one); then
  ;; turns until all have ended or one has failed. Each entry's section asks
  ;; first whether the group is closed: an escape, a Chez engine's expiry
  ;; among them, closes and cancels it through its winds, and a resumed run
  ;; must enter no more, so a call not yet entered is never submitted. On
  ;; the first failure, the first the group saw fail, ties in the order of
  ;; their latest submits, every other call is cancelled, as the inner wind
  ;; does, every token waited for, as the outer wind does, and that failure
  ;; raised as the call raised it. The responses are answered only when
  ;; every call was entered and its answer is done; otherwise, with no
  ;; failure, the first call in STATES' order that is not done raises its
  ;; cancel: an entered one's await's condition, and one never entered a
  ;; cancel of its own, with its &http-exchange. Its calls are submitted by
  ;; SUBMIT, curl-submit when none is given: a test seam.
  (define run-parallel
    (case-lambda
      ((engine limit draw states) (run-parallel engine limit draw states curl-submit))
      ((engine limit draw states submit)
       (let ((group (new-group engine draw limit submit)))
         (with-group group
           (lambda ()
             (let ((pendings
                    (let loop ((rest states) (made '()))
                      (if (null? rest)
                          (reverse made)
                          (let ((pending
                                 (critical-section
                                  (and (not (group-closed? group))
                                       (let ((pending (make-pending group (car rest) 'queued #f
                                                                    (exchange-deadline (car rest))
                                                                    #f #f #f #f #f #f)))
                                         (group-unended-set! group (+ (group-unended group) 1))
                                         (group-queue-set! group (append (group-queue group) (list pending)))
                                         pending)))))
                            (if pending
                                (begin
                                  (admit! group)
                                  (loop (cdr rest) (cons pending made)))
                                (reverse made)))))))
               (let ((over? (lambda ()
                              (or (= (group-unended group) 0) (pair? (group-failed group))))))
                 (let run ()
                   (unless (over?)
                     (turn! group #t over?)
                     (run))))
               (let ((failed (group-failed group)))
                 (cond
                  ((pair? failed)
                   (let ((first (car (reverse failed))))
                     (critical-section (cancel-all! group))
                     (drain-all! group)
                     (raise (cadr (pending-answer first)))))
                  ((and (= (length pendings) (length states))
                        (for-all (lambda (p) (eq? (car (pending-answer p)) 'done)) pendings))
                   (let loop ((rest pendings) (responses '()))
                     (if (null? rest)
                         (reverse responses)
                         (loop (cdr rest) (cons (cadr (pending-answer (car rest))) responses)))))
                  (else
                   (critical-section (cancel-all! group))
                   (drain-all! group)
                   (raise (unfinished-condition pendings states))))))))))))

  ;; unfinished-condition : (Listof Pending) (Listof State) -> Condition
  ;; What run-parallel raises when no call failed but not every one is
  ;; done: the first of STATES, in order, whose call is not done. One that
  ;; was entered, PENDINGS' in the same order, ended as cancelled, whose
  ;; await's condition it is; one never entered, its own cancel, with its
  ;; state's &http-exchange.
  (define (unfinished-condition pendings states)
    (let loop ((ps pendings) (ss states))
      (cond
       ((null? ss)
        (assertion-violation 'drive-group "http-parallel found every call done, and answered none" states))
       ((null? ps)
        (condition (make-http-group-error 'cancelled)
                   (make-who-condition 'http-parallel)
                   (make-message-condition
                    "the call was never submitted: its group was ended by an escape before it was entered")
                   (exchange-condition (car ss))))
       ((eq? (car (pending-answer (car ps))) 'done) (loop (cdr ps) (cdr ss)))
       (else (cancelled-condition (car ps))))))

  ;; --- the pending's operations ---------------------------------------------------------

  ;; cancelled-condition : Pending -> Condition
  ;; What the await of PENDING, cancelled, raises, made once: &http-group-
  ;; error, cancelled, compounded with its token's outcome when that is a
  ;; condition, and with its &http-exchange.
  (define (cancelled-condition pending)
    (or (pending-raised pending)
        (let* ((token (pending-cancelled-token pending))
               (outcome (and token (curl-token-outcome token)))
               (made (apply condition
                            (make-http-group-error 'cancelled)
                            (make-who-condition 'http-await)
                            (make-message-condition
                             "the call was cancelled, by http-pending-cancel or by its group's escape")
                            (append (if (and outcome (condition? outcome)) (list outcome) '())
                                    (list (exchange-condition (pending-state pending)))))))
          (pending-raised-set! pending made)
          made)))

  ;; http-await : Pending -> Response
  ;; PENDING's response, or a raise of its condition, once it has ended:
  ;; turns of its group, with waits, until then; and, for a call cancelled
  ;; while its token was live, until that token has ended too. It answers
  ;; the same any number of times, after its group has returned too, and its
  ;; first answer marks the call awaited, so the join does not raise its
  ;; failure. wrong-thread from another thread first, then the refusal
  ;; inside a critical section.
  (define (http-await pending)
    (check-pending 'http-await pending)
    (let ((group (pending-group pending)))
      (check-thread 'http-await group)
      (require-interrupts 'http-await)
      (let loop ()
        (unless (ended? pending)
          (turn! group #t (lambda () (ended? pending)))
          (loop)))
      (let ((token (pending-cancelled-token pending)))
        (when token
          (let loop ()
            (unless (curl-token-done? token)
              (turn! group #t (lambda () (curl-token-done? token)))
              (loop)))))
      (pending-awaited-set! pending #t)
      (let ((answer (pending-answer pending)))
        (case (car answer)
          ((done) (cadr answer))
          ((fail) (raise (cadr answer)))
          (else (raise (cancelled-condition pending)))))))

  ;; http-pending-done? : Pending -> Boolean
  ;; One turn of PENDING's group, with no wait, then whether PENDING has
  ;; ended. wrong-thread from another thread first, then the refusal inside
  ;; a critical section.
  (define (http-pending-done? pending)
    (check-pending 'http-pending-done? pending)
    (let ((group (pending-group pending)))
      (check-thread 'http-pending-done? group)
      (require-interrupts 'http-pending-done?)
      (turn! group #f (lambda () #t))
      (ended? pending)))

  ;; http-pending-cancel : Pending -> Void
  ;; PENDING ended as cancelled, in one critical section, unless it has
  ;; ended already: cancel!. A call that has ended as a failure keeps its
  ;; answer, which its await raises, and is exempt from the join's raise:
  ;; the caller cancelled it, whether or not a turn had seen it fail
  ;; first. It waits for no transfer: a live token's cancel is a message,
  ;; under the engine's mutex; a token still queued in the engine, not yet
  ;; taken in by its thread, is completed here, under the engine's mutex,
  ;; into the group's mailbox, under the mailbox's nested inside it; and a
  ;; call waiting for a slot, or in a retry's wait, has no token, and its
  ;; cancel holds no mutex. wrong-thread from another thread first.
  (define (http-pending-cancel pending)
    (check-pending 'http-pending-cancel pending)
    (let ((group (pending-group pending)))
      (check-thread 'http-pending-cancel group)
      (critical-section
       (if (ended? pending)
           (when (eq? (car (pending-answer pending)) 'fail)
             (pending-exempt-set! pending #t))
           (cancel! group pending)))
      (if #f #f)))

  ;; --- the seams, for the tests alone -----------------------------------------------------

  ;; http-pending-mailbox : Pending -> Mailbox
  ;; PENDING's group's mailbox, every token it submits goes to.
  (define (http-pending-mailbox pending)
    (check-pending 'http-pending-mailbox pending)
    (group-mailbox (pending-group pending)))

  ;; http-pending-token : Pending -> (U Token #f)
  ;; PENDING's live token, or #f.
  (define (http-pending-token pending)
    (check-pending 'http-pending-token pending)
    (pending-token pending))

  ;; http-pending-phase : Pending -> (U 'queued 'live 'waiting 'ended)
  (define (http-pending-phase pending)
    (check-pending 'http-pending-phase pending)
    (pending-phase pending))

  ;; http-pending-census : Pending -> (Listof (Pairof Symbol Natural))
  ;; PENDING's group's counts now: unended calls, queued, waiting, live
  ;; tokens, draining tokens, slots held, and failures.
  (define (http-pending-census pending)
    (check-pending 'http-pending-census pending)
    (let ((group (pending-group pending)))
      (list (cons 'unended (group-unended group))
            (cons 'queued (length (group-queue group)))
            (cons 'waiting (length (group-waiting group)))
            (cons 'live (hashtable-size (group-live group)))
            (cons 'draining (length (group-draining group)))
            (cons 'slots (group-used group))
            (cons 'failed (length (group-failed group)))))))
