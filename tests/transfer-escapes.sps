#!r6rs
;;; tests/transfer-escapes.sps: the transfers whose engines or timers can
;;; land inside curl_easy_perform, run in a child Chez of
;;; tests/test-transfer.sps (ADR-0013, amended 2026-10-23). An escape from
;;; inside perform leaves its easy handle uncleaned, and counted as easy,
;;; and leaks libcurl's connection and its sockets, by design: in the
;;; suite's own process, under the memory gate, Valgrind would see that
;;; leak. Valgrind does not follow the suite into this child. The suite
;;; runs it under a bound, and names a child that times out, or whose
;;; output ends early, as that.
;;;
;;; Each case prints one datum on its own line, and the suite judges them:
;;;
;;;   (sweep NAME FUEL OUTCOME DELTA SOCKETS)  an engine of a sweep at every tick
;;;   (timer TICKS OUTCOME DELTA SOCKETS)      a timer handler that escapes
;;;   (interrupt FIRED ANSWER DELTA)           a timer handler that returns
;;;   (after LIVE LOCKS COUNTS)                once every case has run
;;;   (done)
;;;
;;; OUTCOME is (completed ANSWER), expired or escaped. DELTA is what the
;;; case left in the counts, every kind; SOCKETS, how many more sockets
;;; this process held after the case than before it, or #f off Linux.
;;; ANSWER is (response STATUS BODY-LENGTH), (refused REASON CODE) or
;;; (raised TEXT).
;;;
;;; No case hands the transfer a CHUNK-HOOK it could escape from: CHUNK-HOOK
;;; refuses an exit through a continuation, an engine's expiry included
;;; (tests/test-transfer.sps). The interrupt case's hook returns.
(import (rnrs)
        (only (chezscheme) make-engine timer-interrupt-handler set-timer fork-thread sleep
              make-time file-directory? get-process-id)
        (curl-testing)
        (curl private counters)
        (curl private conditions)
        (curl private transfer))

;; show : Any -> Unspecified
(define (show datum)
  (write datum)
  (newline)
  (flush-output-port (current-output-port)))

;; url-of : Origin Symbol String -> String
(define (url-of o face path)
  (let ((f (origin-face o face)))
    (string-append "http://" (car f) ":" (number->string (cdr f)) path)))

;; answer : (-> Response) -> Answer
(define (answer thunk)
  (guard (e ((curl-transfer-error? e)
             (list 'refused (curl-transfer-error-reason e) (curl-transfer-error-code e)))
            (#t (list 'raised (call-with-string-output-port
                               (lambda (p) (display (condition-message* e) p))))))
    (let ((r (thunk)))
      (list 'response (transfer-response-status r) (bytevector-length (transfer-response-body r))))))

;; condition-message* : Any -> String
(define (condition-message* e)
  (if (message-condition? e) (condition-message e) "a raise of no message"))

;; delta : Counts Counts -> Counts
;; AFTER less BEFORE, kind by kind.
(define (delta before after)
  (map (lambda (b a) (cons (car a) (- (cdr a) (cdr b)))) before after))

;; sweep : String Request -> Unspecified
;; REQUEST's transfer in a fresh engine with fuel 1, 2, 3 and so on, each
;; that runs out abandoned, until one completes, or past 100000 fuel; one
;; datum per engine. One engine's sockets after are the next one's before,
;; so each count is read once: a read starts a shell.
(define (sweep name request)
  (let loop ((fuel 1) (sockets (sockets-open)))
    (let* ((before (native-counts))
           (outcome ((make-engine (lambda () (list 'completed (answer (lambda () (perform-transfer request))))))
                     fuel
                     (lambda (ticks value) value)
                     (lambda (engine) 'expired)))
           (after (native-counts))
           (now (sockets-open)))
      (show (list 'sweep name fuel outcome (delta before after) (and sockets now (- now sockets))))
      (when (and (eq? outcome 'expired) (< fuel 100000))
        (loop (+ fuel 1) now)))))

;; timer-case : Positive-Integer Request -> Unspecified
;; REQUEST's transfer with a timer armed TICKS ticks ahead, whose handler
;; escapes through a continuation captured outside the transfer.
(define (timer-case ticks request)
  (let* ((sockets (sockets-open))
         (before (native-counts))
         (outcome (call/cc
                   (lambda (k)
                     (let ((old (timer-interrupt-handler)))
                       (dynamic-wind
                         (lambda () (timer-interrupt-handler (lambda () (k 'escaped))))
                         (lambda ()
                           (set-timer ticks)
                           (let ((a (answer (lambda () (perform-transfer request)))))
                             (set-timer 0)
                             (list 'completed a)))
                         (lambda () (set-timer 0) (timer-interrupt-handler old))))))))
    (let ((after (native-counts)))
      (show (list 'timer ticks outcome (delta before after) (new-sockets sockets))))))

;; interrupt-case : Origin -> Unspecified
;; A 20-byte drip, 50 ms apart. The hook arms a timer one tick ahead once 3
;; bytes have come; its handler records how many bytes had come, and
;; returns. A thread that put off its interrupts until perform returned
;; would run the handler once all 20 had come.
(define (interrupt-case o)
  (let* ((before (native-counts))
         (chunks 0)
         (armed #f)
         (fired '())
         (old (timer-interrupt-handler))
         (a (dynamic-wind
              (lambda () (timer-interrupt-handler (lambda () (set! fired (cons chunks fired)))))
              (lambda ()
                (answer (lambda ()
                          (perform-transfer
                           (make-transfer-request (url-of o 'raw "/raw/drip?bytes=20&gap=50") 'get '() #f 20000 #f
                                                  (lambda (chunk)
                                                    (set! chunks (+ chunks (bytevector-length chunk)))
                                                    (when (and (>= chunks 3) (not armed)) (set! armed #t) (set-timer 1))))))))
              (lambda () (set-timer 0) (timer-interrupt-handler old)))))
    (show (list 'interrupt (reverse fired) a (delta before (native-counts))))))

;; other-thread-can : (-> Any) -> Symbol
;; other-thread-ran when THUNK, run in a fresh thread, returns within 10 s;
;; other-thread-raised when it raises; other-thread-blocked when neither.
(define (other-thread-can thunk)
  (let ((done #f))
    (fork-thread (lambda () (guard (e (#t (set! done 'raised))) (thunk) (set! done 'ran))))
    (let loop ((i 0))
      (cond ((eq? done 'ran) 'other-thread-ran)
            ((eq? done 'raised) 'other-thread-raised)
            ((= i 1000) 'other-thread-blocked)
            (else (sleep (make-time 'time-duration 10000000 0)) (loop (+ i 1)))))))

;; new-sockets : (U Natural #f) -> (U Integer #f)
;; How many more sockets this process holds now than BEFORE; #f off Linux.
(define (new-sockets before)
  (let ((now (sockets-open)))
    (and before now (- now before))))

;; sockets-open : -> (U Natural #f)
;; The sockets this process holds, from /proc on Linux; #f elsewhere.
(define (sockets-open)
  (and (file-directory? "/proc/self/fd")
       (let ((r (capture-command
                 (list "sh" "-c" (string-append "ls -l /proc/" (number->string (get-process-id))
                                                "/fd | grep -c socket:")))))
         (let ((port (open-string-input-port (cadr r))))
           (let ((n (read port))) (and (integer? n) n))))))

(call-with-origin
  (lambda (o)
    (let ((fields (lambda (url)
                    (make-transfer-request url 'get '(("X-A" . "1") ("X-B" . "2")) "agent" 20000 100 #f))))
      (sweep "whole" (fields (url-of o 'http "/chunked")))
      (sweep "refused" (fields "http://127.0.0.1:1/"))
      (for-each (lambda (ticks)
                  (timer-case ticks (make-transfer-request (url-of o 'raw "/raw/drip?bytes=40&gap=5")
                                                           'get '() #f 20000 #f #f)))
                '(300 700 1100 1300 1500 1700))
      (interrupt-case o)
      (show (list 'after (live-transfer-count)
                  (other-thread-can (lambda () (live-transfer-count) (cached-option-names) (native-counts)))
                  (native-counts)))
      (show '(done)))))
