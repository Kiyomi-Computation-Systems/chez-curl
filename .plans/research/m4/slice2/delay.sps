;;; M4 slice 2's second measurement (the M4 plan, section 5.1): a take's
;;; delay, from a token's completion to the take that returns it.
;;;
;;;   delay.sps WAIT RAW-PORT COUNT
;;;
;;; COUNT transfers, one after another, each /raw/pause-mid-body?ms=M on the
;;; test origin's raw face, M from 50 to 290 ms, spread over every residue
;;; modulo 10: the wait's 10 ms sleeps keep the phase of its submit, so
;;; pauses all multiples of 10 ms would meet them at one phase, and show
;;; one delay (the first run, kept in results). Each is submitted with a
;;; mailbox and waited for at once, as WAIT says: take, by
;;; curl-mailbox-take, bounded at 10 s, or await, by curl-token-await, the
;;; control, which waits as a take does. So the wait's sleeps have grown to
;;; 10 ms by the time the transfer ends.
;;;
;;; A watcher thread reads curl-token-done? every 200 us, and notes when it
;;; first sees the token done: the completion, to within its own pace. The
;;; delay is the time from there to the wait's return, which can be
;;; negative by that pace.
;;;
;;; Prints (delay WAIT COUNT MIN MEDIAN P90 MAX), each in us, then
;;; (samples ...), in the order they ran, each (DELAY LATE): the delay, and
;;; how late the wait returned after the M ms the script pauses, from the
;;; submit, both in us; then (counts ...) once the engine has stopped. LATE
;;; holds the origin's and libcurl's time too: an upper bound where the
;;; watcher's pace slips, as under Valgrind.
(import (chezscheme) (curl private engine) (curl private transfer) (curl private counters))

(define args (command-line-arguments))
(define wait-name (string->symbol (car args)))
(define port (cadr args))
(define count (string->number (caddr args)))

(define (now-us)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000000) (div (time-nanosecond t) 1000))))

(define engine (make-curl-engine))
(define mailbox (make-curl-mailbox))
(define lock (make-mutex))
(define watched #f)    ; the token the watcher watches, or #f
(define seen #f)       ; when the watcher first saw it done
(define finished #f)

(define watcher
  (fork-thread
   (lambda ()
     (let loop ()
       (let ((token (with-mutex lock watched)))
         (when (and token (curl-token-done? token))
           (with-mutex lock
             (when (and (eq? watched token) (not seen)) (set! seen (now-us))))))
       (unless (with-mutex lock finished)
         (sleep (make-time 'time-duration 200000 0))
         (loop))))))

(define (one i)
  (let* ((ms (+ 50 (mod (* i 37) 241)))
         (url (format "http://127.0.0.1:~a/raw/pause-mid-body?ms=~a" port ms))
         (submitted (now-us))
         (token (curl-submit engine (make-curl-request url 'timeout-ms 10000) mailbox)))
    (with-mutex lock (set! watched token) (set! seen #f))
    (case wait-name
      ((take) (unless (eq? (curl-mailbox-take mailbox 10000) token)
                (error 'delay.sps "the take answered no token" i)))
      ((await) (curl-token-await token)
               ;; empty the mailbox, which the await left the token in
               (curl-mailbox-take mailbox 0))
      (else (error 'delay.sps "no such wait" wait-name)))
    (let ((returned (now-us)))
      ;; the watcher's pace bounds how late it can be: give it that to see it
      (sleep (make-time 'time-duration 200000000 0))
      (let ((s (with-mutex lock seen)))
        (unless s (error 'delay.sps "the watcher never saw the token done" i))
        (list (- returned s) (- returned submitted (* ms 1000)))))))

(define samples
  (let loop ((i 0) (acc '()))
    (if (= i count) (reverse acc) (loop (+ i 1) (cons (one i) acc)))))
(with-mutex lock (set! finished #t))
(curl-engine-stop engine)

(define sorted (list-sort < (map car samples)))
(define (at q) (list-ref sorted (min (- count 1) (exact (floor (* q count))))))
(write (list 'delay wait-name count (car sorted) (at 1/2) (at 9/10) (list-ref sorted (- count 1))))
(newline)
(write (cons 'samples samples))
(newline)
(write (list 'counts (native-counts)))
(newline)
