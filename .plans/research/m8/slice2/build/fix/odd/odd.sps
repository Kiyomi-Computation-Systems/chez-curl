;; M8 slice 2's review fixes: each odd head through (curl), buffered, one
;; engine each; prints the case and its outcome: the response's status and
;; headers, or the refusal's reason, code and error buffer.
(import (rnrs) (only (chezscheme) command-line-arguments) (curl))
(define port (car (command-line-arguments)))
(for-each
 (lambda (k)
   (let* ((e (make-curl-engine))
          (t (curl-submit e (make-curl-request (string-append "http://127.0.0.1:" port "/" k)
                                               'proxy #f 'timeout-ms 5000)))
          (ended (curl-token-wait t 10000))
          (o (curl-token-outcome t)))
     (display k) (display " ")
     (write (cond ((curl-response? o) (list 'response (curl-response-status o) (curl-response-headers o)))
                  ((curl-transfer-error? o)
                   (list 'refused (curl-transfer-error-reason o) (curl-transfer-error-code o)
                         (curl-transfer-error-error-buffer o)))
                  (else o)))
     (newline)
     (curl-engine-stop e)))
 '("a" "b" "c" "d" "e" "h" "f" "g" "j" "k" "l" "m" "i"))
