;;; M6 slice 1, item 5 (2026-10-30): the take's escape, against the
;;; prototype's lent take (the M6 plan, section 3.5): the review's SIGINT
;;; recipe (research/m6/review/take-escape.sps; traps.md, "a Chez timer
;;; that runs out inside a critical section ...").
;;;
;;;   scheme --libdirs build/m6s1/src --program escape.sps HTTP RAW HTTPS H2 PROXY CA RUNS
;;;
;;; Linux alone: it binds libc's kill and getpid. Each case, on an engine of
;;; its own: /pieces?n=3&size=5&gap=50 on the raw face, at stream-buffer
;;; 65,536, so three pieces arrive, the bytes of piece i all i, and the
;;; token is done before anything is taken. Then another thread holds the
;;; stream's mutex through call-with-stream-held, the prototype's seam; once
;;; this thread is about to take, it sleeps 100 ms, so the take blocks on
;;; the mutex inside its critical section, sends SIGINT to the process
;;; (Linux offers it to the main thread), sleeps 100 ms more, and lets go.
;;; The keyboard-interrupt handler raises, escaping as the take's section
;;; ends, or returns. The first take is OP: curl-token-next-piece, or a
;;; port's get-bytevector-some or get-u8; then the rest are read with the
;;; same family, next-piece or get-bytevector-some, until the end.
;;;
;;; Each case runs the lent take, the plan's, and the control, which removes
;;; the piece inside its hold (the prototype's private switch). Each line:
;;; how the first take ended, the pieces given (the stream's removals, in
;;; order, so 1 to N), the bytes received of each piece (5 each, whole),
;;; and those lost (fewer than 5) or given twice (more than 5).
(import (chezscheme)
        (curl private engine)
        (curl private transfer)
        (curl private native)
        (curl private libcurl-info))

(define args (command-line-arguments))
(define raw (list-ref args 1))
(define runs (string->number (list-ref args 6)))

(load-shared-object "libc.so.6")
(define kill (foreign-procedure "kill" (int int) int))
(define getpid (foreign-procedure "getpid" () int))
(define sigint 2)

(define (say fmt . xs) (apply printf fmt xs) (newline) (flush-output-port (current-output-port)))
(define (ms n) (make-time 'time-duration (* n 1000000) 0))

(define (stat token key) (cdr (assq key (curl-token-stream-stats token))))

;; one : Natural Symbol Boolean Boolean -> Void
(define (one r op escaping control)
  (set-take-removes-inside-hold! control)
  (let* ((engine (make-curl-engine))
         (token (curl-submit engine (curl-request-with-stream-buffer
                                     (make-curl-request (string-append "http://" raw "/pieces?n=3&size=5&gap=50")
                                                        'proxy #f 'timeout-ms 10000)
                                     65536)))
         (done (curl-token-wait token 10000))
         (port (and (memq op '(some u8)) (curl-token-body-port token)))
         (counts (make-vector 4 0))
         (note! (lambda (bv) (when (bytevector? bv)
                               (for-each (lambda (b) (when (<= 1 b 3) (vector-set! counts b (+ 1 (vector-ref counts b)))))
                                         (bytevector->u8-list bv)))))
         (ready #f)
         (in-take #f))
    (keyboard-interrupt-handler (lambda () (when escaping (raise 'interrupted))))
    (fork-thread
     (lambda ()
       (call-with-stream-held token
         (lambda ()
           (set! ready #t)
           (let loop () (unless in-take (sleep (ms 1)) (loop)))
           (sleep (ms 100))
           (kill (getpid) sigint)
           (sleep (ms 100))))))
    (let loop () (unless ready (sleep (ms 1)) (loop)))
    (let ((first (guard (e ((eq? e 'interrupted) 'escaped))
                   (set! in-take #t)
                   (let ((got (case op
                                ((next-piece) (curl-token-next-piece token 5000))
                                ((some) (get-bytevector-some port))
                                ((u8) (let ((b (get-u8 port))) (if (eof-object? b) b (make-bytevector 1 b)))))))
                     (note! got)
                     'returned))))
      (let rest ()
        (let ((got (if port (get-bytevector-some port) (curl-token-next-piece token 5000))))
          (when (bytevector? got) (note! got) (rest))))
      (keyboard-interrupt-handler (lambda () (void)))
      (let* ((given (stat token 'given))
             (received (map (lambda (i) (vector-ref counts i)) '(1 2 3)))
             (lost (filter (lambda (i) (< (vector-ref counts i) 5)) (iota-from 1 given)))
             (twice (filter (lambda (i) (> (vector-ref counts i) 5)) '(1 2 3))))
        (say "escape run=~a op=~a handler=~a take=~a done=~a first=~a given=~a received-bytes-of-1-2-3=~a lost=~a twice=~a"
             r op (if escaping "escapes" "returns") (if control "control-removes-inside-hold" "lent")
             done first (iota-from 1 given) received lost twice)))
    (curl-engine-stop engine)
    (set-take-removes-inside-hold! #f)))

;; iota-from : Natural Natural -> (Listof Natural)
(define (iota-from start n) (if (= n 0) '() (cons start (iota-from (+ start 1) (- n 1)))))

(say "libcurl ~a ~a" (libcurl-info-version (loaded-libcurl)) (libcurl-info-ssl-version (loaded-libcurl)))
(do ((r 1 (+ r 1))) ((> r runs))
  (for-each (lambda (control)
              (for-each (lambda (op)
                          (one r op #f control)
                          (one r op #t control))
                        '(next-piece some u8)))
            '(#f #t)))
(say "escape done")
