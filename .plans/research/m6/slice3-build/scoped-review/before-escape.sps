#!r6rs
;;; A child of tests/test-stream-call.sps: keyboard interrupts that escape
;;; inside the port's read, at the ends of critical sections, where a
;;; pending one runs (traps.md), with PROC catching each escape and reading
;;; on (the M6 plan, section 3.5; the slice's review, build/m6s3r/).
;;;
;;;   stream-call-escape.sps RAW RUNS
;;;
;;; RAW is the raw face, http://ADDRESS:PORT. Each case, for each run and
;;; each HANDLER, escapes (the handler raises interrupted) or returns (the
;;; control), on a session of its own, a 1 MiB body in 64 KiB pieces, the
;;; plant made by the producer once PROC runs, a thread holding a mutex
;;; that blocks this one inside a critical section, sending SIGINT 100 ms
;;; after this one says it is about to block, and letting go 100 ms on:
;;;
;;;   A  the producer's answer: the gate seam, run in produce!'s critical
;;;      after thunk once the producer has answered its fifth piece. A
;;;      chunked echo, /raw/mirror, read back by PROC.
;;;   B  the body's end: the request stream's mutex held, by the low level's
;;;      call-with-upload-held on the call's token, from the producer's call
;;;      that answers the eof object, so curl-token-end-body! blocks inside
;;;      its section. A sized body to /raw/answer-at, a 200 kept alive once
;;;      64 KiB arrived, so the transfer waits for the body's end, and the
;;;      port's next read feeds.
;;;   C  a refusal: the engine's mutex held, by call-with-engine-held, from
;;;      the producer's call that answers a string, so the refusal's cancel
;;;      blocks inside its section. A chunked echo.
;;;   D  a put: the engine's mutex held from the producer's call that
;;;      answers its fifth piece, so that piece's put blocks inside its
;;;      section, and commits. A chunked echo.
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
        (only (http-client private drive) drive-produce-gate-set! drive-last-token drive-before-gate-set!)
        (only (curl private engine) call-with-engine-held call-with-upload-held)
        (curl private counters))

(define args (command-line-arguments))
(define raw (car args))
(define runs (string->number (cadr args)))

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

;; plant! : ((-> Void) -> Any) -> (-> Void)
;; Forks a thread that runs HOLD, given a thunk to run while it holds; that
;; thread, once holding, waits until this one says it is about to block,
;; then 100 ms, sends SIGINT, which Linux offers the main thread first, then
;; 100 ms on lets go. Answers the thunk this thread calls just before it
;; blocks.
(define (plant! hold)
  (let ((mx (make-mutex)) (held #f) (going #f))
    (fork-thread
     (lambda ()
       (hold (lambda ()
               (with-mutex mx (set! held #t))
               (let loop () (unless (with-mutex mx going) (sleep (ms 1)) (loop)))
               (sleep (ms 100))
               (kill (getpid) 2)
               (sleep (ms 100))))))
    (let wait () (unless (with-mutex mx held) (sleep (ms 1)) (wait)))
    (lambda () (with-mutex mx (set! going #t)))))

;; one-case : Symbol Natural Symbol -> Void
(define (one-case letter run handler)
  (show (list 'start letter run handler))
  (let* ((s (make-http-session 'proxy #f 'timeout-ms 20000))
         (engine (http-session-engine s))
         (in-proc #f) (armed #f) (calls 0) (given 0) (after-eof 0) (ended #f))
    (define (producer)
      (set! calls (+ calls 1))
      (cond
        (ended (set! after-eof (+ after-eof 1)) (eof-object))
        ((>= given total)
         (set! ended #t)
         (when (and (eq? letter 'B) in-proc (not armed))
           (set! armed #t)
           ((plant! (lambda (thunk) (call-with-upload-held (drive-last-token) thunk)))))
         (eof-object))
        (else
         (let ((p (pattern-piece given piece)))
           (set! given (+ given piece))
           (if (and in-proc (not armed) (>= given (* 5 piece)) (memq letter '(A C D E)))
               (begin
                 (set! armed #t)
                 (case letter
                   ;; Held with interrupts off, as the low level's seams
                   ;; hold: a holder that sleeps with them on can join a
                   ;; collection while this thread, blocked on the mutex
                   ;; inside a critical section, stays active, and the two
                   ;; deadlock (traps.md): 1 run in 48 on 8.5.0 did.
                   ((A) (let* ((mx (make-mutex))
                               (go (plant! (lambda (thunk) (critical-section (with-mutex mx (thunk)))))))
                          (drive-produce-gate-set! (lambda () (go) (with-mutex mx #t)))
                          p))
                   ((E) (let* ((mx (make-mutex))
                               (go (plant! (lambda (thunk) (critical-section (with-mutex mx (thunk)))))))
                          (drive-before-gate-set! (lambda () (go) (with-mutex mx #t)))
                          p))
                   ((C) ((plant! (lambda (thunk) (call-with-engine-held engine thunk)))) "text")
                   (else ((plant! (lambda (thunk) (call-with-engine-held engine thunk)))) p)))
               p)))))
    (keyboard-interrupt-handler
     (lambda () (when (eq? handler 'escapes) (raise 'interrupted))))
    (let* ((drained #f)
           (url (if (eq? letter 'B)
                    (string-append raw "/raw/answer-at?status=200&after=65536&close=0")
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

(do ((run 1 (+ run 1))) ((> run runs))
  (for-each (lambda (letter)
              (one-case letter run 'escapes)
              (one-case letter run 'returns))
            (map string->symbol (cddr args))))
(collect-rendezvous)
(show (list 'counts (native-counts)))
