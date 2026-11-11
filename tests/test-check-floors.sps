#!r6rs
;;; The suite for (floors) and tests/check-floors.sps, the program behind `make
;;; check-floors`, and for the CI scripts that read the floors file or hold the
;;; workflows. packaging/floors.sexp is the one file that writes the Chez,
;;; libcurl and Node floors, and check-floors holds README.org to it, and every
;;; file under CI's workflow directory: CI states no floor, so no line of any
;;; file there may contain either floor's version text, nor name the two env
;;; keys that once held them. The build scripts read the floors from the file
;;; themselves (scripts/ci/floor.sh), so an env value or a matrix value in a
;;; workflow cannot change what CI builds. Without this suite, deleting a rule
;;; would leave `make test` green: the real README, workflows and floors file
;;; break none of them.
;;;
;;; Four layers, each asserting whole values written by hand here, never read
;;; back from the code under test: a substring would pass whenever another
;;; rule produced the same words.
;;;
;;;   - the pure procedures, on texts held in this suite: every rule of the
;;;     floors file, every rule of the README comparison and every rule of the
;;;     workflows comparison, the node-version rule among them, one fault in
;;;     an otherwise legal text;
;;;   - the program, on the fixture directories under tests/fixtures/floors/,
;;;     each with its workflows in a directory of their own, and on an empty
;;;     directory it makes, since git keeps none: its exit status, whole
;;;     stdout and whole stderr, and the files and directories it cannot
;;;     read;
;;;   - the answers (floors) gives a suite: a floor by name, as text and as
;;;     numbers;
;;;   - the CI scripts, run in a fresh tree that holds the real scripts/ci
;;;     and a floors file of the suite's own: floor.sh and the build scripts
;;;     read the floor from that file, and fail closed on a bad one;
;;;     check-action-pins.sh on workflow directories the suite writes. Where a
;;;     script would download, a curl that only names its URL stands in.
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

(define wd "W")
(define wp "W/ci.yml")

;; wrote : String Natural String String String -> String
;; The complaint about line N of the workflow file PATH, which contains a
;; floor's version text. WHICH is "Chez" or "libcurl", VERSION its floor,
;; FLOORS the floors file's path.
(define (wrote path n which version floors)
  (string-append path ": line " (number->string n) " contains the " which " floor " version
                 ", which no workflow line may write: the build scripts read it from " floors))

;; named : String Natural String String -> String
;; The complaint about line N of the workflow file PATH, which names KEY, one
;; of the two env keys CI no longer has. FLOORS is the floors file's path.
(define (named path n key floors)
  (string-append path ": line " (number->string n) " names " key
                 ", which no workflow line may name: the build scripts read the floors from " floors))

;; literal, keyed : Natural String String -> String
;; The complaints about line N of ci.yml, held against the floors file f.sexp.
(define (literal n which version) (wrote wp n which version fp))
(define (keyed n key) (named wp n key fp))

;; elsewhere, keyed-in : String Natural String String -> String
;; The same for a workflow file but ci.yml.
(define (elsewhere path n which version) (wrote path n which version fp))
(define (keyed-in path n key) (named path n key fp))

;; named-node : String Natural String -> String
;; The complaint about line N of the workflow file PATH, which names
;; node-version in a form other than a step's output. FLOORS is the floors
;; file's path.
(define (named-node path n floors)
  (string-append path ": line " (number->string n) " names node-version, but is not "
                 "\"node-version: ${{ steps.ID.outputs.NAME }}\": the Node floor comes from "
                 floors ", through a step that runs scripts/ci/floor.sh node"))

;; unread : String Natural Symbol -> String
;; The complaint about line N of the workflow file PATH, which breaks the
;; fail-closed rule WHICH: backslash, explicit, alias, beyond-ascii or tab.
(define (unread path n which)
  (string-append path ": line " (number->string n)
                 (case which
                   ((backslash) " holds a backslash after a double quote, which YAML may read as an escape, and check-floors does not")
                   ((explicit) " writes an explicit key, with ?, whose colon check-floors does not look for")
                   ((alias) " puts an alias or an anchor where a key goes, which check-floors does not resolve")
                   ((beyond-ascii) " holds a character beyond ASCII, which GitHub may fold into a key's letters, and check-floors does not")
                   ((tab) " holds a tab, which YAML may read beside a key, and check-floors does not"))))

;; escaped-key : String Natural -> String
;; The complaint about a double-quoted key with an escape, as the backslash
;; rule words it.
(define (escaped-key path n) (unread path n 'backslash))

;; node-at, node-in : the same against f.sexp, in ci.yml and in another file.
(define (node-at n) (named-node wp n fp))
(define (node-in path n) (named-node path n fp))

;; no-files, no-ci : String
;; The complaints about a workflow directory that holds no file, and one that
;; holds files but no ci.yml.
(define no-files (string-append wd ": it holds no file, but must hold ci.yml, the workflow CI runs"))
(define no-ci (string-append wd ": it holds no ci.yml, the workflow CI runs"))

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

;; --- the workflows the README rows are held beside ----------------------------------

;; workflow : String ... -> String
;; The lines, each ended by a newline.
(define (workflow . lines)
  (apply string-append (map (lambda (line) (string-append line "\n")) lines)))

;; workflow-with : String ... -> String
;; A legal workflow, which states no floor, with the lines BODY after its first
;; job's steps.
(define (workflow-with . body)
  (apply workflow
         (append (list "name: CI" "" "on:" "  pull_request:" "" "jobs:" "  main:"
                       "    runs-on: ubuntu-24.04" "    steps:"
                       "      - run: scripts/ci/build-chez.sh /opt/chez"
                       "      - run: scripts/ci/build-curl.sh /opt/curl")
                 body)))

;; The first line of BODY in workflow-with is line 12.
(define body-line 12)

(define good-workflow (workflow-with))

(define (readme-row name text problems)
  (test-equal (string-append "README: " name)
    (list 'returned problems)
    (outcome (lambda () (check-floors fp good rp text wd (list (list wp good-workflow)))))))

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

;; --- the workflow: what is legal -----------------------------------------------------

(define (workflow-row name text problems)
  (test-equal (string-append "workflow: " name)
    (list 'returned problems)
    (outcome (lambda ()
               (check-floors fp good rp (apply under-section good-lines) wd (list (list wp text)))))))

(workflow-row "a workflow that states no floor: nothing to report" good-workflow '())

(workflow-row "the Node floor may be written anywhere: it is no floor of the workflow"
  (workflow-with "      - run: node --version # 22.3 or later" "      - run: echo 22")
  '())

(workflow-row "a version that is no floor of the file may be written anywhere"
  (workflow-with "      - run: echo 10.4.0 7.85.0, the real floors, here other versions"
                 "      - run: echo 10.9 8.1 10.9.0 8.1.3")
  '())

;; check-floors reads text, not YAML. A matrix value of another version is no
;; floor's text, so it is not seen here: the build scripts read the floors
;; from the file and take no version, so the value reaches nothing.
(workflow-row "a matrix value of another version is no floor's text: check-floors cannot see it"
  (workflow "jobs:" "  floor:" "    strategy:" "      matrix:" "        curl: [\"8.1.3\", \"8.1.1\"]")
  '())

;; --- the workflow: the two env keys --------------------------------------------------

;; job-env : String -> String
;; A workflow whose first job's env holds LINE, which is line 8.
(define (job-env line)
  (workflow "name: CI" "on:" "  pull_request:" "jobs:" "  floor:"
            "    runs-on: ubuntu-24.04" "    env:" (string-append "      " line)
            "    steps:" "      - run: make build"))

(workflow-row "a job's env redefining the libcurl floor, to another version"
  (job-env "CURL_FLOOR_VERSION: \"8.1.3\"")
  (list (keyed 8 "CURL_FLOOR_VERSION")))

(workflow-row "a job's env redefining the Chez floor, to another version"
  (job-env "CHEZ_VERSION: \"10.8.0\"")
  (list (keyed 8 "CHEZ_VERSION")))

(workflow-row "a job's env redefining a floor, to the floor itself: the floor's text and the key"
  (job-env "CURL_FLOOR_VERSION: \"8.1.2\"")
  (list (literal 8 "libcurl" "8.1.2") (keyed 8 "CURL_FLOOR_VERSION")))

(workflow-row "a key in a reference, in the expression syntax"
  (workflow-with "      - run: scripts/ci/build-chez.sh ${{ env.CHEZ_VERSION }} /opt/chez")
  (list (keyed body-line "CHEZ_VERSION")))

(workflow-row "a key in a reference, in the shell syntax"
  (workflow-with "      - run: scripts/ci/build-curl.sh \"$CURL_FLOOR_VERSION\" /opt/curl")
  (list (keyed body-line "CURL_FLOOR_VERSION")))

(workflow-row "a key in a comment"
  (workflow-with "      # CHEZ_VERSION used to hold the Chez floor")
  (list (keyed body-line "CHEZ_VERSION")))

(workflow-row "a key inside a longer name is still the key's text"
  (job-env "MY_CHEZ_VERSION: other")
  (list (keyed 8 "CHEZ_VERSION")))

(workflow-row "both keys on one line: both are named, the Chez key first"
  (workflow-with "      - run: echo $CURL_FLOOR_VERSION $CHEZ_VERSION")
  (list (keyed body-line "CHEZ_VERSION") (keyed body-line "CURL_FLOOR_VERSION")))

(workflow-row "the old env block: each line's floor, then its key, in line order"
  (workflow "env:" "  CHEZ_VERSION: \"10.9.1\"" "  CURL_FLOOR_VERSION: \"8.1.2\"" "jobs:")
  (list (literal 2 "Chez" "10.9.1") (keyed 2 "CHEZ_VERSION")
        (literal 3 "libcurl" "8.1.2") (keyed 3 "CURL_FLOOR_VERSION")))

;; --- the workflow: a floor written anywhere ------------------------------------------

(workflow-row "the Chez floor in a run step"
  (workflow-with "      - run: scripts/ci/build-chez.sh 10.9.1 /opt/chez")
  (list (literal body-line "Chez" "10.9.1")))

(workflow-row "the libcurl floor in a run step"
  (workflow-with "      - run: scripts/ci/build-curl.sh 8.1.2 /opt/curl")
  (list (literal body-line "libcurl" "8.1.2")))

(workflow-row "the Chez floor in a comment"
  (workflow-with "      # Chez 10.9.1 is built from its tarball")
  (list (literal body-line "Chez" "10.9.1")))

(workflow-row "the libcurl floor in a cache key"
  (workflow-with "          key: curl-8.1.2-linux")
  (list (literal body-line "libcurl" "8.1.2")))

(workflow-row "the floor inside a longer number is still the floor's text"
  (workflow-with "      - run: echo 110.9.1")
  (list (literal body-line "Chez" "10.9.1")))

(workflow-row "both floors on one line: both are named, the Chez floor first"
  (workflow-with "      - run: echo 8.1.2 10.9.1")
  (list (literal body-line "Chez" "10.9.1")
        (literal body-line "libcurl" "8.1.2")))

(workflow-row "a floor on several lines: each line is named, in line order"
  (workflow-with "      - run: echo 8.1.2" "      - run: echo fine" "      - run: echo 10.9.1")
  (list (literal body-line "libcurl" "8.1.2")
        (literal (+ body-line 2) "Chez" "10.9.1")))

(workflow-row "a floor and a key on different lines: line order"
  (workflow "env:" "  other: $CHEZ_VERSION" "jobs:" "      - run: echo 10.9.1")
  (list (keyed 2 "CHEZ_VERSION") (literal 4 "Chez" "10.9.1")))

;; --- the workflow: the Node version setup-node installs --------------------------------
;; It comes from a step's output, which a step fills from scripts/ci/floor.sh
;; node. node-version written any other way is named, whatever it gives.

(workflow-row "node-version from a step's output: nothing to report"
  (workflow-with "        with:" "          node-version: ${{ steps.node.outputs.version }}")
  '())

(workflow-row "node-version from a step's output, as a list item, with words of digits, - and _"
  (workflow-with "      - node-version: ${{ steps.floor-2.outputs.node_version }}")
  '())

(for-each
 (lambda (row)
   (workflow-row (string-append "node-version " (car row) ": named")
     (workflow-with "        with:" (cadr row))
     (list (node-at (+ body-line 1)))))
 '(("as a literal" "          node-version: 20")
   ("as the Node floor itself, quoted" "          node-version: \"22.3\"")
   ("from a matrix" "          node-version: ${{ matrix.node }}")
   ("from env" "          node-version: ${{ env.NODE_FLOOR }}")
   ("from a step's output, with a comment after it"
    "          node-version: ${{ steps.node.outputs.version }} # the floor")
   ("with no space after its colon" "          node-version:${{ steps.node.outputs.version }}")
   ("with two spaces inside the braces" "          node-version: ${{  steps.node.outputs.version }}")
   ("from a step with no id" "          node-version: ${{ steps..outputs.version }}")
   ("from a step, but not its outputs" "          node-version: ${{ steps.node.version }}")
   ("from a step's outputs, with no name" "          node-version: ${{ steps.node.outputs. }}")
   ("with its value on the next line" "          node-version:")
   ("as a quoted key" "          \"node-version\": ${{ steps.node.outputs.version }}")
   ("in a flow mapping" "        with: { node-version: ${{ steps.node.outputs.version }} }")
   ("as node-version-file" "          node-version-file: .nvmrc")
   ("in a comment" "        # node-version: 20 is the floor")
   ("with its key in title case, as GitHub reads it all the same" "          Node-Version: 20")
   ("with its key in upper case" "          NODE-VERSION: ${{ steps.node.outputs.version }}")
   ("with its key single-quoted, in title case" "          'Node-Version': 20")
   ("in title case, from a step's output" "          Node-Version: ${{ steps.node.outputs.version }}")))

(for-each
 (lambda (row)
   (workflow-row (string-append "a double-quoted key with an escape " (car row) ": named")
     (workflow-with "        with:" (cadr row))
     (list (escaped-key wp (+ body-line 1)))))
 '(("that spells node-version" "          \"node\\x2Dversion\": 20")
   ("that spells another key" "          \"name\\x2D2\": 20")
   ("after spaces, before its colon" "          \"n\\u006fde-x\"  : 20")))

(workflow-row "a double-quoted value with an escape: named too, since a quoted key may go on over lines"
  (workflow-with "      - run: printf \"a\\nb\"" "        env:" "          X: \"a\\tb\"")
  (list (unread wp body-line 'backslash) (unread wp (+ body-line 2) 'backslash)))

(workflow-row "node-version on two lines: each named, in line order"
  (workflow-with "          node-version: 20" "      - run: echo fine" "          node-version: ${{ matrix.node }}")
  (list (node-at body-line) (node-at (+ body-line 2))))

(workflow-row "node-version holding the Chez floor: the floor first, then node-version"
  (workflow-with "          node-version: 10.9.1")
  (list (literal body-line "Chez" "10.9.1") (node-at body-line)))

;; --- the workflow: what check-floors cannot read, it fails closed on ---------------
;; A key YAML or GitHub would read other than as written: a backslash after a
;; double quote, an explicit key, an alias or anchor where a key goes, a
;; character beyond ASCII, a tab. Each rule, alone, on a line of its own.

(for-each
 (lambda (row)
   (workflow-row (string-append "unread: " (car row) ": named")
     (workflow-with (cadr row))
     (map (lambda (which) (unread wp body-line which)) (caddr row))))
 (list (list "a backslash after a double quote, in a value" "      - run: printf \"a\\nb\"" '(backslash))
       (list "a backslash after a double quote that is never closed" "      - run: echo \"a\\" '(backslash))
       (list "an explicit key" "          ? x" '(explicit))
       (list "an explicit key with nothing after it" "          ?" '(explicit))
       (list "an explicit key in a sequence item" "      - ? x" '(explicit))
       (list "an explicit key in a flow mapping" "        with: { ? x : 1 }" '(explicit))
       (list "an alias as a key" "          *k : 22.3" '(alias))
       (list "an anchor on a key" "          &a x: 1" '(alias))
       (list "an alias as a key in a flow mapping" "        with: { a: 1, *k : 2 }" '(alias))
       (list "a character beyond ASCII, in a comment" (string-append "          # caf" (string #\xe9)) '(beyond-ascii))
       (list "a long s in a key" (string-append "          node-ver" (string #\x17f) "ion: 22.3") '(beyond-ascii))
       (list "a tab before a colon" (string-append "          x" (string #\tab) ": 1") '(tab))
       (list "a backslash after a double quote and a tab" (string-append "          \"a\\x2D\"" (string #\tab) ": 1")
             '(backslash tab))))

(for-each
 (lambda (row)
   (workflow-row (string-append "unread, narrowed: " (car row) ": nothing to report")
     (workflow-with (cadr row))
     '()))
 '(("a shell case pattern *) in a run block" "            *)")
   ("a && at the start of a line of a run block" "            && make test")
   ("a glob *.txt) in a run block" "            *.txt) echo text ;;")
   ("an anchor on a value" "          K: &k plain")
   ("a backslash in single quotes, with no double quote before it" "          pkgs=$(tr '\\n' ' ')")
   ("a question mark inside a value" "          name: what? this")))

;; --- the workflows: every file under the directory -----------------------------------

(define (workflows-row name workflows problems)
  (test-equal (string-append "workflows: " name)
    (list 'returned problems)
    (outcome (lambda ()
               (check-floors fp good rp (apply under-section good-lines) wd workflows)))))

(define release "W/release.yml")

;; release-with : String ... -> String
;; A second workflow, with the lines BODY after its steps. The first line of
;; BODY is line 7.
(define (release-with . body)
  (apply workflow
         (append (list "name: Release" "on:" "  push:" "jobs:" "  release:" "    steps:")
                 body)))

(define release-line 7)

(define clean-release (release-with "      - run: make build"))

;; the-old-env : String
;; The env block CI had before the floors moved to the floors file: two lines,
;; which are lines 2 and 3 of a workflow that starts with them.
(define the-old-env
  (workflow "env:" "  CHEZ_VERSION: \"10.9.1\"" "  CURL_FLOOR_VERSION: \"8.1.2\""))

(workflows-row "a second workflow that writes no floor: nothing to report"
  (list (list wp good-workflow) (list release clean-release))
  '())

(workflows-row "the Node floor, and versions that are no floor, may be written in a second workflow"
  (list (list wp good-workflow)
        (list release (release-with "      - run: node --version # 22.3" "      - run: echo 10.9 8.1.3")))
  '())

(workflows-row "a second workflow that writes the Chez floor in a step: named, by its own path and line"
  (list (list wp good-workflow)
        (list release (release-with "      - run: scripts/ci/build-chez.sh 10.9.1 /opt/chez")))
  (list (elsewhere release release-line "Chez" "10.9.1")))

(workflows-row "a second workflow that writes the libcurl floor in a comment"
  (list (list wp good-workflow)
        (list release (release-with "      - run: make build" "# curl 8.1.2 is the floor")))
  (list (elsewhere release (+ release-line 1) "libcurl" "8.1.2")))

(workflows-row "a second workflow whose env names the Chez key: named, by its own path and line"
  (list (list wp good-workflow)
        (list release (release-with "      - run: make build" "      - run: echo $CHEZ_VERSION")))
  (list (keyed-in release (+ release-line 1) "CHEZ_VERSION")))

(workflows-row "node-version as a literal in a second workflow: named, by its own path and line"
  (list (list wp good-workflow) (list release (release-with "          node-version: 20")))
  (list (node-in release release-line)))

(workflows-row "the old env block in a second workflow: each line's floor and key"
  (list (list wp good-workflow) (list release the-old-env))
  (list (elsewhere release 2 "Chez" "10.9.1") (keyed-in release 2 "CHEZ_VERSION")
        (elsewhere release 3 "libcurl" "8.1.2") (keyed-in release 3 "CURL_FLOOR_VERSION")))

(workflows-row "the old env block in ci.yml itself is no exception"
  (list (list wp the-old-env))
  (list (literal 2 "Chez" "10.9.1") (keyed 2 "CHEZ_VERSION")
        (literal 3 "libcurl" "8.1.2") (keyed 3 "CURL_FLOOR_VERSION")))

(workflows-row "every file is held, in path order, whatever order they come in; a line names its floors, then its keys"
  (list (list "W/z.yml" (workflow "# 10.9.1"))
        (list wp (workflow-with "      - run: echo 8.1.2"))
        (list "W/a.yml" (workflow "" "# CHEZ_VERSION is 8.1.2 and 10.9.1")))
  (list (elsewhere "W/a.yml" 2 "Chez" "10.9.1")
        (elsewhere "W/a.yml" 2 "libcurl" "8.1.2")
        (keyed-in "W/a.yml" 2 "CHEZ_VERSION")
        (literal body-line "libcurl" "8.1.2")
        (elsewhere "W/z.yml" 1 "Chez" "10.9.1")))

(workflows-row "a file in a subdirectory is held like any other"
  (list (list wp good-workflow) (list "W/sub/notes.yml" (workflow "# 10.9.1")))
  (list (elsewhere "W/sub/notes.yml" 1 "Chez" "10.9.1")))

(workflows-row "a ci.yml in a subdirectory is not the workflow: there is no ci.yml, and its lines are held"
  (list (list "W/sub/ci.yml" (workflow-with "      - run: echo 10.9.1")))
  (list no-ci
        (elsewhere "W/sub/ci.yml" body-line "Chez" "10.9.1")))

(workflows-row "no file at all: the directory is named, once"
  '()
  (list no-files))

(workflows-row "no ci.yml, and a second workflow that writes no floor"
  (list (list release clean-release))
  (list no-ci))

(workflows-row "an unreadable ci.yml, #f, is not compared, and is no missing ci.yml; the others still are"
  (list (list wp #f)
        (list release (release-with "      - run: echo 10.9.1")))
  (list (elsewhere release release-line "Chez" "10.9.1")))

(workflows-row "an unreadable second workflow, #f, is not compared"
  (list (list wp good-workflow) (list release #f))
  '())

;; --- the README is held to the file, and the file comes first ------------------------

(test-equal "README and workflow: the lines come from the floors file: other floors, other lines"
  (list 'returned
        (list (altered-line "1" line-chez "- Chez Scheme 10.0.0 or later, built with threads")
              (altered-line "2" line-libcurl "- libcurl 7.85.0 or later, built with TLS")
              (altered-line "3" line-node "- Node.js 20 or later, for the tests")
              (literal body-line "Chez" "10.0.0")
              (literal body-line "libcurl" "7.85.0")))
  (outcome (lambda ()
             (check-floors fp (floors-of "\"10.0.0\"" "\"7.85.0\"" "\"20\"")
                           rp (apply under-section good-lines)
                           wd (list (list wp (workflow-with "      - run: echo 10.0.0 7.85.0")))))))

(test-equal "a bad floors file is reported alone: neither the README nor the workflow is read against it"
  (list 'returned (list (missing-key "node")))
  (outcome (lambda ()
             (check-floors fp "((chez \"10.9.1\") (libcurl \"8.1.2\"))"
                           rp (readme "* Title")
                           wd (list (list wp (workflow "# 10.9.1 and CHEZ_VERSION")))))))

(test-equal "a good floors file, README and workflow report nothing"
  '(returned ())
  (outcome (lambda ()
             (check-floors fp good rp (apply under-section good-lines) wd (list (list wp good-workflow))))))

(test-equal "an unreadable README, #f, is not compared, and the workflow still is"
  (list 'returned (list (literal 1 "Chez" "10.9.1") (keyed 1 "CHEZ_VERSION")))
  (outcome (lambda () (check-floors fp good rp #f wd (list (list wp (workflow "# 10.9.1 CHEZ_VERSION")))))))

(test-equal "an unreadable ci.yml, #f, is not compared, and the README still is"
  (list 'returned (list no-section))
  (outcome (lambda () (check-floors fp good rp (readme "* Title") wd (list (list wp #f))))))

(test-equal "a workflow directory that could not be read, #f, is not compared, and the README still is"
  (list 'returned (list no-section))
  (outcome (lambda () (check-floors fp good rp (readme "* Title") wd #f))))

(test-equal "an unreadable README and an unreadable workflow directory compare nothing"
  '(returned ())
  (outcome (lambda () (check-floors fp good rp #f wd #f))))

(test-equal "a bad README and a bad workflow are both reported, the README first"
  (list 'returned
        (list (lacks-line line-node)
              (literal 1 "libcurl" "8.1.2")))
  (outcome (lambda ()
             (check-floors fp good rp (under-section line-chez line-libcurl)
                           wd (list (list wp (workflow "# 8.1.2")))))))

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
;; The three arguments the program takes for the fixture directory CASE: the
;; floors file, the README and the workflow directory.
(define (both case)
  (list (at case "floors.sexp") (at case "README.org") (at case "workflows")))

;; holds : String String String String String -> (List 0 String "")
;; What a pass prints: the README and the workflow directory that hold the
;; floors in the floors file, the files read there, and the floors.
(define (holds readme-path workflows-path names floors-path summary)
  (list 0
        (string-append "check-floors: " readme-path " and " workflows-path " (" names ")"
                       " hold the floors in " floors-path " (" summary ")\n")
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

;; cannot-list : String String -> String
;; The complaint about a workflow directory at PATH that cannot be listed, for
;; WHY: "no such file or directory", or "not a directory".
(define (cannot-list path why)
  (string-append path ": it cannot be read: Exception in directory-list: failed for "
                 path ": " why))

(define usage
  (list 1
        ""
        "check-floors: usage: scheme --libdirs tests --program tests/check-floors.sps FLOORS README WORKFLOWS\n"))

;; cases : (Listof (List String String (Listof String) Expected))
;; The fixture directory, what it holds, the arguments, and the program's
;; whole answer.
(define cases
  (list
   (list "legal"
         "floors no real floor equals, a README with their lines among other lists and sections, a ci.yml that states no floor"
         (both "legal")
         (holds (at "legal" "README.org") (at "legal" "workflows") "ci.yml" (at "legal" "floors.sexp")
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
         "a floors file with a missing key and a bad version: both named, and the README and workflows not read"
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
         (refused 1 (cannot-read (at "no-floors" "floors.sexp"))))
   (list "workflow-literal"
         "ci.yml passes the libcurl floor to a build script"
         (both "workflow-literal")
         (refused 1 (wrote (at "workflow-literal" "workflows/ci.yml") 10 "libcurl" "8.1.2"
                           (at "workflow-literal" "floors.sexp"))))
   (list "workflow-key"
         "a job's env in ci.yml redefines the libcurl floor, to a version that is not the floor"
         (both "workflow-key")
         (refused 1 (named (at "workflow-key" "workflows/ci.yml") 9 "CURL_FLOOR_VERSION"
                           (at "workflow-key" "floors.sexp"))))
   (list "workflow-env-restored"
         "ci.yml has its old top-level env, writing both floors, and steps that refer to it"
         (both "workflow-env-restored")
         (refused 6
                  (wrote (at "workflow-env-restored" "workflows/ci.yml") 6 "Chez" "10.9.1"
                         (at "workflow-env-restored" "floors.sexp"))
                  (named (at "workflow-env-restored" "workflows/ci.yml") 6 "CHEZ_VERSION"
                         (at "workflow-env-restored" "floors.sexp"))
                  (wrote (at "workflow-env-restored" "workflows/ci.yml") 7 "libcurl" "8.1.2"
                         (at "workflow-env-restored" "floors.sexp"))
                  (named (at "workflow-env-restored" "workflows/ci.yml") 7 "CURL_FLOOR_VERSION"
                         (at "workflow-env-restored" "floors.sexp"))
                  (named (at "workflow-env-restored" "workflows/ci.yml") 12 "CHEZ_VERSION"
                         (at "workflow-env-restored" "floors.sexp"))
                  (named (at "workflow-env-restored" "workflows/ci.yml") 13 "CURL_FLOOR_VERSION"
                         (at "workflow-env-restored" "floors.sexp"))))
   (list "workflow-matrix"
         "a matrix value holding a version that is no floor: no floor's text, so nothing to report"
         (both "workflow-matrix")
         (holds (at "workflow-matrix" "README.org") (at "workflow-matrix" "workflows") "ci.yml"
                (at "workflow-matrix" "floors.sexp") "chez 10.9.1, libcurl 8.1.2, node 22.3"))
   (list "workflow-node-literal"
         "ci.yml hands setup-node a literal version"
         (both "workflow-node-literal")
         (refused 1 (named-node (at "workflow-node-literal" "workflows/ci.yml") 11
                                (at "workflow-node-literal" "floors.sexp"))))
   (list "workflow-node-key-title"
         "ci.yml hands setup-node a literal under Node-Version, which GitHub reads as node-version"
         (both "workflow-node-key-title")
         (refused 1 (named-node (at "workflow-node-key-title" "workflows/ci.yml") 14
                                (at "workflow-node-key-title" "floors.sexp"))))
   (list "workflow-node-key-upper"
         "ci.yml hands setup-node a literal under NODE-VERSION"
         (both "workflow-node-key-upper")
         (refused 1 (named-node (at "workflow-node-key-upper" "workflows/ci.yml") 14
                                (at "workflow-node-key-upper" "floors.sexp"))))
   (list "workflow-node-key-single-quoted"
         "ci.yml hands setup-node a literal under 'Node-Version', single-quoted"
         (both "workflow-node-key-single-quoted")
         (refused 1 (named-node (at "workflow-node-key-single-quoted" "workflows/ci.yml") 14
                                (at "workflow-node-key-single-quoted" "floors.sexp"))))
   (list "workflow-node-key-escaped"
         "ci.yml hands setup-node a literal under \"node\\x2Dversion\", a key YAML reads as node-version"
         (both "workflow-node-key-escaped")
         (refused 1 (escaped-key (at "workflow-node-key-escaped" "workflows/ci.yml") 14)))
   (list "workflow-key-explicit"
         "ci.yml hands setup-node a literal under an explicit key, ? \"node\\x2Dversion\", its colon on the next line"
         (both "workflow-key-explicit")
         (refused 2 (unread (at "workflow-key-explicit" "workflows/ci.yml") 14 'backslash)
                  (unread (at "workflow-key-explicit" "workflows/ci.yml") 14 'explicit)))
   (list "workflow-key-tab"
         "ci.yml hands setup-node a literal under a quoted key with a tab before its colon"
         (both "workflow-key-tab")
         (refused 2 (unread (at "workflow-key-tab" "workflows/ci.yml") 14 'backslash)
                  (unread (at "workflow-key-tab" "workflows/ci.yml") 14 'tab)))
   (list "workflow-key-multiline"
         "ci.yml hands setup-node a literal under a double-quoted key that goes on over two lines"
         (both "workflow-key-multiline")
         (refused 2 (unread (at "workflow-key-multiline" "workflows/ci.yml") 14 'backslash)
                  (unread (at "workflow-key-multiline" "workflows/ci.yml") 14 'explicit)))
   (list "workflow-key-alias"
         "ci.yml hands setup-node a literal under an alias of an anchored \"node\\x2Dversion\""
         (both "workflow-key-alias")
         (refused 2 (unread (at "workflow-key-alias" "workflows/ci.yml") 14 'backslash)
                  (unread (at "workflow-key-alias" "workflows/ci.yml") 16 'alias)))
   (list "workflow-key-flow-explicit"
         "ci.yml hands setup-node a literal under an explicit key in a flow mapping"
         (both "workflow-key-flow-explicit")
         (refused 2 (unread (at "workflow-key-flow-explicit" "workflows/ci.yml") 13 'backslash)
                  (unread (at "workflow-key-flow-explicit" "workflows/ci.yml") 13 'explicit)))
   (list "workflow-key-long-s"
         "ci.yml hands setup-node a literal under node-verſion, which GitHub folds to NODE-VERSION"
         (both "workflow-key-long-s")
         (refused 1 (unread (at "workflow-key-long-s" "workflows/ci.yml") 14 'beyond-ascii)))
   (list "workflow-key-dotless-i"
         "ci.yml hands setup-node a literal under node-versıon, which GitHub folds to NODE-VERSION"
         (both "workflow-key-dotless-i")
         (refused 1 (unread (at "workflow-key-dotless-i" "workflows/ci.yml") 14 'beyond-ascii)))
   (list "workflow-node-step"
         "ci.yml hands setup-node a step's output: nothing to report"
         (both "workflow-node-step")
         (holds (at "workflow-node-step" "README.org") (at "workflow-node-step" "workflows") "ci.yml"
                (at "workflow-node-step" "floors.sexp") "chez 10.9.1, libcurl 8.1.2, node 22.3"))
   (list "no-workflow"
         "a floors file and a README, and no workflow directory beside them"
         (both "no-workflow")
         (refused 1 (cannot-list (at "no-workflow" "workflows") "no such file or directory")))
   (list "workflows-second-literal"
         "a second workflow beside ci.yml writes the Chez floor in a step"
         (both "workflows-second-literal")
         (refused 1 (wrote (at "workflows-second-literal" "workflows/release.yml") 11 "Chez" "10.9.1"
                           (at "workflows-second-literal" "floors.sexp"))))
   (list "workflows-second-key"
         "a second workflow beside ci.yml has an env naming the Chez key"
         (both "workflows-second-key")
         (refused 1 (named (at "workflows-second-key" "workflows/release.yml") 7 "CHEZ_VERSION"
                           (at "workflows-second-key" "floors.sexp"))))
   (list "workflows-second-clean"
         "a second workflow beside ci.yml that writes no floor: both read, and both named"
         (both "workflows-second-clean")
         (holds (at "workflows-second-clean" "README.org") (at "workflows-second-clean" "workflows")
                "ci.yml, release.yml" (at "workflows-second-clean" "floors.sexp")
                "chez 10.9.1, libcurl 8.1.2, node 22.3"))
   (list "workflows-nested"
         "a file in a subdirectory of the workflows names the libcurl floor in a comment"
         (both "workflows-nested")
         (refused 1 (wrote (at "workflows-nested" "workflows/sub/notes.yml") 2 "libcurl" "8.1.2"
                           (at "workflows-nested" "floors.sexp"))))
   (list "workflows-dir-link"
         "a symbolic link to a directory among the workflows is not followed: it is a file that cannot be read"
         (both "workflows-dir-link")
         (refused 1 (string-append
                     (at "workflows-dir-link" "workflows/linked")
                     ": it cannot be read: Exception in get-string-all: failed on #<binary input port "
                     (at "workflows-dir-link" "workflows/linked") ">: is a directory")))))

;; ad hoc : (List String (Listof String) Expected)
;; Runs that need no directory of their own: no file exists, a bad floors file
;; with no README, a workflows argument that is a file, and the wrong number of
;; arguments.
(define ad-hoc
  (list
   (list "no file exists: all three named, the floors first, then the README, then the workflow directory"
         (list (at "legal" "none.sexp") (at "legal" "none.org") (at "legal" "none"))
         (refused 3 (cannot-read (at "legal" "none.sexp"))
                  (cannot-read (at "legal" "none.org"))
                  (cannot-list (at "legal" "none") "no such file or directory")))
   (list "a bad floors file, no README and no workflow directory: the floors problems, then the README, then the directory"
         (list (at "floors-invalid" "floors.sexp") (at "floors-invalid" "none.org")
               (at "floors-invalid" "none"))
         (refused 4
                  (string-append (at "floors-invalid" "floors.sexp") ": the key node is missing")
                  (string-append (at "floors-invalid" "floors.sexp")
                                 ": chez: the version \"10.9\" is not three dot-separated naturals, major.minor.patch")
                  (cannot-read (at "floors-invalid" "none.org"))
                  (cannot-list (at "floors-invalid" "none") "no such file or directory")))
   (list "a README with a problem and no workflow directory: both named, the README first"
         (list (at "legal" "floors.sexp") (at "no-section" "README.org") (at "legal" "none"))
         (refused 2
                  (string-append (at "no-section" "README.org") ": it has no \"** Requirements\" section")
                  (cannot-list (at "legal" "none") "no such file or directory")))
   (list "the workflows argument names ci.yml itself, a file: it cannot be read as a directory"
         (list (at "legal" "floors.sexp") (at "legal" "README.org") (at "legal" "workflows/ci.yml"))
         (refused 1 (cannot-list (at "legal" "workflows/ci.yml") "not a directory")))
   (list "no arguments: the usage line, exit 1" '() usage)
   (list "one argument: the usage line, exit 1" (list (at "legal" "floors.sexp")) usage)
   (list "two arguments: the usage line, exit 1"
         (list (at "legal" "floors.sexp") (at "legal" "README.org"))
         usage)
   (list "four arguments: the usage line, exit 1"
         (list (at "legal" "floors.sexp") (at "legal" "README.org") (at "legal" "workflows") "extra")
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

;; git keeps no empty directory, so the empty workflow directory is made here,
;; beside a floors file and a README that pass. Its path is the run's input,
;; so the expected answer is built from it; the answer itself is the program's.
(test-equal "an empty workflow directory: named, once, and nothing else"
  '(returned same)
  (outcome
   (lambda ()
     (call-with-temp-directory
      (lambda (dir)
        (let ((got (run (list (at "no-workflow" "floors.sexp") (at "no-workflow" "README.org") dir)))
              (want (refused 1 (string-append dir ": it holds no file, but must hold ci.yml,"
                                              " the workflow CI runs"))))
          (if (equal? got want) 'same (list 'got got 'want want))))))))

;; The program and the pure procedure agree on the fixtures: each answer above
;; comes from check-floors on the files' texts. A fixture the pure procedure
;; passes, but the program refuses, would be the program's own rule.
(test-equal "the legal fixture's files pass the pure procedure"
  '(returned ())
  (outcome (lambda ()
             (check-floors "f" (file-text (at "legal" "floors.sexp"))
                           "r" (file-text (at "legal" "README.org"))
                           "w" (list (list "w/ci.yml" (file-text (at "legal" "workflows/ci.yml"))))))))

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

;; --- the CI scripts ------------------------------------------------------------------
;;
;; Each script that reads the floors finds packaging/floors.sexp from its own
;; place, two directories up. So each row below runs the real scripts/ci from
;; a copy, in a fresh tree whose packaging/floors.sexp is the row's own. Where
;; a script would download a tarball, a curl that only names its URL, first on
;; the PATH, stands in. The rows run each script with sh, not by its own name,
;; so a lost execute bit is not what they find.

;; fake-curl : String
;; A curl that names the URL it was asked for, its last argument, and fails.
(define fake-curl "#!/bin/sh\nfor url; do :; done\necho \"$url\" >&2\nexit 7\n")

;; write-file : String String -> Unit
;; TEXT as the whole of the file at PATH, as UTF-8. The directory is there.
(define (write-file path text)
  (call-with-port (open-file-output-port path (file-options no-fail) (buffer-mode block)
                                         (make-transcoder (utf-8-codec)))
    (lambda (port) (put-string port text))))

;; checked : String (Listof String) -> Unit
;; Runs ARGV, which sets a row up and must exit 0 and print nothing.
(define (checked what argv)
  (let ((answer (capture-command argv)))
    (unless (equal? answer (list 0 "" ""))
      (error 'checked what answer))))

;; write-file-in : String String String -> Unit
;; TEXT as the file at DIR/NAME, with the directories above it made.
(define (write-file-in dir name text)
  (let* ((path (string-append dir "/" name))
         (slash (let loop ((i (- (string-length path) 1)))
                  (if (char=? (string-ref path i) #\/) i (loop (- i 1))))))
    (checked "mkdir" (list "mkdir" "-p" (substring path 0 slash)))
    (write-file path text)))

;; last-line : String -> String
;; The last line of TEXT, whose last character is a newline.
(define (last-line text)
  (let loop ((i (- (string-length text) 2)))
    (cond ((< i 0) (substring text 0 (- (string-length text) 1)))
          ((char=? (string-ref text i) #\newline)
           (substring text (+ i 1) (- (string-length text) 1)))
          (else (loop (- i 1))))))

;; with-tree : (U String #f) (Listof (Pair String String)) ((String) -> Any) -> Any
;; PROC on ROOT, a fresh directory holding a copy of the real scripts/ci, a
;; packaging/floors.sexp with FLOORS-TEXT (none when it is #f), and in shim/
;; each executable of SHIMS, a name and its text, after a curl that only
;; names its URL: a script that got as far as a download, by a fault, would
;; find that curl, not the network, first on the shimmed PATH.
(define (with-tree floors-text shims proc)
  (call-with-temp-directory
   (lambda (root)
     (checked "mkdir" (list "mkdir" "-p" (string-append root "/scripts")
                            (string-append root "/packaging") (string-append root "/shim")))
     (checked "cp" (list "cp" "-R" "scripts/ci" (string-append root "/scripts/ci")))
     (when floors-text
       (write-file (string-append root "/packaging/floors.sexp") floors-text))
     (for-each (lambda (shim)
                 (write-file-in root (string-append "shim/" (car shim)) (cdr shim))
                 (checked "chmod" (list "chmod" "+x" (string-append root "/shim/" (car shim)))))
               (cons (cons "curl" fake-curl) shims))
     (proc root))))

;; script : String String -> String
;; The path of the script NAME of scripts/ci in the tree at ROOT.
(define (script root name) (string-append root "/scripts/ci/" name))

;; shimmed : String -> String
;; The PATH assignment that puts the tree's shim/ first.
(define (shimmed root) (string-append "PATH=" root "/shim:" (getenv "PATH")))

;; tree-row : String (U String #f) (Listof (Pair String String))
;;            ((String) -> (Listof String)) (List Integer String String) -> Unit
;; The command ARGV-OF builds for the tree's root must answer EXPECTED: its
;; exit status, whole stdout and whole stderr.
(define (tree-row name floors-text shims argv-of expected)
  (test-equal (string-append "scripts: " name)
    (list 'returned expected)
    (outcome (lambda ()
               (with-tree floors-text shims
                 (lambda (root) (capture-command (argv-of root))))))))

;; sh-script : String String ... -> (String -> (Listof String))
;; sh running the script NAME with ARGS, the root's PATH shimmed.
(define (sh-script name . args)
  (lambda (root)
    (append (list "env" (shimmed root) "sh" (script root name)) args)))

;; sh-script-env : (Listof String) String String ... -> (String -> (Listof String))
;; The same, with the assignments ENV set first.
(define (sh-script-env env name . args)
  (lambda (root)
    (append (list "env" (shimmed root)) env (list "sh" (script root name)) args)))

;; --- floor.sh ------------------------------------------------------------------------

(define (floor-sh-row name floors-text args expected)
  (tree-row (string-append "floor.sh: " name) floors-text '()
            (apply sh-script "floor.sh" args) expected))

;; refused-floor : String ... -> (List 1 "" String)
(define (refused-floor . words)
  (list 1 "" (string-append "floor.sh: packaging/floors.sexp: " (apply string-append words) "\n")))

(define floor-usage (list 2 "" "usage: floor.sh chez|libcurl|node\n"))

(define not-one-list "it is not one list of (key \"version\") entries")

(floor-sh-row "the Chez floor" good '("chez") (list 0 "10.9.1\n" ""))
(floor-sh-row "the libcurl floor" good '("libcurl") (list 0 "8.1.2\n" ""))
(floor-sh-row "the Node floor" good '("node") (list 0 "22.3\n" ""))

(floor-sh-row "zero is a natural, and so is a number of several digits"
  (floors-of "\"0.0.0\"" "\"10.0.10\"" "\"0\"") '("libcurl") (list 0 "10.0.10\n" ""))

(floor-sh-row "a comment above, an entry's own line and after the datum holds an entry of the same name: it is no entry"
  (string-append ";; the old (libcurl \"7.0.0\")\n"
                 "((chez \"10.9.1\") ; and (libcurl \"7.1.0\")\n"
                 " (libcurl \"8.1.2\")\n"
                 " (node \"22.3\"))\n"
                 ";; (libcurl \"7.2.0\")\n")
  '("libcurl") (list 0 "8.1.2\n" ""))

(floor-sh-row "the datum spread over lines, with spaces inside it"
  "(\n  ( chez   \"10.9.1\" )\n\n(libcurl \"8.1.2\")\n (node\t\"22.3\"))"
  '("libcurl") (list 0 "8.1.2\n" ""))

(tree-row "floor.sh: the env cannot change it: the key CI once had is set, and the file's floor comes out"
          good '()
          (sh-script-env '("CHEZ_VERSION=1.2.3" "CURL_FLOOR_VERSION=4.5.6") "floor.sh" "libcurl")
          (list 0 "8.1.2\n" ""))

(floor-sh-row "no floors file" #f '("chez") (refused-floor "it cannot be read"))
(floor-sh-row "an empty file" "" '("chez") (refused-floor not-one-list))
(floor-sh-row "a file of comments only" ";; nothing here\n" '("chez") (refused-floor not-one-list))

(floor-sh-row "the key is missing"
  "((chez \"10.9.1\") (node \"22.3\"))" '("libcurl")
  (refused-floor "it holds no libcurl entry"))

(floor-sh-row "the key twice"
  "((chez \"10.9.1\") (chez \"10.9.2\") (libcurl \"8.1.2\") (node \"22.3\"))" '("chez")
  (refused-floor "it holds more than one chez entry"))

(floor-sh-row "the other floors are well-formed, and the one asked for is not"
  (floors-of good-chez "\"8.1\"" good-node) '("libcurl")
  (refused-floor "the libcurl version \"8.1\" is not three dot-separated naturals, major.minor.patch"))

(floor-sh-row "another floor's malformed version is not this floor's problem: check-floors names it"
  (floors-of good-chez "\"8.1\"" good-node) '("chez")
  (list 0 "10.9.1\n" ""))

(floor-sh-row "a version with a leading zero"
  (floors-of good-chez "\"08.1.2\"" good-node) '("libcurl")
  (refused-floor "the libcurl version \"08.1.2\" is not three dot-separated naturals, major.minor.patch"))

(floor-sh-row "a version with four numbers"
  (floors-of "\"10.9.1.1\"" good-libcurl good-node) '("chez")
  (refused-floor "the chez version \"10.9.1.1\" is not three dot-separated naturals, major.minor.patch"))

(floor-sh-row "a version with a letter"
  (floors-of good-chez "\"8.1.x\"" good-node) '("libcurl")
  (refused-floor "the libcurl version \"8.1.x\" is not three dot-separated naturals, major.minor.patch"))

(floor-sh-row "an empty version"
  (floors-of good-chez "\"\"" good-node) '("libcurl")
  (refused-floor "the libcurl version \"\" is not three dot-separated naturals, major.minor.patch"))

(floor-sh-row "an empty Node version"
  (floors-of good-chez good-libcurl "\"\"") '("node")
  (refused-floor "the node version \"\" is not dot-separated naturals"))

(floor-sh-row "a version that is a symbol, not a string"
  "((chez 10.9.1) (libcurl \"8.1.2\") (node \"22.3\"))" '("libcurl")
  (refused-floor not-one-list))

(floor-sh-row "a key in capitals"
  "((Chez \"10.9.1\") (libcurl \"8.1.2\") (node \"22.3\"))" '("libcurl")
  (refused-floor not-one-list))

(floor-sh-row "an entry of three elements"
  "((chez \"10.9.1\" \"x\") (libcurl \"8.1.2\") (node \"22.3\"))" '("libcurl")
  (refused-floor not-one-list))

(floor-sh-row "a second datum"
  (string-append good good) '("chez")
  (refused-floor not-one-list))

(floor-sh-row "text after the datum"
  (string-append good "(more)\n") '("chez")
  (refused-floor not-one-list))

(floor-sh-row "a datum comment, which the Scheme reader skips and this script does not read"
  (string-append "#;(chez \"9.5.8\")\n" good) '("chez")
  (refused-floor "it holds a # outside a ; comment, which this script does not read"))

(floor-sh-row "a block comment"
  (string-append "#| (chez \"9.5.8\") |#\n" good) '("chez")
  (refused-floor "it holds a # outside a ; comment, which this script does not read"))

(floor-sh-row "no name: the usage" good '() floor-usage)
(floor-sh-row "a name that is no floor: the usage" good '("python") floor-usage)
(floor-sh-row "two names: the usage" good '("chez" "libcurl") floor-usage)

;; --- the build scripts ----------------------------------------------------------------

;; The checked-in floors file, whose floors the build scripts must have a
;; pinned sum for: the rows that use it get as far as the download.
(define real-text (guard (e (#t "")) (file-text floors-path)))
(define real-chez (guard (e (#t "?")) (floor-text (parse-floors real-text) 'chez)))
(define real-curl (guard (e (#t "?")) (floor-text (parse-floors real-text) 'libcurl)))

(define unpinned (floors-of "\"9.9.9\"" "\"9.9.9\"" good-node))

(define (no-sum who what version)
  (list 1 ""
        (string-append who ": no sha256 is pinned for " what " " version
                       ": fetch its release tarball, check it, and add the sum to tarball_sha256 in this script\n")))

(define chez-usage (list 2 "" "usage: build-chez.sh PREFIX [--nothreads]\n"))
(define curl-usage (list 2 "" "usage: build-curl.sh [--current] PREFIX [EXTRA-CONFIGURE-FLAGS...]\n"))

;; current-curl : String
;; The current libcurl build-curl.sh --current pins, written out here
;; (ADR-0020): a change to it is a reviewed change, and shows in this diff.
(define current-curl "8.23.0")

(tree-row "build-curl.sh: the checked-in libcurl floor has a pinned sum: it reaches the download of its tarball"
          real-text '()
          (lambda (root) (list "env" (shimmed root) "sh" (script root "build-curl.sh") "/opt/curl"))
          (list 7 "" (string-append "https://curl.se/download/curl-" real-curl ".tar.xz\n")))

(tree-row "build-chez.sh: the checked-in Chez floor has a pinned sum: it reaches the download of its tarball"
          real-text '()
          (lambda (root) (list "env" (shimmed root) "sh" (script root "build-chez.sh") "/opt/chez"))
          (list 7 ""
                (string-append "https://github.com/cisco/ChezScheme/releases/download/v" real-chez
                               "/csv" real-chez ".tar.gz\n")))

(tree-row "build-chez.sh: --nothreads reaches the same download"
          real-text '()
          (lambda (root) (list "env" (shimmed root) "sh" (script root "build-chez.sh") "/opt/chez" "--nothreads"))
          (list 7 ""
                (string-append "https://github.com/cisco/ChezScheme/releases/download/v" real-chez
                               "/csv" real-chez ".tar.gz\n")))

(tree-row "build-curl.sh: a libcurl floor with no pinned sum fails, naming it"
          unpinned '()
          (lambda (root) (list "env" (shimmed root) "sh" (script root "build-curl.sh") "/opt/curl"))
          (no-sum "build-curl.sh" "curl" "9.9.9"))

(tree-row "build-chez.sh: a Chez floor with no pinned sum fails, naming it"
          unpinned '()
          (lambda (root) (list "env" (shimmed root) "sh" (script root "build-chez.sh") "/opt/chez"))
          (no-sum "build-chez.sh" "Chez" "9.9.9"))

(tree-row "build-curl.sh: the env cannot select a version with a sum: the file's floor has none, and fails"
          unpinned '()
          (sh-script-env (list "CURL_FLOOR_VERSION=7.85.0" "CHEZ_VERSION=10.4.0" "version=7.85.0")
                         "build-curl.sh" "/opt/curl")
          (no-sum "build-curl.sh" "curl" "9.9.9"))

(tree-row "build-chez.sh: the env cannot select a version with a sum: the file's floor has none, and fails"
          unpinned '()
          (sh-script-env (list "CURL_FLOOR_VERSION=7.85.0" "CHEZ_VERSION=10.4.0" "version=10.4.0")
                         "build-chez.sh" "/opt/chez")
          (no-sum "build-chez.sh" "Chez" "9.9.9"))

(tree-row "build-curl.sh: a malformed libcurl floor fails closed, before any download"
          (floors-of good-chez "\"7.85\"" good-node) '()
          (sh-script "build-curl.sh" "/opt/curl")
          (list 1 ""
                (string-append
                 "floor.sh: packaging/floors.sexp: the libcurl version \"7.85\" is not three dot-separated naturals, major.minor.patch\n"
                 "build-curl.sh: no libcurl floor to build\n")))

(tree-row "build-chez.sh: a Chez floor written twice fails closed, before any download"
          "((chez \"10.4.0\") (chez \"10.4.0\") (libcurl \"7.85.0\") (node \"20\"))"
          '()
          (sh-script "build-chez.sh" "/opt/chez")
          (list 1 ""
                (string-append
                 "floor.sh: packaging/floors.sexp: it holds more than one chez entry\n"
                 "build-chez.sh: no Chez floor to build\n")))

(tree-row "build-curl.sh: no floors file fails closed, before any download"
          #f '()
          (sh-script "build-curl.sh" "/opt/curl")
          (list 1 ""
                (string-append "floor.sh: packaging/floors.sexp: it cannot be read\n"
                               "build-curl.sh: no libcurl floor to build\n")))

(tree-row "build-curl.sh: a version where the prefix goes, as the old calls gave one, is no absolute prefix"
          real-text '() (sh-script "build-curl.sh" "7.85.0" "/opt/curl")
          (list 2 "" "build-curl.sh: PREFIX must be an absolute path, not '7.85.0'\n"))

(tree-row "build-chez.sh: a version and a prefix, as the old calls gave, is the usage"
          real-text '() (sh-script "build-chez.sh" "10.4.0" "/opt/chez")
          chez-usage)

(tree-row "build-chez.sh: no prefix is the usage" real-text '() (sh-script "build-chez.sh") chez-usage)
(tree-row "build-chez.sh: a flag but --nothreads is the usage" real-text '()
          (sh-script "build-chez.sh" "/opt/chez" "--threads") chez-usage)
(tree-row "build-chez.sh: a relative prefix is refused" real-text '()
          (sh-script "build-chez.sh" "chez")
          (list 2 "" "build-chez.sh: PREFIX must be an absolute path, not 'chez'\n"))
(tree-row "build-curl.sh: no prefix is the usage" real-text '() (sh-script "build-curl.sh") curl-usage)

;; --current builds the one other version the script pins, which is no floor
;; (ADR-0020): it reaches its tarball's download whatever the floors file
;; holds, or with none, and no environment variable moves it.
(tree-row "build-curl.sh: --current has a pinned sum: it reaches the download of the current libcurl's tarball, not the floor's"
          real-text '()
          (lambda (root) (list "env" (shimmed root) "sh" (script root "build-curl.sh") "--current" "/opt/curl"))
          (list 7 "" (string-append "https://curl.se/download/curl-" current-curl ".tar.xz\n")))
(tree-row "build-curl.sh: --current reads no floors file: with none, it reaches the same download"
          #f '()
          (lambda (root) (list "env" (shimmed root) "sh" (script root "build-curl.sh") "--current" "/opt/curl"))
          (list 7 "" (string-append "https://curl.se/download/curl-" current-curl ".tar.xz\n")))
(tree-row "build-curl.sh: --current with a floor that has no sum still reaches its own download"
          unpinned '()
          (lambda (root) (list "env" (shimmed root) "sh" (script root "build-curl.sh") "--current" "/opt/curl"))
          (list 7 "" (string-append "https://curl.se/download/curl-" current-curl ".tar.xz\n")))
(tree-row "build-curl.sh: the env cannot move --current's version: current_version, version and CURL_FLOOR_VERSION set to the floor change nothing"
          real-text '()
          (lambda (root) (list "env" (shimmed root) "current_version=7.85.0" "version=7.85.0"
                               "CURL_FLOOR_VERSION=7.85.0" "sh" (script root "build-curl.sh") "--current" "/opt/curl"))
          (list 7 "" (string-append "https://curl.se/download/curl-" current-curl ".tar.xz\n")))
(tree-row "build-curl.sh: --current with no prefix is the usage" real-text '()
          (sh-script "build-curl.sh" "--current") curl-usage)
(tree-row "build-curl.sh: --current with a relative prefix is refused" real-text '()
          (sh-script "build-curl.sh" "--current" "curl")
          (list 2 "" "build-curl.sh: PREFIX must be an absolute path, not 'curl'\n"))
(tree-row "build-curl.sh: --current after the prefix is no flag of the script's: it goes to ./configure, after the floor's download"
          real-text '()
          (lambda (root) (list "env" (shimmed root) "sh" (script root "build-curl.sh") "/opt/curl" "--current"))
          (list 7 "" (string-append "https://curl.se/download/curl-" real-curl ".tar.xz\n")))

;; --- expect-missing-api.sh ------------------------------------------------------------

;; refusal : String -> String
;; The refusal block preflight prints for a libcurl missing the header API, at VERSION.
(define (refusal version)
  (string-append "chez-curl: libcurl refused\n"
                 "(reason . missing-api)\n"
                 "  path:       /lib/libcurl.so.4\n"
                 "  source:     override\n"
                 "  detail:     curl_easy_header\n"
                 "  version:    " version "\n"
                 "  TLS:        fake\n"))

;; a make that prints a refusal at VERSION and fails, as make build does
(define (fake-make version)
  (string-append "#!/bin/sh\ncat <<'EOF'\n" (refusal version) "EOF\nexit 2\n"))

(define (missing-api-argv env)
  (lambda (root)
    (append (list "env" (shimmed root) "CHEZ_CURL_LIBCURL=/lib/libcurl.so.4") env
            (list "sh" (script root "expect-missing-api.sh") "curl_easy_header"))))

(tree-row "expect-missing-api.sh: the version it requires is the libcurl floor of the file"
          good (list (cons "make" (fake-make "8.1.2")))
          (missing-api-argv '())
          (list 0
                (string-append (refusal "8.1.2")
                               "expect-missing-api: make build exited 2, refusing /lib/libcurl.so.4 at 8.1.2 as missing-api, naming curl_easy_header\n")
                ""))

;; The diff in a failure holds the names of temporary files, so the row
;; compares the status, the verdict that closes the output, and stderr.
(define (verdict-row name floors-text shim-make env)
  (test-equal (string-append "scripts: expect-missing-api.sh: " name)
    '(returned (1 "::error::expect-missing-api: make build exited 2, but did not refuse /lib/libcurl.so.4 at 8.1.2 as missing-api, naming curl_easy_header: the diff above runs from what must be printed to what was" ""))
    (outcome (lambda ()
               (with-tree floors-text (list (cons "make" shim-make))
                 (lambda (root)
                   (let ((answer (capture-command ((missing-api-argv env) root))))
                     (list (car answer) (last-line (cadr answer)) (caddr answer)))))))))

(verdict-row "a refusal at another version than the file's libcurl floor fails"
             good (fake-make "7.85.0") '())

(verdict-row "the env cannot name the version: CURL_FLOOR_VERSION is not read"
             good (fake-make "7.85.0") '("CURL_FLOOR_VERSION=7.85.0"))

;; --- check-action-pins.sh ------------------------------------------------------------

(define pin-sha "3d3c42e5aac5ba805825da76410c181273ba90b1")

;; pinned : String -> String
;; A canonical step line for ACTION.
(define (pinned action tag) (string-append "      - uses: " action "@" pin-sha " # " tag))

;; steps : String ... -> String
;; A workflow whose first job's steps are LINES. Its first is line 4.
(define (steps . lines) (apply workflow "jobs:" "  main:" "    steps:" lines))

(define the-pinned (pinned "actions/checkout" "v7.0.1"))

;; pin-row : String (Listof (Pair String String)) (String -> (List Integer String String)) -> Unit
;; check-action-pins.sh on a fresh directory holding FILES, a name and its
;; text, answers what EXPECTED-OF gives for the directory's path.
(define (pin-row name files expected-of)
  (test-equal (string-append "pins: " name)
    '(returned same)
    (outcome
     (lambda ()
       (call-with-temp-directory
        (lambda (dir)
          (for-each (lambda (file) (write-file-in dir (car file) (cdr file))) files)
          (let ((got (capture-command (list "sh" "scripts/ci/check-action-pins.sh" dir)))
                (want (expected-of dir)))
            (if (equal? got want) 'same (list 'got got 'want want)))))))))

(define (pins-pass n)
  (lambda (dir)
    (list 0
          (string-append "check-action-pins: all " (number->string n) " lines with a uses key under "
                         dir " name a full commit SHA, with its tag in a comment\n")
          "")))

;; pins-fail : Natural Natural (Listof (Pair String (Pair Natural String))) -> (String -> Answer)
;; BAD is each line at fault, as its file, number and text; BAD-COUNT and
;; TOTAL are given, not counted.
(define (pins-fail bad-count total . bad)
  (lambda (dir)
    (list 1 ""
          (string-append
           (apply string-append
                  (map (lambda (b)
                         (string-append "check-action-pins: " dir "/" (car b) ":"
                                        (number->string (cadr b)) ":" (cddr b) "\n"))
                       bad))
           "check-action-pins: " (number->string bad-count) " of " (number->string total)
           " lines with a uses key are not \"uses: OWNER/REPO@<40 hex digits> # vTAG\", after an optional \"- \"\n"))))

(define (pins-error text)
  (lambda (dir) (list 1 "" (string-append "check-action-pins: " (text dir) "\n"))))

(pin-row "canonical lines: a step's first key, a later key, a path action and a reusable workflow"
         (list (cons "ci.yml"
                     (steps the-pinned
                            (string-append "        uses: actions/cache/restore@" pin-sha " # v6.1.0")
                            (string-append "    uses: owner/repo/.github/workflows/x.yml@" pin-sha " # v1"))))
         (pins-pass 3))

(pin-row "a comment, a value and a word that only end in uses are no uses key"
         (list (cons "ci.yml"
                     (steps the-pinned
                            "      # uses: actions/checkout@v4"
                            "      - name: Report the versions this run uses"
                            "      - run: echo reuses: x")))
         (pins-pass 1))

;; bad-line : String String -> Unit
;; A workflow with the canonical line and then LINE, which is line 5.
(define (bad-line name line)
  (pin-row name
           (list (cons "ci.yml" (steps the-pinned line)))
           (pins-fail 1 2 (cons "ci.yml" (cons 5 line)))))

(bad-line "a tag" "      - uses: actions/checkout@v4")
(bad-line "a branch" "      - uses: actions/checkout@main")
(bad-line "a short commit" (string-append "      - uses: actions/checkout@3d3c42e # v7.0.1"))
(bad-line "a commit with no tag comment" (string-append "      - uses: actions/checkout@" pin-sha))
(bad-line "a comment that is no tag" (string-append "      - uses: actions/checkout@" pin-sha " # latest"))
(bad-line "more after the tag" (string-append "      - uses: actions/checkout@" pin-sha " # v7.0.1 and more"))
(bad-line "a uses key after other text on the line, in a trailing comment: it fails closed"
          (string-append "      - name: checkout # uses: actions/checkout@" pin-sha " # v7.0.1"))
(bad-line "a local action" "      - uses: ./.github/actions/setup")
(bad-line "a docker image" "      - uses: docker://alpine:3.20")
(bad-line "a quoted value" (string-append "      - uses: \"actions/checkout@" pin-sha "\" # v7.0.1"))
(bad-line "a flow mapping, though its commit is pinned"
          (string-append "      - {uses: actions/checkout@" pin-sha ", with: {submodules: true}} # v7.0.1"))
(bad-line "a flow mapping on a tag" "      - {uses: actions/checkout@v4, with: {submodules: true}}")
(bad-line "a flow sequence of mappings" "    steps: [{uses: actions/checkout@v4}]")
(bad-line "a later key of a flow mapping, after a comma" "      - {name: x,uses: actions/checkout@v4}")
(bad-line "a double-quoted key" "      - \"uses\": actions/checkout@v4")
(bad-line "a double-quoted key, though its commit is pinned"
          (string-append "      - \"uses\": actions/checkout@" pin-sha " # v7.0.1"))
(bad-line "a single-quoted key" "      - 'uses': actions/checkout@v4")
(bad-line "a space before the colon" "      - uses : actions/checkout@v4")
(bad-line "a space before the colon, though its commit is pinned"
          (string-append "      - uses : actions/checkout@" pin-sha " # v7.0.1"))
(bad-line "a key in a nested sequence" (string-append "      - - uses: actions/checkout@" pin-sha " # v7.0.1"))
(bad-line "a key with its value on the next line" "      - uses:")

(pin-row "every file is read, subdirectories too, and each line at fault is named by its own file, in path order"
         (list (cons "ci.yml" (steps the-pinned "      - uses: actions/checkout@v4"))
               (cons "sub/b.yml" (steps "      - uses: actions/cache@abc # v6" the-pinned)))
         (pins-fail 2 4
                    (cons "ci.yml" (cons 5 "      - uses: actions/checkout@v4"))
                    (cons "sub/b.yml" (cons 4 "      - uses: actions/cache@abc # v6"))))

(pin-row "a directory with no file: nothing was checked"
         '() (pins-error (lambda (dir) (string-append dir " holds no file"))))

(pin-row "no file has a uses key: nothing was checked"
         (list (cons "ci.yml" (workflow "name: CI" "on: push")))
         (pins-error (lambda (dir)
                       (string-append "no file under " dir " has a line with a uses key, so nothing was checked"))))

(pin-row "a uses key only in a comment: nothing was checked"
         (list (cons "ci.yml" (workflow "# uses: actions/checkout@v4")))
         (pins-error (lambda (dir)
                       (string-append "no file under " dir " has a line with a uses key, so nothing was checked"))))

(test-equal "pins: a path that is no directory"
  '(returned same)
  (outcome
   (lambda ()
     (call-with-temp-directory
      (lambda (dir)
        (let ((got (capture-command (list "sh" "scripts/ci/check-action-pins.sh" (string-append dir "/none"))))
              (want (list 1 "" (string-append "check-action-pins: " dir "/none is not a directory\n"))))
          (if (equal? got want) 'same (list 'got got 'want want))))))))

(test-equal "pins: no directory named: the usage"
  '(returned (2 "" "usage: check-action-pins.sh DIR\n"))
  (outcome (lambda () (capture-command (list "sh" "scripts/ci/check-action-pins.sh")))))

(test-end "check-floors")

(exit (suite-exit-status runner))
