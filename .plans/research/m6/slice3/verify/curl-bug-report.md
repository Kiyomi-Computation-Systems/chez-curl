# Draft: curl bug report, for the maintainer to file

A draft, written 2026-10-31 from the logs beside it; nothing here has been sent. File it at
<https://github.com/curl/curl/issues>, editing as you see fit.

---

**Title:** HTTP/2: an early 3xx response while the request body is still being sent never
completes the transfer (times out with the whole response received)

### I did this

A POST of a 4 MiB body over HTTP/2 to a server that answers `303` (or any of 301, 302, 307,
308) after reading 64 KiB of the body, ends its response stream, and keeps reading the rest:

```
node early-3xx-server.mjs 303 65536        # prints its port; source below
head -c 4194304 /dev/zero > body
curl -v --http2-prior-knowledge -X POST --data-binary @body -m 5 -o /dev/null http://127.0.0.1:PORT/
```

curl logs that it stops sending, and receives the whole response, then waits until the
timeout:

```
< HTTP/2 303
* HTTP error before end of send, stop sending
* abort upload after having sent 196456 bytes
* Operation timed out after 5006 milliseconds with 10 out of 10 bytes received
curl: (28) Operation timed out after 5006 milliseconds with 10 out of 10 bytes received
```

The server sees the stream reset (`STREAM_CLOSED`) only when curl's timeout fires. Without
`-m`, curl waits for ever.

### I expected the following

The transfer to complete with the 303 as soon as the response is received, as it does for a
413 in the same setup:

```
< HTTP/2 413
* HTTP error before end of send, stop sending
* abort upload after having sent 196456 bytes
```

curl exits 0 within 6 ms, and the server sees the stream reset at once.

### What we measured

- Every 3xx tried, 301, 302, 303, 307 and 308, waits to the timeout; 413 and 503 complete at
  once. `Location` present or not makes no difference.
- **curl 8.20.0** (GnuTLS, nghttp2 1.69.0) and **curl 8.23.0** (OpenSSL 3.0.13, nghttp2 1.59.0):
  the wait, on the command-line tool and through libcurl's multi interface, with a body from
  `COPYPOSTFIELDS` or from a read callback.
- **curl 8.5.0** (Ubuntu 24.04's, OpenSSL and GnuTLS builds), **7.85.0** (built from its
  release, OpenSSL) and **Apple's 8.7.1** (macOS 26, SecureTransport, nghttp2 1.68.1): every 3xx
  completes at once; 8.7.1's tool exited 0 in 5 to 8 ms for the 303, after "stop sending" and
  "abort upload after having sent 130921 bytes". Not bisected between 8.7.1 and 8.20.0.
- Over HTTP/1.1 the same server's 3xx completes at once on every version above, through libcurl.
- `CURLOPT_KEEP_SENDING_ON_ERROR` set to 1 avoids the wait on 8.20.0 (a body from
  `COPYPOSTFIELDS`): the transfer completes with the 3xx within 50 ms.
- `FOLLOWLOCATION` is off throughout.

Separately, and perhaps already fixed: curl 7.85.0 waits to the timeout in the same setup after
an early **200** (`10 out of 10 bytes received`), where later versions end at once (8.20.0's
tool with 55, `Failed sending data to the peer`).

### The server

```js
// early-3xx-server.mjs: h2c by prior knowledge; answers STATUS after AFTER body bytes.
import http2 from 'node:http2';
const status = Number(process.argv[2] || 303);
const after = Number(process.argv[3] || 65536);
const server = http2.createServer();
server.on('stream', (stream) => {
  let bytes = 0, answered = false;
  stream.on('data', (chunk) => {
    bytes += chunk.length;
    if (!answered && bytes >= after) {
      answered = true;
      stream.respond({ ':status': status, 'content-length': '10' });
      stream.end('early 3xx\n');
    }
  });
  stream.on('error', () => {});
});
server.listen(0, '127.0.0.1', () => console.log(server.address().port));
```

### curl/libcurl version

curl 8.20.0 (x86_64-unknown-linux-gnu) libcurl/8.20.0 GnuTLS/3.8.13 zlib/1.3.1 zstd/1.5.6
libidn2/2.3.8 libpsl/0.21.5 nghttp2/1.69.0 mit-krb5/1.21

curl 8.23.0 (x86_64-pc-linux-gnu) libcurl/8.23.0 OpenSSL/3.0.13 zlib/1.3 nghttp2/1.59.0

### operating system

Linux x86_64 (Guix; Ubuntu 24.04 in Docker), Node 24.18.0 and 20.10.0 as the server.

---

Evidence in this repository: `early-3xx-cli.sh` and `early-3xx-server.mjs` (the reproduction),
`results/early-3xx-cli-guix-8.20.0.log`, `results/early-3xx-cli-docker.log` and
`results/early-3xx-cli-mac-8.7.1.log` (curl's tool on 8.20.0, 8.23.0, 7.85.0 and Apple's 8.7.1), `results/whole-*.log` (a whole body through libcurl's multi
interface, on 7.85.0, 8.5.0, 8.20.0 and 8.23.0), `results/verbose-guix.log` and `results/keepsend-guix.log`.
