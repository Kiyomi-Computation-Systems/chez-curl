;;; cost-build.sps [REPS]: cost.sps on the built change, its seam the
;;; private gate drive-checks-gate-set!, its marks start and end, for
;;; the comments' numbers. Each case
;;; is one call whose seam raises 'stop-here at its last end mark, so the
;;; checks run whole and nothing is submitted (the URL is never contacted).
;;;
;;; For each case, REPS (3) runs with no other thread busy: the checks'
;;; time, enter to exit, in ms, the least and the most; then one run beside
;;; a thread that asks for a collection back to back (collect-rendezvous,
;;; 1 ms apart): its longest stall that overlapped the checks, in ms, a
;;; rendezvous's own wait or a gap between two past the 1 ms sleep, and how
;;; many of its rendezvous ended inside the checks. A stall is how long
;;; another thread's collection is held off: by a critical section around
;;; the checks, up to the section's length, less the time the section
;;; spends in __collect_safe calls; outside one, until this thread's next
;;; event check, or the end of a primitive that makes none, a large copy's.
;;; Then one run whose first enter sends SIGINT to this process: how long
;;; the Ctrl-C handler waited, in ms. Prints (cost CASE (checks-ms MIN MAX)
;;; (collector-stall-ms MAX) (ctrl-c-ms MS) (collections-ended-inside N)).
;;; Run from a copy's root.
(import (chezscheme) (curl) (http-client) (only (http-client private drive) drive-checks-gate-set!) (curl private counters))

(define reps (if (null? (command-line-arguments)) 3 (string->number (car (command-line-arguments)))))
(define url "http://127.0.0.1:9/never")

(define (now-ns)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000000000) (time-nanosecond t))))

(define session (make-http-session 'timeout-ms 20000))

;; The seam: the time of the first enter and of the EXITS-th exit, which
;; raises 'stop-here.
(define enter-ns #f)
(define exit-ns #f)
(define exits-left 0)
(define (arm! exits)
  (set! enter-ns #f)
  (set! exit-ns #f)
  (set! exits-left exits)
  (drive-checks-gate-set! (lambda (w)
               (case w
                 ((start) (unless enter-ns (set! enter-ns (now-ns))))
                 ((end)
                  (set! exits-left (- exits-left 1))
                  (when (= exits-left 0)
                    (set! exit-ns (now-ns))
                    (raise 'stop-here)))))))

;; The Ctrl-C run: at the first enter, SIGINT to this process; the
;; handler, which returns, records when it ran, so the call goes on to its
;; stop. Its delay is how long a keyboard interrupt waited.
(load-shared-object "libc.so.6")
(define kill (foreign-procedure "kill" (int int) int))
(define sigint-ns #f)
(define handled-ns #f)
(define (arm-sigint! exits)
  (arm! exits)
  (set! sigint-ns #f)
  (set! handled-ns #f)
  (let ((inner (lambda (w)
                 (case w
                   ((start) (unless enter-ns
                              (set! enter-ns (now-ns))
                              (set! sigint-ns (now-ns))
                              (kill (get-process-id) 2)))
                   ((end)
                    (set! exits-left (- exits-left 1))
                    (when (= exits-left 0)
                      (set! exit-ns (now-ns))
                      (raise 'stop-here)))))))
    (drive-checks-gate-set! inner)))
(define (ctrl-c-delay thunk exits)
  (keyboard-interrupt-handler (lambda () (unless handled-ns (set! handled-ns (now-ns)))))
  (arm-sigint! exits)
  (let ((r (guard (e (#t e)) (thunk) 'returned)))
    (drive-checks-gate-set! #f)
    (let ((answer (and (eq? r 'stop-here) sigint-ns handled-ns (- handled-ns sigint-ns))))
      (keyboard-interrupt-handler void)
      answer)))

;; The collector: when on, a thread that asks for a collection back to back,
;; 1 ms apart, recording each wait's start and end.
(define c-lock (make-mutex))
(define c-on #f)
(define c-stop #f)
(define c-waits '())
(define (c-flag get) (critical-section (with-mutex c-lock (get))))
(define collector
  (fork-thread
   (lambda ()
     (let loop ()
       (unless (c-flag (lambda () c-stop))
         (if (c-flag (lambda () c-on))
             (let* ((t0 (now-ns)) (ignored (collect-rendezvous)) (t1 (now-ns)))
               (critical-section (with-mutex c-lock (set! c-waits (cons (cons t0 t1) c-waits)))))
             (sleep (make-time 'time-duration 1000000 0)))
         (sleep (make-time 'time-duration 1000000 0))
         (loop))))))

;; run : (-> Any) Natural -> (U Natural #f)
;; THUNK's call, its checks stopped at the EXITS-th exit: their time in ns,
;; or #f when the stop never came (printed).
(define (run thunk exits)
  (arm! exits)
  (let ((r (guard (e (#t e)) (thunk) 'returned)))
    (drive-checks-gate-set! #f)
    (if (and (eq? r 'stop-here) enter-ns exit-ns)
        (- exit-ns enter-ns)
        (begin (write (list 'no-stop r)) (newline) #f))))

(define (ms ns) (/ (round (/ ns 10000.0)) 100.0))

(define ctrl-c #f)
(define (measure name thunk exits)
  (collect-rendezvous)
  (let ((times (let loop ((i 0) (acc '()))
                 (if (= i reps) acc (loop (+ i 1) (cons (run thunk exits) acc))))))
    (collect-rendezvous)
    (set! ctrl-c (ctrl-c-delay thunk exits))
    (collect-rendezvous)
    (critical-section (with-mutex c-lock (set! c-waits '()) (set! c-on #t)))
    (sleep (make-time 'time-duration 20000000 0))
    (let ((ignored (run thunk exits)))
      (let* ((window-start enter-ns) (window-end exit-ns))
        (sleep (make-time 'time-duration 20000000 0))
        (critical-section (with-mutex c-lock (set! c-on #f)))
        ;; The collector's stalls: each rendezvous, start to end, and each
        ;; gap from one's end to the next one's start, less the 1 ms sleep
        ;; between: a thread that wakes from its sleep while a collection
        ;; is due waits for it before it can ask again. The longest that
        ;; overlaps the checks, and how many rendezvous ended inside them.
        (let* ((waits (list-sort (lambda (a b) (< (car a) (car b))) (c-flag (lambda () c-waits))))
               (spans (append waits
                              (let loop ((rest waits) (acc '()))
                                (if (or (null? rest) (null? (cdr rest)))
                                    acc
                                    (loop (cdr rest)
                                          (cons (cons (+ (cdr (car rest)) 1000000) (car (cadr rest))) acc))))))
               (over (filter (lambda (w) (and window-start window-end
                                               (<= (car w) window-end) (>= (cdr w) window-start)))
                             spans))
               (longest (fold-left (lambda (m w) (max m (- (cdr w) (car w)))) 0 over))
               (inside (length (filter (lambda (w) (and window-start window-end
                                                         (<= window-start (cdr w) window-end)))
                                       waits))))
          (write (list 'cost name
                       (if (memv #f times) (list 'checks-ms 'failed)
                           (list 'checks-ms (ms (apply min times)) (ms (apply max times))))
                       (list 'collector-stall-ms (ms longest))
                       (list 'ctrl-c-ms (if ctrl-c (ms ctrl-c) 'none))
                       (list 'collections-ended-inside inside)))
          (newline)
          (flush-output-port (current-output-port)))))))

(define (bytes n) (make-bytevector n 120))
(define (text n) (make-string n #\a))
(define (mixed n)
  (let ((s (make-string n)))
    (do ((i 0 (+ i 1))) ((= i n) s)
      (string-set! s i (string-ref "a b/\xE9;-c&d=e" (mod i 11))))))

(define cases
  (list
   (list 'get-plain (lambda () (http-get session url)) 1)
   (list 'post-bytevector-1MiB (let ((b (bytes (expt 2 20)))) (lambda () (http-post session url 'body b))) 1)
   (list 'post-bytevector-16MiB (let ((b (bytes (expt 2 24)))) (lambda () (http-post session url 'body b))) 1)
   (list 'post-bytevector-64MiB (let ((b (bytes (expt 2 26)))) (lambda () (http-post session url 'body b))) 1)
   (list 'post-bytevector-256MiB (let ((b (bytes (expt 2 28)))) (lambda () (http-post session url 'body b))) 1)
   (list 'post-string-16Mi-chars (let ((s (text (expt 2 24)))) (lambda () (http-post session url 'body s))) 1)
   (list 'post-string-64Mi-chars (let ((s (text (expt 2 26)))) (lambda () (http-post session url 'body s))) 1)
   (list 'form-one-pair-1Mi-chars
         (let ((f (list (cons "k" (mixed (expt 2 20)))))) (lambda () (http-post session url 'form f))) 1)
   (list 'form-one-pair-16Mi-chars
         (let ((f (list (cons "k" (mixed (expt 2 24)))))) (lambda () (http-post session url 'form f))) 1)
   (list 'form-100000-pairs
         (let ((f (map (lambda (i) (cons (string-append "k" (number->string i)) "v a/l")) (iota 100000))))
           (lambda () (http-post session url 'form f))) 1)
   (list 'headers-1000
         (let ((h (map (lambda (i) (cons (string-append "X-H" (number->string i)) "value")) (iota 1000))))
           (lambda () (http-get session url 'headers h))) 1)
   (list 'headers-10000
         (let ((h (map (lambda (i) (cons (string-append "X-H" (number->string i)) "value")) (iota 10000))))
           (lambda () (http-get session url 'headers h))) 1)
   (list 'headers-100000
         (let ((h (map (lambda (i) (cons (string-append "X-H" (number->string i)) "value")) (iota 100000))))
           (lambda () (http-get session url 'headers h))) 1)
   (list 'url-1MB-path
         (let ((u (string-append "http://127.0.0.1:9/" (text 1000000)))) (lambda () (http-get session u))) 1)
   (list 'url-7.9MB-path
         (let ((u (string-append "http://127.0.0.1:9/" (text 7900000)))) (lambda () (http-get session u))) 1)
   (list 'params-100000-pairs
         (let ((p (map (lambda (i) (cons (string-append "k" (number->string i)) "v")) (iota 100000))))
           (lambda () (http-get session url 'params p))) 1)
   (list 'parallel-1000-gets
         (let ((specs (map (lambda (i) (list 'get url)) (iota 1000))))
           (lambda () (http-parallel session specs))) 1000)
   (list 'parallel-32-posts-of-4MiB
         (let ((specs (map (lambda (i) (list 'post url 'body (bytes (* 4 (expt 2 20))))) (iota 32))))
           (lambda () (http-parallel session specs))) 32)))

(for-each (lambda (c) (measure (car c) (cadr c) (caddr c))) cases)
(critical-section (with-mutex c-lock (set! c-stop #t)))
(sleep (make-time 'time-duration 50000000 0))
(http-session-close session)
(write (list 'counts (native-counts)))
(newline)
