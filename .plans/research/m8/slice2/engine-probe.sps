;;; M8 slice 2's measurement through the engine (the M8 plan, section 5),
;;; against the caps stand-in (research/m8/caps/server.mjs), on the probe's
;;; tree: the prototype and its seam (make-proto.py --seam).
;;;
;;;   scheme --libdirs src --program engine-probe.sps LANE CTL H1 H1TLS H2 PROXY CA [GROUP ...]
;;;
;;; Each cell is one GET (a POST for expect) on an engine of its own, made
;;; for it and stopped after it, so no connection outlives its cell, direct
;;; ('proxy #f) or through the stand-in's proxy, a 30 s timeout, the run's CA
;;; file for https; buffered, or streamed ('stream-buffer 65536), its body
;;; read through the token's port with get-bytevector-some. One line a cell:
;;;   cell GROUP LABEL face=F way=W opts=O outcome ... tally=... stream=...
;;; the outcome: (status S version V headers N) or (failed REASON CODE CLASS
;;; "ERROR BUFFER"); the tally, what the header callable was handed, from the
;;; seam: (calls C lines L bytes B heads (STATUS:LINES:BYTES ...) after A), T a
;;; section no status line opened, A the calls it refused because a reason
;;; was recorded already; for a stream, the head it published,
;;; (head S N) or none, the body's bytes read, and how the port ended, eof or
;;; (raised REASON CODE). Then the stand-in's events for the cell: what it
;;; wrote, ev lines. GROUP, when given, runs those groups alone: edge, toward,
;;; early, suppress, options, hatch.
(import (chezscheme) (curl) (curl unsupported)
        (only (curl private transfer) take-header-tallies!))

(define args (command-line-arguments))
(define lane (list-ref args 0))
(define ctl (list-ref args 1))
(define ports (list (cons 'h1 (list-ref args 2)) (cons 'h1tls (list-ref args 3)) (cons 'h2 (list-ref args 4))))
(define proxy-port (list-ref args 5))
(define ca (list-ref args 6))
(define groups (if (> (length args) 7) (map string->symbol (list-tail args 7)) #f))

(define (ms-of t) (+ (* (time-second t) 1000.0) (/ (time-nanosecond t) 1e6)))
(define (now-ms) (ms-of (current-time 'time-monotonic)))
(define (cpu-ms) (ms-of (current-time 'time-process)))

;; --- the control face, on an engine of its own ------------------------------------

(define ctl-engine (make-curl-engine))

;; ctl-get : String -> String
(define (ctl-get path)
  (let* ((token (curl-submit ctl-engine (make-curl-request (string-append "http://127.0.0.1:" ctl path)
                                                           'proxy #f 'timeout-ms 10000)))
         (r (curl-token-await token)))
    (take-header-tallies!)
    (utf8->string (curl-response-body r))))

(define (ctl-seq) (string->number (let ((s (ctl-get "/seq"))) (substring s 0 (- (string-length s) 1)))))

;; events-after : Natural -> (Listof String)
;; The stand-in's event lines after SEQ, those that say what it wrote or
;; how a stream or a tunnel ended.
(define (events-after seq)
  (let ((text (ctl-get (string-append "/events?after=" (number->string seq)))))
    (let loop ((lines (split-lines text)) (out '()))
      (cond ((null? lines) (reverse out))
            ((exists (lambda (k) (string-search (car lines) k))
                     '(" wrote " " h2-close " " connect-answered " " goaway " " note " "still open"))
             (loop (cdr lines) (cons (car lines) out)))
            (else (loop (cdr lines) out))))))

(define (split-lines s)
  (let loop ((i 0) (start 0) (out '()))
    (cond ((= i (string-length s))
           (reverse (if (> i start) (cons (substring s start i) out) out)))
          ((char=? (string-ref s i) #\newline) (loop (+ i 1) (+ i 1) (cons (substring s start i) out)))
          (else (loop (+ i 1) start out)))))

(define (string-search s k)
  (let ((n (string-length s)) (m (string-length k)))
    (let loop ((i 0))
      (cond ((> (+ i m) n) #f)
            ((string=? (substring s i (+ i m)) k) #t)
            (else (loop (+ i 1)))))))

;; --- describing what a cell ended with --------------------------------------------

(define (class-of e)
  (cond ((curl-too-large? e) 'too-large) ((curl-send-receive-error? e) 'send-receive)
        ((curl-protocol-error? e) 'protocol) ((curl-timeout? e) 'timeout)
        ((curl-connect-error? e) 'connect) ((curl-tls-error? e) 'tls)
        ((curl-transfer-error? e) 'none) (else 'not-a-transfer-error)))

(define (describe outcome)
  (cond
    ((curl-response? outcome)
     (format "(status ~a version ~a headers ~a)" (curl-response-status outcome)
             (curl-response-http-version outcome) (length (curl-response-headers outcome))))
    ((curl-transfer-error? outcome)
     (format "(failed ~a ~a ~a ~s)" (curl-transfer-error-reason outcome) (curl-transfer-error-code outcome)
             (class-of outcome) (or (curl-transfer-error-error-buffer outcome) "")))
    ((condition? outcome)
     (format "(raised ~s)" (call-with-string-output-port (lambda (p) (display-condition outcome p)))))
    (else (format "(other ~s)" outcome))))

(define (describe-tally tallies)
  (cond
    ((null? tallies) "none")
    (else
     (let ((t (car tallies)))
       (format "(calls ~a lines ~a bytes ~a heads (~a) after ~a)~a" (list-ref t 0) (list-ref t 1) (list-ref t 2)
               (apply string-append
                      (let loop ((hs (list-ref t 3)) (first #t))
                        (if (null? hs) '()
                            (cons (format "~a~a:~a:~a" (if first "" " ") (car (car hs)) (cadr (car hs)) (caddr (car hs)))
                                  (loop (cdr hs) #f)))))
               (list-ref t 4)
               (if (null? (cdr tallies)) "" (format " (and ~a more)" (length (cdr tallies)))))))))

;; read-stream : Token -> String
;; The head the token published, the body's bytes, and the port's end.
(define (read-stream token)
  (curl-token-head-wait token 30000)
  (let* ((head (curl-token-head token))
         (port (curl-token-body-port token)))
    (let loop ((n 0))
      (let ((got (guard (e (#t (cons 'raised e))) (get-bytevector-some port))))
        (cond
          ((eof-object? got)
           (format "(~a body ~a end eof)" (if head (format "head ~a ~a" (curl-head-status head) (length (curl-head-headers head))) "head none") n))
          ((and (pair? got) (eq? (car got) 'raised))
           (let ((e (cdr got)))
             (format "(~a body ~a end (raised ~a ~a))"
                     (if head (format "head ~a ~a" (curl-head-status head) (length (curl-head-headers head))) "head none") n
                     (if (curl-transfer-error? e) (curl-transfer-error-reason e) 'other)
                     (if (curl-transfer-error? e) (curl-transfer-error-code e) (condition-message* e)))))
          ((bytevector? got) (loop (+ n (bytevector-length got))))
          (else (format "(stream other ~s)" got)))))))

(define (condition-message* e) (if (message-condition? e) (condition-message e) e))

;; --- one cell ---------------------------------------------------------------------

;; cell : Symbol String Symbol String Symbol (Listof Any) -> Void
;; GROUP's cell LABEL on FACE (h1, h1tls, h2) at PATH, WAY buffered or
;; streamed, with SPEC's settings: (arm QUERY) for the proxy's CONNECT
;; answer and the request through the proxy; (keys KEY VALUE ...) more
;; request keys; (options (NAME . VALUE) ...) through the hatch.
(define (cell group label face path way spec)
  (when (or (not groups) (memq group groups))
    (let* ((arm (assq 'arm spec))
           (keys (let ((k (assq 'keys spec))) (if k (cdr k) '())))
           (options (let ((o (assq 'options spec))) (if o (cdr o) '())))
           (scheme (if (eq? face 'h1) "http" "https"))
           (url (string-append scheme "://127.0.0.1:" (cdr (assq face ports)) path
                               (if (memv #\? (string->list path)) "&" "?") "tag=" label "." (symbol->string way)))
           (base (apply make-curl-request url 'timeout-ms 30000
                        'proxy (if arm (string-append "http://127.0.0.1:" proxy-port) #f)
                        (append (if (eq? face 'h1) '() (list 'ca-file ca))
                                (if (eq? way 'streamed) '(stream-buffer 65536) '())
                                keys)))
           (request (if (null? options) base (curl-request-with-options base options))))
      (when arm (ctl-get (string-append "/arm?" (cadr arm) "&tag=" label "." (symbol->string way))))
      (take-header-tallies!)
      (let* ((seq (ctl-seq))
             (engine (make-curl-engine))
             (c0 (cpu-ms))
             (t0 (now-ms))
             (token (curl-submit engine request))
             (streamed (and (eq? way 'streamed) (read-stream token)))
             (ended (curl-token-wait token 40000))
             (t1 (now-ms))
             (c1 (cpu-ms))
             (outcome (curl-token-outcome token)))
        (curl-engine-stop engine)
        (let ((tallies (take-header-tallies!)))
          (printf "cell ~a ~a face=~a~a way=~a opts=~a ended=~a outcome=~a tally=~a stream=~a ms=~,1f cpu_ms=~,1f~%"
                  group label face (if arm "+proxy" "") way
                  (if (null? options) "-" (apply string-append (map (lambda (o) (format "~a=~s;" (car o) (cdr o))) options)))
                  ended (describe outcome) (describe-tally tallies) (or streamed "-") (- t1 t0) (- c1 c0)))
        (for-each (lambda (line) (printf "  ~a~%" line)) (events-after seq))))))

(define (both group label face path spec)
  (cell group label face path 'buffered spec)
  (cell group label face path 'streamed spec))

;; --- the cells --------------------------------------------------------------------

(define (n->s n) (number->string n))

(printf "probe lane=~a libcurl=~a ~a machine=~a groups=~a~%" lane
        (libcurl-info-version (loaded-libcurl)) (libcurl-info-ssl-version (loaded-libcurl)) (machine-type)
        (or groups 'all))

;; edge: 1,000 and 1,001 header lines; 102,400 and 102,401 bytes as the
;; callable counts them, the status line (17 bytes over HTTP/1.1, 13 over
;; HTTP/2), every line and the empty line in; and one long line at the
;; cap's own edge: 17 + 19 + B + 2 bytes over HTTP/1.1, 13 + 19 + B + 2
;; over HTTP/2.
(for-each
 (lambda (face)
   (let ((slen (if (eq? face 'h2) 13 17)))
     (for-each (lambda (n) (both 'edge (string-append "n" (n->s n)) face (string-append "/head?n=" (n->s n) "&line=16") '()))
               '(1000 1001))
     (for-each (lambda (t) (both 'edge (string-append "total" (n->s t)) face
                                 (string-append "/head?total=" (n->s t) "&line=256&slen=" (n->s slen)) '()))
               '(102400 102401))
     (for-each (lambda (b) (both 'edge (string-append "line" (n->s b)) face (string-append "/head?n=1&big=" (n->s b)) '()))
               (if (eq? face 'h2) '(102366 102367) '(102362 102363)))))
 '(h1 h2))

;; toward: what counts toward the cap across the transfer, each kind at
;; 1,000 lines in all and at 1,001, each head alone under the cap; and its
;; bytes, each head alone under 102,400 and the two past it.
(for-each
 (lambda (face)
   (both 'toward "pre103-500+500" face "/head?pre=103:500:16&n=500" '())
   (both 'toward "pre103-500+501" face "/head?pre=103:500:16&n=501" '())
   (both 'toward "pre100-500+501" face "/head?pre=100:500:16&n=501" '())
   (both 'toward "pre103-250x256+250x256" face "/head?pre=103:250:256&n=250&line=256" '())
   (both 'toward "tr-2+998" face "/head?n=2&tn=998&tl=16" '())
   (both 'toward "tr-2+999" face "/head?n=2&tn=999&tl=16" '())
   (both 'toward "tr-2+400x256" face "/head?n=2&tn=400&tl=256" '())
   (let ((digest '(keys credentials (digest "user" "secret"))))
     (cell 'toward "auth-499+500" face "/auth?a.n=499&b.n=500" 'buffered (list digest))
     (cell 'toward "auth-499+501" face "/auth?a.n=499&b.n=501" 'buffered (list digest))
     (cell 'toward "auth-250x256+250x256" face "/auth?a.n=250&a.line=256&b.n=250&b.line=256" 'buffered (list digest))))
 '(h1 h2))
(let ((post '(keys method post body #vu8(48 49 50 51 52 53 54 55 56 57) headers (("Expect" . "100-continue")))))
  (cell 'toward "expect-500+500" 'h1 "/expect?a.n=500&b.n=500" 'buffered (list post))
  (cell 'toward "expect-500+501" 'h1 "/expect?a.n=500&b.n=501" 'buffered (list post))
  (cell 'toward "expect-250x256+250x256" 'h1 "/expect?a.n=250&a.line=256&b.n=250&b.line=256" 'buffered (list post)))
(for-each
 (lambda (face)
   (both 'toward "connect-500+500" face "/head?n=500" '((arm "n=500")))
   (both 'toward "connect-500+501" face "/head?n=501" '((arm "n=500")))
   (both 'toward "connect-250x256+250x256" face "/head?n=250&line=256" '((arm "n=250&line=256"))))
 '(h1tls h2))

;; early: libcurl's refusals that come before a line reaches the callable
;; (the plan's section 3.8), with the controls beside them.
(both 'early "line102399" 'h1 "/head?n=1&big=102399" '())
(both 'early "line102400" 'h1 "/head?n=1&big=102400" '())
(both 'early "line102400" 'h1tls "/head?n=1&big=102400" '())
(both 'early "line102400" 'h2 "/head?n=1&big=102400" '())
(both 'early "line102400-X" 'h2 "/head?n=1&big=102400&bigch=X" '())
(both 'early "total131071" 'h2 "/head?total=131071&line=256&slen=13" '())
(both 'early "total131072" 'h2 "/head?total=131072&line=256&slen=13" '())
(both 'early "total307199" 'h2 "/head?total=307199&line=256&slen=13" '())
(both 'early "tr-2+1600x256" 'h2 "/head?n=2&tn=1600&tl=256" '())
(both 'early "tr-line4000" 'h1 "/head?n=2&tn=1&tl=4000" '())
(both 'early "tr-line5000" 'h1 "/head?n=2&tn=1&tl=5000" '())
(both 'early "tr-line5000" 'h2 "/head?n=2&tn=1&tl=5000" '())
(both 'early "tr-2+6000" 'h1 "/head?n=2&tn=6000&tl=16" '())
(both 'early "tr-2+6000" 'h2 "/head?n=2&tn=6000&tl=16" '())
(both 'early "tr-2+3" 'h1 "/head?n=2&tn=3&tl=16" '())
(both 'early "tr-2+3" 'h2 "/head?n=2&tn=3&tl=16" '())

;; suppress: SUPPRESS_CONNECT_HEADERS, the hatch's, through the proxy, set
;; and not.
(for-each
 (lambda (face)
   (for-each
    (lambda (opts)
      (both 'suppress "connect-600+600" face "/head?n=600" (list '(arm "n=600") (cons 'options opts)))
      (both 'suppress "connect-4500+600" face "/head?n=600" (list '(arm "n=4500") (cons 'options opts)))
      (both 'suppress "connect-900x256+350x256" face "/head?n=350&line=256" (list '(arm "n=900&line=256") (cons 'options opts))))
    '(() (("SUPPRESS_CONNECT_HEADERS" . 1)))))
 '(h1tls h2))

;; suppress, past the cap: a CONNECT answer of 15,000 lines, set and not,
;; and a final head of 2, buffered: what each lane answers, and its time.
(for-each
 (lambda (face)
   (for-each
    (lambda (opts)
      (cell 'suppress "connect-15000+2" face "/head?n=2" 'buffered (list '(arm "n=15000") (cons 'options opts)))
      (cell 'suppress "connect-2+2" face "/head?n=2" 'buffered (list '(arm "n=2") (cons 'options opts))))
    '(() (("SUPPRESS_CONNECT_HEADERS" . 1))))
   ;; and one of 60,000 lines, 960,000 bytes, hidden: what bounds it, by lane.
   (cell 'suppress "connect-60000+2" face "/head?n=2" 'buffered
         (list '(arm "n=60000") '(options ("SUPPRESS_CONNECT_HEADERS" . 1)))))
 '(h1tls h2))

;; options: another option the hatch takes that changes what the callable
;; sees: HTTP_TRANSFER_DECODING 0 hands a chunked body raw, trailers in.
(for-each
 (lambda (opts)
   (both 'options "tr-2+999" 'h1 "/head?n=2&tn=999&tl=16" (list (cons 'options opts)))
   (both 'options "tr-2+400x256" 'h1 "/head?n=2&tn=400&tl=256" (list (cons 'options opts))))
 '(() (("HTTP_TRANSFER_DECODING" . 0))))

;; hatch: whether the hatch takes each option that can change what the
;; header callable sees, by its answer: accepted, or the refusal's reason.
(when (or (not groups) (memq 'hatch groups))
  (let ((base (make-curl-request "http://127.0.0.1:1/" 'proxy #f)))
    (for-each
     (lambda (o)
       (printf "hatch ~a ~s ~a~%" (car o) (cdr o)
               (guard (e ((curl-request-error? e) (list 'refused (curl-request-error-reason e)))
                         ((assertion-violation? e) (list 'assertion (condition-message* e))))
                 (curl-request-with-options base (list o))
                 'accepted)))
     '(("SUPPRESS_CONNECT_HEADERS" . 1) ("HTTP_TRANSFER_DECODING" . 0) ("HTTP200ALIASES" . ("ICY 200 OK"))
       ("HTTP09_ALLOWED" . 1) ("PROXYAUTH" . 1) ("FAILONERROR" . 1) ("KEEP_SENDING_ON_ERROR" . 1)
       ("EXPECT_100_TIMEOUT_MS" . 1000) ("HEADER" . 1) ("HEADERFUNCTION" . 0) ("HEADERDATA" . 0)
       ("WRITEHEADER" . 0) ("HTTPPROXYTUNNEL" . 1) ("CONNECT_ONLY" . 1) ("NOBODY" . 1)
       ("FOLLOWLOCATION" . 1) ("HTTPAUTH" . 1) ("HTTP_VERSION" . 2) ("PROXYTYPE" . 1)
       ("UNRESTRICTED_AUTH" . 1) ("POSTREDIR" . 1) ("TIMECONDITION" . 1) ("TIMEVALUE" . 1)
       ("HTTP_CONTENT_DECODING" . 0) ("ACCEPT_ENCODING" . "gzip") ("TRANSFER_ENCODING" . 1)
       ("IGNORE_CONTENT_LENGTH" . 1) ("CONNECT_TO" . ("::127.0.0.1:1")) ("RANGE" . "0-1")
       ("MAXREDIRS" . 1) ("PROXY" . "http://127.0.0.1:1") ("HTTPHEADER" . ("X-A: b"))
       ("PROXYHEADER" . ("X-A: b")) ("HEADEROPT" . 1) ("CUSTOMREQUEST" . "GET") ("REQUEST_TARGET" . "/")
       ("HTTPGET" . 1) ("CRLF" . 1) ("DEBUGFUNCTION" . 0) ("VERBOSE" . 1) ("HTTPPOST" . 0)
       ("POSTFIELDS" . "x") ("POST" . 1) ("UPLOAD" . 1) ("TRAILERFUNCTION" . 0) ("TRAILERDATA" . 0)))))

(curl-engine-stop ctl-engine)
(printf "probe done~%")
(exit 0)
