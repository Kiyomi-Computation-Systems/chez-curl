#!r6rs
;;; (http-client private drive): the shell for one call, on its caller's
;;; thread (the M5 plan, sections 3.5 and 3.6). It reads the clocks, draws,
;;; submits, awaits, and hands each outcome to the core, (http-client
;;; private exchange), which answers what comes next: a next, a redirect's
;;; or a retry's, whose request goes through the core's submission, with
;;; the time left, as the first did, once its wait has passed: at once for
;;; a wait of 0.
;;;
;;; A wait above 0 is a take from an empty private mailbox, bounded by the
;;; wait: curl-mailbox-take polls, sleeping up to 10 ms between its looks,
;;; with interrupts on, so Ctrl-C and a timer reach it, and refuses to start
;;; inside a critical section, as every wait of (curl)'s does (ADR-0013,
;;; amended 2026-10-25). Each step draws one number from the session's
;;; generator, through DRAW, whether a retry reads it or not.
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
;;; the first transfer ran on, a post's among them (the slice's first
;;; review); one that re-awaited the done token to tell them apart lost a
;;; raise landing there, and leaked the token's own condition raw (the
;;; second review).
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
;;; it ends, once the token is recorded (traps.md). Each submit of a call,
;;; a redirect's as the first, shares its section with its record. A
;;; submit never waits
;;; but for the engine's mutex; it does copy the request's body inside the
;;; section, as its private copy: about 50 ms for 64 MB, and 207 to 227 ms
;;; for 256 MB (.plans/research/m5/submit-time/), which Ctrl-C then waits
;;; out.
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
(library (http-client private drive)
  (export drive-exchange monotonic-ns utc-seconds take-refusal?)
  (import (curl)
          (except (rnrs) dynamic-wind)
          (only (chezscheme) critical-section current-time dynamic-wind time-second
                time-nanosecond)
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

  ;; refuse-without-interrupts : State -> Nothing
  ;; The call's refusal inside a critical section: an assertion violation
  ;; from http-request, compounded with STATE's &http-exchange.
  (define (refuse-without-interrupts state)
    (raise (condition (make-assertion-violation)
                      (make-who-condition 'http-request)
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
                        (step (exchange-step state outcome (monotonic-ns) utc drawn)))
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
            (curl-token-cancel token)))))))
