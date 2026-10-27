#!r6rs
;;; tests/transfer-proxy.sps: one GET on an engine of its own, run in a
;;; child Chez of tests/test-transfer.sps, which sets http_proxy or
;;; all_proxy for the child alone, through its command, and clears no_proxy
;;; and NO_PROXY there, never in its own environment (ADR-0024, decision 1).
;;;
;;;   transfer-proxy.sps URL PROXY
;;;
;;; PROXY is default, environment or none: the request made without the proxy
;;; key, so with its default, or with it at environment, or at #f. It makes
;;; an engine, submits one GET of URL, awaits it, stops the engine, and
;;; prints three data, each on its own line:
;;;
;;;   (environment (http_proxy . V) (all_proxy . V) (no_proxy . V) (NO_PROXY . V))
;;;   (transfer ANSWER COUNTS)       the native counts, the engine stopped
;;;   (done)
;;;
;;; Each V is #f when unset. ANSWER is (response STATUS LINE), LINE the
;;; body's first line, read as Latin-1: the origin's /echo writes there the
;;; request line it got, whose target is in absolute form when the request
;;; came through a proxy; (refused REASON CODE) for a &curl-transfer-error;
;;; (raised TEXT) for anything else. The environment line is the evidence
;;; that the variables reached the child as the suite set them.
(import (rnrs)
        (only (chezscheme) getenv)
        (only (curl-testing) describe)
        (curl)
        (curl private counters))

;; show : Any -> Unspecified
(define (show datum)
  (write datum)
  (newline)
  (flush-output-port (current-output-port)))

;; first-line : Bytevector -> String
;; BYTES as Latin-1, up to its first LF.
(define (first-line bytes)
  (let loop ((i 0) (chars '()))
    (if (or (= i (bytevector-length bytes)) (= (bytevector-u8-ref bytes i) 10))
        (list->string (reverse chars))
        (loop (+ i 1) (cons (integer->char (bytevector-u8-ref bytes i)) chars)))))

(let ((args (cdr (command-line))))
  (unless (and (= (length args) 2) (for-all string? args)
               (member (cadr args) '("default" "environment" "none")))
    (put-string (current-error-port) "usage: transfer-proxy.sps URL default|environment|none\n")
    (exit 2))
  (show (cons 'environment
              (map (lambda (name) (cons (string->symbol name) (getenv name)))
                   '("http_proxy" "all_proxy" "no_proxy" "NO_PROXY"))))
  (let* ((engine (make-curl-engine))
         (answer (guard (e ((curl-transfer-error? e)
                            (list 'refused (curl-transfer-error-reason e)
                                  (curl-transfer-error-code e)))
                           (#t (list 'raised (describe e))))
                   (let ((r (curl-token-await
                             (curl-submit engine
                                          (if (string=? (cadr args) "default")
                                              (make-curl-request (car args) 'timeout-ms 20000)
                                              (make-curl-request (car args) 'timeout-ms 20000
                                                                 'proxy (and (string=? (cadr args) "environment")
                                                                             'environment)))))))
                     (list 'response (curl-response-status r) (first-line (curl-response-body r)))))))
    (curl-engine-stop engine)
    (show (list 'transfer answer (native-counts))))
  (show '(done))
  (exit 0))
