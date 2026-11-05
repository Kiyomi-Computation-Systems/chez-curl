#!r6rs
;;; M7 slice 4's review: two paths of the jar's lifetime test-cookies does
;;; not reach, each through the engine's fault seam. One line each,
;;; "probe: CASE RESULT".
;;;
;;;   batch    a jar made on an engine whose fault is planted at setup;
;;;            then, in one hold, a submit and a load of the jar, so the
;;;            failing turn takes both in its batch: the submit's set-up
;;;            raises, and the load is never carried out. Its reply, waited
;;;            for on a thread of its own, within 5 s: what it answered, or
;;;            (not-answered 5000). fail-engine! answers the batch's jar
;;;            messages and the queue's.
;;;   free     a jar's transfer on an engine whose fault is planted at
;;;            free, after take-out! has let the transfer's hold go; the
;;;            failure then takes the transfer out again: the token's
;;;            outcome, and the jar's holders and state after. The table of
;;;            holds lets a hold go once.
;;;
;;; Run from a tree's root with src, tests and the SRFI libraries on the
;;; library path (README.md here).
(import (rnrs)
        (only (chezscheme) fork-thread make-mutex with-mutex critical-section sleep make-time
              current-time time-second time-nanosecond)
        (curl)
        (curl-testing)
        (only (curl private engine) make-faulty-curl-engine call-with-engine-held
              curl-cookie-jar-post! curl-cookie-jar-await curl-cookie-jar-holders
              curl-cookie-jar-state)
        (only (curl private counters) native-counts))

(define (say tag x)
  (display "probe: ") (display tag) (display " ") (write x) (newline)
  (flush-output-port (current-output-port)))

(define (refusal e)
  (cond ((curl-request-error? e) (list 'request-refused (curl-request-error-reason e)))
        ((curl-transfer-error? e) (list 'transfer-failed (curl-transfer-error-reason e)))
        ((curl-engine-error? e) (list 'engine-error (curl-engine-error-reason e)))
        ((and (pair? e) (eq? (car e) 'raised)) (list 'raised (refusal (cadr e))))
        (else e)))

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

(define (pause-ms ms) (sleep (make-time 'time-duration (* ms 1000000) 0)))

;; within : (-> Any) Natural -> Any
;; THUNK's answer on a thread of its own, or (not-answered MS).
(define (within thunk ms)
  (let ((box (vector #f)) (lock (make-mutex)))
    (fork-thread (lambda ()
                   (let ((a (guard (e (#t (list 'thread-raised (refusal e)))) (list 'answered (thunk)))))
                     (critical-section (with-mutex lock (vector-set! box 0 a))))))
    (let ((deadline (+ (now-ms) ms)))
      (let loop ()
        (or (critical-section (with-mutex lock (vector-ref box 0)))
            (if (< (now-ms) deadline) (begin (pause-ms 5) (loop)) (list 'not-answered ms)))))))

(define line "a.localhost\tFALSE\t/\tFALSE\t0\tn\tv")

(call-with-origin
 (lambda (o)
   (let ((port (number->string (cdr (origin-face o 'http)))))
     ;; batch
     (let* ((e (make-faulty-curl-engine 'setup))
            (jar (make-curl-cookie-jar e))
            (reply #f))
       (call-with-engine-held e
         (lambda ()
           (curl-submit e (make-curl-request (string-append "http://a.localhost:" port "/cookies?key=b")
                                             'proxy #f 'cookie-jar jar))
           (set! reply (curl-cookie-jar-post! jar 'load (list line)))))
       (say 'batch (let ((a (within (lambda () (curl-cookie-jar-await jar reply)) 5000)))
                     (if (eq? (car a) 'answered) (list 'answered (refusal (cadr a))) a)))
       (say 'batch-engine (guard (x (#t (refusal x))) (curl-engine-stop e) 'stopped)))
     ;; free
     (let* ((e (make-faulty-curl-engine 'free))
            (jar (make-curl-cookie-jar e))
            (t (curl-submit e (make-curl-request (string-append "http://a.localhost:" port "/cookies?key=f")
                                                 'proxy #f 'cookie-jar jar 'timeout-ms 10000))))
       (curl-token-wait t 15000)
       (say 'free (list (refusal (curl-token-outcome t))
                        (curl-cookie-jar-holders jar) (curl-cookie-jar-state jar)))
       (guard (x (#t #f)) (curl-engine-stop e))))))
(say 'counts (native-counts))
