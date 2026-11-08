// A loopback stand-in for example.com, plain http: every request is read
// whole and answered 200 with a short body; /login sets one cookie.
import http from 'node:http';
const server = http.createServer((req, res) => {
  let n = 0;
  req.on('data', (c) => { n += c.length; });
  req.on('end', () => {
    const headers = { 'Content-Type': 'text/plain' };
    if (req.url === '/login') headers['Set-Cookie'] = 'session=abc; Path=/';
    res.writeHead(200, headers);
    res.end(`${req.method} ${req.url} got ${n} bytes\n`);
  });
});
server.listen(0, '127.0.0.1', () => {
  process.stdout.write(`${server.address().port}\n`);
});
