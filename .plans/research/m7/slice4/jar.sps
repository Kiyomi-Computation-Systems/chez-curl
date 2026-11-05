#!chezscheme
;;; M7 slice 4's measurements (2026-11-03; the M7 plan, section 6.3): the
;;; cookie jar through chez-curl's engine, on the prototype
;;; (make-prototype.sh). main.sps runs the parts that need main's src/.
;;;
;;;   scheme --libdirs build/m7s4/src --program jar.sps PART KEY=VALUE ...
;;;
;;; run.sh passes the KEYs: lane; tmp, the run's temp directory; ca, the run
;;; CA; slow, a multiplier for every bound (1 natively, more under
;;; Valgrind); fswatch, the file watch's log, or none; and every stand-in
;;; face's port, FACE=PORT (standin.mjs): o, v4, v6 (or none(CODE)), h2,
;;; tls.
;;;
;;; Every request carries timeout-ms 10,000 unless named; every wait is
;;; bounded, 15,000 ms for a transfer, and a transfer still running then is
;;; cancelled and logged "hung"; every bound is multiplied by slow. Each case
;;; runs on an engine of its own, but where its item shares one.
;;;
;;; PART is one of lifetime (item 1, (a) to (f)), abandon-leave and
;;; abandon-free (item 1 (g)), setopt (item 2), order (item 3), load (item
;;; 4), readout (item 5), cost (item 6), host (item 7), h2 (item 8), rounds
;;; (item 9), twins (item 10), hsts (item 11), ipv6 (item 12), walk (the
;;; read-out walk against libcurl's own file) and lifetime-plant (item 1
;;; (c) alone, for the planted prototype).
;;;
;;; Output, one line each, every line of a case between "case ITEM NAME"
;;; and "end ITEM NAME":
;;;   t ITEM NAME step=S => OUTCOME        a transfer and what it ended with
;;;   s ITEM NAME LINE                     the stand-in's report of it
;;;   r ITEM NAME readout code=C n=N       the jar's read-out, sorted, then
;;;   r ITEM NAME line "LINE" rule=R/R     each line, and the rule's verdict,
;;;                                        as written / with #HttpOnly_ off
;;;   x ITEM NAME FACT                     any other fact
;;;   n ITEM NAME counts K=V ...           the counters at the case's end
;;; Bytes outside 0x20..0x7e, and \ and ", are written \xHH, as the
;;; stand-in writes them.
(import (chezscheme)
        (curl)
        (curl unsupported)
        (only (curl private engine) call-with-engine-held curl-cookie-jar-post-make! curl-cookie-jar-post!
              curl-cookie-jar-reply-wait curl-cookie-jar-state curl-cookie-jar-holders curl-cookie-jar-log
              curl-engine-jar-count curl-engine-live-count)
        (only (curl private transfer) set-jar-order! jar-order)
        (only (curl private counters) native-counts)
        (only (curl private native) curl-easy-init curl-easy-cleanup curl-easy-setopt-pointer
              curl-easy-setopt-long curl-easy-option call-with-c-string call-with-latin-1-c-string
              curl-share-init curl-share-setopt-int curl-share-cleanup curl-easy-getinfo-cookielist
              curl-slist-strings curl-slist-free-all curl-multi-init curl-multi-cleanup
              curl-multi-add-handle curl-multi-remove-handle curl-multi-perform curl-multi-poll
              curl-multi-info-read)
        (only (curl private memory) foreign-block free-foreign-block!))

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
           (unless kv (error 'jar.sps "not KEY=VALUE" a))
           (cons (string->symbol (car kv)) (cdr kv))))
       (cdr args)))

(define (setting key)
  (let ((hit (assq key settings)))
    (unless hit (error 'jar.sps "no such argument" key))
    (cdr hit)))

(define lane (setting 'lane))
(define ca (setting 'ca))
(define tmp (setting 'tmp))
(define slow (string->number (setting 'slow)))
(define (bound ms) (* ms slow))
(define v6-up? (and (string->number (setting 'v6)) #t))

(define (say fmt . xs)
  (apply printf fmt xs)
  (newline)
  (flush-output-port (current-output-port)))

(define (ns-of t) (+ (* (time-second t) 1000000000) (time-nanosecond t)))
(define (now-ns) (ns-of (current-time 'time-monotonic)))
(define (epoch-s) (time-second (current-time 'time-utc)))
(define (sleep-ms ms) (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))

;; --- bytes ------------------------------------------------------------------------

;; render : Bytevector -> String
;; BYTES as the stand-in escapes them: \xHH for any byte outside 0x20..0x7e,
;; and for \ and "; past 600 bytes, cut, with the count.
(define (render bytes)
  (let ((out (open-output-string)) (n (min 600 (bytevector-length bytes))))
    (do ((i 0 (+ i 1))) ((= i n))
      (let ((b (bytevector-u8-ref bytes i)))
        (if (and (>= b 32) (< b 127) (not (= b 92)) (not (= b 34)))
            (put-char out (integer->char b))
            (put-string out (string-append "\\x" (if (< b 16) "0" "") (string-downcase (number->string b 16)))))))
    (when (> (bytevector-length bytes) n)
      (put-string out (format "...(~a bytes)" (bytevector-length bytes))))
    (get-output-string out)))

;; latin-1 : String -> Bytevector
(define (latin-1 s)
  (let ((out (make-bytevector (string-length s))))
    (do ((i 0 (+ i 1))) ((= i (string-length s)) out)
      (bytevector-u8-set! out i (bitwise-and #xff (char->integer (string-ref s i)))))))

;; b : (U String Byte Bytevector) ... -> Bytevector
;; The parts, joined: a string's chars as bytes, a number as one byte, a
;; bytevector as it is. Every line is built so, from byte escapes: no
;; whitespace stands in this file as a literal inside a line.
(define (b . parts)
  (let ((pieces (map (lambda (p) (cond ((string? p) (latin-1 p))
                                       ((bytevector? p) p)
                                       (else (u8-list->bytevector (list p)))))
                     parts)))
    (let ((out (make-bytevector (apply + (map bytevector-length pieces)))))
      (let loop ((ps pieces) (at 0))
        (if (null? ps)
            out
            (begin (bytevector-copy! (car ps) 0 out at (bytevector-length (car ps)))
                   (loop (cdr ps) (+ at (bytevector-length (car ps))))))))))

(define (repeat-byte byte n) (make-bytevector n byte))

(define (hex bytes)
  (apply string-append
         (map (lambda (x) (string-append (if (< x 16) "0" "") (number->string x 16)))
              (bytevector->u8-list bytes))))

(define (bytes<? x y)
  (let ((n (min (bytevector-length x) (bytevector-length y))))
    (let loop ((i 0))
      (cond ((= i n) (< (bytevector-length x) (bytevector-length y)))
            ((< (bytevector-u8-ref x i) (bytevector-u8-ref y i)) #t)
            ((> (bytevector-u8-ref x i) (bytevector-u8-ref y i)) #f)
            (else (loop (+ i 1)))))))

(define (sorted lines) (list-sort bytes<? lines))

(define (split-bytes bv byte)
  (let loop ((i 0) (start 0) (found '()))
    (cond ((= i (bytevector-length bv))
           (reverse (cons (subbytes bv start i) found)))
          ((= (bytevector-u8-ref bv i) byte) (loop (+ i 1) (+ i 1) (cons (subbytes bv start i) found)))
          (else (loop (+ i 1) start found)))))

(define (subbytes bv start end)
  (let ((out (make-bytevector (- end start))))
    (bytevector-copy! bv start out 0 (- end start))
    out))

(define (bytes-prefix? prefix bv)
  (and (>= (bytevector-length bv) (bytevector-length prefix))
       (bytevector=? prefix (subbytes bv 0 (bytevector-length prefix)))))

(define (join strings sep)
  (if (null? strings)
      ""
      (fold-left (lambda (acc s) (string-append acc sep s)) (car strings) (cdr strings))))

(define (split-lines s)
  (let loop ((cs (string->list s)) (cur '()) (acc '()))
    (cond ((null? cs) (reverse (if (null? cur) acc (cons (list->string (reverse cur)) acc))))
          ((char=? (car cs) #\newline) (loop (cdr cs) '() (cons (list->string (reverse cur)) acc)))
          (else (loop (cdr cs) (cons (car cs) cur) acc)))))

(define (str-prefix? p s) (and (>= (string-length s) (string-length p)) (string=? p (substring s 0 (string-length p)))))

;; --- the plan's rule (section 3.5), as written, pure -------------------------------

;; rule : Bytevector Symbol -> Symbol
;; LINE judged by section 3.5's cookie-line rule: accept, or the first
;; reason it refuses, in the rule's order: fields, not seven tab-separated
;; fields; control, a field holding a byte 0x00 to 0x1F or 0x7F; empty, a
;; field empty but the value; path, a path TRUE or FALSE. READING says what
;; "#HttpOnly_ allowed before the domain" means: literal, the first field
;; as split, prefix and all; stripped, the domain after the prefix, which
;; is then the field held to "not empty".
(define httponly (b "#HttpOnly_"))
(define (rule line reading)
  (let ((fields (split-bytes line 9)))
    (if (not (= (length fields) 7))
        'fields
        (let* ((first (car fields))
               (domain (if (and (eq? reading 'stripped) (bytes-prefix? httponly first))
                           (subbytes first 10 (bytevector-length first))
                           first)))
          (cond ((exists (lambda (f) (exists (lambda (x) (or (< x 32) (= x 127))) (bytevector->u8-list f))) fields)
                 'control)
                ((exists (lambda (f) (= (bytevector-length f) 0))
                         (cons domain (list-head (cdr fields) 5)))
                 'empty)
                ((or (bytevector=? (list-ref fields 2) (b "TRUE")) (bytevector=? (list-ref fields 2) (b "FALSE")))
                 'path)
                (else 'accept))))))

(define (rule-text line) (format "~a/~a" (rule line 'literal) (rule line 'stripped)))

;; --- requests, transfers, outcomes ------------------------------------------------

(define (url host face path) (string-append "http://" host ":" (setting face) path))
(define (surl host face path) (string-append "https://" host ":" (setting face) path))

(define tag-n 0)
(define (fresh-tag)
  (set! tag-n (+ tag-n 1))
  (format "~a-~a" part tag-n))

;; q : String (Listof (Pairof String String)) -> String
(define (q tag pairs)
  (string-append "?tag=" tag
                 (apply string-append (map (lambda (p) (string-append "&" (car p) "=" (cdr p))) pairs))))

(define (sc bytes) (cons "sc" (hex bytes)))
(define (hh bytes) (cons "h" (hex bytes)))

;; req : String Any ... -> (U Request Condition)
(define (req u . keys)
  (guard (e (#t e))
    (apply make-curl-request u (append (if (memq 'timeout-ms keys) '() (list 'timeout-ms (bound 10000))) keys))))

(define (with-opts r options)
  (if (or (condition? r) (null? options)) r (guard (e (#t e)) (curl-request-with-options r options))))

(define (await token)
  (if (curl-token-wait token (bound 15000))
      (curl-token-outcome token)
      (begin (curl-token-cancel token) (curl-token-wait token (bound 5000)) 'hung)))

(define (submit engine r)
  (if (condition? r) r (guard (e (#t e)) (curl-submit engine r))))

(define (run engine r)
  (let ((t (submit engine r)))
    (if (curl-token? t) (await t) t)))

(define (classes-of e)
  (filter symbol?
          (list (and (curl-timeout? e) 'timeout) (and (curl-connect-error? e) 'connect)
                (and (curl-send-receive-error? e) 'send-receive) (and (curl-tls-error? e) 'tls)
                (and (curl-protocol-error? e) 'protocol) (and (curl-too-large? e) 'too-large))))

(define (condition-text c)
  (call-with-string-output-port (lambda (p) (display-condition c p))))

;; describe : Any -> String
(define (describe o)
  (cond ((curl-response? o)
         (format "ok status=~a version=~a url=~a connect-us=~a total-us=~a"
                 (curl-response-status o) (curl-response-http-version o) (curl-response-effective-url o)
                 (let ((t (assq 'connect (curl-response-timings o)))) (if t (cdr t) "-"))
                 (let ((t (assq 'total (curl-response-timings o)))) (if t (cdr t) "-"))))
        ((condition? o)
         (cond ((curl-transfer-error? o)
                (format "fail reason=~a code=~a classes=~a errbuf=~s"
                        (curl-transfer-error-reason o) (curl-transfer-error-code o) (classes-of o)
                        (curl-transfer-error-error-buffer o)))
               ((curl-request-error? o)
                (format "refused field=~a reason=~a" (curl-request-error-field o) (curl-request-error-reason o)))
               ((curl-engine-error? o) (format "engine-error reason=~a" (curl-engine-error-reason o)))
               (else (format "condition ~s" (condition-text o)))))
        ((eq? o 'hung) "hung")
        (else (format "other ~s" o))))

(define (report-lines o)
  (if (and (curl-response? o) (curl-response-body o))
      (filter (lambda (l) (not (string=? l "end"))) (split-lines (bytes->latin-1-string (curl-response-body o))))
      '()))

(define (bytes->latin-1-string bv) (list->string (map integer->char (bytevector->u8-list bv))))

(define (outcome-kind o)
  (cond ((curl-response? o) 'ran)
        ((and (curl-request-error? o) (eq? (curl-request-error-reason o) 'cookie-jar-closed)) 'refused)
        ((eq? o 'hung) 'hung)
        (else 'other)))

;; --- logging a case ------------------------------------------------------------------

(define current-item "-")
(define current-case "-")

(define (log-t step o)
  (say "t ~a ~a step=~a => ~a" current-item current-case step (describe o))
  (for-each (lambda (l) (say "s ~a ~a ~a" current-item current-case l)) (report-lines o)))

(define (fact fmt . xs) (say "x ~a ~a ~a" current-item current-case (apply format fmt xs)))

(define (counts-text)
  (join (map (lambda (p) (format "~a=~a" (car p) (cdr p))) (native-counts)) " "))

;; case! : String String (-> Any) -> Void
;; One case: THUNK, which stops every engine it made, then the counters.
(define (case! item name thunk)
  (set! current-item item)
  (set! current-case name)
  (say "case ~a ~a" item name)
  (guard (e (#t (fact "raised ~a" (if (condition? e) (condition-text e) (format "~s" e)))))
    (thunk))
  (say "n ~a ~a counts ~a" item name (counts-text))
  (say "end ~a ~a" item name))

;; with-engine : (Engine -> Any) -> Any
(define (with-engine proc)
  (let ((engine (make-curl-engine)))
    (let ((answer (guard (e (#t (curl-engine-stop engine) (raise e))) (proc engine))))
      (curl-engine-stop engine)
      answer)))

;; --- the jar's messages ---------------------------------------------------------------

;; make-jar : Engine [Ops] -> (Values Jar Answer)
(define (make-jar engine . maybe-ops)
  (let-values (((jar reply) (curl-cookie-jar-post-make! engine (if (null? maybe-ops) '((1 . 2)) (car maybe-ops)))))
    (values jar (or (curl-cookie-jar-reply-wait jar reply (bound 30000)) '(timeout)))))

;; jar : Engine -> Jar
(define (jar engine)
  (let-values (((j a) (make-jar engine)))
    (unless (eq? (car a) 'ok) (error 'jar "make failed" a))
    j))

(define (jar-call j kind arg)
  (or (curl-cookie-jar-reply-wait j (curl-cookie-jar-post! j kind arg) (bound 120000)) '(timeout)))

(define (answer-text a)
  (case (car a)
    ((ok) (format "ok ~s" (cadr a)))
    ((refused) (format "refused ~a" (cdr a)))
    ((raised) (format "raised ~a" (if (condition? (cadr a)) (condition-text (cadr a)) (cadr a))))
    (else (format "~s" a))))

;; load! : Jar (Listof Bytevector) -> (U (Listof Integer) Answer)
(define (load! j lines)
  (let ((a (jar-call j 'jar-load lines)))
    (if (eq? (car a) 'ok) (cadr a) a)))

;; read-out : Jar -> (U (Listof Bytevector) #f), logged whole, sorted
(define (read-out j . kind)
  (let ((a (jar-call j (if (null? kind) 'jar-read (car kind)) #f)))
    (if (eq? (car a) 'ok)
        (let ((lines (sorted (cadr (cadr a)))))
          (say "r ~a ~a readout code=~a n=~a" current-item current-case (car (cadr a)) (length lines))
          (for-each (lambda (l) (say "r ~a ~a line \"~a\" rule=~a" current-item current-case (render l) (rule-text l)))
                    lines)
          lines)
        (begin (say "r ~a ~a readout ~a" current-item current-case (answer-text a)) #f))))

(define (close! j)
  (let ((a (jar-call j 'jar-close #f)))
    (fact "close => ~a state=~a holders=~a" (answer-text a) (curl-cookie-jar-state j) (curl-cookie-jar-holders j))
    a))

(define (log-jar j name)
  (fact "jar ~a state=~a holders=~a log=~s" name (curl-cookie-jar-state j) (curl-cookie-jar-holders j)
        (curl-cookie-jar-log j)))

;; wait-for : (-> Boolean) Natural -> Boolean
(define (wait-for ready ms)
  (let ((deadline (+ (now-ns) (* (bound ms) 1000000))))
    (let loop ()
      (cond ((ready) #t)
            ((> (now-ns) deadline) #f)
            (else (sleep-ms 1) (loop))))))

;; the base Netscape line's fields, each non-default where a transfer can
;; still match it
(define (line . fields) (apply b (fold-right (lambda (f acc) (if (null? acc) (list f) (cons f (cons 9 acc)))) '() fields)))

(define (preload j lines)
  (let ((codes (load! j lines)))
    (fact "preload codes=~s" codes)))

;; ========================================================================================
;; item 1: the jar's lifetime, and the counters
;; ========================================================================================

(define (cookie-count report)
  ;; the cookie pairs in the first Cookie header of a report, and common's value
  (let ((c (find (lambda (l) (str-prefix? "cookie \"" l)) report)))
    (if (not c)
        (list 0 #f)
        (let* ((text (substring c 8 (- (string-length c) 1)))
               (body (let ((kv (split-at-char text #\:))) (if kv (cdr kv) text)))
               (pairs (let loop ((s body) (acc '()))
                        (let ((at (let find-semi ((i 0)) (cond ((= i (string-length s)) #f) ((char=? (string-ref s i) #\;) i) (else (find-semi (+ i 1)))))))
                          (if at (loop (substring s (+ at 1) (string-length s)) (cons (substring s 0 at) acc))
                              (reverse (cons s acc))))))
               (common (find (lambda (p) (str-prefix? "common=" (trim-spaces p))) pairs)))
          (list (length pairs) (and common (trim-spaces common)))))))

(define (trim-spaces s)
  (let* ((n (string-length s))
         (start (let loop ((i 0)) (if (and (< i n) (char=? (string-ref s i) #\space)) (loop (+ i 1)) i)))
         (end (let loop ((i n)) (if (and (> i start) (char=? (string-ref s (- i 1)) #\space)) (loop (- i 1)) i))))
    (substring s start end)))

;; item 1 (a) submits through the mailbox: redefine submit for it
(define (submit-to engine r mb)
  (if (condition? r) r (guard (e (#t e)) (curl-submit engine r mb))))

(define (item-1a-mailbox)
  (case! "1" "a-200-transfers-20-live"
    (lambda ()
      (with-engine
       (lambda (e)
         (let ((j (jar e)) (mb (make-curl-mailbox)) (total 200) (width 20))
           (define (request i)
             (req (url "a.localhost" 'o (string-append "/1a" (q (fresh-tag) (list (sc (b "c" (number->string i) "=v" (number->string i)))
                                                                                  (sc (b "common=" (number->string i)))))))
                  'cookie-jar j))
           (let loop ((next 0) (live 0) (done 0) (most 0) (tally '()))
             (cond
               ((= done total)
                (fact "transfers=~a most-holders=~a outcomes=~s" total most tally))
               ((and (< next total) (< live width))
                (let ((t (submit-to e (request next) mb)))
                  (if (curl-token? t)
                      (loop (+ next 1) (+ live 1) done (max most (curl-cookie-jar-holders j)) tally)
                      (begin (fact "submit ~a refused ~a" next (describe t))
                             (loop (+ next 1) live (+ done 1) most tally)))))
               (else
                (let ((t (curl-mailbox-take mb (bound 15000))))
                  (if (not t)
                      (begin (fact "mailbox empty within the bound, live=~a done=~a" live done)
                             (loop total 0 total most (cons (cons 'hung live) tally)))
                      (let* ((o (curl-token-outcome t)) (k (outcome-kind o)) (report (report-lines o))
                             (cc (cookie-count report)))
                        (say "t ~a ~a step=~a => ~a cookies-sent=~a common-sent=~a" current-item current-case done
                             (describe o) (car cc) (cadr cc))
                        (for-each (lambda (l) (say "s ~a ~a ~a" current-item current-case l)) report)
                        (loop next (- live 1) (+ done 1) most
                              (let ((hit (assq k tally)))
                                (if hit (cons (cons k (+ (cdr hit) 1)) (remq hit tally)) (cons (cons k 1) tally))))))))))
           (fact "holders-after=~a" (curl-cookie-jar-holders j))
           (read-out j)
           (close! j)
           (log-jar j "j")))))))

(define (item-1b)
  (case! "1" "b-load-submit-read-in-one-batch"
    (lambda ()
      (with-engine
       (lambda (e)
         (let* ((j (jar e))
                (r (req (url "a.localhost" 'o (string-append "/1b" (q (fresh-tag) (list (sc (b "post=set")))))) 'cookie-jar j))
                (batch (call-with-engine-held e
                         (lambda ()
                           (let* ((load (curl-cookie-jar-post! j 'jar-load (list (line "a.localhost" "FALSE" "/" "FALSE" "0" "pre" "loaded"))))
                                  (token (submit e r))
                                  (read (curl-cookie-jar-post! j 'jar-read #f)))
                             (list load token read))))))
           (let* ((load-answer (curl-cookie-jar-reply-wait j (car batch) (bound 15000)))
                  (read-answer (curl-cookie-jar-reply-wait j (caddr batch) (bound 15000)))
                  (o (if (curl-token? (cadr batch)) (await (cadr batch)) (cadr batch))))
             (fact "queued load, submit, read-out in one hold; load => ~a" (and load-answer (answer-text load-answer)))
             (log-t 1 o)
             (if (and read-answer (eq? (car read-answer) 'ok))
                 (begin
                   (fact "read-out queued after the submit: n=~a" (length (cadr (cadr read-answer))))
                   (for-each (lambda (l) (fact "read-out-after-submit line \"~a\"" (render l)))
                             (sorted (cadr (cadr read-answer)))))
                 (fact "read-out queued after the submit => ~a" read-answer))
             (fact "read-out once the transfer is done:")
             (read-out j)
             (close! j))))))))

(define (probe! j how)
  (let ((a (jar-call j 'jar-probe how)))
    (fact "probe ~a => ~a holders=~a state=~a" how (answer-text a) (curl-cookie-jar-holders j) (curl-cookie-jar-state j))))

(define (item-1c)
  (case! "1" "c-close-while-held"
    (lambda ()
      (with-engine
       (lambda (e)
         (let* ((j (jar e))
                (r1 (req (url "a.localhost" 'o (string-append "/1c" (q (fresh-tag) (list (sc (b "late1=1")) (cons "delay" (number->string (bound 400))))))) 'cookie-jar j))
                (r2 (req (url "a.localhost" 'o (string-append "/1c" (q (fresh-tag) (list (sc (b "late2=1")) (cons "delay" (number->string (bound 900))))))) 'cookie-jar j))
                (t1 (submit e r1))
                (t2 (submit e r2)))
           (fact "both held: ~a holders=~a" (wait-for (lambda () (= (curl-cookie-jar-holders j) 2)) 5000) (curl-cookie-jar-holders j))
           (probe! j 'attached)
           (probe! j 'detached)
           (close! j)
           (probe! j 'detached)
           (read-out j)
           (fact "peek while closing:")
           (read-out j 'jar-peek)
           (let ((o1 (await t1)))
             (log-t 1 o1)
             (fact "after t1: holders=~a state=~a" (curl-cookie-jar-holders j) (curl-cookie-jar-state j))
             (probe! j 'detached)
             (fact "peek after t1's Set-Cookie, which arrived after the close:")
             (read-out j 'jar-peek))
           (let ((o2 (await t2)))
             (log-t 2 o2)
             (fact "after t2: holders=~a state=~a" (curl-cookie-jar-holders j) (curl-cookie-jar-state j)))
           (read-out j)
           (read-out j 'jar-peek)
           (let ((o3 (run e (req (url "a.localhost" 'o (string-append "/1c" (q (fresh-tag) '()))) 'cookie-jar j))))
             (log-t 3 o3))
           (log-jar j "j")
           (fact "engine jars=~a" (curl-engine-jar-count e))))))))

;; spin-until : Integer -> Void
;; Natively, a spin to the monotonic time T in ns; under Valgrind, which runs
;; one thread at a time, sleeps of 1 ms, so the other thread runs.
(define (spin-until t)
  (if (> slow 1)
      (let loop () (when (< (now-ns) t) (sleep-ms 1) (loop)))
      (let loop () (when (< (now-ns) t) (loop)))))

(define (item-1d)
  (case! "1" "d-close-crossing-submit"
    (lambda ()
      (with-engine
       (lambda (e)
         (let* ((n 500) (w-us (* 1500 slow)))
           (let loop ((i 0) (tally '()) (anomalies 0))
             (if (= i n)
                 (fact "crossings=~a window-us=~a outcomes=~s anomalies=~a" n w-us tally anomalies)
                 (let* ((j (jar e))
                        ;; every offset in [-W, W), in a scattered order
                        (offset-us (- (* (mod (* i 7919) n) (/ (* 2 w-us) n)) w-us))
                        (box (vector #f))
                        (lock (make-mutex))
                        (r (req (url "a.localhost" 'o (string-append "/1d" (q (fresh-tag) (list (sc (b "d=1")))))) 'cookie-jar j))
                        (go (+ (now-ns) (* (bound 3) 1000000))))
                   (fork-thread
                    (lambda ()
                      (spin-until go)
                      (let ((t (submit e r)))
                        (with-mutex lock (vector-set! box 0 (list t (now-ns)))))))
                   (spin-until (+ go (exact (round (* offset-us 1000)))))
                   (let* ((closed-at (now-ns))
                          (c (jar-call j 'jar-close #f))
                          (got (wait-for (lambda () (with-mutex lock (vector-ref box 0))) 5000))
                          (entry (with-mutex lock (vector-ref box 0)))
                          (t (and entry (car entry)))
                          (o (cond ((not entry) 'thread-gave-nothing)
                                   ((curl-token? t) (await t))
                                   (else t)))
                          (k (cond ((and (condition? t) (curl-request-error? t)
                                         (eq? (curl-request-error-reason t) 'cookie-jar-closed))
                                    'refused-at-submit)
                                   ((curl-response? o) 'ran)
                                   ((and (condition? o) (curl-request-error? o)
                                         (eq? (curl-request-error-reason o) 'cookie-jar-closed))
                                    'refused-at-setup)
                                   (else 'other)))
                          (settled (wait-for (lambda () (eq? (curl-cookie-jar-state j) 'closed)) 5000))
                          (bad (or (not got) (eq? k 'other) (not settled) (not (= (curl-cookie-jar-holders j) 0)))))
                     (say "t ~a ~a step=~a offset-us=~a submit-minus-close-us=~a => ~a ~a close=~a state=~a holders=~a"
                          current-item current-case i (exact->inexact offset-us)
                          (if entry (exact->inexact (/ (round (/ (- (cadr entry) closed-at) 100)) 10)) "-")
                          k (if (eq? k 'other) (describe o) "") (answer-text c)
                          (curl-cookie-jar-state j) (curl-cookie-jar-holders j))
                     (for-each (lambda (l) (say "s ~a ~a ~a" current-item current-case l)) (report-lines o))
                     (loop (+ i 1)
                           (let ((hit (assq k tally)))
                             (if hit (cons (cons k (+ (cdr hit) 1)) (remq hit tally)) (cons (cons k 1) tally)))
                           (if bad (+ anomalies 1) anomalies)))))))
         (fact "engine jars=~a live=~a" (curl-engine-jar-count e) (curl-engine-live-count e))))))
  ;; The control: each outcome reached on purpose.
  (case! "1" "d-control"
    (lambda ()
      (with-engine
       (lambda (e)
         ;; ran: the submit, then the close
         (let* ((j (jar e))
                (t (submit e (req (url "a.localhost" 'o (string-append "/1d" (q (fresh-tag) '()))) 'cookie-jar j)))
                (c (jar-call j 'jar-close #f))
                (o (if (curl-token? t) (await t) t)))
           (fact "control submit-then-close => ~a ~a close=~a" (outcome-kind o) (describe o) (answer-text c)))
         ;; refused at setup: the close queued, then the submit, in one hold
         (let* ((j (jar e))
                (r (req (url "a.localhost" 'o (string-append "/1d" (q (fresh-tag) '()))) 'cookie-jar j))
                (pair (call-with-engine-held e
                        (lambda ()
                          (let* ((c (curl-cookie-jar-post! j 'jar-close #f)) (t (submit e r))) (cons c t)))))
                (c (curl-cookie-jar-reply-wait j (car pair) (bound 15000)))
                (t (cdr pair))
                (o (if (curl-token? t) (await t) t)))
           (fact "control close-queued-then-submit => ~a ~a token?=~a close=~a" (outcome-kind o) (describe o)
                 (curl-token? t) (and c (answer-text c))))
         ;; refused at submit: the close answered, then the submit
         (let* ((j (jar e))
                (c (jar-call j 'jar-close #f))
                (t (submit e (req (url "a.localhost" 'o (string-append "/1d" (q (fresh-tag) '()))) 'cookie-jar j))))
           (fact "control close-then-submit => token?=~a ~a close=~a" (curl-token? t)
                 (if (curl-token? t) (describe (await t)) (describe t)) (answer-text c)))
         ;; another engine's jar
         (let* ((j (jar e))
                (t (with-engine (lambda (e2) (submit e2 (req (url "a.localhost" 'o "/1d") 'cookie-jar j))))))
           (fact "control another-engine's-jar => token?=~a ~a" (curl-token? t) (describe t))
           (close! j)))))))

(define (item-1e)
  (case! "1" "e-stop-with-live-and-closing"
    (lambda ()
      (let* ((e (make-curl-engine))
             (j1 (jar e))
             (j2 (jar e)))
        (preload j1 (list (line "a.localhost" "FALSE" "/" "FALSE" "0" "e1" "1")))
        (let ((t (submit e (req (url "a.localhost" 'o (string-append "/1e" (q (fresh-tag) (list (cons "delay" (number->string (bound 3000))))))) 'cookie-jar j2))))
          (fact "held: ~a" (wait-for (lambda () (= (curl-cookie-jar-holders j2) 1)) 5000))
          (close! j2)
          (fact "before stop: j1 state=~a holders=~a; j2 state=~a holders=~a; engine jars=~a"
                (curl-cookie-jar-state j1) (curl-cookie-jar-holders j1) (curl-cookie-jar-state j2)
                (curl-cookie-jar-holders j2) (curl-engine-jar-count e))
          (curl-engine-stop e)
          (log-t 1 (await t))
          (log-jar j1 "j1")
          (log-jar j2 "j2")
          (fact "after stop: engine jars=~a; a read-out => ~a" (curl-engine-jar-count e)
                (guard (x (#t (describe x))) (curl-cookie-jar-post! j1 'jar-read #f) "queued")))))))

(define (item-1f)
  (case! "1" "f-freed-share-then-pooled-connections"
    (lambda ()
      (with-engine
       (lambda (e)
         (let ((j (jar e)))
           (log-t 1 (run e (req (url "a.localhost" 'o (string-append "/1f" (q (fresh-tag) (list (sc (b "f1=1")))))) 'cookie-jar j)))
           (log-t 2 (run e (req (url "a.localhost" 'h2 (string-append "/1f" (q (fresh-tag) (list (sc (b "f2=1"))))))
                                'cookie-jar j 'http-version 'http/2-prior-knowledge)))
           (read-out j)
           (close! j)
           (log-jar j "j")
           (log-t 3 (run e (req (url "a.localhost" 'o (string-append "/1f" (q (fresh-tag) '()))))))
           (log-t 4 (run e (req (url "a.localhost" 'h2 (string-append "/1f" (q (fresh-tag) '()))) 'http-version 'http/2-prior-knowledge)))
           (let ((j2 (jar e)))
             (log-t 5 (run e (req (url "a.localhost" 'o (string-append "/1f" (q (fresh-tag) (list (sc (b "f5=1")))))) 'cookie-jar j2)))
             (log-t 6 (run e (req (url "a.localhost" 'h2 (string-append "/1f" (q (fresh-tag) (list (sc (b "f6=1"))))))
                                  'cookie-jar j2 'http-version 'http/2-prior-knowledge)))
             (read-out j2)
             (close! j2))
           (fact "engine jars=~a" (curl-engine-jar-count e))))))))

(define (part-lifetime)
  (item-1a-mailbox)
  (item-1b)
  (item-1c)
  (item-1d)
  (item-1e)
  (item-1f))

;; item 1 (g): curl_share_cleanup beside an easy handle still in a multi
;; handle, on this thread, through native's counted wrappers. LEAVE says
;; whether to stop where fail-engine! would, the handle abandoned.
(define (part-abandon leave)
  (case! "1" (if leave "g-abandoned-left" "g-abandoned-then-freed")
    (lambda ()
      (let* ((share (curl-share-init))
             (share-code (curl-share-setopt-int share 1 2))
             (multi (curl-multi-init))
             (easy (curl-easy-init))
             (share-id (car (curl-easy-option "SHARE")))
             (attach (curl-easy-setopt-pointer easy share-id share)))
        (fact "share setopt SHARE COOKIE => ~a; easy SHARE => ~a" share-code attach)
        (fact "share cleanup, the handle attached, not added => ~a" (curl-share-cleanup share))
        (fact "add => ~a" (curl-multi-add-handle multi easy))
        (fact "share cleanup, the handle in a live multi handle, before any transfer => ~a" (curl-share-cleanup share))
        ;; a transfer run to its end, the handle left added, as an engine's
        ;; that failed before it could take the handle out
        (fact "URL => ~a" (call-with-c-string (url "a.localhost" 'o (string-append "/1g" (q (fresh-tag) (list (sc (b "g=1"))))))
                            (lambda (a) (curl-easy-setopt-pointer easy (car (curl-easy-option "URL")) a))))
        (fact "COOKIEFILE \"\" => ~a" (call-with-c-string "" (lambda (a) (curl-easy-setopt-pointer easy (car (curl-easy-option "COOKIEFILE")) a))))
        (fact "performed => ~a" (perform-added multi))
        (fact "share cleanup, the transfer done, the handle in a live multi handle => ~a" (curl-share-cleanup share))
        (fact "counts ~a" (counts-text))
        (fact "multi cleanup, the handle still added => ~a" (curl-multi-cleanup multi))
        (fact "share cleanup, the handle in a cleaned-up multi handle => ~a" (curl-share-cleanup share))
        (fact "counts ~a" (counts-text))
        (unless leave
          (curl-easy-cleanup easy)
          (fact "easy cleaned up; share cleanup => ~a" (curl-share-cleanup share)))))))

;; perform-added : Natural -> List
;; MULTI's transfers stepped to their end, within 10 s, none taken out: the
;; messages read.
(define (perform-added multi)
  (let ((slot (foreign-block 8)) (deadline (+ (now-ns) (* (bound 10000) 1000000))))
    (let loop ((seen '()))
      (let-values (((code running) (curl-multi-perform multi slot)))
        (let ((messages (let drain ((acc '()))
                          (let ((m (curl-multi-info-read multi slot)))
                            (if m (drain (cons (list (car m) (caddr m)) acc)) acc)))))
          (if (or (= running 0) (> (now-ns) deadline) (not (= code 0)))
              (begin (free-foreign-block! slot) (list 'perform code 'running running 'messages (append seen messages)))
              (begin (curl-multi-poll multi 100) (loop (append seen messages)))))))))

;; ========================================================================================
;; item 2: curl_share_setopt's answers, and what each share carries
;; ========================================================================================

(define lock-values '(0 1 2 3 4 5 6 7 8 9 99 -1))

(define (part-setopt)
  (case! "2" "answers"
    (lambda ()
      (for-each
       (lambda (v)
         (let ((s (curl-share-init)))
           (fact "fresh SHARE ~a => ~a" v (curl-share-setopt-int s 1 v))
           (fact "cleanup => ~a" (curl-share-cleanup s)))
         (let ((s (curl-share-init)))
           (fact "fresh UNSHARE ~a => ~a" v (curl-share-setopt-int s 2 v))
           (fact "cleanup => ~a" (curl-share-cleanup s)))
         (let* ((s (curl-share-init)) (first (curl-share-setopt-int s 1 2)))
           (fact "after SHARE 2 (=> ~a), UNSHARE ~a => ~a" first v (curl-share-setopt-int s 2 v))
           (fact "cleanup => ~a" (curl-share-cleanup s))))
       lock-values)
      ;; options outside the enum, and setopt on a share in use
      (let ((s (curl-share-init)))
        (fact "option 0 (NONE) value 2 => ~a" (curl-share-setopt-int s 0 2))
        (fact "option 6 (LAST) value 2 => ~a" (curl-share-setopt-int s 6 2))
        (fact "option 99 value 2 => ~a" (curl-share-setopt-int s 99 2))
        (fact "cleanup => ~a" (curl-share-cleanup s)))
      (let* ((s (curl-share-init)) (easy (curl-easy-init))
             (id (car (curl-easy-option "SHARE"))))
        (fact "SHARE 2 => ~a; attach => ~a" (curl-share-setopt-int s 1 2) (curl-easy-setopt-pointer easy id s))
        (fact "in use: SHARE 3 => ~a, UNSHARE 2 => ~a" (curl-share-setopt-int s 1 3) (curl-share-setopt-int s 2 2))
        (fact "in use: cleanup => ~a" (curl-share-cleanup s))
        (curl-easy-cleanup easy)
        (fact "after the handle's cleanup: cleanup => ~a" (curl-share-cleanup s)))))
  (for-each
   (lambda (spec)
     (let ((name (car spec)) (ops (cdr spec)))
       (case! "2" name
         (lambda ()
           (with-engine
            (lambda (e)
              (let-values (((j a) (make-jar e ops)))
                (fact "make ops=~s => ~a" ops (answer-text a))
                (when (eq? (car a) 'ok)
                  (log-t 1 (run e (req (url "a.localhost" 'o (string-append "/2" (q (fresh-tag) (list (sc (b "k=1")))))) 'cookie-jar j)))
                  (log-t 2 (run e (req (url "a.localhost" 'o (string-append "/2" (q (fresh-tag) '()))) 'cookie-jar j)))
                  (read-out j)
                  (close! j)))))))))
   (append (map (lambda (v) (cons (format "carry-SHARE-~a" v) (list (cons 1 v)))) lock-values)
           (map (lambda (v) (cons (format "carry-SHARE-2-UNSHARE-~a" v) (list (cons 1 2) (cons 2 v)))) lock-values)
           (list (cons "carry-none" '())))))

;; ========================================================================================
;; item 3: the order on each transfer
;; ========================================================================================

(define fswatch (setting 'fswatch))

(define (fswatch-lines)
  (if (string=? fswatch "none")
      '()
      (guard (e (#t '()))
        (let ((bytes (call-with-port (open-file-input-port fswatch) get-bytevector-all)))
          (if (eof-object? bytes) '() (split-lines (bytes->latin-1-string bytes)))))))

(define (empty-opens before after)
  (let ((new (list-tail after (min (length before) (length after)))))
    (filter (lambda (l) (let ((n (string-length l))) (and (>= n 3) (string=? (substring l (- n 3) n) " \"\"")))) new)))

(define (part-order)
  ;; the detector: libcurl's own fopen of a cookie file, on a scratch
  ;; handle of this thread's, which the watch must log, so an empty count
  ;; below says something. A Chez foreign-procedure of fopen would not do:
  ;; Chez looks the name up in libcurl's own handle, past the preload.
  (case! "3" "detector"
    (lambda ()
      (let* ((before (fswatch-lines))
             (easy (curl-easy-init))
             (set-str (lambda (n s) (call-with-c-string s (lambda (a) (curl-easy-setopt-pointer easy (car (curl-easy-option n)) a))))))
        (fact "COOKIEFILE /nonexistent-m7s4-detector => ~a" (set-str "COOKIEFILE" "/nonexistent-m7s4-detector"))
        (fact "URL => ~a" (set-str "URL" (url "a.localhost" 'o (string-append "/3" (q (fresh-tag) '())))))
        (fact "transfer => ~a" (scratch-transfer easy))
        (curl-easy-cleanup easy)
        (let* ((want " \"/nonexistent-m7s4-detector\"")
               (k (string-length want))
               (seen (filter (lambda (l) (let ((n (string-length l)))
                                           (and (>= n k) (string=? (substring l (- n k) n) want))))
                             (list-tail (fswatch-lines) (length before)))))
          (fact "detector opens: ~a ~s" (length seen) seen)))))
  (for-each
   (lambda (order)
     (case! "3" (symbol->string order)
       (lambda ()
         (set-jar-order! order)
         (fact "jar-order=~a fswatch=~a" (jar-order) (if (string=? fswatch "none") "none" "on"))
         (let ((before (fswatch-lines)))
           (with-engine
            (lambda (e)
              (let ((j (jar e)))
                (log-t 1 (run e (req (url "a.localhost" 'o (string-append "/3" (q (fresh-tag) (list (sc (b "o1=1")) (sc (b "od=1; Domain=a.localhost")))))) 'cookie-jar j)))
                (fact "after transfer 1:")
                (read-out j)
                (preload j (list (line "a.localhost" "FALSE" "/" "FALSE" "0" "o2" "loaded")))
                (log-t 2 (run e (req (url "a.localhost" 'o (string-append "/3" (q (fresh-tag) '()))) 'cookie-jar j)))
                (log-t 3 (run e (req (url "b.a.localhost" 'o (string-append "/3" (q (fresh-tag) (list (sc (b "o3=1")))))) 'cookie-jar j)))
                (read-out j)
                (close! j))))
           (let ((opens (empty-opens before (fswatch-lines))))
             (fact "empty-path opens during the case: ~a ~s" (length opens) opens)))
         (set-jar-order! 'share-first))))
   '(share-first file-first)))

;; ========================================================================================
;; item 4: loading lines
;; ========================================================================================

;; the base line's fields: domain, tail-match, path, secure, expiry, name, value
(define base-fields (list (b "a.localhost") (b "FALSE") (b "/") (b "FALSE") (b "0") (b "nm") (b "val")))
(define field-names '(domain tailmatch path secure expiry name value))

(define (with-field fields i value)
  (let loop ((k 0) (fs fields) (out '()))
    (if (null? fs) (reverse out) (loop (+ k 1) (cdr fs) (cons (if (= k i) value (car fs)) out)))))

(define (fields->line fields) (apply line fields))

;; the byte classes, each (NAME . BYTES), set into a field after its first byte
(define byte-classes
  (list (cons "x01" (b 1)) (cons "x09" (b 9)) (cons "x0a" (b 10)) (cons "x0d" (b 13)) (cons "x1f" (b 31))
        (cons "x7f" (b 127)) (cons "x80" (b 128)) (cons "xe9" (b 233)) (cons "xff" (b 255))
        (cons "utf8-e-acute" (b 195 169)) (cons "space" (b 32)) (cons "semicolon" (b ";"))
        (cons "equals" (b "=")) (cons "comma" (b ",")) (cons "quote" (b 34))))

(define (insert-class value bytes)
  (if (= (bytevector-length value) 0)
      bytes
      (b (subbytes value 0 1) bytes (subbytes value 1 (bytevector-length value)))))

;; load-cases : -> (Listof (List Name Line Host Path))
(define (load-cases)
  (let* ((now (epoch-s))
         (ahead (number->string (+ now 86400)))
         (base (lambda (i v) (fields->line (with-field base-fields i v))))
         (cases '()))
    (define (add! name bytes host path) (set! cases (cons (list name bytes host path) cases)))
    (add! "base" (fields->line base-fields) "a.localhost" "/")
    (for-each
     (lambda (i)
       (let ((fname (list-ref field-names i)) (value (list-ref base-fields i)))
         (for-each
          (lambda (cls)
            (add! (format "~a-~a" fname (car cls)) (base i (insert-class value (cdr cls))) "a.localhost" "/"))
          byte-classes)
         (add! (format "~a-leading-spaces" fname) (base i (b 32 32 value)) "a.localhost" "/")
         (add! (format "~a-trailing-spaces" fname) (base i (b value 32 32)) "a.localhost" "/")))
     '(0 1 2 3 4 5 6))
    ;; the domain
    (add! "domain-httponly-alone" (base 0 (b "#HttpOnly_")) "a.localhost" "/")
    (add! "domain-httponly" (base 0 (b "#HttpOnly_a.localhost")) "a.localhost" "/")
    (add! "domain-httponly-twice" (base 0 (b "#HttpOnly_#HttpOnly_a.localhost")) "a.localhost" "/")
    (add! "domain-httponly-lower" (base 0 (b "#httponly_a.localhost")) "a.localhost" "/")
    (add! "domain-httponly-upper" (base 0 (b "#HTTPONLY_a.localhost")) "a.localhost" "/")
    (add! "domain-hash" (base 0 (b "#a.localhost")) "a.localhost" "/")
    (add! "domain-set-cookie" (base 0 (b "Set-Cookie:a.localhost")) "a.localhost" "/")
    (add! "domain-set-cookie-lower" (base 0 (b "set-cookie:a.localhost")) "a.localhost" "/")
    (add! "domain-dot-tailmatch-false" (base 0 (b ".a.localhost")) "a.localhost" "/")
    (add! "domain-dot-tailmatch-true" (fields->line (with-field (with-field base-fields 0 (b ".a.localhost")) 1 (b "TRUE"))) "b.a.localhost" "/")
    (add! "domain-upper" (base 0 (b "A.LOCALHOST")) "a.localhost" "/")
    (add! "domain-ip" (base 0 (b "127.0.0.1")) "127.0.0.1" "/")
    (add! "domain-ipv6" (base 0 (b "[::1]")) "[::1]" "/")
    (add! "domain-port" (base 0 (b "a.localhost:" (setting 'o))) "a.localhost" "/")
    ;; the tail-match and secure fields
    (for-each
     (lambda (v)
       (add! (format "tailmatch-~a" (if (string=? v "") "empty" v)) (base 1 (b v)) "b.a.localhost" "/")
       (add! (format "secure-~a" (if (string=? v "") "empty" v)) (base 3 (b v)) "a.localhost" "/"))
     '("TRUE" "FALSE" "true" "false" "yes" "1" "0" ""))
    ;; the path
    (for-each
     (lambda (v)
       (add! (format "path-~a" (cond ((string=? v "") "empty") ((string=? v "/") "slash") (else v))) (base 2 (b v)) "a.localhost" "/a/x"))
     '("/" "/a" "rel" "TRUE" "FALSE" "true" ""))
    ;; the expiry
    (for-each
     (lambda (p)
       (add! (format "expiry-~a" (car p)) (base 4 (cdr p)) "a.localhost" "/"))
     (list (cons "0" (b "0")) (cons "1" (b "1")) (cons "day-ahead" (b ahead)) (cons "99999999999" (b "99999999999"))
           (cons "int64-max" (b "9223372036854775807")) (cons "int64-max+1" (b "9223372036854775808"))
           (cons "minus-1" (b "-1")) (cons "plus-5" (b "+5")) (cons "0x10" (b "0x10")) (cons "abc" (b "abc"))
           (cons "1e3" (b "1e3")) (cons "empty" (b "")) (cons "leading-space" (b 32 ahead)) (cons "trailing-space" (b ahead 32))))
    ;; the name and the value
    (add! "name-empty" (base 5 (b "")) "a.localhost" "/")
    (add! "name-equals" (base 5 (b "=")) "a.localhost" "/")
    (add! "name-a=b" (base 5 (b "a=b")) "a.localhost" "/")
    (add! "name-4096" (base 5 (repeat-byte 110 4096)) "a.localhost" "/")
    (add! "name-5000" (base 5 (repeat-byte 110 5000)) "a.localhost" "/")
    (add! "value-empty" (base 6 (b "")) "a.localhost" "/")
    (add! "value-4096" (base 6 (repeat-byte 118 4096)) "a.localhost" "/")
    (add! "value-5000" (base 6 (repeat-byte 118 5000)) "a.localhost" "/")
    (add! "value-8100" (base 6 (repeat-byte 118 8100)) "a.localhost" "/")
    (add! "value-8200" (base 6 (repeat-byte 118 8200)) "a.localhost" "/")
    (add! "value-100000" (base 6 (repeat-byte 118 100000)) "a.localhost" "/")
    ;; the field count, and the commands
    (add! "six-fields" (apply line (list-head base-fields 6)) "a.localhost" "/")
    (add! "eight-fields" (apply line (append base-fields (list (b "x")))) "a.localhost" "/")
    (for-each (lambda (c) (add! (format "command-~a" c) (b c) "a.localhost" "/")) '("ALL" "SESS" "FLUSH" "RELOAD" "all"))
    (reverse cases)))

(define (part-load)
  (case! "4" "nul"
    (lambda ()
      (let ((s (string #\a #\. #\l #\nul #\x)))
        (fact "call-with-c-string of a line holding U+0000 => ~a"
              (guard (e (#t (if (curl-embedded-nul? e) "embedded-nul" (condition-text e))))
                (call-with-c-string s (lambda (a) "handed to C"))))
        (fact "call-with-latin-1-c-string of a line holding U+0000 => ~a"
              (guard (e (#t (if (curl-embedded-nul? e) "embedded-nul" (condition-text e))))
                (call-with-latin-1-c-string s (lambda (a) "handed to C"))))
        (fact "the prototype's load of bytes holding 0 => ~a"
              (guard (e (#t (condition-text e)))
                (with-engine (lambda (en) (let ((j (jar en))) (curl-cookie-jar-post! j 'jar-load (list (b "a" 0 "b"))) "queued"))))))))
  (for-each
   (lambda (c)
     (let ((name (car c)) (bytes (cadr c)) (host (caddr c)) (path (cadddr c)))
       (case! "4" name
         (lambda ()
           (fact "line \"~a\" rule=~a" (render bytes) (rule-text bytes))
           (with-engine
            (lambda (e)
              (let ((j (jar e)))
                (fact "load => ~s" (load! j (list bytes)))
                (let ((lines (read-out j)))
                  (transfer-or-poll e j host path)
                  (close! j)
                  ;; the round trip: each read-out line into a fresh jar
                  (when (and lines (pair? lines))
                    (let ((j2 (jar e)))
                      (fact "round-trip load => ~s" (load! j2 lines))
                      (let* ((a (jar-call j2 'jar-read #f))
                             (again (and (eq? (car a) 'ok) (sorted (cadr (cadr a))))))
                        (fact "round-trip ~a n=~a" (if (and again (= (length again) (length lines)) (for-all bytevector=? again lines)) "same" "DIFFERS")
                              (if again (length again) "-"))
                        (when (and again (not (and (= (length again) (length lines)) (for-all bytevector=? again lines))))
                          (for-each (lambda (l) (fact "round-trip line \"~a\"" (render l))) again)))
                      (close! j2)))))))))))
   (load-cases))
  ;; two lines, one of them past the Cookie header's cap, each order of
  ;; the two names' lengths: what the header holds
  (for-each
   (lambda (spec)
     (case! "4" (car spec)
       (lambda ()
         (for-each (lambda (l) (fact "line \"~a\" rule=~a" (render l) (rule-text l))) (cdr spec))
         (with-engine
          (lambda (e)
            (let ((j (jar e)))
              (fact "load => ~s" (load! j (cdr spec)))
              (read-out j)
              (transfer-or-poll e j "a.localhost" "/")
              (close! j)))))))
   (list (list "two-lines-big-name-longer"
               (line "a.localhost" "FALSE" "/" "FALSE" "0" "a" "1")
               (line "a.localhost" "FALSE" "/" "FALSE" "0" "nm" (repeat-byte 118 9000)))
         (list "two-lines-big-name-shorter"
               (line "a.localhost" "FALSE" "/" "FALSE" "0" "aa" "1")
               (line "a.localhost" "FALSE" "/" "FALSE" "0" "z" (repeat-byte 118 9000))))))

;; transfer-or-poll : Engine Jar String String -> Void
;; One transfer to HOST and PATH with the jar, logged; when it ends with no
;; response, the stand-in's report of its tag, by a poll, after the
;; connection closed: an unterminated head is reported there alone.
(define (transfer-or-poll e j host path)
  (let* ((tag (fresh-tag))
         (o (run e (req (url host 'o (string-append path (q tag '()))) 'cookie-jar j))))
    (log-t 1 o)
    (unless (curl-response? o)
      (sleep-ms (bound 200))
      (fact "polled the stand-in for the failed transfer's tag:")
      (let ((p (run e (req (url "a.localhost" 'o (string-append "/poll?of=" tag))))))
        (for-each (lambda (l) (say "s ~a ~a ~a" current-item current-case l)) (report-lines p))))))

;; ========================================================================================
;; item 5: reading out what Set-Cookie stored
;; ========================================================================================

(define (readout-cases)
  (let ((cases '()))
    (define (add! name host lines) (set! cases (cons (list name host lines) cases)))
    (for-each
     (lambda (cls)
       (add! (format "name-~a" (car cls)) "a.localhost" (list (b "n" (cdr cls) "m=v")))
       (add! (format "value-~a" (car cls)) "a.localhost" (list (b "nm=v" (cdr cls) "w"))))
     (append (filter (lambda (c) (not (string=? (car c) "x0a"))) byte-classes) (list (cons "nul" (b 0)))))
    (add! "name-leading-spaces" "a.localhost" (list (b 32 32 "nm=v")))
    (add! "name-trailing-spaces" "a.localhost" (list (b "nm" 32 32 "=v")))
    (add! "value-leading-spaces" "a.localhost" (list (b "nm=" 32 32 "vw")))
    (add! "value-trailing-spaces" "a.localhost" (list (b "nm=vw" 32 32)))
    (for-each (lambda (p) (add! (format "path-~a" (car p)) "a.localhost" (list (b "p=1;" 32 "Path=" (cdr p)))))
              '(("empty" . "") ("rel" . "rel") ("TRUE" . "TRUE") ("FALSE" . "FALSE")))
    (for-each (lambda (d) (add! (format "domain-~a" (car d)) "b.a.localhost" (list (b "d=1;" 32 "Domain=" (cdr d)))))
              '(("a.localhost" . "a.localhost") ("dot-a.localhost" . ".a.localhost") ("upper" . "A.LOCALHOST")
                ("empty" . "") ("localhost" . "localhost") ("child" . "c.b.a.localhost") ("own" . "b.a.localhost")))
    (add! "max-age-minus-1" "a.localhost" (list (b "ma=1;" 32 "Max-Age=-1")))
    (add! "httponly" "a.localhost" (list (b "h=1;" 32 "HttpOnly")))
    (add! "persistent" "a.localhost" (list (b "pe=1;" 32 "Max-Age=86400")))
    (reverse cases)))

(define (part-readout)
  (for-each
   (lambda (c)
     (let ((name (car c)) (host (cadr c)) (lines (caddr c)))
       (case! "5" name
         (lambda ()
           (with-engine
            (lambda (e)
              (let ((j (jar e)))
                (for-each (lambda (l) (fact "set-cookie \"~a\"" (render l))) lines)
                (log-t 1 (run e (req (url host 'o (string-append "/5" (q (fresh-tag) (map sc lines)))) 'cookie-jar j)))
                (read-out j)
                (close! j))))))))
   (readout-cases))
  ;; a deletion: set, then delete
  (case! "5" "deletion"
    (lambda ()
      (with-engine
       (lambda (e)
         (let ((j (jar e)))
           (log-t 1 (run e (req (url "a.localhost" 'o (string-append "/5" (q (fresh-tag) (list (sc (b "del=1")) (sc (b "keep=1")))))) 'cookie-jar j)))
           (log-t 2 (run e (req (url "a.localhost" 'o (string-append "/5" (q (fresh-tag) (list (sc (b "del=;" 32 "Max-Age=0")))))) 'cookie-jar j)))
           (read-out j)
           (log-t 3 (run e (req (url "a.localhost" 'o (string-append "/5" (q (fresh-tag) '()))) 'cookie-jar j)))
           (close! j)))))))

;; ========================================================================================
;; item 6: the cost of a load and a read-out
;; ========================================================================================

(define (part-cost)
  (for-each
   (lambda (spec)
     (let ((n (car spec)) (spread (cdr spec)))
       (case! "6" (format "~a-~a" n (if spread "1000-domains" "one-domain"))
         (lambda ()
           (let ((lines (let loop ((i (- n 1)) (acc '()))
                          (if (< i 0)
                              acc
                              (loop (- i 1)
                                    (cons (line (if spread (b "d" (number->string (mod i 1000)) ".localhost") (b "a.localhost"))
                                                "FALSE" "/" "FALSE" "0" (b "c" (number->string i)) "v")
                                          acc))))))
             (with-engine
              (lambda (e)
                (let* ((j (jar e))
                       (t0 (now-ns))
                       (a (jar-call j 'jar-load lines))
                       (t1 (now-ns)))
                  (if (eq? (car a) 'ok)
                      (fact "load n=~a codes-nonzero=~a engine-ns=~a setopt-ns=~a caller-ns=~a" n
                            (length (filter (lambda (c) (not (= c 0))) (cadr a)))
                            (car (caddr a)) (cadr (caddr a)) (- t1 t0))
                      (fact "load => ~a" (answer-text a)))
                  (let loop ((k 1))
                    (when (<= k 2)
                      (let* ((t2 (now-ns)) (r (jar-call j 'jar-read #f)) (t3 (now-ns)))
                        (if (eq? (car r) 'ok)
                            (fact "read-out ~a n=~a getinfo-ns=~a walk-ns=~a free-ns=~a caller-ns=~a" k
                                  (length (cadr (cadr r))) (car (caddr r)) (cadr (caddr r)) (caddr (caddr r)) (- t3 t2))
                            (fact "read-out ~a => ~a" k (answer-text r))))
                      (loop (+ k 1))))
                  (let* ((t4 (now-ns)) (o (run e (req (url "a.localhost" 'o (string-append "/6" (q (fresh-tag) '()))) 'cookie-jar j))) (t5 (now-ns)))
                    (fact "a transfer beside it => ~a caller-ns=~a cookies-sent=~a" (describe o) (- t5 t4) (car (cookie-count (report-lines o)))))
                  (close! j)))))))))
   '((100 . #f) (1000 . #f) (10000 . #f) (50000 . #f) (100 . #t) (1000 . #t) (10000 . #t) (50000 . #t))))

;; ========================================================================================
;; item 7: a caller's Host and Cookie beside the jar
;; ========================================================================================

(define (part-host)
  (for-each
   (lambda (version)
     (let ((face (if (eq? version 'h2) 'h2 'o))
           (keys (if (eq? version 'h2) (list 'http-version 'http/2-prior-knowledge) '())))
       (for-each
        (lambda (spec)
          (case! "7" (format "~a-host-~a" version (car spec))
            (lambda ()
              (with-engine
               (lambda (e)
                 (let ((j (jar e)))
                   (preload j (list (line "a.localhost" "FALSE" "/" "FALSE" "0" "ha" "1")
                                    (line "b.localhost" "FALSE" "/" "FALSE" "0" "hb" "1")))
                   (log-t 1 (run e (apply req (url "a.localhost" face (string-append "/7" (q (fresh-tag) (list (sc (b "set" (car spec) "=1"))))))
                                          'cookie-jar j 'headers (cdr spec) keys)))
                   (read-out j)
                   (close! j)))))))
        (list (cons "none" '())
              (cons "Host" (list (cons "Host" "b.localhost")))
              (cons "host" (list (cons "host" "b.localhost")))
              (cons "HOST" (list (cons "HOST" "b.localhost")))
              (cons "port" (list (cons "Host" (string-append "b.localhost:" (setting face)))))
              (cons "other-port" (list (cons "Host" "b.localhost:1")))))
       (for-each
        (lambda (spec)
          (case! "7" (format "~a-cookie-~a" version (car spec))
            (lambda ()
              (with-engine
               (lambda (e)
                 (let* ((with-jar (cadr spec)) (j (and with-jar (jar e))))
                   (when j (preload j (list (line "a.localhost" "FALSE" "/" "FALSE" "0" "n" "jar"))))
                   (log-t 1 (run e (with-opts (apply req (url "a.localhost" face (string-append "/7" (q (fresh-tag) '())))
                                                     (append (if j (list 'cookie-jar j) '()) (list 'headers (caddr spec)) keys))
                                              (cadddr spec))))
                   (when j (read-out j) (close! j))))))))
        (list (list "none" #t '() '())
              (list "header" #t (list (cons "Cookie" "n=caller")) '())
              (list "option" #t '() (list (cons "COOKIE" "n=opt")))
              (list "option-two" #t '() (list (cons "COOKIE" "n=opt1; o=opt2")))
              (list "header-and-option" #t (list (cons "Cookie" "n=caller")) (list (cons "COOKIE" "n=opt")))
              (list "empty-header" #t (list (cons "Cookie" "")) '())
              (list "empty-header-and-option" #t (list (cons "Cookie" "")) (list (cons "COOKIE" "n=opt")))
              (list "lower-header" #t (list (cons "cookie" "n=caller")) '())
              (list "two-headers" #t (list (cons "Cookie" "n=c1") (cons "Cookie" "n=c2")) '())
              (list "no-jar-option" #f '() (list (cons "COOKIE" "n=opt")))
              (list "no-jar-header" #f (list (cons "Cookie" "n=caller")) '())))))
   '(h1 h2)))

;; ========================================================================================
;; item 8: the Cookie header over HTTP/2
;; ========================================================================================

(define (part-h2)
  (for-each
   (lambda (n)
     (case! "8" (format "crumbs-~a" n)
       (lambda ()
         (with-engine
          (lambda (e)
            (let ((j (jar e)))
              (preload j (let loop ((i (- n 1)) (acc '()))
                           (if (< i 0) acc (loop (- i 1) (cons (line "a.localhost" "FALSE" "/" "FALSE" "0" (b "c" (number->string i)) "1") acc)))))
              (log-t 1 (run e (req (url "a.localhost" 'h2 (string-append "/8" (q (fresh-tag) '()))) 'cookie-jar j 'http-version 'http/2-prior-knowledge)))
              (log-t 2 (run e (req (url "a.localhost" 'o (string-append "/8" (q (fresh-tag) '()))) 'cookie-jar j)))
              (close! j)))))))
   '(1 3))
  (case! "8" "two-streams-one-connection"
    (lambda ()
      (with-engine
       (lambda (e)
         (let* ((j (jar e))
                (t1 (submit e (req (url "a.localhost" 'h2 (string-append "/8" (q (fresh-tag) (list (sc (b "sa=1")) (cons "delay" (number->string (bound 800)))))))
                                   'cookie-jar j 'http-version 'http/2-prior-knowledge))))
           (sleep-ms (bound 300))
           (let ((o2 (run e (req (url "a.localhost" 'h2 (string-append "/8" (q (fresh-tag) (list (sc (b "sb=1"))))))
                                 'cookie-jar j 'http-version 'http/2-prior-knowledge))))
             (fact "t1 done when t2 was: ~a" (curl-token-done? t1))
             (log-t 2 o2))
           (log-t 1 (await t1))
           (log-t 3 (run e (req (url "a.localhost" 'h2 (string-append "/8" (q (fresh-tag) '()))) 'cookie-jar j 'http-version 'http/2-prior-knowledge)))
           (read-out j)
           (close! j)))))))

;; ========================================================================================
;; item 9: requests inside one transfer
;; ========================================================================================

(define (part-rounds)
  (case! "9" "digest-401-sets-a-cookie"
    (lambda ()
      (with-engine
       (lambda (e)
         (let ((j (jar e)))
           (log-t 1 (run e (req (url "a.localhost" 'o (string-append "/9" (q (fresh-tag) (list (cons "ch" "digest") (cons "sc401" (hex (b "d401=1"))) (sc (b "d200=1"))))))
                                'cookie-jar j 'credentials (list 'digest "ouser" "opass"))))
           (read-out j)
           (close! j))))))
  (case! "9" "expect-417-sets-a-cookie"
    (lambda ()
      (with-engine
       (lambda (e)
         (let ((j (jar e)))
           (log-t 1 (run e (req (url "a.localhost" 'o (string-append "/9" (q (fresh-tag) (list (cons "e417" "1") (cons "sc417" (hex (b "e417=1"))) (sc (b "e200=1"))))))
                                'cookie-jar j 'method 'post 'body (b "body-for-the-417") 'headers (list (cons "Expect" "100-continue")))))
           (read-out j)
           (close! j)))))))

;; ========================================================================================
;; item 10: the twins beside a jar
;; ========================================================================================

(define (twin-case name preload-lines options later-delay)
  (case! "10" name
    (lambda ()
      (with-engine
       (lambda (e)
         (let ((j (jar e)))
           (preload j preload-lines)
           (fact "before:")
           (read-out j)
           ;; another transfer holding the jar, its request at the stand-in,
           ;; its answer held, live across the twin's
           (let* ((other-tag (fresh-tag))
                  (other (submit e (req (url "a.localhost" 'o (string-append "/10" (q other-tag (list (sc (b "other=1")) (cons "delay" (number->string (bound later-delay)))))))
                                        'cookie-jar j)))
                  (arrived (wait-for (lambda () (arrived? e other-tag)) 5000))
                  (_ (fact "the other transfer's request at the stand-in: ~a" arrived))
                  (r (with-opts (req (url "a.localhost" 'o (string-append "/10" (q (fresh-tag) (list (sc (b "twin=1")))))) 'cookie-jar j) options)))
             (fact "twin's request => ~a" (if (condition? r) (describe r) "made"))
             (log-t 1 (run e r))
             (fact "after the twin's transfer:")
             (read-out j)
             (log-t 2 (await other)))
           (fact "after the other transfer:")
           (read-out j)
           (log-t 3 (run e (req (url "a.localhost" 'o (string-append "/10" (q (fresh-tag) '()))) 'cookie-jar j)))
           (close! j)))))))

;; arrived? : Engine String -> Boolean
;; Whether the stand-in has logged a request of TAG, by a poll of its own.
(define (arrived? e tag)
  (let ((o (run e (req (url "a.localhost" 'o (string-append "/poll?of=" tag))))))
    (exists (lambda (l) (str-prefix? "req #" l)) (report-lines o))))

(define (part-twins)
  (let ((two (list (line "a.localhost" "FALSE" "/" "FALSE" "0" "sess" "1")
                   (line "a.localhost" "FALSE" "/" "FALSE" (number->string (+ (epoch-s) 86400)) "pers" "1"))))
    (twin-case "control" two '() 300)
    (twin-case "COOKIE" two (list (cons "COOKIE" "h=hatch")) 300)
    (twin-case "COOKIELIST-ALL" two (list (cons "COOKIELIST" "ALL")) 300)
    (twin-case "COOKIELIST-SESS" two (list (cons "COOKIELIST" "SESS")) 300)
    (twin-case "COOKIELIST-FLUSH" two (list (cons "COOKIELIST" "FLUSH")) 300)
    (twin-case "COOKIELIST-RELOAD" two (list (cons "COOKIELIST" "RELOAD")) 300)
    (twin-case "COOKIELIST-netscape" two
               (list (cons "COOKIELIST" (bytes->latin-1-string (line "a.localhost" "FALSE" "/" "FALSE" "0" "via" "hatch")))) 300)
    (twin-case "COOKIELIST-set-cookie" two (list (cons "COOKIELIST" "Set-Cookie: vsc=1; Domain=a.localhost")) 300)
    (twin-case "COOKIESESSION" two (list (cons "COOKIESESSION" 1)) 300)
    (twin-case "HSTS_CTRL" two (list (cons "HSTS_CTRL" 1)) 300)
    (twin-case "SHARE" two (list (cons "SHARE" 0)) 300)
    (twin-case "COOKIEFILE" two (list (cons "COOKIEFILE" "")) 300)
    (twin-case "COOKIEJAR" two (list (cons "COOKIEJAR" (string-append tmp "/twin-jar.txt"))) 300)))

;; ========================================================================================
;; item 11: what the share holds
;; ========================================================================================

(define sts (b "Strict-Transport-Security:" 32 "max-age=86400"))

(define (part-hsts)
  (for-each
   (lambda (spec)
     (let ((name (car spec)) (ops (cadr spec)) (first-opts (caddr spec)) (second-opts (cadddr spec)))
       (case! "11" name
         (lambda ()
           (with-engine
            (lambda (e)
              (let-values (((j a) (if ops (make-jar e ops) (values #f '(ok none 0)))))
                (fact "make ops=~s => ~a" ops (answer-text a))
                (let ((jk (if j (list 'cookie-jar j) '())))
                  (log-t 1 (run e (with-opts (apply req (surl "localhost" 'tls (string-append "/11" (q (fresh-tag) (list (hh sts) (sc (b "hs=1"))))))
                                                    'ca-file ca jk)
                                             first-opts)))
                  (log-t 2 (run e (with-opts (apply req (url "localhost" 'tls (string-append "/11" (q (fresh-tag) '())))
                                                    'ca-file ca jk)
                                             second-opts)))
                  (when j (read-out j) (close! j))))))))))
   (list (list "cookie-share" '((1 . 2)) (list (cons "HSTS_CTRL" 1)) (list (cons "HSTS_CTRL" 1)))
         (list "control-share-with-hsts" '((1 . 2) (1 . 7)) (list (cons "HSTS_CTRL" 1)) (list (cons "HSTS_CTRL" 1)))
         (list "share-with-hsts-second-without-ctrl" '((1 . 2) (1 . 7)) (list (cons "HSTS_CTRL" 1)) '())
         (list "share-with-hsts-no-ctrl-either" '((1 . 2) (1 . 7)) '() '())
         (list "no-jar" #f (list (cons "HSTS_CTRL" 1)) (list (cons "HSTS_CTRL" 1))))))

;; ========================================================================================
;; item 12: IPv6 loopback
;; ========================================================================================

(define (part-ipv6)
  (case! "12" "facts"
    (lambda ()
      (fact "if_inet6 ~s" (guard (e (#t "unreadable"))
                            (let ((bytes (call-with-port (open-file-input-port "/proc/net/if_inet6") get-bytevector-all)))
                              (if (eof-object? bytes) "" (bytes->latin-1-string bytes)))))
      (fact "stand-in v6=~a" (setting 'v6))))
  (for-each
   (lambda (face)
     (for-each
      (lambda (host)
        (case! "12" (format "~a-~a" face host)
          (lambda ()
            (if (and (eq? face 'v6) (not v6-up?))
                (fact "no v6 face: ~a" (setting 'v6))
                (with-engine
                 (lambda (e)
                   (let loop ((k 1))
                     (when (<= k 3)
                       (let* ((t0 (now-ns)) (o (run e (req (url host face (string-append "/12" (q (fresh-tag) '()))) 'connect-timeout-ms (bound 5000))))
                              (t1 (now-ns)))
                         (log-t k o)
                         (fact "caller-ms=~a" (exact->inexact (/ (round (/ (- t1 t0) 10000)) 100))))
                       (loop (+ k 1))))))))))
      '("a.localhost" "localhost" "127.0.0.1" "[::1]")))
   '(v4 v6 o)))

;; ========================================================================================
;; the instrument: the read-out walk against libcurl's own file
;; ========================================================================================

(define walk-lines
  (list (line "a.localhost" "FALSE" "/" "FALSE" "0" "w1" "plain")
        (line "#HttpOnly_a.localhost" "FALSE" "/p" "TRUE" "99999999999" "w2" "ho")
        (line ".b.localhost" "TRUE" "/" "FALSE" "0" "w3" "")
        (line "a.localhost" "FALSE" "/" "FALSE" "0" "w4" (b "caf" 195 169))
        (line "a.localhost" "FALSE" "/" "FALSE" "0" "w5" (b 233 255))
        (b "Set-Cookie:" 32 "w6=sc;" 32 "Domain=a.localhost;" 32 "Path=/q")))

(define (read-file-lines path)
  (let ((bytes (call-with-port (open-file-input-port path) get-bytevector-all)))
    (if (eof-object? bytes)
        '()
        (filter (lambda (l) (not (or (= (bytevector-length l) 0) (bytes-prefix? (b "#" 32) l))))
                (split-bytes bytes 10)))))

(define (part-walk)
  (case! "walk" "scratch-handle"
    (lambda ()
      (let* ((path (string-append tmp "/walk-jar.txt"))
             (easy (curl-easy-init))
             (id (lambda (n) (car (curl-easy-option n))))
             (set-str (lambda (n s) (call-with-c-string s (lambda (a) (curl-easy-setopt-pointer easy (id n) a))))))
        (fact "COOKIEFILE \"\" => ~a; COOKIEJAR => ~a" (set-str "COOKIEFILE" "") (set-str "COOKIEJAR" path))
        (for-each (lambda (l)
                    (fact "COOKIELIST \"~a\" => ~a" (render l)
                          (call-with-latin-1-c-string (bytes->latin-1-string l)
                            (lambda (a) (curl-easy-setopt-pointer easy (id "COOKIELIST") a)))))
                  walk-lines)
        ;; libcurl writes the file only once a transfer has started
        ;; (cookie.c, Curl_flush_cookies, 8.20.0): one transfer on the
        ;; scratch handle, stepped through a multi handle of this thread's.
        (fact "URL => ~a" (set-str "URL" (url "a.localhost" 'o (string-append "/walk" (q (fresh-tag) '())))))
        (fact "transfer => ~a" (scratch-transfer easy))
        (fact "FLUSH => ~a" (set-str "COOKIELIST" "FLUSH"))
        (let ((file (sorted (read-file-lines path))))
          (let-values (((code head) (curl-easy-getinfo-cookielist easy)))
            (let ((walked (sorted (if (= head 0) '() (let ((l (curl-slist-strings head))) (curl-slist-free-all head) l)))))
              (for-each (lambda (l) (fact "file \"~a\"" (render l))) file)
              (for-each (lambda (l) (fact "walk \"~a\"" (render l))) walked)
              (fact "walk-check ~a file=~a walk=~a getinfo=~a"
                    (if (and (= (length file) (length walked)) (for-all bytevector=? file walked)) "same" "DIFFERS")
                    (length file) (length walked) code))))
        (curl-easy-cleanup easy))))
  (case! "walk" "jar"
    (lambda ()
      (let ((path (string-append tmp "/walk-jar.txt")))
        (with-engine
         (lambda (e)
           (let ((j (jar e)))
             (fact "load => ~s" (load! j walk-lines))
             (let ((lines (read-out j)) (file (sorted (read-file-lines path))))
               (fact "jar-walk-check ~a file=~a jar=~a"
                     (if (and lines (= (length file) (length lines)) (for-all bytevector=? file lines)) "same" "DIFFERS")
                     (length file) (if lines (length lines) "-")))
             (close! j))))))))

;; scratch-transfer : Natural -> List
;; EASY's transfer, run to its end on a multi handle of this thread's,
;; within 10 s: the messages read, and how many steps it took.
(define (scratch-transfer easy)
  (let ((multi (curl-multi-init)) (slot (foreign-block 8)) (deadline (+ (now-ns) (* (bound 10000) 1000000))))
    (curl-multi-add-handle multi easy)
    (let loop ((steps 0) (seen '()))
      (let-values (((code running) (curl-multi-perform multi slot)))
        (let ((messages (let drain ((acc '()))
                          (let ((m (curl-multi-info-read multi slot)))
                            (if m (drain (cons (list (car m) (caddr m)) acc)) acc)))))
          (if (or (= running 0) (> (now-ns) deadline) (not (= code 0)))
              (begin
                (curl-multi-remove-handle multi easy)
                (curl-multi-cleanup multi)
                (free-foreign-block! slot)
                (list 'perform code 'running running 'steps steps 'messages (append seen messages)))
              (begin (curl-multi-poll multi 100) (loop (+ steps 1) (append seen messages)))))))))

;; ========================================================================================

(define (say-libcurl)
  (let ((info (loaded-libcurl)))
    (say "libcurl version=~a ssl=~s path=~a part=~a lane=~a" (libcurl-info-version info)
         (libcurl-info-ssl-version info) (libcurl-info-path info) part lane)))

(say-libcurl)
(case part
  ((lifetime) (part-lifetime))
  ((lifetime-plant) (item-1c))
  ((abandon-leave) (part-abandon #t))
  ((abandon-free) (part-abandon #f))
  ((setopt) (part-setopt))
  ((order) (part-order))
  ((load) (part-load))
  ((readout) (part-readout))
  ((cost) (part-cost))
  ((host) (part-host))
  ((h2) (part-h2))
  ((rounds) (part-rounds))
  ((twins) (part-twins))
  ((hsts) (part-hsts))
  ((ipv6) (part-ipv6))
  ((walk) (part-walk))
  (else (say "no part ~a" part)))
(say "native ~a" (counts-text))
(say "done ~a" part)
