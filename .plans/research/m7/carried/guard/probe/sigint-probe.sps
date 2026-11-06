;;; sigint-probe.sps [ENTRY ...]: runs probe/sigint-child.sps for every
;;; ENTRY (request port go parallel by default), WHERE (enter parse) and
;;; ACTION (raise-cond cont-cond raise-false cont-sym), each in a child of
;;; its own under the script below, against the origin's http face, a fast
;;; 200; prints each child's exit status and lines. Run from a copy's root,
;;; with src:tests:build/scheme-libs as the library path; the child is
;;; CHILD, probe/sigint-child.sps under the copy unless set.
(import (chezscheme) (curl-testing))

;; As test-group's interrupt-script: SIGINT 500 ms after (ready PID), then
;; the sent file, then the child's exit status and output.
(define interrupt-script
  (string-append
   "t=$(command -v timeout || command -v gtimeout) || { echo 'guard child: no timeout' >&2; exit 125; }\n"
   "out=$(mktemp \"${TMPDIR:-/tmp}/guard-child.XXXXXX\") || exit 125\n"
   "GUARD_CHILD_SENT=\"$out.sent\" \"$t\" -s KILL 60 \"$@\" >\"$out\" 2>&1 </dev/null &\n"
   "waiter=$!\n"
   "n=0\n"
   "until grep -q '^(ready ' \"$out\" || [ \"$n\" -ge 400 ]; do sleep 0.05; n=$((n + 1)); done\n"
   "pid=$(sed -n 's/^(ready \\([0-9]*\\))$/\\1/p' \"$out\")\n"
   "if [ -z \"$pid\" ]; then kill \"$waiter\"; wait \"$waiter\"; cat \"$out\" >&2; rm -f \"$out\"; echo 'guard child: never ready' >&2; exit 126; fi\n"
   "sleep 0.5\n"
   "kill -INT \"$pid\"\n"
   ": >\"$out.sent\"\n"
   "wait \"$waiter\"\n"
   "status=$?\n"
   "grep -v '^(ready ' \"$out\"\n"
   "rm -f \"$out\" \"$out.sent\"\n"
   "exit $status\n"))

(define child (or (getenv "CHILD") "probe/sigint-child.sps"))
(define entries
  (if (null? (command-line-arguments))
      '(request port go parallel)
      (map string->symbol (command-line-arguments))))

(call-with-origin
 (lambda (o)
   (let* ((f (origin-face o 'http))
          (url (string-append "http://" (car f) ":" (number->string (cdr f)) "/status/200")))
     (for-each
      (lambda (entry)
        (for-each
         (lambda (where)
           (for-each
            (lambda (action)
              (let ((r (capture-command (list "sh" "-c" interrupt-script "sh" (getenv "CHEZ")
                                              "--libdirs" "src:tests:build/scheme-libs"
                                              "--program" child url
                                              (symbol->string entry) (symbol->string where)
                                              (symbol->string action)))))
                (display (list 'child entry where action 'exit (car r)))
                (newline)
                (display (cadr r))
                (unless (string=? (caddr r) "")
                  (display "stderr: ")
                  (display (caddr r))
                  (newline))
                (flush-output-port (current-output-port))))
            '(raise-cond cont-cond raise-false cont-sym)))
         '(enter parse)))
      entries))))
