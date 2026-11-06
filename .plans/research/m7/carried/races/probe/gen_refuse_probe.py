#!/usr/bin/env python3
"""gen_refuse_probe.py SRC-TESTS DEST-TESTS: instrumented copies of
tests/origin.mjs and tests/wire-probe.mjs, for the /refuse race.

A measurement copy, not a test. With RACE_LOG set, each process appends
one JSON object per event to that file, with t, the wall clock in ms
(performance.timeOrigin + performance.now()), and w, origin or probe.
Without it, both behave as the originals. Nothing goes to stdout or stderr
that did not before, so every test is unchanged.

  origin: per HTTP/2 session, on the session's socket (TCP for h2c, TLS for
    h2): session (face, the client's port), client-end (the client's FIN, or
    close_notify then FIN, read: Node's 'end'), server-finish (this side's
    end done: 'finish'), socket-close; per /refuse stream: refuse (the
    route calls stream.close, with the socket's readable state and
    nghttp2's outbound queue size), stream-close (its 'close', rstCode).
    Each carries the TCP handle's bytesWritten (ciphertext for h2), and
    the session socket's handle's (cleartext for h2).
  probe: connected (its local port), sent (its bytes with the kernel),
    half-close (socket.end() called), data (offset, length, hex), end
    (kind), error.
"""
import sys

src, dest = sys.argv[1], sys.argv[2]


def once(text, old, new):
    n = text.count(old)
    if n != 1:
        sys.exit(f"gen_refuse_probe: {old[:60]!r} occurs {n} times, not once")
    return text.replace(old, new)


o = open(f"{src}/origin.mjs").read()
o = once(o, "import { readFileSync } from 'node:fs';",
         "import { appendFileSync, readFileSync } from 'node:fs';")
o = once(o, "import tls from 'node:tls';\n", """import tls from 'node:tls';

// RACE: the /refuse race's log (build/carried-races/probe/gen_refuse_probe.py).
const RACE_LOG = process.env.RACE_LOG;
const rlog = RACE_LOG
  ? (o) => appendFileSync(RACE_LOG, `${JSON.stringify({ w: 'origin', pid: process.pid, t: performance.timeOrigin + performance.now(), ...o })}\\n`)
  : () => {};
const raceTcp = new Map();
const raceBytes = (port, sock) => ({
  tcpw: raceTcp.has(port) && raceTcp.get(port)._handle ? raceTcp.get(port)._handle.bytesWritten : null,
  sockw: sock && sock._handle ? sock._handle.bytesWritten : null,
});
""")
o = once(o, """function h2Face(server, name) {
  let sessionsSeen = 0;
  server.on('connection', track);
  server.on('session', (session) => {
    sessionsSeen += 1;
    session.connectionNumber = sessionsSeen;
    trackSession(session);
""", """function h2Face(server, name) {
  let sessionsSeen = 0;
  server.on('connection', track);
  server.on('connection', (sock) => {
    const port = sock.remotePort;
    raceTcp.set(port, sock);
    sock.on('close', () => raceTcp.delete(port));
  });
  server.on('session', (session) => {
    sessionsSeen += 1;
    session.connectionNumber = sessionsSeen;
    trackSession(session);
    if (RACE_LOG) {
      const port = session.socket.remotePort;
      session.racePort = port;
      rlog({ ev: 'session', face: name, port });
      session.socket.on('end', function raceEnd() {
        rlog({ ev: 'client-end', face: name, port, outq: session.destroyed ? null : session.state.outboundQueueSize, ...raceBytes(port, this) });
      });
      session.socket.on('finish', function raceFinish() { rlog({ ev: 'server-finish', face: name, port, ...raceBytes(port, this) }); });
      session.socket.on('close', function raceClose(hadError) { rlog({ ev: 'socket-close', face: name, port, hadError }); });
      session.socket.on('error', function raceError(err) { rlog({ ev: 'socket-error', face: name, port, code: err && err.code }); });
      session.on('error', (err) => rlog({ ev: 'session-error', face: name, port, code: err && err.code }));
      session.on('close', () => rlog({ ev: 'session-close', face: name, port }));
    }
""")
RACE_REFUSE = """
  const raceS = stream.session;
  if (RACE_LOG) {
    const port = raceS && raceS.racePort;
    const sock = raceS && !raceS.destroyed ? raceS.socket : null;
    rlog({ ev: 'refuse', face: raceS && raceS.raceFace, port, id: stream.id, at: stream.raceAt, key: stream.raceKey,
           outq: raceS && !raceS.destroyed ? raceS.state.outboundQueueSize : null,
           readableEnded: sock ? sock.readableEnded : null, readEnded: sock ? sock._readableState && sock._readableState.ended : null,
           ...raceBytes(port, null) });
    stream.on('close', () => rlog({ ev: 'stream-close', face: raceS && raceS.raceFace, port, id: stream.id, rstCode: stream.rstCode,
                                    outq: raceS && !raceS.destroyed ? raceS.state.outboundQueueSize : null, ...raceBytes(port, null) }));
  }
"""
MAIN_PATCH = r'''
o = once(o, """      const refuseAt = r.kind === 'refuse' && seenNow === 1 ? r.at : null;
      if (refuseAt === 0) return stream.close(http2.constants.NGHTTP2_REFUSED_STREAM);
""", """      const refuseAt = r.kind === 'refuse' && seenNow === 1 ? r.at : null;
      const raceRefuse = (at) => {
        if (!RACE_LOG) return;
        const s = stream.session;
        const port = s && s.racePort;
        const sock = s && !s.destroyed ? s.socket : null;
        rlog({ ev: 'refuse', face, port, id: stream.id, at, key: r.key, outq: s && !s.destroyed ? s.state.outboundQueueSize : null,
               readableEnded: sock ? sock.readableEnded : null, readEnded: sock ? sock._readableState && sock._readableState.ended : null,
               ...raceBytes(port, null) });
        stream.on('close', () => rlog({ ev: 'stream-close', face, port, id: stream.id, rstCode: stream.rstCode,
                                        outq: s && !s.destroyed ? s.state.outboundQueueSize : null, ...raceBytes(port, null) }));
      };
      if (refuseAt === 0) {
        raceRefuse(0);
        return stream.close(http2.constants.NGHTTP2_REFUSED_STREAM);
      }
""")
o = once(o, """        if (refuseAt !== null && record.bytes >= refuseAt) {
          refused = true;
          stream.close(http2.constants.NGHTTP2_REFUSED_STREAM);""", """        if (refuseAt !== null && record.bytes >= refuseAt) {
          refused = true;
          raceRefuse(refuseAt);
          stream.close(http2.constants.NGHTTP2_REFUSED_STREAM);""")
'''
if "function h2Refuse(stream) {" in o:
    # the fixed origin: one place refuses
    o = once(o, "function h2Refuse(stream) {\n", "function h2Refuse(stream) {\n" + RACE_REFUSE)
    o = once(o, """      const refuseAt = r.kind === 'refuse' && seenNow === 1 ? r.at : null;
""", """      const refuseAt = r.kind === 'refuse' && seenNow === 1 ? r.at : null;
      stream.raceAt = refuseAt; stream.raceKey = r.key;
""")
    o = once(o, "      session.racePort = port;\n", "      session.racePort = port;\n      session.raceFace = name;\n")
else:
    exec(MAIN_PATCH)
open(f"{dest}/origin.mjs", "w").write(o)

p = open(f"{src}/wire-probe.mjs").read()
p = once(p, "import { readFileSync, readSync } from 'node:fs';",
         "import { appendFileSync, readFileSync, readSync } from 'node:fs';")
p = once(p, "const started = performance.now();\n", """const started = performance.now();
// RACE: the /refuse race's log (build/carried-races/probe/gen_refuse_probe.py).
const RACE_LOG = process.env.RACE_LOG;
let racePort = null;
const rlog = RACE_LOG
  ? (o) => appendFileSync(RACE_LOG, `${JSON.stringify({ w: 'probe', pid: process.pid, port: racePort, t: performance.timeOrigin + performance.now(), ...o })}\\n`)
  : () => {};
""")
p = once(p, """  connected = true;
  say(`(connected ${ms()})`);""", """  connected = true;
  racePort = socket.localPort;
  rlog({ ev: 'connected', args: process.argv.slice(2, -2) });
  say(`(connected ${ms()})`);""")
p = once(p, """function sent() {
  if (reset)""", """function sent() {
  rlog({ ev: 'sent' });
  if (halfClose && !reset && !done) rlog({ ev: 'half-close' });
  if (reset)""")
p = once(p, """  say(`(data ${offset} ${ms()} "${chunk.toString('hex')}")`);""",
         """  rlog({ ev: 'data', offset, length: chunk.length, hex: chunk.toString('hex') });
  say(`(data ${offset} ${ms()} "${chunk.toString('hex')}")`);""")
p = once(p, """function finish(line, resetting) {
  if (done) return;""", """function finish(line, resetting) {
  if (done) return;
  rlog({ ev: 'end', line });""")
open(f"{dest}/wire-probe.mjs", "w").write(p)
print(f"gen_refuse_probe: wrote {dest}/origin.mjs and {dest}/wire-probe.mjs")
