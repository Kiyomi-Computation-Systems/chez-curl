import http from 'node:http';
const port = Number(process.argv[2]);
http.createServer((req, res) => { res.writeHead(200, { 'Content-Length': 3 }); res.end('ok\n'); })
  .listen(port, '127.0.0.1', () => console.log('listening'));
