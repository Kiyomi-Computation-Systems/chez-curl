#!/usr/bin/env python3
"""gen_children.py TESTS OUT: measurement copies of the SIGINT children of
test-http-client (escape-child, raise-child, quoted in the suite), of
test-mailbox (tests/mailbox-escape.sps) and of test-engine
(tests/engine-interrupt.sps), from the tests directory TESTS, into OUT:
hc-escape.sps, hc-raise.sps, mailbox-escape.sps, engine-interrupt.sps.

A measurement copy, not a test. Each child keeps its program and its
output, and adds, by the environment:
  CHILD_TRIP=N         (collect-trip-bytes N) in the main thread just before
                       it prints its ready line: a collection request once N
                       bytes more are allocated, inside the hold (the races
                       README's GROUP_TRIP).
  CHILD_TRIP_AFTER=N   the same, set by the holder once its hold has ended,
                       outside every critical section: a control, a
                       collection that cannot land in the hold.
and prints one more line before its counts, (probe NAME HELD HANDLER
FRAMES): (collections) as the hold started, as the Ctrl-C handler started,
and as the hold ended (#f when none), and the names of the handler's
continuation's first 24 frames: where the handler ran (the races README's
walk).

When a child already carries child-hold's forms (a fixed tree), its own
(collections) reads are left as they are and this copy adds its own.
"""
import os
import sys

tests, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)


def once(text, old, new, name):
    n = text.count(old)
    if n != 1:
        sys.exit(f"gen_children: {name}: {old[:70]!r} occurs {n} times, not once")
    return text.replace(old, new)


def quoted_forms(src, name):
    """The forms of (define NAME '(FORM ...)) or (define NAME `(FORM ...)) in SRC, as text."""
    for head in (f"(define {name}\n  '(", f"(define {name}\n  `("):
        at = src.find(head)
        if at >= 0:
            break
    else:
        sys.exit(f"gen_children: no (define {name} '(...)) in the suite")
    i = at + len(head)
    start = i
    depth = 1
    while depth:
        c = src[i]
        if c == '"':
            i += 1
            while src[i] != '"':
                i += 2 if src[i] == '\\' else 1
        elif c == ';':
            while src[i] != '\n':
                i += 1
        elif c == '#' and src[i + 1] == '\\':
            i += 2
        elif c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
        i += 1
    return src[start:i - 1]


TRIP = ('(let ((trip (getenv "CHILD_TRIP"))) (when trip (collect-trip-bytes (string->number trip))))')
TRIP_AFTER = ('(let ((trip (getenv "CHILD_TRIP_AFTER"))) (when trip (collect-trip-bytes (string->number trip))))')
PROBE_DEFS = """(define probe-held #f)
    (define probe-handler #f)
    (define probe-released #f)
    (define probe-extra '())
    (define (probe-frames k n)
      (let loop ((i (inspect/object k)) (n n) (acc '()))
        (if (or (= n 0) (not (eq? (i 'type) 'continuation)))
            (reverse acc)
            (loop (i 'link) (- n 1) (cons (let ((c (i 'code))) (and c (c 'name))) acc)))))
    (define (probe-at-handler!)
      (set! probe-handler (collections))
      (call/cc (lambda (k) (set! probe-extra (probe-frames k 24)))))
    """

suite = open(f"{tests}/test-http-client.sps").read()
for name, child in (('hc-escape', 'escape-child'), ('hc-raise', 'raise-child')):
    s = quoted_forms(suite, child)
    s = once(s, "    (define url (car (command-line-arguments)))\n",
             "    (define url (car (command-line-arguments)))\n    " + PROBE_DEFS, name)
    s = once(s, "(critical-section (with-mutex lock (set! holding #t)))",
             "(set! probe-held (collections)) (critical-section (with-mutex lock (set! holding #t)))", name)
    s = once(s, "(critical-section (with-mutex lock (set! letting-go #t)))))",
             "(critical-section (with-mutex lock (set! letting-go #t)))))\n"
             f"       (set! probe-released (collections))\n       {TRIP_AFTER}", name)
    s = once(s, "(set! when-", "(probe-at-handler!) (set! when-", name)
    s = once(s, "(write (list 'ready (get-process-id)))",
             f"{TRIP} (write (list 'ready (get-process-id)))", name)
    s = once(s, "    (write (list 'counts (native-counts)))",
             f"    (write (list 'probe '{name} probe-held probe-handler probe-released probe-extra))\n    (newline)\n"
             "    (write (list 'counts (native-counts)))", name)
    open(f"{out}/{name}.sps", "w").write(s + "\n")

m = open(f"{tests}/mailbox-escape.sps").read()
m = once(m, "(define lock (make-mutex))\n", "(define lock (make-mutex))\n" + PROBE_DEFS.replace("    ", ""), 'mailbox')
m = once(m, "       (with-mutex lock (set! holding #t))",
         "       (set! probe-held (collections))\n       (with-mutex lock (set! holding #t))", 'mailbox')
m = once(m, "   (critical-section (with-mutex lock (set! released #t)))))",
         f"   (set! probe-released (collections))\n   {TRIP_AFTER}\n   (critical-section (with-mutex lock (set! released #t)))))", 'mailbox')
m = once(m, "(keyboard-interrupt-handler (lambda () (out 'escaped)))",
         "(keyboard-interrupt-handler (lambda () (probe-at-handler!) (out 'escaped)))", 'mailbox')
m = once(m, "     (write (list 'ready (get-process-id)))", f"     {TRIP}\n     (write (list 'ready (get-process-id)))", 'mailbox')
m = once(m, "(write (list 'counts (native-counts)))",
         "(write (list 'probe 'mailbox probe-held probe-handler probe-released probe-extra))\n(newline)\n"
         "(write (list 'counts (native-counts)))", 'mailbox')
open(f"{out}/mailbox-escape.sps", "w").write(m)

e = open(f"{tests}/engine-interrupt.sps").read()
e = once(e, "(define handled #f)\n", "(define handled #f)\n" + PROBE_DEFS.replace("    ", ""), 'engine')
e = once(e, "(keyboard-interrupt-handler (lambda () (unless handled (set! handled (- (now-ms) t0)))))",
         "(keyboard-interrupt-handler (lambda () (unless handled (probe-at-handler!) (set! handled (- (now-ms) t0)))))", 'engine')
e = once(e, "(write (list 'ready (get-process-id)))", f"(set! probe-held (collections))\n{TRIP}\n(write (list 'ready (get-process-id)))", 'engine')
e = once(e, "(write (list 'counts (native-counts)))",
         "(write (list 'probe 'engine probe-held probe-handler probe-released probe-extra))\n(newline)\n"
         "(write (list 'counts (native-counts)))", 'engine')
open(f"{out}/engine-interrupt.sps", "w").write(e)
print(f"gen_children: wrote {out}/hc-escape.sps hc-raise.sps mailbox-escape.sps engine-interrupt.sps")
