#!r6rs
;;; (curl-testing): what every suite shares (ADR-0015).
;;;
;;;   suite-exit-form    the last datum of every tests/test-*.sps
;;;   suite-exit-status  the verdict that form exits with
;;;   capture-command    run a command; its exit status, stdout and stderr
;;;   call-with-temp-directory
;;;                      a fresh mktemp -d directory, removed after a call
;;;   make-process-temp-directory
;;;                      one removed when the process ends
;;;   remove-temp-directory
;;;                      a directory and all it holds, removed
;;;   run-until          step until a predicate holds, capped by steps
;;;   seeded-bytes       a payload that is the same on every run
;;;   describe           a raised object as text, for evidence
;;;
;;; Test-only: it lives in tests/, which make test puts on Chez's library
;;; path, not in src/. Its own suite is tests/test-curl-testing.sps.
(library (curl-testing)
  (export suite-exit-form suite-exit-status
          capture-command call-with-temp-directory make-process-temp-directory
          remove-temp-directory run-until seeded-bytes describe)
  (import (rnrs)
          (srfi :64)
          (only (chezscheme) base-exception-handler display-condition
                exit-handler file-directory? get-process-id getenv system))

  ;; --- the shared exit form ------------------------------------------------

  ;; suite-exit-form : Sexp
  ;; The last datum of every tests/test-*.sps, exactly: make check-suites
  ;; reads each suite as data and compares its last datum with this one.
  ;; `runner` is the suite's own binding for the runner it makes current. A
  ;; suite that never makes it current leaves it with no test, and fails.
  (define suite-exit-form '(exit (suite-exit-status runner)))

  ;; suite-exit-status : Test-Runner -> (U 0 1)
  ;; 0 when RUNNER saw a pass, and no failure and no unexpected pass.
  ;; Otherwise 1, after one line on the error port giving the counts.
  ;; Expected failures and skips count neither way. SRFI-64 sets no exit
  ;; status of its own. The answer is 0 or 1, never a count: exit statuses
  ;; wrap at 256, so 256 failures would exit 0.
  (define (suite-exit-status runner)
    (unless (test-runner? runner)
      (assertion-violation 'suite-exit-status "not a SRFI-64 test runner" runner))
    (let ((pass (test-runner-pass-count runner))
          (fail (test-runner-fail-count runner))
          (xpass (test-runner-xpass-count runner)))
      (if (and (> pass 0) (= fail 0) (= xpass 0))
          0
          (let ((err (current-error-port)))
            ;; The runner's own summary, on stdout, comes first.
            (flush-output-port (current-output-port))
            (put-string err
              (string-append "suite-exit-status: exit 1 (pass " (number->string pass)
                             ", fail " (number->string fail)
                             ", xpass " (number->string xpass)
                             "): a suite needs a pass, and no fail or xpass\n"))
            (flush-output-port err)
            1))))

  ;; --- capture-command -----------------------------------------------------

  ;; capture-command : (Listof String) -> (List Integer String String)
  ;; Runs ARGV, a command's name and then its arguments, through /bin/sh.
  ;; Each one is quoted, so it arrives as one word, unchanged. stdin is
  ;; /dev/null. The answer is the exit status as Chez's `system` reports it
  ;; (minus the signal number, when a signal killed the command), then all
  ;; the command wrote to stdout and to stderr, as UTF-8. A non-zero exit is
  ;; an answer, not a raise, so a test compares the whole list with what it
  ;; expects.
  ;;
  ;; A NUL is refused: `system` takes a C string, which would end there and
  ;; run whatever came before it. The two streams go through files in
  ;; $TMPDIR, or /tmp, named for this process and call, removed after.
  (define (capture-command argv)
    (check-command argv)
    (set! captures (+ captures 1))
    (let* ((base (string-append (scratch-directory) "/curl-testing-"
                                (number->string (get-process-id)) "-"
                                (number->string captures)))
           (out (string-append base ".out"))
           (err (string-append base ".err")))
      (remove-files out err)
      (let ((status (system (string-append (join-words (map shell-quote argv))
                                           " </dev/null >" (shell-quote out)
                                           " 2>" (shell-quote err)))))
        (let* ((stdout (file->string out))
               (stderr (file->string err)))
          (remove-files out err)
          (list status stdout stderr)))))

  ;; How many commands this process has captured: part of each file's name.
  (define captures 0)

  (define (check-command argv)
    (unless (and (pair? argv) (list? argv))
      (assertion-violation 'capture-command "a command is a non-empty list of strings" argv))
    (for-each
     (lambda (arg)
       (unless (string? arg)
         (assertion-violation 'capture-command "an argument is not a string" arg))
       (when (memv #\nul (string->list arg))
         (assertion-violation 'capture-command
                              "an argument holds a NUL, which would end the command there"
                              arg)))
     argv))

  (define (scratch-directory)
    (let ((dir (getenv "TMPDIR")))
      (if (and dir (not (string=? dir ""))) dir "/tmp")))

  ;; shell-quote : String -> String
  ;; S as one POSIX shell word: in single quotes, each ' written as '\''.
  (define (shell-quote s)
    (call-with-string-output-port
     (lambda (p)
       (put-char p #\')
       (string-for-each (lambda (c)
                          (if (char=? c #\')
                              (put-string p "'\\''")
                              (put-char p c)))
                        s)
       (put-char p #\'))))

  (define (join-words words)
    (fold-left (lambda (line word) (string-append line " " word))
               (car words) (cdr words)))

  ;; A capture file the shell did not create is a raise, never an empty
  ;; answer, since it means the command did not run as asked.
  (define (file->string path)
    (unless (file-exists? path)
      (error 'capture-command "the shell did not create a capture file" path))
    (let* ((port (open-file-input-port path))
           (bytes (get-bytevector-all port)))
      (close-port port)
      (if (eof-object? bytes) "" (utf8->string bytes))))

  (define (remove-files . paths)
    (for-each (lambda (path) (when (file-exists? path) (delete-file path))) paths))

  ;; --- temporary directories -----------------------------------------------

  ;; call-with-temp-directory : (String -> Any) -> Any
  ;; Makes a fresh directory with `mktemp -d`, under $TMPDIR or /tmp, and
  ;; answers (PROC DIR), DIR being its absolute path. Afterwards the directory
  ;; and all it holds are removed, whether PROC returns, raises or escapes.
  ;; It raises before PROC runs when mktemp's answer is refused, below.
  (define (call-with-temp-directory proc)
    (let ((dir (make-temp-directory)))
      (dynamic-wind
        (lambda () #f)
        (lambda () (proc dir))
        (lambda () (remove-temp-directory dir)))))

  ;; make-process-temp-directory : -> String
  ;; A fresh directory, as call-with-temp-directory makes, for a suite whose
  ;; body is flat top-level forms and cannot be wrapped. It is removed when
  ;; the process ends: through `exit`, or through a raise that nothing
  ;; guards, which ends a program with status 255 without calling the exit
  ;; handler. A program that falls off its last form calls neither (measured
  ;; at 10.4.0), so a suite ends with (exit ...), as check-suites requires.
  ;; A warning, which Chez raises to the same handler and goes on from, does
  ;; not remove it. remove-temp-directory removes it earlier, and the hooks
  ;; then find nothing to do. A removal that fails in a hook is ignored
  ;; there: it must not stop an exit, nor raise from the handler it runs in.
  (define (make-process-temp-directory)
    (let ((dir (make-temp-directory)))
      (exit-handler
       (let ((previous (exit-handler)))
         (lambda args
           (remove-quietly dir)
           (apply previous args))))
      (base-exception-handler
       (let ((previous (base-exception-handler)))
         (lambda (condition)
           (unless (warning? condition)
             (remove-quietly dir))
           (previous condition))))
      dir))

  (define (remove-quietly dir)
    (guard (e (#t #f)) (remove-temp-directory dir)))

  ;; remove-temp-directory : String -> Unit
  ;; Removes the directory DIR and all it holds; DIR may be gone already.
  ;; Only an absolute path other than / is removed. It raises when the
  ;; directory is still there afterwards.
  (define (remove-temp-directory dir)
    (unless (absolute-path? dir)
      (assertion-violation 'remove-temp-directory "not an absolute path" dir))
    (when (string=? dir "/")
      (assertion-violation 'remove-temp-directory "not the root directory" dir))
    (when (file-exists? dir)
      (capture-command (list "rm" "-rf" dir))
      (when (file-exists? dir)
        (error 'remove-temp-directory "could not remove the directory" dir))))

  ;; make-temp-directory : -> String
  ;; A fresh directory from `mktemp -d`, given a template under $TMPDIR, or
  ;; /tmp: a bare `mktemp -d` honours TMPDIR on Linux and ignores it on
  ;; macOS, while both read a template alike. mktemp prints the path and a
  ;; newline. The path is that line, whole: $TMPDIR may hold a space, and a
  ;; path cut at whitespace names another directory, which a removal would
  ;; then destroy. So the answer must be exactly one line, an absolute path
  ;; to a directory that exists. Any other answer (a relative path, a second
  ;; line, a missing directory, a failure) is refused with a raise, and
  ;; nothing is removed.
  (define (make-temp-directory)
    (let* ((made (capture-command (list "mktemp" "-d" (temp-template))))
           (dir (single-line (cadr made))))
      (if (and (= (car made) 0) dir (absolute-path? dir) (file-directory? dir))
          dir
          (error 'make-temp-directory
                 "mktemp -d did not answer one absolute path to a directory" made))))

  ;; temp-template : -> String
  ;; mktemp's template: the scratch directory, without the slash macOS's
  ;; TMPDIR ends with, then curl-testing.XXXXXX.
  (define (temp-template)
    (let loop ((dir (scratch-directory)))
      (let ((n (string-length dir)))
        (if (and (> n 0) (char=? (string-ref dir (- n 1)) #\/))
            (loop (substring dir 0 (- n 1)))
            (string-append dir "/curl-testing.XXXXXX")))))

  ;; single-line : String -> (U String #f)
  ;; TEXT without its one final newline, when that leaves a line: not empty,
  ;; and with no newline in it.
  (define (single-line text)
    (let ((n (string-length text)))
      (and (> n 1)
           (char=? (string-ref text (- n 1)) #\newline)
           (let ((line (substring text 0 (- n 1))))
             (and (not (memv #\newline (string->list line))) line)))))

  (define (absolute-path? s)
    (and (> (string-length s) 0) (char=? (string-ref s 0) #\/)))

  ;; --- run-until -----------------------------------------------------------

  ;; run-until : (-> Any) (-> Any) Positive-Integer
  ;;             -> (U 'satisfied 'iterations-exhausted)
  ;; Calls STEP until DONE? answers true, or until STEP has run MAX-STEPS
  ;; times. DONE? is asked first, so a condition that already holds costs no
  ;; step, and again after every step, the last included. The answer is a
  ;; symbol, never a boolean, so it cannot be taken for the #f that SRFI-64
  ;; makes of a raise. The cap counts steps, not time, so a slow machine
  ;; does not make a suite flaky.
  (define (run-until step done? max-steps)
    (unless (procedure? step)
      (assertion-violation 'run-until "the step is not a procedure" step))
    (unless (procedure? done?)
      (assertion-violation 'run-until "the predicate is not a procedure" done?))
    (unless (and (integer? max-steps) (exact? max-steps) (positive? max-steps))
      (assertion-violation 'run-until "the cap is not a positive exact integer" max-steps))
    (let loop ((taken 0))
      (cond ((done?) 'satisfied)
            ((>= taken max-steps) 'iterations-exhausted)
            (else (step) (loop (+ taken 1))))))

  ;; --- seeded-bytes --------------------------------------------------------

  ;; seeded-bytes : Natural Natural -> Bytevector
  ;; N bytes that depend on SEED alone, the same on every run and machine,
  ;; so a test that compares a payload can say which byte differed. A
  ;; linear congruential generator, x <- (1103515245 x + 12345) mod 2^31,
  ;; from x = SEED; each byte is bits 16 to 23 of the new x. The low bits of
  ;; such a generator repeat with a short period (bit 0 alternates), so they
  ;; are not used. A fixture, not a source of randomness.
  (define (seeded-bytes n seed)
    (unless (and (integer? n) (exact? n) (>= n 0))
      (assertion-violation 'seeded-bytes "the length is not a natural number" n))
    (unless (and (integer? seed) (exact? seed) (>= seed 0))
      (assertion-violation 'seeded-bytes "the seed is not a natural number" seed))
    (let ((bytes (make-bytevector n)))
      (let fill ((i 0) (x (mod seed 2147483648)))
        (if (= i n)
            bytes
            (let ((next (mod (+ (* 1103515245 x) 12345) 2147483648)))
              (bytevector-u8-set! bytes i (mod (div next 65536) 256))
              (fill (+ i 1) next))))))

  ;; --- describe ------------------------------------------------------------

  ;; describe : Any -> String
  ;; OBJ as text, for a test to carry as evidence of what was raised: a
  ;; condition as display-condition shows it, anything else written. Total:
  ;; when printing OBJ raises, the answer is a fixed text, so a guard clause
  ;; that calls it cannot raise in turn.
  (define (describe obj)
    (guard (e (#t "<the raised object could not be printed>"))
      (call-with-string-output-port
       (lambda (p)
         (if (condition? obj) (display-condition obj p) (write obj p)))))))
