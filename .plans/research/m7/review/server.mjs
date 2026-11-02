// Review stand-in: logs each request head's raw bytes, escaped, on stdout.
// /digest answers 401 with a Digest challenge unless an Authorization:
// Digest header came; everything else 200. Connection: close.
import net from 'node:net';
import process from 'node:process';

function esc(buf) {
  let s = '';
  for (const b of buf) {
    if (b === 0x0d) s += '\\r';
    else if (b === 0x0a) s += '\\n\n      ';
    else if (b < 0x20 || b > 0x7e) s += '\\x' + b.toString(16).padStart(2, '0');
    else s += String.fromCharCode(b);
  }
  return s;
}

const server = net.createServer((sock) => {
  let data = Buffer.alloc(0);
  sock.on('data', (chunk) => {
    data = Buffer.concat([data, chunk]);
    const end = data.indexOf('\r\n\r\n');
    if (end < 0) return;
    const head = data.subarray(0, end + 4);
    process.stdout.write(`server: head\n      ${esc(head)}\n`);
    const text = head.toString('latin1');
    const target = text.split(' ')[1] || '';
    const digest = /\r\nAuthorization: Digest /i.test(text);
    if (target.startsWith('/digest') && !digest) {
      sock.end('HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Digest realm="r", nonce="abc", qop="auth"\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
    } else {
      sock.end('HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: close\r\n\r\nok\n');
    }
    data = Buffer.alloc(0);
  });
  sock.on('error', () => {});
});
server.listen(0, '127.0.0.1', () => {
  process.stdout.write(`port ${server.address().port}\n`);
});
process.stdin.on('end', () => process.exit(0));
process.stdin.resume();
