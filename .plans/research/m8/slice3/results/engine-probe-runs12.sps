;;; M8 slice 3's measurement through the engine (the M8 plan, section 6),
;;; on the probe's tree: the prototype (proto.patch) and its seam (seam.py).
;;;
;;;   scheme --libdirs src --program engine-probe.sps LANE HTTP H2C H2 RAW CA FRAW FH2C FCTL DIR [GROUP ...]
;;;
;;; HTTP, H2C, H2 and RAW are the prototype's origin's faces' ports
;;; (tests/origin.mjs, its parts route); CA its run's CA file; FRAW, FH2C and
;;; FCTL the mime-files stand-in's (research/m8/mime-files/server.mjs), 0
;;; where a run starts none; DIR a scratch directory for the files. Every
;;; cell runs on an engine of its own, made for it and stopped after it,
;;; through (curl) and, for EXPECT_100_TIMEOUT_MS, (curl unsupported). One
;;; line a cell:
;;;   cell GROUP LABEL face=F method=M asked=... outcome=... sizes=... [more]
;;; then the origin's report, each line after "  | ". The outcome: (status S
;;; version V) or (failed REASON CODE CLASS "ERROR BUFFER" size=N), or
;;; (refused WHO REASON FIELD VALUE) for a request or submit refused, or
;;; (raised "TEXT"). sizes is each of the cell's transfers' CURLINFO_REQUEST_SIZE,
;;; from the seam. meta and data say whether each part arrived as asked: same,
;;; default-type T (libcurl added that Content-Type), or DIFF.
;;; GROUP, when given, runs those groups alone: load, kinds, defaults, bytes,
;;; ctype, check, after, stat, cap, resend, hole, memory.
(import (chezscheme) (curl) (curl unsupported)
        (only (curl private transfer) transfer-file-check-gate-set! take-transfer-sizes!
              take-file-check-times! curl-request-following)
        (only (curl private native) loaded-mime-probe loaded-mime?)
        (only (curl private counters) native-counts))

(define args (command-line-arguments))
(define lane (list-ref args 0))
(define http-port (list-ref args 1))
(define h2c-port (list-ref args 2))
(define h2-port (list-ref args 3))
(define raw-port (list-ref args 4))
(define ca (list-ref args 5))
(define fraw-port (list-ref args 6))
(define fh2c-port (list-ref args 7))
(define fctl-port (list-ref args 8))
(define dir (list-ref args 9))
(define groups (if (> (length args) 10) (map string->symbol (list-tail args 10)) #f))

(define (ms-of t) (+ (* (time-second t) 1000.0) (/ (time-nanosecond t) 1e6)))
(define (now-ms) (ms-of (current-time 'time-monotonic)))
(define (round1 x) (/ (round (* 10 x)) 10.0))

(define (say . parts) (for-each display parts) (newline) (flush-output-port (current-output-port)))

;; --- bytes, files, escaping ---------------------------------------------------------

;; pattern-bytes : Natural -> Bytevector   byte i is i mod 251
(define (pattern-bytes n)
  (let ((b (make-bytevector n)))
    (do ((i 0 (+ i 1))) ((= i n) b) (bytevector-u8-set! b i (mod i 251)))))

(define (write-file path bytes)
  (when (file-exists? path #f) (delete-file path))
  (call-with-port (open-file-output-port path (file-options no-fail)) (lambda (p) (put-bytevector p bytes))))

(define (append-file path bytes)
  (call-with-port (open-file-output-port path (file-options no-fail no-truncate) (buffer-mode block))
    (lambda (p) (set-port-position! p (port-length p)) (put-bytevector p bytes))))

(define (sh command)
  (let ((status (system command)))
    (unless (= status 0) (say "sh-failed " status " " command))
    status))

(define (path . parts) (apply string-append dir "/" parts))

;; escaped : Bytevector -> String   as the origin's parts report escapes
(define (escaped bytes)
  (let ((out (open-output-string)))
    (do ((i 0 (+ i 1))) ((= i (bytevector-length bytes)) (get-output-string out))
      (let ((b (bytevector-u8-ref bytes i)))
        (cond ((= b #x5c) (display "\\\\" out))
              ((and (>= b #x20) (< b #x7f) (not (= b #x7c))) (write-char (integer->char b) out))
              (else (display (string-append "\\x" (if (< b 16) "0" "") (string-downcase (number->string b 16))) out)))))))

(define (u8 s) (string->utf8 s))

(define (split-on s c)
  (let loop ((i 0) (start 0) (out '()))
    (cond ((= i (string-length s)) (reverse (cons (substring s start i) out)))
          ((char=? (string-ref s i) c) (loop (+ i 1) (+ i 1) (cons (substring s start i) out)))
          (else (loop (+ i 1) start out)))))

(define (string-search s k)
  (let ((n (string-length s)) (m (string-length k)))
    (let loop ((i 0))
      (cond ((> (+ i m) n) #f)
            ((string=? (substring s i (+ i m)) k) i)
            (else (loop (+ i 1)))))))

(define (between line from to)
  ;; the text after FROM, up to TO or the line's end
  (let ((at (string-search line from)))
    (and at
         (let* ((start (+ at (string-length from)))
                (rest (substring line start (string-length line)))
                (end (and to (string-search rest to))))
           (if end (substring rest 0 end) rest)))))

(define (field-of line name)
  ;; the value of NAME= in a report line, up to the next space
  (let ((at (string-search line (string-append " " name "="))))
    (and at
         (let* ((from (+ at (string-length name) 2))
                (to (let loop ((i from)) (if (or (= i (string-length line)) (char=? (string-ref line i) #\space)) i (loop (+ i 1))))))
           (substring line from to)))))

(define (latin-1 bytes)
  (let ((s (make-string (bytevector-length bytes))))
    (do ((i 0 (+ i 1))) ((= i (bytevector-length bytes)) s)
      (string-set! s i (integer->char (bytevector-u8-ref bytes i))))))

(define (lines-of text) (filter (lambda (l) (> (string-length l) 0)) (split-on text #\newline)))

;; --- describing ------------------------------------------------------------------------

(define (class-of e)
  (cond ((curl-too-large? e) 'too-large) ((curl-send-receive-error? e) 'send-receive)
        ((curl-protocol-error? e) 'protocol) ((curl-timeout? e) 'timeout)
        ((curl-connect-error? e) 'connect) ((curl-tls-error? e) 'tls)
        ((curl-transfer-error? e) 'none) (else 'not-a-transfer-error)))

(define (condition-text e)
  (call-with-string-output-port (lambda (p) (display-condition e p))))

(define (describe outcome)
  (cond
    ((curl-response? outcome)
     (format "(status ~a version ~a)" (curl-response-status outcome) (curl-response-http-version outcome)))
    ((curl-transfer-error? outcome)
     (format "(failed ~a ~a ~a ~s size=~a)" (curl-transfer-error-reason outcome) (curl-transfer-error-code outcome)
             (class-of outcome) (or (curl-transfer-error-error-buffer outcome) "")
             (curl-transfer-error-request-size outcome)))
    ((curl-request-error? outcome)
     (format "(refused ~a ~a ~a ~s)" (if (who-condition? outcome) (condition-who outcome) '?)
             (curl-request-error-reason outcome) (curl-request-error-field outcome)
             (curl-request-error-value outcome)))
    ((condition? outcome) (format "(raised ~s)" (condition-text outcome)))
    ((and (pair? outcome) (eq? (car outcome) 'stalled))
     (format "(stalled ~a ms, then cancelled: ~a)" (cadr outcome) (describe (caddr outcome))))
    (else (format "(other ~s)" outcome))))

;; --- the parts asked, and what came -----------------------------------------------------

(define (part-name part) (car part))
(define (part-source part) (cadr part))
(define (part-opt part key) (let ((hit (memq key (cddr part)))) (and hit (cadr hit))))

(define (basename p)
  (let loop ((i (- (string-length p) 1)))
    (cond ((< i 0) p) ((char=? (string-ref p i) #\/) (substring p (+ i 1) (string-length p))) (else (loop (- i 1))))))

(define (source-bytes source)
  (cond ((string? source) (u8 source))
        ((bytevector? source) source)
        (else (let ((b (call-with-port (open-file-input-port (cadr source)) get-bytevector-all)))
                (if (eof-object? b) (make-bytevector 0) b)))))

;; expected-headers : Part -> (Listof String)  the lines asked, escaped
(define (expected-headers part)
  (let* ((source (part-source part))
         (filename (or (part-opt part 'filename) (and (pair? source) (basename (cadr source)))))
         (type (part-opt part 'type)))
    (append (list (escaped (bytevector-append-all
                            (u8 "Content-Disposition: form-data; name=\"") (u8 (part-name part)) (u8 "\"")
                            (if filename (bytevector-append-all (u8 "; filename=\"") (u8 filename) (u8 "\"")) (u8 "")))))
            (if type (list (escaped (bytevector-append-all (u8 "Content-Type: ") (u8 type)))) '()))))

(define (bytevector-append-all . bs)
  (let* ((n (apply + (map bytevector-length bs))) (out (make-bytevector n)))
    (let loop ((bs bs) (at 0))
      (if (null? bs) out
          (begin (bytevector-copy! (car bs) 0 out at (bytevector-length (car bs)))
                 (loop (cdr bs) (+ at (bytevector-length (car bs)))))))))

(define (pattern? bytes)
  (let loop ((i 0)) (or (= i (bytevector-length bytes)) (and (= (bytevector-u8-ref bytes i) (mod i 251)) (loop (+ i 1))))))

;; judge : (Listof Part) (Listof String) -> String
;; Each part asked against the report's part lines, in order.
(define (judge parts report)
  (let ((got (filter (lambda (l) (and (> (string-length l) 5) (string=? (substring l 0 5) "part "))) report)))
    (if (not (= (length got) (length parts)))
        (format "parts=DIFF(asked ~a got ~a)" (length parts) (length got))
        (apply string-append
               (map (lambda (part line)
                      (let* ((heads (split-on (or (between line " headers=" " len=") "") #\|))
                             (want (expected-headers part))
                             (meta (cond ((equal? heads want) "same")
                                         ((and (= (length heads) (+ (length want) 1)) (equal? (list-head heads (length want)) want))
                                          (string-append "default-type:" (list-ref heads (length want))))
                                         (else "DIFF")))
                             (bytes (source-bytes (part-source part)))
                             (len (string->number (or (field-of line "len") "-1")))
                             (data (cond ((not (eqv? len (bytevector-length bytes))) (format "DIFF(len ~a asked ~a)" len (bytevector-length bytes)))
                                         ((<= len 256) (if (string=? (or (between line " data=" " unterminated") "") (escaped bytes)) "same" "DIFF"))
                                         ((pattern? bytes) (if (equal? (field-of line "pattern") "ok") "same" "DIFF(pattern)"))
                                         (else "len-same")))
                             (unterminated (string-search line " unterminated")))
                        (format " [~a meta=~a data=~a~a]" (part-name-short part) meta data (if unterminated " UNTERMINATED" ""))))
                    parts got)))))

(define (part-name-short part)
  (let ((n (escaped (u8 (part-name part))))) (if (> (string-length n) 24) (string-append (substring n 0 24) "...") n)))

(define (describe-asked parts)
  (apply string-append
         (map (lambda (part)
                (let ((s (part-source part)))
                  (format "(~a ~a~a~a)" (part-name-short part)
                          (cond ((string? s) (format "string:~a" (bytevector-length (u8 s))))
                                ((bytevector? s) (format "bytes:~a" (bytevector-length s)))
                                (else (format "file:~a" (basename (cadr s)))))
                          (if (part-opt part 'filename) (format " filename:~a" (escaped (u8 (part-opt part 'filename)))) "")
                          (if (part-opt part 'type) (format " type:~a" (escaped (u8 (part-opt part 'type)))) ""))))
              parts)))

;; --- faces, engines, cells --------------------------------------------------------------

(define key-count 0)
(define (next-key) (set! key-count (+ key-count 1)) (format "k~a" key-count))

(define (face-url face p)
  (case face
    ((h1) (string-append "http://127.0.0.1:" http-port p))
    ((h2c) (string-append "http://127.0.0.1:" h2c-port p))
    ((h2) (string-append "https://127.0.0.1:" h2-port p))
    ((raw) (string-append "http://127.0.0.1:" raw-port p))
    ((fraw) (string-append "http://127.0.0.1:" fraw-port p))
    ((fh2c) (string-append "http://127.0.0.1:" fh2c-port p))
    (else (error 'face-url "no face" face))))

(define (face-keys face)
  (case face
    ((h2c fh2c) '(http-version http/2-prior-knowledge))
    ((h2) (list 'ca-file ca 'http-version 'http/2))
    (else '())))

(define (with-engine proc)
  (let ((e (make-curl-engine)))
    (dynamic-wind (lambda () #f) (lambda () (proc e)) (lambda () (curl-engine-stop e)))))

;; the control engine, for the origin's /seen and /raw/release and the
;; mime-files stand-in's events
(define ctl-engine-box (vector #f))
(define (ctl-engine)
  (or (vector-ref ctl-engine-box 0)
      (let ((e (make-curl-engine))) (vector-set! ctl-engine-box 0 e) e)))
(define (ctl-get url)
  (let* ((token (curl-submit (ctl-engine) (make-curl-request url 'proxy #f 'timeout-ms 10000)))
         (r (curl-token-await token)))
    (latin-1 (curl-response-body r))))
(define (seen key) (let ((s (ctl-get (face-url 'h1 (string-append "/seen?key=" key)))))
                     (string->number (substring s 5 (- (string-length s) 1)))))
(define (release key) (ctl-get (face-url 'raw (string-append "/raw/release?key=" key))))

;; outcome-of : Token Natural -> Outcome   the token's outcome, or after MS a
;; cancel's, as (stalled MS OUTCOME)
(define (outcome-of token ms)
  (if (curl-token-wait token ms)
      (curl-token-outcome token)
      (begin (curl-token-cancel token)
             (curl-token-wait token 30000)
             (list 'stalled ms (curl-token-outcome token)))))

;; guarded-request : (-> Request) -> (U Request Condition)
(define (guarded thunk) (guard (e (#t e)) (thunk)))

(define (sizes-for url)
  (let ((all (take-transfer-sizes!)))
    (map cdr (filter (lambda (entry) (string=? (car entry) url)) all))))

(define (report-of outcome)
  (if (and (curl-response? outcome) (curl-response-body outcome))
      (lines-of (latin-1 (curl-response-body outcome)))
      '()))

(define (print-report report) (for-each (lambda (l) (say "  | " l)) report))

;; run-cell : Symbol String Symbol Symbol (Listof Part) (Listof Any) -> Outcome
;; One multipart transfer of PARTS, METHOD, to FACE's parts route, with
;; EXTRA keys, on an engine of its own; its line and the report printed.
(define (run-cell group label face method parts extra . more)
  (let* ((key (next-key))
         (query (if (and (pair? more) (car more)) (car more) ""))
         (url (face-url face (string-append "/parts?key=" key query)))
         (request (guarded (lambda ()
                             (apply make-curl-request url 'method method 'proxy #f 'timeout-ms 30000
                                    'body (cons 'multipart parts) (append (face-keys face) extra)))))
         (start (now-ms))
         (outcome (if (curl-request? request)
                      (with-engine (lambda (e)
                                     (let ((token (guarded (lambda () (curl-submit e request)))))
                                       (if (condition? token) token (outcome-of token 30000)))))
                      request))
         (took (- (now-ms) start))
         (report (report-of outcome)))
    (say "cell " group " " label " face=" face " method=" method " asked=" (describe-asked parts)
         " outcome=" (describe outcome) " sizes=" (sizes-for url)
         (if (curl-response? outcome) (judge parts report) "")
         " ms=" (round1 took))
    (print-report report)
    outcome))

(define (group? g) (or (not groups) (memq g groups)))

;; --- load --------------------------------------------------------------------------------

(define (load-group)
  (say "load lane=" lane " version=" (libcurl-info-version (loaded-libcurl)) " probe=" (loaded-mime-probe)
       " mime=" (loaded-mime?) " counts-after-load=" (native-counts))
  (with-engine
   (lambda (e)
     (for-each
      (lambda (spec)
        (let* ((label (car spec)) (request (cadr spec))
               (outcome (guard (c (#t c)) (curl-token-await (curl-submit e request)))))
          (say "cell load " label " outcome=" (describe outcome)
               (if (curl-response? outcome) (string-append " body=" (latin-1 (curl-response-body outcome))) ""))))
      (list (list "multipart-post"
                  (make-curl-request (face-url 'h1 (string-append "/parts?key=" (next-key))) 'method 'post 'proxy #f
                                     'body '(multipart ("a" "alpha"))))
            (list "get" (make-curl-request (face-url 'h1 "/status/200") 'proxy #f))
            (list "bytevector-post" (make-curl-request (face-url 'h1 "/sink?key=load1") 'method 'post 'proxy #f
                                                       'body (u8 "hello")))
            ))))
  (say "cell load curl-request-check outcome="
       (describe (guard (c (#t c))
                   (curl-request-check (make-curl-request (face-url 'h1 "/status/200") 'method 'post 'proxy #f
                                                          'body '(multipart ("a" "alpha"))))
                   'passed)))
  (say "load counts-at-end=" (native-counts)))

;; --- kinds, defaults ---------------------------------------------------------------------------

(define (kinds-group)
  (let ((notes (path "notes.txt")) (big (path "big.bin")))
    (write-file notes (pattern-bytes 1000))
    (write-file big (pattern-bytes (* 2 1024 1024)))
    (let ((sources (list (cons "string" "Holiday") (cons "bytes" (bytevector 104 105 0 255 13 10))
                         (cons "file" (list 'file notes))))
          (options (list (cons "none" '()) (cons "filename" '(filename "x.dat"))
                         (cons "type" '(type "application/x-chez"))
                         (cons "both" '(filename "x.dat" type "application/x-chez"))))
          (mixed (list (list "title" "Holiday") (list "photo" (list 'file notes) 'type "image/jpeg")
                       (list "notes" (bytevector 104 105) 'filename "notes.txt"))))
      (for-each
       (lambda (face)
         (for-each (lambda (s)
                     (for-each (lambda (o)
                                 (run-cell 'kinds (string-append (car s) "/" (car o)) face 'post
                                           (list (cons* "p" (cdr s) (cdr o))) '()))
                               options))
                   sources)
         (for-each (lambda (m) (run-cell 'methods (symbol->string m) face m mixed '()))
                   '(post put patch delete))
         (for-each (lambda (m) (run-cell 'methods (symbol->string m) face m mixed '()))
                   '(get head))
         (run-cell 'large "data-1048575" face 'post (list (list "big" (pattern-bytes 1048575))) '())
         (run-cell 'large "data-1048577" face 'post (list (list "big" (pattern-bytes 1048577))) '())
         (run-cell 'large "file-2MiB" face 'post (list (list "big" (list 'file big))) '())
         (run-cell 'large "two-files" face 'post (list (list "a" (list 'file notes)) (list "b" (list 'file big))) '()))
       '(h1 h2c h2)))))

(define (defaults-group)
  (let ((exts '("txt" "TXT" "htm" "html" "gif" "jpg" "jpeg" "png" "svg" "pdf" "xml" "json" "csv" "bin" "")))
    (for-each
     (lambda (ext)
       (let ((name (if (string=? ext "") "t" (string-append "t." ext))))
         (write-file (path name) (pattern-bytes 10))
         (run-cell 'defaults (string-append "file:" name) 'h1 'post (list (list "f" (list 'file (path name)))) '())
         (run-cell 'defaults (string-append "data-filename:" name) 'h1 'post (list (list "d" "v" 'filename name)) '())))
     exts)
    (write-file (path "t.txt") (pattern-bytes 10))
    (run-cell 'defaults "data-none" 'h1 'post (list (list "d" "v")) '())
    (run-cell 'defaults "file-txt-filename-bin" 'h1 'post (list (list "f" (list 'file (path "t.txt")) 'filename "o.bin")) '())
    (run-cell 'defaults "file-bin-filename-txt" 'h1 'post (list (list "f" (list 'file (path "t.bin")) 'filename "o.txt")) '())
    (run-cell 'defaults "file-noext-filename-noext" 'h1 'post (list (list "f" (list 'file (path "t")) 'filename "o")) '())
    (run-cell 'defaults "file-txt-type-given" 'h1 'post (list (list "f" (list 'file (path "t.txt")) 'type "application/x-chez")) '())
    (run-cell 'defaults "two-parts-one-name" 'h1 'post (list (list "dup" "one") (list "dup" "two")) '())
    (run-cell 'defaults "empty-data" 'h1 'post (list (list "e" "")) '())
    (write-file (path "empty.txt") (make-bytevector 0))
    (run-cell 'defaults "empty-file" 'h1 'post (list (list "e" (list 'file (path "empty.txt")))) '())))

;; --- hostile and edge bytes ------------------------------------------------------------------

(define (bytes-group)
  (let* ((controls (map integer->char (append (iota 32) (list #x7f))))
         (values-tested
          (append (map (lambda (c) (cons (string-append "x" (if (< (char->integer c) 16) "0" "") (string-downcase (number->string (char->integer c) 16)))
                                         (string #\a c #\b)))
                       controls)
                  (list (cons "sp" "a b") (cons "bang" "a!b") (cons "hash" "a#b") (cons "tilde" "a~b")
                        (cons "u0080" (string #\a (integer->char #x80) #\b))
                        (cons "quote" "a\"b") (cons "pct" "a%b") (cons "pct22" "a%22b") (cons "bslash" "a\\b")
                        (cons "semi" "a;b") (cons "eacute" "a\xe9;b") (cons "lambda" "a\x3bb;b") (cons "euro" "a\x20ac;b")
                        (cons "feff" "\xfeff;ab") (cons "empty" "")
                        (cons "crlf-header" "a\r\nX-Injected: 1")
                        (cons "dashes" "--------------------------0123456789abcdef")
                        (cons "delim" "a\r\n--------------------------0123456789abcdef--\r\nb")))))
    (for-each
     (lambda (field)
       (for-each
        (lambda (v)
          (let* ((x (cdr v))
                 (part (case field
                         ((name) (list x "v"))
                         ((filename) (list "n" "v" 'filename x))
                         ((type) (list "n" "v" 'type x))
                         ((value) (list "n" x)))))
            (run-cell 'bytes (format "~a/~a" field (car v)) 'h1 'post (list part (list "z" "zz")) '())))
        values-tested))
     '(name filename type value))))

;; --- a caller's Content-Type -----------------------------------------------------------------

(define (ctype-group)
  (for-each
   (lambda (face)
     (for-each
      (lambda (ct)
        (run-cell 'ctype (if ct (if (string=? ct "") "empty" ct) "none") face 'post
                  (list (list "a" "alpha") (list "b" "bravo"))
                  (if ct (list 'headers (list (cons "Content-Type" ct))) '())))
      (list #f "multipart/form-data" "multipart/form-data; boundary=caller-0123456789" "multipart/mixed"
            "text/plain" "")))
   '(h1 h2)))

;; --- the file check, and after it ----------------------------------------------------------------

(define (make-kind kind target)
  ;; TARGET made as KIND: missing, dir, fifo, unreadable, regular
  (case kind
    ((missing) #t)
    ((dir) (mkdir target))
    ((fifo) (sh (string-append "mkfifo " target)))
    ((unreadable) (write-file target (pattern-bytes 100)) (chmod target 0))
    ((regular) (write-file target (pattern-bytes 100)))
    (else (error 'make-kind "no kind" kind))))

(define (remove-path p)
  (cond ((file-symbolic-link? p) (delete-file p))
        ((file-directory? p) (delete-directory p))
        ((file-exists? p #f) (guard (e (#t #f)) (chmod p #o644)) (delete-file p))))

(define (check-group)
  (take-file-check-times!)
  (let ((kinds '(missing dir fifo devnull unreadable regular)))
    ;; at construction, the caller's stat
    (for-each
     (lambda (kind)
       (for-each
        (lambda (form)
          (let ((p (path (format "c-~a-~a" kind form))))
            (remove-path p)
            (if (eq? form 'itself)
                (if (eq? kind 'devnull) #t (make-kind kind p))
                (let ((target (path (format "c-~a-target" kind))))
                  (remove-path target)
                  (unless (memq kind '(devnull missing)) (make-kind kind target))
                  (sh (string-append "ln -s " (if (eq? kind 'devnull) "/dev/null" target) " " p))))
            (let ((the (if (and (eq? kind 'devnull) (eq? form 'itself)) "/dev/null" p)))
              (run-cell 'made (format "~a/~a" kind form) 'h1 'post (list (list "f" (list 'file the))) '()))))
        '(itself symlink)))
     kinds)
    ;; at the engine's check, swapped by the gate after the submit's stat
    (for-each
     (lambda (kind)
       (for-each
        (lambda (form)
          (unless (and (eq? kind 'devnull) (eq? form 'itself))
            (let ((p (path (format "e-~a-~a" kind form)))
                  (target (path (format "e-~a-target" kind))))
              (remove-path p) (remove-path target)
              (write-file p (pattern-bytes 100))
              (transfer-file-check-gate-set!
               (lambda ()
                 (transfer-file-check-gate-set! #f)
                 (if (eq? form 'itself)
                     (begin (unless (eq? kind 'unreadable) (delete-file p)) (make-kind kind p))
                     (begin (delete-file p)
                            (unless (memq kind '(devnull missing)) (make-kind kind target))
                            (sh (string-append "ln -s " (if (eq? kind 'devnull) "/dev/null" target) " " p))))))
              (run-cell 'engine-check (format "~a/~a" kind form) 'h1 'post (list (list "a" "alpha") (list "f" (list 'file p))) '())
              (transfer-file-check-gate-set! #f)
              (say "  check-ns " (take-file-check-times!)))))
        '(itself symlink)))
     kinds)))

(define (after-group)
  (for-each
   (lambda (face)
     (for-each
      (lambda (change)
        (let* ((p (path (format "a-~a-~a" face change)))
               (key (next-key))
               (url (face-url face (string-append "/parts?key=" key "&hold=1")))
               (timeout (and (eq? change 'shrunk-timeout) 3000)))
          (remove-path p)
          (write-file p (pattern-bytes 3000))
          (let* ((last? (eq? change 'grown-last))
                 (parts (if last?
                            (list (list "before" "first") (list "f" (list 'file p)))
                            (list (list "before" "first") (list "f" (list 'file p)) (list "after" "last"))))
                 (request (curl-request-with-options
                           (apply make-curl-request url 'method 'post 'proxy #f 'timeout-ms timeout
                                  'headers (list (cons "Expect" "100-continue"))
                                  'body (cons 'multipart parts) (face-keys face))
                           '(("EXPECT_100_TIMEOUT_MS" . 60000)))))
            (with-engine
             (lambda (e)
               (let* ((token (curl-submit e request))
                      (held (let wait ((n 0))
                              (cond ((>= (seen key) 1) #t)
                                    ((> n 1000) #f)
                                    (else (sleep (make-time 'time-duration 10000000 0)) (wait (+ n 1)))))))
                 (case change
                   ((none) #t)
                   ((grown grown-last) (append-file p (make-bytevector 2000 (char->integer #\Z))))
                   ((shrunk-timeout shrunk-none) (write-file p (pattern-bytes 1000)))
                   ((removed) (delete-file p))
                   ((fifo) (delete-file p) (sh (string-append "mkfifo " p))
                    (write-file (path "fifo-src") (pattern-bytes 3000))
                    (sh (string-append "(sleep 2; cat " (path "fifo-src") " > " p ") > /dev/null 2>&1 &"))))
                 (let ((released (now-ms)))
                   (release key)
                   ;; a second transfer on the same engine, 200 ms on
                   (sleep (make-time 'time-duration 200000000 0))
                   (let* ((other-start (now-ms))
                          (other (curl-submit e (make-curl-request (face-url 'h1 "/status/200") 'proxy #f 'timeout-ms 30000)))
                          (other-outcome (outcome-of other 20000))
                          (other-ms (- (now-ms) other-start))
                          (outcome (outcome-of token (if (eq? change 'shrunk-none) 6000 20000)))
                          (took (- (now-ms) released))
                          (report (report-of outcome)))
                     (say "cell after " change " face=" face " held=" held " outcome=" (describe outcome)
                          " sizes=" (sizes-for url) " release-to-end-ms=" (round1 took)
                          " other-get=" (describe other-outcome) " other-ms=" (round1 other-ms)
                          ;; judged against the file's bytes as they were: the path may
                          ;; be a FIFO now, which an open here would block on
                          (if (curl-response? outcome)
                              (judge (if last?
                                         (list (list "before" "first") (list "f" (pattern-bytes 3000) 'filename (basename p)))
                                         (list (list "before" "first") (list "f" (pattern-bytes 3000) 'filename (basename p))
                                               (list "after" "last")))
                                     report)
                              ""))
                     (print-report report))))))
            (take-file-check-times!))))
      '(none grown grown-last shrunk-timeout shrunk-none removed fifo)))
   '(h1 h2)))

;; --- the caller's stat, held in a critical section ---------------------------------------------------

(define (stat-group)
  (let ((kinds '(regular missing dir fifo devnull unreadable)))
    (for-each
     (lambda (kind)
       (for-each
        (lambda (form)
          (let* ((p (path (format "s-~a-~a" kind form)))
                 (the (if (and (eq? kind 'devnull) (eq? form 'itself)) "/dev/null" p)))
            (remove-path p)
            (if (eq? form 'itself)
                (unless (eq? kind 'devnull) (make-kind kind p))
                (let ((target (path (format "s-~a-target" kind))))
                  (remove-path target)
                  (unless (memq kind '(devnull missing)) (make-kind kind target))
                  (sh (string-append "ln -s " (if (eq? kind 'devnull) "/dev/null" target) " " p))))
            (let ((times
                   (map (lambda (i)
                          (let ((start (now-ms)))
                            (critical-section
                             (guard (e (#t #f))
                               (make-curl-request "http://127.0.0.1:9/" 'method 'post
                                                  'body (list 'multipart (list "f" (list 'file the))))))
                            (* 1000 (- (now-ms) start))))
                        (iota 200)))
                  (stats (map (lambda (i)
                                (let ((start (now-ms)))
                                  (critical-section (guard (e (#t #f)) (file-regular? the)))
                                  (* 1000 (- (now-ms) start))))
                              (iota 200))))
              (let ((sorted (list-sort < times)) (ssorted (list-sort < stats))
                    (verdict (guard (e ((curl-request-error? e) (curl-request-error-reason e)))
                               (make-curl-request "http://127.0.0.1:9/" 'method 'post
                                                  'body (list 'multipart (list "f" (list 'file the))))
                               'made)))
                (say "stat " kind "/" form " verdict=" verdict
                     " make-us min=" (round1 (car sorted)) " median=" (round1 (list-ref sorted 100))
                     " max=" (round1 (list-ref sorted 199))
                     " stat-us min=" (round1 (car ssorted)) " median=" (round1 (list-ref ssorted 100))
                     " max=" (round1 (list-ref ssorted 199)))))))
        '(itself symlink)))
     kinds)))

;; --- the header cap beside MIMEPOST ------------------------------------------------------------------

(define (cap-group)
  (let ((parts (list (list "a" "alpha") (list "b" (pattern-bytes 70000)))))
    (for-each
     (lambda (face)
       (for-each
        (lambda (lines)
          (run-cell 'cap (format "buffered/~a" lines) face 'post parts '() (format "&lines=~a" lines))
          ;; streamed
          (let* ((key (next-key))
                 (url (face-url face (format "/parts?key=~a&lines=~a" key lines)))
                 (request (apply make-curl-request url 'method 'post 'proxy #f 'timeout-ms 30000
                                 'stream-buffer 65536 'body (cons 'multipart parts) (face-keys face))))
            (with-engine
             (lambda (e)
               (let* ((token (curl-submit e request))
                      (got-head (curl-token-head-wait token 30000))
                      (head (curl-token-head token))
                      (port (curl-token-body-port token))
                      (ended (let loop ((n 0))
                               (let ((got (guard (c (#t (cons 'raised c))) (get-bytevector-some port))))
                                 (cond ((eof-object? got) (format "eof after ~a" n))
                                       ((pair? got) (format "raised ~a after ~a" (describe (cdr got)) n))
                                       (else (loop (+ n (bytevector-length got)))))))))
                 (say "cell cap " (format "streamed/~a" lines) " face=" face " head="
                      (if head (format "(~a ~a)" (curl-head-status head) (length (curl-head-headers head))) "none")
                      " port=" ended " outcome=" (describe (outcome-of token 30000)) " sizes=" (sizes-for url)))))))
        '(1000 1001)))
     '(h1 h2))))

;; --- resends, against the mime-files stand-in ------------------------------------------------------------

(define (events-for tag)
  (let ((text (ctl-get (string-append "http://127.0.0.1:" fctl-port "/events?after=0"))))
    (filter (lambda (l) (and (or (string-search l (string-append "tag=" tag " ")) (string-search l (string-append "tag=" tag ".hop")))
                             (exists (lambda (k) (string-search l k)) '(" req " " body " " part " " answer " " drop " " rst " " refused-body "))))
            (lines-of text))))

(define (resend-group)
  (let ((file (path "resend.bin")) (big (path "resend-big.bin")))
    (write-file file (pattern-bytes 3000))
    (write-file big (pattern-bytes (* 4 1024 1024)))
    (for-each
     (lambda (spec)
       (let* ((label (car spec)) (face (cadr spec)) (route (caddr spec)) (kind (cadddr spec))
              (extra (list-ref spec 4)) (warm (list-ref spec 5))
              (tag (string-append "r" (next-key)))
              (url (face-url face (string-append route (if (string-search route "?") "&" "?") "tag=" tag)))
              (parts (case kind
                       ((data) (list (list "field" "value") (list "d" (pattern-bytes 3000))))
                       ((file) (list (list "field" "value") (list "f" (list 'file file))))
                       ((big) (list (list "field" "value") (list "f" (list 'file big))))))
              (request (apply make-curl-request url 'method 'post 'proxy #f 'timeout-ms 20000
                              'body (cons 'multipart parts) (append (face-keys face) extra))))
         (with-engine
          (lambda (e)
            (when warm
              (curl-token-await (curl-submit e (make-curl-request (face-url face (string-append "/hello?tag=" tag)) 'proxy #f
                                                                  'timeout-ms 10000))))
            (let* ((request (if (string-search label "follow") (curl-request-following request) request))
                   (outcome (outcome-of (curl-submit e request) 25000)))
              (say "cell resend " label " kind=" kind " face=" face " outcome=" (describe outcome)
                   " sizes=" (sizes-for url))
              (for-each (lambda (l) (say "  | " l)) (events-for tag)))))))
     (append
      (apply append
             (map (lambda (kind)
                    (list (list "dead-reused" 'fraw "/sink?drop=1&at=body" kind '() #t)
                          (list "dead-reused-head" 'fraw "/sink?drop=1&at=head" kind '() #t)
                          (list "digest-stale" 'fraw "/digest?stale=1" kind '(credentials (digest "user" "pass")) #f)
                          (list "refused-stream-end" 'fh2c "/refuse?n=1&at=end" kind '() #f)
                          (list "refused-stream-head" 'fh2c "/refuse?n=1&at=head" kind '() #f)
                          (list "follow-307" 'fraw "/redir?code=307" kind '() #f)
                          (list "follow-308" 'fraw "/redir?code=308" kind '() #f)
                          (list "expect-417" 'fraw "/sink?expect=417" kind '(headers (("Expect" . "100-continue"))) #f)))
                  '(data file)))
      (list (list "reset-in-big-part" 'fraw "/sink?drop=1&at=head" 'big '() #t)
            (list "reset-in-big-part-2" 'fraw "/sink?drop=1&at=head" 'big '() #t)
            (list "reset-in-big-part-3" 'fraw "/sink?drop=1&at=head" 'big '() #t))))
    ;; a fresh transfer of the same request, and a hop's request made from it:
    ;; each its own mime, as the high level's retry and redirect make them
    (with-engine
     (lambda (e)
       (let* ((tag (string-append "r" (next-key)))
              (r1 (make-curl-request (face-url 'fraw (string-append "/sink?tag=" tag)) 'method 'post 'proxy #f
                                     'body (list 'multipart (list "f" (list 'file file)))))
              (o1 (outcome-of (curl-submit e r1) 20000))
              (o2 (outcome-of (curl-submit e r1) 20000))
              (r3 (make-curl-request (face-url 'fraw (string-append "/sink?tag=" tag ".hop")) 'method 'post 'proxy #f
                                     'body (curl-request-body r1)))
              (o3 (outcome-of (curl-submit e r3) 20000)))
         (say "cell resend again-and-hop kind=file outcomes=" (describe o1) " " (describe o2) " " (describe o3))
         (for-each (lambda (l) (say "  | " l)) (events-for tag)))))))

;; --- holes in what the design relies on (item 4) --------------------------------------------------------

(define (hole-group)
  (let* ((a (path "hole-a")) (b (path "hole-b")))
    (remove-path a) (remove-path b)
    (mkdir a) (mkdir b)
    (write-file (string-append a "/rel.txt") (pattern-bytes 50))
    (write-file (string-append b "/rel.txt") (make-bytevector 80 (char->integer #\B)))
    (let* ((here (current-directory))
           (r (begin (current-directory a)
                     (make-curl-request (face-url 'h1 (string-append "/parts?key=" (next-key))) 'method 'post 'proxy #f
                                        'body '(multipart ("f" (file "rel.txt")))))))
      (say "hole made-in-a body=" (curl-request-body r))
      ;; the body curl-request-body answers is the record's own list
      (let ((body (curl-request-body r)))
        (say "hole body-eq-to-record " (eq? body (curl-request-body r)))
        (set-car! (cdr (cadr (cadr body))) "rel.txt")
        (say "hole after-set-car! body=" (curl-request-body r)))
      (current-directory b)
      (with-engine
       (lambda (e)
         (let ((o (guard (c (#t c)) (curl-token-await (curl-submit e r)))))
           (say "cell hole mutated-relative-submitted-in-b outcome=" (describe o)
                " body-bytes=" (and (curl-response? o) (curl-response-body o) (bytevector-length (curl-response-body o))))
           (print-report (report-of o)))))
      ;; curl-request-with resolves again, against the current directory then
      (let ((r2 (curl-request-with r 'timeout-ms 5000)))
        (say "hole curl-request-with-in-b body=" (curl-request-body r2)))
      (current-directory here))))

;; --- under the memory gate ----------------------------------------------------------------------------------

(define (memory-group)
  (let ((file (path "mem.bin")) (big (path "mem-big.bin")) (locked (path "mem-unreadable")))
    (write-file file (pattern-bytes 3000))
    (write-file big (pattern-bytes (* 8 1024 1024)))
    (remove-path locked) (write-file locked (pattern-bytes 10)) (chmod locked 0)
    (run-cell 'memory "string" 'h1 'post (list (list "s" "Holiday")) '())
    (run-cell 'memory "bytes" 'h1 'post (list (list "b" (bytevector 1 2 3) 'filename "b.bin")) '())
    (run-cell 'memory "file" 'h1 'post (list (list "f" (list 'file file) 'type "text/plain")) '())
    (run-cell 'memory "mixed-h2" 'h2 'post (list (list "s" "x") (list "f" (list 'file file))) '())
    (run-cell 'memory "unreadable" 'h1 'post (list (list "s" "x") (list "f" (list 'file locked))) '())
    ;; a cancel, and a timeout, mid-body: the raw face's sink holds its reading;
    ;; M8S3_SLOW, under Valgrind, gives each longer
    (for-each
     (lambda (how)
       (let* ((slow (getenv "M8S3_SLOW"))
              (key (next-key))
              (url (face-url 'raw (string-append "/raw/sink?key=" key (if slow "&hold=20000" "&hold=3000"))))
              (request (make-curl-request url 'method 'post 'proxy #f
                                          'timeout-ms (if (eq? how 'timeout) (if slow 4000 700) 30000)
                                          'body (list 'multipart (list "f" (list 'file big))))))
         (with-engine
          (lambda (e)
            (let ((token (curl-submit e request)))
              (if (eq? how 'cancel)
                  (begin (if slow (sleep (make-time 'time-duration 0 4)) (sleep (make-time 'time-duration 700000000 0)))
                         (say "cell memory " how " sunk-before=" (ctl-get (face-url 'raw (string-append "/raw/sunk?key=" key))))
                         (curl-token-cancel token))
                  #t)
              (say "cell memory " how " outcome=" (describe (outcome-of token 60000)) " sizes=" (sizes-for url)))))))
     '(cancel timeout))
    (say "memory counts=" (native-counts))))

;; --- the run -----------------------------------------------------------------------------------------------------

(say "probe lane=" lane " libcurl=" (libcurl-info-version (loaded-libcurl)) " " (libcurl-info-ssl-version (loaded-libcurl))
     " mime=" (loaded-mime?) " probe=" (loaded-mime-probe))
(when (group? 'load) (load-group))
(when (loaded-mime?)
  (when (group? 'kinds) (kinds-group))
  (when (group? 'defaults) (defaults-group))
  (when (group? 'bytes) (bytes-group))
  (when (group? 'ctype) (ctype-group))
  (when (group? 'check) (check-group))
  (when (group? 'after) (after-group))
  (when (group? 'stat) (stat-group))
  (when (group? 'cap) (cap-group))
  (when (and (group? 'resend) (not (string=? fraw-port "0"))) (resend-group))
  (when (group? 'hole) (hole-group))
  (when (group? 'memory) (memory-group)))
(when (vector-ref ctl-engine-box 0) (curl-engine-stop (vector-ref ctl-engine-box 0)))
(take-transfer-sizes!)
(say "end counts=" (native-counts))
