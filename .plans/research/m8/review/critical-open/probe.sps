;;; The M8 plan's review, 2026-11-06: what an open of a FIFO costs every other
;;; thread when it runs on the caller's thread at submit, as the plan's file
;;; check would (section 3.4: "the path must name a regular file that opens
;;; for reading, opened and closed then"), inside the critical section every
;;; high-level submit runs in (src/http-client/private/drive.sls:403, :1013,
;;; :1378, :1498), and outside one, at the low level's own curl-submit.
;;;
;;; Usage: scheme --program probe.sps CASE PATH
;;;   CASE  inside   (critical-section (open-file-input-port PATH)), closed
;;;         outside  (open-file-input-port PATH), closed, in no section
;;;         regular  (critical-section (open-file-input-port PATH)) on a
;;;                  regular file: the control
;;;   PATH  the file to open; for inside and outside a FIFO whose writer the
;;;         runner starts 2 s after this program, so the open blocks until
;;;         then
;;; A worker thread allocates 64 KiB at a time, with collect-trip-bytes at 1
;;; MiB, so a collection falls due every 16 allocations or so, and records
;;; the longest time between two of its allocations, and the collections
;;; made. It prints, one line each: the case, how long the open took, the
;;; worker's longest gap, its allocations, and the collections across the
;;; open, all in ms or counts.
(import (chezscheme))

(define args (command-line-arguments))
(define case-name (string->symbol (car args)))
(define path (cadr args))

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* 1000 (time-second t)) (quotient (time-nanosecond t) 1000000))))

(collect-trip-bytes (* 1024 1024))

(define lock (make-mutex))
(define done #f)
(define worst 0)
(define allocations 0)
(define finished #f)

(define (done?) (with-mutex lock done))

(define worker
  (fork-thread
   (lambda ()
     (let loop ((last (now-ms)) (w 0) (n 0))
       (if (done?)
           (with-mutex lock (set! worst w) (set! allocations n) (set! finished #t))
           (begin
             (make-bytevector 65536 0)
             (let* ((t (now-ms)) (gap (- t last)))
               (loop t (max w gap) (+ n 1)))))))))

;; let the worker run a while first
(sleep (make-time 'time-duration 0 1))
(define before (collections))
(define start (now-ms))
(define (open-and-close)
  (let ((p (open-file-input-port path)))
    (close-port p)))
(case case-name
  ((inside regular) (critical-section (open-and-close)))
  ((outside) (open-and-close))
  (else (error 'probe "unknown case" case-name)))
(define took (- (now-ms) start))
(define after (collections))
(sleep (make-time 'time-duration 300000000 0))
(with-mutex lock (set! done #t))
(let wait ()
  (unless (with-mutex lock finished)
    (sleep (make-time 'time-duration 1000000 0))
    (wait)))
(printf "case ~a open-ms ~a worker-worst-gap-ms ~a worker-allocations ~a collections-across-open ~a\n"
        case-name took worst allocations (- after before))
