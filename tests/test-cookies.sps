#!r6rs
;;; The suite for the cookie jar (ADR-0035, amended twice; the M7 plan,
;;; sections 3.1, 3.5, 3.6, 3.7 and 6.4), at both levels, against the test
;;; origin's cookie route, whose log is the record of every Cookie header a
;;; request carried, never a status:
;;;
;;;   - the settings, as data: jar-settings and share-settings written out
;;;     whole, and the cookie-jar field's options;
;;;   - the load's rule, cookie-line-fault, on every control char and
;;;     every other Latin-1 char at the first, a middle and the last
;;;     position of every field, each field's rule against its whole
;;;     complement, the separators and the cookie prefixes, and the lines'
;;;     copy and its refusal, cookie-line, naming the line's index alone;
;;;   - the key: its default, its type, kept by curl-request-with, and
;;;     cookie-beside-jar at every position, in every case, A to Z folded
;;;     alone, at construction and at submit;
;;;   - through the engine: read-out and load, whole lines, Latin-1 both
;;;     ways; cookies across requests and hosts, three labels deep; the
;;;     messages taken in the order queued; the copy a load takes; the
;;;     lifetime: a close while held, a close crossing a submit, a stop, a
;;;     failed engine, a transfer whose start raised, every jar message
;;;     answered, one in a failing turn's batch among them, a hold let go
;;;     once, libcurl's answers read, an abandoned handle's share kept,
;;;     in a child; the counters at zero;
;;;   - the high level: a session's cookies, across hosts and a redirect's
;;;     hops, read out and loaded, refused beside a Cookie or Host header,
;;;     its jar freed with it;
;;;   - what varies by version (the M7 plan, section 3.7; ADR-0017's rule):
;;;     the read-out lines the load refuses, a loaded line whose expiry has
;;;     passed, 7.85.0's head left open by what it writes before its Cookie
;;;     line, a long URL or a long User-Agent, Domain=localhost
;;;     by the PSL bit, the default path, Path=rel and Path=, the 400-day
;;;     cap, Max-Age=-1, a deleted cookie still listed, and a __Host- cookie
;;;     with Domain=localhost;
;;;   - no exit printing a cookie's value: every refusal, a transfer's
;;;     failure, the jar, the request, the token, the session and the
;;;     responses.
;;;
;;; Every expected value is one the code under test cannot produce by
;;; failing: SRFI-64 makes #f of a raise in the actual expression, so none
;;; is #f. Each by-version table has a row for each of the five Linux
;;; libcurls, and fails by name, printing what it measured, on one with none
;;; (ADR-0017), Apple's 8.7.1 among them. A read-out's order moves with
;;; libcurl's hash table: every read-out is compared sorted.
(import (rnrs)
        (rnrs mutable-pairs)
        (rnrs mutable-strings)
        (srfi :64)
        (only (chezscheme) fork-thread make-mutex with-mutex sleep make-time current-time
              time-second time-nanosecond getenv display-condition library-directories
              critical-section list-head record-rtd iota)
        (curl-testing)
        (curl)
        (curl unsupported)
        (http-client)
        (only (curl private transfer) jar-settings share-settings cookie-line-fault cookie-line-bytes
              request-field-options check-cookie-beside-jar)
        (only (curl private engine) curl-cookie-jar-state curl-cookie-jar-holders curl-engine-jar-count
              curl-cookie-jar-post! curl-cookie-jar-await make-curl-engine-answering-jar
              make-curl-engine-delaying-take make-faulty-curl-engine curl-engine-queued-count
              call-with-engine-held curl-engine-state curl-engine-request-stop!)
        (only (curl private constants) curlshopt-share curl-lock-data-cookie)
        (only (http-client private call) session-on session-defaults http-session-engine)
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

(test-begin "cookies")

;; --- helpers --------------------------------------------------------------------------

(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)))

;; The loaded libcurl's version, and whether it was built with PSL, read
;; here, before any engine's thread is forked.
(define version
  (guard (e (#t (list 'no-version (describe e))))
    (libcurl-info-version (loaded-libcurl))))
(define psl?
  (guard (e (#t #f))
    (and (memq 'psl (libcurl-info-feature-names (loaded-libcurl))) #t)))

;; psl-lane : Any
;; The key of a table that varies by version and by the PSL bit:
;; VERSION/psl or VERSION/no-psl.
(define psl-lane (if (string? version) (string-append version (if psl? "/psl" "/no-psl")) version))

;; now-ms : -> Integer
(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

;; now-s : -> Integer
;; The UTC time in seconds, as a cookie's expiry counts it.
(define (now-s) (time-second (current-time 'time-utc)))

;; pause-ms : Natural -> Unit
(define (pause-ms ms)
  (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))

;; wait-for : (-> Any) Natural -> Any
;; THUNK's first true answer, read every 2 ms, or #f after MS ms.
(define (wait-for thunk ms)
  (let ((deadline (+ (now-ms) ms)))
    (let loop ()
      (or (thunk)
          (and (< (now-ms) deadline)
               (begin (pause-ms 2) (loop)))))))

;; contains? : String String -> Boolean
(define (contains? text part)
  (let ((n (string-length text)) (k (string-length part)))
    (let loop ((i 0))
      (and (<= (+ i k) n)
           (or (string=? (substring text i (+ i k)) part) (loop (+ i 1)))))))

;; tabbed : String ... -> String
;; FIELDS joined by tabs: a line, written so, never with a literal tab.
(define (tabbed . fields)
  (if (null? fields)
      ""
      (fold-left (lambda (line field) (string-append line "\t" field)) (car fields) (cdr fields))))

;; split-tabs : String -> (Listof String)
(define (split-tabs line)
  (let loop ((i 0) (start 0) (found '()))
    (cond ((= i (string-length line)) (reverse (cons (substring line start i) found)))
          ((char=? (string-ref line i) #\tab) (loop (+ i 1) (+ i 1) (cons (substring line start i) found)))
          (else (loop (+ i 1) start found)))))

;; sorted : (Listof String) -> (Listof String)
(define (sorted lines) (list-sort string<? lines))

;; repeat : Natural Char -> String
(define (repeat n c) (make-string n c))

;; refusal-of : Any -> Any
;; What RAISED is, as data: a request error's who, field, value and reason;
;; an http request error's; an engine error's reason; an assertion's who;
;; a transfer failure's reason and code; or (other WHO).
(define (refusal-of e)
  (cond ((eq? e 'no-raise) 'no-raise)
        ((curl-request-error? e)
         (list 'request-refused (and (who-condition? e) (condition-who e)) (curl-request-error-field e)
               (curl-request-error-value e) (curl-request-error-reason e)))
        ((http-request-error? e)
         (list 'http-refused (http-request-error-field e) (http-request-error-value e)
               (http-request-error-reason e)))
        ((curl-engine-error? e) (list 'engine-error (curl-engine-error-reason e)))
        ((curl-transfer-error? e)
         (list 'transfer-failed (curl-transfer-error-reason e) (curl-transfer-error-code e)))
        ((assertion-violation? e) (list 'assertion (and (who-condition? e) (condition-who e))))
        ((error? e) (list 'error (and (who-condition? e) (condition-who e))
                          (and (irritants-condition? e) (condition-irritants e))))
        (else (list 'other (and (condition? e) (who-condition? e) (condition-who e))))))

;; raised : (-> Any) -> Any
;; What THUNK raised, or no-raise, a symbol nothing raises here.
(define (raised thunk)
  (call/cc
   (lambda (k)
     (with-exception-handler
      (lambda (e) (k e))
      (lambda () (thunk) 'no-raise)))))

;; refused : (-> Any) -> Any
(define (refused thunk) (refusal-of (raised thunk)))

;; outcome-of : Token -> Any
;; A done token's outcome, as data: (response STATUS) or refusal-of's.
(define (outcome-of token)
  (let ((o (curl-token-outcome token)))
    (cond ((not o) 'not-done)
          ((curl-response? o) (list 'response (curl-response-status o)))
          (else (refusal-of o)))))

;; share-count : -> Natural
(define (share-count) (cdr (assq 'share (native-counts))))
(define (easy-count) (cdr (assq 'easy (native-counts))))

;; printed : Any -> String
;; X as write, display and display-condition print it, one after another.
(define (printed x)
  (call-with-string-output-port
   (lambda (p)
     (write x p) (newline p) (display x p) (newline p)
     (when (condition? x) (display-condition x p)))))

;; library-path : -> String
;; This suite's library path, as --libdirs takes it.
(define (library-path)
  (let loop ((dirs (map car (library-directories))) (text ""))
    (cond ((null? dirs) text)
          ((string=? text "") (loop (cdr dirs) (car dirs)))
          (else (loop (cdr dirs) (string-append text ":" (car dirs)))))))

;; read-all : String -> (Listof Any)
;; TEXT read as data, each datum in turn; one that does not read ends the
;; list with (unreadable).
(define (read-all text)
  (let ((port (open-string-input-port text)))
    (let loop ((found '()))
      (let ((datum (guard (e (#t '(unreadable))) (read port))))
        (cond ((eof-object? datum) (reverse found))
              ((equal? datum '(unreadable)) (reverse (cons datum found)))
              (else (loop (cons datum found))))))))

;; by-version : (Listof (Pairof Any Any)) String Any (-> Any) -> (List Any Any)
;; A per-version test's expected and actual values, from ROWS for KEY and
;; MEASURE's answer: the row's value and the measurement; with no row,
;; (a-row-for KEY), which no measurement gives, and (no-row-for KEY
;; measured M), so the failure names the libcurl and prints the row it
;; lacks (ADR-0017; AGENTS.md's by-version trap). TAG names the table, on
;; stdout with the key and the measurement, as evidence of what ran, and
;; on the error port with the row a libcurl with none would need.
(define (by-version rows tag key measure)
  (let ((row (assoc key rows))
        (measured (guard (e (#t (list 'raised (describe e)))) (measure))))
    (display (string-append "test-cookies: " tag " on " (written key) " measured "
                            (written measured) "\n"))
    (unless row
      (display (string-append "test-cookies: no row of " tag " for this libcurl; measured, it would be:\n")
               (current-error-port))
      (write (cons key measured) (current-error-port))
      (newline (current-error-port)))
    (if row
        (list (cdr row) measured)
        (list (list 'a-row-for key) (list 'no-row-for key 'measured measured)))))

;; spawn : (-> Any) -> (-> (U (List 'answered Any) #f))
;; THUNK on a thread of its own, its answer, or what it raised as
;; (raised D), kept under a mutex; and a reader of it, #f until it is
;; there. Whatever the thread raises is its answer, so no thread dies with
;; a waiter left (AGENTS.md).
(define (spawn thunk)
  (let ((box (vector #f)) (lock (make-mutex)))
    (fork-thread
     (lambda ()
       (let ((answer (guard (e (#t (list 'raised (refusal-of e)))) (list 'returned (thunk)))))
         (critical-section (with-mutex lock (vector-set! box 0 answer))))))
    (lambda () (critical-section (with-mutex lock (vector-ref box 0))))))

;; seam-counts-same : Boolean
;; Whether a make the seam failed left the counts as they were, read on
;; the engine it failed on, its own block and multi handle counted alike.
(define seam-counts-same 'unread)

;; joined : (-> Any) Natural -> Any
;; READER's answer within MS ms, or (not-answered MS).
(define (joined reader ms)
  (or (wait-for reader ms) (list 'not-answered ms)))

;; --- the settings, as data (ADR-0035, decisions 1 and 2) ---------------------------------

(test-equal "jar-settings, written out whole: SHARE at the jar's share, then COOKIEFILE at \"\"; and none for no jar"
  '((("SHARE" . 4660) ("COOKIEFILE" . "")) ())
  (list (jar-settings 4660) (jar-settings #f)))

(test-equal "share-settings, written out whole: one curl_share_setopt call, CURLSHOPT_SHARE, 1, at CURL_LOCK_DATA_COOKIE, 2, alone: no HSTS, no DNS, no lock callbacks"
  '(((1 . 2)) (1 2))
  (list share-settings (list curlshopt-share curl-lock-data-cookie)))

(test-equal "the cookie-jar field sets SHARE then COOKIEFILE, its row of request-field-options"
  '(cookie-jar "SHARE" "COOKIEFILE")
  (assq 'cookie-jar request-field-options))

;; --- the load's rule (ADR-0035, amended 2026-11-04, decisions 7 and 8) --------------------

;; The base line: every field a non-default value, which the rule takes.
(define base-fields '("#HttpOnly_.b.a.localhost" "TRUE" "/p/q" "TRUE" "1893456000" "nm" "v1"))

;; line-of : (Listof String) -> String
(define (line-of fields) (apply tabbed fields))

;; with-field : Natural String -> String
;; The base line with field I replaced by TEXT.
(define (with-field i text)
  (line-of (let loop ((rest base-fields) (j 0))
             (if (null? rest) '() (cons (if (= j i) text (car rest)) (loop (cdr rest) (+ j 1)))))))

;; inserted : String Natural Char -> String
(define (inserted text at c)
  (string-append (substring text 0 at) (string c) (substring text at (string-length text))))

(test-equal "the base line, each field a value but the default, is taken; so is a plain one"
  '(#f #f)
  (list (cookie-line-fault (line-of base-fields))
        (cookie-line-fault (tabbed "b.a.localhost" "FALSE" "/" "FALSE" "0" "n" "v"))))

;; The byte classes: each control a load refuses, every one, U+0000 to
;; U+001F but the tab, and U+007F; a tab, which makes an extra field; a
;; char above U+00FF; and the bytes it takes, as a letter.
(define control-chars
  (map integer->char (append (filter (lambda (i) (not (= i 9))) (iota 32)) '(#x7F))))

;; latin-1-chars : (Listof Char)
;; Every Latin-1 char, U+0000 to U+00FF.
(define latin-1-chars (map integer->char (iota 256)))

;; control? : Char -> Boolean
(define (control? c) (let ((i (char->integer c))) (or (< i #x20) (= i #x7F))))

;; fault-of : String -> Any
;; LINE's fault, or (raised D) for what judging it raised: a rule must
;; answer, never raise.
(define (fault-of line) (guard (e (#t (list 'raised (refusal-of e)))) (cookie-line-fault line)))
(define taken-chars (map integer->char '(#x20 #x7E #x80 #xFF)))
(define wide-char (integer->char #x100))

;; places : (Listof (List Natural Natural))
;; Each field, and the first, a middle and the last position in it.
(define places
  (apply append
         (map (lambda (i field)
                (let ((n (string-length field)))
                  (list (list i 0) (list i (div n 2)) (list i n))))
              '(0 1 2 3 4 5 6) base-fields)))

(test-equal "every control char a load refuses, U+0000 to U+001F but the tab, and U+007F, 32 of them, at the first, a middle and the last position of every field, is control-byte; a tab there makes another field, fields; a char above U+00FF, not-latin-1"
  (map (lambda (place) (cons place (append (map (lambda (c) 'control-byte) control-chars) '(fields not-latin-1))))
       places)
  (map (lambda (place)
         (let ((field (list-ref base-fields (car place))))
           (cons place
                 (map (lambda (c) (cookie-line-fault (with-field (car place) (inserted field (cadr place) c))))
                      (append control-chars (list #\tab wide-char))))))
       places))

(test-equal "every other Latin-1 char, U+0020 to U+007E and U+0080 to U+00FF, 222 of them, at the first, a middle and the last position of every field, is never control-byte, fields or not-latin-1, and raises nothing"
  '()
  (apply append
         (map (lambda (place)
                (let ((field (list-ref base-fields (car place))))
                  (fold-left (lambda (found c)
                               (let ((f (fault-of (with-field (car place) (inserted field (cadr place) c)))))
                                 (if (or (memq f '(control-byte fields not-latin-1)) (pair? f))
                                     (cons (list place (char->integer c) f) found)
                                     found)))
                             '()
                             (filter (lambda (c) (not (control? c))) latin-1-chars))))
              places)))

(test-equal "a space, U+007E, U+0080 and U+00FF, at the first, a middle and the last position of every field, read as a letter does: whatever rule a letter there breaks, and no other"
  (map (lambda (place)
         (let ((field (list-ref base-fields (car place))))
           (cons place (map (lambda (c) (cookie-line-fault (with-field (car place) (inserted field (cadr place) #\x))))
                            taken-chars))))
       places)
  (map (lambda (place)
         (let ((field (list-ref base-fields (car place))))
           (cons place (map (lambda (c) (cookie-line-fault (with-field (car place) (inserted field (cadr place) c))))
                            taken-chars))))
       places))

(test-equal "seven fields alone: six, eight, one, and the empty line are fields; a value left empty is taken"
  '(fields fields fields fields #f)
  (list (cookie-line-fault (apply tabbed (list-head base-fields 6)))
        (cookie-line-fault (apply tabbed (append base-fields '("x"))))
        (cookie-line-fault "a.localhost")
        (cookie-line-fault "")
        (cookie-line-fault (with-field 6 ""))))

(test-equal "the domain: #HttpOnly_ in that case exactly, then a domain neither empty nor starting with #: an empty one, #HttpOnly_ alone, #httponly_, #HTTPONLY_, #HttpOnly with no _, #HttpOnly_ twice and a bare # are domain; #HttpOnly_ before a domain, and none, taken"
  '(domain domain domain domain domain domain domain #f #f)
  (map (lambda (d) (cookie-line-fault (tabbed d "FALSE" "/" "FALSE" "0" "n" "v")))
       '("" "#HttpOnly_" "#httponly_b.a.localhost" "#HTTPONLY_b.a.localhost" "#HttpOnlyb.a.localhost"
         "#HttpOnly_#HttpOnly_b.a.localhost" "#b.a.localhost" "#HttpOnly_b.a.localhost" "b.a.localhost")))

;; case-variants : String -> (Listof String)
;; TEXT in every case of its letters, A to Z: each letter lower and upper.
(define (case-variants text)
  (if (= (string-length text) 0)
      '("")
      (let ((c (string-ref text 0))
            (rest (case-variants (substring text 1 (string-length text)))))
        (if (char-alphabetic? c)
            (append (map (lambda (r) (string-append (string (char-downcase c)) r)) rest)
                    (map (lambda (r) (string-append (string (char-upcase c)) r)) rest))
            (map (lambda (r) (string-append (string c) r)) rest)))))

(test-equal "a line starting Set-Cookie:, in every one of its 512 A to Z cases, is set-cookie, before its fields are read; Set-Cookie with no colon, a domain beside FALSE, is taken; KELVIN SIGN for its k and LONG S for its s are not-latin-1, a rule read before any case is"
  (list 512 '(set-cookie) #f 'not-latin-1 'not-latin-1)
  (let ((variants (case-variants "set-cookie:")))
    (list (length variants)
          (fold-left (lambda (found v)
                       (let ((f (cookie-line-fault (tabbed v "FALSE" "/" "FALSE" "0" "n" "v"))))
                         (if (member f found) found (cons f found))))
                     '() variants)
          (cookie-line-fault (tabbed "Set-Cookie" "FALSE" "/" "FALSE" "0" "n" "v"))
          (cookie-line-fault (tabbed (string-append "Set-Coo" (string (integer->char #x212A)) "ie:")
                                     "FALSE" "/" "FALSE" "0" "n" "v"))
          (cookie-line-fault (tabbed (string-append (string (integer->char #x17F)) "et-Cookie:")
                                     "FALSE" "/" "FALSE" "0" "n" "v")))))

;; Every value a TRUE or FALSE field must refuse: other cases, a word, a
;; digit, empty, padded.
(define not-booleans '("true" "True" "TRUe" "false" "False" "FALSe" "yes" "no" "1" "0" "" " TRUE" "TRUE "))

(test-equal "the tail-match field is TRUE or FALSE exactly: every other case, yes, no, 1, 0, empty, and padded, tail-match; TRUE beside a dot and FALSE beside none taken"
  (append (map (lambda (v) 'tail-match) not-booleans) '(#f #f))
  (append (map (lambda (v) (cookie-line-fault (tabbed ".b.a.localhost" v "/" "FALSE" "0" "n" "v"))) not-booleans)
          (list (cookie-line-fault (tabbed ".b.a.localhost" "TRUE" "/" "FALSE" "0" "n" "v"))
                (cookie-line-fault (tabbed "b.a.localhost" "FALSE" "/" "FALSE" "0" "n" "v")))))

(test-equal "the secure field is TRUE or FALSE exactly, the same complement refused, secure"
  (append (map (lambda (v) 'secure) not-booleans) '(#f #f))
  (append (map (lambda (v) (cookie-line-fault (tabbed "b.a.localhost" "FALSE" "/" v "0" "n" "v"))) not-booleans)
          (list (cookie-line-fault (tabbed "b.a.localhost" "FALSE" "/" "TRUE" "0" "n" "v"))
                (cookie-line-fault (tabbed "b.a.localhost" "FALSE" "/" "FALSE" "0" "n" "v")))))

;; boolean-values : (Listof String)
;; Every Latin-1 char alone, and every A to Z case of TRUE and FALSE.
(define boolean-values
  (append (map string latin-1-chars) (case-variants "TRUE") (case-variants "FALSE")))

;; boolean-expected : String Symbol -> Any
;; What a TRUE or FALSE field holding V must be judged, RULE that field's
;; rule: taken for TRUE and FALSE exactly; a control char, control-byte;
;; a tab, fields; anything else, RULE.
(define (boolean-expected v rule)
  (cond ((member v '("TRUE" "FALSE")) #f)
        ((and (= (string-length v) 1) (char=? (string-ref v 0) #\tab)) 'fields)
        ((and (= (string-length v) 1) (control? (string-ref v 0))) 'control-byte)
        (else rule)))

(test-equal "the tail-match field against its whole complement: every Latin-1 char alone, and every A to Z case of TRUE, 16, and of FALSE, 32: TRUE and FALSE taken, a control char control-byte, a tab fields, every other tail-match"
  (map (lambda (v) (boolean-expected v 'tail-match)) boolean-values)
  (map (lambda (v)
         (fault-of (tabbed (if (string=? v "TRUE") ".b.a.localhost" "b.a.localhost") v "/" "FALSE" "0" "n" "v")))
       boolean-values))

(test-equal "the secure field against the same complement: TRUE and FALSE taken, a control char control-byte, a tab fields, every other secure"
  (map (lambda (v) (boolean-expected v 'secure)) boolean-values)
  (map (lambda (v) (fault-of (tabbed "b.a.localhost" "FALSE" "/" v "0" "n" "v"))) boolean-values))

(test-equal "a dot before the domain exactly when the tail-match is TRUE: a dot beside FALSE and none beside TRUE, after #HttpOnly_ too, leading-dot; the two that agree taken"
  '(leading-dot leading-dot leading-dot leading-dot #f #f #f #f)
  (map (lambda (pair) (cookie-line-fault (tabbed (car pair) (cdr pair) "/" "FALSE" "0" "n" "v")))
       '((".b.a.localhost" . "FALSE") ("b.a.localhost" . "TRUE")
         ("#HttpOnly_.b.a.localhost" . "FALSE") ("#HttpOnly_b.a.localhost" . "TRUE")
         (".b.a.localhost" . "TRUE") ("b.a.localhost" . "FALSE")
         ("#HttpOnly_.b.a.localhost" . "TRUE") ("#HttpOnly_b.a.localhost" . "FALSE"))))

(test-equal "the path starts with /: empty, rel, TRUE, FALSE, a space before /, and a backslash are path; /, /a and //x taken"
  '(path path path path path path #f #f #f)
  (map (lambda (p) (cookie-line-fault (tabbed "b.a.localhost" "FALSE" p "FALSE" "0" "n" "v")))
       '("" "rel" "TRUE" "FALSE" " /" "\\a" "/" "/a" "//x")))

(test-equal "the expiry is decimal digits, at most 9223372036854775807: a sign either way, a space before and after, 0x, an exponent, a dot, empty, 2^63 and one past it are expiry; 0, 00, 007, 1 and 2^63 - 1 taken"
  '(expiry expiry expiry expiry expiry expiry expiry expiry expiry expiry #f #f #f #f #f)
  (map (lambda (x) (cookie-line-fault (tabbed "b.a.localhost" "FALSE" "/" "FALSE" x "n" "v")))
       '("+5" "-1" " 5" "5 " "0x10" "1e3" "1.5" "" "9223372036854775808" "9223372036854775809"
         "0" "00" "007" "1" "9223372036854775807")))

(test-equal "the expiry against every Latin-1 char but the ten digits, alone and between two digits: a control char control-byte, a tab fields, every other expiry, U+00B2, U+00B3, U+00B9 and the other numerics among them, never raising; each digit alone and between two taken"
  (append (map (lambda (c) (cond ((char=? c #\tab) '(fields fields))
                                 ((control? c) '(control-byte control-byte))
                                 (else '(expiry expiry))))
               (filter (lambda (c) (not (char<=? #\0 c #\9))) latin-1-chars))
          (map (lambda (c) '(#f #f)) (string->list "0123456789")))
  (map (lambda (c)
         (list (fault-of (tabbed "b.a.localhost" "FALSE" "/" "FALSE" (string c) "n" "v"))
               (fault-of (tabbed "b.a.localhost" "FALSE" "/" "FALSE" (string #\1 c #\1) "n" "v"))))
       (append (filter (lambda (c) (not (char<=? #\0 c #\9))) latin-1-chars) (string->list "0123456789"))))

(test-equal "a name: an empty one is name; one char taken"
  '(name #f)
  (list (cookie-line-fault (tabbed "b.a.localhost" "FALSE" "/" "FALSE" "0" "" "v"))
        (cookie-line-fault (tabbed "b.a.localhost" "FALSE" "/" "FALSE" "0" "n" ""))))

(test-equal "the name and the value at most 4,096 chars together, split each way: 1 + 4,095, 4,095 + 1, 2,048 + 2,048 and 4,096 + 0 taken; 1 + 4,096, 4,096 + 1, 2,048 + 2,049 and 4,097 + 0 are size"
  '(#f #f #f #f size size size size)
  (map (lambda (pair)
         (cookie-line-fault (tabbed "b.a.localhost" "FALSE" "/" "FALSE" "0" (repeat (car pair) #\n)
                                    (repeat (cdr pair) #\v))))
       '((1 . 4095) (4095 . 1) (2048 . 2048) (4096 . 0) (1 . 4096) (4096 . 1) (2048 . 2049) (4097 . 0))))

;; string-starts? : String String -> Boolean
(define (string-starts? s prefix)
  (and (>= (string-length s) (string-length prefix))
       (string=? (substring s 0 (string-length prefix)) prefix)))

;; separator-lines : (Listof (List String String String))
;; Each separator case: what it is, the name and the value.
(define separator-lines
  (append (map (lambda (at) (list (string-append "; in the name at " (number->string at)) (inserted "name" at #\;) "value"))
               '(0 2 4))
          (map (lambda (at) (list (string-append "; in the value at " (number->string at)) "name" (inserted "value" at #\;)))
               '(0 2 5))
          (map (lambda (at) (list (string-append "= in the name at " (number->string at)) (inserted "name" at #\=) "value"))
               '(0 2 4))
          (map (lambda (at) (list (string-append "= in the value at " (number->string at)) "name" (inserted "value" at #\=)))
               '(0 2 5))))

(test-equal "a ; in the name or the value, or an = in the name, at the first, a middle and the last position, is separator: a read-out never holds one; an = in the value, at each, taken"
  (map (lambda (c) (list (car c) (if (string-starts? (car c) "= in the value") #f 'separator))) separator-lines)
  (map (lambda (c) (list (car c) (fault-of (tabbed "b.a.localhost" "FALSE" "/" "FALSE" "0" (cadr c) (caddr c)))))
       separator-lines))

;; prefix-line : String String String String -> String
;; A line named NAME, with TAIL, PATH and SECURE, its domain dotted
;; exactly beside TAIL TRUE.
(define (prefix-line name tail path secure)
  (tabbed (if (string=? tail "TRUE") ".b.a.localhost" "b.a.localhost") tail path secure "0" name "v"))

(test-equal "a __Secure- name, in every one of its 64 A to Z cases, __secure-, __SECURE- and __sEcure- among them, needs the secure field TRUE: beside FALSE it is prefix, beside TRUE taken, whatever the path and the tail-match"
  (list 64 '(prefix) '(#f))
  (let ((variants (map (lambda (v) (string-append v "a")) (case-variants "__secure-"))))
    (list (length variants)
          (fold-left (lambda (found v)
                       (let ((f (fault-of (prefix-line v "TRUE" "/p" "FALSE")))) (if (member f found) found (cons f found))))
                     '() variants)
          (fold-left (lambda (found v)
                       (let ((f (fault-of (prefix-line v "TRUE" "/p" "TRUE")))) (if (member f found) found (cons f found))))
                     '() variants))))

(test-equal "a __Host- name, in every one of its 16 A to Z cases, __host- and __HOST- among them, needs the secure field TRUE, the path exactly / and the tail-match FALSE: each broken alone is prefix, all three kept taken"
  (list 16 '(prefix) '(prefix) '(prefix) '(#f))
  (let ((variants (map (lambda (v) (string-append v "a")) (case-variants "__host-"))))
    (define (faults tail path secure)
      (fold-left (lambda (found v)
                   (let ((f (fault-of (prefix-line v tail path secure)))) (if (member f found) found (cons f found))))
                 '() variants))
    (list (length variants)
          (faults "FALSE" "/" "FALSE")
          (faults "FALSE" "/p" "TRUE")
          (faults "TRUE" "/" "TRUE")
          (faults "FALSE" "/" "TRUE"))))

(test-equal "a name that only nearly holds a prefix is taken beside fields no prefix allows: __Secure, _Secure-, __Securex, __Secure_, __Host, _Host-, __Hostx, and a prefix after a first char, x__Secure-"
  '(#f #f #f #f #f #f #f #f)
  (map (lambda (name) (fault-of (prefix-line name "TRUE" "/p" "FALSE")))
       '("__Secure" "_Secure-" "__Securex" "__Secure_" "__Host" "_Host-" "__Hostx" "x__Secure-")))

(test-equal "the rules in order: a char above U+00FF before a control byte, a control byte before Set-Cookie:, Set-Cookie: before the fields' count, the count before the domain, each field's rule in the fields' order, then the name's: empty, a separator, the size, the prefix"
  '(not-latin-1 control-byte set-cookie fields domain tail-match path secure expiry name separator size prefix)
  (list (cookie-line-fault (string-append (string wide-char) "\x1;"))
        (cookie-line-fault (string-append "Set-Cookie:" (string #\x1)))
        (cookie-line-fault "Set-Cookie:x")
        (cookie-line-fault (tabbed "" "x"))
        (cookie-line-fault (tabbed "" "x" "x" "x" "x" "" "v"))
        (cookie-line-fault (tabbed "a" "x" "x" "x" "x" "" "v"))
        (cookie-line-fault (tabbed "a" "FALSE" "x" "x" "x" "" "v"))
        (cookie-line-fault (tabbed "a" "FALSE" "/" "x" "x" "" "v"))
        (cookie-line-fault (tabbed "a" "FALSE" "/" "FALSE" "x" "" "v"))
        (cookie-line-fault (tabbed "a" "FALSE" "/" "FALSE" "0" "" "v;"))
        (cookie-line-fault (tabbed "a" "FALSE" "/" "FALSE" "0" "__Secure-;" (repeat 4096 #\v)))
        (cookie-line-fault (tabbed "a" "FALSE" "/" "FALSE" "0" "__Secure-n" (repeat 4096 #\v)))
        (cookie-line-fault (tabbed "a" "FALSE" "/" "FALSE" "0" "__Secure-n" "v"))))

(test-equal "cookie-line-bytes: each line a Latin-1 copy, each char one byte, U+00E9 and U+00FF as E9 and FF"
  (list (u8-list->bytevector (append (map char->integer (string->list (tabbed "b.a.localhost" "FALSE" "/" "FALSE" "0" "n" "v")))
                                     '(#xE9 #xFF))))
  (cookie-line-bytes 'w (list (string-append (tabbed "b.a.localhost" "FALSE" "/" "FALSE" "0" "n" "v")
                                             (string (integer->char #xE9) (integer->char #xFF))))))

(define secret-value "C00kieV4lue")

(test-equal "cookie-line-bytes refuses the first line that breaks a rule, as WHO: &curl-request-error, field lines, its value the line's index from 0, its irritants the index and the rule, never the line, whose value is a secret, its message the rule's; every line is checked, the last too"
  (list '(request-refused w lines 1 cookie-line) '(1 control-byte) #f
        '(request-refused w lines 2 cookie-line) '(2 size)
        "a cookie line a load takes is one in the form a read-out writes: seven tab-separated fields, no control byte, TRUE or FALSE, an absolute path, an expiry of decimal digits, a name, no ; in the name or the value and no = in the name, a name and value of 4,096 bytes at most, and a __Secure- or __Host- name only beside its prefix's fields")
  (let* ((good (tabbed "b.a.localhost" "FALSE" "/" "FALSE" "0" "n" secret-value))
         (bad (tabbed "b.a.localhost" "FALSE" "/" "FALSE" "0" "n" (string-append secret-value "\r")))
         (big (tabbed "b.a.localhost" "FALSE" "/" "FALSE" "0" "n" (string-append secret-value (repeat 4096 #\v))))
         (a (raised (lambda () (cookie-line-bytes 'w (list good bad big)))))
         (b (raised (lambda () (cookie-line-bytes 'w (list good good big))))))
    (list (refusal-of a) (condition-irritants a) (contains? (printed a) secret-value)
          (refusal-of b) (condition-irritants b) (condition-message b))))

(test-equal "cookie-line-bytes takes a list of strings alone: a string, a vector, an improper list, a list holding a symbol, an assertion violation naming the lines by their kind"
  '((assertion w) (assertion w) (assertion w) (assertion w) ((kind string)) ((kind list)))
  (let ((line (tabbed "b.a.localhost" "FALSE" "/" "FALSE" "0" "n" secret-value)))
    (list (refused (lambda () (cookie-line-bytes 'w line)))
          (refused (lambda () (cookie-line-bytes 'w (vector line))))
          (refused (lambda () (cookie-line-bytes 'w (cons line line))))
          (refused (lambda () (cookie-line-bytes 'w (list line 'x))))
          (condition-irritants (raised (lambda () (cookie-line-bytes 'w line))))
          (condition-irritants (raised (lambda () (cookie-line-bytes 'w (list line 'x))))))))

;; --- the key (ADR-0035; the M7 plan, section 3.1) -------------------------------------

;; The suite's own engine and jar, for the checks that need a jar alone.
(define key-engine (guard (e (#t (list 'raised (describe e)))) (make-curl-engine)))
(define key-jar (guard (e (#t (list 'raised (describe e)))) (make-curl-cookie-jar key-engine)))
(define key-made? (curl-cookie-jar? key-jar))

(test-equal "a jar is made on its engine, live, holding no transfer, the engine's one jar, its share and its handle counted, one of each"
  '(#t live 0 1 1 1)
  (if key-made?
      (list (curl-cookie-jar? key-jar) (curl-cookie-jar-state key-jar) (curl-cookie-jar-holders key-jar)
            (curl-engine-jar-count key-engine) (share-count) (easy-count))
      key-jar))

(test-equal "a jar is opaque: it prints as #<curl-cookie-jar>, and record-rtd opens it not"
  '("#<curl-cookie-jar>" (assertion record-rtd))
  (if key-made?
      (list (written key-jar) (refused (lambda () (record-rtd key-jar))))
      key-jar))

(test-equal "inside a critical section, each jar procedure, which waits as a stop does, refuses before anything else, an assertion violation naming it: no jar made, nothing queued, the jar still live"
  '((assertion make-curl-cookie-jar) (assertion curl-cookie-jar-cookies) (assertion curl-cookie-jar-load!)
    (assertion curl-cookie-jar-close!) 1 0 live)
  (if key-made?
      (let* ((made (refused (lambda () (critical-section (make-curl-cookie-jar key-engine)))))
             (read (refused (lambda () (critical-section (curl-cookie-jar-cookies key-jar)))))
             (load (refused (lambda () (critical-section (curl-cookie-jar-load! key-jar '())))))
             (close (refused (lambda () (critical-section (curl-cookie-jar-close! key-jar))))))
        (list made read load close (curl-engine-jar-count key-engine) (curl-engine-queued-count key-engine)
              (curl-cookie-jar-state key-jar)))
      key-jar))

(test-equal "cookie-jar: #f by default; a jar where given, kept by curl-request-with, and replaced by #f; and anything else, 5, a string, an engine, an assertion violation naming it by its kind"
  (list #f #t #t #f '(assertion make-curl-request) '(assertion make-curl-request) '(assertion make-curl-request)
        '(5) '((kind string)) '((kind other)))
  (if key-made?
      (let ((r (make-curl-request "http://a/" 'cookie-jar key-jar)))
        (list (curl-request-cookie-jar (make-curl-request "http://a/"))
              (eq? (curl-request-cookie-jar r) key-jar)
              (eq? (curl-request-cookie-jar (curl-request-with r 'timeout-ms 5)) key-jar)
              (curl-request-cookie-jar (curl-request-with r 'cookie-jar #f))
              (refused (lambda () (make-curl-request "http://a/" 'cookie-jar 5)))
              (refused (lambda () (make-curl-request "http://a/" 'cookie-jar secret-value)))
              (refused (lambda () (make-curl-request "http://a/" 'cookie-jar key-engine)))
              (condition-irritants (raised (lambda () (make-curl-request "http://a/" 'cookie-jar 5))))
              (condition-irritants (raised (lambda () (make-curl-request "http://a/" 'cookie-jar secret-value))))
              (condition-irritants (raised (lambda () (make-curl-request "http://a/" 'cookie-jar key-engine))))))
      key-jar))

;; The names cookie-beside-jar refuses: Cookie and Host in four cases each.
(define jar-header-names '("Cookie" "cookie" "COOKIE" "cOoKiE" "Host" "host" "HOST" "hOsT"))

(test-equal "beside a jar, a header named Cookie or Host, in every case shown, any value, empty too, at the first, the middle and the last place of three, is refused as made, cookie-beside-jar, naming the header as given, never its value"
  (apply append
         (map (lambda (name)
                (map (lambda (at) (list 'request-refused 'make-curl-request 'header-name name 'cookie-beside-jar))
                     '(0 1 2 0)))
              jar-header-names))
  (if key-made?
      (apply append
             (map (lambda (name)
                    (map (lambda (at value)
                           (let ((headers (list (cons "X-A" "1") (cons "X-B" "2"))))
                             (refused (lambda ()
                                        (make-curl-request "http://a/" 'cookie-jar key-jar
                                                           'headers (append (list-head headers at)
                                                                            (list (cons name value))
                                                                            (list-tail headers at)))))))
                         '(0 1 2 0) (list secret-value secret-value secret-value "")))
                  jar-header-names))
      key-jar))

(test-equal "beside a jar the neighbours pass: Cookie2, Cookies, X-Cookie, Set-Cookie, Hosts, Host-X; and with no jar, Cookie and Host pass"
  '(no-raise no-raise no-raise no-raise no-raise no-raise no-raise no-raise)
  (if key-made?
      (append (map (lambda (name)
                     (refused (lambda () (make-curl-request "http://a/" 'cookie-jar key-jar
                                                            'headers (list (cons name "1"))))))
                   '("Cookie2" "Cookies" "X-Cookie" "Set-Cookie" "Hosts" "Host-X"))
              (list (refused (lambda () (make-curl-request "http://a/" 'headers '(("Cookie" . "a=1")))))
                    (refused (lambda () (make-curl-request "http://a/" 'headers '(("Host" . "h")))))))
      key-jar))

(test-equal "the check folds A to Z alone: KELVIN SIGN for Cookie's k and LONG S for Host's s pass it, where string-ci=? would fold them; and with no jar nothing is refused"
  '(no-raise no-raise (request-refused w header-name "COOKIE" cookie-beside-jar) no-raise)
  (if key-made?
      (list (refused (lambda () (check-cookie-beside-jar 'w key-jar (list (cons (string-append "Coo" (string (integer->char #x212A)) "ie") "1")))))
            (refused (lambda () (check-cookie-beside-jar 'w key-jar (list (cons (string-append "Ho" (string (integer->char #x17F)) "t") "1")))))
            (refused (lambda () (check-cookie-beside-jar 'w key-jar '(("COOKIE" . "1")))))
            (refused (lambda () (check-cookie-beside-jar 'w #f '(("Cookie" . "1") ("Host" . "h"))))))
      key-jar))

(test-equal "a header renamed Cookie after the request was made is refused at submit and at curl-request-check, on their own copies"
  '((request-refused curl-submit header-name "Cookie" cookie-beside-jar)
    (request-refused curl-request-check header-name "Cookie" cookie-beside-jar))
  (if key-made?
      (let* ((name (string-copy "Xookie"))
             (r (make-curl-request "http://127.0.0.1:9/" 'cookie-jar key-jar 'headers (list (cons name "1")))))
        (string-set! name 0 #\C)
        (list (refused (lambda () (curl-submit key-engine r)))
              (refused (lambda () (curl-request-check r)))))
      key-jar))

(test-equal "a submit refuses another engine's jar, cookie-jar-engine, before anything is queued, its value the symbol cookie-jar"
  '((request-refused curl-submit cookie-jar cookie-jar cookie-jar-engine) 0)
  (if key-made?
      (let ((other (make-curl-engine)))
        (dynamic-wind
          (lambda () #f)
          (lambda ()
            (list (refused (lambda () (curl-submit other (make-curl-request "http://127.0.0.1:9/" 'cookie-jar key-jar))))
                  (curl-engine-queued-count other)))
          (lambda () (curl-engine-stop other))))
      key-jar))

;; --- through the engine, against the origin -------------------------------------------------

;; on-jar : (Engine Jar -> Any) -> Any
;; PROC's answer on an engine of its own and a jar of it, the engine
;; stopped after, whatever PROC does.
(define (on-jar proc)
  (let ((e (make-curl-engine)))
    (dynamic-wind (lambda () #f)
                  (lambda () (proc e (make-curl-cookie-jar e)))
                  (lambda () (curl-engine-stop e)))))

;; port-of : Origin -> String
(define (port-of o) (number->string (cdr (origin-face o 'http))))

;; route : Origin String String String -> String
;; The cookie route on the http face at HOST, PATH below /cookies, for
;; KEY, with QUERY's pairs after the key.
(define (route o host path key query)
  (string-append "http://" host ":" (port-of o) "/cookies" path "?key=" key query))

;; fetch : Engine Jar String [Positive-Integer] -> Any
;; URL through ENGINE, holding JAR when it is one, bounded by TIMEOUT ms,
;; 20,000 unless given: the response's status and body, as data, or the
;; refusal.
(define (fetch engine jar url . timeout)
  (guard (e (#t (refusal-of e)))
    (let ((r (curl-token-await
              (curl-submit engine (apply make-curl-request url 'proxy #f
                                         'timeout-ms (if (pair? timeout) (car timeout) 20000)
                                         (if jar (list 'cookie-jar jar) '()))))))
      (list (curl-response-status r) (utf8->string (curl-response-body r))))))

;; log-lines : Origin String -> (Listof String)
;; The cookie route's log for KEY, its lines, read through a plain engine.
(define (log-lines o key)
  (let ((e (make-curl-engine)))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (let ((answer (fetch e #f (string-append "http://127.0.0.1:" (port-of o) "/cookie-log?key=" key))))
          (if (and (pair? answer) (eqv? (car answer) 200))
              (cdr (split-lines (cadr answer)))
              (list 'no-log answer))))
      (lambda () (curl-engine-stop e)))))

;; split-lines : String -> (Listof String)
(define (split-lines text)
  (let loop ((start 0) (i 0) (found '()))
    (cond ((= i (string-length text))
           (reverse (if (= start i) found (cons (substring text start i) found))))
          ((char=? (string-ref text i) #\newline)
           (loop (+ i 1) (+ i 1) (cons (substring text start i) found)))
          (else (loop start (+ i 1) found)))))

;; quoted : String -> String
;; TEXT, Latin-1, as the cookie route quotes a value, written here apart
;; from the origin's: printable ASCII as it is, but \ as \\ and " as \x22,
;; every other byte \xNN, lower case.
(define (quoted text)
  (string-append
   "\""
   (apply string-append
          (map (lambda (c)
                 (let ((b (char->integer c)))
                   (cond ((= b #x5c) "\\\\")
                         ((or (< b #x20) (> b #x7e) (= b #x22))
                          (string #\\ #\x (string-ref "0123456789abcdef" (div b 16))
                                  (string-ref "0123456789abcdef" (mod b 16))))
                         (else (string c)))))
               (string->list text)))
   "\""))

;; logged : Natural String String (Listof String) -> String
;; A cookie route log line: request N at HOST:PORT, its Cookie values.
(define (logged n host port cookies)
  (apply string-append "request " (number->string n) " face=http host=" (quoted (string-append host ":" port))
         " cookies=" (number->string (length cookies))
         (map (lambda (c) (string-append " cookie=" (quoted c))) cookies)))

;; expiry-kind : String Integer -> String
;; A read-out's expiry field as the tables write it: 0 and 1 as they are;
;; a time past NOW, past, within 400 days of it, within-400-days, or
;; beyond, beyond-400-days; anything else as it is.
(define (expiry-kind text now)
  (let ((n (and (> (string-length text) 0) (for-all char-numeric? (string->list text))
                (string->number text))))
    (cond ((not n) text)
          ((memv n '(0 1)) text)
          ((<= n now) "past")
          ((<= n (+ now 34560000 600)) "within-400-days")
          (else "beyond-400-days"))))

;; normal : (Listof String) -> (Listof String)
;; A read-out, its expiries as expiry-kind writes them, sorted.
(define (normal lines)
  (let ((now (now-s)))
    (sorted (map (lambda (line) (expiry-written line now)) lines))))

;; expiry-written : String Integer -> String
;; LINE with its expiry as expiry-kind writes it, for NOW, when it has
;; seven fields; else as it is.
(define (expiry-written line now)
  (let ((fields (split-tabs line)))
    (if (= (length fields) 7)
        (apply tabbed (append (list-head fields 4) (list (expiry-kind (list-ref fields 4) now))
                              (list-tail fields 5)))
        line)))

;; faulted : (Listof String) -> (Listof (List String (U Symbol #f)))
;; A read-out, each line as normal writes it, beside the rule's fault for
;; the line as read, sorted.
(define (faulted lines)
  (let ((now (now-s)))
    (list-sort (lambda (a b) (string<? (car a) (car b)))
               (map (lambda (line) (list (expiry-written line now) (cookie-line-fault line))) lines))))

;; with-port-named : String String -> String
;; TEXT with each :PORT written :<port>.
(define (with-port-named text port)
  (let ((k (+ 1 (string-length port))) (needle (string-append ":" port)))
    (let loop ((i 0) (out '()))
      (cond ((> (+ i k) (string-length text)) (apply string-append (reverse (cons (substring text i (string-length text)) out))))
            ((string=? (substring text i (+ i k)) needle) (loop (+ i k) (cons ":<port>" out)))
            (else (loop (+ i 1) (cons (string (string-ref text i)) out)))))))

;; crossing : Engine String Integer -> Any
;; One close and one submit on two threads of their own, the submit
;; OFFSET ms after the close, or before it for a negative one, both
;; from a start 20 ms on: ran, the transfer's 200 with the jar; submit,
;; refused at submit; setup, its token refused as it was set up; or
;; whatever else, as data; and the jar's state and holders after.
(define (crossing engine url offset)
  (let* ((jar (make-curl-cookie-jar engine))
         (start (+ (now-ms) 20))
         (at (lambda (ms) (let ((left (- (+ start ms) (now-ms)))) (when (> left 0) (pause-ms left)))))
         (closer (spawn (lambda () (at (max 0 (- offset))) (curl-cookie-jar-close! jar) 'closed)))
         (submitter (spawn (lambda ()
                             (at (max 0 offset))
                             (let ((t (guard (e (#t (list 'refused (refusal-of e))))
                                        (curl-submit engine (make-curl-request url 'cookie-jar jar 'proxy #f
                                                                               'timeout-ms 20000)))))
                               (if (curl-token? t)
                                   (begin (curl-token-wait t 20000) (outcome-of t))
                                   t)))))
         (closed (joined closer 30000))
         (submitted (joined submitter 30000)))
    (wait-for (lambda () (eq? (curl-cookie-jar-state jar) 'closed)) 5000)
    (list (cond ((equal? submitted '(returned (response 200))) 'ran)
                ((equal? submitted '(returned (refused (request-refused curl-submit cookie-jar cookie-jar cookie-jar-closed))))
                 'submit)
                ((equal? submitted '(returned (request-refused curl-submit cookie-jar cookie-jar cookie-jar-closed)))
                 'setup)
                (else (list 'other submitted closed)))
          (curl-cookie-jar-state jar) (curl-cookie-jar-holders jar))))

;; tally : (Listof Any) -> (Listof (Pairof Any Natural))
;; Each outcome of ANSWERS, with how many times it came, in the order
;; first seen.
(define (tally answers)
  (fold-left (lambda (found a)
               (let ((hit (assoc a found)))
                 (if hit
                     (map (lambda (entry) (if (equal? entry hit) (cons (car hit) (+ (cdr hit) 1)) entry)) found)
                     (append found (list (cons a 1))))))
             '() answers))

;; offsets : Integer Integer Natural -> (Listof Integer)
;; From FROM by STEP, COUNT of them: the submit's offsets, spread over
;; every phase of the engine's take.
(define (offsets from step count)
  (let loop ((i 0) (found '()))
    (if (= i count) (reverse found) (loop (+ i 1) (cons (+ from (* i step)) found)))))


;; set-read : Origin String String String (Listof String) -> (List (Listof Any) Any)
;; On a fresh jar, against the origin O: one request to the cookie route at HOST, PATH below
;; /cookies, under KEY, whose answer sets SETS, each already
;; percent-encoded; then the read-out, normal'ed, each line with the
;; rule's fault; then a request to /cookies/x/y at HOST, and the Cookie
;; headers it sent.
(define (set-read o host path key sets)
  (on-jar
   (lambda (e jar)
     (fetch e jar (string-append (route o host path key "") (apply string-append (map (lambda (s) (string-append "&set=" s)) sets))))
     (let ((out (faulted (curl-cookie-jar-cookies jar))))
       (fetch e jar (route o host "/x/y" key ""))
       (list out
             (let ((lines (log-lines o key)))
               (if (and (list? lines) (= (length lines) 2))
                   (with-port-named (cadr lines) (port-of o))
                   lines)))))))

;; refused-readout-rows: the read-out lines a load refuses, by version:
;; a server's Path=, Path=TRUE, Path=FALSE and Path=rel, and a tab in a
;; name or a value. 7.85.0 and 8.5.0 list the paths as given; 7.85.0
;; lists a tab as an eighth field (the slice's measurement, table 5x).
;; And a server's prefixed cookies in a case not the prefix's own, none
;; Secure, a __host- one with a path and a __HOST- one with a domain:
;; listed on 7.85.0, 8.20.0 and 8.23.0, dropped at the Set-Cookie on
;; 8.5.0; and a tab in a server's Path, eight fields on 7.85.0, dropped
;; elsewhere (the slice's review; ADR-0035, decision 10).
(define refused-readout-rows
  '(("8.20.0" . (("path-empty" (("a.localhost\tFALSE\t/\tFALSE\t0\tp\t1" #f)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"p=1\"") ("path-true" (("a.localhost\tFALSE\t/\tFALSE\t0\tp\t1" #f)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"p=1\"") ("path-false" (("a.localhost\tFALSE\t/\tFALSE\t0\tp\t1" #f)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"p=1\"") ("path-rel" (("a.localhost\tFALSE\t/\tFALSE\t0\tp\t1" #f)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"p=1\"") ("name-tab" () "request 2 face=http host=\"a.localhost:<port>\" cookies=0") ("value-tab" () "request 2 face=http host=\"a.localhost:<port>\" cookies=0") ("prefix-secure-lower" (("a.localhost\tFALSE\t/\tFALSE\t0\t__secure-a\t1" prefix)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"__secure-a=1\"") ("prefix-SECURE-upper" (("a.localhost\tFALSE\t/\tFALSE\t0\t__SECURE-b\t1" prefix)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"__SECURE-b=1\"") ("prefix-host-path" (("a.localhost\tFALSE\t/cookies\tFALSE\t0\t__host-c\t1" prefix)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"__host-c=1\"") ("prefix-HOST-domain" ((".a.localhost\tTRUE\t/\tFALSE\t0\t__HOST-d\t1" prefix)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"__HOST-d=1\"") ("path-tab" () "request 2 face=http host=\"a.localhost:<port>\" cookies=0")))
    ("8.23.0" . (("path-empty" (("a.localhost\tFALSE\t/\tFALSE\t0\tp\t1" #f)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"p=1\"") ("path-true" (("a.localhost\tFALSE\t/\tFALSE\t0\tp\t1" #f)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"p=1\"") ("path-false" (("a.localhost\tFALSE\t/\tFALSE\t0\tp\t1" #f)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"p=1\"") ("path-rel" (("a.localhost\tFALSE\t/\tFALSE\t0\tp\t1" #f)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"p=1\"") ("name-tab" () "request 2 face=http host=\"a.localhost:<port>\" cookies=0") ("value-tab" () "request 2 face=http host=\"a.localhost:<port>\" cookies=0") ("prefix-secure-lower" (("a.localhost\tFALSE\t/\tFALSE\t0\t__secure-a\t1" prefix)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"__secure-a=1\"") ("prefix-SECURE-upper" (("a.localhost\tFALSE\t/\tFALSE\t0\t__SECURE-b\t1" prefix)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"__SECURE-b=1\"") ("prefix-host-path" (("a.localhost\tFALSE\t/cookies\tFALSE\t0\t__host-c\t1" prefix)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"__host-c=1\"") ("prefix-HOST-domain" ((".a.localhost\tTRUE\t/\tFALSE\t0\t__HOST-d\t1" prefix)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"__HOST-d=1\"") ("path-tab" () "request 2 face=http host=\"a.localhost:<port>\" cookies=0")))
    ("7.85.0" . (("path-empty" (("a.localhost\tFALSE\t\tFALSE\t0\tp\t1" path)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"p=1\"") ("path-true" (("a.localhost\tFALSE\tTRUE\tFALSE\t0\tp\t1" path)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"p=1\"") ("path-false" (("a.localhost\tFALSE\tFALSE\tFALSE\t0\tp\t1" path)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"p=1\"") ("path-rel" (("a.localhost\tFALSE\trel\tFALSE\t0\tp\t1" path)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"p=1\"") ("name-tab" (("a.localhost\tFALSE\t/\tFALSE\t0\tn\tm\tv" fields)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"n\\x09m=v\"") ("value-tab" (("a.localhost\tFALSE\t/\tFALSE\t0\tnm\tv\tw" fields)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"nm=v\\x09w\"") ("prefix-secure-lower" (("a.localhost\tFALSE\t/\tFALSE\t0\t__secure-a\t1" prefix)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"__secure-a=1\"") ("prefix-SECURE-upper" (("a.localhost\tFALSE\t/\tFALSE\t0\t__SECURE-b\t1" prefix)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"__SECURE-b=1\"") ("prefix-host-path" (("a.localhost\tFALSE\t/cookies\tFALSE\t0\t__host-c\t1" prefix)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"__host-c=1\"") ("prefix-HOST-domain" ((".a.localhost\tTRUE\t/\tFALSE\t0\t__HOST-d\t1" prefix)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"__HOST-d=1\"") ("path-tab" (("a.localhost\tFALSE\t/a\tb\tFALSE\t0\tk\tv" fields)) "request 2 face=http host=\"a.localhost:<port>\" cookies=0")))
    ("8.5.0" . (("path-empty" (("a.localhost\tFALSE\t\tFALSE\t0\tp\t1" path)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"p=1\"") ("path-true" (("a.localhost\tFALSE\tTRUE\tFALSE\t0\tp\t1" path)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"p=1\"") ("path-false" (("a.localhost\tFALSE\tFALSE\tFALSE\t0\tp\t1" path)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"p=1\"") ("path-rel" (("a.localhost\tFALSE\trel\tFALSE\t0\tp\t1" path)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"p=1\"") ("name-tab" () "request 2 face=http host=\"a.localhost:<port>\" cookies=0") ("value-tab" () "request 2 face=http host=\"a.localhost:<port>\" cookies=0") ("prefix-secure-lower" () "request 2 face=http host=\"a.localhost:<port>\" cookies=0") ("prefix-SECURE-upper" () "request 2 face=http host=\"a.localhost:<port>\" cookies=0") ("prefix-host-path" () "request 2 face=http host=\"a.localhost:<port>\" cookies=0") ("prefix-HOST-domain" () "request 2 face=http host=\"a.localhost:<port>\" cookies=0") ("path-tab" () "request 2 face=http host=\"a.localhost:<port>\" cookies=0")))))


;; expired-rows: a loaded line whose expiry, 1, has passed: listed until
;; the next cookie is added on 7.85.0 and 8.5.0, dropped at once on
;; 8.20.0 and 8.23.0 (ADR-0035, decision 7).
(define expired-rows
  '(("8.20.0" . (() ("a.localhost\tFALSE\t/\tFALSE\t0\tnext\t1")))
    ("8.23.0" . (() ("a.localhost\tFALSE\t/\tFALSE\t0\tnext\t1")))
    ("7.85.0" . (("a.localhost\tFALSE\t/\tFALSE\t1\texp\tv") ("a.localhost\tFALSE\t/\tFALSE\t0\tnext\t1")))
    ("8.5.0" . (("a.localhost\tFALSE\t/\tFALSE\t1\texp\tv") ("a.localhost\tFALSE\t/\tFALSE\t0\tnext\t1")))))


;; open-head-rows: a server's 4,003-byte cookie, then a request whose
;; request line is past 4,200 bytes, and another with a short URL and a
;; 4,300-byte User-Agent. 7.85.0's cap counts everything the head holds
;; before the Cookie line: the request line, Host, the credentials'
;; Authorization and User-Agent among it. Past the cap it writes Cookie:
;; and no line's end, the head never ends, and the transfer waits for its
;; bound, 28, the origin logging the head left open; the rest send it
;; whole, 200 (ADR-0035, amended twice, from verify/cap-url.c and the
;; slice's review).
(define open-head-rows
  '(("8.20.0" . (200 200 (a-request a-request) 200 200 (a-request a-request)))
    ("8.23.0" . (200 200 (a-request a-request) 200 200 (a-request a-request)))
    ("7.85.0" . (200 (transfer-failed perform-failed 28) (a-request the-head-left-open) 200 (transfer-failed perform-failed 28) (a-request the-head-left-open)))
    ("8.5.0" . (200 200 (a-request a-request) 200 200 (a-request a-request)))))


;; domain-localhost-rows: Domain=localhost set at a.localhost, kept on a
;; libcurl without PSL and dropped on one with it; and set at localhost
;; itself, host-only on 8.5.0 (the M7 plan, section 3.7).
(define domain-localhost-rows
  '(("8.20.0/psl" . ((() "request 2 face=http host=\"a.localhost:<port>\" cookies=0") (((".localhost\tTRUE\t/\tFALSE\t0\td\t1" #f)) "request 2 face=http host=\"localhost:<port>\" cookies=1 cookie=\"d=1\"") (() "request 2 face=http host=\"localhost:<port>\" cookies=0")))
    ("8.23.0/no-psl" . ((((".localhost\tTRUE\t/\tFALSE\t0\td\t1" #f)) "request 2 face=http host=\"a.localhost:<port>\" cookies=0") (((".localhost\tTRUE\t/\tFALSE\t0\td\t1" #f)) "request 2 face=http host=\"localhost:<port>\" cookies=1 cookie=\"d=1\"") (() "request 2 face=http host=\"localhost:<port>\" cookies=0")))
    ("7.85.0/no-psl" . ((((".localhost\tTRUE\t/\tFALSE\t0\td\t1" #f)) "request 2 face=http host=\"a.localhost:<port>\" cookies=0") (((".localhost\tTRUE\t/\tFALSE\t0\td\t1" #f)) "request 2 face=http host=\"localhost:<port>\" cookies=1 cookie=\"d=1\"") (() "request 2 face=http host=\"localhost:<port>\" cookies=0")))
    ("8.5.0/psl" . ((() "request 2 face=http host=\"a.localhost:<port>\" cookies=0") ((("localhost\tFALSE\t/\tFALSE\t0\td\t1" #f)) "request 2 face=http host=\"localhost:<port>\" cookies=1 cookie=\"d=1\"") ((("localhost\tFALSE\t/\tTRUE\t0\t__Host-dom\t1" #f)) "request 2 face=http host=\"localhost:<port>\" cookies=1 cookie=\"__Host-dom=1\"")))))


;; matrix-rows: the default path, set at /cookies/a/b/page, /cookies/a/b
;; from 8.20.0 and /cookies/a/b/ before; Path=rel and Path= there, made /
;; and the default from 8.20.0, kept as given before, which the load rule
;; refuses, and sent to /cookies/x/y; the 400-day cap, Max-Age of 1,000
;; days, held from 8.20.0; Max-Age=-1, dropped from 8.20.0, kept as a
;; session cookie on 7.85.0, listed with expiry 1 and not sent on 8.5.0;
;; and a cookie deleted by Max-Age=0, still listed with expiry 1 on
;; 7.85.0 and 8.5.0 until the next request (the M7 plan, section 3.7).
(define matrix-rows
  '(("8.20.0" . (((("a.localhost\tFALSE\t/cookies/a/b\tFALSE\t0\tdp\t1" #f)) "request 2 face=http host=\"a.localhost:<port>\" cookies=0") ((("a.localhost\tFALSE\t/\tFALSE\t0\tpr\t1" #f) ("a.localhost\tFALSE\t/cookies/a/b\tFALSE\t0\tpe\t1" #f)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"pr=1\"") ((("a.localhost\tFALSE\t/\tFALSE\twithin-400-days\tca\t1" #f)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"ca=1\"") (() "request 2 face=http host=\"a.localhost:<port>\" cookies=0") (("a.localhost\tFALSE\t/\tFALSE\t0\tkeep\t1") "request 3 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"keep=1\"" ("a.localhost\tFALSE\t/\tFALSE\t0\tkeep\t1"))))
    ("8.23.0" . (((("a.localhost\tFALSE\t/cookies/a/b\tFALSE\t0\tdp\t1" #f)) "request 2 face=http host=\"a.localhost:<port>\" cookies=0") ((("a.localhost\tFALSE\t/\tFALSE\t0\tpr\t1" #f) ("a.localhost\tFALSE\t/cookies/a/b\tFALSE\t0\tpe\t1" #f)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"pr=1\"") ((("a.localhost\tFALSE\t/\tFALSE\twithin-400-days\tca\t1" #f)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"ca=1\"") (() "request 2 face=http host=\"a.localhost:<port>\" cookies=0") (("a.localhost\tFALSE\t/\tFALSE\t0\tkeep\t1") "request 3 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"keep=1\"" ("a.localhost\tFALSE\t/\tFALSE\t0\tkeep\t1"))))
    ("7.85.0" . (((("a.localhost\tFALSE\t/cookies/a/b/\tFALSE\t0\tdp\t1" #f)) "request 2 face=http host=\"a.localhost:<port>\" cookies=0") ((("a.localhost\tFALSE\t\tFALSE\t0\tpe\t1" path) ("a.localhost\tFALSE\trel\tFALSE\t0\tpr\t1" path)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"pr=1; pe=1\"") ((("a.localhost\tFALSE\t/\tFALSE\tbeyond-400-days\tca\t1" #f)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"ca=1\"") ((("a.localhost\tFALSE\t/\tFALSE\t0\tma\t1" #f)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"ma=1\"") (("a.localhost\tFALSE\t/\tFALSE\t0\tkeep\t1" "a.localhost\tFALSE\t/\tFALSE\t1\tdel\t") "request 3 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"keep=1\"" ("a.localhost\tFALSE\t/\tFALSE\t0\tkeep\t1"))))
    ("8.5.0" . (((("a.localhost\tFALSE\t/cookies/a/b/\tFALSE\t0\tdp\t1" #f)) "request 2 face=http host=\"a.localhost:<port>\" cookies=0") ((("a.localhost\tFALSE\t\tFALSE\t0\tpe\t1" path) ("a.localhost\tFALSE\trel\tFALSE\t0\tpr\t1" path)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"pr=1; pe=1\"") ((("a.localhost\tFALSE\t/\tFALSE\tbeyond-400-days\tca\t1" #f)) "request 2 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"ca=1\"") ((("a.localhost\tFALSE\t/\tFALSE\t1\tma\t1" #f)) "request 2 face=http host=\"a.localhost:<port>\" cookies=0") (("a.localhost\tFALSE\t/\tFALSE\t0\tkeep\t1" "a.localhost\tFALSE\t/\tFALSE\t1\tdel\t") "request 3 face=http host=\"a.localhost:<port>\" cookies=1 cookie=\"keep=1\"" ("a.localhost\tFALSE\t/\tFALSE\t0\tkeep\t1"))))))


(define (scenarios o)
  (let ((port (port-of o)))

    ;; --- read-out and load, whole lines ----------------------------------------------

    (test-equal "a fresh jar reads out empty; loaded lines, an HttpOnly one, a session one, a far expiry, a tab-free value with U+00E9, read out whole; and its read-out loads into a fresh jar as the same lines"
      (let ((lines (sorted (list (tabbed "#HttpOnly_.b.a.localhost" "TRUE" "/p" "FALSE" "0" "h" "1")
                                 (tabbed "a.localhost" "FALSE" "/" "TRUE" "99999999999" "far" "x y")
                                 (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "e" (string #\v (integer->char #xE9)))))))
        (list '() lines lines))
      (on-jar
       (lambda (e jar)
         (let ((empty (curl-cookie-jar-cookies jar)))
           (curl-cookie-jar-load! jar (list (tabbed "#HttpOnly_.b.a.localhost" "TRUE" "/p" "FALSE" "0" "h" "1")
                                            (tabbed "a.localhost" "FALSE" "/" "TRUE" "99999999999" "far" "x y")
                                            (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "e" (string #\v (integer->char #xE9)))))
           (let* ((out (sorted (curl-cookie-jar-cookies jar)))
                  (again (make-curl-cookie-jar e)))
             (curl-cookie-jar-load! again out)
             (list empty out (sorted (curl-cookie-jar-cookies again))))))))

    (test-equal "a load checks every line before it loads any: a list whose last line is refused loads none, its refusal naming index 2"
      '((request-refused curl-cookie-jar-load! lines 2 cookie-line) ())
      (on-jar
       (lambda (e jar)
         (list (refused (lambda ()
                          (curl-cookie-jar-load! jar (list (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "a" "1")
                                                           (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "b" "2")
                                                           (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "" "3")))))
               (curl-cookie-jar-cookies jar)))))

    (test-equal "bytes above 0x7F, Latin-1 both ways: a server's E9 and FF stored and read out as U+00E9 and U+00FF, and sent byte for byte; a loaded U+00FF sent as FF"
      (list (sorted (list (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "srv" (string #\x (integer->char #xE9) (integer->char #xFF)))
                          (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "l" (string (integer->char #xFF)))))
            (list (logged 1 "a.localhost" port '())
                  (logged 2 "a.localhost" port (list (string-append "srv=x" (string (integer->char #xE9) (integer->char #xFF))
                                                                    "; l=" (string (integer->char #xFF)))))))
      (on-jar
       (lambda (e jar)
         (fetch e jar (route o "a.localhost" "" "l1" "&set=srv%3Dx%E9%FF"))
         (curl-cookie-jar-load! jar (list (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "l" (string (integer->char #xFF)))))
         (fetch e jar (route o "a.localhost" "" "l1" ""))
         (list (sorted (curl-cookie-jar-cookies jar)) (log-lines o "l1")))))

    ;; --- across requests and hosts, three labels deep ------------------------------

    (test-equal "across requests and hosts, three labels deep: a.localhost's host-only and Domain=a.localhost cookies go back to a.localhost, the domain one alone to b.a.localhost, and neither to b.localhost, each by the origin's log, whole"
      (list (logged 1 "a.localhost" port '())
            (logged 2 "a.localhost" port '("host1=v1; dom=v1"))
            (logged 3 "b.a.localhost" port '("dom=v1"))
            (logged 4 "b.localhost" port '()))
      (on-jar
       (lambda (e jar)
         (fetch e jar (route o "a.localhost" "" "x1" "&set=host1%3Dv1&set=dom%3Dv1%3B%20Domain%3Da.localhost"))
         (fetch e jar (route o "a.localhost" "" "x1" ""))
         (fetch e jar (route o "b.a.localhost" "" "x1" ""))
         (fetch e jar (route o "b.localhost" "" "x1" ""))
         (log-lines o "x1"))))

    (test-equal "a request without the jar sends none of its cookies, and stores none it is sent"
      (list (list (logged 1 "a.localhost" port '()) (logged 2 "a.localhost" port '()) (logged 3 "a.localhost" port '("j=1")))
            (list (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "j" "1")))
      (on-jar
       (lambda (e jar)
         (curl-cookie-jar-load! jar (list (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "j" "1")))
         (fetch e #f (route o "a.localhost" "" "x2" "&set=n%3D1"))
         (fetch e #f (route o "a.localhost" "" "x2" ""))
         (fetch e jar (route o "a.localhost" "" "x2" ""))
         (list (log-lines o "x2") (curl-cookie-jar-cookies jar)))))

    ;; --- the messages, in the order queued ---------------------------------------------

    (test-equal "a load, a submit and a read-out queued in one hold, taken in one turn: the transfer sends the loaded cookie, and the read-out, carried out before the transfer's exchange, holds the loaded line alone; after it, the server's too"
      (list (list (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "qo" "loaded"))
            '(200)
            (list (logged 1 "a.localhost" port '("qo=loaded")))
            (sorted (list (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "qo" "loaded")
                          (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "srv" "1"))))
      (on-jar
       (lambda (e jar)
         (let* ((held (call-with-engine-held e
                        (lambda ()
                          (let* ((load (curl-cookie-jar-post! jar 'load (list (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "qo" "loaded"))))
                                 (token (curl-submit e (make-curl-request (route o "a.localhost" "" "q1" "&set=srv%3D1")
                                                                          'cookie-jar jar 'proxy #f 'timeout-ms 20000)))
                                 (read (curl-cookie-jar-post! jar 'read '())))
                            (list load token read)))))
                (read-answer (curl-cookie-jar-await jar (caddr held)))
                (status (curl-response-status (curl-token-await (cadr held)))))
           (curl-cookie-jar-await jar (car held))
           (list read-answer (list status) (log-lines o "q1") (sorted (curl-cookie-jar-cookies jar)))))))

    (test-equal "a load takes its copies as it is called: the list and its strings, changed from another thread while the load waits queued, load as given"
      (list 'returned (sorted (list (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "m1" "one")
                                    (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "m2" "two"))))
      (let ((e (make-curl-engine-delaying-take 300)))
        (dynamic-wind
          (lambda () #f)
          (lambda ()
            (let* ((jar (make-curl-cookie-jar e))
                   (one (string-copy (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "m1" "one")))
                   (two (string-copy (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "m2" "two")))
                   (lines (list one two))
                   (loader (spawn (lambda () (curl-cookie-jar-load! jar lines) 'loaded))))
              (wait-for (lambda () (= (curl-engine-queued-count e) 1)) 5000)
              (string-set! one 0 #\#)
              (string-set! two 14 #\X)
              (set-car! (cdr lines) (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "m3" "three"))
              (let ((answer (joined loader 20000)))
                (if (equal? answer '(returned loaded))
                    (list 'returned (sorted (curl-cookie-jar-cookies jar)))
                    answer))))
          (lambda () (curl-engine-stop e)))))

    ;; --- the lifetime (the M7 plan, section 3.5) ------------------------------------------

    (test-equal "a close while two transfers hold the jar answers at once, closing, the share kept and the jar's own handle with it, three easy handles counted; a submit after is refused cookie-jar-closed, and so are a read-out and a load; the two end 200; the last to end frees the jar's handle and the share, the jar closed, holding none"
      (list 2 'closing 1 3 '(request-refused curl-submit cookie-jar cookie-jar cookie-jar-closed)
            '(request-refused curl-cookie-jar-cookies cookie-jar cookie-jar cookie-jar-closed)
            '(request-refused curl-cookie-jar-load! cookie-jar cookie-jar cookie-jar-closed)
            '((response 200) (response 200)) 'closed 0 0 0)
      (let* ((e (make-curl-engine)) (base (share-count)) (easies (easy-count)))
        (dynamic-wind
          (lambda () #f)
          (lambda ()
            (let* ((jar (make-curl-cookie-jar e))
                   (slow (string-append "http://127.0.0.1:" port "/pattern/10?delay=1500"))
                   (a (curl-submit e (make-curl-request slow 'cookie-jar jar 'proxy #f 'timeout-ms 20000)))
                   (b (curl-submit e (make-curl-request slow 'cookie-jar jar 'proxy #f 'timeout-ms 20000)))
                   (holding (wait-for (lambda () (and (= (curl-cookie-jar-holders jar) 2) 2)) 10000)))
              (curl-cookie-jar-close! jar)
              (let* ((state (curl-cookie-jar-state jar))
                     (shares (- (share-count) base))
                     (handles (- (easy-count) easies))
                     (refusal (refused (lambda () (curl-submit e (make-curl-request slow 'cookie-jar jar 'proxy #f)))))
                     (read (refused (lambda () (curl-cookie-jar-cookies jar))))
                     (load (refused (lambda () (curl-cookie-jar-load! jar '())))))
                (curl-token-wait a 20000)
                (curl-token-wait b 20000)
                (wait-for (lambda () (eq? (curl-cookie-jar-state jar) 'closed)) 5000)
                (list holding state shares handles refusal read load (list (outcome-of a) (outcome-of b))
                      (curl-cookie-jar-state jar) (curl-cookie-jar-holders jar) (- (share-count) base)
                      (- (easy-count) easies)))))
          (lambda () (curl-engine-stop e)))))

    (test-equal "a transfer whose start raises holds the jar not at all: IPRESOLVE 99, refused by libcurl's setopt, fails the token setopt-failed, the jar holds none, and a close frees it at once"
      '((transfer-failed setopt-failed 43) 0 closed)
      (on-jar
       (lambda (e jar)
         (let ((t (curl-submit e (curl-request-with-options
                                  (make-curl-request (route o "a.localhost" "" "s1" "") 'cookie-jar jar 'proxy #f)
                                  '(("IPRESOLVE" . 99))))))
           (curl-token-wait t 20000)
           (let ((holders (curl-cookie-jar-holders jar)))
             (curl-cookie-jar-close! jar)
             (list (outcome-of t) holders (curl-cookie-jar-state jar)))))))

    (test-equal "a close crossing a submit, controlled: a submit queued before the close runs with the jar; one after the close is refused at submit; one queued after the close in one hold, before the engine takes either, is refused as it is set up, its token's outcome cookie-jar-closed; one queued before the close in one hold runs with the jar, which the close leaves closing; each jar closed after"
      '(((response 200) closed)
        ((request-refused curl-submit cookie-jar cookie-jar cookie-jar-closed) closed)
        ((request-refused curl-submit cookie-jar cookie-jar cookie-jar-closed) setup closed)
        ((response 200) in-one-hold closed))
      (let ((url (route o "a.localhost" "" "c1" "")))
        (on-jar
         (lambda (e first)
           (let* ((ran (let ((t (curl-submit e (make-curl-request url 'cookie-jar first 'proxy #f 'timeout-ms 20000))))
                         (curl-cookie-jar-close! first)
                         (curl-token-wait t 20000)
                         (wait-for (lambda () (eq? (curl-cookie-jar-state first) 'closed)) 5000)
                         (list (outcome-of t) (curl-cookie-jar-state first))))
                  (second (make-curl-cookie-jar e))
                  (at-submit (begin
                               (curl-cookie-jar-close! second)
                               (list (refused (lambda () (curl-submit e (make-curl-request url 'cookie-jar second 'proxy #f))))
                                     (curl-cookie-jar-state second))))
                  (third (make-curl-cookie-jar e))
                  (at-setup (let ((t (call-with-engine-held e
                                       (lambda ()
                                         (curl-cookie-jar-post! third 'close '())
                                         (curl-submit e (make-curl-request url 'cookie-jar third 'proxy #f))))))
                              (curl-token-wait t 20000)
                              (list (outcome-of t) 'setup (curl-cookie-jar-state third))))
                  (fourth (make-curl-cookie-jar e))
                  (held (let ((t (call-with-engine-held e
                                   (lambda ()
                                     (let ((t (curl-submit e (make-curl-request url 'cookie-jar fourth 'proxy #f
                                                                                'timeout-ms 20000))))
                                       (curl-cookie-jar-post! fourth 'close '())
                                       t)))))
                          (curl-token-wait t 20000)
                          (wait-for (lambda () (eq? (curl-cookie-jar-state fourth) 'closed)) 5000)
                          (list (outcome-of t) 'in-one-hold (curl-cookie-jar-state fourth)))))
             (list ran at-submit at-setup held))))))

    (test-equal "a close crossing a submit, on an engine that waits 40 ms before each take: offsets from 30 ms before the close to 110 after reach each of the three outcomes, and no other; every jar closed after, holding none"
      '((ran submit setup) () (closed 0))
      (let ((e (make-curl-engine-delaying-take 40)))
        (dynamic-wind
          (lambda () #f)
          (lambda ()
            (let* ((url (route o "a.localhost" "" "c2" ""))
                   (answers (map (lambda (offset) (crossing e url offset)) (offsets -30 4 36)))
                   (kinds (map car answers)))
              (display (string-append "test-cookies: crossings on the delaying engine " (written (tally kinds)) "\n"))
              (list (filter (lambda (k) (member k kinds)) '(ran submit setup))
                    (filter (lambda (k) (not (memq k '(ran submit setup)))) kinds)
                    (let ((states (fold-left (lambda (found a) (if (member (cdr a) found) found (cons (cdr a) found)))
                                             '() answers)))
                      (if (= (length states) 1) (car states) states)))))
          (lambda () (curl-engine-stop e)))))

    (test-equal "a close crossing a submit on a plain engine, the submit from 8 ms before the close to 8 after, 33 times: each ends as one of the three outcomes, and no other; every jar closed after, holding none"
      '(() (closed 0))
      (on-jar
       (lambda (e unused)
         (let* ((url (route o "a.localhost" "" "c3" ""))
                (answers (map (lambda (offset) (crossing e url offset)) (offsets -8 1/2 33)))
                (kinds (map car answers)))
           (display (string-append "test-cookies: crossings on a plain engine " (written (tally kinds)) "\n"))
           (list (filter (lambda (k) (not (memq k '(ran submit setup)))) kinds)
                 (let ((states (fold-left (lambda (found a) (if (member (cdr a) found) found (cons (cdr a) found)))
                                          '() answers)))
                   (if (= (length states) 1) (car states) states)))))))

    (test-equal "a stop frees every jar, a live one and one closing while a transfer holds it: the transfer ends stopped, both jars closed, nothing left counted; and a jar of a stopped engine is refused as a submit is, stopped"
      (list '(transfer-failed stopped #f) 'closed 'closed #t
            '((engine-error stopped) (engine-error stopped) (engine-error stopped)))
      (let* ((before (native-counts))
             (e (make-curl-engine))
             (live (make-curl-cookie-jar e))
             (closing (make-curl-cookie-jar e))
             (t (curl-submit e (make-curl-request (string-append "http://127.0.0.1:" port "/pattern/10?delay=5000")
                                                  'cookie-jar closing 'proxy #f 'timeout-ms 20000))))
        (wait-for (lambda () (= (curl-cookie-jar-holders closing) 1)) 10000)
        (curl-cookie-jar-close! closing)
        (curl-engine-stop e)
        (list (outcome-of t) (curl-cookie-jar-state live) (curl-cookie-jar-state closing)
              (equal? (native-counts) before)
              (list (refused (lambda () (curl-cookie-jar-cookies live)))
                    (refused (lambda () (curl-cookie-jar-close! closing)))
                    (refused (lambda () (make-curl-cookie-jar e)))))))

    (test-equal "a failed engine, its fault planted at perform with a transfer holding the jar: the token fails with the engine, the transfer's hold let go, the jar freed and closed, and the jar's messages raise what the engine failed with"
      '((engine-error failed) closed 0 (engine-error failed) (engine-error failed))
      (let* ((e (make-faulty-curl-engine 'perform))
             (jar (make-curl-cookie-jar e))
             (t (curl-submit e (make-curl-request (route o "a.localhost" "" "f1" "") 'cookie-jar jar 'proxy #f
                                                  'timeout-ms 20000))))
        (curl-token-wait t 20000)
        (curl-engine-stop e)
        (list (outcome-of t) (curl-cookie-jar-state jar) (curl-cookie-jar-holders jar)
              (refused (lambda () (curl-cookie-jar-cookies jar)))
              (refused (lambda () (curl-cookie-jar-load! jar '()))))))

    (test-equal "a load and a read-out queued in one hold behind a submit whose set-up fails the engine, so the failing turn takes all three in its batch, are each answered with what the engine failed with, within 10 s; the token fails so too"
      '((returned (raised (engine-error failed))) (returned (raised (engine-error failed))) (engine-error failed))
      (let* ((e (make-faulty-curl-engine 'setup))
             (jar (make-curl-cookie-jar e))
             (held (call-with-engine-held e
                     (lambda ()
                       (let* ((t (curl-submit e (make-curl-request (route o "a.localhost" "" "fb" "") 'cookie-jar jar
                                                                   'proxy #f 'timeout-ms 20000)))
                              (load (curl-cookie-jar-post! jar 'load (list (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "n" "v"))))
                              (read (curl-cookie-jar-post! jar 'read '())))
                         (list t load read)))))
             (await (lambda (reply)
                      (joined (spawn (lambda ()
                                       (let ((x (curl-cookie-jar-await jar reply)))
                                         (if (and (pair? x) (eq? (car x) 'raised)) (list 'raised (refusal-of (cadr x))) x))))
                              10000)))
             (load-answer (await (cadr held)))
             (read-answer (await (caddr held))))
        (curl-token-wait (car held) 10000)
        (guard (x (#t #f)) (curl-engine-stop e))
        (list load-answer read-answer (outcome-of (car held)))))

    (test-equal "a fault after take-out! has let a transfer's hold go, at its free step, fails the engine, which takes the transfer out again: the hold is let go once, the jar holding none, never -1, and freed, closed"
      '((engine-error failed) 0 closed)
      (let* ((e (make-faulty-curl-engine 'free))
             (jar (make-curl-cookie-jar e))
             (t (curl-submit e (make-curl-request (route o "a.localhost" "" "fr" "") 'cookie-jar jar 'proxy #f
                                                  'timeout-ms 10000))))
        (curl-token-wait t 15000)
        ;; The token is done before the failure frees the jar: the stop
        ;; waits for the failure to end.
        (guard (x (#t #f)) (curl-engine-stop e))
        (list (outcome-of t) (curl-cookie-jar-holders jar) (curl-cookie-jar-state jar))))

    (test-equal "every jar message is answered: one queued as the engine stops raises stopped; a make taken by a failing take raises what the engine failed with"
      '((raised (engine-error stopped)) (raised (engine-error failed)))
      (list (let ((e (make-curl-engine-delaying-take 300)))
              (let* ((jar (make-curl-cookie-jar e))
                     (loader (spawn (lambda () (curl-cookie-jar-load! jar (list (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "n" "v")))))))
                (wait-for (lambda () (= (curl-engine-queued-count e) 1)) 5000)
                (curl-engine-request-stop! e)
                (let ((answer (joined loader 20000)))
                  (curl-engine-stop e)
                  answer)))
            (let ((e (make-faulty-curl-engine 'take)))
              (let ((answer (joined (spawn (lambda () (make-curl-cookie-jar e))) 20000)))
                (curl-engine-stop e)
                answer))))

    (test-equal "libcurl's every answer is read, each taken in place of libcurl's by the engine's seam: a curl_share_setopt answer but 0 fails the make, freeing what it made; a COOKIELIST answer but 0 fails the load at that line, naming its index and the code, the line itself loaded; a read-out's answer but 0 fails it"
      (list '(error make-curl-cookie-jar (1 2 1)) #t
            (list '(error curl-cookie-jar-load! (0 1)) (list (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "a" "1")))
            '(error curl-cookie-jar-cookies (2)))
      (list (let ((e (make-curl-engine-answering-jar 'make 1)))
              (dynamic-wind (lambda () #f)
                            (lambda ()
                              (let* ((before (native-counts))
                                     (answer (refused (lambda () (make-curl-cookie-jar e)))))
                                (set! seam-counts-same (equal? (native-counts) before))
                                answer))
                            (lambda () (curl-engine-stop e))))
            seam-counts-same
            (let ((e (make-curl-engine-answering-jar 'load 1)))
              (dynamic-wind (lambda () #f)
                            (lambda ()
                              (let ((jar (make-curl-cookie-jar e)))
                                (list (refused (lambda ()
                                                 (curl-cookie-jar-load! jar (list (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "a" "1")
                                                                                  (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "b" "2")))))
                                      (curl-cookie-jar-cookies jar))))
                            (lambda () (curl-engine-stop e))))
            (let ((e (make-curl-engine-answering-jar 'read 2)))
              (dynamic-wind (lambda () #f)
                            (lambda () (refused (lambda () (curl-cookie-jar-cookies (make-curl-cookie-jar e)))))
                            (lambda () (curl-engine-stop e))))))

    ;; --- the high level (the M7 plan, section 3.1) ----------------------------------------


    (test-equal "a session with cookies: its calls carry the jar across requests and hosts, three labels deep; http-session-cookies reads it out, http-session-load-cookies! loads into it, and its refusal names the line's index; the log whole"
      (list (list (logged 1 "a.localhost" port '()) (logged 2 "b.a.localhost" port '("dom=1"))
                  (logged 3 "b.a.localhost" port '("dom=1; ld=x")))
            (sorted (list (tabbed ".a.localhost" "TRUE" "/" "FALSE" "0" "dom" "1")
                          (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "h" "1")))
            '(request-refused curl-cookie-jar-load! lines 0 cookie-line))
      (call-with-http-session 'cookies #t 'proxy #f 'timeout-ms 20000
        (lambda (s)
          (http-get s (route o "a.localhost" "" "h1" "&set=h%3D1&set=dom%3D1%3B%20Domain%3Da.localhost"))
          (http-get s (route o "b.a.localhost" "" "h1" ""))
          (let ((out (sorted (http-session-cookies s))))
            (http-session-load-cookies! s (list (tabbed ".a.localhost" "TRUE" "/" "FALSE" "0" "ld" "x")))
            (http-get s (route o "b.a.localhost" "" "h1" ""))
            (list (log-lines o "h1") out
                  (refused (lambda () (http-session-load-cookies! s (list (tabbed "a" "x" "/" "FALSE" "0" "n" "v"))))))))))

    (test-equal "a redirect's hops carry the session's jar, another origin's too: a.localhost's 302 sets a domain cookie, and the hop to b.a.localhost sends it, by the log"
      (list 200 (list (logged 1 "a.localhost" port '()) (logged 2 "b.a.localhost" port '("dom=1"))))
      (call-with-http-session 'cookies #t 'proxy #f 'timeout-ms 20000
        (lambda (s)
          (let ((r (http-get s (route o "a.localhost" "" "h2"
                                      (string-append "&set=dom%3D1%3B%20Domain%3Da.localhost&status=302&to="
                                                     "http%3A%2F%2Fb.a.localhost%3A" port "%2Fcookies%3Fkey%3Dh2")))))
            (list (http-response-status r) (log-lines o "h2"))))))

    (test-equal "a session without cookies sends none and keeps none; a call's Cookie header beside a session's jar is refused, cookie-beside-jar, with the call's &http-exchange; without a jar it is sent"
      (list (list (logged 1 "a.localhost" port '()) (logged 2 "a.localhost" port '()) (logged 3 "a.localhost" port '("mine=1")))
            '(request-refused make-curl-request header-name "Cookie" cookie-beside-jar) #t)
      (let ((plain (call-with-http-session 'proxy #f 'timeout-ms 20000
                     (lambda (s)
                       (http-get s (route o "a.localhost" "" "h3" "&set=n%3D1"))
                       (http-get s (route o "a.localhost" "" "h3" ""))
                       (http-get s (route o "a.localhost" "" "h3" "") 'headers '(("Cookie" . "mine=1")))
                       'done))))
        (call-with-http-session 'cookies #t 'proxy #f 'timeout-ms 20000
          (lambda (s)
            (let ((e (raised (lambda () (http-get s (route o "a.localhost" "" "h3" "") 'headers '(("Cookie" . "mine=1")))))))
              (list (log-lines o "h3") (refusal-of e) (http-exchange? e)))))))

    ;; --- what varies by version (the M7 plan, section 3.7) --------------------------------

    (let ((cases '(("path-empty" "p%3D1%3B%20Path%3D") ("path-true" "p%3D1%3B%20Path%3DTRUE")
                   ("path-false" "p%3D1%3B%20Path%3DFALSE") ("path-rel" "p%3D1%3B%20Path%3Drel")
                   ("name-tab" "n%09m%3Dv") ("value-tab" "nm%3Dv%09w")
                   ("prefix-secure-lower" "__secure-a%3D1") ("prefix-SECURE-upper" "__SECURE-b%3D1")
                   ("prefix-host-path" "__host-c%3D1%3B%20Path%3D%2Fcookies")
                   ("prefix-HOST-domain" "__HOST-d%3D1%3B%20Domain%3Da.localhost")
                   ("path-tab" "k%3Dv%3B%20Path%3D%2Fa%09b"))))
      (let ((answer (by-version refused-readout-rows "refused-readout" version
                                (lambda ()
                                  (map (lambda (c) (cons (car c) (set-read o "a.localhost" "" (string-append "rr-" (car c)) (cdr c))))
                                       cases)))))
        (test-equal (string-append "the read-out lines a load refuses, by libcurl " (written version) "'s row: a server's Path=, Path=TRUE, Path=FALSE and Path=rel, a tab in a name and in a value, __secure- and __SECURE- cookies, a __host- one with a path and a __HOST- one with a domain, none Secure, and a tab in its Path, each line with the rule's fault, and the next request's Cookie headers")
          (car answer) (cadr answer))))

    (let ((answer (by-version expired-rows "expired-load" version
                              (lambda ()
                                (on-jar
                                 (lambda (e jar)
                                   (curl-cookie-jar-load! jar (list (tabbed "a.localhost" "FALSE" "/" "FALSE" "1" "exp" "v")))
                                   (let ((first (sorted (curl-cookie-jar-cookies jar))))
                                     (curl-cookie-jar-load! jar (list (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "next" "1")))
                                     (list first (sorted (curl-cookie-jar-cookies jar))))))))))
      (test-equal (string-append "a loaded line whose expiry has passed, then the next line added, by libcurl " (written version) "'s row")
        (car answer) (cadr answer)))

    (let ((answer (by-version open-head-rows "open-head" version
                              (lambda ()
                                (on-jar
                                 (lambda (e jar)
                                   (let* ((pad (repeat 4200 #\p))
                                          (set (fetch e jar (route o "a.localhost" "" "oh" (string-append "&set=nm%3D" (repeat 4000 #\v)))))
                                          (target (string-append "/cookies?key=oh&pad=" pad))
                                          (long (fetch e jar (string-append "http://a.localhost:" port target) 3000))
                                          (lines (wait-for (lambda ()
                                                             (let ((l (log-lines o "oh")))
                                                               (and (list? l) (= (length l) 2) l)))
                                                           5000))
                                          (head (string-append "GET " target " HTTP/1.1\r\nHost: a.localhost:" port
                                                               "\r\nAccept: */*\r\nCookie: \r\n"))
                                          (agent (repeat 4300 #\u))
                                          (fresh (make-curl-cookie-jar e))
                                          (agent-set (fetch e fresh (route o "a.localhost" "" "oha" (string-append "&set=nm%3D" (repeat 4000 #\v)))))
                                          (agent-target "/cookies?key=oha")
                                          (agent-long (guard (x (#t (refusal-of x)))
                                                        (let ((t (curl-submit e (make-curl-request (string-append "http://a.localhost:" port agent-target)
                                                                                                   'cookie-jar fresh 'proxy #f 'timeout-ms 3000
                                                                                                   'user-agent agent))))
                                                          (curl-response-status (curl-token-await t)))))
                                          (agent-lines (wait-for (lambda ()
                                                                   (let ((l (log-lines o "oha")))
                                                                     (and (list? l) (= (length l) 2) l)))
                                                                 5000))
                                          (agent-head (string-append "GET " agent-target " HTTP/1.1\r\nHost: a.localhost:" port
                                                                     "\r\nUser-Agent: " agent "\r\nAccept: */*\r\nCookie: \r\n"))
                                          (kinds (lambda (lines head target)
                                                   (map (lambda (line)
                                                          (cond ((string=? line (string-append "open-head face=http bytes="
                                                                                               (number->string (string-length head))
                                                                                               " headers=" (quoted (substring head (+ (string-length target) 15) (string-length head)))))
                                                                 'the-head-left-open)
                                                                ((contains? line "open-head") (list 'another-open-head (with-port-named line port)))
                                                                (else 'a-request)))
                                                        (if (list? lines) lines '())))))
                                     (list (if (pair? set) (car set) set)
                                           (if (and (pair? long) (eqv? (car long) 200)) 200 long)
                                           (kinds lines head target)
                                           (if (pair? agent-set) (car agent-set) agent-set)
                                           agent-long
                                           (kinds agent-lines agent-head agent-target)))))))))
      (test-equal (string-append "a server's 4,003-byte cookie beside a head past 4,200 bytes before its Cookie line, which 7.85.0's cap counts whole, the request line, Host, the credentials' Authorization and User-Agent among it: by a long request line, and by a 4,300-byte User-Agent beside a short URL, by libcurl " (written version) "'s row: each transfer's answer at a bound of 3 s, and the origin's log, a head left open among it where libcurl ended none")
        (car answer) (cadr answer)))

    (let ((answer (by-version domain-localhost-rows "domain-localhost" psl-lane
                              (lambda ()
                                (list (set-read o "a.localhost" "" "dl1" '("d%3D1%3B%20Domain%3Dlocalhost"))
                                      (set-read o "localhost" "" "dl2" '("d%3D1%3B%20Domain%3Dlocalhost"))
                                      (set-read o "localhost" "" "dl3" '("__Host-dom%3D1%3B%20Secure%3B%20Path%3D%2F%3B%20Domain%3Dlocalhost")))))))
      (test-equal (string-append "Domain=localhost from a.localhost and from localhost, and a __Host- cookie with Domain=localhost, by " (written psl-lane) "'s row: each read-out, and the next request's Cookie headers")
        (car answer) (cadr answer)))

    (let ((answer (by-version matrix-rows "set-cookie-matrix" version
                              (lambda ()
                                (list (set-read o "a.localhost" "/a/b/page" "mx1" '("dp%3D1"))
                                      (set-read o "a.localhost" "/a/b/page" "mx2" '("pr%3D1%3B%20Path%3Drel" "pe%3D1%3B%20Path%3D"))
                                      (set-read o "a.localhost" "" "mx3" '("ca%3D1%3B%20Max-Age%3D86400000"))
                                      (set-read o "a.localhost" "" "mx4" '("ma%3D1%3B%20Max-Age%3D-1"))
                                      (on-jar
                                       (lambda (e jar)
                                         (fetch e jar (route o "a.localhost" "" "mx5" "&set=del%3D1&set=keep%3D1"))
                                         (fetch e jar (route o "a.localhost" "" "mx5" "&set=del%3D%3B%20Max-Age%3D0"))
                                         (let ((listed (normal (curl-cookie-jar-cookies jar))))
                                           (fetch e jar (route o "a.localhost" "" "mx5" ""))
                                           (list listed
                                                 (let ((lines (log-lines o "mx5")))
                                                   (if (and (list? lines) (= (length lines) 3)) (with-port-named (caddr lines) port) lines))
                                                 (normal (curl-cookie-jar-cookies jar)))))))))))
      (test-equal (string-append "the default path, Path=rel and Path=, the 400-day cap, Max-Age=-1 and a deleted cookie, by libcurl " (written version) "'s row: each read-out, and the next request's Cookie headers")
        (car answer) (cadr answer)))

    ;; --- no exit printing a cookie's value (ADR-0035; the M7 plan, section 3.5) ---------

    (test-equal "no exit prints a cookie's value, loaded or a server's: every refusal, cookie-line's, cookie-beside-jar's, cookie-jar-closed's and cookie-jar-engine's; a transfer's failure, its bound's, holding the jar; the jar, the request, the token, the response holding Set-Cookie, the session, the high level's response and its redirect error; as write, display and display-condition print them"
      '()
      (let* ((loaded "L0adedS3cr3t")
             (served "S3rvedS3cr3t")
             (secret? (lambda (x) (let ((text (printed x))) (or (contains? text loaded) (contains? text served)))))
             (e (make-curl-engine))
             (other (make-curl-engine)))
        (dynamic-wind
          (lambda () #f)
          (lambda ()
            (let* ((jar (make-curl-cookie-jar e))
                   (line (tabbed "a.localhost" "FALSE" "/" "FALSE" "0" "ld" loaded))
                   (_ (curl-cookie-jar-load! jar (list line)))
                   (url (route o "a.localhost" "" "pr" (string-append "&set=sv%3D" served)))
                   (request (make-curl-request url 'cookie-jar jar 'proxy #f 'timeout-ms 20000))
                   (token (curl-submit e request))
                   (response (curl-token-await token))
                   (late (curl-submit e (make-curl-request (string-append "http://a.localhost:" port "/pattern/10?delay=3000")
                                                           'cookie-jar jar 'proxy #f 'timeout-ms 500)))
                   (_ (curl-token-wait late 20000))
                   (closed (make-curl-cookie-jar e))
                   (_ (curl-cookie-jar-close! closed))
                   (session (make-http-session 'cookies #t 'proxy #f 'timeout-ms 20000 'redirects 0))
                   (_ (http-session-load-cookies! session (list line)))
                   (high (http-get session url))
                   (redirect (raised (lambda () (http-get session (route o "a.localhost" "" "pr" (string-append "&set=sv%3D" served "&status=302&to=%2Fx"))))))
                   (streamed (curl-submit e (make-curl-request url 'cookie-jar jar 'proxy #f 'timeout-ms 20000
                                                               'stream-buffer 65536)))
                   (head (and (curl-token-head-wait streamed 20000) (curl-token-head streamed))))
              (curl-token-cancel streamed)
              (curl-token-wait streamed 20000)
              (let ((things
                     (list (cons 'cookie-line (raised (lambda () (curl-cookie-jar-load! jar (list (string-append line "\x1;"))))))
                           (cons 'cookie-beside-jar (raised (lambda () (make-curl-request url 'cookie-jar jar 'headers (list (cons "Cookie" (string-append "x=" loaded)))))))
                           (cons 'cookie-jar-closed (raised (lambda () (curl-submit e (make-curl-request url 'cookie-jar closed)))))
                           (cons 'cookie-jar-engine (raised (lambda () (curl-submit other request))))
                           (cons 'failure (curl-token-outcome late))
                           (cons 'jar jar) (cons 'request request) (cons 'token token) (cons 'response response)
                           (cons 'head (if (curl-head? head) head (list 'no-head head)))
                           (cons 'session session) (cons 'high-response high) (cons 'redirect redirect))))
                (http-session-close session)
                (map car (filter (lambda (thing) (secret? (cdr thing))) things)))))
          (lambda () (curl-engine-stop e) (curl-engine-stop other)))))))

;; The scenarios' tests run here, in a definition, and the verdict on their
;; origin after: SRFI-64 keeps one result per runner (traps.md).
(define scenarios-outcome
  (guard (e (#t (list 'raised (describe e))))
    (call-with-origin (lambda (o) (scenarios o) 'done))))

(test-equal "the scenarios' origin starts, serves them all, and stops"
  'done
  scenarios-outcome)

;; --- the high level's refusals, and its engine stopped (the M7 plan, section 3.1) ---------

(test-equal "cookies is a boolean: 1, \"yes\" and a list are refused as make-http-session, not-a-boolean, field cookies, named by their kind; a call that names cookies is refused, unknown-key; nothing native is made"
  (list '(http-refused cookies 1 not-a-boolean) '(http-refused cookies (kind string) not-a-boolean)
        '(http-refused cookies (kind list) not-a-boolean) '(http-refused key cookies unknown-key)
        #t)
  (let ((before (native-counts)))
    (list (refused (lambda () (make-http-session 'cookies 1)))
          (refused (lambda () (make-http-session 'cookies "yes")))
          (refused (lambda () (make-http-session 'cookies (list secret-value))))
          (call-with-http-session
           (lambda (s) (refused (lambda () (http-get s "http://127.0.0.1:9/" 'cookies #t)))))
          (equal? (native-counts) before))))

(test-equal "a session's Cookie or Host header beside its cookies is refused as the jar's request is made, cookie-beside-jar, and the engine made for it is stopped; a jar that fails to be made raises, and stops the engine too"
  '(((request-refused curl-request-with header-name "Cookie" cookie-beside-jar) stopped)
    ((request-refused curl-request-with header-name "host" cookie-beside-jar) stopped)
    ((error make-curl-cookie-jar (1 2 1)) stopped))
  (map (lambda (made)
         (let ((engine (car made)))
           (list (refused (lambda () (session-on engine (session-defaults (cdr made)) '(20 #f #f) #t)))
                 (curl-engine-state engine))))
       (list (cons (make-curl-engine) (list (cons 'headers '(("X-A" . "1") ("Cookie" . "a=1")))))
             (cons (make-curl-engine) (list (cons 'headers '(("host" . "h")))))
             (cons (make-curl-engine-answering-jar 'make 1) '()))))

(test-equal "a session's jar is freed with it: http-session-cookies of a closed session raises its engine's stopped; of a session without cookies, an assertion violation"
  '((engine-error stopped) (assertion http-session-cookies) (assertion http-session-load-cookies!))
  (let ((s (make-http-session 'cookies #t)))
    (http-session-close s)
    (list (refused (lambda () (http-session-cookies s)))
          (call-with-http-session (lambda (plain) (refused (lambda () (http-session-cookies plain)))))
          (call-with-http-session (lambda (plain) (refused (lambda () (http-session-load-cookies! plain '()))))))))

;; --- an abandoned handle keeps its share (the M7 plan, section 3.5) ------------------------

;; abandon-child : String -> Any
;; tests/jar-abandon.sps in a child Chez, with HOW, abandon or free: what
;; it printed, read as data, or what went wrong.
(define (abandon-child how)
  (guard (e (#t (list 'raised (describe e))))
    (let ((r (capture-command (list (getenv "CHEZ") "--libdirs" (library-path) "--program"
                                    "tests/jar-abandon.sps" how))))
      (if (= (car r) 0)
          (read-all (cadr r))
          (list 'exit (car r) (cadr r) (caddr r))))))

(test-equal "a failed engine that abandons a live transfer's easy handle keeps its hold on the jar: the share stays in use, the jar closing, held once, and both stay counted, one easy handle and one share; the control, which frees the handle, lets the hold go, frees the share, the jar closed, nothing counted"
  (list (list '((engine-error failed) closing 1 ((block . 0) (easy . 1) (url . 0) (slist . 0) (curl-string . 0)
                                                 (transfer . 0) (multi . 0) (share . 1))))
        (list (list '(engine-error failed) 'closed 0 zero-counts)))
  (list (abandon-child "abandon") (abandon-child "free")))

;; --- freeing what it made ------------------------------------------------------------------

(define key-freed
  (guard (e (#t (list 'raised (describe e))))
    (when (curl-engine? key-engine) (curl-engine-stop key-engine))
    'freed))

(test-equal "every count is zero at the end, the suite's own engine stopped"
  (list 'freed zero-counts)
  (list key-freed (native-counts)))

(test-end "cookies")

(exit (suite-exit-status runner))
