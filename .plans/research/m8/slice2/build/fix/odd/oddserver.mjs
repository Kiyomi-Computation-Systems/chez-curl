// M8 slice 2's review fixes: the odd-header stand-in. GET /K answers head K,
// written whole as the request's head ends, then closes. Prints its port,
// then serves until its stdin ends.
import net from 'node:net';
const heads = {
  // mid-head, after content-length
  a: 'HTTP/1.1 200 OK\r\ncontent-length: 0\r\nHTTP/1.1 200 OK\r\nx-a: v\r\n\r\n',
  b: 'HTTP/1.1 200 OK\r\ncontent-length: 0\r\nHTTP/1 : v\r\nx-a: v\r\n\r\n',
  c: 'HTTP/1.1 200 OK\r\ncontent-length: 0\r\nHTTP/1.1 x: v\r\nx-a: v\r\n\r\n',
  d: 'HTTP/1.1 200 OK\r\ncontent-length: 0\r\nHTTP/1: v\r\nx-a: v\r\n\r\n',
  e: 'HTTP/1.1 200 OK\r\ncontent-length: 0\r\nHTTP/1 200: v\r\nx-a: v\r\n\r\n',
  h: 'HTTP/1.1 200 OK\r\ncontent-length: 0\r\nHTTP/1.1 x-000001: vvvv\r\nHTTP/1.1 x-000002: vvvv\r\n\r\n',
  // a trailer section's first line
  f: 'HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\n\r\n0\r\nHTTP/x: v\r\nx-a: v\r\n\r\n',
  g: 'HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\n\r\n0\r\nHTTP/1.1 200 OK\r\nx-a: v\r\n\r\n',
  j: 'HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\n\r\n0\r\nHTTP/x-000001: vvvv\r\nx-000002: vvvv\r\n\r\n',
  k: 'HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\n\r\n0\r\nHTTP/1.1 x: v\r\nx-a: v\r\n\r\n',
  l: 'HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\n\r\n0\r\nHTTP/1 : v\r\nx-a: v\r\n\r\n',
  m: 'HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\n\r\n0\r\nHTTP/1.1: v\r\nx-a: v\r\n\r\n',
  // an HTTP/1.0 head
  i: 'HTTP/1.0 200 OK\r\ncontent-length: 0\r\nx-a: v\r\n\r\n',
};
const s = net.createServer((c) => {
  let buf = '';
  c.on('data', (d) => {
    buf += d;
    const m = /^GET \/(\w)/.exec(buf);
    if (buf.includes('\r\n\r\n') && m) c.end(heads[m[1]]);
  });
  c.on('error', () => {});
});
s.listen(0, '127.0.0.1', () => { process.stdout.write(`${s.address().port}\n`); });
process.stdin.on('end', () => process.exit(0));
process.stdin.resume();
