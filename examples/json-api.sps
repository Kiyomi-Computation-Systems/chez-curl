#!r6rs
;;; json-api.sps: a JSON API, called with the headers it insists on. The
;;; test server's /json stands in for one: it answers 406 unless Accept names
;;; application/json, and refuses a body unless its Content-Type does. This
;;; sends JSON that jsonparse writes, decodes what comes back, and prints a
;;; few lines. It needs jsonparse, a submodule: on the host, once,
;;; git submodule update --init --recursive, then make deps, which links it
;;; into build/scheme-libs.
;;; Start the test server first, from the repository's root, in a terminal
;;; of its own, and leave it running:
;;;   node tests/origin.mjs
;;; It prints one line, {"node":...,"http":"127.0.0.1:PORT","raw":...}, PORT
;;; a new one at each start, and serves until Ctrl-D. Then run this from the
;;; root, URL being http:// and the address after "http": (raw's and h2c's
;;; speak other protocols), with no trailing /:
;;;   scheme --libdirs src:build/scheme-libs --program examples/json-api.sps URL
(import (rnrs) (http-client) (jsonparse easy))

(define base (cadr (command-line)))

;; show : Any -> Unit
(define (show x) (write x) (newline))

;; media-type : String -> String
;; A Content-Type's type and subtype: its text before any ;, which begins
;; its parameters, such as charset, with no space or tab at either end, and
;; A to Z as a to z.
(define (media-type value)
  (define (before-semicolon cs)
    (if (or (null? cs) (char=? (car cs) #\;)) '() (cons (car cs) (before-semicolon (cdr cs)))))
  (define (drop-blanks cs)
    (if (and (pair? cs) (memv (car cs) '(#\space #\tab))) (drop-blanks (cdr cs)) cs))
  (list->string
   (map (lambda (c) (if (char<=? #\A c #\Z) (integer->char (+ (char->integer c) 32)) c))
        (reverse (drop-blanks (reverse (drop-blanks (before-semicolon (string->list value)))))))))

;; json-answer : Response Integer -> Any
;; The response's body, decoded from its bytes, once its status is STATUS
;; and its Content-Type's media type application/json; else an error.
(define (json-answer response status)
  (let ((type (http-response-header response "Content-Type")))
    (unless (and (= (http-response-status response) status)
                 type (string=? (media-type type) "application/json"))
      (error 'json-answer "not the JSON answer expected" (http-response-status response) type))
    (bytevector->json (http-response-body response))))

;; Every call of this session sends its Accept.
(call-with-http-session 'headers '(("Accept" . "application/json")) 'timeout-ms 10000
  (lambda (session)
    (define url (string-append base "/json"))
    ;; A GET: the API answers what it got.
    (let ((got (json-answer (http-get session url) 200)))
      (show (list (json-ref got "method") (json-ref got "accept"))))
    ;; A POST adds its Content-Type, and sends JSON's bytes.
    (let ((got (json-answer
                (http-post session url
                           'headers '(("Content-Type" . "application/json"))
                           'body (json->bytevector '(("name" . "Ada") ("langs" . #("Scheme" "C")))))
                201)))
      (show (list (json-ref got "bytes") (json-ref got "json" "name") (json-ref got "json" "langs" 1))))
    ;; A call's header replaces the session's of its name: this API says 406.
    (let ((got (json-answer (http-get session url 'headers '(("Accept" . "text/html"))) 406)))
      (show (list (json-ref got "error") (json-ref got "accept"))))
    ;; A body that is no JSON raises &json-error, its reason and byte offset.
    (show (guard (e ((json-error? e) (list (json-error-reason e) (json-error-offset e))))
            (bytevector->json (http-response-body (http-get session (string-append base "/status/200"))))))))
