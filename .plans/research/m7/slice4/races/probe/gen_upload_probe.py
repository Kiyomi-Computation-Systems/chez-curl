#!/usr/bin/env python3
"""gen_upload_probe.py SRC DEST: an instrumented copy of tests/test-upload.sps.

A measurement copy, not a test: the body-asked test's rows each print a
PROBE-UPLOAD line, (NAME bit BIT asked ASKED asked-at NS head-at NS
submit-at NS reads READS outcome OUTCOME), ASKED and asked-at read once the
transfer has ended (libcurl's first ask, or #f with none), head-at the
head's publication, each a monotonic time in ns as the engine reads it.
The test itself is unchanged.
"""
import sys

src, dest = sys.argv[1], sys.argv[2]
s = open(src).read()


def once(text, old, new):
    n = text.count(old)
    if n != 1:
        sys.exit(f"gen_upload_probe: {old!r} occurs {n} times, not 1")
    return text.replace(old, new)


start = s.index('(test-equal "the head\'s body-asked bit: #t for a streamed body')
end = s.index(";; --- the body-asked bit with the answer first", start)
seg = s[start:end]
seg = once(seg, "                      (t (curl-submit own (case body",
           "                      (submit-at (let ((x (current-time 'time-monotonic)))\n"
           "                                   (+ (* (time-second x) 1000000000) (time-nanosecond x))))\n"
           "                      (t (curl-submit own (case body")
seg = once(seg, "                 (if (eq? name 'raw-answer)\n",
           "                 (let ((line (guard (e (#t (list name 'bit asked 'unread)))\n"
           "                               (if (eq? body 'stream)\n"
           "                                   (list name 'bit asked 'asked (ustat t 'asked) 'asked-at (ustat t 'asked-at)\n"
           "                                         'head-at (cdr (assq 'head-at (curl-token-stream-stats t)))\n"
           "                                         'submit-at submit-at 'reads (ustat t 'reads) 'outcome (outcome-of t))\n"
           "                                   (list name 'bit asked 'not-streamed)))))\n"
           "                   (display \"PROBE-UPLOAD \")\n"
           "                   (write line)\n"
           "                   (newline))\n"
           "                 (flush-output-port (current-output-port))\n"
           "                 (if (eq? name 'raw-answer)\n")
s = s[:start] + seg + s[end:]
open(dest, 'w').write(s)
print(f"gen_upload_probe: wrote {dest}")
