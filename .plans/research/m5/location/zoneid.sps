#!r6rs
;;; M5 slice 2's review (2026-10-28): libcurl gives an IPv6 host without its
;;; zone ID, so an origin rule that compares hosts alone sees
;;; [fe80::1%25eth0] and [fe80::1%25eth1] as one host. What does each
;;; libcurl give as the host and as CURLUPART_ZONEID, 10, by curl_url_get
;;; with no flags?
;;;
;;;   scheme --libdirs src --program zoneid.sps
;;;
;;; Prints, per URL: url=, host=, zoneid= (absent for CURLUE_NO_ZONEID, or
;;; ucN), each as written, or the refusal; then resolutions against a base
;;; with a zone ID.
(import (rnrs)
        (curl)
        (curl private url)
        (curl private native)
        (curl private constants))

(define (written x) (call-with-string-output-port (lambda (p) (write x p))))

;; part : String Natural -> Any
(define (part url n)
  (guard (e ((curl-url-error? e) (list 'refused (curl-url-error-code e) (curl-url-error-reason e))))
    (call-with-parsed-url url
      (lambda (handle)
        (let-values (((code address) (curl-url-get handle n 0)))
          (cond ((eqv? code curlue-ok)
                 (let ((b (c-string->bytevector address)))
                   (curl-free address)
                   (utf8->string b)))
                ((eqv? code 18) 'absent)
                (else (list 'uc code))))))))

(put-string (current-output-port)
            (string-append "libcurl " (libcurl-info-version (loaded-libcurl)) "\n"))
(for-each
 (lambda (url)
   (put-string (current-output-port)
               (string-append (written url) " url=" (written (part url 0)) " host=" (written (part url 5))
                              " zoneid=" (written (part url 10)) "\n")))
 '("http://[fe80::1%25eth0]/" "http://[fe80::1%25eth1]/" "http://[fe80::1]/"
   "http://[FE80::1%25ETH0]/" "http://[fe80::1%25eth0]:8080/p" "http://[fe80::1%eth0]/"
   "http://[fe80::1%25]/" "http://[fe80::1%2525x]/" "http://[::1%25lo]/" "http://h.example/"
   "http://127.0.0.1/" "http://[fe80::1%25en%30]/"))
(for-each
 (lambda (ref)
   (put-string (current-output-port)
               (string-append "resolve " (written ref) " => "
                              (written (guard (e ((curl-url-error? e) (list 'refused (curl-url-error-code e))))
                                         (url-resolve "http://[fe80::1%25eth0]/a/b" ref)))
                              "\n")))
 '("/c" "//[fe80::1%25eth1]/c" "//[fe80::1]/c" "http://[fe80::1%25eth0]/c"))
