#!/usr/bin/env python3
"""gen_upload_loop.py SRC DEST K: test-upload.sps with its body-asked test run
K times in a row, at its place in the suite, each row printing a
PROBE-UPLOAD line (as gen_upload_probe.py's) with the iteration. For the
fixed suite, whose h2-answer row holds its answer, each iteration's hold
key is its own: a release holds for good. A measurement copy, not a test."""
import sys

src, dest, k = sys.argv[1], sys.argv[2], int(sys.argv[3])
s = open(src).read()


def once(text, old, new):
    n = text.count(old)
    if n != 1:
        sys.exit(f"gen_upload_loop: {old[:80]!r} occurs {n} times, not 1")
    return text.replace(old, new)


start = s.index('  (test-equal "the head\'s body-asked bit: #t for a streamed body')
end = s.index("  ;; --- the body-asked bit with the answer first", start)
seg = s[start:end]
fixed = 'hold=asked-h2-answer' in seg
seg = once(seg, "                      (t (curl-submit own (case body",
           "                      (submit-at (let ((x (current-time 'time-monotonic)))\n"
           "                                   (+ (* (time-second x) 1000000000) (time-nanosecond x))))\n"
           "                      (t (curl-submit own (case body")
probe = ("                 (let ((line (guard (e (#t (list name 'bit asked 'unread)))\n"
         "                               (if (eq? body 'stream)\n"
         "                                   (list name 'bit asked 'asked (ustat t 'asked) 'asked-at (ustat t 'asked-at)\n"
         "                                         'head-at (cdr (assq 'head-at (curl-token-stream-stats t)))\n"
         "                                         'submit-at submit-at 'reads (ustat t 'reads) 'outcome (outcome-of t)\n"
         "                                         'iteration iteration)\n"
         "                                   (list name 'bit asked 'not-streamed)))))\n"
         "                   (display \"PROBE-UPLOAD \")\n"
         "                   (write line)\n"
         "                   (newline))\n"
         "                 (flush-output-port (current-output-port))\n")
if fixed:
    seg = once(seg, "                 (cond ((eq? name 'raw-answer)\n", probe + "                 (cond ((eq? name 'raw-answer)\n")
    seg = once(seg, """           (h2-answer h2 "/answer?status=200&hold=asked-h2-answer" stream #f)""",
               """           (h2-answer h2 ,(string-append "/answer?status=200&hold=asked-h2-answer-" (number->string iteration)) stream #f)""")
    seg = once(seg, """(url-of o 'raw "/raw/release?key=asked-h2-answer")""",
               """(url-of o 'raw (string-append "/raw/release?key=asked-h2-answer-" (number->string iteration)))""")
else:
    seg = once(seg, "                 (if (eq? name 'raw-answer)\n", probe + "                 (if (eq? name 'raw-answer)\n")
seg = once(seg, "         '((raw-answer raw", "         `((raw-answer raw")
loop = (f"  (let iterate ((iteration 0))\n    (when (< iteration {k})\n" + seg.rstrip('\n') +
         "\n      (iterate (+ iteration 1))))\n\n")
s = s[:start] + loop + s[end:]
open(dest, 'w').write(s)
print('gen_upload_loop: wrote', dest, 'fixed' if fixed else 'unfixed', k)
