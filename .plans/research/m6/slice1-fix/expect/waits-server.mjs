// For waits.sps: reads a request's head, then waits 400 ms. If the body
// (Content-Length) has arrived by then, libcurl sent it at once: it did not
// wait for a 100. If not, it waited. Either way it then answers 200 with
// "waited\n" or "sent\n" as the body, after reading the body (it sends a
// 100 Continue first if the body has not come). Prints its port on stdout.
import net from 'node:net';
const server = net.createServer((socket) => {
  let buf = Buffer.alloc(0);
  let state = 'head';
  let need = 0;
  let verdict = null;
  socket.on('data', (d) => {
    buf = Buffer.concat([buf, d]);
    step();
  });
  function step() {
    if (state === 'head') {
      const end = buf.indexOf('\r\n\r\n');
      if (end < 0) return;
      const lines = buf.subarray(0, end).toString('latin1').split('\r\n');
      const cl = lines.map((l) => /^content-length:\s*(\d+)/i.exec(l)).find((m) => m);
      need = cl ? Number(cl[1]) : 0;
      buf = buf.subarray(end + 4);
      state = 'wait';
      setTimeout(() => {
        verdict = buf.length >= need ? 'sent' : 'waited';
        if (verdict === 'waited') socket.write('HTTP/1.1 100 Continue\r\n\r\n');
        state = 'body';
        step();
      }, 400);
    } else if (state === 'body') {
      if (buf.length < need) return;
      buf = buf.subarray(need);
      const body = verdict + '\n';
      socket.write(`HTTP/1.1 200 OK\r\nContent-Length: ${body.length}\r\n\r\n${body}`);
      state = 'head';
      if (buf.length) step();
    }
  }
  socket.on('error', () => socket.destroy());
});
server.listen(0, '127.0.0.1', () => process.stdout.write(`${server.address().port}\n`));
