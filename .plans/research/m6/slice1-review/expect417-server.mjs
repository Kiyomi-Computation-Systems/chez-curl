// A raw HTTP/1.1 server for expect417.sps (M6 slice 1's review). It answers
// a request carrying "Expect: 100-continue" with "417 Expectation Failed",
// Content-Length 0, keeping the connection, and any other request, after
// reading its Content-Length body, with a 200 whose body is "second\n".
// With the argument "once", only a connection's first request gets the
// 417, and every later one, Expect or not, the 200.
// Each request's first line and whether it carried the Expect is logged to
// stderr. It prints its port on stdout, then serves until killed.
import net from 'node:net';

const once = process.argv[2] === 'once';
const server = net.createServer((socket) => {
  let buf = Buffer.alloc(0);
  let refused = 0;
  socket.on('data', (d) => {
    buf = Buffer.concat([buf, d]);
    for (;;) {
      const end = buf.indexOf('\r\n\r\n');
      if (end < 0) return;
      const head = buf.subarray(0, end).toString('latin1');
      const lines = head.split('\r\n');
      const expect = lines.some((l) => /^expect:\s*100-continue/i.test(l));
      const cl = lines.map((l) => /^content-length:\s*(\d+)/i.exec(l)).find((m) => m);
      const len = cl ? Number(cl[1]) : 0;
      if (expect && !(once && refused > 0)) {
        refused += 1;
        process.stderr.write(`request ${lines[0]} expect=yes\n`);
        buf = buf.subarray(end + 4);
        socket.write('HTTP/1.1 417 Expectation Failed\r\nContent-Length: 0\r\n\r\n');
        continue;
      }
      if (buf.length < end + 4 + len) return;
      process.stderr.write(`request ${lines[0]} expect=no\n`);
      buf = buf.subarray(end + 4 + len);
      socket.write('HTTP/1.1 200 OK\r\nContent-Length: 7\r\n\r\nsecond\n');
    }
  });
  socket.on('error', () => socket.destroy());
});
server.listen(0, '127.0.0.1', () => {
  process.stdout.write(`${server.address().port}\n`);
});
