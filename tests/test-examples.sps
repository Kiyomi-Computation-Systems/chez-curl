#!r6rs
;;; The suite for examples/: every example runs as its head comment says to run
;;; it, against the test origin, and prints what examples/expected/ holds for it.
;;;
;;;   - examples/ holds exactly the examples written out below, each
;;;     NAME.sps, and examples/expected/ an output for exactly those, each
;;;     NAME.out: an example deleted with its output fails here;
;;;   - each example starts #!r6rs, and its one import form names public
;;;     libraries alone, (rnrs), (curl), (curl unsupported) and (http-client),
;;;     so a reader can copy it; json-api may name (jsonparse easy) too, and
;;;     no other example may (ADR-0041);
;;;   - each example's head comment holds one run line, the one the pages
;;;     teach, naming the example itself:
;;;       ;;;   scheme --libdirs src --program examples/NAME.sps URL
;;;     json-api's names src:build/scheme-libs, where make deps links
;;;     jsonparse;
;;;   - each runs as a child, `$CHEZ --libdirs LIBDIRS --program
;;;     tests/example-runner.sps examples/NAME.sps URL`, LIBDIRS the one its
;;;     head comment's run line names, so it runs as a reader running that
;;;     line would, from the
;;;     repository's root, URL the origin's http base URL, with no trailing
;;;     /, under GNU timeout's 60 s, twice against one origin, every example
;;;     once and then every one again: each run exits 0; its stdout is
;;;     examples/expected/NAME.out byte for byte; and its stderr is one line,
;;;     the runner's (counts ALIST), every count 0. An example that raises,
;;;     or calls exit, writes no counts line, one that leaves a native object
;;;     behind writes a count that is not 0 (the child prints its counts, and
;;;     the suite asserts them zero), and one whose output hangs on what the
;;;     origin kept from the first round differs in the second;
;;;   - the runner reads its counts once the program's body has returned: a
;;;     control, tests/example-leak.sps, run through it beside the examples,
;;;     leaves an engine and a jar behind, and its counts line shows one
;;;     multi handle and one share. A runner that read them first, or wrote
;;;     a fixed line, shows none.
;;;
;;; Each output is compared as bytes, read as Latin-1, one char per byte, so
;;; no decoding drops or replaces a byte, and a failure prints as text. The
;;; children's runs come first, inside the origin's call, as data; the tests
;;; read them after (SRFI-64 keeps one result per runner).
(import (rnrs)
        (srfi :64)
        (only (chezscheme) directory-list getenv)
        (curl-testing)
        (curl private counters))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; written : Any -> String
(define (written x) (call-with-string-output-port (lambda (p) (write x p))))

;; The simple runner names a failing test but not its values. Print both.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (display "  expected: ")
        (display (written (test-result-ref r 'expected-value)))
        (newline)
        (display "  actual:   ")
        (display (written (test-result-ref r 'actual-value)))
        (newline))
      (flush-output-port (current-output-port)))))

(test-begin "examples")

;; --- what the examples are ---------------------------------------------------------------

;; examples : (Listof String)
;; Every example, by name, sorted: examples/NAME.sps, its output
;; examples/expected/NAME.out. Written out, so that an example deleted with
;; its output fails the listing.
(define examples
  '("cookie-jar" "engine-and-tokens" "errors" "form-and-params" "group" "json-api" "multipart"
    "quick-start" "session-retries" "stream-download" "stream-upload"))

;; jsonparse-examples : (Listof String)
;; The examples that import (jsonparse easy) too, and run with
;; build/scheme-libs on their library path (ADR-0041).
(define jsonparse-examples '("json-api"))

;; allowed-imports : String -> (Listof (Listof Symbol))
;; The libraries NAME may import: R6RS's, and chez-curl's public ones; and
;; (jsonparse easy) for a jsonparse example.
(define (allowed-imports name)
  (append '((rnrs) (curl) (curl unsupported) (http-client))
          (if (member name jsonparse-examples) '((jsonparse easy)) '())))

;; libdirs : String -> String
;; The library path NAME's run line must name.
(define (libdirs name)
  (if (member name jsonparse-examples) "src:build/scheme-libs" "src"))

;; zero-counts : (Listof (Pairof Symbol 0))
;; (curl private counters)' native counts, every kind 0, in its order.
(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)))

;; counts-line : String
;; What the runner writes on stderr, alone, for an example that left nothing.
(define counts-line (string-append (written (list 'counts zero-counts)) "\n"))

;; --- helpers -----------------------------------------------------------------------------

;; ends-with? : String String -> Boolean
(define (ends-with? suffix text)
  (let ((n (string-length text)) (k (string-length suffix)))
    (and (>= n k) (string=? suffix (substring text (- n k) n)))))

;; names-in : String String -> (U (Listof String) (List 'unreadable String))
;; The names, sorted, of DIR's entries that end in SUFFIX, the suffix cut off;
;; or why DIR cannot be listed.
(define (names-in dir suffix)
  (guard (e (#t (list 'unreadable (describe e))))
    (list-sort string<?
               (map (lambda (entry) (substring entry 0 (- (string-length entry) (string-length suffix))))
                    (filter (lambda (entry) (ends-with? suffix entry)) (directory-list dir))))))

;; latin-1 : Bytevector -> String
;; Each byte one char, so two strings are equal exactly when the bytes are.
(define (latin-1 bytes)
  (list->string (map integer->char (bytevector->u8-list bytes))))

;; file-bytes : String -> (U String (List 'missing String))
;; PATH's bytes, read as Latin-1; or a value no run prints, naming PATH.
(define (file-bytes path)
  (guard (e (#t (list 'missing path (describe e))))
    (let* ((port (open-file-input-port path))
           (bytes (get-bytevector-all port)))
      (close-port port)
      (if (eof-object? bytes) "" (latin-1 bytes)))))

;; first-line : String -> (U String #f)
(define (first-line text)
  (let loop ((i 0))
    (cond ((= i (string-length text)) #f)
          ((char=? (string-ref text i) #\newline) (substring text 0 i))
          (else (loop (+ i 1))))))

;; run-line : String -> String
;; The run line NAME's head comment holds, the form the pages teach.
(define (run-line name)
  (string-append ";;;   scheme --libdirs " (libdirs name) " --program examples/" name ".sps URL"))

;; contains? : String String -> Boolean
(define (contains? part text)
  (let ((n (string-length text)) (k (string-length part)))
    (let loop ((i 0))
      (and (<= (+ i k) n)
           (or (string=? part (substring text i (+ i k))) (loop (+ i 1)))))))

;; text-lines : String -> (Listof String)
(define (text-lines text)
  (let loop ((i 0) (start 0) (found '()))
    (cond ((= i (string-length text))
           (reverse (if (< start i) (cons (substring text start i) found) found)))
          ((char=? (string-ref text i) #\newline)
           (loop (+ i 1) (+ i 1) (cons (substring text start i) found)))
          (else (loop (+ i 1) start found)))))

;; head-run-lines : String -> (U (Listof String) (List 'unreadable String))
;; The lines of NAME's head comment, every ;;; line after #!r6rs before the
;; first other line, that hold --program; or why the file cannot be read.
(define (head-run-lines name)
  (guard (e (#t (list 'unreadable (describe e))))
    (let* ((lines (text-lines (call-with-input-file (string-append "examples/" name ".sps")
                                get-string-all)))
           (head (let loop ((rest (if (pair? lines) (cdr lines) '())) (found '()))
                   (if (and (pair? rest) (>= (string-length (car rest)) 3)
                            (string=? ";;;" (substring (car rest) 0 3)))
                       (loop (cdr rest) (cons (car rest) found))
                       (reverse found)))))
      (filter (lambda (line) (contains? "--program" line)) head))))

;; words : String -> (Listof String)
;; TEXT's words, split at spaces.
(define (words text)
  (let loop ((i 0) (start 0) (found '()))
    (cond ((= i (string-length text))
           (reverse (if (< start i) (cons (substring text start i) found) found)))
          ((char=? (string-ref text i) #\space)
           (loop (+ i 1) (+ i 1) (if (< start i) (cons (substring text start i) found) found)))
          (else (loop (+ i 1) start found)))))

;; run-libdirs : String -> String
;; The library path NAME's one head run line names after --libdirs, which
;; its child runs with; "src" when it has no one run line, or names none,
;; which its run-line test fails.
(define (run-libdirs name)
  (let ((lines (head-run-lines name)))
    (or (and (list? lines) (= (length lines) 1) (string? (car lines))
             (let ((tail (member "--libdirs" (words (car lines)))))
               (and tail (pair? (cdr tail)) (cadr tail))))
        "src")))

;; example-shape : String -> (List (U String #f) Any)
;; NAME's first line, and the libraries its first datum imports that are
;; not allowed: () when that datum is an import form of allowed libraries
;; alone; (no-import DATUM) when it is no import form; (unreadable TEXT)
;; when the file does not read.
(define (example-shape name)
  (let ((path (string-append "examples/" name ".sps")))
    (guard (e (#t (list 'unreadable (describe e))))
      (let ((text (call-with-input-file path get-string-all)))
        (list (first-line text)
              (let ((datum (read (open-string-input-port text))))
                (if (and (pair? datum) (eq? (car datum) 'import) (list? datum))
                    (filter (lambda (spec) (not (member spec (allowed-imports name)))) (cdr datum))
                    (list 'no-import datum))))))))

;; child-script : String
;; sh -c CHILD-SCRIPT sh OUT COMMAND...: COMMAND, stdin at its end, stdout
;; into the file OUT, under GNU timeout (gtimeout on macOS), killed after
;; 60 s, exit 137; with neither found, exit 125, saying so. The shell's own
;; stderr is /dev/null, so a "Killed" of the shell's is not the command's.
(define child-script
  (string-append
   "t=$(command -v timeout || command -v gtimeout) || { echo 'test-examples: no timeout' >&2; exit 125; }\n"
   "out=$1; shift\n"
   "exec 3>&2 2>/dev/null\n"
   "( exec \"$t\" -s KILL 60 \"$@\" </dev/null >\"$out\" 2>&3 3>&- )\n"
   "exit $?\n"))

;; run-program : String String String String -> (List Integer (U String List) String)
;; The program at PATH run through the runner against BASE, LIBDIRS its
;; library path, its stdout in the file OUT: the exit status, the stdout's
;; bytes as Latin-1, and the stderr.
(define (run-program path libdirs base out)
  (let ((r (capture-command (list "sh" "-c" child-script "sh" out
                                  (getenv "CHEZ") "--libdirs" libdirs
                                  "--program" "tests/example-runner.sps" path base))))
    (list (car r) (file-bytes out) (caddr r))))

;; run-example : String Integer String String -> (List Integer (U String List) String)
;; NAME's run in ROUND against BASE, its stdout in a file of DIR.
(define (run-example name round base dir)
  (run-program (string-append "examples/" name ".sps") (run-libdirs name) base
               (string-append dir "/" name "-" (number->string round) ".out")))

;; read-counts : String -> Any
;; STDERR as data: (counts ALIST) when it is that one datum alone, else
;; (not-one-counts-line STDERR).
(define (read-counts stderr)
  (let ((data (guard (e (#t (list 'unreadable)))
                (let ((port (open-string-input-port stderr)))
                  (let loop ((found '()))
                    (let ((datum (read port)))
                      (if (eof-object? datum) (reverse found) (loop (cons datum found)))))))))
    (if (and (= (length data) 1) (pair? (car data)) (eq? (caar data) 'counts)
             (pair? (cdar data)) (list? (cadar data)))
        (car data)
        (list 'not-one-counts-line stderr))))

;; control-counts : (List Integer (U String List) String) -> Any
;; The control's run, as its test reads it: the status, the stdout, and its
;; multi and share counts, or why they could not be read.
(define (control-counts run)
  (let ((counts (read-counts (caddr run))))
    (list (car run) (cadr run)
          (if (eq? (car counts) 'counts)
              (map (lambda (kind)
                     (let ((entry (assq kind (cadr counts))))
                       (if (pair? entry) (cdr entry) (list 'no-count kind))))
                   '(multi share))
              counts))))

;; --- the runs ----------------------------------------------------------------------------

;; sps-names, out-names : (U (Listof String) (List 'unreadable String))
;; The examples examples/ holds, and the outputs examples/expected/ holds.
(define sps-names (names-in "examples" ".sps"))
(define out-names (names-in "examples/expected" ".out"))

;; run-names : (Listof String)
;; Every example examples/ holds, and every one written out, sorted: a
;; planted example runs too, and a deleted one fails its run.
(define run-names
  (let ((listed (if (and (pair? sps-names) (eq? (car sps-names) 'unreadable)) '() sps-names)))
    (list-sort string<?
               (append listed (filter (lambda (name) (not (member name listed))) examples)))))

;; rounds : (Listof Integer)
;; Every example runs once in each, against one origin, round 1's all
;; before round 2's: what the origin keeps from a run must not move the next.
(define rounds '(1 2))

;; runs : (U (List (Listof (Pairof (Pairof Integer String) List)) List) (List 'raised String))
;; Each example's run, by round and name, against one origin; then the
;; control's run, through the runner the same way.
(define runs
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (call-with-origin
        (lambda (o)
          (let* ((face (origin-face o 'http))
                 (base (string-append "http://" (car face) ":" (number->string (cdr face))))
                 (examples-run
                  (let round-loop ((rest rounds) (done '()))
                    (if (null? rest)
                        (reverse done)
                        (round-loop
                         (cdr rest)
                         (let loop ((names run-names) (done done))
                           (if (null? names)
                               done
                               (loop (cdr names)
                                     (cons (cons (cons (car rest) (car names))
                                                 (run-example (car names) (car rest) base dir))
                                           done))))))))
                 (control (run-program "tests/example-leak.sps" "src" base
                                       (string-append dir "/control.out"))))
            (list examples-run control))))))))

;; example-runs, control-run : the two parts of runs, or what raised.
(define example-runs (if (eq? (car runs) 'raised) runs (car runs)))
(define control-run (if (eq? (car runs) 'raised) runs (cadr runs)))

;; --- the tests ---------------------------------------------------------------------------

(test-equal "examples/ holds exactly the examples this suite writes out, each NAME.sps"
  examples
  sps-names)

(test-equal "examples/expected/ holds an output for exactly those examples, each NAME.out"
  examples
  out-names)

(test-equal "the origin starts, every example runs against it in each round, and it stops"
  (apply append (map (lambda (round) (map (lambda (name) (cons round name)) run-names)) rounds))
  (if (eq? (car example-runs) 'raised) example-runs (map car example-runs)))

(test-equal "the control, tests/example-leak.sps, run through the runner, exits 0, prints its line, and its counts line, read once its body has returned, holds the engine's multi handle and the jar's share"
  (list 0 "left an engine and a jar\n" '(1 1))
  (if (eq? (car control-run) 'raised) control-run (control-counts control-run)))

(for-each
 (lambda (name)
   (test-equal (string-append "examples/" name ".sps starts #!r6rs, and its one import form names"
                              " these libraries alone: " (written (allowed-imports name)))
     (list "#!r6rs" '())
     (example-shape name))
   (test-equal (string-append "examples/" name ".sps's head comment holds one run line, the pages' form,"
                              " naming itself: " (run-line name))
     (list (run-line name))
     (head-run-lines name))
   (for-each
    (lambda (round)
      (test-equal (string-append "examples/" name ".sps, run " (number->string round)
                                 " by tests/example-runner.sps against the origin's http base URL,"
                                 " exits 0, writes examples/expected/" name
                                 ".out byte for byte, and on stderr one counts line, every count zero")
        (list 0 (file-bytes (string-append "examples/expected/" name ".out")) counts-line)
        (let ((run (and (not (eq? (car example-runs) 'raised))
                        (assoc (cons round name) example-runs))))
          (if run (cdr run) (list 'not-run example-runs)))))
    rounds))
 run-names)

(test-equal "every count is zero at the end"
  zero-counts
  (native-counts))

(test-end "examples")

(exit (suite-exit-status runner))
