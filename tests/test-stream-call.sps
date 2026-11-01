#!r6rs
;;; The suite for the high level's streams (ADR-0031, amended 2026-10-31;
;;; ADR-0032, amended; the M6 plan, sections 3.6 and 6.2):
;;; call-with-response-port, a producer as a call's body with body-length,
;;; the head's step, hops cancelled at their heads or read whole, at most
;;; once, next-request's stream keys, stream-in-group, the bound across
;;; PROC's reading, libcurl's HTTP/2 3xx that never ends, and the thread
;;; rule. Each check was watched failing, on a mutant or before its code
;;; (build/m6s3b/mutants.md).
;;;
;;;   - with no origin: call-with-response-port's refusals; a head's
;;;     response refused by http-response-text; stream-in-group, by go and
;;;     by http-parallel, before anything is submitted; the head's
;;;     predicate against exchange-step on every row of a table of steps,
;;;     with the same clocks and draw; at most once and next-request's
;;;     stream keys, by tables; exchange-raised; and a retry that leaves no
;;;     time, through drive-stream itself;
;;;   - against the origin: PROC handed the final head and the port, its
;;;     values answered, over every face; a hop read whole when its request
;;;     sends no body, and cancelled at its head when it sends one, a
;;;     redirect's and a retry's; a failure while a hop's body is read,
;;;     stepped with its own clocks; a retry's wait measured from its
;;;     head; a retry whose wait would pass the bound, decided once; every
;;;     method through every redirect a producer's body meets; the port
;;;     closed and its transfer cancelled when PROC returns and when it
;;;     escapes; the bound across PROC's reading; a producer's pieces, its
;;;     first call only once libcurl asks, never after its end, asked for
;;;     its end at once once the length is taken, a body short and long,
;;;     its raise, its bad answer and its read of its own port, each sticky
;;;     inside the port's read; drive-last-token's record, let go as its
;;;     call ends; a full-duplex server, an early 413 and an early 303;
;;;     the drive's two sides; no retry of a
;;;     producer called, and a refused connect's retry; libcurl's HTTP/2
;;;     3xx, by version; a head before libcurl's first ask, on the engine
;;;     that holds its prerequest callable, by version; and the thread
;;;     rule.
;;;
;;; Every check on a raw face makes its own session: the raw scripts close
;;; after each answer without saying so (ADR-0020). A suite cannot tell
;;; whether it runs under the memory gate's Valgrind, so every bound holds
;;; there too (the M6 plan, section 6.1, as measured: a call that ended on
;;; its own took 5,797 ms at most under Valgrind). Where libcurl's answer
;;; varies by version, a row holds it, and a libcurl with no row fails,
;;; printing what it measured. Every expected value is one the code under
;;; test cannot produce by failing: SRFI-64 makes #f of a raise in the
;;; actual expression, so none is #f.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) sleep make-time current-time time-second time-nanosecond getenv
              get-thread-id port-closed? collect-rendezvous parameterize iota fork-thread
              make-mutex with-mutex critical-section library-directories list-head
              collect collect-maximum-generation collect-request-handler bytes-allocated)
        (curl-testing)
        (curl)
        (http-client)
        (only (http-client private call) new-http-session session-defaults http-session-engine
              http-session-draw)
        (only (http-client private exchange) make-exchange exchange-step exchange-steps-past?
              exchange-mark-called exchange-called? exchange-raised exchange-submission
              exchange-request make-http-response)
        (only (http-client private drive) drive-stream drive-stream-waits monotonic-ns
              drive-last-token drive-last-token-arm!)
        (only (curl private engine) make-curl-engine-holding-prereq curl-engine-prereq-holds
              curl-engine-thread curl-engine-live-count curl-token-body-count)
        (only (curl private conditions) make-classed-transfer-error)
        (only (curl private transfer) transfers-started)
        (curl private counters))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; written : Any -> String
(define (written x) (call-with-string-output-port (lambda (p) (write x p))))

;; shown : Any -> String
;; X written, cut to 3000 characters.
(define (shown x)
  (let ((text (written x)))
    (if (> (string-length text) 3000) (string-append (substring text 0 3000) "...") text)))

;; The simple runner names a failing test but not its values. Print both,
;; and flush each verdict: a suite killed at its bound never flushes.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (display "  expected: ")
        (display (shown (test-result-ref r 'expected-value)))
        (newline)
        (display "  actual:   ")
        (display (shown (test-result-ref r 'actual-value)))
        (newline))
      (flush-output-port (current-output-port)))))

(test-begin "stream-call")

;; --- helpers --------------------------------------------------------------------------

(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0)))

;; version : (U String List)
;; The loaded libcurl's version, read on this thread before any is forked.
(define version
  (guard (e (#t (list 'no-version (describe e))))
    (libcurl-info-version (loaded-libcurl))))

;; version-text : String
(define version-text (if (string? version) version (written version)))

;; main-thread : Integer
(define main-thread (get-thread-id))

;; now-ms : -> Integer
(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

;; cpu-ms : -> Real
;; This process's CPU time, every thread's, in ms.
(define (cpu-ms)
  (let ((t (current-time 'time-process)))
    (+ (* (time-second t) 1000) (/ (time-nanosecond t) 1000000))))

;; pause-ms : Natural -> Unit
(define (pause-ms ms)
  (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))

;; wait-for : (-> Any) Natural -> Any
;; THUNK's first true answer, read every 1 ms, or #f after MS ms.
(define (wait-for thunk ms)
  (let ((deadline (+ (now-ms) ms)))
    (let loop ()
      (or (thunk)
          (and (< (now-ms) deadline)
               (begin (pause-ms 1) (loop)))))))

;; latin-1 : Bytevector -> String
(define (latin-1 bytes)
  (list->string (map integer->char (bytevector->u8-list bytes))))

;; bytes-of : String -> Bytevector
;; S, chars below U+0100, a byte each.
(define (bytes-of s)
  (u8-list->bytevector (map char->integer (string->list s))))

;; make-list-of : Natural Any -> (Listof Any)
(define (make-list-of n x) (if (= n 0) '() (cons x (make-list-of (- n 1) x))))

;; in-order : (Any -> Any) (Listof Any) -> (Listof Any)
;; PROC of each of ITEMS, first to last: map calls its procedure in no
;; fixed order (traps.md).
(define (in-order proc items)
  (let loop ((rest items) (answers '()))
    (if (null? rest)
        (reverse answers)
        (let ((answer (proc (car rest))))
          (loop (cdr rest) (cons answer answers))))))

;; pct : String -> String
;; S, chars below U+0100, each kept when an ASCII letter or digit, -, ., _
;; or ~, else %XX in upper case: a query value the origin decodes back.
(define (pct s)
  (apply string-append
         (map (lambda (ch)
                (let ((b (char->integer ch)))
                  (if (or (<= 48 b 57) (<= 65 b 90) (<= 97 b 122) (memv b '(45 46 95 126)))
                      (string ch)
                      (string #\% (string-ref "0123456789ABCDEF" (div b 16))
                              (string-ref "0123456789ABCDEF" (mod b 16))))))
              (string->list s))))

;; class-of : Condition -> Symbol
(define (class-of e)
  (cond ((curl-timeout? e) 'timeout) ((curl-connect-error? e) 'connect)
        ((curl-send-receive-error? e) 'send-receive) ((curl-tls-error? e) 'tls)
        ((curl-protocol-error? e) 'protocol) ((curl-too-large? e) 'too-large)
        (else 'none)))

;; summary : Response -> (List Integer Any Any Any)
;; A response's status, whether its body and timings are #f or what, and
;; its history, summarised.
(define (summary r)
  (if (http-response? r)
      (list (http-response-status r)
            (let ((b (http-response-body r))) (if (bytevector? b) (latin-1 b) b))
            (let ((t (http-response-timings r))) (if (list? t) (map car t) t))
            (map summary (http-response-history r)))
      (list 'not-a-response r)))

;; described : Any -> (Listof Any)
;; What a raised object is, whole: for a condition, each of these it is, in
;; this order, with its fields; for anything else, (non-condition X).
(define (described e)
  (if (condition? e)
      (filter
       (lambda (x) x)
       (list (and (http-error? e) '(http-error))
             (and (http-request-error? e)
                  (list 'http-request-error (http-request-error-field e) (http-request-error-value e)
                        (http-request-error-reason e)))
             (and (http-redirect-error? e)
                  (list 'http-redirect-error (http-redirect-error-reason e)
                        (http-redirect-error-location e) (summary (http-redirect-error-response e))))
             (and (http-timeout? e) (list 'http-timeout (http-timeout-timeout-ms e)))
             (and (curl-request-error? e)
                  (list 'curl-request-error (curl-request-error-field e) (curl-request-error-value e)
                        (curl-request-error-reason e)))
             (and (curl-engine-error? e) (list 'curl-engine-error (curl-engine-error-reason e)))
             (and (curl-transfer-error? e)
                  (list 'curl-transfer-error (class-of e) (curl-transfer-error-reason e)
                        (curl-transfer-error-code e)))
             (and (assertion-violation? e)
                  (list 'assertion (and (who-condition? e) (condition-who e))))
             (and (http-exchange? e)
                  (list 'exchange (http-exchange-method e) (http-exchange-url e)
                        (map summary (http-exchange-history e)) (http-exchange-transfers e)))))
      (list 'non-condition e)))

;; outcome : (-> Any) -> (Pairof Symbol Any)
;; (returned VALUE), or (raised . DESCRIBED).
(define (outcome thunk)
  (guard (e (#t (cons 'raised (described e))))
    (list 'returned (thunk))))

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
;; written here, computed outside the suite (tests/test-upload.sps holds the
;; same), never by the origin.
(define pattern-sha256
  '((2000 . "63d8d35920be456776a35578ade76725c687821ad55d4bb950225fed2d33e6cb")
    (65536 . "4b640d85ab3ba30fd02c9fc9db4a8928f416322ad27022ea58a65aaee68a4df2")
    (262144 . "31a1f9dea0169551092d05e8bf4a446228c8c3eb4c9b713c66adcb7fd53c89be")
    (1048576 . "631b84027d6b9e52b539c4e8373622d23032dfadc64d60af87339c9037e4f769")))

;; sha-of : Natural -> String
(define (sha-of n) (cdr (assv n pattern-sha256)))

;; first-bad : Bytevector Natural -> (U Natural #f)
;; The first offset of BYTES, read as the pattern from AT, that is not the
;; pattern's byte, or #f.
(define (first-bad bytes at)
  (let ((n (bytevector-length bytes)))
    (let loop ((i 0) (v (mod at 251)))
      (cond ((= i n) #f)
            ((not (= (bytevector-u8-ref bytes i) v)) (+ at i))
            (else (loop (+ i 1) (if (= v 250) 0 (+ v 1))))))))

;; drain : Binary-Input-Port -> (List Symbol Natural Any)
;; PORT read to its end by get-bytevector-some, each piece checked against
;; the pattern: (end N BAD), BAD the first offset that is not the
;; pattern's, or #f; or (raised N . DESCRIBED) once a read raises.
(define (drain port)
  (let loop ((n 0) (bad #f))
    (let ((got (guard (e (#t (cons 'raised (described e)))) (get-bytevector-some port))))
      (cond ((eof-object? got) (list 'end n bad))
            ((and (pair? got) (eq? (car got) 'raised)) (cons 'raised (cons n (cdr got))))
            (else (loop (+ n (bytevector-length got)) (or bad (first-bad got n))))))))

;; text-of : Binary-Input-Port -> (List Symbol Any)
;; PORT read to its end: (text STRING), its bytes as Latin-1; or (raised
;; TEXT-SO-FAR . DESCRIBED).
(define (text-of port)
  (let loop ((pieces '()))
    (let ((got (guard (e (#t (cons 'raised (described e)))) (get-bytevector-some port))))
      (cond ((eof-object? got) (list 'text (apply string-append (reverse pieces))))
            ((and (pair? got) (eq? (car got) 'raised))
             (cons 'raised (cons (apply string-append (reverse pieces)) (cdr got))))
            (else (loop (cons (latin-1 got) pieces)))))))

;; words : String -> (Listof String)
(define (words text)
  (let loop ((cs (string->list text)) (cur '()) (found '()))
    (cond ((null? cs) (reverse (if (null? cur) found (cons (list->string (reverse cur)) found))))
          ((memv (car cs) '(#\space #\newline))
           (loop (cdr cs) '() (if (null? cur) found (cons (list->string (reverse cur)) found))))
          (else (loop (cdr cs) (cons (car cs) cur) found)))))

;; sink-fields : String -> (U (Listof (Pairof Symbol String)) List)
;; The origin's sink line as fields: (face . FACE), then each NAME=VALUE;
;; (unread TEXT) for any other text.
(define (sink-fields text)
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

;; field : Any Symbol -> Any
(define (field line name)
  (let ((f (and (list? line) (for-all pair? line) (assq name line))))
    (if f (cdr f) (list 'no-field name line))))

;; whole : Any Natural -> Any
;; whole-body when the sink LINE says the body arrived as N bytes of the
;; pattern, its SHA-256 the pattern's; else what it says.
(define (whole line n)
  (if (and (equal? (field line 'bytes) (number->string n))
           (equal? (field line 'pattern) "ok")
           (equal? (field line 'sha256) (sha-of n)))
      'whole-body
      (list 'not-whole n line)))

;; A producer: the pattern's TOTAL bytes in pieces of PIECE, then the eof
;; object, with its record: its calls, the bytes it gave, its calls after
;; the eof object, the threads it ran on, and when it was first called, in
;; ms after it was made. FAULT, when given, is called with the call's
;; number, from 1, and its answer, if not #f, answered in place of the
;; piece: a test plants a raise or a bad answer so.
(define-record-type producer
  (fields (immutable total) (immutable piece) (immutable made) (immutable fault)
          (mutable calls) (mutable given) (mutable after-eof) (mutable threads) (mutable first-at)
          (mutable ended)))

;; new-producer : Natural Natural [(Natural -> Any)] -> Producer
(define (new-producer total piece . fault)
  (make-producer total piece (now-ms) (and (pair? fault) (car fault)) 0 0 0 '() #f #f))

;; thunk-of : Producer -> ( -> (U Bytevector Eof Any))
;; P's producer, as a call's body takes it.
(define (thunk-of p)
  (lambda ()
    (producer-calls-set! p (+ 1 (producer-calls p)))
    (unless (memv (get-thread-id) (producer-threads p))
      (producer-threads-set! p (cons (get-thread-id) (producer-threads p))))
    (unless (producer-first-at p) (producer-first-at-set! p (- (now-ms) (producer-made p))))
    (let ((planted (and (producer-fault p) ((producer-fault p) (producer-calls p)))))
      (cond
        (planted planted)
        ((producer-ended p) (producer-after-eof-set! p (+ 1 (producer-after-eof p))) (eof-object))
        ((>= (producer-given p) (producer-total p)) (producer-ended-set! p #t) (eof-object))
        (else
         (let* ((at (producer-given p)) (n (min (producer-piece p) (- (producer-total p) at))))
           (producer-given-set! p (+ at n))
           (pattern-piece at n)))))))

;; with-session : (Listof Any) (Session -> Any) -> Any
;; PROC's answer, on a session of its own made from PLIST, closed after.
(define (with-session plist proc)
  (let ((session (apply make-http-session plist)))
    (dynamic-wind
      (lambda () #f)
      (lambda () (proc session))
      (lambda () (http-session-close session)))))

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
;; GNU timeout (gtimeout on macOS), killed with SIGKILL after 120 s, exit
;; 137. The shell's own stderr is /dev/null, so dash's "Killed" is not the
;; command's (traps.md).
(define child-script
  (string-append
   "t=$(command -v timeout || command -v gtimeout) || { echo 'stream-call child: no timeout' >&2; exit 125; }\n"
   "exec 3>&2 2>/dev/null\n"
   "( exec \"$t\" -s KILL 120 \"$@\" </dev/null 2>&3 3>&- )\n"
   "exit $?\n"))

;; run-child : String . (Listof String) -> (List Integer (Listof Any) String)
;; tests/PROGRAM with ARGS in a child Chez, under child-script: its exit
;; status, what it printed, read as data, and its stderr.
(define (run-child program . args)
  (guard (e (#t (list 'raised (describe e) "")))
    (let ((r (capture-command (append (list "sh" "-c" child-script "sh" (getenv "CHEZ") "--libdirs" (library-path)
                                            "--program" program)
                                      args))))
      (list (car r) (read-all (cadr r)) (caddr r)))))

;; The run's PKI, for the TLS faces.
(define pki-made
  (guard (e (#t (list 'raised (describe e))))
    (list 'made (make-test-pki))))
(define pki (and (eq? (car pki-made) 'made) (cadr pki-made)))
(define ca (and pki (string-append pki "/ca.pem")))

;; base-keys : (Listof Any)
;; Every session's here: direct, the run's CA file, a 60 s bound.
(define base-keys (list 'proxy #f 'ca-file ca 'timeout-ms 60000))

;; with-held-session : (Session -> Any) -> Any
;; PROC's answer, on a session of its own whose engine holds a streamed
;; body's prerequest callable 200 ms once connected, before the request is
;; sent, made by (http-client private call)'s new-http-session, as the
;; slice's measurement holds it (research/m6/slice3/): an answer written as
;; the connection is accepted is then read before libcurl's first ask.
(define (with-held-session proc)
  (let ((s (new-http-session (make-curl-engine-holding-prereq 200)
                             (session-defaults (list (cons 'proxy #f) (cons 'ca-file ca)
                                                     (cons 'timeout-ms 20000)))
                             20 #f #f)))
    (dynamic-wind
      (lambda () #f)
      (lambda () (proc s))
      (lambda () (http-session-close s)))))

;; url-of : Origin Symbol String -> String
(define (url-of o face path)
  (let ((f (origin-face o face)))
    (string-append (if (memq face '(https h2 raw-tls)) "https://" "http://")
                   (car f) ":" (number->string (cdr f)) path)))

;; head-of : Response -> (List Integer Any String Any Any (Listof Any))
;; What call-with-response-port hands PROC, whole enough to compare: the
;; status, the version, the URL, the body, the timings and the history.
(define (head-of r)
  (if (http-response? r)
      (list (http-response-status r) (http-response-http-version r) (http-response-url r)
            (http-response-body r) (http-response-timings r) (map summary (http-response-history r)))
      (list 'not-a-response r)))

;; retained-bytes : -> Natural
;; The bytes Chez's heap holds once two collections of every generation
;; have run, each at a rendezvous of every thread: collect alone raises
;; while another thread is active (traps.md).
(define (retained-bytes)
  (parameterize ((collect-request-handler (lambda () (collect (collect-maximum-generation)))))
    (collect-rendezvous)
    (collect-rendezvous))
  (bytes-allocated))

;; live-ends : Session -> Any
;; ended once SESSION's engine holds no live transfer, within 5 s.
(define (live-ends s)
  (if (wait-for (lambda () (= 0 (curl-engine-live-count (http-session-engine s)))) 5000)
      'ended
      (list 'still-live (curl-engine-live-count (http-session-engine s)))))

;; --- with no origin ---------------------------------------------------------------------

(define nowhere "http://127.0.0.1:1/")

(test-equal "the PKI is this run's"
  'made
  (car pki-made))

(test-equal "call-with-response-port refuses its arguments before anything: no procedure, and a last argument that is no procedure, each an assertion violation from call-with-response-port; a stream-buffer of #f, the same; 0, the low level's assertion violation; an unknown key, a producer with get, and body-length beside a bytevector, each the refusal that names it; all but the arguments' shape compounded with &http-exchange; no transfer started"
  (list '(raised (assertion call-with-response-port))
        '(raised (assertion call-with-response-port))
        (list 'raised '(assertion call-with-response-port) (list 'exchange 'get nowhere '() 0))
        (list 'raised '(assertion make-curl-request) (list 'exchange 'get nowhere '() 0))
        (list 'raised '(http-error) '(http-request-error key limit unknown-key) (list 'exchange 'get nowhere '() 0))
        (list 'raised '(http-error) '(http-request-error body get body-not-allowed) (list 'exchange 'get nowhere '() 0))
        (list 'raised '(curl-request-error body-length 3 body-length-without-stream) (list 'exchange 'post nowhere '() 0))
        0)
  (guard (e (#t (list 'raised (describe e))))
    (with-session base-keys
      (lambda (s)
        (let* ((started (transfers-started))
               (proc (lambda (r p) 'called))
               (refusals
                (in-order (lambda (thunk) (outcome thunk))
                          (list (lambda () (call-with-response-port s 'get nowhere))
                                (lambda () (call-with-response-port s 'get nowhere 'timeout-ms 100))
                                (lambda () (call-with-response-port s 'get nowhere 'stream-buffer #f proc))
                                (lambda () (call-with-response-port s 'get nowhere 'stream-buffer 0 proc))
                                (lambda () (call-with-response-port s 'get nowhere 'limit 1 proc))
                                (lambda () (call-with-response-port s 'get nowhere 'body (lambda () (eof-object)) proc))
                                (lambda () (call-with-response-port s 'post nowhere 'body #vu8(1 2 3) 'body-length 3
                                                                    proc))))))
          (append refusals (list (- (transfers-started) started))))))))

(test-equal "http-request takes body-length and a producer as its body, and refuses body-length beside a bytevector and a string, (curl)'s body-length-without-stream, and a stream-buffer, which is call-with-response-port's alone, by name; no transfer started"
  (list (list 'raised '(curl-request-error body-length 2 body-length-without-stream) (list 'exchange 'post nowhere '() 0))
        (list 'raised '(curl-request-error body-length 2 body-length-without-stream) (list 'exchange 'put nowhere '() 0))
        (list 'raised '(http-error) '(http-request-error key stream-buffer unknown-key) (list 'exchange 'post nowhere '() 0))
        0)
  (guard (e (#t (list 'raised (describe e))))
    (with-session base-keys
      (lambda (s)
        (let* ((started (transfers-started))
               (refusals
                (in-order (lambda (thunk) (outcome thunk))
                          (list (lambda () (http-post s nowhere 'body #vu8(1 2) 'body-length 2))
                                (lambda () (http-put s nowhere 'body "ab" 'body-length 2))
                                (lambda () (http-post s nowhere 'body (lambda () (eof-object)) 'stream-buffer 10))))))
          (append refusals (list (- (transfers-started) started))))))))

(test-equal "http-response-text refuses a response whose body is #f, a head's, an assertion violation from http-response-text; the body and timings #f read back as #f"
  '((raised (assertion http-response-text)) #f #f)
  (let ((r (make-http-response 200 'http/1.1 "http://h.example/" '() #f #f '())))
    (list (outcome (lambda () (http-response-text r))) (http-response-body r) (http-response-timings r))))

(test-equal "stream-in-group: go with a producer as its body raises &http-request-error, stream-in-group, its field body, its value the producer, compounded with &http-exchange, from go, before anything is submitted; the producer never called; a go after it runs, its one transfer refused at the connect"
  (list (list 'raised '(http-error) (list 'http-request-error 'body 'the-producer 'stream-in-group)
              (list 'exchange 'post nowhere '() 0))
        0 1 (list 'raised '(curl-transfer-error connect perform-failed 7) (list 'exchange 'get nowhere '() 1)))
  (guard (e (#t (list 'raised (describe e))))
    (with-session base-keys
      (lambda (s)
        (let* ((p (new-producer 10 10))
               (thunk (thunk-of p))
               (started (transfers-started))
               (seen (call-with-request-group s
                       (lambda (go)
                         (let* ((refused (outcome (lambda () (go 'post nowhere 'body thunk))))
                                (later (outcome (lambda () (http-await (go 'get nowhere 'timeout-ms 2000))))))
                           (list refused later))))))
          (list (let ((r (car seen)))
                  (if (and (eq? (car r) 'raised) (equal? (caddr r) (list 'http-request-error 'body thunk 'stream-in-group)))
                      (list 'raised (cadr r) (list 'http-request-error 'body 'the-producer 'stream-in-group) (cadddr r))
                      r))
                (producer-calls p)
                (- (transfers-started) started)
                (cadr seen)))))))

(test-equal "stream-in-group: http-parallel with a producer in its third spec raises it, its value the producer, before any spec is submitted: no transfer started, the producer never called"
  (list (list 'raised '(http-error) '(http-request-error body the-producer stream-in-group)
              (list 'exchange 'put nowhere '() 0))
        0 0)
  (guard (e (#t (list 'raised (describe e))))
    (with-session base-keys
      (lambda (s)
        (let* ((p (new-producer 10 10))
               (thunk (thunk-of p))
               (started (transfers-started))
               (r (outcome (lambda () (http-parallel s (list (list 'get nowhere) (list 'post nowhere 'body #vu8(1))
                                                             (list 'put nowhere 'body thunk 'body-length 10)))))))
          (list (if (and (eq? (car r) 'raised) (equal? (caddr r) (list 'http-request-error 'body thunk 'stream-in-group)))
                    (list 'raised (cadr r) '(http-request-error body the-producer stream-in-group) (cadddr r))
                    r)
                (- (transfers-started) started)
                (producer-calls p)))))))

;; --- the head's step, by tables --------------------------------------------------------

;; Every table's call starts at table-start, a time no clock gives, bounded
;; by 5000 ms; its head comes 1 ms in, at UTC 1800000000, with a draw of
;; 0.5.
(define table-start 7000000000123)
(define table-now (+ table-start 1000000))
(define table-utc 1800000000)

;; table-request : Symbol (U Bytevector 'stream #f) (U Natural #f) -> Request
(define (table-request method body length)
  (make-curl-request "http://given.example/a" 'method method 'body body 'body-length length
                     'stream-buffer 4096 'timeout-ms 5000 'connect-timeout-ms 700 'proxy #f))

;; table-state : Symbol (U Bytevector 'stream #f) Boolean (U Retry #f) [(U Natural #f)] -> State
;; A call of METHOD with BODY, its producer counted as called when CALLED,
;; with POLICY, following REDIRECTS, 20 unless given.
(define (table-state method body called policy . redirects)
  (let ((s (make-exchange method "http://given.example/a"
                          (table-request method body (and (eq? body 'stream) 100))
                          5000 table-start (if (pair? redirects) (car redirects) 20) #f policy)))
    (if called (exchange-mark-called s) s)))

;; head : Integer (Listof (Pairof String String)) -> Response
;; A head's response: its body and timings #f, as the shell hands one.
(define (head status headers)
  (make-http-response status 'http/1.1 "" headers #f #f '()))

;; tag : Answer -> (List Symbol Any)
;; An answer, short: (done STATUS), (next URL METHOD BODY LENGTH BUFFER WAIT),
;; or (fail REASON).
(define (tag answer)
  (case (car answer)
    ((done) (list 'done (http-response-status (cadr answer))))
    ((next) (let ((r (caddr answer)))
              (list 'next (curl-request-url r) (curl-request-method r)
                    (let ((b (curl-request-body r))) (if (bytevector? b) (latin-1 b) b))
                    (curl-request-body-length r) (curl-request-stream-buffer r) (cadddr answer))))
    ((fail) (list 'fail (let ((c (cadr answer)))
                          (cond ((http-redirect-error? c) (http-redirect-error-reason c))
                                ((http-timeout? c) 'http-timeout)
                                ((curl-transfer-error? c) (list 'transfer (curl-transfer-error-code c)))
                                (else (described c))))))
    (else (list 'unknown answer))))

;; a-policy-made : (U Retry (List 'raised String))
;; Made under a guard, as every top-level definition that can raise is: a
;; raise there would kill the suite, naming no test (traps.md).
(define a-policy-made
  (guard (e (#t (list 'raised (describe e))))
    (make-http-retry 'attempts 3 'backoff-ms 100 'jitter #f 'statuses '(503)
                     'methods '(get post put patch delete))))
(define a-policy (and (http-retry? a-policy-made) a-policy-made))

(test-equal "the tables' policy is made"
  #t
  (http-retry? a-policy-made))

;; head-rows : (Listof (List String State Response Answer-Tag))
;; Each row: a name, the state before the head, the head, and exchange-step's
;; answer, tagged. The predicate must answer #t exactly for a next. Made
;; under a guard: a raise makes one row that names it, and fails the test.
(define head-rows
  (guard (e (#t (list (list "the rows raised" (describe e) #f '(not-made)))))
   (let ((loc (lambda (to) (list (cons "Location" to)))))
    (list
     (list "a 200, no policy" (table-state 'get #f #f #f) (head 200 '()) '(done 200))
     (list "a 302 with a Location" (table-state 'get #f #f #f) (head 302 (loc "/b"))
           '(next "http://given.example/b" get #f #f 4096 0))
     (list "a 302 with no Location" (table-state 'get #f #f #f) (head 302 '()) '(done 302))
     (list "a 302 with redirects #f" (table-state 'get #f #f #f #f) (head 302 (loc "/b")) '(done 302))
     (list "a 302 past redirects 0" (table-state 'get #f #f #f 0) (head 302 (loc "/b")) '(fail too-many-redirects))
     (list "a 302 to ftp:, no http or https on every libcurl" (table-state 'get #f #f #f) (head 302 (loc "ftp://h.example/x"))
           '(fail bad-location))
     (list "a 503 with a policy" (table-state 'get #f #f a-policy) (head 503 '())
           '(next "http://given.example/a" get #f #f 4096 100))
     (list "a 503 whose Retry-After passes the bound" (table-state 'get #f #f a-policy)
           (head 503 (list (cons "Retry-After" "5"))) '(done 503))
     (list "a 503 with no policy" (table-state 'get #f #f #f) (head 503 '()) '(done 503))
     (list "a whole body's 307" (table-state 'post (bytes-of "body") #f #f) (head 307 (loc "/b"))
           '(next "http://given.example/b" post "body" #f 4096 0))
     (list "a whole body's 503 with a policy" (table-state 'post (bytes-of "body") #f a-policy) (head 503 '())
           '(next "http://given.example/a" post "body" #f 4096 100))
     (list "a producer's 307, not called" (table-state 'post 'stream #f #f) (head 307 (loc "/b"))
           '(next "http://given.example/b" post stream 100 4096 0))
     (list "a producer's 307, called" (table-state 'post 'stream #t #f) (head 307 (loc "/b"))
           '(fail body-not-replayable))
     (list "a producer's 303, called" (table-state 'post 'stream #t #f) (head 303 (loc "/b"))
           '(next "http://given.example/b" get #f #f 4096 0))
     (list "a producer's 503 with a policy, not called" (table-state 'post 'stream #f a-policy) (head 503 '())
           '(next "http://given.example/a" post stream 100 4096 100))
     (list "a producer's 503 with a policy, called" (table-state 'post 'stream #t a-policy) (head 503 '())
           '(done 503))))))

(test-equal "the head's predicate, exchange-steps-past?, against exchange-step with the same clocks and draw, on every row: #t exactly where exchange-step answers next, a redirect followed or a retry taken; #f for done and fail; and exchange-step's answer as the row says"
  (map (lambda (row) (list (car row) (eq? (car (cadddr row)) 'next) (cadddr row))) head-rows)
  (map (lambda (row)
         (guard (e (#t (list (car row) 'raised (describe e))))
           (let ((state (cadr row)) (response (caddr row)))
             (list (car row)
                   (exchange-steps-past? state response table-now table-utc 0.5)
                   (tag (exchange-step state (list 'response response) table-now table-utc 0.5))))))
       head-rows))

(test-equal "the head's predicate reads the clocks it is given: a 503 whose Retry-After of 2 s fits at 1 ms in steps past it, and at 3001 ms in does not, as exchange-step answers at each"
  '((#t next) (#f done))
  (map (lambda (at)
         (let ((state (table-state 'get #f #f a-policy)) (r (head 503 (list (cons "Retry-After" "2")))))
           (list (exchange-steps-past? state r (+ table-start (* at 1000000)) table-utc 0.5)
                 (car (exchange-step state (list 'response r) (+ table-start (* at 1000000)) table-utc 0.5)))))
       '(1 3001)))

;; at-most-once-rows : the redirects a producer's body meets once it counts
;; as called: (METHOD STATUS ANSWER) for each method that takes a body and
;; each redirect status.
(define at-most-once-rows
  (apply append
         (map (lambda (method)
                (map (lambda (status)
                       (list method status
                             (cond ((= status 303) 'followed)
                                   ((and (memv status '(301 302)) (eq? method 'post)) 'followed)
                                   (else 'body-not-replayable))))
                     '(301 302 303 307 308)))
              '(post put patch delete))))

(test-equal "at most once, by table: a producer's body that counts as called meets body-not-replayable at a 307 or a 308 of every method, and at a 301 or a 302 of every method but post; a post through a 301 or a 302 and every method through a 303 are followed, as a get; not called, every one is followed, a 307 keeping the body"
  (list (map (lambda (row) (list (car row) (cadr row) (caddr row))) at-most-once-rows)
        (map (lambda (row) (list (car row) (cadr row) 'followed)) at-most-once-rows))
  (let ((answer (lambda (called)
                  (map (lambda (row)
                         (let ((a (exchange-step (table-state (car row) 'stream called #f)
                                                 (list 'response (head (cadr row) (list (cons "Location" "/b"))))
                                                 table-now table-utc 0.5)))
                           (list (car row) (cadr row)
                                 (case (car a)
                                   ((next) 'followed)
                                   ((fail) (if (http-redirect-error? (cadr a)) (http-redirect-error-reason (cadr a))
                                               (described (cadr a))))
                                   (else (tag a))))))
                       at-most-once-rows))))
    (list (answer #t) (answer #f))))

(test-equal "at most once, by table: body-not-replayable is checked first, before too-many-redirects and bad-location; it carries the response, its body and timings #f, and the Location; the call's context counts the transfer"
  (list '(fail body-not-replayable) '(fail body-not-replayable)
        (list 'http-redirect-error 'body-not-replayable "/b" '(307 #f #f ()))
        (list 'exchange 'post "http://given.example/a" '() 1))
  (let* ((past (exchange-step (table-state 'post 'stream #t #f 0)
                              (list 'response (head 307 (list (cons "Location" "/b")))) table-now table-utc 0.5))
         (bad (exchange-step (table-state 'post 'stream #t #f)
                             (list 'response (head 308 (list (cons "Location" "ftp://h.example/x")))) table-now table-utc 0.5))
         (plain (exchange-step (table-state 'post 'stream #t #f)
                               (list 'response (head 307 (list (cons "Location" "/b")))) table-now table-utc 0.5))
         (d (described (cadr plain))))
    (list (tag past) (tag bad)
          (find (lambda (x) (and (pair? x) (eq? (car x) 'http-redirect-error))) d)
          (find (lambda (x) (and (pair? x) (eq? (car x) 'exchange))) d))))

(test-equal "at most once, by table: no retry takes a step whose producer counts as called, a status's nor a failure's, a refused connect's among them, whatever the policy; not called, each is retried; a whole body's is retried either way, marked or not"
  '((done 503) (fail (transfer 7)) (next "http://given.example/a" post stream 100 4096 100)
    (next "http://given.example/a" post stream 100 4096 100)
    (next "http://given.example/a" post "body" #f 4096 100) (next "http://given.example/a" post "body" #f 4096 100))
  (let ((refused (make-classed-transfer-error 'perform-failed 7 #f "Could not connect" #f #f 0)))
    (list (tag (exchange-step (table-state 'post 'stream #t a-policy) (list 'response (head 503 '())) table-now table-utc 0.5))
          (tag (exchange-step (table-state 'post 'stream #t a-policy) (list 'failed refused) table-now table-utc 0.5))
          (tag (exchange-step (table-state 'post 'stream #f a-policy) (list 'response (head 503 '())) table-now table-utc 0.5))
          (tag (exchange-step (table-state 'post 'stream #f a-policy) (list 'failed refused) table-now table-utc 0.5))
          (tag (exchange-step (table-state 'post (bytes-of "body") #t a-policy) (list 'response (head 503 '()))
                              table-now table-utc 0.5))
          (tag (exchange-step (table-state 'post (bytes-of "body") #f a-policy) (list 'failed refused)
                              table-now table-utc 0.5)))))

(test-equal "next-request carries the stream's keys: a producer's 307 keeps body stream, its body-length and its stream-buffer; a 303 and a post's 301 drop the body and the body-length, and keep the stream-buffer; a whole body's 308 keeps its bytes and the stream-buffer"
  '((next "http://given.example/b" post stream 100 4096 0) (next "http://given.example/b" get #f #f 4096 0)
    (next "http://given.example/b" get #f #f 4096 0) (next "http://given.example/b" put "body" #f 4096 0))
  (let ((step (lambda (method body status)
                (tag (exchange-step (table-state method body #f #f)
                                    (list 'response (head status (list (cons "Location" "/b"))))
                                    table-now table-utc 0.5)))))
    (list (step 'post 'stream 307) (step 'put 'stream 303) (step 'post 'stream 301) (step 'put (bytes-of "body") 308))))

(test-equal "exchange-mark-called: a state's producer counts as called once marked, and a marked state is answered as it is; a fresh one does not"
  '(#f #t #t)
  (let* ((fresh (table-state 'post 'stream #f #f)) (marked (exchange-mark-called fresh)))
    (list (exchange-called? fresh) (exchange-called? marked) (eq? marked (exchange-mark-called marked)))))

(test-equal "exchange-raised: a 28 at the deadline is the bound's, &http-timeout first; one before it, with the transfer's connect timeout shorter than its timeout, is the transfer's own; a 56 is neither; each with the call's context, its transfer counted"
  (list (list '(http-error) '(http-timeout 5000) '(curl-transfer-error timeout perform-failed 28)
              (list 'exchange 'get "http://given.example/a" '() 1))
        (list '(curl-transfer-error timeout perform-failed 28) (list 'exchange 'get "http://given.example/a" '() 1))
        (list '(curl-transfer-error send-receive perform-failed 56) (list 'exchange 'get "http://given.example/a" '() 1)))
  (let* ((c28 (make-classed-transfer-error 'perform-failed 28 #f "Timeout was reached" #f #f 10))
         (c56 (make-classed-transfer-error 'perform-failed 56 #f "Failure when receiving data" #f #f 10))
         (state (cadr (exchange-submission (table-state 'get #f #f #f) table-now))))
    (list (described (exchange-raised state c28 (+ table-start 5000000000)))
          (described (exchange-raised (exchange-mark-called (table-state 'get #f #f #f)) c28 table-now))
          (described (exchange-raised state c56 (+ table-start 5000000000))))))

;; A retry whose wait leaves no time, through the shell: a state past its
;; deadline whose step retried a response answers it at its submission, and
;; drive-stream hands PROC that response and a port over its body in
;; memory, empty for a body of #f. No transfer is made.
(test-equal "a retry whose wait leaves no time, through drive-stream: PROC is handed the response the retry repeated, its body read, and a port over that body in memory, the call answering PROC's values, two of them; for a hop cancelled at its head, its body #f, the call raises &http-timeout with its context, PROC never called, through call-with-response-port's mode and http-request's alike (decided by the maintainer, 2026-11-01); no transfer started"
  (list (list 503 "attempt 1\n" '(text "attempt 1\n") 'two)
        (list 'raised '(http-error) '(http-timeout 5000) (list 'exchange 'get nowhere '() 1))
        (list 'raised '(http-error) '(http-timeout 5000) (list 'exchange 'get nowhere '() 1))
        0)
  (guard (e (#t (list 'raised (describe e))))
    (with-session base-keys
      (lambda (s)
        (let* ((started (transfers-started))
               (retried
                (lambda (body mode)
                  (let* ((start (- (monotonic-ns) 6000000000))
                         (state (make-exchange 'get nowhere (table-request 'get #f #f) 5000 start 20 #f a-policy))
                         (step (exchange-step (cadr (exchange-submission state (+ start 1000000)))
                                              (list 'response (make-http-response 503 'http/1.1 "" '() body #f '()))
                                              (+ start 1000000) table-utc 0.5)))
                    (guard (e (#t (cons 'raised (described e))))
                      (call-with-values
                        (lambda ()
                          (drive-stream (http-session-engine s) (cadr step) (lambda () 0.5) #f mode
                                        (lambda (r p)
                                          (values (list (http-response-status r)
                                                        (let ((b (http-response-body r))) (and b (latin-1 b)))
                                                        (text-of p))
                                                  'two))
                                        (if (eq? mode 'port) 'call-with-response-port 'http-request)))
                        (lambda answers
                          (if (= (length answers) 2)
                              (append (car answers) (list (cadr answers)))
                              (list 'one answers)))))))))
          (list (retried (bytes-of "attempt 1\n") 'port) (retried #f 'port) (retried #f 'whole)
                (- (transfers-started) started)))))))

(test-equal "the core: a retry that runs out of time, its retried response's body #f, a hop cancelled at its head, fails with &http-timeout at its submission and at its transfer's bound's 28 having sent nothing, where one whose body was read answers that response"
  (list '(fail http-timeout) '(fail http-timeout) '(done 503) '(done 503))
  (let* ((start table-start)
         (c28 (make-classed-transfer-error 'perform-failed 28 #f "Timeout was reached" #f #f 0))
         (retried (lambda (body)
                    (cadr (exchange-step (cadr (exchange-submission (make-exchange 'get nowhere (table-request 'get #f #f) 5000 start
                                                                                   20 #f a-policy)
                                                                    (+ start 1000000)))
                                         (list 'response (make-http-response 503 'http/1.1 "" '() body #f '()))
                                         (+ start 1000000) table-utc 0.5))))
         (at-submission (lambda (body) (tag (exchange-submission (retried body) (+ start 6000000000)))))
         (at-the-bound (lambda (body)
                         (let ((sub (exchange-submission (retried body) (+ start 4000000000))))
                           (tag (exchange-step (cadr sub) (list 'failed c28) (+ start 5000000000) table-utc 0.5))))))
    (list (at-submission #f) (at-the-bound #f) (at-submission (bytes-of "attempt 1\n"))
          (at-the-bound (bytes-of "attempt 1\n")))))

(test-equal "a streamed call made inside a critical section is refused before anything is submitted, an assertion violation from its name, with its context: call-with-response-port, and http-request with a producer; PROC and the producer never called; no transfer started"
  (list (list 'raised '(assertion call-with-response-port) (list 'exchange 'get nowhere '() 0))
        (list 'raised '(assertion http-request) (list 'exchange 'post nowhere '() 0))
        0 0 0)
  (guard (e (#t (list 'raised (describe e))))
    (with-session base-keys
      (lambda (s)
        (let* ((started (transfers-started))
               (proc-calls 0)
               (p (new-producer 10 10))
               (port-call (outcome (lambda ()
                                     (critical-section
                                      (call-with-response-port s 'get nowhere
                                        (lambda (r port) (set! proc-calls (+ proc-calls 1)) 'called))))))
               (producer-call (outcome (lambda ()
                                         (critical-section (http-post s nowhere 'body (thunk-of p)))))))
          (list port-call producer-call proc-calls (producer-calls p) (- (transfers-started) started)))))))

;; --- against the origin ----------------------------------------------------------------

(define (scenarios o)

  ;; --- PROC handed the final head and the port, over every face
  (for-each
   (lambda (spec)
     (let ((face (car spec)) (path (cadr spec)))
       (test-equal (string-append (symbol->string face) ": PROC is handed the final head, its status, version, URL and history whole, its headers those of the same response read whole, its body and timings #f, and a port over its body, 100,000 bytes of the pattern, whole; PROC runs on this thread, never the engine's; the call answers its two values")
         (list (list 200 (caddr spec) (url-of o face path) #f #f '()) 'same-headers '(end 100000 #f)
               'this-thread 'second)
         (guard (e (#t (list 'raised (describe e))))
           (with-session base-keys
             (lambda (s)
               (let* ((plain (http-get s (url-of o face path)))
                      (engine-thread (curl-engine-thread (http-session-engine s))))
                 (call-with-values
                   (lambda ()
                     (call-with-response-port s 'get (url-of o face path)
                       (lambda (r port)
                         (values (list (head-of r)
                                       (if (equal? (http-response-headers r) (http-response-headers plain))
                                           'same-headers
                                           (list (http-response-headers r) (http-response-headers plain)))
                                       (drain port)
                                       (if (and (eqv? (get-thread-id) main-thread)
                                                (not (eqv? (get-thread-id) engine-thread)))
                                           'this-thread
                                           (list (get-thread-id) main-thread engine-thread)))
                                 'second))))
                   (lambda (seen second) (append seen (list second)))))))))))
   (list (list 'http "/pattern/100000" 'http/1.1)
         (list 'raw "/raw/pattern?key=head-raw&bytes=100000&chunk=16384" 'http/1.1)
         (list 'https "/pattern/100000" 'http/1.1)
         (list 'h2 "/pattern/100000" 'http/2)))

  ;; --- a hop read whole when its request sends no body
  (for-each
   (lambda (face)
     (test-equal (string-append (symbol->string face) ": a redirect decided at its head, the request sending no body: the 302's body read whole into the history, \"redirect 302\\n\", with its timings; the final body through the port")
       (list (list 200 #f #f (list (list 302 "redirect 302\n" '(name-lookup connect tls-handshake first-byte total) '())))
             '(end 1000 #f))
       (guard (e (#t (list 'raised (describe e))))
         (with-session base-keys
           (lambda (s)
             (call-with-response-port s 'get (url-of o face "/redirect/302?to=%2Fpattern%2F1000")
               (lambda (r port)
                 (list (summary r) (drain port)))))))))
   '(http h2))

  ;; --- a hop cancelled at its head when its request sends a body
  (test-equal "http: a whole body's post through a 307, decided at the head: the hop is cancelled there, its history entry's body and timings #f; the 307 keeps the body, which the sink reads whole"
    (list (list 200 #f #f (list (list 307 #f #f '()))) 'whole-body)
    (guard (e (#t (list 'raised (describe e))))
      (with-session base-keys
        (lambda (s)
          (call-with-response-port s 'post (url-of o 'http "/redirect/307?to=%2Fsink%3Fkey%3Dhop-whole")
            'body (pattern-piece 0 65536)
            (lambda (r port)
              (list (summary r) (whole (sink-fields (cadr (text-of port))) 65536))))))))

  ;; --- a retry decided at the head
  (test-equal "raw: a retry decided at its head, the request sending no body: the 503's body read whole and dropped, as a retried response joins no history; the retry's 200 through the port; two attempts at the origin"
    '((200 #f #f ()) (text "attempt 2\n") "attempts 2\n")
    (guard (e (#t (list 'raised (describe e))))
      (with-session (append base-keys (list 'retry (make-http-retry 'backoff-ms 50 'jitter #f 'statuses '(503))))
        (lambda (s)
          (let ((seen (call-with-response-port s 'get (url-of o 'raw "/raw/retry?key=sc-retry-get&fail=1&how=status&code=503")
                        (lambda (r port) (list (summary r) (text-of port))))))
            (append seen (list (latin-1 (http-response-body (http-get s (url-of o 'raw "/raw/attempts?key=sc-retry-get")))))))))))

  (test-equal "raw: a retry of a whole body's post, decided at its head and cancelled there: the retry's 200 through the port; two attempts at the origin"
    '((200 #f #f ()) (text "attempt 2\n") "attempts 2\n")
    (guard (e (#t (list 'raised (describe e))))
      (with-session (append base-keys (list 'retry (make-http-retry 'backoff-ms 50 'jitter #f 'statuses '(503)
                                                                    'methods '(post))))
        (lambda (s)
          (let ((seen (call-with-response-port s 'post (url-of o 'raw "/raw/retry?key=sc-retry-post&fail=1&how=status&code=503")
                        'body (pattern-piece 0 2000)
                        (lambda (r port) (list (summary r) (text-of port))))))
            (append seen (list (latin-1 (http-response-body (http-get s (url-of o 'raw "/raw/attempts?key=sc-retry-post")))))))))))

  ;; --- the clocks: a failure in a hop's read is stepped with its own; a
  ;; retry's wait runs from its head
  (test-equal "raw: a failure while a hop's body is read is stepped with the clocks read at the failure: a 503 retried at its head, its body stalled past the call's bound of 1500 ms, its connect timeout 700 ms, fails with the bound's 28, &http-timeout first, one transfer; read with the head's clocks it would be retried, and raised with no &http-timeout"
    (list 'raised '(http-error) '(http-timeout 1500) '(curl-transfer-error timeout perform-failed 28)
          (list 'exchange 'get (url-of o 'raw "/raw/retry?key=sc-slow-fail&fail=5&how=status&code=503&slow=4000") '() 1))
    (guard (e (#t (list 'raised (describe e))))
      (with-session (append base-keys (list 'retry (make-http-retry 'backoff-ms 100 'jitter #f 'statuses '(503))))
        (lambda (s)
          (outcome (lambda ()
                     (call-with-response-port s 'get (url-of o 'raw "/raw/retry?key=sc-slow-fail&fail=5&how=status&code=503&slow=4000")
                       'timeout-ms 1500 'connect-timeout-ms 700
                       (lambda (r port) (list 'proc-called (summary r))))))))))

  (test-equal "raw: a retry's wait is measured from its head: a 503 with Retry-After 1, its body 900 ms slow, within a bound of 1600 ms, is retried 1000 ms after its head, not after its body, and the retry's 200 reaches PROC, sooner than 1600 ms and no sooner than 1000"
    '((200 #f #f ()) (text "attempt 2\n") within)
    (guard (e (#t (list 'raised (describe e))))
      (with-session (append base-keys (list 'retry (make-http-retry 'backoff-ms 100 'jitter #f 'statuses '(503))))
        (lambda (s)
          (let* ((t0 (now-ms))
                 (seen (call-with-response-port s 'get (url-of o 'raw "/raw/retry?key=sc-from-head&fail=1&how=status&code=503&after=1&slow=900")
                         'timeout-ms 1600
                         (lambda (r port) (list (summary r) (text-of port)))))
                 (took (- (now-ms) t0)))
            (append seen (list (if (and (>= took 1000) (< took 1600)) 'within (list 'took took)))))))))

  (test-equal "raw: a retry whose wait would pass the bound is decided once, at the head: a 503 whose Retry-After of 3 s passes a bound of 1500 ms is the final head, handed to PROC with its body through the port; one attempt at the origin"
    '((503 #f #f ()) (text "attempt 1\n") "attempts 1\n")
    (guard (e (#t (list 'raised (describe e))))
      (with-session (append base-keys (list 'retry (make-http-retry 'backoff-ms 100 'jitter #f 'statuses '(503)
                                                                    'max-backoff-ms 5000)))
        (lambda (s)
          (let ((seen (call-with-response-port s 'get (url-of o 'raw "/raw/retry?key=sc-once&fail=1&how=status&code=503&after=3")
                        'timeout-ms 1500
                        (lambda (r port) (list (summary r) (text-of port))))))
            (append seen (list (latin-1 (http-response-body (http-get s (url-of o 'raw "/raw/attempts?key=sc-once")))))))))))

  ;; --- a producer's body through every redirect, once libcurl asked:
  ;; the raw face answers once 65,536 body bytes have come, so libcurl had
  ;; asked by the head on every libcurl
  (test-equal "raw: a producer's body of 256 KiB, sized, answered once 65,536 bytes arrived, through every redirect status and method: body-not-replayable at a 307 and a 308 of every method, and at a 301 and a 302 of put, patch and delete, carrying the response and its Location, one transfer; followed, to a get of the raw face's seq, for a post's 301 and 302 and every method's 303"
    (map (lambda (row)
           (if (eq? (caddr row) 'followed)
               (list (car row) (cadr row) 'followed 200 "GET" (list (list (cadr row) #f #f '())))
               (list (car row) (cadr row) 'body-not-replayable (cadr row) 1)))
         at-most-once-rows)
    (in-order
     (lambda (row)
       (let* ((method (car row)) (status (cadr row))
              (key (string-append "sc-amo-" (symbol->string method) "-" (number->string status)))
              (to (pct (string-append "/raw/seq?key=" key "&bytes=10"))))
         (guard (e (#t (list method status 'raised (describe e))))
           (with-session base-keys
             (lambda (s)
               (let ((p (new-producer 262144 65536)))
                 (guard (e ((http-redirect-error? e)
                            (list method status (http-redirect-error-reason e)
                                  (http-response-status (http-redirect-error-response e))
                                  (if (http-exchange? e) (http-exchange-transfers e) 'no-exchange)))
                           (#t (list method status 'raised (described e))))
                   (let ((r (http-request s method (url-of o 'raw (string-append "/raw/answer-at?status=" (number->string status)
                                                                                 "&after=65536&to=" to))
                                          'body (thunk-of p) 'body-length 262144)))
                     (list method status 'followed (http-response-status r)
                           (field (sink-fields (or (http-response-header r "Sink") "")) 'method)
                           (map summary (http-response-history r)))))))))))
     at-most-once-rows))

  ;; --- the port closed and the transfer cancelled
  (test-equal "raw: when PROC returns after one read of a 64 MiB body, the call answers its value, the port is closed, and the transfer is cancelled: no transfer live within 5 s, the origin's writes short of the body"
    '(early closed ended short)
    (guard (e (#t (list 'raised (describe e))))
      (with-session base-keys
        (lambda (s)
          (let* ((port #f)
                 (answer (call-with-response-port s 'get (url-of o 'raw "/raw/pattern?key=sc-early&bytes=67108864&chunk=65536")
                           (lambda (r p) (set! port p) (get-bytevector-some p) 'early)))
                 (closed (if (and port (port-closed? port)) 'closed (list 'open port)))
                 (ended (live-ends s))
                 (stalls (words (latin-1 (http-response-body (http-get s (url-of o 'raw "/raw/stalls?key=sc-early")))))))
            (list answer closed ended
                  (if (and (= (length stalls) 4) (< (string->number (cadr stalls)) 67108864)) 'short stalls)))))))

  (test-equal "raw: when PROC escapes after one read, by a raise, the raise leaves the call as raised, the port is closed, and the transfer is cancelled"
    '((raised non-condition escaped) closed ended)
    (guard (e (#t (list 'raised (describe e))))
      (with-session base-keys
        (lambda (s)
          (let* ((port #f)
                 (answer (outcome (lambda ()
                                    (call-with-response-port s 'get (url-of o 'raw "/raw/pattern?key=sc-escape&bytes=67108864&chunk=65536")
                                      (lambda (r p) (set! port p) (get-bytevector-some p) (raise 'escaped)))))))
            (list answer (if (and port (port-closed? port)) 'closed (list 'open port)) (live-ends s)))))))

  ;; --- drive-last-token's record, a test seam's (the slice's fourth review):
  ;; a call's token, and the private copy of a whole body its plan holds,
  ;; never outlive the call through the seam. A 64 MiB body, as the review's
  ;; probe sent: held after the call, the heap kept 64.1 MB more.
  (test-equal "raw: drive-last-token records a streamed call's token only while a test arms it, and lets it go as the call ends: a 64 MiB whole body's post through call-with-response-port, unarmed, leaves the seam #f inside PROC and after, and under 16 MiB more retained once collected; armed, the seam answers the call's token inside PROC, #f once the call has ended, and again under 16 MiB retained"
    '((unarmed #f #f retained-under-16-mib) (armed in-proc-token #f retained-under-16-mib))
    (guard (e (#t (list 'raised (describe e))))
      (let* ((one (lambda (key armed?)
                    (drive-last-token-arm! armed?)
                    (let* ((base (retained-bytes))
                           (inside (with-session base-keys
                                     (lambda (s)
                                       (call-with-response-port s 'post (url-of o 'raw (string-append "/raw/sink?key=" key))
                                         'body (make-bytevector (* 64 1024 1024) 7)
                                         (lambda (r port)
                                           (get-bytevector-all port)
                                           (and (drive-last-token) 'in-proc-token))))))
                           (after (drive-last-token))
                           (retained (- (retained-bytes) base)))
                      (drive-last-token-arm! #f)
                      (list (if armed? 'armed 'unarmed) inside (and after 'a-token-still-held)
                            (if (< retained (* 16 1024 1024)) 'retained-under-16-mib
                                (list 'retained retained))))))
             (unarmed (one "sc-retain-unarmed" #f))
             (armed (one "sc-retain-armed" #t)))
        (list unarmed armed))))

  ;; --- the shell's draws (the M6 plan, section 3.6): one a transfer, read
  ;; at its head, the hop's step taking that same draw. Through drive-stream
  ;; itself, with a sequenced draw that counts its calls, 0.1 then 0.9, and a
  ;; jittered policy whose backoff, 2,000 ms, fits a 1,500 ms bound at 0.1
  ;; of it and passes it at 0.9: the first 503's retry is taken only when
  ;; its step reads the head's draw, 0.1; a fresh one, 0.9, answers the 503.
  (for-each
   (lambda (spec)
     (test-equal (string-append "raw: " (car spec) ": the hop stepped with the draw its head read, one draw a transfer: the 503's retry taken at 0.1 of the backoff, the retry's 200 handed to PROC, two draws for two transfers")
       '(200 (text "attempt 2\n") 2)
       (guard (e (#t (list 'raised (describe e))))
         (with-session base-keys
           (lambda (s)
             (let* ((key (string-append "sc-draws-" (cadr spec)))
                    (url (url-of o 'raw (string-append "/raw/retry?key=" key "&fail=1&how=status&code=503")))
                    (policy (make-http-retry 'attempts 3 'backoff-ms 2000 'max-backoff-ms 10000 'jitter #t
                                             'statuses '(503) 'methods '(get post)))
                    (request (if (string=? (cadr spec) "post")
                                 (make-curl-request url 'method 'post 'body (pattern-piece 0 2000) 'proxy #f
                                                    'stream-buffer 65536 'timeout-ms 1500)
                                 (make-curl-request url 'proxy #f 'stream-buffer 65536 'timeout-ms 1500)))
                    (state (make-exchange (string->symbol (cadr spec)) url request 1500 (monotonic-ns) 20 #f policy))
                    (draws '(0.1 0.9 0.9 0.9 0.9 0.9))
                    (drawn 0)
                    (draw (lambda ()
                            (let ((d (list-ref draws (min drawn 5))))
                              (set! drawn (+ drawn 1))
                              d)))
                    (seen (drive-stream (http-session-engine s) state draw #f 'port
                                        (lambda (r port) (list (http-response-status r) (text-of port)))
                                        'call-with-response-port)))
               (append seen (list drawn))))))))
   '(("a get, its hop read whole" "get") ("a whole body's post, its hop cancelled at its head" "post")))

  ;; --- the port is the call's thread's, and waits only with interrupts on
  (test-equal "http: the port is read on the call's thread alone: another thread's read that reaches the port's read is an assertion violation from call-with-response-port; the call's own reads then take the body whole"
    '((raised (assertion call-with-response-port)) (end 100000 #f))
    (guard (e (#t (list 'raised (describe e))))
      (with-session base-keys
        (lambda (s)
          (call-with-response-port s 'get (url-of o 'http "/pattern/100000")
            (lambda (r port)
              (let ((seen #f) (mx (make-mutex)))
                (fork-thread (lambda ()
                               (let ((got (outcome (lambda () (get-bytevector-some port)))))
                                 (with-mutex mx (set! seen got)))))
                (wait-for (lambda () (with-mutex mx seen)) 10000)
                (list (with-mutex mx seen) (drain port)))))))))

  (test-equal "http: the port is closed on the call's thread alone: another thread's close is an assertion violation from call-with-response-port, which leaves the port open; the call's own reads then take the body whole"
    '((raised (assertion call-with-response-port)) open (end 100000 #f))
    (guard (e (#t (list 'raised (describe e))))
      (with-session base-keys
        (lambda (s)
          (call-with-response-port s 'get (url-of o 'http "/pattern/100000")
            (lambda (r port)
              (let ((seen #f) (mx (make-mutex)))
                (fork-thread (lambda ()
                               (let ((got (outcome (lambda () (close-port port)))))
                                 (with-mutex mx (set! seen got)))))
                (wait-for (lambda () (with-mutex mx seen)) 10000)
                (list (with-mutex mx seen) (if (port-closed? port) 'closed 'open) (drain port)))))))))

  (test-equal "http: a read that must wait, inside a critical section, is refused before it waits, an assertion violation from call-with-response-port; outside one, the body whole"
    '((raised (assertion call-with-response-port)) (end 1000 #f))
    (guard (e (#t (list 'raised (describe e))))
      (with-session base-keys
        (lambda (s)
          (call-with-response-port s 'get (url-of o 'http "/pattern/1000?delay=300")
            (lambda (r port)
              (list (outcome (lambda () (critical-section (get-bytevector-some port))))
                    (drain port))))))))

  ;; --- the bound across PROC's reading
  (test-equal "http: the call's bound runs across PROC's reading: PROC waits 1500 ms, past a bound of 1000, then reads 1,000,000 bytes, which the transfer paused for: the port's read raises the bound's 28, &http-timeout first, with the call's context, one transfer, every time after"
    (list (list 'raised 'some '(http-error) '(http-timeout 1000) '(curl-transfer-error timeout perform-failed 28)
                (list 'exchange 'get (url-of o 'http "/pattern/1000000") '() 1))
          'same-again)
    (guard (e (#t (list 'raised (describe e))))
      (with-session base-keys
        (lambda (s)
          (call-with-response-port s 'get (url-of o 'http "/pattern/1000000") 'timeout-ms 1000
            (lambda (r port)
              (pause-ms 1500)
              (let* ((first (drain port))
                     (again (guard (e (#t (described e))) (get-bytevector-some port) 'no-raise)))
                (list (if (eq? (car first) 'raised) (cons 'raised (cons 'some (cddr first))) first)
                      (if (equal? again (cddr first)) 'same-again again)))))))))

  ;; --- a producer's pieces
  (for-each
   (lambda (face)
     (test-equal (string-append (symbol->string face) ": a producer's 1 MiB in 64 KiB pieces, sized and chunked, through http-request: the sink line whole; every call on this thread, its first only once libcurl asked, never one after its end; each a 200")
       '((sized whole-body 17 0 this-thread) (chunked whole-body 17 0 this-thread))
       (in-order
        (lambda (framing)
          (guard (e (#t (list framing 'raised (describe e))))
            (with-session base-keys
              (lambda (s)
                (let* ((p (new-producer 1048576 65536))
                       (path (if (memq face '(raw raw-tls)) "/raw/sink?key=sc-pieces" "/sink?key=sc-pieces"))
                       (r (http-post s (url-of o face path) 'body (thunk-of p)
                                     'body-length (and (eq? framing 'sized) 1048576))))
                  (list framing (whole (sink-fields (latin-1 (http-response-body r))) 1048576)
                        (producer-calls p) (producer-after-eof p)
                        (if (equal? (producer-threads p) (list main-thread)) 'this-thread (producer-threads p))))))))
        '(sized chunked))))
   '(raw raw-tls h2))

  (test-equal "raw: a producer's first call comes only once libcurl asks: on the engine that holds the prerequest callable 200 ms once connected, before the request is sent, the producer is first called 200 ms or more after the call starts; the body whole"
    '(after-the-hold whole-body)
    (guard (e (#t (list 'raised (describe e))))
      (with-held-session
        (lambda (s)
          (let* ((p (new-producer 2000 1000))
                 (r (http-post s (url-of o 'raw "/raw/sink?key=sc-first-ask") 'body (thunk-of p) 'body-length 2000)))
            (list (if (and (producer-first-at p) (>= (producer-first-at p) 200)) 'after-the-hold (producer-first-at p))
                  (whole (sink-fields (latin-1 (http-response-body r))) 2000)))))))

  ;; On 8.7.0 and 8.7.1 the request size is unknown, so a post's failure is
  ;; never retried there (ADR-0022, amended; test-retry's
  ;; unknown-size-versions): the Mac's run made one transfer.
  (test-equal (string-append "a producer is never called for a refused connect, and the connect is retried, as nothing was sent: three transfers, the low level's 7, with &http-exchange; on 8.7.0 and 8.7.1, whose request size is unknown, one, on " version-text)
    (list 0 (list 'raised '(curl-transfer-error connect perform-failed 7)
                  (list 'exchange 'post nowhere '() (if (member version '("8.7.0" "8.7.1")) 1 3))))
    (guard (e (#t (list 'raised (describe e))))
      (with-session (append base-keys (list 'retry (make-http-retry 'backoff-ms 10 'jitter #f)))
        (lambda (s)
          (let* ((p (new-producer 2000 1000))
                 (r (outcome (lambda () (http-post s nowhere 'body (thunk-of p) 'body-length 2000)))))
            (list (producer-calls p) r))))))

  ;; A piece past the length straddles it, 1,500 bytes on 1,500 against
  ;; 2,000, so a put of its first 500 bytes shows; the cancel is read where
  ;; the raise is made, by the caller's handler, before the call's own wind
  ;; could cancel; the puts by the token's count, the low level's, and what
  ;; reached the server by the sink's record (the slice's fourth review).
  (test-equal "raw: a body short of its body-length fails the call by the low level's body-length-mismatch, alike on every libcurl; a piece past it, 1,500 bytes on 1,500 against 2,000, is &http-request-error, field body, its value the producer, body-length-mismatch, its irritants the body-length and the piece's length, as the low level's are, with the call's context; no transfer live where the caller's handler sees the raise; nothing of that piece put, the token's puts 1,500 bytes and the sink's read 1,500 at most; neither producer called after its end"
    (list (list 'raised '(curl-transfer-error none body-length-mismatch 42)
                (list 'exchange 'post (url-of o 'raw "/raw/sink?key=sc-short") '() 1))
          (list 'raised '(http-error) '(http-request-error body the-producer body-length-mismatch)
                (list 'exchange 'post (url-of o 'raw "/raw/sink?key=sc-long") '() 1))
          '(irritants (2000 1500))
          '(at-the-raise ended)
          '(put 1500)
          'sunk-1500-at-most
          '(0 0))
    (guard (e (#t (list 'raised (describe e))))
      (drive-last-token-arm! #t)
      (let* ((short (new-producer 1000 1000))
             (long (new-producer 3000 1500))
             (token #f)
             (raised #f)
             (at-raise #f)
             (long-thunk (let ((t (thunk-of long)))
                           (lambda ()
                             (unless token (set! token (drive-last-token)))
                             (t))))
             (short-r (with-session base-keys
                        (lambda (s) (outcome (lambda () (http-post s (url-of o 'raw "/raw/sink?key=sc-short")
                                                                   'body (thunk-of short) 'body-length 2000))))))
             (long-r (with-session base-keys
                       (lambda (s)
                         (outcome
                          (lambda ()
                            (with-exception-handler
                              (lambda (c)
                                (when (and (http-request-error? c) (not raised))
                                  (set! raised c)
                                  (set! at-raise (live-ends s)))
                                (raise-continuable c))
                              (lambda ()
                                (http-post s (url-of o 'raw "/raw/sink?key=sc-long")
                                           'body long-thunk 'body-length 2000))))))))
             (sunk (with-session base-keys
                     (lambda (s)
                       (let ((r (http-get s (url-of o 'raw "/raw/sunk?key=sc-long"))))
                         (words (latin-1 (http-response-body r))))))))
        (drive-last-token-arm! #f)
        (list short-r
              (map (lambda (part)
                     (if (equal? part (list 'http-request-error 'body long-thunk 'body-length-mismatch))
                         '(http-request-error body the-producer body-length-mismatch)
                         part))
                   long-r)
              (list 'irritants (and raised (irritants-condition? raised) (condition-irritants raised)))
              (list 'at-the-raise at-raise)
              (list 'put (and token (curl-token-body-count token)))
              (let ((n (and (= (length sunk) 2) (string=? (car sunk) "sunk") (string->number (cadr sunk)))))
                (if (and n (<= n 1500)) 'sunk-1500-at-most (cons 'sunk sunk)))
              (list (producer-after-eof short) (producer-after-eof long))))))

  ;; The producer is asked for its end at once once its puts take the
  ;; body-length whole, room or none (ADR-0031, decision 2). The piece that
  ;; takes it is 32 MiB, to a sink that reads nothing for 60 s: the kernel
  ;; takes a few MB of it, so libcurl never has room again before the
  ;; bound, and only an ask made at once, not on room, meets the piece past
  ;; the length. Asked on room, the drive waited out the bound; the races
  ;; that killed that mutant before were won both ways (mutants.md).
  (test-equal "raw: once a producer's puts take its body-length whole, it is asked for its end at once, room or none: a 32 MiB piece, the whole length, to a sink that reads nothing for 60 s, then a piece more: &http-request-error, body-length-mismatch, with the call's context, at the producer's second call, well within the call's bound of 10 s, though libcurl never has room again"
    (list (list 'raised '(http-error) '(http-request-error body the-producer body-length-mismatch)
                (list 'exchange 'post (url-of o 'raw "/raw/sink?key=sc-at-length&hold=60000") '() 1))
          2 'within-5-s)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((calls 0)
             (producer (lambda ()
                         (set! calls (+ calls 1))
                         (if (= calls 1) (make-bytevector (* 32 1024 1024) 1) (make-bytevector 1500 2))))
             (start (now-ms))
             (r (with-session (list 'proxy #f 'ca-file ca 'timeout-ms 10000)
                  (lambda (s)
                    (outcome (lambda () (http-post s (url-of o 'raw "/raw/sink?key=sc-at-length&hold=60000")
                                                   'body producer 'body-length (* 32 1024 1024)))))))
             (took (- (now-ms) start)))
        (list (map (lambda (part)
                     (if (equal? part (list 'http-request-error 'body producer 'body-length-mismatch))
                         '(http-request-error body the-producer body-length-mismatch)
                         part))
                   r)
              calls
              (if (< took 5000) 'within-5-s (list 'took took))))))

  ;; --- a producer's failures, sticky inside the port's read
  ;; A producer's failures inside the port's read: each planted at the
  ;; producer's first call once PROC runs, so a head that comes after more
  ;; calls than natively, under Valgrind say, moves nothing.
  (test-equal "raw: a producer's raise inside the port's read, its first call's once PROC runs, leaves the read as raised, that object, its transfer cancelled by then, read inside PROC; every later read raises it again; and the call raises it once PROC returns"
    '((raised non-condition boom) ended (raised non-condition boom) (raised non-condition boom))
    (guard (e (#t (list 'raised (describe e))))
      (with-session base-keys
        (lambda (s)
          (let* ((in-proc (vector #f))
                 (p (new-producer 4194304 65536 (lambda (n) (and (vector-ref in-proc 0) (raise 'boom)))))
                 (inside '())
                 (call (outcome
                        (lambda ()
                          (call-with-response-port s 'post (url-of o 'raw "/raw/mirror") 'body (thunk-of p)
                            'body-length 4194304
                            (lambda (r port)
                              (vector-set! in-proc 0 #t)
                              (let* ((first (drain port))
                                     (live (live-ends s))
                                     (again (outcome (lambda () (get-bytevector-some port)))))
                                (set! inside (list (cons 'raised (cddr first)) live again))
                                'proc-returned)))))))
            (append inside (list call)))))))

  (test-equal "raw: a producer's bad answer inside the port's read, a string, is an assertion violation from call-with-response-port with the call's context, its transfer cancelled by then, read inside PROC; every later read raises it again, and the call once PROC returns"
    (let ((av (list 'raised '(assertion call-with-response-port) (list 'exchange 'post 'the-url '() 1))))
      (list av 'ended av av))
    (guard (e (#t (list 'raised (describe e))))
      (with-session base-keys
        (lambda (s)
          (let* ((url (url-of o 'raw "/raw/mirror"))
                 (in-proc (vector #f))
                 (p (new-producer 4194304 65536 (lambda (n) (and (vector-ref in-proc 0) "text"))))
                 (inside '())
                 (call (outcome
                        (lambda ()
                          (call-with-response-port s 'post url 'body (thunk-of p) 'body-length 4194304
                            (lambda (r port)
                              (vector-set! in-proc 0 #t)
                              (let* ((first (drain port))
                                     (live (live-ends s))
                                     (again (outcome (lambda () (get-bytevector-some port)))))
                                (set! inside (list (cons 'raised (cddr first)) live again))
                                'proc-returned))))))
                 (named (lambda (x) (if (and (pair? x) (eq? (car x) 'raised))
                                        (map (lambda (part) (if (and (pair? part) (eq? (car part) 'exchange))
                                                                (list 'exchange (cadr part) (if (equal? (caddr part) url) 'the-url (caddr part))
                                                                      (cadddr part) (car (cddddr part)))
                                                                part))
                                             x)
                                        x))))
            (append (map named inside) (list (named call))))))))

  (test-equal "a producer's bad answer before PROC, during the wait for the head, is an assertion violation from the call, with its context, once the transfer is cancelled; an empty bytevector as well; PROC never called"
    (list (list 'raised '(assertion http-request) (list 'exchange 'post 'the-url '() 1))
          (list 'raised '(assertion call-with-response-port) (list 'exchange 'post 'the-url '() 1))
          'ended)
    (guard (e (#t (list 'raised (describe e))))
      (with-session base-keys
        (lambda (s)
          (let* ((url (url-of o 'raw "/raw/sink?key=sc-bad-head"))
                 (named (lambda (x) (if (and (pair? x) (eq? (car x) 'raised))
                                        (map (lambda (part) (if (and (pair? part) (eq? (car part) 'exchange))
                                                                (list 'exchange (cadr part) (if (equal? (caddr part) url) 'the-url (caddr part))
                                                                      (cadddr part) (car (cddddr part)))
                                                                part))
                                             x)
                                        x)))
                 (first (outcome (lambda () (http-post s url 'body (thunk-of (new-producer 10 10 (lambda (n) 'nonsense)))))))
                 (second (outcome (lambda () (call-with-response-port s 'post url
                                               'body (thunk-of (new-producer 10 10 (lambda (n) (make-bytevector 0))))
                                               (lambda (r p) 'proc-called))))))
            (list (named first) (named second) (live-ends s)))))))

  (test-equal "raw: a producer that reads the port it feeds, chunked, is refused: the read, an assertion violation from call-with-response-port, which the producer does not catch, is the call's failure for good, raised by PROC's read, by the next, and by the call once PROC returns"
    '((raised (assertion call-with-response-port)) (raised (assertion call-with-response-port))
      (raised (assertion call-with-response-port)) ended)
    (guard (e (#t (list 'raised (describe e))))
      (with-session base-keys
        (lambda (s)
          (let* ((the-port #f)
                 (p (new-producer 4194304 65536 (lambda (n) (and the-port (get-bytevector-some the-port)))))
                 (inside '())
                 (strip (lambda (x) (filter (lambda (part) (not (and (pair? part) (eq? (car part) 'exchange)))) x)))
                 ;; Chunked: with a length, a read let through would put
                 ;; echoed bytes past it, refused by the same who.
                 (call (outcome
                        (lambda ()
                          (call-with-response-port s 'post (url-of o 'raw "/raw/mirror") 'body (thunk-of p)
                            (lambda (r port)
                              (set! the-port port)
                              (let* ((first (drain port))
                                     (again (outcome (lambda () (get-bytevector-some port)))))
                                (set! inside (list (cons 'raised (cddr first)) again))
                                'proc-returned)))))))
            (append (map strip inside) (list (strip call) (live-ends s))))))))

  (test-equal "a producer's raise during the wait for the head leaves the call as raised, that object, PROC never called, and the transfer cancelled"
    '((raised non-condition boom) ended)
    (guard (e (#t (list 'raised (describe e))))
      (with-session base-keys
        (lambda (s)
          (list (outcome (lambda ()
                           (call-with-response-port s 'post (url-of o 'raw "/raw/sink?key=sc-raise-head")
                             'body (thunk-of (new-producer 1048576 65536 (lambda (n) (and (= n 2) (raise 'boom)))))
                             'body-length 1048576
                             (lambda (r p) 'proc-called))))
                (live-ends s))))))

  ;; --- a full-duplex server, an early 413, an early 303
  (for-each
   (lambda (face)
     (test-equal (string-append (symbol->string face) ": a full-duplex server, 4 MiB echoed as it arrives, sized and chunked: the producer fed throughout, inside the port's read too; the echo whole")
       '((sized (end 4194304 #f)) (chunked (end 4194304 #f)))
       (in-order
        (lambda (framing)
          (guard (e (#t (list framing 'raised (describe e))))
            (with-session base-keys
              (lambda (s)
                (call-with-response-port s 'post (url-of o face (if (eq? face 'h2) "/mirror" "/raw/mirror"))
                  'body (thunk-of (new-producer 4194304 65536)) 'body-length (and (eq? framing 'sized) 4194304)
                  'timeout-ms 20000
                  (lambda (r port) (list framing (drain port))))))))
        '(sized chunked))))
   '(raw raw-tls h2))

  (for-each
   (lambda (where)
     (let ((face (car where)) (path (cadr where)))
       (test-equal (string-append (symbol->string face) ": an early 413, answered once 65,536 bytes of a 4 MiB body arrived" (caddr where) ": PROC handed it, its body \"early 413\\n\" whole through the port, the producer fed there, the call ending well before its bound of 20 s")
         '(413 (text "early 413\n") ended-early)
         (guard (e (#t (list 'raised (describe e))))
           (with-session base-keys
             (lambda (s)
               (let* ((t0 (now-ms))
                      (seen (call-with-response-port s 'post (url-of o face path)
                              'body (thunk-of (new-producer 4194304 65536)) 'body-length 4194304 'timeout-ms 20000
                              (lambda (r port) (list (http-response-status r) (text-of port))))))
                 (append seen (list (if (< (- (now-ms) t0) 10000) 'ended-early (list 'took (- (now-ms) t0))))))))))))
   (list (list 'raw "/raw/answer-at?status=413&after=65536&close=0" ", kept alive")
         (list 'raw "/raw/answer-at?status=413&after=65536&close=1" ", with a close")
         (list 'raw-tls "/raw/answer-at?status=413&after=65536&close=0" ", kept alive")
         (list 'h2 "/answer-at?status=413&after=65536" "")))

  (for-each
   (lambda (where)
     (let ((face (car where)) (path (cadr where)))
       (test-equal (string-append (symbol->string face) ": an early 303, once 65,536 bytes of a 4 MiB body arrived" (caddr where) ": the hop cancelled at its head, its history entry's body and timings #f, the producer never given its whole body; followed, a get, whose body reaches PROC")
         (list (list 200 #f #f (list (list 303 #f #f '()))) '(end 1000 #f) 'never-whole)
         (guard (e (#t (list 'raised (describe e))))
           (with-session base-keys
             (lambda (s)
               (let* ((p (new-producer 4194304 65536))
                      (seen (call-with-response-port s 'post (url-of o face path)
                              'body (thunk-of p) 'body-length 4194304 'timeout-ms 20000
                              (lambda (r port) (list (summary r) (drain port))))))
                 (append seen (list (if (producer-ended p) 'ended-whole 'never-whole))))))))))
   (list (list 'raw (string-append "/raw/answer-at?status=303&after=65536&close=0&to=" (pct "/raw/pattern?key=sc-303&bytes=1000&chunk=1000")) ", kept alive")
         (list 'raw (string-append "/raw/answer-at?status=303&after=65536&close=1&to=" (pct "/raw/pattern?key=sc-303c&bytes=1000&chunk=1000")) ", with a close")
         (list 'h2 (string-append "/answer-at?status=303&after=65536&to=" (pct "/pattern/1000")) "")))

  ;; --- the drive's two sides
  (for-each
   (lambda (face)
     (test-equal (string-append (symbol->string face) ": the drive's throughput: a full-duplex echo of 16 MiB, whole, within 60 s, a bound the memory gate's Valgrind needs, which cannot tell the 0 ms waits apart: the next test holds them")
       '((end 16777216 #f) within-60-s)
       (guard (e (#t (list 'raised (describe e))))
         (with-session base-keys
           (lambda (s)
             (let* ((t0 (now-ms))
                    (seen (call-with-response-port s 'post (url-of o face (if (eq? face 'h2) "/mirror" "/raw/mirror"))
                            'body (thunk-of (new-producer 16777216 65536)) 'body-length 16777216
                            (lambda (r port) (drain port))))
                    (took (- (now-ms) t0)))
               (display (list 'stream-call-throughput face 'ms took)) (newline)
               (list seen (if (< took 60000) 'within-60-s took))))))))
   '(raw h2))

  (test-equal "raw: a side waits 0 ms while the other has just moved bytes: a producer's 1 MiB in 64 KiB pieces to the sink, each put followed by a response wait bounded by 0 ms, 16 or more of them, and by 10 ms too, the head's wait among them; counted by the drive's seam, alike under the memory gate's Valgrind"
    '(zero-waits-16-or-more full-waits-too whole-body)
    (guard (e (#t (list 'raised (describe e))))
      (with-session base-keys
        (lambda (s)
          (let* ((before (drive-stream-waits))
                 (r (http-post s (url-of o 'raw "/raw/sink?key=sc-zero-waits")
                               'body (thunk-of (new-producer 1048576 65536)) 'body-length 1048576))
                 (after (drive-stream-waits))
                 (zero (- (car after) (car before)))
                 (full (- (cadr after) (cadr before))))
            (list (if (>= zero 16) 'zero-waits-16-or-more (list 'zero-waits zero))
                  (if (> full 0) 'full-waits-too (list 'full-waits full))
                  (whole (sink-fields (latin-1 (http-response-body r))) 1048576)))))))

  (test-equal "raw: the drive's flag is cleared at a wait that finds nothing: a producer's 1,000 bytes ended at once, then a head 2 s later, the sink holding its reading: the process's CPU over the call is under 1000 ms, where a response side kept at 0 ms polls throughout; the body whole"
    '(under-1000-ms whole-body)
    (guard (e (#t (list 'raised (describe e))))
      (with-session base-keys
        (lambda (s)
          (collect-rendezvous)
          (let* ((c0 (cpu-ms))
                 (r (http-post s (url-of o 'raw "/raw/sink?key=sc-cpu&hold=2000")
                               'body (thunk-of (new-producer 2000 2000)) 'body-length 2000))
                 (used (- (cpu-ms) c0)))
            (display (list 'stream-call-idle-cpu 'ms used)) (newline)
            (list (if (< used 1000) 'under-1000-ms used)
                  (whole (sink-fields (latin-1 (http-response-body r))) 2000)))))))

  ;; --- a failure with no head after the producer was called (the slice's
  ;; review): the raw face's cut script ends the connection once 64 KiB of
  ;; the body have come, with nothing written. No head says libcurl asked;
  ;; the drive's own call of the producer counts it as called, so no retry
  ;; takes the call. The code moves between runs, 52 and 56 (the review's
  ;; probe, build/m6s3r/probe-reset-tree.log), so its class is held, not it.
  (test-equal "raw: a failure with no head, after the producer was called: under a policy that retries a post's send-receive failure, the call raises the transfer's own failure, perform-failed, of the send-receive class, one transfer, never retried; the producer called; the origin saw one upload"
    (list (list 'raised '(curl-transfer-error send-receive perform-failed)
                (list 'exchange 'post (url-of o 'raw "/raw/cut?key=sc-cut&after=65536") '() 1))
          'called "seen 1\n")
    (guard (e (#t (list 'raised (describe e))))
      (with-session (append base-keys (list 'retry (make-http-retry 'attempts 3 'backoff-ms 10 'jitter #f
                                                                    'methods '(post))))
        (lambda (s)
          (let* ((p (new-producer 1048576 65536))
                 (r (outcome (lambda () (http-post s (url-of o 'raw "/raw/cut?key=sc-cut&after=65536")
                                                   'body (thunk-of p) 'body-length 1048576))))
                 (seen (latin-1 (http-response-body (http-get s (url-of o 'http "/seen?key=sc-cut"))))))
            (list (map (lambda (part)
                         (if (and (pair? part) (eq? (car part) 'curl-transfer-error) (= (length part) 4))
                             (list-head part 3)
                             part))
                       r)
                  (if (> (producer-calls p) 0) 'called 'never-called)
                  seen))))))

  ;; --- the same after an early final head, on the held engine: the raw
  ;; face, armed in its cut mode, answers a 200 kept alive as it accepts
  ;; the connection, then ends it once 64 KiB of the body have come. On
  ;; 7.85.0 and 8.5.0 the head comes before libcurl's first ask, its bit #f;
  ;; libcurl asks after it, so http-request's final read calls the producer
  ;; first, and the failure there must count it as called.
  (test-equal "raw, held: a failure in http-request's final read after an early 200, the producer first called during that read: under a policy that retries a post's send-receive failure, the call raises the transfer's own failure, perform-failed, of the send-receive class, one transfer, never retried; the producer called; the hold made once"
    (list (list 'raised '(curl-transfer-error send-receive perform-failed)
                (list 'exchange 'post (url-of o 'raw "/raw/sink?key=sc-held-cut") '() 1))
          'called 1)
    (guard (e (#t (list 'raised (describe e))))
      (let ((s (new-http-session (make-curl-engine-holding-prereq 200)
                                 (session-defaults (list (cons 'proxy #f) (cons 'timeout-ms 20000)))
                                 20 #f (make-http-retry 'attempts 3 'backoff-ms 10 'jitter #f 'methods '(post)))))
        (dynamic-wind
          (lambda () #f)
          (lambda ()
            (let* ((armed (http-get s (url-of o 'raw "/raw/arm?status=200&mode=cut&after=65536")))
                   (p (new-producer 1048576 65536))
                   (r (outcome (lambda () (http-post s (url-of o 'raw "/raw/sink?key=sc-held-cut")
                                                     'body (thunk-of p) 'body-length 1048576)))))
              (list (map (lambda (part)
                           (if (and (pair? part) (eq? (car part) 'curl-transfer-error) (= (length part) 4))
                               (list-head part 3)
                               part))
                         r)
                    (if (> (producer-calls p) 0) 'called 'never-called)
                    (curl-engine-prereq-holds (http-session-engine s)))))
          (lambda () (http-session-close s))))))

  ;; --- no retry of a producer called
  (test-equal "raw: no retry takes a call whose producer counts as called: an early 503, once 65,536 bytes arrived, with a policy that retries a post's 503, is answered, its body \"early 503\\n\""
    '(503 "early 503\n" ())
    (guard (e (#t (list 'raised (describe e))))
      (with-session (append base-keys (list 'retry (make-http-retry 'backoff-ms 0 'jitter #f 'statuses '(503) 'methods '(post))))
        (lambda (s)
          (let ((r (http-post s (url-of o 'raw "/raw/answer-at?status=503&after=65536&close=1")
                              'body (thunk-of (new-producer 1048576 65536)) 'body-length 1048576)))
            (list (http-response-status r) (latin-1 (http-response-body r)) (http-response-history r)))))))

  ;; --- the http-request's whole read of a producer's response
  (test-equal "raw: http-request with a producer reads the final body whole: the seq script's 262,144 bytes of the pattern after the upload, its Sink header saying the upload arrived whole, the body's timings read"
    '(200 whole-body 262144 #f (name-lookup connect tls-handshake first-byte total))
    (guard (e (#t (list 'raised (describe e))))
      (with-session base-keys
        (lambda (s)
          (let ((r (http-put s (url-of o 'raw "/raw/seq?key=sc-seq&bytes=262144")
                             'body (thunk-of (new-producer 65536 16384)) 'body-length 65536)))
            (list (http-response-status r)
                  (whole (sink-fields (or (http-response-header r "Sink") "")) 65536)
                  (bytevector-length (http-response-body r))
                  (first-bad (http-response-body r) 0)
                  (map car (http-response-timings r))))))))

  ;; --- keyboard interrupts that escape inside the port's read, in a child
  ;; (tests/stream-call-escape.sps): each planted at a critical section's
  ;; end, where a pending one runs (traps.md), PROC catching it and reading
  ;; on. A, the producer's answer; B, the body's end, its response held
  ;; live until a read after the escape has fed; C, a refusal; D, a put; E,
  ;; produce!'s before thunk, the producer not yet entered.
  ;; Each case is shown short: A, D and E, (BYTES BAD RAISES); B, (TEXT
  ;; RAISES); C, its RAISES alone, the bytes echoed before the refusal moving
  ;; between runs; then the call's outcome, the producer's calls and its
  ;; calls after its end.
  (let ((short (lambda (d)
                 (if (and (pair? d) (eq? (car d) 'case) (= (length d) 8))
                     (let ((letter (list-ref d 1)) (drained (list-ref d 4)))
                       (list 'case letter (list-ref d 2) (list-ref d 3)
                             (if (and (eq? letter 'C) (list? drained) (= (length drained) 3)) (caddr drained) drained)
                             (list-ref d 5) (list-ref d 6) (list-ref d 7)))
                     d)))
        (av '(assertion call-with-response-port)))
    (test-equal "a keyboard interrupt that escapes inside the port's read loses nothing, in a child, 3 runs: A, as the producer's answer leaves its critical after thunk, before the drive holds it: the echo whole, 17 calls; B, as curl-token-end-body!'s section ends: the producer never called after its eof; C, as a refusal's cancel ends: the refusal is the call's for good, raised by every read after and by the call; D, as a put's section ends, the piece committed: never put twice, the echo whole; E, as produce!'s before thunk ends, the producer not entered: the transfer not cancelled, the echo whole, 17 calls; the controls, whose handler returns, alike but for the raise; every count zero"
      (list 0
            (apply append
                   (map (lambda (run)
                          (list (list 'case 'A run 'escapes '(1048576 #f (interrupted)) '(returned proc-returned) 17 0)
                                (list 'case 'A run 'returns '(1048576 #f ()) '(returned proc-returned) 17 0)
                                (list 'case 'B run 'escapes '("early 200\n" (interrupted)) '(returned proc-returned) 17 0)
                                (list 'case 'B run 'returns '("early 200\n" ()) '(returned proc-returned) 17 0)
                                (list 'case 'C run 'escapes (list 'interrupted av av av av) (list 'raised av) 5 0)
                                (list 'case 'C run 'returns (list av av av av av) (list 'raised av) 5 0)
                                (list 'case 'D run 'escapes '(1048576 #f (interrupted)) '(returned proc-returned) 17 0)
                                (list 'case 'D run 'returns '(1048576 #f ()) '(returned proc-returned) 17 0)
                                (list 'case 'E run 'escapes '(1048576 #f (interrupted)) '(returned proc-returned) 17 0)
                                (list 'case 'E run 'returns '(1048576 #f ()) '(returned proc-returned) 17 0)))
                        '(1 2 3)))
            zero-counts)
      (let ((r (run-child "tests/stream-call-escape.sps" (url-of o 'raw "") "3")))
        (list (car r)
              (map short (filter (lambda (d) (and (pair? d) (eq? (car d) 'case))) (cadr r)))
              (let ((c (filter (lambda (d) (and (pair? d) (eq? (car d) 'counts))) (cadr r))))
                (if (pair? c) (cadr (car c)) r))))))

  ;; --- the thread rule (the M6 plan, section 3.8)
  (test-equal "the thread rule: the producer, PROC and every read of the port run on this thread, the caller's, never the engine's"
    '(this-thread this-thread (end 1048576 #f))
    (guard (e (#t (list 'raised (describe e))))
      (with-session base-keys
        (lambda (s)
          (let* ((engine-thread (curl-engine-thread (http-session-engine s)))
                 (p (new-producer 1048576 65536))
                 (here? (lambda (t) (and (eqv? t main-thread) (not (eqv? t engine-thread))))))
            (call-with-response-port s 'post (url-of o 'raw "/raw/mirror") 'body (thunk-of p) 'body-length 1048576
              (lambda (r port)
                (let ((proc-thread (get-thread-id)) (seen (drain port)))
                  (list (if (for-all here? (producer-threads p)) 'this-thread (producer-threads p))
                        (if (here? proc-thread) 'this-thread proc-thread)
                        seen)))))))))

  ;; --- libcurl's HTTP/2 3xx that never ends while a body is owed
  ;; (ADR-0031, amended 2026-10-31): on 8.20.0 and 8.23.0 a 3xx over HTTP/2
  ;; that arrives before the body is sent whole never ends but at the
  ;; call's bound; 7.85.0, 8.5.0 and Apple's 8.7.1 end it with the 3xx. Each
  ;; row is the slice's measurement (research/m6/slice3/, verify/), 8.7.1's
  ;; the Mac's run (research/m6/slice3-build/results/). A final 303, with
  ;; redirects #f, its Location kept: (PRODUCER WHOLE), each 303 and its
  ;; body, or 28 at the bound.
  (let ((rows '(("7.85.0" (303 (text "early 303\n")) (303 "early 303\n"))
                ("8.5.0" (303 (text "early 303\n")) (303 "early 303\n"))
                ("8.7.1" (303 (text "early 303\n")) (303 "early 303\n"))
                ("8.20.0" (303 (raised 28 http-timeout)) (raised 28 http-timeout))
                ("8.23.0" (303 (raised 28 http-timeout)) (raised 28 http-timeout))))
        (path (string-append "/answer-at?status=303&after=65536&to=" (pct "/pattern/1000")))
        (short (lambda (r)
                 (cond ((and (pair? r) (eq? (car r) 'raised))
                        (let ((d (if (string? (cadr r)) (cddr r) (cdr r))))
                          (list 'raised
                                (let ((t (find (lambda (x) (and (pair? x) (eq? (car x) 'curl-transfer-error))) d)))
                                  (if t (cadddr t) d))
                                (if (find (lambda (x) (and (pair? x) (eq? (car x) 'http-timeout))) d) 'http-timeout 'no-timeout))))
                       (else r)))))
    (test-equal (string-append "h2, by version, on " version-text
                               ": a final 303 over HTTP/2, answered once 65,536 bytes of a 4 MiB body arrived, redirects #f: through call-with-response-port with a producer, PROC handed the 303, its body read through the port; through http-request with a whole body; 28 at the bound of 3000 ms, &http-timeout, on 8.20.0 and 8.23.0, the 303 and its body on 7.85.0, 8.5.0 and 8.7.1; a libcurl with no row fails, showing what it measured")
      (let ((row (and (string? version) (assoc version rows))))
        (if row (cdr row) (list 'a-row-for version)))
      (let* ((measured
              (guard (e (#t (list 'raised (describe e))))
                (with-session (append base-keys (list 'redirects #f))
                  (lambda (s)
                    (list (let ((seen (outcome (lambda ()
                                                 (call-with-response-port s 'post (url-of o 'h2 path)
                                                   'body (thunk-of (new-producer 4194304 65536)) 'body-length 4194304
                                                   'timeout-ms 3000
                                                   (lambda (r port)
                                                     (let ((t (text-of port)))
                                                       (list (http-response-status r)
                                                             (if (eq? (car t) 'raised) (short (cons 'raised (cddr t))) t)))))))))
                            (if (eq? (car seen) 'returned) (cadr seen) (short seen)))
                          (let ((seen (outcome (lambda ()
                                                 (let ((r (http-post s (url-of o 'h2 path) 'body (pattern-piece 0 4194304)
                                                                     'timeout-ms 3000)))
                                                   (list (http-response-status r) (latin-1 (http-response-body r))))))))
                            (if (eq? (car seen) 'returned) (cadr seen) (short seen))))))))
             (row (and (string? version) (assoc version rows))))
        (if row measured (list 'no-row-for version 'measured measured)))))

  ;; --- a head before libcurl's first ask, on the held engine (the M6
  ;; plan, section 6.1): the raw face, armed, answers the next connection as
  ;; it accepts it; the engine holds the prerequest callable 200 ms once
  ;; connected, so the answer is read before libcurl's first ask on 7.85.0
  ;; and 8.5.0, whose head's bit is then #f; 8.7.1, 8.20.0 and 8.23.0 ask
  ;; with the request's head, once the hold ends and before the head is
  ;; read, and their bit is #t. 8.7.1's row is the Mac's run; its 200 read
  ;; after-the-head once, and is held to either, as 8.20.0's and 8.23.0's
  ;; are, since a row from one run cannot show a cell that splits.
  (let ((rows '(("7.85.0" (followed 200 whole-body ((307 #f #f ()))) (200 "early 200\n" after-the-head))
                ("8.5.0" (followed 200 whole-body ((307 #f #f ()))) (200 "early 200\n" after-the-head))
                ("8.7.1" (body-not-replayable 307) (200 "early 200\n" either))
                ("8.20.0" (body-not-replayable 307) (200 "early 200\n" either))
                ("8.23.0" (body-not-replayable 307) (200 "early 200\n" either)))))
    (test-equal (string-append "raw, held, by version, on " version-text
                               ": a 307 written as the connection is accepted, before libcurl's first ask on 7.85.0 and 8.5.0, four times: the hop cancelled at its head, the producer never called, the 307 followed with the body, which the sink reads whole, the producer's first call in the next request; on 8.7.1, 8.20.0 and 8.23.0, which ask with the head, body-not-replayable; and a 200 kept alive, so written, fed when libcurl asks after it on 7.85.0 and 8.5.0, its first call after PROC has the head, ending 200 on every libcurl; a libcurl with no row fails, showing what it measured")
      (let ((row (and (string? version) (assoc version rows))))
        (if row (list (make-list-of 4 (cadr row)) (caddr row)) (list 'a-row-for version)))
      (let* ((measured
              (guard (e (#t (list 'raised (describe e))))
                (list
                 ;; Four times: on 8.20.0 and 8.23.0 the bit alone counts
                 ;; the producer as called only when the head is read before
                 ;; the drive's next step calls it, about one run in two.
                 (in-order
                  (lambda (n)
                    (with-held-session
                      (lambda (s)
                        (let* ((key (string-append "sc-held-307-" (number->string n)))
                               (armed (http-get s (url-of o 'raw (string-append "/raw/arm?status=307&to=" (pct (string-append "/raw/sink?key=" key))))))
                               (p (new-producer 2000 1000)))
                          (guard (e ((http-redirect-error? e)
                                     (list (http-redirect-error-reason e) (http-response-status (http-redirect-error-response e))))
                                    (#t (list 'raised (described e))))
                            (call-with-response-port s 'post (url-of o 'raw "/raw/sink?key=sc-held-first") 'body (thunk-of p)
                              'body-length 2000
                              (lambda (r port)
                                (list 'followed (http-response-status r) (whole (sink-fields (cadr (text-of port))) 2000)
                                      (map summary (http-response-history r))))))))))
                  '(1 2 3 4))
                 (with-held-session
                   (lambda (s)
                     (let* ((armed (http-get s (url-of o 'raw "/raw/arm?status=200&mode=keep")))
                            (p (new-producer 2000 1000))
                            (calls-at-head #f))
                       (call-with-response-port s 'post (url-of o 'raw "/raw/sink?key=sc-held-200") 'body (thunk-of p)
                         'body-length 2000 'timeout-ms 10000
                         (lambda (r port)
                           (set! calls-at-head (producer-calls p))
                           (let ((t (text-of port)))
                             (list (http-response-status r) (if (eq? (car t) 'text) (cadr t) t)
                                   (if (= calls-at-head 0) 'after-the-head (list 'before-the-head calls-at-head))))))))))))
             (row (and (string? version) (assoc version rows))))
        (if row
            ;; A cell whose row says either holds its status and body alone.
            (let ((r (cdr row)))
              (list (car measured)
                    (if (and (eq? (caddr (cadr r)) 'either) (list? (cadr measured)) (= (length (cadr measured)) 3))
                        (list (car (cadr measured)) (cadr (cadr measured)) 'either)
                        (cadr measured))))
            (list 'no-row-for version 'measured measured)))))

  (test-equal "every count is back to zero once the scenarios' sessions have closed"
    zero-counts
    (begin (wait-for (lambda () (equal? (native-counts) zero-counts)) 10000)
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

(test-equal "every count is zero at the end"
  zero-counts
  (begin (wait-for (lambda () (equal? (native-counts) zero-counts)) 10000)
         (native-counts)))

(test-end "stream-call")

(exit (suite-exit-status runner))
