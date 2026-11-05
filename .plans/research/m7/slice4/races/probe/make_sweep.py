#!/usr/bin/env python3
"""make_sweep.py SRC DEST: the sweep program from a tree's tests/test-group.sps:
its instrumented copy (gen_group_probe.py), the interrupt script's sleep
read from GROUP_PROBE_SLEEP, cut before the suite's tests, and a main that
runs GROUP_SWEEP's child at each delay, GROUP_REPEAT times. A probe, not a test."""
import subprocess, sys, os
src, dest = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
tmp = dest + '.probe'
subprocess.run([sys.executable, os.path.join(here, 'gen_group_probe.py'), src, tmp], check=True)
s = open(tmp).read()
os.remove(tmp)
old = '   "sleep 0.5\\n"'
assert s.count(old) == 1
s = s.replace(old, '   "sleep \\"${GROUP_PROBE_SLEEP:-0.5}\\"\\n"')
cut = s.index(';; --- the condition and the keys')
head = s[:cut].replace("(only (chezscheme) sleep make-time", "(only (chezscheme) putenv sleep make-time", 1)
main = r'''
;; --- the sweep: CHILD run under interrupt-script with its sleep at each of
;; DELAYS (GROUP_SWEEP: "child d1 d2 ..." seconds), REPEAT times each.
(define sweep-spec (read (open-string-input-port (string-append "(" (or (getenv "GROUP_SWEEP") "raise 0.5") ")"))))
(define sweep-repeat (or (and (getenv "GROUP_REPEAT") (string->number (getenv "GROUP_REPEAT"))) 1))
(define sweep-deltas (let ((d (getenv "GROUP_DELTAS"))) (if d (read (open-string-input-port (string-append "(" d ")"))) '(#f))))
(call-with-origin
 (lambda (o)
   (define (url-of face path)
     (let ((f (origin-face o face)))
       (string-append "http://" (car f) ":" (number->string (cdr f)) path)))
   (define child (car sweep-spec))
   (define n 0)
   (for-each
    (lambda (delta)
     (for-each
      (lambda (d)
        (let loop ((i 0))
          (when (< i sweep-repeat)
            (set! n (+ n 1))
            (putenv "GROUP_PROBE_SLEEP" (number->string d))
            (when delta (putenv "GROUP_TRIP_DELTA" (number->string delta)))
            (display (list 'sweep child d i 'delta delta)) (newline)
            (case child
              ((raise) (run-child raise-child (url-of 'raw "/raw/pause-mid-body?ms=10000")))
              ((submit) (run-child submit-child (url-of 'raw "/raw/pause-mid-body?ms=10000")))
              ((turn-raise) (run-child turn-child (url-of 'raw (string-append "/raw/retry?key=turn-raise-" (number->string n) "&fail=1&how=close&then=stall")) "raise"))
              (else (display "unknown child") (newline)))
            (loop (+ i 1)))))
      (cdr sweep-spec)))
    sweep-deltas)))
(exit 0)
'''
open(dest, 'w').write(head + main)
print('make_sweep: wrote', dest)
