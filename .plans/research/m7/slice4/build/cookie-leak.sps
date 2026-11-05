#!r6rs
;; build/m7s4b/cookie-leak.sps: does any exit of the cookie jar print a
;; cookie's value? Each exit below is run, and what write, display and
;; display-condition print of what it raised, or of what it answers, is
;; searched for the two secrets: one loaded, one a server set. One line per
;; exit, then the count. Run from the repository's root:
;;   $CHEZ --libdirs src:tests:build/scheme-libs --program build/m7s4b/cookie-leak.sps
(import (rnrs) (rnrs mutable-pairs)
        (only (chezscheme) display-condition make-list)
        (curl) (http-client) (curl-testing) (only (curl private counters) native-counts))

(define loaded "L0adedS3cr3t")
(define served "S3rvedS3cr3t")

(define (contains? text part)
  (let ((n (string-length text)) (m (string-length part)))
    (let loop ((i 0))
      (and (<= (+ i m) n)
           (or (string=? (substring text i (+ i m)) part) (loop (+ i 1)))))))

(define (printed x)
  (call-with-string-output-port
   (lambda (p)
     (write x p) (newline p) (display x p) (newline p)
     (when (condition? x) (display-condition x p)))))

(define exits 0)
(define leaks 0)

;; report : String Any -> Void
(define (report name x)
  (let* ((text (printed x))
         (leak (or (contains? text loaded) (contains? text served))))
    (set! exits (+ exits 1))
    (when leak (set! leaks (+ leaks 1)))
    (display name) (display ": secret printed: ") (display (if leak "YES" "no")) (newline)
    (display "  ") (write (if (> (string-length text) 800) (substring text 0 800) text)) (newline)))

;; outcome : (-> Any) -> Any
;; THUNK's raise, or its answer.
(define (outcome thunk) (guard (e (#t e)) (thunk)))

(define (tabbed . fields)
  (let loop ((rest (cdr fields)) (text (car fields)))
    (if (null? rest) text (loop (cdr rest) (string-append text "\t" (car rest))))))

(define (line-with value) (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "n" value))

;; One bad line per rule, each holding the loaded secret.
(define bad-lines
  (list (cons "not-latin-1" (line-with (string-append loaded (string (integer->char #x3BB)))))
        (cons "control-byte" (line-with (string-append loaded (string (integer->char 1)))))
        (cons "set-cookie" (string-append "Set-Cookie: n=" loaded))
        (cons "fields" (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "n" loaded "x"))
        (cons "domain" (tabbed "#a.localhost" "FALSE" "/" "FALSE" "0" "n" loaded))
        (cons "tail-match" (tabbed "a.localhost" "true" "/" "FALSE" "0" "n" loaded))
        (cons "leading-dot" (tabbed ".a.localhost" "FALSE" "/" "FALSE" "0" "n" loaded))
        (cons "path" (tabbed "a.localhost" "FALSE" "rel" "FALSE" "0" "n" loaded))
        (cons "secure" (tabbed "a.localhost" "FALSE" "/" "no" "0" "n" loaded))
        (cons "expiry" (tabbed "a.localhost" "FALSE" "/" "FALSE" "-1" "n" loaded))
        (cons "name" (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "" loaded))
        (cons "size" (line-with (string-append loaded (make-string 4096 #\p))))
        (cons "separator, a ; in the value" (line-with (string-append loaded "; admin=1")))
        (cons "separator, a ; in the name" (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" (string-append "n;" loaded) "v"))
        (cons "separator, an = in the name" (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" (string-append "n=" loaded) "v"))
        (cons "prefix, __Secure- not secure" (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "__Secure-n" loaded))
        (cons "prefix, __host- with a path" (tabbed "a.localhost" "FALSE" "/p" "TRUE" "0" "__host-n" loaded))))

(define (run o)
  (let* ((port (number->string (cdr (origin-face o 'http))))
         (url (lambda (host query) (string-append "http://" host ":" port "/cookies?key=leak" query)))
         (e (make-curl-engine))
         (other (make-curl-engine))
         (jar (make-curl-cookie-jar e))
         (good (line-with loaded)))
    (curl-cookie-jar-load! jar (list good))
    ;; the load's refusals, each rule, the bad line at index 1
    (for-each (lambda (bad)
                (report (string-append "load refused, " (car bad))
                        (outcome (lambda () (curl-cookie-jar-load! jar (list good (cdr bad)))))))
              bad-lines)
    ;; the load's wrong kinds
    (report "load of a vector of the line" (outcome (lambda () (curl-cookie-jar-load! jar (vector good)))))
    (report "load of an improper list" (outcome (lambda () (curl-cookie-jar-load! jar (cons good good)))))
    (report "load of a list holding a symbol" (outcome (lambda () (curl-cookie-jar-load! jar (list good 'x)))))
    (report "load of the line alone" (outcome (lambda () (curl-cookie-jar-load! jar good))))
    ;; the line where a jar belongs
    (report "make-curl-cookie-jar of the line" (outcome (lambda () (make-curl-cookie-jar good))))
    (report "curl-cookie-jar-cookies of the line" (outcome (lambda () (curl-cookie-jar-cookies good))))
    (report "curl-cookie-jar-load! of the line, then lines" (outcome (lambda () (curl-cookie-jar-load! good (list good)))))
    (report "curl-cookie-jar-close! of the line" (outcome (lambda () (curl-cookie-jar-close! good))))
    (report "curl-cookie-jar? of the line" (outcome (lambda () (curl-cookie-jar? good))))
    (report "cookie-jar key of the line" (outcome (lambda () (make-curl-request (url "a.localhost" "") 'cookie-jar good))))
    (report "curl-request-cookie-jar of the line" (outcome (lambda () (curl-request-cookie-jar good))))
    (report "curl-response-status of the jar" (outcome (lambda () (curl-response-status jar))))
    (report "curl-token-await of the jar" (outcome (lambda () (curl-token-await jar))))
    ;; cookie-beside-jar, as made and at submit
    (report "Cookie header beside the jar, as made"
            (outcome (lambda () (make-curl-request (url "a.localhost" "") 'cookie-jar jar
                                                   'headers (list (cons "Cookie" (string-append "c=" loaded)))))))
    (report "Host header beside the jar, as made"
            (outcome (lambda () (make-curl-request (url "a.localhost" "") 'cookie-jar jar
                                                   'headers (list (cons "Host" loaded))))))
    (let* ((headers (list (cons "X-A" (string-append "c=" loaded))))
           (request (make-curl-request (url "a.localhost" "") 'cookie-jar jar 'headers headers 'proxy #f)))
      (set-car! (car headers) "Cookie")
      (report "Cookie header renamed after made, at submit" (outcome (lambda () (curl-submit e request))))
      (report "Cookie header renamed after made, at curl-request-check" (outcome (lambda () (curl-request-check request)))))
    ;; another engine's jar
    (report "a submit of another engine's jar"
            (outcome (lambda () (curl-submit other (make-curl-request (url "a.localhost" "") 'cookie-jar jar 'proxy #f)))))
    ;; a transfer's failures holding the jar
    (let ((t (curl-submit e (make-curl-request "http://127.0.0.1:9/" 'cookie-jar jar 'proxy #f 'timeout-ms 5000))))
      (curl-token-wait t 10000)
      (report "a refused connect holding the jar, its token" t)
      (report "a refused connect holding the jar, its outcome" (curl-token-outcome t)))
    (let ((t (curl-submit e (make-curl-request (string-append "http://a.localhost:" port "/pattern/10?delay=3000")
                                               'cookie-jar jar 'proxy #f 'timeout-ms 300))))
      (curl-token-wait t 10000)
      (report "a timeout holding the jar, its outcome" (curl-token-outcome t)))
    ;; the jar, the request, the token and the response holding the server's Set-Cookie
    (let* ((request (make-curl-request (url "a.localhost" (string-append "&set=sv%3D" served)) 'cookie-jar jar 'proxy #f))
           (token (curl-submit e request))
           (response (curl-token-await token)))
      (report "the jar" jar)
      (report "the request" request)
      (report "the token" token)
      (report "the response" response)
      (report "the response's headers, which hold the Set-Cookie: a caller's own read"
              (if (exists (lambda (h) (contains? (cdr h) served)) (curl-response-headers response))
                  'holds-it-as-data 'missing)))
    (let* ((streamed (curl-submit e (make-curl-request (url "a.localhost" (string-append "&set=sv%3D" served))
                                                       'cookie-jar jar 'proxy #f 'stream-buffer 65536)))
           (head (and (curl-token-head-wait streamed 10000) (curl-token-head streamed))))
      (report "a streamed head" head)
      (curl-token-cancel streamed)
      (curl-token-wait streamed 10000))
    ;; closed
    (let ((closed (make-curl-cookie-jar e)))
      (curl-cookie-jar-load! closed (list good))
      (curl-cookie-jar-close! closed)
      (report "a submit of a closed jar" (outcome (lambda () (curl-submit e (make-curl-request (url "a.localhost" "") 'cookie-jar closed 'proxy #f)))))
      (report "a read-out of a closed jar" (outcome (lambda () (curl-cookie-jar-cookies closed))))
      (report "a load into a closed jar" (outcome (lambda () (curl-cookie-jar-load! closed (list good)))))
      (report "a closed jar" closed))
    ;; the high level
    (let ((s (make-http-session 'cookies #t 'proxy #f 'timeout-ms 10000 'redirects 0)))
      (http-session-load-cookies! s (list good))
      (http-get s (url "a.localhost" (string-append "&set=sv%3D" served)))
      (report "the session" s)
      (report "the session's response" (http-get s (url "a.localhost" (string-append "&set=sv%3D" served))))
      (report "the session's redirect error" (outcome (lambda () (http-get s (url "a.localhost" (string-append "&set=sv%3D" served "&status=302&to=%2Fx"))))))
      (report "the session's load refused" (outcome (lambda () (http-session-load-cookies! s (list good (cdr (car bad-lines)))))))
      (report "the session's call with a Cookie header" (outcome (lambda () (http-get s (url "a.localhost" "") 'headers (list (cons "Cookie" (string-append "c=" loaded)))))))
      (report "http-session-cookies of the line" (outcome (lambda () (http-session-cookies good))))
      (report "http-session-load-cookies! of the line" (outcome (lambda () (http-session-load-cookies! good (list good)))))
      (http-session-close s)
      (report "a closed session's read-out" (outcome (lambda () (http-session-cookies s)))))
    (report "a session with a Cookie header and cookies"
            (outcome (lambda () (make-http-session 'cookies #t 'headers (list (cons "Cookie" (string-append "c=" loaded)))))))
    (display "control: the jar's read-out holds the loaded secret: ")
    (display (if (exists (lambda (l) (contains? l loaded)) (curl-cookie-jar-cookies jar)) "yes" "NO"))
    (newline)
    (display "control: the search finds the secret in the line itself: ")
    (display (if (contains? (printed good) loaded) "yes" "NO"))
    (newline)
    (curl-engine-stop other)
    (curl-engine-stop e)
    (report "a stopped engine's jar, read out" (outcome (lambda () (curl-cookie-jar-cookies jar))))
    (report "a stopped engine's jar" jar)))

(call-with-origin (lambda (o) (run o)))
(display "cookie-leak: ") (display exits) (display " exits, ") (display leaks) (display " printed a secret") (newline)
(display "counts: ") (write (native-counts)) (newline)
