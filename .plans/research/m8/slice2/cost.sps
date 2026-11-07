;;; M8 slice 2's cost of the buffered transfer's new callable (the M8 plan,
;;; section 5), through (curl) alone, so it runs alike on main's tree and the
;;; prototype's: the caps probe's case 6, buffered alone.
;;;
;;;   scheme --libdirs src --program cost.sps LANE H1PORT ROUNDS
;;;
;;; H1PORT is the caps stand-in's h1 face. Each request is a GET on one
;;; engine, direct, a 60 s timeout, no stream-buffer: on main no callable
;;; takes the head, on the prototype read-head takes every line. Three heads:
;;;   base   /head?n=2: a 200 of 2 lines.
;;;   final  /head?n=1000: a 200 of 1,000 lines, the cap's own count; the
;;;          callable takes 1,002 lines, and the walk returns 1,000.
;;;   pre    /head?pre=103:500:16&n=500: a 103 of 500 lines and a 200 of
;;;          500, 1,000 in all; the callable takes 1,004 lines, and the walk
;;;          returns 500, scanning the 1,000 stored.
;;; Per request, one line: kind, round, status, headers, cpu_ms, the
;;; process's CPU from the submit to the wait's return, the engine's thread's
;;; work and this thread's polls; wall_ms; total_us, libcurl's total, which
;;; holds the callable's calls, made inside curl_multi_perform, and not
;;; finish-transfer's walk, made after it. Before each request every thread
;;; collects, by collect-rendezvous, outside the measured window. The order
;;; turns each round.
(import (chezscheme) (curl))

(define args (command-line-arguments))
(define lane (car args))
(define port (cadr args))
(define rounds (string->number (caddr args)))

(define (ms-of t) (+ (* (time-second t) 1000.0) (/ (time-nanosecond t) 1e6)))
(define (now-ms what) (ms-of (current-time what)))

(define engine (make-curl-engine))

(define (one kind round path)
  (let* ((request (make-curl-request (string-append "http://127.0.0.1:" port path "&tag=cost." (symbol->string kind)
                                                    ".r" (number->string round))
                                     'proxy #f 'timeout-ms 60000))
         ;; Every thread collects first, outside the measured window, so a
         ;; collection the last request's garbage owes falls before it.
         (collected (collect-rendezvous))
         (c0 (now-ms 'time-process))
         (w0 (now-ms 'time-monotonic))
         (token (curl-submit engine request))
         (ended (curl-token-wait token 60000))
         (w1 (now-ms 'time-monotonic))
         (c1 (now-ms 'time-process))
         (outcome (curl-token-outcome token)))
    (if (curl-response? outcome)
        (printf "cost lane=~a kind=~a round=~a ended=~a status=~a headers=~a cpu_ms=~,3f wall_ms=~,3f total_us=~a~%"
                lane kind round ended (curl-response-status outcome) (length (curl-response-headers outcome))
                (- c1 c0) (- w1 w0) (cdr (assq 'total (curl-response-timings outcome))))
        (printf "cost lane=~a kind=~a round=~a ended=~a outcome=~s cpu_ms=~,3f wall_ms=~,3f~%"
                lane kind round ended
                (if (condition? outcome) (call-with-string-output-port (lambda (p) (display-condition outcome p))) outcome)
                (- c1 c0) (- w1 w0)))))

(define plan '((base "/head?n=2") (final "/head?n=1000") (pre "/head?pre=103:500:16&n=500")))

(printf "cost start lane=~a libcurl=~a port=~a rounds=~a machine=~a~%" lane
        (libcurl-info-version (loaded-libcurl)) port rounds (machine-type))
(one 'warm 0 "/head?n=2")
(one 'warm 0 "/head?n=1000")
(let loop ((r 0))
  (when (< r rounds)
    (let ((k (length plan)))
      (let turn ((i 0))
        (when (< i k)
          (let ((p (list-ref plan (mod (+ i r) k))))
            (one (car p) r (cadr p)))
          (turn (+ i 1)))))
    (loop (+ r 1))))
(curl-engine-stop engine)
(printf "cost done~%")
(exit 0)
