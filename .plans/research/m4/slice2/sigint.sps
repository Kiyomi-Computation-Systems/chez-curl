;;; M4 slice 2's first measurement (the M4 plan, section 5.1): can a
;;; process-directed SIGINT land on a thread other than the main one, while
;;; the main thread waits in a take?
;;;
;;;   sigint.sps CASE URL
;;;
;;; It makes an engine, submits URL with a mailbox, prints (ready PID) and
;;; waits as CASE says:
;;;   take   in curl-mailbox-take, bounded at 120 s, until the token arrives;
;;;   busy   running, reading curl-token-done? in a loop with no sleep.
;;; URL is a transfer that stays live while the runner sends its signals:
;;; libcurl's thread and the engine's wait in poll meanwhile, and a stalled
;;; lookup's resolver thread in getaddrinfo.
;;;
;;; The runner sends SIGINT to PID, N times, 300 ms apart. Chez acts on
;;; SIGINT on the main thread alone, and drops it on any other (c/schsig.c):
;;; so each signal the main thread took runs the keyboard-interrupt handler
;;; once, and one the kernel handed another thread runs it never.
;;;
;;; Prints (sigint CASE HANDLED THREADS ANSWER COUNTS): the ms after ready at
;;; which the handler ran, oldest first; the process's thread count as the
;;; wait started, from Linux's /proc, or #f elsewhere; what the transfer
;;; answered; and the counts once the engine has stopped. On Linux, it first
;;; prints (masks (TID SIGBLK SIGIGN) ...): each thread's blocked and ignored
;;; signals as the wait started, from /proc/self/task/TID/status, in hex;
;;; SIGINT is bit 1, 0x2.
(import (chezscheme) (curl private engine) (curl private transfer) (curl private conditions)
        (curl private counters))

(define args (command-line-arguments))
(define case-name (string->symbol (car args)))
(define url (cadr args))

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

(define (thread-count)
  (and (file-directory? "/proc/self/task")
       (length (directory-list "/proc/self/task"))))

;; status-field : String String -> (U String #f)
(define (status-field tid name)
  (let ((p (open-input-file (format "/proc/self/task/~a/status" tid))))
    (let loop ()
      (let ((line (get-line p)))
        (cond ((eof-object? line) (close-port p) #f)
              ((and (> (string-length line) (string-length name))
                    (string=? (substring line 0 (string-length name)) name))
               (close-port p)
               (let ((v (substring line (string-length name) (string-length line))))
                 (list->string (filter (lambda (c) (not (char-whitespace? c))) (string->list v)))))
              (else (loop)))))))

(define (masks)
  (and (file-directory? "/proc/self/task")
       (map (lambda (tid) (list tid (status-field tid "SigBlk:") (status-field tid "SigIgn:")))
            (list-sort string<? (directory-list "/proc/self/task")))))

(define engine (make-curl-engine))
(define mailbox (make-curl-mailbox))
(define handled '())
(define t0 (now-ms))
(keyboard-interrupt-handler (lambda () (set! handled (cons (- (now-ms) t0) handled))))
(define token (curl-submit engine (make-curl-request url 'timeout-ms 120000) mailbox))
(sleep (make-time 'time-duration 0 1))
(define threads (thread-count))
(let ((m (masks))) (when m (write (cons 'masks m)) (newline)))
(set! t0 (now-ms))
(write (list 'ready (get-process-id)))
(newline)
(flush-output-port (current-output-port))
(define waited
  (case case-name
    ((take) (curl-mailbox-take mailbox 120000))
    ((busy) (let spin () (if (curl-token-done? token) token (spin))))
    (else (error 'sigint.sps "no such case" case-name))))
(define answer
  (cond ((not (eq? waited token)) (list 'wait-answered waited))
        (else (guard (e ((curl-transfer-error? e)
                         (list (curl-transfer-error-reason e) (curl-transfer-error-code e))))
                (list 'response (curl-response-status (curl-token-await token)))))))
(curl-engine-stop engine)
(write (list 'sigint case-name (reverse handled) threads answer (native-counts)))
(newline)
