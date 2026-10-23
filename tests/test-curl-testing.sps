#!r6rs
;;; The suite for (curl-testing), the helpers every suite shares (ADR-0015):
;;; the verdict behind the shared exit form, then capture-command, the
;;; temporary directories, run-until, seeded-bytes and describe; the test
;;; origin's lifecycle, its announcement and the byte probe; and bounded, the
;;; TLS material and its openssl checker. The parsers are held to synthetic
;;; outputs in OpenSSL 3.5.7's and LibreSSL 3.3.6's formats, their
;;; certificates' base64 made here: no real certificate or key is checked in
;;; (ADR-0005).
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
        (curl private counters)
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

;; --- the counters' rule (ADR-0014, decision 7, amended) ---
;; Each raises counts on purpose, and lowers them again under dynamic-wind,
;; so this suite's own exit, which reads the same counts, sees zero.

;; with-counts : (Listof Symbol) (-> Any) -> Any
;; THUNK's answer, with one more of each kind in KINDS counted while it runs.
(define (with-counts kinds thunk)
  (dynamic-wind
    (lambda () (for-each count-up! kinds))
    thunk
    (lambda () (for-each count-down! kinds))))

(define counts-tail "): every native object a suite makes must be freed by its end\n")

(test-equal "a pass, and native objects left: exit 1, one line naming each count not zero, in the counters' order"
  (list 1 (string-append "suite-exit-status: exit 1 (native objects left: block 1, easy 2"
                         counts-tail))
  (with-counts '(easy block easy)
    (lambda () (verdict (runner-after (lambda () (test-assert "passes" #t)))))))

;; Each kind alone fails a suite that passed: a gate that read some kinds
;; only passes a test of two. Written out here, not read from native-kinds.
(for-each
 (lambda (kind)
   (test-equal (string-append "a pass, and one " (symbol->string kind)
                              " left alone: exit 1, the line naming it")
     (list 1 (string-append "suite-exit-status: exit 1 (native objects left: "
                            (symbol->string kind) " 1" counts-tail))
     (with-counts (list kind)
       (lambda () (verdict (runner-after (lambda () (test-assert "passes" #t))))))))
 '(block easy url slist curl-string transfer))

(test-equal "every kind left is named, each with its count"
  (list 1 (string-append "suite-exit-status: exit 1 (native objects left: block 1, easy 1, url 1, slist 1, curl-string 1, transfer 3"
                         counts-tail))
  (with-counts '(transfer curl-string slist url easy block transfer transfer)
    (lambda () (verdict (runner-after (lambda () (test-assert "passes" #t)))))))

(test-equal "a failure, and a native object left: both lines, the runner's first"
  (list 1 (string-append
           "suite-exit-status: exit 1 (pass 1, fail 1, xpass 0): a suite needs a pass, and no fail or xpass\n"
           "suite-exit-status: exit 1 (native objects left: url 1" counts-tail))
  (with-counts '(url)
    (lambda () (verdict (runner-after (lambda ()
                                        (test-assert "passes" #t)
                                        (test-assert "fails" #f)))))))

(test-equal "the counts are back at zero once with-counts returns: a pass exits 0, and nothing is said"
  (list '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0))
        '(0 ""))
  (list (native-counts)
        (verdict (runner-after (lambda () (test-assert "passes" #t))))))

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
                               (list chez "--libdirs" "src:tests:build/scheme-libs"
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

;; timed : (-> Any) -> (List Any Natural)
;; THUNK's answer, and the milliseconds it took by the monotonic clock.
(define (timed thunk)
  (let* ((start (current-time 'time-monotonic))
         (answer (thunk))
         (took (time-difference (current-time 'time-monotonic) start)))
    (list answer (+ (* 1000 (time-second took)) (div (time-nanosecond took) 1000000)))))

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
  (list 'answer (list 0 "" "") #t '("127.0.0.1" "127.0.0.1" "127.0.0.1") #t)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-origin
     (lambda (o)
       (let ((version (capture-command (list node "--version"))))
         (list 'answer
               (list (car version)
                     (if (string=? (cadr version) (string-append (origin-node o) "\n")) "" (cadr version))
                     (caddr version))
               (and (integer? (origin-pid o)) (positive? (origin-pid o)))
               (map (lambda (face) (car (origin-face o face))) '(http raw h2c))
               (for-all (lambda (face) (< 0 (cdr (origin-face o face)) 65536)) '(http raw h2c))))))))

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
;; and three faces nothing serves, then runs AT-END when its stdin ends.
(define (announced at-end)
  (string-append
   "process.stdout.write(JSON.stringify({ node: process.version, pid: process.pid,"
   " http: '127.0.0.1:1', raw: '127.0.0.1:2', h2c: '127.0.0.1:3' }) + '\\n');\n"
   "process.stdin.resume();\n"
   "process.stdin.on('end', () => { " at-end " });\n"))

;; good-faces : String
;; A stand-in's three faces, which nothing serves.
(define good-faces "\"http\":\"127.0.0.1:1\",\"raw\":\"127.0.0.1:2\",\"h2c\":\"127.0.0.1:3\"")

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
 (list (list "{\"node\":\"v1\",\"pid\":1,\"http\":\"127.0.0.1:1\",\"raw\":\"127.0.0.1:2\"}"
             "its keys are node, pid, http, raw, not node, pid, http, raw, h2c")
       (list (string-append "{\"pid\":1,\"node\":\"v1\"," good-faces "}")
             "its keys are pid, node, http, raw, h2c, not node, pid, http, raw, h2c")
       (list (string-append "{\"node\":\"v1\",\"pid\":1," good-faces ",\"https\":\"127.0.0.1:4\"}")
             "its keys are node, pid, http, raw, h2c, https, not node, pid, http, raw, h2c")
       (list (string-append "{\"node\":5,\"pid\":1," good-faces "}") "its node is not a string")
       (list (string-append "{\"node\":\"v1\",\"pid\":0," good-faces "}") "its pid is not a positive natural")
       (list (string-append "{\"node\":\"v1\",\"pid\":\"1\"," good-faces "}") "its pid is not a positive natural")
       (list "{\"node\":\"v1\",\"pid\":1,\"http\":\"127.0.0.1\",\"raw\":\"127.0.0.1:2\",\"h2c\":\"127.0.0.1:3\"}"
             "its http face is not ADDRESS:PORT")
       (list "{\"node\":\"v1\",\"pid\":1,\"http\":\"127.0.0.1:1\",\"raw\":\"127.0.0.1:65536\",\"h2c\":\"127.0.0.1:3\"}"
             "its raw face is not ADDRESS:PORT")
       (list "{\"node\":\"v1\",\"pid\":1,\"http\":\":1\",\"raw\":\"127.0.0.1:2\",\"h2c\":\"127.0.0.1:3\"}"
             "its http face is not ADDRESS:PORT")
       (list "{\"node\":\"v1\",\"pid\":1,\"http\":\"127.0.0.1:01\",\"raw\":\"127.0.0.1:2\",\"h2c\":\"127.0.0.1:3\"}"
             "its http face is not ADDRESS:PORT")
       (list "{\"node\":\"v1\",\"pid\":1,\"http\":1,\"raw\":\"127.0.0.1:2\",\"h2c\":\"127.0.0.1:3\"}"
             "its http face is not ADDRESS:PORT")
       (list "{\"node\":\"v1\",\"pid\":1,\"http\":\"127.0.0.1:1\",\"raw\":\"127.0.0.1:2\",\"h2c\":\"h2c\"}"
             "its h2c face is not ADDRESS:PORT")
       (list (string-append "{\"node\":\"v1\",\"pid\":1," good-faces "}")
             "its pid is not that of the Node process call-with-origin started")))

(test-equal "call-with-origin raises on an origin that writes a second line with its announcement"
  (list 'call-with-origin "the origin wrote to stdout after its announcement"
        (list (cons 'stdout (string-append "{\"node\":\"v1\",\"pid\":1," good-faces "}\nmore\n"))
              (cons 'stderr "") (cons 'status 0)))
  (with-stand-in (announcing (string-append "{\"node\":\"v1\",\"pid\":1," good-faces "}\nmore\n"))
    no-proc))

(test-equal "call-with-origin raises when no announcement comes within origin-timeout, 500 ms: not before them, and within 2000 ms"
  '((call-with-origin "the origin wrote no announcement within 500 ms"
                      ((stdout . "") (stderr . "") (status . 0)))
    waited-500-to-2000-ms)
  (with-stand-in "process.stdin.resume();\nprocess.stdin.on('end', () => process.exit(0));\n"
    (lambda ()
      (let ((got (timed (lambda () (parameterize ((origin-timeout 500)) (no-proc))))))
        (list (car got) (if (<= 500 (cadr got) 2000) 'waited-500-to-2000-ms (list 'took (cadr got))))))))

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
   "  process.stdout.write(JSON.stringify({ node: process.version, pid: process.pid, http: face, raw: face, h2c: face }) + '\\n');\n"
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
   "  process.stdout.write(JSON.stringify({ node: process.version, pid: process.pid, http: face, raw: face, h2c: face }) + '\\n');\n"
   "  process.stdin.resume();\n"
   "});\n"))

(test-equal "call-with-origin: an origin that ignores stdin's end is killed after origin-timeout, 1000 ms, not before them and within 3000 ms, and the raise says so; until then it served"
  '((call-with-origin "the origin's stdout did not end within 1000 ms of its stdin closing, so it was killed"
                      ((stdout . "") (stderr . "") (status . 137)))
    ("deaf\n" eof)
    ((refused "ECONNREFUSED") (refused "ECONNREFUSED"))
    killed-1000-to-3000-ms-after-proc)
  (with-stand-in deaf-origin
    (lambda ()
      (parameterize ((origin-timeout 1000))
        (let* ((kept #f)
               (served #f)
               (returned-at #f)
               (got (timed (lambda ()
                             (refusal-of
                              (lambda ()
                                (call-with-origin
                                 (lambda (o)
                                   (set! kept o)
                                   (set! served (let ((p (wire-probe o 'raw (make-bytevector 0) 2000)))
                                                  (list (utf8->string (probe-bytes p)) (probe-end p))))
                                   (set! returned-at (current-time 'time-monotonic)))))))))
               (since (and returned-at
                           (let ((d (time-difference (current-time 'time-monotonic) returned-at)))
                             (+ (* 1000 (time-second d)) (div (time-nanosecond d) 1000000))))))
          (list (car got) served (if kept (ends kept) 'no-origin)
                (if (and since (<= 1000 since 3000)) 'killed-1000-to-3000-ms-after-proc (list 'since-proc since))))))))

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
              "  process.stdout.write(JSON.stringify({ node: process.version, pid: process.pid, http: face, raw: face, h2c: face }) + '\\n');\n"
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
   "  process.stdout.write(JSON.stringify({ node: process.version, pid: process.pid, http: face, raw: face, h2c: face }) + '\\n');\n"
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
   "  process.stdout.write(JSON.stringify({ node: process.version, pid: process.pid, http: face, raw: face, h2c: face }) + '\\n');\n"
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
              "sh" chez "--libdirs" "src:tests:build/scheme-libs" "--program" program))))))

;; --- parse-wire-probe

(test-equal "parse-wire-probe: the probe's lines, as the bytes joined, the end, each arrival, when it connected and when it ended"
  '(#vu8(104 105 33) eof ((0 . 8) (2 . 9)) 7 10)
  (guard (e (#t (list 'raised (describe e))))
    (let ((p (parse-wire-probe "(connected 7)\n(data 0 8 \"6869\")\n(data 2 9 \"21\")\n(end eof 10)\n")))
      (list (probe-bytes p) (probe-end p) (probe-arrivals p) (probe-connected p) (probe-ended p)))))

(test-equal "parse-wire-probe: a refused probe never connected, and ended when it was refused"
  '((refused "ECONNREFUSED") #f 3)
  (guard (e (#t (list 'raised (describe e))))
    (let ((p (parse-wire-probe "(refused \"ECONNREFUSED\" 3)\n")))
      (list (probe-end p) (probe-connected p) (probe-ended p)))))

(test-equal "parse-wire-probe: each other end, and when: reset, timeout, a deadline, an error with its code, a reset sent, and a refusal"
  '((reset 1) (timeout 200) (deadline 300) ((error "EPIPE") 5) (reset-sent 4) ((refused "ECONNREFUSED") 3))
  (map (lambda (text)
         (guard (e (#t (list 'raised (describe e))))
           (let ((p (parse-wire-probe text))) (list (probe-end p) (probe-ended p)))))
       '("(connected 0)\n(data 0 1 \"00\")\n(end reset 1)\n"
         "(connected 0)\n(end timeout 200)\n"
         "(connected 0)\n(end deadline 300)\n"
         "(connected 0)\n(end error 5 \"EPIPE\")\n"
         "(connected 0)\n(reset-sent 4)\n"
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

;; --- bounded: capture-command under GNU timeout ----------------------------

(test-equal "bounded: the command's exit status, stdout and stderr, with stdin at its end"
  '(3 "out\n" "err\n")
  (bounded "sh" "-c" "cat; echo out; echo err >&2; exit 3"))

(test-equal "bounded: a command still running after 10 s is killed with SIGKILL, exit 137, within 12000 ms"
  '((137 "started\n" "") within-12000-ms)
  (let ((got (timed (lambda () (bounded "sh" "-c" "echo started; exec sleep 30")))))
    (list (car got) (if (<= (cadr got) 12000) 'within-12000-ms (list 'took (cadr got))))))

;; Children of system hold this process's pipe ends, an origin's stdin among
;; them, so anything bounded left running would hold that stdin open: the
;; origin would not see its end, and would be killed after origin-timeout.
(test-equal "bounded leaves nothing running: an origin whose call ran a bounded command stops cleanly"
  '(ran within-3000-ms)
  (guard (e (#t (list 'raised (describe e))))
    (parameterize ((origin-timeout 2000))
      (let ((got (timed (lambda () (call-with-origin (lambda (o) (bounded "true") 'ran))))))
        (list (car got) (if (<= (cadr got) 3000) 'within-3000-ms (list 'took (cadr got))))))))

(test-equal "bounded: with neither timeout nor gtimeout on PATH, it exits 125, saying so"
  '(125 "" "bounded: no timeout\n")
  (call-with-temp-directory
   (lambda (dir)
     (let ((sh (cadr (capture-command '("sh" "-c" "command -v sh")))))
       (capture-command (list "ln" "-s" (substring sh 0 (- (string-length sh) 1)) (string-append dir "/sh")))
       (call-with-env "PATH" dir (lambda () (bounded "true")))))))

(test-equal "bounded: every argument is a string"
  '(assertion-violation capture-command (5))
  (refusal-of (lambda () (bounded "echo" 5))))

;; --- openssl-program -----------------------------------------------------

;; with-openssl : String (-> Any) -> Any
;; THUNK with OPENSSL set to VALUE. Afterwards OPENSSL is put back, or set to
;; the empty string, which openssl-program reads as unset, when it was unset.
(define (with-openssl value thunk)
  (let ((old (getenv "OPENSSL")))
    (dynamic-wind
      (lambda () (putenv "OPENSSL" value))
      thunk
      (lambda () (putenv "OPENSSL" (or old ""))))))

(test-equal "openssl-program: OPENSSL from the environment, else openssl, an empty one included"
  '("/some/where/openssl" "openssl")
  (list (with-openssl "/some/where/openssl" openssl-program)
        (with-openssl "" openssl-program)))

;; --- make-test-pki and test-pki-script ------------------------------------

(define pki-ten
  '("ca.pem" "expired.key" "expired.pem" "good.key" "good.pem" "other-ca.pem"
    "untrusted.key" "untrusted.pem" "wrong-host.key" "wrong-host.pem"))

;; The real PKI, made once: the TLS checks below use it.
(define pki-made (guard (e (#t (list 'raised (describe e)))) (list 'made (make-test-pki))))
(define pki (and (eq? (car pki-made) 'made) (cadr pki-made)))
(define (pki-file name) (string-append pki "/" name))

(test-equal "make-test-pki: tests/make-test-pki.sh makes a directory of exactly the ten files"
  (list 'made pki-ten)
  (guard (e (#t (list 'raised (describe e))))
    (list (car pki-made) (list-sort string<? (directory-list pki)))))

;; stand-in-pki : String -> Any
;; make-test-pki's answer, the ten names or what it raised, with
;; test-pki-script naming a script that runs BODY in DIR, and TMPDIR a fresh
;; directory, whose listing after the call comes last: make-test-pki removes
;; the directory it refuses.
(define (stand-in-pki body)
  (call-with-temp-directory
   (lambda (base)
     (let ((script (string-append base "/stand-in-pki.sh"))
           (tmp (string-append base "/tmp")))
       (write-file script (string-append "cd \"$1\" || exit 9\n" body "\n"))
       (capture-command (list "mkdir" tmp))
       (let ((answer (call-with-env "TMPDIR" tmp
                       (lambda ()
                         (parameterize ((test-pki-script script))
                           (guard (e ((and (who-condition? e) (message-condition? e) (irritants-condition? e))
                                      (list (condition-who e) (condition-message e)
                                            (map (lambda (pair)
                                                   (if (and (eq? (car pair) 'script) (equal? (cdr pair) script))
                                                       (cons 'script 'the-stand-in)
                                                       pair))
                                                 (condition-irritants e))))
                                     (#t (list 'other (describe e))))
                             (let ((dir (make-test-pki)))
                               (list 'made (list-sort string<? (directory-list dir))))))))))
         (list answer (map (lambda (name) (if (prefix? "curl-testing." name) 'a-temp-directory name))
                           (directory-list tmp))))))))

(define touch-ten
  "touch ca.pem other-ca.pem good.pem good.key expired.pem expired.key wrong-host.pem wrong-host.key untrusted.pem untrusted.key")
(define touch-nine
  "touch ca.pem other-ca.pem good.pem good.key expired.pem expired.key wrong-host.pem wrong-host.key untrusted.pem")
(define pki-nine (filter (lambda (name) (not (string=? name "untrusted.key"))) pki-ten))

;; refused-pki : String Integer String String (Listof String) -> List
(define (refused-pki wrong status stdout stderr files)
  (list (list 'make-test-pki (string-append "the PKI script did not make the PKI: " wrong)
              (list (cons 'script 'the-stand-in) (cons 'status status) (cons 'stdout stdout)
                    (cons 'stderr stderr) (cons 'files files)))
        '()))

(for-each
 (lambda (row)
   (test-equal (string-append "make-test-pki, with a stand-in script that " (car row))
     (caddr row)
     (stand-in-pki (cadr row))))
 (list (list "makes the ten files and says nothing: their directory, which is not removed"
             touch-ten (list (list 'made pki-ten) '(a-temp-directory)))
       (list "exits 1: a raise, with all it saw, and the directory removed"
             (string-append touch-ten "\nexit 1") (refused-pki "it exited 1" 1 "" "" pki-ten))
       (list "writes to stderr: a raise"
             (string-append touch-ten "\necho 'openssl said something' >&2")
             (refused-pki "it wrote to stderr" 0 "" "openssl said something\n" pki-ten))
       (list "writes to stdout: a raise"
             (string-append touch-ten "\necho hello")
             (refused-pki "it wrote to stdout" 0 "hello\n" "" pki-ten))
       (list "leaves out a file: a raise"
             touch-nine (refused-pki "it did not leave exactly the ten files" 0 "" "" pki-nine))
       (list "leaves an eleventh file: a raise"
             (string-append touch-ten "\ntouch extra")
             (refused-pki "it did not leave exactly the ten files" 0 "" "" (list-sort string<? (cons "extra" pki-ten))))
       (list "does all of those at once: a raise naming each"
             (string-append touch-nine "\necho out\necho err >&2\nexit 3")
             (refused-pki "it exited 3; it wrote to stdout; it wrote to stderr; it did not leave exactly the ten files"
                          3 "out\n" "err\n" pki-nine))))

(test-equal "test-pki-script refuses what is not a path"
  '((assertion-violation test-pki-script ("")) (assertion-violation test-pki-script (5)))
  (list (refusal-of (lambda () (parameterize ((test-pki-script "")) 'set)))
        (refusal-of (lambda () (parameterize ((test-pki-script 5)) 'set)))))

;; --- origin-pki: call-with-origin with the TLS faces ------------------------

(define tls-face-names '(https https-expired https-wrong-host https-untrusted raw-tls h2))

(test-equal "origin-pki: with a PKI, the origin serves every TLS face too, each on loopback"
  (map (lambda (face) "127.0.0.1") (append '(http raw h2c) tls-face-names))
  (guard (e (#t (list 'raised (describe e))))
    (parameterize ((origin-pki pki))
      (call-with-origin
       (lambda (o) (map (lambda (face) (car (origin-face o face))) (append '(http raw h2c) tls-face-names)))))))

;; announced-tls : String -> String
;; A stand-in announcing every face, the TLS ones too, none served, that
;; runs AT-END when its stdin ends.
(define (announced-tls at-end)
  (string-append
   "process.stdout.write(JSON.stringify({ node: process.version, pid: process.pid,"
   " http: '127.0.0.1:1', raw: '127.0.0.1:2', h2c: '127.0.0.1:3', https: '127.0.0.1:4',"
   " 'https-expired': '127.0.0.1:5', 'https-wrong-host': '127.0.0.1:6', 'https-untrusted': '127.0.0.1:7',"
   " 'raw-tls': '127.0.0.1:8', h2: '127.0.0.1:9' }) + '\\n');\n"
   "process.stdin.resume();\n"
   "process.stdin.on('end', () => { " at-end " });\n"))

(test-equal "origin-pki: call-with-origin hands the origin --pki DIR, its only arguments"
  '(call-with-origin "the origin did not end cleanly: it wrote to stderr"
                     ((stdout . "") (stderr . "[\"--pki\",\"/the pki's dir\"]\n") (status . 0)))
  (with-stand-in (announced-tls "process.stderr.write(JSON.stringify(process.argv.slice(2)) + '\\n', () => process.exit(0));")
    (lambda ()
      (parameterize ((origin-pki "/the pki's dir"))
        (refusal-of (lambda () (call-with-origin (lambda (o) 'returned))))))))

(test-equal "origin-pki: with a PKI, an announcement without the TLS faces is malformed"
  (list 'call-with-origin
        "the origin's announcement is malformed: its keys are node, pid, http, raw, h2c, not node, pid, http, raw, h2c, https, https-expired, https-wrong-host, https-untrusted, raw-tls, h2"
        (list (cons 'stdout (string-append "{\"node\":\"v1\",\"pid\":1," good-faces "}\n")) (cons 'stderr "")
              (cons 'status 0)))
  (with-stand-in (announcing (string-append "{\"node\":\"v1\",\"pid\":1," good-faces "}\n"))
    (lambda () (parameterize ((origin-pki "/a/pki")) (no-proc)))))

(test-equal "origin-pki refuses what is neither #f nor a path"
  '((assertion-violation origin-pki ("")) (assertion-violation origin-pki (5)))
  (list (refusal-of (lambda () (parameterize ((origin-pki "")) 'set)))
        (refusal-of (lambda () (parameterize ((origin-pki 5)) 'set)))))

;; --- wire-probe-tls --------------------------------------------------------

(test-equal "wire-probe-tls refuses what is not #f, nor a list of SERVERNAME and then protocols, each a string with no comma, each once"
  '((assertion-violation wire-probe-tls (tls))
    (assertion-violation wire-probe-tls (()))
    (assertion-violation wire-probe-tls ((5)))
    (assertion-violation wire-probe-tls (("" "h2")))
    (assertion-violation wire-probe-tls (("localhost" "")))
    (assertion-violation wire-probe-tls (("localhost" "h2,http/1.1")))
    (assertion-violation wire-probe-tls (("localhost" "h2" "http/1.1" "h2"))))
  (map (lambda (tls) (refusal-of (lambda () (parameterize ((wire-probe-tls tls)) 'set))))
       '(tls () (5) ("" "h2") ("localhost" "") ("localhost" "h2,http/1.1") ("localhost" "h2" "http/1.1" "h2"))))

;; An origin whose raw face is TLS, with the good leaf, and that tells each
;; client the SNI it sent, the protocol ALPN chose, and the protocols it
;; offered, in its order, or none: its ALPNCallback sees the client's list
;; (Node 20.10.0 and 24.18.0, measured), and chooses the first of yy and zz
;; the client offered, or refuses. The probes run one at a time, so one
;; variable carries each list to its connection.
(define (sni-reporter)
  (string-append
   "import tls from 'node:tls';\n"
   "import { readFileSync } from 'node:fs';\n"
   "let offered = 'none';\n"
   "const server = tls.createServer({ key: readFileSync(" (write-text (pki-file "good.key"))
   "), cert: readFileSync(" (write-text (pki-file "good.pem"))
   "), ALPNCallback: ({ protocols }) => { offered = protocols.join(','); return ['yy', 'zz'].find((p) => protocols.includes(p)); } }, (s) => {\n"
   "  s.on('error', () => s.destroy());\n"
   "  s.end(`${s.servername} ${s.alpnProtocol} ${offered}\\n`);\n"
   "  offered = 'none';\n"
   "}).listen(0, '127.0.0.1', () => {\n"
   "  const face = `127.0.0.1:${server.address().port}`;\n"
   "  process.stdout.write(JSON.stringify({ node: process.version, pid: process.pid, http: face, raw: face, h2c: face }) + '\\n');\n"
   "  process.stdin.resume();\n"
   "  process.stdin.on('end', () => process.exit(0));\n"
   "});\n"))

(test-equal "wire-probe-tls: each probe speaks TLS with its SNI, offering its protocols, joined, in order, or none; #f speaks none"
  '(("sni.example zz xx,zz\n" eof) ("sni.example yy yy,xx\n" eof) ("localhost false none\n" eof)
    ("sni.example zz xx,zz\n" eof) ("" timeout))
  (guard (e (#t (list 'raised (describe e))))
    (with-stand-in (sni-reporter)
      (lambda ()
        (call-with-origin
         (lambda (o)
           (let ((seen (lambda (p) (list (utf8->string (probe-bytes p)) (probe-end p)))))
             (list (parameterize ((wire-probe-tls '("sni.example" "xx" "zz")))
                     (seen (wire-probe o 'raw (make-bytevector 0) 2000)))
                   (parameterize ((wire-probe-tls '("sni.example" "yy" "xx")))
                     (seen (wire-probe o 'raw (make-bytevector 0) 2000)))
                   (parameterize ((wire-probe-tls '("localhost")))
                     (seen (wire-probe o 'raw (make-bytevector 0) 2000)))
                   (parameterize ((wire-probe-tls '("sni.example" "xx" "zz")))
                     (seen (wire-probe-half-close o 'raw (make-bytevector 0) 2000)))
                   (seen (wire-probe o 'raw (make-bytevector 0) 200))))))))))

(test-equal "wire-probe-reset refuses to run under wire-probe-tls, before running a probe"
  '(assertion-violation wire-probe-reset (("localhost" "h2")))
  (parameterize ((wire-probe-tls '("localhost" "h2")))
    (refusal-of (lambda () (wire-probe-reset 'no-origin 'raw (make-bytevector 0))))))

;; --- parse-s-client: synthetic outputs in both implementations' formats ----

;; base64 : Bytevector -> String
(define (base64 bytes)
  (let ((alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
        (n (bytevector-length bytes)))
    (call-with-string-output-port
     (lambda (p)
       (let loop ((i 0))
         (when (< i n)
           (let* ((b1 (if (< (+ i 1) n) (bytevector-u8-ref bytes (+ i 1)) 0))
                  (b2 (if (< (+ i 2) n) (bytevector-u8-ref bytes (+ i 2)) 0))
                  (w (+ (* (bytevector-u8-ref bytes i) 65536) (* b1 256) b2)))
             (put-char p (string-ref alphabet (div w 262144)))
             (put-char p (string-ref alphabet (mod (div w 4096) 64)))
             (put-char p (if (< (+ i 1) n) (string-ref alphabet (mod (div w 64) 64)) #\=))
             (put-char p (if (< (+ i 2) n) (string-ref alphabet (mod w 64)) #\=))
             (loop (+ i 3)))))))))

;; Two certificates' base64 text, made here, for no real certificate is
;; checked in (ADR-0005).
(define cert-a (base64 (seeded-bytes 300 11)))
(define cert-b (base64 (seeded-bytes 200 12)))

;; pem-block : String String -> String
;; TEXT as a PEM block of LABEL, its base64 in lines of 64.
(define (pem-block label text)
  (string-append "-----BEGIN " label "-----\n"
                 (let loop ((i 0) (acc ""))
                   (if (>= i (string-length text))
                       acc
                       (loop (+ i 64)
                             (string-append acc (substring text i (min (string-length text) (+ i 64))) "\n"))))
                 "-----END " label "-----\n"))

;; The chain s_client -showcerts prints, its leaf cert-a, then cert-b.
(define openssl-chain
  (string-append " 0 s:CN=good\n   i:CN=chez-curl test CA\n"
                 "   a:PKEY: EC, (prime256v1); sigalg: ecdsa-with-SHA256\n"
                 "   v:NotBefore: Oct 18 16:47:30 2026 GMT; NotAfter: Oct 20 16:47:30 2026 GMT\n"
                 (pem-block "CERTIFICATE" cert-a)
                 " 1 s:CN=chez-curl test CA\n   i:CN=chez-curl test CA\n"
                 (pem-block "CERTIFICATE" cert-b)))
(define libressl-chain
  (string-append " 0 s:/CN=good\n   i:/CN=chez-curl test CA\n" (pem-block "CERTIFICATE" cert-a)
                 " 1 s:/CN=chez-curl test CA\n   i:/CN=chez-curl test CA\n" (pem-block "CERTIFICATE" cert-b)))

;; openssl-stdout, libressl-stdout : String String String -> String
;; s_client's stdout as OpenSSL 3.5.7 and LibreSSL 3.3.6 write it (measured),
;; with CHAIN, an ALPN line and a verify code line.
(define (openssl-stdout chain alpn code)
  (string-append "CONNECTED(00000004)\n---\nCertificate chain\n" chain
                 "---\nServer certificate\nsubject=CN=good\nissuer=CN=chez-curl test CA\n---\n"
                 "No client certificate CA names sent\nPeer signing digest: SHA256\n"
                 "Peer signature type: ecdsa_secp256r1_sha256\nNegotiated TLS1.3 group: X25519MLKEM768\n---\n"
                 "SSL handshake has read 1919 bytes and written 1640 bytes\nVerification: OK\n---\n"
                 "New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384\nProtocol: TLSv1.3\nServer public key is 256 bit\n"
                 "This TLS version forbids renegotiation.\nCompression: NONE\nExpansion: NONE\n"
                 alpn "Early data was not sent\n" code "---\n"))
(define (libressl-stdout chain alpn code)
  (string-append "CONNECTED(00000004)\nwrite W BLOCK\n---\nCertificate chain\n" chain
                 "---\nServer certificate\nsubject=/CN=good\nissuer=/CN=chez-curl test CA\n---\n"
                 "No client certificate CA names sent\nServer Temp Key: ECDH, X25519, 253 bits\n---\n"
                 "SSL handshake has read 801 bytes and written 403 bytes\n---\n"
                 "New, TLSv1/SSLv3, Cipher is AEAD-AES256-GCM-SHA384\nServer public key is 256 bit\n"
                 "Secure Renegotiation IS NOT supported\nCompression: NONE\nExpansion: NONE\n"
                 alpn "SSL-Session:\n    Protocol  : TLSv1.3\n    Cipher    : AEAD-AES256-GCM-SHA384\n"
                 "    Session-ID: \n    Session-ID-ctx: \n    Master-Key: \n    Start Time: 1792342050\n"
                 "    Timeout   : 7200 (sec)\n" code "---\n"))

(define openssl-untrusted-stderr
  (string-append "Connecting to 127.0.0.1\ndepth=0 CN=untrusted\n"
                 "verify error:num=20:unable to get local issuer certificate\nverify return:1\n"
                 "depth=0 CN=untrusted\nverify error:num=21:unable to verify the first certificate\n"
                 "verify return:1\ndepth=0 CN=untrusted\nverify return:1\nDONE\n"))
(define libressl-untrusted-stderr
  (string-append "depth=0 CN = untrusted\nverify error:num=20:unable to get local issuer certificate\n"
                 "verify return:1\ndepth=0 CN = untrusted\nverify error:num=21:unable to verify the first certificate\n"
                 "verify return:1\nDONE\n"))
(define openssl-good-stderr
  "Connecting to 127.0.0.1\ndepth=1 CN=chez-curl test CA\nverify return:1\ndepth=0 CN=good\nverify return:1\nDONE\n")
(define libressl-good-stderr
  "depth=1 CN = chez-curl test CA\nverify return:1\ndepth=0 CN = good\nverify return:1\nDONE\n")
(define openssl-expired-stderr
  "Connecting to 127.0.0.1\ndepth=0 CN=expired\nverify error:num=10:certificate has expired\nverify return:1\nDONE\n")

(define code-21 "Verify return code: 21 (unable to verify the first certificate)\n")
(define code-0 "Verify return code: 0 (ok)\n")

;; peer : Peer -> List
;; Each field, #f written as no-alpn: SRFI-64 makes a raise #f.
(define (peer-fields p)
  (list (peer-verify-errors p) (peer-verify-code p) (or (peer-alpn p) 'no-alpn) (peer-leaf p)))

(for-each
 (lambda (row)
   (test-equal (string-append "parse-s-client: " (car row))
     (cadr row)
     (guard (e (#t (list 'raised (describe e))))
       (peer-fields (parse-s-client (caddr row) (cadddr row))))))
 (list (list "OpenSSL 3.5.7, an untrusted leaf, ALPN h2, two certificates: the errors from stderr in order, the code, the protocol and the first certificate"
             (list '(20 21) 21 "h2" cert-a)
             (openssl-stdout openssl-chain "ALPN protocol: h2\n" code-21) openssl-untrusted-stderr)
       (list "LibreSSL 3.3.6, the same, its code line indented"
             (list '(20 21) 21 "h2" cert-a)
             (libressl-stdout libressl-chain "ALPN protocol: h2\n" (string-append "    " code-21))
             libressl-untrusted-stderr)
       (list "OpenSSL 3.5.7, a good leaf, no ALPN: no errors, code 0, no protocol"
             (list '() 0 'no-alpn cert-a)
             (openssl-stdout openssl-chain "No ALPN negotiated\n" code-0) openssl-good-stderr)
       (list "LibreSSL 3.3.6, the same"
             (list '() 0 'no-alpn cert-a)
             (libressl-stdout libressl-chain "No ALPN negotiated\n" (string-append "    " code-0))
             libressl-good-stderr)
       (list "an expired leaf, ALPN http/1.1, one certificate"
             (list '(10) 10 "http/1.1" cert-b)
             (openssl-stdout (pem-block "CERTIFICATE" cert-b) "ALPN protocol: http/1.1\n"
                             "Verify return code: 10 (certificate has expired)\n")
             openssl-expired-stderr)
       (list "a verify error line on stdout is not one of stderr's, nor an indented one on stderr"
             (list '(21) 21 "h2" cert-a)
             (openssl-stdout (string-append "verify error:num=20:on stdout\n" openssl-chain) "ALPN protocol: h2\n" code-21)
             (string-append " verify error:num=20:indented\nverify error:num=21:unable to verify the first certificate\n"))
       (list "a key block before the first certificate is not it"
             (list '() 0 "h2" cert-b)
             (openssl-stdout (string-append (pem-block "EC PRIVATE KEY" cert-a) (pem-block "CERTIFICATE" cert-b))
                             "ALPN protocol: h2\n" code-0)
             "")))

;; s-client-refusal : String String -> Any
(define (s-client-refusal stdout stderr) (refusal-of (lambda () (parse-s-client stdout stderr))))

(let* ((good (lambda (alpn code) (openssl-stdout openssl-chain alpn code)))
       (no-code (good "ALPN protocol: h2\n" ""))
       (two-codes (good "ALPN protocol: h2\n" (string-append code-0 "    " code-0)))
       (no-alpn-line (good "" code-0))
       (two-alpn (good "ALPN protocol: h2\nNo ALPN negotiated\n" code-0))
       (no-cert (openssl-stdout "" "ALPN protocol: h2\n" code-0))
       (empty-cert (openssl-stdout "-----BEGIN CERTIFICATE-----\n-----END CERTIFICATE-----\n" "ALPN protocol: h2\n" code-0))
       (open-cert (string-append (good "ALPN protocol: h2\n" code-0) "-----BEGIN CERTIFICATE-----\nAAAA\n"))
       (open-cert-stdout (openssl-stdout (string-append "-----BEGIN CERTIFICATE-----\n" cert-a "\n")
                                         "ALPN protocol: h2\n" code-0)))
  (for-each
   (lambda (row)
     (test-equal (string-append "parse-s-client refuses " (car row))
       (cadr row)
       (s-client-refusal (caddr row) (cadddr row))))
   (list (list "a verify error line with no number"
               '(parse-s-client "a verify error line is verify error:num=N:TEXT" ("verify error:num=x:bad"))
               (good "ALPN protocol: h2\n" code-0) "verify error:num=x:bad\n")
         (list "a verify error line with no colon after its number"
               '(parse-s-client "a verify error line is verify error:num=N:TEXT" ("verify error:num=20"))
               (good "ALPN protocol: h2\n" code-0) "verify error:num=20\n")
         (list "no Verify return code line"
               (list 'parse-s-client "stdout has no Verify return code line" (list no-code))
               no-code "")
         (list "a second Verify return code line with no ticket line before it"
               '(parse-s-client "a Verify return code line after the handshake's has no Post-Handshake New Session Ticket arrived: line of its own before it"
                                ("    Verify return code: 0 (ok)"))
               two-codes "")
         (list "a Verify return code line with no number"
               '(parse-s-client "a Verify return code line is Verify return code: N (TEXT)" ("Verify return code: ok"))
               (good "ALPN protocol: h2\n" "Verify return code: ok\n") "")
         (list "a Verify return code line with no text after its number"
               '(parse-s-client "a Verify return code line is Verify return code: N (TEXT)" ("Verify return code: 0"))
               (good "ALPN protocol: h2\n" "Verify return code: 0\n") "")
         (list "a Verify return code line whose text is not in brackets"
               '(parse-s-client "a Verify return code line is Verify return code: N (TEXT)" ("Verify return code: 0 ok"))
               (good "ALPN protocol: h2\n" "Verify return code: 0 ok\n") "")
         (list "no ALPN line"
               (list 'parse-s-client "stdout has no ALPN protocol or No ALPN negotiated line" (list no-alpn-line))
               no-alpn-line "")
         (list "an ALPN protocol line and a No ALPN negotiated line"
               (list 'parse-s-client "stdout has more than one ALPN protocol or No ALPN negotiated line"
                     (list (list "ALPN protocol: h2" "No ALPN negotiated")))
               two-alpn "")
         (list "two ALPN protocol lines"
               (list 'parse-s-client "stdout has more than one ALPN protocol or No ALPN negotiated line"
                     (list (list "ALPN protocol: h2" "ALPN protocol: h2")))
               (good "ALPN protocol: h2\nALPN protocol: h2\n" code-0) "")
         (list "an ALPN protocol line with no protocol"
               '(parse-s-client "an ALPN line is ALPN protocol: X, or No ALPN negotiated" ("ALPN protocol:"))
               (good "ALPN protocol:\n" code-0) "")
         (list "no certificate"
               (list 'parse-s-client "no -----BEGIN CERTIFICATE----- line" (list no-cert))
               no-cert "")
         (list "an empty certificate"
               (list 'parse-s-client "a certificate is empty" (list empty-cert))
               empty-cert "")
         (list "a first certificate that is not closed"
               (list 'parse-s-client "a certificate has no -----END CERTIFICATE----- line" (list open-cert-stdout))
               open-cert-stdout "")
         (list "stdout that is not a string"
               '(assertion-violation parse-s-client (5)) 5 "")
         (list "stderr that is not a string"
               '(assertion-violation parse-s-client (5)) "" 5))))

;; --- parse-s-client: TLS 1.3 session tickets ------------------------------
;; OpenSSL 3 prints a block for each session ticket it reads before stdin's
;; end, by timing, with a Verify return code of its own: the handshake's.

(define ticket-line "Post-Handshake New Session Ticket arrived:")

;; ticket-block : String -> String
;; A ticket's block as OpenSSL 3.5.7 prints it after the handshake's lines
;; (measured), its session's Verify return code line CODE indented, its
;; session's bytes made up here.
(define (ticket-block code)
  (string-append "---\n" ticket-line "\nSSL-Session:\n    Protocol  : TLSv1.3\n"
                 "    Cipher    : TLS_AES_256_GCM_SHA384\n    Session-ID: 0F1E2D3C4B5A6978\n    Session-ID-ctx: \n"
                 "    Resumption PSK: 8796A5B4C3D2E1F0\n    PSK identity: None\n    PSK identity hint: None\n"
                 "    SRP username: None\n    TLS session ticket lifetime hint: 7200 (seconds)\n    TLS session ticket:\n"
                 "    0000 - 01 02 03 04 05 06 07 08-09 0a 0b 0c 0d 0e 0f 10   ................\n\n"
                 "    Start Time: 1792346241\n    Timeout   : 7200 (sec)\n    " code
                 "    Extended master secret: no\n    Max Early Data: 0\n---\nread R BLOCK\n"))

;; with-tickets : String (Listof String) -> String
;; OpenSSL 3.5.7's stdout, ALPN h2, the handshake's code line CODE, then a
;; ticket block for each of TICKETS, its code line.
(define (with-tickets code tickets)
  (apply string-append (openssl-stdout openssl-chain "ALPN protocol: h2\n" code) (map ticket-block tickets)))

(for-each
 (lambda (row)
   (test-equal (string-append "parse-s-client, with ticket blocks: " (car row))
     (cadr row)
     (guard (e (#t (list 'raised (describe e))))
       (peer-fields (parse-s-client (caddr row) (cadddr row))))))
 (list (list "none: the handshake's code"
             (list '() 0 "h2" cert-a) (with-tickets code-0 '()) openssl-good-stderr)
       (list "one, its code the handshake's: the handshake's code"
             (list '() 0 "h2" cert-a) (with-tickets code-0 (list code-0)) openssl-good-stderr)
       (list "two, as Node sends, each code the handshake's: the handshake's code"
             (list '() 0 "h2" cert-a) (with-tickets code-0 (list code-0 code-0)) openssl-good-stderr)
       (list "two, the handshake's code 21 and each ticket's 21: 21, and the errors from stderr"
             (list '(20 21) 21 "h2" cert-a) (with-tickets code-21 (list code-21 code-21)) openssl-untrusted-stderr)
       (list "two, the first after the server's bytes, binary ones as on h2, at the start of its --- line"
             (list '() 0 "h2" cert-a)
             (string-append (openssl-stdout openssl-chain "ALPN protocol: h2\n" code-0)
                            (string #\nul #\nul #\nul #\x4 #\nul #\nul #\nul #\nul #\nul)
                            (ticket-block code-0) (ticket-block code-0))
             openssl-good-stderr)))

(let* ((stray-code (string-append (with-tickets code-0 (list code-0)) "    " code-0))
       (no-code-after (string-append (with-tickets code-0 '()) "---\n" ticket-line "\nSSL-Session:\n---\n"))
       (two-lines (string-append (with-tickets code-0 '()) "---\n" ticket-line "\n" (ticket-block code-0)))
       (before (string-append (ticket-block code-0) (openssl-stdout openssl-chain "ALPN protocol: h2\n" code-0)))
       (malformed (with-tickets code-0 (list "Verify return code: x (ok)\n"))))
  (for-each
   (lambda (row)
     (test-equal (string-append "parse-s-client refuses " (car row))
       (cadr row)
       (s-client-refusal (caddr row) openssl-good-stderr)))
   (list (list "a ticket block followed by a second code line with no ticket line of its own"
               '(parse-s-client "a Verify return code line after the handshake's has no Post-Handshake New Session Ticket arrived: line of its own before it"
                                ("    Verify return code: 0 (ok)"))
               stray-code)
         (list "a ticket line with no Verify return code line after it"
               (list 'parse-s-client "a Post-Handshake New Session Ticket arrived: line has no Verify return code line after it"
                     (list ticket-line))
               no-code-after)
         (list "two ticket lines before one Verify return code line"
               (list 'parse-s-client "two Post-Handshake New Session Ticket arrived: lines come before one Verify return code line"
                     (list ticket-line))
               two-lines)
         (list "a ticket's code that is not the handshake's: 21, then 0"
               '(parse-s-client "a ticket's Verify return code is not the handshake's" (21 "    Verify return code: 0 (ok)"))
               (with-tickets code-21 (list code-0)))
         (list "a ticket's code that is not the handshake's, in the second ticket: 0, 0, then 21"
               '(parse-s-client "a ticket's Verify return code is not the handshake's"
                                (0 "    Verify return code: 21 (unable to verify the first certificate)"))
               (with-tickets code-0 (list code-0 code-21)))
         (list "a ticket line before the handshake's Verify return code line"
               (list 'parse-s-client "a Post-Handshake New Session Ticket arrived: line comes before the handshake's Verify return code line"
                     (list ticket-line))
               before)
         (list "a ticket's malformed Verify return code line"
               '(parse-s-client "a Verify return code line is Verify return code: N (TEXT)" ("    Verify return code: x (ok)"))
               malformed))))

;; --- parse-s-client: the chain ---------------------------------------------

(for-each
 (lambda (row)
   (test-equal (string-append "parse-s-client: peer-chain is every certificate block, in order, and peer-leaf the first: " (car row))
     (cadr row)
     (guard (e (#t (list 'raised (describe e))))
       (let ((p (parse-s-client (caddr row) "")))
         (list (map (lambda (c) (cond ((string=? c cert-a) 'cert-a) ((string=? c cert-b) 'cert-b) (else c)))
                    (peer-chain p))
               (cond ((string=? (peer-leaf p) cert-a) 'cert-a) ((string=? (peer-leaf p) cert-b) 'cert-b)
                     (else (peer-leaf p))))))))
 (list (list "OpenSSL 3.5.7, two" '((cert-a cert-b) cert-a)
             (openssl-stdout openssl-chain "ALPN protocol: h2\n" code-0))
       (list "LibreSSL 3.3.6, two" '((cert-a cert-b) cert-a)
             (libressl-stdout libressl-chain "ALPN protocol: h2\n" (string-append "    " code-0)))
       (list "OpenSSL 3.5.7, one" '((cert-b) cert-b)
             (openssl-stdout (string-append " 0 s:CN=chez-curl test leaf\n   i:CN=chez-curl test CA\n"
                                            (pem-block "CERTIFICATE" cert-b))
                             "ALPN protocol: h2\n" code-0))
       (list "LibreSSL 3.3.6, one" '((cert-a) cert-a)
             (libressl-stdout (string-append " 0 s:/CN=chez-curl test leaf\n   i:/CN=chez-curl test CA\n"
                                             (pem-block "CERTIFICATE" cert-a))
                              "ALPN protocol: h2\n" (string-append "    " code-0)))
       (list "a key block among them is none of them" '((cert-a cert-b) cert-a)
             (openssl-stdout (string-append (pem-block "CERTIFICATE" cert-a) (pem-block "EC PRIVATE KEY" cert-b)
                                            (pem-block "CERTIFICATE" cert-b))
                             "ALPN protocol: h2\n" code-0))))

(let ((second-open (openssl-stdout (string-append (pem-block "CERTIFICATE" cert-a) "-----BEGIN CERTIFICATE-----\n" cert-b "\n")
                                   "ALPN protocol: h2\n" code-0))
      (second-empty (openssl-stdout (string-append (pem-block "CERTIFICATE" cert-a)
                                                   "-----BEGIN CERTIFICATE-----\n-----END CERTIFICATE-----\n")
                                    "ALPN protocol: h2\n" code-0)))
  (test-equal "parse-s-client refuses a chain whose second certificate is not closed, or empty"
    (list (list 'parse-s-client "a certificate has no -----END CERTIFICATE----- line" (list second-open))
          (list 'parse-s-client "a certificate is empty" (list second-empty)))
    (list (s-client-refusal second-open "") (s-client-refusal second-empty ""))))

(test-equal "peer-leaf refuses what is not a Peer"
  '(assertion-violation peer-leaf (5))
  (refusal-of (lambda () (peer-leaf 5))))

;; --- s-client ---------------------------------------------------------------

(test-equal "s-client against the origin's https and h2 faces: the good leaf, as good.pem holds it, by ALPN http/1.1 and h2, and none offered"
  '((() 0 "http/1.1" same) (() 0 "h2" same) (() 0 no-alpn same) ((10) 10 "http/1.1" expired-same))
  (guard (e (#t (list 'raised (describe e))))
    (parameterize ((origin-pki pki))
      (call-with-origin
       (lambda (o)
         (let ((row (lambda (face alpn leaf)
                      (let ((p (s-client o face "localhost" (pki-file "ca.pem") alpn)))
                        (list (peer-verify-errors p) (peer-verify-code p) (or (peer-alpn p) 'no-alpn)
                              (if (string=? (peer-leaf p) (pem-certificate (pki-file leaf)))
                                  (if (string=? leaf "good.pem") 'same 'expired-same)
                                  'differs))))))
           (list (row 'https "h2,http/1.1" "good.pem")
                 (row 'h2 "h2,http/1.1" "good.pem")
                 (row 'https #f "good.pem")
                 (row 'https-expired "http/1.1" "expired.pem"))))))))

;; with-openssl-stand-in : String String Integer (String -> Any) -> Any
;; (PROC DIR) with OPENSSL naming a stand-in in DIR that records each of its
;; arguments as a line of DIR/argv, and in DIR/stdin whether its stdin is a
;; pipe and how many bytes it held, writes STDOUT and STDERR, and exits
;; STATUS.
(define (with-openssl-stand-in stdout stderr status proc)
  (call-with-temp-directory
   (lambda (dir)
     (write-file (string-append dir "/stdout") stdout)
     (write-file (string-append dir "/stderr") stderr)
     (write-file (string-append dir "/openssl")
                 (string-append "#!/bin/sh\nfor a in \"$@\"; do printf '%s\\n' \"$a\"; done > \"$(dirname \"$0\")/argv\"\n"
                                "if [ -p /dev/stdin ]; then kind=pipe; else kind=other; fi\n"
                                "printf '%s %s\\n' \"$kind\" \"$(wc -c | tr -d ' ')\" > \"$(dirname \"$0\")/stdin\"\n"
                                "cat \"$(dirname \"$0\")/stdout\"\ncat \"$(dirname \"$0\")/stderr\" >&2\nexit "
                                (number->string status) "\n"))
     (capture-command (list "chmod" "+x" (string-append dir "/openssl")))
     (with-openssl (string-append dir "/openssl") (lambda () (proc dir))))))

;; argv-of : String -> (Listof String)
(define (argv-of dir)
  (let ((text (cadr (capture-command (list "cat" (string-append dir "/argv"))))))
    (let loop ((chars (string->list text)) (line '()) (lines '()))
      (cond ((null? chars) (reverse lines))
            ((char=? (car chars) #\newline) (loop (cdr chars) '() (cons (list->string (reverse line)) lines)))
            (else (loop (cdr chars) (cons (car chars) line) lines))))))

(test-equal "s-client runs $OPENSSL s_client -connect ADDRESS:PORT, -servername SERVERNAME when given, -CAfile CA -showcerts, then -alpn LIST when given"
  '((("s_client" "-connect" "ADDRESS:PORT" "-servername" "localhost" "-CAfile" "the/ca.pem" "-showcerts"
      "-alpn" "h2,http/1.1")
     ((20 21) 21 "h2" "cert-a"))
    (("s_client" "-connect" "ADDRESS:PORT" "-servername" "sni.example" "-CAfile" "the/ca.pem" "-showcerts")
     ((20 21) 21 "h2" "cert-a"))
    (("s_client" "-connect" "ADDRESS:PORT" "-CAfile" "the/ca.pem" "-showcerts" "-alpn" "h2")
     ((20 21) 21 "h2" "cert-a"))
    (("s_client" "-connect" "ADDRESS:PORT" "-CAfile" "the/ca.pem" "-showcerts")
     ((20 21) 21 "h2" "cert-a")))
  (guard (e (#t (list 'raised (describe e))))
    (call-with-origin
     (lambda (o)
       (let ((address (string-append "127.0.0.1:" (number->string (cdr (origin-face o 'raw))))))
         (map (lambda (servername alpn)
                (with-openssl-stand-in (openssl-stdout openssl-chain "ALPN protocol: h2\n" code-21)
                                       openssl-untrusted-stderr 0
                  (lambda (dir)
                    (let ((p (s-client o 'raw servername "the/ca.pem" alpn)))
                      (list (map (lambda (a) (if (string=? a address) "ADDRESS:PORT" a)) (argv-of dir))
                            (list (peer-verify-errors p) (peer-verify-code p) (peer-alpn p)
                                  (if (string=? (peer-leaf p) cert-a) "cert-a" (peer-leaf p))))))))
              '("localhost" "sni.example" #f #f) '("h2,http/1.1" #f "h2" #f)))))))

;; LibreSSL 3.3.6's s_client polls its stdin with poll(2), and macOS's poll
;; does not support devices. On the maintainer's Mac, with stdin at /dev/null
;; it printed "poll error" and exited 1 once connected; with an empty pipe it
;; printed DONE and exited 0 (measured 2026-10-23).
(test-equal "s-client gives openssl an empty pipe as its stdin, never a device such as /dev/null"
  '("pipe 0\n" "pipe 0\n")
  (guard (e (#t (list 'raised (describe e))))
    (call-with-origin
     (lambda (o)
       (map (lambda (alpn)
              (with-openssl-stand-in (openssl-stdout openssl-chain "ALPN protocol: h2\n" code-21)
                                     openssl-untrusted-stderr 0
                (lambda (dir)
                  (s-client o 'raw "localhost" "the/ca.pem" alpn)
                  (cadr (capture-command (list "cat" (string-append dir "/stdin")))))))
            '("h2" #f))))))

(test-equal "s-client raises, with its status, stdout and stderr, when openssl does not exit 0"
  '(s-client "openssl s_client did not exit 0" ((status . 1) (stdout . "partial\n") (stderr . "connect: refused\n")))
  (guard (e (#t (list 'raised (describe e))))
    (call-with-origin
     (lambda (o)
       (with-openssl-stand-in "partial\n" "connect: refused\n" 1
         (lambda (dir) (refusal-of (lambda () (s-client o 'raw "localhost" "the/ca.pem" "h2")))))))))

(test-equal "s-client refuses an unknown face, a server name that is neither #f nor a string, a CA that is no path and an ALPN list that is neither #f nor a string"
  '((assertion-violation origin-face (https))
    (assertion-violation s-client (5))
    (assertion-violation s-client (""))
    (assertion-violation s-client (""))
    (assertion-violation s-client (h2)))
  (guard (e (#t (list 'raised (describe e))))
    (call-with-origin
     (lambda (o)
       (list (refusal-of (lambda () (s-client o 'https "localhost" "ca.pem" #f)))
             (refusal-of (lambda () (s-client o 'raw 5 "ca.pem" #f)))
             (refusal-of (lambda () (s-client o 'raw "" "ca.pem" #f)))
             (refusal-of (lambda () (s-client o 'raw "localhost" "" #f)))
             (refusal-of (lambda () (s-client o 'raw "localhost" "ca.pem" 'h2))))))))

;; --- certificate-san ------------------------------------------------------

(test-equal "certificate-san: the good leaf names localhost, 127.0.0.1 and ::1, and the wrong-host leaf wrong-host.invalid alone"
  '("DNS:localhost, IP Address:127.0.0.1, IP Address:0:0:0:0:0:0:0:1" "DNS:wrong-host.invalid")
  (guard (e (#t (list 'raised (describe e))))
    (list (certificate-san (pki-file "good.pem")) (certificate-san (pki-file "wrong-host.pem")))))

;; x509-text : Boolean String -> String
;; x509 -noout -text's output around the extensions, as OpenSSL 3.5.7, or
;; with LIBRESSL? LibreSSL 3.3.6, writes it (measured), with SAN-LINES after
;; the extensions' first one.
(define (x509-text libressl? san-lines)
  (string-append "Certificate:\n    Data:\n        Version: 3 (0x2)\n        Serial Number: 1 (0x1)\n"
                 (if libressl? "    Signature Algorithm: ecdsa-with-SHA256\n" "        Signature Algorithm: ecdsa-with-SHA256\n")
                 "        Issuer: CN=chez-curl test CA\n        Validity\n"
                 "            Not Before: Oct 18 16:47:30 2026 GMT\n            Not After : Oct 20 16:47:30 2026 GMT\n"
                 "        Subject: CN=good\n        X509v3 extensions:\n"
                 "            X509v3 Basic Constraints: critical\n                CA:FALSE\n"
                 san-lines
                 "            X509v3 Authority Key Identifier: \n"
                 (if libressl?
                     "                keyid:0F:39:3C:6A:C7:13:D1:65:C7:88:07:34:B1:00:E8:EA:75:57:AA:62\n\n"
                     "                4D:64:58:03:D3:63:B8:D9:4F:DF:EF:84:E7:2A:75:D3:7A:4F:48:F3\n")
                 "    Signature Algorithm: ecdsa-with-SHA256\n"))

(define san-heading "            X509v3 Subject Alternative Name: \n")
(define san-value "                DNS:localhost, IP Address:127.0.0.1, IP Address:0:0:0:0:0:0:0:1  \n")

(for-each
 (lambda (row)
   (test-equal (string-append "certificate-san, on " (car row))
     (cadr row)
     (with-openssl-stand-in (caddr row) "" 0
       (lambda (dir)
         (guard (e (#t (list 'raised (describe e))))
           (list (certificate-san "the/cert.pem") (argv-of dir)))))))
 (list (list "OpenSSL 3.5.7's text: the line after the heading, trimmed, from x509 -in FILE -noout -text"
             '("DNS:localhost, IP Address:127.0.0.1, IP Address:0:0:0:0:0:0:0:1"
               ("x509" "-in" "the/cert.pem" "-noout" "-text"))
             (x509-text #f (string-append san-heading san-value)))
       (list "LibreSSL 3.3.6's text"
             '("DNS:localhost, IP Address:127.0.0.1, IP Address:0:0:0:0:0:0:0:1"
               ("x509" "-in" "the/cert.pem" "-noout" "-text"))
             (x509-text #t (string-append san-heading san-value)))
       (list "a critical SAN"
             '("DNS:a.invalid" ("x509" "-in" "the/cert.pem" "-noout" "-text"))
             (x509-text #f "            X509v3 Subject Alternative Name: critical\n                DNS:a.invalid\n"))))

(let ((no-heading (x509-text #f ""))
      (twice (x509-text #f (string-append san-heading san-value san-heading san-value)))
      (last (string-append (x509-text #f "") san-heading)))
  (for-each
   (lambda (row)
     (test-equal (string-append "certificate-san refuses " (car row))
       (cadr row)
       (with-openssl-stand-in (caddr row) (cadddr row) (list-ref row 4)
         (lambda (dir) (refusal-of (lambda () (certificate-san "the/cert.pem")))))))
   (list (list "a status other than 0"
               (list 'certificate-san "openssl x509 did not exit 0"
                     (list (cons 'status 1) (cons 'stdout "") (cons 'stderr "unable to load certificate\n")))
               "" "unable to load certificate\n" 1)
         (list "text with no SAN heading"
               (list 'certificate-san "openssl x509 wrote no X509v3 Subject Alternative Name: heading"
                     (list (cons 'status 0) (cons 'stdout no-heading) (cons 'stderr "")))
               no-heading "" 0)
         (list "text with the SAN heading twice"
               (list 'certificate-san "openssl x509 wrote the X509v3 Subject Alternative Name: heading more than once"
                     (list (cons 'status 0) (cons 'stdout twice) (cons 'stderr "")))
               twice "" 0)
         (list "text whose last line is the SAN heading"
               (list 'certificate-san "openssl x509 wrote no line after the X509v3 Subject Alternative Name: heading"
                     (list (cons 'status 0) (cons 'stdout last) (cons 'stderr "")))
               last "" 0))))

(test-equal "certificate-san refuses what is not a path"
  '(assertion-violation certificate-san (5))
  (refusal-of (lambda () (certificate-san 5))))

;; --- certificate-text, certificate-values, certificate-time -----------------

(for-each
 (lambda (row)
   (test-equal (string-append "certificate-text: x509 -in FILE -noout -text's lines, trimmed at both ends, from " (car row))
     (cadr row)
     (with-openssl-stand-in (caddr row) "" 0
       (lambda (dir)
         (guard (e (#t (list 'raised (describe e))))
           (list (certificate-text "the/cert.pem") (argv-of dir)))))))
 (list (list "OpenSSL 3.5.7's indentation"
             '(("Certificate:" "Data:" "Signature Algorithm: ecdsa-with-SHA256" "Public-Key: (256 bit)" ""
                "ASN1 OID: prime256v1" "Not After : Oct 20 16:47:30 2026 GMT")
               ("x509" "-in" "the/cert.pem" "-noout" "-text"))
             "Certificate:\n    Data:\n        Signature Algorithm: ecdsa-with-SHA256\n            Public-Key: (256 bit)  \n\n\t\tASN1 OID: prime256v1\n            Not After : Oct 20 16:47:30 2026 GMT\n")
       (list "LibreSSL 3.3.6's"
             '(("Certificate:" "Data:" "Signature Algorithm: ecdsa-with-SHA256" "Public-Key: (256 bit)" "")
               ("x509" "-in" "the/cert.pem" "-noout" "-text"))
             "Certificate:\n    Data:\n    Signature Algorithm: ecdsa-with-SHA256\n                Public-Key: (256 bit)\n\n")))

(test-equal "certificate-text raises, with its status, stdout and stderr, when openssl does not exit 0, and refuses what is not a path"
  '((certificate-text "openssl x509 did not exit 0" ((status . 1) (stdout . "") (stderr . "unable to load certificate\n")))
    (assertion-violation certificate-text (5)))
  (list (with-openssl-stand-in "" "unable to load certificate\n" 1
          (lambda (dir) (refusal-of (lambda () (certificate-text "the/cert.pem")))))
        (refusal-of (lambda () (certificate-text 5)))))

(test-equal "certificate-text: the good leaf's file, read by $OPENSSL, names P-256 and ECDSA with SHA-256"
  '(("prime256v1") ("(256 bit)") ("ecdsa-with-SHA256" "ecdsa-with-SHA256"))
  (guard (e (#t (list 'raised (describe e))))
    (let ((lines (certificate-text (pki-file "good.pem"))))
      (list (certificate-values lines "ASN1 OID:") (certificate-values lines "Public-Key:")
            (certificate-values lines "Signature Algorithm:")))))

(test-equal "certificate-values: what follows the label, trimmed, on every line that starts with it, in order, its spacing matched whole"
  '(("ecdsa-with-SHA256" "sha256WithRSAEncryption") ("Oct 20 16:47:30 2026 GMT") () () ())
  (let ((lines '("Signature Algorithm: ecdsa-with-SHA256" "Not After : Oct 20 16:47:30 2026 GMT"
                 "Signature Algorithm:   sha256WithRSAEncryption  " "X Signature Algorithm: other")))
    (list (certificate-values lines "Signature Algorithm:")
          (certificate-values lines "Not After :")
          (certificate-values lines "Not After:")
          (certificate-values lines "Public-Key:")
          (certificate-values '() "Signature Algorithm:"))))

(test-equal "certificate-values refuses what is not a list of lines, or not a label"
  '((assertion-violation certificate-values (lines))
    (assertion-violation certificate-values (("a" 5)))
    (assertion-violation certificate-values (""))
    (assertion-violation certificate-values (5)))
  (list (refusal-of (lambda () (certificate-values 'lines "A:")))
        (refusal-of (lambda () (certificate-values '("a" 5) "A:")))
        (refusal-of (lambda () (certificate-values '("a") "")))
        (refusal-of (lambda () (certificate-values '("a") 5)))))

(test-equal "certificate-names: a Subject or Issuer line's names, each \" = \" written \"=\": OpenSSL 3.0's CN = x as 3.5's and LibreSSL's CN=x, and nothing else folded"
  '(("CN=chez-curl test leaf") ("CN=chez-curl test leaf") ("C=XX, O=a = b, CN=c=d") ("CN=chez-curl test CA") ())
  (let ((lines '("Subject: CN = chez-curl test leaf" "Subject: CN=chez-curl test leaf"
                 "Subject: C = XX, O = a  =  b, CN = c=d" "Issuer: CN = chez-curl test CA"
                 "X Subject: CN = other" "subject: CN = other")))
    (list (list (car (certificate-names lines "Subject:")))
          (list (cadr (certificate-names lines "Subject:")))
          (list (caddr (certificate-names lines "Subject:")))
          (certificate-names lines "Issuer:")
          (certificate-names '() "Subject:"))))

(test-equal "certificate-names: from $OPENSSL's own text, the good leaf's Subject and Issuer"
  '(("CN=chez-curl test leaf") ("CN=chez-curl test CA"))
  (guard (e (#t (list 'raised (describe e))))
    (let ((lines (certificate-text (pki-file "good.pem"))))
      (list (certificate-names lines "Subject:") (certificate-names lines "Issuer:")))))

(test-equal "certificate-names refuses any label but Subject: and Issuer:, and what certificate-values refuses"
  '((assertion-violation certificate-names ("Signature Algorithm:"))
    (assertion-violation certificate-names ("Subject"))
    (assertion-violation certificate-values (lines)))
  (list (refusal-of (lambda () (certificate-names '("a") "Signature Algorithm:")))
        (refusal-of (lambda () (certificate-names '("a") "Subject")))
        (refusal-of (lambda () (certificate-names 'lines "Subject:")))))

;; The seconds below are date -u's, run outside Chez: date -u -d "2000-01-01
;; 00:00:00" +%s and so on. 2000 is a leap year by the 400-year rule, and
;; 2100 is none by the 100-year one, so the day after its Feb 28 is Mar 1.
(test-equal "certificate-time: x509 -text's dates as seconds since 1970-01-01 UTC, its padded day, a leap day and the centuries' rules"
  '(946684800 946771200 946684799 1792349997 1792522797 1709208000 951782400 951868800 4107542400 0)
  (map (lambda (text) (guard (e (#t (list 'raised (describe e)))) (certificate-time text)))
       '("Jan  1 00:00:00 2000 GMT" "Jan  2 00:00:00 2000 GMT" "Dec 31 23:59:59 1999 GMT"
         "Oct 18 18:59:57 2026 GMT" "Oct 20 18:59:57 2026 GMT" "Feb 29 12:00:00 2024 GMT"
         "Feb 29 00:00:00 2000 GMT" "Mar  1 00:00:00 2000 GMT"
         "Mar  1 00:00:00 2100 GMT" "Jan  1 00:00:00 1970 GMT")))

(for-each
 (lambda (row)
   (test-equal (string-append "certificate-time refuses " (car row))
     (list 'assertion-violation 'certificate-time (list (cadr row)))
     (refusal-of (lambda () (certificate-time (cadr row))))))
 '(("a day not padded" "Jan 1 00:00:00 2000 GMT")
   ("a day padded with a zero" "Jan 01 00:00:00 2000 GMT")
   ("a day its month lacks" "Feb 29 00:00:00 2023 GMT")
   ("the 29th of February 2100, no leap year" "Feb 29 00:00:00 2100 GMT")
   ("a day 0" "Jan  0 00:00:00 2000 GMT")
   ("an hour 24" "Jan  1 24:00:00 2000 GMT")
   ("a minute 60" "Jan  1 00:60:00 2000 GMT")
   ("a second 60" "Jan  1 00:00:60 2000 GMT")
   ("another zone" "Jan  1 00:00:00 2000 UTC")
   ("a month of no name" "Foo  1 00:00:00 2000 GMT")
   ("a month in capitals" "JAN  1 00:00:00 2000 GMT")
   ("a time with no colons" "Jan  1 00.00.00 2000 GMT")
   ("a sign in a number" "Jan  1 -0:00:00 2000 GMT")
   ("an empty text" "")))

(test-equal "certificate-time refuses what is not a string"
  '(assertion-violation certificate-time (5))
  (refusal-of (lambda () (certificate-time 5))))

;; --- pem-certificate --------------------------------------------------------

;; pem-of : String -> Any
;; pem-certificate's answer, or its raise, for a file holding TEXT.
(define (pem-of text)
  (call-with-temp-directory
   (lambda (dir)
     (let ((path (string-append dir "/f.pem")))
       (write-file path text)
       (guard (e ((and (who-condition? e) (message-condition? e) (irritants-condition? e))
                  (list (condition-who e) (condition-message e) (condition-irritants e)))
                 (#t (list 'other (describe e))))
         (pem-certificate path))))))

(test-equal "pem-certificate: the first certificate's base64 text, its lines joined, past a key block and before another certificate"
  cert-a
  (pem-of (string-append (pem-block "EC PRIVATE KEY" cert-b) (pem-block "CERTIFICATE" cert-a)
                         (pem-block "CERTIFICATE" cert-b))))

(test-equal "pem-certificate: the good leaf's file holds what the https face serves"
  'same
  (guard (e (#t (list 'raised (describe e))))
    (parameterize ((origin-pki pki))
      (call-with-origin
       (lambda (o)
         (if (string=? (pem-certificate (pki-file "good.pem"))
                       (peer-leaf (s-client o 'https "localhost" (pki-file "ca.pem") #f)))
             'same
             'differs))))))

(let ((key-only (pem-block "EC PRIVATE KEY" cert-b))
      (open (string-append "-----BEGIN CERTIFICATE-----\n" cert-a "\n"))
      (empty "-----BEGIN CERTIFICATE-----\n-----END CERTIFICATE-----\n"))
  (test-equal "pem-certificate refuses a file with no certificate, an empty one, and one not closed"
    (list (list 'pem-certificate "no -----BEGIN CERTIFICATE----- line" (list key-only))
          (list 'pem-certificate "a certificate is empty" (list empty))
          (list 'pem-certificate "a certificate has no -----END CERTIFICATE----- line" (list open)))
    (map pem-of (list key-only empty open))))

(test-equal "pem-certificate refuses what is not a path"
  '(assertion-violation pem-certificate (5))
  (refusal-of (lambda () (pem-certificate 5))))

(test-end "curl-testing")

;; This suite tests suite-exit-status, so its exit cannot rest on it alone:
;; a suite-exit-status that ignored failures would pass this suite, and
;; make test with it. Any failure here exits 1 first.
(when (positive? (test-runner-fail-count runner))
  (exit 1))

(exit (suite-exit-status runner))
