#!r6rs
;; Does a misused accessor, or a refused origin URL, print a password?
(import (rnrs) (only (chezscheme) display-condition) (curl))
(define secret "Pr0xyS3cr3t")
(define (printed thunk)
  (call-with-string-output-port
    (lambda (port)
      (guard (e (#t (display-condition e port)))
        (thunk)
        (display "no raise" port)))))
(define (contains? text part)
  (let ((n (string-length text)) (m (string-length part)))
    (let loop ((i 0))
      (and (<= (+ i m) n)
           (or (string=? (substring text i (+ i m)) part) (loop (+ i 1)))))))
(define (report name thunk)
  (let ((text (printed thunk)))
    (display name) (display ": secret printed: ") (display (if (contains? text secret) "YES" "no")) (newline)
    (display "  ") (write text) (newline)))
(report "curl-request-url on a string" (lambda () (curl-request-url "http://u:Pr0xyS3cr3t@h/")))
(report "curl-response-status on a string" (lambda () (curl-response-status "http://u:Pr0xyS3cr3t@h/")))
(let ((e (make-curl-engine)))
  (report "submit of ftp://u:Pr0xyS3cr3t@h/"
          (lambda () (curl-token-await (curl-submit e (make-curl-request "ftp://u:Pr0xyS3cr3t@h/")))))
  (report "submit of a URL with a space, http://u:Pr0xyS3cr3t@h /"
          (lambda () (curl-token-await (curl-submit e (make-curl-request "http://u:Pr0xyS3cr3t@h /")))))
  (curl-engine-stop e))
