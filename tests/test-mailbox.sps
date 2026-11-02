#!r6rs
;;; The suite for the asynchronous API (M4 plan, sections 3.3, 3.5 and 5.2):
;;; curl-submit with a mailbox and a callback, a token's bounded wait, and
;;; the mailbox, its take and its delivery (ADR-0021), through (curl). Each
;;; check but the first and the last, which make and stop the suite's
;;; engines, was watched failing on a mutant before it counted
;;; (.plans/mailbox-mutation-log.md).
;;;
;;;   - the refusals: at submit, a callback without a mailbox, and each
;;;     argument of the wrong kind; at a take, a delivery and a token's
;;;     wait, a bound that is no natural number, and a wait inside a
;;;     critical section;
;;;   - a token's wait, within its bound and past it, the transfer running
;;;     on;
;;;   - the mailbox: a take and a delivery, a callback's answer and its
;;;     raise, a take's bound, and the order tokens leave in;
;;;   - every completion delivered, once: from two engines into one mailbox,
;;;     to two delivering threads; a cancel, queued and live; a token
;;;     completed twice; a stop's; an engine failure's; a set-up failure's;
;;;   - the test ADR-0012 asks for, its delivery half: a callback runs on the
;;;     thread that delivers it, never the engine's, nor a canceller's;
;;;   - in children, each under a bound: an interrupt handler that escapes
;;;     from a take, and from a delivery, as its critical section ends: the
;;;     notice lost, the outcome kept.
;;;
;;; Importing (curl) runs the load before this suite's first line, on this
;;; thread. Every expected value is one the code under test cannot produce
;;; by failing: SRFI-64 makes #f of a raise in the actual expression, so
;;; none is #f. Every wait here is bounded, by its own bound or by a
;;; watcher's: a hang names no test.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) fork-thread make-mutex with-mutex sleep make-time current-time
              time-second time-nanosecond critical-section get-thread-id library-directories getenv
              make-list iota)
        (curl-testing)
        (curl)
        (curl unsupported)
        (only (curl private engine) call-with-engine-held call-with-mailbox-held
              curl-engine-request-stop! curl-engine-thread
              curl-engine-queued-count make-faulty-curl-engine planted-engine-fault)
        (only (curl private transfer) transfers-started)
        (curl private counters))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; written : Any -> String
(define (written x) (call-with-string-output-port (lambda (p) (write x p))))

;; The simple runner names a failing test but not its values. Print both.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (display "  expected: ")
        (display (written (test-result-ref r 'expected-value)))
        (newline)
        (display "  actual:   ")
        (display (written (test-result-ref r 'actual-value)))
        (newline))
      ;; A suite killed at its bound never flushes: flush each verdict.
      (flush-output-port (current-output-port)))))

(test-begin "mailbox")

;; --- helpers --------------------------------------------------------------------------

(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0)))

;; The counts while the suite's two engines run: each one's multi handle and
;; its slot, and nothing else.
(define running-counts
  '((block . 2) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 2)))

;; now-ms : -> Integer
(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

;; now-us : -> Integer
(define (now-us)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000000) (div (time-nanosecond t) 1000))))

;; pause-ms : Natural -> Unit
(define (pause-ms ms)
  (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))

;; latin-1 : Bytevector -> String
(define (latin-1 bytes)
  (list->string (map integer->char (bytevector->u8-list bytes))))

;; request : String -> Request
;; A GET of TARGET with a 20 s timeout, and libcurl's defaults else.
(define (request target) (make-curl-request target 'timeout-ms 20000))

;; outcome : (-> Response) -> Outcome
;; What THUNK answers, whole: (response STATUS BODY), the body as Latin-1;
;; (transfer-error REASON CODE); (engine-error REASON CONDITION);
;; (assertion-violation WHO); (raised TEXT) for anything else.
(define (outcome thunk)
  (guard (e ((curl-transfer-error? e)
             (list 'transfer-error (curl-transfer-error-reason e) (curl-transfer-error-code e)))
            ((curl-engine-error? e)
             (list 'engine-error (curl-engine-error-reason e) (curl-engine-error-condition e)))
            ((and (assertion-violation? e) (who-condition? e))
             (list 'assertion-violation (condition-who e)))
            (#t (list 'raised (describe e))))
    (let ((r (thunk)))
      (list 'response (curl-response-status r) (latin-1 (curl-response-body r))))))

;; refusal : (-> Any) -> Any
;; (assertion-violation WHO) for an assertion violation THUNK raises;
;; (raised TEXT) for anything else it raises; not-refused when it returns.
(define (refusal thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e))
             (list 'assertion-violation (condition-who e)))
            (#t (list 'raised (describe e))))
    (thunk)
    'not-refused))

;; within : Natural (-> Any) -> Any
;; THUNK's answer, run on a thread of its own and waited for here for at
;; most MS: (raised TEXT) for anything it raises, and (never-returned) if
;; it has not returned by then. So a wait that never ends fails the check
;; that made it, by name.
(define (within ms thunk)
  (let ((mx (make-mutex)) (done #f) (answer #f) (deadline (+ (now-ms) ms)))
    (fork-thread
     (lambda ()
       (let ((a (guard (e (#t (list 'raised (describe e)))) (thunk))))
         (with-mutex mx (set! answer a) (set! done #t)))))
    (let wait ()
      (cond ((with-mutex mx done) answer)
            ((> (now-ms) deadline) '(never-returned))
            (else (pause-ms 1) (wait))))))

;; awaited : Token -> Outcome
;; TOKEN's outcome, awaited on a thread of its own, within 20 s.
(define (awaited token) (within 20000 (lambda () (outcome (lambda () (curl-token-await token))))))

;; stop-within : Engine -> Any
;; curl-engine-stop of ENGINE, within 20 s: returned, or (never-returned).
(define (stop-within engine) (within 20000 (lambda () (curl-engine-stop engine) 'returned)))

;; on-own-engine : (Engine -> Any) -> Any
;; What PROC answers, given an engine made for it alone and stopped once
;; PROC returns, so a raw transfer's dead connection pools nowhere else
;; (traps.md, 8.23.0); (raised TEXT) for anything raised.
(define (on-own-engine proc)
  (guard (e (#t (list 'raised (describe e))))
    (let* ((own (make-curl-engine))
           (answer (guard (e (#t (list 'raised (describe e)))) (proc own))))
      (stop-within own)
      answer)))

;; drain : Mailbox -> (Listof Token)
;; Every token MAILBOX holds now, oldest first, each taken with a bound of 0.
(define (drain mailbox)
  (let loop ((found '()))
    (let ((t (curl-mailbox-take mailbox 0)))
      (if t (loop (cons t found)) (reverse found)))))

;; collect : Mailbox Natural Natural -> (Listof Token)
;; The first N tokens MAILBOX hands over, oldest first, taking for at most
;; MS in all; fewer if MS passes first.
(define (collect mailbox n ms)
  (let ((deadline (+ (now-ms) ms)))
    (let loop ((found '()))
      (if (or (= (length found) n) (> (now-ms) deadline))
          (reverse found)
          (let ((t (curl-mailbox-take mailbox 50)))
            (loop (if t (cons t found) found)))))))

;; positions : (Listof Any) (Listof Any) -> (Listof (U Natural #f))
;; Where each of XS stands in YS, by eq?.
(define (positions xs ys)
  (map (lambda (x)
         (let loop ((ys ys) (i 0))
           (cond ((null? ys) #f) ((eq? (car ys) x) i) (else (loop (cdr ys) (+ i 1))))))
       xs))

;; url-of : Origin Symbol String -> String
(define (url-of o face path)
  (let ((f (origin-face o face)))
    (string-append "http://" (car f) ":" (number->string (cdr f)) path)))

;; library-path : -> String
;; This suite's library path, as --libdirs takes it.
(define (library-path)
  (let loop ((dirs (map car (library-directories))) (text ""))
    (cond ((null? dirs) text)
          ((string=? text "") (loop (cdr dirs) (car dirs)))
          (else (loop (cdr dirs) (string-append text ":" (car dirs)))))))

;; read-all : String -> (Listof Any)
(define (read-all text)
  (let ((port (open-string-input-port text)))
    (let loop ((found '()))
      (let ((datum (guard (e (#t '(unreadable))) (read port))))
        (cond ((eof-object? datum) (reverse found))
              ((equal? datum '(unreadable)) (reverse (cons datum found)))
              (else (loop (cons datum found))))))))

;; interrupt-script : String
;; sh -c INTERRUPT-SCRIPT sh COMMAND...: COMMAND under GNU timeout (gtimeout
;; on macOS), killed with SIGKILL after 60 s, its output in a file made
;; under TMPDIR; once it prints (ready PID), 500 ms later, SIGINT to PID,
;; the child Chez itself; then its exit status, and its output but the
;; ready line. Exit 125 with no timeout, 126 when the child never says it
;; is ready, within 20 s.
(define interrupt-script
  (string-append
   "t=$(command -v timeout || command -v gtimeout) || { echo 'mailbox-escape: no timeout' >&2; exit 125; }\n"
   "out=$(mktemp \"${TMPDIR:-/tmp}/mailbox-escape.XXXXXX\") || exit 125\n"
   "\"$t\" -s KILL 60 \"$@\" >\"$out\" 2>&1 </dev/null &\n"
   "waiter=$!\n"
   "n=0\n"
   "until grep -q '^(ready ' \"$out\" || [ \"$n\" -ge 400 ]; do sleep 0.05; n=$((n + 1)); done\n"
   "pid=$(sed -n 's/^(ready \\([0-9]*\\))$/\\1/p' \"$out\")\n"
   "if [ -z \"$pid\" ]; then kill \"$waiter\"; wait \"$waiter\"; cat \"$out\" >&2; rm -f \"$out\"; echo 'mailbox-escape: the child never said it was ready' >&2; exit 126; fi\n"
   "sleep 0.5\n"
   "kill -INT \"$pid\"\n"
   "wait \"$waiter\"\n"
   "status=$?\n"
   "grep -v '^(ready ' \"$out\"\n"
   "rm -f \"$out\"\n"
   "exit $status\n"))

;; run-escape-child : Symbol String -> (List Integer (Listof Any) String)
;; tests/mailbox-escape.sps, WAIT on URL, under interrupt-script: its exit
;; status, what it printed but its ready line, read as data, and the
;; script's stderr.
(define (run-escape-child wait url)
  (guard (e (#t (list 'raised (describe e) "")))
    (let ((r (capture-command (list "sh" "-c" interrupt-script "sh" (getenv "CHEZ")
                                    "--libdirs" (library-path)
                                    "--program" "tests/mailbox-escape.sps"
                                    (symbol->string wait) url))))
      (list (car r) (read-all (cadr r)) (caddr r)))))

;; --- the engines -------------------------------------------------------------------------

(define main-thread (get-thread-id))

(define engine (guard (e (#t (list 'raised (describe e)))) (make-curl-engine)))
(define other (guard (e (#t (list 'raised (describe e)))) (make-curl-engine)))

(test-equal "the suite's two engines are made, each running"
  '(#t #t)
  (list (curl-engine? engine) (curl-engine? other)))

;; --- refusals ----------------------------------------------------------------------------

(test-equal "curl-submit refuses a callback without a mailbox, a mailbox that is no mailbox, and a callback that is no procedure, each an assertion violation from curl-submit, with nothing queued and nothing started"
  (list (make-list 4 '(assertion-violation curl-submit)) 0 0 running-counts)
  (let ((started (transfers-started))
        (r (request "http://127.0.0.1:1/")))
    (let ((answers (call-with-engine-held engine
                     (lambda ()
                       (list (refusal (lambda () (curl-submit engine r #f (lambda (t) t))))
                             (refusal (lambda () (curl-submit engine r 'mailbox)))
                             (refusal (lambda () (curl-submit engine r (make-curl-mailbox) 'callback)))
                             (refusal (lambda () (curl-submit 'engine r (make-curl-mailbox)))))))))
      (list answers (curl-engine-queued-count engine) (- (transfers-started) started)
            (native-counts)))))

(test-equal "curl-mailbox-take and curl-mailbox-deliver each refuse a mailbox that is no mailbox, and a bound that is no natural number, -1, 1.5, 10.0, #f and \"10\", each an assertion violation from its own name"
  (list (make-list 6 '(assertion-violation curl-mailbox-take))
        (make-list 6 '(assertion-violation curl-mailbox-deliver)))
  (let ((m (make-curl-mailbox)))
    (map (lambda (wait)
           (cons (refusal (lambda () (wait 'mailbox 10)))
                 (map (lambda (bound) (refusal (lambda () (wait m bound))))
                      (list -1 1.5 10.0 #f "10"))))
         (list curl-mailbox-take curl-mailbox-deliver))))

(test-equal "curl-token-wait refuses a token that is no token, and a bound that is no natural number, -1, 1.5, #f and \"10\", each an assertion violation from curl-token-wait"
  (make-list 5 '(assertion-violation curl-token-wait))
  (let ((t (curl-submit engine (request "http://127.0.0.1:1/"))))
    (cons (refusal (lambda () (curl-token-wait 'token 10)))
          (map (lambda (bound) (refusal (lambda () (curl-token-wait t bound))))
               (list -1 1.5 #f "10")))))

;; A wait inside a critical section would sleep with its thread active,
;; holding up every collection (ADR-0013, amended 2026-10-25). Each is
;; bounded, so a mutant that waits anyway returns, and is caught by its
;; answer rather than by a hang.
(test-equal "a take, a delivery and a token's wait, each inside critical-section, are each refused before they start, an assertion violation from its own name"
  '((assertion-violation curl-mailbox-take) (assertion-violation curl-mailbox-deliver)
    (assertion-violation curl-token-wait))
  (let ((m (make-curl-mailbox))
        (t (curl-submit engine (request "http://127.0.0.1:1/"))))
    (list (refusal (lambda () (critical-section (curl-mailbox-take m 50))))
          (refusal (lambda () (critical-section (curl-mailbox-deliver m 50))))
          (refusal (lambda () (critical-section (curl-token-wait t 50)))))))

(call-with-origin
 (lambda (o)
   (define status (url-of o 'http "/status/200"))
   (define (pause ms) (url-of o 'raw (string-append "/raw/pause-mid-body?ms=" (number->string ms))))
   (define status-200 '(response 200 "status 200\n"))

   ;; --- a token's wait (section 3.3) ----------------------------------------------------

   (test-equal "curl-token-wait answers #f for a transfer that has not ended within its bound, at the bound, and leaves it running; then #t once it ends, and await answers its response"
     (list #f 'at-the-bound #t '(response 200 "hello world"))
     (on-own-engine
      (lambda (own)
        (let* ((t (curl-submit own (request (pause 800))))
               (t0 (now-ms))
               (first (within 5000 (lambda () (curl-token-wait t 200))))
               (took (- (now-ms) t0))
               (second (within 5000 (lambda () (curl-token-wait t 4000))))
               (answer (awaited t)))
          (list first (if (<= 200 took 400) 'at-the-bound took) second answer)))))

   ;; Each wait above runs out; these do not. A wait that slept out its
   ;; whole bound after one empty read passed every check but these (the
   ;; slice's review): each must return once its transfer ends, a 300 ms
   ;; pause, long before its bound of 5000 ms. Each on an engine of its own,
   ;; as a raw transfer leaves a dead connection pooled.
   (test-equal "a take, a delivery and a token's wait, each bounded at 5000 ms, return once their transfer, a 300 ms pause, ends: each between 300 and 2000 ms after its submit, not at the bound"
     '((#t soon) (#t soon) (#t soon))
     (map (lambda (wait)
            (on-own-engine
             (lambda (own)
               (let* ((m (make-curl-mailbox))
                      (t0 (now-ms))
                      (t (curl-submit own (request (pause 300)) m))
                      (answer (within 10000 (lambda () (wait m t))))
                      (took (- (now-ms) t0)))
                 (list (or (eq? answer t) (eq? answer #t) answer)
                       (if (<= 300 took 1999) 'soon took))))))
          (list (lambda (m t) (curl-mailbox-take m 5000))
                (lambda (m t) (curl-mailbox-deliver m 5000))
                (lambda (m t) (curl-token-wait t 5000)))))

   ;; curl-token-outcome reads a done token's outcome as data, so a caller can
   ;; wait with curl-token-wait, with no guard around the wait, and still
   ;; tell the transfer's failure from what an interrupt handler raised
   ;; there (M5 slice 3's review). The refused connect is to port 1.
   (test-equal "curl-token-outcome answers #f while the transfer runs, inside critical-section too; once done, the response await answers, eq?, or the condition await raises, eq?, never raising it; and refuses what is no token"
     (list #f #f #t 'response #t #t #t '(assertion-violation curl-token-outcome))
     (on-own-engine
      (lambda (own)
        (let* ((t (curl-submit own (request (pause 600))))
               (live (curl-token-outcome t))
               (live-critical (critical-section (curl-token-outcome t)))
               (ended (within 5000 (lambda () (curl-token-wait t 5000))))
               (o (curl-token-outcome t))
               (f (curl-submit own (make-curl-request "http://127.0.0.1:1/x" 'proxy #f
                                                      'timeout-ms 5000)))
               (f-ended (within 5000 (lambda () (curl-token-wait f 5000))))
               (fo (curl-token-outcome f))
               (raised (guard (e (#t e)) (curl-token-await f) 'not-raised)))
          (list live live-critical ended
                (if (curl-response? o) 'response o)
                (and (curl-response? o) (eq? o (curl-token-await t)))
                f-ended
                (and (condition? fo) (curl-transfer-error? fo) (eq? fo raised))
                (refusal (lambda () (curl-token-outcome 'not-a-token))))))))

   ;; --- the mailbox ---------------------------------------------------------------------

   (test-equal "a token submitted with a mailbox goes there when done: a take answers it, eq?, then #f, and await answers its response"
     (list #t #f status-200)
     (let* ((m (make-curl-mailbox))
            (t (curl-submit engine (request status) m)))
       (list (eq? (within 20000 (lambda () (curl-mailbox-take m 10000))) t)
             (curl-mailbox-take m 0)
             (awaited t))))

   (test-equal "a delivery calls the token's callback with the token, on the delivering thread, and answers the token, never the callback's answer: a callback answering #f is no timeout"
     (list #t #t #t #t)
     (let* ((m (make-curl-mailbox))
            (seen #f)
            (t (curl-submit engine (request status) m
                            (lambda (token) (set! seen (cons token (get-thread-id))) #f))))
       (let ((delivered (curl-mailbox-deliver m 10000)))
         (list (eq? delivered t) (and (pair? seen) (eq? (car seen) t))
               (and (pair? seen) (eqv? (cdr seen) main-thread))
               (curl-token-done? t)))))

   (test-equal "a take never calls a callback, and a delivery of a token with none calls nothing and answers the token"
     (list #t 'not-called #t)
     (let* ((m (make-curl-mailbox))
            (called #f)
            (with-callback (curl-submit engine (request status) m (lambda (token) (set! called #t))))
            (taken (curl-mailbox-take m 10000))
            (without (curl-submit engine (request status) m))
            (delivered (curl-mailbox-deliver m 10000)))
       (list (eq? taken with-callback) (if called 'called 'not-called) (eq? delivered without))))

   ;; On an engine of its own: a callback called where its token completes
   ;; would raise on the engine's thread, and fail it, so the suite's two
   ;; engines are kept for the delivery test, which must fail by name.
   (test-equal "a callback's raise leaves through the delivery, on the delivering thread: the token stays done, await answers its response, and the mailbox has moved past it"
     (list '(boom) #t status-200 #f)
     (on-own-engine
      (lambda (own)
        (let* ((m (make-curl-mailbox))
               (t (curl-submit own (request status) m (lambda (token) (raise '(boom))))))
          (let ((raised (guard (e ((equal? e '(boom)) e) (#t (list 'raised (describe e))))
                          (curl-mailbox-deliver m 10000)
                          'not-raised)))
            (list raised (curl-token-done? t) (awaited t) (curl-mailbox-take m 0)))))))

   (test-equal "a take from an empty mailbox answers #f once its bound of 300 ms has passed, and not before"
     (list #f 'at-the-bound)
     (let* ((m (make-curl-mailbox))
            (t0 (now-ms))
            (answer (within 5000 (lambda () (curl-mailbox-take m 300))))
            (took (- (now-ms) t0)))
       (list answer (if (<= 300 took 400) 'at-the-bound took))))

   ;; A wait's sleeps double from 50 us to 10 ms: an empty take reads at
   ;; about 13.2 ms, then 23.3 and 33.5 (measured in the container). The
   ;; last sleep stops at the bound, so a take bounded at 15 ms answers at
   ;; about 15.1; one that slept its whole pause would answer at the read
   ;; after, about 23.3. The fastest of three is judged, so one descheduled
   ;; sleep does not fail it. (A bound of 23 ms passed either way: its read
   ;; at 23.3 came after it, the mutation log.)
   (test-equal "a take's last sleep stops at its bound: of three takes bounded at 15 ms, the fastest answers #f under 19 ms, where sleeping past the bound would take about 23"
     (list '(#f #f #f) 'by-the-bound)
     (let* ((m (make-curl-mailbox))
            (runs (map (lambda (i)
                         (let* ((t0 (now-us)) (answer (curl-mailbox-take m 15)))
                           (cons answer (- (now-us) t0))))
                       '(0 1 2)))
            (fastest (apply min (map cdr runs))))
       (list (map car runs) (if (<= 15000 fastest 18999) 'by-the-bound (map cdr runs)))))

   (test-equal "a mailbox hands its tokens over oldest first: three transfers submitted in one order, which end in another, 150 ms apart, are taken in the order they ended"
     '(#t (0 1 2))
     (on-own-engine
      (lambda (own)
        (let* ((m (make-curl-mailbox))
               (late (curl-submit own (request (pause 500)) m))
               (early (curl-submit own (request (pause 200)) m))
               (middle (curl-submit own (request (pause 350)) m)))
          (let* ((ended (within 10000 (lambda () (curl-token-wait late 5000))))
                 (got (drain m)))
            (list ended (positions (list early middle late) got)))))))

   ;; --- every completion delivered, once -------------------------------------------------

   ;; The delivery half of ADR-0012's test: two threads deliver from one
   ;; mailbox that two engines fill, and each callback notes the thread it
   ;; ran on. A callback called where its token completes would run on an
   ;; engine's thread.
   ;; Computed under a guard: a raise in a suite's top-level forms kills it,
   ;; naming no test.
   (let* ((m (make-curl-mailbox))
          (lock (make-mutex))
          (ran '())
          (tokens (guard (e (#t '()))
                    (map (lambda (i)
                           (curl-submit (if (even? i) engine other) (request status) m
                                        (lambda (t)
                                          (with-mutex lock (set! ran (cons (cons t (get-thread-id)) ran))))))
                         (iota 100))))
          ;; deliverer : -> (Pairof Integer (Listof Token))
          ;; Its thread, and the tokens it delivered, until every callback
          ;; has run, or 20 s pass.
          (deliverer (lambda ()
                       (let ((deadline (+ (now-ms) 20000)))
                         (let loop ((got '()))
                           (if (or (> (now-ms) deadline) (with-mutex lock (= (length ran) 100)))
                               (cons (get-thread-id) got)
                               (let ((t (curl-mailbox-deliver m 20)))
                                 (loop (if t (cons t got) got))))))))
          (results (let ((a #f) (b #f) (mx (make-mutex)))
                     (fork-thread (lambda () (let ((r (deliverer))) (with-mutex mx (set! a r)))))
                     (fork-thread (lambda () (let ((r (deliverer))) (with-mutex mx (set! b r)))))
                     (within 30000
                             (lambda ()
                               (let wait ()
                                 (if (with-mutex mx (and a b))
                                     (with-mutex mx (list a b))
                                     (begin (pause-ms 5) (wait))))))))
          (results (if (and (list? results) (= (length results) 2) (for-all pair? results))
                       results
                       '()))
          (delivered (apply append (map cdr results))))
     (test-equal "a hundred transfers on two engines, into one mailbox that two threads deliver from: each token delivered once, and every one of them"
       (list 100 100 #t)
       (list (length delivered)
             (length (positions tokens delivered))
             (for-all (lambda (p) (and p #t)) (positions tokens delivered))))
     (test-equal "each of the hundred callbacks ran once, on the thread that delivered its token, never an engine's"
       (list 100 #t #t)
       (list (length ran)
             (for-all (lambda (entry)
                        (let ((by (find (lambda (r) (memq (car entry) (cdr r))) results)))
                          (and by (eqv? (car by) (cdr entry)))))
                      ran)
             (guard (e (#t (list 'raised (describe e))))
               (not (exists (lambda (entry)
                              (memv (cdr entry) (list (curl-engine-thread engine)
                                                      (curl-engine-thread other))))
                            ran))))))

   ;; A cancel of a token still queued completes it on the cancelling
   ;; thread: the callback must still run on the delivering one, so the
   ;; submit and the cancel come from a thread of their own, which holds
   ;; the engine so the token stays queued.
   (test-equal "a token cancelled while queued, on a thread of its own, reaches the mailbox cancelled, and its callback runs on the delivering thread, not the canceller's"
     (list '(transfer-error cancelled #f) #t #t)
     (let* ((m (make-curl-mailbox))
            (ran-on #f)
            (t (within 5000
                       (lambda ()
                         (call-with-engine-held engine
                           (lambda ()
                             (let ((t (curl-submit engine (request status) m
                                                   (lambda (t) (set! ran-on (get-thread-id))))))
                               (curl-token-cancel t)
                               t))))))
            (delivered (curl-mailbox-deliver m 10000)))
       (list (awaited t) (eq? delivered t) (eqv? ran-on main-thread))))

   (test-equal "a live transfer cancelled reaches the mailbox cancelled, its callback run on the delivering thread"
     (list '(transfer-error cancelled #f) #t #t)
     (on-own-engine
      (lambda (own)
        (let* ((m (make-curl-mailbox))
               (ran-on #f)
               (t (curl-submit own (request (pause 2000)) m (lambda (t) (set! ran-on (get-thread-id))))))
          (pause-ms 200)
          (curl-token-cancel t)
          (let ((delivered (curl-mailbox-deliver m 10000)))
            (list (awaited t) (eq? delivered t) (eqv? ran-on main-thread)))))))

   ;; Its submit passes through the stop's completion after its cancel's:
   ;; the append belongs to the change to done, so it happens once.
   (test-equal "a token cancelled while queued, then stopped in the same batch, reaches the mailbox once, cancelled"
     (list '(transfer-error cancelled #f) 1)
     (let* ((stopping (make-curl-engine))
            (m (make-curl-mailbox))
            (t (call-with-engine-held stopping
                 (lambda ()
                   (let ((t (curl-submit stopping (request status) m)))
                     (curl-token-cancel t)
                     (curl-engine-request-stop! stopping)
                     t)))))
       (stop-within stopping)
       (list (awaited t) (length (filter (lambda (x) (eq? x t)) (drain m))))))

   (test-equal "a stop's tokens reach the mailbox, each once, stopped: two live and two still queued"
     (list (make-list 4 '(transfer-error stopped #f)) '(#t #t #t #t) 4)
     (on-own-engine
      (lambda (stopping)
        (let* ((m (make-curl-mailbox))
               (live (map (lambda (i) (curl-submit stopping (request (pause 3000)) m)) '(0 1)))
               (queued (begin
                         (pause-ms 200)
                         (call-with-engine-held stopping
                           (lambda ()
                             (let ((q (map (lambda (i) (curl-submit stopping (request status) m)) '(0 1))))
                               (curl-engine-request-stop! stopping)
                               q))))))
          (stop-within stopping)
          (let ((got (drain m)) (all (append live queued)))
            (list (map awaited all)
                  (map (lambda (p) (and p #t)) (positions all got))
                  (length got)))))))

   (test-equal "an engine failure's tokens reach the mailbox, each once, failed: two live, and one set up in the turn the fault came in"
     (list (make-list 3 (list 'engine-error 'failed (planted-engine-fault 'cancel))) '(#t #t #t) 3)
     (let* ((faulty (make-faulty-curl-engine 'cancel))
            (m (make-curl-mailbox))
            (a (curl-submit faulty (request (pause 1000)) m))
            (b (curl-submit faulty (request (pause 1000)) m)))
       (pause-ms 200)
       (let ((c (call-with-engine-held faulty
                  (lambda ()
                    (curl-token-cancel a)
                    (curl-submit faulty (request status) m)))))
         (let* ((all (list a b c))
                (answers (map awaited all))
                (got (collect m 3 10000)))
           (stop-within faulty)
           (list answers (map (lambda (p) (and p #t)) (positions all got))
                 (length (append got (drain m))))))))

   (test-equal "a set-up failure's token reaches the mailbox: LOW_SPEED_LIMIT at -2, which libcurl refuses, through the hatch"
     (list '(transfer-error setopt-failed 43) #t)
     (on-own-engine
      (lambda (own)
        (let* ((m (make-curl-mailbox))
               (t (curl-submit own (curl-request-with-options (request status) '(("LOW_SPEED_LIMIT" . -2)))
                               m)))
          (list (awaited t) (eq? (curl-mailbox-take m 10000) t))))))

   ;; --- the children ------------------------------------------------------------------------

   ;; The escape at the take (ADR-0021, amended): a second thread holds the
   ;; mailbox's mutex, so the take blocks inside its critical section, and
   ;; SIGINT arrives meanwhile. Its handler escapes as the section ends, the
   ;; token taken out and never returned: the notice is lost, and the
   ;; outcome is not.
   (for-each
    (lambda (wait)
      (test-equal (string-append "an interrupt handler that escapes from a " (symbol->string wait)
                                 " as its critical section ends loses the token's notice, its callback unrun, never its outcome: the token is done, and await answers its response; the child's counts zero")
        (list 0 '(escape lost #f #t (response 200)) (list 'counts zero-counts) "")
        (let ((r (run-escape-child wait status)))
          (if (and (pair? r) (= (length r) 3) (list? (cadr r)) (= (length (cadr r)) 2))
              (list (car r) (car (cadr r)) (cadr (cadr r)) (caddr r))
              r))))
    '(take deliver))))

(test-equal "the suite's engines stop, and every count is zero after"
  (list 'returned 'returned zero-counts)
  (if (and (curl-engine? engine) (curl-engine? other))
      (list (stop-within engine) (stop-within other) (native-counts))
      (list engine other)))

(test-end "mailbox")

(exit (suite-exit-status runner))
