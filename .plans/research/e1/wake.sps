;;; Spike E1: curl_multi_wakeup from another thread, the engine's one
;;; cross-thread call (M3 plan, section 3.1).
;;;
;;;   wake.sps
;;;
;;; 1. Latency: the engine thread waits in a __collect_safe poll of 5 s,
;;;    and the main thread wakes it 20 times, 50 ms apart. Each wakeup is
;;;    timed to the poll's return.
;;; 2. A wakeup sent while no poll runs: does the next poll return at once?
;;; 3. Two wakeups, then two polls: does the second return at once too?
;;; Prints one line for each.
(import (chezscheme) (curl private native) (curl private libcurl-info))

(define info (loaded-libcurl))
(define multi-init (foreign-procedure "curl_multi_init" () uptr))
(define multi-cleanup (foreign-procedure "curl_multi_cleanup" (uptr) int))
(define multi-wakeup (foreign-procedure "curl_multi_wakeup" (uptr) int))
(define poll
  (foreign-procedure __collect_safe "curl_multi_poll" (uptr uptr unsigned-int int uptr) int))

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* 1000.0 (time-second t)) (/ (time-nanosecond t) 1e6))))
(define (sleep-ms n) (sleep (make-time 'time-duration (* n 1000000) 0)))

(define numfds (foreign-alloc 8))
;; timed-poll : Natural Natural -> (List Integer Ms)
(define (timed-poll m ms)
  (let* ((t0 (now-ms)) (rc (poll m 0 0 ms numfds)))
    (list rc (round (- (now-ms) t0)))))

(define m (multi-init))
(define mx (make-mutex))
(define cv (make-condition))
(define returns '())                    ; when each poll returned, newest first
(define stop #f)
(define finished #f)

;; 1. Latency.
(fork-thread
 (lambda ()
   (let ((numfds (foreign-alloc 8)))
     (let loop ()
       (unless stop
         (poll m 0 0 5000 numfds)
         (with-mutex mx (set! returns (cons (now-ms) returns)))
         (loop)))
     (foreign-free numfds))
   (with-mutex mx (set! finished #t) (condition-broadcast cv))))
(sleep-ms 200)
(define latencies
  (let loop ((i 0) (acc '()))
    (if (= i 20)
        acc
        (begin
          (sleep-ms 50)
          (let* ((n (with-mutex mx (length returns))) (t0 (now-ms)))
            (multi-wakeup m)
            (let wait ()
              (when (= n (with-mutex mx (length returns))) (sleep-ms 0) (wait)))
            (loop (+ i 1) (cons (- (with-mutex mx (car returns)) t0) acc)))))))
(set! stop #t)
(multi-wakeup m)
(with-mutex mx (let wait () (unless finished (condition-wait cv mx) (wait))))
(printf "wake 1, libcurl ~a: 20 wakeups of a waiting poll, latency min ~,3f ms, max ~,3f ms\n"
        (libcurl-info-version info) (apply min latencies) (apply max latencies))

;; 2 and 3, on this thread, with nothing else polling.
(printf "wake 2, libcurl ~a: one wakeup sent with no poll running, then a poll of 5000 ms: ~s\n"
        (libcurl-info-version info)
        (begin (multi-wakeup m) (timed-poll m 5000)))
(let* ((first (begin (multi-wakeup m) (multi-wakeup m) (timed-poll m 5000)))
       (second (timed-poll m 300)))
  (printf "wake 3, libcurl ~a: two wakeups, then a poll of 5000 ms: ~s, and another of 300 ms: ~s\n"
          (libcurl-info-version info) first second))
(foreign-free numfds)
(multi-cleanup m)
