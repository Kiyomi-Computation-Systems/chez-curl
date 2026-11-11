#!r6rs
;;; tests/test-printed.sps: no printed text carries a misplaced value or a
;;; refused URL (ADR-0036; ADR-0008).
;;;
;;;   - every export of (curl), (curl unsupported) and (http-client), a row
;;;     each, written out here: a condition type's name, syntax; a list of
;;;     reasons, value; a procedure of no argument, none; every other, its
;;;     least arity of 1 or more and what it answers, called with a URL
;;;     holding a password as every argument. The rows' names are the exports
;;;     exactly, so an export with no row fails; each procedure's answer is
;;;     its row's, an accessor's an assertion violation from the accessor
;;;     naming the string by its kind, (kind string); and no export, at any
;;;     arity from 1 to 3, prints the password; nor, handed a cookie jar holding
;;;     a cookie whose value was loaded and one a server set, a line holding the
;;;     first, or a session keeping both, as every argument, either value
;;;     (ADR-0035; a cookie's value is a secret, as a password is);
;;;   - (curl private libcurl-info)'s own copy of shown-value's rule, which it
;;;     cannot import, alike shown-value on each kind;
;;;   - every path that refuses a URL, given one holding a password: the
;;;     request's URL at check and at submit, scheme-not-http, a parse
;;;     failure, embedded-nul and not-utf-8; each URL function's refusal of
;;;     its URL, its reference, its query part and its fragment; and the high
;;;     level's, passed through: each prints no password, its irritants name
;;;     its field, and curl-url-error-input still answers the string.
;;;
;;; Every expected value is one the code under test cannot produce by
;;; failing: SRFI-64 makes #f of a raise in the actual expression, so none
;;; is #f.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) library-exports environment eval procedure-arity-mask logbit?
              display-condition make-list)
        (curl-testing)
        (curl)
        (curl unsupported)
        (http-client)
        (only (curl private conditions) shown-value)
        (curl private counters))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; written : Any -> String
(define (written x) (call-with-string-output-port (lambda (p) (write x p))))

;; shown : Any -> String
;; X written, cut to 4000 characters.
(define (shown x)
  (let ((text (written x)))
    (if (> (string-length text) 4000)
        (string-append (substring text 0 4000) "...")
        text)))

;; The simple runner names a failing test but not its values. Print both.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (display "  expected: ")
        (display (shown (test-result-ref r 'expected-value)))
        (newline)
        (display "  actual:   ")
        (display (shown (test-result-ref r 'actual-value)))
        (newline))
      ;; A suite killed at its bound never flushes: flush each verdict.
      (flush-output-port (current-output-port)))))

(test-begin "printed")

(define secret "Pr0xyS3cr3t")
(define url (string-append "http://u:" secret "@h/"))

;; contains? : String String -> Boolean
(define (contains? text part)
  (let ((n (string-length text)) (k (string-length part)))
    (let loop ((i 0))
      (and (<= (+ i k) n) (or (string=? (substring text i (+ i k)) part) (loop (+ i 1)))))))

;; printed : Any -> String
;; X as write, display and display-condition print it, one after another.
(define (printed x)
  (call-with-string-output-port
   (lambda (p)
     (write x p) (newline p) (display x p) (newline p)
     (when (condition? x) (display-condition x p)))))

;; raised : (-> Any) -> Any
;; What THUNK raised, or no-raise, a symbol nothing raises here.
(define (raised thunk)
  (call/cc
   (lambda (k)
     (with-exception-handler
      (lambda (e) (k e))
      (lambda () (thunk) 'no-raise)))))

;; answer-of : Any -> Any
;; What RAISED is, as data: a request error's field, value and reason; a
;; URL error's reason; an assertion's who and irritants; or (other WHO).
(define (answer-of e)
  (cond ((eq? e 'no-raise) 'no-raise)
        ((curl-request-error? e)
         (list 'curl-request-error (curl-request-error-field e) (curl-request-error-value e)
               (curl-request-error-reason e)))
        ((http-request-error? e)
         (list 'http-request-error (http-request-error-field e) (http-request-error-value e)
               (http-request-error-reason e)))
        ((curl-url-error? e) (list 'curl-url-error (curl-url-error-reason e)))
        ((assertion-violation? e)
         (list 'assertion (and (who-condition? e) (condition-who e))
               (and (irritants-condition? e) (condition-irritants e))))
        (else (list 'other (and (who-condition? e) (condition-who e))))))

;; --- every export, a row (ADR-0036) -----------------------------------------------------

;; export-rows : (Listof (Pairof Symbol List))
;; Written out, by library: (NAME syntax), (NAME value), (NAME none), or
;; (NAME ARITY ANSWER), ANSWER answer-of what NAME raised called at ARITY
;; with url as every argument. An accessor's is (assertion NAME ((kind
;; string))): it names the string by its kind, never prints it.
(define curl-rows
  '(
    (&curl-connect-error syntax)
    (&curl-embedded-nul syntax)
    (&curl-engine-error syntax)
    (&curl-error syntax)
    (&curl-library-unavailable syntax)
    (&curl-protocol-error syntax)
    (&curl-request-error syntax)
    (&curl-send-receive-error syntax)
    (&curl-timeout syntax)
    (&curl-tls-error syntax)
    (&curl-too-large syntax)
    (&curl-transfer-error syntax)
    (&curl-url-error syntax)
    (&curl-wrong-thread syntax)
    (curl-connect-error? 1 no-raise)
    (curl-cookie-jar-close! 1 (assertion curl-cookie-jar-close! ((kind string))))
    (curl-cookie-jar-cookies 1 (assertion curl-cookie-jar-cookies ((kind string))))
    (curl-cookie-jar-load! 2 (assertion curl-cookie-jar-load! ((kind string))))
    (curl-cookie-jar? 1 no-raise)
    (curl-embedded-nul-string 1 (assertion curl-embedded-nul-string ((kind string))))
    (curl-embedded-nul? 1 no-raise)
    (curl-engine-error-condition 1 (assertion curl-engine-error-condition ((kind string))))
    (curl-engine-error-reason 1 (assertion curl-engine-error-reason ((kind string))))
    (curl-engine-error-reasons value)
    (curl-engine-error? 1 no-raise)
    (curl-engine-stop 1 (assertion curl-engine-stop ((kind string))))
    (curl-engine? 1 no-raise)
    (curl-error? 1 no-raise)
    (curl-head-body-asked? 1 (assertion curl-head-body-asked? ((kind string))))
    (curl-head-headers 1 (assertion curl-head-headers ((kind string))))
    (curl-head-http-version 1 (assertion curl-head-http-version ((kind string))))
    (curl-head-status 1 (assertion curl-head-status ((kind string))))
    (curl-head? 1 no-raise)
    (curl-library-unavailable-candidates 1 (assertion curl-library-unavailable-candidates ((kind string))))
    (curl-library-unavailable-detail 1 (assertion curl-library-unavailable-detail ((kind string))))
    (curl-library-unavailable-library 1 (assertion curl-library-unavailable-library ((kind string))))
    (curl-library-unavailable-path 1 (assertion curl-library-unavailable-path ((kind string))))
    (curl-library-unavailable-reason 1 (assertion curl-library-unavailable-reason ((kind string))))
    (curl-library-unavailable-reasons value)
    (curl-library-unavailable-source 1 (assertion curl-library-unavailable-source ((kind string))))
    (curl-library-unavailable? 1 no-raise)
    (curl-mailbox-deliver 2 (assertion curl-mailbox-deliver ((kind string))))
    (curl-mailbox-take 2 (assertion curl-mailbox-take ((kind string))))
    (curl-mailbox? 1 no-raise)
    (curl-protocol-error? 1 no-raise)
    (curl-request-body 1 (assertion curl-request-body ((kind string))))
    (curl-request-body-length 1 (assertion curl-request-body-length ((kind string))))
    (curl-request-body-limit 1 (assertion curl-request-body-limit ((kind string))))
    (curl-request-ca-file 1 (assertion curl-request-ca-file ((kind string))))
    (curl-request-check 1 (assertion curl-request-check ((kind string))))
    (curl-request-connect-timeout-ms 1 (assertion curl-request-connect-timeout-ms ((kind string))))
    (curl-request-cookie-jar 1 (assertion curl-request-cookie-jar ((kind string))))
    (curl-request-credentials 1 (assertion curl-request-credentials ((kind string))))
    (curl-request-error-field 1 (assertion curl-request-error-field ((kind string))))
    (curl-request-error-reason 1 (assertion curl-request-error-reason ((kind string))))
    (curl-request-error-reasons value)
    (curl-request-error-value 1 (assertion curl-request-error-value ((kind string))))
    (curl-request-error? 1 no-raise)
    (curl-request-headers 1 (assertion curl-request-headers ((kind string))))
    (curl-request-http-version 1 (assertion curl-request-http-version ((kind string))))
    (curl-request-method 1 (assertion curl-request-method ((kind string))))
    (curl-request-proxy 1 (assertion curl-request-proxy ((kind string))))
    (curl-request-proxy-ca-file 1 (assertion curl-request-proxy-ca-file ((kind string))))
    (curl-request-proxy-verify 1 (assertion curl-request-proxy-verify ((kind string))))
    (curl-request-stream-buffer 1 (assertion curl-request-stream-buffer ((kind string))))
    (curl-request-timeout-ms 1 (assertion curl-request-timeout-ms ((kind string))))
    (curl-request-url 1 (assertion curl-request-url ((kind string))))
    (curl-request-user-agent 1 (assertion curl-request-user-agent ((kind string))))
    (curl-request-verify 1 (assertion curl-request-verify ((kind string))))
    (curl-request-with 1 (assertion curl-request-with ((kind string))))
    (curl-request? 1 no-raise)
    (curl-response-body 1 (assertion curl-response-body ((kind string))))
    (curl-response-effective-url 1 (assertion curl-response-effective-url ((kind string))))
    (curl-response-headers 1 (assertion curl-response-headers ((kind string))))
    (curl-response-http-version 1 (assertion curl-response-http-version ((kind string))))
    (curl-response-status 1 (assertion curl-response-status ((kind string))))
    (curl-response-timings 1 (assertion curl-response-timings ((kind string))))
    (curl-response? 1 no-raise)
    (curl-send-receive-error? 1 no-raise)
    (curl-submit 2 (assertion curl-submit ((kind string))))
    (curl-timeout? 1 no-raise)
    (curl-tls-error? 1 no-raise)
    (curl-token-await 1 (assertion curl-token-await ((kind string))))
    (curl-token-body-count 1 (assertion curl-token-body-count ((kind string))))
    (curl-token-body-port 1 (assertion curl-token-body-port ((kind string))))
    (curl-token-cancel 1 (assertion curl-token-cancel ((kind string))))
    (curl-token-done? 1 (assertion curl-token-done? ((kind string))))
    (curl-token-end-body! 1 (assertion curl-token-end-body! ((kind string))))
    (curl-token-head 1 (assertion curl-token-head ((kind string))))
    (curl-token-head-wait 2 (assertion curl-token-head-wait ((kind string))))
    (curl-token-next-piece 2 (assertion curl-token-next-piece ((kind string))))
    (curl-token-outcome 1 (assertion curl-token-outcome ((kind string))))
    (curl-token-put-piece! 2 (assertion curl-token-put-piece! ((kind string))))
    (curl-token-room-wait 2 (assertion curl-token-room-wait ((kind string))))
    (curl-token-wait 2 (assertion curl-token-wait ((kind string))))
    (curl-token? 1 no-raise)
    (curl-too-large? 1 no-raise)
    (curl-transfer-error-code 1 (assertion curl-transfer-error-code ((kind string))))
    (curl-transfer-error-connect-code 1 (assertion curl-transfer-error-connect-code ((kind string))))
    (curl-transfer-error-error-buffer 1 (assertion curl-transfer-error-error-buffer ((kind string))))
    (curl-transfer-error-option 1 (assertion curl-transfer-error-option ((kind string))))
    (curl-transfer-error-reason 1 (assertion curl-transfer-error-reason ((kind string))))
    (curl-transfer-error-reasons value)
    (curl-transfer-error-recorded 1 (assertion curl-transfer-error-recorded ((kind string))))
    (curl-transfer-error-request-size 1 (assertion curl-transfer-error-request-size ((kind string))))
    (curl-transfer-error-strerror 1 (assertion curl-transfer-error-strerror ((kind string))))
    (curl-transfer-error? 1 no-raise)
    (curl-url-append-query 2 no-raise)
    (curl-url-error-code 1 (assertion curl-url-error-code ((kind string))))
    (curl-url-error-input 1 (assertion curl-url-error-input ((kind string))))
    (curl-url-error-message 1 (assertion curl-url-error-message ((kind string))))
    (curl-url-error-reason 1 (assertion curl-url-error-reason ((kind string))))
    (curl-url-error? 1 no-raise)
    (curl-url-part 2 (assertion curl-url-part ((kind string))))
    (curl-url-resolve 2 no-raise)
    (curl-url-with-fragment 2 no-raise)
    (curl-wrong-thread-actual 1 (assertion curl-wrong-thread-actual ((kind string))))
    (curl-wrong-thread-expected 1 (assertion curl-wrong-thread-expected ((kind string))))
    (curl-wrong-thread-who 1 (assertion curl-wrong-thread-who ((kind string))))
    (curl-wrong-thread? 1 no-raise)
    (libcurl-info-feature-names 1 (assertion libcurl-info-feature-names ((kind string))))
    (libcurl-info-features 1 (assertion libcurl-info-features ((kind string))))
    (libcurl-info-host 1 (assertion libcurl-info-host ((kind string))))
    (libcurl-info-path 1 (assertion libcurl-info-path ((kind string))))
    (libcurl-info-source 1 (assertion libcurl-info-source ((kind string))))
    (libcurl-info-ssl-version 1 (assertion libcurl-info-ssl-version ((kind string))))
    (libcurl-info-version 1 (assertion libcurl-info-version ((kind string))))
    (libcurl-info-version-number 1 (assertion libcurl-info-version-number ((kind string))))
    (libcurl-info? 1 no-raise)
    (loaded-libcurl none)
    (make-curl-cookie-jar 1 (assertion make-curl-cookie-jar ((kind string))))
    (make-curl-engine none)
    (make-curl-mailbox none)
    (make-curl-request 1 no-raise)))

(define unsupported-rows
  '(
    (curl-request-with-options 2 (assertion curl-request-with-options ((kind string))))))

(define http-client-rows
  '(
    (&http-error syntax)
    (&http-exchange syntax)
    (&http-group-error syntax)
    (&http-redirect-error syntax)
    (&http-request-error syntax)
    (&http-timeout syntax)
    (call-with-http-session 1 (assertion call-with-http-session (proc)))
    (call-with-request-group 1 (assertion call-with-request-group (proc)))
    (call-with-response-port 3 (assertion call-with-response-port (proc)))
    (http-await 1 (assertion http-await ((kind string))))
    (http-delete 2 (assertion http-request ((kind string))))
    (http-error? 1 no-raise)
    (http-exchange-history 1 (assertion http-exchange-history ((kind string))))
    (http-exchange-method 1 (assertion http-exchange-method ((kind string))))
    (http-exchange-transfers 1 (assertion http-exchange-transfers ((kind string))))
    (http-exchange-url 1 (assertion http-exchange-url ((kind string))))
    (http-exchange? 1 no-raise)
    (http-get 2 (assertion http-request ((kind string))))
    (http-group-error-reason 1 (assertion http-group-error-reason ((kind string))))
    (http-group-error-reasons value)
    (http-group-error? 1 no-raise)
    (http-head 2 (assertion http-request ((kind string))))
    (http-parallel 2 (assertion http-parallel ((kind string))))
    (http-patch 2 (assertion http-request ((kind string))))
    (http-pending-cancel 1 (assertion http-pending-cancel ((kind string))))
    (http-pending-done? 1 (assertion http-pending-done? ((kind string))))
    (http-pending? 1 no-raise)
    (http-post 2 (assertion http-request ((kind string))))
    (http-put 2 (assertion http-request ((kind string))))
    (http-redirect-error-location 1 (assertion http-redirect-error-location ((kind string))))
    (http-redirect-error-reason 1 (assertion http-redirect-error-reason ((kind string))))
    (http-redirect-error-reasons value)
    (http-redirect-error-response 1 (assertion http-redirect-error-response ((kind string))))
    (http-redirect-error? 1 no-raise)
    (http-request 3 (assertion http-request ((kind string))))
    (http-request-error-field 1 (assertion http-request-error-field ((kind string))))
    (http-request-error-reason 1 (assertion http-request-error-reason ((kind string))))
    (http-request-error-reasons value)
    (http-request-error-value 1 (assertion http-request-error-value ((kind string))))
    (http-request-error? 1 no-raise)
    (http-response-body 1 (assertion http-response-body ((kind string))))
    (http-response-header 2 (assertion http-response-header ((kind string))))
    (http-response-headers 1 (assertion http-response-headers ((kind string))))
    (http-response-history 1 (assertion http-response-history ((kind string))))
    (http-response-http-version 1 (assertion http-response-http-version ((kind string))))
    (http-response-status 1 (assertion http-response-status ((kind string))))
    (http-response-text 1 (assertion http-response-text ((kind string))))
    (http-response-timings 1 (assertion http-response-timings ((kind string))))
    (http-response-url 1 (assertion http-response-url ((kind string))))
    (http-response? 1 no-raise)
    (http-retry? 1 no-raise)
    (http-session-close 1 (assertion http-session-close ((kind string))))
    (http-session-cookies 1 (assertion http-session-cookies ((kind string))))
    (http-session-load-cookies! 2 (assertion http-session-load-cookies! ((kind string))))
    (http-session? 1 no-raise)
    (http-timeout-timeout-ms 1 (assertion http-timeout-timeout-ms ((kind string))))
    (http-timeout? 1 no-raise)
    (make-http-retry 1 (http-request-error key (kind string) unknown-key))
    (make-http-session 1 (http-request-error key (kind string) unknown-key))))

;; sorted : (Listof Symbol) -> (Listof Symbol)
(define (sorted names)
  (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) names))

;; exports-of : List -> (Listof Symbol)
(define (exports-of lib)
  (guard (e (#t (list 'raised (describe e)))) (sorted (library-exports lib))))

(test-equal "the rows name every export of (curl), (curl unsupported) and (http-client), exactly: an export with no row fails here"
  (list (sorted (map car curl-rows)) (sorted (map car unsupported-rows)) (sorted (map car http-client-rows)))
  (list (exports-of '(curl)) (exports-of '(curl unsupported)) (exports-of '(http-client))))

;; the-environment : Environment
(define the-environment (environment '(rnrs) '(curl) '(curl unsupported) '(http-client)))

;; value-of : Symbol -> Any
;; NAME's value, or syntax when it names no variable: a condition type's
;; name does not.
(define (value-of name)
  (guard (e (#t 'syntax)) (eval name the-environment)))

;; row-measured : (Pairof Symbol List) -> List
;; What NAME is now, as its row writes it.
(define (row-measured row)
  (let ((v (value-of (car row))))
    (cond ((eq? v 'syntax) (list (car row) 'syntax))
          ((not (procedure? v)) (list (car row) 'value))
          (else
           (let ((n (let loop ((n 1))
                      (cond ((> n 4) #f) ((logbit? n (procedure-arity-mask v)) n) (else (loop (+ n 1)))))))
             (if n
                 (list (car row) n (answer-of (raised (lambda () (apply v (make-list n url))))))
                 (list (car row) 'none)))))))

;; in-order : (A -> B) (Listof A) -> (Listof B)
;; PROC on each of XS, in order: map's order is no order.
(define (in-order proc xs)
  (let loop ((rest xs) (found '()))
    (if (null? rest) (reverse found) (loop (cdr rest) (cons (proc (car rest)) found)))))

(for-each
 (lambda (lib rows)
   (test-equal (string-append "each export of " lib ", called with a URL holding a password as every argument, answers its row: an accessor, an assertion from it naming the string (kind string); a key where a key belongs, (kind string); a predicate, no raise")
     rows
     (in-order row-measured rows)))
 '("(curl)" "(curl unsupported)" "(http-client)")
 (list curl-rows unsupported-rows http-client-rows))

;; prints-secret : Symbol -> (Listof Natural)
;; The arities from 1 to 3 NAME takes at which, called with url as every
;; argument, what it raised prints the password.
(define (prints-secret name)
  (let ((v (value-of name)))
    (if (procedure? v)
        (filter (lambda (n)
                  (and (logbit? n (procedure-arity-mask v))
                       (let ((r (raised (lambda () (apply v (make-list n url))))))
                         (and (not (eq? r 'no-raise)) (contains? (printed r) secret)))))
                '(1 2 3))
        '())))

(test-equal "no export of the three, at any arity from 1 to 3, every argument a URL holding a password, prints the password in what it raises, as write, display and display-condition print it"
  '()
  (filter (lambda (entry) (pair? (cdr entry)))
          (in-order (lambda (name) (cons name (prints-secret name)))
                    (map car (append curl-rows unsupported-rows http-client-rows)))))

;; --- a cookie's value is never printed (ADR-0035) -----------------------------------------

;; Two cookie values, each a secret: one loaded into the jar, one a server
;; set; and a line holding the first, as a load takes it.
(define loaded-secret "L0adedC00kie")
(define server-secret "S3rverC00kie")
(define secret-line (string-append "a.localhost\tFALSE\t/\tFALSE\t0\tloaded\t" loaded-secret))

;; cookie-holders : (U (List Engine Jar Session Engine) (List 'raised String))
;; An engine and a jar of its, and a session keeping cookies, each holding
;; both cookies: the loaded one by a load, the server's by a transfer to
;; the origin's cookie route, which set it; the session's engine is the
;; fourth, read back only to be stopped. Made here, in a definition, under
;; a guard, and freed at the end.
(define cookie-holders
  (guard (e (#t (list 'raised (describe e))))
    (call-with-origin
     (lambda (o)
       (let* ((port (number->string (cdr (origin-face o 'http))))
              (route (string-append "http://a.localhost:" port "/cookies?key=printed&set=server%3D"
                                    server-secret))
              (engine (make-curl-engine))
              (jar (make-curl-cookie-jar engine))
              (session (make-http-session 'cookies #t 'proxy #f 'timeout-ms 20000)))
         (curl-cookie-jar-load! jar (list secret-line))
         (curl-token-await (curl-submit engine (make-curl-request route 'cookie-jar jar 'proxy #f
                                                                  'timeout-ms 20000)))
         (http-session-load-cookies! session (list secret-line))
         (http-get session route)
         (list engine jar session))))))

(define holders-made? (and (pair? cookie-holders) (curl-engine? (car cookie-holders))))

(test-equal "the jar and the session each hold both secrets: the loaded cookie and the one the server set"
  '((#t #t) (#t #t))
  (if holders-made?
      (map (lambda (lines)
             (list (and (exists (lambda (l) (contains? l loaded-secret)) lines) #t)
                   (and (exists (lambda (l) (contains? l server-secret)) lines) #t)))
           (list (curl-cookie-jar-cookies (cadr cookie-holders))
                 (http-session-cookies (caddr cookie-holders))))
      cookie-holders))

;; prints-cookie : Symbol Any -> (Listof Natural)
;; The arities from 1 to 3 NAME takes at which, called with ARGUMENT as
;; every argument, what it raised prints either secret.
(define (prints-cookie name argument)
  (let ((v (value-of name)))
    (if (procedure? v)
        (filter (lambda (n)
                  (and (logbit? n (procedure-arity-mask v))
                       (let ((r (raised (lambda () (apply v (make-list n argument))))))
                         (and (not (eq? r 'no-raise))
                              (let ((text (printed r)))
                                (or (contains? text loaded-secret) (contains? text server-secret)))))))
                '(1 2 3))
        '())))

;; The exports whose call with a jar, a line or a session as every argument
;; would close or stop what holds the secrets, or wait on the origin gone,
;; before the rest are called: called last, apart.
(define closing-exports
  '(curl-cookie-jar-close! curl-engine-stop http-session-close call-with-http-session))

(test-equal "no export of the three, at any arity from 1 to 3, handed the jar, a line holding the loaded secret, or the session as every argument, prints either cookie value in what it raises, as write, display and display-condition print it; nor the jar, the session, nor a request with the jar, printed themselves"
  '(() #f)
  (if holders-made?
      (let* ((jar (cadr cookie-holders))
             (session (caddr cookie-holders))
             (names (map car (append curl-rows unsupported-rows http-client-rows)))
             (open (filter (lambda (name) (not (memq name closing-exports))) names))
             (each (lambda (argument)
                     (filter (lambda (entry) (pair? (cdr entry)))
                             (in-order (lambda (name) (cons name (prints-cookie name argument)))
                                       (append open closing-exports))))))
        (list (append (each secret-line) (each (list secret-line)) (each jar) (each session))
              (let ((text (string-append (printed jar) (printed session)
                                         (printed (make-curl-request "http://a.localhost/" 'cookie-jar jar)))))
                (or (contains? text loaded-secret) (contains? text server-secret)))))
      cookie-holders))

(define holders-freed
  (guard (e (#t (list 'raised (describe e))))
    (when holders-made?
      (http-session-close (caddr cookie-holders))
      (curl-engine-stop (car cookie-holders)))
    'freed))

;; --- libcurl-info's own copy of the rule --------------------------------------------------

;; kinds : (Listof Any)
;; One value of each kind shown-value tells apart, a string with the
;; password, a list holding it, an improper and a proper list of symbols.
(define kinds
  (list 'x 5 #f #\a '() '(429 503) url (list 'basic "alice" secret) '(1 . 2) (make-bytevector 1 0)
        (vector "p") car (make-eq-hashtable)))

(test-equal "libcurl-info's accessors name a wrong argument as shown-value does, which libcurl-info cannot import: each kind alike, the string and the list holding the password by their kind"
  (map (lambda (x) (list (shown-value x))) kinds)
  (in-order (lambda (x)
              (let ((e (raised (lambda () (libcurl-info-path x)))))
                (if (and (assertion-violation? e) (irritants-condition? e)) (condition-irritants e) (answer-of e))))
            kinds))

;; --- a refused URL is never printed (ADR-0008) ------------------------------------------

;; url-refusal : (-> Any) -> Any
;; What THUNK raised, for a &curl-url-error: (refused IRRITANTS INPUT
;; PRINTED), PRINTED whether its print holds the password; else
;; answer-of's.
(define (url-refusal thunk)
  (let ((e (raised thunk)))
    (if (curl-url-error? e)
        (list 'refused (and (irritants-condition? e) (condition-irritants e)) (curl-url-error-input e)
              (if (contains? (printed e) secret) 'printed-the-secret 'no-secret))
        (answer-of e))))

;; on-engine : (Engine -> Any) -> Any
;; PROC's answer on an engine made for it and stopped after, whatever PROC
;; raises, which passes on.
(define (on-engine proc)
  (let ((e (make-curl-engine)))
    (dynamic-wind (lambda () #f) (lambda () (proc e)) (lambda () (curl-engine-stop e)))))

(define ftp (string-append "ftp://u:" secret "@h/"))
(define spaced (string-append "http://u:" secret "@h /"))
(define with-nul (string-append "http://u:" secret "@h/\x0;"))
(define latin-host (string-append "http://u:" secret "@caf%E9.example/"))
(define part (string-append secret "\x0;"))

;; url-cases : (Listof (List String Any (-> Any)))
;; Each path that refuses a URL, or a part of one, holding the password,
;; with what it must raise: refused, its irritants the field, its input the
;; string refused, and its print holding no password.
(define url-cases
  (list (list "the request's URL, scheme-not-http, at check" (list 'refused '(url) ftp 'no-secret)
              (lambda () (curl-request-check (make-curl-request ftp))))
        (list "the request's URL, scheme-not-http, at submit" (list 'refused '(url) ftp 'no-secret)
              (lambda () (on-engine (lambda (e) (curl-submit e (make-curl-request ftp))))))
        (list "the request's URL, a parse failure, at check" (list 'refused '(url) spaced 'no-secret)
              (lambda () (curl-request-check (make-curl-request spaced))))
        (list "the request's URL, a parse failure, at submit" (list 'refused '(url) spaced 'no-secret)
              (lambda () (on-engine (lambda (e) (curl-submit e (make-curl-request spaced))))))
        (list "the request's URL, embedded-nul, at check" (list 'refused '(url) with-nul 'no-secret)
              (lambda () (curl-request-check (make-curl-request with-nul))))
        (list "the request's URL, not-utf-8, at check" (list 'refused '(url) latin-host 'no-secret)
              (lambda () (curl-request-check (make-curl-request latin-host))))
        (list "curl-url-part, its URL a parse failure" (list 'refused '(url) spaced 'no-secret)
              (lambda () (curl-url-part spaced 'host)))
        (list "curl-url-part, its host not UTF-8" (list 'refused '(url) latin-host 'no-secret)
              (lambda () (curl-url-part latin-host 'host)))
        (list "curl-url-part, its URL holding U+0000" (list 'refused '(url) with-nul 'no-secret)
              (lambda () (curl-url-part with-nul 'host)))
        (list "curl-url-resolve, its base a parse failure" (list 'refused '(url) spaced 'no-secret)
              (lambda () (curl-url-resolve spaced "x")))
        (list "curl-url-resolve, its reference a string that fails to parse" (list 'refused '(url) spaced 'no-secret)
              (lambda () (curl-url-resolve "http://h/" spaced)))
        (list "curl-url-resolve, its reference a string holding U+0000" (list 'refused '(reference) part 'no-secret)
              (lambda () (curl-url-resolve "http://h/" part)))
        (list "curl-url-resolve, its reference bytes holding 0x00" (list 'refused '(reference) part 'no-secret)
              (lambda () (curl-url-resolve "http://h/" (string->utf8 part))))
        (list "curl-url-append-query, its URL a parse failure" (list 'refused '(url) spaced 'no-secret)
              (lambda () (curl-url-append-query spaced "a=1")))
        (list "curl-url-append-query, its query part holding U+0000" (list 'refused '(query) part 'no-secret)
              (lambda () (curl-url-append-query "http://h/" part)))
        (list "curl-url-with-fragment, its URL a parse failure" (list 'refused '(url) spaced 'no-secret)
              (lambda () (curl-url-with-fragment spaced "f")))
        (list "curl-url-with-fragment, its fragment holding U+0000" (list 'refused '(fragment) part 'no-secret)
              (lambda () (curl-url-with-fragment "http://h/" part)))
        (list "curl-url-with-fragment, its fragment bytes holding 0x00" (list 'refused '(fragment) part 'no-secret)
              (lambda () (curl-url-with-fragment "http://h/" (string->utf8 part))))
        (list "the high level, a call's URL scheme-not-http, passed through" (list 'refused '(url) ftp 'no-secret)
              (lambda () (call-with-http-session (lambda (s) (http-get s ftp)))))
        (list "the high level, a call's URL a parse failure, passed through" (list 'refused '(url) spaced 'no-secret)
              (lambda () (call-with-http-session (lambda (s) (http-get s spaced)))))))

(test-equal "every path that refuses a URL holding a password, the request's at check and at submit, each URL function's URL, reference, query part and fragment, and the high level's, raises &curl-url-error whose irritants name its field, url, reference, query or fragment, whose input is still the string, and whose print holds no password"
  (map (lambda (c) (list (car c) (cadr c))) url-cases)
  (in-order (lambda (c) (list (car c) (url-refusal (caddr c)))) url-cases))

(test-equal "every count is zero at the end, the jar's and the session's engines stopped"
  '(freed ((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)))
  (list holders-freed (native-counts)))

(test-end "printed")

(exit (suite-exit-status runner))
