#!r6rs
;;; The suite for (floors) and tests/check-floors.sps, the program behind
;;; `make check-floors` (harness plan, section 3, item 5). packaging/floors.sexp
;;; is the one file that writes the Chez, libcurl and Node floors, and
;;; check-floors holds README.org to it. Without this suite, deleting a rule
;;; would leave `make test` green: the real README and floors file break none
;;; of them.
;;;
;;; Three layers, each asserting whole values written by hand here, never read
;;; back from the code under test: a substring would pass whenever another
;;; rule produced the same words.
;;;
;;;   - the pure procedures, on texts held in this suite: every rule of the
;;;     floors file, and every rule of the README comparison, one fault in an
;;;     otherwise legal text;
;;;   - the program, on the fixture directories under tests/fixtures/floors/:
;;;     its exit status, whole stdout and whole stderr, and the files it
;;;     cannot read;
;;;   - the answers (floors) gives a suite: a floor by name, as text and as
;;;     numbers.
;;;
;;; The floors in every legal text here, 10.9.1, 8.1.2 and 22.3, are none of
;;; the real floors, so a check that wrote the README's lines from constants
;;; in place of the file would fail the legal rows.
;;;
;;; make test runs every suite from the repository root, where tests/ is, with
;;; CHEZ exported. Without CHEZ nothing below can run: that fails here, by
;;; name, and never skips.
;;;
;;; Each computation that can raise runs under a guard that names what was
;;; raised, since SRFI-64 turns a raise in the actual expression into #f and
;;; does not catch one in the expected expression. No expected value is #f.
(import (rnrs)
        (srfi :64)
        (curl-testing)
        (floors)
        (only (chezscheme) getenv directory-list file-directory?))

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

(define chez (getenv "CHEZ"))

(define program "tests/check-floors.sps")

(define fixtures "tests/fixtures/floors")

;; outcome : (-> Any) -> (U (List 'returned Any) (List 'raised String))
;; What THUNK did: returned a value, or raised, and what.
(define (outcome thunk)
  (guard (e (#t (list 'raised (describe e))))
    (list 'returned (thunk))))

;; --- words the messages are made of, written by hand --------------------------------

(define fp "f.sexp")
(define rp "R.org")

;; q : String -> String
;; S in double quotes, as write shows a string with no quote, backslash or
;; control character in it.
(define (q s) (string-append "\"" s "\""))

(define three "three dot-separated naturals, major.minor.patch")
(define dotted "dot-separated naturals")

(define (f: . words) (apply string-append fp ": " words))

(define (missing-key key) (f: "the key " key " is missing"))

(define (extra-key key)
  (f: "the key " key " is extra: the keys are chez, libcurl, node"))

(define (repeated-key key times)
  (f: "the key " key " appears " times " times"))

(define (misordered found)
  (f: "the keys are in the order " found ", but must be chez, libcurl, node"))

;; bad-version : String String String -> String
;; SHOWN is the version as written, quotes included when it is a string.
(define (bad-version key shown what)
  (f: key ": the version " shown " is not " what))

(define (not-an-entry shown) (f: shown " is not an entry (key \"version\")"))

(define (r: . words) (apply string-append rp ": " words))

(define section "** Requirements")

(define no-section (r: "it has no " (q section) " section"))

(define (many-sections n)
  (r: "it has " n " " (q section) " sections, but must have one"))

(define (altered-line i found wanted)
  (r: "list line " i " under " (q section) " is " (q found) ", but " fp " gives " (q wanted)))

(define (extra-line line)
  (r: (q section) " has an extra list line, " (q line) ", which " fp " does not give"))

(define (lacks-line line)
  (r: (q section) " lacks the list line " (q line) ", which " fp " gives"))

;; --- the floors file: texts ----------------------------------------------------------

;; floors-of : String String String -> String
;; A floors file holding the three datum texts as the versions.
(define (floors-of chez libcurl node)
  (string-append "((chez " chez ")\n (libcurl " libcurl ")\n (node " node "))\n"))

(define good-chez "\"10.9.1\"")
(define good-libcurl "\"8.1.2\"")
(define good-node "\"22.3\"")

(define good (floors-of good-chez good-libcurl good-node))

(define (floors-row name text problems)
  (test-equal (string-append "floors file: " name)
    (list 'returned problems)
    (outcome (lambda () (floors-problems fp text)))))

(test-begin "check-floors")

(test-equal "CHEZ names the Chez to spawn"
  'set
  (if (and chez (not (string=? chez ""))) 'set 'unset))

(unless (and chez (not (string=? chez "")))
  (exit 1))

;; --- the floors file: what is legal --------------------------------------------------

(floors-row "the base text is legal" good '())

(floors-row "a comment above, between, after and inside the datum is no datum"
  (string-append ";; the floors\n"
                 "((chez \"10.9.1\") ; the Chez floor\n"
                 " #;(python \"3\") (libcurl \"8.1.2\")\n"
                 " #| block |# (node \"22.3\"))\n"
                 ";; end\n")
  '())

(floors-row "zero is a natural, and so is a number of several digits"
  (floors-of "\"0.0.0\"" "\"10.0.10\"" "\"0\"")
  '())

(floors-row "Node may be one number, or several"
  (floors-of good-chez good-libcurl "\"22\"")
  '())

(floors-row "Node may be one number, or several: three"
  (floors-of good-chez good-libcurl "\"22.3.4\"")
  '())

;; --- the floors file: what is one datum ----------------------------------------------

(floors-row "an empty file holds no datum" ""
  (list (f: "it holds no datum, but must hold exactly one")))

(floors-row "a file of comments holds no datum" "; nothing here\n#| nor here |#\n"
  (list (f: "it holds no datum, but must hold exactly one")))

(floors-row "a second datum"
  (string-append good "(more)\n")
  (list (f: "it holds 2 data, but must hold exactly one")))

(floors-row "three data"
  (string-append good good good)
  (list (f: "it holds 3 data, but must hold exactly one")))

(floors-row "a datum cut short cannot be read"
  "((chez \"10.9.1\")"
  (list (f: "it cannot be read as data: Exception in read: unexpected end-of-file reading list at char 0 of #<input port string>")))

(floors-row "an #!eof literal would end the reading early"
  (string-append "#!eof " good)
  (list (f: "it cannot be read as data: Exception in read: an #!eof literal ends the reading before the end of the file")))

;; --- the floors file: what is an entry -----------------------------------------------

(floors-row "the datum is a number" "42"
  (list (f: "the datum is 42, not a list of (key \"version\") entries")))

(floors-row "the datum is a string" "\"10.9.1\""
  (list (f: "the datum is \"10.9.1\", not a list of (key \"version\") entries")))

(floors-row "the datum is a dotted pair" "(chez . \"10.9.1\")"
  (list (f: "the datum is (chez . \"10.9.1\"), not a list of (key \"version\") entries")))

(floors-row "the datum is a cyclic list, which is named and never walked" "#0=(a . #0#)"
  (list (f: "the datum is #0=(a . #0#), not a list of (key \"version\") entries")))

(floors-row "an empty list names all three keys missing" "()"
  (list (missing-key "chez") (missing-key "libcurl") (missing-key "node")))

(floors-row "an entry with a key and no version"
  "((chez \"10.9.1\") (libcurl) (node \"22.3\"))"
  (list (not-an-entry "(libcurl)") (missing-key "libcurl")))

(floors-row "an entry with a key and two versions"
  "((chez \"10.9.1\" \"10.9.2\") (libcurl \"8.1.2\") (node \"22.3\"))"
  (list (not-an-entry "(chez \"10.9.1\" \"10.9.2\")") (missing-key "chez")))

(floors-row "an entry whose key is a string"
  "((\"chez\" \"10.9.1\") (libcurl \"8.1.2\") (node \"22.3\"))"
  (list (not-an-entry "(\"chez\" \"10.9.1\")") (missing-key "chez")))

(floors-row "an entry that is no list"
  "(chez (libcurl \"8.1.2\") (node \"22.3\"))"
  (list (not-an-entry "chez") (missing-key "chez")))

(floors-row "the keys and versions in one flat list"
  "(chez \"10.9.1\")"
  (list (not-an-entry "chez") (not-an-entry "\"10.9.1\"")
        (missing-key "chez") (missing-key "libcurl") (missing-key "node")))

;; --- the floors file: the keys -------------------------------------------------------

(floors-row "no chez key"
  "((libcurl \"8.1.2\") (node \"22.3\"))"
  (list (missing-key "chez")))

(floors-row "no libcurl key"
  "((chez \"10.9.1\") (node \"22.3\"))"
  (list (missing-key "libcurl")))

(floors-row "no node key"
  "((chez \"10.9.1\") (libcurl \"8.1.2\"))"
  (list (missing-key "node")))

(floors-row "an extra key"
  "((chez \"10.9.1\") (libcurl \"8.1.2\") (node \"22.3\") (python \"3.12\"))"
  (list (extra-key "python")))

(floors-row "an extra key first"
  "((python \"3.12\") (chez \"10.9.1\") (libcurl \"8.1.2\") (node \"22.3\"))"
  (list (extra-key "python")))

(floors-row "an extra key twice is named once"
  "((chez \"10.9.1\") (libcurl \"8.1.2\") (node \"22.3\") (python \"3.12\") (python \"3.13\"))"
  (list (extra-key "python")))

(floors-row "a key in capitals is another key"
  "((Chez \"10.9.1\") (libcurl \"8.1.2\") (node \"22.3\"))"
  (list (missing-key "chez") (extra-key "Chez")))

(floors-row "a key twice"
  "((chez \"10.9.1\") (chez \"10.9.1\") (libcurl \"8.1.2\") (node \"22.3\"))"
  (list (repeated-key "chez" "2")))

(floors-row "a key three times, and another twice"
  (string-append "((node \"22.3\") (node \"22.3\") (node \"22.3\") (chez \"10.9.1\")"
                 " (libcurl \"8.1.2\") (libcurl \"8.1.2\"))")
  (list (repeated-key "node" "3") (repeated-key "libcurl" "2")))

(floors-row "libcurl before chez"
  "((libcurl \"8.1.2\") (chez \"10.9.1\") (node \"22.3\"))"
  (list (misordered "libcurl, chez, node")))

(floors-row "node first"
  "((node \"22.3\") (chez \"10.9.1\") (libcurl \"8.1.2\"))"
  (list (misordered "node, chez, libcurl")))

(floors-row "node before libcurl"
  "((chez \"10.9.1\") (node \"22.3\") (libcurl \"8.1.2\"))"
  (list (misordered "chez, node, libcurl")))

(floors-row "an extra key and a missing one, and no word about the order"
  "((node \"22.3\") (python \"3.12\") (chez \"10.9.1\"))"
  (list (missing-key "libcurl") (extra-key "python")))

;; --- the floors file: the versions ---------------------------------------------------

;; Chez and libcurl are each three numbers, because that is how the code compares them
;; (a list of three, and curl_version_info's version_num).
(for-each
 (lambda (text)
   (floors-row (string-append "chez " (q text) " is not three dot-separated naturals")
     (floors-of (q text) good-libcurl good-node)
     (list (bad-version "chez" (q text) three)))
   (floors-row (string-append "libcurl " (q text) " is not three dot-separated naturals")
     (floors-of good-chez (q text) good-node)
     (list (bad-version "libcurl" (q text) three))))
 '("10.9" "10" "10.9.1.2" "" "v10.9.1" "10.9.x" "10..1" "10.9." ".9.1" "." " 10.9.1" "10.9.1 "
   "10.09.1" "00.9.1" "-10.9.1" "+10.9.1" "1e1.9.1" "10.9.1-pre" "10,9,1" "0x10.9.1"
   "\x661;0.9.1"))

(for-each
 (lambda (text)
   (floors-row (string-append "node " (q text) " is not dot-separated naturals")
     (floors-of good-chez good-libcurl (q text))
     (list (bad-version "node" (q text) dotted))))
 '("" "x" "22..3" "22." ".22" "v22" "22.x" "022" "22 " "-22"))

(for-each
 (lambda (row)
   (floors-row (string-append "chez " (car row) " is no string")
     (floors-of (car row) good-libcurl good-node)
     (list (bad-version "chez" (car row) three)))
   (floors-row (string-append "node " (car row) " is no string")
     (floors-of good-chez good-libcurl (car row))
     (list (bad-version "node" (car row) dotted))))
 '(("10") ("10.9") ("ten") ("#f") ("()") ("(\"10.9.1\")")))

(floors-row "a version longer than the message shows is cut"
  (floors-of (q (make-string 70 #\1)) good-libcurl good-node)
  (list (bad-version "chez" (string-append "\"" (make-string 56 #\1) "...") three)))

(floors-row "several faults at once come in a fixed order: the entries, the keys, the versions"
  "((chez \"10.9\") (libcurl) (python \"3\") (node \"x\"))"
  (list (not-an-entry "(libcurl)")
        (missing-key "libcurl")
        (extra-key "python")
        (bad-version "chez" (q "10.9") three)
        (bad-version "node" (q "x") dotted)))

;; --- the README: what is legal -------------------------------------------------------

(define line-chez "- Chez Scheme 10.9.1 or later, built with threads")
(define line-libcurl "- libcurl 8.1.2 or later, built with TLS")
(define line-node "- Node.js 22.3 or later, for the tests")
(define good-lines (list line-chez line-libcurl line-node))

;; readme : String ... -> String
;; The lines, each ended by a newline.
(define (readme . lines)
  (apply string-append (map (lambda (line) (string-append line "\n")) lines)))

;; under-section : String ... -> String
;; A README whose Requirements section holds BODY.
(define (under-section . body)
  (apply readme (append (list "* Title" "" "An opening paragraph." "" section "") body)))

(define (readme-row name text problems)
  (test-equal (string-append "README: " name)
    (list 'returned problems)
    (outcome (lambda () (check-floors fp good rp text)))))

(readme-row "the three lines the floors give, in order" (apply under-section good-lines) '())

(readme-row "the section last in the file, with no newline after its last line"
  (string-append (readme "* Title" section line-chez line-libcurl) line-node)
  '())

(readme-row "prose, blank lines and lines that are no bullets between the items"
  (under-section line-chez "Some prose." "" line-libcurl "-not a bullet"
                 "text - with a dash" "-- two dashes" "*bold*" line-node "Closing prose.")
  '())

(readme-row "lists under other headings are not compared"
  (readme "* Title" "** Status" "- Chez Scheme 9.9.9 or later, built with threads"
          section line-chez line-libcurl line-node
          "** License" "- Node.js 1 or later, for the tests")
  '())

(readme-row "a deeper heading ends the section"
  (under-section line-chez line-libcurl line-node "*** Details" "- an extra item")
  '())

(readme-row "a heading of one star ends the section"
  (under-section line-chez line-libcurl line-node "* Next" "- an extra item")
  '())

;; --- the README: the section ---------------------------------------------------------

(readme-row "an empty README" "" (list no-section))

(readme-row "the right lines and no heading"
  (apply readme (cons "* Title" good-lines))
  (list no-section))

(readme-row "the right lines under another heading"
  (apply readme (append (list "* Title" "** Status") good-lines))
  (list no-section))

(readme-row "a heading of one star"
  (apply readme (append (list "* Title" "* Requirements") good-lines))
  (list no-section))

(readme-row "a heading of three stars"
  (apply readme (append (list "* Title" "*** Requirements") good-lines))
  (list no-section))

(readme-row "a heading with a tag"
  (apply readme (append (list "* Title" "** Requirements :build:") good-lines))
  (list no-section))

(readme-row "a heading in lower case"
  (apply readme (append (list "* Title" "** requirements") good-lines))
  (list no-section))

(readme-row "a plain line that says Requirements"
  (apply readme (append (list "* Title" "Requirements") good-lines))
  (list no-section))

(readme-row "two sections"
  (string-append (apply under-section good-lines) (apply under-section good-lines))
  (list (many-sections "2")))

(readme-row "three sections"
  (string-append (apply under-section good-lines) (apply under-section good-lines)
                 (apply under-section good-lines))
  (list (many-sections "3")))

;; --- the README: a line altered ------------------------------------------------------

(readme-row "the Chez line says an older Chez"
  (under-section "- Chez Scheme 10.8.0 or later, built with threads" line-libcurl line-node)
  (list (altered-line "1" "- Chez Scheme 10.8.0 or later, built with threads" line-chez)))

(readme-row "the libcurl line says SSL, not TLS"
  (under-section line-chez "- libcurl 8.1.2 or later, built with SSL" line-node)
  (list (altered-line "2" "- libcurl 8.1.2 or later, built with SSL" line-libcurl)))

(readme-row "the Node line says another Node"
  (under-section line-chez line-libcurl "- Node.js 22.4 or later, for the tests")
  (list (altered-line "3" "- Node.js 22.4 or later, for the tests" line-node)))

(readme-row "a line with a space at its end"
  (under-section line-chez (string-append line-libcurl " ") line-node)
  (list (altered-line "2" (string-append line-libcurl " ") line-libcurl)))

(readme-row "a line with two spaces inside it"
  (under-section line-chez "- libcurl 8.1.2 or later,  built with TLS" line-node)
  (list (altered-line "2" "- libcurl 8.1.2 or later,  built with TLS" line-libcurl)))

(readme-row "a line indented"
  (under-section line-chez line-libcurl (string-append "  " line-node))
  (list (altered-line "3" (string-append "  " line-node) line-node)))

(readme-row "a line with a plus for its bullet"
  (under-section "+ Chez Scheme 10.9.1 or later, built with threads" line-libcurl line-node)
  (list (altered-line "1" "+ Chez Scheme 10.9.1 or later, built with threads" line-chez)))

(readme-row "all three lines altered"
  (under-section "- Chez Scheme 1 or later, built with threads"
                 "- libcurl 2 or later, built with TLS"
                 "- Node.js 3 or later, for the tests")
  (list (altered-line "1" "- Chez Scheme 1 or later, built with threads" line-chez)
        (altered-line "2" "- libcurl 2 or later, built with TLS" line-libcurl)
        (altered-line "3" "- Node.js 3 or later, for the tests" line-node)))

;; --- the README: a line added or lost ------------------------------------------------

(readme-row "an extra line at the end"
  (under-section line-chez line-libcurl line-node "- Python 3 or later")
  (list (extra-line "- Python 3 or later")))

(readme-row "an extra line at the start"
  (under-section "- Python 3 or later" line-chez line-libcurl line-node)
  (list (extra-line "- Python 3 or later")))

(readme-row "an extra line in the middle"
  (under-section line-chez "- Python 3 or later" line-libcurl line-node)
  (list (extra-line "- Python 3 or later")))

(readme-row "an extra line with a plus bullet"
  (under-section line-chez line-libcurl line-node "+ Python 3 or later")
  (list (extra-line "+ Python 3 or later")))

(readme-row "an extra line nested under an item"
  (under-section line-chez line-libcurl line-node "  - nested")
  (list (extra-line "  - nested")))

(readme-row "an extra numbered line"
  (under-section line-chez line-libcurl line-node "1. numbered")
  (list (extra-line "1. numbered")))

(readme-row "an extra numbered line with a parenthesis"
  (under-section line-chez line-libcurl line-node "12) numbered")
  (list (extra-line "12) numbered")))

(readme-row "an extra line with an indented star"
  (under-section line-chez line-libcurl line-node "  * starred")
  (list (extra-line "  * starred")))

(readme-row "an extra line indented with a tab"
  (under-section line-chez line-libcurl line-node "\t- tabbed")
  (list (r: (q section) " has an extra list line, \"\\t- tabbed\", which " fp " does not give")))

(readme-row "a line twice"
  (under-section line-chez line-libcurl line-libcurl line-node)
  (list (extra-line line-libcurl)))

(readme-row "the Chez line missing"
  (under-section line-libcurl line-node)
  (list (lacks-line line-chez)))

(readme-row "the libcurl line missing"
  (under-section line-chez line-node)
  (list (lacks-line line-libcurl)))

(readme-row "the Node line missing"
  (under-section line-chez line-libcurl)
  (list (lacks-line line-node)))

(readme-row "the heading and nothing under it"
  (readme "* Title" section)
  (list (lacks-line line-chez) (lacks-line line-libcurl) (lacks-line line-node)))

(readme-row "the heading and prose under it"
  (under-section "Prose, and no list.")
  (list (lacks-line line-chez) (lacks-line line-libcurl) (lacks-line line-node)))

(readme-row "one line altered and one added"
  (under-section "- Chez Scheme 10.8.0 or later, built with threads" line-libcurl line-node
                 "- Python 3 or later")
  (list (extra-line "- Chez Scheme 10.8.0 or later, built with threads")
        (extra-line "- Python 3 or later")
        (lacks-line line-chez)))

;; --- the README: lines in another order ----------------------------------------------

(readme-row "the first two lines swapped"
  (under-section line-libcurl line-chez line-node)
  (list (altered-line "1" line-libcurl line-chez)
        (altered-line "2" line-chez line-libcurl)))

(readme-row "the last two lines swapped"
  (under-section line-chez line-node line-libcurl)
  (list (altered-line "2" line-node line-libcurl)
        (altered-line "3" line-libcurl line-node)))

(readme-row "the three lines rotated"
  (under-section line-libcurl line-node line-chez)
  (list (altered-line "1" line-libcurl line-chez)
        (altered-line "2" line-node line-libcurl)
        (altered-line "3" line-chez line-node)))

;; --- the README is held to the file, and the file comes first ------------------------

(test-equal "README: the lines come from the floors file: other floors, other lines"
  (list 'returned
        (list (altered-line "1" line-chez "- Chez Scheme 10.0.0 or later, built with threads")
              (altered-line "2" line-libcurl "- libcurl 7.85.0 or later, built with TLS")
              (altered-line "3" line-node "- Node.js 20 or later, for the tests")))
  (outcome (lambda ()
             (check-floors fp (floors-of "\"10.0.0\"" "\"7.85.0\"" "\"20\"")
                           rp (apply under-section good-lines)))))

(test-equal "a bad floors file is reported alone: the README is not read against it"
  (list 'returned (list (missing-key "node")))
  (outcome (lambda ()
             (check-floors fp "((chez \"10.9.1\") (libcurl \"8.1.2\"))"
                           rp (readme "* Title")))))

(test-equal "a good floors file and a good README report nothing"
  '(returned ())
  (outcome (lambda () (check-floors fp good rp (apply under-section good-lines)))))

;; --- the program -----------------------------------------------------------------------

;; run : (Listof String) -> (U (List Integer String String) (List 'raised String))
;; tests/check-floors.sps in a fresh Chez with ARGS: its exit status, stdout
;; and stderr.
(define (run args)
  (guard (e (#t (list 'raised (describe e))))
    (capture-command (append (list chez "--libdirs" "tests" "--program" program) args))))

;; at : String String -> String
;; The path the program names for FILE in the fixture directory CASE.
(define (at case file) (string-append fixtures "/" case "/" file))

;; both : String -> (Listof String)
;; The two files of the fixture directory CASE, as the program takes them.
(define (both case) (list (at case "floors.sexp") (at case "README.org")))

;; holds : String String String -> (List 0 String "")
;; What a pass prints: the README that states the floors in the floors file,
;; and the floors.
(define (holds readme-path floors-path summary)
  (list 0
        (string-append "check-floors: " readme-path " states the floors in "
                       floors-path " (" summary ")\n")
        ""))

;; refused : Natural String ... -> (List 1 "" String)
;; What a failure prints: PROBLEMS, one line each, then the count. COUNT is
;; given, not counted, so a miscount in the program is not copied here.
(define (refused count . problems)
  (list 1
        ""
        (string-append
         (apply string-append
                (map (lambda (p) (string-append "check-floors: " p "\n")) problems))
         "check-floors: FAILED (problems: " (number->string count) ")\n")))

(define (cannot-read path)
  (string-append path ": it cannot be read: Exception in open-file-input-port: failed for "
                 path ": no such file or directory"))

(define usage
  (list 1
        ""
        "check-floors: usage: scheme --libdirs tests --program tests/check-floors.sps FLOORS README\n"))

;; cases : (Listof (List String String (Listof String) Expected))
;; The fixture directory, what it holds, the arguments, and the program's
;; whole answer.
(define cases
  (list
   (list "legal"
         "floors no real floor equals, a README with their lines among other lists and sections"
         (both "legal")
         (holds (at "legal" "README.org") (at "legal" "floors.sexp")
                "chez 10.9.1, libcurl 8.1.2, node 22.3"))
   (list "readme-altered"
         "one README line altered"
         (both "readme-altered")
         (refused 1 (string-append
                     (at "readme-altered" "README.org")
                     ": list line 1 under \"** Requirements\" is \"- Chez Scheme 10.8.0 or later, built with threads\", but "
                     (at "readme-altered" "floors.sexp")
                     " gives \"- Chez Scheme 10.9.1 or later, built with threads\"")))
   (list "no-section"
         "the right lines under another heading"
         (both "no-section")
         (refused 1 (string-append (at "no-section" "README.org")
                                   ": it has no \"** Requirements\" section")))
   (list "floors-invalid"
         "a floors file with a missing key and a bad version: both named, and the README not read"
         (both "floors-invalid")
         (refused 2
                  (string-append (at "floors-invalid" "floors.sexp") ": the key node is missing")
                  (string-append (at "floors-invalid" "floors.sexp")
                                 ": chez: the version \"10.9\" is not three dot-separated naturals, major.minor.patch")))
   (list "no-readme"
         "a floors file and no README beside it"
         (both "no-readme")
         (refused 1 (cannot-read (at "no-readme" "README.org"))))
   (list "no-floors"
         "a README and no floors file beside it"
         (both "no-floors")
         (refused 1 (cannot-read (at "no-floors" "floors.sexp"))))))

;; ad hoc : (List String (Listof String) Expected)
;; Runs that need no directory of their own: neither file exists, a bad
;; floors file with no README, and the wrong number of arguments.
(define ad-hoc
  (list
   (list "neither file exists: both named, the floors first"
         (list (at "legal" "none.sexp") (at "legal" "none.org"))
         (refused 2 (cannot-read (at "legal" "none.sexp"))
                  (cannot-read (at "legal" "none.org"))))
   (list "a bad floors file and no README: the floors problems, then the README"
         (list (at "floors-invalid" "floors.sexp") (at "floors-invalid" "none.org"))
         (refused 3
                  (string-append (at "floors-invalid" "floors.sexp") ": the key node is missing")
                  (string-append (at "floors-invalid" "floors.sexp")
                                 ": chez: the version \"10.9\" is not three dot-separated naturals, major.minor.patch")
                  (cannot-read (at "floors-invalid" "none.org"))))
   (list "no arguments: the usage line, exit 1" '() usage)
   (list "one argument: the usage line, exit 1" (list (at "legal" "floors.sexp")) usage)
   (list "three arguments: the usage line, exit 1"
         (list (at "legal" "floors.sexp") (at "legal" "README.org") "extra")
         usage)))

(for-each
 (lambda (case)
   (test-equal (string-append (car case) ": " (cadr case))
     (cadddr case)
     (run (caddr case))))
 cases)

(for-each
 (lambda (case)
   (test-equal (car case) (caddr case) (run (cadr case))))
 ad-hoc)

;; The program and the pure procedure agree on the fixtures: each answer above
;; comes from check-floors on the files' texts. A fixture the pure procedure
;; passes, but the program refuses, would be the program's own rule.
(test-equal "the legal fixture's files pass the pure procedure"
  '(returned ())
  (outcome (lambda ()
             (check-floors "f" (file-text (at "legal" "floors.sexp"))
                           "r" (file-text (at "legal" "README.org"))))))

;; A fixture nothing runs guards nothing, and a case with no fixture runs on a
;; missing directory.
(test-equal "every fixture directory is a case above, and every case has its directory"
  (list-sort string<? (map car cases))
  (list-sort string<?
             (filter (lambda (name) (file-directory? (string-append fixtures "/" name)))
                     (directory-list fixtures))))

;; --- the answers (floors) gives a suite ------------------------------------------------

(define parsed (outcome (lambda () (parse-floors good))))

(test-equal "parse-floors answers the floors file's datum"
  `(returned ((chez "10.9.1") (libcurl "8.1.2") (node "22.3")))
  parsed)

(define (floor-row name proc key expected)
  (test-equal name
    (list 'returned expected)
    (outcome (lambda () (proc (parse-floors good) key)))))

(floor-row "floor-text: chez" floor-text 'chez "10.9.1")
(floor-row "floor-text: libcurl" floor-text 'libcurl "8.1.2")
(floor-row "floor-text: node" floor-text 'node "22.3")
(floor-row "floor-numbers: chez" floor-numbers 'chez '(10 9 1))
(floor-row "floor-numbers: libcurl" floor-numbers 'libcurl '(8 1 2))
(floor-row "floor-numbers: node" floor-numbers 'node '(22 3))

(test-equal "floor-numbers: zeros and several digits stay as they are"
  '(returned ((0 0 0) (10 0 10) (0)))
  (outcome (lambda ()
             (let ((floors (parse-floors (floors-of "\"0.0.0\"" "\"10.0.10\"" "\"0\""))))
               (map (lambda (key) (floor-numbers floors key)) '(chez libcurl node))))))

(test-equal "floor-text: a name that is no floor is refused, by name"
  '(raised "Exception in floor-text: no such floor with irritant python")
  (outcome (lambda () (floor-text (parse-floors good) 'python))))

(test-equal "floor-numbers: a name that is no floor is refused, by name"
  '(raised "Exception in floor-numbers: no such floor with irritant python")
  (outcome (lambda () (floor-numbers (parse-floors good) 'python))))

(test-equal "parse-floors refuses a file with a problem, naming it"
  '(raised "Exception in parse-floors: packaging/floors.sexp: the key node is missing")
  (outcome (lambda () (parse-floors "((chez \"10.9.1\") (libcurl \"8.1.2\"))"))))

(test-equal "parse-floors refuses a file with two problems, naming both"
  '(raised "Exception in parse-floors: packaging/floors.sexp: the key node is missing; packaging/floors.sexp: chez: the version \"10.9\" is not three dot-separated naturals, major.minor.patch")
  (outcome (lambda () (parse-floors "((chez \"10.9\") (libcurl \"8.1.2\"))"))))

(test-equal "requirement-lines: the three lines the README states, from the file"
  (list 'returned good-lines)
  (outcome (lambda () (requirement-lines (parse-floors good)))))

(test-equal "requirement-lines: other floors, other lines"
  '(returned ("- Chez Scheme 11.0.0 or later, built with threads"
              "- libcurl 9.9.9 or later, built with TLS"
              "- Node.js 30 or later, for the tests"))
  (outcome (lambda ()
             (requirement-lines
              (parse-floors (floors-of "\"11.0.0\"" "\"9.9.9\"" "\"30\""))))))

(test-equal "floors-path names the checked-in file"
  "packaging/floors.sexp"
  floors-path)

(test-equal "the checked-in floors file is legal"
  '(returned ())
  (outcome (lambda () (floors-problems floors-path (file-text floors-path)))))

(test-equal "read-floors answers the checked-in file's three floors, in order"
  '(returned (chez libcurl node))
  (outcome (lambda () (map car (read-floors)))))

(test-end "check-floors")

(exit (suite-exit-status runner))
