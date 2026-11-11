#!r6rs
;;; tests/proxy-env-join.sps: a transfer through proxy environment beside a live
;;; tunnel a named proxy's transfer opened with its userinfo, on one engine, run
;;; in a child Chez of tests/test-proxy.sps, which sets https_proxy for the
;;; child alone, through its command (ADR-0037).
;;;
;;;   proxy-env-join.sps NAMED-PROXY SLOW-URL QUICK-URL CA-FILE
;;;
;;; It makes an engine; streams a GET of SLOW-URL through NAMED-PROXY, a
;;; proxy URL with userinfo, and waits for its head, so its stream is live;
;;; then submits a GET of QUICK-URL through proxy environment and awaits
;;; it, then the first; stops the engine, and prints five data, each on its
;;; own line:
;;;
;;;   (environment (NAME . V) ...)   each proxy variable as it started, #f
;;;                                  when unset
;;;   (multiplexing BEFORE AFTER)    curl-engine-multiplexing's answer once
;;;                                  the engine runs, and once the first's
;;;                                  head is in
;;;   (join HEAD SECOND FIRST)       whether the first's head came; the
;;;                                  second's ANSWER, and the first's
;;;   (transfer COUNTS)              the native counts, the engine stopped
;;;   (done)
;;;
;;; ANSWER is (response STATUS) for a response, (refused REASON CODE CLASS
;;; CONNECT-CODE) for a &curl-transfer-error, (request-refused FIELD VALUE
;;; REASON) for a &curl-request-error, (raised TEXT) for anything else.
(import (rnrs)
        (only (chezscheme) getenv)
        (only (curl-testing) describe)
        (curl)
        (only (curl private engine) curl-engine-multiplexing)
        (curl private counters))

;; show : Any -> Unspecified
(define (show datum)
  (write datum)
  (newline)
  (flush-output-port (current-output-port)))

;; class-of : Condition -> Symbol
(define (class-of e)
  (cond ((curl-timeout? e) 'timeout)
        ((curl-connect-error? e) 'connect)
        ((curl-send-receive-error? e) 'send-receive)
        ((curl-tls-error? e) 'tls)
        ((curl-protocol-error? e) 'protocol)
        ((curl-too-large? e) 'too-large)
        (else 'none)))

;; answer-of : Any -> Answer
(define (answer-of x)
  (cond ((curl-response? x) (list 'response (curl-response-status x)))
        ((curl-transfer-error? x)
         (list 'refused (curl-transfer-error-reason x) (curl-transfer-error-code x) (class-of x)
               (curl-transfer-error-connect-code x)))
        ((curl-request-error? x)
         (list 'request-refused (curl-request-error-field x) (curl-request-error-value x)
               (curl-request-error-reason x)))
        (else (list 'raised (describe x)))))

;; awaited : Token -> Answer
;; TOKEN's outcome, waited for up to 20 s, as an answer.
(define (awaited token)
  (if (curl-token-wait token 20000)
      (answer-of (curl-token-outcome token))
      '(raised "no outcome within 20 s")))

(let ((args (cdr (command-line))))
  (unless (and (= (length args) 4) (for-all string? args))
    (put-string (current-error-port)
                "usage: proxy-env-join.sps NAMED-PROXY SLOW-URL QUICK-URL CA-FILE\n")
    (exit 2))
  (show (cons 'environment
              (map (lambda (name) (cons (string->symbol name) (getenv name)))
                   '("no_proxy" "NO_PROXY" "http_proxy" "https_proxy" "all_proxy"))))
  (let* ((named (list-ref args 0))
         (ca (list-ref args 3))
         (engine (make-curl-engine))
         (before (curl-engine-multiplexing engine))
         (first (curl-submit engine (make-curl-request (list-ref args 1) 'proxy named 'ca-file ca
                                                       'timeout-ms 20000 'stream-buffer 4096)))
         (head (and (curl-token-head-wait first 20000) #t))
         (after (curl-engine-multiplexing engine))
         (second (guard (e ((curl-request-error? e) (answer-of e)))
                   (awaited (curl-submit engine (make-curl-request (list-ref args 2) 'proxy 'environment
                                                                   'ca-file ca 'timeout-ms 20000)))))
         (drained (let loop ()
                    (let ((piece (curl-token-next-piece first 20000)))
                      (when (bytevector? piece) (loop)))))
         (first-answer (awaited first)))
    (curl-engine-stop engine)
    (show (list 'multiplexing before after))
    (show (list 'join head second first-answer))
    (show (list 'transfer (native-counts))))
  (show '(done))
  (exit 0))
