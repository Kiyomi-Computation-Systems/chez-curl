;;; M6 slice 2, item 3c (2026-10-30): the CPU during a slow upload and a
;;; paused one (curl #16084, fixed in 8.12.0: "the poll returned at once,
;;; repeatedly, during h2 uploads"), with the paced poll on and off (the M6
;;; plan, sections 2.2, 3.4 and 5.1).
;;;
;;;   scheme --libdirs build/m6s2/src --program cpu.sps HTTP RAW HTTPS H2 CA RUNS
;;;
;;; Each case on an engine of its own, make-curl-engine (pacing on) or
;;; make-curl-engine-unpaced (off), a streamed post to /sink on the raw
;;; (HTTP/1.1) and h2 faces, sized:
;;;
;;;   slow    1,228,800 bytes: room-wait, then 300 puts of 4,096 bytes, a
;;;           sleep of 10 ms after each; the window runs from the first put
;;;           to the last, about 3 s;
;;;   paused  8,192 bytes: room-wait, a put of 4,096, then, once the read
;;;           callable has paused, a window of 3 s with nothing put; then
;;;           the other 4,096 and the end.
;;;
;;; Each line, over the window: its wall time, the process's CPU by Chez's
;;; time-process clock (every thread's) and by /proc/self/stat (10 ms
;;; ticks); the engine's turns, polls, polls under 1 ms, and of those the
;;; ones in a turn that took a message, else that moved bytes, else with no
;;; transfer paused, else with one paused (the polls the pacing follows
;;; with a sleep); and its paced sleeps. Then the outcome and the server's
;;; sink line.
(import (chezscheme)
        (curl private engine)
        (curl private transfer)
        (curl private conditions)
        (curl private native)
        (curl private libcurl-info))

(define args (command-line-arguments))
(define faces (map cons '(http raw https h2) (list-head args 4)))
(define ca (list-ref args 4))
(define runs (string->number (list-ref args 5)))

(define (say fmt . xs) (apply printf fmt xs) (newline) (flush-output-port (current-output-port)))
(define (ns-of t) (+ (* (time-second t) 1000000000) (time-nanosecond t)))
(define (now-ns) (ns-of (current-time 'time-monotonic)))
(define (cpu-ns) (ns-of (current-time 'time-process)))
(define (ms x) (/ (round (/ x 1000)) 1000.0))
(define (sleep-ms n) (when (> n 0) (sleep (make-time 'time-duration (* (mod n 1000) 1000000) (div n 1000)))))

;; proc-stat-ms : -> Natural
;; This process's utime plus stime, from /proc/self/stat, in ms (10 ms ticks).
(define (proc-stat-ms)
  (let* ((s (call-with-input-file "/proc/self/stat" get-line))
         (after (let loop ((i (- (string-length s) 1)))
                  (if (char=? (string-ref s i) #\)) (+ i 2) (loop (- i 1)))))
         (fields (let loop ((i after) (start after) (acc '()))
                   (cond ((= i (string-length s)) (reverse (cons (substring s start i) acc)))
                         ((char=? (string-ref s i) #\space) (loop (+ i 1) (+ i 1) (cons (substring s start i) acc)))
                         (else (loop (+ i 1) start acc))))))
    (* 10 (+ (string->number (list-ref fields 11)) (string->number (list-ref fields 12))))))

(define (url face path tag)
  (string-append (if (memq face '(https h2)) "https://" "http://") (cdr (assq face faces)) path
                 (if (memv #\? (string->list path)) "&" "?") "tag=" tag))

(define (request face method path tag timeout)
  (let ((r (make-curl-request (url face path tag) 'method method 'proxy #f 'timeout-ms timeout)))
    (if (memq face '(https h2)) (curl-request-with r 'ca-file ca) r)))

(define (pattern-piece at n)
  (let ((bv (make-bytevector n)))
    (let loop ((i 0) (v (mod at 251)))
      (when (< i n) (bytevector-u8-set! bv i v) (loop (+ i 1) (if (= v 250) 0 (+ v 1)))))
    bv))

(define (split-lines s)
  (let loop ((cs (string->list s)) (cur '()) (acc '()))
    (cond ((null? cs) (reverse (if (null? cur) acc (cons (list->string (reverse cur)) acc))))
          ((char=? (car cs) #\newline) (loop (cdr cs) '() (cons (list->string (reverse cur)) acc)))
          (else (loop (cdr cs) (cons (car cs) cur) acc)))))

(define (outcome-text o)
  (cond ((curl-response? o) (format "status=~a version=~a" (curl-response-status o) (curl-response-http-version o)))
        ((curl-transfer-error? o)
         (format "failed reason=~a code=~a request-size=~a error=~s" (curl-transfer-error-reason o)
                 (curl-transfer-error-code o) (curl-transfer-error-request-size o)
                 (curl-transfer-error-error-buffer o)))
        ((curl-engine-error? o) (format "engine ~a" (curl-engine-error-reason o)))
        ((not o) "not-done")
        (else (format "other ~s" o))))

(define log-engine (make-curl-engine))
(define (server-log tag)
  (let* ((t (curl-submit log-engine
                         (make-curl-request (string-append "http://" (cdr (assq 'raw faces)) "/log?tag=" tag)
                                            'proxy #f 'timeout-ms 10000)))
         (o (begin (curl-token-wait t 15000) (curl-token-outcome t))))
    (if (curl-response? o)
        (split-lines (utf8->string (curl-response-body o)))
        (list (format "log fetch failed: ~a" (outcome-text o))))))

(define (stat token key) (cdr (assq key (curl-token-upload-stats token))))

(define count-names '(turns polls fast-polls fast-message fast-moved fast-unpaused fast-paced-eligible paced))
(define (counts engine) (map (lambda (k) (cdr (assq k (curl-engine-counts engine)))) count-names))

;; wait-for : (-> Any) Natural -> Any
(define (wait-for thunk bound)
  (let ((deadline (+ (now-ns) (* bound 1000000))))
    (let loop () (or (thunk) (and (< (now-ns) deadline) (begin (sleep-ms 1) (loop)))))))

;; one : Natural Symbol Symbol Boolean -> Void
(define (one r face scenario pacing)
  (let* ((n (if (eq? scenario 'slow) 1228800 8192))
         (label (format "cpu run=~a face=~a scenario=~a pacing=~a" r face scenario (if pacing "on" "off")))
         (tag (format "cpu.~a.~a.~a.r~a" face scenario (if pacing "on" "off") r))
         (engine (if pacing (make-curl-engine) (make-curl-engine-unpaced)))
         (token (curl-submit engine (curl-request-with-body-stream
                                     (request face 'post (format "/sink?want=~a&arr=0" n) tag 60000) n)))
         (asked (curl-token-room-wait token 10000)))
    (let-values (((window c0 c1 cpu st extra)
                  (case scenario
                    ((slow)
                     (collect-rendezvous)
                     (let* ((c0 (counts engine)) (cpu0 (cpu-ns)) (st0 (proc-stat-ms)) (t0 (now-ns)))
                       (let loop ((i 0) (odd '()))
                         (if (< i 300)
                             (let ((a (curl-token-put-piece! token (pattern-piece (* i 4096) 4096) 2000)))
                               (sleep-ms 10)
                               (loop (+ i 1) (if (eq? a #t) odd (cons (list i a) odd))))
                             (let* ((t1 (now-ns)) (cpu1 (cpu-ns)) (st1 (proc-stat-ms)) (c1 (counts engine)))
                               (values (- t1 t0) c0 c1 (- cpu1 cpu0) (- st1 st0) (format "odd-puts=~s" (reverse odd))))))))
                    (else
                     (curl-token-put-piece! token (pattern-piece 0 4096) 2000)
                     (let ((paused (wait-for (lambda () (and (stat token 'send-paused) (= (stat token 'handed) 4096))) 5000)))
                       (collect-rendezvous)
                       (let* ((c0 (counts engine)) (cpu0 (cpu-ns)) (st0 (proc-stat-ms)) (t0 (now-ns)))
                         (sleep-ms 3000)
                         (let* ((t1 (now-ns)) (cpu1 (cpu-ns)) (st1 (proc-stat-ms)) (c1 (counts engine))
                                (still (stat token 'send-paused)))
                           (curl-token-put-piece! token (pattern-piece 4096 4096) 2000)
                           (values (- t1 t0) c0 c1 (- cpu1 cpu0) (- st1 st0)
                                   (format "paused-before=~a still-paused=~a" (and paused #t) still)))))))))
      (curl-token-end-body! token)
      (curl-token-wait token 30000)
      (apply say (string-append "~a asked=~a window-ms=~a cpu-ms=~a proc-stat-ms=~a"
                                (apply string-append (map (lambda (k) (format " ~a=~~a" k)) count-names))
                                " ~a ~a reads=~a pauses=~a resumes=~a")
             label asked (ms window) (ms cpu) st
             (append (map - c1 c0)
                     (list extra (outcome-text (curl-token-outcome token))
                           (stat token 'reads) (stat token 'pauses) (stat token 'resumes))))
      (for-each (lambda (line) (when (and (> (string-length line) 4) (string=? (substring line 0 4) "sink")) (say "~a server: ~a" label line)))
                (server-log tag)))
    (curl-engine-stop engine)))

(say "libcurl ~a ~a" (libcurl-info-version (loaded-libcurl)) (libcurl-info-ssl-version (loaded-libcurl)))
(do ((r 1 (+ r 1))) ((> r runs))
  (for-each (lambda (face)
              (for-each (lambda (scenario)
                          (one r face scenario #t)
                          (one r face scenario #f))
                        '(slow paused)))
            '(raw h2)))
(curl-engine-stop log-engine)
(say "cpu done")
