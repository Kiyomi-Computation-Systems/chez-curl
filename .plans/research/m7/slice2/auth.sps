#!chezscheme
;;; M7 slice 2's measurements (2026-11-02; the M7 plan, section 5.1),
;;; through chez-curl's engine: credentials by the hatch, on the prototype
;;; (make-prototype.sh), but for the parts that run on main's src/.
;;;
;;;   scheme --libdirs LIBDIRS --program auth.sps PART KEY=VALUE ...
;;;
;;; run.sh passes the KEYs: tmp, the run's temp directory; ca, the run CA;
;;; slow, a multiplier for every bound (1 natively, more under Valgrind);
;;; and the stand-in's ports: http, httpb, https, h2, ctl (standin.mjs).
;;; Every request carries ca-file and timeout-ms 10,000 unless named, and
;;; each transfer is waited on for 15,000 ms at most, then cancelled
;;; ("hung"). Every bound is multiplied by slow.
;;;
;;; PART is one of:
;;;   refusals  the hatch's answers to what the prototype unowns, and to the
;;;             options measured: run on main's src/ and on the prototype.
;;;   schemes   item 1: each scheme, each case, get and post, each face.
;;;   wire      the wire check's cases: libcurl's own trace (VERBOSE) beside
;;;             the stand-in's log (wire.mjs compares them).
;;;   streams   item 2: Basic, Bearer and Digest beside a streamed body and
;;;             a streamed response.
;;;   empty     item 3: empty user, password and token.
;;;   bytes     item 4: hostile and edge bytes, and lengths.
;;;   bytestrace  item 4's control bytes over h2, with libcurl's own trace.
;;;   rounds    item 5: Expect, stale, and the private follow.
;;;   pooled    item 6: transfers on one engine, the connections they use.
;;;   twins     item 7: the options beside each scheme.
;;;   hops      item 8: a redirect's hops built by hand, as next-request would.
;;;   origin    item 8: today's origin rule, by the pure functions (main's src/).
;;;
;;; Each transfer prints one "t" line: the item, its case's fields, its tag
;;; and "=>" what it ended with; then the stand-in's log for the tag, each
;;; line "s TAG ...". Each part ends with a "native" line.
(import (chezscheme)
        (curl)
        (curl unsupported)
        (only (curl private engine) call-with-engine-held)
        (only (curl private counters) native-counts)
        (only (curl private transfer) curl-request-following)
        (only (http-client private exchange) make-exchange exchange-submission exchange-step
              make-http-response))

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
           (unless kv (error 'auth.sps "not KEY=VALUE" a))
           (cons (string->symbol (car kv)) (cdr kv))))
       (cdr args)))

(define (setting key)
  (let ((hit (assq key settings)))
    (unless hit (error 'auth.sps "no such argument" key))
    (cdr hit)))

(define ca (setting 'ca))
(define tmp (setting 'tmp))
(define slow (string->number (setting 'slow)))
(define (bound ms) (* ms slow))

(define (say fmt . xs)
  (apply printf fmt xs)
  (newline)
  (flush-output-port (current-output-port)))

(define (ns-of t) (+ (* (time-second t) 1000000000) (time-nanosecond t)))
(define (now-ns) (ns-of (current-time 'time-monotonic)))
(define (ms-since t0) (/ (round (/ (- (now-ns) t0) 100000)) 10.0))

;; --- bytes, URLs ------------------------------------------------------------------

(define (hex bv)
  (apply string-append
         (map (lambda (b) (string-append (if (< b 16) "0" "") (number->string b 16)))
              (bytevector->u8-list bv))))

(define (bytes-of x) (if (string? x) (string->utf8 x) x))

;; pct : String -> String
;; S's UTF-8 bytes, each but A-Z a-z 0-9 - . _ ~ as %HH.
(define (pct s)
  (apply string-append
         (map (lambda (b)
                (if (or (<= 65 b 90) (<= 97 b 122) (<= 48 b 57) (memv b '(45 46 95 126)))
                    (string (integer->char b))
                    (string-append "%" (if (< b 16) "0" "") (string-upcase (number->string b 16)))))
              (bytevector->u8-list (string->utf8 s)))))

;; pattern-bytes : Natural Natural -> Bytevector
;; N bytes from OFFSET of the body pattern, byte i = i mod 251.
(define (pattern-bytes offset n)
  (let ((bv (make-bytevector n)))
    (do ((i 0 (+ i 1))) ((= i n) bv)
      (bytevector-u8-set! bv i (mod (+ offset i) 251)))))

;; pattern26 : Natural -> String
;; N chars a to z, char i being a + i mod 26: the stand-in's plen and tlen.
(define (pattern26 n)
  (let ((s (make-string n)))
    (do ((i 0 (+ i 1))) ((= i n) s)
      (string-set! s i (integer->char (+ 97 (mod i 26)))))))

(define hosts '((ip . "127.0.0.1") (name . "localhost") (v6 . "[::1]")))
(define (host-of h) (cdr (assq h hosts)))
(define (origin scheme host face) (string-append scheme "://" (host-of host) ":" (setting face)))

;; query : (Listof (Pairof String String)) -> String
(define (query params)
  (let loop ((ps params) (acc ""))
    (if (null? ps)
        acc
        (loop (cdr ps) (string-append acc (if (string=? acc "") "" "&") (caar ps) "=" (cdar ps))))))

;; faces: name, scheme, port key.
(define faces '((http "http" http) (https "https" https) (h2 "https" h2) (httpb "http" httpb)))
(define (face-scheme f) (cadr (assq f faces)))
(define (face-port f) (caddr (assq f faces)))

;; route-url : Symbol Symbol String (Listof (Pairof String String)) String -> String
;; FACE's URL at HOST, PATH, with PARAMS and the tag.
(define (route-url face host path params tag)
  (string-append (origin (face-scheme face) host (face-port face)) path "?"
                 (query (append params (list (cons "tag" tag))))))

;; --- credentials ------------------------------------------------------------------

(define curlauth-basic 1)
(define curlauth-digest 2)
(define curlauth-bearer 64)

;; cred-options : Symbol Any Any Any -> (Listof (Pairof String Any))
;; The hatch's options for SCHEME, as the credentials field would set them:
;; HTTPAUTH, then USERNAME and PASSWORD, or XOAUTH2_BEARER.
(define (cred-options scheme user pass token)
  (case scheme
    ((basic) (list (cons "HTTPAUTH" curlauth-basic) (cons "USERNAME" user) (cons "PASSWORD" pass)))
    ((digest) (list (cons "HTTPAUTH" curlauth-digest) (cons "USERNAME" user) (cons "PASSWORD" pass)))
    ((bearer) (list (cons "HTTPAUTH" curlauth-bearer) (cons "XOAUTH2_BEARER" token)))
    ((none) '())
    (else (error 'cred-options "no such scheme" scheme))))

;; account : Any Any Any -> (Listof (Pairof String String))
;; The stand-in's account for USER, PASS and TOKEN, as hex bytes.
(define (account user pass token)
  (list (cons "uh" (hex (bytes-of user))) (cons "ph" (hex (bytes-of pass))) (cons "th" (hex (bytes-of token)))))

(define (scheme-ch scheme) (case scheme ((basic) "basic") ((digest) "digest") ((bearer) "bearer") (else "open")))

;; --- requests, transfers, outcomes ------------------------------------------------

;; make-req : String Symbol Any (Listof Option) Any ... -> (U Request Condition)
;; URL's request of METHOD, with BODY when not #f, ca-file, timeout-ms
;; 10,000 unless KEYS name one, KEYS, then OPTIONS through the hatch; or
;; what raised.
(define (make-req url method body options . keys)
  (guard (e (#t e))
    (let* ((base (apply make-curl-request url 'ca-file ca 'method method
                        (append (if (memq 'timeout-ms keys) '() (list 'timeout-ms (bound 10000)))
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

;; render : Bytevector -> String
;; BYTES as the stand-in escapes them: printable ASCII as is, \ and "
;; escaped, any other byte as \xHH; past 300 bytes, cut, with the count.
(define (render bytes)
  (let ((out (open-output-string)) (n (min 300 (bytevector-length bytes))))
    (do ((i 0 (+ i 1))) ((= i n))
      (let ((b (bytevector-u8-ref bytes i)))
        (cond ((= b 92) (put-string out "\\\\"))
              ((= b 34) (put-string out "\\\""))
              ((and (>= b 32) (< b 127)) (put-char out (integer->char b)))
              (else (put-string out (string-append "\\x" (if (< b 16) "0" "") (number->string b 16)))))))
    (when (> (bytevector-length bytes) n)
      (put-string out (format "...(~a bytes)" (bytevector-length bytes))))
    (get-output-string out)))

(define (class-of e)
  (cond ((curl-timeout? e) 'timeout) ((curl-connect-error? e) 'connect)
        ((curl-send-receive-error? e) 'send-receive) ((curl-tls-error? e) 'tls)
        ((curl-protocol-error? e) 'protocol) ((curl-too-large? e) 'too-large)
        (else 'base)))

(define (condition-text c)
  (call-with-string-output-port (lambda (p) (display-condition c p))))

(define (header-of headers name)
  (let loop ((hs headers))
    (cond ((null? hs) #f)
          ((string-ci=? (caar hs) name) (cdar hs))
          (else (loop (cdr hs))))))

;; describe : (U Response Condition 'hung) -> String
(define (describe o)
  (cond ((curl-response? o)
         (format "ok status=~a version=~a location=~s body-bytes=~a"
                 (curl-response-status o) (curl-response-http-version o)
                 (or (header-of (curl-response-headers o) "location") "-")
                 (let ((b (curl-response-body o))) (if b (bytevector-length b) "#f"))))
        ((curl-transfer-error? o)
         (format "fail reason=~a code=~a class=~a sent=~a option=~a strerror=~s errbuf=~s"
                 (curl-transfer-error-reason o) (curl-transfer-error-code o) (class-of o)
                 (curl-transfer-error-request-size o) (curl-transfer-error-option o)
                 (curl-transfer-error-strerror o) (curl-transfer-error-error-buffer o)))
        ((curl-request-error? o)
         (format "refused field=~a reason=~a value=~s" (curl-request-error-field o)
                 (curl-request-error-reason o)
                 (let ((v (curl-request-error-value o))) (if (and (string? v) (> (string-length v) 80)) "(long)" v))))
        ((condition? o) (format "condition ~s" (condition-text o)))
        ((eq? o 'hung) "hung")
        (else (format "other ~s" o))))

;; fields->text : (Listof (Pairof Symbol Any)) -> String
(define (fields->text alist)
  (let loop ((ps alist) (acc ""))
    (if (null? ps)
        acc
        (loop (cdr ps) (string-append acc (if (string=? acc "") "" " ") (symbol->string (caar ps)) "="
                                      (let ((v (cdar ps))) (if (string? v) v (format "~a" v))))))))

;; --- tags and the stand-in's log ----------------------------------------------------

(define tag-n 0)
(define (fresh-tag)
  (set! tag-n (+ tag-n 1))
  (format "~a~a" part tag-n))

(define log-engine #f)

;; show-log : String -> Void
;; The stand-in's log for TAG, from its ctl face, each line "s TAG LINE".
(define (show-log tag)
  (let* ((url (string-append "http://127.0.0.1:" (setting 'ctl) "/log?tag=" tag))
         (o (run log-engine (make-req url 'get #f '() 'proxy #f))))
    (if (and (curl-response? o) (curl-response-body o))
        (for-each (lambda (line) (unless (string=? line "") (say "s ~a ~a" tag line)))
                  (split-lines (utf8->string (curl-response-body o))))
        (say "s ~a log-fetch-failed ~a" tag (describe o)))))

(define (split-lines s)
  (let loop ((cs (string->list s)) (cur '()) (acc '()))
    (cond ((null? cs) (reverse (if (null? cur) acc (cons (list->string (reverse cur)) acc))))
          ((char=? (car cs) #\newline) (loop (cdr cs) '() (cons (list->string (reverse cur)) acc)))
          (else (loop (cdr cs) (cons (car cs) cur) acc)))))

;; report : String Alist String Any String -> Void
(define (report item alist tag outcome extra)
  (say "t ~a ~a tag=~a~a => ~a" item (fields->text alist) tag (if (string=? extra "") "" (string-append " " extra))
       (describe outcome))
  (show-log tag))

;; one-case : String Alist (String -> (U Request Condition)) -> Any
;; A transfer of the request MAKE builds for a fresh tag, on an engine of
;; its own, reported.
(define (one-case item alist make)
  (let* ((tag (fresh-tag))
         (t0 (now-ns))
         (o (with-engine (lambda (e) (run e (make tag))))))
    (report item alist tag o (format "ms=~a" (ms-since t0)))
    o))

(define (say-libcurl)
  (let ((info (loaded-libcurl)))
    (say "libcurl version=~a ssl=~s path=~a part=~a" (libcurl-info-version info)
         (libcurl-info-ssl-version info) (libcurl-info-path info) part)))

(define (say-native) (say "native ~s" (native-counts)))

;; --- the hatch's answers (both trees) -------------------------------------------------

(define (attach url keys options)
  (guard (e (#t e))
    (let ((base (apply make-curl-request url keys)))
      (curl-request-with-options base options)
      'attached)))

(define (part-refusals)
  (let ((url (route-url 'http 'ip "/auth" '(("ch" . "open")) "refusals")))
    (for-each
     (lambda (row)
       (let ((o (attach url (cadr row) (caddr row))))
         (say "r case=~a => ~a" (car row) (if (eq? o 'attached) "attached" (describe o)))))
     `((USERNAME () (("USERNAME" . "user")))
       (PASSWORD () (("PASSWORD" . "pass")))
       (HTTPAUTH () (("HTTPAUTH" . 1)))
       (HTTPAUTH-beside-stream-buffer (stream-buffer 4096) (("HTTPAUTH" . 2)))
       (HTTPAUTH-beside-body-stream (method post body stream) (("HTTPAUTH" . 2)))
       (PROXYAUTH-beside-stream-buffer (stream-buffer 4096) (("PROXYAUTH" . 1)))
       (XOAUTH2_BEARER () (("XOAUTH2_BEARER" . "tok")))
       (AWS_SIGV4 () (("AWS_SIGV4" . "aws:amz:us-east-1:s3")))
       (XOAUTH2_BEARER-CR () (("XOAUTH2_BEARER" . ,(string #\a #\return #\b))))
       (XOAUTH2_BEARER-LF () (("XOAUTH2_BEARER" . ,(string #\a #\newline #\b))))
       (XOAUTH2_BEARER-NUL () (("XOAUTH2_BEARER" . ,(string #\a #\nul #\b))))
       (XOAUTH2_BEARER-bytes () (("XOAUTH2_BEARER" . ,(bytevector 97 13 10 98))))
       (XOAUTH2_BEARER-bytes-NUL () (("XOAUTH2_BEARER" . ,(bytevector 97 0 98))))
       (USERNAME-bytes () (("USERNAME" . ,(bytevector 97 255 98))))
       (LOGIN_OPTIONS () (("LOGIN_OPTIONS" . "AUTH=*")))
       (DISALLOW_USERNAME_IN_URL () (("DISALLOW_USERNAME_IN_URL" . 1)))
       (UNRESTRICTED_AUTH () (("UNRESTRICTED_AUTH" . 1)))
       (NETRC_FILE () (("NETRC_FILE" . "/nonexistent")))
       (NETRC () (("NETRC" . 1)))
       (SASL_AUTHZID () (("SASL_AUTHZID" . "authz")))
       (SASL_IR () (("SASL_IR" . 1)))
       (SERVICE_NAME () (("SERVICE_NAME" . "svc")))
       (KEEP_SENDING_ON_ERROR () (("KEEP_SENDING_ON_ERROR" . 1)))
       (FAILONERROR () (("FAILONERROR" . 1)))
       (USERPWD () (("USERPWD" . "user:pass")))
       (PROXYAUTH () (("PROXYAUTH" . 1)))))))

;; --- item 1: each scheme --------------------------------------------------------------

(define digest-algs '("MD5" "MD5-sess" "SHA-256" "SHA-256-sess" "SHA-512-256"))

;; item1-schemes : (Listof (List String Symbol (Listof (Pairof String String))))
;; Each scheme's name, its credentials' scheme, and its challenge's params.
(define item1-schemes
  (append (list (list "basic" 'basic '()))
          (apply append
                 (map (lambda (alg)
                        (map (lambda (qop) (list (format "digest-~a-~a" alg qop) 'digest
                                                 (list (cons "alg" alg) (cons "qop" qop))))
                             '("auth" "none")))
                      digest-algs))
          (list (list "bearer" 'bearer '()))))

;; the-challenge : Symbol Symbol Params -> Params
;; The route's ch and challenge params for CASE under SCHEME.
(define (the-challenge scheme kase params)
  (case kase
    ((right wrong) (cons (cons "ch" (scheme-ch scheme)) params))
    ((other) (list (cons "ch" (if (eq? scheme 'basic) "digest" "basic"))))
    ((none) '(("ch" . "none")))
    ((open) '(("ch" . "open")))
    (else (error 'the-challenge "no such case" kase))))

(define (item1-options scheme kase)
  (if (eq? kase 'wrong)
      (cred-options scheme "user" "wrong" "wrong")
      (cred-options scheme "user" "pass" "tok123")))

(define (part-schemes)
  (for-each
   (lambda (face)
     (for-each
      (lambda (s)
        (for-each
         (lambda (kase)
           (for-each
            (lambda (method)
              (one-case "i1" (list (cons 'scheme (car s)) (cons 'case kase) (cons 'method method) (cons 'face face))
                (lambda (tag)
                  (make-req (route-url face 'ip "/auth" (append (the-challenge (cadr s) kase (caddr s))
                                                                (account "user" "pass" "tok123"))
                                       tag)
                            method (and (eq? method 'post) (pattern-bytes 0 1024))
                            (item1-options (cadr s) kase)))))
            '(get post)))
         '(right wrong other none open)))
      item1-schemes))
   '(http https h2)))

;; --- the wire check's cases ------------------------------------------------------------

(define (part-wire)
  (for-each
   (lambda (face)
     (for-each
      (lambda (s)
        (for-each
         (lambda (method)
           (let ((tag (fresh-tag)))
             (say "verbose-begin ~a" tag)
             (let ((o (with-engine
                       (lambda (e)
                         (run e (make-req (route-url face 'ip "/auth" (append (cons (cons "ch" (scheme-ch (cadr s))) (caddr s))
                                                                              (account "user" "pass" "tok123"))
                                                     tag)
                                          method (and (eq? method 'post) (pattern-bytes 0 1024))
                                          (append (cred-options (cadr s) "user" "pass" "tok123")
                                                  '(("VERBOSE" . 1)))))))))
               (flush-output-port (current-error-port))
               (say "verbose-end ~a" tag)
               (report "wire" (list (cons 'scheme (car s)) (cons 'method method) (cons 'face face)) tag o ""))))
         '(get post)))
      (list (list "basic" 'basic '()) (list "digest-MD5-auth" 'digest '(("alg" . "MD5") ("qop" . "auth")))
            (list "digest-SHA-256-none" 'digest '(("alg" . "SHA-256") ("qop" . "none")))
            (list "bearer" 'bearer '()))))
   '(http https)))

;; --- item 2: streams ---------------------------------------------------------------------

(define stream-total 262144)
(define stream-piece 16384)

;; stream-body : Engine (U Request Condition) -> String
;; REQUEST, whose body streams, submitted on ENGINE: pieces of the pattern
;; put, each bounded at 3,000 ms, until one is not taken, then the end;
;; the outcome awaited. Answers (EXTRA . OUTCOME): the line's extra fields
;; and the outcome.
(define (stream-body engine req)
  (if (condition? req)
      (cons "" req)
      (let* ((t0 (now-ns)) (token (curl-submit engine req)))
        (let loop ((i 0))
          (if (< (* i stream-piece) stream-total)
              (let ((a (curl-token-put-piece! token (pattern-bytes (* i stream-piece) stream-piece) (bound 3000))))
                (if (eq? a #t)
                    (loop (+ i 1))
                    (let* ((at (ms-since t0)) (o (await token)))
                      (cons (format "puts=~a last-put=~a last-at=~a count=~a ms=~a" i a at
                                      (curl-token-body-count token) (ms-since t0))
                              o))))
              (let ((at (ms-since t0)))
                (curl-token-end-body! token)
                (let ((o (await token)))
                  (cons (format "puts=~a last-put=end last-at=~a count=~a ms=~a" i at (curl-token-body-count token)
                                  (ms-since t0))
                          o))))))))

;; stream-response : Engine (U Request Condition) -> String
;; REQUEST, whose response streams: its head, then every piece, each wait
;; bounded at 5,000 ms, the pattern checked; the outcome awaited. Answers
;; (EXTRA . OUTCOME).
(define (stream-response engine req)
  (if (condition? req)
      (cons "" req)
      (let* ((t0 (now-ns)) (token (curl-submit engine req))
             (arrived (curl-token-head-wait token (bound 5000)))
             (head (curl-token-head token)))
        (let loop ((n 0) (good #t))
          (let ((p (curl-token-next-piece token (bound 5000))))
            (cond ((bytevector? p)
                   (loop (+ n (bytevector-length p))
                         (and good (bytevector=? p (pattern-bytes n (bytevector-length p))))))
                  (else
                   (let ((o (if (eof-object? p) (await token) (begin (curl-token-cancel token) (await token) 'hung))))
                     (cons (format "head=~a read=~a pattern=~a end=~a ms=~a"
                                     (if head (curl-head-status head) (if arrived "ended" "none"))
                                     n (if good "ok" "bad") (if (eof-object? p) "eof" "timeout") (ms-since t0))
                             o)))))))))

;; stream-case : String Alist Symbol Symbol Symbol Params Options -> Void
(define (stream-case item alist face kind scheme params options)
  (let* ((tag (fresh-tag))
         (url (route-url face 'ip "/auth" (append params (list (cons "size" (number->string stream-total)))) tag)))
    (let* ((answer
                  (with-engine
                   (lambda (e)
                     (case kind
                       ((sized) (stream-body e (make-req url 'post 'stream options 'body-length stream-total
                                                         'timeout-ms (bound 10000))))
                       ((chunked) (stream-body e (make-req url 'post 'stream options 'timeout-ms (bound 10000))))
                       ((response) (stream-response e (make-req url 'get #f options 'stream-buffer 4096
                                                                'timeout-ms (bound 10000))))
                       (else (error 'stream-case "no such kind" kind))))))
           (extra (car answer)) (o (cdr answer)))
      (report item alist tag o extra))))

(define (part-streams)
  ;; (a) Basic and Bearer, the right credentials.
  (for-each
   (lambda (face)
     (for-each
      (lambda (scheme)
        (for-each
         (lambda (kind)
           (stream-case "i2" (list (cons 'scheme scheme) (cons 'case 'right) (cons 'kind kind) (cons 'when 'normal)
                                   (cons 'face face))
                        face kind scheme
                        (cons (cons "ch" (scheme-ch scheme)) (account "user" "pass" "tok123"))
                        (cred-options scheme "user" "pass" "tok123")))
         '(sized chunked response)))
      '(basic bearer)))
   '(http h2))
  ;; (b) a wrong password or token: the stand-in answers as the head
  ;; arrives (early), once 64 KiB have arrived (mid), or after the body.
  (for-each
   (lambda (face)
     (for-each
      (lambda (scheme)
        (for-each
         (lambda (kind)
           (for-each
            (lambda (when)
              (stream-case "i2" (list (cons 'scheme scheme) (cons 'case 'wrong) (cons 'kind kind) (cons 'when when)
                                      (cons 'face face))
                           face kind scheme
                           (append (list (cons "ch" (scheme-ch scheme)))
                                   (case when ((early) '(("early" . "1"))) ((mid) '(("after" . "65536"))) (else '()))
                                   (account "user" "pass" "tok123"))
                           (cred-options scheme "user" "wrong" "wrong")))
            (if (eq? kind 'response) '(normal) '(early mid normal))))
         '(sized chunked response)))
      '(basic bearer)))
   '(http h2))
  ;; (c) Digest beside each, on the prototype: what digest-with-stream
  ;; would prevent. Every wait is bounded.
  (for-each
   (lambda (face)
     (for-each
      (lambda (kind)
        (for-each
         (lambda (kase)
           (for-each
            (lambda (when)
              (stream-case "i2" (list (cons 'scheme 'digest) (cons 'case kase) (cons 'kind kind) (cons 'when when)
                                      (cons 'face face))
                           face kind 'digest
                           (append '(("ch" . "digest")) (if (eq? when 'early) '(("early" . "1")) '())
                                   (account "user" "pass" "tok123"))
                           (cred-options 'digest "user" (if (eq? kase 'right) "pass" "wrong") "x")))
            (if (eq? kind 'response) '(normal) '(normal early))))
         '(right wrong)))
      '(sized chunked response)))
   '(http h2)))

;; --- item 3: empty values ------------------------------------------------------------------

(define (part-empty)
  (for-each
   (lambda (face)
     (for-each
      (lambda (c)
        (let ((scheme (car c)) (user (cadr c)) (pass (caddr c)) (token (cadddr c)))
          (one-case "i3" (list (cons 'scheme scheme) (cons 'user (if (string=? user "") "empty" "user"))
                               (cons 'pass (if (string=? pass "") "empty" "pass"))
                               (cons 'token (if (string=? token "") "empty" "tok")) (cons 'face face))
            (lambda (tag)
              (make-req (route-url face 'ip "/auth" (cons (cons "ch" (scheme-ch scheme)) (account user pass token)) tag)
                        'get #f (cred-options scheme user pass token))))))
      '((basic "" "" "-") (basic "user" "" "-") (basic "" "pass" "-")
        (digest "" "" "-") (digest "user" "" "-") (digest "" "pass" "-")
        (bearer "-" "-" ""))))
   '(http h2)))

;; --- item 4: hostile and edge bytes, and lengths --------------------------------------------

;; byte-cases : (Listof (Pairof String Bytevector))
;; Each case's name and the bytes it puts between a and b. x is the
;; neighbour that passes; crlf-header CR LF and a header of its own.
(define byte-cases
  (list (cons "x" (bytevector 120)) (cons "01" (bytevector 1)) (cons "tab" (bytevector 9))
        (cons "lf" (bytevector 10)) (cons "cr" (bytevector 13)) (cons "1f" (bytevector 31))
        (cons "sp" (bytevector 32)) (cons "dquote" (bytevector 34)) (cons "comma" (bytevector 44))
        (cons "colon" (bytevector 58)) (cons "backslash" (bytevector 92)) (cons "7f" (bytevector 127))
        (cons "80" (bytevector 128)) (cons "ff" (bytevector 255)) (cons "latin1-u-umlaut" (bytevector 252))
        (cons "utf8-u-umlaut" (bytevector 195 188))
        (cons "crlf-header" (string->utf8 "\r\nX-Injected: 1"))))

(define (around bv) (bv-append (bytevector 97) bv (bytevector 98)))
(define (bv-append . bvs)
  (let* ((n (apply + (map bytevector-length bvs))) (out (make-bytevector n)))
    (let loop ((bvs bvs) (at 0))
      (if (null? bvs)
          out
          (begin (bytevector-copy! (car bvs) 0 out at (bytevector-length (car bvs)))
                 (loop (cdr bvs) (+ at (bytevector-length (car bvs)))))))))

(define (part-bytes)
  (for-each
   (lambda (face)
     ;; each byte in the user, the password and the token, under each scheme
     ;; it reaches, by the prototype's byte seam
     (for-each
      (lambda (target)
        (let ((field (car target)) (scheme (cadr target)))
          (for-each
           (lambda (bc)
             (let* ((v (around (cdr bc)))
                    (user (if (eq? field 'user) v "user"))
                    (pass (if (eq? field 'pass) v "pass"))
                    (token (if (eq? field 'token) v "tok123")))
               (one-case "i4" (list (cons 'field field) (cons 'scheme scheme) (cons 'byte (car bc))
                                    (cons 'sent (hex v)) (cons 'face face))
                 (lambda (tag)
                   (make-req (route-url face 'ip "/auth" (cons (cons "ch" (scheme-ch scheme)) (account user pass token)) tag)
                             'get #f (cred-options scheme user pass token))))))
           byte-cases)))
      '((user basic) (user digest) (pass basic) (pass digest) (token bearer)))
     ;; a UTF-8 user name as a string, the hatch's own path, by USERNAME
     (for-each
      (lambda (scheme)
        (one-case "i4" (list (cons 'field 'user) (cons 'scheme scheme) (cons 'byte "utf8-string")
                             (cons 'sent (hex (string->utf8 "\x00FC;ser"))) (cons 'face face))
          (lambda (tag)
            (make-req (route-url face 'ip "/auth" (cons (cons "ch" (scheme-ch scheme)) (account "\x00FC;ser" "pass" "-")) tag)
                      'get #f (cred-options scheme "\x00FC;ser" "pass" "-")))))
      '(basic digest))
     ;; NUL: the hatch refuses it, a string's U+0000 and the seam's 0 byte
     (for-each
      (lambda (target)
        (for-each
         (lambda (v)
           (let* ((field (car target)) (scheme (cadr target))
                  (user (if (eq? field 'user) v "user")) (pass (if (eq? field 'pass) v "pass"))
                  (token (if (eq? field 'token) v "tok123")))
             (one-case "i4" (list (cons 'field field) (cons 'scheme scheme)
                                  (cons 'byte (if (string? v) "nul-string" "nul-bytes")) (cons 'sent "-") (cons 'face face))
               (lambda (tag)
                 (make-req (route-url face 'ip "/auth" (list (cons "ch" (scheme-ch scheme))) tag)
                           'get #f (cred-options scheme user pass token))))))
         (list (string #\a #\nul #\b) (bytevector 97 0 98))))
      '((user basic) (pass digest) (token bearer)))
     ;; lengths: a password under Basic and Digest, a token under Bearer
     (for-each
      (lambda (target)
        (for-each
         (lambda (n)
           (let* ((field (car target)) (scheme (cadr target)) (v (pattern26 n)))
             (one-case "i4len" (list (cons 'field field) (cons 'scheme scheme) (cons 'length n) (cons 'face face))
               (lambda (tag)
                 (make-req (route-url face 'ip "/auth"
                                      (list (cons "ch" (scheme-ch scheme))
                                            (cons (if (eq? field 'token) "tlen" "plen") (number->string n)))
                                      tag)
                           'get #f (cred-options scheme "user" (if (eq? field 'pass) v "pass")
                                                 (if (eq? field 'token) v "-")))))))
         '(8192 65536 1048576 8000000 8000001)))
      '((pass basic) (pass digest) (token bearer))))
   '(http h2)))

;; part-bytestrace: item 4's control bytes over h2 again, with libcurl's own
;; trace (VERBOSE) between verbose-begin and verbose-end lines, since the h2
;; face's HTTP/2 stack drops a field it finds invalid before the stand-in
;; sees it: what libcurl handed nghttp2, in its own words.
(define (part-bytestrace)
  (for-each
   (lambda (target)
     (for-each
      (lambda (bc)
        (let* ((field (car target)) (scheme (cadr target)) (v (around (cdr bc)))
               (user (if (eq? field 'user) v "user")) (token (if (eq? field 'token) v "tok123"))
               (tag (fresh-tag)))
          (say "verbose-begin ~a" tag)
          (let ((o (with-engine
                    (lambda (e)
                      (run e (make-req (route-url 'h2 'ip "/auth" (cons (cons "ch" (scheme-ch scheme)) (account user "pass" token)) tag)
                                       'get #f (append (cred-options scheme user "pass" token) '(("VERBOSE" . 1)))))))))
            (flush-output-port (current-error-port))
            (say "verbose-end ~a" tag)
            (report "i4trace" (list (cons 'field field) (cons 'scheme scheme) (cons 'byte (car bc)) '(face . h2)) tag o ""))))
      (filter (lambda (bc) (member (car bc) '("x" "01" "tab" "lf" "cr" "1f" "7f" "80"))) byte-cases)))
   '((user digest) (token bearer))))

;; --- item 5: requests inside one transfer ----------------------------------------------------

(define (part-rounds)
  ;; (b) a caller's Expect: 100-continue on a post with a 64 KiB body: the
  ;; stand-in answering 417 to every such request, to the first alone, or
  ;; (401) refusing a head that would fail before any 100
  (for-each
   (lambda (face)
     (for-each
      (lambda (scheme)
        (for-each
         (lambda (kase)
           (for-each
            (lambda (mode)
              (one-case "i5expect" (list (cons 'scheme scheme) (cons 'case kase) (cons 'mode mode) (cons 'face face))
                (lambda (tag)
                  (make-req (route-url face 'ip "/auth"
                                       (append (list (cons "ch" (scheme-ch scheme)))
                                               (case mode ((417) '(("expect" . "417"))) ((417once) '(("expect" . "417once")))
                                                 (else '()))
                                               (account "user" "pass" "tok123"))
                                       tag)
                            'post (pattern-bytes 0 65536)
                            (cred-options scheme "user" (if (eq? kase 'right) "pass" "wrong") (if (eq? kase 'right) "tok123" "wrong"))
                            'headers '(("Expect" . "100-continue")) 'timeout-ms (bound 5000)))))
            '(417 417once 401)))
         '(right wrong)))
      '(basic bearer digest)))
   '(http https h2))
  ;; (c) stale: the first valid request (or the first two) answered 401
  ;; again, Digest with stale=true
  (for-each
   (lambda (face)
     (for-each
      (lambda (c)
        (let ((scheme (car c)) (n (cadr c)))
          (one-case "i5stale" (list (cons 'scheme scheme) (cons 'stale n) (cons 'face face))
            (lambda (tag)
              (make-req (route-url face 'ip "/auth" (append (list (cons "ch" (scheme-ch scheme)) (cons "stale" (number->string n)))
                                                            (account "user" "pass" "tok123"))
                                   tag)
                        'get #f (cred-options scheme "user" "pass" "tok123"))))))
      '((digest 1) (digest 2) (basic 1) (bearer 1))))
   '(http h2))
  ;; (d) the private follow: a 302 from the first hop to TARGET, each scheme,
  ;; without and with UNRESTRICTED_AUTH 1
  (for-each
   (lambda (scheme)
     (for-each
      (lambda (t)
        (for-each
         (lambda (unrestricted)
           (one-case "i5follow" (list (cons 'scheme scheme) (cons 'target (car t)) (cons 'unrestricted unrestricted))
             (lambda (tag)
               (let* ((from-face (cadr t)) (from-host (caddr t)) (to-face (cadddr t)) (to-host (list-ref t 4))
                      (to-scheme (list-ref t 5))
                      (acct (cons (cons "ch" (scheme-ch scheme)) (account "user" "pass" "tok123")))
                      (target (string-append to-scheme "://" (host-of to-host) ":" (setting (face-port to-face))
                                             "/auth/next?" (query (append acct (list (cons "hop" "2") (cons "tag" tag))))))
                      (req (make-req (route-url from-face from-host "/auth" (append acct (list (cons "go" (pct target)))) tag)
                                     'get #f (append (cred-options scheme "user" "pass" "tok123")
                                                     (if (eq? unrestricted 'on) '(("UNRESTRICTED_AUTH" . 1)) '())))))
                 (if (condition? req) req (curl-request-following req))))))
         '(off on)))
      ;; name, from face, from host, to face, to host, to scheme
      '((same-origin http ip http ip "http")
        (other-port http ip httpb ip "http")
        (ip-to-localhost http ip http name "http")
        (localhost-to-ip http name http ip "http")
        (http-to-https-same-port http ip http ip "https")
        (http-to-https-face http ip https ip "https")
        (h2-same-origin h2 ip h2 ip "https"))))
   '(basic digest bearer)))

;; --- item 6: pooled connections ------------------------------------------------------------------

;; pooled-pair : String Alist Engine (String -> Request) (String -> Request) -> Void
;; Two transfers on ENGINE, one after the other, each reported.
(define (pooled-pair item alist engine make1 make2)
  (let* ((tag1 (fresh-tag)) (o1 (run engine (make1 tag1)))
         (tag2 (fresh-tag)) (o2 (run engine (make2 tag2))))
    (report item (append alist '((step . 1))) tag1 o1 "")
    (report item (append alist '((step . 2))) tag2 o2 "")))

(define (part-pooled)
  (for-each
   (lambda (face)
     ;; (a) Digest twice, one after the other
     (with-engine
      (lambda (e)
        (let ((mk (lambda (tag) (make-req (route-url face 'ip "/auth" (cons '("ch" . "digest") (account "user" "pass" "-")) tag)
                                          'get #f (cred-options 'digest "user" "pass" "-")))))
          (pooled-pair "i6" (list '(case . digest-twice) '(scheme . digest) (cons 'face face)) e mk mk))))
     ;; (b) other credentials on the pooled connection, (c) then none
     (for-each
      (lambda (scheme)
        (with-engine
         (lambda (e)
           (pooled-pair "i6" (list '(case . other-credentials) (cons 'scheme scheme) (cons 'face face)) e
                        (lambda (tag) (make-req (route-url face 'ip "/auth" (cons (cons "ch" (scheme-ch scheme)) (account "alice" "pw-a" "tok-a")) tag)
                                                'get #f (cred-options scheme "alice" "pw-a" "tok-a")))
                        (lambda (tag) (make-req (route-url face 'ip "/auth" (cons (cons "ch" (scheme-ch scheme)) (account "bob" "pw-b" "tok-b")) tag)
                                                'get #f (cred-options scheme "bob" "pw-b" "tok-b"))))))
        (with-engine
         (lambda (e)
           (pooled-pair "i6" (list '(case . then-none) (cons 'scheme scheme) (cons 'face face)) e
                        (lambda (tag) (make-req (route-url face 'ip "/auth" (cons (cons "ch" (scheme-ch scheme)) (account "alice" "pw-a" "tok-a")) tag)
                                                'get #f (cred-options scheme "alice" "pw-a" "tok-a")))
                        (lambda (tag) (make-req (route-url face 'ip "/auth" '(("ch" . "open")) tag) 'get #f '()))))))
      '(basic digest bearer)))
   '(http https h2))
  ;; (d) over h2: two with other credentials in one batch, then one after
  ;; the other's head
  (for-each
   (lambda (scheme)
     (with-engine
      (lambda (e)
        (let* ((tag1 (fresh-tag)) (tag2 (fresh-tag))
               (r1 (make-req (route-url 'h2 'ip "/auth" (cons (cons "ch" (scheme-ch scheme)) (account "alice" "pw-a" "tok-a")) tag1)
                             'get #f (cred-options scheme "alice" "pw-a" "tok-a")))
               (r2 (make-req (route-url 'h2 'ip "/auth" (cons (cons "ch" (scheme-ch scheme)) (account "bob" "pw-b" "tok-b")) tag2)
                             'get #f (cred-options scheme "bob" "pw-b" "tok-b")))
               (tokens (call-with-engine-held e (lambda () (let* ((t1 (curl-submit e r1)) (t2 (curl-submit e r2))) (list t1 t2)))))
               (o1 (await (car tokens))) (o2 (await (cadr tokens))))
          (report "i6" (list '(case . together) (cons 'scheme scheme) '(face . h2) '(step . 1)) tag1 o1 "")
          (report "i6" (list '(case . together) (cons 'scheme scheme) '(face . h2) '(step . 2)) tag2 o2 ""))))
     (with-engine
      (lambda (e)
        (let* ((tag1 (fresh-tag)) (tag2 (fresh-tag)) (t0 (now-ns))
               (t1 (curl-submit e (make-req (route-url 'h2 'ip "/auth" (append (list (cons "ch" (scheme-ch scheme)) '("size" . "1024") '("slow" . "1500"))
                                                                               (account "alice" "pw-a" "tok-a"))
                                                       tag1)
                                            'get #f (cred-options scheme "alice" "pw-a" "tok-a") 'stream-buffer 4096)))
               (arrived (curl-token-head-wait t1 (bound 5000)))
               (head (curl-token-head t1))
               (head-ms (ms-since t0))
               (o2 (run e (make-req (route-url 'h2 'ip "/auth" (cons (cons "ch" (scheme-ch scheme)) (account "bob" "pw-b" "tok-b")) tag2)
                                    'get #f (cred-options scheme "bob" "pw-b" "tok-b"))))
               (first-done (curl-token-done? t1)))
          (let loop ((n 0))
            (let ((p (curl-token-next-piece t1 (bound 5000))))
              (if (bytevector? p)
                  (loop (+ n (bytevector-length p)))
                  (let ((o1 (await t1)))
                    (report "i6" (list '(case . after-head) (cons 'scheme scheme) '(face . h2) '(step . 1)) tag1 o1
                            (format "head=~a head-ms=~a read=~a" (if head (curl-head-status head) (if arrived "ended" "none")) head-ms n))
                    (report "i6" (list '(case . after-head) (cons 'scheme scheme) '(face . h2) '(step . 2)) tag2 o2
                            (format "first-done-at-second-end=~a" first-done))))))))))
   '(basic digest bearer)))

;; --- item 7: the twins ------------------------------------------------------------------------------

(define (write-file! path text)
  (call-with-port (open-file-output-port path (file-options no-fail) (buffer-mode block) (native-transcoder))
    (lambda (p) (put-string p text))))

(define (part-twins)
  (let ((netrc (string-append tmp "/netrc")))
    (write-file! netrc "machine 127.0.0.1 login netuser password netpass\n")
    (let ((twin
           (lambda (name scheme params method body options . keys)
             (one-case "i7" (list (cons 'twin name) (cons 'scheme scheme))
               (lambda (tag)
                 (apply make-req (route-url 'http 'ip "/auth" params tag) method body options keys)))))
          (acct (account "user" "pass" "tok123")))
      (for-each
       (lambda (scheme)
         (let ((ch (cons (cons "ch" (scheme-ch scheme)) acct))
               (creds (cred-options scheme "user" "pass" "tok123")))
           (twin "control" scheme ch 'get #f creds)
           (twin "LOGIN_OPTIONS=AUTH=*" scheme ch 'get #f (append creds '(("LOGIN_OPTIONS" . "AUTH=*"))))
           (twin "LOGIN_OPTIONS=AUTH=PLAIN" scheme ch 'get #f (append creds '(("LOGIN_OPTIONS" . "AUTH=PLAIN"))))
           (twin "DISALLOW_USERNAME_IN_URL=1" scheme ch 'get #f (append creds '(("DISALLOW_USERNAME_IN_URL" . 1))))
           (twin "AWS_SIGV4-after" scheme '(("ch" . "open")) 'get #f (append creds '(("AWS_SIGV4" . "aws:amz:us-east-1:s3"))))
           (twin "FAILONERROR=1" scheme ch 'get #f (append creds '(("FAILONERROR" . 1))))
           (twin "FAILONERROR=1-wrong" scheme ch 'get #f (append (cred-options scheme "user" "wrong" "wrong") '(("FAILONERROR" . 1))))
           (twin "NETRC_FILE-beside" scheme ch 'get #f (append creds (list (cons "NETRC_FILE" netrc))))))
       '(basic digest bearer))
      ;; AWS_SIGV4 before HTTPAUTH Basic, and alone with a user and password
      (twin "AWS_SIGV4-before" 'basic '(("ch" . "open")) 'get #f
            (append '(("AWS_SIGV4" . "aws:amz:us-east-1:s3")) (cred-options 'basic "user" "pass" "-")))
      (twin "AWS_SIGV4-alone" 'none '(("ch" . "open")) 'get #f
            '(("USERNAME" . "user") ("PASSWORD" . "pass") ("AWS_SIGV4" . "aws:amz:us-east-1:s3")))
      ;; userinfo alone, with and without DISALLOW_USERNAME_IN_URL
      (for-each
       (lambda (c)
         (one-case "i7" (list (cons 'twin (car c)) (cons 'scheme (cadr c)))
           (lambda (tag)
             (make-req (string-append "http://user:pass@127.0.0.1:" (setting 'http) "/auth?"
                                      (query (append (list (cons "ch" (scheme-ch (cadr c)))) acct (list (cons "tag" tag)))))
                       'get #f (caddr c)))))
       '(("userinfo-control" basic ())
         ("userinfo-DISALLOW_USERNAME_IN_URL=1" basic (("DISALLOW_USERNAME_IN_URL" . 1)))
         ("userinfo-digest-control" digest (("HTTPAUTH" . 2)))
         ("userinfo-digest-DISALLOW_USERNAME_IN_URL=1" digest (("HTTPAUTH" . 2) ("DISALLOW_USERNAME_IN_URL" . 1)))))
      ;; NETRC_FILE alone, NETRC owned and unset: the file holds the host
      (let ((nacct (account "netuser" "netpass" "-")))
        (twin "NETRC_FILE-alone" 'none (cons '("ch" . "basic") nacct) 'get #f (list (cons "NETRC_FILE" netrc)))
        (twin "NETRC_FILE-HTTPAUTH-basic" 'basic (cons '("ch" . "basic") nacct) 'get #f
              (list (cons "HTTPAUTH" 1) (cons "NETRC_FILE" netrc)))
        (twin "NETRC_FILE-HTTPAUTH-digest" 'digest (cons '("ch" . "digest") nacct) 'get #f
              (list (cons "HTTPAUTH" 2) (cons "NETRC_FILE" netrc)))
        (one-case "i7" (list (cons 'twin "NETRC_FILE-userinfo-user") (cons 'scheme 'basic))
          (lambda (tag)
            (make-req (string-append "http://netuser@127.0.0.1:" (setting 'http) "/auth?"
                                     (query (append '(("ch" . "basic")) nacct (list (cons "tag" tag)))))
                      'get #f (list (cons "NETRC_FILE" netrc))))))
      ;; beside Digest with a 64 KiB body
      (let ((ch (cons '("ch" . "digest") acct)) (creds (cred-options 'digest "user" "pass" "-")))
        (for-each
         (lambda (o)
           (twin (format "~a-post" (if o (car o) "control")) 'digest ch 'post (pattern-bytes 0 65536)
                 (append creds (if o (list o) '()))))
         '(#f ("SASL_AUTHZID" . "authz") ("SASL_IR" . 1) ("SERVICE_NAME" . "svc") ("KEEP_SENDING_ON_ERROR" . 1))))
      ;; KEEP_SENDING_ON_ERROR beside an early 401 to a 1 MiB body, Basic
      ;; with a wrong password, and Digest's round
      (for-each
       (lambda (c)
         (twin (car c) (cadr c) (append (list (cons "ch" (scheme-ch (cadr c))) '("early" . "1")) acct)
               'post (pattern-bytes 0 1048576) (append (cred-options (cadr c) "user" "wrong" "-") (caddr c))))
       '(("early-401-control" basic ()) ("early-401-KEEP_SENDING_ON_ERROR=1" basic (("KEEP_SENDING_ON_ERROR" . 1)))
         ("early-401-control" digest ()) ("early-401-KEEP_SENDING_ON_ERROR=1" digest (("KEEP_SENDING_ON_ERROR" . 1)))))
      ;; found by reading the auth path (the README's source list): each
      ;; auth round and 417 resend is a follow libcurl counts against
      ;; MAXREDIRS; AUTOREFERER sets a Referer on each follow; 8.23.0 makes a
      ;; transfer's credentials from SERVICE_NAME and SASL_AUTHZID too
      (for-each
       (lambda (scheme)
         (let ((ch (cons (cons "ch" (scheme-ch scheme)) acct))
               (creds (cred-options scheme "user" "pass" "tok123")))
           (twin "MAXREDIRS=0" scheme ch 'get #f (append creds '(("MAXREDIRS" . 0))))
           (twin "MAXREDIRS=1" scheme ch 'get #f (append creds '(("MAXREDIRS" . 1))))
           (twin "MAXREDIRS=1-stale" scheme (cons '("stale" . "1") ch) 'get #f (append creds '(("MAXREDIRS" . 1))))
           (twin "AUTOREFERER=1" scheme ch 'get #f (append creds '(("AUTOREFERER" . 1))))
           (twin "SERVICE_NAME" scheme ch 'get #f (append creds '(("SERVICE_NAME" . "svc"))))
           (twin "SASL_AUTHZID" scheme ch 'get #f (append creds '(("SASL_AUTHZID" . "authz"))))))
       '(basic digest bearer))
      (twin "MAXREDIRS=0-expect417once" 'basic (append '(("ch" . "basic") ("expect" . "417once")) acct)
            'post (pattern-bytes 0 65536) (append (cred-options 'basic "user" "pass" "-") '(("MAXREDIRS" . 0)))
            'headers '(("Expect" . "100-continue")) 'timeout-ms (bound 5000))
      (twin "MAXREDIRS=-1-expect417" 'basic (append '(("ch" . "basic") ("expect" . "417")) acct)
            'post (pattern-bytes 0 65536) (append (cred-options 'basic "user" "pass" "-") '(("MAXREDIRS" . -1)))
            'headers '(("Expect" . "100-continue")) 'timeout-ms (bound 3000))
      (for-each
       (lambda (o)
         (twin (format "~a-alone-HTTPAUTH-basic" (car o)) 'basic '(("ch" . "open")) 'get #f
               (list '("HTTPAUTH" . 1) o)))
       '(("SERVICE_NAME" . "svc") ("SASL_AUTHZID" . "authz")))
      ;; KEEP_SENDING_ON_ERROR beside a streamed body a 401 answers at its
      ;; head, a wrong password, over http and h2
      (for-each
       (lambda (face)
         (for-each
          (lambda (keep)
            (stream-case "i7" (list (cons 'twin (if keep "stream-early-401-KEEP_SENDING_ON_ERROR=1" "stream-early-401-control"))
                                    '(scheme . basic) (cons 'face face))
                         face 'sized 'basic (append '(("ch" . "basic") ("early" . "1")) acct)
                         (append (cred-options 'basic "user" "wrong" "-") (if keep '(("KEEP_SENDING_ON_ERROR" . 1)) '()))))
          '(#f #t)))
       '(http h2)))))

;; --- item 8: a redirect's hops by hand ----------------------------------------------------------------

(define (part-hops)
  (for-each
   (lambda (scheme)
     (for-each
      (lambda (t)
        (with-engine
         (lambda (e)
           (let* ((tag (fresh-tag))
                  (acct (cons (cons "ch" (scheme-ch scheme)) (account "user" "pass" "tok123")))
                  (to-face (cadr t)) (to-host (caddr t)) (to-scheme (cadddr t))
                  (target (string-append to-scheme "://" (host-of to-host) ":" (setting (face-port to-face))
                                         (list-ref t 4) "?" (query (append acct (list (cons "hop" "2") (cons "tag" tag))))))
                  (creds (cred-options scheme "user" "pass" "tok123"))
                  (o1 (run e (make-req (route-url 'http 'ip "/auth" (append acct (list (cons "go" (pct target)))) tag) 'get #f creds)))
                  (location (and (curl-response? o1) (header-of (curl-response-headers o1) "location")))
                  (o2 (if location (run e (make-req location 'get #f creds)) 'no-location)))
             (say "t i8 scheme=~a target=~a step=1 tag=~a => ~a" scheme (car t) tag (describe o1))
             (say "t i8 scheme=~a target=~a step=2 tag=~a => ~a" scheme (car t) tag (if (symbol? o2) (symbol->string o2) (describe o2)))
             (show-log tag)))))
      ;; name, to face, to host, to scheme, path
      '((same-origin-other-path http ip "http" "/auth/next")
        (other-port httpb ip "http" "/auth")
        (other-host http name "http" "/auth")
        (http-to-https-same-port http ip "https" "/auth")
        (http-to-https-face https ip "https" "/auth"))))
   '(basic digest bearer))
  ;; a Location holding userinfo on a same-origin hop, credentials by option
  (for-each
   (lambda (scheme)
     (with-engine
      (lambda (e)
        (let* ((tag (fresh-tag))
               (acct (cons (cons "ch" (scheme-ch scheme)) (account "user" "pass" "tok123")))
               (target (string-append "http://u2:p2@127.0.0.1:" (setting 'http) "/auth/next?"
                                      (query (append acct (list (cons "hop" "2") (cons "tag" tag))))))
               (creds (cred-options scheme "user" "pass" "tok123"))
               (o1 (run e (make-req (route-url 'http 'ip "/auth" (append acct (list (cons "go" (pct target)))) tag) 'get #f creds)))
               (location (and (curl-response? o1) (header-of (curl-response-headers o1) "location")))
               (o2 (if location (run e (make-req location 'get #f creds)) 'no-location)))
          (say "t i8 scheme=~a target=userinfo-location step=1 tag=~a => ~a" scheme tag (describe o1))
          (say "t i8 scheme=~a target=userinfo-location step=2 tag=~a => ~a" scheme tag (if (symbol? o2) (symbol->string o2) (describe o2)))
          (show-log tag)))))
   '(basic digest bearer)))

;; --- item 8: today's origin rule, by the pure functions ------------------------------------------------

(define (part-origin)
  (for-each
   (lambda (pair)
     (let ((a (car pair)) (b (cadr pair)))
       (let* ((parts (lambda (u) (guard (e (#t (list 'refused (condition-text e))))
                                   (list (curl-url-part u 'scheme) (curl-url-part u 'host) (curl-url-part u 'port)))))
              (req (make-curl-request a 'headers '(("Authorization" . "Basic dXNlcjpwYXNz") ("Cookie" . "c=1") ("X-Other" . "1"))))
              (state (make-exchange 'get a req #f 0 5 #f))
              (sub (exchange-submission state 0))
              (resp (make-http-response 302 'http/1.1 a (list (cons "Location" b)) (make-bytevector 0) '() '()))
              (step (guard (e (#t (list 'raised (condition-text e)))) (exchange-step (cadr sub) (list 'response resp) 0 0 0))))
         (say "o a=~a b=~a a-parts=~s b-parts=~s answer=~a next-url=~a next-headers=~s" a b (parts a) (parts b)
              (car step)
              (if (eq? (car step) 'next) (curl-request-url (caddr step)) "-")
              (if (eq? (car step) 'next) (map car (curl-request-headers (caddr step))) "-")))))
   '(("http://h.example/a" "http://h.example:80/b")
     ("http://h.example:80/a" "http://h.example/b")
     ("https://h.example/a" "https://h.example:443/b")
     ("http://h.example/a" "http://H.EXAMPLE/b")
     ("http://h.example/a" "http://h.example:8080/b")
     ("http://h.example/a" "https://h.example/b")
     ("http://h.example/a" "https://h.example:80/b")
     ("http://127.0.0.1/a" "http://localhost/b")
     ("http://h.example/a" "/b")
     ("http://[::1]/a" "http://[::1]:80/b")
     ("http://u:p@h.example/a" "http://h.example/b")
     ("http://h.example/a" "http://u:p@h.example/b"))))

;; --- the parts -----------------------------------------------------------------------------------------

(say-libcurl)
(set! log-engine (make-curl-engine))
(case part
  ((refusals) (part-refusals))
  ((schemes) (part-schemes))
  ((wire) (part-wire))
  ((streams) (part-streams))
  ((empty) (part-empty))
  ((bytes) (part-bytes))
  ((bytestrace) (part-bytestrace))
  ((rounds) (part-rounds))
  ((pooled) (part-pooled))
  ((twins) (part-twins))
  ((hops) (part-hops))
  ((origin) (part-origin))
  (else (error 'auth.sps "no such part" part)))
(curl-engine-stop log-engine)
(say-native)
(say "part ~a done" part)
