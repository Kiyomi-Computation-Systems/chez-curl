#!r6rs
;;; A child of tests/test-stream-call.sps: keyboard interrupts that escape
;;; inside the port's read, at the ends of critical sections, where a pending
;;; one runs, with PROC catching each escape and reading on.
;;;
;;;   stream-call-escape.sps RAW RUNS [LETTER ...]
;;;
;;; RAW is the raw face, http://ADDRESS:PORT; LETTERs name the cases to run,
;;; every one when none is named. Each case, for each run and
;;; each HANDLER, escapes (the handler raises interrupted) or returns (the
;;; control), on a session of its own, a 1 MiB body in 64 KiB pieces, the
;;; plant made by the producer once PROC runs: for A and E, a gate of the
;;; drive's, inside its critical section, where this thread sends itself
;;; SIGINT; for B, C and D, inside a section of the low level's, a thread
;;; holding the mutex that blocks this one there, sending SIGINT 100 ms
;;; after it holds, and letting go 100 ms on:
;;;
;;;   A  the producer's answer: the gate seam, run in produce!'s critical
;;;      after thunk once the producer has answered its fifth piece. A
;;;      chunked echo, /raw/mirror, read back by PROC.
;;;   B  the body's end: the request stream's mutex held, by the low level's
;;;      call-with-upload-held on the call's token, from the producer's call
;;;      that answers the eof object, so curl-token-end-body! blocks inside
;;;      its section. A sized body to /raw/answer-at, a 200 kept alive once
;;;      64 KiB arrived, its last byte held (hold=KEY), so the transfer is
;;;      still live after the body's end: the planting thread lets that byte
;;;      go, by /raw/release, only once the response side has waited twice
;;;      more after the escape, so the port's next read has fed by then.
;;;      With the byte written at once, that read often found the transfer
;;;      done, fed nothing, and a producer called after its eof showed in
;;;      14 runs of 20.
;;;   C  a refusal: the engine's mutex held, by call-with-engine-held, from
;;;      the producer's call that answers a string, so the refusal's cancel
;;;      blocks inside its section. A chunked echo.
;;;   D  a put: the engine's mutex held from the producer's call that
;;;      answers its fifth piece, so that piece's put blocks inside its
;;;      section, and commits. A chunked echo.
;;;   E  before the producer: the before gate seam, run in produce!'s
;;;      critical before thunk at the call after the fifth piece, so the
;;;      interrupt runs as that section ends, before the producer is
;;;      entered. A chunked echo.
;;;
;;; Prints (start LETTER RUN HANDLER) as each case starts, so a case that
;;; hangs is named, then one datum a case:
;;;
;;;   (case LETTER RUN HANDLER DRAINED CALL CALLS AFTER-EOF)
;;;
;;; DRAINED (BYTES BAD RAISES), what PROC read by get-bytevector-some, BAD
;;; the first offset that is not the pattern's or #f, RAISES each read's
;;; raise, up to 5; or, for B, (TEXT RAISES); CALL the call's outcome,
;;; (returned VALUE) or (raised WHAT); CALLS and AFTER-EOF the producer's
;;; calls and its calls after its eof. Then (counts COUNTS) once every
;;; session is closed.
(import (chezscheme)
        (curl)
        (http-client)
        (only (http-client private call) http-session-engine)
        (only (http-client private drive) drive-produce-gate-set! drive-before-gate-set!
              drive-last-token drive-last-token-arm! drive-stream-waits)
        (only (curl private engine) call-with-engine-held call-with-upload-held)
        (curl private counters))

(define args (command-line-arguments))
(define raw (car args))
(define runs (string->number (cadr args)))
;; letters : (Listof Symbol)
;; The cases to run, A to E, every one when none is named.
(define letters (if (pair? (cddr args)) (map string->symbol (cddr args)) '(A B C D E)))

(define kill (foreign-procedure "kill" (int int) int))
(define getpid (foreign-procedure "getpid" () int))

(define (show datum) (write datum) (newline) (flush-output-port (current-output-port)))
(define (ms n) (make-time 'time-duration (* n 1000000) 0))

(define total 1048576)
(define piece 65536)

;; pattern-piece : Natural Natural -> Bytevector
(define (pattern-piece at n)
  (let ((bv (make-bytevector n)))
    (do ((i 0 (+ i 1))) ((= i n) bv)
      (bytevector-u8-set! bv i (mod (+ at i) 251)))))

;; first-bad : Bytevector Natural -> (U Natural #f)
(define (first-bad bytes at)
  (let ((n (bytevector-length bytes)))
    (let loop ((i 0))
      (cond ((= i n) #f)
            ((not (= (bytevector-u8-ref bytes i) (mod (+ at i) 251))) (+ at i))
            (else (loop (+ i 1)))))))

;; what : Any -> Any
;; A raised object, short: interrupted; (assertion WHO); (transfer REASON);
;; (request FIELD REASON); or (other TEXT).
(define (what e)
  (cond ((eq? e 'interrupted) 'interrupted)
        ((http-request-error? e) (list 'request (http-request-error-field e) (http-request-error-reason e)))
        ((curl-transfer-error? e) (list 'transfer (curl-transfer-error-reason e)))
        ((assertion-violation? e) (list 'assertion (and (who-condition? e) (condition-who e))))
        (else (list 'other (call-with-string-output-port (lambda (p) (display e p)))))))

;; drain : Port Boolean -> List
;; PORT read to its end by get-bytevector-some, each raise noted and the
;; reading gone on with, up to 5 raises: (BYTES BAD RAISES), or, TEXT?,
;; (TEXT RAISES).
(define (drain port text?)
  (let loop ((n 0) (bad #f) (pieces '()) (raises '()))
    (let ((got (guard (e (#t (list 'raised (what e)))) (get-bytevector-some port))))
      (cond ((or (eof-object? got) (>= (length raises) 5))
             (if text?
                 (list (utf8->string (apply bytevector-append-all (reverse pieces))) (reverse raises))
                 (list n bad (reverse raises))))
            ((and (pair? got) (eq? (car got) 'raised)) (loop n bad pieces (cons (cadr got) raises)))
            (else (loop (+ n (bytevector-length got)) (or bad (first-bad got n)) (cons got pieces) raises))))))

;; bytevector-append-all : Bytevector ... -> Bytevector
(define (bytevector-append-all . bvs)
  (let ((out (make-bytevector (apply + (map bytevector-length bvs)))))
    (let loop ((bvs bvs) (at 0))
      (if (null? bvs)
          out
          (begin (bytevector-copy! (car bvs) 0 out at (bytevector-length (car bvs)))
                 (loop (cdr bvs) (+ at (bytevector-length (car bvs)))))))))

;; waits-total : -> Natural
;; The response side's waits, every streamed call's, by drive-stream-waits.
(define (waits-total) (apply + (drive-stream-waits)))

;; plant! : ((-> Void) -> Any) [(Natural -> Any)] -> Void
;; For a section of the low level's, which no gate reaches: forks a thread
;; that runs HOLD, given a thunk to run while it holds, a hold the low
;; level's seams make with interrupts off; that thunk sleeps 100 ms, sends
;; SIGINT, which Linux offers the main thread first, sleeps 100 ms more,
;; reads waits-total, this thread blocked meanwhile, and lets go; then the
;; thread calls AFTER, when given, with that count. This thread waits,
;; with interrupts on, until the hold is made, then returns, to block on
;; it inside the section. The holder waits on nothing this thread does: a
;; holder that waited inside its section for this thread to go on
;; deadlocked whenever a collection came between, this thread stopped at
;; the collection's rendezvous and the rendezvous waiting for the holder;
;; case E's long window hung 1 run in 8.
(define (plant! hold . after)
  (let ((mx (make-mutex)) (held #f) (count 0))
    (fork-thread
     (lambda ()
       (hold (lambda ()
               (with-mutex mx (set! held #t))
               (sleep (ms 100))
               (kill (getpid) 2)
               (sleep (ms 100))
               (set! count (waits-total))))
       (when (pair? after) ((car after) count))))
    (let wait () (unless (with-mutex mx held) (sleep (ms 1)) (wait)))))

;; self-signal! : -> Void
;; For a gate, run inside the drive's own critical section: SIGINT sent by
;; this thread to its process, which Linux gives the sender, before kill
;; returns; Chez holds the keyboard interrupt until the section ends,
;; where it runs. No second thread, so nothing to deadlock.
(define (self-signal!) (kill (getpid) 2))

;; release-after-two! : String -> (Natural -> Void)
;; Given the count of waits when this thread let go: waits, up to 10 s,
;; until the response side has waited twice more, so a feed! has run
;; between, then lets KEY's held byte go by /raw/release, on a session of
;; its own. A raise is dropped: a forked thread that raises dies naming
;; no case, and the case then shows the byte never came.
(define (release-after-two! key)
  (lambda (count)
    (let wait ((left 10000))
      (unless (or (>= (waits-total) (+ count 2)) (<= left 0))
        (sleep (ms 1))
        (wait (- left 1))))
    (guard (e (#t #f))
      (let ((s (make-http-session 'proxy #f 'timeout-ms 10000)))
        (dynamic-wind
          (lambda () #f)
          (lambda () (http-get s (string-append raw "/raw/release?key=" key)))
          (lambda () (http-session-close s)))))))

;; one-case : Symbol Natural Symbol -> Void
(define (one-case letter run handler)
  (show (list 'start letter run handler))
  (let* ((s (make-http-session 'proxy #f 'timeout-ms 20000))
         (engine (http-session-engine s))
         (hold-key (string-append "esc-" (symbol->string letter) "-" (number->string run) "-"
                                  (symbol->string handler)))
         (in-proc #f) (armed #f) (calls 0) (given 0) (after-eof 0) (ended #f))
    (define (producer)
      (set! calls (+ calls 1))
      (cond
        (ended (set! after-eof (+ after-eof 1)) (eof-object))
        ((>= given total)
         (set! ended #t)
         (when (and (eq? letter 'B) in-proc (not armed))
           (set! armed #t)
           (plant! (lambda (thunk) (call-with-upload-held (drive-last-token) thunk))
                   (release-after-two! hold-key)))
         (eof-object))
        (else
         (let ((p (pattern-piece given piece)))
           (set! given (+ given piece))
           (if (and in-proc (not armed) (>= given (* 5 piece)) (memq letter '(A C D E)))
               (begin
                 (set! armed #t)
                 (case letter
                   ((A) (drive-produce-gate-set! self-signal!) p)
                   ((E) (drive-before-gate-set! self-signal!) p)
                   ((C) (plant! (lambda (thunk) (call-with-engine-held engine thunk))) "text")
                   (else (plant! (lambda (thunk) (call-with-engine-held engine thunk))) p)))
               p)))))
    (keyboard-interrupt-handler
     (lambda () (when (eq? handler 'escapes) (raise 'interrupted))))
    (let* ((drained #f)
           (url (if (eq? letter 'B)
                    (string-append raw "/raw/answer-at?status=200&after=65536&close=0&hold=" hold-key)
                    (string-append raw "/raw/mirror")))
           (call (guard (e (#t (list 'raised (what e))))
                   (list 'returned
                         (call-with-response-port s 'post url 'body producer
                           'body-length (and (eq? letter 'B) total)
                           (lambda (r port)
                             (set! in-proc #t)
                             (set! drained (drain port (eq? letter 'B)))
                             'proc-returned))))))
      (keyboard-interrupt-handler (lambda () #f))
      (drive-produce-gate-set! #f)
      (drive-before-gate-set! #f)
      (http-session-close s)
      (show (list 'case letter run handler drained call calls after-eof)))))

;; The seam records the call's token only while armed: B holds that token's
;; request stream.
(drive-last-token-arm! #t)

(do ((run 1 (+ run 1))) ((> run runs))
  (for-each (lambda (letter)
              (one-case letter run 'escapes)
              (one-case letter run 'returns))
            letters))
(collect-rendezvous)
(show (list 'counts (native-counts)))
