// A minimal HTTP/2 server, plaintext by prior knowledge (h2c), for the curl
// bug report beside it: it answers STATUS (default 303) with a 10-byte body
// once AFTER bytes (default 65536) of the request body have arrived, ends
// its side of the stream, and goes on reading the rest of the body. It
// prints its port on stdout, then one line per stream on stderr.
//   node early-3xx-server.mjs [STATUS] [AFTER]
import http2 from 'node:http2';

const status = Number(process.argv[2] || 303);
const after = Number(process.argv[3] || 65536);
const server = http2.createServer();
server.on('stream', (stream) => {
  let bytes = 0;
  let answered = false;
  stream.on('data', (chunk) => {
    bytes += chunk.length;
    if (!answered && bytes >= after) {
      answered = true;
      stream.respond({ ':status': status, 'content-length': '10' });
      stream.end('early 3xx\n');
      console.error(`answered ${status} after ${bytes} bytes`);
    }
  });
  stream.on('end', () => console.error(`request body ended at ${bytes} bytes`));
  stream.on('error', (e) => console.error(`stream error ${e.code} at ${bytes} bytes`));
  stream.on('close', () => console.error(`stream closed at ${bytes} bytes, rst code ${stream.rstCode}`));
});
server.listen(0, '127.0.0.1', () => console.log(server.address().port));
process.stdin.on('end', () => process.exit(0));
process.stdin.resume();
