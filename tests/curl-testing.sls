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
;;; The test origin and the byte probe (M1 plan, section 6; ADR-0005,
;;; amended):
;;;
;;;   call-with-origin   run tests/origin.mjs for the length of a call
;;;   origin-node, origin-pid, origin-face
;;;                      what its announcement says
;;;   origin-script      the origin program it runs, a parameter
;;;   origin-timeout     how long it waits for the origin, a parameter
;;;   read-announcement  one flat JSON object, strictly
;;;   read-within        read a port, bounded by the clock and by size
;;;   wire-probe         tests/wire-probe.mjs against a face
;;;   wire-probe-reset   the same, resetting the connection once it has sent
;;;   wire-probe-half-close
;;;                      the same, half-closing once it has sent
;;;   wire-probe-deadline
;;;                      how long any probe may run in all, a parameter
;;;   parse-wire-probe   the probe's output as a Probe
;;;   probe-bytes, probe-end, probe-arrivals, probe-connected
;;;                      what a Probe holds
;;;
;;; Node is NODE from the environment, else node.
;;;
;;; Test-only: it lives in tests/, which make test puts on Chez's library
;;; path, not in src/. Its own suite is tests/test-curl-testing.sps.
(library (curl-testing)
  (export suite-exit-form suite-exit-status
          capture-command call-with-temp-directory make-process-temp-directory
          remove-temp-directory run-until seeded-bytes describe
          call-with-origin origin-node origin-pid origin-face origin-script origin-timeout
          read-announcement read-within wire-probe wire-probe-reset wire-probe-half-close
          wire-probe-deadline
          parse-wire-probe probe-bytes probe-end probe-arrivals probe-connected)
  (import (rnrs)
          (srfi :64)
          (only (chezscheme) base-exception-handler current-time display-condition
                exit-handler file-directory? get-process-id getenv input-port-ready?
                make-parameter make-time open-process-ports sleep system time-nanosecond
                time-second))

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
         (if (condition? obj) (display-condition obj p) (write obj p))))))

  ;; --- the test origin -----------------------------------------------------

  ;; node-program : -> String
  ;; NODE from the environment, else node.
  (define (node-program)
    (let ((node (getenv "NODE")))
      (if (and node (not (string=? node ""))) node "node")))

  ;; origin-script : (Parameter String)
  ;; The program call-with-origin runs under Node, from the working
  ;; directory: tests/origin.mjs. A test points it at a stand-in.
  (define origin-script
    (make-parameter "tests/origin.mjs"
      (lambda (path)
        (unless (and (string? path) (positive? (string-length path)))
          (assertion-violation 'origin-script "not a path" path))
        path)))

  ;; origin-timeout : (Parameter Positive-Integer)
  ;; The milliseconds call-with-origin waits for the announcement, and then,
  ;; once it has closed the origin's stdin, for its stdout to end, by the
  ;; monotonic clock.
  (define origin-timeout
    (make-parameter 5000
      (lambda (ms)
        (unless (and (integer? ms) (exact? ms) (positive? ms))
          (assertion-violation 'origin-timeout "not a positive exact integer" ms))
        ms)))

  ;; origin-evidence-bytes : Natural
  ;; How much of the origin's stdout, and of its stderr, a raise carries: the
  ;; first 4096 bytes of each. Anything more is read and dropped, so a flood
  ;; costs no memory. The announcement must come within them.
  (define origin-evidence-bytes 4096)

  ;; The keys of an announcement, in order: node, pid, then each face.
  (define origin-faces-named '(http raw))

  ;; An Origin is what its announcement said: its Node's version, its pid, and
  ;; each face's address and port, as ((http "127.0.0.1" . 40001) ...).
  (define-record-type (origin make-origin origin?)
    (fields (immutable node origin-node)
            (immutable pid origin-pid)
            (immutable faces origin-faces)))

  ;; origin-node : Origin -> String
  ;; origin-pid : Origin -> Integer
  ;; origin-face : Origin Symbol -> (Pair String Integer)
  ;; The face named NAME, as its address and port. An unknown face raises.
  (define (origin-face origin name)
    (unless (origin? origin)
      (assertion-violation 'origin-face "not an origin" origin))
    (let ((face (assq name (origin-faces origin))))
      (if face
          (cdr face)
          (assertion-violation 'origin-face "no such face" name))))

  ;; now-ms : -> Integer
  ;; Milliseconds on the monotonic clock.
  (define (now-ms)
    (let ((t (current-time 'time-monotonic)))
      (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

  (define poll-interval (make-time 'time-duration 10000000 0))

  ;; read-until : Binary-Input-Port (Bytevector -> Boolean) Integer Boolean
  ;;              -> (Values (U 'done 'eof 'timeout 'full) Bytevector)
  ;; Reads PORT until a piece it keeps satisfies DONE?, the port ends, or the
  ;; monotonic clock passes DEADLINE, which it reads before every read, so a
  ;; port that is always ready cannot hold it. It keeps the first
  ;; origin-evidence-bytes bytes and drops the rest; with FULL-STOPS?, it
  ;; stops once it has kept that many, as full. It never blocks on the port:
  ;; it reads only what input-port-ready? says is there, which includes the
  ;; end, and sleeps 10 ms between looks. The answer is why it stopped, and
  ;; what it kept, joined once.
  (define (read-until port done? deadline full-stops?)
    (let loop ((pieces '()) (kept 0))
      (cond ((> (now-ms) deadline) (values 'timeout (bytes-join (reverse pieces))))
            ((input-port-ready? port)
             (let ((more (get-bytevector-some port)))
               (if (eof-object? more)
                   (values 'eof (bytes-join (reverse pieces)))
                   (let* ((piece (bytes-prefix more (- origin-evidence-bytes kept)))
                          (pieces (if (positive? (bytevector-length piece)) (cons piece pieces) pieces))
                          (kept (+ kept (bytevector-length piece))))
                     (cond ((done? piece) (values 'done (bytes-join (reverse pieces))))
                           ((and full-stops? (>= kept origin-evidence-bytes))
                            (values 'full (bytes-join (reverse pieces))))
                           (else (loop pieces kept)))))))
            (else (sleep poll-interval) (loop pieces kept)))))

  (define (never bytes) #f)

  ;; read-within : Binary-Input-Port Positive-Integer (Bytevector -> Boolean) Boolean
  ;;               -> (Values (U 'done 'eof 'timeout 'full) Bytevector)
  ;; read-until, for MS milliseconds from now: the bounded read every wait on
  ;; a process uses. It reads the monotonic clock before every read, keeps
  ;; the first origin-evidence-bytes bytes, and stops on DONE?, the end, the
  ;; deadline, or, with FULL-STOPS?, once it has kept that many.
  (define (read-within port ms done? full-stops?)
    (unless (and (integer? ms) (exact? ms) (positive? ms))
      (assertion-violation 'read-within "not a positive exact integer" ms))
    (read-until port done? (+ (now-ms) ms) full-stops?))

  ;; bytes-prefix : Bytevector Natural -> Bytevector
  ;; BYTES' first N bytes, or BYTES whole when it has no more.
  (define (bytes-prefix bytes n)
    (if (<= (bytevector-length bytes) n)
        bytes
        (let ((head (make-bytevector (max n 0))))
          (bytevector-copy! bytes 0 head 0 (max n 0))
          head)))

  ;; bytes-join : (Listof Bytevector) -> Bytevector
  ;; The bytevectors, end to end, copied once.
  (define (bytes-join pieces)
    (let ((joined (make-bytevector (fold-left + 0 (map bytevector-length pieces)))))
      (fold-left (lambda (at piece)
                   (bytevector-copy! piece 0 joined at (bytevector-length piece))
                   (+ at (bytevector-length piece)))
                 0 pieces)
      joined))

  ;; latin-1 : Bytevector -> String
  ;; Each byte as the character of its code, so no byte is lost or refused.
  (define (latin-1 bytes)
    (list->string (map integer->char (bytevector->u8-list bytes))))

  (define (newline-in? bytes)
    (and (memv 10 (bytevector->u8-list bytes)) #t))

  ;; origin-runner : String
  ;; The shell that runs Node, as sh -c RUNNER sh NODE SCRIPT STATUS PID
  ;; STDERR. Chez has no wait, so the shell waits: it starts Node in the
  ;; background, on its own stdin (fd 3, since a background command's stdin
  ;; is /dev/null) and with its stderr in STDERR, records Node's pid in PID,
  ;; waits for it, and writes its exit status to STATUS, 128 plus the signal
  ;; when a signal ended it. The shell holds the stdout pipe until it exits,
  ;; so stdout's end means the status is written. $! is the command's own
  ;; pid (measured with dash), so a kill reaches Node. The shell's own stderr
  ;; is not Node's: dash's wait prints "Killed" there for a job SIGKILL ended
  ;; (measured in Debian), so spawn-origin sends it to /dev/null. A NODE that
  ;; is not found is reported by the background command, into STDERR.
  (define origin-runner
    (string-append "exec 3<&0\n"
                   "\"$1\" \"$2\" <&3 3<&- 2>\"$5\" &\n"
                   "echo $! >\"$4\"\n"
                   "exec 3<&- </dev/null\n"
                   "wait $!\n"
                   "echo $? >\"$3\"\n"))

  ;; A spawned origin: its stdin, its stdout, the runner's pid, and the files
  ;; for its stderr, its exit status and Node's pid.
  (define-record-type (running make-running running?)
    (fields to from pid stderr-path status-path pid-path))

  ;; spawn-origin : String -> Running
  ;; origin-runner, through exec, running $NODE (origin-script), with Node's
  ;; stderr in a file in DIR, where reading it never blocks, and the shell's
  ;; own in /dev/null. open-process-ports closes every other fd in its child
  ;; (measured), so the origin holds no pipe of another.
  (define (spawn-origin dir)
    (let ((stderr-path (string-append dir "/stderr"))
          (status-path (string-append dir "/status"))
          (pid-path (string-append dir "/pid")))
      (let-values (((to from err pid)
                    (open-process-ports
                     (string-append "exec sh -c " (shell-quote origin-runner) " sh "
                                    (shell-quote (node-program)) " " (shell-quote (origin-script)) " "
                                    (shell-quote status-path) " " (shell-quote pid-path) " "
                                    (shell-quote stderr-path) " 2>/dev/null")
                     (buffer-mode block) #f)))
        (close-port err)
        (make-running to from pid stderr-path status-path pid-path))))

  ;; file-prefix : String -> Bytevector
  ;; The first origin-evidence-bytes bytes of the file at PATH, none when it
  ;; is not there.
  (define (file-prefix path)
    (if (file-exists? path)
        (call-with-port (open-file-input-port path)
          (lambda (p)
            (let ((bytes (get-bytevector-n p origin-evidence-bytes)))
              (if (eof-object? bytes) (make-bytevector 0) bytes))))
        (make-bytevector 0)))

  ;; recorded-natural : String -> (U Natural #f)
  ;; The natural a runner file holds, as a line, or #f.
  (define (recorded-natural path)
    (let* ((text (latin-1 (file-prefix path)))
           (n (string-length text)))
      (and (> n 1)
           (char=? (string-ref text (- n 1)) #\newline)
           (natural-text (substring text 0 (- n 1))))))

  ;; kill-9 : Integer -> Unit
  (define (kill-9 pid)
    (system (string-append "kill -9 " (number->string pid) " 2>/dev/null")))

  ;; An Ending is how a stop went: exited or killed, what the origin wrote to
  ;; stdout meanwhile, its stderr, and its exit status (#f when none was
  ;; recorded), each kept to origin-evidence-bytes.
  (define-record-type (ending make-ending ending?)
    (fields how stdout stderr status))

  ;; stop-running : Running Integer -> Ending
  ;; Closes the origin's stdin and waits up to BOUND ms for its stdout to
  ;; end. When it does not, it kills Node, whose pid the runner recorded, and
  ;; waits once more; then, if need be, the runner too. It never raises.
  (define (stop-running running bound)
    (let ((from (running-from running)))
      (define (wait-end) (let-values (((how bytes) (read-until from never (+ (now-ms) bound) #f)))
                           (cons how bytes)))
      (define (ended how bytes)
        (guard (e (#t #f)) (close-port from))
        (make-ending how (bytes-prefix bytes origin-evidence-bytes)
                     (file-prefix (running-stderr-path running))
                     (recorded-natural (running-status-path running))))
      (guard (e (#t (ended 'killed (make-bytevector 0))))
        (guard (e (#t #f)) (close-port (running-to running)))
        (let ((first (wait-end)))
          (if (eq? (car first) 'eof)
              (ended 'exited (cdr first))
              (begin
                (kill-9 (or (recorded-natural (running-pid-path running)) (running-pid running)))
                (let ((second (wait-end)))
                  (unless (eq? (car second) 'eof)
                    (kill-9 (running-pid running))
                    (wait-end))
                  (ended 'killed (bytes-join (list (cdr first) (cdr second)))))))))))

  ;; origin-failure : String Bytevector Ending -> Condition
  ;; The raise for an origin that went wrong: MESSAGE, then what it wrote to
  ;; stdout and to stderr, as (stdout . TEXT) and (stderr . TEXT), and its
  ;; exit status, as (status . N), N #f when none was recorded.
  (define (origin-failure message stdout ending)
    (condition (make-error)
               (make-who-condition 'call-with-origin)
               (make-message-condition message)
               (make-irritants-condition
                (list (cons 'stdout (latin-1 (bytes-prefix stdout origin-evidence-bytes)))
                      (cons 'stderr (latin-1 (ending-stderr ending)))
                      (cons 'status (ending-status ending))))))

  ;; start-origin : Running Integer (-> Ending) -> Origin
  ;; The origin's announcement, read within BOUND ms, as an Origin. On any
  ;; failure it stops the origin with STOP!, then raises, with all it wrote
  ;; and its exit status.
  (define (start-origin running bound stop!)
    (let* ((deadline (+ (now-ms) bound)))
      (let-values (((how bytes) (read-until (running-from running) newline-in? deadline #t)))
        (let ((found
               (case how
                 ((timeout)
                  (string-append "the origin wrote no announcement within "
                                 (number->string bound) " ms"))
                 ((eof) "the origin's stdout ended before its announcement")
                 ((full)
                  (string-append "the origin wrote " (number->string origin-evidence-bytes)
                                 " bytes to stdout with no newline, so no announcement"))
                 (else
                  (let* ((line (latin-1 (line-before-newline bytes)))
                         (rest (- (bytevector-length bytes) (string-length line) 1)))
                    (if (positive? rest)
                        "the origin wrote to stdout after its announcement"
                        (let* ((parsed (guard (e ((message-condition? e) (condition-message e)))
                                         (read-announcement line)))
                               (made (if (string? parsed)
                                         parsed
                                         (announcement->origin parsed (recorded-pid running deadline)))))
                          (if (string? made)
                              (string-append "the origin's announcement is malformed: " made)
                              made))))))))
          (if (origin? found)
              found
              (let ((stopped (stop!)))
                (raise (origin-failure found (bytes-join (list bytes (ending-stdout stopped)))
                                       stopped))))))))

  ;; recorded-pid : Running Integer -> (U Natural #f)
  ;; Node's pid as the runner recorded it, waiting for the file until
  ;; DEADLINE: the runner writes it as it starts Node, before Node can
  ;; announce.
  (define (recorded-pid running deadline)
    (let loop ()
      (or (recorded-natural (running-pid-path running))
          (if (> (now-ms) deadline)
              #f
              (begin (sleep poll-interval) (loop))))))

  (define (line-before-newline bytes)
    (let loop ((i 0))
      (if (= (bytevector-u8-ref bytes i) 10)
          (bytes-prefix bytes i)
          (loop (+ i 1)))))

  ;; announcement->origin : (Listof (Pair String (U String Natural))) (U Natural #f)
  ;;                        -> (U Origin String)
  ;; The Origin an announcement describes, or what is wrong with it: its
  ;; keys must be node, pid, http and raw, in that order, with node a string,
  ;; pid a positive natural, each face ADDRESS:PORT, and then pid the pid of
  ;; the Node process the runner started, SPAWNED.
  (define (announcement->origin entries spawned)
    (let ((keys (map car entries))
          (wanted (append '("node" "pid") (map symbol->string origin-faces-named))))
      (cond
        ((not (equal? keys wanted))
         (string-append "its keys are " (join-words* keys) ", not " (join-words* wanted)))
        ((not (string? (cdr (assoc "node" entries)))) "its node is not a string")
        ((not (and (integer? (cdr (assoc "pid" entries)))
                   (positive? (cdr (assoc "pid" entries)))))
         "its pid is not a positive natural")
        (else
         (let ((faces (map (lambda (name)
                             (cons name (address-and-port (cdr (assoc (symbol->string name) entries)))))
                           origin-faces-named)))
           (let ((bad (find (lambda (face) (not (cdr face))) faces)))
             (cond (bad (string-append "its " (symbol->string (car bad)) " face is not ADDRESS:PORT"))
                   ((not (eqv? (cdr (assoc "pid" entries)) spawned))
                    "its pid is not that of the Node process call-with-origin started")
                   (else (make-origin (cdr (assoc "node" entries)) (cdr (assoc "pid" entries))
                                      faces)))))))))

  (define (join-words* words)
    (if (null? words)
        "none"
        (fold-left (lambda (line word) (string-append line ", " word)) (car words) (cdr words))))

  ;; address-and-port : Any -> (U (Pair String Integer) #f)
  ;; "ADDRESS:PORT" as (ADDRESS . PORT): it splits at the last colon, the
  ;; address is not empty, and the port is a natural, written with no leading
  ;; zero, up to 65535.
  (define (address-and-port value)
    (and (string? value)
         (let loop ((i (- (string-length value) 1)))
           (cond ((< i 1) #f)
                 ((char=? (string-ref value i) #\:)
                  (let ((port (natural-text (substring value (+ i 1) (string-length value)))))
                    (and port (<= port 65535) (cons (substring value 0 i) port))))
                 (else (loop (- i 1)))))))

  ;; natural-text : String -> (U Natural #f)
  (define (natural-text s)
    (and (positive? (string-length s))
         (for-all (lambda (c) (char<=? #\0 c #\9)) (string->list s))
         (or (string=? s "0") (not (char=? (string-ref s 0) #\0)))
         (string->number s)))

  ;; ending-problem : (U Ending #f) (U 'removed String #f) Integer -> (U Condition #f)
  ;; What was wrong with how the origin ended, once PROC returned: a
  ;; temporary directory that could not be removed; a stdout that did not end
  ;; in time, so it was killed; or, ending cleanly, anything on stdout after
  ;; the announcement, anything on stderr, or an exit status other than 0.
  (define (ending-problem ending removal bound)
    (cond
      ((string? removal)
       (condition (make-error) (make-who-condition 'call-with-origin)
                  (make-message-condition "the origin's temporary directory could not be removed")
                  (make-irritants-condition (list removal))))
      ((not ending) #f)
      ((eq? (ending-how ending) 'killed)
       (origin-failure (string-append "the origin's stdout did not end within "
                                      (number->string bound)
                                      " ms of its stdin closing, so it was killed")
                       (ending-stdout ending) ending))
      (else
       (let ((wrong (append
                     (if (positive? (bytevector-length (ending-stdout ending)))
                         '("it wrote to stdout after its announcement") '())
                     (if (positive? (bytevector-length (ending-stderr ending)))
                         '("it wrote to stderr") '())
                     (let ((status (ending-status ending)))
                       (cond ((not status) '("it recorded no exit status"))
                             ((zero? status) '())
                             (else (list (string-append "it exited " (number->string status)))))))))
         (and (pair? wrong)
              (origin-failure (string-append "the origin did not end cleanly: "
                                             (fold-left (lambda (text w) (string-append text "; " w))
                                                        (car wrong) (cdr wrong)))
                              (ending-stdout ending) ending))))))

  ;; call-with-origin : (Origin -> Any) -> Any
  ;; Spawns $NODE (origin-script), NODE from the environment or else node,
  ;; under origin-runner, reads its announcement, and answers (PROC origin).
  ;; Then, whether PROC returns, raises or escapes, it closes the origin's
  ;; stdin and waits up to (origin-timeout) ms for its stdout to end, and
  ;; kills it with SIGKILL if it does not. It never waits on a reap: the
  ;; runner shell reads Node's exit status. Should this process die instead,
  ;; the origin's stdin ends once every process holding its write end has
  ;; gone: children of system inherit Chez's pipe ends, so a probe or command
  ;; running at the death holds it until its own bound ends it,
  ;; wire-probe-deadline for a probe.
  ;;
  ;; It raises, with what the origin wrote to stdout and stderr and its exit
  ;; status, when the origin dies before announcing, announces nothing in
  ;; time, or announces something malformed, a pid other than Node's
  ;; included. Once PROC returns, the origin must have ended cleanly: its
  ;; stdout ended in time, with nothing after the announcement, nothing on
  ;; stderr, and exit status 0. Any other ending raises then. A raise or
  ;; escape from PROC goes on as it was: the origin is still stopped, or
  ;; killed, and nothing about its ending is raised in its place. The
  ;; origin's files go in a temporary directory, removed after.
  (define (call-with-origin proc)
    (unless (procedure? proc)
      (assertion-violation 'call-with-origin "not a procedure" proc))
    (let ((bound (origin-timeout))
          (dir (make-temp-directory))
          (running #f)
          (ended #f)
          (removal #f))
      ;; stop! : -> (U Ending #f)
      ;; Stops the origin, once, and answers how that went. It never raises.
      (define (stop!)
        (when (and running (not ended))
          (set! ended (stop-running running bound)))
        ended)
      (define (clean-up!)
        (stop!)
        (unless removal
          (set! removal (guard (e (#t (describe e)))
                          (remove-temp-directory dir)
                          'removed))))
      (let ((answer
             (call-with-values
               (lambda ()
                 (dynamic-wind
                   (lambda () #f)
                   (lambda ()
                     (set! running (spawn-origin dir))
                     (proc (start-origin running bound stop!)))
                   clean-up!))
               list)))
        (let ((problem (ending-problem ended removal bound)))
          (if problem (raise problem) (apply values answer))))))

  ;; --- read-announcement ---------------------------------------------------

  ;; read-announcement : String -> (Listof (Pair String (U String Natural)))
  ;; TEXT as one flat JSON object, as JSON.stringify writes one: its entries,
  ;; in order, each key a string and each value a string or a natural. It is
  ;; strict, and raises, naming the problem and where, on anything else:
  ;; whitespace anywhere, an escape or a control character in a string, a
  ;; nested object or array, any other value (true, null, -1, 1.5, 1e3, 01),
  ;; a duplicate key, and text after the closing brace, a newline included.
  (define (read-announcement text)
    (unless (string? text)
      (assertion-violation 'read-announcement "not a string" text))
    (let ((n (string-length text)))
      (define (refuse message at) (error 'read-announcement message text at))
      (define (char-at i) (and (< i n) (string-ref text i)))
      (define (digit? c) (and c (char<=? #\0 c #\9)))
      ;; A string opening at I: its text, and the place after it.
      (define (read-string i)
        (let loop ((j (+ i 1)))
          (let ((c (char-at j)))
            (cond ((not c) (refuse "a string is not closed" i))
                  ((char=? c #\") (values (substring text (+ i 1) j) (+ j 1)))
                  ((char=? c #\\) (refuse "an escape in a string" j))
                  ((char<? c #\space) (refuse "a control character in a string" j))
                  (else (loop (+ j 1)))))))
      ;; A natural starting at I: its value, and the place after it.
      (define (read-natural i)
        (let loop ((j i))
          (if (digit? (char-at j))
              (loop (+ j 1))
              (cond ((and (> (- j i) 1) (char=? (string-ref text i) #\0))
                     (refuse "a natural with a leading zero" i))
                    ((memv (char-at j) '(#\. #\e #\E))
                     (refuse "a value is a string or a natural" i))
                    (else (values (string->number (substring text i j)) j))))))
      (define (read-value i)
        (let ((c (char-at i)))
          (cond ((not c) (refuse "the object is not closed" i))
                ((char=? c #\") (read-string i))
                ((digit? c) (read-natural i))
                ((memv c '(#\{ #\[)) (refuse "a nested value" i))
                (else (refuse "a value is a string or a natural" i)))))
      (define (after-object i entries)
        (if (= i n) (reverse entries) (refuse "text after the object" i)))
      (unless (eqv? (char-at 0) #\{)
        (refuse "an announcement is one JSON object, from { to }" 0))
      (if (eqv? (char-at 1) #\})
          (after-object 2 '())
          (let loop ((i 1) (entries '()))
            (unless (eqv? (char-at i) #\")
              (if (char-at i)
                  (refuse "a key is a string" i)
                  (refuse "the object is not closed" i)))
            (let-values (((key after-key) (read-string i)))
              (when (assoc key entries) (refuse "a duplicate key" i))
              (unless (eqv? (char-at after-key) #\:)
                (if (char-at after-key)
                    (refuse "a colon after each key" after-key)
                    (refuse "the object is not closed" after-key)))
              (let-values (((value after-value) (read-value (+ after-key 1))))
                (let ((entries (cons (cons key value) entries)))
                  (case (char-at after-value)
                    ((#\,) (loop (+ after-value 1) entries))
                    ((#\}) (after-object (+ after-value 1) entries))
                    ((#f) (refuse "the object is not closed" after-value))
                    (else (refuse "a comma or } after each value" after-value))))))))))

  ;; --- the probe -----------------------------------------------------------

  ;; The probe program, from the working directory.
  (define probe-script "tests/wire-probe.mjs")

  ;; A Probe is what tests/wire-probe.mjs saw: every byte it received, joined;
  ;; how the connection ended; each chunk's arrival; and when it connected.
  (define-record-type (probe-answer make-probe-answer probe-answer?)
    (fields (immutable bytes probe-bytes)
            (immutable end probe-end)
            (immutable arrivals probe-arrivals)
            (immutable connected probe-connected)))

  ;; probe-bytes : Probe -> Bytevector
  ;; probe-end : Probe -> (U 'eof 'reset 'timeout 'deadline 'reset-sent
  ;;                         (List 'error String) (List 'refused String))
  ;; probe-arrivals : Probe -> (Listof (Pair Natural Natural))
  ;;   each chunk's first byte's offset, and the milliseconds since the probe
  ;;   started when it came. Chunk boundaries are no contract.
  ;; probe-connected : Probe -> (U Natural #f)
  ;;   the milliseconds since the probe started when it connected, taken
  ;;   before it sent a byte; #f when it was refused. So no reply's arrival
  ;;   can be earlier than it plus the time the origin took.

  ;; probe-argument-bytes : Natural
  ;; The most bytes that travel to the probe as hex in its argument: 16 KiB,
  ;; so 32 KiB of hex, a quarter of the 128 KiB Linux allows one argument
  ;; (MAX_ARG_STRLEN), and the whole command, which capture-command hands
  ;; sh -c as one string, stays well inside it. More go through a file,
  ;; as @FILE.
  (define probe-argument-bytes 16384)

  ;; wire-probe : Origin Symbol Bytevector Positive-Integer -> Probe
  ;; Runs $NODE tests/wire-probe.mjs against ORIGIN's face FACE: it sends
  ;; BYTES once, and reads until the connection ends or IDLE-MS pass with no
  ;; data. BYTES travel as hex in the probe's argument, or, beyond
  ;; probe-argument-bytes, in a file in $TMPDIR, or /tmp, removed after. It
  ;; raises when the probe does not exit 0, with its stderr, and when
  ;; parse-wire-probe refuses its output.
  (define (wire-probe origin face bytes idle-ms)
    (run-probe 'wire-probe origin face bytes idle-ms '()))

  ;; wire-probe-reset : Origin Symbol Bytevector -> Probe
  ;; As wire-probe, with --reset: once BYTES are handed to the kernel, the
  ;; probe resets the connection, a client that vanishes with a RST mid-
  ;; request. Its end is reset-sent, unless the connection ended first.
  (define (wire-probe-reset origin face bytes)
    (run-probe 'wire-probe-reset origin face bytes 2000 '("--reset")))

  ;; wire-probe-half-close : Origin Symbol Bytevector Positive-Integer -> Probe
  ;; As wire-probe, with --half-close: once BYTES are handed to the kernel,
  ;; the probe ends its side, a FIN, and goes on reading.
  (define (wire-probe-half-close origin face bytes idle-ms)
    (run-probe 'wire-probe-half-close origin face bytes idle-ms '("--half-close")))

  ;; wire-probe-deadline : (Parameter Positive-Integer)
  ;; The milliseconds every probe may run in all, by the clock, as its
  ;; --deadline: IDLE-MS bounds a silence, and a peer that keeps sending
  ;; would never let it pass. At the deadline the probe's end is deadline.
  (define wire-probe-deadline
    (make-parameter 30000
      (lambda (ms)
        (unless (and (integer? ms) (exact? ms) (positive? ms))
          (assertion-violation 'wire-probe-deadline "not a positive exact integer" ms))
        ms)))

  ;; hex-files : Natural
  ;; How many hex files this process has written: part of each file's name.
  (define hex-files 0)

  (define (run-probe who origin face bytes idle-ms options)
    (let ((address (origin-face origin face)))
      (unless (bytevector? bytes)
        (assertion-violation who "the bytes to send are not a bytevector" bytes))
      (unless (and (integer? idle-ms) (exact? idle-ms) (positive? idle-ms))
        (assertion-violation who "the idle bound is not a positive exact integer" idle-ms))
      (let* ((hex (bytes->hex bytes))
             (file (and (> (bytevector-length bytes) probe-argument-bytes)
                        (begin
                          (set! hex-files (+ hex-files 1))
                          (string-append (scratch-directory) "/curl-testing-"
                                         (number->string (get-process-id)) "-"
                                         (number->string hex-files) ".hex")))))
        (dynamic-wind
          (lambda ()
            (when file
              (remove-files file)
              (call-with-port (open-file-output-port file (file-options no-fail)
                                                     (buffer-mode block) (native-transcoder))
                (lambda (p) (put-string p hex)))))
          (lambda ()
            (let ((answer (capture-command
                           (append (list (node-program) probe-script) options
                                   (list "--deadline" (number->string (wire-probe-deadline)))
                                   (list (car address) (number->string (cdr address))
                                         (if file (string-append "@" file) hex)
                                         (number->string idle-ms))))))
              (unless (= (car answer) 0)
                (error who "the probe did not exit 0" (car answer) (caddr answer)))
              (parse-wire-probe (cadr answer))))
          (lambda () (when file (remove-files file)))))))

  ;; bytes->hex : Bytevector -> String
  ;; Two lower-case hex digits per byte.
  (define (bytes->hex bytes)
    (let ((digits "0123456789abcdef"))
      (call-with-string-output-port
       (lambda (p)
         (for-each (lambda (b)
                     (put-char p (string-ref digits (div b 16)))
                     (put-char p (string-ref digits (mod b 16))))
                   (bytevector->u8-list bytes))))))

  ;; hex->bytes : String -> (U Bytevector #f)
  ;; Pairs of lower-case hex digits as bytes, #f for any other text.
  (define (hex->bytes text)
    (let ((n (string-length text)))
      (define (digit c)
        (cond ((char<=? #\0 c #\9) (- (char->integer c) 48))
              ((char<=? #\a c #\f) (- (char->integer c) 87))
              (else #f)))
      (and (even? n)
           (let ((bytes (make-bytevector (div n 2))))
             (let loop ((i 0))
               (if (= i n)
                   bytes
                   (let ((high (digit (string-ref text i)))
                         (low (digit (string-ref text (+ i 1)))))
                     (and high low
                          (begin (bytevector-u8-set! bytes (div i 2) (+ (* 16 high) low))
                                 (loop (+ i 2)))))))))))

  ;; parse-wire-probe : String -> Probe
  ;; The probe's stdout, TEXT, as a Probe. It must be Scheme data in one of
  ;; two shapes, and it raises, naming the datum at fault, on anything else:
  ;;   (refused "CODE" MS)
  ;;   (connected MS) (data OFFSET MS "HEX") ... END
  ;; END being (end KIND MS), KIND eof, reset, timeout or deadline; (end error MS
  ;; "CODE"); or (reset-sent MS), whose end is reset-sent. Each data's OFFSET
  ;; is the count of bytes before it, its HEX holds at least one byte, and no
  ;; time is less than the one before it.
  (define (parse-wire-probe text)
    (unless (string? text)
      (assertion-violation 'parse-wire-probe "not a string" text))
    (let ((data (guard (e (#t (error 'parse-wire-probe "the probe's output is not Scheme data" text)))
                  (read-all text))))
      (define (refuse message datum) (error 'parse-wire-probe message datum))
      (define (ms? x) (and (integer? x) (exact? x) (>= x 0)))
      (cond
        ((null? data) (refuse "the probe printed nothing" text))
        ((and (pair? (car data)) (eq? (caar data) 'refused))
         (let ((line (car data)))
           (unless (and (= (length line) 3) (string? (cadr line)) (ms? (caddr line)))
             (refuse "a refused line is (refused \"CODE\" MS)" line))
           (unless (null? (cdr data))
             (refuse "nothing follows a refused line" (cadr data)))
           (make-probe-answer (make-bytevector 0) (list 'refused (cadr line)) '() #f)))
        ((not (and (list? (car data)) (= (length (car data)) 2)
                   (eq? (caar data) 'connected) (ms? (cadar data))))
         (refuse "the first line is (connected MS) or (refused \"CODE\" MS)" (car data)))
        (else
         (let loop ((rest (cdr data)) (offset 0) (last-ms (cadar data))
                    (chunks '()) (arrivals '()))
           (when (null? rest) (refuse "the probe's output has no end line" text))
           (let ((line (car rest)))
             (cond
               ((and (pair? line) (eq? (car line) 'data))
                (unless (and (list? line) (= (length line) 4) (ms? (cadr line))
                             (ms? (caddr line)) (string? (cadddr line)))
                  (refuse "a data line is (data OFFSET MS \"HEX\")" line))
                (let ((bytes (hex->bytes (cadddr line))))
                  (unless (and bytes (positive? (bytevector-length bytes)))
                    (refuse "a data line's HEX is one byte or more, as lower-case hex" line))
                  (unless (= (cadr line) offset)
                    (refuse "a data line's offset is not the count of bytes before it" line))
                  (unless (>= (caddr line) last-ms)
                    (refuse "a time is less than the one before it" line))
                  (loop (cdr rest) (+ offset (bytevector-length bytes)) (caddr line)
                        (cons bytes chunks) (cons (cons (cadr line) (caddr line)) arrivals))))
               ((and (pair? line) (memq (car line) '(end reset-sent)))
                (let ((end (end-kind line)))
                  (unless end
                    (refuse "an end line is (end KIND MS), (end error MS \"CODE\") or (reset-sent MS)" line))
                  (unless (>= (if (eq? end 'reset-sent) (cadr line) (caddr line)) last-ms)
                    (refuse "a time is less than the one before it" line))
                  (unless (null? (cdr rest))
                    (refuse "nothing follows the end line" (cadr rest)))
                  (make-probe-answer (bytes-join (reverse chunks)) end (reverse arrivals)
                                     (cadar data))))
               (else (refuse "a line is (data ...), (end ...) or (reset-sent MS)" line)))))))))

  ;; end-kind : Any -> (U 'eof 'reset 'timeout 'reset-sent (List 'error String) #f)
  (define (end-kind line)
    (and (list? line)
         (cond ((eq? (car line) 'reset-sent)
                (and (= (length line) 2) (integer? (cadr line)) (exact? (cadr line))
                     (>= (cadr line) 0)
                     'reset-sent))
               ((and (= (length line) 3) (memq (cadr line) '(eof reset timeout deadline))
                     (integer? (caddr line)) (exact? (caddr line)) (>= (caddr line) 0))
                (cadr line))
               ((and (= (length line) 4) (eq? (cadr line) 'error)
                     (integer? (caddr line)) (exact? (caddr line)) (>= (caddr line) 0)
                     (string? (cadddr line)))
                (list 'error (cadddr line)))
               (else #f))))

  ;; read-all : String -> (Listof Any)
  ;; Every datum in TEXT. It raises on text that is not Scheme data.
  (define (read-all text)
    (let ((port (open-string-input-port text)))
      (let loop ((found '()))
        (let ((datum (get-datum port)))
          (if (eof-object? datum)
              (reverse found)
              (loop (cons datum found))))))))
