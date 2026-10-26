// M4 slice 1's capturing server (the M4 plan, section 4.1): node:net on
// 127.0.0.1, which knows only enough HTTP to find a request's end.
//
//   node capture.mjs
//
// It reads each request's head, up to the first CRLF CRLF, then the body its
// Content-Length declares, or none. To a request for /continue that asks
// Expect: 100-continue it answers 100 Continue at once; to /silent, never, so
// the client sends its body when its own wait ends. Then it answers 200 with
// one JSON line: the head as Latin-1 text, the body's length and FNV-1a, and
// the ms between the head's end and the body's first byte, null with no body.
// It announces its port on stdout, and exits 0 when its stdin ends.
import net from 'node:net';
import { performance } from 'node:perf_hooks';

const fnv1a = (bytes) => {
  let h = 2166136261;
  for (const b of bytes) h = Math.imul(h ^ b, 16777619) >>> 0;
  return h.toString(16).padStart(8, '0');
};

const server = net.createServer((socket) => {
  let buffered = Buffer.alloc(0);
  let head = null;
  let need = 0;
  let headAt = 0;
  let bodyAt = null;
  const parts = [];
  let got = 0;
  let done = false;
  const finish = () => {
    if (done) return;
    done = true;
    const body = Buffer.concat(parts);
    const json = JSON.stringify({
      head: head.toString('latin1'),
      length: body.length,
      fnv: fnv1a(body),
      wait: bodyAt === null ? null : Math.round(bodyAt - headAt),
    });
    socket.end(`HTTP/1.1 200 OK\r\nContent-Length: ${Buffer.byteLength(json)}\r\nConnection: close\r\n\r\n${json}`);
  };
  socket.on('error', () => socket.destroy());
  socket.on('data', (chunk) => {
    let rest = chunk;
    if (head === null) {
      buffered = Buffer.concat([buffered, chunk]);
      const end = buffered.indexOf('\r\n\r\n');
      if (end < 0) return;
      head = buffered.subarray(0, end + 4);
      headAt = performance.now();
      rest = buffered.subarray(end + 4);
      const text = head.toString('latin1');
      const length = /\r\ncontent-length:[ \t]*([0-9]+)\r\n/i.exec(text);
      need = length ? Number(length[1]) : 0;
      if (/\r\nexpect:[ \t]*100-continue\r\n/i.test(text) && text.split(' ')[1] === '/continue') {
        socket.write('HTTP/1.1 100 Continue\r\n\r\n');
      }
    }
    if (rest.length > 0) {
      if (bodyAt === null) bodyAt = performance.now();
      parts.push(rest);
      got += rest.length;
    }
    if (got >= need) finish();
  });
});

server.listen(0, '127.0.0.1', () => process.stdout.write(`${server.address().port}\n`));
process.stdin.on('data', () => {});
process.stdin.on('end', () => {
  server.close();
  process.exit(0);
});
