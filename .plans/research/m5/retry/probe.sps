#!r6rs
;;; M5 slice 3's retry probe, chez-curl's half (2026-10-28; the M5 plan,
;;; section 6.1): what a retry policy reads of each failure, through an
;;; engine of its own per transfer, so no pool holds a dead connection.
;;;
;;;   scheme --libdirs src --program probe.sps RAW TLS H2 STALL REFUSED CA
;;;
;;; The ports server.mjs announced, and the run CA. Per transfer, one line:
;;;
;;;   FACE SCENARIO METHOD ok STATUS VERSION
;;;   FACE SCENARIO METHOD fail CLASS CODE REASON size=SIZE
;;;
;;; CLASS is the condition's class, by (curl)'s predicates: connect,
;;; send-receive, timeout, tls, protocol, too-large, or none; SIZE is
;;; curl-transfer-error-request-size, #f where the libcurl's is unknown.
;;; A post carries a 7-byte body. Every transfer is bounded by 3000 ms, a
;;; stall-before-head by 1500, and the handshake stall's connect by 1000.
(import (rnrs)
        (curl))

(define args (cdr (command-line)))
(define (arg i) (list-ref args i))
(define ca (arg 5))

(define (class-of e)
  (cond ((curl-connect-error? e) 'connect)
        ((curl-send-receive-error? e) 'send-receive)
        ((curl-timeout? e) 'timeout)
        ((curl-tls-error? e) 'tls)
        ((curl-protocol-error? e) 'protocol)
        ((curl-too-large? e) 'too-large)
        (else 'none)))

(define (written x) (call-with-string-output-port (lambda (p) (write x p))))

(define (probe face scenario method url . keys)
  (let ((engine (make-curl-engine))
        (out (current-output-port)))
    (put-string out (string-append face " " scenario " " (symbol->string method) " "))
    (guard (e ((curl-transfer-error? e)
               (put-string out (string-append "fail " (symbol->string (class-of e)) " "
                                              (written (curl-transfer-error-code e)) " "
                                              (written (curl-transfer-error-reason e)) " size="
                                              (written (curl-transfer-error-request-size e)))))
              (#t (put-string out (string-append "raised " (if (message-condition? e)
                                                                (condition-message e)
                                                                "?")))))
      (let* ((request (apply make-curl-request url 'method method 'proxy #f 'ca-file ca
                             (append (if (eq? method 'post) (list 'body (string->utf8 "hello=1")) '())
                                     keys
                                     (if (memq 'timeout-ms keys) '() (list 'timeout-ms 3000)))))
             (response (curl-token-await (curl-submit engine request))))
        (put-string out (string-append "ok " (number->string (curl-response-status response)) " "
                                       (written (curl-response-http-version response))))))
    (newline out)
    (curl-engine-stop engine)))

(put-string (current-output-port)
            (string-append "libcurl " (libcurl-info-version (loaded-libcurl)) "\n"))

(define faces
  (list (list "http" (string-append "http://127.0.0.1:" (arg 0)))
        (list "tls" (string-append "https://127.0.0.1:" (arg 1)))
        (list "h2" (string-append "https://127.0.0.1:" (arg 2)))))

(for-each
 (lambda (face)
   (for-each
    (lambda (scenario)
      (for-each
       (lambda (method)
         (let ((url (string-append (cadr face) "/" scenario)))
           (if (string=? scenario "stall-before-head")
               (probe (car face) scenario method url 'timeout-ms 1500)
               (probe (car face) scenario method url))))
       '(get post)))
    (append '("ok" "close-before-response" "reset-before-response" "reset-after-head"
              "stall-before-head")
            (if (string=? (car face) "h2") '("rst-stream" "goaway") '()))))
 faces)

(for-each
 (lambda (method)
   (probe "http" "refused" method (string-append "http://127.0.0.1:" (arg 4) "/x"))
   (probe "tls" "refused" method (string-append "https://127.0.0.1:" (arg 4) "/x"))
   (probe "tls" "handshake-stall" method (string-append "https://127.0.0.1:" (arg 3) "/x")
          'connect-timeout-ms 1000))
 '(get post))

(put-string (current-output-port) "-- done\n")
