#!r6rs
;;; A child of tests/test-upload.sps: the put's escape (the M6 plan,
;;; section 3.5). A keyboard interrupt made pending while a put waits for
;;; the request stream's mutex inside its critical section runs as that
;;; section ends, the piece already committed in its hold; a handler that
;;; escapes there must leave it committed, counted and sent, and one that
;;; returns the same (traps.md: planting an escape at a section's end).
;;;
;;;   upload-escape.sps BASE RUNS
;;;
;;; BASE is the http face, http://ADDRESS:PORT. For each run and each
;;; HANDLER, escapes or returns, on an engine of its own: a chunked post to
;;; /sink, room-wait until libcurl asks, and a wait until the read callable
;;; has paused. Another thread holds the request stream's mutex, waits until
;;; this one is about to put, then 100 ms, then sends SIGINT to the process,
;;; which Linux offers the main thread first, and 100 ms on lets the mutex
;;; go. This thread's handler raises interrupted, or returns. The first put
;;; is bytes 0 to 4 of the pattern, i mod 251; then, the handler quiet
;;; again, bytes 5 to 9 and 10 to 14, and the end. Prints one datum a case:
;;;
;;;   (case RUN HANDLER FIRST COUNT-AFTER COUNT-AT-END BYTES PATTERN SHA256)
;;;
;;; FIRST escaped, or (returned ANSWER), how the first put ended; the body
;;; count right after it and at the end; and the origin's sink line's
;;; bytes, pattern and sha256 fields; then (counts COUNTS), once the
;;; engines have stopped.
(import (chezscheme)
        (curl)
        (curl private engine)
        (curl private counters))

(define args (command-line-arguments))
(define base (car args))
(define runs (string->number (cadr args)))

(define kill (foreign-procedure "kill" (int int) int))
(define getpid (foreign-procedure "getpid" () int))

(define (show datum) (write datum) (newline) (flush-output-port (current-output-port)))

(define (ms n) (make-time 'time-duration (* n 1000000) 0))

;; pattern-piece : Natural Natural -> Bytevector
(define (pattern-piece at n)
  (let ((bv (make-bytevector n)))
    (do ((i 0 (+ i 1))) ((= i n) bv)
      (bytevector-u8-set! bv i (mod (+ at i) 251)))))

;; sink-field : String String -> (U String #f)
;; The value of NAME=VALUE in the sink line TEXT, or #f.
(define (sink-field text name)
  (let ((prefix (string-append name "=")))
    (let loop ((words (let split ((cs (string->list text)) (cur '()) (found '()))
                        (cond ((null? cs) (reverse (if (null? cur) found (cons (list->string (reverse cur)) found))))
                              ((memv (car cs) '(#\space #\newline))
                               (split (cdr cs) '() (if (null? cur) found (cons (list->string (reverse cur)) found))))
                              (else (split (cdr cs) (cons (car cs) cur) found))))))
      (cond ((null? words) #f)
            ((and (> (string-length (car words)) (string-length prefix))
                  (string=? (substring (car words) 0 (string-length prefix)) prefix))
             (substring (car words) (string-length prefix) (string-length (car words))))
            (else (loop (cdr words)))))))

;; send-paused? : Token -> Boolean
(define (send-paused? token)
  (let ((stats (curl-token-upload-stats token)))
    (and (cdr (assq 'paused stats)) (not (cdr (assq 'queued stats))))))

;; one-case : Natural Symbol -> Void
(define (one-case run handler)
  (let* ((engine (make-curl-engine))
         (token (curl-submit engine
                             (make-curl-request
                              (string-append base "/sink?key=escape-" (symbol->string handler) "-"
                                             (number->string run))
                              'method 'post 'proxy #f 'timeout-ms 20000 'body 'stream)))
         (mx (make-mutex))
         (held #f)
         (in-put #f))
    (curl-token-room-wait token 10000)
    (let wait ((i 0))
      (unless (or (send-paused? token) (> i 10000))
        (sleep (ms 1))
        (wait (+ i 1))))
    (keyboard-interrupt-handler
     (lambda () (when (eq? handler 'escapes) (raise 'interrupted))))
    (fork-thread
     (lambda ()
       (call-with-upload-held token
         (lambda ()
           (with-mutex mx (set! held #t))
           (let loop () (unless (with-mutex mx in-put) (sleep (ms 1)) (loop)))
           (sleep (ms 100))
           (kill (getpid) 2)
           (sleep (ms 100))))))
    (let wait () (unless (with-mutex mx held) (sleep (ms 1)) (wait)))
    (with-mutex mx (set! in-put #t))
    (let* ((first (guard (e ((eq? e 'interrupted) 'escaped))
                    (list 'returned (curl-token-put-piece! token (pattern-piece 0 5) 5000))))
           (count-after (curl-token-body-count token)))
      (keyboard-interrupt-handler (lambda () #f))
      (curl-token-put-piece! token (pattern-piece 5 5) 5000)
      (curl-token-put-piece! token (pattern-piece 10 5) 5000)
      (curl-token-end-body! token)
      (curl-token-wait token 20000)
      (let* ((o (curl-token-outcome token))
             (text (if (and (curl-response? o) (curl-response-body o)) (utf8->string (curl-response-body o)) "")))
        (show (list 'case run handler first count-after (curl-token-body-count token)
                    (sink-field text "bytes") (sink-field text "pattern") (sink-field text "sha256")))))
    (curl-engine-stop engine)))

(do ((run 1 (+ run 1))) ((> run runs))
  (one-case run 'escapes)
  (one-case run 'returns))
(show (list 'counts (native-counts)))
