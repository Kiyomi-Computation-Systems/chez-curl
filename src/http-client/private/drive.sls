#!r6rs
;;; (http-client private drive): the shell for one call, on its caller's
;;; thread (the M5 plan, section 3.6). It reads the clocks, submits, awaits,
;;; and hands each outcome to the core, (http-client private exchange),
;;; which answers what comes next: a redirect is a next with a wait of 0,
;;; whose request goes through the core's submission at once, with the time
;;; left, as the first did. A next with a wait above 0 is a retry's, slice
;;; 3's, and this shell refuses it.
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
;;; the submit raises is the core's (refused C), and one the await raises
;;; its (failed C), and everything (curl) raises there is a &curl-error.
;;; Any other raise is the caller's own, an interrupt handler's or a
;;; timer's landing in the await, and leaves unchanged: the guard matches no
;;; clause, so it re-raises it, continuably, where it was raised, and a
;;; handler that returns from a continuable raise resumes the call. A raise
;;; that leaves the call does so after the after thunk has cancelled.
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

  ;; drive-exchange : Engine State -> Response
  ;; STATE's call, driven on ENGINE until the core answers done, whose
  ;; response it answers, or fail, whose condition it raises; a next with a
  ;; wait of 0, a redirect, is submitted at once, from its state. Each step
  ;; reads the monotonic clock and the UTC clock, with a draw of 0.0: no
  ;; retry draws before slice 3. With interrupts off it refuses, before
  ;; the first submit.
  (define (drive-exchange engine state)
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
                (else
                 (let* ((state (cadr submission))
                        (request (caddr submission))
                        (refusal (guard (e ((curl-error? e) (list 'refused e)))
                                   (critical-section
                                    (set! token (curl-submit engine request)))
                                   #f))
                        (outcome (or refusal
                                     (guard (e ((curl-error? e) (list 'failed e)))
                                       (list 'response (curl-token-await token)))))
                        (step (exchange-step state outcome (monotonic-ns) (utc-seconds) 0.0)))
                   (case (car step)
                     ((done) (cadr step))
                     ((fail) (raise (cadr step)))
                     ((next)
                      (if (eqv? (cadddr step) 0)
                          (loop (cadr step))
                          (assertion-violation 'drive-exchange
                                               "the core answered a next with a wait, a retry's, which this shell does not take before retries"
                                               step)))
                     (else
                      (assertion-violation 'drive-exchange
                                           "the core answered a step this shell does not know"
                                           step)))))))))
        (lambda ()
          (when (and token (not (curl-token-done? token)))
            (curl-token-cancel token)))))))
