#!r6rs
;;; A child of tests/test-stream.sps: a streamed response's head through a
;;; proxy's CONNECT tunnel. The suite runs it with https_proxy at the origin's
;;; http face, which tunnels to the origin's own faces, in this child's
;;; environment alone, no_proxy and NO_PROXY cleared. libcurl reads the
;;; CONNECT's head first, its RESPONSE_CODE 0 at its empty line, a head the
;;; header callable passes over.
;;;
;;;   stream-connect.sps HTTP HTTPS H2 CA
;;;
;;; HTTP, HTTPS and H2 are the faces, each ADDRESS:PORT, and CA the run's
;;; CA file. It reads the http face's /connects, direct; then, for the
;;; https and h2 faces, streams /early through the tunnel, the request's
;;; proxy the environment's, its head waited for, its pieces taken; then
;;; reads /connects again. Prints:
;;;
;;;   (environment (https_proxy . V) (no_proxy . V) (NO_PROXY . V))
;;;   (connects N)
;;;   (head FACE HEAD-WAIT HEAD SAME BODY OUTCOME)  for https, then h2
;;;   (connects N)
;;;   (counts COUNTS)                                the engine stopped
;;;
;;; HEAD is (STATUS VERSION HEADERS), or #f; SAME whether it equals, as
;;; whole values, the status, version and headers the response read when
;;; the transfer ended; BODY the pieces' bytes as Latin-1; OUTCOME (response
;;; STATUS BODY), BODY #f for a stream, or (failed REASON CODE).
(import (rnrs)
        (only (chezscheme) getenv)
        (curl)
        (curl private counters))

(define (show datum) (write datum) (newline) (flush-output-port (current-output-port)))

(define args (cdr (command-line)))
(define http (car args))
(define https (cadr args))
(define h2 (caddr args))
(define ca (cadddr args))

(define (latin-1 bytes) (list->string (map integer->char (bytevector->u8-list bytes))))

(define engine (make-curl-engine))

;; connects : -> (U Natural String)
(define (connects)
  (guard (e (#t (list 'raised (condition-message e))))
    (let* ((r (curl-token-await
               (curl-submit engine (make-curl-request (string-append "http://" http "/connects")
                                                      'proxy #f 'timeout-ms 10000))))
           (text (latin-1 (curl-response-body r))))
      (string->number (substring text 9 (- (string-length text) 1))))))

;; head-of : String -> List
(define (head-of face host)
  (let* ((token (curl-submit engine (make-curl-request (string-append "https://" host "/early")
                                                       'ca-file ca 'timeout-ms 20000
                                                       'stream-buffer 65536)))
         (waited (curl-token-head-wait token 20000))
         (head (curl-token-head token))
         (body (let loop ((found '()))
                 (let ((piece (curl-token-next-piece token 20000)))
                   (if (bytevector? piece)
                       (loop (append found (bytevector->u8-list piece)))
                       found))))
         (outcome (curl-token-outcome token)))
    (list 'head face waited
          (and head (list (curl-head-status head) (curl-head-http-version head) (curl-head-headers head)))
          (and head (curl-response? outcome)
               (equal? (list (curl-head-status head) (curl-head-http-version head) (curl-head-headers head))
                       (list (curl-response-status outcome) (curl-response-http-version outcome)
                             (curl-response-headers outcome))))
          (list->string (map integer->char body))
          (cond ((curl-response? outcome)
                 (list 'response (curl-response-status outcome) (curl-response-body outcome)))
                ((curl-transfer-error? outcome)
                 (list 'failed (curl-transfer-error-reason outcome) (curl-transfer-error-code outcome)))
                (else (list 'other outcome))))))

(show (cons 'environment (map (lambda (name) (cons (string->symbol name) (getenv name)))
                              '("https_proxy" "no_proxy" "NO_PROXY"))))
(show (list 'connects (connects)))
(show (head-of 'https https))
(show (head-of 'h2 h2))
(show (list 'connects (connects)))
(curl-engine-stop engine)
(show (list 'counts (native-counts)))
