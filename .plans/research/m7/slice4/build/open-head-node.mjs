// build/m7s4b/probe/open-head-node.mjs: what node:http tells a server of a
// head its client leaves open, ending the connection mid-head. One request
// line and a Cookie: with no line end, then FIN. Prints clientError's code,
// bytesParsed and rawPacket, and what a 'data' listener of the server's own
// saw. With "listen" as its argument the server keeps a 'data' listener on
// each connection; without, none.
import http from 'node:http';
import net from 'node:net';

const listen = process.argv[2] === 'listen';
const server = http.createServer((req, res) => { res.end('ok\n'); });
let seen = 0;
if (listen) server.on('connection', (socket) => socket.on('data', (chunk) => { seen += chunk.length; }));
server.on('clientError', (err, socket) => {
  console.log(`clientError ${err.code} bytesParsed ${err.bytesParsed} rawPacket ${err.rawPacket === undefined ? 'undefined' : err.rawPacket.length}`);
  socket.destroy();
});
server.listen(0, '127.0.0.1', () => {
  const { port } = server.address();
  const c = net.connect(port, '127.0.0.1', () => {
    c.end('GET /cookies?key=k HTTP/1.1\r\nHost: a\r\nCookie: ');
  });
  c.on('close', () => {
    setTimeout(() => {
      console.log(`data listener ${listen ? `saw ${seen} bytes` : 'none'}`);
      server.close();
    }, 200);
  });
});
