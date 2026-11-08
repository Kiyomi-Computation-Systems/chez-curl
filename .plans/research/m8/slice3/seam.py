#!/usr/bin/env python3
"""M8 slice 3's probe seam, on a copy of the prototype's tree:
   python3 seam.py TREE
Adds to src/curl/private/transfer.sls, for engine-probe.sps alone (make test
never runs it):
  - transfer-file-check-gate-set!: a procedure the engine's file check calls
    first, on the engine's thread, outside every critical section, so a probe
    can change a path between the submit's stat and the engine's check;
  - take-transfer-sizes!: each finished transfer's URL and CURLINFO_REQUEST_SIZE,
    as libcurl answered it, (URL . SIZE), oldest first, read in finish-transfer;
  - take-file-check-times!: how long each engine's file check took, in ns."""
import sys
p = sys.argv[1] + '/src/curl/private/transfer.sls'
s = open(p).read()
def rep(old, new):
    global s
    assert s.count(old) == 1, old[:70]
    s = s.replace(old, new)
rep("""          multipart? check-plan-files! plan-body)""",
"""          multipart? check-plan-files! plan-body
          transfer-file-check-gate-set! take-transfer-sizes! take-file-check-times!)""")
rep("""  (define (check-plan-files! plan)
    (let ((body (plan-body plan)))""",
"""  ;; The probe's seam (seam.py): the gate, and the logs.
  (define file-check-gate (vector #f))
  (define (transfer-file-check-gate-set! proc) (vector-set! file-check-gate 0 proc))
  (define seam-lock (make-mutex))
  (define transfer-sizes '())
  (define file-check-times '())
  (define (take-transfer-sizes!)
    (locked seam-lock (lambda () (let ((all (reverse transfer-sizes))) (set! transfer-sizes '()) all))))
  (define (take-file-check-times!)
    (locked seam-lock (lambda () (let ((all (reverse file-check-times))) (set! file-check-times '()) all))))
  (define (seam-ns)
    (let ((t (current-time 'time-monotonic))) (+ (* (time-second t) 1000000000) (time-nanosecond t))))
  (define (check-plan-files! plan)
    (let ((gate (vector-ref file-check-gate 0)))
      (when (and gate (multipart? (plan-body plan))) (gate)))
    (let ((start (seam-ns)))
      (dynamic-wind
        (lambda () #f)
        (lambda () (seamless-check-plan-files! plan))
        (lambda ()
          (when (multipart? (plan-body plan))
            (let ((took (- (seam-ns) start)))
              (locked seam-lock (lambda () (set! file-check-times (cons took file-check-times))))))))))
  (define (seamless-check-plan-files! plan)
    (let ((body (plan-body plan)))""")
rep("""    (let* ((sink (live-transfer-sink live))
           (buffer (live-transfer-buffer live))
           (easy (live-transfer-easy live))
           (recorded (reason-of sink)))""",
"""    (let ((size (info-long (live-transfer-easy live) curlinfo-request-size)))
      (locked seam-lock (lambda () (set! transfer-sizes (cons (cons (plan-url (live-transfer-plan live)) size)
                                                              transfer-sizes)))))
    (let* ((sink (live-transfer-sink live))
           (buffer (live-transfer-buffer live))
           (easy (live-transfer-easy live))
           (recorded (reason-of sink)))""")
open(p, 'w').write(s)
