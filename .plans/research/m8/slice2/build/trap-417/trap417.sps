;;; The 417 trap (M8 slice 2's build): test-headers' 417 case alone, a POST
;;; of 10 digits with the caller's Expect: 100-continue to /raw/head417 of
;;; a 417 of 500 lines and a 200 of 500, 1,000 in all, at the cap: taken
;;; when libcurl resends on the 417's connection, refused header-limit when
;;; a second 417 is counted. Each request on an engine of its own.
;;;
;;;   scheme --libdirs src:tests:build/scheme-libs --program trap417.sps RUN VARIANT COUNT
;;;
;;; VARIANT fixed raises EXPECT_100_TIMEOUT_MS to 60,000 through the hatch,
;;; as test-headers does; plain leaves libcurl's 1,000 ms; verbose is fixed
;;; with VERBOSE 1, libcurl's own account of the transfer on stderr. One line per
;;; request: RUN, VARIANT, its index, its key, its outcome, and its wall ms.
(import (rnrs) (only (chezscheme) command-line-arguments current-time time-second time-nanosecond)
        (curl-testing) (curl) (curl unsupported))
(define args (command-line-arguments))
(define run (car args))
(define variant (string->symbol (cadr args)))
(define count (string->number (caddr args)))
(define (now-ms) (let ((t (current-time 'time-monotonic))) (+ (* 1000.0 (time-second t)) (/ (time-nanosecond t) 1e6))))
(define (answer-of outcome)
  (cond ((curl-response? outcome) (list 'response (curl-response-status outcome) (length (curl-response-headers outcome))))
        ((curl-transfer-error? outcome) (list 'refused (curl-transfer-error-reason outcome) (curl-transfer-error-code outcome)))
        (else (list 'other outcome))))
(call-with-origin
 (lambda (o)
   (let loop ((i 0))
     (when (< i count)
       (let* ((key (string-append "r" run "-" (symbol->string variant) "-" (number->string i)))
              (url (string-append "http://127.0.0.1:" (number->string (cdr (origin-face o 'raw)))
                                  "/raw/head417?key=" key "&a.n=500&b.n=500"))
              (base (make-curl-request url 'proxy #f 'timeout-ms 30000 'method 'post
                                       'body (string->utf8 "0123456789")
                                       'headers '(("Expect" . "100-continue"))))
              (request (case variant
                         ((fixed) (curl-request-with-options base '(("EXPECT_100_TIMEOUT_MS" . 60000))))
                         ((verbose) (curl-request-with-options base '(("EXPECT_100_TIMEOUT_MS" . 60000) ("VERBOSE" . 1))))
                         (else base)))
              (e (make-curl-engine))
              (t0 (now-ms))
              (token (curl-submit e request))
              (ended (curl-token-wait token 40000))
              (t1 (now-ms)))
         (display (string-append "trap417 run=" run " variant=" (symbol->string variant) " i=" (number->string i)
                                 " key=" key " ended=" (if ended "yes" "no") " outcome="))
         (write (answer-of (curl-token-outcome token)))
         (display (string-append " ms=" (number->string (round (- t1 t0))) "\n"))
         (curl-engine-stop e))
       (loop (+ i 1))))))
(exit 0)
