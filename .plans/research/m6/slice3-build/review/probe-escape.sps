#!r6rs
;;; Review probe (build/m6s3r): two windows in the streamed drive where a
;;; keyboard interrupt made pending inside a critical section runs as that
;;; section ends (traps.md), and PROC catches the escape and reads on.
;;;
;;;   A. produce!'s critical after thunk, once the producer has returned its
;;;      piece and before produce-and-put! holds it. Planted by a gate (a
;;;      probe seam in this mutant's drive.sls) that blocks inside the after
;;;      thunk on a mutex another thread holds, while that thread sends
;;;      SIGINT. A chunked 1 MiB body to /raw/mirror, read back by PROC.
;;;   B. curl-token-end-body!'s critical section, before produce-and-put!
;;;      sets the phase ended. Planted with the low level's own seam,
;;;      call-with-upload-held, on the leg's token (read by a read-only probe
;;;      seam). A sized 1 MiB body to /raw/mirror.
;;;
;;; Each case runs with the handler raising interrupted (escapes) and
;;; returning (returns), the control. Prints one datum per case.
(import (chezscheme)
        (curl-testing)
        (curl)
        (http-client)
        (only (http-client private drive) drive-produce-gate-set! drive-last-token)
        (only (curl private engine) call-with-upload-held))

(define kill (foreign-procedure "kill" (int int) int))
(define getpid (foreign-procedure "getpid" () int))
(define (show datum) (write datum) (newline) (flush-output-port (current-output-port)))
(define (ms n) (make-time 'time-duration (* n 1000000) 0))

(define (pattern-piece at n)
  (let ((bv (make-bytevector n)))
    (do ((i 0 (+ i 1))) ((= i n) bv)
      (bytevector-u8-set! bv i (mod (+ at i) 251)))))

(define (first-bad bytes at)
  (let ((n (bytevector-length bytes)))
    (let loop ((i 0))
      (cond ((= i n) #f)
            ((not (= (bytevector-u8-ref bytes i) (mod (+ at i) 251))) (+ at i))
            (else (loop (+ i 1)))))))

;; drain : Port -> (List Natural (U Natural #f) (Listof Any))
;; PORT read to its end by get-bytevector-some; a raise is noted and the
;; reading goes on, up to 5 raises.
(define (drain port)
  (let loop ((n 0) (bad #f) (raises '()))
    (let ((got (guard (e (#t (list 'raised (if (condition? e)
                                               (list (and (who-condition? e) (condition-who e))
                                                     (and (message-condition? e) (condition-message e)))
                                               e))))
                 (get-bytevector-some port))))
      (cond ((eof-object? got) (list n bad (reverse raises)))
            ((and (pair? got) (eq? (car got) 'raised))
             (if (>= (length raises) 5)
                 (list n bad (reverse (cons got raises)))
                 (loop n bad (cons got raises))))
            (else (loop (+ n (bytevector-length got)) (or bad (first-bad got n)) raises))))))

;; plant! : (-> Void) -> (-> Void)
;; Forks a thread that runs HOLD, a procedure given a thunk to run while
;; holding; that thread, once held, waits for this one to say it is about to
;; block, sleeps 100 ms, sends SIGINT, sleeps 100 ms, and lets go. Answers
;; the thunk this thread calls just before it blocks.
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

(define total 1048576)
(define piece 65536)

;; run-case : Symbol Symbol Origin -> Void
(define (run-case which handler o)
  (let* ((f (origin-face o 'raw))
         (url (string-append "http://" (car f) ":" (number->string (cdr f)) "/raw/mirror"))
         (in-proc #f) (armed #f) (calls 0) (given 0) (after-eof 0) (ended #f))
    (define (producer)
      (set! calls (+ calls 1))
      (cond
        (ended (set! after-eof (+ after-eof 1)) (eof-object))
        ((>= given total)
         (set! ended #t)
         (when (and (eq? which 'B) in-proc (not armed))
           (set! armed #t)
           (let ((go (plant! (lambda (thunk) (call-with-upload-held (drive-last-token) thunk)))))
             (go)))
         (eof-object))
        (else
         (let ((p (pattern-piece given piece)))
           (set! given (+ given piece))
           (when (and (eq? which 'A) in-proc (not armed) (>= given (* 4 piece)))
             (set! armed #t)
             (let* ((mx (make-mutex))
                    (go (plant! (lambda (thunk) (with-mutex mx (thunk))))))
               (drive-produce-gate-set! (lambda () (go) (with-mutex mx #t)))))
           p))))
    (keyboard-interrupt-handler
     (lambda () (when (eq? handler 'escapes) (raise 'interrupted))))
    (let* ((s (make-http-session 'proxy #f 'timeout-ms 20000))
           (seen (guard (e (#t (list 'call-raised (if (condition? e) (list (and (who-condition? e) (condition-who e)) (and (message-condition? e) (condition-message e))) e))))
                   (call-with-response-port s 'post url 'body producer
                     'body-length (and (eq? which 'B) total)
                     (lambda (r port) (set! in-proc #t) (drain port))))))
      (keyboard-interrupt-handler (lambda () #f))
      (http-session-close s)
      (show (list 'case which handler 'armed armed 'drained seen 'producer-calls calls
                  'given given 'after-eof after-eof)))))

(define runs (let ((a (command-line-arguments))) (if (pair? a) (string->number (car a)) 3)))

(call-with-origin
 (lambda (o)
   (do ((i 0 (+ i 1))) ((= i runs))
     (run-case 'A 'escapes o)
     (run-case 'A 'returns o)
     (run-case 'B 'escapes o)
     (run-case 'B 'returns o))))
