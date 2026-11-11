#!r6rs
;;; A child of tests/test-engine.sps: several caller threads, each submitting
;;; a transfer and awaiting it, over and over, while their allocation asks for
;;; collections (ADR-0013). A wait that held the engine's mutex with
;;; interrupts on joined a collection there, while another thread, blocked on
;;; that mutex with interrupts off, stayed active: four threads hung within
;;; 1 s.
;;;
;;;   engine-awaiters.sps together THREADS MS URL
;;;   engine-awaiters.sps latency N 0 URL
;;;   engine-awaiters.sps cpu 1 0 URL
;;;   engine-awaiters.sps wake N 0 URL
;;;   engine-awaiters.sps critical 1 0 URL
;;;
;;; together: THREADS caller threads for MS; prints (awaiters THREADS
;;; DONE COLLECTIONS), how many transfers answered 200, and how many
;;; collections ran meanwhile. latency: this thread submits
;;; URL and awaits it N times, one after another; prints (latency N MS),
;;; how long the N took, so a wait that wakes late shows. cpu: this thread
;;; awaits URL, a slow drip, once; prints (cpu CPU WALL), the process's
;;; cpu-time over the await and its length, in ms, so a wait that spins
;;; shows. wake: this thread awaits URL, a slow drip, N times, while a
;;; watcher polls curl-token-done? every 1 ms; prints (wake N GAP), the
;;; longest time from the watcher seeing a token done to the await's
;;; return, so a wait that sleeps past its cap shows. critical: an await, a
;;; stop and a make-curl-engine, each inside critical-section; prints
;;; (critical WHO ...), the who of each refusal, so a wait that would sleep
;;; with interrupts off, and deadlock, shows. Each then prints
;;; (counts COUNTS), once the engine has stopped. A hang is killed by the
;;; suite's bound.
(import (chezscheme) (curl private engine) (curl private transfer) (curl private counters))

(define args (command-line-arguments))
(define mode (string->symbol (car args)))
(define threads (string->number (cadr args)))
(define ms (string->number (caddr args)))
(define url (cadddr args))

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

(define engine (make-curl-engine))
(define mx (make-mutex))
(define done 0)
(define finished 0)
(define stop #f)

(define (request) (make-curl-request url 'timeout-ms 20000))

;; refusal-who : (-> Any) -> Any
;; The who of THUNK's assertion violation, or (answered).
(define (refusal-who thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e)) (condition-who e))
            (#t '(raised)))
    (thunk)
    '(answered)))

(when (eq? mode 'critical)
  (let* ((t (curl-submit engine (request)))
         (await (refusal-who (lambda () (critical-section (curl-token-await t)))))
         (stop (refusal-who (lambda () (critical-section (curl-engine-stop engine)))))
         (make (refusal-who (lambda () (critical-section (make-curl-engine))))))
    (guard (e (#t #f)) (curl-token-await t))
    (curl-engine-stop engine)
    (write (list 'critical await stop make))
    (newline)
    (write (list 'counts (native-counts)))
    (newline)
    (exit 0)))

(when (eq? mode 'wake)
  (let loop ((i 0) (longest 0))
    (if (= i threads)
        (begin
          (curl-engine-stop engine)
          (write (list 'wake threads longest))
          (newline)
          (write (list 'counts (native-counts)))
          (newline)
          (exit 0))
        (let* ((t (curl-submit engine (request)))
               (seen #f)
               (watcher-mx (make-mutex)))
          (fork-thread
           (lambda ()
             (let watch ()
               (if (curl-token-done? t)
                   (with-mutex watcher-mx (set! seen (now-ms)))
                   (begin (sleep (make-time 'time-duration 1000000 0)) (watch))))))
          (guard (e (#t #f)) (curl-token-await t))
          (let ((returned (now-ms)))
            (let wait ()
              (unless (with-mutex watcher-mx seen)
                (sleep (make-time 'time-duration 1000000 0))
                (wait)))
            (loop (+ i 1) (max longest (- returned (with-mutex watcher-mx seen)))))))))

(when (eq? mode 'cpu)
  (let* ((c0 (cpu-time)) (t0 (now-ms)))
    (guard (e (#t #f)) (curl-token-await (curl-submit engine (request))))
    (let ((cpu (- (cpu-time) c0)) (wall (- (now-ms) t0)))
      (curl-engine-stop engine)
      (write (list 'cpu cpu wall))
      (newline)
      (write (list 'counts (native-counts)))
      (newline)
      (exit 0))))

(when (eq? mode 'latency)
  (let ((t0 (now-ms)))
    (do ((i 0 (+ i 1))) ((= i threads))
      (curl-token-await (curl-submit engine (request))))
    (let ((elapsed (- (now-ms) t0)))
      (curl-engine-stop engine)
      (write (list 'latency threads elapsed))
      (newline)
      (write (list 'counts (native-counts)))
      (newline)
      (exit 0))))

(define collections-before (collections))

(do ((i 0 (+ i 1))) ((= i threads))
  (fork-thread
   (lambda ()
     (let loop ()
       (if (with-mutex mx stop)
           (with-mutex mx (set! finished (+ finished 1)))
           (begin
             (let ((answered (guard (e (#t #f))
                               (curl-response-status
                                (curl-token-await (curl-submit engine (request)))))))
               (when (eqv? answered 200)
                 (with-mutex mx (set! done (+ done 1)))))
             (loop)))))))

(sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000)))
(with-mutex mx (set! stop #t))
(let wait ()
  (unless (= (with-mutex mx finished) threads)
    (sleep (make-time 'time-duration 10000000 0))
    (wait)))
(curl-engine-stop engine)
(write (list 'awaiters threads (with-mutex mx done) (- (collections) collections-before)))
(newline)
(write (list 'counts (native-counts)))
(newline)
