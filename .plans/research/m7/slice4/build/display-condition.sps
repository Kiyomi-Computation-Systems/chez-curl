#!r6rs
;; build/m7s4b/probe/display-condition.sps: what display-condition prints of
;; a condition with no &message, and of one with it, a field holding a secret.
(import (rnrs) (only (chezscheme) display-condition))
(define-condition-type &held &condition make-held held? (value held-value))
(define (shown c) (call-with-string-output-port (lambda (p) (display-condition c p))))
(write (shown (make-held "S3cr3t"))) (newline)
(write (shown (condition (make-held "S3cr3t") (make-who-condition 'w)))) (newline)
(write (shown (condition (make-held "S3cr3t") (make-message-condition "refused")))) (newline)
(write (shown (condition (make-held "S3cr3t") (make-message-condition "refused") (make-irritants-condition '(1))))) (newline)
