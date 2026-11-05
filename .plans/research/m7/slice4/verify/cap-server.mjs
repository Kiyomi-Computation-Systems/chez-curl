// A raw TCP server for verify/cap-cli.sh: it logs each connection's bytes,
// hex-escaped outside 0x20-0x7e, as one line when the connection ends or
// after 2 s, and whether the head ended in a blank line. Never answers.
import net from 'node:net';
const show = (b) => [...b].map((c) => (c >= 0x20 && c <= 0x7e && c !== 0x5c ? String.fromCharCode(c) : '\\x' + c.toString(16).padStart(2, '0'))).join('');
let n = 0;
const server = net.createServer((s) => {
  const id = ++n;
  const parts = [];
  let done = false;
  const report = (why) => {
    if (done) return;
    done = true;
    const all = Buffer.concat(parts);
    const ended = all.includes(Buffer.from('\r\n\r\n'));
    const tail = all.subarray(Math.max(0, all.length - 60));
    console.log(`conn=${id} why=${why} bytes=${all.length} head-ended=${ended} tail="${show(tail)}"`);
    s.destroy();
  };
  s.on('data', (d) => parts.push(d));
  s.on('end', () => report('end'));
  s.on('error', () => report('error'));
  setTimeout(() => report('2s'), 2000);
});
server.listen(0, '127.0.0.1', () => console.log(`port=${server.address().port}`));
process.stdin.on('end', () => process.exit(0));
process.stdin.resume();
