#!r6rs
;;; tests/transfer-tls-env.sps: one request against a TLS face, on an engine
;;; of its own, run in a child Chez of tests/test-transfer-tls.sps, which
;;; sets SSL_CERT_FILE or SSL_CERT_DIR for the child alone, through its
;;; command, never in its own environment (ADR-0018; ADR-0024). Guix's
;;; libcurl reads both at curl_global_init, and its 8.20.0 writes them over
;;; CAINFO and CAPATH when a transfer starts; the native layer records both
;;; there, and a submit refuses a CA file, verification on, on such a
;;; libcurl with either set. Any other libcurl ignores them. The suite
;;; judges the answer by the libcurl's mapped file and its version.
;;;
;;;   transfer-tls-env.sps URL CA-FILE VERIFY [NAME VALUE]
;;;
;;; CA-FILE is a path, or - for none; VERIFY is on or off. With NAME and
;;; VALUE, once libcurl has loaded, which a program's references do before
;;; its first line, it putenvs NAME to VALUE, the empty string standing for
;;; unset, as libcurl's curl_getenv reads it. Then it makes an engine,
;;; submits one request of URL with that CA file and verification, awaits
;;; it, stops the engine, and prints six data, each on its own line:
;;;
;;;   (libcurl VERSION)                                     the libcurl it loaded
;;;   (file FILE)                                           loaded-libcurl-file
;;;   (environment (SSL_CERT_FILE . V) (SSL_CERT_DIR . V))  as it started, each #f when unset
;;;   (recorded (("SSL_CERT_FILE" . V) ("SSL_CERT_DIR" . V)))
;;;                                                         loaded-ca-variables, after the
;;;                                                         putenv: what native read at the load
;;;   (transfer ANSWER COUNTS)                              the native counts, the engine stopped
;;;   (done)
;;;
;;; ANSWER is (response STATUS VERSION HEADERS BODY), each header (NAME
;;; VALUE) and the body read as Latin-1; (refused REASON CODE) for a
;;; &curl-transfer-error; (request-refused FIELD REASON IRRITANTS) for a
;;; &curl-request-error, IRRITANTS those after the value; (raised TEXT) for
;;; anything else. The environment line is the evidence that the variable
;;; reached the child: elsewhere than Guix, the answer is the one the child
;;; would give without it.
(import (rnrs)
        (only (chezscheme) getenv putenv)
        (only (curl-testing) describe)
        (only (curl) loaded-libcurl libcurl-info-version)
        (only (curl private native) loaded-libcurl-file loaded-ca-variables)
        (curl private counters)
        (curl private conditions)
        (curl private engine)
        (curl private transfer))

;; show : Any -> Unspecified
(define (show datum)
  (write datum)
  (newline)
  (flush-output-port (current-output-port)))

;; latin-1 : Bytevector -> String
(define (latin-1 bytes)
  (list->string (map integer->char (bytevector->u8-list bytes))))

;; answer-of : (-> Response) -> Answer
(define (answer-of thunk)
  (guard (e ((curl-transfer-error? e)
             (list 'refused (curl-transfer-error-reason e) (curl-transfer-error-code e)))
            ((curl-request-error? e)
             (list 'request-refused (curl-request-error-field e) (curl-request-error-reason e)
                   (if (irritants-condition? e)
                       (let ((irritants (condition-irritants e)))
                         (if (pair? irritants) (cdr irritants) irritants))
                       'no-irritants)))
            (#t (list 'raised (describe e))))
    (let ((r (thunk)))
      (list 'response (curl-response-status r) (curl-response-http-version r)
            (map (lambda (h) (list (car h) (cdr h))) (curl-response-headers r))
            (latin-1 (curl-response-body r))))))

(let ((args (cdr (command-line))))
  (unless (and (memv (length args) '(3 5)) (for-all string? args)
               (member (caddr args) '("on" "off")))
    (put-string (current-error-port) "usage: transfer-tls-env.sps URL CA-FILE on|off [NAME VALUE]\n")
    (exit 2))
  (show (list 'libcurl (libcurl-info-version (loaded-libcurl))))
  (show (list 'file (loaded-libcurl-file)))
  (show (list 'environment
              (cons 'SSL_CERT_FILE (getenv "SSL_CERT_FILE"))
              (cons 'SSL_CERT_DIR (getenv "SSL_CERT_DIR"))))
  (when (= (length args) 5)
    (putenv (list-ref args 3) (list-ref args 4)))
  (show (list 'recorded (loaded-ca-variables)))
  (let* ((engine (make-curl-engine))
         (ca-file (if (string=? (cadr args) "-") #f (cadr args)))
         (answer (answer-of
                  (lambda ()
                    (curl-token-await
                     (curl-submit engine
                                  (make-curl-request (car args) 'timeout-ms 20000
                                                     'ca-file ca-file
                                                     'verify (string=? (caddr args) "on"))))))))
    (curl-engine-stop engine)
    (show (list 'transfer answer (native-counts))))
  (show '(done))
  (exit 0))
