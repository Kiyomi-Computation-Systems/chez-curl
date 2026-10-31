;;; M6 slice 2, a defect in main found on the way (2026-10-30): an engine
;;; made by make-curl-engine-unpaced or make-curl-engine-unmultiplexed fails
;;; at its first resume step, since resume! reads its seams by
;;; (assq 'pause-answer SEAMS), and assq raises on a seam that is a bare
;;; symbol. Run on main's own src/, not the prototype:
;;;
;;;   LIBDIRS=src sh .plans/research/m6/slice2/run.sh LANE unpaced 1
;;;
;;; Each case, on an engine of its own: a streamed response, stream-buffer
;;; 65,536, of /body?n=1048576 on the raw face, every piece taken, so the
;;; transfer pauses and the engine resumes it; then the token's outcome and
;;; the engine's state. The control is make-curl-engine.
(import (chezscheme)
        (curl private engine)
        (curl private transfer)
        (curl private conditions)
        (curl private native)
        (curl private libcurl-info))

(define args (command-line-arguments))
(define raw (list-ref args 1))
(define runs (string->number (list-ref args 5)))

(define (say fmt . xs) (apply printf fmt xs) (newline) (flush-output-port (current-output-port)))

(define (outcome-text o)
  (cond ((curl-response? o) (format "status=~a" (curl-response-status o)))
        ((curl-transfer-error? o) (format "failed reason=~a code=~a" (curl-transfer-error-reason o) (curl-transfer-error-code o)))
        ((curl-engine-error? o)
         (format "engine-error reason=~a raised=~s" (curl-engine-error-reason o)
                 (let ((c (curl-engine-error-condition o)))
                   (if (message-condition? c)
                       (list (condition-message c) (and (irritants-condition? c) (condition-irritants c)))
                       c))))
        ((not o) "not-done")
        (else (format "other ~s" o))))

(define (one r name make)
  (let* ((engine (make))
         (token (curl-submit engine (make-curl-request (string-append "http://" raw "/body?n=1048576&mode=length")
                                                       'proxy #f 'timeout-ms 20000 'stream-buffer 65536))))
    (let loop ((bytes 0))
      (let ((piece (curl-token-next-piece token 20000)))
        (if (bytevector? piece)
            (loop (+ bytes (bytevector-length piece)))
            (begin
              (curl-token-wait token 5000)
              (say "unpaced run=~a engine=~a bytes=~a end=~a resumes=~a ~a engine-state=~a"
                   r name bytes (if (eof-object? piece) "eof" piece)
                   (cdr (assq 'resumes (curl-token-stream-stats token)))
                   (outcome-text (curl-token-outcome token)) (curl-engine-state engine))))))
    (curl-engine-stop engine)))

(say "libcurl ~a ~a" (libcurl-info-version (loaded-libcurl)) (libcurl-info-ssl-version (loaded-libcurl)))
(do ((r 1 (+ r 1))) ((> r runs))
  (one r "make-curl-engine" make-curl-engine)
  (one r "make-curl-engine-unpaced" make-curl-engine-unpaced)
  (one r "make-curl-engine-unmultiplexed" make-curl-engine-unmultiplexed))
(say "unpaced done")
