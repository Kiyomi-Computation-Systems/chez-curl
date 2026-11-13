#!r6rs
;;; engine-and-tokens.sps: with (curl), requests submitted to one engine,
;;; their tokens awaited, or taken from a mailbox as each transfer ends.
;;; Start the test server first, from the repository's root, in a terminal
;;; of its own, and leave it running:
;;;   node tests/origin.mjs
;;; It prints one line, {"node":...,"http":"127.0.0.1:PORT","raw":...}, PORT
;;; a new one at each start, and serves until Ctrl-D. Then run this from the
;;; root, URL being http:// and the address after "http": (raw's and h2c's
;;; speak other protocols), with no trailing /:
;;;   scheme --libdirs src --program examples/engine-and-tokens.sps URL
(import (rnrs) (curl))

(define base (cadr (command-line)))

;; One engine: a thread of its own, which runs every transfer submitted.
(define engine (make-curl-engine))

;; A request is data; curl-request-with makes another from it.
(define ok (make-curl-request (string-append base "/status/200") 'timeout-ms 10000))
(define created (curl-request-with ok 'url (string-append base "/status/201")))
(define accepted (curl-request-with ok 'url (string-append base "/status/202")))

;; A submit answers a token at once; an await waits for its response.
(display (curl-response-status (curl-token-await (curl-submit engine ok))))
(newline)

;; With a mailbox, each token goes there when its transfer ends. They end
;; in no fixed order: sort what they answer.
(define mailbox (make-curl-mailbox))
(for-each (lambda (request) (curl-submit engine request mailbox))
          (list ok created accepted))
(let loop ((left 3) (statuses '()))
  (if (= left 0)
      (begin (write (list-sort < statuses)) (newline))
      (let ((token (curl-mailbox-take mailbox 10000)))
        (loop (- left 1)
              (cons (curl-response-status (curl-token-await token)) statuses)))))

;; A stop ends what the engine still holds, frees it all, and ends its thread.
(curl-engine-stop engine)
