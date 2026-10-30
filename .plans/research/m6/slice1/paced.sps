;;; M6 slice 1, item 2 (2026-10-30): the paced poll, through the engine (the
;;; M6 plan, sections 3.4 and 4.1).
;;;
;;;   scheme --libdirs build/m6s1/src --program paced.sps HTTP RAW HTTPS H2 PROXY CA RUNS
;;;
;;; Each run, on the http and h2 faces, with the pacing on and then off (the
;;; prototype's private switch), on an engine of its own:
;;;
;;;   1. a stream of /body, 8 MiB of i mod 251, at stream-buffer 65,536,
;;;      until the write callable has paused it: the receive bit set;
;;;   2. the quiet window: the consumer takes nothing for 3 s. The process's
;;;      CPU over it, by Chez's time-process clock (every thread's) and by
;;;      /proc/self/stat's utime and stime (10 ms ticks), and the engine's
;;;      turns, polls, polls under 1 ms and paced sleeps in it;
;;;   3. the active window, the stream still paused: 8 rounds, each a
;;;      submit of /hold?ms=30000, a cancel of that token once it is live,
;;;      and a resume, each after a sleep of 23 ms plus 125 us times the
;;;      round, so the calls fall across the 1 ms period of the paced poll's
;;;      sleep, and of any wait with it. The delays, in ms:
;;;        submit  from just before curl-submit to the engine's add of the
;;;                transfer to its multi handle (and, as taken=, to the turn
;;;                that took the message);
;;;        cancel  from just before curl-token-cancel to the engine's
;;;                completion of the token as cancelled;
;;;        resume  from the look that queued it, inside the caller's take,
;;;                to the engine's call of curl_easy_pause; each round takes
;;;                pieces, a bound of 0 ms each, until one take has queued a
;;;                resume, then waits for the stream to pause again;
;;;   4. the drain: every piece taken, every byte checked against its
;;;      pattern, and the outcome.
;;;
;;; One line per run and setting, then a delays line per kind.
(import (chezscheme)
        (curl private engine)
        (curl private transfer)
        (curl private conditions)
        (curl private native)
        (curl private libcurl-info))

(define args (command-line-arguments))
(define faces (map cons '(http raw https h2 proxy) (list-head args 5)))
(define ca (list-ref args 5))
(define runs (string->number (list-ref args 6)))

(define (say fmt . xs) (apply printf fmt xs) (newline) (flush-output-port (current-output-port)))

(define (ns-of t) (+ (* (time-second t) 1000000000) (time-nanosecond t)))
(define (now-ns) (ns-of (current-time 'time-monotonic)))
(define (cpu-ns) (ns-of (current-time 'time-process)))
(define (ms x) (/ (round (/ x 1000)) 1000.0))
(define (sleep-ns n) (when (> n 0) (sleep (make-time 'time-duration (mod n 1000000000) (div n 1000000000)))))

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

(define (url face path)
  (string-append (if (memq face '(https h2)) "https://" "http://") (cdr (assq face faces)) path))

(define (request face path)
  (let ((r (make-curl-request (url face path) 'proxy #f 'timeout-ms 120000)))
    (if (memq face '(https h2)) (curl-request-with r 'ca-file ca) r)))

(define (bad-at piece at)
  (let ((n (bytevector-length piece)))
    (let loop ((i 0) (v (mod at 251)))
      (cond ((= i n) #f)
            ((fx= (bytevector-u8-ref piece i) v) (loop (fx+ i 1) (if (fx= v 250) 0 (fx+ v 1))))
            (else (+ at i))))))

(define (stat token key) (cdr (assq key (curl-token-stream-stats token))))
(define (probe engine key) (cdr (assq key (curl-engine-probe engine))))
(define (events engine kind token)
  (filter (lambda (e) (and (eq? (car e) kind) (eq? (cadr e) token))) (probe engine 'events)))

;; wait-for : (-> Any) Natural -> Any
;; THUNK's first true answer, read every 1 ms, or #f after MS ms.
(define (wait-for thunk ms)
  (let ((deadline (+ (now-ns) (* ms 1000000))))
    (let loop ()
      (or (thunk)
          (and (< (now-ns) deadline)
               (begin (sleep-ns 1000000) (loop)))))))

(define (paused? token) (and (stat token 'recv-paused) (not (stat token 'resume-queued))))

(define (outcome-text token)
  (let ((o (curl-token-outcome token)))
    (cond ((curl-response? o) (format "status=~a" (curl-response-status o)))
          ((curl-transfer-error? o)
           (format "failed reason=~a code=~a" (curl-transfer-error-reason o) (curl-transfer-error-code o)))
          ((curl-engine-error? o) (format "engine ~a" (curl-engine-error-reason o)))
          (else (format "other ~s" o)))))

;; run : Natural Symbol Boolean -> Void
(define (run r face pacing)
  (set-engine-pacing! pacing)
  (let* ((engine (make-curl-engine))
         (n 8388608)
         (token (curl-submit engine (curl-request-with-stream-buffer
                                     (request face (format "/body?n=~a" n)) 65536)))
         (label (format "paced run=~a face=~a pacing=~a" r face (if pacing "on" "off"))))
    (if (not (wait-for (lambda () (paused? token)) 20000))
        (say "~a never paused: ~s" label (curl-token-stream-stats token))
        (let ((counts (lambda () (map (lambda (k) (probe engine k)) '(turns polls fast-polls paced)))))
          ;; the quiet window
          (collect-rendezvous)
          (let* ((c0 (counts)) (cpu0 (cpu-ns)) (st0 (proc-stat-ms)) (t0 (now-ns)))
            (sleep-ns 3000000000)
            (let* ((t1 (now-ns)) (cpu1 (cpu-ns)) (st1 (proc-stat-ms)) (c1 (counts))
                   (still (paused? token)))
              (say "~a window-ms=~a cpu-ms=~a proc-stat-ms=~a turns=~a polls=~a fast-polls=~a paced=~a still-paused=~a"
                   label (ms (- t1 t0)) (ms (- cpu1 cpu0)) (- st1 st0)
                   (- (car c1) (car c0)) (- (cadr c1) (cadr c0)) (- (caddr c1) (caddr c0))
                   (- (cadddr c1) (cadddr c0)) still)))
          ;; the active window
          (let loop ((i 0) (submits '()) (takens '()) (cancels '()) (resumes '()) (at 0) (bad #f))
            (if (< i 8)
                (let* ((offset (+ 23000000 (* i 125000))))
                  ;; a submit
                  (sleep-ns offset)
                  (let* ((s0 (now-ns))
                         (hold (curl-submit engine (request face "/hold?ms=30000")))
                         (added (wait-for (lambda () (let ((e (events engine 'submit hold))) (and (pair? e) (car e)))) 5000)))
                    ;; a cancel of that token, once live
                    (sleep-ns offset)
                    (let* ((k0 (now-ns))
                           (_ (curl-token-cancel hold))
                           (cancelled (wait-for (lambda () (let ((e (events engine 'cancel hold))) (and (pair? e) (car e)))) 5000)))
                      ;; a resume
                      (sleep-ns offset)
                      (let* ((before (length (events engine 'resume token)))
                             (taken (let take ((at at) (bad bad))
                                      (let ((piece (curl-token-next-piece token 0)))
                                        (cond ((bytevector? piece)
                                               (let ((at2 (+ at (bytevector-length piece)))
                                                     (bad2 (or bad (bad-at piece at))))
                                                 (if (or (stat token 'resume-queued)
                                                         (> (length (events engine 'resume token)) before))
                                                     (cons at2 bad2)
                                                     (take at2 bad2))))
                                              (else (cons at bad))))))
                             (resumed (wait-for (lambda () (let ((e (events engine 'resume token)))
                                                             (and (> (length e) before) (list-ref e before))))
                                                5000)))
                        (wait-for (lambda () (paused? token)) 5000)
                        (loop (+ i 1)
                              (cons (and added (ms (- (list-ref added 4) s0))) submits)
                              (cons (and added (ms (- (list-ref added 3) s0))) takens)
                              (cons (and cancelled (ms (- (list-ref cancelled 4) k0))) cancels)
                              (cons (and resumed (ms (- (list-ref resumed 4) (list-ref resumed 2)))) resumes)
                              (car taken) (cdr taken))))))
                (begin
                  (say "~a delays submit-ms=~a" label (reverse submits))
                  (say "~a delays submit-taken-ms=~a" label (reverse takens))
                  (say "~a delays cancel-ms=~a" label (reverse cancels))
                  (say "~a delays resume-ms=~a" label (reverse resumes))
                  ;; the drain
                  (let drain ((at at) (bad bad))
                    (let ((piece (curl-token-next-piece token 60000)))
                      (cond ((bytevector? piece) (drain (+ at (bytevector-length piece)) (or bad (bad-at piece at))))
                            (else
                             (curl-token-wait token 5000)
                             (say "~a drained bytes=~a whole=~a pattern=~a end=~a pauses=~a resumes=~a passed-over=~a queued-polls=~a queued-poll-max-ms=~a queued-polls-100ms=~a ~a"
                                  label at (= at n) (or bad "ok") (if (eof-object? piece) "eof" piece)
                                  (stat token 'pauses) (length (events engine 'resume token))
                                  (probe engine 'passed-over) (probe engine 'queued-polls)
                                  (ms (probe engine 'queued-poll-max-ns)) (probe engine 'queued-polls-100ms)
                                  (outcome-text token)))))))))))
    (curl-engine-stop engine)))

(say "libcurl ~a ~a" (libcurl-info-version (loaded-libcurl)) (libcurl-info-ssl-version (loaded-libcurl)))
(do ((r 1 (+ r 1))) ((> r runs))
  (for-each (lambda (face)
              (run r face #t)
              (run r face #f))
            '(http h2)))
(set-engine-pacing! #t)
(say "paced done")
