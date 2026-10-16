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
              file-directory?)
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

(test-end "curl-testing")

;; This suite tests suite-exit-status, so its exit cannot rest on it alone:
;; a suite-exit-status that ignored failures would pass this suite, and
;; make test with it. Any failure here exits 1 first.
(when (positive? (test-runner-fail-count runner))
  (exit 1))

(exit (suite-exit-status runner))
