#!r6rs
;;; M4 slice 4's measurement of RESOLVE through chez-curl's own hatch: does
;;; an entry one request attaches reach a later request on the same engine,
;;; which never named it? libcurl's docs say RESOLVE fills the DNS cache a
;;; multi handle shares; the slice's twin review read it from the source.
;;;
;;;   resolve-chez.sps PORT
;;;
;;; PORT is an http server's on 127.0.0.1. It prints one line per case, each
;;; a GET of http://resolve-probe.invalid:PORT/x:
;;;   (fresh ANSWER)      on an engine of its own, with no option: the control
;;;   (attached ANSWER)   on a second engine, with RESOLVE through the hatch
;;;   (after ANSWER)      then, on that engine, without it
;;;   (removed ANSWER)    then with RESOLVE -resolve-probe.invalid:PORT
;;;   (after-removed ANSWER) then without it again
;;; ANSWER is (status N), or (refused REASON CODE).
(import (chezscheme) (curl) (curl unsupported))

(define port (car (command-line-arguments)))
(define url (string-append "http://resolve-probe.invalid:" port "/x"))
(define entry (string-append "resolve-probe.invalid:" port ":127.0.0.1"))

(define (answer engine options)
  (guard (e ((curl-transfer-error? e)
             (list 'refused (curl-transfer-error-reason e) (curl-transfer-error-code e)))
            (#t (list 'raised (if (message-condition? e) (condition-message e) e))))
    (let* ((r (make-curl-request url 'timeout-ms 10000))
           (r (if (null? options) r (curl-request-with-options r options))))
      (list 'status (curl-response-status (curl-token-await (curl-submit engine r)))))))

(define (show tag value) (write (list tag value)) (newline))

(let ((fresh (make-curl-engine)))
  (show 'fresh (answer fresh '()))
  (curl-engine-stop fresh))
(let ((engine (make-curl-engine)))
  (show 'attached (answer engine (list (list "RESOLVE" entry))))
  (show 'after (answer engine '()))
  (show 'removed (answer engine (list (list "RESOLVE" (string-append "-resolve-probe.invalid:" port)))))
  (show 'after-removed (answer engine '()))
  (curl-engine-stop engine))
