#!r6rs
;;; tests/transfer-tls-env.sps: one request against a TLS face, on an engine
;;; of its own, run in a child Chez of tests/test-transfer-tls.sps, which
;;; sets SSL_CERT_FILE or SSL_CERT_DIR for the child alone, through its
;;; command, never in its own environment (ADR-0018). Guix's libcurl reads both at
;;; curl_global_init and writes them over CAINFO and CAPATH when a transfer
;;; starts; Guix's 8.6.0 set them as the easy handle's defaults, which a
;;; request's setopts win; any other libcurl ignores them. The suite judges
;;; the answer by ADR-0002's world and the libcurl's version.
;;;
;;;   transfer-tls-env.sps URL CA-FILE
;;;
;;; It makes an engine, submits one request to it, URL with CA-FILE as its
;;; CA file and verification on, awaits it, stops the engine, and prints
;;; four data, each on its own line:
;;;
;;;   (libcurl VERSION)                                     the libcurl it loaded
;;;   (environment (SSL_CERT_FILE . V) (SSL_CERT_DIR . V))  each #f when unset
;;;   (transfer ANSWER COUNTS)                              the native counts, the engine stopped
;;;   (done)
;;;
;;; ANSWER is (response STATUS VERSION HEADERS BODY), each header (NAME
;;; VALUE) and the body read as Latin-1; (refused REASON CODE) for a
;;; &curl-transfer-error; (request-refused FIELD REASON) for a
;;; &curl-request-error; (raised TEXT) for anything else. The environment
;;; line is the evidence that the variable reached the child: elsewhere
;;; than Guix, the answer is the one the child would give without it.
(import (rnrs)
        (only (chezscheme) getenv)
        (only (curl-testing) describe)
        (only (curl) loaded-libcurl libcurl-info-version)
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
             (list 'request-refused (curl-request-error-field e) (curl-request-error-reason e)))
            (#t (list 'raised (describe e))))
    (let ((r (thunk)))
      (list 'response (transfer-response-status r) (transfer-response-http-version r)
            (map (lambda (h) (list (car h) (cdr h))) (transfer-response-headers r))
            (latin-1 (transfer-response-body r))))))

(let ((args (cdr (command-line))))
  (unless (and (= (length args) 2) (for-all string? args))
    (put-string (current-error-port) "usage: transfer-tls-env.sps URL CA-FILE\n")
    (exit 2))
  (show (list 'libcurl (libcurl-info-version (loaded-libcurl))))
  (show (list 'environment
              (cons 'SSL_CERT_FILE (getenv "SSL_CERT_FILE"))
              (cons 'SSL_CERT_DIR (getenv "SSL_CERT_DIR"))))
  (let* ((engine (make-curl-engine))
         (answer (answer-of
                  (lambda ()
                    (curl-token-await
                     (curl-engine-submit engine
                                         (make-transfer-request (car args) 'get '() #f 20000 #f (cadr args)
                                                                #t #f)))))))
    (curl-engine-stop engine)
    (show (list 'transfer answer (native-counts))))
  (show '(done))
  (exit 0))
