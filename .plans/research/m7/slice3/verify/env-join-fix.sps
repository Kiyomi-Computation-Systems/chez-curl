#!r6rs
;;; My variant (2026-11-03) of the review's env-join.sps: the case again,
;;; then a candidate fix: an engine that does not multiplex, CURLMOPT_PIPELINING
;;; 0, as 8.7.x's engines run. The original header follows.
;;; M7 slice 3's review: does a transfer through proxy environment ride a
;;; live tunnel that a named proxy's transfer opened with its userinfo?
;;; ADR-0037's decision 8 sets FRESH_CONNECT on a named proxy's tunnelled
;;; transfer below 8.19.0, so it joins nothing, and FORBID_REUSE beside
;;; userinfo, so it leaves nothing pooled. A transfer through the
;;; environment's proxy sets neither. Against the test origin: its http face
;;; is the proxy, and a CONNECT to localhost needs Basic for alice:s3cret;
;;; the h2 face answers /connection?delay=MS with its HTTP/2 session's
;;; number after MS ms.
;;;
;;;   A: https://localhost:<h2>/connection?delay=3000 through the named
;;;      proxy http://alice:s3cret@127.0.0.1:<http>, its stream live;
;;;   B: https://localhost:<h2>/connection, submitted while A's stream is
;;;      live, through proxy environment, https_proxy naming the same proxy
;;;      with no userinfo.
;;;
;;; Controls, run first: B alone, through the environment, and B through
;;; the named proxy with no userinfo while A is live: each must CONNECT on
;;; its own and be refused 407. Prints each outcome, each body, and the
;;; proxy's log lines each case made.
(import (rnrs)
        (only (chezscheme) parameterize putenv getenv sleep make-time current-time time-second time-nanosecond)
        (curl)
        (only (curl private engine) make-curl-engine-unmultiplexed)
        (curl-testing))

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))
(define (pause-ms ms) (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))

(define (split-lines text)
  (let loop ((start 0) (i 0) (found '()))
    (cond ((= i (string-length text))
           (reverse (if (= start i) found (cons (substring text start i) found))))
          ((char=? (string-ref text i) #\newline) (loop (+ i 1) (+ i 1) (cons (substring text start i) found)))
          (else (loop start (+ i 1) found)))))

(define (prefix? p s) (and (<= (string-length p) (string-length s)) (string=? p (substring s 0 (string-length p)))))

(define (outcome x)
  (cond ((curl-response? x)
         (list 'response (curl-response-status x) (utf8->string (curl-response-body x))))
        ((curl-transfer-error? x)
         (list 'failed (curl-transfer-error-code x) (curl-transfer-error-connect-code x)))
        ((condition? x) (list 'raised (describe x)))
        (else x)))

(define pki (make-test-pki))

(define (run o)
  (define (port face) (number->string (cdr (origin-face o face))))
  (define http-port (port 'http))
  (define log-engine (make-curl-engine))
  (define (log-lines)
    (let* ((t (curl-submit log-engine (make-curl-request (string-append "http://127.0.0.1:" http-port "/proxy-log?from=0")
                                                         'proxy #f 'timeout-ms 10000)))
           (r (curl-token-await t)))
      (cdr (split-lines (utf8->string (curl-response-body r))))))
  (define (lines-after mark) (list-tail (log-lines) mark))
  (define (wait-inner mark)
    (let ((deadline (+ (now-ms) 5000)))
      (let loop ()
        (cond ((exists (lambda (l) (prefix? "inner h2" l)) (lines-after mark)) #t)
              ((> (now-ms) deadline) #f)
              (else (pause-ms 20) (loop))))))
  (define named (string-append "http://alice:s3cret@127.0.0.1:" http-port))
  (define named-none (string-append "http://127.0.0.1:" http-port))
  (define slow (string-append "https://localhost:" (port 'h2) "/connection?delay=3000"))
  (define quick (string-append "https://localhost:" (port 'h2) "/connection"))
  (define ca (string-append pki "/ca.pem"))
  (define (request url proxy) (make-curl-request url 'proxy proxy 'ca-file ca 'timeout-ms 10000))
  (define (request-1.1 url proxy) (make-curl-request url 'proxy proxy 'ca-file ca 'timeout-ms 10000 'http-version 'http/1.1))
  (define (run-case name thunk)
    (let* ((mark (length (log-lines)))
           (answer (thunk)))
      (pause-ms 300)
      (display name) (newline)
      (display "  outcomes: ") (write answer) (newline)
      (for-each (lambda (l) (display "  log: ") (display l) (newline)) (lines-after mark))))
  (display "libcurl ") (display (libcurl-info-version (loaded-libcurl))) (newline)
  ;; Control 1: B through the named proxy with no userinfo, while A is live.
  (run-case "control: A live with alice's userinfo, then B through the named proxy with no userinfo"
    (lambda ()
      (let* ((e (make-curl-engine))
             (mark (length (log-lines)))
             (a (curl-submit e (request slow named)))
             (live (wait-inner mark))
             (b (curl-submit e (request quick named-none))))
        (let ((answer (list 'a-live-before-b live
                            'b (begin (curl-token-wait b 15000) (outcome (curl-token-outcome b)))
                            'a (begin (curl-token-wait a 15000) (outcome (curl-token-outcome a))))))
          (curl-engine-stop e)
          answer))))
  (putenv "https_proxy" named-none)
  (display "https_proxy=") (display (getenv "https_proxy")) (newline)
  ;; Control 2: B alone, through the environment.
  (run-case "control: B alone through proxy environment"
    (lambda ()
      (let* ((e (make-curl-engine))
             (b (curl-submit e (request quick 'environment))))
        (let ((answer (list 'b (begin (curl-token-wait b 15000) (outcome (curl-token-outcome b))))))
          (curl-engine-stop e)
          answer))))
  ;; The case: B through the environment while A is live.
  (run-case "case: A live with alice's userinfo, then B through proxy environment, no userinfo"
    (lambda ()
      (let* ((e (make-curl-engine))
             (mark (length (log-lines)))
             (a (curl-submit e (request slow named)))
             (live (wait-inner mark))
             (b (curl-submit e (request quick 'environment))))
        (let ((answer (list 'a-live-before-b live
                            'b (begin (curl-token-wait b 15000) (outcome (curl-token-outcome b)))
                            'a (begin (curl-token-wait a 15000) (outcome (curl-token-outcome a))))))
          (curl-engine-stop e)
          answer))))
  ;; Fix 1, an engine that does not multiplex: B through the environment while A is live.
  (run-case "fix 1, unmultiplexed engine: A live with alice's userinfo, then B through proxy environment, no userinfo"
    (lambda ()
      (let* ((e (make-curl-engine-unmultiplexed))
             (mark (length (log-lines)))
             (a (curl-submit e (request slow named)))
             (live (wait-inner mark))
             (b (curl-submit e (request quick 'environment))))
        (let ((answer (list 'a-live-before-b live
                            'b (begin (curl-token-wait b 15000) (outcome (curl-token-outcome b)))
                            'a (begin (curl-token-wait a 15000) (outcome (curl-token-outcome a))))))
          (curl-engine-stop e)
          answer))))
  (curl-engine-stop log-engine)
  'done)

(display (parameterize ((origin-pki pki)) (call-with-origin run)))
(newline)
