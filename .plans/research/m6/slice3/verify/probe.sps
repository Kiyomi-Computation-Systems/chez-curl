;;; My check of the slice 3 measurement's claim that 8.20.0 and 8.23.0 never
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

(define (probe engine face status loc? sized? r)
  (let* ((path (format "/answer-at?status=~a&after=65536~a&tag=probe-~a-~a-~a-~a-~a" status (if loc? location "")
                       face status (if loc? "loc" "noloc") (if sized? "sized" "chunked") r))
         (req (apply make-curl-request
                     (string-append (if (eq? face 'raw) "http://" "https://") (cdr (assq face faces)) path)
                     'method 'post 'proxy #f 'timeout-ms 20000 'body 'stream 'stream-buffer 65536
                     (if sized? (list 'body-length total) '())))
         (req (if (eq? face 'raw) req (curl-request-with req 'ca-file ca)))
         (t0 (current-time 'time-monotonic))
         (t (curl-submit engine req)))
    (let loop ((given 0) (in-hand #f) (ended? #f) (head-ms #f) (got '()))
      (let* ((head (curl-token-head t))
             (head-ms (or head-ms (and head (ms-since t0)))))
        (cond
         ((curl-token-done? t)
          (finish t face status loc? sized? r head head-ms (ms-since t0) #t got given))
         ((and head-ms (> (- (ms-since t0) head-ms) 5000))
          (finish t face status loc? sized? r head head-ms (ms-since t0) #f got given))
         (else
          (let ((p (curl-token-next-piece t 5)))
            (let ((got (if (bytevector? p) (cons p got) got)))
              (cond
               (in-hand
                (let ((a (curl-token-put-piece! t in-hand 5)))
                  (loop (if (eq? a #t) (+ given (bytevector-length in-hand)) given) (if (eq? a #t) #f in-hand) ended? head-ms got)))
               ((and (not ended?) (>= given total))
                (curl-token-end-body! t) (loop given #f #t head-ms got))
               ((and (not ended?) (eq? #t (curl-token-room-wait t 5)))
                (loop given piece ended? head-ms got))
               (else (loop given #f ended? head-ms got)))))))))))

(define (finish t face status loc? sized? r head head-ms now done? got given)
  (unless done? (curl-token-cancel t) (curl-token-wait t 5000))
  (let ((o (curl-token-outcome t))
        (text (call-with-values open-bytevector-output-port (lambda (port take) (for-each (lambda (b) (put-bytevector port b)) (reverse got)) (utf8->string (take))))))
    (printf "probe face=~a status=~a location=~a framing=~a run=~a head=~a bit=~a head-ms=~a ended-own=~a end-after-head-ms=~a body=~s put=~a handed=~a outcome=~a~%"
            face status (if loc? "yes" "no") (if sized? "sized" "chunked") r (and head (curl-head-status head))
            (and head (curl-head-body-asked? head)) head-ms (if done? "yes" "no")
            (and head-ms (- now head-ms)) text given (cdr (assq 'handed (curl-token-upload-stats t)))
            (cond ((curl-response? o) (format "status=~a" (curl-response-status o)))
                  ((curl-transfer-error? o) (format "failed:~a:~a" (curl-transfer-error-reason o) (curl-transfer-error-code o)))
                  ((condition? o) (format "condition:~a" (if (message-condition? o) (condition-message o) "?")))
                  (else o)))))

(printf "probe libcurl ~a ~a~%" (libcurl-info-version (loaded-libcurl)) (libcurl-info-ssl-version (loaded-libcurl)))
(let ((engine (make-curl-engine)))
  (do ((r 1 (+ r 1))) ((> r runs))
    (for-each
     (lambda (face)
       (for-each
        (lambda (status)
          (for-each
           (lambda (loc?)
             (for-each (lambda (sized?) (probe engine face status loc? sized? r)) '(#t #f)))
           '(#t #f)))
        '(303 307 413 200)))
     '(h2 raw)))
  (curl-engine-stop engine))
(collect-rendezvous)
(printf "probe counts ~a~%" (native-counts))
