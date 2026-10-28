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
;;; transfers it has made, its history, the request in flight, and its
;;; redirect policy: the most redirects it follows, or #f, whether it
;;; follows one from https to http, and how many it has followed. A header a
;;; redirect drops is gone from the step's request, which each later one is
;;; made from, so it stays dropped. Each answer is a tagged list:
;;;
;;;   (exchange-submission STATE NOW-NS)
;;;     (submit STATE REQUEST)  submit REQUEST: the step's request, with the
;;;                             time left, rounded up to a whole ms, as its
;;;                             timeout-ms, and, when it has none, as its
;;;                             connect-timeout-ms too, capped at libcurl's
;;;                             300000; as it is, with no bound
;;;     (fail CONDITION)        no time left: &http-timeout
;;;
;;;   (exchange-step STATE OUTCOME NOW-NS UTC-S DRAW), OUTCOME one of
;;;   (response RESPONSE) or (failed CONDITION) from a transfer's await, or
;;;   (refused CONDITION) from a submit that raised. RESPONSE is the
;;;   transfer's curl-response, or an http-response, which the suite's
;;;   tables build: the core reads its status, version, headers, body and
;;;   timings alike, and gives the answer the URL in flight and the history.
;;;     (done RESPONSE)               the call's answer
;;;     (fail CONDITION)              what the call raises
;;;     (next STATE REQUEST WAIT-MS)  a redirect: REQUEST, STATE's step
;;;                                   request, goes through
;;;                                   exchange-submission once WAIT-MS ms
;;;                                   pass, 0 for a redirect; a retry's,
;;;                                   never, before slice 3
;;;
;;; Every fail is (condition [HTTP-TIMEOUT] C EXCHANGE), built here: C what
;;; the transfer or the submit raised, when there is one, and EXCHANGE the
;;; call's &http-exchange. A 28 is the call's bound's when the call has one
;;; and either the transfer's connect-timeout-ms is not shorter than its
;;; timeout-ms, the time left, or NOW-NS is at or past the deadline; it then
;;; carries &http-timeout too. Otherwise a 28 is the transfer's own connect
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
;;;   - a 301 or a 302 makes a post a get, without its body; a 303 makes
;;;     every method but head a get, without its body; every other method,
;;;     and a 307 and a 308, keep the method and the body. Without the body
;;;     go the headers named Content-*, Digest, Last-Modified and Expect, A
;;;     to Z folded: a 100-continue asks for a body there is none of (RFC
;;;     9110, section 10.1.1);
;;;   - another origin, by scheme, host A to Z folded, zone ID and port,
;;;     each by curl-url-part, drops Authorization, Cookie and
;;;     Proxy-Authorization, and another host, A to Z folded, or another
;;;     zone ID, drops Host too: libcurl gives an IPv6 host without its zone,
;;;     so two zones of one address are told apart by the zone alone;
;;;   - the next request is made by make-curl-request from the new URL,
;;;     every other key read from the step's request, whose timeout-ms is
;;;     the call's bound: exchange-submission gives it the time left;
;;;   - the response joins the history, oldest first, with a history of
;;;     its own of (); the answer, and a redirect error's response, carry
;;;     the history before them.
(library (http-client private exchange)
  (export make-exchange exchange? exchange-method exchange-url exchange-request
          exchange-bound exchange-start-ns exchange-transfers exchange-history
          exchange-flight exchange-redirects exchange-allow-downgrade exchange-followed
          exchange-deadline exchange-condition
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
            (immutable followed exchange-followed))
    (sealed #t))

  ;; ns? : Any -> Boolean
  (define (ns? x) (and (integer? x) (exact? x)))

  ;; make-exchange : Any Any Request (U Positive-Integer #f) Integer (U Natural #f) Boolean
  ;;                 -> State
  ;; A call of METHOD on URL, as the caller gave them, whose first request
  ;; is REQUEST, bounded by TIMEOUT-MS from START-NS, or unbounded for #f,
  ;; that follows REDIRECTS redirects at most, or none for #f, and one from
  ;; https to http when ALLOW-DOWNGRADE; no transfer made, no history, none
  ;; followed, and REQUEST in flight.
  (define (make-exchange method url request timeout-ms start-ns redirects allow-downgrade)
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
    (make-exchange-state method url request timeout-ms start-ns 0 '() request redirects
                         allow-downgrade 0))

  ;; remade : State Request Natural (Listof Response) Request Natural -> State
  ;; STATE with its step's request, transfers, history, request in flight
  ;; and redirects followed replaced.
  (define (remade state request transfers history flight followed)
    (make-exchange-state (exchange-method state) (exchange-url state) request
                         (exchange-bound state) (exchange-start-ns state) transfers history
                         flight (exchange-redirects state) (exchange-allow-downgrade state)
                         followed))

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
    (remade state (exchange-request state) (exchange-transfers state) (exchange-history state)
            request (exchange-followed state)))

  ;; counted : State -> State
  ;; STATE, with one more transfer made.
  (define (counted state)
    (remade state (exchange-request state) (+ (exchange-transfers state) 1)
            (exchange-history state) (exchange-flight state) (exchange-followed state)))

  (define (check-state who state)
    (unless (exchange? state) (assertion-violation who "not an exchange" state)))

  (define (check-ns who now-ns)
    (unless (ns? now-ns) (assertion-violation who "a time is an exact integer of ns" now-ns)))

  ;; default-connect-timeout-ms : Positive-Integer
  ;; libcurl's DEFAULT_CONNECT_TIMEOUT, which it applies to a connect when
  ;; CONNECTTIMEOUT is unset: 300000 on 7.85.0 and 8.23.0 alike.
  (define default-connect-timeout-ms 300000)

  ;; exchange-submission : State Integer -> (U (List 'submit State Request) (List 'fail Condition))
  ;; What to submit at NOW-NS, a monotonic time in ns: the step's request,
  ;; its timeout-ms the time left before the deadline, rounded up to a whole
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

  ;; location-of : (Listof (Pairof String String)) -> (U String #f)
  ;; The value of the first of HEADERS named Location, A to Z folded alone,
  ;; or #f.
  (define (location-of headers)
    (let ((hit (find (lambda (header) (ascii-ci=? (car header) "location")) headers)))
      (and hit (cdr hit))))

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
  ;; Authorization, Cookie and Proxy-Authorization, A to Z folded.
  (define (credential-header? name)
    (exists (lambda (credential) (ascii-ci=? name credential))
            '("Authorization" "Cookie" "Proxy-Authorization")))

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
                    (else "a redirect from https to http, which the call does not allow")))
                 (append (if url-error (list url-error) '())
                         (list (exchange-condition state))))))

  ;; next-request : Request String Integer Boolean Boolean -> Request
  ;; The request a STATUS redirect to URL makes from LAST, the step's: its
  ;; method, its body and its body's headers kept or dropped by
  ;; body-dropped?; its credential headers dropped when ACROSS, to another
  ;; origin; its Host when ANOTHER-HOST; every other key LAST's.
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
                         'user-agent (curl-request-user-agent last)
                         'timeout-ms (curl-request-timeout-ms last)
                         'connect-timeout-ms (curl-request-connect-timeout-ms last)
                         'body-limit (curl-request-body-limit last)
                         'ca-file (curl-request-ca-file last)
                         'verify (curl-request-verify last)
                         'proxy (curl-request-proxy last))))

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
                                           request (+ (exchange-followed state) 1))))
                        (list 'next next request 0)))))))))

  ;; redirected : State Response
  ;;              -> (U (List 'done Response) (List 'fail Condition) (List 'next State Request 0))
  ;; What RESPONSE, the call's response with STATE's history, makes of the
  ;; call: done, unless it is a redirect; for a redirect, done with no
  ;; bound, too-many-redirects once the bound's are followed, else follow's
  ;; answer.
  (define (redirected state response)
    (let ((status (http-response-status response))
          (location (location-of (http-response-headers response)))
          (bound (exchange-redirects state)))
      (cond ((not (memv status redirect-statuses)) (list 'done response))
            ((or (not location) (blank? location)) (list 'done response))
            ((not bound) (list 'done response))
            ((>= (exchange-followed state) bound)
             (refuse-redirect state 'too-many-redirects response location #f))
            (else (follow state response status location)))))

  ;; exchange-step : State Outcome Integer Integer Real
  ;;                 -> (U (List 'done Response) (List 'fail Condition)
  ;;                       (List 'next State Request Natural))
  ;; What the call does after OUTCOME, at NOW-NS, a monotonic time in ns,
  ;; UTC-S, the UTC time in seconds, with DRAW, a number in [0, 1), for a
  ;; retry's jitter. A response or a failure from the await counts a
  ;; transfer; a refused submit does not. A response is done, or a redirect,
  ;; by the rules in the header; a failure or a refusal fails, with the
  ;; call's context, and &http-timeout for a 28 that is the bound's. UTC-S
  ;; and DRAW are read by retries alone.
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
         (let ((state (counted state)))
           (redirected state (response-of state what))))
        ((failed)
         (let ((state (counted state)))
           (list 'fail (if (bound-timeout? state what now-ns)
                           (condition (make-http-timeout (exchange-bound state)) what
                                      (exchange-condition state))
                           (condition what (exchange-condition state))))))
        (else
         (list 'fail (condition what (exchange-condition state))))))))
