#!r6rs
;;; M7 slice 3's fix round, item 7: a proxy a variable names, its userinfo
;;; decoding to a control byte, through proxy environment. Does the
;;; transfer go direct, as a named proxy's did on 7.85.0 and 8.5.0? Against
;;; the test origin, its http face the proxy: each case runs
;;; tests/proxy-env.sps in a child, one variable set for it alone, every
;;; other proxy variable unset, and prints the child's transfer line and the
;;; proxy's log lines the case made. A transfer that went direct is a 200
;;; with no line on the proxy's log.
;;;
;;;   chez --libdirs src:tests:build/scheme-libs --program build/m7s3b/env-userinfo.sps
(import (rnrs)
        (only (chezscheme) parameterize getenv)
        (curl)
        (curl-testing))

(define pki (make-test-pki))
(define ca (string-append pki "/ca.pem"))

(define (split-lines text)
  (let loop ((start 0) (i 0) (found '()))
    (cond ((= i (string-length text)) (reverse (if (= start i) found (cons (substring text start i) found))))
          ((char=? (string-ref text i) #\newline) (loop (+ i 1) (+ i 1) (cons (substring text start i) found)))
          (else (loop start (+ i 1) found)))))

(define (read-all text)
  (let ((port (open-string-input-port text)))
    (let loop ((found '()))
      (let ((datum (guard (e (#t '(unreadable))) (read port))))
        (if (or (eof-object? datum) (equal? datum '(unreadable))) (reverse found) (loop (cons datum found)))))))

(define child-script
  (string-append
   "t=$(command -v timeout || command -v gtimeout) || { echo 'no timeout' >&2; exit 125; }\n"
   "exec 3>&2 2>/dev/null\n"
   "( exec \"$t\" -s KILL 60 \"$@\" </dev/null 2>&3 3>&- )\n"
   "exit $?\n"))

(define unset '("http_proxy" "HTTP_PROXY" "https_proxy" "HTTPS_PROXY" "all_proxy" "ALL_PROXY" "no_proxy"
                "NO_PROXY" "SSL_CERT_FILE" "SSL_CERT_DIR"))

(define (run o)
  (define (port face) (number->string (cdr (origin-face o face))))
  (define proxy-base (string-append "127.0.0.1:" (port 'http)))
  (define log-engine (make-curl-engine))
  (define (log-lines)
    (let* ((t (curl-submit log-engine (make-curl-request (string-append "http://" proxy-base "/proxy-log?from=0")
                                                         'proxy #f 'timeout-ms 10000)))
           (r (curl-token-await t)))
      (cdr (split-lines (utf8->string (curl-response-body r))))))
  (define (child variable value url)
    (let ((r (capture-command
              (append (list "sh" "-c" child-script "sh" "env")
                      (apply append (map (lambda (name) (list "-u" name)) unset))
                      (list (string-append variable "=" value))
                      (list (getenv "CHEZ") "--libdirs" "src:tests:build/scheme-libs"
                            "--program" "tests/proxy-env.sps" url "environment" "-" "on" ca)))))
      (if (= (car r) 0)
          (let ((data (read-all (cadr r))))
            (or (find (lambda (d) (and (pair? d) (eq? (car d) 'transfer))) data) data))
          (list 'exit (car r) (cadr r) (caddr r)))))
  (define https-url (string-append "https://127.0.0.1:" (port 'https) "/status/200"))
  (define http-url (string-append "http://127.0.0.1:" (port 'http) "/status/200"))
  (display "libcurl ") (display (libcurl-info-version (loaded-libcurl))) (newline)
  (for-each
   (lambda (case)
     (let* ((mark (length (log-lines)))
            (answer (apply child (cdr case)))
            (lines (list-tail (log-lines) mark)))
       (display (car case)) (newline)
       (display "  ") (write (cadr case)) (display "=") (write (caddr case)) (newline)
       (display "  ") (write answer) (newline)
       (for-each (lambda (l) (display "  log: ") (display l) (newline)) lines)))
   (list (list "control: https_proxy, no userinfo" "https_proxy" (string-append "http://" proxy-base) https-url)
         (list "control: https_proxy, userinfo u:p" "https_proxy" (string-append "http://u:p@" proxy-base) https-url)
         (list "https_proxy, the user decoding to 0x01" "https_proxy" (string-append "http://u%01x:p@" proxy-base) https-url)
         (list "https_proxy, the password decoding to 0x01" "https_proxy" (string-append "http://u:p%01x@" proxy-base) https-url)
         (list "https_proxy, the user decoding to 0x1F" "https_proxy" (string-append "http://u%1Fx:p@" proxy-base) https-url)
         (list "https_proxy, the user decoding to 0x00" "https_proxy" (string-append "http://u%00x:p@" proxy-base) https-url)
         (list "https_proxy, the user decoding to 0x7F" "https_proxy" (string-append "http://u%7Fx:p@" proxy-base) https-url)
         (list "https_proxy, a raw 0x01 in the user" "https_proxy" (string-append "http://u\x1;x:p@" proxy-base) https-url)
         (list "control: http_proxy, userinfo u:p" "http_proxy" (string-append "http://u:p@" proxy-base) http-url)
         (list "http_proxy, the user decoding to 0x01" "http_proxy" (string-append "http://u%01x:p@" proxy-base) http-url)
         (list "all_proxy, the password decoding to 0x01" "all_proxy" (string-append "http://u:p%01x@" proxy-base) https-url)))
  (curl-engine-stop log-engine)
  'done)

(display (parameterize ((origin-pki pki)) (call-with-origin run)))
(newline)
