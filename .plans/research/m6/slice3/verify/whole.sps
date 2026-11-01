;;; whole.sps, beside probe.sps. My check of the slice 3 measurement's claim that 8.20.0 and 8.23.0 never
;;; end an HTTP/2 3xx while a streamed body is owed, even fed. Its server
;;; adds Location exactly when the status is a 3xx, so this crosses the
;;; status with Location. Fed throughout: every room-wait #t gets a piece.
;;;   probe.sps HTTP RAW HTTPS H2 CLOSED CA RUNS
(import (chezscheme) (curl)
        (only (curl private engine) curl-token-upload-stats)
        (only (curl private counters) native-counts))

(define args (command-line-arguments))
(define faces (map cons '(http raw https h2 closed) (list-head args 5)))
(define ca (list-ref args 5))
(define runs (string->number (list-ref args 6)))

(define (ms-since t0)
  (let ((d (time-difference (current-time 'time-monotonic) t0)))
    (/ (round (* 1000 (+ (* 1000 (time-second d)) (/ (time-nanosecond d) 1000000)))) 1000.0)))

(define piece (let ((bv (make-bytevector 65536))) (do ((i 0 (+ i 1))) ((= i 65536) bv) (bytevector-u8-set! bv i (mod i 251)))))
(define total (* 4 1024 1024))
(define location "&to=%2Fbody%3Fn%3D65536%26mode%3Dlength")


;; A whole body, as M5's http-request sends one: 4 MiB in the request.
(define whole (let ((bv (make-bytevector total))) (do ((i 0 (+ i 1))) ((= i total) bv) (bytevector-u8-set! bv i (mod i 251)))))
(define (probe engine face status loc? r)
  (let* ((path (format "/answer-at?status=~a&after=65536~a&tag=whole-~a-~a-~a-~a" status (if loc? location "")
                       face status (if loc? "loc" "noloc") r))
         (req (make-curl-request (string-append (if (eq? face 'raw) "http://" "https://") (cdr (assq face faces)) path)
                                 'method 'post 'proxy #f 'timeout-ms 8000 'body whole))
         (req (if (eq? face 'raw) req (curl-request-with req 'ca-file ca)))
         (t0 (current-time 'time-monotonic))
         (t (curl-submit engine req)))
    (curl-token-wait t 10000)
    (let ((o (curl-token-outcome t)))
      (printf "whole face=~a status=~a location=~a run=~a done-ms=~a outcome=~a~%" face status (if loc? "yes" "no") r
              (ms-since t0)
              (cond ((curl-response? o) (format "status=~a body=~s" (curl-response-status o) (utf8->string (curl-response-body o))))
                    ((curl-transfer-error? o) (format "failed:~a:~a" (curl-transfer-error-reason o) (curl-transfer-error-code o)))
                    (else o))))))
(printf "whole libcurl ~a ~a~%" (libcurl-info-version (loaded-libcurl)) (libcurl-info-ssl-version (loaded-libcurl)))
(let ((engine (make-curl-engine)))
  (do ((r 1 (+ r 1))) ((> r runs))
    (for-each (lambda (face)
                (for-each (lambda (status) (for-each (lambda (loc?) (probe engine face status loc? r)) '(#t #f)))
                          '(303 307 413 200)))
              '(h2 raw)))
  (curl-engine-stop engine))
(collect-rendezvous)
(printf "whole counts ~a~%" (native-counts))
