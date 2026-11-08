#!r6rs
;;; quick-start.sps: one GET with (http-client), its status and body printed.
;;; Run it from the repository's root, URL the test server's base URL with no
;;; trailing / (docs/README.md says how to start one):
;;;   scheme --libdirs src --program examples/quick-start.sps URL
(import (rnrs) (http-client))

(define base (cadr (command-line)))

(call-with-http-session
 (lambda (session)
   (let ((response (http-get session (string-append base "/status/200"))))
     (display (http-response-status response))
     (newline)
     (display (http-response-text response)))))
