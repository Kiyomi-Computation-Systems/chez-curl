#!r6rs
;;; The request record is not opaque: record-rtd opens it, and the private
;;; copy of its credentials can be read and changed by any caller. Run:
;;;   scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program build/m7s2-review/reflect.sps' < /dev/null
(import (rnrs) (rnrs mutable-strings) (only (chezscheme) format) (curl))
(define r (make-curl-request "http://127.0.0.1:1/" 'proxy #f 'credentials (list 'basic "user" "pass")))
(define rtd (record-rtd r))
(define names (vector->list (record-type-field-names rtd)))
(define index (let loop ((i 0) (ns names)) (if (eq? (car ns) 'credentials) i (loop (+ i 1) (cdr ns)))))
(define private ((record-accessor rtd index) r))
(display (format "the record's private copy, read by reflection: ~s~%" private))
(string-set! (caddr private) 0 #\newline)
(display (format "after string-set! on it, curl-request-credentials answers ~s~%" (curl-request-credentials r)))
(display (format "curl-request-check: ~s~%"
                 (guard (e ((curl-request-error? e) (list 'refused (curl-request-error-reason e) (condition-who e))))
                   (curl-request-check r) 'no-raise)))
