#!r6rs
;;; The suite for a streamed request body at the low level (ADR-0030,
;;; ADR-0032; the M6 plan, sections 3.3 to 3.5 and 5.2): body stream and
;;; body-length, the token's room, puts, end and count, the read, seek and
;;; prerequest callables, at most once, and the send side of the paced poll.
;;; Each check was watched failing, on a mutant or before its code
;;; (build/m6s2b/mutants.md).
;;;
;;;   - each method's framing, sized and chunked, the body whole by its hash,
;;;     over the http, raw, https and h2 faces, a streamed delete's
;;;     Content-Type: and Expect: among them;
;;;   - a request stream per submit, there for a token still queued;
;;;   - pause and resume: a producer that waits, the gap on the wire, one
;;;     resume per pause;
;;;   - room-wait before libcurl asks; a put that waits while the buffer is
;;;     full, refused inside a critical section; every operation once the
;;;     token is done;
;;;   - the put's escape, in a child: a keyboard interrupt at the put's
;;;     section's end leaves the piece committed and counted; and the put's
;;;     stress test, a full-duplex producer of small pieces;
;;;   - body-length-mismatch, short and long, a put past the length, and a
;;;     length of 0;
;;;   - at most once: FRESH_CONNECT keeps a dead pooled connection away;
;;;     without it, by a test seam, the seek refuses libcurl's resend once a
;;;     byte was handed; an HTTP/2 stream refused after bytes, refused; a
;;;     resend before any byte goes on; the prerequest callable refuses the
;;;     resend a seam lets past the seek; the send bit at libcurl's own
;;;     resend;
;;;   - each callable's guard, by a raise planted at its call;
;;;   - an answer while the body is sent, by version: whether the transfer
;;;     ends without a resume, and how;
;;;   - the paced poll on the send side: its rule by the probe seam, with an
;;;     upload paused; the CPU of a paused HTTP/2 upload;
;;;   - throughput: 64 MiB in 64 KiB puts, whole by hash;
;;;   - the thread rule: every put on the caller's thread, the read
;;;     callable's calls on the engine's alone;
;;;   - the read callable's lock, beside a thread that collects;
;;;   - a request that streams both ways; cancel and the engine's failure
;;;     while the send is paused;
;;;   - the owned options, and the refusals of a token that does not stream
;;;     its body.
;;;
;;; Every check that reaches the raw face runs on an engine of its own,
;;; whose scripts close their connections without saying so (ADR-0020); so
;;; does every check that reads a pool.
;;;
;;; A suite cannot tell whether it runs under the memory gate's Valgrind, so
;;; every bound holds there too (the plan's section 5.1, as measured). Every
;;; expected value is one the code under test cannot produce by failing:
;;; SRFI-64 makes #f of a raise in the actual expression, so none is #f.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) fork-thread make-mutex with-mutex sleep make-time current-time
              time-second time-nanosecond getenv get-thread-id library-directories
              collect-rendezvous critical-section parameterize list-head set-timer
              timer-interrupt-handler)
        (curl-testing)
        (curl)
        (curl unsupported)
        (curl private engine)
        (only (curl private transfer) upload-verdicts curl-request-with-upload-fault
              planted-upload-fault)
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

(test-begin "upload")

;; --- helpers --------------------------------------------------------------------------

(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0)))

;; The counts while the suite's engine runs: its multi handle and its slot.
(define running-counts
  '((block . 1) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 1)))

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

;; make-list-of : Natural Any -> (Listof Any)
(define (make-list-of n x) (if (= n 0) '() (cons x (make-list-of (- n 1) x))))

;; pause-us : Natural -> Unit
(define (pause-us us)
  (sleep (make-time 'time-duration (* us 1000) 0)))

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

;; class-of : Any -> Symbol
(define (class-of c)
  (cond ((curl-timeout? c) 'timeout) ((curl-connect-error? c) 'connect)
        ((curl-send-receive-error? c) 'send-receive) ((curl-tls-error? c) 'tls)
        ((curl-protocol-error? c) 'protocol) ((curl-too-large? c) 'too-large)
        (else 'none)))

;; outcome-of : Token -> Any
;; TOKEN's outcome, as data: (response STATUS VERSION); (transfer-error
;; REASON CODE CLASS); (engine-error REASON CONDITION); not-done; or (other
;; TEXT).
(define (outcome-of token)
  (let ((o (curl-token-outcome token)))
    (cond ((not o) 'not-done)
          ((curl-response? o) (list 'response (curl-response-status o) (curl-response-http-version o)))
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

;; on-own-engine : (-> Engine) (Engine -> Any) -> Any
;; PROC's answer, given an engine MAKE made for it and stopped once it
;; returns: an engine of its own starts with an empty pool, and its seams
;; are its alone; (raised TEXT) for a raise.
(define (on-own-engine make proc)
  (guard (e (#t (list 'raised (describe e))))
    (let* ((own (make))
           (answer (guard (e (#t (list 'raised (describe e)))) (proc own))))
      (stop-bounded own)
      answer)))

;; on-engine-for : Symbol (Engine -> Any) -> Any
;; PROC's answer, given an engine of its own for the raw face, whose
;; scripts close their connections without saying so (ADR-0020); the
;; suite's engine for any other face.
(define (on-engine-for face proc)
  (if (eq? face 'raw) (on-own-engine make-curl-engine proc) (proc engine)))

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
   "t=$(command -v timeout || command -v gtimeout) || { echo 'upload child: no timeout' >&2; exit 125; }\n"
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

;; --- the request stream's helpers ----------------------------------------------------

;; pattern-piece : Natural Natural -> Bytevector
;; N bytes of the pattern from offset AT, byte i being i mod 251.
(define (pattern-piece at n)
  (let ((bv (make-bytevector n)))
    (let loop ((i 0) (v (mod at 251)))
      (when (< i n)
        (bytevector-u8-set! bv i v)
        (loop (+ i 1) (if (= v 250) 0 (+ v 1)))))
    bv))

;; pattern-sha256 : (Listof (Pairof Natural String))
;; The SHA-256 of the pattern's first N bytes, for each N a check sends,
;; written here, computed outside the suite, never by the origin.
(define pattern-sha256
  '((15 . "7071fc3188fde7e7e500d4768f1784bede1a22e991648dcab9dc3219acff1d4c")
    (2000 . "63d8d35920be456776a35578ade76725c687821ad55d4bb950225fed2d33e6cb")
    (8192 . "25df2449b2e5a35fea14e02a7158e283801a1069c9f84631b9a9dacb2f809a7f")
    (20000 . "93a6015a3874a774dd59fdd5db19414b301525381eb5ddcc265cdcc68bb9d350")
    (64000 . "c57e96ad5cd41d73308e0691fa6568bbcf561c18982f257fe0b6b108a46212fe")
    (65536 . "4b640d85ab3ba30fd02c9fc9db4a8928f416322ad27022ea58a65aaee68a4df2")
    (131072 . "feb1e4409d009e0ec502eaabe321f86b5197a881e9b765252ec8a75d6957596d")
    (262144 . "31a1f9dea0169551092d05e8bf4a446228c8c3eb4c9b713c66adcb7fd53c89be")
    (1000000 . "2c030d49ec131bfbbb446ad21e7a2f12cdb4f2f4f3fda3ac709dd2e68a4646c7")
    (1048576 . "631b84027d6b9e52b539c4e8373622d23032dfadc64d60af87339c9037e4f769")
    (33554432 . "1cbd22e11bc209926b1e050d644779ba4105d7a023109c3b78bb35edf5c7c292")
    (67108864 . "98dc891b284e4d84ac25b0c0a24fdbe39a7f0dbd643ad5e8aa06e02fc6258254")))

;; sha-of : Natural -> String
(define (sha-of n) (cdr (assv n pattern-sha256)))

;; upload-request : Origin Symbol String Symbol (U Natural #f) . (Listof Any) -> Request
;; A streamed METHOD of PATH on FACE, of LENGTH bytes or chunked, direct, a
;; 60 s timeout, the run's CA file for a TLS face; KEYS, key then value,
;; replace these.
(define (upload-request o face path method length . keys)
  (let ((r (make-curl-request (url-of o face path) 'method method 'proxy #f 'timeout-ms 60000
                              'body 'stream 'body-length length)))
    (apply curl-request-with (if (memq face '(https h2)) (curl-request-with r 'ca-file ca) r) keys)))

;; sink-path : Symbol String . (Listof String) -> String
;; FACE's sink under KEY, the raw face's script or the others' route, with
;; EXTRA, each &NAME=VALUE, after.
(define (sink-path face key . extra)
  (apply string-append (if (eq? face 'raw) "/raw/sink?key=" "/sink?key=") key extra))

;; put-all : Token Natural Natural Natural (U Natural #f) -> (U 'put List)
;; The pattern from FROM to TO put in pieces of PIECE bytes, each with a
;; bound of MS: put once every piece is taken, or (OFFSET ANSWER) at the
;; first answer but #t, a raise's as raised gives it.
(define (put-all token from to piece ms)
  (let loop ((at from))
    (if (>= at to)
        'put
        (let* ((n (min piece (- to at)))
               (a (raised (lambda () (if ms
                                         (curl-token-put-piece! token (pattern-piece at n) ms)
                                         (curl-token-put-piece! token (pattern-piece at n)))))))
          (if (equal? a '(returned #t))
              (loop (+ at n))
              (list at a))))))

;; send-whole : Token Natural Natural -> (List Any Any)
;; room-wait's answer, then the pattern's N bytes put in pieces of PIECE,
;; then the end: what room-wait and the puts answered.
(define (send-whole token n piece)
  (let* ((room (curl-token-room-wait token 20000))
         (puts (put-all token 0 n piece 20000)))
    (curl-token-end-body! token)
    (list room puts)))

;; fill-until-stalled : Token Natural -> (U (List #f Natural) List)
;; The pattern put in 64 KiB pieces, each with a bound of 500 ms, until
;; the buffer is full and libcurl takes nothing through a put: the put
;; answers #f at its bound, and the bytes handed, read before it, are as
;; they were, so the buffer held what refused the put for its whole
;; bound. It asks no more of the kernel: a kernel full on loopback lets
;; more in about a second on, on CI's runner every second (traps.md), so
;; a quiet past the put's bound would never come. A put that answers #f
;; while libcurl took bytes is tried again. Answers (#f AT), AT the offset
;; of the piece not taken; (never-full N) once N bytes were taken.
;; It prints (fill ANSWER AT ms MS retried ((AT MS) ...) mib (MS ...)):
;; how it ended, where and how long after its start, each put that answered
;; #f while libcurl took bytes, and when each MiB was taken.
(define (fill-until-stalled token n)
  (let ((t0 (now-ms)))
    (define (ended answer at retried marks)
      (display (list 'fill (car answer) at 'ms (- (now-ms) t0) 'retried (reverse retried) 'mib (reverse marks)))
      (newline)
      answer)
    (let loop ((at 0) (retried '()) (marks '()))
      (if (>= at n)
          (ended (list 'never-full at) at retried marks)
          (let* ((handed (ustat token 'handed))
                 (a (curl-token-put-piece! token (pattern-piece at 65536) 500)))
            (cond ((eq? a #t)
                   (let ((next (+ at 65536)))
                     (loop next retried (if (= 0 (mod next 1048576)) (cons (- (now-ms) t0) marks) marks))))
                  ((not (eq? a #f)) (ended (list a at) at retried marks))
                  ((= handed (ustat token 'handed)) (ended (list #f at) at retried marks))
                  (else (loop at (cons (list at (- (now-ms) t0)) retried) marks))))))))

;; ustat : Token Symbol -> Any
(define (ustat token key)
  (cdr (assq key (curl-token-upload-stats token))))

;; send-paused? : Token -> Boolean
;; Whether TOKEN's transfer is paused for sending, with no resume queued.
(define (send-paused? token)
  (and (ustat token 'paused) (not (ustat token 'queued))))

;; words : String -> (Listof String)
;; TEXT's words, split at spaces and the newline.
(define (words text)
  (let loop ((cs (string->list text)) (cur '()) (found '()))
    (cond ((null? cs) (reverse (if (null? cur) found (cons (list->string (reverse cur)) found))))
          ((memv (car cs) '(#\space #\newline))
           (loop (cdr cs) '() (if (null? cur) found (cons (list->string (reverse cur)) found))))
          (else (loop (cdr cs) (cons (car cs) cur) found)))))

;; parse-sink : String -> (U (Listof (Pairof Symbol String)) List)
;; The origin's sink line as fields: (face . FACE), then each NAME=VALUE as
;; (NAME . VALUE); (unread TEXT) for any other text.
(define (parse-sink text)
  (let ((ws (words text)))
    (if (and (>= (length ws) 2) (string=? (car ws) "sink"))
        (cons (cons 'face (cadr ws))
              (map (lambda (w)
                     (let loop ((i 0))
                       (cond ((= i (string-length w)) (cons 'unread w))
                             ((char=? (string-ref w i) #\=)
                              (cons (string->symbol (substring w 0 i)) (substring w (+ i 1) (string-length w))))
                             (else (loop (+ i 1))))))
                   (cddr ws)))
        (list 'unread text))))

;; sink-line : Token -> Any
;; TOKEN's response, the origin's sink line, as fields, once it is a 200;
;; else its outcome.
(define (sink-line token)
  (let ((o (curl-token-outcome token)))
    (if (and (curl-response? o) (= (curl-response-status o) 200) (curl-response-body o))
        (parse-sink (latin-1 (curl-response-body o)))
        (outcome-of token))))

;; field : Any Symbol -> Any
(define (field line name)
  (let ((f (and (list? line) (for-all pair? line) (assq name line))))
    (if f (cdr f) (list 'no-field name line))))

;; whole : Any Natural -> Any
;; whole-body when LINE says the body arrived as N bytes of the pattern,
;; its SHA-256 the pattern's; else what it says.
(define (whole line n)
  (if (and (equal? (field line 'bytes) (number->string n))
           (equal? (field line 'pattern) "ok")
           (equal? (field line 'sha256) (sha-of n)))
      'whole-body
      (list 'not-whole n line)))

;; seen-count : Origin Engine String -> Any
;; The origin's count of the requests for KEY, by GET /seen on the http
;; face, a whole body read on ENGINE.
(define (seen-count o engine key)
  (guard (e (#t (list 'raised (describe e))))
    (let* ((t (curl-submit engine (make-curl-request (url-of o 'http (string-append "/seen?key=" key))
                                                     'proxy #f 'timeout-ms 20000)))
           (r (curl-token-await t))
           (ws (words (latin-1 (curl-response-body r)))))
      (if (and (= (length ws) 2) (string=? (car ws) "seen")) (string->number (cadr ws)) (list 'unread ws)))))

;; --- the suite's engine -------------------------------------------------------------

(define main-thread (get-thread-id))

(define engine
  (guard (e (#t (list 'raised (describe e))))
    (make-curl-engine)))

(test-equal "the suite's engine is made, running, and the PKI is this run's"
  (list #t 'running 'made running-counts)
  (list (curl-engine? engine) (and (curl-engine? engine) (curl-engine-state engine)) (car pki-made)
        (native-counts)))

;; --- with no origin ---------------------------------------------------------------------

;; refused-token : Engine Symbol Any -> Token
;; The token of a METHOD request with BODY, done: it reaches a port
;; nothing listens on.
(define (refused-token engine method body)
  (let ((t (curl-submit engine (make-curl-request "http://127.0.0.1:1/" 'method method 'proxy #f
                                                  'timeout-ms 5000 'body body))))
    (curl-token-wait t 10000)
    t))

(test-equal "a stream operation on a token whose request does not stream its body is an assertion violation from its name, before anything: room-wait, a put, the end and the count; a whole body's and none's alike"
  '(((assertion-violation curl-token-room-wait) (assertion-violation curl-token-put-piece!)
     (assertion-violation curl-token-end-body!) (assertion-violation curl-token-body-count))
    ((assertion-violation curl-token-room-wait) (assertion-violation curl-token-put-piece!)
     (assertion-violation curl-token-end-body!) (assertion-violation curl-token-body-count)))
  (guard (e (#t (list 'raised (describe e))))
    (map (lambda (t)
           (list (raised (lambda () (curl-token-room-wait t 0)))
                 (raised (lambda () (curl-token-put-piece! t (pattern-piece 0 1) 0)))
                 (raised (lambda () (curl-token-end-body! t)))
                 (raised (lambda () (curl-token-body-count t)))))
         (list (refused-token engine 'post #vu8(1 2)) (refused-token engine 'post #f)))))

(test-equal "each request-stream operation refuses what is no token, an assertion violation from its name"
  '((assertion-violation curl-token-room-wait) (assertion-violation curl-token-put-piece!)
    (assertion-violation curl-token-end-body!) (assertion-violation curl-token-body-count))
  (list (raised (lambda () (curl-token-room-wait 'no 0)))
        (raised (lambda () (curl-token-put-piece! 'no (pattern-piece 0 1))))
        (raised (lambda () (curl-token-end-body! 'no)))
        (raised (lambda () (curl-token-body-count 'no)))))

(test-equal "a put of what is no piece is an assertion violation from curl-token-put-piece!, before anything, on a token done too: an empty bytevector, a string, a list and #f; so is a bound that is no natural, -1 and 1.5; a token done answers done to a piece and a good bound, room-wait done, and its count is 0"
  (list (make-list-of 6 '(assertion-violation curl-token-put-piece!))
        '(returned done) '(returned done) '(returned 0) '(transfer-error perform-failed 7 connect))
  (guard (e (#t (list 'raised (describe e))))
    (let ((t (refused-token engine 'post 'stream)))
      (list (map (lambda (thunk) (raised thunk))
                 (list (lambda () (curl-token-put-piece! t #vu8() 10))
                       (lambda () (curl-token-put-piece! t "ab" 10))
                       (lambda () (curl-token-put-piece! t '(1 2) 10))
                       (lambda () (curl-token-put-piece! t #f 10))
                       (lambda () (curl-token-put-piece! t (pattern-piece 0 1) -1))
                       (lambda () (curl-token-put-piece! t (pattern-piece 0 1) 1.5))))
            (raised (lambda () (curl-token-put-piece! t (pattern-piece 0 1) 10)))
            (raised (lambda () (curl-token-room-wait t 10)))
            (raised (lambda () (curl-token-body-count t)))
            (outcome-of t)))))

(test-equal "room-wait is refused inside a critical section, an assertion violation from curl-token-room-wait, before it waits; end-body! and the count are not waits, and are taken there"
  '((assertion-violation curl-token-room-wait) (returned unspecified) (returned 0))
  (guard (e (#t (list 'raised (describe e))))
    (let ((t (refused-token engine 'put 'stream)))
      (list (raised (lambda () (critical-section (curl-token-room-wait t 100))))
            (raised (lambda () (critical-section (curl-token-end-body! t)) 'unspecified))
            (raised (lambda () (critical-section (curl-token-body-count t))))))))

(test-equal "a put after the body's end is an assertion violation from curl-token-put-piece!, the piece not taken: on a token still queued, while the engine is held, a put taken, the end, then a put; a second end does nothing; the count stays at the first put's"
  '((returned #t) (returned unspecified) (assertion-violation curl-token-put-piece!) (returned unspecified) 3)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-engine-held engine
      (lambda ()
        (let ((t (curl-submit engine (make-curl-request "http://127.0.0.1:1/" 'method 'post 'proxy #f
                                                        'timeout-ms 5000 'body 'stream))))
          ;; let*: each step after the last, whatever order list's
          ;; arguments would be evaluated in (traps.md).
          (let* ((first (raised (lambda () (curl-token-put-piece! t (pattern-piece 0 3) 0))))
                 (end (raised (lambda () (curl-token-end-body! t) 'unspecified)))
                 (after (raised (lambda () (curl-token-put-piece! t (pattern-piece 3 3) 0))))
                 (again (raised (lambda () (curl-token-end-body! t) 'unspecified))))
            (list first end after again (curl-token-body-count t))))))))

(test-equal "a token cancelled while still queued, which no engine's thread ever set up, is done: a put answers done, the piece not taken, room-wait done, the end nothing, the count 0"
  '((returned done) (returned done) (returned unspecified) 0 (transfer-error cancelled #f none))
  (guard (e (#t (list 'raised (describe e))))
    (let ((t (call-with-engine-held engine
               (lambda ()
                 (let ((t (curl-submit engine (make-curl-request "http://127.0.0.1:1/" 'method 'post 'proxy #f
                                                                 'timeout-ms 5000 'body 'stream))))
                   (curl-token-cancel t)
                   t)))))
      (let* ((put (raised (lambda () (curl-token-put-piece! t (pattern-piece 0 3) 10))))
             (room (raised (lambda () (curl-token-room-wait t 10))))
             (end (raised (lambda () (curl-token-end-body! t) 'unspecified))))
        (list put room end (curl-token-body-count t) (outcome-of t))))))

;; owned-by-stream : (Listof String)
;; A streamed body's options, owned (the M6 plan, section 3.3): its read,
;; seek and prerequest callables and their data, and FRESH_CONNECT.
(define owned-by-stream
  '("READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA" "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT"))

(test-equal "the hatch refuses each of a streamed body's options as owned-option, by name: the read, seek and prerequest callables and their data, and FRESH_CONNECT, at 1 and at 0, on a streamed request and a whole one"
  (map (lambda (name) (list 'request-refused 'options name 'owned-option))
       (append owned-by-stream '("FRESH_CONNECT") owned-by-stream))
  (append (map (lambda (name)
                 (raised (lambda () (curl-request-with-options (make-curl-request "http://a/" 'method 'post 'body 'stream)
                                                               (list (cons name 1))))))
               owned-by-stream)
          (list (raised (lambda () (curl-request-with-options (make-curl-request "http://a/" 'method 'post 'body 'stream)
                                                              '(("FRESH_CONNECT" . 0))))))
          (map (lambda (name)
                 (raised (lambda () (curl-request-with-options (make-curl-request "http://a/" 'method 'post 'body #vu8(1))
                                                               (list (cons name 1))))))
               owned-by-stream)))

;; --- against the origin ----------------------------------------------------------------

(define (scenarios o)

  ;; --- each method's framing, every face
  (for-each
   (lambda (face)
     (test-equal (string-append (symbol->string face) ": post, put, patch and delete, each sized and chunked, 262,144 bytes in 16 KiB puts: each method and its framing as sent, Content-Length when sized, Transfer-Encoding: chunked over HTTP/1.1 when not, neither over HTTP/2, no Expect nor Content-Type, a streamed delete's too, each body whole by its hash, each a 200")
       (map (lambda (row)
              (let ((sized (cadr row)) (h2 (eq? face 'h2)))
                (list (car row) (if sized 'sized 'chunked)
                      (string-upcase (symbol->string (car row)))
                      (if sized "262144" "-")
                      (if (or sized h2) "-" "chunked")
                      "-" "-" 'whole-body '(#t put))))
            '((post #t) (post #f) (put #t) (put #f) (patch #t) (patch #f) (delete #t) (delete #f)))
       (on-engine-for face
         (lambda (engine)
           (map (lambda (row)
                  (let* ((method (car row))
                         (key (string-append "framing-" (symbol->string face) "-" (symbol->string method)
                                             (if (cadr row) "-sized" "-chunked")))
                         (t (curl-submit engine (upload-request o face (sink-path face key) method
                                                                (and (cadr row) 262144))))
                         (sent (send-whole t 262144 16384)))
                    (curl-token-wait t 30000)
                    (let ((line (sink-line t)))
                      (list method (if (cadr row) 'sized 'chunked)
                            (field line 'method) (field line 'cl) (field line 'te)
                            (field line 'expect) (field line 'ct) (whole line 262144) sent))))
                '((post #t) (post #f) (put #t) (put #f) (patch #t) (patch #f) (delete #t) (delete #f)))))))
   '(http raw https h2))

  ;; --- a request stream per submit
  (test-equal "a request submitted twice makes a request stream for each submit: two tokens of one request, fed in turn, each 2,000 bytes whole at its own sink"
    '((whole-body whole-body) (2000 2000))
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((r (upload-request o 'http (sink-path 'http "per-submit") 'post 2000))
               (a (curl-submit engine r))
               (b (curl-submit engine r)))
          (curl-token-room-wait a 20000)
          (curl-token-room-wait b 20000)
          (let loop ((at 0))
            (when (< at 2000)
              (curl-token-put-piece! a (pattern-piece at 500) 20000)
              (curl-token-put-piece! b (pattern-piece at 500) 20000)
              (loop (+ at 500))))
          (curl-token-end-body! a)
          (curl-token-end-body! b)
          (curl-token-wait a 20000)
          (curl-token-wait b 20000)
          (list (list (whole (sink-line a) 2000) (whole (sink-line b) 2000))
                (list (curl-token-body-count a) (curl-token-body-count b)))))))

  (test-equal "a token still queued has its request stream already: a put on it, while the engine is held, inside its critical section, is taken at once, the buffer empty; then the rest, and the body whole"
    '((returned #t) 1000 whole-body)
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((queued (call-with-engine-held engine
                         (lambda ()
                           (let ((t (curl-submit engine (upload-request o 'http (sink-path 'http "queued") 'post 2000))))
                             (list t (raised (lambda () (curl-token-put-piece! t (pattern-piece 0 1000) 0))))))))
               (t (car queued))
               (count (curl-token-body-count t)))
          (put-all t 1000 2000 1000 20000)
          (curl-token-end-body! t)
          (curl-token-wait t 20000)
          (list (cadr queued) count (whole (sink-line t) 2000))))))

  ;; --- pause and resume, and the gap on the wire
  (for-each
   (lambda (face)
     (test-equal (string-append (symbol->string face) ": pause and resume: a producer that puts 1,000 bytes, waits 300 ms, then puts 1,000 more: the read callable paused while it waited, and was resumed; the origin saw the first 1,000 bytes, then a gap of 250 ms or more, then the rest, the body whole")
       '(paused-and-resumed (gap 1000) whole-body)
       (on-engine-for face
         (lambda (engine)
           (let* ((t (curl-submit engine (upload-request o face (sink-path face (string-append "gap-" (symbol->string face)))
                                                         'post #f)))
                  (room (curl-token-room-wait t 20000))
                  (first (curl-token-put-piece! t (pattern-piece 0 1000) 20000))
                  (paused (wait-for (lambda () (and (= (ustat t 'handed) 1000) (send-paused? t))) 10000))
                  (_ (pause-ms 300))
                  (second (curl-token-put-piece! t (pattern-piece 1000 1000) 20000)))
             (curl-token-end-body! t)
             (curl-token-wait t 20000)
             (let* ((line (sink-line t))
                    (gap (field line 'gap))
                    (at (and (string? gap) (let loop ((i 0)) (and (< i (string-length gap))
                                                                     (if (char=? (string-ref gap i) #\@) i (loop (+ i 1)))))))
                    (ms (and at (string->number (substring gap 0 at))))
                    (before (and at (string->number (substring gap (+ at 1) (string-length gap))))))
               (list (if (and (eq? room #t) (eq? first #t) (eq? second #t) paused (>= (ustat t 'resumes) 1)
                              (assq 'paused (ustat t 'reads)))
                         'paused-and-resumed
                         (list room first second paused (curl-token-upload-stats t)))
                     (if (and ms (>= ms 250)) (list 'gap before) (list 'gap-was gap))
                     (whole line 2000))))))))
   '(http h2))

  (test-equal "one resume per pause: 20 pieces of 1,000 bytes, chunked, each once the last was handed and the send paused, 30 ms apart: every pause the read callable made was resumed, once, the end's among them, and the engine passed none over; the body whole"
    '(paused-and-resumed-once none-passed whole-body)
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((passed (curl-engine-passed-resumes engine))
               (t (curl-submit engine (upload-request o 'http (sink-path 'http "once") 'post #f))))
          (curl-token-room-wait t 20000)
          (let loop ((at 0))
            (when (< at 20000)
              (curl-token-put-piece! t (pattern-piece at 1000) 20000)
              (wait-for (lambda () (send-paused? t)) 5000)
              (pause-ms 30)
              (loop (+ at 1000))))
          (curl-token-end-body! t)
          (curl-token-wait t 20000)
          (list (if (and (>= (ustat t 'pauses) 20) (= (ustat t 'pauses) (ustat t 'resumes)))
                    'paused-and-resumed-once
                    (list 'pauses (ustat t 'pauses) 'resumes (ustat t 'resumes)))
                (if (= passed (curl-engine-passed-resumes engine)) 'none-passed
                    (list passed (curl-engine-passed-resumes engine)))
                (whole (sink-line t) 20000))))))

  ;; --- "once": a put or an end queues a resume when the transfer is
  ;; paused for sending, once (the M6 plan, section 3.3), the flag deciding.
  ;; Two puts while the engine is held reach one turn; so do a put and an
  ;; end. With a resume per put, that turn carries out two.
  (for-each
   (lambda (row)
     (test-equal (string-append "a resume is queued once per pause: " (car row)
                                ", made while the engine is held and the send paused, reach one turn, which carries out one resume; then the body arrives whole")
       '(paused 1 whole-body)
       (on-own-engine make-curl-engine
         (lambda (engine)
           (let* ((t (curl-submit engine (upload-request o 'http (sink-path 'http (cadr row)) 'post #f)))
                  (room (curl-token-room-wait t 20000))
                  (paused (wait-for (lambda () (send-paused? t)) 20000))
                  (resumes (ustat t 'resumes)))
             (call-with-engine-held engine
               (lambda ()
                 (if (string=? (cadr row) "once-two")
                     (begin (curl-token-put-piece! t (pattern-piece 0 1000) 0)
                            (curl-token-put-piece! t (pattern-piece 1000 1000) 0))
                     (begin (curl-token-put-piece! t (pattern-piece 0 2000) 0)
                            (curl-token-end-body! t)))))
             (let* ((n 2000)
                    (taken (wait-for (lambda () (= (ustat t 'handed) n)) 10000))
                    (count (- (ustat t 'resumes) resumes)))
               (when (string=? (cadr row) "once-two") (curl-token-end-body! t))
               (curl-token-wait t 20000)
               (list (if (and (eq? room #t) paused taken) 'paused (list room paused taken))
                     count (whole (sink-line t) n))))))))
   '(("two puts" "once-two") ("a put and an end" "once-end")))

  ;; --- the head's body-asked bit (the M6 plan, section 3.2; ADR-0032,
  ;; decision 3): whether libcurl had asked for a streamed body by the final
  ;; head, read in the hold that publishes it. Measured 5 runs of 5 on each
  ;; of the five Linux libcurls (build/m6s2b/logs/asked-*.log): #t for every
  ;; streamed body libcurl asks for, a server's answer before it reads the
  ;; body included, since the first ask comes with the head or as it is
  ;; sent; #f for a whole body, none, and a length of 0, which libcurl
  ;; never asks for. No case's answer moves by version.
  (test-equal "the head's body-asked bit: #t for a streamed body whose server answers before reading it, over HTTP/1.1 with a close and over HTTP/2, nothing put by the head; #t for one whose server reads it before answering, on the raw face and over HTTP/2; #f for a whole body, for none, and for a streamed length of 0, which libcurl never asks for"
    '((raw-answer #t) (h2-answer #t) (raw-sink #t) (h2-sink #t) (whole #f) (none #f) (zero #f))
    (map (lambda (row)
           (on-own-engine make-curl-engine
             (lambda (own)
               (let* ((name (car row)) (face (cadr row)) (body (cadddr row)) (length (car (cddddr row)))
                      (base (let ((r (make-curl-request (url-of o face (caddr row)) 'proxy #f 'timeout-ms 20000
                                                        'stream-buffer 1024
                                                        'method (if (eq? body 'none) 'get 'post))))
                              (if (memq face '(https h2)) (curl-request-with r 'ca-file ca) r)))
                      (t (curl-submit own (case body
                                            ((stream) (curl-request-with base 'body 'stream 'body-length length))
                                            ((whole) (curl-request-with base 'body (pattern-piece 0 1000)))
                                            (else base))))
                      (fed (and (memq name '(raw-sink h2-sink))
                                (begin (curl-token-room-wait t 20000)
                                       (curl-token-put-piece! t (pattern-piece 0 1000) 20000)
                                       (curl-token-end-body! t)
                                       #t)))
                      (head (and (curl-token-head-wait t 20000) (curl-token-head t)))
                      (asked (if (curl-head? head) (curl-head-body-asked? head) (list 'no-head (outcome-of t)))))
                 (when (memq name '(raw-answer h2-answer))
                   (put-all t 0 1000 1000 1000)
                   (curl-token-end-body! t))
                 (let drain () (when (bytevector? (curl-token-next-piece t 5000)) (drain)))
                 (curl-token-wait t 20000)
                 (list name asked)))))
         '((raw-answer raw "/raw/answer?status=200&close=1" stream #f)
           (h2-answer h2 "/answer?status=200" stream #f)
           (raw-sink raw "/raw/sink?key=asked-raw" stream 1000)
           (h2-sink h2 "/sink?key=asked-h2" stream 1000)
           (whole http "/sink?key=asked-whole" whole #f)
           (none http "/seen?key=asked-none" none #f)
           (zero http "/sink?key=asked-zero" stream 0))))

  ;; --- the body-asked bit with the answer first (M6 slice 2, round 4):
  ;; the raw face, armed by /raw/arm, writes its answer to its next
  ;; connection as it accepts it, before reading a byte. Whether that
  ;; answer lands before libcurl sends its request is a race: libcurl won
  ;; it in 100 of 100 native runs on the five Linux libcurls, and lost it
  ;; in 20 of 20 for 8.5.0 under Valgrind (build/m6s2b/asked2/lane-*.log,
  ;; vg-unheld.log). An engine whose prerequest callable holds 200 ms once
  ;; connected decides it: the answer lands first, and 7.85.0 and 8.5.0,
  ;; which read before they send, stop sending without asking, while
  ;; 8.20.0 and 8.23.0 ask with the head; 20 of 20 on each lane, 8.5.0
  ;; under Valgrind too (held-*.log, vg-held.log). Each case, a streamed
  ;; post of 1,000 bytes with a stream-buffer, nothing put by its head:
  ;; (FRAMING STATUS BIT ASK OUTCOME HOLDS), ASK asked when the read
  ;; callable was ever called, never when not, and HOLDS the hold seam's
  ;; count on the case's own engine.
  (let ((arm-first
         (lambda (own status framing)
           (let ((armed (curl-token-await
                         (curl-submit own (make-curl-request
                                           (url-of o 'raw (string-append "/raw/arm?status=" (number->string status)))
                                           'proxy #f 'timeout-ms 10000)))))
             (if (not (eqv? (curl-response-status armed) 200))
                 (list framing status 'arm-answered (curl-response-status armed))
                 (let* ((t (curl-submit own (curl-request-with
                                             (upload-request o 'raw "/raw/content-length" 'post
                                                             (and (eq? framing 'sized) 1000))
                                             'timeout-ms 10000 'stream-buffer 1024)))
                        (head (and (curl-token-head-wait t 5000) (curl-token-head t)))
                        (bit (if (curl-head? head) (curl-head-body-asked? head) (list 'no-head (outcome-of t)))))
                   ;; A put on a token done answers done, and an end there
                   ;; does nothing.
                   (curl-token-put-piece! t (pattern-piece 0 1000) 1000)
                   (curl-token-end-body! t)
                   (let drain () (when (bytevector? (curl-token-next-piece t 2000)) (drain)))
                   (curl-token-wait t 10000)
                   (list framing status bit
                         (if (cdr (assq 'asked (curl-token-upload-stats t))) 'asked 'never)
                         (outcome-of t)
                         (curl-engine-prereq-holds own)))))))
        (cases '((200 sized) (200 chunked) (413 sized) (413 chunked)))
        ;; (VERSION BIT ASK): every case's bit and ask, on that libcurl.
        (held-rows '(("7.85.0" #f never) ("8.5.0" #f never) ("8.7.1" #t asked) ("8.20.0" #t asked)
                     ("8.23.0" #t asked))))
    (test-equal (string-append "the head's body-asked bit with the answer first, by version, on "
                               (if (string? version) version (written version))
                               ": on an engine whose prerequest callable holds 200 ms once connected, the raw face's answer, written as it accepts, lands before the request; 7.85.0 and 8.5.0 read it and stop sending, never asking, #f; 8.20.0 and 8.23.0 ask with the head, #t; each ends with the early status, 200 and 413, sized and chunked, the hold made once; a libcurl with no row fails, showing what it measured")
      (let ((row (and (string? version) (assoc version held-rows))))
        (if row
            (map (lambda (c) (list (cadr c) (car c) (cadr row) (caddr row) (list 'response (car c) 'http/1.1) 1))
                 cases)
            (list 'a-row-for version)))
      (let* ((row (and (string? version) (assoc version held-rows)))
             (measured (map (lambda (c)
                              (on-own-engine (lambda () (make-curl-engine-holding-prereq 200))
                                (lambda (own) (arm-first own (car c) (cadr c)))))
                            cases)))
        (if row measured (list 'no-row-for version 'measured measured))))
    (test-equal "the head's body-asked bit with the answer written as the connection is accepted, on a caller's engine: whether the answer lands before the request is a race, so each case's bit is whether the read callable was ever asked, and it ends with the early status, 200 and 413, sized and chunked; no hold made"
      (map (lambda (c) (list (cadr c) (car c) 'bit-is-ask (list 'response (car c) 'http/1.1) 0)) cases)
      (map (lambda (c)
             (let ((m (on-own-engine make-curl-engine (lambda (own) (arm-first own (car c) (cadr c))))))
               (if (= (length m) 6)
                   (let ((bit (list-ref m 2)) (ask (list-ref m 3)))
                     (list (car m) (cadr m)
                           (if (and (boolean? bit) (eq? bit (eq? ask 'asked))) 'bit-is-ask (list 'bit bit ask))
                           (list-ref m 4) (list-ref m 5)))
                   m)))
           cases)))

  ;; --- a done from a put means the token is done (the M6 plan, section
  ;; 3.1): the request stream closes as the engine's thread reads the
  ;; outcome, before it completes the token, so a put in between waits.
  (test-equal "a put whose request stream has closed waits until its token is done: on an engine whose thread stalls 1,000 ms between reading an outcome and completing its token, a put made once the stream closed answers #f at a bound of 100 ms, and another, with a bound of 5,000, answers done only once the token is done, its outcome readable at once, the piece not taken"
    '(closed-not-done #f done waited (response 200 http/1.1) 10)
    (on-own-engine (lambda () (make-curl-engine-stalling-completion 1000))
      (lambda (own)
        (let* ((t (curl-submit own (upload-request o 'http (sink-path 'http "stalled-completion") 'post 10)))
               (_ (curl-token-room-wait t 20000))
               (_p (curl-token-put-piece! t (pattern-piece 0 10) 20000))
               (closed (wait-for (lambda () (ustat t 'closed)) 20000))
               (state (list closed (curl-token-done? t)))
               (bounded (curl-token-put-piece! t (pattern-piece 10 1) 100))
               (t0 (now-ms))
               (answer (curl-token-put-piece! t (pattern-piece 10 1) 5000))
               (took (- (now-ms) t0))
               (outcome (outcome-of t)))
          (list (if (equal? state '(#t #f)) 'closed-not-done state)
                bounded answer (if (>= took 300) 'waited took) outcome
                (curl-token-body-count t))))))

  ;; --- room-wait before libcurl asks: a length of 0 is never asked for
  (test-equal "room-wait answers #f within its bound before libcurl asks: a length of 0, which libcurl never asks for, to a raw script that holds its answer 1,000 ms; then done once the transfer ends, a 200"
    '(#f done (response 200 http/1.1))
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((t (curl-submit engine (upload-request o 'raw "/raw/hold?key=never-asked&ms=1000" 'post 0)))
               (early (curl-token-room-wait t 300))
               (done (begin (curl-token-wait t 20000) (curl-token-room-wait t 1000))))
          (list early done (outcome-of t))))))

  ;; --- a put that waits while the buffer is full
  (test-equal "a put waits while the buffer is full: to a raw sink that reads nothing for 5,000 ms, 64 KiB puts fill the kernel's buffers and the request's, and a put answers #f at its bound of 500 ms, libcurl taking nothing through it, the buffer holding 65,536 bytes or more; then 32 MiB whole, and once done a put, room-wait and end answer done and nothing"
    '(full-at-bound held-bounded put whole-body
      ((returned done) (returned done) (returned unspecified)) 33554432)
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((n 33554432)
               (t (curl-submit engine (upload-request o 'raw (sink-path 'raw "full" "&hold=5000") 'post n)))
               (room (curl-token-room-wait t 20000))
               (full (fill-until-stalled t n))
               (most (ustat t 'most))
               (rest (if (and (pair? full) (eq? (car full) #f)) (put-all t (cadr full) n 65536 20000) full)))
          (curl-token-end-body! t)
          (curl-token-wait t 30000)
          (list (if (and (eq? room #t) (pair? full) (eq? (car full) #f) (> (ustat t 'fulls) 0)) 'full-at-bound
                    (list room full))
                (if (and (>= most 65536) (< most (* 2 65536))) 'held-bounded most)
                rest (whole (sink-line t) n)
                (list (raised (lambda () (curl-token-put-piece! t (pattern-piece 0 1) 10)))
                      (raised (lambda () (curl-token-room-wait t 10)))
                      (raised (lambda () (curl-token-end-body! t) 'unspecified)))
                (curl-token-body-count t))))))

  ;; A buffer libcurl never drains: an https request to the raw face, which
  ;; is plaintext and waits for a request head, so the TLS handshake never
  ;; ends and libcurl never asks for the body.
  (test-equal "a put waiting on a full buffer answers done once its token is done: to a server whose TLS handshake never ends, so libcurl never asks, a put of 65,536 bytes is taken, the buffer full; another inside a critical section is refused before it waits; another, with a bound of 10,000 ms, waits, a cancel from another thread 300 ms on ends the token, and the put answers done within 5 s, the piece not taken"
    '((returned #t) (assertion-violation curl-token-put-piece!) #f done within-5-s 65536 (transfer-error cancelled #f none))
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((f (origin-face o 'raw))
               (t (curl-submit engine (make-curl-request (string-append "https://" (car f) ":" (number->string (cdr f)) "/never")
                                                         'method 'post 'proxy #f 'timeout-ms 20000 'ca-file ca
                                                         'body 'stream)))
               (first (raised (lambda () (curl-token-put-piece! t (pattern-piece 0 65536) 1000))))
               (inside (raised (lambda () (critical-section (curl-token-put-piece! t (pattern-piece 65536 1) 10)))))
               (asked (ustat t 'asked)))
          (fork-thread (lambda () (pause-ms 300) (curl-token-cancel t)))
          (let* ((t0 (now-ms))
                 (a (curl-token-put-piece! t (pattern-piece 65536 65536) 10000))
                 (took (- (now-ms) t0)))
            (curl-token-wait t 10000)
            (list first inside asked a (if (< took 5000) 'within-5-s took)
                  (curl-token-body-count t) (outcome-of t)))))))

  ;; --- the put's escape, in a child
  (test-equal "the put's escape, in a child: a keyboard interrupt made pending while a put waits for the request stream's mutex, inside its critical section, runs as that section ends; a handler that escapes leaves the piece committed, counted by curl-token-body-count, and sent; one that returns, the same; three runs each, the 15 bytes whole at the origin each time"
    (list 0
          (apply append
                 (map (lambda (run)
                        (list (list 'case run 'escapes 'escaped 5 15 "15" "ok" (sha-of 15))
                              (list 'case run 'returns '(returned #t) 5 15 "15" "ok" (sha-of 15))))
                      '(1 2 3)))
          zero-counts)
    (let ((r (run-child '() "tests/upload-escape.sps" (url-of o 'http "") "3")))
      (list (car r)
            (filter (lambda (d) (and (pair? d) (eq? (car d) 'case))) (cadr r))
            (let ((c (filter (lambda (d) (and (pair? d) (eq? (car d) 'counts))) (cadr r))))
              (if (pair? c) (cadr (car c)) r)))))

  ;; --- the put's commit, a timer swept across its call a tick at a time,
  ;; twice, to 20 ticks past it (the M6 plan, section 3.5; slice 1's take
  ;; sweep, C10's): an expiry inside the put's section waits for a later
  ;; event check, so an escape before the commit leaves the count as it was
  ;; and the piece is put again, and one after leaves it counted; the body
  ;; whole either way. The planted control, the split plant, commits after
  ;; the section in two plain writes with a loop between, where an expiry
  ;; leaves the tail moved and the piece uncounted, and the piece put again
  ;; then gives the wrong bytes.
  (let ((sweep
         (lambda (plant)
           (on-own-engine make-curl-engine
             (lambda (engine)
               (let* ((t (curl-submit engine (upload-request o 'http (sink-path 'http (if plant "sweep-split" "sweep"))
                                                             'post #f)))
                      (room (curl-token-room-wait t 20000))
                      (at 0) (got #f) (escaped-kept 0) (escaped-redone 0) (returned 0))
                 (define (one) (curl-token-put-piece! t (pattern-piece at 1) 5000))
                 (when plant (curl-token-plant-put! t 'split))
                 ;; The call's length, in ticks, read once with no expiry.
                 (set-timer 100000000)
                 (set! got (one))
                 (let ((call-ticks (- 100000000 (set-timer 0))))
                   (when (eq? got #t) (set! returned 1) (set! at 1))
                   (let pass ((passes 2))
                     (when (> passes 0)
                       (let tick ((ticks 1))
                         (when (<= ticks (+ call-ticks 20))
                           (let* ((count (curl-token-body-count t))
                                  (k #f)
                                  (answer (call/cc
                                           (lambda (escape)
                                             (set! k escape)
                                             (set! got #f)
                                             (timer-interrupt-handler (lambda () (k 'escaped)))
                                             (set-timer ticks)
                                             ;; The answer is stored before any event check, so
                                             ;; an expiry after the call returns is told from
                                             ;; one inside it.
                                             (set! got (one))
                                             (set-timer 0)
                                             'returned))))
                             (set-timer 0)
                             (cond ((eq? got #t) (set! returned (+ returned 1)) (set! at (+ at 1)))
                                   ((not (eq? answer 'escaped)) #f)
                                   ((> (curl-token-body-count t) count)
                                    (set! escaped-kept (+ escaped-kept 1)) (set! at (+ at 1)))
                                   (else (set! escaped-redone (+ escaped-redone 1))))
                             (tick (+ ticks 1)))))
                       (pass (- passes 1))))
                   (timer-interrupt-handler (lambda () #f))
                   (when plant (curl-token-plant-put! t #f))
                   (curl-token-end-body! t)
                   (curl-token-wait t 20000)
                   (let ((line (sink-line t)))
                     ;; The sweep's evidence, on stdout: where it landed.
                     (display (list 'put-sweep (if plant 'planted 'plain) 'call-ticks call-ticks
                                    'escaped-kept escaped-kept 'escaped-redone escaped-redone 'returned returned
                                    'at at 'bytes (field line 'bytes) 'pattern (field line 'pattern)))
                     (newline)
                     (list (eq? room #t) call-ticks escaped-kept escaped-redone returned at
                           (field line 'bytes) (field line 'pattern))))))))))
    (test-equal "a timer swept a tick at a time, twice, across a put's call to 20 ticks past it: an escape before the commit leaves the piece uncounted, and it is put again; none leaves it half committed; every piece the count says was taken arrives once, in order"
      '(swept redone whole)
      (let ((r (sweep #f)))
        (if (and (list? r) (= (length r) 8))
            (list (if (and (list-ref r 0) (> (list-ref r 1) 0) (> (list-ref r 4) 1)) 'swept r)
                  (if (> (list-ref r 3) 0) 'redone r)
                  (if (and (equal? (list-ref r 6) (number->string (list-ref r 5))) (equal? (list-ref r 7) "ok"))
                      'whole r))
            r)))
    (test-equal "the sweep's planted control: a put that commits after its section, its tail and its count written apart, a test seam's, where an expiry can land, gives a body that is not the pieces the count said were taken"
      'not-whole
      (let ((r (sweep #t)))
        (if (and (list? r) (= (length r) 8))
            (if (and (equal? (list-ref r 6) (number->string (list-ref r 5))) (equal? (list-ref r 7) "ok"))
                r 'not-whole)
            r))))

  ;; --- the put's stress test: the second review's full-duplex producer
  (test-equal "the put's stress test: 4,000 pieces of 16 bytes, each put once the read callable has handed the last, chunked: no piece waits 500 ms untaken while the send is paused with no resume queued, and the body is whole"
    '(0 put whole-body)
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((n 4000)
               (t (curl-submit engine (upload-request o 'http (sink-path 'http "stress") 'post #f))))
          (curl-token-room-wait t 20000)
          (let loop ((i 0) (stalls 0))
            (if (= i n)
                (begin
                  (curl-token-end-body! t)
                  (curl-token-wait t 30000)
                  (list stalls 'put (whole (sink-line t) 64000)))
                (let ((a (curl-token-put-piece! t (pattern-piece (* 16 i) 16) 20000)))
                  (if (not (eq? a #t))
                      (list stalls (list 'put-answered a i))
                      (let ((since (now-ms)))
                        (let wait ((stalled #f))
                          (cond
                            ((>= (ustat t 'handed) (* 16 (+ i 1))) (loop (+ i 1) (if stalled (+ stalls 1) stalls)))
                            ((> (- (now-ms) since) 5000) (list (+ stalls 1) (list 'never-taken i)))
                            (else
                             (pause-us 50)
                             (wait (or stalled (and (> (- (now-ms) since) 500) (send-paused? t))))))))))))))))

  ;; --- body-length-mismatch, short and long, and a length of 0
  (for-each
   (lambda (face)
     (test-equal (string-append (symbol->string face) ": body-length-mismatch: an end short of the length, 500 bytes of 1,000, fails the transfer as body-length-mismatch, the read callable's abort, 42, of no class, alike on every libcurl; a put past the length, 600 then 600 of 1,000, the second once the read has paused again, is refused, naming body-length and the length, the piece not taken, and the transfer fails the same, by the resume the refusal queued; the counts 500 and 600")
       '(((transfer-error body-length-mismatch 42 none) 500)
         ((returned #t) (request-refused body-length 1000 body-length-mismatch)
          (transfer-error body-length-mismatch 42 none) 600))
       (on-engine-for face
         (lambda (engine)
           (list (let ((t (curl-submit engine (upload-request o face (sink-path face (string-append "short-" (symbol->string face)))
                                                              'post 1000))))
                   (curl-token-room-wait t 20000)
                   (curl-token-put-piece! t (pattern-piece 0 500) 20000)
                   (curl-token-end-body! t)
                   (curl-token-wait t 30000)
                   (list (outcome-of t) (curl-token-body-count t)))
                 (let* ((t (curl-submit engine (upload-request o face (sink-path face (string-append "long-" (symbol->string face)))
                                                               'post 1000)))
                        (_ (curl-token-room-wait t 20000))
                        (a (raised (lambda () (curl-token-put-piece! t (pattern-piece 0 600) 20000))))
                        ;; The read paused again, so only the refusal's own
                        ;; resume can carry it to its abort.
                        (_w (wait-for (lambda () (and (= (ustat t 'handed) 600) (send-paused? t))) 10000))
                        (b (raised (lambda () (curl-token-put-piece! t (pattern-piece 600 600) 20000)))))
                   (curl-token-wait t 30000)
                   (list a b (outcome-of t) (curl-token-body-count t))))))))
   '(http raw h2))

  (test-equal "the resume step clears the send bit: a body of 1,000 bytes, paused at libcurl's first ask, then put whole and resumed, to a raw script that holds its answer 1,000 ms: while it holds, the body handed, libcurl asks for no more, and the transfer is not counted paused for sending; then a 200"
    '(paused-first not-paused (response 200 http/1.1))
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((t (curl-submit engine (upload-request o 'raw "/raw/hold?key=cleared&ms=1000" 'post 1000)))
               (room (curl-token-room-wait t 20000))
               (first (wait-for (lambda () (send-paused? t)) 10000))
               (put (curl-token-put-piece! t (pattern-piece 0 1000) 20000))
               (handed (wait-for (lambda () (and (= (ustat t 'handed) 1000) (>= (ustat t 'resumes) 1))) 10000)))
          (pause-ms 200)
          (let ((held (list (ustat t 'paused) (ustat t 'queued) (curl-token-done? t))))
            (curl-token-wait t 20000)
            (list (if (and (eq? room #t) first (eq? put #t)) 'paused-first (list room first put))
                  (if (and handed (equal? held '(#f #f #f))) 'not-paused (list handed held))
                  (outcome-of t)))))))

  (test-equal "a length of 0: libcurl never asks, and the origin reads Content-Length: 0 and no byte, a 200; and on another submit, a put, made while the engine is held, the token queued, is refused as past the length, the piece not taken, and the transfer, which libcurl ends 0, fails as body-length-mismatch, the refusal's, with the origin's one request; the counts 0"
    '("0" "0" (response 200 http/1.1)
      (request-refused body-length 0 body-length-mismatch) (transfer-error body-length-mismatch 0 none) 1 0)
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((plain (curl-submit engine (upload-request o 'http (sink-path 'http "zero") 'post 0)))
               (_ (curl-token-wait plain 20000))
               (line (sink-line plain))
               (queued (call-with-engine-held engine
                         (lambda ()
                           (let ((t (curl-submit engine (upload-request o 'http (sink-path 'http "zero-put") 'post 0))))
                             (list t (raised (lambda () (curl-token-put-piece! t (pattern-piece 0 1)))))))))
               (t (car queued)))
          (curl-token-wait t 20000)
          (list (field line 'cl) (field line 'bytes) (outcome-of plain)
                (cadr queued) (outcome-of t) (seen-count o engine "zero-put") (curl-token-body-count t))))))

  (test-equal "a put past the length once libcurl has read the length whole, and calls the read callable no more, still fails the transfer: 1,000 bytes put to a raw script that holds its answer 1,000 ms, all handed, then a put of 1 byte, refused; the transfer, which libcurl ends 0 with the answer, fails as body-length-mismatch; a put after the outcome answers done"
    '((returned #t) handed (request-refused body-length 1000 body-length-mismatch)
      (transfer-error body-length-mismatch 0 none) done 1000)
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((t (curl-submit engine (upload-request o 'raw "/raw/hold?key=past-whole&ms=1000" 'post 1000)))
               (_ (curl-token-room-wait t 20000))
               (first (raised (lambda () (curl-token-put-piece! t (pattern-piece 0 1000) 20000))))
               (handed (wait-for (lambda () (= (ustat t 'handed) 1000)) 10000))
               (past (raised (lambda () (curl-token-put-piece! t (pattern-piece 1000 1) 20000)))))
          (curl-token-wait t 20000)
          (list first (if handed 'handed (curl-token-upload-stats t)) past (outcome-of t)
                (curl-token-put-piece! t (pattern-piece 1000 1) 10) (curl-token-body-count t))))))

  ;; --- at most once (ADR-0032, amended)
  (let ((pooled
         (lambda (make then key n)
           ;; On an engine MAKE made: GET /close-after?then=THEN on the http
           ;; face, a whole body, which pools its connection, marked; then a
           ;; streamed post of N bytes to /sink?key=KEY, put whole and ended;
           ;; then the origin's count for KEY: (OUTCOME ATTEMPTS SEEKS SEEN
           ;; SINK).
           (on-own-engine make
             (lambda (own)
               (let* ((first (curl-token-await (curl-submit own (make-curl-request (url-of o 'http (string-append "/close-after?then=" then))
                                                                                     'proxy #f 'timeout-ms 20000))))
                      (t (curl-submit own (upload-request o 'http (sink-path 'http key) 'post n))))
                 (send-whole t n 65536)
                 (curl-token-wait t 30000)
                 (list (outcome-of t) (ustat t 'attempts) (ustat t 'seeks) (seen-count o own key)
                       (let ((r (outcome-of t)))
                         (if (and (pair? r) (eq? (car r) 'response)) (whole (sink-line t) n) 'no-response)))))))))
    (test-equal "at most once: FRESH_CONNECT keeps a dead pooled connection away: after a whole GET whose connection the origin marks to cut the next request read whole, a streamed post goes on a connection of its own: a 200, one attempt, no seek, one request at the origin, the body whole"
      '((response 200 http/1.1) 1 0 1 whole-body)
      (pooled make-curl-engine "kill" "fresh-kill" 131072))

    ;; By version: the prerequest callable's calls when the seek refuses
    ;; libcurl's rewind. Apple's 8.7.1 drops the rewind's result and goes
    ;; on to a second attempt, which the prerequest callable refuses (the
    ;; plan's section 2.4); the Linux libcurls end at the seek.
    (let ((attempt-rows '(("7.85.0" . 1) ("8.5.0" . 1) ("8.7.1" . 2) ("8.20.0" . 1) ("8.23.0" . 1))))
      (test-equal (string-append "at most once, by a test seam that leaves FRESH_CONNECT off: the streamed post reuses the marked connection, the origin reads it whole and cuts it, and libcurl's resend is refused by the seek, body-not-replayable, of no class, with one request at the origin; the prerequest callable's calls as "
                                 (if (string? version) version (written version))
                                 "'s row says; a libcurl with no row fails, showing what it measured")
        (let ((row (and (string? version) (assoc version attempt-rows))))
          (if row (list 'body-not-replayable (cdr row) 'sought 1) (list 'a-row-for version)))
        (let* ((row (and (string? version) (assoc version attempt-rows)))
               (r (pooled make-curl-engine-reusing "kill" "reused-kill" 131072))
               (measured
                (if (and (list? r) (= (length r) 5))
                    (list (if (and (list? (car r)) (= (length (car r)) 4)
                                   (equal? (list-head (car r) 2) '(transfer-error body-not-replayable))
                                   (eq? (cadddr (car r)) 'none))
                              'body-not-replayable (car r))
                          (cadr r) (if (>= (caddr r) 1) 'sought (caddr r)) (cadddr r))
                    r)))
          (if row measured (list 'no-row-for version 'measured measured)))))

    (test-equal "at most once: a resend before any byte was handed goes on: on the seam's engine, the marked connection reset as the post's head arrives, the read paused 500 ms with nothing put; libcurl resends, and the second attempt's body arrives whole, a 200, two attempts, two requests at the origin"
      '((response 200 http/1.1) 2 2 whole-body)
      (on-own-engine make-curl-engine-reusing
        (lambda (own)
          (let* ((first (curl-token-await (curl-submit own (make-curl-request (url-of o 'http "/close-after?then=resethead")
                                                                                'proxy #f 'timeout-ms 20000))))
                 (t (curl-submit own (upload-request o 'http (sink-path 'http "resethead") 'post 65536))))
            (curl-token-room-wait t 20000)
            (pause-ms 500)
            (put-all t 0 65536 65536 20000)
            (curl-token-end-body! t)
            (curl-token-wait t 30000)
            (list (outcome-of t) (ustat t 'attempts) (seen-count o own "resethead") (whole (sink-line t) 65536))))))

    (test-equal "at most once: the prerequest callable refuses the resend a test seam lets past the seek: on an engine whose seek answers OK once bytes were handed, FRESH_CONNECT off, the marked connection cut after the post is read whole, libcurl rewinds and makes a second attempt, which the prerequest callable refuses, body-not-replayable, of no class, before its head is sent: two attempts, one request at the origin, on every libcurl"
      '((transfer-error body-not-replayable none) 2 1)
      (let ((r (pooled make-curl-engine-rewinding "kill" "rewound-kill" 131072)))
        (if (and (list? r) (= (length r) 5))
            (list (if (and (list? (car r)) (= (length (car r)) 4))
                      (list (car (car r)) (cadr (car r)) (cadddr (car r)))
                      (car r))
                  (cadr r) (cadddr r))
            r))))

  (test-equal "at most once over HTTP/2: a stream refused with REFUSED_STREAM after 32 KiB of DATA, 131,072 bytes put, is refused libcurl's resend, body-not-replayable, of no class, with one request at the origin"
    '((transfer-error body-not-replayable none) 1)
    (on-own-engine make-curl-engine
      (lambda (own)
        (let ((t (curl-submit own (upload-request o 'h2 "/refuse?key=refused-bytes&at=32768" 'post 131072))))
          (send-whole t 131072 65536)
          (curl-token-wait t 30000)
          (let ((r (outcome-of t)))
            (list (if (pair? r) (list (car r) (cadr r) (if (eq? (car r) 'transfer-error) (cadddr r) r)) r)
                  (seen-count o own "refused-bytes")))))))

  (test-equal "the send bit at libcurl's own resend: an HTTP/2 stream refused at its headers while the read is paused, before any byte was handed: libcurl resends, and once the producer puts, 500 ms on, the body arrives whole, a 200, two attempts, two requests at the origin; that the prerequest callable's clear of the send bit is needed no Linux libcurl shows, its resend reading unpaused within 1.165 ms (the plan's section 5.1)"
    '((response 200 http/2) 2 2 whole-body)
    (on-own-engine make-curl-engine
      (lambda (own)
        (let ((t (curl-submit own (upload-request o 'h2 "/refuse?key=refused-head&at=0" 'post 65536))))
          (curl-token-room-wait t 20000)
          (pause-ms 500)
          (put-all t 0 65536 65536 20000)
          (curl-token-end-body! t)
          (curl-token-wait t 30000)
          (list (outcome-of t) (ustat t 'attempts) (seen-count o own "refused-head") (whole (sink-line t) 65536))))))

  ;; --- each callable's guard, by a raise planted at its call
  (test-equal "each request-stream callable's guard: a raise planted at the read callable's first call, at the prerequest callable's first, and, on the reusing seam's engine over a marked connection, at the seek callable's first, is recorded, callback-raised with the planted object, and fails the transfer, of no class; the counts back after"
    (list (list 'callback-raised (planted-upload-fault 'read 1))
          (list 'callback-raised (planted-upload-fault 'prereq 1))
          (list 'callback-raised (planted-upload-fault 'seek 1))
          running-counts)
    (let* ((read (on-own-engine make-curl-engine
            (lambda (own)
              (let ((t (curl-submit own (curl-request-with-upload-fault
                                         (upload-request o 'http (sink-path 'http "fault-read") 'post 1000) 'read 1))))
                (send-whole t 1000 1000)
                (curl-token-wait t 20000)
                (let ((c (curl-token-outcome t)))
                  (if (curl-transfer-error? c) (list (curl-transfer-error-reason c) (curl-transfer-error-recorded c))
                      (outcome-of t)))))))
           (prereq (on-own-engine make-curl-engine
            (lambda (own)
              (let ((t (curl-submit own (curl-request-with-upload-fault
                                         (upload-request o 'http (sink-path 'http "fault-prereq") 'post 1000) 'prereq 1))))
                (send-whole t 1000 1000)
                (curl-token-wait t 20000)
                (let ((c (curl-token-outcome t)))
                  (if (curl-transfer-error? c) (list (curl-transfer-error-reason c) (curl-transfer-error-recorded c))
                      (outcome-of t)))))))
           (seek (on-own-engine make-curl-engine-reusing
            (lambda (own)
              (curl-token-await (curl-submit own (make-curl-request (url-of o 'http "/close-after?then=kill")
                                                                      'proxy #f 'timeout-ms 20000)))
              (let ((t (curl-submit own (curl-request-with-upload-fault
                                         (upload-request o 'http (sink-path 'http "fault-seek") 'post 131072) 'seek 1))))
                (send-whole t 131072 65536)
                (curl-token-wait t 20000)
                (let ((c (curl-token-outcome t)))
                  (if (curl-transfer-error? c) (list (curl-transfer-error-reason c) (curl-transfer-error-recorded c))
                      (outcome-of t))))))))
      (wait-for (lambda () (equal? (native-counts) running-counts)) 10000)
      (list read prereq seek (native-counts))))

  ;; --- an answer while the body is sent, by version (the plan's section
  ;; 3.7; the measurement's item 1). Each cell: whether the transfer ended
  ;; within 1 s with nothing put, own, or waited, and the status it ended
  ;; with, or 28 at the bound, once the producer put the rest. Measured:
  ;; an own end within 9.2 ms, a waiting one 0.6 to 8.3 ms after its first
  ;; put. 8.20.0's HTTP/2 200 then ends 200 or 55, split between runs, and
  ;; so does 8.7.1's, so each cell asserts the wait alone. 8.5.0's HTTP/2 413 waited in every
  ;; native run, but under the memory gate's Valgrind ended on its own in 1
  ;; of 10 cells (build/m6s2b/logs/memlock-1.log), so its kind is either,
  ;; and its status alone held. Apple's 8.7.1's row is the Mac's two runs
  ;; on slice 2's PR, its framings alike in every cell but HTTP/2's 200,
  ;; 200 in the first, 55 sized in the second
  ;; (.plans/research/m6/slice2-build/results/mac-8.7.1-*.log). A
  ;; libcurl with no row fails, naming its version, and showing every cell
  ;; it measured.
  (let ((answer-cases
         '((raw-413-close raw "/raw/answer?status=413&close=1")
           (raw-413-keep raw "/raw/answer?status=413&close=0")
           (raw-200-close raw "/raw/answer?status=200&close=1")
           (raw-200-keep raw "/raw/answer?status=200&close=0")
           (h2-413 h2 "/answer?status=413")
           (h2-200 h2 "/answer?status=200")))
        (answer-rows
         '(("7.85.0" (raw-413-close waits 413) (raw-413-keep waits 413) (raw-200-close waits 200)
                     (raw-200-keep waits 200) (h2-413 waits 413) (h2-200 waits 28))
           ("8.5.0" (raw-413-close own 413) (raw-413-keep waits 413) (raw-200-close own 200)
                    (raw-200-keep waits 200) (h2-413 either 413) (h2-200 own 200))
           ("8.7.1" (raw-413-close own 413) (raw-413-keep waits 413) (raw-200-close own 200)
                    (raw-200-keep waits 200) (h2-413 waits 413) (h2-200 waits))
           ("8.20.0" (raw-413-close own 413) (raw-413-keep own 413) (raw-200-close own 200)
                     (raw-200-keep waits 200) (h2-413 own 413) (h2-200 waits))
           ("8.23.0" (raw-413-close own 413) (raw-413-keep own 413) (raw-200-close own 200)
                     (raw-200-keep waits 200) (h2-413 own 413) (h2-200 waits 200)))))
    (test-equal (string-append "an answer while the body is sent, the read paused, sized and chunked, by version, on "
                                 (if (string? version) version (written version))
                                 ": each cell ends within 1 s on its own, or waits for the producer's put of the rest, and how it ends; once done, a put and room-wait answer done; a libcurl with no row fails, showing every cell it measured")
      (let ((row (and (string? version) (assoc version answer-rows))))
        (if row
            (apply append (map (lambda (cell) (list (cons 'sized cell) (cons 'chunked cell))) (cdr row)))
            (list 'a-row-for version)))
      ;; Every case is measured, with or without a row: (FRAMING NAME KIND
      ;; STATUS), and (after ...) when a put or room-wait once done answered
      ;; other than done. A missing row's failure prints these; fold a case's
      ;; two framings into its row's (NAME KIND STATUS), and give a case whose
      ;; framings disagree on KIND the kind either.
      (let* ((row (and (string? version) (assoc version answer-rows)))
             (measured
              (apply append
                     (map (lambda (spec)
                            (map (lambda (framing)
                                   (on-own-engine make-curl-engine
                                     (lambda (own)
                                       (let* ((n 1000000)
                                              (t (curl-submit own (upload-request o (cadr spec) (caddr spec) 'post
                                                                                  (and (eq? framing 'sized) n)
                                                                                  'timeout-ms 4000)))
                                              (_ (curl-token-room-wait t 2000))
                                              (early (curl-token-wait t 1000)))
                                         (unless early
                                           (put-all t 0 n 16384 500)
                                           (curl-token-end-body! t))
                                         (curl-token-wait t 10000)
                                         (let* ((r (outcome-of t))
                                                (status (cond ((and (pair? r) (eq? (car r) 'response)) (cadr r))
                                                              ((equal? r '(transfer-error perform-failed 28 timeout)) 28)
                                                              (else r)))
                                                (put-after (curl-token-put-piece! t (pattern-piece 0 1) 10))
                                                (room-after (curl-token-room-wait t 10)))
                                           (append (list framing (car spec) (if early 'own 'waits) status)
                                                   (if (equal? (list put-after room-after) '(done done))
                                                       '()
                                                       (list (list 'after put-after room-after)))))))))
                                 '(sized chunked)))
                          answer-cases))))
        (if (not row)
            (list 'no-row-for version 'measured measured)
            ;; Each cell of the row against its measurement; a cell whose
            ;; row names no status, split between runs, is held to its kind,
            ;; and one whose kind is either, to its status.
            (apply append
                   (map (lambda (cell)
                          (map (lambda (framing)
                                 (let ((m (find (lambda (x) (and (pair? x) (eq? (car x) framing) (eq? (cadr x) (car cell))))
                                                measured)))
                                   (cond ((not m) (list framing (car cell) 'unmeasured))
                                         ((null? (cddr cell)) (cons framing (cons (car cell) (cons (caddr m) (cddddr m)))))
                                         ((eq? (cadr cell) 'either)
                                          (cons framing (cons (car cell) (cons 'either (cdddr m)))))
                                         (else m))))
                               '(sized chunked)))
                        (cdr row)))))))

  ;; --- the paced poll on the send side (ADR-0012, amended 2026-10-29)
  (let ((probe-turns
         (lambda (engine mark)
           ;; ENGINE's next 50 turns probed: (POLLS FAST MOVED PACED SLEPT).
           (let ((slept (curl-engine-paced-sleeps engine)))
             (curl-engine-probe-turns! engine 50 mark)
             (let ((p (wait-for (lambda () (let ((p (curl-engine-probe engine))) (and p (= (car p) 0) p)))
                                10000)))
               (if p
                   (append (cdr p) (list (- (curl-engine-paced-sleeps engine) slept)))
                   (list 'unfinished (curl-engine-probe engine)))))))
        (paused-on
         (lambda (engine key)
           ;; An upload on ENGINE, paused for sending, nothing put.
           (let* ((t (curl-submit engine (upload-request o 'http (sink-path 'http key) 'post #f)))
                  (room (curl-token-room-wait t 20000))
                  (paused (wait-for (lambda () (send-paused? t)) 20000)))
             (and (eq? room #t) paused t)))))
    (test-equal "the paced poll's rule, with an upload paused for sending alone, by the probe seam that wakes 50 turns' polls: every fast turn that moved no byte paces; beside a second upload that trickles a byte every 1 ms, the read callable's bytes counted as moved, and no turn that moved them paced; none with a message of the seam's own; none on an engine whose pacing is off; each on an engine of its own"
      '((paused paces) (moving unmoved-alone) (marked none) (unpaced none))
      (list
       (on-own-engine make-curl-engine
         (lambda (engine)
           (let* ((t (paused-on engine "probe-paused")) (r (and t (probe-turns engine #f))))
             (when t (curl-token-cancel t) (curl-token-wait t 10000))
             (list 'paused (if (and (list? r) (= (length r) 5) (> (- (list-ref r 1) (list-ref r 2)) 0)
                                    (= (list-ref r 3) (- (list-ref r 1) (list-ref r 2)))
                                    (>= (list-ref r 4) (list-ref r 3)))
                               'paces (list (and t #t) r))))))
       (on-own-engine make-curl-engine
         (lambda (engine)
           (let* ((t (paused-on engine "probe-moving"))
                  (trickle (curl-submit engine (upload-request o 'http (sink-path 'http "probe-trickle") 'post #f)))
                  (mx (make-mutex)) (stop #f) (done #f))
             (curl-token-room-wait trickle 20000)
             (fork-thread (lambda ()
                            (let loop ((at 0))
                              (unless (with-mutex mx stop)
                                (curl-token-put-piece! trickle (pattern-piece at 1) 1000)
                                (pause-ms 1)
                                (loop (+ at 1))))
                            (with-mutex mx (set! done #t))))
             (let* ((flowing (wait-for (lambda () (> (ustat trickle 'handed) 0)) 20000))
                    (r (and t flowing (probe-turns engine #f))))
               (with-mutex mx (set! stop #t))
               (wait-for (lambda () (with-mutex mx done)) 10000)
               (curl-token-cancel trickle)
               (curl-token-wait trickle 10000)
               (when t (curl-token-cancel t) (curl-token-wait t 10000))
               ;; Each byte the trickle's read callable moves follows the
               ;; resume its put queued, so a turn that moved one took a
               ;; message too, and paces by neither rule.
               (list 'moving (if (and (list? r) (= (length r) 5) (> (list-ref r 2) 0)
                                      (<= (list-ref r 3) (- (list-ref r 1) (list-ref r 2))))
                                 'unmoved-alone (list (and t #t) flowing r)))))))
       (on-own-engine make-curl-engine
         (lambda (engine)
           (let* ((t (paused-on engine "probe-marked")) (r (and t (probe-turns engine #t))))
             (when t (curl-token-cancel t) (curl-token-wait t 10000))
             (list 'marked (if (and (list? r) (= (length r) 5) (> (list-ref r 1) 0) (= (list-ref r 3) 0))
                               'none (list (and t #t) r))))))
       (on-own-engine make-curl-engine-unpaced
         (lambda (engine)
           (let* ((t (paused-on engine "probe-unpaced")) (r (and t (probe-turns engine #f))))
             (when t (curl-token-cancel t) (curl-token-wait t 10000))
             (list 'unpaced (if (and (list? r) (= (length r) 5) (> (list-ref r 1) 0) (= (list-ref r 3) 0))
                                'none (list (and t #t) r)))))))))

  ;; The send side's CPU: 7.85.0's poll spins through a paused HTTP/2
  ;; upload once DATA has gone, in 8 runs of 10 with pacing off, measured on
  ;; the floor lane through the engine (build/m6s2b/control/), so no
  ;; pacing-off control can rely on it; the probe seam above holds the
  ;; rule on every libcurl.
  (test-equal "the paced poll: the process's CPU through a 2 s pause of an HTTP/2 upload, 4,096 bytes sent first, then the send paused throughout, nothing put, is under 500 ms on every libcurl, 7.85.0 too, whose poll spins there; then the rest, put, arrives whole"
    '(#t #t under-500-ms whole-body)
    (on-own-engine make-curl-engine
      (lambda (own)
        (let* ((t (curl-submit own (upload-request o 'h2 (sink-path 'h2 "cpu") 'post 8192)))
               (room (curl-token-room-wait t 20000))
               (first (curl-token-put-piece! t (pattern-piece 0 4096) 20000))
               (paused (wait-for (lambda () (and (= (ustat t 'handed) 4096) (send-paused? t))) 20000))
               (resumes (ustat t 'resumes)))
          (collect-rendezvous)
          (let* ((c0 (cpu-ms)) (_ (pause-ms 2000)) (c1 (cpu-ms)) (still (= resumes (ustat t 'resumes))))
            (put-all t 4096 8192 4096 20000)
            (curl-token-end-body! t)
            (curl-token-wait t 20000)
            (list (and (eq? room #t) (eq? first #t) paused #t) still
                  (if (< (- c1 c0) 500) 'under-500-ms (- c1 c0))
                  (whole (sink-line t) 8192)))))))

  ;; --- throughput: 64 MiB in 64 KiB puts, within 60 s, the bound the
  ;; memory gate's Valgrind needs; the plan measured up to 1,998.56 ms
  ;; natively and 6,501.68 ms under Valgrind (section 5.1, as measured).
  ;; Each run's time goes to stdout.
  (for-each
   (lambda (face)
     (test-equal (string-append (symbol->string face) ": 64 MiB in 64 KiB puts, sized and chunked, whole by its hash at the origin, each within 60 s")
       '((sized whole-body within-60-s) (chunked whole-body within-60-s))
       (map (lambda (framing)
              (guard (e (#t (list 'raised (describe e))))
                (let* ((n 67108864)
                       (t0 (now-ms))
                       (t (curl-submit engine (upload-request o face (sink-path face (string-append "throughput-" (symbol->string face)))
                                                              'post (and (eq? framing 'sized) n))))
                       (sent (send-whole t n 65536))
                       (_ (curl-token-wait t 60000))
                       (took (- (now-ms) t0)))
                  (display (list 'throughput face framing 'ms took)) (newline)
                  (list framing (whole (sink-line t) n) (if (< took 60000) 'within-60-s took)))))
            '(sized chunked))))
   '(http https h2))

  ;; --- the thread rule (the plan's section 3.8; ADR-0012, decision 4)
  (test-equal "the thread rule: every put runs on this thread, the producer's, never the engine's, and so does the mailbox's callback; the read callable's log gives each verdict's threads, the engine's alone, on an engine of its own"
    (list 'puts-here 'callback-here 'reads-engine-alone 'whole-body)
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((engine-thread (curl-engine-thread engine))
               (mailbox (make-curl-mailbox))
               (seen '())
               (note! (lambda (where) (set! seen (cons (cons where (get-thread-id)) seen))))
               (t (curl-submit engine (upload-request o 'http (sink-path 'http "threads") 'post #f) mailbox
                               (lambda (token) (note! 'callback)))))
          (curl-token-room-wait t 20000)
          (let loop ((at 0))
            (when (< at 1048576)
              (curl-token-put-piece! t (pattern-piece at 16384) 20000)
              (note! 'put)
              (loop (+ at 16384))))
          (curl-token-end-body! t)
          (curl-mailbox-deliver mailbox 20000)
          (let ((reads (ustat t 'reads)))
            (list (if (and (assq 'put seen) (not (eqv? main-thread engine-thread))
                           (for-all (lambda (s) (eqv? (cdr s) main-thread))
                                    (filter (lambda (s) (eq? (car s) 'put)) seen)))
                      'puts-here seen)
                  (if (equal? (filter (lambda (s) (eq? (car s) 'callback)) seen) (list (cons 'callback main-thread)))
                      'callback-here (filter (lambda (s) (eq? (car s) 'callback)) seen))
                  (if (and (pair? reads) (assq 'gave reads)
                           (for-all (lambda (entry) (and (memq (car entry) upload-verdicts)
                                                         (equal? (caddr entry) (list engine-thread))))
                                    reads))
                      'reads-engine-alone reads)
                  (whole (sink-line t) 1048576)))))))

  ;; --- the read callable's lock: puts beside a thread that collects every
  ;; 2 ms, each piece 2 ms after the last, so the engine's thread waits in
  ;; its __collect_safe poll between the read callable's calls, and the
  ;; collector runs there. Without lock-object a collection moves the
  ;; callable's code, and libcurl calls where it was (the M2 plan, section
  ;; 5.1.1).
  (test-equal "the read callable's lock: 1,000 pieces of 20 bytes, 2 ms apart, beside a thread that collects every 2 ms: the body whole, ten collections or more while the transfer was live"
    '(whole-body collected-while-live)
    (on-own-engine make-curl-engine
      (lambda (engine)
        (let* ((mx (make-mutex)) (stop #f) (while-live 0) (done #f)
               (t (curl-submit engine (upload-request o 'http (sink-path 'http "lock") 'post 20000))))
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
          (curl-token-room-wait t 20000)
          (let loop ((at 0))
            (when (< at 20000)
              (curl-token-put-piece! t (pattern-piece at 20) 20000)
              (pause-ms 2)
              (loop (+ at 20))))
          (curl-token-end-body! t)
          (curl-token-wait t 20000)
          (with-mutex mx (set! stop #t))
          (wait-for (lambda () (with-mutex mx done)) 10000)
          ;; The lock test's evidence, on stdout: its collections while live.
          (display (list 'read-lock 'collections-while-live (with-mutex mx while-live))) (newline)
          (list (whole (sink-line t) 20000)
                (if (>= while-live 10) 'collected-while-live (list 'collections-while-live while-live)))))))

  ;; --- both ways, cancel, and the engine's failure
  (for-each
   (lambda (face)
     (test-equal (string-append (symbol->string face) ": a request that streams both ways: 1 MiB put, then its response read as pieces, a stream-buffer of 1,024 bytes: the sink line whole, the body whole, the head the 200's")
       '(200 whole-body (response 200))
       (on-engine-for face
         (lambda (engine)
           (let* ((t (curl-submit engine (upload-request o face (sink-path face (string-append "both-" (symbol->string face)))
                                                         'post 1048576 'stream-buffer 1024)))
                  (sent (send-whole t 1048576 65536))
                  (text (let loop ((found '()))
                          (let ((p (curl-token-next-piece t 20000)))
                            (if (bytevector? p) (loop (append found (bytevector->u8-list p))) found))))
                  (head (curl-token-head t)))
             (list (and head (curl-head-status head))
                   (whole (parse-sink (list->string (map integer->char text))) 1048576)
                   (let ((r (outcome-of t))) (if (pair? r) (list-head r 2) r))))))))
   '(http h2))

  (test-equal "a cancel while the send is paused ends the token cancelled, its transfer taken out; then a put answers done, the end does nothing, and the count stays 1,000"
    '(paused (transfer-error cancelled #f none) done 1000)
    (on-own-engine make-curl-engine
      (lambda (own)
        (let* ((t (curl-submit own (upload-request o 'http (sink-path 'http "cancel") 'post #f)))
               (_ (curl-token-room-wait t 20000))
               (_p (curl-token-put-piece! t (pattern-piece 0 1000) 20000))
               (paused (wait-for (lambda () (and (= (ustat t 'handed) 1000) (send-paused? t))) 20000)))
          (curl-token-cancel t)
          (curl-token-wait t 10000)
          (let ((after (curl-token-put-piece! t (pattern-piece 1000 10) 10)))
            (curl-token-end-body! t)
            (list (if paused 'paused (curl-token-upload-stats t)) (outcome-of t) after
                  (curl-token-body-count t)))))))

  (test-equal "the engine's failure while the send is paused, a fault planted at the resume step, which a put queued: the token ends with &curl-engine-error, failed, carrying the fault; a later put answers done; the counts back to the suite's engine's"
    (list 'paused (list 'engine-error 'failed (planted-engine-fault 'resume)) 'done running-counts)
    (on-own-engine (lambda () (make-faulty-curl-engine 'resume))
      (lambda (own)
        (let* ((t (curl-submit own (upload-request o 'http (sink-path 'http "fault-resume") 'post #f)))
               (_ (curl-token-room-wait t 20000))
               (paused (wait-for (lambda () (send-paused? t)) 20000))
               (_p (curl-token-put-piece! t (pattern-piece 0 10) 20000))
               (done (curl-token-wait t 10000))
               (after (curl-token-put-piece! t (pattern-piece 10 10) 10)))
          (stop-bounded own)
          (list (if (and paused done) 'paused (list paused done)) (outcome-of t) after (native-counts))))))

  (test-equal "the suite's engine holds nothing once the scenarios end: its multi handle and slot alone"
    running-counts
    (begin (wait-for (lambda () (equal? (native-counts) running-counts)) 10000)
           (native-counts))))

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
  (let* ((stopped (if (curl-engine? engine) (stop-bounded engine) engine)))
    (list stopped (native-counts))))

(test-end "upload")

(exit (suite-exit-status runner))
