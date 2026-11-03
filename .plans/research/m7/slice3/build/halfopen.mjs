// A socket http.Server hands its connect event: half-open after the client's FIN?
// From the repository root: scripts/guix-env sh -c "node .plans/research/m7/slice3/build/halfopen.mjs without-end; node .plans/research/m7/slice3/build/halfopen.mjs with-end" < /dev/null
import http from 'node:http';
import net from 'node:net';
const withEnd = process.argv[2] === 'with-end';
const server = http.createServer();
server.on('connect', (req, sock) => {
  console.log('connect: allowHalfOpen', sock.allowHalfOpen);
  sock.write('HTTP/1.1 407 Proxy Authentication Required\r\nContent-Length: 0\r\n\r\n');
  if (withEnd) sock.on('end', () => sock.destroy());
  sock.on('end', () => console.log('server saw end'));
  sock.on('close', () => console.log('server socket closed'));
});
server.listen(0, '127.0.0.1', () => {
  const c = net.connect(server.address().port, '127.0.0.1', () => {
    c.write('CONNECT localhost:1 HTTP/1.1\r\nHost: localhost:1\r\n\r\n');
  });
  c.once('data', () => { c.end(); });
  setTimeout(() => {
    server.getConnections((e, n) => { console.log('open connections after 1 s:', n); process.exit(0); });
  }, 1000);
});
