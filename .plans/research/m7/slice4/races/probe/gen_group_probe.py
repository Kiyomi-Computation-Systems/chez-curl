#!/usr/bin/env python3
"""gen_group_probe.py SRC DEST: an instrumented copy of tests/test-group.sps.

A measurement copy, not a test: every SIGINT child gets the sigprobe.so
prelude (SIGPROBE names it), notes at its hold, its ready line, its
handler (with the handler's continuation, walked to frame names when the
child prints), and around the call the SIGINT is meant to land in; the
interrupt script reports when it saw ready and when it sent the SIGINT
(CLOCK_REALTIME ns, date +%s%N, taken after the kill); run-child prints
each child's probe data as a PROBE line on the suite's stdout and hands
the tests what they had before, so every test is unchanged.
"""
import re
import sys

src, dest = sys.argv[1], sys.argv[2]
s = open(src).read()


def once(text, old, new, count=1):
    n = text.count(old)
    if n != count:
        sys.exit(f"gen_group_probe: {old!r} occurs {n} times, not {count}")
    return text.replace(old, new)


# --- the parent: the interrupt script and run-child
s = once(s, '   "sleep 0.5\\n"\n   "kill -INT \\"$pid\\"\\n"\n',
         '   "saw=$(date +%s%N)\\n"\n   "sleep 0.5\\n"\n   "kill -INT \\"$pid\\"\\n"\n'
         '   "sent=$(date +%s%N)\\n"\n')
s = once(s, '   "grep -v \'^(ready \' \\"$out\\"\\n"\n',
         '   "grep -v \'^(ready \' \\"$out\\"\\n"\n   "echo \\"(script saw $saw sent $sent)\\"\\n"\n')
s = once(s, "           (list (car r) (read-all (cadr r)) (caddr r))))))))",
         """           (let* ((data (read-all (cadr r)))
                  (probe? (lambda (d) (and (pair? d) (memq (car d) '(probe script)))))
                  (kept (filter (lambda (d) (not (probe? d))) data)))
             (display "PROBE ")
             (write (list 'status (car r) 'kept kept 'probes (filter probe? data) 'stderr (caddr r)))
             (newline)
             (flush-output-port (current-output-port))
             (list (car r) kept (caddr r)))))))))""")

PRELUDE = """
    (load-shared-object (getenv "SIGPROBE"))
    (define probe-install (foreign-procedure "probe_install" () int))
    (define probe-gettid (foreign-procedure "probe_gettid" () long))
    (define probe-now (foreign-procedure "probe_now" () integer-64))
    (define probe-count (foreign-procedure "probe_count" () int))
    (define probe-tid (foreign-procedure "probe_tid" (int) long))
    (define probe-ns (foreign-procedure "probe_ns" (int) integer-64))
    (define probe-rax (foreign-procedure "probe_rax" (int) long))
    (define probe-mainsys (foreign-procedure "probe_mainsys" (int) long))
    (define probe-syscall-of (foreign-procedure "probe_syscall_of" (long) long))
    (define probe-installed (probe-install))
    (define probe-lock (make-mutex))
    (define probe-events '())
    (define (probe-note! tag . vals)
      (let ((t (probe-now)))
        (critical-section
         (with-mutex probe-lock (set! probe-events (cons (cons* tag t (append vals (list (list 'gc (collections) (bytes-allocated) (bytes-allocated 0))))) probe-events))))))
    (define (probe-frames k n)
      (let loop ((i (inspect/object k)) (n n) (acc '()))
        (if (or (= n 0) (not (eq? (i 'type) 'continuation)))
            (reverse acc)
            (loop (i 'link) (- n 1) (cons (let ((c (i 'code))) (and c (c 'name))) acc)))))
    (let ((old (collect-request-handler)))
      (collect-request-handler
       (lambda () (probe-note! 'collect-request (probe-gettid)) (when (getenv "GROUP_TRIP_DELTA") (collect-trip-bytes 8388608)) (old) (probe-note! 'collected (probe-gettid)))))
    (define (probe-handler!)
      (call/cc (lambda (k) (probe-note! 'handler k))))
    (define (probe-print! name)
      (write (list 'probe name (get-process-id) probe-installed
                   (map (lambda (e)
                          (if (eq? (car e) 'handler)
                              (list 'handler (cadr e) (probe-frames (caddr e) 24))
                              e))
                        (reverse probe-events))
                   (let loop ((i 0) (acc '()))
                     (if (>= i (min 16 (probe-count)))
                         (reverse acc)
                         (loop (+ i 1) (cons (list (probe-tid i) (probe-ns i) (probe-rax i) (probe-mainsys i)) acc))))
                   (probe-count)))
      (newline)
      (flush-output-port (current-output-port)))"""

CHILDREN = ['lost', 'submit', 'raise', 'turn', 'sections', 'admissions', 'resume']

# Per child: the call the SIGINT is meant to land in, wrapped in notes.
CALLS = {
    'lost': [("                          (http-await p)\n                          'returned",
              "                          (probe-note! 'await-call)\n                          (http-await p)\n"
              "                          (probe-note! 'await-return)\n                          'returned")],
    'submit': [("(call-with-request-group session (lambda (go) (go 'get url) 'returned))",
                "(call-with-request-group session (lambda (go) (probe-note! 'go-call) (go 'get url) (probe-note! 'go-return) 'returned))")],
    'raise': [("(call-with-request-group session (lambda (go) (go 'get url) 'returned))",
               "(call-with-request-group session (lambda (go) (probe-note! 'go-call) (go 'get url) (probe-note! 'go-return) 'returned))")],
    'turn': [("             (http-await pending)\n             'returned",
              "             (probe-note! 'await-call)\n             (http-await pending)\n"
              "             (probe-note! 'await-return)\n             'returned")],
    'sections': [("        (map http-response-status\n             (http-parallel session",
                  "        (probe-note! 'parallel-call)\n        (map http-response-status\n             (http-parallel session")],
    'admissions': [("            (http-pending-done? b1)\n",
                    "            (probe-note! 'done-call)\n            (http-pending-done? b1)\n            (probe-note! 'done-return)\n")],
    'resume': [("                  (guard (e (#t (cons 'raised (shown e))))\n                    (list 'value (run)))",
                "                  (guard (e (#t (cons 'raised (shown e))))\n                    (probe-note! 'run-call)\n                    (list 'value (run)))")],
}

for name in CHILDREN:
    start = s.index(f"(define {name}-child\n")
    nxt = [s.index(f";; {o}-child : ", start) for o in CHILDREN if f";; {o}-child : " in s[start:]]
    end = min(nxt) if nxt else s.index(";; --- the condition and the keys", start)
    seg = s[start:end]
    first_define = seg.index("\n    (define ")
    seg = seg[:first_define] + PRELUDE + seg[first_define:]
    seg, n = re.subn(r"\(sleep \(make-time 'time-duration 0 ([123])\)\)",
                     r"(begin (probe-note! 'hold-start (probe-gettid)) (sleep (make-time 'time-duration 0 \1)) "
                     r"(probe-note! 'hold-end (probe-syscall-of (get-process-id))))", seg)
    if n != 1:
        sys.exit(f"gen_group_probe: {name}: {n} holds")
    seg = once(seg, "(write (list 'ready (get-process-id)))",
               "(begin (probe-note! 'ready) (let ((trip (getenv \"GROUP_TRIP\")) (delta (getenv \"GROUP_TRIP_DELTA\"))) (when trip (collect-trip-bytes (string->number trip))) (when delta (collect-trip-bytes (+ (bytes-allocated 0) (string->number delta))))) (write (list 'ready (get-process-id))))")
    seg, n = re.subn(r"\(keyboard-interrupt-handler(\s+)\(lambda \(\)", r"(keyboard-interrupt-handler\1(lambda () (probe-handler!)", seg)
    if n != 1:
        sys.exit(f"gen_group_probe: {name}: {n} handlers")
    tag = name
    seg = once(seg, "(write (list 'counts (native-counts)))",
               f"(write (list 'counts (native-counts))) (newline) (probe-print! '{tag})")
    for old, new in CALLS[name]:
        seg = once(seg, old, new)
    s = s[:start] + seg + s[end:]

open(dest, 'w').write(s)
print(f"gen_group_probe: wrote {dest}")
