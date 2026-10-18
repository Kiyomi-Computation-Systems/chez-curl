#!r6rs
;;; The suite for (curl-testing), the helpers every suite shares (ADR-0015):
;;; the verdict behind the shared exit form, then capture-command, the
;;; temporary directories, run-until, seeded-bytes and describe.
;;;
;;; Each expected value is one the code under test cannot produce by failing.
;;; SRFI-64 turns a raise in the actual expression into #f, so no expected
;;; value here is #f, and every check of a refusal compares what was raised
;;; against a no-raise sentinel.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) parameterize record-writer getenv putenv directory-list
              file-directory? make-time sleep current-time time-difference time-second
              time-nanosecond)
        ;; Chez's own current-error-port is a parameter; (rnrs)'s takes no
        ;; argument, and reads the same port.
        (prefix (only (chezscheme) current-error-port) chez:)
        (curl-testing))

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

;; raised : (-> Any) -> Any
;; What THUNK raised: (assertion-violation WHO IRRITANTS) for an assertion
;; violation, something else for any other raise, and the symbol no-raise if
;; THUNK returned.
(define (raised thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e)
                  (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            ((message-condition? e) (list 'other-raise (condition-message e)))
            (#t (list 'other-raise e)))
    (thunk)
    'no-raise))

(test-begin "curl-testing")

;; --- suite-exit-status: the verdict behind the shared exit form -----------
;; Each runner below is a fresh null runner, which prints nothing and which
;; this suite's own runner never sees. Each base holds the outcomes the rule
;; under test must ignore, so that only that rule can produce the expected
;; verdict.

;; runner-after : (-> Any) -> Test-Runner
(define (runner-after thunk)
  (let ((r (test-runner-null)))
    (test-with-runner r
      (test-begin "inner")
      (thunk)
      (test-end "inner"))
    r))

;; verdict : Test-Runner -> (List Integer String)
;; suite-exit-status's answer, then everything it wrote to the error port.
(define (verdict r)
  (let-values (((port contents) (open-string-output-port)))
    (let ((status (parameterize ((chez:current-error-port port))
                    (suite-exit-status r))))
      (list status (contents)))))

(test-equal "a pass beside an expected failure and a skip: exit 0, and nothing said"
  '(0 "")
  (verdict (runner-after (lambda ()
                           (test-assert "passes" #t)
                           (test-expect-fail 1)
                           (test-assert "fails, as expected" #f)
                           (test-skip 1)
                           (test-assert "skipped" #t)))))

(test-equal "two failures beside a pass: exit 1, not a count, since exit statuses wrap at 256"
  '(1 "suite-exit-status: exit 1 (pass 1, fail 2, xpass 0): a suite needs a pass, and no fail or xpass\n")
  (verdict (runner-after (lambda ()
                           (test-assert "passes" #t)
                           (test-assert "fails" #f)
                           (test-assert "fails too" #f)))))

(test-equal "an unexpected pass beside a pass: exit 1"
  '(1 "suite-exit-status: exit 1 (pass 1, fail 0, xpass 1): a suite needs a pass, and no fail or xpass\n")
  (verdict (runner-after (lambda ()
                           (test-assert "passes" #t)
                           (test-expect-fail 1)
                           (test-assert "passes unexpectedly" #t)))))

(test-equal "an expected failure and a skip, but no pass: exit 1"
  '(1 "suite-exit-status: exit 1 (pass 0, fail 0, xpass 0): a suite needs a pass, and no fail or xpass\n")
  (verdict (runner-after (lambda ()
                           (test-expect-fail 1)
                           (test-assert "fails, as expected" #f)
                           (test-skip 1)
                           (test-assert "skipped" #t)))))

(test-equal "no test at all: exit 1"
  '(1 "suite-exit-status: exit 1 (pass 0, fail 0, xpass 0): a suite needs a pass, and no fail or xpass\n")
  (verdict (runner-after (lambda () 'no-tests))))

(test-equal "suite-exit-status refuses what is not a runner"
  '(assertion-violation suite-exit-status ("not a runner"))
  (raised (lambda () (suite-exit-status "not a runner"))))

;; --- capture-command ------------------------------------------------------

(test-equal "capture-command: the exit status, stdout and stderr, kept apart"
  '(3 "out\n" "err\n")
  (capture-command '("sh" "-c" "echo out; echo err >&2; exit 3")))

(test-equal "capture-command: each argument arrives as one word, unchanged"
  '(0 "a b|$HOME|it's|\"q\"|back\\slash||*|;|two\nlines|" "")
  (capture-command
   (list "printf" "%s|"
         "a b" "$HOME" "it's" "\"q\"" "back\\slash" "" "*" ";" "two\nlines")))

(test-equal "capture-command: a NUL would cut the command short, so it is refused"
  (list 'assertion-violation 'capture-command (list (string #\a #\nul #\b)))
  (raised (lambda () (capture-command (list "printf" (string #\a #\nul #\b))))))

(test-equal "capture-command: every argument is a string"
  '(assertion-violation capture-command (5))
  (raised (lambda () (capture-command '("echo" 5)))))

(test-equal "capture-command: a command has at least its name"
  '(assertion-violation capture-command (()))
  (raised (lambda () (capture-command '()))))

;; --- temporary directories ------------------------------------------------
;; call-with-temp-directory, make-process-temp-directory and
;; remove-temp-directory. The dangerous mistake is a path cut at whitespace,
;; so that a removal destroys a neighbour: those rows keep a canary directory
;; beside the one that is made, and require it to survive.

(define chez (getenv "CHEZ"))

(test-equal "CHEZ names the Chez to spawn"
  'set
  (if (and chez (not (string=? chez ""))) 'set 'unset))

;; absolute? : String -> Boolean
(define (absolute? s)
  (and (> (string-length s) 0) (char=? (string-ref s 0) #\/)))

;; prefix? : String String -> Boolean
(define (prefix? prefix s)
  (and (<= (string-length prefix) (string-length s))
       (string=? prefix (substring s 0 (string-length prefix)))))

;; call-with-env : String String (-> Any) -> Any
;; THUNK with the environment variable NAME set to VALUE. Afterwards NAME is
;; put back to its old value, or to /tmp when it was unset: putenv cannot
;; unset, and /tmp is where mktemp and capture-command go for an unset TMPDIR.
;; Only PATH and TMPDIR are set here.
(define (call-with-env name value thunk)
  (let ((old (getenv name)))
    (dynamic-wind
      (lambda () (putenv name value))
      thunk
      (lambda () (putenv name (or old "/tmp"))))))

;; write-file : String String -> Unit
(define (write-file path text)
  (call-with-port (open-file-output-port path (file-options no-fail) (buffer-mode block)
                                         (make-transcoder (utf-8-codec)))
    (lambda (p) (put-string p text))))

;; sorted-names : String -> (Listof String)
(define (sorted-names dir) (list-sort string<? (directory-list dir)))

(test-equal "call-with-temp-directory: PROC gets the path of an empty directory, and the directory is gone after"
  '((#t #t ()) removed)
  (let* ((made #f)
         (inside (call-with-temp-directory
                  (lambda (dir)
                    (set! made dir)
                    (list (absolute? dir) (file-directory? dir) (directory-list dir))))))
    (list inside (if (file-exists? made) 'left 'removed))))

(test-equal "call-with-temp-directory: its answer is PROC's, and what the directory held is removed too"
  '(answer ("g" "sub") removed)
  (let* ((made #f)
         (listing #f)
         (value (call-with-temp-directory
                 (lambda (dir)
                   (set! made dir)
                   (capture-command
                    (list "sh" "-c" "mkdir \"$1/sub\" && echo x > \"$1/sub/f\" && echo y > \"$1/g\""
                          "sh" dir))
                   (set! listing (sorted-names dir))
                   'answer))))
    (list value listing (if (file-exists? made) 'left 'removed))))

(test-equal "call-with-temp-directory: the directory is removed when PROC raises, and the raise goes on"
  '(boom removed)
  (let ((made #f))
    (guard (e (#t (list e (if (file-exists? made) 'left 'removed))))
      (call-with-temp-directory
       (lambda (dir) (set! made dir) (raise 'boom)))
      'no-raise)))

(test-equal "call-with-temp-directory: the directory is removed when PROC escapes"
  '(escaped removed)
  (let* ((made #f)
         (value (call/cc
                 (lambda (k)
                   (call-with-temp-directory
                    (lambda (dir) (set! made dir) (k 'escaped)))))))
    (list value (if (file-exists? made) 'left 'removed))))

(test-equal "call-with-temp-directory: TMPDIR holding a space is one path; the directory beside it survives"
  '(inside kept removed)
  (call-with-temp-directory
   (lambda (base)
     (let ((canary (string-append base "/can"))
           (spaced (string-append base "/can ary")))
       (capture-command (list "mkdir" canary spaced))
       (write-file (string-append canary "/keep") "keep\n")
       (let ((inside (call-with-env "TMPDIR" spaced
                       (lambda ()
                         (call-with-temp-directory
                          (lambda (dir)
                            (if (prefix? (string-append spaced "/") dir) 'inside 'elsewhere)))))))
         (list inside
               (if (file-exists? (string-append canary "/keep")) 'kept 'destroyed)
               (if (null? (directory-list spaced)) 'removed 'left)))))))

;; refusal : (-> Any) -> Any
;; THUNK's raise, or the symbol no-raise.
(define (refusal thunk) (raised thunk))

(define mktemp-refusal
  '(other-raise "mktemp -d did not answer one absolute path to a directory"))

(test-equal "call-with-temp-directory: a newline in TMPDIR makes two lines, which it refuses; the directory named by the first survives"
  (list mktemp-refusal 'kept 'never-called)
  (call-with-temp-directory
   (lambda (base)
     (let ((canary (string-append base "/can"))
           (newlined (string-append base "/can\nary"))
           (called 'never-called))
       (capture-command (list "mkdir" canary newlined))
       (write-file (string-append canary "/keep") "keep\n")
       (let ((answer (call-with-env "TMPDIR" newlined
                       (lambda ()
                         (refusal (lambda ()
                                    (call-with-temp-directory
                                     (lambda (dir) (set! called 'called)))))))))
         (list answer
               (if (file-exists? (string-append canary "/keep")) 'kept 'destroyed)
               called))))))

;; A mktemp on PATH ahead of the real one, answering what BODY (shell
;; commands) makes it. CANARY is a directory that exists, which BODY may name.
(define (with-fake-mktemp base body thunk)
  (let ((bin (string-append base "/bin")))
    (capture-command (list "mkdir" bin))
    (write-file (string-append bin "/mktemp") (string-append "#!/bin/sh\n" body "\n"))
    (capture-command (list "chmod" "+x" (string-append bin "/mktemp")))
    (call-with-env "PATH" (string-append bin ":" (getenv "PATH")) thunk)))

(for-each
 (lambda (row)
   (let ((name (car row)) (body (cadr row)))
     (test-equal (string-append "call-with-temp-directory refuses a mktemp that answers " name
                                ", and calls nothing, and removes nothing")
       (list mktemp-refusal 'kept 'never-called)
       (call-with-temp-directory
        (lambda (base)
          (let ((canary (string-append base "/can"))
                (called 'never-called))
            (capture-command (list "mkdir" canary))
            (write-file (string-append canary "/keep") "keep\n")
            (let ((answer (with-fake-mktemp base (string-append "CANARY='" canary "'\n" body)
                            (lambda ()
                              (refusal (lambda ()
                                         (call-with-temp-directory
                                          (lambda (dir) (set! called 'called)))))))))
              (list answer
                    (if (file-exists? (string-append canary "/keep")) 'kept 'destroyed)
                    called))))))))
 '(("a relative path to a directory that exists" "printf 'tests\\n'")
   ("a path that is not there" "printf '/no/such/directory/anywhere\\n'")
   ("an empty line"        "printf '\\n'")
   ("no newline"           "printf '%s' \"$CANARY\"")
   ("two lines, the first a directory" "printf '%s\\n%s\\n' \"$CANARY\" \"$CANARY/second\"")
   ("a directory and exit 1" "printf '%s\\n' \"$CANARY\"; exit 1")))

(test-equal "remove-temp-directory: it removes a directory and what is in it, and a path that is gone is no error"
  '(no-raise removed no-raise)
  (call-with-temp-directory
   (lambda (base)
     (let ((victim (string-append base "/victim")))
       (capture-command (list "mkdir" "-p" (string-append victim "/sub")))
       (let ((first (refusal (lambda () (remove-temp-directory victim)))))
         (list first
               (if (file-exists? victim) 'left 'removed)
               (refusal (lambda () (remove-temp-directory victim)))))))))

;; with-fake-rm : String (-> Any) -> Any
;; THUNK with an rm ahead of the real one on PATH that removes nothing and
;; logs its arguments to BASE/rm-log. A refusal is shown to run no rm, and a
;; removal that should have been refused cannot reach a real directory.
(define (with-fake-rm base thunk)
  (let ((bin (string-append base "/bin")))
    (capture-command (list "mkdir" bin))
    (write-file (string-append bin "/rm")
                (string-append "#!/bin/sh\necho \"$@\" >> '" base "/rm-log'\nexit 0\n"))
    (capture-command (list "chmod" "+x" (string-append bin "/rm")))
    (call-with-env "PATH" (string-append bin ":" (getenv "PATH")) thunk)))

(test-equal "remove-temp-directory: only an absolute path other than /, and it runs no rm for any other"
  '((assertion-violation remove-temp-directory ("relative/dir"))
    (assertion-violation remove-temp-directory ("/"))
    (assertion-violation remove-temp-directory (""))
    never-run)
  (call-with-temp-directory
   (lambda (base)
     (with-fake-rm base
       (lambda ()
         (list (refusal (lambda () (remove-temp-directory "relative/dir")))
               (refusal (lambda () (remove-temp-directory "/")))
               (refusal (lambda () (remove-temp-directory "")))
               (if (file-exists? (string-append base "/rm-log")) 'run 'never-run)))))))

(test-equal "remove-temp-directory: a directory still there after rm is a raise"
  (list (list 'other-raise "could not remove the directory") 'still-there)
  (call-with-temp-directory
   (lambda (base)
     (let ((bin (string-append base "/bin"))
           (victim (string-append base "/victim")))
       (capture-command (list "mkdir" bin victim))
       (write-file (string-append bin "/rm") "#!/bin/sh\nexit 0\n")
       (capture-command (list "chmod" "+x" (string-append bin "/rm")))
       (let ((answer (call-with-env "PATH" (string-append bin ":" (getenv "PATH"))
                       (lambda () (refusal (lambda () (remove-temp-directory victim)))))))
         (list answer (if (file-exists? victim) 'still-there 'removed)))))))

;; process-outcome : String [Symbol] -> (List Integer Symbol (Listof String) Symbol)
;; Runs a program that makes a process temp directory, prints its path, then
;; runs the forms in AFTER, in a fresh Chez whose TMPDIR is a directory of
;; this suite's making. The answer: its exit status; whether the path it
;; printed is under that TMPDIR; whatever else it printed, as lines; and
;; whether the directory is gone. With the symbol fake-rm after AFTER, the
;; program's PATH has an rm that removes nothing, so a removal fails.
(define (process-outcome after . options)
  (call-with-temp-directory
   (lambda (base)
     (let ((program (string-append base "/probe.sps"))
           (bin (string-append base "/bin")))
       (when (memq 'fake-rm options)
         (capture-command (list "mkdir" bin))
         (write-file (string-append bin "/rm") "#!/bin/sh\nexit 0\n")
         (capture-command (list "chmod" "+x" (string-append bin "/rm"))))
       (write-file program
                   (string-append
                    "#!r6rs\n"
                    "(import (rnrs) (only (chezscheme) warning file-directory?) (curl-testing))\n"
                    "(define dir (make-process-temp-directory))\n"
                    "(put-string (current-output-port) dir)\n"
                    "(put-string (current-output-port) \"\\n\")\n"
                    after "\n"))
       (let* ((answer (capture-command
                       (append (list "env" (string-append "TMPDIR=" base))
                               (if (memq 'fake-rm options)
                                   (list (string-append "PATH=" bin ":" (getenv "PATH")))
                                   '())
                               (list chez "--libdirs" "tests:build/scheme-libs"
                                     "--program" program))))
              (lines (let loop ((chars (string->list (cadr answer))) (line '()) (found '()))
                       (cond ((null? chars) (reverse found))
                             ((char=? (car chars) #\newline)
                              (loop (cdr chars) '() (cons (list->string (reverse line)) found)))
                             (else (loop (cdr chars) (cons (car chars) line) found)))))
              (dir (and (pair? lines) (car lines))))
         (list (car answer)
               (if (and dir (prefix? (string-append base "/") dir)) 'under-tmpdir 'elsewhere)
               (if (pair? lines) (cdr lines) lines)
               (if (and dir (file-exists? dir)) 'left 'removed)))))))

(define kept-line
  (string-append "(put-string (current-output-port) (if (file-directory? dir) \"kept\\n\" \"gone\\n\"))\n"
                 "(exit 0)"))

(test-equal "make-process-temp-directory: removed by exit, which keeps its status"
  '(3 under-tmpdir () removed)
  (process-outcome "(exit 3)"))

(test-equal "make-process-temp-directory: removed by a raise nothing guards, status 255"
  '(255 under-tmpdir () removed)
  (process-outcome "(car '())"))

(test-equal "make-process-temp-directory: removed by a raise of a non-condition too"
  '(255 under-tmpdir () removed)
  (process-outcome "(raise 'boom)"))

(test-equal "make-process-temp-directory: a removal that fails in the exit hook neither raises nor changes the status"
  '(3 under-tmpdir () left)
  (process-outcome "(exit 3)" 'fake-rm))

(test-equal "make-process-temp-directory: a removal that fails in the exception hook neither loops nor changes the status"
  '(255 under-tmpdir () left)
  (process-outcome "(car '())" 'fake-rm))

(test-equal "make-process-temp-directory: a raise a guard catches does not remove it"
  '(0 under-tmpdir ("kept") removed)
  (process-outcome
   (string-append "(guard (e (#t 'caught)) (car '()))\n"
                  "(guard (e (#t 'caught)) (raise 'boom))\n"
                  kept-line)))

(test-equal "make-process-temp-directory: a warning, which goes on, does not remove it"
  '(0 under-tmpdir ("kept") removed)
  (process-outcome
   (string-append "(warning 'probe \"just a warning\")\n" kept-line)))


;; --- run-until ------------------------------------------------------------

;; steps-until : Natural Natural -> (List Symbol Natural)
;; run-until's answer for a predicate that holds once N steps are taken,
;; under a cap of CAP, then the number of steps it took.
(define (steps-until n cap)
  (let* ((steps 0)
         (answer (run-until (lambda () (set! steps (+ steps 1)))
                            (lambda () (>= steps n))
                            cap)))
    (list answer steps)))

(test-equal "run-until: a predicate that already holds costs no step"
  '(satisfied 0)
  (steps-until 0 5))

(test-equal "run-until: it steps until the predicate holds, and no further"
  '(satisfied 3)
  (steps-until 3 5))

(test-equal "run-until: a predicate that first holds after the last step allowed is satisfied"
  '(satisfied 4)
  (steps-until 4 4))

(test-equal "run-until: one step short, it answers iterations-exhausted, with no step past the cap"
  '(iterations-exhausted 4)
  (steps-until 5 4))

(test-equal "run-until: the cap is a positive exact integer"
  '(assertion-violation run-until (0))
  (raised (lambda () (run-until (lambda () 'step) (lambda () #f) 0))))

(test-equal "run-until: the predicate is a procedure"
  '(assertion-violation run-until (#t))
  (raised (lambda () (run-until (lambda () 'step) #t 3))))

(test-equal "run-until: the step is a procedure"
  '(assertion-violation run-until (step))
  (raised (lambda () (run-until 'step (lambda () #f) 3))))

;; --- seeded-bytes ---------------------------------------------------------
;; The expected bytes were computed outside Chez, from the generator its
;; comment documents: x <- (1103515245 x + 12345) mod 2^31, from x = seed,
;; and each byte is bits 16 to 23 of the new x.

(test-equal "seeded-bytes: seed 1, as the documented generator computes it"
  #vu8(198 126 129 107 75 251 226 251)
  (seeded-bytes 8 1))

(test-equal "seeded-bytes: seed 2, other bytes"
  #vu8(140 33 255 114 237 215 24 217)
  (seeded-bytes 8 2))

(test-equal "seeded-bytes: as many bytes as asked for, none included"
  '(0 1000)
  (list (bytevector-length (seeded-bytes 0 1))
        (bytevector-length (seeded-bytes 1000 1))))

(test-equal "seeded-bytes: the length is a natural number"
  '(assertion-violation seeded-bytes (-1))
  (raised (lambda () (seeded-bytes -1 1))))

(test-equal "seeded-bytes: the seed is a natural number"
  '(assertion-violation seeded-bytes (1.5))
  (raised (lambda () (seeded-bytes 4 1.5))))

;; --- describe -------------------------------------------------------------

(define-record-type unprintable (fields x))
(record-writer (record-type-descriptor unprintable)
  (lambda (r port wr) (error 'unprintable "this record cannot be printed")))

(test-equal "describe: a condition, as display-condition shows it"
  "Exception in f: bad thing with irritants (1 \"two\")"
  (describe (condition (make-error)
                       (make-who-condition 'f)
                       (make-message-condition "bad thing")
                       (make-irritants-condition '(1 "two")))))

(test-equal "describe: anything else is written, so a string keeps its quotes"
  "(1 \"two\" three)"
  (describe '(1 "two" three)))

(test-equal "describe: an object whose printing raises gets a fixed text, not a raise"
  "<the raised object could not be printed>"
  (describe (make-unprintable 1)))

;; --- the test origin and the probe ---------------------------------------
;; The real origin, tests/origin.mjs, and stand-ins this suite writes into a
;; temporary directory, each run through origin-script: no fake origin lives
;; in the tree. Every refusal is compared whole: who, message and irritants.

(define node (let ((n (getenv "NODE"))) (if (and n (not (string=? n ""))) n "node")))

;; write-text : String -> String
;; S as write prints it, in double quotes: also a JavaScript string literal,
;; for the text these tests use.
(define (write-text s)
  (call-with-string-output-port (lambda (p) (write s p))))

;; refusal-of : (-> Any) -> Any
;; What THUNK raised, as (WHO MESSAGE IRRITANTS) for a condition that has
;; them, (assertion-violation WHO IRRITANTS) for an assertion violation, the
;; raised object itself for anything else, or the symbol no-raise.
(define (refusal-of thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e) (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            ((and (who-condition? e) (message-condition? e) (irritants-condition? e))
             (list (condition-who e) (condition-message e) (condition-irritants e)))
            ((condition? e) (list 'other-condition (describe e)))
            (#t e))
    (thunk)
    'no-raise))

;; --- read-announcement

(test-equal "read-announcement: the origin's announcement, its entries in order"
  '(("node" . "v24.18.0") ("pid" . 12345) ("http" . "127.0.0.1:40001") ("raw" . "127.0.0.1:40002"))
  (guard (e (#t (list 'raised (describe e))))
    (read-announcement
     "{\"node\":\"v24.18.0\",\"pid\":12345,\"http\":\"127.0.0.1:40001\",\"raw\":\"127.0.0.1:40002\"}")))

(test-equal "read-announcement: an empty object, a zero, an empty string and text beyond ASCII"
  (list '() (list (cons "a" 0) (cons "" "") (cons "k\xe9;" "\x3bb;")))
  (guard (e (#t (list 'raised (describe e))))
    (list (read-announcement "{}")
          (read-announcement "{\"a\":0,\"\":\"\",\"k\xe9;\":\"\x3bb;\"}"))))

(for-each
 (lambda (row)
   (let ((text (car row)) (message (cadr row)) (at (caddr row)))
     (test-equal (string-append "read-announcement refuses " (write-text text) ": " message)
       (list 'read-announcement message (list text at))
       (refusal-of (lambda () (read-announcement text))))))
 (let ((one "an announcement is one JSON object, from { to }")
       (after "text after the object")
       (value "a value is a string or a natural")
       (open "the object is not closed"))
   (list (list "" one 0)
         (list "[1]" one 0)
         (list " {}" one 0)
         (list "{} " after 2)
         (list "{}x" after 2)
         (list "{\"a\":1}\n" after 7)
         (list "{\"a\":1}{\"b\":2}" after 7)
         (list "{\"a\":\"x\\\"y\"}" "an escape in a string" 7)
         (list "{\"a\\u0041\":1}" "an escape in a string" 3)
         (list "{\"a\":\"x\ty\"}" "a control character in a string" 7)
         (list "{\"a\":{}}" "a nested value" 5)
         (list "{\"a\":[1]}" "a nested value" 5)
         (list "{\"a\":1,\"a\":2}" "a duplicate key" 7)
         (list "{\"a\":true}" value 5)
         (list "{\"a\":null}" value 5)
         (list "{\"a\":-1}" value 5)
         (list "{\"a\":1.5}" value 5)
         (list "{\"a\":1e3}" value 5)
         (list "{\"a\":01}" "a natural with a leading zero" 5)
         (list "{ \"a\":1}" "a key is a string" 1)
         (list "{a:1}" "a key is a string" 1)
         (list "{\"a\":1,}" "a key is a string" 7)
         (list "{\"a\" :1}" "a colon after each key" 4)
         (list "{\"a\":1 }" "a comma or } after each value" 6)
         (list "{" open 1)
         (list "{\"a\"" open 4)
         (list "{\"a\":" open 5)
         (list "{\"a\":1" open 6)
         (list "{\"a" "a string is not closed" 1)
         (list "{\"a\":\"b" "a string is not closed" 5))))

(test-equal "read-announcement: its argument is a string"
  '(assertion-violation read-announcement (5))
  (refusal-of (lambda () (read-announcement 5))))

;; --- call-with-origin, with the real origin

(test-equal "call-with-origin: PROC's answer, and an origin whose node is NODE's version and whose faces are on loopback"
  (list 'answer (list 0 "" "") #t '("127.0.0.1" "127.0.0.1") #t)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-origin
     (lambda (o)
       (let ((version (capture-command (list node "--version"))))
         (list 'answer
               (list (car version)
                     (if (string=? (cadr version) (string-append (origin-node o) "\n")) "" (cadr version))
                     (caddr version))
               (and (integer? (origin-pid o)) (positive? (origin-pid o)))
               (map (lambda (face) (car (origin-face o face))) '(http raw))
               (for-all (lambda (face) (< 0 (cdr (origin-face o face)) 65536)) '(http raw))))))))

(test-equal "origin-face: an unknown face raises, by name"
  '(assertion-violation origin-face (https))
  (guard (e (#t (list 'raised (describe e))))
    (call-with-origin (lambda (o) (refusal-of (lambda () (origin-face o 'https)))))))

(test-equal "origin-face: what is not an origin raises"
  '(assertion-violation origin-face (not-an-origin))
  (refusal-of (lambda () (origin-face 'not-an-origin 'http))))

(test-equal "call-with-origin: PROC is a procedure"
  '(assertion-violation call-with-origin (proc))
  (refusal-of (lambda () (call-with-origin 'proc))))

(test-equal "origin-script and origin-timeout refuse what they cannot use"
  '((assertion-violation origin-script (""))
    (assertion-violation origin-timeout (0))
    (assertion-violation origin-timeout (1.5)))
  (list (refusal-of (lambda () (parameterize ((origin-script "")) 'set)))
        (refusal-of (lambda () (parameterize ((origin-timeout 0)) 'set)))
        (refusal-of (lambda () (parameterize ((origin-timeout 1.5)) 'set)))))

;; ends : Origin -> (Listof End)
;; How a probe of each face ends.
(define (ends o)
  (map (lambda (face) (probe-end (wire-probe o face (string->utf8 "GET / HTTP/1.1\r\n\r\n") 2000)))
       '(http raw)))

(define both-refused '((refused "ECONNREFUSED") (refused "ECONNREFUSED")))

(test-equal "call-with-origin: once PROC returns, the origin has exited, so every face refuses"
  (list both-refused)
  (guard (e (#t (list 'raised (describe e))))
    (let ((o (call-with-origin (lambda (o) o))))
      (list (ends o)))))

(test-equal "call-with-origin: when PROC raises, the raise goes on unchanged, and the origin has exited"
  (list 'boom both-refused)
  (let ((kept #f))
    (guard (e ((eq? e 'boom) (list e (guard (e (#t (list 'raised (describe e)))) (ends kept))))
              (#t (list 'other e)))
      (call-with-origin (lambda (o) (set! kept o) (raise 'boom)))
      'no-raise)))

(test-equal "call-with-origin: when PROC escapes, the origin has exited"
  (list 'escaped both-refused)
  (let* ((kept #f)
         (value (call/cc (lambda (k) (call-with-origin (lambda (o) (set! kept o) (k 'escaped)))))))
    (list value (guard (e (#t (list 'raised (describe e)))) (ends kept)))))

(test-equal "wire-probe: the whole bytes, the end, and arrivals from offset 0 that account for every byte"
  '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof 0 counted)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-origin
     (lambda (o)
       (let* ((p (wire-probe o 'raw (string->utf8 "GET /raw/content-length HTTP/1.1\r\n\r\n") 2000))
              (offsets (map car (probe-arrivals p))))
         (list (utf8->string (probe-bytes p)) (probe-end p) (car offsets)
               (if (equal? offsets (list-sort < offsets)) 'counted offsets)))))))

(test-equal "wire-probe: a face that is gone is refused, with no bytes and no arrivals"
  '(#vu8() (refused "ECONNREFUSED") ())
  (guard (e (#t (list 'raised (describe e))))
    (let* ((o (call-with-origin (lambda (o) o)))
           (p (wire-probe o 'http (make-bytevector 0) 2000)))
      (list (probe-bytes p) (probe-end p) (probe-arrivals p)))))

(test-equal "wire-probe refuses an unknown face, bytes that are not a bytevector, and an idle bound that is not positive"
  '((assertion-violation origin-face (https))
    (assertion-violation wire-probe ("GET"))
    (assertion-violation wire-probe (0)))
  (guard (e (#t (list 'raised (describe e))))
    (call-with-origin
     (lambda (o)
       (list (refusal-of (lambda () (wire-probe o 'https (make-bytevector 0) 100)))
             (refusal-of (lambda () (wire-probe o 'raw "GET" 100)))
             (refusal-of (lambda () (wire-probe o 'raw (make-bytevector 0) 0))))))))

;; echoed : Natural -> (List Natural String)
;; A raw echo request head of exactly N bytes, and the response the raw face
;; gives it, written here: the head, with its length as Content-Length.
(define (echoed n)
  (let* ((before "GET /raw/echo HTTP/1.1\r\nX-Pad: ")
         (after "\r\n\r\n")
         (head (string-append before (make-string (- n (string-length before) (string-length after)) #\p)
                              after)))
    (list head (string-append "HTTP/1.1 200 OK\r\nContent-Length: " (number->string n) "\r\n\r\n" head))))

(test-equal "wire-probe: 16384 bytes go in the probe's argument, 16385 through a file, and both arrive whole; the file is removed"
  '((16384 same eof) (16385 same eof) ())
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (call-with-env "TMPDIR" dir
         (lambda ()
           (let ((sent (call-with-origin
                        (lambda (o)
                          (map (lambda (n)
                                 (let* ((pair (echoed n))
                                        (p (wire-probe o 'raw (string->utf8 (car pair)) 2000)))
                                   (list (string-length (car pair))
                                         (if (equal? (probe-bytes p) (string->utf8 (cadr pair))) 'same 'differs)
                                         (probe-end p))))
                               '(16384 16385))))))
             ;; call-with-origin's own directory is gone by now, too.
             (append sent (list (directory-list dir))))))))))

(test-equal "wire-probe-reset: the probe sends, then resets, so its end is reset-sent, with nothing received"
  '(#vu8() reset-sent ())
  (guard (e (#t (list 'raised (describe e))))
    (call-with-origin
     (lambda (o)
       (let ((p (wire-probe-reset o 'raw (string->utf8 "GET /raw/content-length HTTP/1.1\r\n"))))
         (list (probe-bytes p) (probe-end p) (probe-arrivals p)))))))

(test-equal "wire-probe-reset refuses an unknown face and bytes that are not a bytevector"
  '((assertion-violation origin-face (https))
    (assertion-violation wire-probe-reset ("GET")))
  (guard (e (#t (list 'raised (describe e))))
    (call-with-origin
     (lambda (o)
       (list (refusal-of (lambda () (wire-probe-reset o 'https (make-bytevector 0))))
             (refusal-of (lambda () (wire-probe-reset o 'raw "GET"))))))))

;; --- call-with-origin, with stand-ins
;; Every raise carries what the origin wrote to stdout and stderr and its exit
;; status, which the runner shell records, compared whole.

;; with-stand-in : String (-> Any) -> Any
;; THUNK with origin-script naming a module holding SOURCE, in a fresh
;; temporary directory.
(define (with-stand-in source thunk)
  (call-with-temp-directory
   (lambda (dir)
     (let ((path (string-append dir "/stand-in.mjs")))
       (write-file path source)
       (parameterize ((origin-script path)) (thunk))))))

;; announcing : String -> String
;; A stand-in that writes TEXT to stdout, then exits 0 when its stdin ends.
(define (announcing text)
  (string-append "process.stdout.write(" (write-text text) ");\n"
                 "process.stdin.resume();\n"
                 "process.stdin.on('end', () => process.exit(0));\n"))

;; announced : String -> String
;; JavaScript that writes a good announcement, with the stand-in's own pid
;; and two faces nothing serves, then runs AT-END when its stdin ends.
(define (announced at-end)
  (string-append
   "process.stdout.write(JSON.stringify({ node: process.version, pid: process.pid,"
   " http: '127.0.0.1:1', raw: '127.0.0.1:2' }) + '\\n');\n"
   "process.stdin.resume();\n"
   "process.stdin.on('end', () => { " at-end " });\n"))

;; good-faces : String
;; A stand-in's two faces, which nothing serves.
(define good-faces "\"http\":\"127.0.0.1:1\",\"raw\":\"127.0.0.1:2\"")

;; no-proc : -> Any
;; The refusal call-with-origin raises with a PROC that never runs.
(define (no-proc) (refusal-of (lambda () (call-with-origin (lambda (o) 'never-called)))))

(test-equal "call-with-origin raises, with stderr and exit status, on an origin that dies before announcing"
  '(call-with-origin "the origin's stdout ended before its announcement"
                     ((stdout . "") (stderr . "dying early\n") (status . 3)))
  (with-stand-in "process.stderr.write('dying early\\n');\nprocess.exit(3);\n" no-proc))

(test-equal "call-with-origin raises, with stdout and stderr, on an origin that announces garbage"
  '(call-with-origin "the origin's announcement is malformed: an announcement is one JSON object, from { to }"
                     ((stdout . "hello\n") (stderr . "about to say hello\n") (status . 0)))
  (with-stand-in (string-append "process.stderr.write('about to say hello\\n');\n" (announcing "hello\n"))
    no-proc))

(for-each
 (lambda (row)
   (let ((line (car row)) (problem (cadr row)))
     (test-equal (string-append "call-with-origin raises on a malformed announcement: " problem)
       (list 'call-with-origin (string-append "the origin's announcement is malformed: " problem)
             (list (cons 'stdout (string-append line "\n")) (cons 'stderr "") (cons 'status 0)))
       (with-stand-in (announcing (string-append line "\n")) no-proc))))
 (list (list "{\"node\":\"v1\",\"pid\":1,\"http\":\"127.0.0.1:1\"}"
             "its keys are node, pid, http, not node, pid, http, raw")
       (list (string-append "{\"pid\":1,\"node\":\"v1\"," good-faces "}")
             "its keys are pid, node, http, raw, not node, pid, http, raw")
       (list (string-append "{\"node\":5,\"pid\":1," good-faces "}") "its node is not a string")
       (list (string-append "{\"node\":\"v1\",\"pid\":0," good-faces "}") "its pid is not a positive natural")
       (list (string-append "{\"node\":\"v1\",\"pid\":\"1\"," good-faces "}") "its pid is not a positive natural")
       (list "{\"node\":\"v1\",\"pid\":1,\"http\":\"127.0.0.1\",\"raw\":\"127.0.0.1:2\"}"
             "its http face is not ADDRESS:PORT")
       (list "{\"node\":\"v1\",\"pid\":1,\"http\":\"127.0.0.1:1\",\"raw\":\"127.0.0.1:65536\"}"
             "its raw face is not ADDRESS:PORT")
       (list "{\"node\":\"v1\",\"pid\":1,\"http\":\":1\",\"raw\":\"127.0.0.1:2\"}"
             "its http face is not ADDRESS:PORT")
       (list "{\"node\":\"v1\",\"pid\":1,\"http\":\"127.0.0.1:01\",\"raw\":\"127.0.0.1:2\"}"
             "its http face is not ADDRESS:PORT")
       (list "{\"node\":\"v1\",\"pid\":1,\"http\":1,\"raw\":\"127.0.0.1:2\"}"
             "its http face is not ADDRESS:PORT")
       (list (string-append "{\"node\":\"v1\",\"pid\":1," good-faces "}")
             "its pid is not that of the Node process call-with-origin started")))

(test-equal "call-with-origin raises on an origin that writes a second line with its announcement"
  (list 'call-with-origin "the origin wrote to stdout after its announcement"
        (list (cons 'stdout (string-append "{\"node\":\"v1\",\"pid\":1," good-faces "}\nmore\n"))
              (cons 'stderr "") (cons 'status 0)))
  (with-stand-in (announcing (string-append "{\"node\":\"v1\",\"pid\":1," good-faces "}\nmore\n"))
    no-proc))

(test-equal "call-with-origin raises when no announcement comes within origin-timeout"
  '(call-with-origin "the origin wrote no announcement within 500 ms"
                     ((stdout . "") (stderr . "") (status . 0)))
  (with-stand-in "process.stdin.resume();\nprocess.stdin.on('end', () => process.exit(0));\n"
    (lambda () (parameterize ((origin-timeout 500)) (no-proc)))))

;; --- call-with-origin: once PROC returns, a clean ending, by evidence

;; ending-of : String -> Any
;; What call-with-origin raises, or no-raise, with a stand-in announcing well
;; and running AT-END when its stdin ends, and a PROC that returns.
(define (ending-of at-end)
  (with-stand-in (announced at-end)
    (lambda () (refusal-of (lambda () (call-with-origin (lambda (o) 'returned)))))))

(for-each
 (lambda (row)
   (test-equal (string-append "call-with-origin, once PROC returns, refuses an origin that " (car row))
     (caddr row)
     (ending-of (cadr row))))
 (list (list "exits 1 and writes to stderr"
             "process.stderr.write('bye\\n', () => process.exit(1));"
             '(call-with-origin "the origin did not end cleanly: it wrote to stderr; it exited 1"
                                ((stdout . "") (stderr . "bye\n") (status . 1))))
       (list "exits 1, writing nothing"
             "process.exit(1);"
             '(call-with-origin "the origin did not end cleanly: it exited 1"
                                ((stdout . "") (stderr . "") (status . 1))))
       (list "exits 0 but writes to stderr"
             "process.stderr.write('a warning\\n', () => process.exit(0));"
             '(call-with-origin "the origin did not end cleanly: it wrote to stderr"
                                ((stdout . "") (stderr . "a warning\n") (status . 0))))
       (list "writes to stdout after its announcement"
             "process.stdout.write('goodbye\\n', () => process.exit(0));"
             '(call-with-origin "the origin did not end cleanly: it wrote to stdout after its announcement"
                                ((stdout . "goodbye\n") (stderr . "") (status . 0))))
       (list "exits 0, writing nothing: no raise"
             "process.exit(0);"
             'no-raise)))

;; An origin whose one face answers a request, then dies at once.
(define dies-after-answering
  (string-append
   "import net from 'node:net';\n"
   "const server = net.createServer((s) => {\n"
   "  s.on('data', () => s.end('hello\\n', () => { process.stderr.write('died\\n'); process.exit(7); }));\n"
   "}).listen(0, '127.0.0.1', () => {\n"
   "  const face = `127.0.0.1:${server.address().port}`;\n"
   "  process.stdout.write(JSON.stringify({ node: process.version, pid: process.pid, http: face, raw: face }) + '\\n');\n"
   "  process.stdin.resume();\n"
   "  process.stdin.on('end', () => process.exit(0));\n"
   "});\n"))

(test-equal "call-with-origin: an origin that dies right after answering a request, its answer whole, fails the call once PROC returns"
  '(("hello\n" eof)
    (call-with-origin "the origin did not end cleanly: it wrote to stderr; it exited 7"
                      ((stdout . "") (stderr . "died\n") (status . 7))))
  (with-stand-in dies-after-answering
    (lambda ()
      (let* ((answer #f)
             (raised (refusal-of
                      (lambda ()
                        (call-with-origin
                         (lambda (o)
                           (let ((p (wire-probe o 'raw (string->utf8 "GET") 2000)))
                             (set! answer (list (utf8->string (probe-bytes p)) (probe-end p))))
                           ;; Time for the death to happen within the call.
                           (sleep (make-time 'time-duration 100000000 0))))))))
        (list answer raised)))))

;; An origin that announces a face it really serves, and ignores stdin's end.
(define deaf-origin
  (string-append
   "import net from 'node:net';\n"
   "const server = net.createServer((s) => s.end('deaf\\n')).listen(0, '127.0.0.1', () => {\n"
   "  const face = `127.0.0.1:${server.address().port}`;\n"
   "  process.stdout.write(JSON.stringify({ node: process.version, pid: process.pid, http: face, raw: face }) + '\\n');\n"
   "  process.stdin.resume();\n"
   "});\n"))

(test-equal "call-with-origin: an origin that ignores stdin's end is killed after origin-timeout, and the raise says so; until then it served"
  '((call-with-origin "the origin's stdout did not end within 1000 ms of its stdin closing, so it was killed"
                      ((stdout . "") (stderr . "") (status . 137)))
    ("deaf\n" eof)
    ((refused "ECONNREFUSED") (refused "ECONNREFUSED")))
  (with-stand-in deaf-origin
    (lambda ()
      (parameterize ((origin-timeout 1000))
        (let* ((kept #f)
               (served #f)
               (raised (refusal-of
                        (lambda ()
                          (call-with-origin
                           (lambda (o)
                             (set! kept o)
                             (set! served (let ((p (wire-probe o 'raw (make-bytevector 0) 2000)))
                                            (list (utf8->string (probe-bytes p)) (probe-end p))))))))))
          (list raised served (if kept (ends kept) 'no-origin)))))))

(for-each
 (lambda (row)
   (test-equal (string-append "call-with-origin: when PROC raises, its raise goes on unchanged, with an origin that "
                              (car row) ", and the origin is stopped")
     (list 'boom both-refused)
     (with-stand-in (cadr row)
       (lambda ()
         (parameterize ((origin-timeout 1000))
           (let ((kept #f))
             (guard (e ((eq? e 'boom) (list e (guard (e (#t (list 'raised (describe e)))) (ends kept))))
                       (#t (list 'other (describe e))))
               (call-with-origin (lambda (o) (set! kept o) (raise 'boom)))
               'no-raise)))))))
 (list (list "exits 1 with stderr"
             (string-append
              "import net from 'node:net';\n"
              "const server = net.createServer((s) => s.end('x\\n')).listen(0, '127.0.0.1', () => {\n"
              "  const face = `127.0.0.1:${server.address().port}`;\n"
              "  process.stdout.write(JSON.stringify({ node: process.version, pid: process.pid, http: face, raw: face }) + '\\n');\n"
              "  process.stdin.resume();\n"
              "  process.stdin.on('end', () => process.stderr.write('bye\\n', () => process.exit(1)));\n"
              "});\n"))
       (list "ignores stdin's end, so it is killed" deaf-origin)))

;; --- call-with-origin: every wait is bounded by the clock

;; flood-after, flood-before : String
;; Stand-ins that flood stdout with x, without end: once stdin ends, and from
;; the start. They write synchronously, again as soon as the pipe has room
;; (Node's stdout pipe is non-blocking, so a full one answers EAGAIN), so the
;; pipe stays full and input-port-ready? is never false: a reader that read
;; its deadline only when nothing was ready would read forever. Written
;; asynchronously, a flood leaves the pipe empty now and then, and lets such
;; a reader through (measured).
(define flood-loop
  (string-append "const b = Buffer.alloc(65536, 120);"
                 " for (;;) { try { writeSync(1, b); } catch (e) { if (e.code !== 'EAGAIN') throw e; } }"))
(define flood-after
  (string-append "import { writeSync } from 'node:fs';\n" (announced flood-loop)))
(define flood-before
  (string-append "import { writeSync } from 'node:fs';\n" flood-loop "\n"))

;; timed : (-> Any) -> (List Any Natural)
;; THUNK's answer, and the milliseconds it took by the monotonic clock.
(define (timed thunk)
  (let* ((start (current-time 'time-monotonic))
         (answer (thunk))
         (took (time-difference (current-time 'time-monotonic) start)))
    (list answer (+ (* 1000 (time-second took)) (div (time-nanosecond took) 1000000)))))

(for-each
 (lambda (row)
   (test-equal (string-append "call-with-origin: an origin that floods stdout " (car row)
                              " is killed, and the call raises within 2000 ms, with origin-timeout 1000")
     (list (cadr row) 'within-2000-ms)
     (with-stand-in (caddr row)
       (lambda ()
         (parameterize ((origin-timeout 1000))
           (let ((got (timed (lambda ()
                               (refusal-of (lambda () (call-with-origin (lambda (o) 'returned))))))))
             (list (car got) (if (<= (cadr got) 2000) 'within-2000-ms (list 'took (cadr got))))))))))
 (list (list "once its stdin ends"
             (list 'call-with-origin
                   "the origin's stdout did not end within 1000 ms of its stdin closing, so it was killed"
                   (list (cons 'stdout (make-string 4096 #\x)) (cons 'stderr "") (cons 'status 137)))
             flood-after)
       (list "from the start, with no newline"
             (list 'call-with-origin
                   "the origin wrote 4096 bytes to stdout with no newline, so no announcement"
                   (list (cons 'stdout (make-string 4096 #\x)) (cons 'stderr "") (cons 'status 137)))
             flood-before)))

;; An origin that records how the last connection on its one face ended,
;; ECONNRESET or FIN, and tells it to a client that sends "report", whose own
;; ending it does not record.
(define ending-recorder
  (string-append
   "import net from 'node:net';\n"
   "let last = 'none';\n"
   "const server = net.createServer((s) => {\n"
   "  let reporting = false;\n"
   "  s.on('error', (e) => { if (!reporting) last = e.code; });\n"
   "  s.on('end', () => { if (!reporting) last = 'FIN'; });\n"
   "  s.on('data', (d) => {\n"
   "    if (d.toString() === 'report') { reporting = true; s.end(`${last}\\n`); }\n"
   "  });\n"
   "}).listen(0, '127.0.0.1', () => {\n"
   "  const face = `127.0.0.1:${server.address().port}`;\n"
   "  process.stdout.write(JSON.stringify({ node: process.version, pid: process.pid, http: face, raw: face }) + '\\n');\n"
   "  process.stdin.resume();\n"
   "  process.stdin.on('end', () => process.exit(0));\n"
   "});\n"))

(test-equal "wire-probe-reset: the peer sees a reset, ECONNRESET, where wire-probe's end is a FIN"
  '((reset-sent ("ECONNRESET\n" eof)) (timeout ("FIN\n" eof)))
  (with-stand-in ending-recorder
    (lambda ()
      (guard (e (#t (list 'raised (describe e))))
        (call-with-origin
         (lambda (o)
           (let ((report (lambda ()
                           ;; Time for the stand-in to take the last ending in.
                           (sleep (make-time 'time-duration 100000000 0))
                           (let ((p (wire-probe o 'raw (string->utf8 "report") 2000)))
                             (list (utf8->string (probe-bytes p)) (probe-end p))))))
             (let* ((reset (probe-end (wire-probe-reset o 'raw (string->utf8 "hello"))))
                    (after-reset (report))
                    (closed (probe-end (wire-probe o 'raw (string->utf8 "hello") 100)))
                    (after-close (report)))
               (list (list reset after-reset) (list closed after-close))))))))))

;; An origin whose one face, half-open, answers a client's FIN with "saw FIN".
(define fin-answerer
  (string-append
   "import net from 'node:net';\n"
   "const server = net.createServer({ allowHalfOpen: true }, (s) => {\n"
   "  s.on('data', () => {});\n"
   "  s.on('end', () => s.end('saw FIN\\n'));\n"
   "}).listen(0, '127.0.0.1', () => {\n"
   "  const face = `127.0.0.1:${server.address().port}`;\n"
   "  process.stdout.write(JSON.stringify({ node: process.version, pid: process.pid, http: face, raw: face }) + '\\n');\n"
   "  process.stdin.resume();\n"
   "  process.stdin.on('end', () => process.exit(0));\n"
   "});\n"))

(test-equal "wire-probe-half-close: the peer sees a FIN once the bytes are sent, and the probe reads its answer; wire-probe sends none"
  '(("saw FIN\n" eof) ("" timeout))
  (with-stand-in fin-answerer
    (lambda ()
      (guard (e (#t (list 'raised (describe e))))
        (call-with-origin
         (lambda (o)
           (map (lambda (p) (list (utf8->string (probe-bytes p)) (probe-end p)))
                (list (wire-probe-half-close o 'raw (string->utf8 "hello") 2000)
                      (wire-probe o 'raw (string->utf8 "hello") 200)))))))))

(test-equal "wire-probe-half-close refuses an unknown face, bytes that are not a bytevector, and an idle bound that is not positive"
  '((assertion-violation origin-face (https))
    (assertion-violation wire-probe-half-close ("GET"))
    (assertion-violation wire-probe-half-close (0)))
  (guard (e (#t (list 'raised (describe e))))
    (call-with-origin
     (lambda (o)
       (list (refusal-of (lambda () (wire-probe-half-close o 'https (make-bytevector 0) 100)))
             (refusal-of (lambda () (wire-probe-half-close o 'raw "GET" 100)))
             (refusal-of (lambda () (wire-probe-half-close o 'raw (make-bytevector 0) 0))))))))

(test-equal "wire-probe-deadline: a peer that keeps sending ends the probe at the deadline, by the clock, with what came by then"
  '(deadline prefix within-1500-ms)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-origin
     (lambda (o)
       (let* ((got (timed (lambda ()
                            (parameterize ((wire-probe-deadline 300))
                              (wire-probe o 'raw (string->utf8 "GET /raw/drip?bytes=4096&gap=1 HTTP/1.1\r\n\r\n")
                                          2000)))))
              (p (car got))
              (bytes (utf8->string (probe-bytes p)))
              (whole (string-append "HTTP/1.1 200 OK\r\nContent-Length: 4096\r\n\r\n"
                                    (let loop ((i 0) (acc '()))
                                      (if (= i 4096)
                                          (list->string (reverse acc))
                                          (loop (+ i 1) (cons (integer->char (+ 97 (mod i 26))) acc)))))))
         (list (probe-end p)
               (if (and (< (string-length bytes) (string-length whole))
                        (string=? bytes (substring whole 0 (string-length bytes))))
                   'prefix
                   (list 'not-a-prefix (string-length bytes)))
               (if (<= (cadr got) 1500) 'within-1500-ms (list 'took (cadr got)))))))))

(test-equal "wire-probe-deadline refuses what is not a positive exact integer"
  '((assertion-violation wire-probe-deadline (0)) (assertion-violation wire-probe-deadline (1.5)))
  (list (refusal-of (lambda () (parameterize ((wire-probe-deadline 0)) 'set)))
        (refusal-of (lambda () (parameterize ((wire-probe-deadline 1.5)) 'set)))))

;; --- read-within: the bounded read

;; with-file : String (Binary-Input-Port -> Any) -> Any
;; PROC on a binary input port reading a temporary file holding TEXT.
(define (with-file text proc)
  (call-with-temp-directory
   (lambda (dir)
     (let ((path (string-append dir "/f")))
       (write-file path text)
       (call-with-port (open-file-input-port path) proc)))))

(test-equal "read-within: it stops when DONE? holds of a piece it kept, keeping that piece whole"
  '(done "ab\ncd")
  (with-file "ab\ncd" (lambda (p) (let-values (((how bytes) (read-within p 1000 (lambda (b) (and (memv 10 (bytevector->u8-list b)) #t)) #t)))
                                    (list how (utf8->string bytes))))))

(test-equal "read-within: it stops at the end, with all it read"
  '(eof "abc")
  (with-file "abc" (lambda (p) (let-values (((how bytes) (read-within p 1000 (lambda (b) #f) #t)))
                                 (list how (utf8->string bytes))))))

(test-equal "read-within: with FULL-STOPS?, it stops once it has kept 4096 bytes"
  '(full 4096)
  (call-with-port (open-file-input-port "/dev/zero")
    (lambda (p) (let-values (((how bytes) (read-within p 1000 (lambda (b) #f) #t)))
                  (list how (bytevector-length bytes))))))

(test-equal "read-within: its bound is a positive exact integer"
  '(assertion-violation read-within (0))
  (refusal-of (lambda () (read-within (open-bytevector-input-port #vu8()) 0 (lambda (b) #f) #t))))

;; /dev/zero is always ready and never ends, as no pipe can be kept: a flood
;; through one leaves it empty now and then (measured). A reader that read the
;; clock only when nothing was ready would never stop there, so the read runs
;; in a child Chez under GNU timeout (gtimeout on macOS), killed after 10 s:
;; the test fails by name, and does not hang the suite.
(test-equal "read-within: on /dev/zero, a port always ready with no end, it stops at its deadline of 300 ms, by the clock, within 1000 ms, keeping 4096 bytes"
  '(0 "(timeout 4096 within-1000-ms)\n" "")
  (call-with-temp-directory
   (lambda (dir)
     (let ((program (string-append dir "/zero.sps")))
       (write-file program
                   (string-append
                    "(import (rnrs) (curl-testing) (only (chezscheme) current-time time-second time-nanosecond))\n"
                    "(define (now) (let ((t (current-time 'time-monotonic))) (+ (* 1000 (time-second t)) (div (time-nanosecond t) 1000000))))\n"
                    "(define start (now))\n"
                    "(let-values (((how bytes) (read-within (open-file-input-port \"/dev/zero\") 300 (lambda (b) #f) #f)))\n"
                    "  (write (list how (bytevector-length bytes) (if (<= (- (now) start) 1000) 'within-1000-ms (- (now) start))))\n"
                    "  (newline))\n"))
       (capture-command
        (list "sh" "-c"
              "t=$(command -v timeout || command -v gtimeout) || exit 125; exec \"$t\" -s KILL 10 \"$@\""
              "sh" chez "--libdirs" "tests:build/scheme-libs" "--program" program))))))

;; --- parse-wire-probe

(test-equal "parse-wire-probe: the probe's lines, as the bytes joined, the end, each arrival and when it connected"
  '(#vu8(104 105 33) eof ((0 . 8) (2 . 9)) 7)
  (guard (e (#t (list 'raised (describe e))))
    (let ((p (parse-wire-probe "(connected 7)\n(data 0 8 \"6869\")\n(data 2 9 \"21\")\n(end eof 10)\n")))
      (list (probe-bytes p) (probe-end p) (probe-arrivals p) (probe-connected p)))))

(test-equal "parse-wire-probe: a refused probe never connected"
  '((refused "ECONNREFUSED") #f)
  (guard (e (#t (list 'raised (describe e))))
    (let ((p (parse-wire-probe "(refused \"ECONNREFUSED\" 3)\n")))
      (list (probe-end p) (probe-connected p)))))

(test-equal "parse-wire-probe: each other end: reset, timeout, a deadline, an error with its code, a reset sent, and a refusal"
  '(reset timeout deadline (error "EPIPE") reset-sent (refused "ECONNREFUSED"))
  (map (lambda (text) (guard (e (#t (list 'raised (describe e)))) (probe-end (parse-wire-probe text))))
       '("(connected 0)\n(data 0 1 \"00\")\n(end reset 1)\n"
         "(connected 0)\n(end timeout 200)\n"
         "(connected 0)\n(end deadline 300)\n"
         "(connected 0)\n(end error 5 \"EPIPE\")\n"
         "(connected 0)\n(reset-sent 1)\n"
         "(refused \"ECONNREFUSED\" 3)\n")))

(for-each
 (lambda (row)
   (test-equal (string-append "parse-wire-probe refuses " (car row))
     (list 'parse-wire-probe (cadr row) (list (caddr row)))
     (refusal-of (lambda () (parse-wire-probe (cadddr row))))))
 (list
  (list "no output" "the probe printed nothing" "" "")
  (list "text that is not Scheme data" "the probe's output is not Scheme data" "(connected" "(connected")
  (list "a first line that is neither connected nor refused" "the first line is (connected MS) or (refused \"CODE\" MS)"
        '(end eof 1) "(end eof 1)\n")
  (list "a malformed refused line" "a refused line is (refused \"CODE\" MS)"
        '(refused ECONNREFUSED 1) "(refused ECONNREFUSED 1)\n")
  (list "a line after a refusal" "nothing follows a refused line"
        '(end eof 2) "(refused \"ECONNREFUSED\" 1)\n(end eof 2)\n")
  (list "no end line" "the probe's output has no end line"
        "(connected 0)\n(data 0 1 \"61\")\n" "(connected 0)\n(data 0 1 \"61\")\n")
  (list "an offset that skips a byte" "a data line's offset is not the count of bytes before it"
        '(data 2 1 "62") "(connected 0)\n(data 0 1 \"61\")\n(data 2 1 \"62\")\n(end eof 2)\n")
  (list "a first offset that is not 0" "a data line's offset is not the count of bytes before it"
        '(data 1 1 "61") "(connected 0)\n(data 1 1 \"61\")\n(end eof 2)\n")
  (list "upper-case hex" "a data line's HEX is one byte or more, as lower-case hex"
        '(data 0 1 "4A") "(connected 0)\n(data 0 1 \"4A\")\n(end eof 2)\n")
  (list "an odd count of hex digits" "a data line's HEX is one byte or more, as lower-case hex"
        '(data 0 1 "616") "(connected 0)\n(data 0 1 \"616\")\n(end eof 2)\n")
  (list "a data line with no bytes" "a data line's HEX is one byte or more, as lower-case hex"
        '(data 0 1 "") "(connected 0)\n(data 0 1 \"\")\n(end eof 2)\n")
  (list "a data line of three items" "a data line is (data OFFSET MS \"HEX\")"
        '(data 0 "61") "(connected 0)\n(data 0 \"61\")\n(end eof 2)\n")
  (list "a time less than the one before it" "a time is less than the one before it"
        '(data 0 4 "61") "(connected 5)\n(data 0 4 \"61\")\n(end eof 6)\n")
  (list "an end time less than the one before it" "a time is less than the one before it"
        '(end eof 3) "(connected 0)\n(data 0 4 \"61\")\n(end eof 3)\n")
  (list "an end of no known kind" "an end line is (end KIND MS), (end error MS \"CODE\") or (reset-sent MS)"
        '(end weird 3) "(connected 0)\n(end weird 3)\n")
  (list "an error end without its code" "an end line is (end KIND MS), (end error MS \"CODE\") or (reset-sent MS)"
        '(end error 3) "(connected 0)\n(end error 3)\n")
  (list "a line after the end" "nothing follows the end line"
        '(data 0 4 "61") "(connected 0)\n(end eof 3)\n(data 0 4 \"61\")\n")
  (list "a line of no known kind" "a line is (data ...), (end ...) or (reset-sent MS)"
        '(chunk 0 1 "61") "(connected 0)\n(chunk 0 1 \"61\")\n(end eof 3)\n")
  (list "a reset-sent line without its time" "an end line is (end KIND MS), (end error MS \"CODE\") or (reset-sent MS)"
        '(reset-sent) "(connected 0)\n(reset-sent)\n")
  (list "a reset-sent time less than the one before it" "a time is less than the one before it"
        '(reset-sent 3) "(connected 0)\n(data 0 4 \"61\")\n(reset-sent 3)\n")
  (list "a line after reset-sent" "nothing follows the end line"
        '(end reset 5) "(connected 0)\n(reset-sent 3)\n(end reset 5)\n")))

(test-equal "parse-wire-probe: its argument is a string"
  '(assertion-violation parse-wire-probe (5))
  (refusal-of (lambda () (parse-wire-probe 5))))

(test-end "curl-testing")

;; This suite tests suite-exit-status, so its exit cannot rest on it alone:
;; a suite-exit-status that ignored failures would pass this suite, and
;; make test with it. Any failure here exits 1 first.
(when (positive? (test-runner-fail-count runner))
  (exit 1))

(exit (suite-exit-status runner))
