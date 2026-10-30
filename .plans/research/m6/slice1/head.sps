;;; M6 slice 1, item 4 (2026-10-30): the head, read inside the header
;;; callable, through the engine (the M6 plan, sections 3.2 and 4.1).
;;;
;;;   scheme --libdirs build/m6s1/src --program head.sps HTTP RAW HTTPS H2 PROXY CA MODE
;;;
;;; MODE direct, on each of the http, raw, https and h2 faces, each case on
;;; an engine of its own, its response streamed at stream-buffer 65,536:
;;;   body    /body?n=65536&delay=300: the head, then the body 300 ms on;
;;;   early   /early: a 100, a 103 with a Link header, then the final head;
;;;   empty   /empty: a 204;
;;;   head    a head request of /body?n=65536;
;;; and, once, refused: a GET of 127.0.0.1:1, where nothing listens.
;;; MODE connect, run with https_proxy at the server's proxy face in this
;;; program's environment alone (run.sh's CHILD_PROXY=1): body on the https
;;; and h2 faces through the CONNECT tunnel, the request's proxy the
;;; environment's; the proxy face's count of CONNECTs, read from /connects
;;; on the http face direct, before and after.
;;;
;;; Each line: the case and face; whether the head equals, as whole values,
;;; the status, version and headers finish-transfer read into the response
;;; for the same transfer; the head; its time from the submit, and the
;;; first piece's, in ms, and the head's lead over the first piece; the
;;; trace of every head's empty line, (CODE . MS-FROM-SUBMIT) in order; and
;;; the outcome.
(import (chezscheme)
        (curl private engine)
        (curl private transfer)
        (curl private conditions)
        (curl private native)
        (curl private libcurl-info))

(define args (command-line-arguments))
(define faces (map cons '(http raw https h2 proxy) (list-head args 5)))
(define ca (list-ref args 5))
(define mode (string->symbol (list-ref args 6)))

(define (say fmt . xs) (apply printf fmt xs) (newline) (flush-output-port (current-output-port)))
(define (ns-of t) (+ (* (time-second t) 1000000000) (time-nanosecond t)))
(define (now-ns) (ns-of (current-time 'time-monotonic)))
(define (ms x) (and x (/ (round (/ x 1000)) 1000.0)))

(define (url face path)
  (string-append (if (memq face '(https h2)) "https://" "http://") (cdr (assq face faces)) path))

(define (request face path . keys)
  (let ((r (apply make-curl-request (url face path) 'timeout-ms 30000 keys)))
    (if (memq face '(https h2)) (curl-request-with r 'ca-file ca) r)))

(define (stat token key) (cdr (assq key (curl-token-stream-stats token))))

(define (outcome-text o)
  (cond ((curl-response? o) (format "status=~a version=~a body=~a" (curl-response-status o)
                                    (curl-response-http-version o) (if (curl-response-body o) "bytes" "#f")))
        ((curl-transfer-error? o)
         (format "failed reason=~a code=~a" (curl-transfer-error-reason o) (curl-transfer-error-code o)))
        (else (format "other ~s" o))))

;; one : Symbol Symbol Request -> Void
(define (one case face req)
  (let* ((engine (make-curl-engine))
         (t0 (now-ns))
         (token (curl-submit engine (curl-request-with-stream-buffer req 65536)))
         (arrived (curl-token-head-wait token 20000))
         (head (curl-token-head token))
         (bytes (let drain ((at 0))
                  (let ((piece (curl-token-next-piece token 20000)))
                    (if (bytevector? piece) (drain (+ at (bytevector-length piece))) at)))))
    (curl-token-wait token 20000)
    (let* ((o (curl-token-outcome token))
           (equal (and head (curl-response? o)
                       (equal? (list (curl-head-status head) (curl-head-http-version head) (curl-head-headers head))
                               (list (curl-response-status o) (curl-response-http-version o) (curl-response-headers o)))))
           (head-at (stat token 'head-ns))
           (first-at (stat token 'first-piece-ns)))
      (say "head case=~a face=~a head-wait=~a equal=~a head=~a body-bytes=~a head-ms=~a first-piece-ms=~a head-lead-ms=~a trace=~a ~a"
           case face arrived equal
           (if head (list (curl-head-status head) (curl-head-http-version head) (curl-head-headers head)) #f)
           bytes (ms (and head-at (- head-at t0))) (ms (and first-at (- first-at t0)))
           (ms (and head-at first-at (- first-at head-at)))
           (map (lambda (e) (cons (car e) (ms (- (cdr e) t0)))) (stat token 'trace))
           (outcome-text o))
      (when (and (curl-response? o) (not equal))
        (say "head case=~a face=~a response=~s" case face
             (list (curl-response-status o) (curl-response-http-version o) (curl-response-headers o)))))
    (curl-engine-stop engine)))

;; connects : -> String
(define (connects)
  (let* ((engine (make-curl-engine))
         (o (guard (e (#t e)) (curl-token-await (curl-submit engine (request 'http "/connects" 'proxy #f))))))
    (curl-engine-stop engine)
    (if (curl-response? o)
        (let* ((b (curl-response-body o)) (k (bytevector-length b)))
          (utf8->string (if (and (> k 0) (= (bytevector-u8-ref b (- k 1)) 10))
                            (let ((c (make-bytevector (- k 1)))) (bytevector-copy! b 0 c 0 (- k 1)) c)
                            b)))
        (outcome-text o))))

(say "libcurl ~a ~a mode=~a https_proxy=~a" (libcurl-info-version (loaded-libcurl))
     (libcurl-info-ssl-version (loaded-libcurl)) mode (getenv "https_proxy"))
(case mode
  ((direct)
   (for-each (lambda (face)
               (one 'body face (request face "/body?n=65536&delay=300" 'proxy #f))
               (one 'early face (request face "/early" 'proxy #f))
               (one 'empty face (request face "/empty" 'proxy #f))
               (one 'head face (request face "/body?n=65536" 'proxy #f 'method 'head)))
             '(http raw https h2))
   (one 'refused 'none (make-curl-request "http://127.0.0.1:1/" 'proxy #f 'timeout-ms 30000)))
  ((connect)
   (say "head connects before: ~a" (connects))
   (for-each (lambda (face)
               (one 'connect face (request face "/body?n=65536&delay=300" 'proxy 'environment)))
             '(https h2))
   (say "head connects after: ~a" (connects))))
(say "head done")
