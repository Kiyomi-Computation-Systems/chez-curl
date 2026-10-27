#!r6rs
;;; M4 slice 3's measurement of a CA file through chez-curl itself, on the
;;; Mac: whether Apple's libcurl, as chez-curl loads and initialises it,
;;; trusts a server the keychain trusts when the request's CA file names
;;; another CA (ADR-0018, decision 1; ADR-0024, amended).
;;;
;;;   ca-chez.sps URL CA-FILE
;;;
;;; CA-FILE is a path, or - for none. It submits one GET of URL, verification
;;; on, to an engine of its own, and prints two data: (ssl STRING), the TLS
;;; libraries as the loaded libcurl named them at the load, before
;;; curl_global_init; and the answer, (response STATUS) or (refused REASON
;;; CODE CLASS) or (raised TEXT).
(import (chezscheme) (curl))

(define args (command-line-arguments))
(define url (car args))
(define ca-file (if (string=? (cadr args) "-") #f (cadr args)))

(write (list 'ssl (libcurl-info-ssl-version (loaded-libcurl))))
(newline)
(define engine (make-curl-engine))
(write
 (guard (e ((curl-transfer-error? e)
            (list 'refused (curl-transfer-error-reason e) (curl-transfer-error-code e)
                  (cond ((curl-tls-error? e) 'tls) ((curl-connect-error? e) 'connect) (else 'other))))
           (#t (list 'raised (call-with-string-output-port (lambda (p) (display-condition e p))))))
   (let ((r (curl-token-await
             (curl-submit engine (make-curl-request url 'timeout-ms 20000 'ca-file ca-file)))))
     (list 'response (curl-response-status r)))))
(newline)
(curl-engine-stop engine)
