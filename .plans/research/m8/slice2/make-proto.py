#!/usr/bin/env python3
"""M8 slice 2's prototype (the measurement before the build, the M8 plan's section 5).

    python3 make-proto.py TREE [--origin-only] [--seam] [--caps-limits]

Edits TREE, a copy of the repository made by tar (--exclude=./build
--exclude=./.git --exclude=./.plans/research), in place:

  the cap (unless --origin-only), the plan's section 3.3, kept minimal:
    - src/curl/private/transfer.sls: HEADERFUNCTION and HEADERDATA on every
      transfer, buffered too; the header callable counts, over the whole
      transfer, header lines (a head's status line, a line starting HTTP/ at a
      head's start, and its empty line left out) and every byte handed; past
      1,000 lines or 102,400 bytes it records header-limit and answers 0; once
      any reason is recorded it refuses every later call, answering 0;
    - src/curl/private/conditions.sls: header-limit a reason, raised as
      &curl-too-large whatever its code, as body-limit is.
  the origin (always): tests/origin.mjs's two HTTP/2 faces, h2c and h2, with
    Node's send limit raised, maxSendHeaderBlockLength 64 MiB; with
    --caps-limits, all three the caps stand-in's h2 face raises
    (research/m8/caps/server.mjs): that, maxHeaderListPairs 2^20 and
    SETTINGS_MAX_HEADER_LIST_SIZE 64 MiB, which changes the SETTINGS frame
    each face sends first.
  the seam (--seam, the probe's tree alone, never make test's): a log of what
    the header callable was handed, each transfer's, appended as
    finish-transfer reads it, and take-header-tallies!, exported from (curl
    private transfer), which answers the log, oldest first, and empties it.

Each edit replaces one exact text, which must occur once; anything else stops it.
"""
import sys

def edit(path, old, new, count=1):
    with open(path, encoding='utf-8') as f:
        text = f.read()
    n = text.count(old)
    if n != count:
        sys.exit(f"make-proto: {path}: expected {count} of {old[:70]!r}, found {n}")
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text.replace(old, new))

args = sys.argv[1:]
if not args:
    sys.exit("usage: make-proto.py TREE [--origin-only] [--seam]")
tree = args[0]
origin_only = '--origin-only' in args
caps_limits = '--caps-limits' in args
seam = '--seam' in args
transfer = f"{tree}/src/curl/private/transfer.sls"
conditions = f"{tree}/src/curl/private/conditions.sls"
origin = f"{tree}/tests/origin.mjs"

# --- the origin -------------------------------------------------------------
limits = ("maxSendHeaderBlockLength: 64 << 20, maxHeaderListPairs: 1 << 20, settings: { maxHeaderListSize: 64 << 20 }"
          if caps_limits else "maxSendHeaderBlockLength: 64 << 20")
edit(origin, "http2.createServer({ allowHalfOpen: true })",
     "http2.createServer({ allowHalfOpen: true, " + limits + " })")
edit(origin, "http2.createSecureServer({ ...leafOf.options, allowHTTP1: false, allowHalfOpen: true })",
     "http2.createSecureServer({ ...leafOf.options, allowHTTP1: false, allowHalfOpen: true, " + limits + " })")

if not origin_only:
    # --- the sink's counts ---------------------------------------------------
    edit(transfer, "            (mutable reads) (immutable prereq-hold)))",
         "            (mutable reads) (immutable prereq-hold)\n"
         "            (mutable hlines) (mutable hbytes) (mutable hstart)"
         + (" (mutable heads) (mutable hcalls) (mutable hafter)" if seam else "") + "))")
    edit(transfer, """                                  (and seam (cdr seam))))))""",
         """                                  (and seam (cdr seam)))
                                0 0 #t""" + (" '() 0 0" if seam else "") + """)))""")

    # --- the cap in the header callable --------------------------------------
    seam_count = ""
    if seam:
        seam_count = """
      ;; The probe's seam: each head as (STATUS LINES BYTES), T for a
      ;; section no status line opened, newest first.
      (cond (empty (bump-head! sink 0 n))
            (status (sink-heads-set! sink (cons (list (status-of data n) 0 n) (sink-heads sink))))
            (else (when (or (null? (sink-heads sink)) start)
                    (sink-heads-set! sink (cons (list 'T 0 0) (sink-heads sink))))
                  (bump-head! sink 1 n)))"""
    edit(transfer, """  ;; empty-line? : Positive-Integer Natural -> Boolean""",
         """  ;; header-line-cap : Positive-Integer
  ;; header-byte-cap : Positive-Integer
  ;; The cap on a transfer's response headers (ADR-0040): past this many
  ;; header lines, or bytes handed, over the whole transfer, the header
  ;; callable records header-limit and refuses the line.
  (define header-line-cap 1000)
  (define header-byte-cap 102400)

  ;; status-line? : Positive-Integer Natural -> Boolean
  ;; Whether the N bytes at DATA begin "HTTP/", read by the checked copy.
  (define (status-line? data n)
    (and (>= n 5)
         (let ((bytes (make-bytevector 5)))
           (copy-foreign->bytevector! data bytes 0 5)
           (bytevector=? bytes (string->utf8 "HTTP/")))))
""" + ("""
  ;; status-of : Positive-Integer Natural -> (U Integer String)
  ;; The probe's seam: a status line's code, its second word.
  (define (status-of data n)
    (let ((bytes (make-bytevector (min n 64))))
      (copy-foreign->bytevector! data bytes 0 (min n 64))
      (let* ((text (utf8->string bytes))
             (start (let loop ((i 0)) (if (or (= i (string-length text)) (char=? (string-ref text i) #\\space)) (+ i 1) (loop (+ i 1)))))
             (end (let loop ((i start)) (if (or (>= i (string-length text)) (not (char<=? #\\0 (string-ref text i) #\\9))) i (loop (+ i 1))))))
        (or (and (< start end) (string->number (substring text start end))) text))))

  ;; bump-head! : Sink Natural Natural -> Void
  (define (bump-head! sink lines n)
    (when (pair? (sink-heads sink))
      (let ((head (car (sink-heads sink))))
        (sink-heads-set! sink (cons (list (car head) (+ (cadr head) lines) (+ (caddr head) n))
                                    (cdr (sink-heads sink)))))))

  ;; The log of what the header callable was handed, each transfer's, as
  ;; finish-transfer read it, newest first, under sinks-lock.
  (define header-tallies '())

  ;; take-header-tallies! : -> (Listof (List Natural Natural Natural (Listof (List Any Natural Natural))))
  ;; The probe's seam: the log, oldest first, each entry (CALLS LINES BYTES
  ;; HEADS AFTER), HEADS oldest first, AFTER the calls the callable refused
  ;; because a reason was recorded already; the log emptied.
  (define (take-header-tallies!)
    (locked sinks-lock
      (lambda ()
        (let ((log (reverse header-tallies)))
          (set! header-tallies '())
          log))))

  ;; tally! : Sink -> Void
  (define (tally! sink)
    (let ((entry (list (sink-hcalls sink) (sink-hlines sink) (sink-hbytes sink) (reverse (sink-heads sink))
                       (sink-hafter sink))))
      (locked sinks-lock (lambda () (set! header-tallies (cons entry header-tallies))))))
""" if seam else "") + """
  ;; count-header-line! : Sink Positive-Integer Natural -> Boolean
  ;; The line of N bytes at DATA counted against SINK's cap: every byte,
  ;; and a header line unless it is a head's empty line or, at a head's
  ;; start, its status line, a line starting HTTP/. #t while the counts are
  ;; within the cap, the line's among them.
  (define (count-header-line! sink data n)
    (let* ((start (sink-hstart sink))
           (empty (empty-line? data n))
           (status (and (not empty) start (status-line? data n))))
      (sink-hbytes-set! sink (+ (sink-hbytes sink) n))
      (cond (empty (sink-hstart-set! sink #t))
            (status (sink-hstart-set! sink #f))
            (else (sink-hstart-set! sink #f)
                  (sink-hlines-set! sink (+ (sink-hlines sink) 1))))""" + seam_count + """
      (and (<= (sink-hlines sink) header-line-cap) (<= (sink-hbytes sink) header-byte-cap))))

  ;; empty-line? : Positive-Integer Natural -> Boolean""")

    edit(transfer, """            (cond
              ((not sink) 0)
              (else
               (sink-lines-set! sink (+ (sink-lines sink) 1))""",
         """            (cond
              ((not sink) 0)""" + ("""
              ((begin (sink-hcalls-set! sink (+ (sink-hcalls sink) 1)) #f) 0)""" if seam else "") + """
              ((sink-recorded sink)""" + (" (sink-hafter-set! sink (+ (sink-hafter sink) 1))" if seam else "") + """ 0)
              ((not (count-header-line! sink data n))
               (record! key 'header-limit #f)
               0)
              (else
               (sink-lines-set! sink (+ (sink-lines sink) 1))""")

    # --- every transfer sets the header callable -----------------------------
    edit(transfer, """    (when (plan-stream plan)
      (set-option! easy "HEADERFUNCTION" read-head-entry buffer)
      (set-option! easy "HEADERDATA" key buffer))""",
         """    (set-option! easy "HEADERFUNCTION" read-head-entry buffer)
    (set-option! easy "HEADERDATA" key buffer)""")

    if seam:
        edit(transfer, """           (recorded (reason-of sink)))
      (cond
        (recorded
         (failure (car recorded) code #f buffer""",
             """           (recorded (reason-of sink)))
      (tally! sink)
      (cond
        (recorded
         (failure (car recorded) code #f buffer""")
        # export the seam
        with open(transfer, encoding='utf-8') as f:
            text = f.read()
        i = text.index("(export")
        with open(transfer, 'w', encoding='utf-8') as f:
            f.write(text[:i] + "(export take-header-tallies!\n          " + text[i + len("(export"):])

    # --- header-limit, of &curl-too-large -------------------------------------
    edit(conditions, """    '(perform-failed body-limit callback-raised setopt-failed unknown-option no-handle
      cancelled stopped pause-failed body-length-mismatch body-not-replayable))""",
         """    '(perform-failed body-limit callback-raised setopt-failed unknown-option no-handle
      cancelled stopped pause-failed body-length-mismatch body-not-replayable header-limit))""")
    edit(conditions, """                (and (eq? class 'too-large) (eq? reason 'body-limit)))""",
         """                (and (eq? class 'too-large) (memq reason '(body-limit header-limit))))""")
    edit(conditions, """    (let ((make (case (if (eq? reason 'body-limit)
                          'too-large""",
         """    (let ((make (case (if (memq reason '(body-limit header-limit))
                          'too-large""")
print(f"make-proto: {tree} edited ({'origin only' if origin_only else 'the cap and the origin'}"
      f"{', the seam' if seam else ''}, {'the caps stand-in' if caps_limits else 'the send limit'}'s h2 limits)")
