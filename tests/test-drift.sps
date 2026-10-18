#!r6rs
;;; The drift guard (ADR-0017): the libcurl this suite loaded must be one the
;;; maintainers have recorded. tests/known-libcurls.sexp holds one row for each
;;; libcurl the suites have run against, and this suite passes only when the
;;; loaded libcurl's version, version-num, features, ssl-version and host equal
;;; exactly one row's. The path it loaded from and the row's `where` are not
;;; compared: discovery checks the path, and the container's profile path
;;; changes with every manifest change.
;;;
;;; A libcurl with no row fails here, wherever it runs, and the suite prints
;;; the row to add to the error port. Adding a row is a reviewed change.
;;;
;;; Four parts, each held by tests that can fail:
;;;   - the file reads, under a guard, so a missing or broken file is a failing
;;;     test and never a suite that dies unnamed;
;;;   - every row has exactly the shape the file's header describes, and no two
;;;     rows are equal on the five compared fields;
;;;   - the matcher, a pure procedure defined below, on made-up rows and
;;;     reports, so that a matcher that ignores a field fails by name even when
;;;     the loaded libcurl happens to match;
;;;   - the guard itself, on the real report.
;;;
;;; Every expected value here is one the code under test cannot produce by
;;; failing: SRFI-64 makes #f of a raise in the actual expression, so none is
;;; #f, and each check of a refusal asks for a symbol.
(import (rnrs)
        (srfi :64)
        (curl-testing)
        (curl))

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

;; --- rows: their shape, and what a match is -------------------------------

;; A row is (libcurl (where S) (version S) (version-num N) (features N)
;; (ssl-version S) (host S)): S a string, N a natural number, the fields
;; in this order and no others.

;; field-names : (Listof Symbol)
(define field-names '(where version version-num features ssl-version host))

;; field-kinds : (Listof Symbol)
;; What each of field-names holds, in the same order.
(define field-kinds '(string string natural natural string string))

;; compared : (Listof Symbol)
;; The fields a row and a report are compared on: all but `where`, which
;; says only where the libcurl runs.
(define compared '(version version-num features ssl-version host))

;; natural? : Any -> Boolean
(define (natural? x)
  (and (integer? x) (exact? x) (>= x 0)))

;; kind-ok? : Symbol Any -> Boolean
(define (kind-ok? kind x)
  (case kind
    ((string) (string? x))
    ((natural) (natural? x))
    (else #f)))

;; row-problem : Any -> (U 'ok (Listof Any))
;; The symbol ok when ROW has the shape of a row, otherwise a list saying
;; what is wrong with it. Total: it answers for any datum.
(define (row-problem row)
  (cond
    ((not (and (list? row) (pair? row) (eq? (car row) 'libcurl)))
     (list 'not-a-libcurl-row row))
    ((not (for-all (lambda (field)
                     (and (list? field) (= (length field) 2) (symbol? (car field))))
                   (cdr row)))
     (list 'a-field-is-not-a-name-and-a-value (cdr row)))
    ((not (equal? (map car (cdr row)) field-names))
     (list 'fields-are (map car (cdr row)) 'not field-names))
    (else
     (let loop ((fields (cdr row)) (kinds field-kinds))
       (cond ((null? fields) 'ok)
             ((kind-ok? (car kinds) (cadr (car fields))) (loop (cdr fields) (cdr kinds)))
             (else (list 'bad-value (car (car fields)) 'wants (car kinds)
                         'got (cadr (car fields)))))))))

;; row-key : Any -> (U (Listof Any) #f)
;; The values of the compared fields of ROW, in order, or #f when ROW is
;; not shaped like a row: a malformed row is never a match.
(define (row-key row)
  (and (eq? (row-problem row) 'ok)
       (map (lambda (name) (cadr (assq name (cdr row)))) compared)))

;; A report is what the loaded libcurl says: an alist from each of compared
;; to its value, ((version . "8.20.0") (version-num . 529408) ...).

;; report-key : Any -> (U (Listof Any) #f)
;; The values of REPORT's compared fields, in order, or #f when REPORT is not
;; a report.
(define (report-key report)
  (and (list? report)
       (for-all pair? report)
       (for-all (lambda (name) (assq name report)) compared)
       (map (lambda (name) (cdr (assq name report))) compared)))

;; matching-rows : (Listof Any) Any -> (Listof Any)
;; The rows of ROWS whose compared fields equal REPORT's, in order. `where`
;; is not compared.
(define (matching-rows rows report)
  (let ((key (report-key report)))
    (filter (lambda (row) (and key (equal? (row-key row) key))) rows)))

;; duplicate-rows : (Listof Any) -> (Listof (List Positive-Integer Positive-Integer))
;; The pairs (I J), I < J, of rows, counted from 1, that are equal on the
;; compared fields. A row that is not shaped like one has no key, so it is
;; equal to none.
(define (duplicate-rows rows)
  (let ((keyed (let number ((i 1) (rest rows))
                 (if (null? rest)
                     '()
                     (cons (cons i (row-key (car rest))) (number (+ i 1) (cdr rest)))))))
    (let outer ((as keyed) (found '()))
      (if (null? as)
          (reverse found)
          (outer (cdr as)
                 (let inner ((bs (cdr as)) (found found))
                   (cond ((null? bs) found)
                         ((and (cdr (car as)) (equal? (cdr (car as)) (cdr (car bs))))
                          (inner (cdr bs) (cons (list (car (car as)) (car (car bs))) found)))
                         (else (inner (cdr bs) found)))))))))

;; --- the file, read under a guard ----------------------------------------

(define known-file "tests/known-libcurls.sexp")

;; read-data : String -> (U (List 'data (Listof Any)) (List 'unreadable String))
;; Every datum of the file at PATH, read with Chez's reader, or why it did
;; not read. Nothing it raises escapes: a missing file, a file that is not
;; UTF-8, unbalanced parentheses, and text after a #!eof mark all answer
;; (unreadable TEXT). The transcoder raises on a byte that is not UTF-8,
;; where the default would read it as U+FFFD. And the reader answers the
;; end of file at #!eof, so the port must be at its end too: otherwise a
;; row after the mark would go unread, and unchecked.
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

(define file-result (read-data known-file))

;; rows : (Listof Any)
;; What the file holds, one datum per row, or nothing when it did not read.
(define rows (if (eq? (car file-result) 'data) (cadr file-result) '()))

;; --- the loaded libcurl ----------------------------------------------------

;; Read under a guard too: a top-level raise would end the suite unnamed.
(define info
  (guard (e (#t (list 'no-info (describe e))))
    (loaded-libcurl)))

;; report : (U Report (List 'no-report String))
(define report
  (guard (e (#t (list 'no-report (describe e))))
    (list (cons 'version (libcurl-info-version info))
          (cons 'version-num (libcurl-info-version-number info))
          (cons 'features (libcurl-info-features info))
          (cons 'ssl-version (libcurl-info-ssl-version info))
          (cons 'host (libcurl-info-host info)))))

(define matches (matching-rows rows report))

;; written : Any -> String
(define (written datum)
  (call-with-string-output-port (lambda (p) (write datum p))))

;; placeholder : String
;; How the `where` of a printed row begins, until someone says where the
;; library runs. A row in the file must not begin so.
(define placeholder "TODO: ")

;; placeholder? : String -> Boolean
(define (placeholder? s)
  (let ((n (string-length placeholder)))
    (and (>= (string-length s) n) (string=? (substring s 0 n) placeholder))))

;; row-text : Report String -> String
;; The row for REPORT, as it is written in the file, one field to a line,
;; ready to paste. `where` is a note to be replaced: the suite cannot know
;; where the library runs.
(define (row-text report path)
  (string-append
   "(libcurl\n"
   " (where " (written (string-append placeholder "say where this runs (loaded from "
                                      path ")")) ")"
   (apply string-append
          (map (lambda (name)
                 (string-append "\n (" (symbol->string name) " "
                                (written (cdr (assq name report))) ")"))
               compared))
   ")\n"))

;; No row matches: say so on the error port, with the row to add. SRFI-64
;; shows only a test's name and values, and a person with a new libcurl
;; needs the row itself.
(when (null? matches)
  (let ((err (current-error-port)))
    (put-string err
      (if (report-key report)
          (string-append
           "test-drift: no row of " known-file " matches the libcurl this suite loaded"
           " (" (if (libcurl-info? info) (libcurl-info-path info) "path unknown") ").\n"
           "test-drift: if it is one to support, review it, and add this row to "
           known-file ",\n"
           "test-drift: with `where` saying where it runs (ADR-0017):\n\n"
           (row-text report (if (libcurl-info? info) (libcurl-info-path info) "?"))
           "\n")
          (string-append
           "test-drift: could not read what the loaded libcurl reports: "
           (written report) "\n")))
    (flush-output-port err)))

;; --- made-up data for the matcher and the shape check ------------------------
;; Values no real libcurl has, so no real row can stand in for a made-up one.

(define base-report
  '((version . "9.9.9") (version-num . 590592) (features . 2021)
    (ssl-version . "FakeTLS/1.2.3") (host . "madeup-unknown-os")))

(define base-row
  '(libcurl (where "made up, one") (version "9.9.9") (version-num 590592)
            (features 2021) (ssl-version "FakeTLS/1.2.3") (host "madeup-unknown-os")))

;; a row that differs from base-row in all of the five compared fields
(define other-row
  '(libcurl (where "made up, other") (version "8.8.8") (version-num 526336)
            (features 7) (ssl-version "OtherTLS/4.5.6") (host "madeup-other-os")))

;; row-with : Row Symbol Any -> Row
;; ROW with the value of field NAME replaced.
(define (row-with row name value)
  (cons 'libcurl
        (map (lambda (field) (if (eq? (car field) name) (list name value) field))
             (cdr row))))

;; row-without : Row Symbol -> Row
(define (row-without row name)
  (cons 'libcurl (filter (lambda (field) (not (eq? (car field) name))) (cdr row))))

;; report-with : Report Symbol Any -> Report
(define (report-with report name value)
  (map (lambda (field) (if (eq? (car field) name) (cons name value) field)) report))

;; another value of the same kind, for each compared field
(define changed-values
  '((version . "9.9.8") (version-num . 590593) (features . 2022)
    (ssl-version . "FakeTLS/1.2.4") (host . "madeup-unknown-os-2")))

;; verdict : Any -> Symbol
;; ok when ROW has the shape of a row, rejected otherwise.
(define (verdict row)
  (if (eq? (row-problem row) 'ok) 'ok 'rejected))

(test-begin "drift")

;; --- the file ---------------------------------------------------------------

(test-equal "tests/known-libcurls.sexp reads as data"
  'read
  (if (eq? (car file-result) 'data) 'read file-result))

;; One test for each row, named by its place in the file: a row that is
;; wrong is named, and the others still run.
(let loop ((i 1) (rest rows))
  (unless (null? rest)
    (test-equal (string-append "row " (number->string i)
                               " is (libcurl) with exactly where, version, version-num,"
                               " features, ssl-version and host, in that order")
      'ok
      (row-problem (car rest)))
    (loop (+ i 1) (cdr rest))))

(test-equal "no row's where still begins with the placeholder the suite prints"
  '()
  (filter (lambda (row)
            (and (eq? (row-problem row) 'ok)
                 (placeholder? (cadr (assq 'where (cdr row))))))
          rows))

(test-equal "no two rows are equal on version, version-num, features, ssl-version and host"
  '()
  (duplicate-rows rows))

;; --- read-data, on files written here -----------------------------------------

;; read-written : Bytevector -> (U 'data 'unreadable (List 'other Any))
;; What read-data makes of a file holding BYTES, by its first symbol.
(define (read-written bytes)
  (guard (e (#t (list 'other (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (let ((path (string-append dir "/rows.sexp")))
         (call-with-port (open-file-output-port path)
           (lambda (p) (put-bytevector p bytes)))
         (let ((result (read-data path)))
           (if (memq (car result) '(data unreadable)) (car result) (list 'other result))))))))

(test-equal "read-data: every datum of a file, in order"
  '(data ((libcurl (where "a")) (libcurl (where "b"))))
  (guard (e (#t (list 'other (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (let ((path (string-append dir "/rows.sexp")))
         (call-with-port (open-file-output-port path)
           (lambda (p) (put-bytevector p (string->utf8 "(libcurl (where \"a\"))\n(libcurl (where \"b\"))\n"))))
         (read-data path))))))

(test-equal "read-data: a file whose bytes are not UTF-8 does not read"
  'unreadable
  (read-written (u8-list->bytevector
                 (append (bytevector->u8-list (string->utf8 "(libcurl (where \""))
                         '(255 254)
                         (bytevector->u8-list (string->utf8 "\"))\n"))))))

(test-equal "read-data: a row after an end-of-file mark does not read"
  'unreadable
  (read-written (string->utf8 "(libcurl (where \"a\"))\n#!eof\n(libcurl (where \"x\") garbage\n")))

;; --- the shape check, on made-up rows -----------------------------------------

(test-equal "shape: a row with all six fields in order is a row"
  'ok
  (verdict base-row))

(for-each
 (lambda (name)
   (test-equal (string-append "shape: a row without " (symbol->string name) " is refused")
     'rejected
     (verdict (row-without base-row name))))
 field-names)

(test-equal "shape: a row with a seventh field is refused"
  'rejected
  (verdict (append base-row '((note "extra")))))

(test-equal "shape: a row with a field twice is refused"
  'rejected
  (verdict (append base-row '((host "madeup-unknown-os")))))

(test-equal "shape: a row with version and version-num swapped is refused"
  'rejected
  (verdict '(libcurl (where "made up, one") (version-num 590592) (version "9.9.9")
                     (features 2021) (ssl-version "FakeTLS/1.2.3")
                     (host "madeup-unknown-os"))))

(test-equal "shape: a row with where and host swapped is refused"
  'rejected
  (verdict '(libcurl (host "madeup-unknown-os") (version "9.9.9") (version-num 590592)
                     (features 2021) (ssl-version "FakeTLS/1.2.3")
                     (where "made up, one"))))

(for-each
 (lambda (case)
   (test-equal (string-append "shape: a row whose " (symbol->string (car case))
                              " is " (written (cdr case)) " is refused")
     'rejected
     (verdict (row-with base-row (car case) (cdr case)))))
 '((where . 5) (version . 8) (version-num . "529408") (features . -1)
   (features . 1.5) (features . "2021") (ssl-version . #f) (host . #f)
   (host . madeup-os)))

(for-each
 (lambda (case)
   (test-equal (string-append "shape: " (written case) " is refused")
     'rejected
     (verdict case)))
 '(5 () (libcurl) (libcurl2 (where "w")) (curl (where "w") (version "9.9.9"))
   (libcurl where version version-num features ssl-version host)
   ((libcurl (where "w")))))

;; --- the matcher, on made-up rows and reports ---------------------------------

(test-equal "matcher: the one row that equals the report is the one answered"
  (list base-row)
  (matching-rows (list other-row base-row other-row) base-report))

(for-each
 (lambda (name)
   (test-equal (string-append "matcher: a report that differs in " (symbol->string name)
                              " alone matches no row")
     '()
     (matching-rows (list base-row)
                    (report-with base-report name (cdr (assq name changed-values))))))
 compared)

(test-equal "matcher: a row that differs in where alone still matches"
  (list (row-with base-row 'where "made up, somewhere else"))
  (matching-rows (list (row-with base-row 'where "made up, somewhere else"))
                 base-report))

(test-equal "matcher: two rows that match are both answered, in order"
  (list base-row (row-with base-row 'where "made up, twin"))
  (matching-rows (list other-row base-row (row-with base-row 'where "made up, twin"))
                 base-report))

(test-equal "matcher: a row that is not shaped like one is never a match"
  '()
  (matching-rows (list (row-without base-row 'where)
                       (append base-row '((note "extra"))))
                 base-report))

(test-equal "matcher: a report that is not a report matches no row"
  '()
  (matching-rows (list base-row) '(no-report "it did not load")))

;; --- the duplicate check, on made-up rows ------------------------------------

(test-equal "duplicates: rows that differ in every compared field have none"
  '()
  (duplicate-rows (list base-row other-row)))

(test-equal "duplicates: rows that differ in where alone are one, found by place"
  '((1 3))
  (duplicate-rows (list base-row other-row (row-with base-row 'where "made up, twin"))))

(test-equal "duplicates: rows that differ in one compared field are not"
  '()
  (duplicate-rows (list base-row (row-with base-row 'features 2022))))

;; --- the row the suite prints -----------------------------------------------------

;; read-back : String -> Any
;; The first datum of TEXT, or (unreadable WHY).
(define (read-back text)
  (guard (e (#t (list 'unreadable (describe e))))
    (read (open-string-input-port text))))

;; A path with a quote and a backslash in it, the two characters a string
;; datum must escape.
(define awkward-path "/made/up/\"quoted\"/back\\slash/libcurl.so.4")

(test-equal "the row printed for a report reads back as a row that equals the report"
  (list (report-key base-report))
  (map row-key
       (matching-rows (list (read-back (row-text base-report awkward-path)))
                      base-report)))

;; --- the guard ----------------------------------------------------------------

;; The matched rows are read back through row-key, which does not depend on
;; the matcher, so a matcher that compares less than it should is caught here
;; as well as above. The expected value is the report's own five values.
(test-equal
    "the loaded libcurl's version, version-num, features, ssl-version and host equal exactly one row of tests/known-libcurls.sexp"
  (list (report-key report))
  (map row-key matches))

(test-end "drift")

(exit (suite-exit-status runner))
