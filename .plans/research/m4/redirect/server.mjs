// Redirect probe server: /rCODE answers CODE with Location /echo; /echo
// answers 200 with the method, the target, Content-Length, Content-Type and
// the body. Announces its port on stdout; exits when stdin ends.
import http from 'node:http';
const server = http.createServer((req, res) => {
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    const m = /^\/r(\d{3})$/.exec(req.url);
    if (m && m[1] !== '200') {
      res.writeHead(Number(m[1]), { Location: '/echo', 'Content-Length': 0 });
      return res.end();
    }
    const body = Buffer.concat(chunks);
    const text = `${req.method} ${req.url} content-length=${req.headers['content-length'] ?? 'none'} content-type=${req.headers['content-type'] ?? 'none'} expect=${req.headers['expect'] ?? 'none'} body=${JSON.stringify(body.toString('latin1'))}`;
    res.writeHead(200, { 'Content-Length': Buffer.byteLength(text) });
    res.end(text);
  });
});
server.listen(0, '127.0.0.1', () => process.stdout.write(`${server.address().port}\n`));
process.stdin.on('data', () => {});
process.stdin.on('end', () => { server.close(); server.closeAllConnections(); process.exit(0); });
