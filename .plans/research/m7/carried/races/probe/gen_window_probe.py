#!/usr/bin/env python3
"""gen_window_probe.py SRC DEST: an instrumented copy of tests/mailbox-escape.sps,
a measurement copy, not a test: with MAILBOX_PROBE_LOG set, it appends
(window WAIT READY-TO-CALL-MS) to that file, the milliseconds from just before
its ready line to just before it calls WAIT, the take or the delivery that the
suite's SIGINT, 500 ms after the ready line is read, must find blocked. Its
output is unchanged."""
import sys

src, dest = sys.argv[1], sys.argv[2]
s = open(src).read()


def once(old, new):
    global s
    if s.count(old) != 1:
        sys.exit(f"gen_window_probe: {old[:60]!r} occurs {s.count(old)} times")
    s = s.replace(old, new)


once("(define returned #f)\n", """(define returned #f)
(define (probe-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (/ (time-nanosecond t) 1000000))))
(define probe-ready #f)
(define probe-call #f)
""")
once("     (write (list 'ready (get-process-id)))", "     (set! probe-ready (probe-ms))\n     (write (list 'ready (get-process-id)))")
once("     (let ((t (if (eq? wait-name 'take)", "     (set! probe-call (probe-ms))\n     (let ((t (if (eq? wait-name 'take)")
once("(write (list 'counts (native-counts)))", """(let ((log (getenv "MAILBOX_PROBE_LOG")))
  (when (and log probe-ready probe-call)
    (let ((p (open-file-output-port log (file-options no-fail no-truncate append) (buffer-mode block) (native-transcoder))))
      (write (list 'window wait-name (inexact (- probe-call probe-ready))) p)
      (newline p)
      (close-port p))))
(write (list 'counts (native-counts)))""")
open(dest, 'w').write(s)
print(f"gen_window_probe: wrote {dest}")
