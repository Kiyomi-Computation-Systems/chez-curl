#!r6rs
;;; group.sps: many calls at once on one thread, by http-parallel and by a
;;; request group. The session's one engine thread runs every transfer.
;;; Start the test server first, from the repository's root, in a terminal
;;; of its own, and leave it running:
;;;   node tests/origin.mjs
;;; It prints one line, {"node":...,"http":"127.0.0.1:PORT","raw":...}, PORT
;;; a new one at each start, and serves until Ctrl-D. Then run this from the
;;; root, URL being http:// and the address after "http": (raw's and h2c's
;;; speak other protocols), with no trailing /:
;;;   scheme --libdirs src --program examples/group.sps URL
(import (rnrs) (http-client))

(define base (cadr (command-line)))

(define (url path) (string-append base path))

(call-with-http-session 'timeout-ms 10000
  (lambda (session)
    ;; http-parallel: a list of calls, at most two at once; the responses
    ;; come back in the list's order, whichever ends first.
    (write (map http-response-status
                (http-parallel session
                               (list (list 'get (url "/status/200"))
                                     (list 'get (url "/status/201"))
                                     (list 'get (url "/status/404")))
                               'limit 2)))
    (newline)
    ;; A group: go starts a call and hands back its pending at once;
    ;; http-await gives its response.
    (call-with-request-group session
      (lambda (go)
        (let* ((a (go 'get (url "/status/202")))
               (b (go 'get (url "/status/203"))))
          (write (list (http-response-status (http-await a))
                       (http-response-status (http-await b))))
          (newline))))))
