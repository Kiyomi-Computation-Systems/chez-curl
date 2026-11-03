#!chezscheme
;;; M7 slice 2's MAXREDIRS addition (2026-11-02), through chez-curl's engine,
;;; on the prototype (make-prototype.sh): a program of its own, so auth.sps
;;; and the hash its kept logs record stay as they are. Its helpers are
;;; auth.sps's, copied.
;;;
;;;   scheme --libdirs build/m7s2/src --program maxredirs.sps maxredirs KEY=VALUE ...
;;;
;;; run.sh passes the KEYs, as for auth.sps (PROGRAM=maxredirs.sps). Each
;;; case runs on an engine of its own, timeout-ms 5,000, every wait bounded
;;; at 15,000 ms (times slow). Cases, each with MAXREDIRS unset (libcurl's
;;; default: -1 on 7.85.0, 30 from 8.7.1) and at 30 by the hatch:
;;;   expect417   rounds1's case: a post of 64 KiB with a caller's
;;;               Expect: 100-continue, the stand-in answering 417 to every
;;;               request carrying it, under Basic, Bearer and Digest;
;;;   stale       Digest against a route answering every valid response 401
;;;               stale=true, a new nonce each time (stale=1000000);
;;;   round       Digest against a route that challenges once.
;;; Each transfer prints a "t" line, item mr, with ms from the submit to the
;;; end, then the stand-in's log for its tag ("s TAG ..."); tags maxredirsN.
(import (chezscheme)
        (curl)
        (curl unsupported)
        (only (curl private counters) native-counts))

(define args (command-line-arguments))
(define part (string->symbol (car args)))

(define (split-at-char s c)
  (let loop ((i 0))
    (cond ((= i (string-length s)) #f)
          ((char=? (string-ref s i) c) (cons (substring s 0 i) (substring s (+ i 1) (string-length s))))
          (else (loop (+ i 1))))))

(define settings
  (map (lambda (a)
         (let ((kv (split-at-char a #\=)))
           (unless kv (error 'maxredirs.sps "not KEY=VALUE" a))
           (cons (string->symbol (car kv)) (cdr kv))))
       (cdr args)))

(define (setting key)
  (let ((hit (assq key settings)))
    (unless hit (error 'maxredirs.sps "no such argument" key))
    (cdr hit)))

(define ca (setting 'ca))
(define slow (string->number (setting 'slow)))
(define (bound ms) (* ms slow))

(define (say fmt . xs)
  (apply printf fmt xs)
  (newline)
  (flush-output-port (current-output-port)))

(define (ns-of t) (+ (* (time-second t) 1000000000) (time-nanosecond t)))
(define (now-ns) (ns-of (current-time 'time-monotonic)))
(define (ms-since t0) (/ (round (/ (- (now-ns) t0) 100000)) 10.0))

(define (hex bv)
  (apply string-append
         (map (lambda (b) (string-append (if (< b 16) "0" "") (number->string b 16)))
              (bytevector->u8-list bv))))

(define (pattern-bytes offset n)
  (let ((bv (make-bytevector n)))
    (do ((i 0 (+ i 1))) ((= i n) bv)
      (bytevector-u8-set! bv i (mod (+ offset i) 251)))))

(define (query params)
  (let loop ((ps params) (acc ""))
    (if (null? ps)
        acc
        (loop (cdr ps) (string-append acc (if (string=? acc "") "" "&") (caar ps) "=" (cdar ps))))))

(define (route-url params tag)
  (string-append "http://127.0.0.1:" (setting 'http) "/auth?" (query (append params (list (cons "tag" tag))))))

(define (cred-options scheme)
  (case scheme
    ((basic) '(("HTTPAUTH" . 1) ("USERNAME" . "user") ("PASSWORD" . "pass")))
    ((digest) '(("HTTPAUTH" . 2) ("USERNAME" . "user") ("PASSWORD" . "pass")))
    ((bearer) '(("HTTPAUTH" . 64) ("XOAUTH2_BEARER" . "tok123")))
    (else (error 'cred-options "no such scheme" scheme))))

(define account
  (list (cons "uh" (hex (string->utf8 "user"))) (cons "ph" (hex (string->utf8 "pass")))
        (cons "th" (hex (string->utf8 "tok123")))))

(define (scheme-ch scheme) (case scheme ((basic) "basic") ((digest) "digest") ((bearer) "bearer")))

(define (make-req url method body options . keys)
  (guard (e (#t e))
    (let ((base (apply make-curl-request url 'ca-file ca 'method method 'timeout-ms (bound 5000)
                       (append (if body (list 'body body) '()) keys))))
      (if (null? options) base (curl-request-with-options base options)))))

(define (await token)
  (if (curl-token-wait token (bound 15000))
      (curl-token-outcome token)
      (begin (curl-token-cancel token) (curl-token-wait token (bound 5000)) 'hung)))

(define (run engine req)
  (if (condition? req) req (guard (e (#t e)) (await (curl-submit engine req)))))

(define (with-engine proc)
  (let ((engine (make-curl-engine)))
    (let ((answer (guard (e (#t (curl-engine-stop engine) (raise e))) (proc engine))))
      (curl-engine-stop engine)
      answer)))

(define (condition-text c) (call-with-string-output-port (lambda (p) (display-condition c p))))

(define (describe o)
  (cond ((curl-response? o)
         (format "ok status=~a version=~a body-bytes=~a" (curl-response-status o) (curl-response-http-version o)
                 (let ((b (curl-response-body o))) (if b (bytevector-length b) "#f"))))
        ((curl-transfer-error? o)
         (format "fail reason=~a code=~a sent=~a option=~a strerror=~s errbuf=~s"
                 (curl-transfer-error-reason o) (curl-transfer-error-code o)
                 (curl-transfer-error-request-size o) (curl-transfer-error-option o)
                 (curl-transfer-error-strerror o) (curl-transfer-error-error-buffer o)))
        ((curl-request-error? o)
         (format "refused field=~a reason=~a value=~s" (curl-request-error-field o)
                 (curl-request-error-reason o) (curl-request-error-value o)))
        ((condition? o) (format "condition ~s" (condition-text o)))
        ((eq? o 'hung) "hung")
        (else (format "other ~s" o))))

(define tag-n 0)
(define (fresh-tag) (set! tag-n (+ tag-n 1)) (format "~a~a" part tag-n))

(define log-engine #f)

(define (split-lines s)
  (let loop ((cs (string->list s)) (cur '()) (acc '()))
    (cond ((null? cs) (reverse (if (null? cur) acc (cons (list->string (reverse cur)) acc))))
          ((char=? (car cs) #\newline) (loop (cdr cs) '() (cons (list->string (reverse cur)) acc)))
          (else (loop (cdr cs) (cons (car cs) cur) acc)))))

(define (show-log tag)
  (let* ((url (string-append "http://127.0.0.1:" (setting 'ctl) "/log?tag=" tag))
         (o (run log-engine (make-req url 'get #f '() 'proxy #f))))
    (if (and (curl-response? o) (curl-response-body o))
        (for-each (lambda (line) (unless (string=? line "") (say "s ~a ~a" tag line)))
                  (split-lines (utf8->string (curl-response-body o))))
        (say "s ~a log-fetch-failed ~a" tag (describe o)))))

;; one-case : Symbol Symbol (U #f Integer) (String -> Request) -> Void
(define (one-case kase scheme maxredirs make)
  (let* ((tag (fresh-tag))
         (t0 (now-ns))
         (o (with-engine (lambda (e) (run e (make tag))))))
    (say "t mr case=~a scheme=~a maxredirs=~a tag=~a ms=~a => ~a" kase scheme (or maxredirs "unset") tag
         (ms-since t0) (describe o))
    (show-log tag)))

(define (with-maxredirs options maxredirs)
  (if maxredirs (append options (list (cons "MAXREDIRS" maxredirs))) options))

(define (part-maxredirs)
  (for-each
   (lambda (maxredirs)
     ;; 1. rounds1's case, each scheme
     (for-each
      (lambda (scheme)
        (one-case 'expect417 scheme maxredirs
          (lambda (tag)
            (make-req (route-url (append (list (cons "ch" (scheme-ch scheme)) '("expect" . "417")) account) tag)
                      'post (pattern-bytes 0 65536) (with-maxredirs (cred-options scheme) maxredirs)
                      'headers '(("Expect" . "100-continue"))))))
      '(basic bearer digest))
     ;; 2. Digest, answered stale=true for ever
     (one-case 'stale-forever 'digest maxredirs
       (lambda (tag)
         (make-req (route-url (append '(("ch" . "digest") ("stale" . "1000000")) account) tag)
                   'get #f (with-maxredirs (cred-options 'digest) maxredirs))))
     ;; 3. Digest, challenged once
     (one-case 'round 'digest maxredirs
       (lambda (tag)
         (make-req (route-url (cons '("ch" . "digest") account) tag)
                   'get #f (with-maxredirs (cred-options 'digest) maxredirs)))))
   '(#f 30)))

(let ((info (loaded-libcurl)))
  (say "libcurl version=~a ssl=~s path=~a part=~a" (libcurl-info-version info)
       (libcurl-info-ssl-version info) (libcurl-info-path info) part))
(set! log-engine (make-curl-engine))
(case part
  ((maxredirs) (part-maxredirs))
  (else (error 'maxredirs.sps "no such part" part)))
(curl-engine-stop log-engine)
(say "native ~s" (native-counts))
(say "part ~a done" part)
