#!/usr/bin/env python3
"""make_v1.py: the fix's first version, rebuilt, and its three mutants: copies
of the final tree under build/carried-races/v1/NAME/ whose tests/origin.mjs ends
a client's half-closed connection once every refused stream has closed and
nghttp2's outbound queue is empty, checked from an immediate (h2EndOnceWritten),
in place of h2EndNext. v1 is that version; v1-no-refusal-wait drops the
refusals' wait, v1-no-queue-wait the queue's, v1-bare drops both."""
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
OUT = os.path.join(ROOT, 'build', 'carried-races', 'v1')

V1 = """// The streams each HTTP/2 session has reset whose RST_STREAM nghttp2 has
// not yet written (the first version of the fix).
const h2Refusals = new WeakMap();

function h2Refuse(stream) {
  const pending = h2Refusals.get(stream.session);
  if (pending) {
    pending.add(stream);
    stream.once('close', () => pending.delete(stream));
  }
  stream.close(http2.constants.NGHTTP2_REFUSED_STREAM);
}

function h2EndOnceWritten(session, socket) {
  const deadline = performance.now() + 5000;
  const check = () => {
    if (socket.destroyed || socket.writableEnded) return;
    const pending = h2Refusals.get(session);
    const queued = session.destroyed ? 0 : (session.state.outboundQueueSize || 0);
    if (CONDITION || performance.now() > deadline) socket.end();
    else setImmediate(check);
  };
  setImmediate(check);
}

"""
CONDITIONS = {
    'v1': "((!pending || pending.size === 0) && queued === 0)",
    'v1-no-refusal-wait': "(queued === 0)",
    'v1-no-queue-wait': "(!pending || pending.size === 0)",
    'v1-bare': "true",
}


def once(text, old, new):
    if text.count(old) != 1:
        sys.exit(f"make_v1: {old[:60]!r} occurs {text.count(old)} times")
    return text.replace(old, new)


for name, cond in CONDITIONS.items():
    dest = os.path.join(OUT, name)
    os.makedirs(dest, exist_ok=True)
    subprocess.run(['rsync', '-a', '--delete', '--exclude', '/build', '--exclude', '/.git', '--exclude', '/.plans',
                    ROOT + '/', dest + '/'], check=True)
    p = os.path.join(dest, 'tests', 'origin.mjs')
    s = open(p).read()
    s = once(s, "      if (refuseAt === 0) return stream.close(http2.constants.NGHTTP2_REFUSED_STREAM);",
             "      if (refuseAt === 0) return h2Refuse(stream);")
    s = once(s, "          refused = true;\n          stream.close(http2.constants.NGHTTP2_REFUSED_STREAM);",
             "          refused = true;\n          h2Refuse(stream);")
    i = s.index("// h2EndNext: SOCKET, an HTTP/2 session's, ended at the next immediate, as its\n")
    j = s.index("// h2Face: SERVER, the face NAME, with the listeners every HTTP/2 face\n")
    s = s[:i] + V1.replace('CONDITION', cond) + s[j:]
    s = once(s, "    session.socket.on('end', function clientEnded() { h2EndNext(this); });",
             "    h2Refusals.set(session, new Set());\n    session.socket.on('end', function clientEnded() { h2EndOnceWritten(session, this); });")
    open(p, 'w').write(s)
    print(f"make_v1: made {name}: {cond}")
