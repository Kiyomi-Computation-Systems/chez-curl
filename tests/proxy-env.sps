#!r6rs
;;; tests/proxy-env.sps: one request through a named proxy, on an engine of
;;; its own, run in a child Chez of tests/test-proxy.sps, which sets
;;; no_proxy, NO_PROXY, http_proxy, https_proxy, all_proxy, SSL_CERT_FILE or
;;; SSL_CERT_DIR for the child alone, through its command, never in its own
;;; environment (ADR-0024; ADR-0037, decision 2; the M7 plan, section 6.2).
;;;
;;;   proxy-env.sps URL PROXY PROXY-CA-FILE PROXY-VERIFY CA-FILE
;;;
;;; PROXY is a URL, or environment, or none for #f; PROXY-CA-FILE and CA-FILE
;;; are paths, or - for none; PROXY-VERIFY is on or off. It makes one GET of
;;; URL with those keys and a 10 s timeout, checks it by curl-request-check,
;;; makes an engine, submits it, awaits it, stops the engine, and prints
;;; five data, each on its own line:
;;;
;;;   (environment (NAME . V) ...)   each variable above as it started, #f
;;;                                  when unset
;;;   (recorded (("SSL_CERT_FILE" . V) ("SSL_CERT_DIR" . V)))
;;;                                  loaded-ca-variables: what native read
;;;                                  at the load
;;;   (check ANSWER)                 curl-request-check's, (checked) when it
;;;                                  returns
;;;   (transfer ANSWER COUNTS)       the native counts, the engine stopped
;;;   (done)
;;;
;;; ANSWER is (response STATUS LINE), LINE the body's first line, read as
;;; Latin-1; (refused REASON CODE CLASS CONNECT-CODE) for a
;;; &curl-transfer-error; (request-refused FIELD VALUE REASON IRRITANTS)
;;; for a &curl-request-error, IRRITANTS those after the value; (raised
;;; TEXT) for anything else. The environment line is the evidence that the
;;; variables reached the child as the suite set them.
(import (rnrs)
        (only (chezscheme) getenv)
        (only (curl-testing) describe)
        (curl)
        (only (curl private native) loaded-ca-variables)
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

;; class-of : Condition -> Symbol
(define (class-of e)
  (cond ((curl-timeout? e) 'timeout)
        ((curl-connect-error? e) 'connect)
        ((curl-send-receive-error? e) 'send-receive)
        ((curl-tls-error? e) 'tls)
        ((curl-protocol-error? e) 'protocol)
        ((curl-too-large? e) 'too-large)
        (else 'none)))

;; failure-answer : Any -> Answer
(define (failure-answer e)
  (cond ((curl-transfer-error? e)
         (list 'refused (curl-transfer-error-reason e) (curl-transfer-error-code e) (class-of e)
               (curl-transfer-error-connect-code e)))
        ((curl-request-error? e)
         (list 'request-refused (curl-request-error-field e) (curl-request-error-value e)
               (curl-request-error-reason e)
               (let ((irritants (if (irritants-condition? e) (condition-irritants e) '())))
                 (if (pair? irritants) (cdr irritants) '()))))
        (else (list 'raised (describe e)))))

(let ((args (cdr (command-line))))
  (unless (and (= (length args) 5) (for-all string? args) (member (list-ref args 3) '("on" "off")))
    (put-string (current-error-port)
                "usage: proxy-env.sps URL PROXY PROXY-CA-FILE on|off CA-FILE\n")
    (exit 2))
  (show (cons 'environment
              (map (lambda (name) (cons (string->symbol name) (getenv name)))
                   '("no_proxy" "NO_PROXY" "http_proxy" "https_proxy" "all_proxy"
                     "SSL_CERT_FILE" "SSL_CERT_DIR"))))
  (show (list 'recorded (loaded-ca-variables)))
  (let* ((path (lambda (text) (if (string=? text "-") #f text)))
         (proxy (let ((given (list-ref args 1)))
                  (cond ((string=? given "environment") 'environment)
                        ((string=? given "none") #f)
                        (else given))))
         (request (make-curl-request (car args) 'timeout-ms 10000 'proxy proxy
                                     'proxy-ca-file (path (list-ref args 2))
                                     'proxy-verify (string=? (list-ref args 3) "on")
                                     'ca-file (path (list-ref args 4)))))
    (show (list 'check (guard (e (#t (failure-answer e)))
                         (curl-request-check request)
                         '(checked))))
    (let* ((engine (make-curl-engine))
           (answer (guard (e (#t (failure-answer e)))
                     (let ((r (curl-token-await (curl-submit engine request))))
                       (list 'response (curl-response-status r) (first-line (curl-response-body r)))))))
      (curl-engine-stop engine)
      (show (list 'transfer answer (native-counts)))))
  (show '(done))
  (exit 0))
