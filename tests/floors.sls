#!r6rs
;;; (floors): chez-curl's version floors, and the check that holds the rest of
;;; the tree to them (harness plan, section 3, item 5).
;;;
;;; packaging/floors.sexp is the one file that writes the Chez, libcurl and
;;; Node floors: one datum, ((chez "M.m.p") (libcurl "M.m.p") (node "M")),
;;; the keys exactly these, in this order. README.org's Requirements section
;;; states the floors for a reader, and CI states none: the scripts that build
;;; Chez and libcurl at their floors read them from the file themselves
;;; (scripts/ci/floor.sh), and no line of any file in CI's workflow directory
;;; may contain either floor's version text, or name the two env keys the
;;; workflow once held them in; `make check-floors` holds both to the file. The
;;; Scheme code that enforces a floor is held to it by behaviour, in
;;; tests/test-verify.sps and tests/test-require-threaded.sps, which read the
;;; floors from here. Some comments, and the literal rows of
;;; tests/test-library-loading.sps, still name a floor: those rows fail by
;;; name when it changes, and the comments are not checked.
;;;
;;;   floors-problems   what is wrong with the floors file's text
;;;   check-floors      what is wrong with the floors file, the README or the
;;;                     workflows
;;;   workflows-problems what is wrong with the workflow directory's files
;;;   ci-workflow       the workflow, by name, that the directory must hold
;;;   parse-floors      the floors file's text as a Floors, or a raise
;;;   read-floors       the checked-in floors file as a Floors
;;;   floor-text        a floor by name, as text
;;;   floor-numbers     a floor by name, as a list of naturals
;;;   requirement-lines the README lines the floors call for
;;;
;;; A Floors is the file's datum itself: ((chez "10.4.0") (libcurl "7.85.0")
;;; (node "20")). Test-only: it lives in tests/, which make test puts on
;;; Chez's library path, and it imports only (rnrs) and a few of Chez's own
;;; bindings, so `make check-floors` needs no deps. Its own suite is
;;; tests/test-check-floors.sps.
;;;
;;; The checks never evaluate the file: its text is read as data, with Chez's
;;; reader, and every problem comes back as a line of text that starts with
;;; the path of the file at fault, so a failure names what to edit.
;;;
;;; What the floors file must be:
;;;
;;;   - one datum, a list of entries, each (key "version"), a symbol and a
;;;     string, and nothing else but comments;
;;;   - the keys chez, libcurl and node, each once, in that order;
;;;   - each version a string of dot-separated naturals, written without
;;;     a sign, a space or a leading zero: chez and libcurl three of them
;;;     (major.minor.patch, as the code compares them: Chez's
;;;     scheme-version-number, and curl_version_info's version_num), node one
;;;     or more.
;;;
;;; What the README must hold: one line "** Requirements", and under it, up to
;;; the next heading of any level, the list lines requirement-lines gives,
;;; whole, as one list, in order. A list line is one that starts, after any
;;; indent, with "- " or "+ ", or a number and "." or ")" and a space, or, when
;;; indented, "* ". Prose and blank lines between them are not compared.
;;; Lists under other headings are not compared either. The comparison is
;;; exact, a space at a line's end included: each line is named as written.
;;;
;;; What the workflows must be. CI states no floor: scripts/ci/build-chez.sh
;;; and build-curl.sh take no version, and read theirs from the floors file, so
;;; nothing a workflow says, an env value or a matrix value, changes what they
;;; build. Every file under the workflow directory is held, in subdirectories
;;; too, so a second workflow cannot say one unseen. The directory must hold a
;;; file, and ci.yml, directly in it. And no line of any file there may
;;; contain, as text:
;;;
;;;   - the Chez floor's version, or the libcurl floor's, with the versions the
;;;     floors file gives, whatever the line is: a step, a cache key, a comment;
;;;   - CHEZ_VERSION or CURL_FLOOR_VERSION, the two env keys CI held the floors
;;;     in before the build scripts read them, so a job- or step-level env that
;;;     redefines one fails, whatever version it gives, and so does a reference
;;;     to one, ${{ env.CHEZ_VERSION }} or $CHEZ_VERSION.
;;;
;;;   - node-version in any case, anywhere, but in the one form that takes the
;;;     version from a step's output, which a step fills from
;;;     scripts/ci/floor.sh node:
;;;
;;;       node-version: ${{ steps.ID.outputs.NAME }}
;;;
;;;     with any indent, an optional "- " before it, and nothing after it.
;;;     GitHub reads a step's input keys ignoring case, so Node-Version is the
;;;     same key. So a literal fails, whatever version it gives, and so do an
;;;     expression from anywhere else (env, matrix), the key in another case,
;;;     a quoted key, a flow mapping, a comment after it, node-version-file,
;;;     and the word in a comment;
;;;   - anything that would let YAML or GitHub read a key other than as it is
;;;     written, since this check reads text, line by line, and fails closed:
;;;     - a backslash after a double quote, in a key or a value, closed or
;;;       not: YAML reads escapes there ("node\x2Dversion" is node-version),
;;;       and a quoted key may go on over lines;
;;;     - an explicit key, ? where a key goes, whose colon may be on the next
;;;       line;
;;;     - an alias or an anchor where a key goes: *, or &, then a letter,
;;;       digit, _ or -. Narrowed so: a shell case pattern *) and a && in a
;;;       run block are no alias, and ci.yml holds the first;
;;;     - any character beyond ASCII: GitHub folds keys' case beyond it (long
;;;       s is S, dotless i is I);
;;;     - a tab, which YAML may read as white space before a key's colon.
;;;     "Where a key goes" is after the indent and any "- ", or after {, [ or
;;;     , and any spaces.
;;;
;;; The text is searched, not parsed as YAML, so a version inside a longer
;;; number is also the floor's text, and a key inside a longer name is also the
;;; key's. A value that is no floor's text, as a matrix of other versions, is
;;; not seen here: nothing reads it. The Node floor's version text is not
;;; held: a node-version line cannot write it, and nothing else reads it.
(library (floors)
  (export floors-path check-floors floors-problems parse-floors read-floors file-text
          floor-text floor-numbers requirement-lines workflows-problems ci-workflow)
  (import (rnrs)
          (only (chezscheme) display-condition parameterize print-graph))

  ;; floors-path : String
  ;; The checked-in floors file, from the repository root.
  (define floors-path "packaging/floors.sexp")

  ;; section-heading : String
  ;; The README line that opens the section holding the floors.
  (define section-heading "** Requirements")

  ;; required-keys : (Listof Symbol)
  ;; The keys the floors file holds, in order.
  (define required-keys '(chez libcurl node))

  ;; version-shapes : (Listof (List Symbol (U Natural #f) String))
  ;; For each key, how many numbers its version has, #f for one or more, and
  ;; how the messages describe the version.
  (define version-shapes
    '((chez 3 "three dot-separated naturals, major.minor.patch")
      (libcurl 3 "three dot-separated naturals, major.minor.patch")
      (node #f "dot-separated naturals")))

  ;; --- small helpers --------------------------------------------------------

  ;; written : Any -> String
  ;; print-graph makes write label a cyclic datum, #0=(a . #0#), where it
  ;; would not stop.
  (define (written datum)
    (call-with-string-output-port
      (lambda (p) (parameterize ((print-graph #t)) (write datum p)))))

  ;; abbreviated : Any -> String
  ;; DATUM written, cut to 57 characters and three dots when over 60.
  (define (abbreviated datum)
    (let ((text (written datum)))
      (if (> (string-length text) 60)
          (string-append (substring text 0 57) "...")
          text)))

  ;; describe : Any -> String
  (define (describe obj)
    (call-with-string-output-port
      (lambda (p) (if (condition? obj) (display-condition obj p) (write obj p)))))

  ;; joined : String (Listof String) -> String
  (define (joined separator strings)
    (if (null? strings)
        ""
        (fold-left (lambda (text s) (string-append text separator s))
                   (car strings)
                   (cdr strings))))

  ;; split : String Char -> (Listof String)
  ;; TEXT cut at each SEPARATOR, which is dropped: always one piece or more,
  ;; and an empty one between two separators.
  (define (split text separator)
    (let loop ((chars (string->list text)) (current '()) (found '()))
      (cond ((null? chars)
             (reverse (cons (list->string (reverse current)) found)))
            ((char=? (car chars) separator)
             (loop (cdr chars) '() (cons (list->string (reverse current)) found)))
            (else (loop (cdr chars) (cons (car chars) current) found)))))

  ;; prefix? : String String -> Boolean
  (define (prefix? prefix s)
    (let ((n (string-length prefix)))
      (and (>= (string-length s) n)
           (string=? (substring s 0 n) prefix))))

  ;; unique : (Listof Any) -> (Listof Any)
  ;; Each element once, in the order of its first appearance.
  (define (unique items)
    (reverse
     (fold-left (lambda (found item) (if (member item found) found (cons item found)))
                '()
                items)))

  ;; occurrences : Any (Listof Any) -> Natural
  (define (occurrences item items)
    (length (filter (lambda (other) (equal? other item)) items)))

  ;; remove-first : Any (Listof Any) -> (Listof Any)
  ;; ITEMS without its first element equal to ITEM.
  (define (remove-first item items)
    (cond ((null? items) '())
          ((equal? (car items) item) (cdr items))
          (else (cons (car items) (remove-first item (cdr items))))))

  ;; multiset-minus : (Listof Any) (Listof Any) -> (Listof Any)
  ;; The elements of A that B does not account for, in order: each element of
  ;; B cancels one equal element of A.
  (define (multiset-minus a b)
    (let loop ((a a) (b b) (kept '()))
      (cond ((null? a) (reverse kept))
            ((member (car a) b) (loop (cdr a) (remove-first (car a) b) kept))
            (else (loop (cdr a) b (cons (car a) kept))))))

  ;; --- the floors file ------------------------------------------------------

  ;; read-data : String -> (U (List 'data (Listof Any)) (List 'unreadable String))
  ;; Every datum in TEXT, read with Chez's reader.
  (define (read-data text)
    (guard (e (#t (list 'unreadable (describe e))))
      (let ((port (open-string-input-port text)))
        (let loop ((found '()))
          (let ((datum (read port)))
            (cond ((not (eof-object? datum)) (loop (cons datum found)))
                  ((port-eof? port) (list 'data (reverse found)))
                  (else (error 'read "an #!eof literal ends the reading before the end of the file"))))))))

  ;; natural-text? : String -> Boolean
  ;; One or more ASCII digits and no leading zero, but for "0" itself.
  (define (natural-text? s)
    (and (positive? (string-length s))
         (for-all (lambda (c) (and (char>=? c #\0) (char<=? c #\9))) (string->list s))
         (or (string=? s "0") (not (char=? (string-ref s 0) #\0)))))

  ;; version-numbers : Any -> (U (Listof Natural) #f)
  ;; The numbers in the version text VERSION, #f when it is no string of
  ;; dot-separated naturals.
  (define (version-numbers version)
    (and (string? version)
         (let ((parts (split version #\.)))
           (and (for-all natural-text? parts)
                (map string->number parts)))))

  ;; entry? : Any -> Boolean
  ;; (key version): a list of two, the first a symbol.
  (define (entry? x)
    (and (list? x) (= (length x) 2) (symbol? (car x))))

  ;; key-problems : String (Listof Symbol) -> (Listof String)
  ;; What is wrong with KEYS, in order: the required keys missing, the keys that
  ;; are not required, the required keys that come more than once, and only
  ;; when none of those, the order.
  (define (key-problems path keys)
    (let ((missing (remp (lambda (key) (memq key keys)) required-keys))
          (extra (unique (remp (lambda (key) (memq key required-keys)) keys)))
          (repeated (unique (filter (lambda (key)
                                      (and (memq key required-keys)
                                           (> (occurrences key keys) 1)))
                                    keys))))
      (append
       (map (lambda (key)
              (string-append path ": the key " (symbol->string key) " is missing"))
            missing)
       (map (lambda (key)
              (string-append path ": the key " (symbol->string key)
                             " is extra: the keys are "
                             (joined ", " (map symbol->string required-keys))))
            extra)
       (map (lambda (key)
              (string-append path ": the key " (symbol->string key) " appears "
                             (number->string (occurrences key keys)) " times"))
            repeated)
       (if (and (null? missing) (null? extra) (null? repeated)
                (not (equal? keys required-keys)))
           (list (string-append path ": the keys are in the order "
                                (joined ", " (map symbol->string keys))
                                ", but must be "
                                (joined ", " (map symbol->string required-keys))))
           '()))))

  ;; version-problems : String Symbol Any -> (Listof String)
  ;; What is wrong with VERSION as the version of KEY. A key that is not
  ;; required has no shape to hold: key-problems names it.
  (define (version-problems path key version)
    (let ((shape (assq key version-shapes))
          (numbers (version-numbers version)))
      (cond ((not shape) '())
            ((and numbers (or (not (cadr shape)) (= (length numbers) (cadr shape)))) '())
            (else
             (list (string-append path ": " (symbol->string key) ": the version "
                                  (abbreviated version) " is not " (caddr shape)))))))

  ;; datum-problems : String Any -> (Listof String)
  ;; What is wrong with DATUM, the one datum of the floors file at PATH: its
  ;; entries, then its keys, then its versions, in the order of the entries.
  (define (datum-problems path datum)
    (if (not (list? datum))
        (list (string-append path ": the datum is " (abbreviated datum)
                             ", not a list of (key \"version\") entries"))
        (let ((entries (filter entry? datum)))
          (append
           (map (lambda (x)
                  (string-append path ": " (abbreviated x)
                                 " is not an entry (key \"version\")"))
                (remp entry? datum))
           (key-problems path (map car entries))
           (apply append
                  (map (lambda (entry) (version-problems path (car entry) (cadr entry)))
                       entries))))))

  ;; floors-problems : String String -> (Listof String)
  ;; What is wrong with TEXT as the text of the floors file at PATH. Empty
  ;; when the file is right.
  (define (floors-problems path text)
    (let ((found (read-data text)))
      (if (eq? (car found) 'unreadable)
          (list (string-append path ": it cannot be read as data: " (cadr found)))
          (let ((data (cadr found)))
            (cond ((null? data)
                   (list (string-append path ": it holds no datum, but must hold exactly one")))
                  ((pair? (cdr data))
                   (list (string-append path ": it holds " (number->string (length data))
                                        " data, but must hold exactly one")))
                  (else (datum-problems path (car data))))))))

  ;; parse-floors : String -> Floors
  ;; The datum of TEXT, the text of a floors file. It raises, naming each
  ;; problem, unless floors-problems finds none.
  (define (parse-floors text)
    (let ((problems (floors-problems floors-path text)))
      (if (null? problems)
          (car (cadr (read-data text)))
          (assertion-violation 'parse-floors (joined "; " problems)))))

  ;; file-text : String -> String
  ;; The text of the file at PATH, read as UTF-8. It raises when it cannot.
  (define (file-text path)
    (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                          (make-transcoder (utf-8-codec)))
      get-string-all))

  ;; read-floors : -> Floors
  ;; The checked-in floors file, floors-path, from the working directory, which
  ;; is the repository root under make. It raises when it cannot be read, or
  ;; parse-floors refuses it.
  (define (read-floors)
    (parse-floors (file-text floors-path)))

  ;; floor-text : Floors Symbol -> String
  ;; The floor named NAME, as the file writes it: "10.4.0".
  (define (floor-text floors name)
    (let ((entry (assq name floors)))
      (if entry
          (cadr entry)
          (assertion-violation 'floor-text "no such floor" name))))

  ;; floor-numbers : Floors Symbol -> (Listof Natural)
  ;; The floor named NAME, as its numbers: (10 4 0).
  (define (floor-numbers floors name)
    (let ((entry (assq name floors)))
      (if entry
          (map string->number (split (cadr entry) #\.))
          (assertion-violation 'floor-numbers "no such floor" name))))

  ;; --- the README -----------------------------------------------------------

  ;; requirement-lines : Floors -> (Listof String)
  ;; The list lines the README's Requirements section holds: the Chez, libcurl
  ;; and Node floors, in that order.
  (define (requirement-lines floors)
    (list (string-append "- Chez Scheme " (floor-text floors 'chez)
                         " or later, built with threads")
          (string-append "- libcurl " (floor-text floors 'libcurl)
                         " or later, built with TLS")
          (string-append "- Node.js " (floor-text floors 'node)
                         " or later, for the tests")))

  ;; heading? : String -> Boolean
  ;; An org heading: one star or more at the start of the line, then a space.
  (define (heading? line)
    (let loop ((i 0))
      (cond ((= i (string-length line)) #f)
            ((char=? (string-ref line i) #\*) (loop (+ i 1)))
            (else (and (> i 0) (char=? (string-ref line i) #\space))))))

  ;; numbered? : String -> Boolean
  ;; Digits, then "." or ")", then a space, at the start of LINE.
  (define (numbered? line)
    (let loop ((i 0))
      (cond ((= i (string-length line)) #f)
            ((and (char>=? (string-ref line i) #\0) (char<=? (string-ref line i) #\9))
             (loop (+ i 1)))
            (else (and (> i 0)
                       (< (+ i 1) (string-length line))
                       (memv (string-ref line i) '(#\. #\)))
                       (char=? (string-ref line (+ i 1)) #\space)
                       #t)))))

  ;; list-line? : String -> Boolean
  ;; Whether LINE is an item of an org list: "- ", "+ ", a number and "." or
  ;; ")", or, indented, "* ", after any indent.
  (define (list-line? line)
    (let* ((n (string-length line))
           (start (let skip ((i 0))
                    (if (and (< i n) (memv (string-ref line i) '(#\space #\tab)))
                        (skip (+ i 1))
                        i)))
           (rest (substring line start n)))
      (or (prefix? "- " rest)
          (prefix? "+ " rest)
          (numbered? rest)
          (and (> start 0) (prefix? "* " rest)))))

  ;; sections : (Listof String) -> (Listof (Listof String))
  ;; The lines of each section opened by section-heading, up to the next
  ;; heading of any level, the heading itself left out.
  (define (sections lines)
    (let loop ((rest lines) (open? #f) (current '()) (found '()))
      (let ((closed (if open? (cons (reverse current) found) found)))
        (cond ((null? rest) (reverse closed))
              ((string=? (car rest) section-heading) (loop (cdr rest) #t '() closed))
              ((heading? (car rest)) (loop (cdr rest) #f '() closed))
              (open? (loop (cdr rest) #t (cons (car rest) current) found))
              (else (loop (cdr rest) #f '() found))))))

  ;; list-problems : String String (Listof String) (Listof String) -> (Listof String)
  ;; What is wrong with the list lines FOUND in the README at RPATH, against
  ;; the EXPECTED ones the floors file at FPATH calls for. With as many lines
  ;; as expected, each line that is not the one expected at its place, which
  ;; covers a changed line and a changed order. With more or fewer, each
  ;; extra line, then each line that is missing.
  (define (list-problems rpath fpath found expected)
    (cond
      ((equal? found expected) '())
      ((= (length found) (length expected))
       (let loop ((i 1) (f found) (e expected))
         (cond ((null? f) '())
               ((string=? (car f) (car e)) (loop (+ i 1) (cdr f) (cdr e)))
               (else
                (cons (string-append rpath ": list line " (number->string i)
                                     " under " (written section-heading) " is "
                                     (written (car f)) ", but " fpath " gives "
                                     (written (car e)))
                      (loop (+ i 1) (cdr f) (cdr e)))))))
      (else
       (append
        (map (lambda (line)
               (string-append rpath ": " (written section-heading)
                              " has an extra list line, " (written line)
                              ", which " fpath " does not give"))
             (multiset-minus found expected))
        (map (lambda (line)
               (string-append rpath ": " (written section-heading)
                              " lacks the list line " (written line)
                              ", which " fpath " gives"))
             (multiset-minus expected found))))))

  ;; readme-problems : String String String Floors -> (Listof String)
  ;; What is wrong with RTEXT, the text of the README at RPATH, against FLOORS,
  ;; from the floors file at FPATH.
  (define (readme-problems rpath rtext fpath floors)
    (let ((found (sections (split rtext #\newline))))
      (cond
        ((null? found)
         (list (string-append rpath ": it has no " (written section-heading) " section")))
        ((pair? (cdr found))
         (list (string-append rpath ": it has " (number->string (length found)) " "
                              (written section-heading) " sections, but must have one")))
        (else
         (list-problems rpath fpath (filter list-line? (car found))
                        (requirement-lines floors))))))

  ;; --- the workflows --------------------------------------------------------

  ;; workflow-floors : (Listof (List Symbol String))
  ;; The floors no workflow line may contain: the floor's key in the floors
  ;; file, and what the messages call it.
  (define workflow-floors
    '((chez "Chez")
      (libcurl "libcurl")))

  ;; workflow-keys : (Listof String)
  ;; The env keys no workflow line may name, the Chez floor's first: those CI
  ;; held the floors in before the build scripts read them from the file.
  (define workflow-keys '("CHEZ_VERSION" "CURL_FLOOR_VERSION"))

  ;; contains? : String String -> Boolean
  ;; Whether PIECE is somewhere in TEXT.
  (define (contains? text piece)
    (let ((n (string-length text)) (m (string-length piece)))
      (let loop ((i 0))
        (cond ((> (+ i m) n) #f)
              ((string=? (substring text i (+ i m)) piece) #t)
              (else (loop (+ i 1)))))))

  ;; node-version-word : String
  ;; The text that marks a line that sets the Node version setup-node installs.
  (define node-version-word "node-version")

  ;; word-char? : Char -> Boolean
  ;; A character of a step id or an output name: a letter, digit, _ or -.
  (define (word-char? c)
    (or (char<=? #\a c #\z) (char<=? #\A c #\Z) (char<=? #\0 c #\9)
        (char=? c #\_) (char=? c #\-)))

  ;; index-of : String Char Natural -> (U Natural #f)
  ;; Where CHAR first is in TEXT at or after START.
  (define (index-of text char start)
    (let loop ((i start))
      (cond ((>= i (string-length text)) #f)
            ((char=? (string-ref text i) char) i)
            (else (loop (+ i 1))))))

  ;; backslash-after-quote? : String -> Boolean
  ;; Whether LINE holds a backslash anywhere after its first double quote.
  (define (backslash-after-quote? line)
    (let ((quote (index-of line #\" 0)))
      (and quote (index-of line #\\ (+ quote 1)) #t)))

  ;; key-places : String -> (Listof Natural)
  ;; Where a key may start in LINE: after the indent and any "- ", and after
  ;; each {, [ or , and the spaces after it.
  (define (key-places line)
    (let* ((n (string-length line))
           (skip (lambda (i) (let loop ((i i))
                               (if (and (< i n) (char=? (string-ref line i) #\space)) (loop (+ i 1)) i))))
           (first (let loop ((i (skip 0)))
                    (if (and (< (+ i 1) n) (char=? (string-ref line i) #\-)
                             (char=? (string-ref line (+ i 1)) #\space))
                        (loop (skip (+ i 2)))
                        i))))
      (let loop ((i 0) (places (list first)))
        (cond ((>= i n) (reverse places))
              ((memv (string-ref line i) '(#\{ #\[ #\,)) (loop (+ i 1) (cons (skip (+ i 1)) places)))
              (else (loop (+ i 1) places))))))

  ;; at-key-place? : String (Natural -> Boolean) -> Boolean
  ;; Whether OK? holds at one of LINE's key-places.
  (define (at-key-place? line ok?)
    (exists (lambda (i) (and (< i (string-length line)) (ok? i))) (key-places line)))

  ;; explicit-key? : String -> Boolean
  ;; ? where a key goes, then a space or the line's end.
  (define (explicit-key? line)
    (let ((n (string-length line)))
      (at-key-place? line (lambda (i) (and (char=? (string-ref line i) #\?)
                                           (or (= (+ i 1) n) (char=? (string-ref line (+ i 1)) #\space)))))))

  ;; alias-key? : String -> Boolean
  ;; * or & where a key goes, then a letter, digit, _ or -.
  (define (alias-key? line)
    (let ((n (string-length line)))
      (at-key-place? line (lambda (i) (and (memv (string-ref line i) '(#\* #\&))
                                           (< (+ i 1) n)
                                           (word-char? (string-ref line (+ i 1))))))))

  ;; beyond-ascii? : String -> Boolean
  (define (beyond-ascii? line)
    (exists (lambda (c) (char>? c #\x7e)) (string->list line)))

  ;; tab? : String -> Boolean
  (define (tab? line) (and (index-of line #\tab 0) #t))

  ;; unread-key-rules : (Listof (Pair (String -> Boolean) String))
  ;; Each rule that fails a line closed, and what its complaint says.
  (define unread-key-rules
    (list (cons backslash-after-quote?
                " holds a backslash after a double quote, which YAML may read as an escape, and check-floors does not")
          (cons explicit-key?
                " writes an explicit key, with ?, whose colon check-floors does not look for")
          (cons alias-key?
                " puts an alias or an anchor where a key goes, which check-floors does not resolve")
          (cons beyond-ascii?
                " holds a character beyond ASCII, which GitHub may fold into a key's letters, and check-floors does not")
          (cons tab?
                " holds a tab, which YAML may read beside a key, and check-floors does not")))

  ;; step-output-line? : String -> Boolean
  ;; Whether LINE is exactly "node-version: ${{ steps.ID.outputs.NAME }}",
  ;; after any indent and an optional "- ", with at least one space after the
  ;; colon, ID and NAME each a word, and nothing but spaces after it.
  (define (step-output-line? line)
    (let* ((n (string-length line))
           (skip (lambda (i) (let loop ((i i))
                               (if (and (< i n) (char=? (string-ref line i) #\space)) (loop (+ i 1)) i))))
           (word (lambda (i) (let loop ((j i))
                               (if (and (< j n) (word-char? (string-ref line j))) (loop (+ j 1)) j))))
           (at? (lambda (i text)
                  (and (<= (+ i (string-length text)) n)
                       (string=? (substring line i (+ i (string-length text))) text)))))
      (let* ((i (skip 0))
             (i (if (at? i "- ") (skip (+ i 2)) i)))
        (and (at? i "node-version:")
             (let ((j (+ i (string-length "node-version:"))))
               (and (< j n) (char=? (string-ref line j) #\space)
                    (let ((j (skip j)))
                      (and (at? j "${{ steps.")
                           (let* ((id (+ j (string-length "${{ steps.")))
                                  (id-end (word id)))
                             (and (> id-end id)
                                  (at? id-end ".outputs.")
                                  (let* ((name (+ id-end (string-length ".outputs.")))
                                         (name-end (word name)))
                                    (and (> name-end name)
                                         (at? name-end " }}")
                                         (= (skip (+ name-end 3)) n)))))))))))))

  ;; ci-workflow : String
  ;; The name of the file, directly in the workflow directory, that it must
  ;; hold.
  (define ci-workflow "ci.yml")

  ;; line-problems : String String (Listof String) (Listof (List String String)) -> (Listof String)
  ;; Each complaint about the lines LINES of the file at PATH, in line order:
  ;; for a line, the floors whose version text it contains, the Chez floor
  ;; first, then the keys it names, the Chez key first, then a node-version,
  ;; in any case, that is not a step's output, then each of unread-key-rules
  ;; it breaks, in that list's order. FPATH is the floors file's path, FLOORS
  ;; (name version) for each floor.
  (define (line-problems path fpath lines floors)
    (let loop ((rest lines) (n 1))
      (if (null? rest)
          '()
          (append
           (apply append
                  (map (lambda (floor)
                         (if (contains? (car rest) (cadr floor))
                             (list (string-append
                                    path ": line " (number->string n) " contains the "
                                    (car floor) " floor " (cadr floor)
                                    ", which no workflow line may write: the build scripts read it from "
                                    fpath))
                             '()))
                       floors))
           (apply append
                  (map (lambda (key)
                         (if (contains? (car rest) key)
                             (list (string-append
                                    path ": line " (number->string n) " names " key
                                    ", which no workflow line may name: the build scripts read the floors from "
                                    fpath))
                             '()))
                       workflow-keys))
           (if (and (contains? (string-downcase (car rest)) node-version-word)
                    (not (step-output-line? (car rest))))
               (list (string-append
                      path ": line " (number->string n) " names " node-version-word
                      ", but is not \"node-version: ${{ steps.ID.outputs.NAME }}\": the Node floor comes from "
                      fpath ", through a step that runs scripts/ci/floor.sh node"))
               '())
           (apply append
                  (map (lambda (rule)
                         (if ((car rule) (car rest))
                             (list (string-append path ": line " (number->string n) (cdr rule)))
                             '()))
                       unread-key-rules))
           (loop (cdr rest) (+ n 1))))))

  ;; workflows-problems : String String (Listof (List String (U String #f))) Floors -> (Listof String)
  ;; What is wrong with WORKFLOWS, every file under the workflow directory
  ;; WDIR, each as its path and its text, against FLOORS, from the floors file
  ;; at FPATH. A text that is #f is a file the caller could not read, which it
  ;; names: it is not compared. In order: a directory with no file, named
  ;; alone; one with no ci.yml, WDIR/ci.yml; and then, file by file in the
  ;; order of their paths, whatever order they come in, each line that
  ;; contains a floor's version text, names a floor's env key, names
  ;; node-version in any case and any form but a step's output, or breaks one
  ;; of unread-key-rules (line-problems).
  (define (workflows-problems fpath wdir workflows floors)
    (let* ((ci-path (string-append wdir "/" ci-workflow))
           ;; (name version) for each floor.
           (rows (map (lambda (row)
                        (list (cadr row) (floor-text floors (car row))))
                      workflow-floors))
           (sorted (list-sort (lambda (a b) (string<? (car a) (car b))) workflows)))
      (if (null? workflows)
          (list (string-append wdir ": it holds no file, but must hold " ci-workflow
                               ", the workflow CI runs"))
          (append
           (if (assoc ci-path sorted)
               '()
               (list (string-append wdir ": it holds no " ci-workflow ", the workflow CI runs")))
           (apply append
                  (map (lambda (entry)
                         (if (cadr entry)
                             (line-problems (car entry) fpath (split (cadr entry) #\newline) rows)
                             '()))
                       sorted))))))

  ;; check-floors : String String String (U String #f) String
  ;;                (U (Listof (List String (U String #f))) #f) -> (Listof String)
  ;; What is wrong with FTEXT, the text of the floors file at FPATH, or, when
  ;; that is right, with RTEXT, the text of the README at RPATH, and then with
  ;; WORKFLOWS, every file under the workflow directory WDIR as its path and
  ;; text, against it (workflows-problems). Empty when all are right. A bad
  ;; floors file is reported alone: the others cannot be held to it. A text
  ;; that is #f is a file that could not be read, and WORKFLOWS #f a directory
  ;; that could not be read, which the caller reports: neither is compared.
  (define (check-floors fpath ftext rpath rtext wdir workflows)
    (let ((problems (floors-problems fpath ftext)))
      (if (null? problems)
          (let ((floors (car (cadr (read-data ftext)))))
            (append (if rtext (readme-problems rpath rtext fpath floors) '())
                    (if workflows (workflows-problems fpath wdir workflows floors) '())))
          problems))))
