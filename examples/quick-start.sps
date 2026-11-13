#!r6rs
;;; quick-start.sps: one GET with (http-client), its status and body printed.
;;; Start the test server first, from the repository's root, in a terminal
;;; of its own, and leave it running:
;;;   node tests/origin.mjs
;;; It prints one line, {"node":...,"http":"127.0.0.1:PORT","raw":...}, PORT
;;; a new one at each start, and serves until Ctrl-D. Then run this from the
;;; root, URL being http:// and the address after "http": (raw's and h2c's
;;; speak other protocols), with no trailing /:
;;;   scheme --libdirs src --program examples/quick-start.sps URL
(import (rnrs) (http-client))

(define base (cadr (command-line)))

(call-with-http-session
 (lambda (session)
   (let ((response (http-get session (string-append base "/status/200"))))
     (display (http-response-status response))
     (newline)
     (display (http-response-text response)))))
