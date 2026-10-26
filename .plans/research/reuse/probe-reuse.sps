#!r6rs
;;; Review probe: test-engine's reuse check, replayed RUNS times, each on an
;;; engine of its own, with knobs.
;;;   scheme --libdirs src:tests:SRFI --program .plans/research/reuse/probe-reuse.sps \
;;;     N BYTES GAP STAGGER PAUSE RUNS
;;; Written by the slice's review (ADR-0020, amended 2026-10-26); its results are
;;; results/review-*.log, named for what each varied; each line prints the
;;; spread of the submits and the pause before the last drip, as measured.
;;; N drips of BYTES at GAP ms, submitted STAGGER ms apart; once all answer,
;;; PAUSE ms, then one more drip of BYTES at GAP. Prints, per run, the
;;; ninth's outcome, the N answers' summary, how long the submits took, and
;;; the ms from the last of the N answering to the ninth's submit.
(import (rnrs)
        (only (chezscheme) sleep make-time current-time time-second time-nanosecond
              command-line-arguments iota)
        (curl-testing)
        (curl)
        (curl private engine)
        (curl private transfer)
        (curl private conditions))

(define args (map string->number (command-line-arguments)))
(define n (list-ref args 0))
(define bytes (list-ref args 1))
(define gap (list-ref args 2))
(define stagger (list-ref args 3))
(define pause (list-ref args 4))
(define runs (list-ref args 5))

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))
(define (pause-ms ms)
  (when (> ms 0) (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000)))))
(define (request url) (make-transfer-request url 'get '() #f 20000 #f #f #t #f))
(define (outcome token)
  (guard (e ((curl-transfer-error? e)
             (list 'transfer-error (curl-transfer-error-reason e) (curl-transfer-error-code e)))
            (#t (list 'raised (describe e))))
    (let ((deadline (+ (now-ms) 30000)))
      (let wait ()
        (cond ((curl-token-done? token)
               (let ((r (curl-token-await token)))
                 (list 'response (transfer-response-status r) (bytevector-length (transfer-response-body r)))))
              ((> (now-ms) deadline) '(never-completed))
              (else (pause-ms 1) (wait)))))))

(call-with-origin
 (lambda (o)
   (define drip
     (let ((f (origin-face o 'raw)))
       (string-append "http://" (car f) ":" (number->string (cdr f))
                      "/raw/drip?bytes=" (number->string bytes) "&gap=" (number->string gap))))
   (let loop ((i 0))
     (when (< i runs)
       (let* ((engine (make-curl-engine))
              (t0 (now-ms))
              (tokens (let submit ((k 0) (acc '()))
                        (if (= k n)
                            (reverse acc)
                            (let ((t (curl-engine-submit engine (request drip))))
                              (when (< (+ k 1) n) (pause-ms stagger))
                              (submit (+ k 1) (cons t acc))))))
              (spread (- (now-ms) t0))
              (answers (map outcome tokens))
              (t1 (now-ms))
              (ninth (begin (pause-ms pause)
                            (let ((t2 (now-ms)))
                              (cons (- t2 t1) (curl-engine-submit engine (request drip))))))
              (ninth-outcome (outcome (cdr ninth))))
         (curl-engine-stop engine)
         (write (list 'run i 'ninth ninth-outcome
                      'answers-ok (for-all (lambda (a) (equal? a (list 'response 200 bytes))) answers)
                      'submit-spread-ms spread 'end-to-ninth-ms (car ninth)))
         (newline)
         (flush-output-port (current-output-port))
         (loop (+ i 1)))))))
