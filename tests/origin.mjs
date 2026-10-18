// tests/origin.mjs: chez-curl's test origin (ADR-0005, amended; M1 plan,
// sections 3 and 4). One ES module, Node's standard library only, for Node 20
// and later (measured on 20.10.0 and 24.18.0).
//
// The contract:
//   - `node tests/origin.mjs` takes no arguments. Any argument exits 2, with
//     a message on stderr.
//   - Each face listens on 127.0.0.1, port 0, so the OS picks the port.
//   - Once every face listens, it writes one line on stdout, a flat JSON
//     object, and nothing else ever goes there:
//       {"node":"v24.18.0","pid":12345,"http":"127.0.0.1:40001","raw":"127.0.0.1:40002"}
//     node is process.version and pid process.pid. Each face is ADDRESS:PORT,
//     both read back from server.address() once it listens.
//   - It exits 0 when its stdin ends, after closing every listener and
//     destroying every open socket. Its stdin ends once every process holding
//     the pipe's write end has gone: its suite, and, when the suite dies, any
//     probe or command the suite was running, each ended by its own bound.
//   - A client that misbehaves ends only its own connection. Any other error
//     goes to stderr and exits 1, so a suite sees the origin die, not hang.
//
// The faces:
//   http  node:http. Deterministic: no Date, headers in a fixed order, and
//         Connection: close back when Node will close.
//           GET /status/CODE             200-599: status CODE, body "status CODE\n"
//           GET /redirect/CODE?to=TARGET 300-308: Location: TARGET, decoded,
//                                        body "redirect CODE\n"
//           GET /chunked                 three writes, each its own chunk
//           ANY /echo                    the request as Node parsed it
//           anything else                404, body "not found\n"
//         204 and 304 carry no body and no Content-Length; 205 carries
//         Content-Length: 0 and no body.
//   raw   node:net. Reads the request head, up to the first CRLF CRLF, and
//         gives up on one longer than 64 KiB. Plays the script that
//         /raw/NAME?QUERY names, then closes: no keep-alive. An unknown NAME
//         or parameter, or one out of range, gets the fixed 400. A client
//         that half-closes after its request still gets its whole script
//         (allowHalfOpen); once the script has ended or stalls, the client's
//         FIN closes the connection.
//
// The suites (tests/test-origin.sps) hold their own copy of each scenario's
// bytes, written separately from these. They never read them from here, so
// changing a script here fails them.

import http from 'node:http';
import net from 'node:net';
import process from 'node:process';

const HOST = '127.0.0.1';

// fatal: the one way out on an error that is not a client's: stderr, exit 1.
function fatal(what, err) {
  process.stderr.write(`origin: ${what}: ${(err && err.stack) || err}\n`);
  process.exit(1);
}

process.on('uncaughtException', (err) => fatal('uncaught exception', err));
process.on('unhandledRejection', (err) => fatal('unhandled rejection', err));

if (process.argv.length > 2) {
  process.stderr.write(
    `origin: it takes no arguments, and was given ${JSON.stringify(process.argv.slice(2))}\n`);
  process.exit(2);
}

// Every open socket, of either face, so that stdin's end can destroy them.
const sockets = new Set();
function track(socket) {
  sockets.add(socket);
  socket.on('close', () => sockets.delete(socket));
}

// --- the well-formed face -------------------------------------------------

// noBody: the statuses that carry no body.
const noBody = new Set([204, 304]);

// send: writes one whole response, its headers in the order given, then
// Connection, from Node's own decision whether to keep the connection.
function send(res, status, headers, body) {
  res.sendDate = false;
  const connection = res.shouldKeepAlive ? 'keep-alive' : 'close';
  res.writeHead(status, [...headers, 'Connection', connection]);
  res.end(body);
}

// text: a whole response with the body BODY, or none for a status that
// carries none.
function text(res, status, body, headers = []) {
  if (noBody.has(status)) {
    send(res, status, headers, undefined);
  } else if (status === 205) {
    send(res, status, [...headers, 'Content-Length', '0'], undefined);
  } else {
    const bytes = Buffer.from(body, 'latin1');
    send(res, status, [...headers, 'Content-Length', String(bytes.length)], bytes);
  }
}

function notFound(res) {
  text(res, 404, 'not found\n');
}

// redirectTarget: the decoded TARGET of a query that is exactly to=TARGET,
// or null. TARGET must decode to printable ASCII with no space, which is
// what a header value can carry unchanged.
function redirectTarget(query) {
  if (query === undefined || !query.startsWith('to=')) return null;
  const raw = query.slice(3);
  if (raw === '' || raw.includes('&')) return null;
  let target;
  try {
    target = decodeURIComponent(raw);
  } catch {
    return null;
  }
  return /^[\x21-\x7e]+$/.test(target) ? target : null;
}

function respond(req, res, body) {
  const at = req.url.indexOf('?');
  const path = at < 0 ? req.url : req.url.slice(0, at);
  const query = at < 0 ? undefined : req.url.slice(at + 1);
  let m;
  if ((m = /^\/status\/([2-5][0-9][0-9])$/.exec(path)) && query === undefined) {
    const code = Number(m[1]);
    text(res, code, `status ${code}\n`);
  } else if ((m = /^\/redirect\/(30[0-8])$/.exec(path))) {
    const code = Number(m[1]);
    const target = redirectTarget(query);
    if (target === null) return notFound(res);
    text(res, code, `redirect ${code}\n`, ['Location', target]);
  } else if (path === '/chunked' && query === undefined) {
    res.sendDate = false;
    const connection = res.shouldKeepAlive ? 'keep-alive' : 'close';
    res.writeHead(200, ['Transfer-Encoding', 'chunked', 'Connection', connection]);
    res.write('alpha\n');
    res.write('beta\n');
    res.write('gamma\n');
    res.end();
  } else if (path === '/echo') {
    let lines = `${req.method} ${req.url} HTTP/${req.httpVersion}\n`;
    for (let i = 0; i < req.rawHeaders.length; i += 2) {
      lines += `${req.rawHeaders[i]}: ${req.rawHeaders[i + 1]}\n`;
    }
    lines += '\n';
    const bytes = Buffer.concat([Buffer.from(lines, 'latin1'), body]);
    send(res, 200, ['Content-Length', String(bytes.length)], bytes);
  } else {
    notFound(res);
  }
}

const httpServer = http.createServer((req, res) => {
  const chunks = [];
  req.on('error', () => res.destroy());
  req.on('data', (chunk) => chunks.push(chunk));
  req.on('end', () => respond(req, res, Buffer.concat(chunks)));
});
httpServer.on('connection', track);

// --- the raw face ---------------------------------------------------------

// The longest request head the raw face reads, its CRLF CRLF included.
const HEAD_LIMIT = 64 * 1024;

const ascii = (s) => Buffer.from(s, 'latin1');

// A script is a list of steps: write these bytes, wait N ms, end (FIN),
// reset (RST), or stall (write nothing until the client goes).
const write = (s) => ({ step: 'write', bytes: typeof s === 'string' ? ascii(s) : s });
const wait = (ms) => ({ step: 'wait', ms });
const END = { step: 'end' };
const RESET = { step: 'reset' };
const STALL = { step: 'stall' };

const badRequest = [
  write('HTTP/1.1 400 Bad Request\r\nContent-Length: 12\r\nConnection: close\r\n\r\nbad request\n'),
  END,
];

// The scripts, by NAME. Each takes its parameters, by name: every one listed,
// each a decimal natural within its range, and no other. play gets the
// parameters and the request head's bytes.
const scripts = {
  // framing
  'content-length': { play: () => [write('HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n'), END] },
  'chunked': {
    play: () => [write('HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n'
                       + '5\r\nhello\r\n1\r\n\n\r\n0\r\n\r\n'), END],
  },
  'chunked-extensions-trailers': {
    play: () => [write('HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nTrailer: X-Trailer\r\n\r\n'
                       + 'C;name=value\r\nhello world\n\r\n0;last\r\nX-Trailer: done\r\n\r\n'), END],
  },
  'chunked-tiny': {
    play: () => [write('HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n'
                       + [...'hello\n'].map((c) => `1\r\n${c}\r\n`).join('') + '0\r\n\r\n'), END],
  },
  'close-delimited': { play: () => [write('HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nhello\n'), END] },
  'http10': { play: () => [write('HTTP/1.0 200 OK\r\n\r\nhello\n'), END] },

  // drips
  'drip': {
    params: { bytes: [1, 4096], gap: [1, 5000] },
    play: ({ bytes, gap }) => {
      const steps = [write(`HTTP/1.1 200 OK\r\nContent-Length: ${bytes}\r\n\r\n`)];
      for (let i = 0; i < bytes; i++) {
        steps.push(wait(gap), write(String.fromCharCode(97 + (i % 26))));
      }
      steps.push(END);
      return steps;
    },
  },
  'stall-after-head': { play: () => [write('HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\n'), STALL] },
  'stall-before-head': { play: () => [STALL] },

  // oversized
  'big-header': {
    params: { bytes: [1, 1048576] },
    play: ({ bytes }) => [write(Buffer.concat([ascii('HTTP/1.1 200 OK\r\nX-Big: '),
                                               Buffer.alloc(bytes, 'a'), ascii('\r\n\r\n')])), END],
  },
  'many-headers': {
    params: { count: [1, 100000] },
    play: ({ count }) => {
      const lines = ['HTTP/1.1 200 OK\r\n'];
      for (let i = 1; i <= count; i++) lines.push(`X-H-${i}: v\r\n`);
      lines.push('\r\n');
      return [write(lines.join('')), END];
    },
  },

  // protocol errors
  'bad-status-line': { play: () => [write('HTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n'), END] },
  'bad-status-code': { play: () => [write('HTTP/1.1 2000 OK\r\nContent-Length: 6\r\n\r\nhello\n'), END] },
  'bad-chunk-size': {
    play: () => [write('HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\nhello\n\r\n0\r\n\r\n'), END],
  },
  'short-body': { play: () => [write('HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhello'), END] },
  'reset-mid-body': { play: () => [write('HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhello'), RESET] },
  'conflicting-content-length': {
    play: () => [write('HTTP/1.1 200 OK\r\nContent-Length: 5\r\nContent-Length: 6\r\n\r\nhello\n'), END],
  },
  'chunked-and-content-length': {
    play: () => [write('HTTP/1.1 200 OK\r\nContent-Length: 6\r\nTransfer-Encoding: chunked\r\n\r\n'
                       + '6\r\nhello\n\r\n0\r\n\r\n'), END],
  },
  'header-no-colon': {
    play: () => [write('HTTP/1.1 200 OK\r\nContent-Length: 6\r\nX-No-Colon\r\n\r\nhello\n'), END],
  },
  'nul-in-header': {
    play: () => [write('HTTP/1.1 200 OK\r\nContent-Length: 6\r\nX-Nul: a\0b\r\n\r\nhello\n'), END],
  },
  'close-before-response': { play: () => [END] },
  'http09': { play: () => [write('hello\n'), END] },

  // tolerated
  'bare-lf': { play: () => [write('HTTP/1.1 200 OK\nContent-Length: 6\n\nhello\n'), END] },

  // echo
  'echo': {
    play: (_, head) => [write(Buffer.concat([ascii(`HTTP/1.1 200 OK\r\nContent-Length: ${head.length}\r\n\r\n`),
                                             head])), END],
  },
};

// parameters: the query's parameters as SPEC asks for them, or null.
function parameters(spec, query) {
  const names = Object.keys(spec);
  if (query === undefined) return names.length === 0 ? {} : null;
  const found = {};
  for (const pair of query.split('&')) {
    const m = /^([a-z]+)=(0|[1-9][0-9]*)$/.exec(pair);
    if (!m || !Object.hasOwn(spec, m[1]) || Object.hasOwn(found, m[1])) return null;
    const value = Number(m[2]);
    const [low, high] = spec[m[1]];
    if (!(value >= low && value <= high)) return null;
    found[m[1]] = value;
  }
  return names.every((name) => Object.hasOwn(found, name)) ? found : null;
}

// scriptFor: the steps for the request head HEAD, its CRLF CRLF included.
function scriptFor(head) {
  const text = head.toString('latin1');
  const parts = text.slice(0, text.indexOf('\r\n')).split(' ');
  if (parts.length !== 3) return badRequest;
  const m = /^\/raw\/([a-z0-9-]+)(?:\?(.*))?$/.exec(parts[1]);
  if (!m || !Object.hasOwn(scripts, m[1])) return badRequest;
  const script = scripts[m[1]];
  const found = parameters(script.params || {}, m[2]);
  return found === null ? badRequest : script.play(found, head);
}

// pause: resolves after MS ms by the clock, never sooner, or when SOCKET
// closes. A timer can fire early by the loop's cached time, so it is rearmed
// for what is left.
function pause(socket, ms) {
  return new Promise((resolve) => {
    const start = performance.now();
    let timer;
    const done = () => {
      clearTimeout(timer);
      socket.off('close', done);
      resolve();
    };
    const check = () => {
      const left = ms - (performance.now() - start);
      if (left > 0) timer = setTimeout(check, Math.ceil(left));
      else done();
    };
    socket.on('close', done);
    timer = setTimeout(check, ms);
  });
}

// play: runs STEPS on SOCKET, whose STATE says whether the client has
// half-closed. A write waits until its bytes are handed to the kernel. It
// stops as soon as the socket can take no more. A stall writes nothing more,
// and leaves the connection to the client's FIN.
async function play(socket, state, steps) {
  state.playing = true;
  try {
    for (const s of steps) {
      if (socket.destroyed || !socket.writable) return;
      switch (s.step) {
        case 'write':
          await new Promise((resolve) => socket.write(s.bytes, () => resolve()));
          break;
        case 'wait':
          await pause(socket, s.ms);
          break;
        case 'end':
          socket.end();
          return;
        case 'reset':
          socket.resetAndDestroy();
          return;
        case 'stall':
          return;
        default:
          throw new Error(`no such step: ${s.step}`);
      }
    }
  } finally {
    state.playing = false;
    if (state.clientEnded && !socket.destroyed && socket.writable) socket.end();
  }
}

const rawServer = net.createServer({ allowHalfOpen: true }, (socket) => {
  track(socket);
  // Each write goes out as written: Nagle's algorithm may hold a small write
  // back while one is unacknowledged, which would join a drip's bytes.
  socket.setNoDelay(true);
  // A reset, or a write after the client went, ends this connection only.
  socket.on('error', () => socket.destroy());
  // With allowHalfOpen, the client's FIN leaves this side open: a script that
  // is playing goes on; otherwise this side ends too.
  const state = { playing: false, clientEnded: false };
  socket.on('end', () => {
    state.clientEnded = true;
    if (!state.playing) socket.end();
  });
  let head = Buffer.alloc(0);
  let started = false;
  socket.on('data', (chunk) => {
    if (started) return;
    head = Buffer.concat([head, chunk]);
    const end = head.subarray(0, HEAD_LIMIT).indexOf('\r\n\r\n');
    if (end >= 0) {
      started = true;
      const request = Buffer.from(head.subarray(0, end + 4));
      head = null;
      play(socket, state, scriptFor(request)).catch((err) => fatal('a script failed', err));
    } else if (head.length >= HEAD_LIMIT) {
      started = true;
      head = null;
      play(socket, state, badRequest).catch((err) => fatal('a script failed', err));
    }
  });
});

// --- the lifecycle --------------------------------------------------------

function listen(server, name) {
  return new Promise((resolve) => {
    server.on('error', (err) => fatal(`the ${name} face failed`, err));
    server.listen(0, HOST, resolve);
  });
}

function face(server) {
  const { address, port } = server.address();
  return `${address}:${port}`;
}

let stopping = false;
function stop(code) {
  if (stopping) return;
  stopping = true;
  let open = 2;
  const closed = () => {
    open -= 1;
    if (open === 0) process.exit(code);
  };
  httpServer.close(closed);
  rawServer.close(closed);
  for (const socket of sockets) socket.destroy();
}

await Promise.all([listen(httpServer, 'http'), listen(rawServer, 'raw')]);

const announcement = JSON.stringify({
  node: process.version,
  pid: process.pid,
  http: face(httpServer),
  raw: face(rawServer),
});

// stdin is read only once the announcement is out, so its end cannot come
// first.
process.stdout.write(`${announcement}\n`, () => {
  process.stdin.on('data', () => {});
  process.stdin.on('end', () => stop(0));
  process.stdin.on('error', (err) => {
    process.stderr.write(`origin: stdin failed: ${err && err.stack}\n`);
    stop(1);
  });
});
