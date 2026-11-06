#!/usr/bin/env python3
"""The carried races' fixes, their mutants: each a copy of the working tree
(every file but build/, .git and .plans) under build/carried-races/mut/NAME/,
with one mutation, its mutation.diff and suites.txt beside it.

  python3 build/carried-races/mut.py make [NAME ...]   make the copies
  python3 build/carried-races/mut.py list               the names, rules and suites

o*: the origin's /refuse route and its end (test-origin-tls); o0 is main's
origin whole, copied in. h*: the
drive's critical section, which test-http-client's SIGINT children guard.
m*: the take's order, which test-mailbox's guards. f*: the fixes' own
data, planted against.
"""
import difflib
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'build', 'carried-races', 'mut')
ORIGIN = 'tests/origin.mjs'
DRIVE = 'src/http-client/private/drive.sls'
ENGINE = 'src/curl/private/engine.sls'
HC = 'tests/test-http-client.sps'
MB = 'tests/mailbox-escape.sps'

ROUTE_AT0 = "      if (refuseAt === 0) return stream.close(http2.constants.NGHTTP2_REFUSED_STREAM);"
ROUTE_AT_N = """          refused = true;
          stream.close(http2.constants.NGHTTP2_REFUSED_STREAM);"""
PUSHED = """{ stream.pushStream({ ':path': '/refused' }, (err, push) => {
            if (err) return;
            push.on('error', () => {});
            push.close(http2.constants.NGHTTP2_REFUSED_STREAM);
          }); }"""
END_NEXT = """  setImmediate(() => {
    if (!socket.destroyed && !socket.writableEnded) socket.end();
  });"""

DRIVE_SECTION = """                        (refusal (critical-section
                                  (guard (e ((curl-error? e) (list 'refused e)))
                                    (set! token (curl-submit engine request))
                                    #f)))
                        (outcome (or refusal (outcome-of token)))"""

TAKE = """      (wait-until who (mailbox-lock mailbox) (lambda () (mailbox-pop! mailbox)) deadline)))"""

MUTANTS = [
    ('baseline', 'control: no mutation', 'test-origin-tls test-origin test-http-client test-engine test-mailbox', []),
    ('o0-main-origin', "main's origin, tests/origin.mjs at 29f4b5d, under the fixed suite", 'test-origin-tls', [
        (ORIGIN, None, os.path.join(ROOT, 'build', 'carried-races', 'snap-main', 'tests', 'origin.mjs'))]),
    ('o1-no-rst', "/refuse's stream left open: no RST_STREAM", 'test-origin-tls', [
        (ORIGIN, ROUTE_AT0, "      if (refuseAt === 0) return undefined;"),
        (ORIGIN, ROUTE_AT_N, "          refused = true;")]),
    ('o2-wrong-code', '/refuse resets with INTERNAL_ERROR, not REFUSED_STREAM', 'test-origin-tls', [
        (ORIGIN, ROUTE_AT0, ROUTE_AT0.replace('NGHTTP2_REFUSED_STREAM', 'NGHTTP2_INTERNAL_ERROR')),
        (ORIGIN, ROUTE_AT_N, ROUTE_AT_N.replace('NGHTTP2_REFUSED_STREAM', 'NGHTTP2_INTERNAL_ERROR'))]),
    ('o3-wrong-stream', '/refuse resets a stream it pushes, stream 2, and leaves the request open', 'test-origin-tls', [
        (ORIGIN, ROUTE_AT0, """      if (refuseAt === 0) {
        stream.pushStream({ ':path': '/refused' }, (err, push) => {
          if (err) return;
          push.on('error', () => {});
          push.close(http2.constants.NGHTTP2_REFUSED_STREAM);
        });
        return undefined;
      }"""),
        (ORIGIN, ROUTE_AT_N, "          refused = true;\n          " + PUSHED)]),
    ('o4-end-at-once', "the client's end ends the connection at once, half-open kept", 'test-origin-tls', [
        (ORIGIN, END_NEXT, """  if (!socket.destroyed && !socket.writableEnded) socket.end();""")]),
    ('o5-node-end', "Node's own end: the HTTP/2 servers not half-open", 'test-origin-tls', [
        (ORIGIN, "http2.createServer({ allowHalfOpen: true })", "http2.createServer()"),
        (ORIGIN, "allowHTTP1: false, allowHalfOpen: true }", "allowHTTP1: false }")]),
    ('o6-next-tick', "the client's end ends the connection at the next tick, before the immediates", 'test-origin-tls', [
        (ORIGIN, END_NEXT, END_NEXT.replace('setImmediate(', 'process.nextTick('))]),
    ('h1-record-after-section', "the drive records its token after the submit's critical section", 'test-http-client', [
        (DRIVE, DRIVE_SECTION, """                        (refusal (let ((t (critical-section
                                           (guard (e ((curl-error? e) (cons 'refused e)))
                                             (curl-submit engine request)))))
                                   (if (and (pair? t) (eq? (car t) 'refused))
                                       (list 'refused (cdr t))
                                       (begin (set! token t) #f))))
                        (outcome (or refusal (outcome-of token)))""")]),
    ('h2-guard-outside-section', "the drive's refusal guard wraps the submit's critical section", 'test-http-client', [
        (DRIVE, DRIVE_SECTION, """                        (refusal (guard (e ((curl-error? e) (list 'refused e)))
                                   (critical-section
                                    (set! token (curl-submit engine request))
                                    #f)))
                        (outcome (or refusal (outcome-of token)))""")]),
    ('h3-no-section', "the drive's submit in no critical section of its own", 'test-http-client', [
        (DRIVE, DRIVE_SECTION, """                        (refusal (guard (e ((curl-error? e) (list 'refused e)))
                                   (set! token (curl-submit engine request))
                                   #f))
                        (outcome (or refusal (outcome-of token)))""")]),
    ('m1-take-peeks', "the take looks inside its section, and takes the token out after it", 'test-mailbox', [
        (ENGINE, TAKE, """      (let ((token (wait-until who (mailbox-lock mailbox)
                               (lambda ()
                                 (when (null? (mailbox-front mailbox))
                                   (mailbox-front-set! mailbox (reverse (mailbox-back mailbox)))
                                   (mailbox-back-set! mailbox '()))
                                 (let ((front (mailbox-front mailbox))) (and (pair? front) (car front))))
                               deadline)))
        (when token (locked (mailbox-lock mailbox) (lambda () (mailbox-pop! mailbox))))
        token)))""")]),
    ('m2-callback-in-section', "the delivery's callback runs inside the take's section", 'test-mailbox', [
        (ENGINE, """  (define (curl-mailbox-deliver mailbox ms)
    (let ((token (take 'curl-mailbox-deliver mailbox ms)))
      (when token
        (let ((callback (token-callback token)))
          (when callback (callback token))))
      token))""", """  (define (curl-mailbox-deliver mailbox ms)
    (check-mailbox 'curl-mailbox-deliver mailbox)
    (wait-until 'curl-mailbox-deliver (mailbox-lock mailbox)
                (lambda ()
                  (let ((token (mailbox-pop! mailbox)))
                    (when token
                      (let ((callback (token-callback token)))
                        (when callback (callback token))))
                    token))
                (deadline-after 'curl-mailbox-deliver ms)))""")]),
    ('f1-plant-trip-http-client', "plant: a collection asked for in the http-client children's holds", 'test-http-client', [
        (HC, """    (define (until-sent)
      (let wait ((n 0))""", """    (define (until-sent)
      (collect-trip-bytes 1024)
      (let wait ((n 0))""")]),
    ('f2-plant-trip-mailbox', "plant: a collection asked for in the mailbox child's hold, 64 KiB allocated as it prints its ready line", 'test-mailbox', [
        (MB, """     (write (list 'ready (get-process-id)))""", """     (collect-trip-bytes 1024)
     (make-bytevector 65536 0)
     (write (list 'ready (get-process-id)))""")]),
    ('f2a-plant-bare-trip-mailbox', "plant: a bare 1 KiB trip as the mailbox child prints its ready line, nothing allocated after it", 'test-mailbox', [
        (MB, """     (write (list 'ready (get-process-id)))""", """     (collect-trip-bytes 1024)
     (write (list 'ready (get-process-id)))""")]),
    ('f2b-plant-trip-mailbox-holder', "plant: a collection asked for by the mailbox child's holder as its hold starts, 64 KiB allocated after it", 'test-mailbox', [
        (MB, """(define (until-sent)
  (let wait ((n 0))""", """(define (until-sent)
  (collect-trip-bytes 1024)
  (make-bytevector 65536 0)
  (let wait ((n 0))""")]),
    ('f3-late-sigint-fixed-hold-hc', "plant: the http-client SIGINT 3.5 s after ready, each hold 1 s", 'test-http-client', [
        (HC, '   "sleep 0.5\\n"\n   "kill -INT \\"$pid\\"\\n"', '   "sleep 3.5\\n"\n   "kill -INT \\"$pid\\"\\n"'),
        (HC, """        (unless (or (and child-sent (file-exists? child-sent)) (>= n 2000))""",
         """        (unless (>= n 100)""")]),
    ('f4-late-sigint-fixed-hold-mb', "plant: the mailbox SIGINT 3.5 s after ready, the hold 1 s", 'test-mailbox', [
        ('tests/test-mailbox.sps', '   "sleep 0.5\\n"\n   "kill -INT \\"$pid\\"\\n"', '   "sleep 3.5\\n"\n   "kill -INT \\"$pid\\"\\n"'),
        (MB, """    (unless (or (and child-sent (file-exists? child-sent)) (>= n 2000))""",
         """    (unless (>= n 100)""")]),
    ('f5-late-sigint-hc', "control: the http-client SIGINT 3.5 s after ready, the holds until sent", 'test-http-client', [
        (HC, '   "sleep 0.5\\n"\n   "kill -INT \\"$pid\\"\\n"', '   "sleep 3.5\\n"\n   "kill -INT \\"$pid\\"\\n"')]),
    ('f6-late-sigint-mb', "control: the mailbox SIGINT 3.5 s after ready, the hold until sent", 'test-mailbox', [
        ('tests/test-mailbox.sps', '   "sleep 0.5\\n"\n   "kill -INT \\"$pid\\"\\n"', '   "sleep 3.5\\n"\n   "kill -INT \\"$pid\\"\\n"')]),
]


def make(name, rule, suite, edits):
    dest = os.path.join(OUT, name)
    os.makedirs(dest, exist_ok=True)
    subprocess.run(['rsync', '-a', '--delete', '--exclude', '/build', '--exclude', '/.git', '--exclude', '/.plans',
                    ROOT + '/', dest + '/'], check=True)
    diffs = []
    for f, old, new in edits:
        path = os.path.join(dest, f)
        text = open(path).read()
        if old is None:
            mutated = open(new).read()
        elif text.count(old) != 1:
            sys.exit(f'mut.py: {name}: {f}: the old text occurs {text.count(old)} times')
        else:
            mutated = text.replace(old, new)
        open(path, 'w').write(mutated)
        diffs.extend(difflib.unified_diff(text.splitlines(True), mutated.splitlines(True), 'a/' + f, 'b/' + f))
    open(os.path.join(dest, 'mutation.diff'), 'w').write(''.join(diffs))
    open(os.path.join(dest, 'suites.txt'), 'w').write(' '.join('tests/' + s + '.sps' for s in suite.split()) + '\n')
    print(f'mut.py: made {name}: {rule}')


if __name__ == '__main__':
    if len(sys.argv) < 2 or sys.argv[1] not in ('make', 'list'):
        sys.exit(__doc__)
    names = sys.argv[2:]
    for name, rule, suite, edits in MUTANTS:
        if names and name not in names:
            continue
        if sys.argv[1] == 'list':
            print(name, '|', rule, '|', suite)
        else:
            make(name, rule, suite, edits)
