;;; M6 slice 1, item 1 (2026-10-30): the prototype streams a body whole and
;;; in order, before anything is measured with it.
;;;
;;;   scheme --libdirs build/m6s1/src --program check.sps HTTP RAW HTTPS H2 PROXY CA
;;;
;;; Each face is server.mjs's ADDRESS:PORT; CA its run's ca.pem. On each of
;;; the http, raw, https and h2 faces, an engine of its own streams /body of
;;; 4 MiB, byte i being i mod 251, at stream-buffer 65,536, twice: through
;;; curl-token-next-piece, and through the port by get-bytevector-some.
;;; Every byte is checked against its pattern. Each line names the face and
;;; the reader, the bytes and pieces read, the first bad offset or ok, the
;;; stream's pauses and the engine's resumes, and the outcome: the status
;;; and whether its body is #f, or the failure's reason and code.
(import (chezscheme)
        (curl private engine)
        (curl private transfer)
        (curl private conditions)
        (curl private native)
        (curl private libcurl-info))

(define args (command-line-arguments))
(define faces (map cons '(http raw https h2 proxy) (list-head args 5)))
(define ca (list-ref args 5))

(define (say fmt . xs) (apply printf fmt xs) (newline) (flush-output-port (current-output-port)))

(define (url face path)
  (string-append (if (memq face '(https h2)) "https://" "http://")
                 (cdr (assq face faces)) path))

(define (request face path)
  (let ((r (make-curl-request (url face path) 'proxy #f 'timeout-ms 60000)))
    (if (memq face '(https h2)) (curl-request-with r 'ca-file ca) r)))

;; bad-at : Bytevector Natural -> (U Natural #f)
;; The offset of PIECE's first byte, read from AT on, that is not its
;; offset mod 251; #f for none.
(define (bad-at piece at)
  (let ((n (bytevector-length piece)))
    (let loop ((i 0) (v (mod at 251)))
      (cond ((= i n) #f)
            ((fx= (bytevector-u8-ref piece i) v) (loop (fx+ i 1) (if (fx= v 250) 0 (fx+ v 1))))
            (else (+ at i))))))

(define (outcome-text token)
  (let ((o (curl-token-outcome token)))
    (cond ((curl-response? o)
           (format "status=~a version=~a body=~a" (curl-response-status o)
                   (curl-response-http-version o) (if (curl-response-body o) "bytes" "#f")))
          ((curl-transfer-error? o)
           (format "failed reason=~a code=~a" (curl-transfer-error-reason o) (curl-transfer-error-code o)))
          (else (format "other ~s" o)))))

(define (resumes engine)
  (length (filter (lambda (e) (eq? (car e) 'resume)) (cdr (assq 'events (curl-engine-probe engine))))))

(define (stat token key) (cdr (assq key (curl-token-stream-stats token))))

;; run : Symbol Symbol -> Void
(define (run face reader)
  (let* ((engine (make-curl-engine))
         (n 4194304)
         (token (curl-submit engine (curl-request-with-stream-buffer
                                     (request face (format "/body?n=~a" n)) 65536))))
    (let loop ((at 0) (pieces 0) (bad #f)
               (port (and (eq? reader 'port) (curl-token-body-port token))))
      (let ((piece (if port
                       (get-bytevector-some port)
                       (curl-token-next-piece token 30000))))
        (cond
          ((not piece) (say "check face=~a reader=~a timed out at ~a bytes" face reader at))
          ((eof-object? piece)
           (curl-token-wait token 5000)
           (say "check face=~a reader=~a bytes=~a pieces=~a pattern=~a whole=~a pauses=~a resumes=~a max-buffered=~a ~a"
                face reader at pieces (or bad "ok") (= at n) (stat token 'pauses) (resumes engine)
                (stat token 'max-buffered) (outcome-text token)))
          (else
           (loop (+ at (bytevector-length piece)) (+ pieces 1) (or bad (bad-at piece at)) port)))))
    (curl-engine-stop engine)))

(say "libcurl ~a ~a" (libcurl-info-version (loaded-libcurl)) (libcurl-info-ssl-version (loaded-libcurl)))
(for-each (lambda (face)
            (run face 'next-piece)
            (run face 'port))
          '(http raw https h2))
(say "check done")
