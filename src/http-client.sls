#!r6rs
;;; (http-client): chez-curl's high level (ADR-0007, ADR-0010, ADR-0025; the
;;; M5 plan, sections 3.1 to 3.7). It reaches the low level through (curl)
;;; alone, and holds no native object of its own.
;;;
;;; A session owns one engine, and the defaults its calls share. Every call
;;; takes its session first; there is no default session, and nothing here
;;; starts a thread a caller did not ask for. A call blocks its caller's
;;; thread until its response, which it answers whatever the status: a
;;; status is data. Its timeout-ms bounds the whole call, from its start:
;;; each transfer gets the time left, a redirect's and a retry's among them,
;;; and a retry's wait must end before it.
;;;
;;; Nothing is retried unless the session or the call names a policy
;;; (ADR-0026), and libcurl may still resend a request on its own: on a
;;; reused connection that died before any response byte, and on an HTTP/2
;;; stream refused with REFUSED_STREAM, five times more, a post's among them
;;; (ADR-0026, amended 2026-10-28). With a policy, a step, one URL, makes
;;; the policy's attempts at most, and a redirect starts the count again
;;; (the M5 plan, section 3.5). A step retries a failure of the connect,
;;; send-receive or timeout class, but the bound's own 28: for any method
;;; when nothing was sent, by the failure's request size, 0; otherwise only
;;; for a method in the policy's methods, and on libcurl 8.7.0 and 8.7.1,
;;; whose request size is unknown, #f, a transfer that ran is read as sent.
;;; It retries a status in the policy's statuses, 400 to 599, for a method
;;; in its methods. Between, it waits the backoff, doubling, capped, a draw's share
;;; of it with jitter, from the session's own generator; or a retried
;;; status's Retry-After, delta-seconds or an HTTP-date, which one longer
;;; than max-backoff-ms, or than the time left, makes no retry. What is not
;;; retried is answered or raised as with no policy. A retried response
;;; joins no history. A retry that runs out of time having sent nothing,
;;; the bound passing before the retried request is submitted or while its
;;; transfer has a request size of 0, answers the last response it
;;; retried, or raises the last failure, with &http-exchange and no
;;; &http-timeout; one whose request may have gone out raises the bound's
;;; &http-timeout. A raised failure's request size speaks for its own
;;; transfer alone: with more than one transfer counted, an earlier one of
;;; the step may have sent its request.
;;;
;;; A call follows a redirect by chez-curl's rules, alike on every libcurl
;;; (the M5 plan, section 3.4; ADR-0008, ADR-0023 and ADR-0027): a 301,
;;; 302, 303, 307 or 308 whose first Location header is neither empty nor
;;; blank. The Location's bytes are resolved by curl-url-resolve against
;;; the URL the transfer requested; one that is # and a fragment keeps that
;;; URL, its fragment set by curl-url-with-fragment, and one with no #
;;; takes that URL's own fragment. A 301 or 302 makes a post a get, and a
;;; 303 every method but head, each without its body or the call's headers
;;; for one: Content-*, Digest and Last-Modified. Another origin, by scheme,
;;; host A to Z folded and port, drops Authorization, Cookie and
;;; Proxy-Authorization from then on, and another host drops Host too;
;;; every other header follows. Each followed response joins the history.
;;; libcurl's own following stays off.
;;;
;;; What a call raises carries its context: a call compounds its own
;;; failures, (curl)'s included, with &http-exchange. A condition the
;;; caller's own interrupt handler or timer raises while the call awaits
;;; leaves it unchanged, after the call has cancelled its transfer; a
;;; continuable one a handler returns from resumes the call. One that lands
;;; earlier, while the call's keys and URL are checked, is compounded as
;;; the checks' own are: the low level's assertion violations among them
;;; are no &curl-error, so nothing tells the two apart there. It re-exports
;;; nothing of (curl): a caller who catches a class of the low level's
;;; imports (curl) too.
;;;
;;; A call that is escaped cancels its transfer: a Ctrl-C whose handler
;;; escapes, a timer's, a continuation, and a Chez engine's expiry, which
;;; is an escape too. So a call inside an engine that time-slices fails
;;; whenever an expiry lands in its await: the expiry cancels the transfer,
;;; and the call, once the engine is resumed, raises the low level's
;;; cancelled, with its &http-exchange and the transfer counted. A call made
;;; with interrupts off, inside a critical section, is refused before it
;;; submits anything: its await could not wait there.
;;;
;;; A request group runs many calls at once on one thread, with no thread
;;; per call (ADR-0012; the M5 plan, section 3.7):
;;; call-with-request-group calls its procedure with go, which starts a
;;; call and answers its pending at once, and http-await answers one. Its
;;; calls share one mailbox (ADR-0021), and whichever the thread waits for,
;;; it drives them all: each step of a call, a redirect's and a retry's
;;; among them, is the one-call shell's, and a submit's refusal is its own
;;; call's failure alone. A limit queues the calls past it, each on its
;;; clock. The group does not return while one of its calls is live: when
;;; its procedure returns, it awaits every call and raises the first
;;; failure no await answered; when its procedure escapes, it cancels
;;; every call, waits for each transfer to end, then lets the escape go
;;; on. http-parallel runs a list of calls so, checked first, and answers
;;; their responses in order, or raises the first failure once the rest
;;; have ended.
(library (http-client)
  (export
   ;; --- sessions (ADR-0025) ------------------------------------------------
   ;; make-http-session : Any ... -> Session
   ;; (make-http-session KEY VALUE ...): a session, with these keys, each
   ;; once at most, each left out taking the low level's default, as
   ;; make-curl-request takes them: headers, user-agent, timeout-ms,
   ;; connect-timeout-ms, body-limit, ca-file, verify and proxy; and two of
   ;; the high level's own:
   ;;   redirects        the most redirects a call follows, an exact
   ;;                    natural; or #f, which follows none and answers the
   ;;                    redirect; 20
   ;;   allow-downgrade  whether a redirect from https to http is followed,
   ;;                    a boolean; #f (ADR-0027)
   ;;   retry            a policy, made by make-http-retry, that a call
   ;;                    retries by; or #f, none; #f (ADR-0026)
   ;; A key it does not take, one given twice, and one with no value are
   ;; refused by name, as &http-request-error; then redirects,
   ;; allow-downgrade and retry, as &http-request-error,
   ;; not-a-redirect-count, not-a-boolean and not-a-retry-policy; then each
   ;; other value, as make-curl-request refuses it; and only then is its
   ;; engine made, so a refusal leaves none. Each session draws its jitter
   ;; from a generator of its own, under a mutex of its own, so threads may
   ;; share it.
   ;; http-session? : Any -> Boolean
   ;; http-session-close : Session -> Void
   ;; Stops the session's engine: each call in flight ends as stopped, and a
   ;; later call raises the engine's &curl-engine-error. A second close
   ;; returns. It does not drain. A second escape, a Ctrl-C or a timer's
   ;; handler, that lands as the close starts can leave the engine running
   ;; until the process exits (ADR-0025, amended 2026-10-27), as a second
   ;; Ctrl-C during a group's join leaves its tokens live (the M5 plan,
   ;; section 3.7).
   ;; call-with-http-session : Any ... (Session -> Any) -> Any
   ;; (call-with-http-session KEY VALUE ... PROC): PROC's answer, called with
   ;; a session made from the keys, which is closed when PROC returns or
   ;; escapes. The close is the after thunk of a plain dynamic-wind, so a
   ;; second escape that lands as it starts can skip it, and leave the
   ;; engine running until the process exits, as for http-session-close: a
   ;; documented limit, not prevented (ADR-0025, amended 2026-10-27).
   make-http-session http-session? http-session-close call-with-http-session

   ;; --- the verbs (ADR-0025) -----------------------------------------------
   ;; http-request : Session Symbol String Any ... -> Response
   ;; (http-request SESSION METHOD URL KEY VALUE ...): METHOD, one of get,
   ;; head, post, put, patch and delete, on URL, an http or https URL. Its
   ;; keys are the session's, redirects, allow-downgrade and retry among
   ;; them, each replacing the session's value, a retry of #f none over the
   ;; session's policy, and:
   ;;   body    a bytevector, sent as it is, or a string, sent as its UTF-8
   ;;           bytes, with no Content-Type of its own
   ;;   form    a list of (NAME . VALUE) strings, sent encoded as
   ;;           application/x-www-form-urlencoded, with that Content-Type,
   ;;           unless the headers name one, in any A to Z case
   ;;   params  a list of (NAME . VALUE) strings, encoded the same way and
   ;;           appended to the URL's query
   ;; body and form together are refused, and either with get or head. A
   ;; call's header replaces every session header of its name, A to Z
   ;; folded, after the session's others; a call's User-Agent header sets
   ;; no user-agent field, and a call's user-agent field drops the session's
   ;; User-Agent header. Its timeout-ms bounds the whole call, from its
   ;; start: a 28 at that bound raises &http-timeout, compounded with the
   ;; low level's &curl-timeout. A redirect it does not follow raises
   ;; &http-redirect-error. Two Location headers fail the transfer as
   ;; (curl)'s &curl-protocol-error on the libcurls measured from 8.20.0,
   ;; 8.20.0 and 8.23.0, and the first is followed on 7.85.0, 8.5.0 and
   ;; 8.7.1.
   ;; http-get, http-head, http-post, http-put, http-patch, http-delete :
   ;;   Session String Any ... -> Response
   ;; http-request with the method each name says.
   http-request http-get http-head http-post http-put http-patch http-delete

   ;; --- the retry policy (ADR-0026) ----------------------------------------
   ;; make-http-retry : Any ... -> Retry
   ;; (make-http-retry KEY VALUE ...): a policy, data alone, for a session's
   ;; or a call's retry key, with these keys, each once at most, each left
   ;; out its default:
   ;;   attempts        transfers per step, the first among them, an exact
   ;;                   integer of 1 or more; 3
   ;;   backoff-ms      the first retry's wait, doubling for each later one
   ;;                   of the step, an exact natural; 200
   ;;   max-backoff-ms  the backoff's cap, and the longest Retry-After
   ;;                   waited, an exact natural; 10000
   ;;   jitter          #t waits a uniform share of the backoff, rounded
   ;;                   down to a whole ms ("full jitter"), #f the backoff
   ;;                   itself; #t
   ;;   statuses        the statuses retried, exact integers from 400 to
   ;;                   599; (429 503)
   ;;   methods         the methods a status, or a failure after a request
   ;;                   was sent, is retried for, of get, head, post, put,
   ;;                   patch and delete; (get head put delete), which RFC
   ;;                   9110, section 9.2.2, calls idempotent
   ;; A key it does not take, one given twice, and one with no value are
   ;; refused by name, as &http-request-error, as a session's are; then each
   ;; value, in that order, as &http-request-error: not-an-attempt-count,
   ;; not-a-backoff, not-a-boolean, not-a-status-list and not-a-method-list.
   ;; Its lists are copied.
   ;; http-retry? : Any -> Boolean
   make-http-retry http-retry?

   ;; --- the request group (the M5 plan, section 3.7) ----------------------
   ;; call-with-request-group : Session Any ... (Go -> Any) -> Any
   ;; (call-with-request-group SESSION KEY VALUE ... PROC): PROC's values,
   ;; called with go, on a group of SESSION's on this thread, once every
   ;; call it started has ended and no transfer of its is live. Its one key:
   ;;   limit  the most calls in flight, an exact positive integer; or #f,
   ;;          no limit; #f
   ;; A key it does not take, one given twice, and one with no value are
   ;; refused by name, as &http-request-error, then a limit, not-a-limit.
   ;; It refuses inside a critical section, as an assertion violation from
   ;; call-with-request-group, before anything else.
   ;;   go : Symbol String Any ... -> Pending
   ;;   (go METHOD URL KEY VALUE ...): starts a call, as http-request takes
   ;;   one, its clock started then, and answers its pending at once. Its
   ;;   method, keys and URL are checked first, as http-request checks them:
   ;;   a refusal raises from go, compounded with &http-exchange, and starts
   ;;   no call. Past the limit, the call waits its turn, first in, first
   ;;   out, on its clock: its bound passing first fails it with
   ;;   &http-timeout. A call holds its slot until it ends, through every
   ;;   redirect, retry and retry's wait. From its first submit on, what
   ;;   becomes of it, a submit's refusal among it, is its own answer, never
   ;;   raised by go; and so is anything else its own code raises later, in
   ;;   a step or a submit, as its failure. go waits for no transfer, only
   ;;   for brief holds of the engine's mutex, for its submit, and of the
   ;;   session's, for a refused submit's draw; and it copies the call's
   ;;   body. A condition a caller's interrupt handler or timer raises
   ;;   while go checks the call is compounded as the checks' own are, as
   ;;   http-request's is (the M5 plan, section 10, carried).
   ;; The group's thread drives every call whenever it awaits one, polls one
   ;; or joins, so a redirect or a retry of one call proceeds while another
   ;; is awaited. When PROC returns, the group awaits every call, then
   ;; raises the first call to fail that no await answered, compounded as
   ;; the call raised it: the first the group saw fail, ties seen together
   ;; in the order of their latest submits, a redirect's or a retry's among
   ;; them. A call the caller cancelled
   ;; raises nothing there, whether it had failed first or not. When PROC
   ;; raises or escapes, the group cancels every live transfer, ends every
   ;; call as cancelled, waits for each transfer to end, then lets the
   ;; raise leave. A handler installed outside the group by
   ;; with-exception-handler runs before that, where the raise is made,
   ;; inside the group: it sees the calls as they were. A Chez engine's
   ;; expiry is an escape too: around a group, it ends the whole group and
   ;; closes it. Once the engine is resumed, an await raises cancelled; a go
   ;; that had not yet entered its call raises closed, and one that had
   ;; answers its pending, whose await raises cancelled. An expiry inside a
   ;; call's checks, whose URL parse runs
   ;; in (curl)'s critical winds, leaves the parse behind: the resumed call
   ;; raises (curl)'s refusal to re-enter it, an assertion violation from
   ;; call-with-parsed-url (the M5 plan, section 10, carried). A group is its
   ;; thread's: go, http-await,
   ;; http-pending-done? and http-pending-cancel from another thread raise
   ;; &http-group-error, wrong-thread, and go once PROC has returned or
   ;; escaped, closed. The join can wait: a cancel ends a transfer once
   ;; libcurl has let go of it, which a stalled name lookup holds up to
   ;; glibc's resolver timeout on libcurl 7.85.0 to 7.86.x (ADR-0019); and a
   ;; second Ctrl-C whose handler escapes during that wait abandons it,
   ;; leaving those transfers live: a documented limit, not prevented.
   ;; http-pending? : Any -> Boolean
   ;; http-await : Pending -> Response
   ;;   the call's response, or a raise of its condition, once it has ended,
   ;;   the group driven meanwhile; the same any number of times, after the
   ;;   group has returned too. A cancelled call's raises &http-group-error,
   ;;   cancelled, with its &http-exchange, once a transfer live at the
   ;;   cancel has ended, and compounded with that transfer's own
   ;;   condition. It refuses inside a critical section.
   ;; http-pending-done? : Pending -> Boolean
   ;;   one turn of the group, with no wait, then whether the call has
   ;;   ended, a cancelled one among them: a caller that polls it moves the
   ;;   group on. It refuses inside a critical section.
   ;; http-pending-cancel : Pending -> Void
   ;;   ends the call as cancelled: its live transfer cancelled, or its
   ;;   turn or its retry's wait dropped. A call that has ended keeps its
   ;;   answer, which its await gives, but one that failed is no longer
   ;;   raised by the join. It waits for no transfer: a live transfer's
   ;;   cancel is a message, under the engine's mutex; a transfer still
   ;;   queued in the engine, not yet taken in by its thread, is completed
   ;;   at once, under the engine's mutex, into the group's mailbox, under
   ;;   the mailbox's nested inside it; and a call waiting for a slot, or in
   ;;   a retry's wait, has no transfer, and its cancel holds no mutex.
   call-with-request-group http-pending? http-await http-pending-done? http-pending-cancel

   ;; http-parallel : Session (Listof (Pairof Symbol (Pairof String (Listof Any)))) Any ...
   ;;                 -> (Listof Response)
   ;; (http-parallel SESSION SPECS KEY VALUE ...): each spec (METHOD URL KEY
   ;; VALUE ...), as http-request takes them, run in one group, its one key
   ;; limit, as call-with-request-group's; the responses, in SPECS' order.
   ;; Every spec is checked before any is submitted: SPECS and each spec
   ;; must be a list, else an assertion violation from http-parallel; each
   ;; call's method, keys and URL as go checks them; then its first request
   ;; by (curl)'s curl-request-check, as a submit would check it, its URL's
   ;; scheme and its CA file against the environment (ADR-0024) among it;
   ;; each refusal compounded with &http-exchange (ADR-0023, amended
   ;; 2026-10-28). A refusal only an engine makes, its stop or its
   ;; failure, can still come once the calls run, as a failure among them.
   ;; The first call to fail raises, as it raised, once every other is
   ;; cancelled and its transfer has ended: the first the group saw fail,
   ;; ties in the order of their latest submits. A condition a caller's
   ;; interrupt handler or timer raises during the checks is compounded as
   ;; the checks' own are, as http-request's is (the M5 plan, section 10,
   ;; carried). An escape ends its group, a Chez engine's expiry among them:
   ;; resumed, it enters no call more, submits none it had not, and raises
   ;; its first failure, if any, or else the cancel of its first call, in
   ;; SPECS' order, not done; an expiry inside the checks makes the resumed
   ;; call raise
   ;; (curl)'s refusal to re-enter a URL's parse, as go's does. It refuses
   ;; inside a critical section, before anything else.
   http-parallel

   ;; --- the response -------------------------------------------------------
   ;; http-response? : Any -> Boolean
   ;; http-response-status : Response -> Integer
   ;; http-response-http-version : Response -> (U 'http/1.0 'http/1.1 'http/2 'http/3 Integer #f)
   ;; http-response-url : Response -> String
   ;;   the URL its transfer requested, as curl-url-part gives it whole: the
   ;;   call's, its params appended, or a redirect's; its user info and
   ;;   fragment kept, and a redirect's fragment, which is never sent
   ;; http-response-headers : Response -> (Listof (Pairof String String))
   ;; http-response-body : Response -> Bytevector
   ;; http-response-timings : Response -> (Listof (Pairof Symbol Natural))
   ;;   as curl-response-timings
   ;; http-response-history : Response -> (Listof Response)
   ;;   the call's earlier responses, each a redirect it followed, oldest
   ;;   first, each with a history of (); a response a retry repeated is not
   ;;   among them
   ;; http-response-header : Response String -> (U String #f)
   ;;   the first header of that name, A to Z folded, or #f
   ;; http-response-text : Response -> String
   ;;   the body as UTF-8, by utf8->string: U+FFFD for a malformed sequence,
   ;;   a leading byte-order mark dropped; no charset read
   http-response? http-response-status http-response-http-version http-response-url
   http-response-headers http-response-body http-response-timings http-response-history
   http-response-header http-response-text

   ;; --- the conditions -----------------------------------------------------
   ;; &http-error: the base of the high level's own, under &curl-error.
   ;; http-error? : Any -> Boolean
   &http-error http-error?

   ;; &http-request-error: a key or a value the high level checks, refused.
   ;; http-request-error? : Any -> Boolean
   ;; http-request-error-field : &http-request-error -> Symbol
   ;; http-request-error-value : &http-request-error -> Any
   ;; http-request-error-reason : &http-request-error -> Symbol
   ;; http-request-error-reasons : (Listof Symbol)
   ;;   unknown-key, repeated-key and missing-value, field key, the key;
   ;;   body-and-form, field form; body-not-allowed, field body or form, the
   ;;   method; not-a-body, field body; not-name-value-pairs, field form or
   ;;   params; not-a-redirect-count, field redirects; not-a-boolean, field
   ;;   allow-downgrade or jitter; not-a-retry-policy, field retry;
   ;;   not-an-attempt-count, field attempts; not-a-backoff, field
   ;;   backoff-ms or max-backoff-ms; not-a-status-list, field statuses;
   ;;   not-a-method-list, field methods; not-a-limit, field limit; each
   ;;   the value as given
   &http-request-error http-request-error? http-request-error-field
   http-request-error-value http-request-error-reason http-request-error-reasons

   ;; &http-redirect-error: a redirect the rules do not follow.
   ;; http-redirect-error? : Any -> Boolean
   ;; http-redirect-error-reason : &http-redirect-error -> Symbol
   ;; http-redirect-error-response : &http-redirect-error -> Response
   ;;   the response that named the redirect, with the call's history
   ;;   before it
   ;; http-redirect-error-location : &http-redirect-error -> (U String #f)
   ;;   its first Location header's value, as the response holds it
   ;; http-redirect-error-reasons : (Listof Symbol)
   ;;   too-many-redirects, the call had followed redirects of them;
   ;;   bad-location, a Location a URL function of (curl) refused, whose
   ;;   &curl-url-error is compounded with it, or one whose scheme is not
   ;;   http or https, with none; insecure-redirect, from https to http,
   ;;   with allow-downgrade #f
   &http-redirect-error http-redirect-error? http-redirect-error-reason
   http-redirect-error-response http-redirect-error-location http-redirect-error-reasons

   ;; &http-timeout: a call's timeout-ms passed.
   ;; http-timeout? : Any -> Boolean
   ;; http-timeout-timeout-ms : &http-timeout -> Positive-Integer
   &http-timeout http-timeout? http-timeout-timeout-ms

   ;; &http-group-error: a request group's refusal, or its call's cancel.
   ;; http-group-error? : Any -> Boolean
   ;; http-group-error-reason : &http-group-error -> Symbol
   ;; http-group-error-reasons : (Listof Symbol)
   ;;   wrong-thread, a group's operation from another thread than its
   ;;   own, its irritants that thread's id and this one's; closed, go once
   ;;   the group's procedure has returned or escaped; cancelled, the await
   ;;   of a call http-pending-cancel or its group's escape ended
   &http-group-error http-group-error? http-group-error-reason http-group-error-reasons

   ;; &http-exchange: what a call raises carries it, under &condition.
   ;; http-exchange? : Any -> Boolean
   ;; http-exchange-method : &http-exchange -> Any
   ;; http-exchange-url : &http-exchange -> Any
   ;;   the method and the URL as the caller gave them
   ;; http-exchange-history : &http-exchange -> (Listof Response)
   ;;   the responses that redirected, oldest first: a retried one is not
   ;;   among them
   ;; http-exchange-transfers : &http-exchange -> Natural
   ;;   the transfers the call submitted that the engine took, each retry's
   ;;   among them
   &http-exchange http-exchange? http-exchange-method http-exchange-url
   http-exchange-history http-exchange-transfers)
  (import (curl)
          (rnrs)
          (http-client private conditions)
          (http-client private call)
          (http-client private exchange)
          (http-client private drive))

  ;; check-session : Symbol Any -> Void
  (define (check-session who x)
    (unless (http-session? x) (assertion-violation who "not a session" x)))

  ;; call-state : Session Any Any List Boolean -> State
  ;; A call's exchange, as http-request and go make one, its clock started
  ;; first: its bound runs from here. The caller's URL is read once, into a
  ;; copy, which both the context and the request are made from. With
  ;; CHECK?, the first request also passes (curl)'s curl-request-check, a
  ;; submit's own checks, for http-parallel's checks before any submit
  ;; (ADR-0023, amended 2026-10-28). Every condition raised, a check's, the
  ;; URL's or the low level's, is compounded with &http-exchange, with no
  ;; transfer made.
  (define (call-state session method url plist check?)
    (let* ((start (monotonic-ns))
           (given (if (string? url) (string-copy url) url)))
      (guard (e ((condition? e)
                 (raise (condition e (make-http-exchange method given '() 0)))))
        (check-session 'http-request session)
        (let-values (((request redirects allow-downgrade retry)
                      (call-request session method given plist)))
          (when check? (curl-request-check request))
          (make-exchange method given request (curl-request-timeout-ms request)
                         start redirects allow-downgrade retry)))))

  (define (make-http-session . plist)
    (let* ((settings (key-settings 'make-http-session session-keys plist))
           (policy (session-policy settings))
           (defaults (session-defaults settings)))
      (new-http-session (make-curl-engine) defaults (car policy) (cadr policy) (caddr policy))))

  (define (http-session-close session)
    (check-session 'http-session-close session)
    (curl-engine-stop (http-session-engine session)))

  (define (call-with-http-session . arguments)
    (when (null? arguments)
      (assertion-violation 'call-with-http-session "a procedure, after the keys, is required"
                           arguments))
    (let* ((reversed (reverse arguments))
           (proc (car reversed))
           (plist (reverse (cdr reversed))))
      (unless (procedure? proc)
        (assertion-violation 'call-with-http-session
                             "the last argument is a procedure, of the session" proc))
      (let ((session (apply make-http-session plist)))
        (dynamic-wind
          (lambda () #f)
          (lambda () (proc session))
          (lambda () (http-session-close session))))))

  ;; http-request : Session Any Any Any ... -> Response
  ;; The call's exchange, by call-state, then the drive: in the drive,
  ;; (curl)'s conditions are compounded by the core, and the drive's own
  ;; refusal by the drive.
  (define (http-request session method url . plist)
    (let ((state (call-state session method url plist #f)))
      (drive-exchange (http-session-engine session) state
                      (lambda () (http-session-draw session)))))

  ;; call-with-request-group : Session Any ... (Go -> Any) -> Any
  ;; Refuses a critical section first, then its arguments, then its keys;
  ;; then the group, on the session's engine, drawing from its generator,
  ;; each go's call made by call-state.
  (define (call-with-request-group . arguments)
    (require-interrupts 'call-with-request-group)
    (when (or (null? arguments) (null? (cdr arguments)))
      (assertion-violation 'call-with-request-group
                           "a session, then the keys, then a procedure of go, are required"
                           arguments))
    (let* ((session (car arguments))
           (reversed (reverse (cdr arguments)))
           (proc (car reversed))
           (plist (reverse (cdr reversed))))
      (check-session 'call-with-request-group session)
      (unless (procedure? proc)
        (assertion-violation 'call-with-request-group
                             "the last argument is a procedure, of go" proc))
      (let ((limit (group-limit 'call-with-request-group plist)))
        (call-with-group (http-session-engine session) limit
                         (lambda () (http-session-draw session))
                         (lambda (method url plist) (call-state session method url plist #f))
                         proc))))

  ;; spec-copies : Any -> (Listof (Pairof Any (Pairof Any List)))
  ;; A copy of SPECS, a list of specs, each a list of a method, a URL, then
  ;; keys: fresh pairs, each list judged by list?, which answers #f for an
  ;; improper or circular one and raises nothing, so no guard is needed,
  ;; and an interrupt handler's raise there leaves as raised, never read as
  ;; a refusal; then measured by length and copied within that bound, so a
  ;; list another thread changes after cannot loop the copy. Anything else
  ;; is an assertion violation from http-parallel.
  (define (spec-copies specs)
    (let ((copy (lambda (x)
                  (and (list? x)
                       (let loop ((rest x) (left (length x)) (copied '()))
                         (cond ((and (null? rest) (= left 0)) (reverse copied))
                               ((or (= left 0) (not (pair? rest))) #f)
                               (else (loop (cdr rest) (- left 1) (cons (car rest) copied)))))))))
      (let ((outer (copy specs)))
        (unless outer
          (assertion-violation 'http-parallel "the specs are a list" specs))
        (let loop ((rest outer) (copied '()))
          (if (null? rest)
              (reverse copied)
              (let ((spec (copy (car rest))))
                (unless (and spec (>= (length spec) 2))
                  (assertion-violation 'http-parallel
                                       "a spec is a list of a method, a URL, then keys"
                                       (car rest)))
                (loop (cdr rest) (cons spec copied))))))))

  ;; http-parallel : Session (Listof (Pairof Symbol (Pairof String (Listof Any)))) Any ...
  ;;                 -> (Listof Response)
  ;; Refuses a critical section first, then the session, its keys and the
  ;; specs' shape; then makes every spec's call by call-state, in order,
  ;; each first request checked by curl-request-check, before any is
  ;; submitted; then runs them in one group.
  (define (http-parallel session specs . plist)
    (require-interrupts 'http-parallel)
    (check-session 'http-parallel session)
    (let* ((limit (group-limit 'http-parallel plist))
           (copies (spec-copies specs))
           (states (let loop ((rest copies) (made '()))
                     (if (null? rest)
                         (reverse made)
                         (let ((spec (car rest)))
                           (loop (cdr rest)
                                 (cons (call-state session (car spec) (cadr spec) (cddr spec) #t)
                                       made)))))))
      (run-parallel (http-session-engine session) limit
                    (lambda () (http-session-draw session))
                    states)))

  (define (http-get session url . plist) (apply http-request session 'get url plist))
  (define (http-head session url . plist) (apply http-request session 'head url plist))
  (define (http-post session url . plist) (apply http-request session 'post url plist))
  (define (http-put session url . plist) (apply http-request session 'put url plist))
  (define (http-patch session url . plist) (apply http-request session 'patch url plist))
  (define (http-delete session url . plist) (apply http-request session 'delete url plist)))
