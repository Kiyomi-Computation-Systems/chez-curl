#!r6rs
;; build/m7s4b/probe/char-numeric.sps: which Latin-1 chars char-numeric?
;; takes, and what string->number makes of each.
(import (rnrs))
(for-each (lambda (c)
            (when (char-numeric? c)
              (write (list (char->integer c) (string->number (string c) 10)))
              (newline)))
          (map integer->char (let loop ((i 255) (acc '())) (if (< i 0) acc (loop (- i 1) (cons i acc))))))
