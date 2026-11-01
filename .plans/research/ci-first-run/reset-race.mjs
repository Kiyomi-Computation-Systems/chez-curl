// The CI-fix PR (2026-11-01): what a net server reads when wire-probe.mjs
// --reset sends "hello" and resets, with the server's loop blocked BLOCK ms
// as each connection arrives, so the data and the reset arrive in one
// wakeup; and what one read(2) of the fd shows at Node's end.
//   node build/cifix/reset-race.mjs RUNS BLOCK
import net from 'node:net';
import { spawn } from 'node:child_process';
import { readSync } from 'node:fs';

const [runs, block] = process.argv.slice(2).map(Number);
const seen = [];
const server = net.createServer((s) => {
  const until = Date.now() + block;
  while (Date.now() < until) { /* block the loop */ }
  let got = '';
  s.on('data', (d) => { got += d.toString(); });
  s.on('error', (e) => seen.push(`error:${e.code} data=${got}`));
  s.on('end', () => {
    let fd;
    try { readSync(s._handle.fd, Buffer.alloc(1)); fd = 'read-ok'; } catch (e) { fd = e.code; }
    seen.push(`end fd=${fd} data=${got}`);
  });
});
server.listen(0, '127.0.0.1', async () => {
  const port = server.address().port;
  for (let i = 0; i < runs; i++) {
    await new Promise((done) => {
      const p = spawn(process.execPath, ['tests/wire-probe.mjs', '--reset', '127.0.0.1', String(port), '68656c6c6f', '2000']);
      p.on('exit', done);
    });
    await new Promise((done) => setTimeout(done, block + 100));
  }
  const counts = {};
  for (const k of seen) counts[k] = (counts[k] || 0) + 1;
  console.log(`node ${process.version} uv ${process.versions.uv} block ${block} runs ${runs}: ${JSON.stringify(counts)}`);
  server.close();
});
