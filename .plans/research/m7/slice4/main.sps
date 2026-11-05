#!chezscheme
;;; M7 slice 4's measurements on main's src/ (2026-11-03): item 10's first
;;; half, whether the hatch takes each twin of the jar's options today, and
;;; that main's request takes no cookie-jar key.
;;;
;;;   scheme --libdirs src --program main.sps twins-main KEY=VALUE ...
;;;
;;; Each line: "h OPTION => attached" or "h OPTION => refused REASON".
(import (chezscheme) (curl) (curl unsupported))

(define (say fmt . xs) (apply printf fmt xs) (newline) (flush-output-port (current-output-port)))

(define (attach options)
  (guard (e (#t (if (curl-request-error? e)
                    (format "refused field=~a reason=~a" (curl-request-error-field e) (curl-request-error-reason e))
                    (format "condition ~s" (call-with-string-output-port (lambda (p) (display-condition e p)))))))
    (curl-request-with-options (make-curl-request "http://127.0.0.1:1/") options)
    "attached"))

(let ((info (loaded-libcurl)))
  (say "libcurl version=~a ssl=~s path=~a part=twins-main" (libcurl-info-version info)
       (libcurl-info-ssl-version info) (libcurl-info-path info)))
(for-each
 (lambda (row)
   (say "h ~a => ~a" (car row) (attach (cdr row))))
 (list (cons "COOKIE" (list (cons "COOKIE" "h=hatch")))
       (cons "COOKIELIST-ALL" (list (cons "COOKIELIST" "ALL")))
       (cons "COOKIELIST-SESS" (list (cons "COOKIELIST" "SESS")))
       (cons "COOKIELIST-line" (list (cons "COOKIELIST" "Set-Cookie: v=1; Domain=a.localhost")))
       (cons "COOKIESESSION" (list (cons "COOKIESESSION" 1)))
       (cons "COOKIEFILE" (list (cons "COOKIEFILE" "")))
       (cons "COOKIEJAR" (list (cons "COOKIEJAR" "/dev/null")))
       (cons "SHARE" (list (cons "SHARE" 0)))
       (cons "HSTS_CTRL" (list (cons "HSTS_CTRL" 1)))
       (cons "HSTS" (list (cons "HSTS" "/dev/null")))))
(say "k cookie-jar key => ~a"
     (guard (e (#t (if (curl-request-error? e)
                       (format "refused field=~a reason=~a" (curl-request-error-field e) (curl-request-error-reason e))
                       "condition")))
       (make-curl-request "http://127.0.0.1:1/" 'cookie-jar #f)
       "made"))
(say "done twins-main")
