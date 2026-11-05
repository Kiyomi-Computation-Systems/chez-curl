#!r6rs
;;; What the two surviving rule mutants let through: cookie-line-fault of a
;;; line with U+0002 in its value, and of one whose expiry is U+00B2, on the
;;; tree it runs in. One line each, "rule: CASE ANSWER".
(import (rnrs) (only (curl private transfer) cookie-line-fault))
(define (tabbed . f) (fold-left (lambda (l x) (string-append l "\t" x)) (car f) (cdr f)))
(define (say tag x) (display "rule: ") (display tag) (display " ") (write x) (newline))
(say 'value-U+0002 (guard (e (#t (list 'raised (condition-who e))))
                     (cookie-line-fault (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "n" (string #\v (integer->char 2))))))
(say 'value-U+000B (guard (e (#t (list 'raised (condition-who e))))
                     (cookie-line-fault (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "n" (string #\v (integer->char 11))))))
(say 'expiry-U+00B2 (guard (e (#t (list 'raised (and (who-condition? e) (condition-who e)))))
                      (cookie-line-fault (tabbed "a.localhost" "FALSE" "/" "FALSE" (string (integer->char #xB2)) "n" "v"))))
(say 'char-numeric-U+00B2 (char-numeric? (integer->char #xB2)))
