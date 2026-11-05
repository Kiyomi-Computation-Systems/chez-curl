#!r6rs
;;; M7 slice 4's review: lines the load rule takes, and what libcurl does
;;; with them, through the engine and the test origin, on one lane. Each
;;; result is one line, "probe: CASE RESULT", RESULT written by write.
;;;
;;;   prefix-*   one line loaded alone into a fresh jar, each one the rule
;;;              takes, then the jar read out, sorted: the __Secure- and
;;;              __Host- prefixes, in their case and in others, where the
;;;              cookie is not secure, or a __Host- one has a path but / or
;;;              a domain. libcurl drops a prefixed cookie that breaks its
;;;              prefix's rule; 7.85.0 to 8.20.0 match a loaded line's prefix
;;;              in any case, 8.23.0 in its own case alone (read in source).
;;;   pair-*     a loaded value holding "; " and a loaded name holding =,
;;;              then a request to a.localhost: the Cookie header the origin
;;;              logged, whole.
;;;   path-tab   a server's Set-Cookie with a tab in its Path, then the
;;;              read-out, each line with its field count.
;;;   head-*     a server's 4,003-byte cookie, then a short URL with a long
;;;              user agent, or long Basic credentials, or neither, at a
;;;              bound of 3 s: the transfer's answer, and the origin's log.
;;;
;;; Run from a tree's root with src, tests and the SRFI libraries on the
;;; library path (README.md here).
(import (rnrs)
        (only (chezscheme) list-sort)
        (curl)
        (curl-testing)
        (only (curl private counters) native-counts))

(define (tabbed . fields)
  (fold-left (lambda (line field) (string-append line "\t" field)) (car fields) (cdr fields)))

(define (say tag x)
  (display "probe: ") (display tag) (display " ") (write x) (newline)
  (flush-output-port (current-output-port)))

(define (refusal e)
  (cond ((curl-request-error? e) (list 'request-refused (curl-request-error-reason e)))
        ((curl-transfer-error? e) (list 'transfer-failed (curl-transfer-error-reason e) (curl-transfer-error-code e)))
        ((curl-engine-error? e) (list 'engine-error (curl-engine-error-reason e)))
        (else (list 'other (condition? e)))))

(define (fields-of line)
  (let loop ((i 0) (n 1))
    (cond ((= i (string-length line)) n)
          ((char=? (string-ref line i) #\tab) (loop (+ i 1) (+ n 1)))
          (else (loop (+ i 1) n)))))

(define version (libcurl-info-version (loaded-libcurl)))
(say 'libcurl version)

(define prefix-lines
  (list (list 'prefix-plain (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "plain" "1"))
        (list 'prefix-Secure-not-secure (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "__Secure-a" "1"))
        (list 'prefix-secure-lower-not-secure (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "__secure-b" "1"))
        (list 'prefix-SECURE-upper-not-secure (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "__SECURE-c" "1"))
        (list 'prefix-Secure-secure (tabbed "a.localhost" "FALSE" "/" "TRUE" "0" "__Secure-d" "1"))
        (list 'prefix-Host-path-p (tabbed "a.localhost" "FALSE" "/p" "TRUE" "0" "__Host-e" "1"))
        (list 'prefix-host-lower-path-p (tabbed "a.localhost" "FALSE" "/p" "TRUE" "0" "__host-f" "1"))
        (list 'prefix-Host-ok (tabbed "a.localhost" "FALSE" "/" "TRUE" "0" "__Host-g" "1"))
        (list 'prefix-HOST-upper-domain (tabbed ".a.localhost" "TRUE" "/" "TRUE" "0" "__HOST-h" "1"))))

(call-with-origin
 (lambda (o)
   (let* ((port (number->string (cdr (origin-face o 'http))))
          (e (make-curl-engine))
          (get (lambda (jar url . keys)
                 (guard (x (#t (refusal x)))
                   (let ((r (curl-token-await
                             (curl-submit e (apply make-curl-request url 'proxy #f 'cookie-jar jar keys)))))
                     (list (curl-response-status r) (utf8->string (curl-response-body r)))))))
          (log-of (lambda (key)
                    (let ((r (curl-token-await
                              (curl-submit e (make-curl-request
                                              (string-append "http://127.0.0.1:" port "/cookie-log?key=" key)
                                              'proxy #f)))))
                      (utf8->string (curl-response-body r))))))
     (dynamic-wind
       (lambda () #f)
       (lambda ()
         ;; Each prefix line alone, in a fresh jar.
         (for-each
          (lambda (c)
            (let ((jar (make-curl-cookie-jar e)))
              (say (car c)
                   (guard (x (#t (refusal x)))
                     (curl-cookie-jar-load! jar (list (cadr c)))
                     (list-sort string<? (curl-cookie-jar-cookies jar))))
              (curl-cookie-jar-close! jar)))
          prefix-lines)
         ;; A cookie pair inside a loaded value, and an = inside a name.
         (let ((jar (make-curl-cookie-jar e)))
           (say 'pair-load
                (guard (x (#t (refusal x)))
                  (curl-cookie-jar-load! jar (list (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "n" "x; admin=1")
                                                   (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "a=b" "c")))
                  'loaded))
           (say 'pair-sent (get jar (string-append "http://a.localhost:" port "/cookies?key=pair")))
           (curl-cookie-jar-close! jar))
         ;; A server's Set-Cookie with a tab in its Path.
         (let ((jar (make-curl-cookie-jar e)))
           (say 'path-tab-set (get jar (string-append "http://a.localhost:" port
                                                      "/cookies?key=pt&set=k%3Dv%3B%20Path%3D%2Fa%09b")))
           (say 'path-tab-readout (map (lambda (l) (list (fields-of l) l))
                                       (list-sort string<? (curl-cookie-jar-cookies jar))))
           (curl-cookie-jar-close! jar))
         ;; 7.85.0's open head: a server's 4,003-byte cookie, then a long user
         ;; agent, or long Basic credentials, beside a short URL.
         (let ((big (string-append "big%3D" (make-string 3999 #\v))))
           (for-each
            (lambda (c)
              (let ((jar (make-curl-cookie-jar e)) (key (car c)))
                (get jar (string-append "http://a.localhost:" port "/cookies?key=" key "&set=" big))
                (say (string->symbol (string-append "head-" key))
                     (list (let ((answer (apply get jar (string-append "http://a.localhost:" port "/cookies?key=" key)
                                                'timeout-ms 3000 (cdr c))))
                             (if (and (pair? answer) (number? (car answer))) (car answer) answer))
                           (map (lambda (line) (if (> (string-length line) 60) (substring line 0 60) line))
                                (let ((text (log-of key)))
                                  (let loop ((i 0) (start 0) (found '()))
                                    (cond ((= i (string-length text)) (reverse found))
                                          ((char=? (string-ref text i) #\newline)
                                           (loop (+ i 1) (+ i 1) (cons (substring text start i) found)))
                                          (else (loop (+ i 1) start found))))))))
                (curl-cookie-jar-close! jar)))
            (list (list "control")
                  (list "agent" 'user-agent (make-string 4300 #\u))
                  (list "basic" 'credentials (list 'basic "u" (make-string 3300 #\p)))))))
       (lambda () (curl-engine-stop e))))))
(say 'counts (native-counts))
