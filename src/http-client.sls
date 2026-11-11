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
;;; &http-timeout. A streamed call whose retry runs out so after its hop
;;; was cancelled at its head, whose body it never read, fails with
;;; &http-timeout, as with no time left for any request. A raised
;;; failure's request size speaks for its own transfer alone: with more
;;; than one transfer counted, an earlier one of the step may have sent
;;; its request.
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
;;; host A to Z folded and port, drops Authorization and Cookie from then
;;; on, and the credentials key with them (ADR-0036), and another host
;;; drops Host too; no request holds a Proxy-Authorization header, which the
;;; low level refuses (ADR-0037);
;;; every other header follows, as every other key does, the http-version
;;; among them: a redirect from http:// to https:// by prior knowledge
;;; fails the call with the low level's refusal of its next request,
;;; prior-knowledge-over-https, compounded with its &http-exchange (ADR-0034);
;;; and a redirect within one origin to a URL holding a user or a password,
;;; beside credentials, fails it so with credentials-beside-userinfo. The
;;; proxy, the proxy CA file and the proxy's verification go to every hop,
;;; another origin's too, the proxy URL's credentials with it: a hop to
;;; https:// through an https:// proxy where TLS inside TLS stalls fails
;;; the call so, proxy-tls-in-tls. A session's cookie jar goes to every
;;; hop, another origin's too: libcurl matches cookies to hosts.
;;; Each followed response joins the history. libcurl's own following stays
;;; off.
;;;
;;; A retry policy treats a CONNECT a proxy refused with a status, a
;;; transfer failure that carries curl-transfer-error-connect-code, as a
;;; response with that status: retried when the policy's statuses hold it
;;; and its methods the call's, alike on every libcurl, its wait the
;;; backoff's (ADR-0026, amended 2026-11-03). So the default policy retries
;;; no 403 nor 407. A proxy that ends a CONNECT with no status keeps the
;;; class rule above, where 7.85.0's request size, the CONNECT's, errs
;;; toward not repeating a post.
;;;
;;; What a call raises carries its context: a call compounds its own
;;; failures, (curl)'s included, with &http-exchange. A condition the
;;; caller's own interrupt handler or timer raises while the call awaits
;;; leaves it unchanged, after the call has cancelled its transfer; a
;;; continuable one a handler returns from resumes the call. A call's
;;; checks, of its session, keys, body, form, params, request and URL, run
;;; in one critical section, its guard inside it, so no handler runs inside
;;; them: a Ctrl-C made pending there runs as the section ends, and a timer
;;; that runs out there at a later event check, each outside the checks,
;;; so what it raises leaves as raised, whatever it is, and a continuable
;;; raise a handler returns from resumes the call (ADR-0025, amended
;;; 2026-11-05). A guard around the checks with interrupts on read a
;;; handler's raise there as the call's own: its condition left
;;; compounded, a continuable one could not resume the call, and an object
;;; no clause took was re-raised back inside the URL's parse, whose
;;; critical wind refused the re-entry (the M5 plan, section 10). The
;;; section holds Ctrl-C and other threads' collections for the checks'
;;; length, under 0.5 ms for an ordinary call, and each hold grows with
;;; its input, with no bound but the input's: about 0.4 to 0.5 ms a MiB of
;;; a bytevector body, as long as its copy, a primitive that makes no event
;;; check wherever it runs; 2 to 2.7 ms a Mi chars of a string body; 31 to
;;; 52 ms a Mi chars of a form value; 0.4 to 0.5 ms a thousand headers; 0.6
;;; to 0.7 ms a thousand params; and about 29 ms a million chars of a URL,
;;; up to libcurl's 8,000,000-byte cap: a URL longer than 8,000,000 chars,
;;; whose UTF-8 bytes pass it, is refused at the checks' start, at once, as
;;; libcurl refuses it, malformed-input, its refusal before the keys'
;;; (.plans/research/m7/carried/guard/, the fix round's hold-rates.log).
;;; Once a collection falls due during a hold, every thread stops at its
;;; next event check until the hold ends, the engine's thread among them,
;;; and with it every transfer that engine drives (traps.md). A caller who
;;; takes a body, a form, headers or params from untrusted input bounds
;;; their sizes first. A refusal is raised once the section has ended, so
;;; a caller's handler runs with interrupts on. A redirect's step runs in
;;; a critical section of its own too (the drive's section-step): what a
;;; handler raises there comes after it, and no expiry lands inside it. A
;;; group's step submits the next hop inside its section, so a raise that
;;; comes as it ends cancels a transfer the engine may already have
;;; started: one or two started, measured (research/m7/carried/guard/,
;;; the fix round's tally); a single call submits after its section. It
;;; re-exports nothing of (curl): a caller who catches a class of the low
;;; level's imports (curl) too.
;;;
;;; A call that is escaped cancels its transfer: a Ctrl-C whose handler
;;; escapes, a timer's, a continuation, and a Chez engine's expiry, which
;;; is an escape too. So a call inside an engine that time-slices fails
;;; whenever an expiry lands in its await: the expiry cancels the transfer,
;;; and the call, once the engine is resumed, raises the low level's
;;; cancelled, with its &http-exchange and the transfer counted. No expiry
;;; lands inside a call's checks or a step, a redirect's among them: one
;;; that runs out there lands once its section has ended, and the call
;;; goes on, resumed. A call made
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
;;; have ended. A group takes no producer.
;;;
;;; A call streams (ADR-0031; the M6 plan, section 3.6): through
;;; call-with-response-port, whose procedure is handed the final head and a
;;; port over the body as it arrives; and with a producer as its body,
;;; called as libcurl asks, its body sent at most once (ADR-0032). Each
;;; streamed transfer's head decides whether the call ends with it or steps
;;; past it, by the rules above, read once: a hop whose request sends a
;;; body is cancelled at its head, and one whose request sends none is read
;;; whole into the history.
(library (http-client)
  (export
   ;; --- sessions (ADR-0025) ------------------------------------------------
   ;; make-http-session : Any ... -> Session
   ;; (make-http-session KEY VALUE ...): a session, with these keys, each
   ;; once at most, each left out taking the low level's default, as
   ;; make-curl-request takes them: headers, user-agent, timeout-ms,
   ;; connect-timeout-ms, body-limit, ca-file, verify, proxy, http-version,
   ;; credentials, which a redirect to another origin drops, and which a
   ;; streamed call, call-with-response-port's or a producer's, takes as
   ;; Basic or Bearer alone, digest-with-stream, proxy-ca-file and
   ;; proxy-verify; a call's value replaces its session's, but a call that
   ;; names its own proxy drops the session's proxy-ca-file and
   ;; proxy-verify; and four of the high level's own:
   ;;   redirects        the most redirects a call follows, an exact
   ;;                    natural; or #f, which follows none and answers the
   ;;                    redirect; 20
   ;;   allow-downgrade  whether a redirect from https to http is followed,
   ;;                    a boolean; #f (ADR-0027)
   ;;   retry            a policy, made by make-http-retry, that a call
   ;;                    retries by; or #f, none; #f (ADR-0026)
   ;;   cookies          whether the session keeps cookies: #t makes a jar
   ;;                    on its engine, (curl)'s make-curl-cookie-jar, which
   ;;                    every call of the session carries, every hop of a
   ;;                    redirect among them, another origin's too, and its
   ;;                    close frees; a boolean; #f, none (ADR-0035). No call
   ;;                    takes it. Beside it a Cookie or Host header, the
   ;;                    session's or a call's, in any A to Z case, is
   ;;                    refused, (curl)'s cookie-beside-jar
   ;; A key it does not take, one given twice, and one with no value are
   ;; refused by name, as &http-request-error; then redirects,
   ;; allow-downgrade, retry and cookies, as &http-request-error,
   ;; not-a-redirect-count, not-a-boolean, not-a-retry-policy and
   ;; not-a-boolean; then each other value, as make-curl-request refuses
   ;; it; and only then is its engine made, so a refusal leaves none. With
   ;; cookies, its jar is made then, and a session's Cookie or Host header
   ;; refused: either refusal, and a jar that fails to be made, stops the
   ;; engine it made, and leaves as it was raised. Each session draws its jitter
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

   ;; http-session-cookies : Session -> (Listof String)
   ;; The session's cookies, as (curl)'s curl-cookie-jar-cookies reads them
   ;; out: Netscape lines, Latin-1 strings, in libcurl's order.
   ;; http-session-load-cookies! : Session (Listof String) -> Void
   ;; Loads the lines into the session's jar, as (curl)'s
   ;; curl-cookie-jar-load! loads them, every line checked first, its
   ;; refusal cookie-line, naming the line's index alone.
   ;; Each waits for the engine, as a session's close does, with no bound;
   ;; a session without cookies is an assertion violation, and a closed
   ;; one's raises its engine's &curl-engine-error, stopped.
   http-session-cookies http-session-load-cookies!

   ;; --- the verbs (ADR-0025) -----------------------------------------------
   ;; http-request : Session Symbol String Any ... -> Response
   ;; (http-request SESSION METHOD URL KEY VALUE ...): METHOD, one of get,
   ;; head, post, put, patch and delete, on URL, an http or https URL. Its
   ;; keys are the session's, redirects, allow-downgrade and retry among
   ;; them, each replacing the session's value, a retry of #f none over the
   ;; session's policy, and:
   ;;   body         a bytevector, sent as it is, or a string, sent as its
   ;;                UTF-8 bytes, with no Content-Type of its own; or a
   ;;                producer, ( -> (U Bytevector Eof)), the body streamed
   ;;                as it gives it (ADR-0031, decision 2), below
   ;;   form         a list of (NAME . VALUE) strings, sent encoded as
   ;;                application/x-www-form-urlencoded, with that
   ;;                Content-Type, unless the headers name one, in any A to Z
   ;;                case
   ;;   params       a list of (NAME . VALUE) strings, encoded the same way
   ;;                and appended to the URL's query
   ;;   body-length  a producer's length, an exact natural below 2^63 - 1,
   ;;                sent as Content-Length; or #f, the body chunked over
   ;;                HTTP/1.1 and as DATA frames over HTTP/2; #f. Beside a
   ;;                body that is no producer, (curl)'s refusal,
   ;;                body-length-without-stream
   ;;   multipart    a multipart/form-data body's parts, (PART ...), each
   ;;                as (curl)'s request body (multipart PART ...) takes
   ;;                it, checked as it does: a relative path is resolved
   ;;                once, as the call starts, and each part's data copied
   ;;                then, so its retries and hops send the files and bytes
   ;;                it began with; a session's Content-Type header is
   ;;                dropped, and libcurl writes the type and its boundary
   ;;                (ADR-0039; the M8 plan, section 3.1). A multipart body
   ;;                is a whole body, no producer: a group takes one, a
   ;;                retry resends it, and a 307 or 308 keeps it
   ;; A producer is called on the caller's thread, only once libcurl has
   ;; asked for the body and has room, and never after it answered the eof
   ;; object; it answers a bytevector of a byte or more, or the eof object
   ;; at the end: (lambda () (get-bytevector-some port)) streams a port.
   ;; Its body is sent at most once, on a connection of its own (ADR-0032):
   ;; once the producer counts as called, libcurl having asked for the body
   ;; by a head or the call having called it, no retry takes the call, and a
   ;; redirect that keeps the body, a 307 or 308, and a 301 or 302 of every
   ;; method but post, raises &http-redirect-error, body-not-replayable. A
   ;; refused connect, before any ask, stays retryable. Its answer that is
   ;; neither a bytevector of a byte or more nor the eof object is an
   ;; assertion violation from the call; a piece that would take the body
   ;; past its body-length is &http-request-error, field body, its value the
   ;; producer, body-length-mismatch (ADR-0031, amended); each with its
   ;; &http-exchange, once its transfer is cancelled, before any of it is
   ;; put. Its own raise leaves the call as raised, once its transfer is
   ;; cancelled; a body that ends short of its body-length fails the
   ;; transfer, (curl)'s body-length-mismatch, alike on every libcurl. Such a
   ;; call is a streamed call, as call-with-response-port's is: it streams
   ;; its response too, and reads its body whole, to body-limit. A streamed
   ;; call's hop, a redirect it follows or a retry it takes, whose request
   ;; sends a body is cancelled at its head, its history entry's body and
   ;; timings #f; one whose request sends none is read whole (ADR-0031,
   ;; amended 2026-10-31). A whole body's call is no streamed call, and runs
   ;; as M5's. Over HTTP/2 on libcurl 8.20.0 and 8.23.0, a final 3xx, one
   ;; the call does not follow, that arrives before a body is sent whole,
   ;; streamed or whole, never ends but at the call's bound: pass a
   ;; timeout-ms. So does a whole body's call's hop: M5's drive cannot
   ;; cancel it at its head. A streamed call whose retry runs out of time
   ;; after a hop it cancelled at its head fails with &http-timeout, as with
   ;; no time left (decided by the maintainer, 2026-11-01).
   ;; body and form together are refused, multipart beside either, and any
   ;; of the three with get or head. A
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

   ;; --- streaming the response (ADR-0031, decision 1) ----------------------
   ;; call-with-response-port : Session Symbol String Any ...
   ;;                           (Response Binary-Input-Port -> Any ...) -> Any ...
   ;; (call-with-response-port SESSION METHOD URL KEY VALUE ... PROC): the
   ;; call, as http-request takes it, every response streamed, with one key
   ;; of its own:
   ;;   stream-buffer  the bytes of the body the call buffers, a positive
   ;;                  exact integer; 65536. A full buffer pauses the
   ;;                  transfer: over HTTP/1.1 the server's writes then stall
   ;; It is a streamed call: redirects and retries are decided as each head
   ;; arrives, by the rules above; a hop whose request sends no body has its
   ;; body read whole into the history, and one whose request sends a body
   ;; is cancelled at its head. At the final head PROC is called, on this thread, with
   ;; the response, its status, version, headers, URL and history whole and
   ;; its body and timings #f, and a binary input port over its body, and
   ;; the call answers PROC's values. When PROC returns or escapes, the port
   ;; is closed and a live transfer cancelled. The port feeds a producer as
   ;; it waits, so a server that answers while the body is sent is never
   ;; left without it. Its end is the end of the body, every time after; a
   ;; transfer's failure is raised by its read, the low level's condition
   ;; compounded with &http-exchange, and with &http-timeout when it was the
   ;; call's bound's 28, every time after. Inside the port's read, a
   ;; producer's raise or refusal is the call's for good: every later read
   ;; raises it, and the call raises it once PROC returns. The port is read
   ;; and closed on this thread alone, never by the producer; bytes Chez's
   ;; port has already buffered are served to any thread. Prefer
   ;; get-bytevector-some: a failure raised inside get-bytevector-n, -n! or
   ;; -all loses the bytes that call had read. The call's timeout-ms bounds
   ;; it whole, PROC's reading among it: a reader slower than the bound
   ;; meets &http-timeout. A PROC that never reads, and never returns,
   ;; starves its upload. A call whose retry runs out of time hands PROC the
   ;; retried response and a port over its body in memory; after a hop it
   ;; cancelled at its head, whose body it never read, the call raises
   ;; &http-timeout instead, PROC not called. A Chez engine's expiry during
   ;; the call is an escape, as any is: the transfer is cancelled and the
   ;; port closed. Once the engine resumes, the call meets that cancel: the
   ;; port's reads raise it, then Chez's error for a closed port. A last
   ;; argument that is no procedure is an
   ;; assertion violation, before anything else; a stream-buffer of #f is
   ;; one too, once the keys and the body are checked. The port feeds the
   ;; producer only when no piece is ready: a server that sends faster than
   ;; PROC reads leaves the upload waiting.
   call-with-response-port

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
   ;;   method, keys and URL are checked first, as http-request checks them,
   ;;   and a producer as its body is refused, stream-in-group: a refusal
   ;;   raises from go, compounded with &http-exchange, and starts no call.
   ;;   Past the limit, the call waits its turn, first in, first
   ;;   out, on its clock: its bound passing first fails it with
   ;;   &http-timeout. A call holds its slot until it ends, through every
   ;;   redirect, retry and retry's wait. From its first submit on, what
   ;;   becomes of it, a submit's refusal among it, is its own answer, never
   ;;   raised by go; and so is anything else its own code raises later, in
   ;;   a step or a submit, as its failure. go waits for no transfer, only
   ;;   for brief holds of the engine's mutex, for its submit, and of the
   ;;   session's, for a refused submit's draw; and it copies the call's
   ;;   body. What a caller's interrupt handler or timer raises while go
   ;;   checks the call comes once the checks' critical section has ended,
   ;;   as http-request's does: a raise that leaves starts no call; a
   ;;   continuable one a handler returns from resumes go, which then starts
   ;;   the call.
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
   ;; answers its pending, whose await raises cancelled. An expiry that runs
   ;; out in a call's checks lands once their section has ended, so a go
   ;; resumed there raises closed. A group is its thread's: go, http-await,
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
   ;; call's method, keys and URL as go checks them, a producer refused,
   ;; stream-in-group; then its first request
   ;; by (curl)'s curl-request-check, as a submit would check it, its URL's
   ;; scheme and its CA file against the environment (ADR-0024) among it;
   ;; each refusal compounded with &http-exchange (ADR-0023, amended
   ;; 2026-10-28). A refusal only an engine makes, its stop or its
   ;; failure, can still come once the calls run, as a failure among them.
   ;; The first call to fail raises, as it raised, once every other is
   ;; cancelled and its transfer has ended: the first the group saw fail,
   ;; ties in the order of their latest submits. What a caller's interrupt
   ;; handler or timer raises during the checks leaves as raised, as
   ;; http-request's does; each spec's checks are a critical section of
   ;; their own. An escape ends its group, a Chez engine's expiry among
   ;; them: resumed, it enters no call more, submits none it had not, and
   ;; raises its first failure, if any, or else the cancel of its first
   ;; call, in SPECS' order, not done; an expiry that runs out in the checks
   ;; lands after them, before the group is made, and the call goes on. It
   ;; refuses inside a critical section, before anything else.
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
   ;; http-response-body : Response -> (U Bytevector #f)
   ;;   #f for call-with-response-port's response, whose body streams
   ;;   through its port, and for a hop cancelled at its head
   ;; http-response-timings : Response -> (U (Listof (Pairof Symbol Natural)) #f)
   ;;   as curl-response-timings; #f where the body is #f
   ;; http-response-history : Response -> (Listof Response)
   ;;   the call's earlier responses, each a redirect it followed, oldest
   ;;   first, each with a history of (); a response a retry repeated is not
   ;;   among them
   ;; http-response-header : Response String -> (U String #f)
   ;;   the first header of that name, A to Z folded, or #f
   ;; http-response-text : Response -> String
   ;;   the body as UTF-8, by utf8->string: U+FFFD for a malformed sequence,
   ;;   a leading byte-order mark dropped; no charset read. A body of #f is
   ;;   an assertion violation
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
   ;;   body-and-form, field form; multipart-beside-body, field multipart, a
   ;;   multipart body beside a body or a form; body-not-allowed, field
   ;;   body, form or multipart, the method; not-a-body, field body;
   ;;   not-name-value-pairs, field form or params; not-a-redirect-count, field redirects; not-a-boolean, field
   ;;   allow-downgrade or jitter; not-a-retry-policy, field retry;
   ;;   not-an-attempt-count, field attempts; not-a-backoff, field
   ;;   backoff-ms or max-backoff-ms; not-a-status-list, field statuses;
   ;;   not-a-method-list, field methods; not-a-limit, field limit; each
   ;;   the value as given; stream-in-group, field body, the producer: go
   ;;   and http-parallel take no producer, before anything is submitted;
   ;;   body-length-mismatch, field body, the producer: a piece that would
   ;;   take the body past its body-length
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
   ;;   with allow-downgrade #f; body-not-replayable, a redirect that keeps
   ;;   a producer's body once the producer counts as called (ADR-0032)
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
          (http-client private drive)
          (only (chezscheme) critical-section))

  ;; check-session : Symbol Any -> Void
  (define (check-session who x)
    (unless (http-session? x) (assertion-violation who "not a session" (shown-value x))))

  ;; url-input-cap : Positive-Integer
  ;; libcurl's cap on a URL's bytes, CURL_MAX_INPUT_LENGTH: 8,000,000 on every
  ;; libcurl measured. A string of more chars has more UTF-8 bytes.
  (define url-input-cap 8000000)

  ;; call-state : Session Any Any List Boolean (U 'request 'group 'port) Symbol
  ;;              -> (Pairof State (U Procedure #f))
  ;; A call's exchange, as http-request, go and call-with-response-port
  ;; make one, its clock started first: its bound runs from here; and its
  ;; producer, or #f. The caller's URL is read once, into a copy, which
  ;; both the context and the request are made from. MODE is whose call it
  ;; is, as call-request-of takes it, a group's refusing a producer, and WHO
  ;; names it in the refusals. With CHECK?, the first request also passes
  ;; (curl)'s curl-request-check, a submit's own checks, for http-parallel's
  ;; checks before any submit (ADR-0023, amended 2026-10-28). Every
  ;; condition raised, a check's, the URL's or the low level's, is
  ;; compounded with &http-exchange, with no transfer made.
  ;;
  ;; The checks run in one critical section, the guard inside it, which
  ;; takes every raise there and answers it as data, raised once the
  ;; section has ended (ADR-0025, amended 2026-11-05). So no interrupt
  ;; handler runs inside the guard, which reads the checks' own raises
  ;; alone: a Ctrl-C made pending in the section runs as it ends, outside
  ;; the guard, and a timer or an engine's expiry at a later event check;
  ;; an expiry never leaves a URL's parse behind; and the caller's handler
  ;; for a refusal runs with interrupts on. Nothing inside calls the
  ;; caller's code: a producer is kept, not called, and the keys' values
  ;; are read by length, car, cdr and the copies. What runs inside is
  ;; pure but for a stat of each file part's path a multipart body names,
  ;; by make-curl-request's checks, once for the checked request and once
  ;; for the call's own, and once more with CHECK?: a stat waits only on a
  ;; hung network mount, which no check here can make (ADR-0039, after
  ;; slice 3's review). The URL's parse takes
  ;; three mutexes, the counters', native's owners' and memory's, each
  ;; through locked, briefly, as every holder holds them. The test seam's
  ;; gate, drive-checks-gate-set!'s, is called at the checks' start and end,
  ;; inside the section.
  (define (call-state session method url plist check? mode who)
    (let* ((start (monotonic-ns))
           (given (if (string? url) (string-copy url) url))
           (made (critical-section
                  (guard (e (#t (list 'refused
                                      (if (condition? e)
                                          (condition e (make-http-exchange method given '() 0))
                                          e))))
                    (run-checks-gate! 'start)
                    (check-session who session)
                    ;; A URL past libcurl's cap is refused first, as (curl)'s
                    ;; curl-url-part refuses one at once, libcurl's own
                    ;; refusal, before anything is copied: its checks would
                    ;; have grown with it, held in this section.
                    (when (and (string? given) (> (string-length given) url-input-cap))
                      (curl-url-part given 'url))
                    (let-values (((request redirects allow-downgrade retry producer)
                                  (call-request-of who mode session method given plist)))
                      (when check? (curl-request-check request))
                      (run-checks-gate! 'end)
                      (list 'made
                            (cons (make-exchange method given request (curl-request-timeout-ms request)
                                                 start redirects allow-downgrade retry)
                                  producer)))))))
      (if (eq? (car made) 'refused)
          (raise (cadr made))
          (cadr made))))

  (define (make-http-session . plist)
    (let* ((settings (key-settings 'make-http-session session-keys plist))
           (policy (session-policy settings))
           (cookies (session-cookies settings))
           (defaults (session-defaults settings)))
      (session-on (make-curl-engine) defaults policy cookies)))

  ;; session-jar : Symbol Session -> Jar
  ;; SESSION's cookie jar; a session that keeps none is an assertion
  ;; violation from WHO.
  (define (session-jar who session)
    (check-session who session)
    (or (http-session-jar session)
        (assertion-violation who "the session keeps no cookies: make it with cookies #t" 'cookies)))

  (define (http-session-cookies session)
    (curl-cookie-jar-cookies (session-jar 'http-session-cookies session)))

  (define (http-session-load-cookies! session lines)
    (curl-cookie-jar-load! (session-jar 'http-session-load-cookies! session) lines))

  (define (http-session-close session)
    (check-session 'http-session-close session)
    (curl-engine-stop (http-session-engine session)))

  (define (call-with-http-session . arguments)
    (when (null? arguments)
      (assertion-violation 'call-with-http-session "a procedure, after the keys, is required"
                           'proc))
    (let* ((reversed (reverse arguments))
           (proc (car reversed))
           (plist (reverse (cdr reversed))))
      ;; The irritant names the argument, never its value: a key's value
      ;; given last, a proxy URL holding a password among them, is never
      ;; handed on (M7 slice 3).
      (unless (procedure? proc)
        (assertion-violation 'call-with-http-session
                             "the last argument is a procedure, of the session" 'proc))
      (let ((session (apply make-http-session plist)))
        (dynamic-wind
          (lambda () #f)
          (lambda () (proc session))
          (lambda () (http-session-close session))))))

  ;; http-request : Session Any Any Any ... -> Response
  ;; The call's exchange, by call-state, then the drive: in the drive,
  ;; (curl)'s conditions are compounded by the core, and the drive's own
  ;; refusal by the drive. A call whose body is a producer is streamed,
  ;; drive-stream's whole mode, its final body read whole; any other is M5's
  ;; drive-exchange's.
  (define (http-request session method url . plist)
    (let* ((made (call-state session method url plist #f 'request 'http-request))
           (state (car made))
           (producer (cdr made)))
      (if producer
          (drive-stream (http-session-engine session) state (lambda () (http-session-draw session))
                        producer 'whole #f 'http-request)
          (drive-exchange (http-session-engine session) state
                          (lambda () (http-session-draw session))))))

  ;; call-with-response-port : Session Any Any Any ... -> Any
  ;; Checks that the last argument is a procedure, PROC, then makes the
  ;; call's exchange by call-state, with port-keys, then drives it by
  ;; drive-stream's port mode, which answers PROC's values.
  (define (call-with-response-port session method url . rest)
    (when (null? rest)
      (assertion-violation 'call-with-response-port
                           "a procedure, of the response and its port, after the keys, is required" 'proc))
    (let* ((reversed (reverse rest))
           (proc (car reversed))
           (plist (reverse (cdr reversed))))
      (unless (procedure? proc)
        (assertion-violation 'call-with-response-port
                             "the last argument is a procedure, of the response and its port" 'proc))
      (let ((made (call-state session method url plist #f 'port 'call-with-response-port)))
        (drive-stream (http-session-engine session) (car made)
                      (lambda () (http-session-draw session))
                      (cdr made) 'port proc 'call-with-response-port))))

  ;; call-with-request-group : Session Any ... (Go -> Any) -> Any
  ;; Refuses a critical section first, then its arguments, then its keys;
  ;; then the group, on the session's engine, drawing from its generator,
  ;; each go's call made by call-state.
  (define (call-with-request-group . arguments)
    (require-interrupts 'call-with-request-group)
    (when (or (null? arguments) (null? (cdr arguments)))
      (assertion-violation 'call-with-request-group
                           "a session, then the keys, then a procedure of go, are required"
                           'proc))
    (let* ((session (car arguments))
           (reversed (reverse (cdr arguments)))
           (proc (car reversed))
           (plist (reverse (cdr reversed))))
      (check-session 'call-with-request-group session)
      (unless (procedure? proc)
        (assertion-violation 'call-with-request-group
                             "the last argument is a procedure, of go" 'proc))
      (let ((limit (group-limit 'call-with-request-group plist)))
        (call-with-group (http-session-engine session) limit
                         (lambda () (http-session-draw session))
                         (lambda (method url plist)
                           (car (call-state session method url plist #f 'group 'http-request)))
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
          (assertion-violation 'http-parallel "the specs are a list" (shown-value specs)))
        (let loop ((rest outer) (copied '()))
          (if (null? rest)
              (reverse copied)
              (let ((spec (copy (car rest))))
                (unless (and spec (>= (length spec) 2))
                  (assertion-violation 'http-parallel
                                       "a spec is a list of a method, a URL, then keys"
                                       (shown-value (car rest))))
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
                                 (cons (car (call-state session (car spec) (cadr spec) (cddr spec) #t
                                                        'group 'http-request))
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
