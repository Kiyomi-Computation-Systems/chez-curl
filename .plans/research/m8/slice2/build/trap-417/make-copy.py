#!/usr/bin/env python3
"""The 417 trap's copy of the tree (M8 slice 2's build): tests/origin.mjs's
/raw/head417 back to its per-connection 417 hold, the route as it was before
the build keyed it, and a log of what the route sees.

    python3 make-copy.py TREE

The hold: a connection's first request whose Expect holds 100-continue gets
the 417; every later request on that connection, 100 Continue and the 200;
a request on a new connection starts again, so a resend there gets a second
417. The key the query names is read and kept, and holds nothing.

The log, when HEAD417_LOG names a file, one line per event, appended:
  head417 EVENT conn=PORT t=MS ...
PORT the client's port, the connection; MS performance.now(), the origin's
monotonic clock. Events: start, the script given the connection's first
head; request, each request the route reads, its request line, its Expect,
its Content-Length, and the body bytes queued, already arrived after its
head, as the route reads it; wrote-417, with the bytes queued as the 417 is
written; next, the first bytes after the 417, their first byte and whether
the route reads them as the next request or as the body; skipped, the body
bytes it dropped; wrote-100 and wrote-200; close, the connection closing.
"""
import sys
p = sys.argv[1] + '/tests/origin.mjs'
t = open(p, encoding='utf-8').read()
def rep(a, b):
    global t
    assert t.count(a) == 1, a[:70]
    t = t.replace(a, b)
rep("import { readFileSync } from 'node:fs';", "import { appendFileSync, readFileSync } from 'node:fs';")
rep('''          const send = (bytes) => new Promise((resolve) => socket.write(bytes, () => resolve()));
          let head = s.head;
          for (;;) {
            const pairs = headPairs(head);
            const framing = framingOf(pairs);
            const length = framing !== null && framing.kind === 'length' ? framing.length : 0;
            if (!head417Keys.has(s.key) && expectsContinue(pairs)) {
              head417Keys.add(s.key);
              await send(h1Response(417, s.a, []));
              while (buffer.length === 0) if (!(await more())) return;
              if (!(buffer[0] >= 0x41 && buffer[0] <= 0x5a)) {
                while (buffer.length < length) if (!(await more())) return;
                buffer = buffer.subarray(length);
              }''','''          const send = (bytes) => new Promise((resolve) => socket.write(bytes, () => resolve()));
          const port = socket.remotePort;
          const log = (event, rest) => {
            if (process.env.HEAD417_LOG) {
              appendFileSync(process.env.HEAD417_LOG,
                             `head417 ${event} conn=${port} t=${performance.now().toFixed(1)}${rest ? ` ${rest}` : ''}\\n`);
            }
          };
          const queued = () => buffer.length + s.conn.input.items.reduce((n, item) => n + item[0].length, 0);
          socket.on('close', () => log('close', ''));
          log('start', `head-at=${s.conn.headAt.toFixed(1)}`);
          let head = s.head;
          let refused = false;
          for (;;) {
            const pairs = headPairs(head);
            const framing = framingOf(pairs);
            const length = framing !== null && framing.kind === 'length' ? framing.length : 0;
            log('request', `line="${head.toString('latin1').split('\\r\\n')[0]}" expect=${expectsContinue(pairs)} cl=${length} queued=${queued()} held=${refused}`);
            if (!refused && expectsContinue(pairs)) {
              refused = true;
              log('writing-417', `queued=${queued()}`);
              await send(h1Response(417, s.a, []));
              log('wrote-417', `queued=${queued()}`);
              while (buffer.length === 0) if (!(await more())) { log('ended-after-417', `queued=${queued()}`); return; }
              const letter = buffer[0] >= 0x41 && buffer[0] <= 0x5a;
              log('next', `first=0x${buffer[0].toString(16)} read-as=${letter ? 'request' : 'body'} queued=${queued()}`);
              if (!letter) {
                while (buffer.length < length) if (!(await more())) return;
                buffer = buffer.subarray(length);
                log('skipped', `bytes=${length}`);
              }''')
rep('''            if (expectsContinue(pairs)) await send(ascii('HTTP/1.1 100 Continue\\r\\n\\r\\n'));
            while (buffer.length < length) if (!(await more())) return;
            await send(h1Response(200, s.b, []));
            break;''','''            if (expectsContinue(pairs)) { await send(ascii('HTTP/1.1 100 Continue\\r\\n\\r\\n')); log('wrote-100', ''); }
            while (buffer.length < length) if (!(await more())) return;
            await send(h1Response(200, s.b, []));
            log('wrote-200', '');
            break;''')
open(p, 'w', encoding='utf-8').write(t)
print('made', p)
