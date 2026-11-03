// Answers 417 to every request head carrying Expect: 100-continue; with
// MODE=close it adds Connection: close and ends the socket after the answer.
// Prints "requests N" on each head, and the port on stdout first.
import net from 'node:net';
const mode = process.argv[2];
let n = 0;
const srv = net.createServer((s) => {
  let buf = Buffer.alloc(0);
  s.on('data', (d) => {
    buf = Buffer.concat([buf, d]);
    for (;;) {
      const i = buf.indexOf('\r\n\r\n');
      if (i < 0) return;
      const head = buf.subarray(0, i).toString('latin1');
      buf = buf.subarray(i + 4);
      n += 1;
      process.stdout.write(`requests ${n} ${head.split('\r\n')[0]}\n`);
      if (/^expect:\s*100-continue/im.test(head)) {
        s.write(`HTTP/1.1 417 Expectation Failed\r\nContent-Length: 0\r\n${mode === 'close' ? 'Connection: close\r\n' : ''}\r\n`);
        if (mode === 'close') { s.end(); return; }
      } else {
        s.write('HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok');
      }
    }
  });
  s.on('error', () => {});
});
srv.listen(0, '127.0.0.1', () => { process.stdout.write(`port ${srv.address().port}\n`); });
setTimeout(() => process.exit(0), 15000);
