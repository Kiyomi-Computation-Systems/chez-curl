#!r6rs
;;; tests/example-leak.sps: the control tests/test-examples.sps runs through
;;; tests/example-runner.sps beside the examples. Shaped as an example, it
;;; makes an engine and a cookie jar of it and frees neither, so the
;;; runner's counts, read once this body has returned, hold one multi
;;; handle and one share. A runner that read its counts before the body ran,
;;; or wrote them from anywhere but (curl private counters), would show 0.
(import (rnrs) (curl))

(define engine (make-curl-engine))
(define jar (make-curl-cookie-jar engine))

(display "left an engine and a jar")
(newline)
