#!r6rs
;;; The suite for the cap on a transfer's response headers (ADR-0040): 1,000
;;; header lines and 102,400 bytes over the whole transfer, counted by the header
;;; callable every transfer sets, and refused there as header-limit, a
;;; reason of &curl-too-large, against the test origin's head routes, their
;;; bytes held by test-origin and test-origin-tls.
;;;
;;;   - the cap's values, written out;
;;;   - the edges, 1,000 and 1,001 lines, 102,400 and 102,401 bytes, and one
;;;     long line at the cap's own edge, buffered and streamed, over
;;;     HTTP/1.1 and HTTP/2, each refusal beside the neighbour that passes;
;;;     for a stream, that no head was published and that its port raises
;;;     the reason;
;;;   - every head kind counting across the transfer, each head alone under
;;;     the cap: a 103 and a 100 head, HTTP/1.1 and HTTP/2 trailers, a
;;;     Digest round, a 417 and its resend, and a CONNECT answer, through
;;;     the origin's proxy armed by /proxy-arm; their bytes too;
;;;   - a status line exempt at a head's start alone: header lines named as a
;;;     status line begins, HTTP/1.1 x, mid-head; a trailer section's first
;;;     line named HTTP/x; and an HTTP/1.0 status line, exempt;
;;;   - the rule that once any reason is recorded the callable refuses every
;;;     later call, by the private mark, (mark N), which records a reason and
;;;     answers its line, since the Linux libcurls never call again after a
;;;     refusal;
;;;   - the high level, a call and a streamed call;
;;;   - a per-version table, written out here (ADR-0017): libcurl's own
;;;     refusals that come before a line reaches the callable, the cap's own
;;;     code by version, 23, 0 for 8.5.0's HTTP/2 trailers, and on 8.7.1 56
;;;     for an HTTP/2 head and 23 for its trailers, and 7.85.0's HTTP/2
;;;     trailers among a response's headers. A
;;;     libcurl with no row fails by name, and prints the row it measured.
;;;
;;; Every refusal is read from the outcome by its reason and its class, never by
;;; its code, which the table alone holds: 8.5.0 ends a transfer whose HTTP/2
;;; trailer the callable refused 0, and 8.7.1 ends one whose HTTP/2 head line it
;;; refused 56. Each transfer runs on an engine of its own, stopped after it, so
;;; no connection outlives its test: the raw face closes after each answer
;;; without saying so, and 8.23.0 reuses such a connection unchecked. Every
;;; computation that can raise runs under a guard that names what was raised,
;;; and no expected value is #f: SRFI-64 makes #f of a raise in the actual
;;; expression.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) parameterize)
        (curl-testing)
        (curl)
        (curl unsupported)
        (http-client)
        (only (curl private transfer) header-line-cap header-byte-cap curl-request-with-head-mark
              planted-head-mark)
        (curl private counters))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; written : Any -> String
(define (written x) (call-with-string-output-port (lambda (p) (write x p))))

;; shown : Any -> String
;; X written, cut to 4000 characters.
(define (shown x)
  (let ((text (written x)))
    (if (> (string-length text) 4000)
        (string-append (substring text 0 4000) "...")
        text)))

;; The simple runner names a failing test but not its values. Print both.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (display "  expected: ")
        (display (shown (test-result-ref r 'expected-value)))
        (newline)
        (display "  actual:   ")
        (display (shown (test-result-ref r 'actual-value)))
        (newline))
      ;; A suite killed at its bound never flushes: flush each verdict.
      (flush-output-port (current-output-port)))))

(test-begin "headers")

;; --- helpers --------------------------------------------------------------------------

(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)))

;; The loaded libcurl's version, read before any engine's thread is forked.
(define version
  (guard (e (#t (list 'no-version (describe e))))
    (libcurl-info-version (loaded-libcurl))))

;; The run's PKI, for the h2 face and raw-tls, which the proxy tunnels to.
(define pki-made
  (guard (e (#t (list 'raised (describe e))))
    (list 'made (make-test-pki))))
(define pki (and (eq? (car pki-made) 'made) (cadr pki-made)))
(define ca (and pki (string-append pki "/ca.pem")))

(test-equal "the run's PKI is made"
  'made
  (car pki-made))

(test-equal "the cap's values, written out: 1,000 header lines and 102,400 bytes, over the whole transfer"
  '(1000 102400)
  (list header-line-cap header-byte-cap))

;; hostport : Origin Symbol -> String
(define (hostport o face)
  (let ((f (origin-face o face))) (string-append (car f) ":" (number->string (cdr f)))))

;; face-url : Origin Symbol String -> String
(define (face-url o face path)
  (string-append (if (memq face '(raw http)) "http://" "https://") (hostport o face) path))

;; request-for : Origin Symbol String Any ... -> Request
;; A GET of PATH on FACE, direct, a 30 s bound, the run's CA file for a TLS
;; face, with KEYS after.
(define (request-for o face path . keys)
  (apply make-curl-request (face-url o face path) 'proxy #f 'timeout-ms 30000
         (append (if (memq face '(raw http)) '() (list 'ca-file ca)) keys)))

;; tunnelled-for : Origin Symbol String -> Request
;; A GET of PATH on FACE, a TLS face, through the origin's proxy on its http
;; face, by CONNECT.
(define (tunnelled-for o face path)
  (make-curl-request (face-url o face path) 'proxy (string-append "http://" (hostport o 'http))
                     'timeout-ms 30000 'ca-file ca))

;; with-engine : (Engine -> Any) -> Any
;; PROC's answer, on an engine of its own, stopped as PROC returns or
;; escapes.
(define (with-engine proc)
  (let ((e (make-curl-engine)))
    (dynamic-wind (lambda () #f) (lambda () (proc e)) (lambda () (curl-engine-stop e)))))

;; class-of : Condition -> Symbol
;; The class a failure was raised as, by the six predicates; none for the
;; base type alone.
(define (class-of e)
  (cond ((curl-too-large? e) 'too-large) ((curl-send-receive-error? e) 'send-receive)
        ((curl-protocol-error? e) 'protocol) ((curl-timeout? e) 'timeout)
        ((curl-connect-error? e) 'connect) ((curl-tls-error? e) 'tls)
        ((curl-transfer-error? e) 'none) (else 'not-a-transfer-error)))

;; answer-of : (U Response Condition #f) -> List
;; An outcome, as data: (response STATUS HEADERS), its status and how many
;; headers the response holds; or (refused REASON CODE CLASS RECORDED).
(define (answer-of outcome)
  (cond ((curl-response? outcome)
         (list 'response (curl-response-status outcome) (length (curl-response-headers outcome))))
        ((curl-transfer-error? outcome)
         (list 'refused (curl-transfer-error-reason outcome) (curl-transfer-error-code outcome)
               (class-of outcome) (curl-transfer-error-recorded outcome)))
        (else (list 'other (describe outcome)))))

;; verdict : List -> List
;; ANSWER with a refusal's code left out: what the shared tests assert, the
;; reason, the class and what was recorded. The code is the table's.
(define (verdict answer)
  (if (and (pair? answer) (eq? (car answer) 'refused) (= (length answer) 5))
      (list 'refused (list-ref answer 1) (list-ref answer 3) (list-ref answer 4))
      answer))

;; buffered : Request -> List
;; REQUEST's answer, submitted to an engine of its own and awaited.
(define (buffered request)
  (guard (e (#t (list 'raised (describe e))))
    (with-engine
     (lambda (e)
       (let* ((token (curl-submit e request))
              (ended (curl-token-wait token 40000)))
         (if ended (answer-of (curl-token-outcome token)) (list 'not-ended)))))))

;; port-end : Binary-Input-Port -> List
;; The port read to its end: (eof N), N the bytes read, or (raised REASON)
;; for the transfer's failure it raises.
(define (port-end port)
  (let loop ((n 0))
    (let ((got (guard (e (#t (cons 'raised e))) (get-bytevector-some port))))
      (cond ((eof-object? got) (list 'eof n))
            ((bytevector? got) (loop (+ n (bytevector-length got))))
            ((curl-transfer-error? (cdr got)) (list 'raised (curl-transfer-error-reason (cdr got))))
            (else (list 'raised-other (describe (cdr got))))))))

;; streamed : Request -> List
;; REQUEST streamed, stream-buffer 65536, on an engine of its own: its
;; answer, the head it published, (head STATUS HEADERS) or no-head, and its
;; port's end.
(define (streamed request)
  (guard (e (#t (list 'raised (describe e))))
    (with-engine
     (lambda (e)
       (let* ((token (curl-submit e (curl-request-with request 'stream-buffer 65536)))
              (arrived (curl-token-head-wait token 40000))
              (head (curl-token-head token))
              (end (port-end (curl-token-body-port token)))
              (ended (curl-token-wait token 40000)))
         (list (if ended (answer-of (curl-token-outcome token)) (list 'not-ended))
               (if head (list 'head (curl-head-status head) (length (curl-head-headers head))) 'no-head)
               end))))))

;; both : Request -> List
;; REQUEST buffered, then streamed, each answer's code left out.
(define (both request)
  (let* ((one (buffered request))
         (two (streamed request)))
    (list (verdict one)
          (if (and (pair? two) (pair? (car two))) (cons (verdict (car two)) (cdr two)) two))))

;; armed : Origin Natural Natural -> List
;; The proxy armed: its next CONNECT answered 200 carries N lines of LINE
;; bytes. The arm's own GET's answer.
(define (armed o n line)
  (buffered (request-for o 'http (string-append "/proxy-arm?n=" (number->string n)
                                                "&line=" (number->string line)))))

(define taken-1000 '(response 200 1000))
(define capped '(refused header-limit too-large #f))
(define capped-stream (list capped 'no-head '(raised header-limit)))

;; --- the per-version table (ADR-0017) ----------------------------------------------------

;; varying-cases : (Listof (List Symbol Symbol String))
;; The cases whose answers vary by version, each a buffered GET on a face: the
;; cap's own refusal over HTTP/1.1, of an HTTP/2 head and of an HTTP/2 trailer,
;; by its code; libcurl's refusals before a line reaches the callable: a line of
;; 102,400 bytes over HTTP/1.1, over HTTP/2 Huffman-coded and raw; an HTTP/2
;; head of 131,072 bytes, past 7.85.0's 128 KiB; one past nghttp2's limit,
;; 307,199 bytes of 256-byte lines; HTTP/2 trailers past nghttp2's limit; a
;; trailer line of 5,000 bytes over HTTP/1.1, and over HTTP/2, the response's
;; headers holding it on 7.85.0; and 6,000 HTTP/2 trailers.
(define varying-cases
  '((cap-h1 raw "/raw/head?n=1001")
    (cap-h2-head h2 "/head?n=1001")
    (cap-h2-trailer h2 "/head?n=2&tn=999")
    (line-102400-h1 raw "/raw/head?n=1&big=102400")
    (line-102400-h2 h2 "/head?n=1&big=102400")
    (line-102400-h2-raw h2 "/head?n=1&big=102400&bigch=X")
    (head-131072-h2 h2 "/head?total=131072&line=256&slen=13")
    (head-past-nghttp2-h2 h2 "/head?total=307199&line=256&slen=13")
    (trailers-past-nghttp2-h2 h2 "/head?n=2&tn=1600&tl=256")
    (trailer-line-5000-h1 raw "/raw/head?n=2&tn=1&tl=5000")
    (trailer-line-5000-h2 h2 "/head?n=2&tn=1&tl=5000")
    (trailers-6000-h2 h2 "/head?n=2&tn=6000")))

;; rows : (Listof (Pair String (Listof (Pair Symbol Answer))))
;; Each libcurl's answer to every varying case, written out: the Linux libcurls'
;; measured through the engine, two runs each, every one alike; 8.5.0 with
;; OpenSSL and with GnuTLS alike; Apple's 8.7.1's from a probe's two runs on
;; macOS, its cap mode's, libcurl and a header callback alone. An answer is
;; answer-of's, (one-of ANSWER ...) for a cell that races. The header-limit rows
;; read the recorded reason; the code beside it is libcurl's answer to the
;; refusal.
(define rows
  '(("7.85.0"
     (cap-h1 refused header-limit 23 too-large #f)
     (cap-h2-head refused header-limit 23 too-large #f)
     (cap-h2-trailer refused header-limit 23 too-large #f)
     (line-102400-h1 refused perform-failed 27 none #f)
     (line-102400-h2 refused perform-failed 27 none #f)
     (line-102400-h2-raw refused perform-failed 52 send-receive #f)
     (head-131072-h2 refused perform-failed 56 send-receive #f)
     (head-past-nghttp2-h2 refused perform-failed 56 send-receive #f)
     (trailers-past-nghttp2-h2 refused perform-failed 56 send-receive #f)
     (trailer-line-5000-h1 refused perform-failed 56 send-receive #f)
     (trailer-line-5000-h2 response 200 3)
     (trailers-6000-h2 refused header-limit 23 too-large #f))
    ("8.5.0"
     (cap-h1 refused header-limit 23 too-large #f)
     (cap-h2-head refused header-limit 23 too-large #f)
     (cap-h2-trailer refused header-limit 0 too-large #f)
     (line-102400-h1 refused perform-failed 27 none #f)
     (line-102400-h2 refused perform-failed 27 none #f)
     (line-102400-h2-raw refused perform-failed 56 send-receive #f)
     (head-131072-h2 refused header-limit 23 too-large #f)
     (head-past-nghttp2-h2 refused perform-failed 56 send-receive #f)
     (trailers-past-nghttp2-h2 refused perform-failed 56 send-receive #f)
     (trailer-line-5000-h1 refused perform-failed 56 send-receive #f)
     (trailer-line-5000-h2 response 200 2)
     (trailers-6000-h2 refused header-limit 0 too-large #f))
    ("8.7.1"
     (cap-h1 refused header-limit 23 too-large #f)
     (cap-h2-head refused header-limit 56 too-large #f)
     (cap-h2-trailer refused header-limit 23 too-large #f)
     (line-102400-h1 refused perform-failed 100 too-large #f)
     (line-102400-h2 refused perform-failed 56 send-receive #f)
     (line-102400-h2-raw refused perform-failed 16 protocol #f)
     (head-131072-h2 refused header-limit 56 too-large #f)
     (head-past-nghttp2-h2 refused header-limit 56 too-large #f)
     (trailers-past-nghttp2-h2 refused perform-failed 56 send-receive #f)
     (trailer-line-5000-h1 refused perform-failed 100 too-large #f)
     (trailer-line-5000-h2 response 200 2)
     (trailers-6000-h2 refused header-limit 23 too-large #f))
    ("8.20.0"
     (cap-h1 refused header-limit 23 too-large #f)
     (cap-h2-head refused header-limit 23 too-large #f)
     (cap-h2-trailer refused header-limit 23 too-large #f)
     (line-102400-h1 refused perform-failed 100 too-large #f)
     (line-102400-h2 refused perform-failed 16 protocol #f)
     (line-102400-h2-raw refused perform-failed 16 protocol #f)
     (head-131072-h2 refused header-limit 23 too-large #f)
     (head-past-nghttp2-h2 refused header-limit 23 too-large #f)
     (trailers-past-nghttp2-h2 refused perform-failed 16 protocol #f)
     (trailer-line-5000-h1 refused perform-failed 100 too-large #f)
     (trailer-line-5000-h2 response 200 2)
     (trailers-6000-h2 refused header-limit 23 too-large #f))
    ("8.23.0"
     (cap-h1 refused header-limit 23 too-large #f)
     (cap-h2-head refused header-limit 23 too-large #f)
     (cap-h2-trailer refused header-limit 23 too-large #f)
     (line-102400-h1 refused perform-failed 100 too-large #f)
     (line-102400-h2 refused perform-failed 56 send-receive #f)
     (line-102400-h2-raw refused perform-failed 16 protocol #f)
     (head-131072-h2 refused header-limit 23 too-large #f)
     (head-past-nghttp2-h2 refused header-limit 23 too-large #f)
     (trailers-past-nghttp2-h2 refused perform-failed 56 send-receive #f)
     (trailer-line-5000-h1 refused perform-failed 100 too-large #f)
     (trailer-line-5000-h2 response 200 2)
     (trailers-6000-h2 refused perform-failed 56 send-receive #f))))

;; row : (U (Listof (Pair Symbol Answer)) #f)
;; This libcurl's row.
(define row (let ((found (assoc version rows))) (and found (cdr found))))

;; cell : Symbol -> Any
;; This libcurl's answer to CASE: its row's, or (no-row CASE), which no
;; measurement gives, for a libcurl with no row.
(define (cell case)
  (let ((found (and row (assq case row))))
    (if found (cdr found) (list 'no-row case))))

;; matches? : Any Any -> Boolean
;; Whether MEASURED is the cell WANT, or one of a racing cell's answers.
(define (matches? want measured)
  (if (and (pair? want) (eq? (car want) 'one-of))
      (and (member measured (cdr want)) #t)
      (equal? want measured)))

;; cap-code : Symbol -> Any
;; The code the cap's own refusal of CASE's kind ends with on this libcurl,
;; by its row: cap-h1, cap-h2-head or cap-h2-trailer.
(define (cap-code case)
  (let ((answer (cell case)))
    (if (and (pair? answer) (eq? (car answer) 'refused)) (list-ref answer 2) (list 'no-code answer))))

;; trailers-listed? : Any
;; Whether this libcurl lists HTTP/2 trailers among a response's headers,
;; by its row: 7.85.0 does.
(define trailers-listed?
  (let ((answer (cell 'trailer-line-5000-h2)))
    (cond ((equal? answer '(response 200 3)) #t)
          ((equal? answer '(response 200 2)) #f)
          (else (list 'unknown answer)))))

;; h2-trailer-headers : Natural Natural -> Any
;; How many headers a 200 with HEAD lines and TRAILERS HTTP/2 trailers
;; holds on this libcurl: HEAD, or both on 7.85.0.
(define (h2-trailer-headers head trailers)
  (cond ((eq? trailers-listed? #t) (+ head trailers))
        ((eq? trailers-listed? #f) head)
        (else trailers-listed?)))

;; --- the scenarios, against one origin ------------------------------------------------

(define (scenarios o)

  ;; --- the edges ---------------------------------------------------------------------
  (for-each
   (lambda (face slen long)
     (let ((name (if (eq? face 'raw) "HTTP/1.1" "HTTP/2")))
       (test-equal (string-append name ": 1,000 header lines are taken, buffered and streamed; 1,001 are refused, header-limit, of &curl-too-large, buffered, and streamed with no head published and its port raising header-limit")
         (list (list taken-1000 (list taken-1000 '(head 200 1000) '(eof 0)))
               (list capped capped-stream))
         (list (both (request-for o face (if (eq? face 'raw) "/raw/head?n=1000" "/head?n=1000")))
               (both (request-for o face (if (eq? face 'raw) "/raw/head?n=1001" "/head?n=1001")))))
       (test-equal (string-append name ": a head of 102,400 bytes as the callable counts them, its status line of " (number->string slen) " bytes, every line's CR LF and the empty line in, is taken, buffered and streamed; one of 102,401 is refused, header-limit, at its empty line, with no head published")
         (list (list '(response 200 401) (list '(response 200 401) '(head 200 401) '(eof 0)))
               (list capped capped-stream))
         (map (lambda (total)
                (both (request-for o face (string-append (if (eq? face 'raw) "/raw/head" "/head") "?total="
                                                         (number->string total) "&line=256&slen="
                                                         (number->string slen)))))
              '(102400 102401)))
       (test-equal (string-append name ": one line of " (number->string long) " bytes after content-length: 0 takes the head to 102,400 bytes, taken; one byte more is refused, header-limit, though libcurl takes a line of 102,399")
         (list (list '(response 200 2) (list '(response 200 2) '(head 200 2) '(eof 0)))
               (list capped capped-stream))
         (map (lambda (big)
                (both (request-for o face (string-append (if (eq? face 'raw) "/raw/head" "/head") "?n=1&big="
                                                         (number->string big)))))
              (list long (+ long 1))))))
   '(raw h2) '(17 13) '(102362 102366))

  ;; --- a status line is exempt only at a head's start ---------------------------------
  ;; Lines named HTTP/1.1 x-000001 on begin as a status line does, HTTP/1.1 and a
  ;; space, and libcurl takes each as a header, on every libcurl measured:
  ;; mid-head, each is a header line. A trailer section's first line starts a
  ;; section, where a status line would be exempt: named HTTP/x, it is a header
  ;; line. And an HTTP/1.0 status line is exempt as HTTP/1.1's is. HTTP/2 refuses
  ;; a / in a name, so these are HTTP/1.1's alone.
  (test-equal "HTTP/1.1: 1,000 header lines named HTTP/1.1 x-NNNNNN, as a status line begins, are taken, buffered and streamed; 1,001 are refused, header-limit: a status line is exempt at a head's start alone"
    (list (list taken-1000 (list taken-1000 '(head 200 1000) '(eof 0)))
          (list capped capped-stream))
    (map (lambda (n) (both (request-for o 'raw (string-append "/raw/head?n=" (number->string n) "&line=32&hname=1"))))
         '(1000 1001)))
  (test-equal "HTTP/1.1: a trailer section's first line named HTTP/x is a header line, though it starts the section: 2 head lines and 998 trailers are taken, buffered and streamed; 999 are refused, header-limit, after the head was published; 300 trailers of 256 bytes, the first HTTP/x, are taken, and 400 refused"
    (list (list '(response 200 2) (list '(response 200 2) '(head 200 2) '(eof 0)))
          (list capped (list capped '(head 200 2) '(raised header-limit)))
          (list '(response 200 2) (list '(response 200 2) '(head 200 2) '(eof 0)))
          (list capped (list capped '(head 200 2) '(raised header-limit))))
    (map (lambda (q) (both (request-for o 'raw (string-append "/raw/head?n=2&tname=1&" q))))
         '("tn=998" "tn=999" "tn=300&tl=256" "tn=400&tl=256")))
  (test-equal "HTTP/1.0: a head of 1,000 header lines, its status line HTTP/1.0 200 OK, is taken, buffered and streamed; 1,001 are refused, header-limit: an HTTP/1.0 status line is exempt as an HTTP/1.1 one is"
    (list (list taken-1000 (list taken-1000 '(head 200 1000) '(eof 0)))
          (list capped capped-stream))
    (map (lambda (n) (both (request-for o 'raw (string-append "/raw/head?n=" (number->string n) "&v10=1"))))
         '(1000 1001)))

  ;; --- every head kind counts across the transfer ------------------------------------
  (for-each
   (lambda (face)
     (let ((name (if (eq? face 'raw) "HTTP/1.1" "HTTP/2"))
           (head (if (eq? face 'raw) "/raw/head" "/head")))
       (for-each
        (lambda (status)
          (test-equal (string-append name ": a " (number->string status) " head of 500 lines and a final head of 500 are taken, buffered and streamed; of 500 and 501, refused, header-limit, the count across both heads, each under the cap")
            (list (list '(response 200 500) (list '(response 200 500) '(head 200 500) '(eof 0)))
                  (list capped capped-stream))
            (map (lambda (n)
                   (both (request-for o face (string-append head "?pre=" (number->string status)
                                                            ":500:16&n=" (number->string n)))))
                 '(500 501))))
        '(103 100))
       (test-equal (string-append name ": a 103 head of 150 lines of 256 bytes and a final head of 150 are taken; of 250 and 250, 128,000 bytes or so, refused, header-limit, the bytes across both heads, each under 102,400")
         (list (list '(response 200 150) (list '(response 200 150) '(head 200 150) '(eof 0)))
               (list capped capped-stream))
         (map (lambda (n)
                (both (request-for o face (string-append head "?pre=103:" (number->string n) ":256&n="
                                                         (number->string n) "&line=256"))))
              '(150 250)))
       (test-equal (string-append name ": a head of 2 lines and 998 trailers are taken, buffered and streamed, the stream's head published before them; 999 trailers are refused, header-limit, after the head was published")
         (let ((listed (if (eq? face 'raw) 2 (h2-trailer-headers 2 998))))
           (list (list (list 'response 200 listed) (list (list 'response 200 listed) '(head 200 2) '(eof 0)))
                 (list capped (list capped '(head 200 2) '(raised header-limit)))))
         (map (lambda (n) (both (request-for o face (string-append head "?n=2&tn=" (number->string n)))))
              '(998 999)))
       (test-equal (string-append name ": 300 trailers of 256 bytes are taken; 400, 102,400 bytes of trailers, are refused, header-limit, the bytes across the head and the trailers")
         (let ((listed (if (eq? face 'raw) 2 (h2-trailer-headers 2 300))))
           (list (list (list 'response 200 listed) (list (list 'response 200 listed) '(head 200 2) '(eof 0)))
                 (list capped (list capped '(head 200 2) '(raised header-limit)))))
         (map (lambda (n) (both (request-for o face (string-append head "?n=2&tn=" (number->string n) "&tl=256"))))
              '(300 400)))
       ;; A Digest round, buffered alone: Digest beside a stream is refused.
       ;; The 401 holds its www-authenticate line and a.n lines, 500 for
       ;; a.n=499.
       (test-equal (string-append name ": a Digest round, its 401 of 500 lines and its 200 of 500, is taken; of 500 and 501, refused, header-limit, the count across both responses; of 251 and 250 lines of 256 bytes, refused, the bytes across both")
         (list '(response 200 500) capped capped)
         (map (lambda (spec)
                (verdict (buffered (request-for o face (string-append (if (eq? face 'raw) "/raw/head-auth" "/head-auth")
                                                                      "?" spec)
                                                'credentials '(digest "user" "secret")))))
              '("a.n=499&b.n=500" "a.n=499&b.n=501" "a.n=250&a.line=256&b.n=250&b.line=256")))))
   '(raw h2))
  ;; A 417 and its resend, buffered alone, a caller's Expect: 100-continue: a
  ;; stream refuses it. The resend gets a 100 Continue first, a head of no lines.
  ;; Under the memory gate's Valgrind, 8.20.0 resent on a new connection once, so
  ;; the route holds its 417 by key, one per request here, not by connection.
  ;; libcurl's wait for the 417 is raised through the hatch past the transfer's
  ;; bound, so the body never goes first, and the body is digits, never a letter
  ;; the route would read as the next request's start.
  (test-equal "HTTP/1.1: a 417 of 500 lines and its resend's 200 of 500 are taken; of 500 and 501, refused, header-limit, the count across both responses; of 250 and 250 lines of 256 bytes, refused, the bytes across both"
    (list '(response 200 500) capped capped)
    (map (lambda (spec)
           (verdict (buffered (curl-request-with-options
                               (request-for o 'raw (string-append "/raw/head417?key=" (car spec) "&" (cadr spec))
                                            'method 'post 'body (string->utf8 "0123456789")
                                            'headers '(("Expect" . "100-continue")))
                               '(("EXPECT_100_TIMEOUT_MS" . 60000))))))
         '(("k1" "a.n=500&b.n=500") ("k2" "a.n=500&b.n=501") ("k3" "a.n=250&a.line=256&b.n=250&b.line=256"))))
  ;; A CONNECT answer, through the origin's proxy, armed before each
  ;; transfer: its lines count with the tunnelled response's.
  (for-each
   (lambda (face)
     (let ((name (if (eq? face 'raw-tls) "HTTP/1.1 over TLS" "HTTP/2"))
           (head (if (eq? face 'raw-tls) "/raw/head" "/head")))
       (test-equal (string-append name " through the proxy: a CONNECT answer of 500 lines and a response of 500 are taken, buffered and streamed; of 500 and 501, refused, header-limit, the count across both; of 250 and 250 lines of 256 bytes, refused, the bytes across both")
         (list (list '(response 200 500) (list '(response 200 500) '(head 200 500) '(eof 0)))
               (list capped capped-stream)
               (list capped capped-stream))
         (map (lambda (arm path)
                (let* ((one (begin (armed o (car arm) (cadr arm)) (buffered (tunnelled-for o face path))))
                       (two (begin (armed o (car arm) (cadr arm)) (streamed (tunnelled-for o face path)))))
                  (list (verdict one)
                        (if (and (pair? two) (pair? (car two))) (cons (verdict (car two)) (cdr two)) two))))
              '((500 16) (500 16) (250 256))
              (list (string-append head "?n=500") (string-append head "?n=501")
                    (string-append head "?n=250&line=256"))))))
   '(raw-tls h2))

  ;; --- once a reason is recorded, every later call is refused -----------------------
  ;; The private mark records a reason at the head's line 2, its
  ;; content-length line, and answers that line, so libcurl hands the next:
  ;; refused, the transfer ends there, with the h1 cap code, and a stream
  ;; never publishes its head. Without the refusal libcurl would end it 0,
  ;; the head published.
  (test-equal "a reason recorded at the head's line 2 by the private mark refuses every later call: buffered, callback-raised, (planted-head-mark 2), ended at line 3 with this libcurl's code for a refused HTTP/1.1 line; streamed, no head published, its port raising callback-raised; beside the same request without the mark, taken whole"
    (let ((marked (list 'refused 'callback-raised (cap-code 'cap-h1) 'none (planted-head-mark 2))))
      (list '(response 200 5) (list '(response 200 5) '(head 200 5) '(eof 0))
            marked (list marked 'no-head '(raised callback-raised))))
    (let ((plain (request-for o 'raw "/raw/head?n=5")))
      (list (buffered plain) (streamed plain)
            (buffered (curl-request-with-head-mark plain 2))
            (streamed (curl-request-with-head-mark plain 2)))))

  ;; --- the high level ------------------------------------------------------------------
  (test-equal "the high level: http-get of 1,000 header lines answers its 200; of 1,001 raises &curl-too-large, header-limit; call-with-response-port of 1,001 raises it too, before PROC"
    '((status 200) (raised header-limit too-large) (raised header-limit too-large))
    (guard (e (#t (list 'raised (describe e))))
      (call-with-http-session 'proxy #f 'timeout-ms 30000
        (lambda (s)
          (define (raised thunk)
            (guard (e ((curl-transfer-error? e)
                       (list 'raised (curl-transfer-error-reason e) (class-of e))))
              (thunk)
              (list 'no-raise)))
          (list (list 'status (http-response-status (http-get s (face-url o 'raw "/raw/head?n=1000"))))
                (raised (lambda () (http-get s (face-url o 'raw "/raw/head?n=1001"))))
                (raised (lambda ()
                          (call-with-response-port s 'get (face-url o 'raw "/raw/head?n=1001")
                            (lambda (response port) 'called)))))))))

  ;; --- the table ---------------------------------------------------------------------
  (let ((measured (map (lambda (c) (cons (car c) (buffered (request-for o (cadr c) (caddr c)))))
                       varying-cases)))
    (unless row
      (display (string-append "test-headers: no row in rows for libcurl " (written version)
                              "; measured, it would be:\n")
               (current-error-port))
      (write (cons version (map (lambda (m) (cons (car m) (cdr m))) measured)) (current-error-port))
      (newline (current-error-port)))
    (test-equal (string-append "the loaded libcurl, " (written version) ", has a row in this suite's table")
      'has-a-row
      (if row 'has-a-row (list 'no-row version)))
    (for-each
     (lambda (c m)
       (test-equal (string-append "by version, " (symbol->string (car c)) ": GET " (symbol->string (cadr c)) " "
                                  (caddr c) " answers as this libcurl's row says")
         (list (car c) 'as-the-row)
         (list (car c) (if (matches? (cell (car c)) (cdr m)) 'as-the-row (list 'row (cell (car c)) 'measured (cdr m))))))
     varying-cases measured))
  'done)

;; The scenarios' tests run here, in a definition, and the verdict on their
;; origin after: SRFI-64 keeps one result per runner.
(define scenarios-outcome
  (guard (e (#t (list 'raised (describe e))))
    (parameterize ((origin-pki pki))
      (call-with-origin scenarios))))

(test-equal "the scenarios' origin starts with the PKI, serves them all, and stops"
  'done
  scenarios-outcome)

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "headers")

(exit (suite-exit-status runner))
