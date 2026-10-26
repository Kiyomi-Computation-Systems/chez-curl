;;; M3 slice 3: how late a 500 ms timeout's 28 comes on an engine while its
;;; lookup stalls (ADR-0019, amended 2026-10-25), under the stand-in, which
;;; run.sh's timeout-late set loads with a 3,000 ms stall. N transfers, one
;;; after another, each on a fresh engine, as tests/engine-stall.sps's
;;; timeout is, or all on one. Prints the largest lateness, and every one
;;; above 50 ms.
;;;
;;;   timeout-late.sps fresh|shared N
(import (chezscheme) (curl private engine) (curl private transfer) (curl private conditions))

(define mode (string->symbol (car (command-line-arguments))))
(define n (string->number (cadr (command-line-arguments))))

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

(define shared (and (eq? mode 'shared) (make-curl-engine)))

(define late
  (map (lambda (i)
         (let* ((e (or shared (make-curl-engine)))
                (t0 (now-ms))
                (token (curl-engine-submit e (make-transfer-request (format "http://t~a.stall.invalid/" i)
                                                                    'get '() #f 500 #f #f #t #f)))
                (code (guard (x ((curl-transfer-error? x) (curl-transfer-error-code x)))
                        (curl-token-await token) 'ok))
                (ms (- (now-ms) t0 500)))
           (unless shared (curl-engine-stop e))
           (list code ms)))
       (iota n)))
(when shared (curl-engine-stop shared))
(printf "timeout-late ~a ~a: codes ~s, latest ~a ms, above 50 ms ~s\n"
        mode n (sort < (map car (filter (lambda (x) (number? (car x))) late)))
        (apply max (map cadr late)) (filter (lambda (x) (> (cadr x) 50)) late))
