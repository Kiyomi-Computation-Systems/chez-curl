#!chezscheme
;;; M7 slice 1's measurements (2026-11-02; the M7 plan, section 4.1),
;;; through chez-curl's engine, on today's src/ or the prototype's copy.
;;;
;;;   scheme --libdirs LIBDIRS --program version.sps PART KEY=VALUE ...
;;;
;;; run.sh passes the KEYs: tmp, the run's temp directory; ca, the run CA;
;;; and each face, HOST:PORT: http, https, h2c, h2 (tests/origin.mjs), alt1,
;;; alt1h, alt2, both, icy, ctl, closed (standin.mjs). HTTP_VERSION and every
;;; other option go through the hatch, curl-request-with-options. Every
;;; request carries ca-file and timeout-ms 10,000, and each transfer is
;;; waited on for 15,000 ms at most, then cancelled ("hung").
;;;
;;; PART is one of:
;;;   versions  item 1: HTTP_VERSION unset, NONE, 1_1, 2_0, 2TLS and
;;;             2_PRIOR_KNOWLEDGE, each over the http, https, h2c and h2
;;;             faces' /echo, each on an engine of its own. One "v1" line
;;;             a cell.
;;;   envproxy  item 2 (a), run with http_proxy and https_proxy naming the
;;;             http face: prior knowledge and the rest over http:// and
;;;             https://, proxy environment; the tunnels the http face has
;;;             opened, read before and after each, direct. One "p2a" line a
;;;             case. First, the hatch's answer to PROXY on this src/.
;;;   named     item 2 (b), on the prototype (make-prototype.sh): the same
;;;             cases with the hatch's PROXY at the http face and NOPROXY "".
;;;             One "p2b" line a case.
;;;   twins     item 3: SSL_ENABLE_ALPN, ALTSVC and ALTSVC_CTRL (with a
;;;             file, a pre-written file, and ALTSVC_CTRL alone),
;;;             HTTP09_ALLOWED, HTTP200ALIASES and CONNECT_TO. Lines
;;;             "alpn", "altsvc-i", "altsvc-ii", "altsvc-iii", "h09",
;;;             "alias", "connect-to".
;;;   sharing   item 4: two requests to /connection, together in one
;;;             call-with-engine-held, the second after the first's head, and
;;;             the second after the first's end; to h2 unset and 2TLS, and
;;;             to h2c by prior knowledge; three reps each, each case on a
;;;             fresh engine. One "share" line a case.
;;; Each part ends with a "native" line, (curl private counters)' counts.
(import (chezscheme)
        (curl)
        (curl unsupported)
        (only (curl private engine) call-with-engine-held)
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
           (unless kv (error 'version.sps "not KEY=VALUE" a))
           (cons (string->symbol (car kv)) (cdr kv))))
       (cdr args)))

(define (setting key)
  (let ((hit (assq key settings)))
    (unless hit (error 'version.sps "no such argument" key))
    (cdr hit)))

(define ca (setting 'ca))
(define tmp (setting 'tmp))
(define (face key) (setting key))
(define (port-of key) (cdr (split-at-char (face key) #\:)))
(define (url scheme key path) (string-append scheme "://" (face key) path))

(define (say fmt . xs)
  (apply printf fmt xs)
  (newline)
  (flush-output-port (current-output-port)))

(define (ns-of t) (+ (* (time-second t) 1000000000) (time-nanosecond t)))
(define (now-ns) (ns-of (current-time 'time-monotonic)))
(define (ms-since t0) (/ (round (/ (- (now-ns) t0) 100000)) 10.0))

;; --- requests and outcomes ---------------------------------------------------

(define versions
  '((unset . #f) (NONE . 0) (1_1 . 2) (2_0 . 3) (2TLS . 4) (2_PRIOR_KNOWLEDGE . 5)))

(define (version-value name)
  (let ((hit (assq name versions)))
    (unless hit (error 'version.sps "no such version" name))
    (cdr hit)))

;; request : String Symbol (Listof (Pairof String Any)) Any ... -> (U Request Condition)
;; URL's request, with ca-file and timeout-ms, KEYS, and HTTP_VERSION at
;; VERSION, unless unset, then OPTIONS, through the hatch; or what raised.
(define (request url version options . keys)
  (guard (e (#t e))
    (let* ((base (apply make-curl-request url 'ca-file ca 'timeout-ms 10000 keys))
           (v (version-value version))
           (all (append (if v (list (cons "HTTP_VERSION" v)) '()) options)))
      (if (null? all) base (curl-request-with-options base all)))))

;; run : Engine (U Request Condition) -> (U Response Condition 'hung)
(define (run engine req)
  (if (condition? req)
      req
      (guard (e (#t e))
        (let ((token (curl-submit engine req)))
          (if (curl-token-wait token 15000)
              (curl-token-outcome token)
              (begin (curl-token-cancel token) (curl-token-wait token 5000) 'hung))))))

(define (with-engine proc)
  (let ((engine (make-curl-engine)))
    (let ((answer (guard (e (#t (curl-engine-stop engine) (raise e))) (proc engine))))
      (curl-engine-stop engine)
      answer)))

;; render : Bytevector -> String
;; BYTES, printable ASCII as itself, \n, \r, \\ and \" escaped, any other
;; byte as \xHH; past 700 bytes, cut, with the count.
(define (render bytes)
  (let ((out (open-output-string)) (n (min 700 (bytevector-length bytes))))
    (let loop ((i 0))
      (when (< i n)
        (let ((b (bytevector-u8-ref bytes i)))
          (cond ((= b 10) (put-string out "\\n"))
                ((= b 13) (put-string out "\\r"))
                ((= b 92) (put-string out "\\\\"))
                ((= b 34) (put-string out "\\\""))
                ((and (>= b 32) (< b 127)) (put-char out (integer->char b)))
                (else (put-string out (string-append "\\x" (if (< b 16) "0" "") (number->string b 16))))))
        (loop (+ i 1))))
    (when (> (bytevector-length bytes) n)
      (put-string out (format "...(~a bytes)" (bytevector-length bytes))))
    (get-output-string out)))

(define (header-of response name)
  (let loop ((hs (curl-response-headers response)))
    (cond ((null? hs) #f)
          ((string-ci=? (caar hs) name) (cdar hs))
          (else (loop (cdr hs))))))

(define (timing response name) (cdr (assq name (curl-response-timings response))))

(define (class-of e)
  (cond ((curl-timeout? e) 'timeout) ((curl-connect-error? e) 'connect)
        ((curl-send-receive-error? e) 'send-receive) ((curl-tls-error? e) 'tls)
        ((curl-protocol-error? e) 'protocol) ((curl-too-large? e) 'too-large)
        (else 'base)))

(define (condition-text c)
  (call-with-string-output-port (lambda (p) (display-condition c p))))

;; describe : (U Response Condition 'hung) -> String
(define (describe o)
  (cond ((curl-response? o)
         (format "ok status=~a version=~a connect-us=~a alt-svc=~s effective=~a body=\"~a\""
                 (curl-response-status o) (curl-response-http-version o) (timing o 'connect)
                 (or (header-of o "alt-svc") "-") (curl-response-effective-url o)
                 (let ((b (curl-response-body o))) (if b (render b) "#f"))))
        ((curl-transfer-error? o)
         (format "fail reason=~a code=~a class=~a sent=~a option=~a strerror=~s errbuf=~s"
                 (curl-transfer-error-reason o) (curl-transfer-error-code o) (class-of o)
                 (curl-transfer-error-request-size o) (curl-transfer-error-option o)
                 (curl-transfer-error-strerror o) (curl-transfer-error-error-buffer o)))
        ((curl-request-error? o)
         (format "refused field=~a reason=~a value=~s" (curl-request-error-field o)
                 (curl-request-error-reason o) (curl-request-error-value o)))
        ((condition? o) (format "condition ~s" (condition-text o)))
        ((eq? o 'hung) "hung")
        (else (format "other ~s" o))))

(define (body-string o)
  (if (and (curl-response? o) (curl-response-body o)) (utf8->string (curl-response-body o)) ""))

(define (say-libcurl)
  (let ((info (loaded-libcurl)))
    (say "libcurl version=~a ssl=~s path=~a part=~a" (libcurl-info-version info)
         (libcurl-info-ssl-version info) (libcurl-info-path info) part)))

(define (say-native) (say "native ~s" (native-counts)))

;; verbosely : String (-> String) -> Void
;; THUNK's line, with libcurl's own trace (VERBOSE, which THUNK's request
;; sets) on stderr between a begin and an end line naming LABEL.
(define (verbosely label thunk)
  (say "verbose-begin ~a" label)
  (let ((line (thunk)))
    (flush-output-port (current-error-port))
    (say "verbose-end ~a" label)
    (say "~a" line)))

;; --- item 1: each version over each face -----------------------------------

(define item1-faces '((http "http") (https "https") (h2c "http") (h2 "https")))

(define (part-versions)
  ;; libcurl's own words for the ALPN offer: prior knowledge and unset over
  ;; the https face.
  (for-each
   (lambda (v)
     (verbosely (format "v1 version=~a face=https" v)
       (lambda ()
         (format "v1v version=~a face=https ~a" v
                 (describe (with-engine (lambda (e) (run e (request (url "https" 'https "/echo") v '(("VERBOSE" . 1)))))))))))
   '(unset 2_PRIOR_KNOWLEDGE))
  (for-each
   (lambda (v)
     (for-each
      (lambda (f)
        (let ((o (with-engine (lambda (e) (run e (request (url (cadr f) (car f) "/echo") (car v) '()))))))
          (say "v1 version=~a face=~a ~a" (car v) (car f) (describe o))))
      item1-faces))
   versions))

;; --- item 2: prior knowledge through a proxy --------------------------------

;; connects : -> String
;; The http face's /connects, direct, on an engine of its own.
(define (connects)
  (let ((o (with-engine (lambda (e) (run e (request (url "http" 'http "/connects") 'unset '() 'proxy #f))))))
    (let ((s (body-string o)))
      (if (and (> (string-length s) 9) (string=? (substring s 0 9) "connects "))
          (substring s 9 (- (string-length s) 1))
          (format "?~a" (describe o))))))

;; proxy-cases : (Listof (List Symbol String Symbol Symbol (Listof Option)))
;; Each case: its name, scheme, face, version and options beyond the proxy's.
(define proxy-cases
  `((plain-unset "http" h2c unset ())
    (plain-pk "http" h2c 2_PRIOR_KNOWLEDGE ())
    ;; plain-pk again, with libcurl's own trace on stderr, for its words.
    (plain-pk-verbose "http" h2c 2_PRIOR_KNOWLEDGE (("VERBOSE" . 1)))
    (plain-pk-to-http "http" http 2_PRIOR_KNOWLEDGE ())
    (tunnel-unset "http" h2c unset (("HTTPPROXYTUNNEL" . 1)))
    (tunnel-pk "http" h2c 2_PRIOR_KNOWLEDGE (("HTTPPROXYTUNNEL" . 1)))
    (https-unset "https" h2 unset ())
    (https-2tls "https" h2 2TLS ())
    (https-pk "https" h2 2_PRIOR_KNOWLEDGE ())))

(define (run-proxy-cases tag proxy-options)
  (for-each
   (lambda (c)
     (let* ((before (connects))
            (o (with-engine
                (lambda (e)
                  (run e (request (url (list-ref c 1) (list-ref c 2) "/echo") (list-ref c 3)
                                  (append proxy-options (list-ref c 4)))))))
            (after (connects)))
       (say "~a case=~a face=~a version=~a connects=~a->~a ~a" tag (car c) (list-ref c 2) (list-ref c 3)
            before after (describe o))))
   proxy-cases))

(define (part-envproxy)
  (say "p2a env http_proxy=~s https_proxy=~s no_proxy=~s" (getenv "http_proxy") (getenv "https_proxy")
       (getenv "no_proxy"))
  (say "p2a hatch-proxy-on-this-src ~a"
       (describe (request (url "http" 'h2c "/echo") 'unset (list (cons "PROXY" (string-append "http://" (face 'http)))))))
  (let* ((before (connects))
         (o (with-engine (lambda (e) (run e (request (url "http" 'h2c "/echo") '2_PRIOR_KNOWLEDGE '() 'proxy #f)))))
         (after (connects)))
    (say "p2a case=direct-pk-proxy-#f face=h2c version=2_PRIOR_KNOWLEDGE connects=~a->~a ~a" before after (describe o)))
  (run-proxy-cases "p2a" '()))

(define (part-named)
  (say "p2b env http_proxy=~s https_proxy=~s no_proxy=~s" (getenv "http_proxy") (getenv "https_proxy")
       (getenv "no_proxy"))
  (run-proxy-cases "p2b" (list (cons "PROXY" (string-append "http://" (face 'http))) (cons "NOPROXY" ""))))

;; --- item 3: the twins -------------------------------------------------------

(define (events)
  (let ((o (with-engine (lambda (e) (run e (request (url "http" 'ctl "/events") 'unset '() 'proxy #f))))))
    (let ((s (body-string o)))
      (if (> (string-length s) 0) (substring s 0 (- (string-length s) 1)) (format "?~a" (describe o))))))

(define (file->string path)
  (if (file-exists? path)
      (call-with-port (open-file-input-port path) (lambda (p) (let ((b (get-bytevector-all p))) (if (eof-object? b) "" (utf8->string b)))))
      #f))

;; altsvc-file : String -> String
;; The file's entries, its comment lines left out, joined by " | "; or
;; absent.
(define (altsvc-file path)
  (let ((text (file->string path)))
    (if (not text)
        "absent"
        (let loop ((lines (split-lines text)) (acc '()))
          (cond ((null? lines) (if (null? acc) "no-entries" (join (reverse acc) " | ")))
                ((or (string=? (car lines) "") (char=? (string-ref (car lines) 0) #\#)) (loop (cdr lines) acc))
                (else (loop (cdr lines) (cons (car lines) acc))))))))

(define (split-lines s)
  (let loop ((cs (string->list s)) (cur '()) (acc '()))
    (cond ((null? cs) (reverse (if (null? cur) acc (cons (list->string (reverse cur)) acc))))
          ((char=? (car cs) #\newline) (loop (cdr cs) '() (cons (list->string (reverse cur)) acc)))
          (else (loop (cdr cs) (cons (car cs) cur) acc)))))

(define (join strings sep)
  (if (null? strings) ""
      (fold-left (lambda (acc s) (string-append acc sep s)) (car strings) (cdr strings))))

(define (write-file! path text)
  (call-with-port (open-file-output-port path (file-options no-fail) (buffer-mode block) (native-transcoder))
    (lambda (p) (put-string p text))))

(define (unique-path name) (string-append tmp "/" name))

;; streamed-with-file : Engine Request String -> (Values String String String)
;; REQUEST, streamed, on ENGINE: the alt-svc file at PATH once its head is
;; in, and again once it has ended, and the outcome's description, its body
;; from the pieces.
(define (streamed-with-file engine req path)
  (if (condition? req)
      (values "-" "-" (describe req))
      (let* ((token (curl-submit engine req))
             (head (curl-token-head-wait token 5000))
             (at-head (if (curl-token-done? token) (format "done-before-look:~a" (altsvc-file path)) (altsvc-file path))))
        (let loop ((pieces '()))
          (let ((p (curl-token-next-piece token 5000)))
            (cond ((bytevector? p) (loop (cons p pieces)))
                  (else
                   (curl-token-wait token 5000)
                   (let ((o (curl-token-outcome token)))
                     (values at-head (altsvc-file path)
                             (if (curl-response? o)
                                 (format "ok status=~a version=~a body=\"~a\"" (curl-response-status o)
                                         (curl-response-http-version o)
                                         (render (apply bytevector-append-all (reverse pieces))))
                                 (describe o)))))))))))

(define (bytevector-append-all . bvs)
  (let* ((n (apply + (map bytevector-length bvs))) (out (make-bytevector n)))
    (let loop ((bvs bvs) (at 0))
      (if (null? bvs)
          out
          (begin (bytevector-copy! (car bvs) 0 out at (bytevector-length (car bvs)))
                 (loop (cdr bvs) (+ at (bytevector-length (car bvs)))))))))

(define curlaltsvc-readonlyfile 4)
(define curlaltsvc-h1 8)
(define curlaltsvc-h2 16)

(define (part-alpn)
  ;; SSL_ENABLE_ALPN 0, and libcurl's default, beside unset, 2TLS and 1_1,
  ;; over the https face (http/1.1 alone), h2 (h2 alone) and both (h2 and
  ;; http/1.1).
  (for-each
   (lambda (f)
     (for-each
      (lambda (v)
        (for-each
         (lambda (alpn)
           (let ((o (with-engine
                     (lambda (e)
                       (run e (request (url "https" (car f) (cadr f)) v
                                       (if (eq? alpn 'off) '(("SSL_ENABLE_ALPN" . 0)) '())))))))
             (say "alpn face=~a version=~a alpn=~a ~a" (car f) v alpn (describe o))))
         '(default off)))
      '(unset 2TLS 1_1)))
   '((https "/echo") (h2 "/echo") (both "/alpn"))))

(define (part-altsvc-i)
  ;; (i) ALTSVC at a fresh path, ALTSVC_CTRL as given: A streamed to /slow
  ;; (the file read at its head and at its end), then B on the same engine,
  ;; then C on a fresh engine; the stand-in's counts before and after.
  (for-each
   (lambda (c)
     (let* ((name (car c)) (scheme (cadr c)) (key (caddr c)) (v (cadddr c)) (ctrl (list-ref c 4))
            (file? (list-ref c 5))
            (path (unique-path (format "altsvc-i-~a.txt" name)))
            (options (append (if file? (list (cons "ALTSVC" path)) '())
                             (if ctrl (list (cons "ALTSVC_CTRL" ctrl)) '()))))
       (say "altsvc-i case=~a face=~a version=~a ctrl=~a altsvc-option=~a file-before=~a events=~a" name key v ctrl
            (if file? "set" "none") (altsvc-file path) (events))
       (with-engine
        (lambda (e)
          (let-values (((at-head at-end a) (streamed-with-file e (request (url scheme key "/slow-a") v options 'stream-buffer 4096) path)))
            (say "altsvc-i case=~a step=A file-at-head=~a file-at-end=~a events=~a ~a" name at-head at-end (events) a))
          (let ((b (run e (request (url scheme key "/b") v options))))
            (say "altsvc-i case=~a step=B-same-engine file=~a events=~a ~a" name (altsvc-file path) (events) (describe b)))))
       (let ((c (with-engine (lambda (e) (run e (request (url scheme key "/c") v options))))))
         (say "altsvc-i case=~a step=C-fresh-engine file=~a events=~a ~a" name (altsvc-file path) (events) (describe c)))))
   `((h1h2-unset "https" alt1 unset ,(+ curlaltsvc-h1 curlaltsvc-h2) #t)
     (h1h2-2tls "https" alt1 2TLS ,(+ curlaltsvc-h1 curlaltsvc-h2) #t)
     (h1h2-1_1 "https" alt1 1_1 ,(+ curlaltsvc-h1 curlaltsvc-h2) #t)
     (h1only-unset "https" alt1 unset ,curlaltsvc-h1 #t)
     (file-ctrl-default "https" alt1 unset #f #t)
     (plain-http-unset "http" alt1h unset ,(+ curlaltsvc-h1 curlaltsvc-h2) #t)
     ;; (iii): ALTSVC_CTRL alone, no ALTSVC: the path is never handed to
     ;; libcurl, so "absent" there is the control that nothing wrote it.
     (ctrl-alone-unset "https" alt1 unset ,(+ curlaltsvc-h1 curlaltsvc-h2) #f)
     (ctrl-alone-2tls "https" alt1 2TLS ,(+ curlaltsvc-h1 curlaltsvc-h2) #f))))

(define (altsvc-line src-alpn src-key dst-alpn dst-host dst-key)
  (format "~a 127.0.0.1 ~a ~a ~a ~a \"20301231 00:00:00\" 0 0\n" src-alpn (port-of src-key) dst-alpn dst-host
          (port-of dst-key)))

(define (part-altsvc-ii)
  ;; (ii) a pre-written file: one entry for the URL's origin, then one
  ;; transfer on a fresh engine, ALTSVC alone (libcurl's default control)
  ;; or ALTSVC with ALTSVC_CTRL; the file read after.
  (for-each
   (lambda (c)
     (for-each
      (lambda (v)
        (let* ((name (car c)) (scheme (cadr c)) (key (caddr c)) (entry (cadddr c)) (ctrl (list-ref c 4))
               (path (unique-path (format "altsvc-ii-~a-~a.txt" name v)))
               (options (append (list (cons "ALTSVC" path)) (if ctrl (list (cons "ALTSVC_CTRL" ctrl)) '()))))
          (write-file! path (string-append "# pre-written by version.sps\n" entry))
          (let* ((before (events))
                 (o (with-engine (lambda (e) (run e (request (url scheme key (if (eq? key 'https) "/echo" "/ii")) v options))))))
            (say "altsvc-ii case=~a version=~a ctrl=~a entry=~s events=~a->~a file-after=~a ~a" name v ctrl
                 (substring entry 0 (- (string-length entry) 1)) before (events) (altsvc-file path) (describe o)))))
      '(unset 2TLS 1_1)))
   (list (list 'port "https" 'alt1 (altsvc-line "h1" 'alt1 "h2" "127.0.0.1" 'alt2) #f)
         (list 'port-ctrl-ro "https" 'alt1 (altsvc-line "h1" 'alt1 "h2" "127.0.0.1" 'alt2)
               (+ curlaltsvc-h1 curlaltsvc-h2 curlaltsvc-readonlyfile))
         (list 'host "https" 'alt1 (altsvc-line "h1" 'alt1 "h2" "localhost" 'alt2) #f)
         (list 'h1-to-both "https" 'alt1 (altsvc-line "h1" 'alt1 "h1" "127.0.0.1" 'both) #f)
         (list 'h2src "https" 'alt1 (altsvc-line "h2" 'alt1 "h2" "127.0.0.1" 'alt2) #f)
         (list 'dead "https" 'alt1 (altsvc-line "h1" 'alt1 "h2" "127.0.0.1" 'closed) #f)
         (list 'origin-h2 "https" 'https (altsvc-line "h1" 'https "h2" "127.0.0.1" 'h2) #f)
         (list 'plain-http "http" 'alt1h (altsvc-line "h1" 'alt1h "h2" "127.0.0.1" 'alt2) #f))))

(define (part-misc)
  ;; HTTP09_ALLOWED against the h2c face; the icy face's "ICY 200 OK" bare,
  ;; with HTTP200ALIASES, and with HTTP09_ALLOWED; CONNECT_TO from alt1's
  ;; URL to alt2.
  (for-each
   (lambda (c)
     (let ((o (with-engine (lambda (e) (run e (request (url "http" 'h2c "/echo") (cadr c) (caddr c)))))))
       (say "h09 case=~a face=h2c version=~a ~a" (car c) (cadr c) (describe o))))
   '((control unset ()) (allowed unset (("HTTP09_ALLOWED" . 1))) (allowed-1_1 1_1 (("HTTP09_ALLOWED" . 1)))))
  (for-each
   (lambda (c)
     (let ((o (with-engine (lambda (e) (run e (request (url "http" 'icy "/") 'unset (cadr c)))))))
       (say "alias case=~a face=icy ~a" (car c) (describe o))))
   '((control ()) (alias (("HTTP200ALIASES" "ICY 200 OK"))) (http09 (("HTTP09_ALLOWED" . 1)))))
  (for-each
   (lambda (v)
     (let* ((before (events))
            (o (with-engine
                (lambda (e)
                  (run e (request (url "https" 'alt1 "/ct") v
                                  (list (cons "CONNECT_TO" (list (string-append "::127.0.0.1:" (port-of 'alt2)))))))))))
       (say "connect-to version=~a to=alt2 events=~a->~a ~a" v before (events) (describe o))))
   '(unset 1_1)))

(define (part-altsvc-verbose)
  ;; (ii)'s port entry again, unset and 1_1, with libcurl's own trace.
  (for-each
   (lambda (v)
     (let ((path (unique-path (format "altsvc-v-~a.txt" v))))
       (write-file! path (string-append "# pre-written by version.sps\n" (altsvc-line "h1" 'alt1 "h2" "127.0.0.1" 'alt2)))
       (verbosely (format "altsvc-v case=port version=~a" v)
         (lambda ()
           (format "altsvc-v case=port version=~a ~a" v
                   (describe (with-engine
                              (lambda (e)
                                (run e (request (url "https" 'alt1 "/v") v
                                                (list (cons "ALTSVC" path) (cons "VERBOSE" 1))))))))))))
   '(unset 1_1)))

(define (part-twins)
  (part-alpn)
  (part-altsvc-i)
  (part-altsvc-ii)
  (part-altsvc-verbose)
  (part-misc))

;; --- item 4: connection sharing ------------------------------------------------

;; connection-k : String -> (U Integer #f)
(define (connection-k s)
  (and (> (string-length s) 11) (string=? (substring s 0 11) "connection ")
       (string->number (substring s 11 (- (string-length s) 1)))))

(define (k-of o) (and (curl-response? o) (connection-k (body-string o))))

(define (brief o)
  (if (curl-response? o)
      (format "k=~a version=~a connect-us=~a" (k-of o) (curl-response-http-version o) (timing o 'connect))
      (describe o)))

(define (await token)
  (if (curl-token-wait token 15000)
      (curl-token-outcome token)
      (begin (curl-token-cancel token) (curl-token-wait token 5000) 'hung)))

(define (share-together setup rep . options)
  (let ((scheme (cadr setup)) (key (car setup)) (v (caddr setup)))
    (with-engine
     (lambda (e)
       (let* ((r1 (request (url scheme key "/connection?delay=300") v options))
              (r2 (request (url scheme key "/connection?delay=300") v options))
              (tokens (call-with-engine-held e (lambda () (let* ((t1 (curl-submit e r1)) (t2 (curl-submit e r2))) (list t1 t2)))))
              (o1 (await (car tokens)))
              (o2 (await (cadr tokens))))
         (say "share setup=~a/~a case=a-together rep=~a same=~a first: ~a second: ~a" key v rep
              (and (k-of o1) (k-of o2) (= (k-of o1) (k-of o2))) (brief o1) (brief o2)))))))

(define (share-after-head setup rep delay)
  (let ((scheme (cadr setup)) (key (car setup)) (v (caddr setup)))
    (with-engine
     (lambda (e)
       (let* ((t0 (now-ns))
              (t1 (curl-submit e (request (url scheme key (format "/connection?delay=~a" delay)) v '() 'stream-buffer 4096)))
              (head (curl-token-head-wait t1 5000))
              (head-ms (ms-since t0))
              (first-done-at-submit (curl-token-done? t1))
              (t2 (curl-submit e (request (url scheme key "/connection") v '())))
              (o2 (await t2))
              (second-ms (ms-since t0))
              (first-done-at-second-end (curl-token-done? t1)))
         (let loop ((pieces '()))
           (let ((p (curl-token-next-piece t1 5000)))
             (if (bytevector? p)
                 (loop (cons p pieces))
                 (let* ((o1 (begin (curl-token-wait t1 5000) (curl-token-outcome t1)))
                        (k1 (connection-k (utf8->string (apply bytevector-append-all (reverse pieces))))))
                   (say "share setup=~a/~a case=b-after-head rep=~a delay=~a head=~a head-ms=~a first-done-at-submit=~a second-ended-ms=~a first-done-at-second-end=~a same=~a first: k=~a version=~a ~a second: ~a"
                        key v rep delay head head-ms first-done-at-submit second-ms first-done-at-second-end
                        (and k1 (k-of o2) (= k1 (k-of o2))) k1
                        (and (curl-response? o1) (curl-response-http-version o1))
                        (if (curl-response? o1) (format "connect-us=~a" (timing o1 'connect)) (describe o1))
                        (brief o2)))))))))))

(define (share-after-end setup rep)
  (let ((scheme (cadr setup)) (key (car setup)) (v (caddr setup)))
    (with-engine
     (lambda (e)
       (let* ((o1 (run e (request (url scheme key "/connection") v '())))
              (o2 (run e (request (url scheme key "/connection") v '()))))
         (say "share setup=~a/~a case=c-after-end rep=~a same=~a first: ~a second: ~a" key v rep
              (and (k-of o1) (k-of o2) (= (k-of o1) (k-of o2))) (brief o1) (brief o2)))))))

(define (part-sharing)
  (for-each
   (lambda (setup)
     (for-each
      (lambda (rep delay)
        (share-together setup rep)
        (share-after-head setup rep delay)
        (share-after-end setup rep))
      '(1 2 3) '(700 900 1100)))
   '((h2 "https" unset) (h2 "https" 2TLS) (h2c "http" 2_PRIOR_KNOWLEDGE)))
  ;; together again, with libcurl's own trace: a fourth rep, "verbose".
  (for-each
   (lambda (setup)
     (verbosely (format "share setup=~a/~a case=a-together rep=verbose" (car setup) (caddr setup))
       (lambda () (share-together setup 'verbose '("VERBOSE" . 1)) "share-verbose done")))
   '((h2 "https" unset) (h2c "http" 2_PRIOR_KNOWLEDGE))))

;; --- the parts -----------------------------------------------------------------

(say-libcurl)
(case part
  ((versions) (part-versions))
  ((envproxy) (part-envproxy))
  ((named) (part-named))
  ((twins) (part-twins))
  ((sharing) (part-sharing))
  (else (error 'version.sps "no such part" part)))
(say-native)
(say "part ~a done" part)
