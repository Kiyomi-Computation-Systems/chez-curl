#!r6rs
;;; The suite for (curl private url): URLs parsed, resolved and checked by
;;; libcurl's own URL API (ADR-0008, amended 2026-10-19; M2 plan, section
;;; 4.4).
;;;
;;; Its cases are ADR-0008's 16, against the base A, http://example.com/a/b/c?q=1,
;;; RFC 3986 section 5.4's 42 resolution examples, against the base R,
;;; http://a/b/c/d;p?q, and 12 URLs that hold é, λ, €, U+1F600 or a host
;;; with ü: 70, written once, in all-cases. "normalize X" is curl_url_set of X
;;; on a fresh handle, then curl_url_get; "resolve X" sets the base, then X,
;;; then gets. curl's verdicts vary by version:
;;;
;;;   - shared-answers holds the answer every recorded libcurl gives, for 60
;;;     of them;
;;;   - tests/known-url-verdicts.sexp holds a row per libcurl version a lane
;;;     runs, 7.85.0, 8.5.0 and 8.20.0, and for Apple's 8.7.1, with that
;;;     version's answer to each of the 10 others, the varying cases.
;;;
;;; The non-ASCII cases hold the decoding to UTF-8: curl_url_get hands back
;;; the bytes it was given, and 9 of their answers carry them raw, where
;;; UTF-8 and Latin-1 read differently, in two-, three- and four-byte
;;; sequences. The 3 that vary are relative references curl percent-encodes,
;;; in lower case before 8.20.0.
;;;
;;; The two must cover the 70 exactly, each once. A libcurl whose version has
;;; no row fails here, and the suite prints the row it would need on the
;;; error port, as test-drift does (ADR-0017). Every answer is asserted
;;; whole, the URL or (refused CODE), never a message, together with the
;;; native counts after it, which must all be zero, refusals included.
;;;
;;; Then chez-curl's own refusals: a scheme other than http or https, refused
;;; by require-http-scheme after it parses, for every other protocol the
;;; loaded libcurl lists (loaded-protocols), so no narrower check passes; and
;;; a NUL, refused before libcurl sees it, wherever it sits in the string, by
;;; every entry point, as &curl-url-error. Without that refusal libcurl would read "http://a/\x0;b" as
;;; http://a/ (C reads a string to its first NUL), so the tests assert the
;;; refusal's reason, not only a failure. And call-with-parsed-url's handle:
;;; counted while PROC runs, freed when it returns or escapes, and never
;;; reachable again through a continuation.
;;;
;;; Importing (curl) runs the load before this suite's first line, so a
;;; refused libcurl kills it with exit 255, which make test names FAIL.
;;; Every expected value is one the code under test cannot produce by
;;; failing: SRFI-64 makes #f of a raise in the actual expression, so none
;;; is #f.
(import (rnrs)
        (srfi :64)
        (curl-testing)
        (curl)
        (curl private url)
        (curl private conditions)
        (curl private counters)
        (only (curl private native) loaded-protocols)
        (rnrs mutable-strings)
        (only (chezscheme) fork-thread thread-join sleep make-time make-engine))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; The simple runner names a failing test but not its values. Print both.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (display "  expected: ")
        (write (test-result-ref r 'expected-value))
        (newline)
        (display "  actual:   ")
        (write (test-result-ref r 'actual-value))
        (newline)))))

;; --- the cases ----------------------------------------------------------------------

(define base-a "http://example.com/a/b/c?q=1")
(define base-r "http://a/b/c/d;p?q")

;; adr-0008-cases : (Listof Case)
;; ADR-0008's 16: six references against A, then ten URLs normalized.
(define adr-0008-cases
  (append
   (map (lambda (reference) (list 'resolve base-a reference))
        '("../d?x=2" "//other.example/x" "/root" "?only=query" "#frag" "https://elsewhere/"))
   (map (lambda (url) (list 'normalize url))
        '("http://example.com/./a/../b" "http://example.com/a b" "http://exa mple.com/"
          "http://example.com:99999/" "example.com/x" "foo://x/" "http://example.com/a%zz"
          "http:/example.com/x" "HTTP://Example.COM:80/x" "file:///etc/passwd"))))

;; rfc-3986-examples : (Listof (List String String))
;; RFC 3986 section 5.4's 42 examples, each reference with the RFC's answer
;; against R: 5.4.1's 23 normal ones, then 5.4.2's 19 abnormal ones.
(define rfc-3986-examples
  '(("g:h" "g:h") ("g" "http://a/b/c/g") ("./g" "http://a/b/c/g") ("g/" "http://a/b/c/g/")
    ("/g" "http://a/g") ("//g" "http://g") ("?y" "http://a/b/c/d;p?y") ("g?y" "http://a/b/c/g?y")
    ("#s" "http://a/b/c/d;p?q#s") ("g#s" "http://a/b/c/g#s") ("g?y#s" "http://a/b/c/g?y#s")
    (";x" "http://a/b/c/;x") ("g;x" "http://a/b/c/g;x") ("g;x?y#s" "http://a/b/c/g;x?y#s")
    ("" "http://a/b/c/d;p?q") ("." "http://a/b/c/") ("./" "http://a/b/c/") (".." "http://a/b/")
    ("../" "http://a/b/") ("../g" "http://a/b/g") ("../.." "http://a/") ("../../" "http://a/")
    ("../../g" "http://a/g")
    ("../../../g" "http://a/g") ("../../../../g" "http://a/g") ("/./g" "http://a/g")
    ("/../g" "http://a/g") ("g." "http://a/b/c/g.") (".g" "http://a/b/c/.g")
    ("g.." "http://a/b/c/g..") ("..g" "http://a/b/c/..g") ("./../g" "http://a/b/g")
    ("./g/." "http://a/b/c/g/") ("g/./h" "http://a/b/c/g/h") ("g/../h" "http://a/b/c/h")
    ("g;x=1/./y" "http://a/b/c/g;x=1/y") ("g;x=1/../y" "http://a/b/c/y")
    ("g?y/./x" "http://a/b/c/g?y/./x") ("g?y/../x" "http://a/b/c/g?y/../x")
    ("g#s/./x" "http://a/b/c/g#s/./x") ("g#s/../x" "http://a/b/c/g#s/../x")
    ("http:g" "http:g")))

;; non-ascii-cases : (Listof Case)
;; 12 URLs holding é (U+00E9), λ (U+03BB), € (U+20AC), U+1F600, and the
;; host bücher.example,
;; through normalize and resolve: in a path, a query and a fragment, a
;; relative reference, an absolute one, and a base.
(define base-e "http://example.com/\xE9;/")
(define non-ascii-cases
  `((normalize "http://example.com/\xE9;")
    (normalize "http://example.com/a?q=\x3BB;")
    (normalize "http://example.com/a?q=\x1F600;")
    (normalize "http://b\xFC;cher.example/")
    (normalize "http://example.com/\x20AC;?q=\x20AC;#\x20AC;")
    (resolve ,base-a "\xE9;")
    (resolve ,base-a "?q=\x3BB;")
    (resolve ,base-a "?q=\x1F600;")
    (resolve ,base-a "//b\xFC;cher.example/x")
    (resolve ,base-a "http://example.com/\xE9;?q=\x3BB;")
    (resolve ,base-a "https://elsewhere/\x1F600;#\x3BB;")
    (resolve ,base-e "x?q=1")))

;; all-cases : (Listof Case)
(define all-cases
  (append adr-0008-cases
          (map (lambda (example) (list 'resolve base-r (car example))) rfc-3986-examples)
          non-ascii-cases))

;; rfc-answer : String -> String
(define (rfc-answer reference) (cadr (assoc reference rfc-3986-examples)))

;; shared-answers : (Listof (List Case Answer))
;; The 60 cases every recorded libcurl answers alike: of ADR-0008's and the
;; RFC's, 51, on 7.85.0, 7.88.1, 8.5.0 (OpenSSL and GnuTLS) and 8.20.0
;; (ADR-0008, amended 2026-10-19); of the non-ASCII ones, 9, on 7.85.0,
;; 8.5.0 (both) and 8.20.0 (measured 2026-10-23). The RFC's examples give
;; the RFC's answer, but //g, which every version writes http://g/, and the
;; four the rows hold. Each non-ASCII answer holds its bytes raw, the host's
;; ü included, with and without IDN, and € (measured 2026-10-23, fix round
;; 2).
(define shared-answers
  (append
   `(((resolve ,base-a "../d?x=2") "http://example.com/a/d?x=2")
     ((resolve ,base-a "//other.example/x") "http://other.example/x")
     ((resolve ,base-a "/root") "http://example.com/root")
     ((resolve ,base-a "?only=query") "http://example.com/a/b/c?only=query")
     ((resolve ,base-a "https://elsewhere/") "https://elsewhere/")
     ((normalize "http://example.com/./a/../b") "http://example.com/b")
     ((normalize "http://example.com:99999/") (refused 4))
     ((normalize "example.com/x") (refused 27))
     ((normalize "foo://x/") (refused 5))
     ((normalize "http://example.com/a%zz") "http://example.com/a%zz")
     ((normalize "http:/example.com/x") "http://example.com/x")
     ((normalize "HTTP://Example.COM:80/x") "http://Example.COM:80/x")
     ((normalize "file:///etc/passwd") "file:///etc/passwd")
     ((normalize "http://example.com/\xE9;") "http://example.com/\xE9;")
     ((normalize "http://example.com/a?q=\x3BB;") "http://example.com/a?q=\x3BB;")
     ((normalize "http://example.com/a?q=\x1F600;") "http://example.com/a?q=\x1F600;")
     ((normalize "http://b\xFC;cher.example/") "http://b\xFC;cher.example/")
     ((normalize "http://example.com/\x20AC;?q=\x20AC;#\x20AC;") "http://example.com/\x20AC;?q=\x20AC;#\x20AC;")
     ((resolve ,base-a "//b\xFC;cher.example/x") "http://b\xFC;cher.example/x")
     ((resolve ,base-a "http://example.com/\xE9;?q=\x3BB;") "http://example.com/\xE9;?q=\x3BB;")
     ((resolve ,base-a "https://elsewhere/\x1F600;#\x3BB;") "https://elsewhere/\x1F600;#\x3BB;")
     ((resolve ,base-e "x?q=1") "http://example.com/\xE9;/x?q=1"))
   (map (lambda (reference)
          (list (list 'resolve base-r reference)
                (if (string=? reference "//g") "http://g/" (rfc-answer reference))))
        (filter (lambda (reference) (not (member reference '("g:h" "#s" "" "http:g"))))
                (map car rfc-3986-examples)))))

;; shared-cases : (Listof Case)
(define shared-cases (map car shared-answers))

;; varying-cases : (Listof Case)
;; The cases shared-answers leaves out, in all-cases' order: what each row
;; of the file answers.
(define varying-cases
  (filter (lambda (a-case) (not (member a-case shared-cases))) all-cases))

;; --- answers --------------------------------------------------------------------------

(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0)))

;; answer : Case -> Any
;; What (curl private url) answers for CASE, whole: the URL, (refused CODE)
;; for libcurl's refusal, (refused-by-chez-curl REASON) for chez-curl's own,
;; or (raised TEXT) for anything else.
(define (answer a-case)
  (guard (e ((curl-url-error? e)
             (if (curl-url-error-code e)
                 (list 'refused (curl-url-error-code e))
                 (list 'refused-by-chez-curl (curl-url-error-reason e))))
            (#t (list 'raised (describe e))))
    (case (car a-case)
      ((normalize) (url-normalize (cadr a-case)))
      ((resolve) (url-resolve (cadr a-case) (caddr a-case)))
      (else (list 'not-a-case a-case)))))

;; answered : Case -> (List Any (Listof (Pairof Symbol Natural)))
;; CASE's answer, and the native counts once it returned.
(define (answered a-case)
  (let ((a (answer a-case)))
    (list a (native-counts))))

;; case-text : Case -> String
(define (case-text a-case)
  (case (car a-case)
    ((normalize) (string-append "normalize " (written (cadr a-case))))
    (else (string-append "resolve " (written (caddr a-case)) " against " (written (cadr a-case))))))

;; written : Any -> String
(define (written x) (call-with-string-output-port (lambda (p) (write x p))))

;; --- the rows, read under a guard ---------------------------------------------------

(define verdicts-file "tests/known-url-verdicts.sexp")

;; read-data : String -> (U (List 'data (Listof Any)) (List 'unreadable String))
;; Every datum of the file at PATH, as test-drift reads its file: strict
;; UTF-8, and nothing after an end-of-file mark.
(define (read-data path)
  (guard (e (#t (list 'unreadable (describe e))))
    (call-with-port
     (open-file-input-port path (file-options) (buffer-mode block)
                           (make-transcoder (utf-8-codec) (native-eol-style)
                                            (error-handling-mode raise)))
     (lambda (port)
       (let loop ((found '()))
         (let ((datum (read port)))
           (cond ((not (eof-object? datum)) (loop (cons datum found)))
                 ((port-eof? port) (list 'data (reverse found)))
                 (else (list 'unreadable "text after an end-of-file mark")))))))))

(define file-result (read-data verdicts-file))

(define rows (if (eq? (car file-result) 'data) (cadr file-result) '()))

;; answer-shaped? : Any -> Boolean
;; A URL, or (refused CODE).
(define (answer-shaped? x)
  (or (string? x)
      (and (list? x) (= (length x) 2) (eq? (car x) 'refused)
           (integer? (cadr x)) (exact? (cadr x)))))

;; case-shaped? : Any -> Boolean
(define (case-shaped? x)
  (and (list? x)
       (or (and (= (length x) 2) (eq? (car x) 'normalize) (string? (cadr x)))
           (and (= (length x) 3) (eq? (car x) 'resolve) (string? (cadr x)) (string? (caddr x))))))

;; row-problem : Any -> (U 'ok (Listof Any))
;; ok when ROW is (libcurl (where S) (version S) (answers (CASE ANSWER) ...)),
;; each CASE and ANSWER well formed; else what is wrong. Total.
(define (row-problem row)
  (cond
    ((not (and (list? row) (= (length row) 4) (eq? (car row) 'libcurl)))
     (list 'not-a-row-of-three-fields row))
    ((not (and (list? (cadr row)) (= (length (cadr row)) 2) (eq? (car (cadr row)) 'where)
               (string? (cadr (cadr row)))))
     (list 'where-is (cadr row)))
    ((not (and (list? (caddr row)) (= (length (caddr row)) 2) (eq? (car (caddr row)) 'version)
               (string? (cadr (caddr row)))))
     (list 'version-is (caddr row)))
    ((not (and (list? (cadddr row)) (pair? (cadddr row)) (eq? (car (cadddr row)) 'answers)))
     (list 'answers-is (cadddr row)))
    ((find (lambda (pair)
             (not (and (list? pair) (= (length pair) 2)
                       (case-shaped? (car pair)) (answer-shaped? (cadr pair)))))
           (cdr (cadddr row)))
     => (lambda (pair) (list 'not-a-case-and-an-answer pair)))
    (else 'ok)))

;; row-version : Row -> String
(define (row-version row) (cadr (caddr row)))

;; row-answers : Row -> (Listof (List Case Answer))
(define (row-answers row) (cdr (cadddr row)))

;; rows-for-version : (Listof Any) String -> (Listof Row)
;; The well-formed rows of ROWS whose version is VERSION, in order.
(define (rows-for-version rows version)
  (filter (lambda (row) (and (eq? (row-problem row) 'ok) (string=? (row-version row) version)))
          rows))

;; version-verdict : (Listof Any) String -> (U 'one 'none 'several)
;; Whether ROWS hold exactly one row for VERSION.
(define (version-verdict rows version)
  (let ((n (length (rows-for-version rows version))))
    (cond ((= n 1) 'one) ((= n 0) 'none) (else 'several))))

;; distinct? : (Listof Any) -> Boolean
(define (distinct? xs)
  (or (null? xs) (and (not (member (car xs) (cdr xs))) (distinct? (cdr xs)))))

;; same-cases? : (Listof Case) (Listof Case) -> Boolean
;; Whether A and B hold the same cases, each once.
(define (same-cases? a b)
  (and (distinct? a) (distinct? b) (= (length a) (length b))
       (for-all (lambda (a-case) (member a-case b)) a)
       #t))

;; --- the loaded libcurl, and its row -------------------------------------------------

(define version
  (guard (e (#t (list 'no-version (describe e))))
    (libcurl-info-version (loaded-libcurl))))

(define matches (if (string? version) (rows-for-version rows version) '()))

(define the-row (and (= (length matches) 1) (car matches)))

;; row-text : String -> String
;; The row this libcurl would need: each varying case with what it answers
;; here, ready to paste, its where to be replaced.
(define (row-text version)
  (string-append
   "(libcurl\n"
   " (where \"TODO: say where this libcurl runs\")\n"
   " (version " (written version) ")\n"
   " (answers"
   (apply string-append
          (map (lambda (a-case) (string-append "\n  (" (written a-case) " " (written (answer a-case)) ")"))
               varying-cases))
   "))\n"))

;; No row: say so on the error port, with the row to add.
(when (and (string? version) (not the-row))
  (let ((err (current-error-port)))
    (put-string err
      (string-append
       "test-url: " (if (null? matches) "no row" "more than one row") " of " verdicts-file
       " is for libcurl " version ".\n"
       "test-url: if it is one to support, review its answers, and add this row,\n"
       "test-url: with `where` saying where it runs (ADR-0008, amended 2026-10-19):\n\n"
       (row-text version) "\n"))
    (flush-output-port err)))

(test-begin "url")

;; --- the tables cover the 70 cases ------------------------------------------------------

(test-equal "all-cases: ADR-0008's 16, RFC 3986's 42 and 12 non-ASCII ones, 70 cases, each once"
  '(16 42 12 70 distinct)
  (list (length adr-0008-cases) (length rfc-3986-examples) (length non-ascii-cases)
        (length all-cases)
        (if (distinct? all-cases) 'distinct 'repeated)))

(test-equal "shared-answers: 60 cases, each once, each one of all-cases"
  '(60 distinct ())
  (list (length shared-cases)
        (if (distinct? shared-cases) 'distinct 'repeated)
        (filter (lambda (a-case) (not (member a-case all-cases))) shared-cases)))

(test-equal "the varying cases are the 10 shared-answers leaves out: #frag against A, a space in a path and in a host, #s, the empty reference, g:h and http:g against R, and é, ?q=λ and ?q=U+1F600 against A"
  `((resolve ,base-a "#frag")
    (normalize "http://example.com/a b")
    (normalize "http://exa mple.com/")
    (resolve ,base-r "g:h")
    (resolve ,base-r "#s")
    (resolve ,base-r "")
    (resolve ,base-r "http:g")
    (resolve ,base-a "\xE9;")
    (resolve ,base-a "?q=\x3BB;")
    (resolve ,base-a "?q=\x1F600;"))
  varying-cases)

;; The decoding's control: of the shared answers, 9 hold bytes past ASCII,
;; where Latin-1 reads each byte as its own character, and each length of
;; sequence is there: é is U+00E9, two UTF-8 bytes, € three, U+1F600 four.
(test-equal "9 shared answers hold characters past ASCII, so a URL read back in any encoding but UTF-8 fails them"
  9
  (length (filter (lambda (pair)
                    (and (string? (cadr pair))
                         (exists (lambda (c) (> (char->integer c) 127)) (string->list (cadr pair)))))
                  shared-answers)))

;; --- the file ------------------------------------------------------------------------------

(test-equal "tests/known-url-verdicts.sexp reads as data"
  'read
  (if (eq? (car file-result) 'data) 'read file-result))

(test-equal "it holds rows for 7.85.0, 8.5.0 and 8.23.0, the libcurls the lanes run, 8.20.0, the container's, and 8.7.1, Apple's"
  '("7.85.0" "8.5.0" "8.20.0" "8.23.0" "8.7.1")
  (map (lambda (row) (if (eq? (row-problem row) 'ok) (row-version row) row)) rows))

(let loop ((i 1) (rest rows))
  (unless (null? rest)
    (let ((row (car rest)))
      (test-equal (string-append "row " (number->string i)
                                 " is (libcurl (where S) (version S) (answers (CASE ANSWER) ...))")
        'ok
        (row-problem row))
      (test-equal (string-append "row " (number->string i)
                                 " answers exactly the varying cases, each once")
        'exactly
        (if (and (eq? (row-problem row) 'ok)
                 (same-cases? (map car (row-answers row)) varying-cases))
            'exactly
            (if (eq? (row-problem row) 'ok) (map car (row-answers row)) row))))
    (loop (+ i 1) (cdr rest))))

(test-equal "each varying case has different answers in two rows at least: one all rows answer alike is a shared answer"
  '()
  (filter (lambda (a-case)
            (let ((answers (map (lambda (row) (let ((p (assoc a-case (row-answers row)))) (and p (cadr p))))
                                (filter (lambda (row) (eq? (row-problem row) 'ok)) rows))))
              (< (length (fold-left (lambda (seen a) (if (member a seen) seen (cons a seen))) '() answers)) 2)))
          varying-cases))

(test-equal "no two rows share a version"
  'distinct
  (let ((versions (map (lambda (row) (if (eq? (row-problem row) 'ok) (row-version row) row)) rows)))
    (if (distinct? versions) 'distinct versions)))

;; --- the matcher, on made-up rows ---------------------------------------------------------

(define made-up-row
  `(libcurl (where "made up") (version "9.9.9")
            (answers ((normalize "http://x/") "http://x/"))))

(test-equal "the matcher: a version with one row is one, with none is none, with two is several; a malformed row is never a match"
  '(one none several none)
  (list (version-verdict (list made-up-row) "9.9.9")
        (version-verdict (list made-up-row) "9.9.8")
        (version-verdict (list made-up-row made-up-row) "9.9.9")
        (version-verdict (list '(libcurl (version "9.9.9"))) "9.9.9")))

(test-equal "the shape: a row missing where, or with an answer that is no URL nor (refused CODE), is refused"
  '(rejected rejected rejected ok)
  (map (lambda (row) (if (eq? (row-problem row) 'ok) 'ok 'rejected))
       (list '(libcurl (version "9.9.9") (answers ((normalize "http://x/") "http://x/")))
             '(libcurl (where "w") (version "9.9.9") (answers ((normalize "http://x/") 3)))
             '(libcurl (where "w") (version "9.9.9") (answers ((normalize "http://x/") (refused "3"))))
             made-up-row)))

(test-equal "the printed row reads back as a well-formed row for this version, answering exactly the varying cases"
  'ok
  (guard (e (#t (list 'raised (describe e))))
    (let ((row (read (open-string-input-port (row-text "9.9.9")))))
      (cond ((not (eq? (row-problem row) 'ok)) (row-problem row))
            ((not (same-cases? (map car (row-answers row)) varying-cases)) (row-answers row))
            (else 'ok)))))

;; --- the guard -----------------------------------------------------------------------------

(test-equal "the loaded libcurl's version has exactly one row in tests/known-url-verdicts.sexp"
  (list version)
  (map row-version matches))

;; --- every case, answered whole, the counts back at zero -------------------------------------

(for-each
 (lambda (pair)
   (test-equal (string-append "shared: " (case-text (car pair)) " is " (written (cadr pair))
                              ", and the counts are back at zero")
     (list (cadr pair) zero-counts)
     (answered (car pair))))
 shared-answers)

(for-each
 (lambda (a-case)
   (test-equal (string-append "libcurl " (if (string? version) version "?") ": " (case-text a-case)
                              " is its row's answer, and the counts are back at zero")
     (list (if the-row
               (let ((pair (assoc a-case (row-answers the-row))))
                 (if pair (cadr pair) (list 'no-answer-in-its-row a-case)))
               (list 'no-row version))
           zero-counts)
     (answered a-case)))
 varying-cases)

;; --- the refusal's condition --------------------------------------------------------------

;; refusal : (-> Any) -> Any
;; What THUNK raised, as a &curl-url-error's fields, its message's type for
;; the message; (other TEXT) for any other raise, or (no-raise VALUE).
(define (refusal thunk)
  (guard (e ((curl-url-error? e)
             (list (curl-url-error-reason e) (curl-url-error-code e) (curl-url-error-input e)
                   (let ((m (curl-url-error-message e)))
                     (if (and (string? m) (> (string-length m) 0)) 'a-message m))))
            (#t (list 'other (describe e))))
    (list 'no-raise (thunk))))

(test-equal "libcurl's refusal: the code's name from curlue-codes, the code, the string refused, and curl_url_strerror's message"
  '(bad-port-number 4 "http://example.com:99999/" a-message)
  (refusal (lambda () (url-normalize "http://example.com:99999/"))))

(test-equal "a reference refused names the reference, not the base"
  `(unsupported-scheme 5 "foo://x/" a-message)
  (refusal (lambda () (url-resolve base-a "foo://x/"))))

(test-equal "a base refused names the base"
  `(bad-scheme 27 "example.com/x" a-message)
  (refusal (lambda () (url-resolve "example.com/x" "/root"))))

;; --- the scheme check (ADR-0008, decision 2) -------------------------------------------------

;; scheme-check : String -> Any
;; STRING parsed, then held to http or https: accepted, or what was raised;
;; and the counts after.
(define (scheme-check string)
  (let ((outcome (guard (e ((curl-url-error? e)
                            (list 'refused (curl-url-error-reason e) (curl-url-error-code e)
                                  (curl-url-error-input e)))
                           (#t (list 'other (describe e))))
                   (call-with-parsed-url string
                     (lambda (handle) (require-http-scheme handle string) 'accepted)))))
    (list outcome (native-counts))))

(test-equal "file:///etc/passwd parses, and require-http-scheme refuses it as scheme-not-http, with no code, naming the URL"
  (list '(refused scheme-not-http #f "file:///etc/passwd") zero-counts)
  (scheme-check "file:///etc/passwd"))

(test-equal "require-http-scheme accepts http, https, and HTTP, which libcurl writes in lower case"
  (list (list 'accepted zero-counts) (list 'accepted zero-counts) (list 'accepted zero-counts))
  (list (scheme-check "http://example.com/")
        (scheme-check "https://example.com/")
        (scheme-check "HTTP://Example.COM:80/x")))

;; The allowlist against its whole complement: every other scheme this
;; libcurl parses. curl_url_set with no flags parses only a scheme the
;; library supports (foo:// is refused 5, unsupported-scheme), and those are
;; the protocols it lists. Each must parse here, measured on 7.85.0, 8.5.0
;; (both) and 8.20.0, and then be refused by name. A check that refused
;; file alone, or any narrower set, fails one of these.
(define protocols
  (guard (e (#t (list 'raised (describe e))))
    (loaded-protocols)))

(define other-protocols
  (if (and (list? protocols) (for-all string? protocols))
      (filter (lambda (p) (not (member p '("http" "https")))) protocols)
      '()))

(test-equal "the loaded libcurl lists http and https among its protocols, each once, and at least four others"
  '(listed listed distinct at-least-four-others)
  (if (and (list? protocols) (for-all string? protocols))
      (list (if (member "http" protocols) 'listed 'missing)
            (if (member "https" protocols) 'listed 'missing)
            (if (distinct? protocols) 'distinct 'repeated)
            (if (>= (length other-protocols) 4) 'at-least-four-others other-protocols))
      protocols))

;; probe-url : String -> String
;; The URL for the protocol P: file:///etc/passwd for file, which takes no
;; host, else P://example.com/.
(define (probe-url p)
  (if (string=? p "file") "file:///etc/passwd" (string-append p "://example.com/")))

(for-each
 (lambda (p)
   (test-equal (string-append "require-http-scheme refuses " (probe-url p)
                              ", a protocol this libcurl lists, as scheme-not-http, after it parses")
     (list (list 'refused 'scheme-not-http #f (probe-url p)) zero-counts)
     (scheme-check (probe-url p))))
 other-protocols)

;; --- NUL, refused before libcurl sees it ------------------------------------------------------

;; (curl private url)'s own check, at every place a scan can miss: first,
;; in the middle, last, the whole string, and between é and λ. Each must
;; come back as &curl-url-error, reason embedded-nul: (curl private
;; native)'s check, behind it, raises a bare &curl-embedded-nul, which the
;; refusal helper reports as (other ...). And before libcurl sees it, so
;; with no handle and no block at the raise.
(define nul-urls
  '("\x0;http://a/" "http://a/\x0;b" "http://a/\x0;" "\x0;" "http://a/\xE9;\x0;\x3BB;"))

(define nul-references '("\x0;b" "b\x0;c" "b\x0;" "\x0;" "\xE9;\x0;\x3BB;"))

;; refusal-at-raise : (-> Any) -> (List Any (Listof (Pairof Symbol Natural)))
;; refusal's answer for THUNK, and the native counts at the moment of the
;; raise, read by a handler that runs before any dynamic-wind's after thunk,
;; then raises on. A refusal made once a handle or block existed shows it
;; there, though it is freed by the time the raise is caught.
(define (refusal-at-raise thunk)
  (let* ((seen 'no-raise)
         (r (refusal (lambda ()
                       (with-exception-handler
                         (lambda (c) (set! seen (native-counts)) (raise c))
                         thunk)))))
    (list r seen)))

(for-each
 (lambda (url)
   (test-equal (string-append "url-normalize refuses " (written url)
                              " as &curl-url-error, embedded-nul, with no code, naming it, with no handle or block at the raise")
     (list (list (list 'embedded-nul #f url 'a-message) zero-counts) zero-counts)
     (let ((r (refusal-at-raise (lambda () (url-normalize url)))))
       (list r (native-counts))))
   (test-equal (string-append "url-resolve refuses the base " (written url) " the same way")
     (list (list (list 'embedded-nul #f url 'a-message) zero-counts) zero-counts)
     (let ((r (refusal-at-raise (lambda () (url-resolve url "b")))))
       (list r (native-counts))))
   (test-equal (string-append "call-with-parsed-url refuses " (written url)
                              " the same way, before PROC, or any handle, exists")
     (list (list (list 'embedded-nul #f url 'a-message) zero-counts) 'proc-not-run zero-counts)
     (let* ((ran #f)
            (r (refusal-at-raise (lambda () (call-with-parsed-url url (lambda (h) (set! ran #t)))))))
       (list r (if ran 'proc-ran 'proc-not-run) (native-counts)))))
 nul-urls)

(for-each
 (lambda (reference)
   (test-equal (string-append "url-resolve refuses the reference " (written reference)
                               " as &curl-url-error, embedded-nul, naming it, with no handle or block at the raise")
     (list (list (list 'embedded-nul #f reference 'a-message) zero-counts) zero-counts)
     (let ((r (refusal-at-raise (lambda () (url-resolve "http://a/" reference)))))
       (list r (native-counts)))))
 nul-references)

;; --- call-with-parsed-url's handle ----------------------------------------------------------

(test-equal "call-with-parsed-url: PROC gets a handle, counted as url while it runs; PROC's answer comes back, and the count is zero after"
  (list (list 'handle '((block . 0) (easy . 0) (url . 1) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0)))
        'answer
        zero-counts)
  (let* ((inside #f)
         (result (call-with-parsed-url "http://example.com/"
                   (lambda (handle)
                     (set! inside (list (if (and (integer? handle) (> handle 0)) 'handle handle)
                                        (native-counts)))
                     'answer))))
    (list inside result (native-counts))))

(test-equal "call-with-parsed-url: a raise from PROC frees the handle, and reaches the caller"
  (list 'proc-raised zero-counts)
  (let ((r (guard (e ((eq? e 'from-proc) 'proc-raised))
             (call-with-parsed-url "http://example.com/" (lambda (handle) (raise 'from-proc))))))
    (list r (native-counts))))

(test-equal "call-with-parsed-url: a refused URL raises before PROC runs, and frees the handle"
  (list '(bad-port-number 4 "http://example.com:99999/" a-message) 'proc-not-run zero-counts)
  (let* ((ran #f)
         (r (refusal (lambda () (call-with-parsed-url "http://example.com:99999/"
                                  (lambda (h) (set! ran #t)))))))
    (list r (if ran 'proc-ran 'proc-not-run) (native-counts))))

;; A continuation captured in PROC, invoked once the call has returned and
;; freed its handle, must not run PROC on the freed handle again.
(test-equal "call-with-parsed-url: re-entering PROC through a continuation, once the handle is freed, raises, and PROC runs once"
  (list '(assertion-violation call-with-parsed-url) 1 zero-counts)
  (let ((k #f) (runs 0))
    (let ((r (guard (e ((and (assertion-violation? e) (who-condition? e))
                        (list 'assertion-violation (condition-who e)))
                       (#t (list 'other (describe e))))
               (call-with-parsed-url "http://example.com/"
                 (lambda (handle)
                   (call/cc (lambda (c) (set! k c)))
                   (set! runs (+ runs 1))))
               (if (= runs 1) (k #f) (list 'reentered runs)))))
      (list r runs (native-counts)))))

;; --- check-then-use: a URL another thread changes ----------------------------------------
;; call-with-parsed-url checks a copy of its input, and hands libcurl that
;; same copy. Checking the caller's string, then handing libcurl the
;; caller's string, lets a second thread put a NUL in between: the check
;; passes, and the NUL reaches the C string, refused there, as
;; call-with-c-string's &curl-embedded-nul, or not at all. Here a thread
;; flips one char between a and U+0000 while this one normalizes the URL:
;; each answer is the URL refused as embedded-nul, or the URL, whole.

;; flipped-normalize : Natural -> (List (Listof Any) (Listof Symbol) Counts)
;; N normalizations of http://a/xax, its a flipped: the answers that are
;; neither, which of the two were seen, and the counts after.
(define (flipped-normalize n)
  (let* ((s (string-copy "http://a/xax"))
         (stop #f)
         (yield (lambda () (sleep (make-time 'time-duration 0 0))))
         (pause (lambda () (sleep (make-time 'time-duration 1000000 0))))
         (flip (lambda ()
                 (let loop ((i 0))
                   (when (< i 100000)
                     (string-set! s 10 #\nul)
                     (string-set! s 10 #\a)
                     (loop (+ i 1))))))
         ;; It flips 100000 times as fast as it can, then yields once in
         ;; each state: natively it spins most of the time, and under
         ;; Valgrind both states reach the calls.
         (flipper (fork-thread (lambda ()
                                 (let loop ()
                                   (unless stop
                                     (flip)
                                     (yield)
                                     (flip)
                                     (string-set! s 10 #\nul)
                                     (yield)
                                     (loop)))))))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (let loop ((i 0) (odd '()) (seen '()))
          (if (= i n)
              (list (reverse odd) (filter (lambda (k) (memq k seen)) '(refused whole)) (native-counts))
              ;; Before every tenth, a sleep of a millisecond, where Valgrind,
              ;; which runs one thread at a time, lets the flipper run,
              ;; leaving the URL in either state. A sleep of no time there
              ;; could hand this thread the lock straight back: in 1 of 3
              ;; runs the flipper never ran, 0 of 1000 refused, where 1 ms
              ;; gave 490 to 500 in each of 6 (M5 slice 1,
              ;; .plans/research/m5/valgrind-yield/). Natively the flipper
              ;; races each call from another core.
              (let ((o (let ((a (begin (when (= (mod i 10) 0) (pause))
                                       (answer (list 'normalize s)))))
                         (cond ((equal? a '(refused-by-chez-curl embedded-nul)) 'refused)
                               ((equal? a "http://a/xax") 'whole)
                               (else a)))))
                (loop (+ i 1)
                      (if (memq o '(refused whole)) odd (cons o odd))
                      (if (memq o seen) seen (cons o seen)))))))
      (lambda () (set! stop #t) (thread-join flipper)))))

(test-equal "url-normalize, while another thread flips a char of its URL to U+0000: 1000 answers each the URL refused as embedded-nul, or the URL whole, both seen, and nothing left"
  (list '() '(refused whole) zero-counts)
  (flipped-normalize 1000))


;; --- asynchronous escapes: an engine's fuel running out anywhere ------------------------
;; An engine that runs out of fuel leaves through a continuation at its next
;; safe point, running the after thunks; an abandoned one is never resumed.
;; Each sweep runs THUNK in a fresh engine with fuel 1, 1+STEP, 1+2 STEP and
;; so on, abandoning each that runs out, until one completes: a native
;; object made but not yet recorded where its free finds it, at any of those
;; points, would stay made, and counted or not.

;; engine-sweep : (-> Any) Natural -> (List Symbol Natural)
;; (completed EXPIRED), EXPIRED the engines that ran out first; or
;; (never-completed EXPIRED) past 100000 fuel.
(define (engine-sweep thunk step)
  (let loop ((fuel 1) (expired 0))
    (cond ((> fuel 100000) (list 'never-completed expired))
          (((make-engine thunk) fuel (lambda (ticks v) #t) (lambda (e) #f)) (list 'completed expired))
          (else (loop (+ fuel step) (+ expired 1))))))

;; swept : (List Symbol Natural) -> Any
;; completed-after-expiries when the sweep completed after more than ten
;; engines ran out, its positive evidence; else the sweep itself.
(define (swept result)
  (if (and (eq? (car result) 'completed) (> (cadr result) 10)) 'completed-after-expiries result))

(for-each
 (lambda (row)
   (test-equal (string-append (car row) " in an engine that runs out at every tick, each abandoned, until one completes: it completes, and no native object is left, no CURLU and no string libcurl made")
     (list 'completed-after-expiries zero-counts)
     (let* ((sweep (swept (engine-sweep (cadr row) 1)))
            (counts (native-counts)))
       (list sweep counts))))
 (list (list "url-normalize" (lambda () (url-normalize "http://a/b/../c")))
       (list "url-resolve" (lambda () (url-resolve "http://a/b/c" "../d")))))

(test-end "url")

(exit (suite-exit-status runner))
