#!chezscheme
;;; M7 slice 3's measurements (2026-11-02; the M7 plan, section 6.1),
;;; through chez-curl's engine: a proxy given by URL, on the prototype
;;; (make-prototype.sh), but for the parts that run on main's src/.
;;;
;;;   scheme --libdirs LIBDIRS --program proxy.sps PART KEY=VALUE ...
;;;
;;; run.sh passes the KEYs: tmp, the run's temp directory; ca, the run CA;
;;; other, the PKI's second CA; cadir, the run CA's hashed directory; slow,
;;; a multiplier for every bound (1 natively, more under Valgrind); env, the
;;; name of the environment run.sh gave this process (none, or one of
;;; item 1's and item 5's); and every stand-in face's port, FACE=PORT
;;; (standin.mjs). run.sh runs every part under env -i: the process's
;;; environment is CHEZ_CURL_LIBCURL, EXTRA_ENV on the Mac, and the
;;; variables its env names, and nothing else. The first line printed is
;;; that environment, read from /proc/self/environ.
;;;
;;; Every request carries timeout-ms 10,000, and ca-file the run CA for an
;;; https:// URL, unless named; every wait is bounded at 15,000 ms, and a
;;; transfer still running then is cancelled and logged "hung". Every bound
;;; is multiplied by slow. Each case runs on an engine of its own, but
;;; item 3's, whose two transfers share one, and item 8's, a session's.
;;; Each case is a stand-in case: /begin before it, /end after its engine
;;; has stopped, so every connection a case's transfers opened is closed,
;;; and its log is printed whole.
;;;
;;; PART is one of:
;;;   refusals   the hatch's and the proxy field's answers: on main's src/
;;;              (refusals-main) and on the prototype.
;;;   setopts    curl_easy_setopt's own answer to each proxy TLS setting, on
;;;              a scratch easy handle (item 5).
;;;   urlparse   item 2 (a): curl-url-part of each proxy URL, every part, on
;;;              main's src/.
;;;   named      item 1: a named proxy beside the environment env names.
;;;   userinfo   item 2 (b): each userinfo form's Proxy-Authorization.
;;;   ports      item 2 (c): proxy URLs naming :80, :443 and none, against
;;;              the stand-in's p80, p1080 and tp443 (Docker alone).
;;;   pooled     item 3: two transfers on one engine through one proxy.
;;;   refused    item 4: a refused CONNECT, and the high level's retry.
;;;   tls        item 5: the proxy's TLS: leaves, switches, the two TLS
;;;              settings apart.
;;;   tlsenv     item 5: SSL_CERT_FILE and SSL_CERT_DIR beside a
;;;              PROXY_CAINFO, in the environment env names.
;;;   stall      item 5: an https:// origin through an https:// proxy, ten
;;;              times each, with its controls.
;;;   twins      item 6.
;;;   pk         item 7: prior knowledge through a named proxy.
;;;   hl         item 8: the high level's proxy, a call's, redirects and
;;;              credentials.
;;;   sent       item 9: REQUEST_SIZE of proxied transfers that pass, read
;;;              from a twin that fails at body-limit 1 after the send.
;;;   wire       the wire check's cases, with libcurl's own trace (VERBOSE).
;;;
;;; Each transfer prints one "t" line: the item, its case's fields, its tag
;;; and "=>" what it ended with; then the stand-in's log for the tag, each
;;; line "s TAG ...". Each part ends with a "native" line.
(import (chezscheme)
        (curl)
        (curl unsupported)
        (http-client)
        (only (curl private engine) call-with-engine-held)
        (only (curl private counters) native-counts)
        (only (curl private native) curl-easy-init curl-easy-cleanup curl-easy-setopt-pointer
              curl-easy-setopt-long curl-easy-option call-with-c-string))

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
           (unless kv (error 'proxy.sps "not KEY=VALUE" a))
           (cons (string->symbol (car kv)) (cdr kv))))
       (cdr args)))

(define (setting key)
  (let ((hit (assq key settings)))
    (unless hit (error 'proxy.sps "no such argument" key))
    (cdr hit)))
(define (setting? key) (and (assq key settings) #t))

(define ca (setting 'ca))
(define other-ca (setting 'other))
(define cadir (setting 'cadir))
(define slow (string->number (setting 'slow)))
(define env-name (setting 'env))
(define (bound ms) (* ms slow))

(define (say fmt . xs)
  (apply printf fmt xs)
  (newline)
  (flush-output-port (current-output-port)))

(define (ns-of t) (+ (* (time-second t) 1000000000) (time-nanosecond t)))
(define (now-ns) (ns-of (current-time 'time-monotonic)))
(define (ms-since t0) (/ (round (/ (- (now-ns) t0) 100000)) 10.0))

;; --- bytes ----------------------------------------------------------------------------

;; render : Bytevector -> String
;; BYTES as the stand-in escapes them: \r \n \\ \" and any byte outside
;; 0x20..0x7e as \xHH; past 400 bytes, cut, with the count.
(define (render bytes)
  (let ((out (open-output-string)) (n (min 400 (bytevector-length bytes))))
    (do ((i 0 (+ i 1))) ((= i n))
      (let ((b (bytevector-u8-ref bytes i)))
        (cond ((= b 13) (put-string out "\\r"))
              ((= b 10) (put-string out "\\n"))
              ((= b 92) (put-string out "\\\\"))
              ((= b 34) (put-string out "\\\""))
              ((and (>= b 32) (< b 127)) (put-char out (integer->char b)))
              (else (put-string out (string-append "\\x" (if (< b 16) "0" "") (string-downcase (number->string b 16))))))))
    (when (> (bytevector-length bytes) n)
      (put-string out (format "...(~a bytes)" (bytevector-length bytes))))
    (get-output-string out)))

;; latin-1 : String -> Bytevector
;; Each char of S, a header string, as the byte it stands for.
(define (latin-1 s)
  (u8-list->bytevector (map (lambda (c) (bitwise-and #xff (char->integer c))) (string->list s))))

(define (join strings sep)
  (if (null? strings)
      ""
      (fold-left (lambda (acc s) (string-append acc sep s)) (car strings) (cdr strings))))

(define (split-lines s)
  (let loop ((cs (string->list s)) (cur '()) (acc '()))
    (cond ((null? cs) (reverse (if (null? cur) acc (cons (list->string (reverse cur)) acc))))
          ((char=? (car cs) #\newline) (loop (cdr cs) '() (cons (list->string (reverse cur)) acc)))
          (else (loop (cdr cs) (cons (car cs) cur) acc)))))

;; environment-line : -> String
;; This process's environment, as it began: /proc/self/environ's entries,
;; sorted, each rendered; on a system without it, the variables a proxy
;; case reads, by getenv.
(define (environment-line)
  (let ((bytes (guard (e (#t #f))
                 (call-with-port (open-file-input-port "/proc/self/environ") get-bytevector-all))))
    (cond ((eof-object? bytes) "env 0 (empty)")
          ((not bytes)
           (format "env (no /proc/self/environ) ~a"
                   (join (map (lambda (n) (format "~a=~a" n (or (getenv n) "#unset")))
                              '("http_proxy" "HTTP_PROXY" "https_proxy" "HTTPS_PROXY" "all_proxy" "ALL_PROXY"
                                "no_proxy" "NO_PROXY" "SSL_CERT_FILE" "SSL_CERT_DIR" "CURL_SSL_BACKEND"
                                "CHEZ_CURL_LIBCURL"))
                         " ")))
          (else
           (let loop ((i 0) (start 0) (found '()))
             (cond ((= i (bytevector-length bytes))
                    (let ((all (list-sort string<? (if (> i start)
                                                       (cons (render (subbytes bytes start i)) found)
                                                       found))))
                      (format "env ~a ~a" (length all) (join all " "))))
                   ((= (bytevector-u8-ref bytes i) 0)
                    (loop (+ i 1) (+ i 1) (if (> i start) (cons (render (subbytes bytes start i)) found) found)))
                   (else (loop (+ i 1) start found))))))))

(define (subbytes bv start end)
  (let ((out (make-bytevector (- end start))))
    (bytevector-copy! bv start out 0 (- end start))
    out))

;; --- faces and URLs ---------------------------------------------------------------------

(define tls-faces '(o-tls o-h2 tp-good tp-expired tp-wrong tp-untrusted tp-basic tp443))
(define (scheme-of face) (if (memq face tls-faces) "https" "http"))

;; url : Symbol String -> String
;; FACE's URL with PATH, at 127.0.0.1.
(define (url face path) (string-append (scheme-of face) "://127.0.0.1:" (setting face) path))

;; purl : Symbol String -> String
;; A proxy URL for FACE with USERINFO, its scheme FACE's own.
(define (purl face userinfo) (string-append (scheme-of face) "://" userinfo "127.0.0.1:" (setting face)))

(define (path-of tag) (string-append "/x?tag=" tag))
(define (https? u) (and (>= (string-length u) 8) (string=? (substring u 0 8) "https://")))

;; options a case names
(define noproxy-empty '(("NOPROXY" . "")))
(define (proxy-ca path) (list (cons "PROXY_CAINFO" path) (cons "PROXY_CAPATH" #f)))
(define proxy-noverify '(("PROXY_SSL_VERIFYPEER" . 0) ("PROXY_SSL_VERIFYHOST" . 0)))

;; --- requests, transfers, outcomes ----------------------------------------------------

;; make-req : String Symbol Any Any (Listof Option) Any ... -> (U Request Condition)
;; URL's request of METHOD, through PROXY, with BODY when not #f,
;; timeout-ms 10,000 and, for an https:// URL, ca-file the run CA, unless
;; KEYS name either, then KEYS, then OPTIONS through the hatch; or what
;; raised.
(define (make-req url method body proxy options . keys)
  (guard (e (#t e))
    (let ((base (apply make-curl-request url 'method method 'proxy proxy
                       (append (if (memq 'timeout-ms keys) '() (list 'timeout-ms (bound 10000)))
                               (if (or (memq 'ca-file keys) (not (https? url))) '() (list 'ca-file ca))
                               (if body (list 'body body) '())
                               keys))))
      (if (null? options) base (curl-request-with-options base options)))))

(define (await token)
  (if (curl-token-wait token (bound 15000))
      (curl-token-outcome token)
      (begin (curl-token-cancel token) (curl-token-wait token (bound 5000)) 'hung)))

;; run : Engine (U Request Condition) -> (U Response Condition 'hung)
(define (run engine req)
  (if (condition? req)
      req
      (guard (e (#t e)) (await (curl-submit engine req)))))

(define (with-engine proc)
  (let ((engine (make-curl-engine)))
    (let ((answer (guard (e (#t (curl-engine-stop engine) (raise e))) (proc engine))))
      (curl-engine-stop engine)
      answer)))

(define (classes-of e)
  (filter symbol?
          (list (and (curl-timeout? e) 'timeout) (and (curl-connect-error? e) 'connect)
                (and (curl-send-receive-error? e) 'send-receive) (and (curl-tls-error? e) 'tls)
                (and (curl-protocol-error? e) 'protocol) (and (curl-too-large? e) 'too-large))))

(define (condition-text c)
  (call-with-string-output-port (lambda (p) (display-condition c p))))

(define (headers-text headers)
  (render (latin-1 (join (map (lambda (h) (string-append (car h) ": " (cdr h))) headers) " | "))))

;; describe : Any -> String
(define (describe o)
  (cond ((curl-response? o)
         (format "ok status=~a version=~a headers=\"~a\" body=\"~a\" timings=~a"
                 (curl-response-status o) (curl-response-http-version o)
                 (headers-text (curl-response-headers o))
                 (let ((b (curl-response-body o))) (if b (render b) "#f"))
                 (curl-response-timings o)))
        ((curl-head? o)
         (format "head status=~a version=~a headers=\"~a\"" (curl-head-status o) (curl-head-http-version o)
                 (headers-text (curl-head-headers o))))
        ((http-response? o)
         (format "hok status=~a version=~a url=~a history=~a headers=\"~a\" body=\"~a\""
                 (http-response-status o) (http-response-http-version o) (http-response-url o)
                 (map http-response-status (http-response-history o))
                 (headers-text (http-response-headers o))
                 (let ((b (http-response-body o))) (if b (render b) "#f"))))
        ((condition? o)
         (string-append
          (cond ((curl-transfer-error? o)
                 (format "fail reason=~a code=~a classes=~a sent=~a option=~a strerror=~s errbuf=~s"
                         (curl-transfer-error-reason o) (curl-transfer-error-code o) (classes-of o)
                         (curl-transfer-error-request-size o) (curl-transfer-error-option o)
                         (curl-transfer-error-strerror o) (curl-transfer-error-error-buffer o)))
                ((curl-request-error? o)
                 (format "refused field=~a reason=~a value=~s" (curl-request-error-field o)
                         (curl-request-error-reason o) (curl-request-error-value o)))
                ((http-request-error? o)
                 (format "hrefused field=~a reason=~a value=~s" (http-request-error-field o)
                         (http-request-error-reason o) (http-request-error-value o)))
                ((http-redirect-error? o)
                 (format "redirect-error reason=~a location=~s" (http-redirect-error-reason o)
                         (http-redirect-error-location o)))
                ((curl-url-error? o)
                 (format "url-error reason=~a code=~a" (curl-url-error-reason o) (curl-url-error-code o)))
                (else (format "condition ~s" (condition-text o))))
          (if (http-exchange? o)
              (format " transfers=~a history=~a timeout=~a" (http-exchange-transfers o)
                      (map http-response-status (http-exchange-history o)) (http-timeout? o))
              "")))
        ((eq? o 'hung) "hung")
        (else (format "other ~s" o))))

;; fields->text : (Listof (Pairof Symbol Any)) -> String
(define (fields->text alist)
  (join (map (lambda (p) (format "~a=~a" (car p) (cdr p))) alist) " "))

;; --- cases and the stand-in's log --------------------------------------------------------

(define tag-n 0)
(define (fresh-tag)
  (set! tag-n (+ tag-n 1))
  (if (string=? env-name "none")
      (format "~a~a" part tag-n)
      (format "~a.~a.~a" part env-name tag-n)))

(define log-engine #f)

;; ctl : String -> (U String #f)
;; The stand-in's answer to the control PATH, through the log engine, with
;; no proxy.
(define (ctl path)
  (let ((o (run log-engine (make-req (string-append "http://127.0.0.1:" (setting 'ctl) path) 'get #f #f '()))))
    (and (curl-response? o) (curl-response-body o) (utf8->string (curl-response-body o)))))

;; in-case : String Alist (String -> (Listof (Pairof Alist Any))) -> Void
;; One stand-in case: /begin, THUNK's transfers, given the case's tag, each
;; row (FIELDS . OUTCOME) printed as a t line, then the log, by /end.
(define (in-case item alist thunk)
  (let ((tag (fresh-tag)))
    (ctl (string-append "/begin?case=" tag))
    (let ((rows (guard (e (#t (list (cons '((step . raised)) e)))) (thunk tag))))
      (for-each (lambda (row)
                  (say "t ~a ~a tag=~a ~a => ~a" item (fields->text alist) tag (fields->text (car row))
                       (describe (cdr row))))
                rows)
      (let ((text (ctl (string-append "/end?case=" tag))))
        (if text
            (for-each (lambda (l) (unless (string=? l "") (say "s ~a ~a" tag l))) (split-lines text))
            (say "s ~a log-fetch-failed" tag))))))

;; single : String Alist (String -> (U Request Condition)) -> Void
;; A case of one transfer, MAKE's request for the tag, on an engine of its
;; own.
(define (single item alist make)
  (in-case item alist
    (lambda (tag)
      (let* ((t0 (now-ns))
             (o (with-engine (lambda (e) (run e (make tag))))))
        (list (cons (list (cons 'step 1) (cons 'ms (ms-since t0))) o))))))

(define (say-libcurl)
  (let ((info (loaded-libcurl)))
    (say "libcurl version=~a ssl=~s path=~a part=~a env=~a" (libcurl-info-version info)
         (libcurl-info-ssl-version info) (libcurl-info-path info) part env-name)))

(define (say-native) (say "native ~s" (native-counts)))

(define post-body (string->utf8 "m7s3 post body: sixty-four bytes of it, no more and no less!!\n"))

;; --- refusals: the hatch's and the field's answers (both trees) ---------------------

(define (attach options keys)
  (guard (e (#t e))
    (let ((base (apply make-curl-request (url 'o-raw "/refusals") keys)))
      (curl-request-with-options base options)
      'attached)))

(define (part-refusals)
  (for-each
   (lambda (row)
     (let ((o (attach (cadr row) '())))
       (say "r case=~a => ~a" (car row) (if (eq? o 'attached) "attached" (describe o)))))
   `((PROXY (("PROXY" . "http://127.0.0.1:1")))
     (NOPROXY (("NOPROXY" . "")))
     (PROXY_CAINFO (("PROXY_CAINFO" . ,ca)))
     (PROXY_CAPATH (("PROXY_CAPATH" . ,cadir)))
     (PROXY_CAPATH-clear (("PROXY_CAPATH" . #f)))
     (PROXY_SSL_VERIFYPEER (("PROXY_SSL_VERIFYPEER" . 0)))
     (PROXY_SSL_VERIFYHOST (("PROXY_SSL_VERIFYHOST" . 0)))
     (HTTPPROXYTUNNEL (("HTTPPROXYTUNNEL" . 1)))
     (SUPPRESS_CONNECT_HEADERS (("SUPPRESS_CONNECT_HEADERS" . 1)))
     (PROXY_SERVICE_NAME (("PROXY_SERVICE_NAME" . "svc")))
     (PROXY_SERVICE_NAME-clear (("PROXY_SERVICE_NAME" . #f)))
     (SOCKS5_AUTH (("SOCKS5_AUTH" . 1)))
     (HAPROXYPROTOCOL (("HAPROXYPROTOCOL" . 1)))
     (HAPROXY_CLIENT_IP (("HAPROXY_CLIENT_IP" . "10.1.2.3")))
     (PROXYAUTH (("PROXYAUTH" . 1)))
     (PROXYUSERPWD (("PROXYUSERPWD" . "alice:s3cret")))
     (PROXYUSERNAME (("PROXYUSERNAME" . "alice")))
     (PROXYPASSWORD (("PROXYPASSWORD" . "s3cret")))
     (PROXYHEADER (("PROXYHEADER" . ("X-Proxy-Only: 1"))))
     (HEADEROPT (("HEADEROPT" . 1)))
     (PRE_PROXY (("PRE_PROXY" . "socks5://127.0.0.1:1")))
     (PROXYTYPE (("PROXYTYPE" . 0)))
     (PROXYPORT (("PROXYPORT" . 8080)))
     (FRESH_CONNECT (("FRESH_CONNECT" . 1)))
     (FORBID_REUSE (("FORBID_REUSE" . 1)))
     (VERBOSE (("VERBOSE" . 1)))
     (CAPATH-clear (("CAPATH" . #f)))
     (USERAGENT-clear (("USERAGENT" . #f)))))
  ;; the proxy field itself, at both levels
  (for-each
   (lambda (value)
     (let ((o (guard (e (#t e)) (make-curl-request (url 'o-raw "/refusals") 'proxy value) 'made)))
       (say "r case=field-proxy value=~s => ~a" value (if (eq? o 'made) "made" (describe o))))
     (let ((o (guard (e (#t e)) (let ((s (make-http-session 'proxy value))) (http-session-close s) 'made))))
       (say "r case=session-proxy value=~s => ~a" value (if (eq? o 'made) "made" (describe o)))))
   (list "http://127.0.0.1:1" 'environment #f "")))

;; --- setopts: libcurl's own answers ------------------------------------------------------

(define (part-setopts)
  (let ((easy (curl-easy-init)))
    (for-each
     (lambda (row)
       (let* ((name (car row)) (value (cdr row)) (option (curl-easy-option name)))
         (if (not option)
             (say "o name=~a value=~s => unknown" name value)
             (let ((code (cond ((string? value)
                                (call-with-c-string value (lambda (a) (curl-easy-setopt-pointer easy (car option) a))))
                               ((not value) (curl-easy-setopt-pointer easy (car option) 0))
                               (else (curl-easy-setopt-long easy (car option) value)))))
               (say "o name=~a value=~s => code ~a" name value code)))))
     (list (cons "PROXY_CAINFO" ca) (cons "PROXY_CAPATH" #f) (cons "PROXY_CAPATH" cadir)
           (cons "PROXY_CAINFO" #f) (cons "PROXY_SSL_VERIFYPEER" 0) (cons "PROXY_SSL_VERIFYPEER" 1)
           (cons "PROXY_SSL_VERIFYHOST" 0) (cons "PROXY_SSL_VERIFYHOST" 2)
           (cons "CAINFO" ca) (cons "CAPATH" #f) (cons "CAPATH" cadir)
           (cons "HAPROXY_CLIENT_IP" "10.1.2.3") (cons "NOPROXY" "")))
    (curl-easy-cleanup easy)))

;; --- item 2 (a): the URL parse, on main's src/ -------------------------------------------

(define url-parts '(url scheme user password host port path query fragment zoneid))

(define (part-urlparse)
  (let ((p (setting 'p-open)))
    (for-each
     (lambda (row)
       (let ((name (car row)) (u (cadr row)))
         (for-each
          (lambda (prt)
            (let ((o (guard (e (#t e)) (curl-url-part u prt))))
              (say "u case=~a url=\"~a\" part=~a => ~a" name (render (string->utf8 u)) prt
                   (cond ((string? o) (format "\"~a\"" (render (string->utf8 o))))
                         ((not o) "absent")
                         ((number? o) (number->string o))
                         (else (describe o))))))
          url-parts)))
     `((port-http ,(string-append "http://127.0.0.1:" p))
       (noport-http "http://127.0.0.1")
       (noport-https "https://127.0.0.1")
       (port80 "http://127.0.0.1:80")
       (port443 "https://127.0.0.1:443")
       (upper-scheme ,(string-append "HTTP://127.0.0.1:" p))
       (no-scheme ,(string-append "127.0.0.1:" p))
       (foo ,(string-append "foo://127.0.0.1:" p))
       (ftp ,(string-append "ftp://127.0.0.1:" p))
       (socks5 ,(string-append "socks5://127.0.0.1:" p))
       (path-a ,(string-append "http://127.0.0.1:" p "/a"))
       (path-slash ,(string-append "http://127.0.0.1:" p "/"))
       (query ,(string-append "http://127.0.0.1:" p "/?q=1"))
       (query-nopath ,(string-append "http://127.0.0.1:" p "?q=1"))
       (fragment ,(string-append "http://127.0.0.1:" p "/#f"))
       (fragment-nopath ,(string-append "http://127.0.0.1:" p "#f"))
       (ipv6 ,(string-append "http://[::1]:" p))
       (ipv6-zone ,(string-append "http://[fe80::1%25eth0]:" p))
       (ipv6-zone-lo ,(string-append "http://[::1%25lo]:" p))
       ,@(map (lambda (u) (list (string->symbol (string-append "ui-" (car u)))
                                (string-append "http://" (cdr u) "127.0.0.1:" p)))
              userinfo-forms)))))

;; userinfo-forms : (Listof (Pairof String String))
;; Each userinfo form, its name and its text with the @.
(define userinfo-forms
  '(("at" . "@") ("colon-at" . ":@") ("u-at" . "u@") ("u-colon-at" . "u:@") ("colon-p-at" . ":p@")
    ("u-p-at" . "u:p@") ("user-3A" . "a%3Ab:p@") ("pass-3A" . "u:p%3Aq@")
    ("user-0D0A" . "u%0D%0Ax:p@") ("pass-0D0A" . "u:p%0D%0Ax@")
    ("user-00" . "u%00x:p@") ("pass-00" . "u:p%00x@")
    ("user-01" . "u%01x:p@") ("user-09" . "u%09x:p@") ("user-1F" . "u%1Fx:p@") ("user-20" . "u%20x:p@")
    ("user-7F" . "u%7Fx:p@") ("pass-7F" . "u:p%7Fx@")
    ("utf8-pct" . "%C3%A9l%C3%A8ve:p%C3%A4ss@")
    ("user-FF" . "u%FFx:p@") ("pass-FF" . "u:p%FFx@")
    ("pct-25" . "u%25x:p%25q@")
    ("utf8-raw" . "\xe9;l\xe8;ve:p\xe4;ss@")))

;; --- item 1: a named proxy beside the environment ------------------------------------------

(define (part-named)
  (for-each
   (lambda (transport)
     (for-each
      (lambda (np)
        (let ((face (car transport)) (version (cadr transport)))
          (single "i1" (list (cons 'transport (caddr transport)) (cons 'noproxy (car np)))
            (lambda (tag)
              (apply make-req (url face (path-of tag)) 'get #f (purl 'p-open "") (cdr np)
                     (if version (list 'http-version version) '()))))))
      (list (cons "empty" noproxy-empty) (cons "unset" '()))))
   '((o-raw #f "absolute-http") (o-tls #f "connect-https") (o-h2 http/2 "connect-h2")))
  ;; controls: no proxy, and the environment's
  (for-each
   (lambda (row)
     (single "i1" (list (cons 'transport (car row)) (cons 'noproxy "control"))
       (lambda (tag) (make-req (url (cadr row) (path-of tag)) 'get #f (caddr row) '()))))
   '(("direct-http" o-raw #f) ("environment-http" o-raw environment) ("environment-https" o-tls environment))))

;; --- item 2 (b): each userinfo form on the wire -----------------------------------------------

(define (part-userinfo)
  (for-each
   (lambda (form)
     (for-each
      (lambda (transport)
        (single "i2b" (list (cons 'form (car form)) (cons 'transport (cadr transport)))
          (lambda (tag) (make-req (url (car transport) (path-of tag)) 'get #f (purl 'p-open (cdr form)) '()))))
      '((o-raw "absolute") (o-tls "connect"))))
   (cons '("none" . "") userinfo-forms))
  ;; no scheme, with userinfo
  (for-each
   (lambda (transport)
     (single "i2b" (list (cons 'form "noscheme-u-p") (cons 'transport (cadr transport)))
       (lambda (tag) (make-req (url (car transport) (path-of tag)) 'get #f
                               (string-append "u:p@127.0.0.1:" (setting 'p-open)) '()))))
   '((o-raw "absolute") (o-tls "connect"))))

;; --- item 2 (c): the ports a URL names, and none --------------------------------------------

(define (part-ports)
  (if (not (setting? 'p80))
      (say "ports skipped: the stand-in has no low ports (Docker alone)")
      (for-each
       (lambda (row)
         (for-each
          (lambda (transport)
            (single "i2c" (list (cons 'proxy (car row)) (cons 'transport (cadr transport)))
              (lambda (tag) (make-req (url (car transport) (path-of tag)) 'get #f (cadr row) (caddr row)))))
          '((o-raw "absolute") (o-tls "connect"))))
       `(("http-80" "http://127.0.0.1:80" ())
         ("http-none" "http://127.0.0.1" ())
         ("noscheme-none" "127.0.0.1" ())
         ("https-443" "https://127.0.0.1:443" ,(proxy-ca ca))
         ("https-none" "https://127.0.0.1" ,(proxy-ca ca))))))

;; --- item 3: the pooled tunnel ----------------------------------------------------------------

;; pooled-modes : each mode's name, origin, proxy face, the hatch options
;; every transfer of it carries, and its http-version.
(define pooled-modes
  `(("connect-https" o-tls p-basic () #f)
    ("tunnel-http" o-raw p-basic (("HTTPPROXYTUNNEL" . 1)) #f)
    ("absolute-http" o-raw p-basic () #f)
    ("https-proxy-connect-https" o-tls tp-basic ,(proxy-ca ca) #f)
    ("https-proxy-absolute-http" o-raw tp-basic ,(proxy-ca ca) #f)
    ("connect-h2" o-h2 p-basic () http/2)))

(define second-variants
  '(("same" . "alice:s3cret@") ("other" . "bob:hunter2@") ("wrong" . "alice:wrong@") ("none" . "")))

(define pooled-flags
  '(("plain" () ()) ("fresh-second" () (("FRESH_CONNECT" . 1))) ("forbid-first" (("FORBID_REUSE" . 1)) ())))

(define (pooled-req mode userinfo extra tag step)
  (let ((face (cadr mode)) (proxy (caddr mode)) (opts (cadddr mode)) (version (car (cddddr mode))))
    (apply make-req (url face (string-append (path-of tag) "&step=" step)) 'get #f (purl proxy userinfo)
           (append opts extra)
           (if version (list 'http-version version) '()))))

(define (part-pooled)
  (for-each
   (lambda (mode)
     (for-each
      (lambda (flags)
        (for-each
         (lambda (variant)
           (in-case "i3" (list (cons 'mode (car mode)) (cons 'flags (car flags)) (cons 'second (car variant)) '(order . sequential))
             (lambda (tag)
               (with-engine
                (lambda (e)
                  (let* ((t0 (now-ns))
                         (o1 (run e (pooled-req mode "alice:s3cret@" (cadr flags) tag "1")))
                         (m1 (ms-since t0))
                         (o2 (run e (pooled-req mode (cdr variant) (caddr flags) tag "2"))))
                    (list (cons (list '(step . 1) (cons 'ms m1)) o1)
                          (cons (list '(step . 2) (cons 'ms (ms-since t0))) o2))))))))
         second-variants))
      pooled-flags))
   pooled-modes)
  ;; two in one batch, to h2 by CONNECT
  (for-each
   (lambda (flags)
     (for-each
      (lambda (variant)
        (in-case "i3" (list '(mode . "connect-h2") (cons 'flags (car flags)) (cons 'second (car variant)) '(order . batch))
          (lambda (tag)
            (with-engine
             (lambda (e)
               (let* ((mode (assoc "connect-h2" pooled-modes))
                      (r1 (pooled-req mode "alice:s3cret@" (cadr flags) tag "1"))
                      (r2 (pooled-req mode (cdr variant) (caddr flags) tag "2"))
                      (t0 (now-ns))
                      (tokens (if (or (condition? r1) (condition? r2))
                                  #f
                                  (call-with-engine-held e (lambda () (let* ((t1 (curl-submit e r1)) (t2 (curl-submit e r2))) (list t1 t2))))))
                      (o1 (if tokens (await (car tokens)) r1))
                      (o2 (if tokens (await (cadr tokens)) r2)))
                 (list (cons (list '(step . 1) (cons 'ms (ms-since t0))) o1)
                       (cons (list '(step . 2) (cons 'ms (ms-since t0))) o2))))))))
      second-variants))
   pooled-flags))

;; --- item 4: a refused CONNECT, and the retry ------------------------------------------------

;; refusing : each case's name, its proxy face, and its userinfo.
(define refusing
  '(("403" p-403 "") ("407-none" p-basic "") ("407-wrong" p-basic "alice:wrong@") ("502" p-502 "")
    ("close" p-close "") ("partial" p-partial "") ("refused" refused "")))

(define (part-refused)
  (for-each
   (lambda (r)
     (for-each
      (lambda (transport)
        (single "i4" (list (cons 'proxy (car r)) (cons 'transport (cadr transport)) '(level . low))
          (lambda (tag) (make-req (url (car transport) (path-of tag)) 'get #f (purl (cadr r) (caddr r)) '()))))
      '((o-raw "absolute") (o-tls "connect"))))
   refusing)
  ;; the high level, with a policy and without
  (let ((policy (make-http-retry 'attempts 3 'backoff-ms 20 'max-backoff-ms 100 'jitter #f)))
    (for-each
     (lambda (r)
       (for-each
        (lambda (transport)
          (for-each
           (lambda (method)
             (for-each
              (lambda (retry)
                (in-case "i4" (list (cons 'proxy (car r)) (cons 'transport (cadr transport)) '(level . high)
                                    (cons 'method method) (cons 'retry (car retry)))
                  (lambda (tag)
                    (let* ((s (make-http-session 'proxy (purl (cadr r) (caddr r)) 'ca-file ca 'timeout-ms (bound 10000)
                                                 'retry (cdr retry)))
                           (t0 (now-ns))
                           (o (guard (e (#t e))
                                (if (eq? method 'get)
                                    (http-get s (url (car transport) (path-of tag)))
                                    (http-post s (url (car transport) (path-of tag)) 'body post-body)))))
                      (http-session-close s)
                      (list (cons (list '(step . 1) (cons 'ms (ms-since t0))) o))))))
              (list (cons "policy" policy) (cons "none" #f))))
           '(get post)))
        '((o-raw "absolute") (o-tls "connect"))))
     refusing)))

;; --- item 5: the proxy's TLS ------------------------------------------------------------------

(define leaves '(("good" . tp-good) ("expired" . tp-expired) ("wrong-host" . tp-wrong) ("untrusted" . tp-untrusted)))

(define (part-tls)
  (part-setopts)
  (for-each
   (lambda (leaf)
     (for-each
      (lambda (v)
        (for-each
         (lambda (transport)
           (single "i5" (list (cons 'leaf (car leaf)) (cons 'verify (car v)) (cons 'transport (cadr transport)))
             (lambda (tag) (make-req (url (car transport) (path-of tag)) 'get #f (purl (cdr leaf) "")
                                     (append (proxy-ca ca) (cdr v))))))
         '((o-raw "absolute") (o-tls "connect"))))
      (list (cons "on" '()) (cons "off" proxy-noverify))))
   leaves)
  ;; the origin's TLS against the proxy's
  (for-each
   (lambda (row)
     (single "i5" (list (cons 'sep (car row)) '(transport . "connect"))
       (lambda (tag) (apply make-req (url 'o-tls (path-of tag)) 'get #f (purl 'tp-good "") (cadr row) (caddr row)))))
   `(("both-good" ,(proxy-ca ca) (ca-file ,ca))
     ("origin-bad" ,(proxy-ca ca) (ca-file ,other-ca))
     ("proxy-bad" ,(proxy-ca other-ca) (ca-file ,ca))
     ("origin-noverify-proxy-bad" ,(proxy-ca other-ca) (ca-file #f verify #f))
     ("proxy-noverify-origin-bad" ,(append (proxy-ca other-ca) proxy-noverify) (ca-file ,other-ca))
     ("both-off" ,(append (proxy-ca other-ca) proxy-noverify) (ca-file #f verify #f))
     ("origin-verify-off-proxy-good" ,(proxy-ca ca) (ca-file #f verify #f)))))

;; tlsenv: an http:// origin through tp-good, so the proxy's TLS alone is
;; read, in the environment run.sh gave (SSL_CERT_FILE or SSL_CERT_DIR).
(define (part-tlsenv)
  (for-each
   (lambda (row)
     (single "i5env" (list (cons 'proxyca (car row)))
       (lambda (tag) (make-req (url 'o-raw (path-of tag)) 'get #f (purl 'tp-good "") (cadr row)))))
   `(("run-ca" ,(proxy-ca ca)) ("other-ca" ,(proxy-ca other-ca))
     ("other-ca-capath-default" (("PROXY_CAINFO" . ,other-ca))))))

(define (part-stall)
  (for-each
   (lambda (row)
     (do ((i 1 (+ i 1))) ((> i 10))
       (single "i5stall" (list (cons 'case (car row)) (cons 'rep i))
         (lambda (tag) (apply make-req (url (cadr row) (path-of tag)) 'get #f (purl (caddr row) "")
                              (if (eq? (caddr row) 'tp-good) (proxy-ca ca) '())
                              (cadddr row))))))
   '(("https-via-https" o-tls tp-good ())
     ("http-via-https" o-raw tp-good ())
     ("h2-via-https" o-h2 tp-good (http-version http/2))
     ("https-via-http" o-tls p-open ()))))

;; --- item 6: the twins --------------------------------------------------------------------

(define caller-headers '(("X-Caller" . "m7s3") ("Proxy-Authorization" . "Basic YWxpY2U6czNjcmV0")))

(define (part-twins)
  (for-each
   (lambda (row)
     (for-each
      (lambda (transport)
        (let* ((face (car transport)) (stream? (eq? (caddr transport) 'stream))
               (make (lambda (tag)
                       (apply make-req (url face (path-of tag)) 'get #f (purl 'p-open "") (cadr row)
                              'headers caller-headers
                              (if stream? (list 'stream-buffer 4096) '()))))
               (alist (list (cons 'twin (car row)) (cons 'transport (cadr transport)))))
          (if stream?
              ;; a streamed response: the outcome, then the head the token
              ;; published, which the header callable read
              (in-case "i6" alist
                (lambda (tag)
                  (let ((req (make tag)) (t0 (now-ns)))
                    (if (condition? req)
                        (list (cons '((step . 1)) req))
                        (with-engine
                         (lambda (e)
                           (let* ((token (curl-submit e req))
                                  (o (await token))
                                  (head (guard (x (#t x)) (curl-token-head token))))
                             (list (cons (list '(step . 1) (cons 'ms (ms-since t0))) o)
                                   (cons '((step . head)) head)))))))))
              (single "i6" alist make))))
      (caddr row)))
   `(("base" () ((o-raw "absolute" whole) (o-tls "connect" whole) (o-tls "connect-stream" stream)))
     ("HTTPPROXYTUNNEL-1" (("HTTPPROXYTUNNEL" . 1))
      ((o-raw "absolute" whole) (o-raw "absolute-stream" stream) (o-tls "connect" whole)))
     ("HTTPPROXYTUNNEL-0" (("HTTPPROXYTUNNEL" . 0)) ((o-raw "absolute" whole) (o-tls "connect" whole)))
     ("SUPPRESS_CONNECT_HEADERS" (("SUPPRESS_CONNECT_HEADERS" . 1))
      ((o-raw "absolute" whole) (o-tls "connect" whole) (o-tls "connect-stream" stream)))
     ("SUPPRESS_CONNECT_HEADERS-tunnel" (("SUPPRESS_CONNECT_HEADERS" . 1) ("HTTPPROXYTUNNEL" . 1))
      ((o-raw "absolute" whole) (o-raw "absolute-stream" stream)))
     ("PROXY_SERVICE_NAME" (("PROXY_SERVICE_NAME" . "svc")) ((o-raw "absolute" whole) (o-tls "connect" whole)))
     ("SOCKS5_AUTH" (("SOCKS5_AUTH" . 1)) ((o-raw "absolute" whole) (o-tls "connect" whole)))
     ("HAPROXYPROTOCOL" (("HAPROXYPROTOCOL" . 1)) ((o-raw "absolute" whole) (o-tls "connect" whole)))
     ("HAPROXYPROTOCOL-tunnel" (("HAPROXYPROTOCOL" . 1) ("HTTPPROXYTUNNEL" . 1)) ((o-raw "absolute" whole)))
     ("HAPROXY_CLIENT_IP" (("HAPROXYPROTOCOL" . 1) ("HAPROXY_CLIENT_IP" . "10.1.2.3"))
      ((o-raw "absolute" whole) (o-tls "connect" whole))))))

;; --- item 7: prior knowledge through a named proxy -------------------------------------------

(define (part-pk)
  (for-each
   (lambda (row)
     (single "i7" (list (cons 'case (car row)))
       (lambda (tag) (make-req (url 'o-h2c (path-of tag)) 'get #f (cadr row) (caddr row)
                               'http-version 'http/2-prior-knowledge))))
   `(("direct" #f ())
     ("plain-proxy" ,(purl 'p-open "") ())
     ("tunnel" ,(purl 'p-open "") (("HTTPPROXYTUNNEL" . 1))))))

;; --- item 8: the high level ------------------------------------------------------------------

(define (hl-case alist session-keys call)
  (in-case "i8" alist
    (lambda (tag)
      (let* ((s (apply make-http-session 'ca-file ca 'timeout-ms (bound 10000) session-keys))
             (t0 (now-ns))
             (o (guard (e (#t e)) (call s tag))))
        (http-session-close s)
        (list (cons (list '(step . 1) (cons 'ms (ms-since t0))) o))))))

(define (part-hl)
  (let ((alice (purl 'p-basic "alice:s3cret@"))
        (bob (purl 'p-basic "bob:hunter2@"))
        (go (lambda (target) (string-append "&go=" (pct target)))))
    ;; the session's proxy, and a call's
    (hl-case '((case . "session-proxy") (origin . "http")) (list 'proxy alice)
             (lambda (s tag) (http-get s (url 'o-raw (path-of tag)))))
    (hl-case '((case . "session-proxy") (origin . "https")) (list 'proxy alice)
             (lambda (s tag) (http-get s (url 'o-tls (path-of tag)))))
    (hl-case '((case . "call-proxy-other") (origin . "http")) (list 'proxy alice)
             (lambda (s tag) (http-get s (url 'o-raw (path-of tag)) 'proxy bob)))
    (hl-case '((case . "call-proxy-other") (origin . "https")) (list 'proxy alice)
             (lambda (s tag) (http-get s (url 'o-tls (path-of tag)) 'proxy bob)))
    (hl-case '((case . "call-proxy-none") (origin . "http")) (list 'proxy alice)
             (lambda (s tag) (http-get s (url 'o-raw (path-of tag)) 'proxy #f)))
    (hl-case '((case . "call-proxy-environment") (origin . "http")) (list 'proxy alice)
             (lambda (s tag) (http-get s (url 'o-raw (path-of tag)) 'proxy 'environment)))
    (hl-case '((case . "call-proxy-on-none-session") (origin . "http")) (list 'proxy #f)
             (lambda (s tag) (http-get s (url 'o-raw (path-of tag)) 'proxy alice)))
    ;; redirects through the proxy
    (for-each
     (lambda (row)
       (hl-case (list '(case . "redirect") (cons 'to (car row))) (list 'proxy alice)
                (lambda (s tag) (http-get s (string-append (url 'o-raw (path-of tag)) (go ((cadr row) tag)))))))
     (list (list "same-origin" (lambda (tag) (url 'o-raw (string-append (path-of tag) "&hop=2"))))
           (list "other-http" (lambda (tag) (url 'o-raw2 (string-append (path-of tag) "&hop=2"))))
           (list "other-https" (lambda (tag) (url 'o-tls (string-append (path-of tag) "&hop=2"))))))
    ;; credentials beside proxy userinfo, at the origin
    (for-each
     (lambda (scheme)
       (for-each
        (lambda (origin)
          (hl-case (list '(case . "credentials") (cons 'scheme scheme) (cons 'origin (scheme-of origin)))
                   (list 'proxy alice 'credentials (list scheme "ouser" "opass"))
                   (lambda (s tag) (http-get s (url origin (string-append (path-of tag) "&ch=" (symbol->string scheme)))))))
        '(o-raw o-tls)))
     '(basic digest))
    ;; credentials across a redirect to another origin, and within one
    (for-each
     (lambda (row)
       (hl-case (list '(case . "credentials-redirect") '(scheme . basic) (cons 'to (car row)))
                (list 'proxy alice 'credentials '(basic "ouser" "opass"))
                (lambda (s tag) (http-get s (string-append (url 'o-raw (string-append (path-of tag) "&ch=basic"))
                                                           (go ((cadr row) tag)))))))
     (list (list "same-origin" (lambda (tag) (url 'o-raw (string-append (path-of tag) "&hop=2&ch=basic"))))
           (list "other-http" (lambda (tag) (url 'o-raw2 (string-append (path-of tag) "&hop=2"))))
           (list "other-https" (lambda (tag) (url 'o-tls (string-append (path-of tag) "&hop=2"))))))))

;; pct : String -> String
;; S's UTF-8 bytes, each but A-Z a-z 0-9 - . _ ~ as %HH.
(define (pct s)
  (apply string-append
         (map (lambda (b)
                (if (or (<= 65 b 90) (<= 97 b 122) (<= 48 b 57) (memv b '(45 46 95 126)))
                    (string (integer->char b))
                    (string-append "%" (if (< b 16) "0" "") (string-upcase (number->string b 16)))))
              (bytevector->u8-list (string->utf8 s)))))

;; --- item 9: the sent rule -------------------------------------------------------------------

(define (part-sent)
  (for-each
   (lambda (row)
     (for-each
      (lambda (method)
        (for-each
         (lambda (limit)
           (single "i9" (list (cons 'route (car row)) (cons 'method method) (cons 'limit (or limit "none")))
             (lambda (tag)
               (apply make-req (url (cadr row) (path-of tag)) method (and (eq? method 'post) post-body)
                      (caddr row) '()
                      (if limit (list 'body-limit limit) '())))))
         '(#f 1)))
      '(get post)))
   `(("direct-http" o-raw #f)
     ("direct-https" o-tls #f)
     ("absolute-open" o-raw ,(purl 'p-open ""))
     ("connect-open" o-tls ,(purl 'p-open ""))
     ("absolute-basic" o-raw ,(purl 'p-basic "alice:s3cret@"))
     ("connect-basic" o-tls ,(purl 'p-basic "alice:s3cret@")))))

;; --- the wire check's cases -------------------------------------------------------------------

(define (part-wire)
  (for-each
   (lambda (row)
     (let ((tag-holder #f))
       (in-case "wire" (list (cons 'case (car row)))
         (lambda (tag)
           (say "verbose-begin ~a" tag)
           (let ((o (with-engine
                     (lambda (e)
                       (run e (make-req (url (cadr row) (path-of tag)) 'get #f (caddr row)
                                        (append (cadddr row) '(("VERBOSE" . 1)))))))))
             (flush-output-port (current-error-port))
             (say "verbose-end ~a" tag)
             (list (cons '((step . 1)) o)))))))
   `(("absolute-basic" o-raw ,(purl 'p-basic "alice:s3cret@") ())
     ("connect-basic" o-tls ,(purl 'p-basic "alice:s3cret@") ())
     ("tunnel-basic" o-raw ,(purl 'p-basic "bob:hunter2@") (("HTTPPROXYTUNNEL" . 1)))
     ("absolute-bytes" o-raw ,(purl 'p-open "u%FFx:p%7Fq@") ())
     ("connect-utf8" o-tls ,(purl 'p-open "%C3%A9l%C3%A8ve:p%C3%A4ss@") ())
     ("absolute-https-proxy" o-raw ,(purl 'tp-basic "alice:s3cret@") ,(proxy-ca ca)))))

;; --- the parts -----------------------------------------------------------------------------------

(say "~a" (environment-line))
(say-libcurl)
(set! log-engine (make-curl-engine))
(case part
  ((refusals) (part-refusals))
  ((setopts) (part-setopts))
  ((urlparse) (part-urlparse))
  ((named) (part-named))
  ((userinfo) (part-userinfo))
  ((ports) (part-ports))
  ((pooled) (part-pooled))
  ((refused) (part-refused))
  ((tls) (part-tls))
  ((tlsenv) (part-tlsenv))
  ((stall) (part-stall))
  ((twins) (part-twins))
  ((pk) (part-pk))
  ((hl) (part-hl))
  ((sent) (part-sent))
  ((wire) (part-wire))
  (else (error 'proxy.sps "no such part" part)))
(curl-engine-stop log-engine)
(say-native)
(say "part ~a done" part)
