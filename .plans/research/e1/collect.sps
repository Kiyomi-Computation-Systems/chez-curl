;;; Spike E1 (ADR-0013, decision 5): a worker's collections beside an idle
;;; engine thread that waits in curl_multi_poll, as chez-http-server's E5c
;;; waited in uv_run.
;;;
;;;   collect.sps MODE POLL-MS TICKS [WORK]
;;;
;;; MODE is none (no engine thread), plain or safe (curl_multi_poll bound
;;; plain or __collect_safe). The engine waits POLL-MS in each poll, then
;;; spins TICKS turns of a loop, each one of Chez's event checks, and polls
;;; again. Nothing is added to its multi handle, so every poll waits its
;;; whole timeout.
;;;
;;; WORK is what the main thread does beside it:
;;;   lists  (the default) makes 60 lists of 100,000 elements and keeps every
;;;          tenth: 11 collections, each asked for soon after the last.
;;;          Prints one line: the worker's time, its collections, and the
;;;          polls that returned while it ran.
;;;   once   10 times: sleeps 37 ms, then 98, and so on 61 ms longer each
;;;          time up to 586, then asks for one collection with
;;;          collect-rendezvous. Prints one line: the sleeps, and the polls
;;;          that returned during each collection.
(import (chezscheme) (curl private native) (curl private libcurl-info))

(define args (command-line-arguments))
(define mode (string->symbol (car args)))
(define poll-ms (string->number (cadr args)))
(define ticks (string->number (caddr args)))
(define work (if (> (length args) 3) (string->symbol (cadddr args)) 'lists))
(define info (loaded-libcurl))          ; the load, on this thread, before any fork

(define multi-init (foreign-procedure "curl_multi_init" () uptr))
(define multi-cleanup (foreign-procedure "curl_multi_cleanup" (uptr) int))
(define multi-wakeup (foreign-procedure "curl_multi_wakeup" (uptr) int))
(define poll-plain
  (foreign-procedure "curl_multi_poll" (uptr uptr unsigned-int int uptr) int))
(define poll-safe
  (foreign-procedure __collect_safe "curl_multi_poll" (uptr uptr unsigned-int int uptr) int))

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* 1000.0 (time-second t)) (/ (time-nanosecond t) 1e6))))

;; spin : Natural -> Natural
;; N turns of a loop. Each turn is one of Chez's event checks, so each costs
;; one timer tick.
(define (spin n) (let loop ((i 0)) (if (= i n) i (loop (+ i 1)))))

(define polls 0)                        ; written by the engine thread alone
(define sink 0)
(define stop #f)
(define multi #f)
(define finished #f)
(define mx (make-mutex))
(define cv (make-condition))

(unless (eq? mode 'none)
  (fork-thread
   (lambda ()
     (let ((m (multi-init)) (numfds (foreign-alloc 8))
           (poll (if (eq? mode 'safe) poll-safe poll-plain)))
       (with-mutex mx (set! multi m) (condition-broadcast cv))
       (let loop ()
         (unless stop
           (poll m 0 0 poll-ms numfds)
           (set! sink (spin ticks))
           (set! polls (+ polls 1))
           (loop)))
       (foreign-free numfds)
       (multi-cleanup m)
       (with-mutex mx (set! finished #t) (condition-broadcast cv)))))
  (with-mutex mx (let wait () (unless multi (condition-wait cv mx) (wait))))
  (sleep (make-time 'time-duration 0 1)))   ; let it settle into its polls

(define (lists-work)
  (let ((c0 (collections)) (p0 polls) (t0 (now-ms)))
    (let loop ((i 0) (keep '()))
      (unless (= i 60)
        (let ((l (make-list 100000 i)))
          (loop (+ i 1) (if (zero? (mod i 10)) (cons l keep) keep)))))
    (list (- (now-ms) t0) (- (collections) c0) (- polls p0))))

;; polls-during : (-> Any) -> Natural
(define (polls-during thunk)
  (let ((p0 polls)) (thunk) (- polls p0)))

(define once-sleeps (map (lambda (k) (+ 37 (* 61 k))) (iota 10)))

(define (once-work)
  (map (lambda (ms)
         (sleep (make-time 'time-duration (* 1000000 ms) 0))
         (polls-during collect-rendezvous))
       once-sleeps))

(define result (if (eq? work 'once) (once-work) (lists-work)))

(set! stop #t)
(unless (eq? mode 'none)
  (multi-wakeup multi)
  (with-mutex mx (let wait () (unless finished (condition-wait cv mx) (wait)))))

(if (eq? work 'once)
    (printf "collect once ~a, poll ~a ms, ticks ~a, libcurl ~a: after sleeps of ~s ms, polls during each collection ~s\n"
            mode poll-ms ticks (libcurl-info-version info) once-sleeps result)
    (printf "collect ~a, poll ~a ms, ticks ~a, libcurl ~a: worker ~,1f ms, ~a collections, ~a polls\n"
            mode poll-ms ticks (libcurl-info-version info)
            (car result) (cadr result) (caddr result)))
