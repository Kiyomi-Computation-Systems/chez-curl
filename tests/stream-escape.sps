#!r6rs
;;; A child of tests/test-stream.sps: the take's escape (the M6 plan,
;;; sections 3.5 and 4.1). A keyboard interrupt made pending while a take's
;;; look waits for the stream's mutex inside its critical section runs as
;;; that section ends; a handler that escapes there must lose no piece, and
;;; one that returns none either (traps.md: planting an escape at a
;;; section's end).
;;;
;;;   stream-escape.sps BASE
;;;
;;; BASE is the raw face, http://ADDRESS:PORT. For each case, OP next-piece,
;;; some (get-bytevector-some of the token's port) or u8 (get-u8 of it), and
;;; HANDLER escapes or returns, it streams /raw/pattern 15 bytes, 5 a write,
;;; and waits until all are buffered, three pieces. Another thread holds the
;;; stream's mutex, waits until this one is about to take, then 100 ms, then
;;; sends SIGINT to the process, which Linux offers the main thread first,
;;; and 100 ms on lets the mutex go. This thread's handler raises
;;; interrupted, or returns; the take is the first read, and every read
;;; after it, until the end, gives what the stream holds. Prints one datum
;;; a case:
;;;
;;;   (case OP HANDLER FIRST RECEIVED)
;;;
;;; FIRST escaped or returned, how the first read ended, and RECEIVED every
;;; byte the reads gave, in order, the pattern 0 to 14 when nothing was
;;; lost or given twice; then (counts COUNTS), once the engine has stopped.
(import (chezscheme)
        (curl)
        (curl private engine)
        (curl private counters))

(define base (car (command-line-arguments)))

(define kill (foreign-procedure "kill" (int int) int))
(define getpid (foreign-procedure "getpid" () int))

(define (show datum) (write datum) (newline) (flush-output-port (current-output-port)))

(define (ms n) (make-time 'time-duration (* n 1000000) 0))

(define engine (make-curl-engine))

;; one-case : Natural Symbol Symbol -> Void
(define (one-case n op handler)
  (let* ((token (curl-submit engine
                             (make-curl-request
                              (string-append base "/raw/pattern?key=escape-" (number->string n)
                                             "&bytes=15&chunk=5&gap=50")
                              'proxy #f 'timeout-ms 20000 'stream-buffer 1000000)))
         (port (and (memq op '(some u8)) (curl-token-body-port token)))
         (mx (make-mutex))
         (held #f)
         (in-take #f)
         (received '()))
    (define (note! bytes) (set! received (append received bytes)))
    (let wait ((i 0))
      (unless (or (curl-token-done? token) (> i 10000))
        (sleep (ms 1))
        (wait (+ i 1))))
    (keyboard-interrupt-handler
     (lambda () (when (eq? handler 'escapes) (raise 'interrupted))))
    (fork-thread
     (lambda ()
       (call-with-stream-held token
         (lambda ()
           (with-mutex mx (set! held #t))
           (let loop () (unless (with-mutex mx in-take) (sleep (ms 1)) (loop)))
           (sleep (ms 100))
           (kill (getpid) 2)
           (sleep (ms 100))))))
    (let wait () (unless (with-mutex mx held) (sleep (ms 1)) (wait)))
    (with-mutex mx (set! in-take #t))
    (let ((first (guard (e ((eq? e 'interrupted) 'escaped))
                   (case op
                     ((next-piece)
                      (let ((piece (curl-token-next-piece token 5000)))
                        (when (bytevector? piece) (note! (bytevector->u8-list piece)))))
                     ((some)
                      (let ((bytes (get-bytevector-some port)))
                        (when (bytevector? bytes) (note! (bytevector->u8-list bytes)))))
                     ((u8)
                      (let ((b (get-u8 port)))
                        (when (fixnum? b) (note! (list b))))))
                   'returned)))
      (keyboard-interrupt-handler (lambda () #f))
      (let drain ()
        (let ((bytes (if port (get-bytevector-some port) (curl-token-next-piece token 5000))))
          (when (bytevector? bytes)
            (note! (bytevector->u8-list bytes))
            (drain))))
      (when port (close-port port))
      (show (list 'case op handler first received)))))

(let loop ((cases '((next-piece escapes) (next-piece returns) (some escapes) (some returns)
                    (u8 escapes) (u8 returns)))
           (n 1))
  (unless (null? cases)
    (one-case n (car (car cases)) (cadr (car cases)))
    (loop (cdr cases) (+ n 1))))
(curl-engine-stop engine)
(show (list 'counts (native-counts)))
