#!r6rs
;;; (http-client private exchange): the functional core of a call, its
;;; exchange (the M5 plan, section 3.6). It makes no transfer, reads no
;;; clock and draws no number: the shell hands it the time, and it answers
;;; what to do next, as data, so the suite drives it by tables. Only
;;; (curl)'s URL functions, whose answers depend on the loaded libcurl
;;; alone, and its condition types reach out.
;;;
;;; An exchange is one call: its method and URL as the caller gave them,
;;; its first request, its bound, the call's timeout-ms, from START-NS, the
;;; monotonic time it began, the transfers it has made, its history, and the
;;; request in flight. Each answer is a tagged list:
;;;
;;;   (exchange-submission STATE NOW-NS)
;;;     (submit STATE REQUEST)  submit REQUEST: the request in flight, with
;;;                             the time left, rounded up to a whole ms, as
;;;                             its timeout-ms, and, when it has none, as its
;;;                             connect-timeout-ms too, capped at libcurl's
;;;                             300000; as it is, with no bound
;;;     (fail CONDITION)        no time left: &http-timeout
;;;
;;;   (exchange-step STATE OUTCOME NOW-NS UTC-S DRAW), OUTCOME one of
;;;   (response CURL-RESPONSE), (failed CONDITION) from a transfer's await,
;;;   or (refused CONDITION) from a submit that raised:
;;;     (done RESPONSE)               the call's answer
;;;     (fail CONDITION)              what the call raises
;;;     (next STATE REQUEST WAIT-MS)  a redirect or a retry: never, before
;;;                                   slices 2 and 3
;;;
;;; Every fail is (condition [HTTP-TIMEOUT] C EXCHANGE), built here: C what
;;; the transfer or the submit raised, when there is one, and EXCHANGE the
;;; call's &http-exchange. A 28 is the call's bound's when the call has one
;;; and either the transfer's connect-timeout-ms is not shorter than its
;;; timeout-ms, the time left, or NOW-NS is at or past the deadline; it then
;;; carries &http-timeout too. Otherwise a 28 is the transfer's own connect
;;; timeout's (the M5 plan, section 3.5).
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
;;; The response is the high level's, read from the last transfer's
;;; curl-response, with the URL the call requested, and its history.
(library (http-client private exchange)
  (export make-exchange exchange? exchange-method exchange-url exchange-request
          exchange-bound exchange-start-ns exchange-transfers exchange-history
          exchange-flight exchange-deadline exchange-condition
          exchange-submission exchange-step
          make-http-response http-response? http-response-status http-response-http-version
          http-response-url http-response-headers http-response-body http-response-timings
          http-response-history http-response-header http-response-text)
  (import (curl)
          (rnrs)
          (http-client private conditions)
          (only (http-client private call) ascii-ci=?))

  ;; --- the response ----------------------------------------------------------------

  ;; make-http-response : Integer (U Symbol Integer #f) String
  ;;                      (Listof (Pairof String String)) Bytevector
  ;;                      (Listof (Pairof Symbol Natural)) (Listof Response) -> Response
  ;; http-response? : Any -> Boolean
  ;; http-response-status : Response -> Integer
  ;; http-response-http-version : Response -> (U 'http/1.0 'http/1.1 'http/2 'http/3 Integer #f)
  ;; http-response-url : Response -> String
  ;; http-response-headers : Response -> (Listof (Pairof String String))
  ;; http-response-body : Response -> Bytevector
  ;; http-response-timings : Response -> (Listof (Pairof Symbol Natural))
  ;; http-response-history : Response -> (Listof Response)
  (define-record-type (http-response make-http-response http-response?)
    (fields (immutable status http-response-status)
            (immutable http-version http-response-http-version)
            (immutable url http-response-url)
            (immutable headers http-response-headers)
            (immutable body http-response-body)
            (immutable timings http-response-timings)
            (immutable history http-response-history))
    (sealed #t))

  ;; http-response-header : Response String -> (U String #f)
  ;; The value of RESPONSE's first header named NAME, A to Z folded alone,
  ;; or #f. A copy of NAME is what is compared.
  (define (http-response-header response name)
    (unless (http-response? response)
      (assertion-violation 'http-response-header "not a response" response))
    (unless (string? name)
      (assertion-violation 'http-response-header "a header's name is a string" name))
    (let* ((copy (string-copy name))
           (hit (find (lambda (header) (ascii-ci=? (car header) copy))
                      (http-response-headers response))))
      (and hit (cdr hit))))

  ;; http-response-text : Response -> String
  ;; RESPONSE's body decoded as UTF-8 by utf8->string: a malformed sequence
  ;; read as U+FFFD, and a leading byte-order mark dropped. It reads no
  ;; charset.
  (define (http-response-text response)
    (unless (http-response? response)
      (assertion-violation 'http-response-text "not a response" response))
    (utf8->string (http-response-body response)))

  ;; --- the exchange ----------------------------------------------------------------

  ;; An exchange's state, immutable: each step answers a new one.
  ;; exchange? : Any -> Boolean
  ;; exchange-method : State -> Any
  ;; exchange-url : State -> Any
  ;; exchange-request : State -> Request
  ;; exchange-bound : State -> (U Positive-Integer #f)
  ;; exchange-start-ns : State -> Integer
  ;; exchange-transfers : State -> Natural
  ;; exchange-history : State -> (Listof Response)
  ;; exchange-flight : State -> Request
  (define-record-type (exchange make-exchange-state exchange?)
    (fields (immutable method exchange-method)
            (immutable url exchange-url)
            (immutable request exchange-request)
            (immutable bound exchange-bound)
            (immutable start-ns exchange-start-ns)
            (immutable transfers exchange-transfers)
            (immutable history exchange-history)
            (immutable flight exchange-flight))
    (sealed #t))

  ;; ns? : Any -> Boolean
  (define (ns? x) (and (integer? x) (exact? x)))

  ;; make-exchange : Any Any Request (U Positive-Integer #f) Integer -> State
  ;; A call of METHOD on URL, as the caller gave them, whose first request
  ;; is REQUEST, bounded by TIMEOUT-MS from START-NS, or unbounded for #f;
  ;; no transfer made, no history, and REQUEST in flight.
  (define (make-exchange method url request timeout-ms start-ns)
    (unless (curl-request? request)
      (assertion-violation 'make-exchange "not a request" request))
    (unless (or (not timeout-ms)
                (and (integer? timeout-ms) (exact? timeout-ms) (positive? timeout-ms)))
      (assertion-violation 'make-exchange "a bound is a positive exact integer of ms, or #f"
                           timeout-ms))
    (unless (ns? start-ns)
      (assertion-violation 'make-exchange "a time is an exact integer of ns" start-ns))
    (make-exchange-state method url request timeout-ms start-ns 0 '() request))

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

  ;; with-flight : State Request -> State
  (define (with-flight state request)
    (make-exchange-state (exchange-method state) (exchange-url state) (exchange-request state)
                         (exchange-bound state) (exchange-start-ns state)
                         (exchange-transfers state) (exchange-history state) request))

  ;; counted : State -> State
  ;; STATE, with one more transfer made.
  (define (counted state)
    (make-exchange-state (exchange-method state) (exchange-url state) (exchange-request state)
                         (exchange-bound state) (exchange-start-ns state)
                         (+ (exchange-transfers state) 1) (exchange-history state)
                         (exchange-flight state)))

  (define (check-state who state)
    (unless (exchange? state) (assertion-violation who "not an exchange" state)))

  (define (check-ns who now-ns)
    (unless (ns? now-ns) (assertion-violation who "a time is an exact integer of ns" now-ns)))

  ;; default-connect-timeout-ms : Positive-Integer
  ;; libcurl's DEFAULT_CONNECT_TIMEOUT, which it applies to a connect when
  ;; CONNECTTIMEOUT is unset: 300000 on 7.85.0 and 8.23.0 alike.
  (define default-connect-timeout-ms 300000)

  ;; exchange-submission : State Integer -> (U (List 'submit State Request) (List 'fail Condition))
  ;; What to submit at NOW-NS, a monotonic time in ns: the request, its
  ;; timeout-ms the time left before the deadline, rounded up to a whole
  ;; ms, and, when it has no connect-timeout-ms, the one libcurl would
  ;; apply, written out: the smaller of the time left and 300000 ms; and the
  ;; state with it in flight. With no bound, the request as it is. With no
  ;; time left, the call's &http-timeout, compounded with its
  ;; &http-exchange.
  (define (exchange-submission state now-ns)
    (check-state 'exchange-submission state)
    (check-ns 'exchange-submission now-ns)
    (let ((request (exchange-request state))
          (deadline (exchange-deadline state)))
      (if (not deadline)
          (list 'submit (with-flight state request) request)
          (let ((left-ns (- deadline now-ns)))
            (if (<= left-ns 0)
                (list 'fail (condition (make-http-timeout (exchange-bound state))
                                       (exchange-condition state)))
                (let* ((left (div (+ left-ns 999999) 1000000))
                       (sent (if (curl-request-connect-timeout-ms request)
                                 (curl-request-with request 'timeout-ms left)
                                 (curl-request-with request 'timeout-ms left
                                                    'connect-timeout-ms
                                                    (min left default-connect-timeout-ms)))))
                  (list 'submit (with-flight state sent) sent)))))))

  ;; bound-timeout? : State Condition Integer -> Boolean
  ;; Whether C, a transfer's failure at NOW-NS, is a 28 that is the call's
  ;; bound's: the call has a bound, and the transfer in flight had a
  ;; connect-timeout-ms not shorter than its timeout-ms, or NOW-NS is at or
  ;; past the deadline. Under a bound, every request exchange-submission
  ;; puts in flight carries both, so no path the drive takes meets one
  ;; without: only a table's state that no submission made holds its first
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

  ;; response-of : State Curl-Response -> Response
  ;; The call's response: R's fields, the URL of the request in flight, and
  ;; STATE's history.
  (define (response-of state r)
    (make-http-response (curl-response-status r) (curl-response-http-version r)
                        (curl-request-url (exchange-flight state))
                        (curl-response-headers r) (curl-response-body r)
                        (curl-response-timings r) (exchange-history state)))

  ;; exchange-step : State Outcome Integer Integer Real
  ;;                 -> (U (List 'done Response) (List 'fail Condition)
  ;;                       (List 'next State Request Natural))
  ;; What the call does after OUTCOME, at NOW-NS, a monotonic time in ns,
  ;; UTC-S, the UTC time in seconds, with DRAW, a number in [0, 1), for a
  ;; retry's jitter. A response or a failure from the await counts a
  ;; transfer; a refused submit does not. A response is done; a failure or
  ;; a refusal fails, with the call's context, and &http-timeout for a 28
  ;; that is the bound's. UTC-S and DRAW are read by retries alone.
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
                     (curl-response? (cadr outcome))
                     (condition? (cadr outcome))))
      (assertion-violation 'exchange-step
                           "an outcome is (response CURL-RESPONSE), (failed CONDITION) or (refused CONDITION)"
                           outcome))
    (let ((what (cadr outcome)))
      (case (car outcome)
        ((response)
         (list 'done (response-of (counted state) what)))
        ((failed)
         (let ((state (counted state)))
           (list 'fail (if (bound-timeout? state what now-ns)
                           (condition (make-http-timeout (exchange-bound state)) what
                                      (exchange-condition state))
                           (condition what (exchange-condition state))))))
        (else
         (list 'fail (condition what (exchange-condition state))))))))
