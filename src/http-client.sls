#!r6rs
;;; (http-client): chez-curl's high level (ADR-0007, ADR-0010, ADR-0025; the
;;; M5 plan, sections 3.1 to 3.4). It reaches the low level through (curl)
;;; alone, and holds no native object of its own.
;;;
;;; A session owns one engine, and the defaults its calls share. Every call
;;; takes its session first; there is no default session, and nothing here
;;; starts a thread a caller did not ask for. A call blocks its caller's
;;; thread until its response, which it answers whatever the status: a
;;; status is data. Its timeout-ms bounds the whole call, from its start:
;;; each transfer gets the time left, a redirect's among them. Nothing is
;;; retried, before retries come.
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
   ;; A key it does not take, one given twice, and one with no value are
   ;; refused by name, as &http-request-error; then redirects and
   ;; allow-downgrade, as &http-request-error, not-a-redirect-count and
   ;; not-a-boolean; then each other value, as make-curl-request refuses
   ;; it; and only then is its engine made, so a refusal leaves none.
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
   ;; keys are the session's, redirects and allow-downgrade among them,
   ;; each replacing the session's value, and:
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
   ;;   first, each with a history of ()
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
   ;;   allow-downgrade; each the value as given
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

   ;; &http-exchange: what a call raises carries it, under &condition.
   ;; http-exchange? : Any -> Boolean
   ;; http-exchange-method : &http-exchange -> Any
   ;; http-exchange-url : &http-exchange -> Any
   ;;   the method and the URL as the caller gave them
   ;; http-exchange-history : &http-exchange -> (Listof Response)
   ;; http-exchange-transfers : &http-exchange -> Natural
   ;;   the transfers the call submitted that the engine took
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

  (define (make-http-session . plist)
    (let* ((settings (key-settings 'make-http-session session-keys plist))
           (policy (session-policy settings))
           (defaults (session-defaults settings)))
      (new-http-session (make-curl-engine) defaults (car policy) (cadr policy))))

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
  ;; The clock is read first: the call's bound runs from its start. The
  ;; caller's URL is read once, into a copy, which both the context and the
  ;; request are made from. Every condition raised before the drive, a
  ;; check's, the URL's or the low level's, is compounded with
  ;; &http-exchange, with no transfer made; in the drive, (curl)'s are
  ;; compounded by the core, and the drive's own refusal by the drive.
  (define (http-request session method url . plist)
    (let* ((start (monotonic-ns))
           (given (if (string? url) (string-copy url) url))
           (state (guard (e ((condition? e)
                             (raise (condition e (make-http-exchange method given '() 0)))))
                    (check-session 'http-request session)
                    (let-values (((request redirects allow-downgrade)
                                  (call-request session method given plist)))
                      (make-exchange method given request (curl-request-timeout-ms request)
                                     start redirects allow-downgrade)))))
      (drive-exchange (http-session-engine session) state)))

  (define (http-get session url . plist) (apply http-request session 'get url plist))
  (define (http-head session url . plist) (apply http-request session 'head url plist))
  (define (http-post session url . plist) (apply http-request session 'post url plist))
  (define (http-put session url . plist) (apply http-request session 'put url plist))
  (define (http-patch session url . plist) (apply http-request session 'patch url plist))
  (define (http-delete session url . plist) (apply http-request session 'delete url plist)))
