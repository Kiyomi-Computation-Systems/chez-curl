// step-server.mjs: a stand-in HTTP/1.1 server for step-hold.sps, on
// 127.0.0.1, its port printed on stdout as one line, (port N); it exits
// when its stdin ends. It reads each request's head whole, with no cap, so
// a request line of megabytes is taken. A target whose query holds n=N and
// h=H answers 302, a Location of N bytes, / then t then a's, and H more
// headers, X-H-i: v, then Content-Length: 0 and Connection: close; any
// other target answers 200, Content-Length: 0, Connection: close.
import net from 'node:net';

const server = net.createServer({ allowHalfOpen: true }, (socket) => {
  const chunks = [];
  let size = 0;
  let answered = false;
  socket.on('data', (chunk) => {
    if (answered) return;
    chunks.push(chunk);
    size += chunk.length;
    const all = Buffer.concat(chunks, size);
    const end = all.indexOf('\r\n\r\n');
    if (end < 0) return;
    answered = true;
    const line = all.subarray(0, all.indexOf('\r\n')).toString('latin1');
    const target = line.split(' ')[1] || '/';
    const q = target.indexOf('?');
    const params = new URLSearchParams(q < 0 ? '' : target.slice(q + 1));
    const n = Number(params.get('n'));
    const h = Number(params.get('h') || 0);
    if (params.has('n') && Number.isInteger(n) && n >= 2) {
      const parts = ['HTTP/1.1 302 Found\r\n', 'Location: /t', 'a'.repeat(n - 2), '\r\n'];
      for (let i = 1; i <= h; i++) parts.push(`X-H-${i}: v\r\n`);
      parts.push('Content-Length: 0\r\nConnection: close\r\n\r\n');
      socket.end(parts.join(''));
    } else {
      socket.end('HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
    }
  });
  socket.on('error', () => {});
});
server.listen(0, '127.0.0.1', () => {
  process.stdout.write(`(port ${server.address().port})\n`);
});
process.stdin.on('end', () => { server.close(); process.exit(0); });
process.stdin.resume();
