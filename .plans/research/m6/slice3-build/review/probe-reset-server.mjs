// Review probe: a server that reads a request's head and N body bytes, then
// ends the connection with nothing written. GET /count answers the uploads
// seen; GET /quit exits.
import net from 'node:net';
const N = Number(process.argv[2] || 65536);
let uploads = 0;
const server = net.createServer({ allowHalfOpen: false }, (socket) => {
  let buf = Buffer.alloc(0);
  let headEnd = -1;
  let control = false;
  socket.on('error', () => {});
  socket.on('data', (d) => {
    if (control) return;
    buf = Buffer.concat([buf, d]);
    if (headEnd < 0) {
      const i = buf.indexOf('\r\n\r\n');
      if (i < 0) return;
      headEnd = i + 4;
      const line = buf.subarray(0, buf.indexOf('\r\n')).toString('latin1');
      if (line.startsWith('GET /count')) {
        control = true;
        const body = `${uploads}\n`;
        socket.end(`HTTP/1.1 200 OK\r\nContent-Length: ${body.length}\r\nConnection: close\r\n\r\n${body}`);
        return;
      }
      if (line.startsWith('GET /quit')) { control = true; socket.end(); server.close(); setTimeout(() => process.exit(0), 50); return; }
      uploads += 1;
    }
    if (buf.length - headEnd >= N) socket.destroy();
  });
});
server.listen(0, '127.0.0.1', () => { process.stdout.write(`${server.address().port}\n`); });
