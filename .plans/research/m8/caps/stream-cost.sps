;;; M8's header-caps probe, case 6 (2026-11-06): what a Scheme callable per
;;; header line costs, through today's (curl), unchanged, on lane X alone.
;;;
;;;   scheme --libdirs src --program stream-cost.sps H1PORT ROUNDS
;;;
;;; H1PORT is server.mjs's h1 face: plaintext HTTP/1.1, the head written by
;;; hand. Each request is a GET on one engine, direct, a 60 s timeout:
;;;   buffered  no stream-buffer: libcurl hands the head to no callable, and
;;;             finish-transfer walks the headers once, curl_easy_nextheader
;;;             and a Latin-1 copy of each name and value.
;;;   streamed  stream-buffer 65536: read-head, a __collect_safe callable,
;;;             takes every line libcurl hands; head-line! walks the headers
;;;             at the final head, and finish-transfer again at the end.
;;; Each against two heads of N lines:
;;;   final     /head?n=N: a 200 of N header lines.
;;;   pre       /head?pre=103:N-2:16&n=2: a 103 of N - 2 lines, then a 200 of
;;;             2. The callable takes N + 4 lines, as many as final's N + 2
;;;             but 2, and the walk returns 2 headers (it skips the 103's,
;;;             CURLH_1XX), scanning the N stored.
;;; And a base, /head?n=2, both ways. N is 1000 and 5000: 8.20.0 stores 5,000
;;; at most, the 103's among them.
;;;
;;; Per request, one line: its kind, N, round, status, the headers the
;;; response holds, whether a streamed token held its head, and three times:
;;; cpu_ms, the process's CPU from the submit to the end, the engine's
;;; thread's work, a collector's and this thread's polls among it; wall_ms,
;;; the monotonic time from the submit until curl-token-wait returns, whose
;;; polls sleep up to 10 ms; total_us, libcurl's own total, which ends as
;;; libcurl ends the transfer, before finish-transfer's walk. The order turns
;;; each round, so every kind meets every position.
(import (chezscheme) (curl))

(define args (command-line-arguments))
(define port (string->number (car args)))
(define rounds (string->number (cadr args)))

(define (ms-of t) (+ (* (time-second t) 1000.0) (/ (time-nanosecond t) 1e6)))
(define (now-ms what) (ms-of (current-time what)))

(define (url-of path) (string-append "http://127.0.0.1:" (number->string port) path))

(define engine (make-curl-engine))

;; one : Symbol Symbol Natural Natural String -> Void
(define (one way head n round path)
  (let* ((tag (string-append "c6." (symbol->string way) "." (symbol->string head) "."
                             (number->string n) ".r" (number->string round)))
         (full (string-append path "&tag=" tag))
         (base (make-curl-request (url-of full) 'proxy #f 'timeout-ms 60000))
         (request (if (eq? way 'streamed) (curl-request-with base 'stream-buffer 65536) base))
         (c0 (now-ms 'time-process))
         (w0 (now-ms 'time-monotonic))
         (token (curl-submit engine request))
         (ended (curl-token-wait token 60000))
         (w1 (now-ms 'time-monotonic))
         (c1 (now-ms 'time-process))
         (outcome (curl-token-outcome token)))
    (if (curl-response? outcome)
        (let ((timings (curl-response-timings outcome)))
          (printf "c6 way=~a head=~a n=~a round=~a ended=~a status=~a headers=~a held_head=~a cpu_ms=~,2f wall_ms=~,2f total_us=~a~%"
                  way head n round ended (curl-response-status outcome)
                  (length (curl-response-headers outcome))
                  (if (eq? way 'streamed)
                      (let ((h (curl-token-head token))) (if h (length (curl-head-headers h)) 'none))
                      '-)
                  (- c1 c0) (- w1 w0) (cdr (assq 'total timings))))
        (printf "c6 way=~a head=~a n=~a round=~a ended=~a outcome=~s cpu_ms=~,2f wall_ms=~,2f~%"
                way head n round ended
                (if (condition? outcome)
                    (call-with-string-output-port (lambda (p) (display-condition outcome p)))
                    outcome)
                (- c1 c0) (- w1 w0)))))

(define plan
  (append
   (list (list 'buffered 'base 2 "/head?n=2") (list 'streamed 'base 2 "/head?n=2"))
   (apply append
          (map (lambda (n)
                 (let ((final (string-append "/head?n=" (number->string n)))
                       (pre (string-append "/head?pre=103:" (number->string (- n 2)) ":16&n=2")))
                   (list (list 'buffered 'final n final) (list 'streamed 'final n final)
                         (list 'buffered 'pre n pre) (list 'streamed 'pre n pre))))
               '(1000 5000)))))

(printf "c6 start port=~a rounds=~a requests_per_round=~a machine=~a threaded=~a~%"
        port rounds (length plan) (machine-type) (threaded?))
;; One warm request each way, so the first round pays no first use.
(one 'buffered 'warm 2 0 "/head?n=2")
(one 'streamed 'warm 2 0 "/head?n=2")
(let loop ((r 0))
  (when (< r rounds)
    (let ((k (length plan)))
      (let turn ((i 0))
        (when (< i k)
          (let ((p (list-ref plan (mod (+ i (* r 3)) k))))
            (apply one (car p) (cadr p) (caddr p) r (list (cadddr p))))
          (turn (+ i 1)))))
    (loop (+ r 1))))
(curl-engine-stop engine)
(printf "c6 done~%")
(exit 0)
