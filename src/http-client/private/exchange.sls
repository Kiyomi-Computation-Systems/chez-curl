#!r6rs
;;; (http-client private exchange): the functional core of a call, its
;;; exchange (the M5 plan, sections 3.4 and 3.6). It makes no transfer,
;;; reads no clock and draws no number: the shell hands it the time, and it
;;; answers what to do next, as data, so the suite drives it by tables. Only
;;; (curl)'s URL functions, whose answers depend on the loaded libcurl
;;; alone, and its condition types reach out.
;;;
;;; An exchange is one call: its method and URL as the caller gave them,
;;; the request of its step, the first and then each redirect's, its bound,
;;; the call's timeout-ms, from START-NS, the monotonic time it began, the
;;; transfers it has made, its history, the request in flight, its
;;; redirect policy: the most redirects it follows, or #f, whether it
;;; follows one from https to http, and how many it has followed; and its
;;; retry policy, or #f, with the transfers its step has made. A header a
;;; redirect drops is gone from the step's request, which each later one is
;;; made from, so it stays dropped. Each answer is a tagged list:
;;;
;;;   (exchange-submission STATE NOW-NS)
;;;     (submit STATE REQUEST)  submit REQUEST: the step's request, with the
;;;                             time left, rounded up to a whole ms, as its
;;;                             timeout-ms, and, when it has none, as its
;;;                             connect-timeout-ms too, capped at libcurl's
;;;                             300000; as it is, with no bound
;;;     (fail CONDITION)        no time left: &http-timeout; for a retry,
;;;                             which has sent nothing, the failure it
;;;                             repeated; for a retry of a response whose
;;;                             body is #f, a streamed call's hop cancelled
;;;                             at its head, &http-timeout, as with no time
;;;                             left for any request
;;;     (done RESPONSE)         no time left for a retry of a response: the
;;;                             response it repeated, its body read
;;;
;;;   (exchange-step STATE OUTCOME NOW-NS UTC-S DRAW), OUTCOME one of
;;;   (response RESPONSE) or (failed CONDITION) from a transfer's await, or
;;;   (refused CONDITION) from a submit that raised. RESPONSE is the
;;;   transfer's curl-response, or an http-response, which the suite's
;;;   tables build: the core reads its status, version, headers, body and
;;;   timings alike, and gives the answer the URL in flight and the history.
;;;     (done RESPONSE)               the call's answer
;;;     (fail CONDITION)              what the call raises
;;;     (next STATE REQUEST WAIT-MS)  a redirect or a retry: REQUEST,
;;;                                   STATE's step request, goes through
;;;                                   exchange-submission once WAIT-MS ms
;;;                                   pass, a natural: 0 for a redirect;
;;;                                   for a retry, its wait, which ends
;;;                                   before the bound
;;;
;;;   (exchange-steps-past? STATE HEAD NOW-NS UTC-S DRAW), a streamed
;;;   transfer's head, its body and timings #f: whether exchange-step
;;;   answers next for it, so the call steps past it, by exchange-step
;;;   itself (the M6 plan, section 3.6). exchange-raised is what a call
;;;   raises for a failure no rule steps, once its head was handed on.
;;;
;;; Every fail is (condition [HTTP-TIMEOUT] C EXCHANGE), built here: C what
;;; the transfer or the submit raised, when there is one, and EXCHANGE the
;;; call's &http-exchange. A 28 is the call's bound's when the call has one
;;; and either the transfer's connect-timeout-ms is not shorter than its
;;; timeout-ms, the time left, or NOW-NS is at or past the deadline; it then
;;; carries &http-timeout too, unless it ends a retry that sent nothing,
;;; which answers what it repeated (below). Otherwise a 28 is the transfer's own connect
;;; timeout's (the M5 plan, section 3.5). A redirect the rules refuse fails
;;; with (condition REDIRECT-ERROR WHO MESSAGE [URL-ERROR] EXCHANGE).
;;;
;;; A transfer with no connect-timeout-ms still has one: libcurl applies
;;; DEFAULT_CONNECT_TIMEOUT, 300000 ms, during the connect, and uses the
;;; smaller of it and TIMEOUT (7.85.0's lib/connect.c, Curl_timeleft; 8.23.0
;;; defines the same constant). So a call bounded past 300 s could meet a 28
;;; at 300 s that is not its bound's, with no connect timeout of its own to
;;; compare. exchange-submission therefore gives a bounded transfer with
;;; none the connect timeout libcurl would apply, the smaller of the time
;;; left and 300000 ms, written out: the rule above then holds exactly, and
;;; a bounded call never connects for longer than an unbounded one. A
;;; transfer with no bound keeps libcurl's default, and every 28 of its is
;;; its own.
;;;
;;; The rule's clock is NOW-NS, which the shell reads after the await
;;; returns, and the await notices a done token up to about 10 ms late: its
;;; polling sleeps reach 10 ms (the slice's second review measured a median
;;; of 8.8 ms and a maximum of 10.0, over 30 runs). So a transfer's own
;;; connect timeout that fires within that much of the deadline can be read
;;; at or past it, and reported as &http-timeout: 1 of 9 calls did, at a
;;; connect timeout of 393 ms and a bound of 400. (curl) gives no completion
;;; time to read instead, so the window stays, documented.
;;;
;;; The redirect rules (the M5 plan, section 3.4; ADR-0008, amended
;;; 2026-10-27 and 2026-10-28; ADR-0027; ADR-0029), for a response:
;;;
;;;   - a 301, 302, 303, 307 or 308 whose first header named Location, A
;;;     to Z folded, is neither empty nor blank, of SP, HTAB and CR alone,
;;;     is a redirect: 8.5.0 hands an empty one over as a lone CR. Every
;;;     other response is the call's answer;
;;;   - with no bound, #f, a redirect is the answer; once the bound's
;;;     redirects have been followed, the next fails as too-many-redirects,
;;;     before its Location is read, as libcurl's own follow checks it;
;;;   - the Location's Latin-1 string is read as its bytes. One whose first
;;;     byte is # keeps the URL requested, its fragment set by
;;;     curl-url-with-fragment from the bytes after it; any other is
;;;     resolved by curl-url-resolve against the URL requested, its bytes
;;;     encoded first as a fragment's are (ADR-0029, amended), and one
;;;     whose bytes hold no # takes that URL's own fragment, as curl-url-part
;;;     gives it, by curl-url-with-fragment (RFC 9110, section 10.2.2). A
;;;     refusal of either, or a scheme other than http or https, fails as
;;;     bad-location;
;;;   - from https to http fails as insecure-redirect, unless the call
;;;     allows a downgrade;
;;;   - a step that streams its body from a producer counted as called, by
;;;     exchange-called?, fails a redirect that keeps the body as
;;;     body-not-replayable, before any other refusal (ADR-0032, decision 3,
;;;     amended);
;;;   - a 301 or a 302 makes a post a get, without its body; a 303 makes
;;;     every method but head a get, without its body; every other method,
;;;     and a 307 and a 308, keep the method and the body, a streamed
;;;     body's body-length with it. Without the body
;;;     go the headers named Content-*, Digest, Last-Modified and Expect, A
;;;     to Z folded: a 100-continue asks for a body there is none of (RFC
;;;     9110, section 10.1.1);
;;;   - another origin, by scheme, host A to Z folded, zone ID and port,
;;;     each by curl-url-part, drops Authorization and Cookie, and another
;;;     host, A to Z folded, or another zone ID, drops Host too: libcurl
;;;     gives an IPv6 host without its zone, so two zones of one address are
;;;     told apart by the zone alone. No request holds a Proxy-Authorization
;;;     header: the low level refuses one (ADR-0037, decision 4), and a
;;;     proxy's credentials, its URL's, go to every hop with it;
;;;   - the next request is made by make-curl-request from the new URL,
;;;     every other key read from the step's request, whose timeout-ms is
;;;     the call's bound: exchange-submission gives it the time left;
;;;   - the response joins the history, oldest first, with a history of
;;;     its own of (); the answer, and a redirect error's response, carry
;;;     the history before them.
;;;
;;; The retry rules (the M5 plan, section 3.5; ADR-0026, amended
;;; 2026-10-28; ADR-0022, amended 2026-10-28), with a policy. A policy's
;;; statuses are 400 to 599, so no status both retries and redirects. A
;;; step is one URL: its attempts count the transfers
;;; it has made, and a redirect starts them again, so a call makes at most
;;; attempts x (redirects + 1) transfers of its own. While the step has made
;;; fewer than the policy's attempts, and the wait would end before the
;;; deadline, strictly, these are retried, by (next STATE REQUEST WAIT-MS),
;;; REQUEST the step's again:
;;;
;;;   - a failure from the await, perform-failed, that carries a CONNECT's
;;;     status, curl-transfer-error-connect-code, a proxy's refusal of the
;;;     tunnel: as a response with that status is, when the policy's
;;;     statuses hold it, for a method in its methods, whatever its code and
;;;     request size, which move with the version: 56 on 7.85.0 and 8.5.0,
;;;     7 later, and the CONNECT's bytes on 7.85.0 alone (ADR-0026 and
;;;     ADR-0037, amended 2026-11-03). Its wait is the backoff's: a proxy's
;;;     headers are not the response's;
;;;   - any other failure from the await, perform-failed, of the connect,
;;;     send-receive or timeout class, that is not the bound's 28, with a
;;;     request size of 0, nothing sent, for any method; above 0, or #f,
;;;     unknown (8.7.0 and 8.7.1), for a method in the policy's methods
;;;     alone. The method is the step's request's, which a redirect may have
;;;     made a get;
;;;   - a response whose status is in the policy's statuses, for a method
;;;     in its methods.
;;;
;;; The wait is backoff-wait's: backoff-ms, doubled for each retry of the
;;; step after the first, capped at max-backoff-ms; with jitter, DRAW times
;;; that, rounded down to a whole ms. A retried status's first Retry-After,
;;; A to Z folded, sets the wait in place of the backoff, untouched by
;;; jitter: delta-seconds, or an HTTP-date in any of RFC 9110's three forms,
;;; measured against UTC-S, 0 for one past. One that cannot be read is
;;; absent, and the backoff waits; one longer than max-backoff-ms, or one
;;; that would end at or past the deadline, is no retry. A Retry-After of
;;; 0, or a date at or before UTC-S, waits 0, and so may a backoff with
;;; jitter: the step's attempts bound how often such a retry repeats.
;;;
;;; A retry that runs out of time having sent nothing answers what it
;;; retried (decided by the maintainer, 2026-10-28, and narrowed after the
;;; slice's second review): the state keeps the step's last retried
;;; outcome, and when the bound passes before the retry sends anything,
;;; either exchange-submission finding no time left for the retried
;;; request or that request's transfer failing with the bound's 28 and a
;;; request size of 0, the call answers the last response the retry
;;; repeated, or raises the last failure with its &http-exchange, and no
;;; &http-timeout. But a streamed call whose retry runs out so after its
;;; hop was cancelled at its head, the retried response's body #f, at its
;;; submission or at the bound's 28 with nothing sent, fails with
;;; &http-timeout, as with no time left for any request (decided by the
;;; maintainer, 2026-11-01). A bound's 28 whose request size is above 0,
;;; or #f, unknown, means the retry may have reached the server: it raises
;;; with &http-timeout, so the last transfer's own "nothing sent" is never
;;; claimed for it. A raised failure's size speaks for its own transfer
;;; alone: an earlier transfer of the step, retried for a method in the
;;; policy's methods, may have sent its request, which &http-exchange's
;;; transfer count above 1 says may be so (the slice's third review). A
;;; redirect clears the kept outcome, so a later transfer's bound is the
;;; plain &http-timeout; a retried transfer that ends any other way goes
;;; through the rules. Not retried: a step that streams its body from a
;;; producer counted as called (ADR-0032, decision 3, amended); any
;;; other class, a code no class names, any reason but perform-failed, a
;;; refused submit, the engine's stop among them, a redirect the rules
;;; refuse, and the bound's 28. What is not retried is as with no policy: a
;;; failure fails, and a response is done or redirects. A retried response,
;;; or failure, joins no history, and the call's context counts its
;;; transfer.
(library (http-client private exchange)
  (export make-exchange exchange? exchange-method exchange-url exchange-request
          exchange-bound exchange-start-ns exchange-transfers exchange-history
          exchange-flight exchange-redirects exchange-allow-downgrade exchange-followed
          exchange-policy exchange-attempts exchange-retried exchange-called?
          exchange-mark-called exchange-deadline exchange-condition exchange-live-condition
          exchange-submission exchange-step exchange-steps-past? exchange-raised
          retry-after-ms http-date-seconds backoff-wait
          make-http-response http-response? http-response-status http-response-http-version
          http-response-url http-response-headers http-response-body http-response-timings
          http-response-history http-response-header http-response-text http-response-with)
  (import (curl)
          (rnrs)
          (http-client private conditions)
          (only (http-client private call) ascii-ci=? http-retry? http-retry-attempts
                http-retry-backoff-ms http-retry-max-backoff-ms http-retry-jitter
                http-retry-statuses http-retry-methods))

  ;; --- the response ----------------------------------------------------------------

  ;; make-http-response : Integer (U Symbol Integer #f) String
  ;;                      (Listof (Pairof String String)) (U Bytevector #f)
  ;;                      (U (Listof (Pairof Symbol Natural)) #f) (Listof Response) -> Response
  ;; http-response? : Any -> Boolean
  ;; http-response-status : Response -> Integer
  ;; http-response-http-version : Response -> (U 'http/1.0 'http/1.1 'http/2 'http/3 Integer #f)
  ;; http-response-url : Response -> String
  ;; http-response-headers : Response -> (Listof (Pairof String String))
  ;; http-response-body : Response -> (U Bytevector #f)
  ;;   #f for a head's response: call-with-response-port's, whose body
  ;;   streams through its port, and a hop a call cancelled at its head
  ;; http-response-timings : Response -> (U (Listof (Pairof Symbol Natural)) #f)
  ;;   #f where the body is #f: the transfer had not ended
  ;; http-response-history : Response -> (Listof Response)
  (define-record-type (http-response make-http-response http-response?)
    (fields (immutable status unchecked-http-response-status)
            (immutable http-version unchecked-http-response-http-version)
            (immutable url unchecked-http-response-url)
            (immutable headers unchecked-http-response-headers)
            (immutable body unchecked-http-response-body)
            (immutable timings unchecked-http-response-timings)
            (immutable history unchecked-http-response-history))
    (sealed #t))

  ;; Each accessor checks its argument first: anything else is an assertion
  ;; violation from the accessor, naming it by its kind, shown-value's,
  ;; never printed, as Chez's own check printed it (ADR-0036, amended
  ;; 2026-11-03).
  (define http-response-status
    (checked-accessor 'http-response-status http-response? "a response" unchecked-http-response-status))
  (define http-response-http-version
    (checked-accessor 'http-response-http-version http-response? "a response" unchecked-http-response-http-version))
  (define http-response-url
    (checked-accessor 'http-response-url http-response? "a response" unchecked-http-response-url))
  (define http-response-headers
    (checked-accessor 'http-response-headers http-response? "a response" unchecked-http-response-headers))
  (define http-response-body
    (checked-accessor 'http-response-body http-response? "a response" unchecked-http-response-body))
  (define http-response-timings
    (checked-accessor 'http-response-timings http-response? "a response" unchecked-http-response-timings))
  (define http-response-history
    (checked-accessor 'http-response-history http-response? "a response" unchecked-http-response-history))

  ;; http-response-header : Response String -> (U String #f)
  ;; The value of RESPONSE's first header named NAME, A to Z folded alone,
  ;; or #f. A copy of NAME is what is compared.
  (define (http-response-header response name)
    (unless (http-response? response)
      (assertion-violation 'http-response-header "not a response" (shown-value response)))
    (unless (string? name)
      (assertion-violation 'http-response-header "a header's name is a string" (shown-value name)))
    (let* ((copy (string-copy name))
           (hit (find (lambda (header) (ascii-ci=? (car header) copy))
                      (http-response-headers response))))
      (and hit (cdr hit))))

  ;; http-response-text : Response -> String
  ;; RESPONSE's body decoded as UTF-8 by utf8->string: a malformed sequence
  ;; read as U+FFFD, and a leading byte-order mark dropped. It reads no
  ;; charset. A response whose body is #f, a head's, is an assertion
  ;; violation: its body streamed, or was never read (the M6 plan, section
  ;; 3.1).
  (define (http-response-text response)
    (unless (http-response? response)
      (assertion-violation 'http-response-text "not a response" (shown-value response)))
    (let ((body (http-response-body response)))
      (unless (bytevector? body)
        (assertion-violation 'http-response-text
          "the response's body was not read: it streams through call-with-response-port's port, or its hop was cancelled at its head"
          'response))
      (utf8->string body)))

  ;; http-response-with : Response (U Bytevector #f) (U (Listof (Pairof Symbol Natural)) #f)
  ;;                      -> Response
  ;; R with BODY and TIMINGS in place of its own: a head's response once its
  ;; body has been read whole.
  (define (http-response-with r body timings)
    (make-http-response (http-response-status r) (http-response-http-version r)
                        (http-response-url r) (http-response-headers r) body timings
                        (http-response-history r)))

  ;; without-history : Response -> Response
  ;; R, with a history of (), as the history holds it.
  (define (without-history r)
    (make-http-response (http-response-status r) (http-response-http-version r)
                        (http-response-url r) (http-response-headers r) (http-response-body r)
                        (http-response-timings r) '()))

  ;; --- the exchange ----------------------------------------------------------------

  ;; An exchange's state, immutable: each step answers a new one.
  ;; exchange? : Any -> Boolean
  ;; exchange-method : State -> Any
  ;; exchange-url : State -> Any
  ;; exchange-request : State -> Request
  ;;   the step's request: the call's first, then each redirect's, with the
  ;;   call's timeout-ms, before exchange-submission gives it the time left
  ;; exchange-bound : State -> (U Positive-Integer #f)
  ;; exchange-start-ns : State -> Integer
  ;; exchange-transfers : State -> Natural
  ;; exchange-history : State -> (Listof Response)
  ;; exchange-flight : State -> Request
  ;;   the request in flight, as exchange-submission put it there
  ;; exchange-redirects : State -> (U Natural #f)
  ;; exchange-allow-downgrade : State -> Boolean
  ;; exchange-followed : State -> Natural
  ;;   the redirects the call has followed
  ;; exchange-policy : State -> (U Retry #f)
  ;;   the call's retry policy, or #f for none
  ;; exchange-attempts : State -> Natural
  ;;   the transfers the step has made: 0 for a call's first request and
  ;;   for each redirect's, one more for each response or failure from an
  ;;   await
  ;; exchange-retried : State -> (U (List 'response Response) (List 'failed Condition) #f)
  ;;   the step's last outcome a retry repeated, the response as the call
  ;;   would answer it or the transfer's condition as raised, which the
  ;;   call answers or raises if its bound passes before the retry ends;
  ;;   #f before any retry of the step, and again after a redirect
  ;; exchange-called? : State -> Boolean
  ;;   whether the call's producer counts as called: the drive called it,
  ;;   or libcurl had asked for the body by a head, by the head's bit
  ;;   (ADR-0032, decision 3, amended). A step whose request streams its
  ;;   body from that producer is then never sent again: no retry takes it,
  ;;   and a redirect that keeps the body raises body-not-replayable. It
  ;;   stays set for the call: the producer is the call's one
  (define-record-type (exchange make-exchange-state exchange?)
    (fields (immutable method exchange-method)
            (immutable url exchange-url)
            (immutable request exchange-request)
            (immutable bound exchange-bound)
            (immutable start-ns exchange-start-ns)
            (immutable transfers exchange-transfers)
            (immutable history exchange-history)
            (immutable flight exchange-flight)
            (immutable redirects exchange-redirects)
            (immutable allow-downgrade exchange-allow-downgrade)
            (immutable followed exchange-followed)
            (immutable policy exchange-policy)
            (immutable attempts exchange-attempts)
            (immutable retried exchange-retried)
            (immutable called exchange-called?))
    (sealed #t)
    ;; Opaque: a call's state holds its requests, and the drive hands a
    ;; core step that holds one to an assertion as its irritant (the review
    ;; of M7 slice 2).
    (opaque #t))

  ;; ns? : Any -> Boolean
  (define (ns? x) (and (integer? x) (exact? x)))

  ;; make-exchange : Any Any Request (U Positive-Integer #f) Integer (U Natural #f) Boolean
  ;;                 [(U Retry #f)] -> State
  ;; A call of METHOD on URL, as the caller gave them, whose first request
  ;; is REQUEST, bounded by TIMEOUT-MS from START-NS, or unbounded for #f,
  ;; that follows REDIRECTS redirects at most, or none for #f, one from
  ;; https to http when ALLOW-DOWNGRADE, and retries by RETRY, a policy, or
  ;; none for #f, the default; no transfer made, no history, none followed,
  ;; no attempt, and REQUEST in flight.
  (define make-exchange
    (case-lambda
      ((method url request timeout-ms start-ns redirects allow-downgrade)
       (make-exchange method url request timeout-ms start-ns redirects allow-downgrade #f))
      ((method url request timeout-ms start-ns redirects allow-downgrade retry)
       (unless (curl-request? request)
         (assertion-violation 'make-exchange "not a request" request))
       (unless (or (not timeout-ms)
                   (and (integer? timeout-ms) (exact? timeout-ms) (positive? timeout-ms)))
         (assertion-violation 'make-exchange "a bound is a positive exact integer of ms, or #f"
                              timeout-ms))
       (unless (ns? start-ns)
         (assertion-violation 'make-exchange "a time is an exact integer of ns" start-ns))
       (unless (or (not redirects) (and (integer? redirects) (exact? redirects) (>= redirects 0)))
         (assertion-violation 'make-exchange "redirects is an exact natural, or #f" redirects))
       (unless (boolean? allow-downgrade)
         (assertion-violation 'make-exchange "allow-downgrade is a boolean" allow-downgrade))
       (unless (or (not retry) (http-retry? retry))
         (assertion-violation 'make-exchange "retry is a policy, or #f" retry))
       (make-exchange-state method url request timeout-ms start-ns 0 '() request redirects
                            allow-downgrade 0 retry 0 #f #f))))

  ;; remade : State Request Natural (Listof Response) Request Natural Natural
  ;;          (U (List Symbol Any) #f) -> State
  ;; STATE with its step's request, transfers, history, request in flight,
  ;; redirects followed, the step's attempts and its retried outcome
  ;; replaced; whether its producer counts as called kept.
  (define (remade state request transfers history flight followed attempts retried)
    (make-exchange-state (exchange-method state) (exchange-url state) request
                         (exchange-bound state) (exchange-start-ns state) transfers history
                         flight (exchange-redirects state) (exchange-allow-downgrade state)
                         followed (exchange-policy state) attempts retried
                         (exchange-called? state)))

  ;; exchange-mark-called : State -> State
  ;; STATE, its producer counted as called (ADR-0032, decision 3, amended):
  ;; the shell marks it once it has called the producer, or a head said
  ;; libcurl had asked for the body. A state whose producer counts as
  ;; called already is answered as it is.
  (define (exchange-mark-called state)
    (check-state 'exchange-mark-called state)
    (if (exchange-called? state)
        state
        (make-exchange-state (exchange-method state) (exchange-url state) (exchange-request state)
                             (exchange-bound state) (exchange-start-ns state)
                             (exchange-transfers state) (exchange-history state)
                             (exchange-flight state) (exchange-redirects state)
                             (exchange-allow-downgrade state) (exchange-followed state)
                             (exchange-policy state) (exchange-attempts state)
                             (exchange-retried state) #t)))

  ;; spent? : State -> Boolean
  ;; Whether STATE's step request streams its body from the call's
  ;; producer, and that producer counts as called: a step that must never
  ;; be sent again (ADR-0032, decision 3, amended).
  (define (spent? state)
    (and (exchange-called? state) (eq? (curl-request-body (exchange-request state)) 'stream)))

  ;; exchange-deadline : State -> (U Integer #f)
  ;; The monotonic time, in ns, at which STATE's bound passes, or #f.
  (define (exchange-deadline state)
    (let ((bound (exchange-bound state)))
      (and bound (+ (exchange-start-ns state) (* bound 1000000)))))

  ;; exchange-condition : State -> &http-exchange
  ;; STATE's context, as a call compounds it onto what it raises.
  (define (exchange-condition state)
    (make-http-exchange (exchange-method state) (exchange-url state) (exchange-history state)
                        (exchange-transfers state)))

  ;; exchange-live-condition : State -> &http-exchange
  ;; STATE's context with the transfer in flight counted: what a streamed
  ;; call compounds onto a refusal of its own, a producer's bad answer, made
  ;; while that transfer is live, the engine having taken it.
  (define (exchange-live-condition state)
    (check-state 'exchange-live-condition state)
    (exchange-condition (counted state)))

  ;; with-flight : State Request -> State
  (define (with-flight state request)
    (remade state (exchange-request state) (exchange-transfers state) (exchange-history state)
            request (exchange-followed state) (exchange-attempts state) (exchange-retried state)))

  ;; counted : State -> State
  ;; STATE, with one more transfer made, by the call and by its step.
  (define (counted state)
    (remade state (exchange-request state) (+ (exchange-transfers state) 1)
            (exchange-history state) (exchange-flight state) (exchange-followed state)
            (+ (exchange-attempts state) 1) (exchange-retried state)))

  (define (check-state who state)
    (unless (exchange? state) (assertion-violation who "not an exchange" state)))

  (define (check-ns who now-ns)
    (unless (ns? now-ns) (assertion-violation who "a time is an exact integer of ns" now-ns)))

  ;; default-connect-timeout-ms : Positive-Integer
  ;; libcurl's DEFAULT_CONNECT_TIMEOUT, which it applies to a connect when
  ;; CONNECTTIMEOUT is unset: 300000 on 7.85.0 and 8.23.0 alike.
  (define default-connect-timeout-ms 300000)

  ;; ran-out : State -> (U (List 'done Response) (List 'fail Condition))
  ;; What a call answers when its bound passes before a retry of its step
  ;; sends anything: the outcome the retry repeated, as with no policy. Its
  ;; response, as the call would have answered it then; or its failure,
  ;; compounded with STATE's &http-exchange, which counts every transfer,
  ;; and no &http-timeout. A response whose body is #f, a streamed call's
  ;; hop cancelled at its head, is no answer: the call fails with its
  ;; &http-timeout instead, as with no time left for any request (decided
  ;; by the maintainer, 2026-11-01).
  (define (ran-out state)
    (let ((last (exchange-retried state)))
      (cond ((and (eq? (car last) 'response) (not (http-response-body (cadr last))))
             (list 'fail (condition (make-http-timeout (exchange-bound state))
                                    (exchange-condition state))))
            ((eq? (car last) 'response) (list 'done (cadr last)))
            (else (list 'fail (condition (cadr last) (exchange-condition state)))))))

  ;; exchange-submission : State Integer
  ;;                       -> (U (List 'submit State Request) (List 'fail Condition)
  ;;                             (List 'done Response))
  ;; What to submit at NOW-NS, a monotonic time in ns: the step's request,
  ;; its timeout-ms the time left before the deadline, rounded up to a whole
  ;; ms, and, when it has no connect-timeout-ms, the one libcurl would
  ;; apply, written out: the smaller of the time left and 300000 ms; and the
  ;; state with it in flight. With no bound, the request as it is. With no
  ;; time left, the call's &http-timeout, compounded with its
  ;; &http-exchange; but for a retry, ran-out's answer, the outcome the
  ;; retry repeated.
  (define (exchange-submission state now-ns)
    (check-state 'exchange-submission state)
    (check-ns 'exchange-submission now-ns)
    (let ((request (exchange-request state))
          (deadline (exchange-deadline state)))
      (if (not deadline)
          (list 'submit (with-flight state request) request)
          (let ((left-ns (- deadline now-ns)))
            (cond
             ((and (<= left-ns 0) (exchange-retried state)) (ran-out state))
             ((<= left-ns 0)
              (list 'fail (condition (make-http-timeout (exchange-bound state))
                                     (exchange-condition state))))
             (else
                (let* ((left (div (+ left-ns 999999) 1000000))
                       (sent (if (curl-request-connect-timeout-ms request)
                                 (curl-request-with request 'timeout-ms left)
                                 (curl-request-with request 'timeout-ms left
                                                    'connect-timeout-ms
                                                    (min left default-connect-timeout-ms)))))
                  (list 'submit (with-flight state sent) sent))))))))

  ;; bound-timeout? : State Condition Integer -> Boolean
  ;; Whether C, a transfer's failure at NOW-NS, is a 28 that is the call's
  ;; bound's: the call has a bound, and the transfer in flight had a
  ;; connect-timeout-ms not shorter than its timeout-ms, or NOW-NS is at or
  ;; past the deadline. Under a bound, every request exchange-submission
  ;; puts in flight carries both, so no path the drive takes meets one
  ;; without: only a table's state that no submission made holds its step's
  ;; request in flight, and there a missing one is no evidence, so only the
  ;; deadline decides. NOW-NS is read after the await, up to about 10 ms
  ;; after the transfer ended (the header): a connect timeout of the
  ;; transfer's own that fires that close to the deadline reads as the
  ;; bound's.
  (define (bound-timeout? state c now-ns)
    (let ((deadline (exchange-deadline state))
          (flight (exchange-flight state)))
      (and (curl-timeout? c)
           deadline
           (or (let ((connect (curl-request-connect-timeout-ms flight))
                     (timeout (curl-request-timeout-ms flight)))
                 (and connect timeout (>= connect timeout)))
               (>= now-ns deadline)))))

  ;; exchange-raised : State Condition Integer -> Condition
  ;; What a call raises for C, the failure of its transfer in flight, read
  ;; at NOW-NS once the call has handed that transfer's head on, to
  ;; call-with-response-port's procedure, so no rule steps it and no retry
  ;; takes it: C compounded with STATE's context, that transfer counted,
  ;; and with &http-timeout first when C is a 28 that is the call's bound's,
  ;; by bound-timeout?'s rule (the M6 plan, section 3.6).
  (define (exchange-raised state c now-ns)
    (check-state 'exchange-raised state)
    (check-ns 'exchange-raised now-ns)
    (unless (condition? c)
      (assertion-violation 'exchange-raised "a transfer's failure is a condition" c))
    (let ((counted (counted state)))
      (if (bound-timeout? counted c now-ns)
          (condition (make-http-timeout (exchange-bound counted)) c (exchange-condition counted))
          (condition c (exchange-condition counted)))))

  ;; response-of : State (U Curl-Response Response) -> Response
  ;; The call's response: R's status, version, headers, body and timings,
  ;; the URL of the request in flight, and STATE's history. R is a
  ;; transfer's curl-response, or an http-response a table built.
  (define (response-of state r)
    (let ((url (curl-request-url (exchange-flight state)))
          (history (exchange-history state)))
      (if (curl-response? r)
          (make-http-response (curl-response-status r) (curl-response-http-version r) url
                              (curl-response-headers r) (curl-response-body r)
                              (curl-response-timings r) history)
          (make-http-response (http-response-status r) (http-response-http-version r) url
                              (http-response-headers r) (http-response-body r)
                              (http-response-timings r) history))))

  ;; --- redirects -------------------------------------------------------------------

  ;; redirect-statuses : (Listof Integer)
  ;; The statuses a Location makes a redirect of (RFC 9110, section 15.4):
  ;; 300, 304, 305 and 306 are answered.
  (define redirect-statuses '(301 302 303 307 308))

  ;; first-header : (Listof (Pairof String String)) String -> (U String #f)
  ;; The value of the first of HEADERS named NAME, A to Z folded alone, or
  ;; #f.
  (define (first-header headers name)
    (let ((hit (find (lambda (header) (ascii-ci=? (car header) name)) headers)))
      (and hit (cdr hit))))

  ;; location-of : (Listof (Pairof String String)) -> (U String #f)
  ;; The value of the first of HEADERS named Location, A to Z folded alone,
  ;; or #f.
  (define (location-of headers) (first-header headers "location"))

  ;; blank? : String -> Boolean
  ;; Whether S is empty, or made of SP, HTAB and CR alone: libcurl trims a
  ;; value's ends, and 8.5.0 hands an empty one over as a lone CR.
  (define (blank? s)
    (let loop ((i 0))
      (or (= i (string-length s))
          (and (memv (string-ref s i) '(#\space #\tab #\return))
               (loop (+ i 1))))))

  ;; header-bytes : String -> Bytevector
  ;; S, a header's Latin-1 string, as its bytes: each char's code, one byte.
  ;; A char above U+00FF, which no header from libcurl holds, is an
  ;; assertion violation.
  (define (header-bytes s)
    (let* ((n (string-length s))
           (bytes (make-bytevector n 0)))
      (let loop ((i 0))
        (if (= i n)
            bytes
            (let ((c (char->integer (string-ref s i))))
              (unless (<= c #xFF)
                (assertion-violation 'exchange-step
                                     "a header's value holds a char above U+00FF, which no byte is"
                                     s))
              (bytevector-u8-set! bytes i c)
              (loop (+ i 1)))))))

  ;; hash-byte : Natural
  ;; #, 0x23.
  (define hash-byte #x23)

  ;; holds-byte? : Bytevector Natural -> Boolean
  (define (holds-byte? bytes b)
    (let loop ((i 0))
      (and (< i (bytevector-length bytes))
           (or (= (bytevector-u8-ref bytes i) b) (loop (+ i 1))))))

  ;; bytes-from : Bytevector Natural -> Bytevector
  ;; BYTES from index START to the end, fresh.
  (define (bytes-from bytes start)
    (let* ((n (- (bytevector-length bytes) start))
           (tail (make-bytevector n 0)))
      (bytevector-copy! bytes start tail 0 n)
      tail))

  ;; redirect-url : String Bytevector -> String
  ;; The URL a Location's BYTES name from REQUESTED, the URL the transfer
  ;; requested. BYTES that begin with # keep REQUESTED, with the fragment
  ;; the bytes after it, which curl-url-with-fragment encodes: curl_url's
  ;; own resolution of a lone # drops the last segment and the query on
  ;; 7.85.0, 8.5.0 and 8.7.1, and moves its hex case on 8.20.0 and 8.23.0
  ;; (ADR-0029). Any others are resolved by curl-url-resolve, which encodes
  ;; them first, as it encodes a fragment (ADR-0029, amended); then, when
  ;; they hold no #, the answer takes REQUESTED's own fragment, as a string,
  ;; which comes back as REQUESTED holds it. A refusal raises
  ;; &curl-url-error.
  (define (redirect-url requested bytes)
    (if (and (> (bytevector-length bytes) 0) (= (bytevector-u8-ref bytes 0) hash-byte))
        (curl-url-with-fragment requested (bytes-from bytes 1))
        (let ((resolved (curl-url-resolve requested bytes)))
          (if (holds-byte? bytes hash-byte)
              resolved
              (let ((own (curl-url-part requested 'fragment)))
                (if own (curl-url-with-fragment resolved own) resolved))))))

  ;; body-dropped? : Integer Symbol -> Boolean
  ;; Whether a STATUS redirect sends METHOD's next request as a get without
  ;; its body (RFC 9110, section 15.4): a post through a 301 or a 302, and
  ;; every method but head through a 303.
  (define (body-dropped? status method)
    (case status
      ((301 302) (eq? method 'post))
      ((303) (not (eq? method 'head)))
      (else #f)))

  ;; starts-with? : String String -> Boolean
  ;; Whether NAME begins with PREFIX, A to Z folded.
  (define (starts-with? name prefix)
    (let ((k (string-length prefix)))
      (and (>= (string-length name) k) (ascii-ci=? (substring name 0 k) prefix))))

  ;; body-header? : String -> Boolean
  ;; Whether a header named NAME is the body's (RFC 9110, section 15.4,
  ;; item 5): Content-*, Digest and Last-Modified, A to Z folded; and
  ;; Expect, whose 100-continue a client must not send with no body (RFC
  ;; 9110, section 10.1.1).
  (define (body-header? name)
    (or (starts-with? name "Content-") (ascii-ci=? name "Digest")
        (ascii-ci=? name "Last-Modified") (ascii-ci=? name "Expect")))

  ;; credential-header? : String -> Boolean
  ;; Whether a header named NAME is one another origin never gets:
  ;; Authorization and Cookie, A to Z folded. A Proxy-Authorization header
  ;; was one too, until the low level refused every one (ADR-0037, decision
  ;; 4): no request this reads holds one.
  (define (credential-header? name)
    (exists (lambda (credential) (ascii-ci=? name credential))
            '("Authorization" "Cookie")))

  ;; same-host? : (U String #f) (U String #f) -> Boolean
  ;; Whether two hosts are one, A to Z folded.
  (define (same-host? a b)
    (if (and a b) (ascii-ci=? a b) (eq? a b)))

  ;; refuse-redirect : State Symbol Response String (U Condition #f) -> (List 'fail Condition)
  ;; The call's failure for a redirect it does not follow: REASON, the
  ;; RESPONSE that named it, its LOCATION, URL-ERROR when a URL function
  ;; refused it, and STATE's context.
  (define (refuse-redirect state reason response location url-error)
    (list 'fail
          (apply condition
                 (make-http-redirect-error reason response location)
                 (make-who-condition 'http-request)
                 (make-message-condition
                  (case reason
                    ((too-many-redirects) "the call has followed as many redirects as it may")
                    ((bad-location) "the Location names no http or https URL the call can follow")
                    ((body-not-replayable)
                     "a redirect whose next request keeps a streamed body its producer has given, or libcurl asked for: it is sent at most once")
                    (else "a redirect from https to http, which the call does not allow")))
                 (append (if url-error (list url-error) '())
                         (list (exchange-condition state))))))

  ;; next-request : Request String Integer Boolean Boolean -> Request
  ;; The request a STATUS redirect to URL makes from LAST, the step's: its
  ;; method, its body and its body's headers kept or dropped by
  ;; body-dropped?, a streamed body's body-length with it; its credential
  ;; headers dropped when ACROSS, to another origin; its Host when
  ;; ANOTHER-HOST; every other key LAST's, its stream-buffer among them (the
  ;; M6 plan, section 3.6), and its http-version (the M7 plan, section
  ;; 3.1): a hop to https:// by prior knowledge is refused as it is
  ;; submitted, prior-knowledge-over-https; and its credentials within one
  ;; origin, dropped when ACROSS, as the credential headers are (ADR-0036;
  ;; the M7 plan, section 3.1): a hop within the origin whose URL holds a
  ;; user or a password is refused as it is submitted,
  ;; credentials-beside-userinfo; and its proxy, its proxy CA file and its
  ;; proxy verification, to every hop, another origin's too: a proxy's
  ;; credentials are the proxy's, not the origin's (ADR-0037, amended
  ;; 2026-11-03). A hop to https:// through an https:// proxy where TLS
  ;; inside TLS stalls is refused as it is submitted, proxy-tls-in-tls.
  (define (next-request last url status across another-host)
    (let* ((method (curl-request-method last))
           (dropped (body-dropped? status method))
           (headers (filter (lambda (header)
                              (let ((name (car header)))
                                (not (or (and dropped (body-header? name))
                                         (and across (credential-header? name))
                                         (and another-host (ascii-ci=? name "Host"))))))
                            (curl-request-headers last))))
      (make-curl-request url
                         'method (if dropped 'get method)
                         'headers headers
                         'body (if dropped #f (curl-request-body last))
                         'body-length (if dropped #f (curl-request-body-length last))
                         'stream-buffer (curl-request-stream-buffer last)
                         'user-agent (curl-request-user-agent last)
                         'timeout-ms (curl-request-timeout-ms last)
                         'connect-timeout-ms (curl-request-connect-timeout-ms last)
                         'body-limit (curl-request-body-limit last)
                         'ca-file (curl-request-ca-file last)
                         'verify (curl-request-verify last)
                         'proxy (curl-request-proxy last)
                         'http-version (curl-request-http-version last)
                         'credentials (if across #f (curl-request-credentials last))
                         'proxy-ca-file (curl-request-proxy-ca-file last)
                         'proxy-verify (curl-request-proxy-verify last))))

  ;; follow : State Response Integer String
  ;;          -> (U (List 'fail Condition) (List 'next State Request 0))
  ;; RESPONSE, a STATUS redirect to LOCATION the bound lets the call follow:
  ;; its URL, refused as bad-location; the downgrade, refused as
  ;; insecure-redirect unless allowed; then the next request, the history
  ;; and the count.
  (define (follow state response status location)
    (let* ((requested (curl-request-url (exchange-flight state)))
           (target (guard (e ((curl-url-error? e) (list 'refused e)))
                     (let ((url (redirect-url requested (header-bytes location))))
                       (list 'url url (curl-url-part url 'scheme))))))
      (cond ((eq? (car target) 'refused)
             (refuse-redirect state 'bad-location response location (cadr target)))
            ((not (member (caddr target) '("http" "https")))
             (refuse-redirect state 'bad-location response location #f))
            (else
             (let* ((url (cadr target))
                    (scheme (caddr target))
                    (parts (guard (e ((curl-url-error? e) (list 'refused e)))
                             (list 'parts (curl-url-part url 'host) (curl-url-part url 'port)
                                   (curl-url-part url 'zoneid)))))
               (cond ((eq? (car parts) 'refused)
                      (refuse-redirect state 'bad-location response location (cadr parts)))
                     ((and (string=? scheme "http")
                           (equal? (curl-url-part requested 'scheme) "https")
                           (not (exchange-allow-downgrade state)))
                      (refuse-redirect state 'insecure-redirect response location #f))
                     (else
                      (let* ((another-host (or (not (same-host? (cadr parts)
                                                                (curl-url-part requested 'host)))
                                               (not (equal? (cadddr parts)
                                                            (curl-url-part requested 'zoneid)))))
                             (across (or another-host
                                         (not (equal? scheme (curl-url-part requested 'scheme)))
                                         (not (eqv? (caddr parts)
                                                    (curl-url-part requested 'port)))))
                             (request (next-request (exchange-request state) url status across
                                                    another-host))
                             (next (remade state request (exchange-transfers state)
                                           (append (exchange-history state)
                                                   (list (without-history response)))
                                           request (+ (exchange-followed state) 1) 0 #f)))
                        (list 'next next request 0)))))))))

  ;; redirected : State Response
  ;;              -> (U (List 'done Response) (List 'fail Condition) (List 'next State Request 0))
  ;; What RESPONSE, the call's response with STATE's history, makes of the
  ;; call: done, unless it is a redirect; for a redirect, done with no
  ;; bound; then, first, body-not-replayable, when the step streams its body
  ;; from a producer that counts as called and the redirect keeps the body,
  ;; by body-dropped?: a 307 or 308, and a 301 or 302 of every method but
  ;; post (ADR-0032, decision 3, amended); then too-many-redirects once the
  ;; bound's are followed; else follow's answer.
  (define (redirected state response)
    (let ((status (http-response-status response))
          (location (location-of (http-response-headers response)))
          (bound (exchange-redirects state)))
      (cond ((not (memv status redirect-statuses)) (list 'done response))
            ((or (not location) (blank? location)) (list 'done response))
            ((not bound) (list 'done response))
            ((and (spent? state) (not (body-dropped? status (step-method state))))
             (refuse-redirect state 'body-not-replayable response location #f))
            ((>= (exchange-followed state) bound)
             (refuse-redirect state 'too-many-redirects response location #f))
            (else (follow state response status location)))))

  ;; --- retries (ADR-0026; the M5 plan, section 3.5) ---------------------------------

  ;; backoff-wait : Retry Positive-Integer Real -> Natural
  ;; The wait, in ms, before the retry that follows the ATTEMPTS-th transfer
  ;; of a step, by POLICY's backoff: backoff-ms, doubled for each retry of
  ;; the step after the first, capped at max-backoff-ms. With jitter, DRAW,
  ;; in [0, 1), times that, rounded down to a whole ms, so a wait in
  ;; [0, backoff) for a backoff above 0, "full jitter"; without, the backoff
  ;; itself. The product is exact: DRAW is made exact first.
  (define (backoff-wait policy attempts draw)
    (let* ((cap (http-retry-max-backoff-ms policy))
           (backoff (let loop ((b (http-retry-backoff-ms policy)) (k 1))
                      (if (or (>= k attempts) (>= b cap) (= b 0))
                          (min b cap)
                          (loop (* b 2) (+ k 1))))))
      (if (http-retry-jitter policy)
          (floor (* (exact draw) backoff))
          backoff)))

  ;; ows? : Char -> Boolean
  ;; Whether C is optional whitespace, SP or HTAB (RFC 9110, section 5.6.3).
  (define (ows? c) (memv c '(#\space #\tab)))

  ;; trimmed : String -> String
  ;; S without its leading and trailing SP and HTAB.
  (define (trimmed s)
    (let* ((n (string-length s))
           (start (let loop ((i 0)) (if (and (< i n) (ows? (string-ref s i))) (loop (+ i 1)) i)))
           (end (let loop ((i n)) (if (and (> i start) (ows? (string-ref s (- i 1)))) (loop (- i 1)) i))))
      (substring s start end)))

  ;; ascii-digit? : Char -> Boolean
  ;; 0 to 9 alone: char-numeric? takes every Unicode digit.
  (define (ascii-digit? c) (and (char<=? #\0 c) (char<=? c #\9)))

  ;; digits-value : String Natural Natural -> (U Natural #f)
  ;; The decimal value of S from START to END, every char an ASCII digit,
  ;; at least one; #f otherwise.
  (define (digits-value s start end)
    (and (< start end)
         (let loop ((i start) (v 0))
           (cond ((= i end) v)
                 ((ascii-digit? (string-ref s i))
                  (loop (+ i 1) (+ (* v 10) (- (char->integer (string-ref s i)) 48))))
                 (else #f)))))

  ;; day-names, long-day-names, month-names : (Listof String)
  ;; RFC 9110, section 5.6.7, written out: each compared case-sensitively.
  (define day-names '("Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun"))
  (define long-day-names '("Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday" "Sunday"))
  (define month-names '("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))

  ;; month-of : String Natural -> (U Natural #f)
  ;; The month, 1 to 12, whose name is S's three chars from START, or #f.
  (define (month-of s start)
    (let ((name (substring s start (+ start 3))))
      (let loop ((names month-names) (m 1))
        (cond ((null? names) #f)
              ((string=? (car names) name) m)
              (else (loop (cdr names) (+ m 1)))))))

  ;; leap-year? : Integer -> Boolean
  (define (leap-year? y)
    (and (= (mod y 4) 0) (or (not (= (mod y 100) 0)) (= (mod y 400) 0))))

  ;; days-in-month : Integer Natural -> Natural
  (define (days-in-month y m)
    (case m
      ((2) (if (leap-year? y) 29 28))
      ((4 6 9 11) 30)
      (else 31)))

  ;; days-from-civil : Integer Natural Natural -> Integer
  ;; The days from 1970-01-01 to Y-M-D, proleptic Gregorian (Howard
  ;; Hinnant's days_from_civil).
  (define (days-from-civil y m d)
    (let* ((y (if (<= m 2) (- y 1) y))
           (era (div y 400))
           (yoe (- y (* era 400)))
           (doy (+ (div (+ (* 153 (+ m (if (> m 2) -3 9))) 2) 5) (- d 1)))
           (doe (+ (* yoe 365) (div yoe 4) (- (div yoe 100)) doy)))
      (+ (* era 146097) doe -719468)))

  ;; civil-of-seconds : Integer -> (List Integer Natural Natural)
  ;; The Gregorian year, month and day holding UTC-S, seconds since 1970
  ;; (Howard Hinnant's civil_from_days).
  (define (civil-of-seconds utc-s)
    (let* ((z (+ (div utc-s 86400) 719468))
           (era (div z 146097))
           (doe (- z (* era 146097)))
           (yoe (div (+ doe (- (div doe 1460)) (div doe 36524) (- (div doe 146096))) 365))
           (doy (- doe (+ (* 365 yoe) (div yoe 4) (- (div yoe 100)))))
           (mp (div (+ (* 5 doy) 2) 153))
           (d (+ (- doy (div (+ (* 153 mp) 2) 5)) 1))
           (m (if (< mp 10) (+ mp 3) (- mp 9))))
      (list (+ yoe (* era 400) (if (<= m 2) 1 0)) m d)))

  ;; char-at? : String Natural Char -> Boolean
  (define (char-at? s i c) (char=? (string-ref s i) c))

  ;; time-of-day : String Natural -> (U Natural #f)
  ;; The seconds into the day of S's HH:MM:SS from START: hour 00 to 23,
  ;; minute 00 to 59, second 00 to 60, a leap second's 60 among them; or #f.
  (define (time-of-day s start)
    (and (char-at? s (+ start 2) #\:) (char-at? s (+ start 5) #\:)
         (let ((h (digits-value s start (+ start 2)))
               (mi (digits-value s (+ start 3) (+ start 5)))
               (sec (digits-value s (+ start 6) (+ start 8))))
           (and h mi sec (<= h 23) (<= mi 59) (<= sec 60)
                (+ (* h 3600) (* mi 60) sec)))))

  ;; date-seconds : Integer Natural Natural Natural -> (U Integer #f)
  ;; Y-M-D at SECONDS into the day, as seconds since 1970, or #f for a day
  ;; its month does not have.
  (define (date-seconds y m d seconds)
    (and m (>= d 1) (<= d (days-in-month y m))
         (+ (* (days-from-civil y m d) 86400) seconds)))

  ;; two-digit-year-seconds : Natural Natural Natural Natural Integer -> (U Integer #f)
  ;; An rfc850-date of YY, month M, day D and SECONDS into the day, read
  ;; at UTC-S by its timestamp (RFC 9110, section 5.6.7): in the current
  ;; century, unless that timestamp is more than 50 years after UTC-S,
  ;; that is past the same day, month and time 50 years on, then in the
  ;; century before, the most recent past year with those digits. The day
  ;; is checked in the year chosen; #f for one it lacks.
  (define (two-digit-year-seconds yy m d seconds utc-s)
    (let* ((now (civil-of-seconds utc-s))
           (year (car now))
           (limit (+ (* (days-from-civil (+ year 50) (cadr now) (caddr now)) 86400)
                     (mod utc-s 86400)))
           (this (+ (- year (mod year 100)) yy))
           (candidate (date-seconds this m d seconds)))
      (if (and candidate (> candidate limit))
          (date-seconds (- this 100) m d seconds)
          candidate)))

  ;; http-date-seconds : String Integer -> (U Integer #f)
  ;; S, an HTTP-date in any of RFC 9110's three forms (section 5.6.7), as
  ;; seconds since 1970, UTC; #f for anything else. Names and GMT are
  ;; matched case-sensitively; a day name is not checked against the date;
  ;; a day its month lacks, an hour past 23, a minute past 59 and a second
  ;; past 60 are refused. UTC-S, now, reads an rfc850-date's two-digit year.
  ;;   IMF-fixdate    Sun, 06 Nov 1994 08:49:37 GMT
  ;;   rfc850-date    Sunday, 06-Nov-94 08:49:37 GMT
  ;;   asctime-date   Sun Nov  6 08:49:37 1994
  (define (http-date-seconds s utc-s)
    (let ((n (string-length s)))
      (cond
       ;; IMF-fixdate: 29 chars.
       ((and (= n 29) (char-at? s 3 #\,))
        (and (member (substring s 0 3) day-names)
             (char-at? s 4 #\space) (char-at? s 7 #\space) (char-at? s 11 #\space)
             (char-at? s 16 #\space) (char-at? s 25 #\space)
             (string=? (substring s 26 29) "GMT")
             (let ((d (digits-value s 5 7)) (m (month-of s 8)) (y (digits-value s 12 16))
                   (t (time-of-day s 17)))
               (and d y t (date-seconds y m d t)))))
       ;; asctime-date: 24 chars, the day as 2DIGIT or SP DIGIT.
       ((and (= n 24) (char-at? s 3 #\space))
        (and (member (substring s 0 3) day-names)
             (char-at? s 7 #\space) (char-at? s 10 #\space) (char-at? s 19 #\space)
             (let ((d (if (char-at? s 8 #\space) (digits-value s 9 10) (digits-value s 8 10)))
                   (m (month-of s 4)) (y (digits-value s 20 24)) (t (time-of-day s 11)))
               (and d y t (date-seconds y m d t)))))
       ;; rfc850-date: a long day name, then 24 chars from its comma.
       (else
        (let ((comma (let loop ((i 0))
                       (cond ((= i n) #f) ((char-at? s i #\,) i) (else (loop (+ i 1)))))))
          (and comma (= (- n comma) 24)
               (member (substring s 0 comma) long-day-names)
               (char-at? s (+ comma 1) #\space) (char-at? s (+ comma 4) #\-)
               (char-at? s (+ comma 8) #\-) (char-at? s (+ comma 11) #\space)
               (char-at? s (+ comma 20) #\space)
               (string=? (substring s (+ comma 21) n) "GMT")
               (let ((d (digits-value s (+ comma 2) (+ comma 4))) (m (month-of s (+ comma 5)))
                     (yy (digits-value s (+ comma 9) (+ comma 11))) (t (time-of-day s (+ comma 12))))
                 (and d yy t (two-digit-year-seconds yy m d t utc-s)))))))))

  ;; retry-after-ms : String Integer -> (U Natural #f)
  ;; The wait, in ms, a Retry-After header's VALUE asks for at UTC-S (RFC
  ;; 9110, section 10.2.3), its SP and HTAB trimmed: delta-seconds, one or
  ;; more ASCII digits, times 1000; or an HTTP-date's seconds after UTC-S,
  ;; times 1000, 0 for one at or before it; #f for a value that is neither,
  ;; which is read as absent.
  (define (retry-after-ms value utc-s)
    (let* ((s (trimmed value))
           (delta (digits-value s 0 (string-length s))))
      (if delta
          (* delta 1000)
          (let ((date (http-date-seconds s utc-s)))
            (and date (* (max 0 (- date utc-s)) 1000))))))

  ;; wait-fits? : State Integer Natural -> Boolean
  ;; Whether a wait of WAIT-MS from NOW-NS ends before STATE's deadline:
  ;; always, with no bound.
  (define (wait-fits? state now-ns wait-ms)
    (let ((deadline (exchange-deadline state)))
      (or (not deadline) (< (+ now-ns (* wait-ms 1000000)) deadline))))

  ;; retry : State Natural (List Symbol Any) -> (List 'next State Request Natural)
  ;; The step's request again, after WAIT-MS: STATE, which counted the
  ;; transfer, with the step's request in flight, as a redirect's answer
  ;; has its own, and OUTCOME, (response RESPONSE) or (failed CONDITION),
  ;; the one repeated, kept for ran-out. Nothing joins the history.
  (define (retry state wait-ms outcome)
    (let ((request (exchange-request state)))
      (list 'next
            (remade state request (exchange-transfers state) (exchange-history state) request
                    (exchange-followed state) (exchange-attempts state) outcome)
            request wait-ms)))

  ;; step-method : State -> Symbol
  ;; The method of STATE's step: a redirect's may differ from the call's.
  (define (step-method state) (curl-request-method (exchange-request state)))

  ;; attempts-left? : State -> Boolean
  ;; Whether STATE has a policy, its step has made fewer transfers than the
  ;; policy's attempts, and its step may be sent again: no step that
  ;; streams its body from a producer counted as called is (ADR-0032,
  ;; decision 3, amended), whatever the policy says.
  (define (attempts-left? state)
    (let ((policy (exchange-policy state)))
      (and policy (< (exchange-attempts state) (http-retry-attempts policy))
           (not (spent? state)))))

  ;; status-retry : State Response Integer Integer Real
  ;;                -> (U (List 'next State Request Natural) #f)
  ;; RESPONSE's retry, or #f: attempts left, its status among the policy's
  ;; statuses and the step's method among its methods, and the wait ending
  ;; before the bound. The wait is its first Retry-After's, A to Z folded,
  ;; when one can be read, else the backoff; a Retry-After longer than
  ;; max-backoff-ms is no retry, and jitter never shortens one.
  (define (status-retry state response now-ns utc-s draw)
    (let ((policy (exchange-policy state)))
      (and (attempts-left? state)
           (memv (http-response-status response) (http-retry-statuses policy))
           (memq (step-method state) (http-retry-methods policy))
           (let* ((after (first-header (http-response-headers response) "Retry-After"))
                  (asked (and after (retry-after-ms after utc-s)))
                  (wait (or asked (backoff-wait policy (exchange-attempts state) draw))))
             (and (or (not asked) (<= asked (http-retry-max-backoff-ms policy)))
                  (wait-fits? state now-ns wait)
                  (retry state wait (list 'response response)))))))

  ;; retried-failure? : Condition Symbol Retry -> Boolean
  ;; Whether C, a transfer's failure that is not the bound's, is one a
  ;; retry may repeat for METHOD: perform-failed, and then, first, one that
  ;; carries a CONNECT's status, a proxy's refusal of the tunnel, as a
  ;; response with that status, when POLICY's statuses hold it and its
  ;; methods METHOD, alike on every version (ADR-0026, amended 2026-11-03);
  ;; else of the connect, send-receive or timeout class, with a request
  ;; size of 0, nothing sent, for any method; above 0, or #f, unknown, for
  ;; a method in POLICY's methods alone.
  (define (retried-failure? c method policy)
    (and (curl-transfer-error? c)
         (eq? (curl-transfer-error-reason c) 'perform-failed)
         (let ((status (curl-transfer-error-connect-code c)))
           (if status
               (and (memv status (http-retry-statuses policy))
                    (memq method (http-retry-methods policy))
                    #t)
               (and (or (curl-connect-error? c) (curl-send-receive-error? c) (curl-timeout? c))
                    (or (eqv? (curl-transfer-error-request-size c) 0)
                        (and (memq method (http-retry-methods policy)) #t)))))))

  ;; failure-retry : State Condition Integer Real -> (U (List 'next State Request Natural) #f)
  ;; C's retry, or #f: attempts left, a failure retried-failure? takes, and
  ;; the backoff ending before the bound, a refused CONNECT's among them.
  (define (failure-retry state c now-ns draw)
    (and (attempts-left? state)
         (retried-failure? c (step-method state) (exchange-policy state))
         (let ((wait (backoff-wait (exchange-policy state) (exchange-attempts state) draw)))
           (and (wait-fits? state now-ns wait)
                (retry state wait (list 'failed c))))))

  ;; exchange-step : State Outcome Integer Integer Real
  ;;                 -> (U (List 'done Response) (List 'fail Condition)
  ;;                       (List 'next State Request Natural))
  ;; What the call does after OUTCOME, at NOW-NS, a monotonic time in ns,
  ;; UTC-S, the UTC time in seconds, with DRAW, a number in [0, 1), for a
  ;; retry's jitter. A response or a failure from the await counts a
  ;; transfer, for the call and its step; a refused submit does not. A
  ;; response is a retry, by the rules in the header, else done or a
  ;; redirect; a failure is a retry, unless it is a 28 at the bound, else it
  ;; fails, with the call's context, and &http-timeout for a 28 that is the
  ;; bound's; a refusal fails. UTC-S and DRAW are read by retries alone.
  (define (exchange-step state outcome now-ns utc-s draw)
    (check-state 'exchange-step state)
    (check-ns 'exchange-step now-ns)
    (unless (ns? utc-s)
      (assertion-violation 'exchange-step "a UTC time is an exact integer of seconds" utc-s))
    (unless (and (real? draw) (<= 0 draw) (< draw 1))
      (assertion-violation 'exchange-step "a draw is a real in [0, 1)" draw))
    (unless (and (list? outcome) (= (length outcome) 2)
                 (memq (car outcome) '(response failed refused))
                 (if (eq? (car outcome) 'response)
                     (or (curl-response? (cadr outcome)) (http-response? (cadr outcome)))
                     (condition? (cadr outcome))))
      (assertion-violation 'exchange-step
                           "an outcome is (response RESPONSE), (failed CONDITION) or (refused CONDITION)"
                           outcome))
    (let ((what (cadr outcome)))
      (case (car outcome)
        ((response)
         (let* ((state (counted state))
                (response (response-of state what)))
           (or (status-retry state response now-ns utc-s draw)
               (redirected state response))))
        ((failed)
         (let ((state (counted state)))
           (cond
            ((and (bound-timeout? state what now-ns) (exchange-retried state)
                  (eqv? (curl-transfer-error-request-size what) 0))
             (ran-out state))
            ((bound-timeout? state what now-ns)
             (list 'fail (condition (make-http-timeout (exchange-bound state)) what
                                    (exchange-condition state))))
            (else
             (or (failure-retry state what now-ns draw)
                 (list 'fail (condition what (exchange-condition state))))))))
        (else
         (list 'fail (condition what (exchange-condition state)))))))

  ;; exchange-steps-past? : State Response Integer Integer Real -> Boolean
  ;; Whether the call steps past RESPONSE, a streamed transfer's head, its
  ;; body and timings #f, at NOW-NS and UTC-S with DRAW: #t when
  ;; exchange-step answers next for it with the same values, a redirect it
  ;; follows or a retry it takes, so the head is a hop's; #f when it answers
  ;; done or fail, so the call ends with this response, handed on, or
  ;; raises. A pure predicate, by exchange-step's own rules: the shell
  ;; reads the clocks, the draw and the head's bit once, at the head, and
  ;; steps a hop by exchange-step with the same values, so the two cannot
  ;; disagree (the M6 plan, section 3.6). STATE is the step's state before
  ;; the head, its producer marked called when the head says libcurl had
  ;; asked for the body.
  (define (exchange-steps-past? state response now-ns utc-s draw)
    (eq? (car (exchange-step state (list 'response response) now-ns utc-s draw)) 'next)))
