#!r6rs
;;; The suite for a streamed response at the low level (ADR-0030; the M6
;;; plan, sections 3.2 to 3.5 and 4.2): a request's stream-buffer, the
;;; token's head, pieces and port, the engine's resume and its paced poll.
;;; Each check was watched failing on a mutant before it counted
;;; (build/m6s1/mutants.md).
;;;
;;;   - every byte in order, by next-piece and by the port, over the http,
;;;     raw, https and h2 faces; a piece the caller owns; 64 MiB within 60 s;
;;;     a stream per submit, there for a token still queued;
;;;   - backpressure: a consumer that stops, and the origin's report that its
;;;     writes stalled, over HTTP/1.1;
;;;   - the token's bound: at most stream-buffer bytes or one chunk;
;;;   - the resume at half the buffer; one resume per pause, and a resume
;;;     for a token taken out since, passed over;
;;;   - the pause state under stress: a stream-buffer of 1 byte over HTTP/2,
;;;     a fast consumer; and the window the second review's model found: a
;;;     take held, by a test seam, between its look and its removal while
;;;     the write callable pauses, whose next look must queue the resume;
;;;   - follow beside stream-buffer, refused, stream-with-rounds, however
;;;     the two came together, and the hatch's HTTPAUTH refused as
;;;     owned-option, the credentials field's since M7 slice 2, whose Digest
;;;     is digest-with-stream (tests/test-auth.sps), and its PROXYAUTH, the
;;;     proxy field's since M7 slice 3, whose credentials go by Basic alone;
;;;     and an Expect
;;;     whose value holds 100-continue, by every path, at submit too, its
;;;     rule written out, folding A to Z alone;
;;;   - pause-failed: an answer but 0, by a test seam; a refusal planted in
;;;     a replay, and a body limit crossed in one, each the recorded reason,
;;;     on every libcurl, 7.85.0 and 8.5.0 among them, which lose a refusal
;;;     there and would end 0, the latter with its take held by a test seam
;;;     while the engine replays; the header callable's guard, by a raise
;;;     planted at a head's line;
;;;   - the resume step holds nothing across curl_easy_pause: a replay
;;;     stalled by a test seam, the engine's mutex, the stream's and a
;;;     collection free meanwhile;
;;;   - the body limit on a stream;
;;;   - the head: equal to the response's, before the first piece by the
;;;     body's delay, 1xx heads passed over on every face, and a CONNECT's in
;;;     a child; a 204 and a head request; head-wait on a token done with
;;;     none, and one with none yet;
;;;   - the take's escape: a child that plants a keyboard interrupt at a
;;;     take's section's end; and a timer swept a tick at a time across
;;;     next-piece's call and the port's read, with a planted control;
;;;   - the port: its ends, sticky; its thread rule, at read!, past what the
;;;     port had buffered; a read refused inside a
;;;     critical section; a close that cancels; each get-bytevector form's
;;;     loss at a failure, pinned;
;;;   - a stream operation on a token that does not stream, refused;
;;;   - a consumer slower than the bound: 28 at it;
;;;   - the paced poll: the process's CPU through a 2 s pause, and its
;;;     control, which spins on 8.5.0 by version; its rule, by a test seam
;;;     that wakes the poll, paced with a stream paused alone, never with a
;;;     message taken, nor with none paused, nor with pacing off; a resume's
;;;     delay; the look, a message queued before the perform carried out at
;;;     once;
;;;   - cancel, stop and the engine's failure while paused;
;;;   - the thread rule: every consumer on the caller's thread, the chunk
;;;     log's threads the engine's alone;
;;;   - no multiplexing on 8.7.0 and 8.7.1: the rule, written out, and, by a
;;;     test seam, two HTTP/2 transfers on one connection by default, on one
;;;     each without;
;;;   - the header callable's lock, beside a thread that collects;
;;;   - an order no behaviour shows, read from engine.sls as data: a look
;;;     reads whether its token is done first.
;;;
;;; Every check that reaches the raw face runs on an engine of its own,
;;; whose scripts close their connections without saying so (ADR-0020).
;;;
;;; A suite cannot tell whether it runs under the memory gate's Valgrind, so
;;; every bound holds there too (the plan's section 4.1, as measured). Every
;;; expected value is one the code under test cannot produce by failing:
;;; SRFI-64 makes #f of a raise in the actual expression, so none is #f.
(import (rnrs)
        (rnrs mutable-strings)
        (srfi :64)
        (only (chezscheme) fork-thread make-mutex with-mutex sleep make-time current-time
              time-second time-nanosecond getenv get-thread-id library-directories
              collect-rendezvous critical-section set-timer timer-interrupt-handler
              port-closed? parameterize get-bytevector-some! make-list list-head
              binary-port-input-count)
        (curl-testing)
        (curl)
        (curl unsupported)
        (curl private engine)
        (only (curl private transfer) curl-request-following curl-request-with-fault planted-fault
              stream-verdicts expect-continue? ascii-folded curl-request-with-head-fault
              planted-head-fault)
        (curl private conditions)
        (curl private counters))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; written : Any -> String
(define (written x) (call-with-string-output-port (lambda (p) (write x p))))

;; The simple runner names a failing test but not its values. Print both,
;; cut to 2000 characters each.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (let ((cut (lambda (x) (let ((t (written x)))
                                 (if (> (string-length t) 2000) (string-append (substring t 0 2000) "...") t)))))
          (display "  expected: ")
          (display (cut (test-result-ref r 'expected-value)))
          (newline)
          (display "  actual:   ")
          (display (cut (test-result-ref r 'actual-value)))
          (newline))))))

(test-begin "stream")

;; --- helpers --------------------------------------------------------------------------

(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0)))

;; The counts while the suite's engine runs: its multi handle and its slot.
(define running-counts
  '((block . 1) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 1)))

;; The counts while the suite's engine and one more run: a check's own.
(define own-running-counts
  '((block . 2) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 2)))

;; The loaded libcurl's version, read on this thread before any is forked.
(define version
  (guard (e (#t (list 'no-version (describe e))))
    (libcurl-info-version (loaded-libcurl))))

;; now-ns : -> Integer
(define (now-ns)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000000000) (time-nanosecond t))))

;; now-ms : -> Integer
(define (now-ms) (div (now-ns) 1000000))

;; cpu-ms : -> Real
;; This process's CPU time, every thread's, in ms.
(define (cpu-ms)
  (let ((t (current-time 'time-process)))
    (+ (* (time-second t) 1000) (/ (time-nanosecond t) 1000000))))

;; pause-ms : Natural -> Unit
(define (pause-ms ms)
  (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))

;; latin-1 : Bytevector -> String
(define (latin-1 bytes)
  (list->string (map integer->char (bytevector->u8-list bytes))))

;; wait-for : (-> Any) Natural -> Any
;; THUNK's first true answer, read every 1 ms, or #f after MS ms.
(define (wait-for thunk ms)
  (let ((deadline (+ (now-ms) ms)))
    (let loop ()
      (or (thunk)
          (and (< (now-ms) deadline)
               (begin (pause-ms 1) (loop)))))))

;; url-of : Origin Symbol String -> String
(define (url-of o face path)
  (let ((f (origin-face o face)))
    (string-append (if (memq face '(https h2)) "https://" "http://")
                   (car f) ":" (number->string (cdr f)) path)))

;; The run's PKI, for the TLS faces.
(define pki-made
  (guard (e (#t (list 'raised (describe e))))
    (list 'made (make-test-pki))))
(define pki (and (eq? (car pki-made) 'made) (cadr pki-made)))
(define ca (and pki (string-append pki "/ca.pem")))

;; stream-request : Origin Symbol String . (Listof Any) -> Request
;; A GET of PATH on FACE, direct, a 60 s timeout, streamed at 65,536 bytes,
;; the run's CA file for a TLS face; KEYS, key then value, replace these.
(define (stream-request o face path . keys)
  (let ((r (make-curl-request (url-of o face path) 'proxy #f 'timeout-ms 60000 'stream-buffer 65536)))
    (apply curl-request-with (if (memq face '(https h2)) (curl-request-with r 'ca-file ca) r) keys)))

;; pattern-path : Symbol Natural String -> String
;; The path of N bytes of the pattern, byte i being i mod 251, on FACE: the
;; raw face's script, 65,536 bytes a write, its record under KEY; the
;; others' route.
(define (pattern-path face n key)
  (if (eq? face 'raw)
      (string-append "/raw/pattern?key=" key "&bytes=" (number->string n) "&chunk=65536")
      (string-append "/pattern/" (number->string n))))

;; bad-at : Bytevector Natural -> (U Natural #f)
;; The offset in the body of PIECE's first byte that is not the pattern's,
;; PIECE holding the body's bytes from AT; #f when every one is.
(define (bad-at piece at)
  (let ((n (bytevector-length piece)))
    (let loop ((i 0) (v (mod at 251)))
      (cond ((= i n) #f)
            ((= (bytevector-u8-ref piece i) v) (loop (+ i 1) (if (= v 250) 0 (+ v 1))))
            (else (+ at i))))))

;; drain-pieces : Token Natural [Natural] -> (List Natural (U 'in-order (List 'bad Natural)) Any)
;; Every piece TOKEN gives by curl-token-next-piece, each waited for up to
;; MS, checked against the pattern from offset FROM: the bytes taken,
;; whether every one was the pattern's, and how it ended: eof, or what
;; next-piece answered else.
(define drain-pieces
  (case-lambda
    ((token ms) (drain-pieces token ms 0))
    ((token ms from)
     (let loop ((at from) (bad #f))
       (let ((piece (curl-token-next-piece token ms)))
         (if (bytevector? piece)
             (loop (+ at (bytevector-length piece)) (or bad (bad-at piece at)))
             (list (- at from) (if bad (list 'bad bad) 'in-order)
                   (if (eof-object? piece) 'eof piece))))))))

;; drain-port : Binary-Input-Port [Natural] -> (List Natural (U 'in-order (List 'bad Natural)) Any)
;; As drain-pieces, through PORT by get-bytevector-some, ended by its eof,
;; or by what it raised, as (raised TEXT).
(define drain-port
  (case-lambda
    ((port) (drain-port port 0))
    ((port from)
     (let loop ((at from) (bad #f))
       (let ((bytes (guard (e (#t (list 'raised (describe e)))) (get-bytevector-some port))))
         (if (bytevector? bytes)
             (loop (+ at (bytevector-length bytes)) (or bad (bad-at bytes at)))
             (list (- at from) (if bad (list 'bad bad) 'in-order) (if (eof-object? bytes) 'eof bytes))))))))

;; stat : Token Symbol -> Any
(define (stat token key)
  (cdr (assq key (curl-token-stream-stats token))))

;; paused? : Token -> Boolean
;; Whether TOKEN's transfer is paused for receiving with no resume queued.
(define (paused? token)
  (and (stat token 'paused) (not (stat token 'queued))))

;; class-of : Any -> Symbol
(define (class-of c)
  (cond ((curl-timeout? c) 'timeout) ((curl-connect-error? c) 'connect)
        ((curl-send-receive-error? c) 'send-receive) ((curl-tls-error? c) 'tls)
        ((curl-protocol-error? c) 'protocol) ((curl-too-large? c) 'too-large)
        (else 'none)))

;; outcome-of : Token -> Any
;; TOKEN's outcome, as data: (response STATUS VERSION BODY); (transfer-error
;; REASON CODE CLASS); (engine-error REASON CONDITION); not-done; or
;; (other TEXT).
(define (outcome-of token)
  (let ((o (curl-token-outcome token)))
    (cond ((not o) 'not-done)
          ((curl-response? o)
           (list 'response (curl-response-status o) (curl-response-http-version o) (curl-response-body o)))
          ((curl-transfer-error? o)
           (list 'transfer-error (curl-transfer-error-reason o) (curl-transfer-error-code o) (class-of o)))
          ((curl-engine-error? o)
           (list 'engine-error (curl-engine-error-reason o) (curl-engine-error-condition o)))
          (else (list 'other (describe o))))))

;; raised : (-> Any) -> Any
;; What THUNK raises, as data: (assertion-violation WHO), (request-refused
;; FIELD VALUE REASON), (wrong-thread WHO EXPECTED ACTUAL), (transfer-error
;; REASON CODE), or (raised TEXT); (returned VALUE) when it raises nothing.
(define (raised thunk)
  (guard (e ((curl-wrong-thread? e)
             (list 'wrong-thread (curl-wrong-thread-who e) (curl-wrong-thread-expected e)
                   (curl-wrong-thread-actual e)))
            ((curl-request-error? e)
             (list 'request-refused (curl-request-error-field e) (curl-request-error-value e)
                   (curl-request-error-reason e)))
            ((curl-transfer-error? e)
             (list 'transfer-error (curl-transfer-error-reason e) (curl-transfer-error-code e)))
            ((and (assertion-violation? e) (who-condition? e))
             (list 'assertion-violation (condition-who e)))
            (#t (list 'raised (describe e))))
    (list 'returned (thunk))))

;; stop-bounded : Engine -> Any
;; curl-engine-stop of ENGINE on a thread of its own, waited for up to
;; 20 s: stopped, or never-stopped.
(define (stop-bounded engine)
  (let ((mx (make-mutex)) (done #f))
    (fork-thread (lambda ()
                   (guard (e (#t #f)) (curl-engine-stop engine))
                   (with-mutex mx (set! done #t))))
    (if (wait-for (lambda () (with-mutex mx done)) 20000) 'stopped 'never-stopped)))

;; on-own-engine : (Engine -> Any) -> Any
;; PROC's answer, given an engine made for it and stopped once it returns:
;; an engine of its own starts with an empty pool, and its seams are its
;; alone; (raised TEXT) for a raise.
(define (on-own-engine make proc)
  (guard (e (#t (list 'raised (describe e))))
    (let* ((own (make))
           (answer (guard (e (#t (list 'raised (describe e)))) (proc own))))
      (stop-bounded own)
      answer)))

;; on-engine-for : Symbol (Engine -> Any) -> Any
;; PROC's answer, given an engine of its own, as on-own-engine, for the raw
;; face, whose scripts close their connections without saying so: no
;; other check's pool reaches it, nor its pool another check (ADR-0020;
;; the M6 plan, section 3.8). The suite's engine for any other face.
(define (on-engine-for face proc)
  (if (eq? face 'raw) (on-own-engine make-curl-engine proc) (proc engine)))

;; on-thread : (-> Any) Natural -> Any
;; THUNK's answer, run on a thread of its own, waited for up to MS: what
;; it raised as (raised TEXT), (never-answered) after MS.
(define (on-thread thunk ms)
  (let ((mx (make-mutex)) (answer #f) (done #f))
    (fork-thread (lambda ()
                   (let ((a (guard (e (#t (list 'raised e))) (list 'answered (thunk)))))
                     (with-mutex mx (set! answer a) (set! done #t)))))
    (if (wait-for (lambda () (with-mutex mx done)) ms)
        (with-mutex mx answer)
        '(never-answered))))

;; stalls-report : Origin Engine String -> (U (List Natural (U Natural 'none)) List)
;; The raw face's record of KEY's pattern, (WRITTEN STALLED), read on
;; ENGINE as a whole body.
(define (stalls-report o engine key)
  (guard (e (#t (list 'raised (describe e))))
    (let* ((r (curl-token-await (curl-submit engine (make-curl-request (url-of o 'raw (string-append "/raw/stalls?key=" key))
                                                                   'proxy #f 'timeout-ms 20000))))
           (port (open-string-input-port (latin-1 (curl-response-body r))))
           (words (let loop ((found '()))
                    (let ((d (read port))) (if (eof-object? d) (reverse found) (loop (cons d found)))))))
      (if (and (= (length words) 4) (eq? (car words) 'written))
          (list (cadr words) (cadddr words))
          (list 'unread words)))))

;; library-path : -> String
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

;; child-script : String
;; sh -c CHILD-SCRIPT sh COMMAND...: COMMAND, its stdin at its end, under
;; GNU timeout (gtimeout on macOS), killed with SIGKILL after 60 s, exit
;; 137. The shell's own stderr is /dev/null, so dash's "Killed" is not the
;; command's (traps.md).
(define child-script
  (string-append
   "t=$(command -v timeout || command -v gtimeout) || { echo 'stream child: no timeout' >&2; exit 125; }\n"
   "exec 3>&2 2>/dev/null\n"
   "( exec \"$t\" -s KILL 60 \"$@\" </dev/null 2>&3 3>&- )\n"
   "exit $?\n"))

;; run-child : (Listof String) String . (Listof String) -> (List Integer (Listof Any) String)
;; tests/PROGRAM with ARGS in a child Chez, under child-script, ENV, each
;; NAME=VALUE, in its environment alone, and no_proxy and NO_PROXY unset:
;; its exit status, what it printed, read as data, and its stderr.
(define (run-child env program . args)
  (guard (e (#t (list 'raised (describe e) "")))
    (let ((r (capture-command (append (list "sh" "-c" child-script "sh" "env" "-u" "no_proxy" "-u" "NO_PROXY")
                                      env
                                      (list (getenv "CHEZ") "--libdirs" (library-path) "--program" program)
                                      args))))
      (list (car r) (read-all (cadr r)) (caddr r)))))

;; --- the suite's engine -------------------------------------------------------------

(define main-thread (get-thread-id))

(define engine
  (guard (e (#t (list 'raised (describe e))))
    (make-curl-engine)))

(test-equal "the suite's engine is made, running, and the PKI is this run's"
  (list #t 'running 'made running-counts)
  (list (curl-engine? engine) (and (curl-engine? engine) (curl-engine-state engine)) (car pki-made)
        (native-counts)))

(define engine-thread (and (curl-engine? engine) (curl-engine-thread engine)))

;; --- the key and its refusals (no origin) ------------------------------------------

;; rounds-refused : (-> Request) -> Any
(define (rounds-refused who make)
  (let ((answer (raised make)))
    (if (equal? answer (list 'request-refused 'stream-buffer 10 'stream-with-rounds))
        (list who 'refused)
        answer)))

(test-equal "follow beside stream-buffer is refused as stream-with-rounds, naming stream-buffer and its value, however the two came together: the private following constructor of a streamed request, and curl-request-with of a following one; the hatch's HTTPAUTH and PROXYAUTH are refused as owned-option, the credentials field's and the proxy field's, before any stream is seen"
  '((following refused) (with-follow refused)
    (request-refused options "HTTPAUTH" owned-option) (request-refused options "HTTPAUTH" owned-option)
    (request-refused options "PROXYAUTH" owned-option) (request-refused options "PROXYAUTH" owned-option))
  (list (rounds-refused 'following
          (lambda () (curl-request-following (make-curl-request "http://a/" 'stream-buffer 10))))
        (rounds-refused 'with-follow
          (lambda () (curl-request-with (curl-request-following (make-curl-request "http://a/"))
                                        'stream-buffer 10)))
        (rounds-refused 'options-httpauth
          (lambda () (curl-request-with-options (make-curl-request "http://a/" 'stream-buffer 10)
                                                '(("HTTPAUTH" . 1)))))
        (rounds-refused 'with-httpauth
          (lambda () (curl-request-with (curl-request-with-options (make-curl-request "http://a/")
                                                                   '(("HTTPAUTH" . 1)))
                                        'stream-buffer 10)))
        (rounds-refused 'options-proxyauth
          (lambda () (curl-request-with-options (make-curl-request "http://a/" 'stream-buffer 10)
                                                '(("PROXYAUTH" . 1)))))
        (rounds-refused 'with-proxyauth
          (lambda () (curl-request-with (curl-request-with-options (make-curl-request "http://a/")
                                                                   '(("PROXYAUTH" . 1)))
                                        'stream-buffer 10)))))

(test-equal "beside each other but not beside stream-buffer, each is taken: follow on a whole body, and stream-buffer beside another hatch option, LOW_SPEED_TIME; stream-buffer #f clears the refusal; PROXYAUTH and HTTPAUTH on a whole body are refused as owned-option"
  '((returned #t) (request-refused options "PROXYAUTH" owned-option)
    (request-refused options "HTTPAUTH" owned-option) (returned #t) (returned #t)
    (returned #t))
  (list (raised (lambda () (curl-request? (curl-request-following (make-curl-request "http://a/")))))
        (raised (lambda () (curl-request? (curl-request-with-options (make-curl-request "http://a/")
                                                                     '(("PROXYAUTH" . 1))))))
        (raised (lambda () (curl-request? (curl-request-with-options (make-curl-request "http://a/")
                                                                     '(("HTTPAUTH" . 1))))))
        (raised (lambda () (curl-request? (curl-request-with-options (make-curl-request "http://a/" 'stream-buffer 10)
                                                                     '(("LOW_SPEED_TIME" . 30))))))
        (raised (lambda () (curl-request? (curl-request-with (curl-request-following
                                                              (curl-request-with (make-curl-request "http://a/" 'stream-buffer 10)
                                                                                 'stream-buffer #f))))))
        (raised (lambda () (curl-request? (curl-request-with-fault (make-curl-request "http://a/" 'stream-buffer 10) 2))))))

;; --- an Expect of 100-continue: a 417 is a second request (the review of slice 1) ----

;; method-request : Symbol . (Listof Any) -> Request
;; A request of METHOD to http://a/, a body of three bytes where METHOD
;; sends one, KEYS after.
(define (method-request method . keys)
  (apply make-curl-request "http://a/" 'method method
         (append (if (memq method '(post put patch)) (list 'body (u8-list->bytevector '(1 2 3))) '()) keys)))

(define expect-continue '(("Expect" . "100-continue")))

(test-equal "an Expect header whose value holds 100-continue beside stream-buffer is refused as stream-with-rounds, naming stream-buffer and its value, whatever the method, though libcurl resends on a 417 only a request that sends a body; by make-curl-request, by curl-request-with adding stream-buffer, and adding the header; the name and the value in any ASCII case; the header after others"
  '((get refused) (head refused) (post refused) (put refused) (patch refused) (delete refused)
    (with-stream refused) (with-headers refused) (cased refused) (after-others refused))
  (list (rounds-refused 'get (lambda () (method-request 'get 'headers expect-continue 'stream-buffer 10)))
        (rounds-refused 'head (lambda () (method-request 'head 'headers expect-continue 'stream-buffer 10)))
        (rounds-refused 'post (lambda () (method-request 'post 'headers expect-continue 'stream-buffer 10)))
        (rounds-refused 'put (lambda () (method-request 'put 'headers expect-continue 'stream-buffer 10)))
        (rounds-refused 'patch (lambda () (method-request 'patch 'headers expect-continue 'stream-buffer 10)))
        (rounds-refused 'delete (lambda () (method-request 'delete 'headers expect-continue 'stream-buffer 10)))
        (rounds-refused 'with-stream
          (lambda () (curl-request-with (method-request 'post 'headers expect-continue) 'stream-buffer 10)))
        (rounds-refused 'with-headers
          (lambda () (curl-request-with (method-request 'post 'stream-buffer 10) 'headers expect-continue)))
        (rounds-refused 'cased
          (lambda () (method-request 'post 'headers '(("eXPECT" . "100-ConTinue")) 'stream-buffer 10)))
        (rounds-refused 'after-others
          (lambda () (method-request 'post 'headers '(("Accept" . "*/*") ("Expect" . "foo") ("Expect" . "x100-continue"))
                                     'stream-buffer 10)))))

(test-equal "beside an Expect that names no 100-continue, or none beside stream-buffer, each is taken: Expect of 100-continu, 1oo-continue and 100 continue, a 100-continue in another header, streamed; Expect of 100-continue on a whole body; stream-buffer #f clears the refusal"
  '((returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (returned #t))
  (list (raised (lambda () (curl-request? (method-request 'post 'headers '(("Expect" . "100-continu")) 'stream-buffer 10))))
        (raised (lambda () (curl-request? (method-request 'post 'headers '(("Expect" . "1oo-continue")) 'stream-buffer 10))))
        (raised (lambda () (curl-request? (method-request 'post 'headers '(("Expect" . "100 continue")) 'stream-buffer 10))))
        (raised (lambda () (curl-request? (method-request 'post 'headers '(("X-Expect" . "100-continue")) 'stream-buffer 10))))
        (raised (lambda () (curl-request? (method-request 'post 'headers expect-continue))))
        (raised (lambda () (curl-request? (curl-request-with (method-request 'post 'headers expect-continue)
                                                             'stream-buffer #f))))))

(test-equal "the Expect rule holds at submit, on the submit's own copies: a streamed request made beside Expect: 100-xontinue, checked and taken, then its value's string changed to 100-continue, is refused by curl-submit and curl-request-check alike, stream-with-rounds; so is one beside Xxpect: 100-continue whose name's string changed to Expect; nothing native made"
  (list '((returned checked) (returned checked))
        '(request-refused stream-buffer 10 stream-with-rounds) '(request-refused stream-buffer 10 stream-with-rounds)
        '(request-refused stream-buffer 10 stream-with-rounds) '(request-refused stream-buffer 10 stream-with-rounds)
        running-counts)
  (guard (e (#t (list 'raised (describe e))))
    (let* ((value (string-copy "100-xontinue"))
           (name (string-copy "Xxpect"))
           (by-value (make-curl-request "http://127.0.0.1:1/" 'method 'post 'proxy #f 'timeout-ms 5000
                                        'headers (list (cons "Expect" value)) 'stream-buffer 10))
           (by-name (make-curl-request "http://127.0.0.1:1/" 'method 'post 'proxy #f 'timeout-ms 5000
                                       'headers (list (cons name "100-continue")) 'stream-buffer 10))
           (before (list (raised (lambda () (curl-request-check by-value) 'checked))
                         (raised (lambda () (curl-request-check by-name) 'checked)))))
      (string-set! value 4 #\c)
      (string-set! name 0 #\E)
      (list before
            (raised (lambda () (curl-submit engine by-value)))
            (raised (lambda () (curl-request-check by-value)))
            (raised (lambda () (curl-submit engine by-name)))
            (raised (lambda () (curl-request-check by-name)))
            (native-counts)))))

(test-equal "expect-continue?, the rule: a header named Expect, in any ASCII case, whose value holds 100-continue, in any ASCII case, anywhere, as 7.85.0 and 8.5.0 read it, x100-continue, y100-continuez, 100-continue;q=1 and a, 100-continue among them; any Expect header, not only the first; no other name, and no value without it"
  '(#t #t #t #t #t #t #t #t #f #f #f #f #f #f #f #f)
  (map expect-continue?
       '((("Expect" . "100-continue")) (("EXPECT" . "100-CONTINUE")) (("eXpEcT" . "100-Continue"))
         (("Expect" . "x100-continue")) (("Expect" . "y100-continuez")) (("Expect" . "100-continue;q=1"))
         (("Expect" . "a, 100-continue")) (("Accept" . "*/*") ("Expect" . "foo") ("Expect" . "100-continue"))
         (("Expect" . "100-continu")) (("Expect" . "1oo-continue")) (("Expect" . "100 continue"))
         (("X-Expect" . "100-continue")) (("Expectation" . "100-continue")) (("Expec" . "100-continue"))
         (("Expect" . "")) ())))

(test-equal "ascii-folded folds A to Z alone: over every char of the BMP but the surrogates, each of A to Z becomes its lower case, one char, and every other char stays, U+017F LONG S, U+212A KELVIN SIGN and U+0130 among them, which char-foldcase, string-ci=? or char-downcase fold to s, k or i; so 100-cont\x130;nue is no 100-continue"
  (list '() "\x17F;\x212A;\x130;\xDF;" #f)
  (list (let loop ((i 0) (wrong '()))
          (cond ((= i #x10000) (reverse wrong))
                ((<= #xD800 i #xDFFF) (loop (+ i 1) wrong))
                (else
                 (let* ((c (integer->char i))
                        (expected (if (char<=? #\A c #\Z) (integer->char (+ i 32)) c)))
                   (loop (+ i 1) (if (equal? (ascii-folded (string c)) (string expected)) wrong (cons i wrong)))))))
        (ascii-folded "\x17F;\x212A;\x130;\xDF;")
        (expect-continue? '(("Expect" . "100-cont\x130;nue")))))

;; --- no multiplexing on 8.7.0 and 8.7.1 (ADR-0030, amended 2026-10-29) ------------

(test-equal "unmultiplexed-versions, written out here: 8.7.0 and 8.7.1"
  '("8.7.0" "8.7.1")
  unmultiplexed-versions)

(test-equal "multiplexing-off?, the rule: off on 8.7.0 and 8.7.1 alone, by the whole version, never a prefix"
  '(#f #f #f #f #t #t #f #f #f #f #f)
  (map multiplexing-off? '("7.85.0" "8.5.0" "8.6.0" "8.7" "8.7.0" "8.7.1" "8.7.10" "8.7.1-DEV" "8.8.0" "8.20.0" "8.23.0")))

(test-equal "an engine sets CURLMOPT_PIPELINING to 0 as the rule says for the loaded libcurl, and the test seam's always does"
  (list (if (multiplexing-off? version) 'off 'default) 'off)
  (list (if (curl-engine? engine) (curl-engine-multiplexing engine) engine)
        (on-own-engine make-curl-engine-unmultiplexed curl-engine-multiplexing)))

;; --- a stream operation on a token that does not stream ---------------------------

(test-equal "a stream operation on a token whose request does not stream its response is an assertion violation from its name, before anything: next-piece, the port, the head and head-wait"
  '((assertion-violation curl-token-next-piece) (assertion-violation curl-token-body-port)
    (assertion-violation curl-token-head) (assertion-violation curl-token-head-wait))
  (guard (e (#t (list 'raised (describe e))))
    (let ((t (curl-submit engine (make-curl-request "http://127.0.0.1:1/" 'proxy #f 'timeout-ms 5000))))
      (curl-token-wait t 10000)
      (list (raised (lambda () (curl-token-next-piece t 0)))
            (raised (lambda () (curl-token-body-port t)))
            (raised (lambda () (curl-token-head t)))
            (raised (lambda () (curl-token-head-wait t 0)))))))

(test-equal "each stream operation refuses what is no token, an assertion violation from its name"
  '((assertion-violation curl-token-next-piece) (assertion-violation curl-token-body-port)
    (assertion-violation curl-token-head) (assertion-violation curl-token-head-wait))
  (list (raised (lambda () (curl-token-next-piece 'no 0)))
        (raised (lambda () (curl-token-body-port 'no)))
        (raised (lambda () (curl-token-head 'no)))
        (raised (lambda () (curl-token-head-wait 'no 0)))))

;; --- the order no behaviour shows, read from engine.sls as data ------------------
;; A look reads whether its token is done before it looks at the stream, so
;; the last piece is never taken for the end: an order a check can watch
;; fail only in a window of a few instructions. Its limit is test-transfer's
;; orders': it holds an accidental move, not a rewrite made to pass it.
;; What the resume step holds across curl_easy_pause is watched by
;; behaviour, a replay stalled by a test seam, among the scenarios.

(define engine-source "src/curl/private/engine.sls")

;; engine-library : Any
(define engine-library
  (guard (e (#t (list 'unreadable (describe e))))
    (call-with-port (open-file-input-port engine-source (file-options) (buffer-mode block)
                                          (make-transcoder (utf-8-codec)))
      read)))

;; engine-definition : Symbol -> Any
;; The (define (NAME ...) ...) form in engine.sls's library, or #f.
(define (engine-definition name)
  (and (pair? engine-library) (eq? (car engine-library) 'library)
       (find (lambda (form)
               (and (pair? form) (eq? (car form) 'define) (pair? (cdr form)) (pair? (cadr form))
                    (eq? (car (cadr form)) name)))
             (cddddr engine-library))))

;; symbols-in : (Listof Symbol) Any -> (Listof Symbol)
;; Each of NAMES standing in X, in the order written, depth first.
(define (symbols-in names x)
  (cond ((and (symbol? x) (memq x names)) (list x))
        ((pair? x) (append (symbols-in names (car x)) (symbols-in names (cdr x))))
        (else '())))

(test-equal "look, read from engine.sls: whether the token is done, its state, is read before stream-look!, and, after it, whether it is live, then the resume queued"
  '(token-state stream-look! token-state curl-engine-queue-set!)
  (symbols-in '(token-state stream-look! curl-engine-queue-set!) (engine-definition 'look)))

;; --- against the origin ----------------------------------------------------------------

(define (scenarios o)

  ;; --- every byte in order, over every face, by next-piece and by the port
  (for-each
   (lambda (face)
     (test-equal (string-append (symbol->string face) ": 4 MiB of the pattern, by next-piece and through the port, each whole and in order, then the end; each outcome a 200 whose body is #f, over "
                                (if (eq? face 'h2) "HTTP/2" "HTTP/1.1"))
       (let ((v (if (eq? face 'h2) 'http/2 'http/1.1)))
         (list '(4194304 in-order eof) '(4194304 in-order eof)
               (list 'response 200 v #f) (list 'response 200 v #f)
               (if (eq? face 'raw) own-running-counts running-counts)))
       (on-engine-for face
         (lambda (engine)
           (let* ((t1 (curl-submit engine (stream-request o face (pattern-path face 4194304 "every-1"))))
                  (d1 (drain-pieces t1 30000))
                  (t2 (curl-submit engine (stream-request o face (pattern-path face 4194304 "every-2"))))
                  (port (curl-token-body-port t2))
                  (d2 (drain-port port)))
             (close-port port)
             (curl-token-wait t1 10000)
             (curl-token-wait t2 10000)
             (list d1 d2 (outcome-of t1) (outcome-of t2) (native-counts)))))))
   '(http raw https h2))

  (test-equal "a piece is the caller's: a fresh bytevector of a byte or more, no other piece's; overwritten, it changes nothing the stream gives after, nor what it counts"
    '(fresh-pieces 1000000 in-order eof taken-counted)
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((t (curl-submit engine (stream-request o 'raw "/raw/pattern?key=own&bytes=1000000&chunk=4096&gap=1")))
               (p1 (curl-token-next-piece t 20000))
               (p2 (curl-token-next-piece t 20000))
               (fresh (and (bytevector? p1) (bytevector? p2) (> (bytevector-length p1) 0)
                           (> (bytevector-length p2) 0) (not (eq? p1 p2))
                           (not (bad-at p1 0)) (not (bad-at p2 (bytevector-length p1)))))
               (n1 (and (bytevector? p1) (bytevector-length p1)))
               (n2 (and (bytevector? p2) (bytevector-length p2))))
          (when fresh
            (bytevector-fill! p1 255)
            (bytevector-fill! p2 255))
          (let ((d (drain-pieces t 20000 (+ n1 n2))))
            (list (if fresh 'fresh-pieces (list p1 p2))
                  (+ n1 n2 (car d)) (cadr d) (caddr d)
                  (if (= (stat t 'taken) 1000000) 'taken-counted (stat t 'taken))))))))

  ;; --- throughput: 64 MiB through the write callable and a consumer of
  ;; pieces, within 60 s, the bound the memory gate's Valgrind needs; the
  ;; plan measured up to 1.63 s natively and 9.48 s under Valgrind (section
  ;; 4.1, as measured).
  (for-each
   (lambda (face)
     (test-equal (string-append (symbol->string face) ": 64 MiB at a stream-buffer of 65,536 bytes, taken as they come, whole and in order within 60 s")
       '(67108864 in-order eof within-60-s (response 200))
       (guard (e (#t (list 'raised (describe e))))
         (let* ((t0 (now-ms))
                (t (curl-submit engine (stream-request o face (pattern-path face 67108864 "throughput"))))
                (d (drain-pieces t 60000))
                (took (- (now-ms) t0)))
           (curl-token-wait t 10000)
           (append d (list (if (< took 60000) 'within-60-s took)
                           (let ((r (outcome-of t))) (if (pair? r) (list-head r 2) r))))))))
   '(http h2))

  ;; --- backpressure, over HTTP/1.1
  (test-equal "backpressure: a consumer that stops, over the raw face: the stream pauses with at most one chunk or its buffer held; the origin reports its writes stalled, short of the body, and no byte more taken by the kernel across a second; read again, 64 MiB come whole and in order, every write taken"
    '(paused held-bounded stalled-short still 67108864 in-order eof all-written)
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((t (curl-submit engine (stream-request o 'raw (pattern-path 'raw 67108864 "stop"))))
               (paused (wait-for (lambda () (paused? t)) 20000))
               (r1 (begin (pause-ms 500) (stalls-report o engine "stop")))
               (r2 (begin (pause-ms 1000) (stalls-report o engine "stop")))
               (most (stat t 'most))
               (d (drain-pieces t 60000))
               (r3 (begin (curl-token-wait t 10000) (stalls-report o engine "stop"))))
          (list (if paused 'paused (curl-token-stream-stats t))
                (if (and (> most 0) (<= most 65536)) 'held-bounded most)
                (if (and (integer? (cadr r1)) (<= (cadr r1) (car r1)) (< (car r1) 67108864)) 'stalled-short r1)
                (if (equal? r1 r2) 'still (list r1 r2))
                (car d) (cadr d) (caddr d)
                (if (equal? r3 (list 67108864 (cadr r1))) 'all-written r3))))))

  ;; --- the token's bound
  (test-equal "the token's bound: at most stream-buffer bytes or one chunk, whichever is more, as the write callable's appends left it: at 20,000 bytes, under 20,000 with a consumer that stops and through a drain; at 1 byte, one chunk, 16,384 bytes at most"
    '((bounded 4194304 in-order eof) (bounded 1048576 in-order eof))
    (guard (e (#t (list 'raised (describe e))))
      (map (lambda (row)
             (on-own-engine make-curl-engine
               (lambda (engine)
                 (let* ((limit (car row)) (n (cadr row))
                        (t (curl-submit engine (stream-request o 'raw (pattern-path 'raw n "bound") 'stream-buffer limit)))
                        (paused (wait-for (lambda () (paused? t)) 20000))
                        (stopped-most (stat t 'most))
                        (d (drain-pieces t 30000))
                        (most (stat t 'most)))
                   (cons (if (and paused (> stopped-most 0) (<= stopped-most (max (- limit 1) 16384))
                                  (<= most (max (- limit 1) 16384)))
                             'bounded
                             (list 'paused paused 'stopped stopped-most 'drained most))
                         d)))))
           '((20000 4194304) (1 1048576)))))

  ;; --- a stream per submit, made with its token
  (test-equal "a request submitted twice makes a stream for each submit: two tokens of one request, their pieces taken in turn, each 1 MiB whole and in order"
    '((1048576 in-order eof) (1048576 in-order eof))
    (guard (e (#t (list 'raised (describe e))))
      (let* ((r (stream-request o 'http "/pattern/1048576" 'stream-buffer 16384))
             (a (curl-submit engine r))
             (b (curl-submit engine r)))
        (let loop ((at-a 0) (bad-a #f) (at-b 0) (bad-b #f) (a-end #f) (b-end #f))
          (if (and a-end b-end)
              (list (list at-a (if bad-a (list 'bad bad-a) 'in-order) a-end)
                    (list at-b (if bad-b (list 'bad bad-b) 'in-order) b-end))
              (let ((pa (if a-end #f (curl-token-next-piece a 20000)))
                    (pb (if b-end #f (curl-token-next-piece b 20000))))
                (loop (if (bytevector? pa) (+ at-a (bytevector-length pa)) at-a)
                      (or bad-a (and (bytevector? pa) (bad-at pa at-a)))
                      (if (bytevector? pb) (+ at-b (bytevector-length pb)) at-b)
                      (or bad-b (and (bytevector? pb) (bad-at pb at-b)))
                      (or a-end (and (not (bytevector? pa)) (if (eof-object? pa) 'eof pa)))
                      (or b-end (and (not (bytevector? pb)) (if (eof-object? pb) 'eof pb))))))))))

  (test-equal "a token still queued has its stream already: next-piece answers #f within its bound, and the head is #f, while the engine is held, inside its critical section, where no wait may sleep; then the stream comes whole"
    '((#f #f) (600 in-order eof))
    (guard (e (#t (list 'raised (describe e))))
      (let* ((queued (call-with-engine-held engine
                       (lambda ()
                         (let ((t (curl-submit engine (stream-request o 'http "/pattern/600"))))
                           (list t (curl-token-next-piece t 0) (curl-token-head t))))))
             (t (car queued)))
        (list (cdr queued) (drain-pieces t 20000)))))

  ;; --- one resume per pause, and a resume passed over
  (test-equal "the resume comes at half the buffer: paused with a stream-buffer of 100,000 bytes, no take queues a resume while the bytes left would be more than 50,000, and the first take that leaves 50,000 or fewer does"
    '(paused resume-at-half)
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((t (curl-submit engine (stream-request o 'raw (pattern-path 'raw 4194304 "half") 'stream-buffer 100000)))
               (paused (wait-for (lambda () (paused? t)) 20000))
               (appended (stat t 'appended))
               (resumes (stat t 'resumes)))
          (let loop ((steps '()))
            (let* ((piece (curl-token-next-piece t 5000))
                   (left (- appended (stat t 'taken)))
                   (resumed (or (stat t 'queued) (> (stat t 'resumes) resumes))))
              (cond
                ((not (bytevector? piece)) (list paused (reverse steps)))
                (resumed
                 (let ((rest (drain-pieces t 30000)))
                   (list (if paused 'paused (curl-token-stream-stats t))
                         (if (and (<= (* 2 left) 100000)
                                  (for-all (lambda (step) (> (* 2 step) 100000)) steps)
                                  (eq? (caddr rest) 'eof))
                             'resume-at-half
                             (list 'left left 'before (reverse steps) rest)))))
                (else (loop (cons left steps))))))))))

  (test-equal "one resume per pause: through a drain of 4 MiB at 65,536 bytes, every pause the write callable made was resumed, once, and the engine passed none over"
    '(4194304 in-order eof paused-and-resumed none-passed)
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((passed (curl-engine-passed-resumes engine))
               (t (curl-submit engine (stream-request o 'raw (pattern-path 'raw 4194304 "once"))))
               (paused (wait-for (lambda () (paused? t)) 20000))
               (d (drain-pieces t 30000)))
          (curl-token-wait t 10000)
          (append d (list (if (and paused (> (stat t 'pauses) 0) (= (stat t 'pauses) (stat t 'resumes)))
                              'paused-and-resumed
                              (list 'pauses (stat t 'pauses) 'resumes (stat t 'resumes)))
                          (if (= passed (curl-engine-passed-resumes engine)) 'none-passed
                              (list passed (curl-engine-passed-resumes engine)))))))))

  ;; The seamed engines resume too (M6 slice 2's measurement, unpaced.sps):
  ;; resume! read its pause-answer seam by assq, which raised on these
  ;; engines' bare-symbol seams, failing each at its first resume.
  (test-equal "each seamed engine resumes: 1 MiB at a stream-buffer of 1 byte, so every take that drains the buffer resumes it, on make-curl-engine-unpaced's engine and on make-curl-engine-unmultiplexed's, each whole and in order, a 200, resumed"
    '((1048576 in-order eof (response 200 http/1.1 #f) resumed)
      (1048576 in-order eof (response 200 http/1.1 #f) resumed))
    (map (lambda (make)
           (on-own-engine make
             (lambda (own)
               (let* ((t (curl-submit own (stream-request o 'http "/pattern/1048576" 'stream-buffer 1)))
                      (d (drain-pieces t 20000)))
                 (curl-token-wait t 10000)
                 (append d (list (outcome-of t)
                                 (if (> (stat t 'resumes) 0) 'resumed (curl-token-stream-stats t))))))))
         (list make-curl-engine-unpaced make-curl-engine-unmultiplexed)))

  (test-equal "a resume for a token taken out since is passed over: a cancel and then a take that queues a resume, while the engine is held, reach one turn, which carries out the cancel first; the token ends cancelled, its piece taken, the rest of what it held still readable, then the end"
    '(piece-taken (transfer-error cancelled #f none) one-passed in-order eof)
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((t (curl-submit engine (stream-request o 'raw (pattern-path 'raw 4194304 "passed") 'stream-buffer 1)))
               (paused (wait-for (lambda () (paused? t)) 20000))
               (passed (curl-engine-passed-resumes engine))
               (piece (call-with-engine-held engine
                        (lambda ()
                          (curl-token-cancel t)
                          (curl-token-next-piece t 0))))
               (done (curl-token-wait t 10000))
               (d (drain-pieces t 5000 (if (bytevector? piece) (bytevector-length piece) 0))))
          (list (if (and paused (bytevector? piece) (not (bad-at piece 0))) 'piece-taken (list paused piece))
                (outcome-of t)
                (if (and done (= (curl-engine-passed-resumes engine) (+ passed 1))) 'one-passed
                    (list done passed (curl-engine-passed-resumes engine)))
                (cadr d) (caddr d))))))

  ;; --- the pause state under stress
  (test-equal "the pause state under stress: a stream-buffer of 1 byte over HTTP/2, where replays pause again, 4 MiB taken by a consumer as fast as it can: whole and in order within 60 s, every pause resumed once"
    '(4194304 in-order eof within-bound resumed-once)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((t0 (now-ms))
             (t (curl-submit engine (stream-request o 'h2 "/pattern/4194304" 'stream-buffer 1)))
             (d (drain-pieces t 20000))
             (took (- (now-ms) t0)))
        (curl-token-wait t 10000)
        (append d (list (if (< took 60000) 'within-bound took)
                        (if (= (stat t 'pauses) (stat t 'resumes)) 'resumed-once
                            (list (stat t 'pauses) (stat t 'resumes))))))))

  (test-equal "the window every look closes: a take held, by a test seam, between its look and its removal, while the write callable finds the buffer full and pauses; once it removes its piece, the next take's look, finding no piece, queues the resume, and the next piece comes"
    '(first-piece paused-in-window second-piece 3000 in-order eof)
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((t (curl-submit engine (stream-request o 'raw "/raw/pattern?key=window&bytes=3000&chunk=1000&gap=1000"
                                                      'stream-buffer 1500)))
               (first-in (wait-for (lambda () (= (stat t 'appended) 1000)) 20000))
               (_ (curl-token-plant! t 'gate))
               (mx (make-mutex))
               (taken #f)
               (_t (fork-thread (lambda ()
                                  (let ((p (guard (e (#t (list 'raised (describe e)))) (curl-token-next-piece t 10000))))
                                    (with-mutex mx (set! taken (list p)))))))
               (held (wait-for (lambda () (eq? (curl-token-gate t) 'waiting)) 10000))
               (paused (wait-for (lambda () (stat t 'paused)) 10000))
               (window (list (stat t 'paused) (stat t 'queued) (stat t 'resumes)))
               (_o (curl-token-open-gate! t))
               (first (wait-for (lambda () (with-mutex mx taken)) 10000))
               (second (curl-token-next-piece t 5000)))
          (let ((d (drain-pieces t 20000 2000)))
            (list (if (and first-in held first (bytevector? (car first)) (= (bytevector-length (car first)) 1000)
                           (not (bad-at (car first) 0)))
                      'first-piece (list first-in held first))
                  (if (and paused (equal? window '(#t #f 0))) 'paused-in-window window)
                  (if (and (bytevector? second) (= (bytevector-length second) 1000) (not (bad-at second 1000)))
                      'second-piece second)
                  (+ 2000 (car d)) (cadr d) (caddr d)))))))

  ;; --- the resume step holds nothing across curl_easy_pause (the M6 plan,
  ;; section 3.4): a replay stalled 2 s by a test seam, inside the call, and
  ;; meanwhile the engine's mutex, the stream's, and a collection, each
  ;; within 500 ms. A mutex held across the call blocks the first two; a
  ;; critical section around it keeps the engine's thread active through
  ;; the stall's sleep, and blocks the collection.
  (test-equal "the resume step holds nothing across curl_easy_pause, by behaviour: a replay stalled 2,000 ms by a test seam, inside the call, the resume not yet counted; meanwhile this thread reads the engine's state under its mutex, the stream's stats under its, and collects, each within 500 ms; then 3,000 bytes come whole and in order, on an engine of its own"
    '(stalled-inside-pause engine-free stream-free collects 3000 in-order eof)
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((t (curl-submit engine (stream-request o 'raw "/raw/pattern?key=stall&bytes=3000&chunk=1000&gap=100"
                                                      'stream-buffer 1)))
               (paused (wait-for (lambda () (paused? t)) 20000))
               (resumes (stat t 'resumes))
               (_ (curl-token-plant-stall! t 2000))
               (piece (curl-token-next-piece t 5000))
               (stalling (wait-for (lambda () (eq? (curl-token-stall-state t) 'stalling)) 10000))
               (t0 (now-ns))
               (state (curl-engine-state engine))
               (t1 (now-ns))
               (stats (curl-token-stream-stats t))
               (t2 (now-ns))
               (_c (collect-rendezvous))
               (t3 (now-ns))
               (rest (drain-pieces t 20000 (if (bytevector? piece) (bytevector-length piece) 0))))
          (list (if (and paused (bytevector? piece) (= (bytevector-length piece) 1000) stalling
                         (eqv? (cdr (assq 'resumes stats)) resumes))
                    'stalled-inside-pause
                    (list paused (and (bytevector? piece) (bytevector-length piece)) stalling resumes stats))
                (if (and (eq? state 'running) (< (- t1 t0) 500000000)) 'engine-free (list state (- t1 t0)))
                (if (< (- t2 t1) 500000000) 'stream-free (- t2 t1))
                (if (< (- t3 t2) 500000000) 'collects (- t3 t2))
                (+ 1000 (car rest)) (cadr rest) (caddr rest))))))

  ;; --- pause-failed (ADR-0012, amended 2026-10-29)
  (test-equal "pause-failed: curl_easy_pause's answer but 0, given by a test seam as 43, fails the transfer as pause-failed, its code 43, of no class, its request size counted as one that ran; the piece taken stays the caller's, what the call's replay appended stays readable, in order, then the end"
    (list 'piece '(transfer-error pause-failed 43 none) 'request-size-read 'in-order 'eof running-counts)
    (on-own-engine (lambda () (make-curl-engine-answering-pause 43))
      (lambda (own)
        (let* ((t (curl-submit own (stream-request o 'raw (pattern-path 'raw 1048576 "pause-43") 'stream-buffer 1)))
               (paused (wait-for (lambda () (paused? t)) 20000))
               (piece (curl-token-next-piece t 5000))
               (done (curl-token-wait t 10000))
               (o (curl-token-outcome t))
               (rest (drain-pieces t 5000 (if (bytevector? piece) (bytevector-length piece) 0))))
          (stop-bounded own)
          (list (if (and paused done (bytevector? piece) (not (bad-at piece 0))) 'piece (list paused done piece))
                (outcome-of t)
                (let ((size (and (curl-transfer-error? o) (curl-transfer-error-request-size o))))
                  (if (or (and (integer? size) (> size 0)) (and (not size) (member version '("8.7.0" "8.7.1"))))
                      'request-size-read size))
                (cadr rest) (caddr rest)
                (native-counts))))))

  (test-equal "a refusal planted in a replay, the write callable's third call, the paused chunk handed again inside curl_easy_pause, fails the transfer by the recorded reason, callback-raised with the planted object, on every libcurl: 7.85.0 and 8.5.0 lose it there and end 0"
    (list 'paused (list 'transfer-error 'callback-raised 23 'none) (planted-fault 3) 'eof)
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((t (curl-submit engine (curl-request-with-fault
                                       (stream-request o 'raw "/raw/pattern?key=replay-fault&bytes=3000&chunk=1000&gap=300"
                                                       'stream-buffer 1)
                                       3)))
               (paused (wait-for (lambda () (paused? t)) 20000))
               (piece (curl-token-next-piece t 5000))
               (done (curl-token-wait t 10000))
               (o (curl-token-outcome t)))
          (list (if (and paused done (bytevector? piece) (= (bytevector-length piece) 1000)) 'paused (list paused done piece))
                (outcome-of t)
                (and (curl-transfer-error? o) (curl-transfer-error-recorded o))
                (let ((end (curl-token-next-piece t 5000))) (if (eof-object? end) 'eof end)))))))

  (test-equal "the header callable's guard: a raise planted at the head's second line, by the private (head 2), is recorded, callback-raised with the planted object, and fails the transfer by it, 23; no head published, the end at once, on an engine of its own, its counts back after"
    (list '(transfer-error callback-raised 23 none) (planted-head-fault 2) 'no-head 'eof running-counts)
    (on-own-engine make-curl-engine
      (lambda (own)
        (let* ((t (curl-submit own (curl-request-with-head-fault (stream-request o 'http "/pattern/1000") 2)))
               (done (curl-token-wait t 20000))
               (o (curl-token-outcome t))
               (head (curl-token-head t))
               (end (curl-token-next-piece t 5000)))
          (stop-bounded own)
          (list (if done (outcome-of t) 'not-done)
                (and (curl-transfer-error? o) (curl-transfer-error-recorded o))
                (if head (list 'head (curl-head-status head)) 'no-head)
                (if (eof-object? end) 'eof end)
                (native-counts))))))

  (test-equal "a body limit crossed in a replay, the paused chunk handed again past it, ends body-limit, the recorded reason, too-large, on every libcurl: the bytes under the limit taken, drained to the end, each take's look deciding the resume, then the outcome"
    '(paused 1000 in-order eof (transfer-error body-limit 23 too-large))
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((t (curl-submit engine (stream-request o 'raw "/raw/pattern?key=replay-limit&bytes=3000&chunk=1000&gap=300&framing=chunked"
                                                      'stream-buffer 1 'body-limit 1999)))
               (paused (wait-for (lambda () (paused? t)) 20000))
               (piece (curl-token-next-piece t 5000))
               (rest (drain-pieces t 10000 1000)))
          (list (if (and paused (bytevector? piece) (= (bytevector-length piece) 1000) (not (bad-at piece 0)))
                    'paused (list paused piece))
                (+ 1000 (car rest)) (cadr rest) (caddr rest)
                (outcome-of t))))))

  (test-equal "a body limit crossed in a replay, the take held by a test seam between its look and its removal while the engine replays: the replay finds the piece still in place and pauses again; once the take removes it, a drain's next look queues the resume, and the replay ends body-limit, too-large"
    '(paused paused-again 1000 in-order eof (transfer-error body-limit 23 too-large))
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((t (curl-submit engine (stream-request o 'raw "/raw/pattern?key=replay-limit-gated&bytes=3000&chunk=1000&gap=300&framing=chunked"
                                                      'stream-buffer 1 'body-limit 1999)))
               (paused (wait-for (lambda () (paused? t)) 20000))
               (pauses (stat t 'pauses))
               (_ (curl-token-plant! t 'gate))
               (mx (make-mutex))
               (taken #f)
               (_t (fork-thread (lambda ()
                                  (let ((p (guard (e (#t (list 'raised (describe e)))) (curl-token-next-piece t 10000))))
                                    (with-mutex mx (set! taken (list p)))))))
               (held (wait-for (lambda () (eq? (curl-token-gate t) 'waiting)) 10000))
               (again (wait-for (lambda () (and (> (stat t 'pauses) pauses) (paused? t))) 10000))
               (_o (curl-token-open-gate! t))
               (first (wait-for (lambda () (with-mutex mx taken)) 10000))
               (rest (drain-pieces t 10000 1000)))
          (list (if (and paused held first (bytevector? (car first)) (= (bytevector-length (car first)) 1000)
                         (not (bad-at (car first) 0)))
                    'paused (list paused held first))
                (if again 'paused-again (curl-token-stream-stats t))
                (+ 1000 (car rest)) (cadr rest) (caddr rest)
                (outcome-of t))))))

  ;; --- the body limit on a stream
  (test-equal "the body limit counts a stream's bytes as a whole body's: 2,500 against three chunks of 1,000, chunked, refuses the third, ending body-limit, too-large; the 2,000 under it whole and in order, then the end"
    '(2000 in-order eof (transfer-error body-limit 23 too-large))
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((t (curl-submit engine (stream-request o 'raw "/raw/pattern?key=limit&bytes=3000&chunk=1000&gap=100&framing=chunked"
                                                      'stream-buffer 1000000 'body-limit 2500)))
               (done (curl-token-wait t 20000))
               (d (drain-pieces t 5000)))
          (append d (list (outcome-of t)))))))

  ;; --- the head
  (for-each
   (lambda (face)
     (test-equal (string-append (symbol->string face)
                                ": a 100 and a 103 before the final head are passed over: the head is the 200, equal as whole values to the status, version and headers the response read at the end; the body early")
       (list 'head-arrived 200 'same "early\n")
       (on-engine-for face
         (lambda (engine)
           (let* ((t (curl-submit engine (stream-request o face (if (eq? face 'raw) "/raw/early" "/early"))))
                  (waited (curl-token-head-wait t 20000))
                  (head (curl-token-head t))
                  (body (let loop ((found '()))
                          (let ((p (curl-token-next-piece t 20000)))
                            (if (bytevector? p) (loop (append found (bytevector->u8-list p))) found))))
                  (r (curl-token-outcome t)))
             (list (if (and waited (curl-head? head)) 'head-arrived (list waited head))
                   (and (curl-head? head) (curl-head-status head))
                   (if (and (curl-head? head) (curl-response? r)
                            (equal? (list (curl-head-status head) (curl-head-http-version head) (curl-head-headers head))
                                    (list (curl-response-status r) (curl-response-http-version r)
                                          (curl-response-headers r))))
                       'same
                       (list head (outcome-of t)))
                   (list->string (map integer->char body))))))))
   '(http raw https h2))

  (for-each
   (lambda (face)
     (test-equal (string-append (symbol->string face)
                                ": the head comes before the first piece, by the body's delay: for a body written 300 ms after its head, the head published 250 ms or more before the first piece was appended, each read on the engine's thread; head-wait answered with the head there, before that piece was appended")
       'head-first
       (on-engine-for face
         (lambda (engine)
           (let* ((t (curl-submit engine (stream-request o face (if (eq? face 'raw)
                                                                    "/raw/pattern?key=lead&bytes=600&chunk=600&delay=300"
                                                                    "/pattern/600?delay=300"))))
                  (waited (curl-token-head-wait t 20000))
                  (waited-at (now-ns))
                  (head (curl-token-head t))
                  (piece (curl-token-next-piece t 20000))
                  (head-at (stat t 'head-at))
                  (first-at (stat t 'first-at)))
             (drain-pieces t 20000)
             (if (and waited (curl-head? head) (= (curl-head-status head) 200) (bytevector? piece)
                      head-at first-at (>= (- first-at head-at) 250000000) (< waited-at first-at))
                 'head-first
                 (list waited head piece head-at first-at waited-at)))))))
   '(raw http))

  (test-equal "a 204 publishes its head, and no piece: the end at once, its outcome a 204 whose body is #f; a head request, the same, its head carrying Content-Length"
    '((204 eof (response 204 http/1.1 #f)) (200 ("Content-Length" . "600") eof (response 200 http/1.1 #f)))
    (guard (e (#t (list 'raised (describe e))))
      (let* ((t1 (curl-submit engine (stream-request o 'http "/status/204")))
             (h1 (and (curl-token-head-wait t1 20000) (curl-token-head t1)))
             (e1 (curl-token-next-piece t1 20000))
             (t2 (curl-submit engine (stream-request o 'http "/pattern/600" 'method 'head)))
             (h2 (and (curl-token-head-wait t2 20000) (curl-token-head t2)))
             (e2 (curl-token-next-piece t2 20000)))
        (list (list (and (curl-head? h1) (curl-head-status h1)) (if (eof-object? e1) 'eof e1) (outcome-of t1))
              (list (and (curl-head? h2) (curl-head-status h2))
                    (and (curl-head? h2) (assoc "Content-Length" (curl-head-headers h2)))
                    (if (eof-object? e2) 'eof e2) (outcome-of t2))))))

  (test-equal "head-wait answers #t for a token done with no head, a refused connect, whose head stays #f; and #f within its bound for one whose server has sent none yet, whose head is #f"
    '(#t #f (transfer-error perform-failed 7 connect) #f #f)
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((t1 (curl-submit engine (make-curl-request "http://127.0.0.1:1/" 'proxy #f 'timeout-ms 10000
                                                          'stream-buffer 1024)))
               (w1 (curl-token-head-wait t1 20000))
               (t2 (curl-submit engine (stream-request o 'raw "/raw/stall-before-head")))
               (w2 (curl-token-head-wait t2 300))
               (h2 (curl-token-head t2)))
          (curl-token-cancel t2)
          (curl-token-wait t2 10000)
          (list w1 (curl-token-head t1) (outcome-of t1) w2 h2)))))

  (test-equal "through a proxy's CONNECT tunnel, in a child whose https_proxy is the http face: the CONNECT's head, RESPONSE_CODE 0, is passed over, and the head is the 200, equal to the response's, on the https and h2 faces; the tunnel counted each time"
    (list 0
          (list 'head 'https #t 'same "early\n" '(response 200 #f))
          (list 'head 'h2 #t 'same "early\n" '(response 200 #f))
          'two-tunnels
          zero-counts)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((host (lambda (face) (let ((f (origin-face o face))) (string-append (car f) ":" (number->string (cdr f))))))
             (r (run-child (list (string-append "https_proxy=http://" (host 'http)))
                           "tests/stream-connect.sps" (host 'http) (host 'https) (host 'h2) ca))
             (lines (cadr r))
             (of (lambda (tag) (filter (lambda (d) (and (pair? d) (eq? (car d) tag))) lines)))
             (heads (of 'head))
             (connects (map cadr (of 'connects))))
        (list (car r)
              (let ((h (assq 'https (map cdr heads))))
                (if (and h (eqv? (car (list-ref h 2)) 200))
                    (list 'head 'https (list-ref h 1) (if (list-ref h 3) 'same 'differs) (list-ref h 4) (list-ref h 5))
                    (list heads (caddr r))))
              (let ((h (assq 'h2 (map cdr heads))))
                (if (and h (eqv? (car (list-ref h 2)) 200))
                    (list 'head 'h2 (list-ref h 1) (if (list-ref h 3) 'same 'differs) (list-ref h 4) (list-ref h 5))
                    (list heads (caddr r))))
              (if (and (= (length connects) 2) (integer? (car connects)) (eqv? (cadr connects) (+ (car connects) 2)))
                  'two-tunnels connects)
              (let ((c (of 'counts))) (if (pair? c) (cadr (car c)) lines))))))

  ;; --- the header callable's lock: heads beside a thread that collects
  ;; every 2 ms. The raw face writes a 100 and a 103, then the final head
  ;; 50 ms on, so the engine's thread waits in its __collect_safe poll
  ;; between the header callable's calls, and the collector runs there.
  ;; Without lock-object a collection moves the callable's code, and libcurl
  ;; calls where it was (the M2 plan, section 5.1.1).
  (test-equal "the header callable's lock: ten streamed heads, a 100 and a 103 then the 200, 50 ms apart, beside a thread that collects every 2 ms: each head the 200, each body early, ten collections or more while a transfer was live"
    (list (make-list 10 '(200 "early\n")) 'collected-while-live)
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((mx (make-mutex)) (stop #f) (while-live 0) (done #f))
          (fork-thread (lambda ()
                         (let loop ()
                           (unless (with-mutex mx stop)
                             (make-bytevector 20000 1)
                             (collect-rendezvous)
                             (when (> (curl-engine-live-count engine) 0)
                               (with-mutex mx (set! while-live (+ while-live 1))))
                             (pause-ms 2)
                             (loop)))
                         (with-mutex mx (set! done #t))))
          (let ((heads (let loop ((i 0) (found '()))
                         (if (= i 10)
                             (reverse found)
                             (let* ((t (curl-submit engine (stream-request o 'raw "/raw/early")))
                                    (head (and (curl-token-head-wait t 20000) (curl-token-head t)))
                                    (body (let drain ((bytes '()))
                                            (let ((p (curl-token-next-piece t 20000)))
                                              (if (bytevector? p) (drain (append bytes (bytevector->u8-list p))) bytes)))))
                               (loop (+ i 1) (cons (list (and (curl-head? head) (curl-head-status head))
                                                         (list->string (map integer->char body)))
                                                   found)))))))
            (with-mutex mx (set! stop #t))
            (wait-for (lambda () (with-mutex mx done)) 10000)
            (list heads (if (>= while-live 10) 'collected-while-live (list 'collections-while-live while-live))))))))

  ;; --- the take's escape: a keyboard interrupt at the take's section's end
  (test-equal "the take's escape, in a child: a keyboard interrupt made pending while a take waits for the stream's mutex, inside its look's section, runs as that section ends; a handler that escapes, and one that returns, under next-piece, get-bytevector-some and get-u8, lose no piece and give none twice"
    (list 0
          (map (lambda (row) (list 'case (car row) (cadr row) (caddr row) (iota 15)))
               '((next-piece escapes escaped) (next-piece returns returned) (some escapes escaped)
                 (some returns returned) (u8 escapes escaped) (u8 returns returned)))
          zero-counts)
    (let ((r (run-child '() "tests/stream-escape.sps" (url-of o 'raw ""))))
      (list (car r)
            (filter (lambda (d) (and (pair? d) (eq? (car d) 'case))) (cadr r))
            (let ((c (filter (lambda (d) (and (pair? d) (eq? (car d) 'counts))) (cadr r))))
              (if (pair? c) (cadr (car c)) r)))))

  ;; --- the take's removal, a timer swept across it a tick at a time
  (let ((sweep
         (lambda (read plant)
           ;; READ reads once: 'piece or 'port. Each run arms the timer for T
           ;; ticks, its handler escaping; a run that escapes leaves the
           ;; stream's taken count as it was, or, past a removal, loses what
           ;; it removed. Every byte read is checked against the pattern,
           ;; through the final drain.
           (on-own-engine make-curl-engine
             (lambda (engine)
               (let* ((n 3000)
                      (t (curl-submit engine (stream-request o 'raw (string-append "/raw/pattern?key=sweep-" (symbol->string read)
                                                                                   (if plant "-planted" "")
                                                                                   "&bytes=3000&chunk=1&gap=1")
                                                             'stream-buffer 1000000)))
                      (all-in (wait-for (lambda () (curl-token-done? t)) 30000))
                      (port (and (eq? read 'port) (curl-token-body-port t)))
                      (one (lambda () (if port (get-bytevector-some port) (curl-token-next-piece t 1000))))
                      (got #f)
                      (at 0) (bad #f) (escaped-kept 0) (escaped-lost 0) (returned 0))
                 (define (took! bytes)
                   (set! returned (+ returned 1))
                   (set! bad (or bad (bad-at bytes at)))
                   (set! at (+ at (bytevector-length bytes))))
                 (when plant (curl-token-plant! t 'spin))
                 ;; The call's length, in ticks, read once with no expiry.
                 (set-timer 100000000)
                 (set! got (one))
                 (let ((call-ticks (- 100000000 (set-timer 0))))
                   (when (bytevector? got) (took! got))
                   (let pass ((passes 2))
                     (when (> passes 0)
                       (let tick ((ticks 1))
                         (when (<= ticks (+ call-ticks 20))
                           (let* ((taken (stat t 'taken))
                                  (k #f)
                                  (answer (call/cc
                                           (lambda (escape)
                                             (set! k escape)
                                             (set! got #f)
                                             (timer-interrupt-handler (lambda () (k 'escaped)))
                                             (set-timer ticks)
                                             ;; The answer is stored before any event check,
                                             ;; so an expiry after the call returns is
                                             ;; told from one inside it.
                                             (set! got (one))
                                             (set-timer 0)
                                             'returned))))
                             (set-timer 0)
                             (cond ((bytevector? got) (took! got))
                                   ((not (eq? answer 'escaped)) #f)
                                   ((= (stat t 'taken) taken) (set! escaped-kept (+ escaped-kept 1)))
                                   (else (set! escaped-lost (+ escaped-lost 1))))
                             (tick (+ ticks 1)))))
                       (pass (- passes 1))))
                   (timer-interrupt-handler (lambda () #f))
                   (curl-token-plant! t #f)
                   (let ((rest (if port (drain-port port at) (drain-pieces t 5000 at))))
                     (when port (close-port port))
                     ;; The sweep's evidence, on stdout: where it landed.
                     (display (list 'sweep read (if plant 'planted 'plain) 'call-ticks call-ticks
                                    'escaped-kept escaped-kept 'escaped-lost escaped-lost 'returned returned))
                     (newline)
                     (list all-in call-ticks escaped-kept escaped-lost returned
                           (+ at (car rest))
                           (or (and bad (list 'bad bad)) (cadr rest)))))))))))
    (for-each
     (lambda (read)
       (test-equal (string-append "a timer swept a tick at a time, twice, across "
                                  (if (eq? read 'piece) "next-piece's call" "the port's get-bytevector-some")
                                  " to 20 ticks past it: an expiry before the removal leaves the piece for the next take, none past it loses one, and 3,000 bytes come whole and in order")
         '(swept kept-and-returned 0 3000 in-order)
         (let ((r (sweep read #f)))
           (if (and (list? r) (= (length r) 7))
               (list (if (and (list-ref r 0) (> (list-ref r 1) 0)) 'swept r)
                     (if (and (> (list-ref r 2) 0) (> (list-ref r 4) 0)) 'kept-and-returned r)
                     (list-ref r 3) (list-ref r 5) (list-ref r 6))
               r))))
     '(piece port))
    (test-equal "the sweep's planted control: a loop after next-piece's removal, a test seam's, where an expiry can land, loses a piece the sweep sees: an escape past the removal, and bytes short of the body"
      '(lost short)
      (let ((r (sweep 'piece #t)))
        (if (and (list? r) (= (length r) 7))
            (list (if (> (list-ref r 3) 0) 'lost r)
                  (if (or (< (list-ref r 5) 3000) (pair? (list-ref r 6))) 'short r))
            r))))

  ;; --- the port
  (test-equal "the port's ends stick: once every byte is read of a response, get-bytevector-some, get-u8 and get-bytevector-all each answer the end, every time"
    '(600 in-order eof eof eof eof eof)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((t (curl-submit engine (stream-request o 'http "/pattern/600")))
             (port (curl-token-body-port t))
             (d (drain-port port))
             (ends (list (get-bytevector-some port) (get-u8 port) (get-bytevector-all port)
                         (get-bytevector-some port))))
        (close-port port)
        (append d (map (lambda (x) (if (eof-object? x) 'eof x)) ends)))))

  (test-equal "the port raises a failure every time: hello, then the short body's 18, of send-receive, the same condition at each read after"
    '("hello" (transfer-error perform-failed 18) (transfer-error perform-failed 18) same send-receive)
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((t (curl-submit engine (stream-request o 'raw "/raw/short-body")))
               (port (curl-token-body-port t))
               (hello (get-bytevector-some port))
               (c1 (guard (e (#t e)) (get-bytevector-some port) 'no-raise))
               (c2 (guard (e (#t e)) (get-u8 port) 'no-raise)))
          (close-port port)
          (list (if (bytevector? hello) (latin-1 hello) hello)
                (raised (lambda () (raise c1)))
                (raised (lambda () (raise c2)))
                (if (eq? c1 c2) 'same 'different)
                (class-of c1))))))

  (test-equal "each get-bytevector form's loss at a failure, pinned: get-bytevector-n, -n! and -all raise it, losing the hello an earlier read gave them, so the next read raises again; get-bytevector-some, -some! and get-u8 give hello first"
    '((n raised raised) (n! raised raised) (all raised raised)
      (some "hello" raised) (some! "hello" raised) (u8 "hello" raised))
    (on-own-engine make-curl-engine
      (lambda (engine)
        (map (lambda (form)
               (let* ((t (curl-submit engine (stream-request o 'raw "/raw/short-body")))
                      (port (curl-token-body-port t))
                      (_ (curl-token-wait t 20000))
                      (first (guard (e ((curl-transfer-error? e) 'raised))
                               (case form
                                 ((n) (latin-1 (get-bytevector-n port 10)))
                                 ((n!) (let ((bv (make-bytevector 10 0)))
                                         (get-bytevector-n! port bv 0 10)
                                         (latin-1 bv)))
                                 ((all) (latin-1 (get-bytevector-all port)))
                                 ((some) (latin-1 (get-bytevector-some port)))
                                 ((some!) (let* ((bv (make-bytevector 10 0)) (k (get-bytevector-some! port bv 0 10)))
                                            (substring (latin-1 bv) 0 k)))
                                 ((u8) (let loop ((chars '()) (i 0))
                                         (if (= i 5) (list->string (reverse chars))
                                             (loop (cons (integer->char (get-u8 port)) chars) (+ i 1))))))))
                      (then (guard (e ((curl-transfer-error? e) 'raised)) (get-bytevector-some port) 'gave)))
                 (close-port port)
                 (list form first then)))
             '(n n! all some some! u8)))))

  (test-equal "the port belongs to the thread that made it: a read from another raises &curl-wrong-thread, naming curl-token-body-port, this thread and that one; so does a close, which leaves the port open, read here whole after"
    (let ((wrong (lambda (who) (list 'raised-wrong-thread who))))
      (list (wrong 'curl-token-body-port) (wrong 'curl-token-body-port) 'open '(600 in-order eof)))
    (guard (e (#t (list 'raised (describe e))))
      (let* ((t (curl-submit engine (stream-request o 'http "/pattern/600")))
             (port (curl-token-body-port t))
             (judge (lambda (answer)
                      (if (and (pair? answer) (eq? (car answer) 'raised) (curl-wrong-thread? (cadr answer))
                               (eqv? (curl-wrong-thread-expected (cadr answer)) main-thread)
                               (not (eqv? (curl-wrong-thread-actual (cadr answer)) main-thread)))
                          (list 'raised-wrong-thread (curl-wrong-thread-who (cadr answer)))
                          answer)))
             (read (judge (on-thread (lambda () (get-u8 port)) 10000)))
             (close (judge (on-thread (lambda () (close-port port)) 10000)))
             (open (if (port-closed? port) 'closed 'open))
             (d (drain-port port)))
        (close-port port)
        (list read close open d))))

  (test-equal "the port's thread rule holds where the port asks for bytes, its read!: what Chez's port had buffered, after this thread's get-u8, another thread reads, every byte, in order; once that buffer is empty, its next read raises &curl-wrong-thread, naming curl-token-body-port; this thread then reads the rest, the whole body read"
    '(buffered served-in-order (raised-wrong-thread curl-token-body-port) 600 in-order eof)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((t (curl-submit engine (stream-request o 'http "/pattern/600")))
             (port (curl-token-body-port t))
             (first (get-u8 port))
             (n (binary-port-input-count port))
             (served (on-thread (lambda () (get-bytevector-n port n)) 10000))
             (refused (on-thread (lambda () (get-u8 port)) 10000))
             (d (drain-port port (+ 1 n))))
        (close-port port)
        (list (if (and (eqv? first 0) (> n 0)) 'buffered (list first n))
              (if (and (eq? (car served) 'answered) (bytevector? (cadr served))
                       (= (bytevector-length (cadr served)) n) (not (bad-at (cadr served) 1)))
                  'served-in-order served)
              (if (and (eq? (car refused) 'raised) (curl-wrong-thread? (cadr refused))
                       (eqv? (curl-wrong-thread-expected (cadr refused)) main-thread)
                       (not (eqv? (curl-wrong-thread-actual (cadr refused)) main-thread)))
                  (list 'raised-wrong-thread (curl-wrong-thread-who (cadr refused)))
                  refused)
              (+ 1 n (car d)) (cadr d) (caddr d)))))

  (test-equal "another thread's get-bytevector-n that needs more than the port had buffered takes the buffered bytes, then raises &curl-wrong-thread at read!, naming curl-token-body-port, and loses them, as at a failure: this thread's next byte is the one after them (slice 1's second review)"
    '(buffered (raised-wrong-thread curl-token-body-port) next-after-buffered)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((t (curl-submit engine (stream-request o 'http "/pattern/600")))
             (port (curl-token-body-port t))
             (first (get-u8 port))
             (n (binary-port-input-count port))
             (over (on-thread (lambda () (get-bytevector-n port (+ n 10))) 10000))
             (next (get-u8 port)))
        (drain-port port (+ 2 n))
        (close-port port)
        (list (if (and (eqv? first 0) (> n 0)) 'buffered (list first n))
              (if (and (eq? (car over) 'raised) (curl-wrong-thread? (cadr over))
                       (eqv? (curl-wrong-thread-expected (cadr over)) main-thread)
                       (not (eqv? (curl-wrong-thread-actual (cadr over)) main-thread)))
                  (list 'raised-wrong-thread (curl-wrong-thread-who (cadr over)))
                  over)
              (if (eqv? next (mod (+ 1 n) 251)) 'next-after-buffered (list next n))))))

  (test-equal "a port's read that must wait is refused inside a critical section, an assertion violation from curl-token-body-port, before it waits; next-piece's, from curl-token-next-piece; head-wait's, from curl-token-head-wait"
    '((assertion-violation curl-token-body-port) (assertion-violation curl-token-next-piece)
      (assertion-violation curl-token-head-wait))
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((t (curl-submit engine (stream-request o 'raw "/raw/stall-before-head")))
               (port (curl-token-body-port t))
               (answers (list (raised (lambda () (critical-section (get-u8 port))))
                              (raised (lambda () (critical-section (curl-token-next-piece t 100))))
                              (raised (lambda () (critical-section (curl-token-head-wait t 100)))))))
          (curl-token-cancel t)
          (curl-token-wait t 10000)
          (close-port port)
          answers))))

  (test-equal "a port's close cancels its token while the stream is paused: it ends cancelled, its transfer taken out, and a second port of it is refused"
    '(paused (transfer-error cancelled #f none) (assertion-violation curl-token-body-port))
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((t (curl-submit engine (stream-request o 'raw (pattern-path 'raw 67108864 "close"))))
               (port (curl-token-body-port t))
               (paused (wait-for (lambda () (paused? t)) 20000)))
          (close-port port)
          (curl-token-wait t 10000)
          (list (if paused 'paused (curl-token-stream-stats t)) (outcome-of t)
                (raised (lambda () (curl-token-body-port t))))))))

  ;; --- the bound: a consumer slower than the timeout
  (test-equal "a consumer slower than the transfer's bound: paused, its timeout of 1,000 ms runs, and it ends with 28, a timeout; what it held stays readable, then the end, and the port raises the 28"
    '(paused (transfer-error perform-failed 28 timeout) held-readable eof (transfer-error perform-failed 28))
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((t (curl-submit engine (stream-request o 'raw (pattern-path 'raw 67108864 "slow") 'timeout-ms 1000)))
               (paused (wait-for (lambda () (paused? t)) 20000))
               (done (curl-token-wait t 20000))
               (held (stat t 'appended))
               (d (drain-pieces t 5000))
               (t2 (curl-submit engine (stream-request o 'raw (pattern-path 'raw 67108864 "slow-port") 'timeout-ms 1000)))
               (port (curl-token-body-port t2))
               (_ (curl-token-wait t2 20000))
               (port-end (let loop () (let ((r (raised (lambda () (get-bytevector-some port)))))
                                        (if (and (eq? (car r) 'returned) (bytevector? (cadr r))) (loop) r)))))
          (close-port port)
          (list (if (and paused done) 'paused (list paused done)) (outcome-of t)
                (if (and (> held 0) (= (car d) held) (eq? (cadr d) 'in-order)) 'held-readable (list held d))
                (caddr d) port-end)))))

  ;; --- the paced poll (ADR-0012, amended 2026-10-29)
  (let ((pause-cpu
         (lambda (make)
           ;; The process's CPU over 2 s while a stream on its own engine is
           ;; paused, its consumer taking nothing, over HTTP/1.1.
           (on-own-engine make
             (lambda (own)
               (let* ((t (curl-submit own (stream-request o 'raw (pattern-path 'raw 67108864 "cpu"))))
                      (paused (wait-for (lambda () (paused? t)) 20000))
                      (resumes (stat t 'resumes)))
                 (collect-rendezvous)
                 (let* ((c0 (cpu-ms)) (_ (pause-ms 2000)) (c1 (cpu-ms)))
                   (curl-token-cancel t)
                   (curl-token-wait t 10000)
                   (list paused (= resumes (stat t 'resumes)) (- c1 c0)))))))))
    (test-equal "the paced poll: the process's CPU through a 2 s pause, over HTTP/1.1, the stream paused throughout, is under 500 ms on every libcurl, Ubuntu's 8.5.0 too, whose poll spins"
      '(#t #t under-500-ms)
      (let ((r (pause-cpu make-curl-engine)))
        (if (and (list? r) (= (length r) 3))
            (list (car r) (cadr r) (if (< (caddr r) 500) 'under-500-ms (caddr r)))
            r)))
    ;; The control: pacing off, by a test seam. The libcurls the plan
    ;; measured, by version: 8.5.0 spins, at a core's whole time; the others
    ;; poll a few times. A libcurl with no row fails, naming its version, and
    ;; shows what it measured: the expected value names the row it lacks,
    ;; which no measurement can give.
    (let ((spin-rows '(("7.85.0" . quiet) ("8.5.0" . spins) ("8.7.1" . quiet) ("8.20.0" . quiet)
                       ("8.23.0" . quiet))))
      (test-equal (string-append "the paced poll's control: pacing off, by a test seam, the CPU through the same pause, on "
                                 (if (string? version) version (written version))
                                 ", as its row says: 1,000 ms or more where 8.5.0's poll spins, under 500 ms where it does not; a libcurl with no row fails, showing what it measured")
        (let ((row (and (string? version) (assoc version spin-rows))))
          (if row (list #t #t (cdr row)) (list 'a-row-for version)))
        (let* ((row (and (string? version) (assoc version spin-rows)))
               (r (pause-cpu make-curl-engine-unpaced))
               (measured (if (and (list? r) (= (length r) 3))
                             (list (car r) (cadr r)
                                   (cond ((>= (caddr r) 1000) 'spins) ((< (caddr r) 500) 'quiet) (else (caddr r))))
                             r)))
          (if row measured (list 'no-row-for version 'measured measured))))))

  ;; --- the paced poll's rule, by the probe seam: each probed turn wakes
  ;; its own poll, which then returns at once, and records whether it paced.
  (let ((probe-turns
         (lambda (engine mark)
           ;; ENGINE's next 50 turns probed, MARK as given: (POLLS FAST MOVED
           ;; PACED SLEPT), SLEPT the paced sleeps the engine counted
           ;; meanwhile.
           (let ((slept (curl-engine-paced-sleeps engine)))
             (curl-engine-probe-turns! engine 50 mark)
             (let ((p (wait-for (lambda () (let ((p (curl-engine-probe engine))) (and p (= (car p) 0) p)))
                                10000)))
               (if p
                   (append (cdr p) (list (- (curl-engine-paced-sleeps engine) slept)))
                   (list 'unfinished (curl-engine-probe engine)))))))
        (paused-on
         (lambda (engine key)
           ;; A raw stream on ENGINE, paused, its consumer taking nothing.
           (let* ((t (curl-submit engine (stream-request o 'raw (pattern-path 'raw 67108864 key))))
                  (paused (wait-for (lambda () (paused? t)) 20000)))
             (and paused t)))))
    (test-equal "the paced poll's rule, by a test seam that wakes 50 turns' polls at once: a turn whose poll returns in under 1 ms paces, with a stream paused, no message taken and no byte moved, every such turn, each sleep counted; but none whose callables took bytes, beside a second stream that trickles in; none with a message of the seam's own taken; none on an engine with no stream paused, nor on one whose pacing is off; each on an engine of its own"
      '((paused paces) (moving unmoved-alone) (marked none) (idle none) (unpaced none))
      (list
       (on-own-engine make-curl-engine
         (lambda (engine)
           (let* ((t (paused-on engine "probe-paused")) (r (and t (probe-turns engine #f))))
             (when t (curl-token-cancel t) (curl-token-wait t 10000))
             ;; The turn the pause fell in may be probed too, its bytes
             ;; moved: every fast turn but those paces.
             (list 'paused (if (and (list? r) (= (length r) 5) (> (- (list-ref r 1) (list-ref r 2)) 0)
                                    (= (list-ref r 3) (- (list-ref r 1) (list-ref r 2)))
                                    (>= (list-ref r 4) (list-ref r 3)))
                               'paces (list (and t #t) r))))))
       (on-own-engine make-curl-engine
         (lambda (engine)
           (let* ((t (paused-on engine "probe-moving"))
                  (trickle (curl-submit engine (stream-request o 'raw "/raw/pattern?key=probe-trickle&bytes=20000&chunk=1&gap=1"
                                                               'stream-buffer 1000000)))
                  (flowing (wait-for (lambda () (> (stat trickle 'appended) 0)) 20000))
                  (r (and t flowing (probe-turns engine #f))))
             (curl-token-cancel trickle)
             (curl-token-wait trickle 10000)
             (when t (curl-token-cancel t) (curl-token-wait t 10000))
             (list 'moving (if (and (list? r) (= (length r) 5) (> (list-ref r 2) 0)
                                    (= (list-ref r 3) (- (list-ref r 1) (list-ref r 2))))
                               'unmoved-alone (list (and t #t) flowing r))))))
       (on-own-engine make-curl-engine
         (lambda (engine)
           (let* ((t (paused-on engine "probe-marked")) (r (and t (probe-turns engine #t))))
             (when t (curl-token-cancel t) (curl-token-wait t 10000))
             (list 'marked (if (and (list? r) (= (length r) 5) (> (list-ref r 1) 0) (= (list-ref r 3) 0))
                               'none (list (and t #t) r))))))
       (on-own-engine make-curl-engine
         (lambda (engine)
           (let ((r (probe-turns engine #f)))
             (list 'idle (if (and (list? r) (= (length r) 5) (> (list-ref r 1) 0) (= (list-ref r 3) 0))
                             'none r)))))
       (on-own-engine make-curl-engine-unpaced
         (lambda (engine)
           (let* ((t (paused-on engine "probe-unpaced")) (r (and t (probe-turns engine #f))))
             (when t (curl-token-cancel t) (curl-token-wait t 10000))
             (list 'unpaced (if (and (list? r) (= (length r) 5) (> (list-ref r 1) 0) (= (list-ref r 3) 0))
                                'none (list (and t #t) r)))))))))

  (test-equal "a resume's delay, from the look that queued it to the engine's call of curl_easy_pause, is under 50 ms, in each of 8 rounds spread across the paced poll's 1 ms period"
    '(8 under-50-ms)
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((t (curl-submit engine (stream-request o 'raw (pattern-path 'raw 67108864 "delay") 'stream-buffer 1)))
               (delays
                (let loop ((round 0) (found '()))
                  (if (= round 8)
                      (reverse found)
                      (let ((paused (wait-for (lambda () (paused? t)) 20000))
                            (resumes (stat t 'resumes)))
                        (collect-rendezvous)
                        (sleep (make-time 'time-duration (+ 23000000 (* round 125000)) 0))
                        (curl-token-next-piece t 1000)
                        (let ((resumed (wait-for (lambda () (> (stat t 'resumes) resumes)) 10000)))
                          (loop (+ round 1)
                                (cons (and paused resumed (stat t 'last-resume-ns)) found))))))))
          (curl-token-cancel t)
          (curl-token-wait t 10000)
          (list (length (filter integer? delays))
                (if (for-all (lambda (d) (and (integer? d) (< d 50000000))) delays)
                    'under-50-ms
                    (map (lambda (d) (and d (/ d 1000000.))) delays)))))))

  (test-equal "the look: a message queued from the engine's own thread between its resume step and its perform, a test seam's, is taken by the next turn within 50 ms; Guix's 8.20.0 reads its wakeup back inside the perform, and the poll would wait up to 1,000 ms"
    '(taken under-50-ms)
    (on-own-engine make-curl-engine
      (lambda (own)
        (let* ((t (curl-submit own (stream-request o 'raw (pattern-path 'raw 67108864 "look") 'stream-buffer 1)))
               (paused (wait-for (lambda () (paused? t)) 20000)))
          (curl-engine-arm-late-message! own)
          (collect-rendezvous)
          (curl-token-next-piece t 1000)
          (let* ((late (wait-for (lambda () (let ((l (curl-engine-late-message own)))
                                              (and (pair? l) (eq? (car l) 'taken) l)))
                                 10000)))
            (curl-token-cancel t)
            (curl-token-wait t 10000)
            (if (and paused late)
                (list 'taken (if (< (- (caddr late) (cadr late)) 50000000) 'under-50-ms
                                 (/ (- (caddr late) (cadr late)) 1000000.)))
                (list paused (curl-engine-late-message own))))))))

  ;; --- cancel, stop and the engine's failure while paused
  (test-equal "a cancel while paused ends the token cancelled, its transfer taken out at once; what it held stays readable, then the end"
    '(paused (transfer-error cancelled #f none) held-readable eof)
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((t (curl-submit engine (stream-request o 'raw (pattern-path 'raw 67108864 "cancel"))))
               (paused (wait-for (lambda () (paused? t)) 20000))
               (held (stat t 'appended)))
          (curl-token-cancel t)
          (let* ((done (curl-token-wait t 10000)) (d (drain-pieces t 5000)))
            (list (if (and paused done) 'paused (list paused done)) (outcome-of t)
                  (if (and (> held 0) (= (car d) held) (eq? (cadr d) 'in-order)) 'held-readable (list held d))
                  (caddr d)))))))

  (test-equal "a stop while paused ends the token stopped; what it held stays readable, then the end; the counts back to the suite's engine's"
    (list 'paused '(transfer-error stopped #f none) 'held-readable 'eof running-counts)
    (on-own-engine make-curl-engine
      (lambda (own)
        (let* ((t (curl-submit own (stream-request o 'raw (pattern-path 'raw 67108864 "stop-own"))))
               (paused (wait-for (lambda () (paused? t)) 20000))
               (held (stat t 'appended))
               (stopped (stop-bounded own))
               (d (drain-pieces t 5000)))
          (list (if (and paused (eq? stopped 'stopped)) 'paused (list paused stopped)) (outcome-of t)
                (if (and (> held 0) (= (car d) held) (eq? (cadr d) 'in-order)) 'held-readable (list held d))
                (caddr d) (native-counts))))))

  (test-equal "the engine's failure while paused, a fault planted at the resume step, which a read of the port queued: the token ends with &curl-engine-error, failed, carrying the fault; the port then raises that failure, every read; a later submit is refused with it"
    (list 'paused (list 'engine-error 'failed (planted-engine-fault 'resume)) 'raised-twice 'refused-later running-counts)
    (on-own-engine (lambda () (make-faulty-curl-engine 'resume))
      (lambda (own)
        (let* ((t (curl-submit own (stream-request o 'raw (pattern-path 'raw 67108864 "fault") 'stream-buffer 1)))
               (port (curl-token-body-port t))
               (paused (wait-for (lambda () (paused? t)) 20000))
               (bytes (get-bytevector-some port))
               (done (curl-token-wait t 10000))
               (failure (curl-token-outcome t))
               ;; The piece the first read took is at hand; past it, the end.
               (reads (let loop ((n 0))
                        (let ((r (guard (e (#t (list 'raised e))) (get-bytevector-some port))))
                          (cond ((> n 100) (list 'never-raised))
                                ((bytevector? r) (loop (+ n 1)))
                                (else (list (cadr r) (guard (e (#t e)) (get-u8 port) 'no-raise)))))))
               (later (guard (e ((curl-engine-error? e) 'refused-later))
                        (curl-submit own (stream-request o 'raw "/raw/content-length")))))
          (close-port port)
          (stop-bounded own)
          (list (if (and paused done (bytevector? bytes)) 'paused (list paused done bytes)) (outcome-of t)
                (if (for-all (lambda (r) (eq? r failure)) reads) 'raised-twice reads)
                later (native-counts))))))

  ;; --- the thread rule (§3.8; ADR-0012, decision 4)
  (test-equal "the thread rule: the pieces' consumer, the port's reader and the mailbox's callback each run on this thread, never the engine's; the chunk log, the write callable's, gives each verdict's threads, the engine's alone, on an engine of its own"
    (list 'consumers-here 'callback-here 'log-engine-alone)
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((engine-thread (curl-engine-thread engine))
               (mailbox (make-curl-mailbox))
               (seen '())
               (note! (lambda (where) (set! seen (cons (cons where (get-thread-id)) seen))))
               (t1 (curl-submit engine (stream-request o 'raw (pattern-path 'raw 1048576 "threads-1")) mailbox
                                (lambda (token) (note! 'callback))))
               (t2 (curl-submit engine (stream-request o 'raw (pattern-path 'raw 1048576 "threads-2")))))
          (let loop () (let ((p (curl-token-next-piece t1 20000))) (when (bytevector? p) (note! 'piece) (loop))))
          (let ((port (curl-token-body-port t2)))
            (let loop () (let ((b (get-bytevector-some port))) (when (bytevector? b) (note! 'port) (loop))))
            (close-port port))
          (curl-mailbox-deliver mailbox 20000)
          (curl-token-wait t2 10000)
          (let ((log (curl-token-chunks t1)))
            (list (if (and (assq 'piece seen) (assq 'port seen)
                           (for-all (lambda (s) (eqv? (cdr s) main-thread))
                                    (filter (lambda (s) (memq (car s) '(piece port))) seen))
                           (not (eqv? main-thread engine-thread)))
                      'consumers-here seen)
                  (if (equal? (filter (lambda (s) (eq? (car s) 'callback)) seen) (list (cons 'callback main-thread)))
                      'callback-here seen)
                  (if (and (pair? log) (assq 'accepted log)
                           (for-all (lambda (entry) (and (memq (car entry) stream-verdicts)
                                                         (equal? (caddr entry) (list engine-thread))))
                                    log))
                      'log-engine-alone log)))))))

  ;; --- no multiplexing, by behaviour
  (let ((connections
         (lambda (make)
           ;; A streams /connection on h2, its head at once, its body 1 s on;
           ;; B, a whole body, starts once A's head has come.
           (on-own-engine make
             (lambda (own)
               (let* ((a (curl-submit own (stream-request o 'h2 "/connection?delay=1000")))
                      (head (curl-token-head-wait a 20000))
                      (b (curl-token-await (curl-submit own (make-curl-request (url-of o 'h2 "/connection")
                                                                               'proxy #f 'ca-file ca 'timeout-ms 20000))))
                      (a-body (let loop ((found '()))
                                (let ((p (curl-token-next-piece a 20000)))
                                  (if (bytevector? p) (loop (append found (bytevector->u8-list p))) found))))
                      (a-text (list->string (map integer->char a-body)))
                      (b-text (latin-1 (curl-response-body b))))
                 (and head (if (string=? a-text b-text) 'shared (list 'apart a-text b-text)))))))))
    (test-equal "HTTP/2 multiplexing by behaviour: on the loaded libcurl, two transfers to one h2 origin at once share a connection, but on 8.7.0 and 8.7.1, where the engine multiplexes nothing; with the test seam's CURLMOPT_PIPELINING at 0, each has its own"
      (list (if (multiplexing-off? version) 'apart 'shared) 'apart)
      (let ((default (connections make-curl-engine))
            (off (connections make-curl-engine-unmultiplexed)))
        (list (if (pair? default) (car default) default) (if (pair? off) (car off) off)))))

  (test-equal "the suite's engine holds nothing once the scenarios end: its multi handle and slot alone"
    running-counts
    (begin (wait-for (lambda () (equal? (native-counts) running-counts)) 10000)
           (native-counts))))

;; iota : Natural -> (Listof Natural)
(define (iota n) (let loop ((i (- n 1)) (acc '())) (if (< i 0) acc (loop (- i 1) (cons i acc)))))

;; The scenarios' tests run here, in a definition, and the verdict on their
;; origin after: SRFI-64 keeps one result per runner (traps.md).
(define scenarios-outcome
  (guard (e (#t (list 'raised (describe e))))
    (parameterize ((origin-pki pki))
      (call-with-origin (lambda (o) (scenarios o) 'done)))))

(test-equal "the scenarios' origin starts with the PKI, serves them all, and stops"
  'done
  scenarios-outcome)

(test-equal "the suite's engine stops, and every count is zero after"
  (list 'stopped zero-counts)
  (list (if (curl-engine? engine) (stop-bounded engine) engine) (native-counts)))

(test-end "stream")

(exit (suite-exit-status runner))
