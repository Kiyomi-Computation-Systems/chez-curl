#!r6rs
;;; (curl-testing): what every suite shares (ADR-0015).
;;;
;;;   suite-exit-form    the last datum of every tests/test-*.sps
;;;   suite-exit-status  the verdict that form exits with: the runner's
;;;                      counts, and (curl private counters)' native counts
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
;;;   wire-probe-tls     #f, or the SNI and ALPN every probe speaks TLS with,
;;;                      a parameter
;;;   parse-wire-probe   the probe's output as a Probe
;;;   probe-bytes, probe-end, probe-arrivals, probe-connected, probe-ended
;;;                      what a Probe holds
;;;   bounded            capture-command under GNU timeout's 10 s
;;;
;;; The TLS material and its checker, openssl (M1 plan, section 8):
;;;
;;;   origin-pki         #f, or the PKI directory call-with-origin hands the
;;;                      origin as --pki, a parameter
;;;   make-test-pki      a fresh PKI, from tests/make-test-pki.sh
;;;   test-pki-script    the script it runs, a parameter
;;;   openssl-program    OPENSSL from the environment, else openssl
;;;   s-client           openssl s_client against a face, as a Peer
;;;   parse-s-client     s_client's stdout and stderr as a Peer
;;;   peer-verify-errors, peer-verify-code, peer-alpn, peer-leaf, peer-chain
;;;                      what a Peer holds
;;;   certificate-text   a certificate file's x509 -text, as trimmed lines
;;;   certificate-values what those lines say after a label
;;;   certificate-names  a Subject or Issuer line's names, read portably
;;;   certificate-time   an x509 -text date, as seconds since 1970, UTC
;;;   certificate-san    a certificate file's subjectAltName, from x509 -text
;;;   pem-certificate    a PEM file's first certificate, as its base64 text
;;;
;;; Node is NODE from the environment, else node, and openssl is OPENSSL,
;;; else openssl.
;;;
;;; Test-only: it lives in tests/, which make test puts on Chez's library
;;; path, not in src/. Its own suite is tests/test-curl-testing.sps.
(library (curl-testing)
  (export suite-exit-form suite-exit-status
          capture-command call-with-temp-directory make-process-temp-directory
          remove-temp-directory run-until seeded-bytes describe
          call-with-origin origin-node origin-pid origin-face origin-script origin-timeout
          read-announcement read-within wire-probe wire-probe-reset wire-probe-half-close
          wire-probe-deadline wire-probe-tls
          parse-wire-probe probe-bytes probe-end probe-arrivals probe-connected probe-ended
          bounded origin-pki make-test-pki test-pki-script openssl-program
          s-client parse-s-client peer-verify-errors peer-verify-code peer-alpn peer-leaf
          peer-chain certificate-text certificate-values certificate-names certificate-time
          certificate-san
          pem-certificate)
  (import (rnrs)
          (srfi :64)
          (curl private counters)
          (only (chezscheme) base-exception-handler critical-section current-time
                delete-directory directory-list display-condition exit-handler
                file-directory? get-process-id getenv input-port-ready? make-mutex
                make-parameter make-time mkdir open-process-ports sleep system
                time-nanosecond time-second with-mutex)
          ;; Chez's file-exists? takes a second argument, #f not to follow a
          ;; symbolic link; (rnrs)'s takes one.
          (prefix (only (chezscheme) file-exists?) chez:))

  ;; --- the shared exit form ------------------------------------------------

  ;; suite-exit-form : Sexp
  ;; The last datum of every tests/test-*.sps, exactly: make check-suites
  ;; reads each suite as data and compares its last datum with this one.
  ;; `runner` is the suite's own binding for the runner it makes current. A
  ;; suite that never makes it current leaves it with no test, and fails.
  (define suite-exit-form '(exit (suite-exit-status runner)))

  ;; suite-exit-status : Test-Runner -> (U 0 1)
  ;; 0 when RUNNER saw a pass, and no failure and no unexpected pass, and
  ;; every count of (curl private counters) is zero. Otherwise 1, after a
  ;; line on the error port for each rule broken: the runner's counts, then
  ;; each native count that is not zero, in native-kinds order (ADR-0014,
  ;; decision 7, amended: a native object a suite made and never freed is a
  ;; leak, which Valgrind sees as still reachable when a Chez object held
  ;; its address). Expected failures and skips count neither way. SRFI-64
  ;; sets no exit status of its own. The answer is 0 or 1, never a count:
  ;; exit statuses wrap at 256, so 256 failures would exit 0.
  (define (suite-exit-status runner)
    (unless (test-runner? runner)
      (assertion-violation 'suite-exit-status "not a SRFI-64 test runner" runner))
    (let* ((pass (test-runner-pass-count runner))
           (fail (test-runner-fail-count runner))
           (xpass (test-runner-xpass-count runner))
           (runner-ok? (and (> pass 0) (= fail 0) (= xpass 0)))
           (left (filter (lambda (entry) (not (eqv? (cdr entry) 0))) (native-counts))))
      (if (and runner-ok? (null? left))
          0
          (let ((err (current-error-port)))
            ;; The runner's own summary, on stdout, comes first.
            (flush-output-port (current-output-port))
            (unless runner-ok?
              (put-string err
                (string-append "suite-exit-status: exit 1 (pass " (number->string pass)
                               ", fail " (number->string fail)
                               ", xpass " (number->string xpass)
                               "): a suite needs a pass, and no fail or xpass\n")))
            (unless (null? left)
              (put-string err
                (string-append "suite-exit-status: exit 1 (native objects left: "
                               (join-words*
                                (map (lambda (entry)
                                       (string-append (symbol->string (car entry)) " "
                                                      (number->string (cdr entry))))
                                     left))
                               "): every native object a suite makes must be freed by its end\n")))
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
  ;; run whatever came before it. The two streams go through two files in a
  ;; directory of the call's own (make-capture-directory), removed after,
  ;; however the call ends. Any thread may call it, and calls on several at
  ;; once share no file. `system` lets other threads collect while the
  ;; command runs, except inside a critical section, where it holds them
  ;; all until the command ends (Chez 10.4.0's c/prim5.c; measured in spike
  ;; E1, .plans/research/e1/findings.md).
  (define (capture-command argv)
    (check-command argv)
    (let ((dir #f))
      (dynamic-wind
        (lambda () #f)
        (lambda ()
          ;; Made and recorded in one critical section, so that no escape
          ;; leaves a directory the after thunk cannot see.
          (critical-section (set! dir (make-capture-directory)))
          (let* ((out (string-append dir "/out"))
                 (err (string-append dir "/err"))
                 (status (system (string-append (join-words (map shell-quote argv))
                                                " </dev/null >" (shell-quote out)
                                                " 2>" (shell-quote err)))))
            (let* ((stdout (file->string out))
                   (stderr (file->string err)))
              (list status stdout stderr))))
        (lambda ()
          (when dir
            (for-each (lambda (name)
                        (guard (e (#t #f)) (remove-files (string-append dir "/" name))))
                      '("out" "err"))
            (delete-directory dir))))))

  ;; make-capture-directory : -> String
  ;; A fresh directory for one capture's files: the scratch directory, then
  ;; curl-testing-PID-N, N counted for this process under a mutex. Chez's
  ;; mkdir makes it with mode 700, and refuses a name that anything already
  ;; holds, a dangling symbolic link included (measured at 10.4.0). So no
  ;; two captures share a file, in this process or any other, and none
  ;; writes through a name someone else planted. A name that is taken costs
  ;; the next N, up to 100 tries; any other failure raises, before the
  ;; command runs. The mutex keeps this process's numbers distinct, so a
  ;; name is taken only by another process or what one left behind.
  (define (make-capture-directory)
    (let ((base (string-append (scratch-root) "/curl-testing-"
                               (number->string (get-process-id)) "-")))
      (let try ((tries 1))
        (let ((dir (string-append base (number->string (next-capture)))))
          (cond
            ((guard (e (#t #f)) (mkdir dir #o700) #t) dir)
            ((and (< tries 100) (chez:file-exists? dir #f)) (try (+ tries 1)))
            (else (error 'capture-command "could not make a directory for the command's output"
                         dir)))))))

  ;; next-capture : -> Positive-Integer
  ;; How many captures this process has begun, this one included. The
  ;; mutex is held through critical-section around with-mutex, so no
  ;; escape can leave it held (traps.md).
  (define (next-capture)
    (critical-section
     (with-mutex capture-mutex
       (set! captures (+ captures 1))
       captures)))

  (define capture-mutex (make-mutex))
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
    (string-append (scratch-root) "/curl-testing.XXXXXX"))

  ;; scratch-root : -> String
  ;; The scratch directory without the slashes it may end with, as macOS's
  ;; TMPDIR does: a name is appended to it after one slash.
  (define (scratch-root)
    (let loop ((dir (scratch-directory)))
      (let ((n (string-length dir)))
        (if (and (> n 0) (char=? (string-ref dir (- n 1)) #\/))
            (loop (substring dir 0 (- n 1)))
            dir))))

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

  ;; origin-faces-named : Boolean -> (Listof Symbol)
  ;; The faces an announcement names, in order, after node and pid: the
  ;; plaintext ones, and, with a PKI, the TLS ones after them.
  (define (origin-faces-named pki?)
    (append '(http raw h2c)
            (if pki? '(https https-expired https-wrong-host https-untrusted raw-tls h2) '())))

  ;; origin-pki : (Parameter (U String #f))
  ;; #f, or a directory, as make-test-pki makes one. With a directory,
  ;; call-with-origin runs the origin with --pki DIR, and requires the TLS
  ;; faces in its announcement.
  (define origin-pki
    (make-parameter #f
      (lambda (dir)
        (unless (or (not dir) (and (string? dir) (positive? (string-length dir))))
          (assertion-violation 'origin-pki "not #f, nor a directory's path" dir))
        dir)))

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
  ;; STDERR ARG..., each ARG an argument of the script's. Chez has no wait,
  ;; so the shell waits: it starts Node in the
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
                   "node=$1 script=$2 status=$3 pid=$4 stderr=$5\n"
                   "shift 5\n"
                   "\"$node\" \"$script\" \"$@\" <&3 3<&- 2>\"$stderr\" &\n"
                   "echo $! >\"$pid\"\n"
                   "exec 3<&- </dev/null\n"
                   "wait $!\n"
                   "echo $? >\"$status\"\n"))

  ;; A spawned origin: its stdin, its stdout, the runner's pid, and the files
  ;; for its stderr, its exit status and Node's pid.
  (define-record-type (running make-running running?)
    (fields to from pid stderr-path status-path pid-path))

  ;; spawn-origin : String (Listof String) -> Running
  ;; origin-runner, through exec, running $NODE (origin-script) ARGS, with
  ;; Node's stderr in a file in DIR, where reading it never blocks, and the
  ;; shell's own in /dev/null. open-process-ports closes every other fd in
  ;; its child (measured), so the origin holds no pipe of another.
  (define (spawn-origin dir args)
    (let ((stderr-path (string-append dir "/stderr"))
          (status-path (string-append dir "/status"))
          (pid-path (string-append dir "/pid")))
      (let-values (((to from err pid)
                    (open-process-ports
                     (string-append "exec sh -c " (shell-quote origin-runner) " sh "
                                    (shell-quote (node-program)) " " (shell-quote (origin-script)) " "
                                    (shell-quote status-path) " " (shell-quote pid-path) " "
                                    (shell-quote stderr-path)
                                    (apply string-append
                                           (map (lambda (arg) (string-append " " (shell-quote arg))) args))
                                    " 2>/dev/null")
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

  ;; start-origin : Running Integer Boolean (-> Ending) -> Origin
  ;; The origin's announcement, read within BOUND ms, as an Origin, with the
  ;; TLS faces when PKI?. On any failure it stops the origin with STOP!, then
  ;; raises, with all it wrote and its exit status.
  (define (start-origin running bound pki? stop!)
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
                                         (announcement->origin parsed (recorded-pid running deadline)
                                                               pki?))))
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

  ;; announcement->origin : (Listof (Pair String (U String Natural))) (U Natural #f) Boolean
  ;;                        -> (U Origin String)
  ;; The Origin an announcement describes, or what is wrong with it: its
  ;; keys must be node, pid, and then each face origin-faces-named names for
  ;; PKI?, in that order, with node a string, pid a positive natural, each
  ;; face ADDRESS:PORT, and then pid the pid of the Node process the runner
  ;; started, SPAWNED.
  (define (announcement->origin entries spawned pki?)
    (let* ((named (origin-faces-named pki?))
           (keys (map car entries))
           (wanted (append '("node" "pid") (map symbol->string named))))
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
                           named)))
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
  ;; with --pki DIR when origin-pki is DIR, under origin-runner, reads its
  ;; announcement, and answers (PROC origin). With a PKI, the announcement
  ;; must name the TLS faces too.
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
          (pki (origin-pki))
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
                     (set! running (spawn-origin dir (if pki (list "--pki" pki) '())))
                     (proc (start-origin running bound (and pki #t) stop!)))
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
  ;; how the connection ended; each chunk's arrival; when it connected; and
  ;; when it ended.
  (define-record-type (probe-answer make-probe-answer probe-answer?)
    (fields (immutable bytes probe-bytes)
            (immutable end probe-end)
            (immutable arrivals probe-arrivals)
            (immutable connected probe-connected)
            (immutable ended probe-ended)))

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
  ;; probe-ended : Probe -> Natural
  ;;   the milliseconds since the probe started when it ended: its end,
  ;;   reset-sent or refused line's MS. A refusal before the handshake is done
  ;;   is bounded by nothing but wire-probe-deadline, so a test that claims a
  ;;   time asserts it here.

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
  ;; request. Its end is reset-sent, unless the connection ended first. The
  ;; probe has no reset over TLS, so under wire-probe-tls it raises, before
  ;; running one.
  (define (wire-probe-reset origin face bytes)
    (when (wire-probe-tls)
      (assertion-violation 'wire-probe-reset
                           "the probe has no reset over TLS, and wire-probe-tls is set"
                           (wire-probe-tls)))
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

  ;; wire-probe-tls : (Parameter (U #f (Pair String (Listof String))))
  ;; #f, or a list of SERVERNAME and then the ALPN protocols. While it is a
  ;; list, every probe speaks TLS, with --tls SERVERNAME, a DNS name, and,
  ;; when protocols follow it, --alpn and them, joined by commas. Each is a
  ;; string with no comma, not empty, and no protocol comes twice, as the
  ;; probe requires. The probe judges no certificate.
  (define wire-probe-tls
    (make-parameter #f
      (lambda (tls)
        (unless (or (not tls)
                    (and (list? tls) (pair? tls)
                         (for-all (lambda (word)
                                    (and (string? word) (positive? (string-length word))
                                         (not (memv #\, (string->list word)))))
                                  tls)
                         (let distinct ((rest (cdr tls)))
                           (or (null? rest) (and (not (member (car rest) (cdr rest))) (distinct (cdr rest)))))))
          (assertion-violation 'wire-probe-tls
                               "not #f, nor a list of SERVERNAME and then ALPN protocols, each a string with no comma, each once"
                               tls))
        tls)))

  ;; tls-options : -> (Listof String)
  ;; The probe's options for wire-probe-tls.
  (define (tls-options)
    (let ((tls (wire-probe-tls)))
      (cond ((not tls) '())
            ((null? (cdr tls)) (list "--tls" (car tls)))
            (else (list "--tls" (car tls) "--alpn"
                        (fold-left (lambda (joined word) (string-append joined "," word))
                                   (cadr tls) (cddr tls)))))))

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
                           (append (list (node-program) probe-script) options (tls-options)
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
           (make-probe-answer (make-bytevector 0) (list 'refused (cadr line)) '() #f (caddr line))))
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
                                     (cadar data)
                                     (if (eq? end 'reset-sent) (cadr line) (caddr line)))))
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

  ;; --- bounded -------------------------------------------------------------

  ;; bounded-script : String
  ;; sh -c BOUNDED-SCRIPT sh COMMAND...: COMMAND, with stdin at its end, under
  ;; GNU timeout (gtimeout on macOS), killed with SIGKILL after 10 s, exit
  ;; 137. timeout waits for COMMAND and exits with it, so nothing it started
  ;; outlives the call: a sleep in a subshell, its first form, did (ppid 1),
  ;; holding the caller's pipes for its 10 s. With neither found, it exits
  ;; 125, saying so on stderr.
  ;;
  ;; The shell's own stderr is not COMMAND's. timeout's KILL reaches timeout
  ;; too, and dash, Debian's sh, then prints "Killed" on the stderr of the
  ;; shell that waited, with that command's own redirections still in force
  ;; (measured in node:20.10.0-bookworm); bash as sh prints nothing. So the
  ;; shell's stderr is /dev/null, timeout runs in a subshell that takes the
  ;; caller's stderr from fd 3 as it execs it, and an exit after it keeps
  ;; dash from execing the subshell in the shell's place, where the shell
  ;; that ran this one would print the message instead.
  (define bounded-script
    (string-append
     "t=$(command -v timeout || command -v gtimeout) || { echo 'bounded: no timeout' >&2; exit 125; }\n"
     "exec 3>&2 2>/dev/null\n"
     "( exec \"$t\" -s KILL 10 \"$@\" </dev/null 2>&3 3>&- )\n"
     "exit $?\n"))

  ;; bounded : String String ... -> (List Integer String String)
  ;; capture-command on PROGRAM and ARGS under bounded-script: the command,
  ;; and all it started, end within 10 s, killed with SIGKILL then, exit
  ;; status 137. So a command that hangs, or an origin that ignores its
  ;; stdin's end, fails by status and does not hang the suite. Nothing it
  ;; started holds a pipe of this process's after it returns.
  (define (bounded program . args)
    (capture-command (append (list "sh" "-c" bounded-script "sh" program) args)))

  ;; --- the TLS material ----------------------------------------------------

  ;; openssl-program : -> String
  ;; OPENSSL from the environment, else openssl, an empty OPENSSL included:
  ;; the checker s-client and certificate-san run, and the program
  ;; tests/make-test-pki.sh runs, which reads OPENSSL alike.
  (define (openssl-program)
    (let ((openssl (getenv "OPENSSL")))
      (if (and openssl (not (string=? openssl ""))) openssl "openssl")))

  ;; test-pki-script : (Parameter String)
  ;; The script make-test-pki runs with sh, from the working directory:
  ;; tests/make-test-pki.sh. A test points it at a stand-in.
  (define test-pki-script
    (make-parameter "tests/make-test-pki.sh"
      (lambda (path)
        (unless (and (string? path) (positive? (string-length path)))
          (assertion-violation 'test-pki-script "not a path" path))
        path)))

  ;; pki-files : (Listof String)
  ;; The ten files tests/make-test-pki.sh makes, sorted.
  (define pki-files
    '("ca.pem" "expired.key" "expired.pem" "good.key" "good.pem" "other-ca.pem"
      "untrusted.key" "untrusted.pem" "wrong-host.key" "wrong-host.pem"))

  ;; make-test-pki : -> String
  ;; A fresh PKI: a process temp directory, into which it runs sh
  ;; (test-pki-script) DIR under bounded. It requires exit status 0, nothing
  ;; on stdout or stderr, and exactly the script's ten files, by name, and
  ;; answers DIR. Otherwise it removes DIR and raises, naming each thing
  ;; wrong, with the script, its exit status, stdout and stderr, and the
  ;; files it left, sorted.
  (define (make-test-pki)
    (let* ((script (test-pki-script))
           (dir (make-process-temp-directory))
           (made (bounded "sh" script dir))
           (files (list-sort string<? (directory-list dir)))
           (wrong (append
                   (if (zero? (car made)) '() (list (string-append "it exited " (number->string (car made)))))
                   (if (string=? (cadr made) "") '() '("it wrote to stdout"))
                   (if (string=? (caddr made) "") '() '("it wrote to stderr"))
                   (if (equal? files pki-files) '() '("it did not leave exactly the ten files")))))
      (if (null? wrong)
          dir
          (begin
            (remove-quietly dir)
            (raise (condition (make-error)
                              (make-who-condition 'make-test-pki)
                              (make-message-condition
                               (string-append "the PKI script did not make the PKI: " (join-with "; " wrong)))
                              (make-irritants-condition
                               (list (cons 'script script) (cons 'status (car made)) (cons 'stdout (cadr made))
                                     (cons 'stderr (caddr made)) (cons 'files files)))))))))

  ;; join-with : String (Listof String) -> String
  (define (join-with separator words)
    (if (null? words)
        ""
        (fold-left (lambda (text word) (string-append text separator word)) (car words) (cdr words))))

  ;; checker-failure : Symbol String (List Integer String String) -> Condition
  ;; The raise for an openssl command that did not exit 0: WHO, MESSAGE, and
  ;; RAN's status, stdout and stderr, as (status . N) (stdout . TEXT)
  ;; (stderr . TEXT).
  (define (checker-failure who message ran)
    (condition (make-error) (make-who-condition who) (make-message-condition message)
               (make-irritants-condition
                (list (cons 'status (car ran)) (cons 'stdout (cadr ran)) (cons 'stderr (caddr ran))))))

  ;; A Peer is what openssl s_client said of a face: the verify errors, in
  ;; order, the final verify code, the protocol ALPN chose, or #f for none,
  ;; and the chain it was served, each certificate as its base64 text.
  (define-record-type (peer make-peer peer?)
    (fields (immutable verify-errors peer-verify-errors)
            (immutable verify-code peer-verify-code)
            (immutable alpn peer-alpn)
            (immutable chain peer-chain)))

  ;; peer-verify-errors : Peer -> (Listof Natural)
  ;; peer-verify-code : Peer -> Natural
  ;; peer-alpn : Peer -> (U String #f)
  ;; peer-chain : Peer -> (Pair String (Listof String))
  ;;   every certificate the face served, in order, the leaf first: -showcerts
  ;;   prints each, and no other.

  ;; peer-leaf : Peer -> String
  ;; The leaf the face served: its chain's first certificate.
  (define (peer-leaf p)
    (unless (peer? p)
      (assertion-violation 'peer-leaf "not a Peer" p))
    (car (peer-chain p)))

  ;; s-client : Origin Symbol (U String #f) String (U String #f) -> Peer
  ;; Runs, under bounded, with stdin an empty pipe, at its end, so that it
  ;; closes once connected:
  ;;   $OPENSSL s_client -connect ADDRESS:PORT [-servername SERVERNAME]
  ;;     -CAfile CA -showcerts [-alpn ALPN]
  ;; against ORIGIN's face FACE, -servername only when SERVERNAME is a
  ;; string, -alpn only when ALPN is. With no -servername, to an IP address,
  ;; s_client sends no SNI, as libcurl does to an IP URL: OpenSSL 3.5.7 and
  ;; 3.0.11 and LibreSSL 3.3.6 all sent none, by a face's log. It
  ;; requires exit status 0, and answers parse-s-client of its stdout and
  ;; stderr. Otherwise it raises, with the status, stdout and stderr. It
  ;; asks for no hostname check: LibreSSL 3.3.6 has none (ADR-0005, amended).
  ;; Stdin's end does not stop OpenSSL 3 reading the server's TLS 1.3
  ;; session tickets first: by timing, it sometimes prints a block for each,
  ;; with a Verify return code of its own, which parse-s-client reads.
  ;; The pipe is no /dev/null: LibreSSL 3.3.6's s_client polls stdin with
  ;; poll(2), and macOS's poll does not support devices. There, with stdin at
  ;; /dev/null, it printed "poll error" and exited 1 once connected; with an
  ;; empty pipe, DONE and 0 (measured on the maintainer's Mac, 2026-10-23).
  (define (s-client origin face servername ca alpn)
    (let ((address (origin-face origin face)))
      (unless (or (not servername) (and (string? servername) (positive? (string-length servername))))
        (assertion-violation 's-client "the server name is not #f nor a string" servername))
      (unless (and (string? ca) (positive? (string-length ca)))
        (assertion-violation 's-client "the CA file is not a path" ca))
      (unless (or (not alpn) (and (string? alpn) (positive? (string-length alpn))))
        (assertion-violation 's-client "the ALPN list is not #f nor a string" alpn))
      (let ((ran (apply bounded "sh" "-c" ": | exec \"$0\" \"$@\"" (openssl-program) "s_client"
                        "-connect" (string-append (car address) ":" (number->string (cdr address)))
                        (append (if servername (list "-servername" servername) '())
                                (list "-CAfile" ca "-showcerts")
                                (if alpn (list "-alpn" alpn) '())))))
        (unless (zero? (car ran))
          (raise (checker-failure 's-client "openssl s_client did not exit 0" ran)))
        (parse-s-client (cadr ran) (caddr ran)))))

  ;; parse-s-client : String String -> Peer
  ;; openssl s_client's STDOUT and STDERR as a Peer, read as OpenSSL 3 and
  ;; LibreSSL 3.3.6 write them (measured on 3.5.7, 3.0.13, 3.0.11 and
  ;; 3.3.6):
  ;;   - peer-verify-errors: N of each stderr line verify error:num=N:TEXT,
  ;;     in order;
  ;;   - peer-verify-code: N of stdout's first line Verify return code: N
  ;;     (TEXT), the handshake's, which LibreSSL indents with spaces;
  ;;   - peer-alpn: X of stdout's one line ALPN protocol: X, or #f for its
  ;;     one line No ALPN negotiated: one of the two, once;
  ;;   - peer-chain: the base64 text of each of stdout's blocks from
  ;;     -----BEGIN CERTIFICATE----- to -----END CERTIFICATE-----, in order,
  ;;     each block's lines joined; peer-leaf is the first.
  ;; A later Verify return code line is a TLS 1.3 session ticket's. OpenSSL
  ;; 3 prints a block for each ticket it reads before stdin's end, which it
  ;; does or not by timing: a line Post-Handshake New Session Ticket
  ;; arrived:, then the session, its code indented. Node sends two. Their
  ;; codes are the handshake's (measured on every TLS face). LibreSSL prints
  ;; none. So each later code line must have a ticket line of its own after
  ;; the code line before it, and the same N, and every ticket line a code
  ;; line after it. A ticket's block can follow bytes of the server's that
  ;; s_client copied to stdout, binary ones on h2, but those end up on the
  ;; --- line s_client writes before the ticket line, which stays whole.
  ;; It raises, naming the rule, with the line or text at fault, on a
  ;; malformed verify error or Verify return code line; no Verify return
  ;; code line; a later one with no ticket line of its own, or another N; a
  ;; ticket line before the handshake's code line, one with no code line
  ;; after it, or two before one code line; no ALPN line or more than one;
  ;; and no certificate block, or any empty or not closed. Every other line
  ;; is ignored.
  (define (parse-s-client stdout stderr)
    (unless (string? stdout)
      (assertion-violation 'parse-s-client "stdout is not a string" stdout))
    (unless (string? stderr)
      (assertion-violation 'parse-s-client "stderr is not a string" stderr))
    (let ((out (text-lines stdout))
          (err (text-lines stderr)))
      (define (refuse message . irritants) (apply error 'parse-s-client message irritants))
      ;; handshake-code : -> Natural
      ;; The first code line's N, once every later one is held to its ticket.
      (define (handshake-code)
        (let loop ((rest out) (code #f) (ticket #f))
          (cond
            ((null? rest)
             (cond ((not code) (refuse "stdout has no Verify return code line" stdout))
                   (ticket (refuse "a Post-Handshake New Session Ticket arrived: line has no Verify return code line after it"
                                   ticket))
                   (else code)))
            ((string=? (car rest) ticket-line)
             (cond ((not code)
                    (refuse "a Post-Handshake New Session Ticket arrived: line comes before the handshake's Verify return code line"
                            (car rest)))
                   (ticket
                    (refuse "two Post-Handshake New Session Ticket arrived: lines come before one Verify return code line"
                            (car rest)))
                   (else (loop (cdr rest) code (car rest)))))
            ((prefix? "Verify return code:" (trim-left (car rest)))
             (let ((n (verify-code-number (trim-left (car rest)))))
               (cond ((not n) (refuse "a Verify return code line is Verify return code: N (TEXT)" (car rest)))
                     ((not code) (loop (cdr rest) n #f))
                     ((not ticket)
                      (refuse "a Verify return code line after the handshake's has no Post-Handshake New Session Ticket arrived: line of its own before it"
                              (car rest)))
                     ((not (= n code))
                      (refuse "a ticket's Verify return code is not the handshake's" code (car rest)))
                     (else (loop (cdr rest) code #f)))))
            (else (loop (cdr rest) code ticket)))))
      (let* ((errors
              (map (lambda (line)
                     (or (verify-error-number line)
                         (refuse "a verify error line is verify error:num=N:TEXT" line)))
                   (filter (lambda (line) (prefix? "verify error:num=" line)) err)))
             (code (handshake-code))
             (alpn-lines (filter (lambda (line)
                                   (or (prefix? "ALPN protocol:" line) (string=? line "No ALPN negotiated")))
                                 out)))
        (cond ((null? alpn-lines) (refuse "stdout has no ALPN protocol or No ALPN negotiated line" stdout))
              ((pair? (cdr alpn-lines))
               (refuse "stdout has more than one ALPN protocol or No ALPN negotiated line" alpn-lines)))
        (let ((alpn (alpn-protocol (car alpn-lines))))
          (unless alpn
            (refuse "an ALPN line is ALPN protocol: X, or No ALPN negotiated" (car alpn-lines)))
          (make-peer errors code (and (string? alpn) alpn) (certificate-blocks 'parse-s-client stdout))))))

  ;; ticket-line : String
  ;; The line OpenSSL 3's s_client writes before each TLS 1.3 session
  ;; ticket's block.
  (define ticket-line "Post-Handshake New Session Ticket arrived:")

  ;; verify-error-number : String -> (U Natural #f)
  ;; N of verify error:num=N:TEXT.
  (define (verify-error-number line)
    (let* ((rest (substring line 17 (string-length line)))
           (n (digits-before #\: rest)))
      (and n (car n))))

  ;; verify-code-number : String -> (U Natural #f)
  ;; N of Verify return code: N (TEXT).
  (define (verify-code-number line)
    (and (prefix? "Verify return code: " line)
         (let* ((rest (substring line 20 (string-length line)))
                (n (digits-before #\space rest)))
           (and n
                (let ((after (cdr n)))
                  (and (>= (string-length after) 2)
                       (char=? (string-ref after 0) #\()
                       (char=? (string-ref after (- (string-length after) 1)) #\))
                       (car n)))))))

  ;; alpn-protocol : String -> (U String 'none #f)
  ;; X of ALPN protocol: X, X not empty; none for No ALPN negotiated.
  (define (alpn-protocol line)
    (cond ((string=? line "No ALPN negotiated") 'none)
          ((and (prefix? "ALPN protocol: " line) (> (string-length line) 15))
           (substring line 15 (string-length line)))
          (else #f)))

  ;; digits-before : Char String -> (U (Pair Natural String) #f)
  ;; The natural TEXT starts with, written in one or more digits, and what
  ;; follows the character STOP right after them; #f when TEXT does not start
  ;; so.
  (define (digits-before stop text)
    (let loop ((i 0))
      (cond ((and (< i (string-length text)) (char<=? #\0 (string-ref text i) #\9)) (loop (+ i 1)))
            ((and (> i 0) (< i (string-length text)) (char=? (string-ref text i) stop))
             (cons (string->number (substring text 0 i)) (substring text (+ i 1) (string-length text))))
            (else #f))))

  ;; run-x509 : Symbol String -> (List Integer String String)
  ;; $OPENSSL x509 -in FILE -noout -text under bounded, its status 0, or WHO
  ;; raises with the status, stdout and stderr.
  (define (run-x509 who file)
    (unless (and (string? file) (positive? (string-length file)))
      (assertion-violation who "not a path" file))
    (let ((ran (bounded (openssl-program) "x509" "-in" file "-noout" "-text")))
      (unless (zero? (car ran))
        (raise (checker-failure who "openssl x509 did not exit 0" ran)))
      ran))

  ;; certificate-text : String -> (Listof String)
  ;; What $OPENSSL x509 -in FILE -noout -text writes, run under bounded, as
  ;; its lines, each trimmed of spaces and tabs at both ends. OpenSSL 3 and
  ;; LibreSSL 3.3.6 indent the text differently, and agree on the trimmed
  ;; lines the checks read: Signature Algorithm, Public-Key, ASN1 OID, Not
  ;; Before and Not After (measured on 3.5.7, 3.0.11 and 3.3.6). They differ
  ;; on Subject and Issuer, CN=x or CN = x, which no check reads. It raises,
  ;; with the status, stdout and stderr, when the status is not 0.
  (define (certificate-text file)
    (map trim (text-lines (cadr (run-x509 'certificate-text file)))))

  ;; certificate-values : (Listof String) String -> (Listof String)
  ;; For each of LINES that starts with LABEL, what follows LABEL, trimmed,
  ;; in order: "Signature Algorithm:" gives two, the copy inside the signed
  ;; part and the copy outside it, of the one signature the issuer made.
  ;; LABEL is matched whole, its spacing included: x509 writes "Not After :".
  (define (certificate-values lines label)
    (unless (and (list? lines) (for-all string? lines))
      (assertion-violation 'certificate-values "not a list of lines" lines))
    (unless (and (string? label) (positive? (string-length label)))
      (assertion-violation 'certificate-values "not a label" label))
    (map (lambda (line) (trim (substring line (string-length label) (string-length line))))
         (filter (lambda (line) (prefix? label line)) lines)))

  ;; certificate-names : (Listof String) String -> (Listof String)
  ;; certificate-values for LABEL, "Subject:" or "Issuer:" alone, each value
  ;; with every " = " written "=": OpenSSL 3.0 writes CN = x there, and 3.5
  ;; and LibreSSL 3.3.6 write CN=x (measured on 3.0.11, 3.5.7 and 3.3.6). It
  ;; folds nothing else, and refuses any other label: no other line differs
  ;; that way.
  (define (certificate-names lines label)
    (unless (member label '("Subject:" "Issuer:"))
      (assertion-violation 'certificate-names "a name's label is Subject: or Issuer:" label))
    (map (lambda (value)
           (let loop ((i 0) (acc '()))
             (cond ((>= i (string-length value)) (list->string (reverse acc)))
                   ((and (<= (+ i 3) (string-length value)) (string=? (substring value i (+ i 3)) " = "))
                    (loop (+ i 3) (cons #\= acc)))
                   (else (loop (+ i 1) (cons (string-ref value i) acc))))))
         (certificate-values lines label)))

  ;; certificate-time : String -> Integer
  ;; A date as x509 -text writes one, MMM DD HH:MM:SS YYYY GMT, its day
  ;; padded with a space to two places ("Jan  1 00:00:00 2000 GMT"), as
  ;; seconds since 1970-01-01 00:00:00 UTC. It raises on any other text: a
  ;; day not padded, or not in its month, a zone other than GMT, a field out
  ;; of range.
  (define (certificate-time text)
    (define (refuse) (assertion-violation 'certificate-time "not a date as x509 -text writes one" text))
    (unless (and (string? text) (= (string-length text) 24)) (refuse))
    (let* ((field (lambda (from to) (substring text from to)))
           (number (lambda (from to)
                     (let ((digits (field from to)))
                       (if (for-all (lambda (c) (char<=? #\0 c #\9)) (string->list digits))
                           (string->number digits)
                           (refuse)))))
           (months '("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))
           (month (let ((m (member (field 0 3) months))) (if m (- 13 (length m)) (refuse))))
           (day (if (char=? (string-ref text 4) #\space) (number 5 6) (number 4 6))))
      (unless (and (char=? (string-ref text 3) #\space) (char=? (string-ref text 6) #\space)
                   (char=? (string-ref text 9) #\:) (char=? (string-ref text 12) #\:)
                   (char=? (string-ref text 15) #\space) (char=? (string-ref text 20) #\space)
                   (string=? (field 21 24) "GMT")
                   (not (char=? (string-ref text 4) #\0)))
        (refuse))
      (let ((hour (number 7 9)) (minute (number 10 12)) (second (number 13 15)) (year (number 16 20)))
        (unless (and (<= 1 day (days-in-month year month)) (<= hour 23) (<= minute 59) (<= second 59))
          (refuse))
        (+ (* 86400 (days-from-civil year month day)) (* 3600 hour) (* 60 minute) second))))

  ;; days-in-month : Integer Integer -> Integer
  (define (days-in-month year month)
    (case month
      ((4 6 9 11) 30)
      ((2) (if (and (zero? (mod year 4)) (or (not (zero? (mod year 100))) (zero? (mod year 400)))) 29 28))
      (else 31)))

  ;; days-from-civil : Integer Integer Integer -> Integer
  ;; The days from 1970-01-01 to YEAR-MONTH-DAY in the proleptic Gregorian
  ;; calendar: Howard Hinnant's days_from_civil.
  (define (days-from-civil year month day)
    (let* ((y (if (<= month 2) (- year 1) year))
           (era (div y 400))
           (yoe (- y (* era 400)))
           (doy (+ (div (+ (* 153 (+ month (if (> month 2) -3 9))) 2) 5) (- day 1)))
           (doe (+ (* yoe 365) (div yoe 4) (- (div yoe 100)) doy)))
      (+ (* era 146097) doe -719468)))

  ;; certificate-san : String -> String
  ;; The subjectAltName of the certificate in FILE: the line after X509v3
  ;; Subject Alternative Name: in certificate-text's lines. OpenSSL 3 and
  ;; LibreSSL 3.3.6 write it alike, the heading with a space after its colon
  ;; (measured). It raises, with the status, stdout and stderr, when the
  ;; status is not 0, and when that heading is missing, there more than once,
  ;; or the last line.
  (define (certificate-san file)
    (let* ((ran (run-x509 'certificate-san file))
           (fail (lambda (message) (raise (checker-failure 'certificate-san message ran)))))
      (let loop ((lines (map trim (text-lines (cadr ran)))) (found #f))
        (cond ((null? lines)
               (or found (fail "openssl x509 wrote no X509v3 Subject Alternative Name: heading")))
              ((prefix? "X509v3 Subject Alternative Name:" (car lines))
               (cond (found (fail "openssl x509 wrote the X509v3 Subject Alternative Name: heading more than once"))
                     ((null? (cdr lines)) (fail "openssl x509 wrote no line after the X509v3 Subject Alternative Name: heading"))
                     (else (loop (cddr lines) (cadr lines)))))
              (else (loop (cdr lines) found))))))

  ;; pem-certificate : String -> String
  ;; The first certificate in the PEM file FILE, as its base64 text, its
  ;; lines joined, read in Scheme: what s-client's peer-leaf is for a face
  ;; that serves it. It raises when FILE holds no certificate block, or one
  ;; is empty or not closed.
  (define (pem-certificate file)
    (unless (and (string? file) (positive? (string-length file)))
      (assertion-violation 'pem-certificate "not a path" file))
    (car (certificate-blocks 'pem-certificate
                             (latin-1 (call-with-port (open-file-input-port file)
                                        (lambda (p)
                                          (let ((bytes (get-bytevector-all p)))
                                            (if (eof-object? bytes) (make-bytevector 0) bytes))))))))

  ;; certificate-blocks : Symbol String -> (Pair String (Listof String))
  ;; The base64 text of every block in TEXT from a line
  ;; -----BEGIN CERTIFICATE----- to a line -----END CERTIFICATE-----, in
  ;; order, each block's lines joined. WHO raises, with TEXT, when there is
  ;; none, or one is empty or not closed.
  (define (certificate-blocks who text)
    (let find ((rest (text-lines text)) (blocks '()))
      (cond ((null? rest)
             (if (null? blocks)
                 (error who "no -----BEGIN CERTIFICATE----- line" text)
                 (reverse blocks)))
            ((string=? (car rest) "-----BEGIN CERTIFICATE-----")
             (let collect ((rest (cdr rest)) (pieces '()))
               (cond ((null? rest) (error who "a certificate has no -----END CERTIFICATE----- line" text))
                     ((string=? (car rest) "-----END CERTIFICATE-----")
                      (if (null? pieces)
                          (error who "a certificate is empty" text)
                          (find (cdr rest) (cons (apply string-append (reverse pieces)) blocks))))
                     (else (collect (cdr rest) (cons (car rest) pieces))))))
            (else (find (cdr rest) blocks)))))

  ;; text-lines : String -> (Listof String)
  ;; TEXT's lines, each without its newline. A last line with no newline is
  ;; a line; the empty text has none.
  (define (text-lines text)
    (let loop ((chars (string->list text)) (line '()) (lines '()))
      (cond ((null? chars)
             (reverse (if (null? line) lines (cons (list->string (reverse line)) lines))))
            ((char=? (car chars) #\newline)
             (loop (cdr chars) '() (cons (list->string (reverse line)) lines)))
            (else (loop (cdr chars) (cons (car chars) line) lines)))))

  ;; prefix? : String String -> Boolean
  (define (prefix? start s)
    (and (<= (string-length start) (string-length s))
         (string=? start (substring s 0 (string-length start)))))

  ;; trim-left, trim : String -> String
  ;; S without its leading spaces, or its leading and trailing spaces and
  ;; tabs.
  (define (blank? c) (memv c '(#\space #\tab)))
  (define (trim-left s)
    (let loop ((i 0))
      (if (and (< i (string-length s)) (blank? (string-ref s i))) (loop (+ i 1)) (substring s i (string-length s)))))
  (define (trim s)
    (let* ((t (trim-left s))
           (end (let loop ((end (string-length t)))
                  (if (and (> end 0) (blank? (string-ref t (- end 1)))) (loop (- end 1)) end))))
      (substring t 0 end)))

  ;; read-all : String -> (Listof Any)
  ;; Every datum in TEXT. It raises on text that is not Scheme data.
  (define (read-all text)
    (let ((port (open-string-input-port text)))
      (let loop ((found '()))
        (let ((datum (get-datum port)))
          (if (eof-object? datum)
              (reverse found)
              (loop (cons datum found))))))))
