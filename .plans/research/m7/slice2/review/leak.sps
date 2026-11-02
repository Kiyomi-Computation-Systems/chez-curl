#!r6rs
;;; Where a credentials string reaches a condition's irritants or a printed
;;; record. Run from the repository's root:
;;;   scripts/guix-env sh -c '$CHEZ --libdirs src:tests --program build/m7s2-review/leak.sps' < /dev/null
(import (rnrs) (only (chezscheme) display-condition format) (curl))

(define secret "s3cretPass")

;; holds? : String -> Boolean
(define (holds? text)
  (let ((n (string-length text)) (k (string-length secret)))
    (let loop ((i 0))
      (and (<= (+ i k) n)
           (or (string=? (substring text i (+ i k)) secret) (loop (+ i 1)))))))

(define (shown-condition e)
  (call-with-string-output-port (lambda (p) (display-condition e p))))

(define (report label thunk)
  (let ((text (guard (e (#t (shown-condition e)))
                (thunk)
                "no-raise")))
    (display (format "~a: secret in display-condition: ~a~%  ~a~%"
                     label (if (holds? text) "YES" "no")
                     (if (> (string-length text) 400) (string-append (substring text 0 400) "...") text)))))

(define r (make-curl-request "http://127.0.0.1:1/" 'proxy #f 'timeout-ms 2000
                             'credentials (list 'basic "user" secret)))

(let ((w (call-with-string-output-port (lambda (p) (write r p)))))
  (display (format "write request: secret printed: ~a~%" (if (holds? w) "YES" "no"))))

(define e (make-curl-engine))
(define t (curl-submit e r))

(let ((w (call-with-string-output-port (lambda (p) (write t p)))))
  (display (format "write token: secret printed: ~a~%" (if (holds? w) "YES" "no"))))

(report "curl-token-next-piece on a whole-body token" (lambda () (curl-token-next-piece t 10)))
(report "curl-token-body-port on a whole-body token" (lambda () (curl-token-body-port t)))
(report "curl-token-put-piece! on a token that streams no body" (lambda () (curl-token-put-piece! t #vu8(1) 10)))
(curl-token-wait t 5000)
(curl-engine-stop e)
