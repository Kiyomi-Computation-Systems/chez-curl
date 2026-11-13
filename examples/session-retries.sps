#!r6rs
;;; session-retries.sps: a session's defaults, a redirect followed, and a
;;; retry policy. The test server's /parts?key=K&fail=2 answers 503 to K's
;;; first two requests, then 200. It counts K for as long as it runs, so
;;; each run takes a key it has never counted.
;;; Start the test server first, from the repository's root, in a terminal
;;; of its own, and leave it running:
;;;   node tests/origin.mjs
;;; It prints one line, {"node":...,"http":"127.0.0.1:PORT","raw":...}, PORT
;;; a new one at each start, and serves until Ctrl-D. Then run this from the
;;; root, URL being http:// and the address after "http": (raw's and h2c's
;;; speak other protocols), with no trailing /:
;;;   scheme --libdirs src --program examples/session-retries.sps URL
(import (rnrs) (http-client))

(define base (cadr (command-line)))

(define (show . items)
  (for-each display items)
  (newline))

;; unseen-key : Session String -> String
;; PREFIX and a number: the first such key the server has counted no
;; request for, as its /seen?key=K says, "seen 0".
(define (unseen-key session prefix)
  (let loop ((n 1))
    (let* ((key (string-append prefix (number->string n)))
           (seen (http-get session (string-append base "/seen?key=" key))))
      (if (string=? "seen 0\n" (http-response-text seen))
          key
          (loop (+ n 1))))))

(call-with-http-session 'timeout-ms 10000
                        'retry (make-http-retry 'attempts 3 'backoff-ms 10 'statuses '(503))
  (lambda (session)
    ;; A redirect is followed; the 302 joins the response's history.
    (let ((response (http-get session (string-append base "/redirect/302?to=/status/200"))))
      (show (http-response-status response) " "
            (map http-response-status (http-response-history response))))
    ;; The server answers this URL 503 twice, then 200.
    (let ((url (string-append base "/parts?key=" (unseen-key session "example-retry-")
                              "&fail=2")))
      ;; A call's retry #f overrides the session's policy: the 503 is answered.
      (show (http-response-status (http-get session url 'retry #f)))
      ;; With the policy, the second 503 is retried, and the 200 after it is
      ;; answered. A retried response joins no history.
      (let ((response (http-get session url)))
        (show (http-response-status response) " " (http-response-history response))))))
