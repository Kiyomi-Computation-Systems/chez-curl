// tests/wire-probe.mjs: the byte probe (ADR-0005). It knows no HTTP: it sends
// the bytes it is given and reports every byte it receives, so nothing between
// the origin and a suite normalises framing. Node's standard library only, for
// Node 20 and later (measured on 20.10.0 and 24.18.0).
//
//   node tests/wire-probe.mjs [--reset | --half-close] [--tls SERVERNAME [--alpn LIST]]
//                             [--split OFFSET:MS] [--deadline MS] HOST PORT HEX IDLE-MS
//
// It connects to HOST:PORT and sends HEX's bytes once (none for an empty
// HEX). With --split OFFSET:MS, two positive naturals, OFFSET fewer than
// HEX's bytes, it sends the first OFFSET of them, then, MS ms by the clock
// after the kernel took those, the rest; the idle bound starts again as
// the rest goes. HEX is pairs of lower-case hex digits, or @FILE: a file holding
// them, read whole, for bytes too many for one argument. It ends the
// connection itself when IDLE-MS pass with no data, or when the whole run
// reaches --deadline MS, 30000 when not given: a peer that keeps sending
// cannot keep it waiting. On stdout it prints Scheme data, one datum per
// line; each MS is whole milliseconds since it started:
//
//   (connected MS)             taken before it sends a byte: once connected,
//                              or, with --tls, once the handshake is done
//   (data OFFSET MS "HEX")     one per chunk it reads; OFFSET is the chunk's
//                              first byte's place in the stream. Chunk
//                              boundaries are not part of any contract.
//   (end KIND MS)              KIND is eof; reset; timeout, IDLE-MS passed
//                              with no data; or deadline, the run reached
//                              --deadline. On the last two it destroys the
//                              socket. An end Node reports is a reset when
//                              one read(2) of the socket's fd, then, fails
//                              with ECONNRESET: libuv before 1.52 reports an
//                              end, never reading the reset, when the last
//                              data and a reset are read in one wakeup
//                              (measured on Node 20.10.0, TCP and TLS, and
//                              22.23.4, TCP). Node 24 bundles 1.52.1 from
//                              24.16.0; every Node 20 and 22 to 20.20.2 and
//                              22.23.4, CI's, bundles an older one
//   (end error MS "CODE")      any other error, with its code
//   (reset-sent MS)            with --reset: once its bytes are handed to the
//                              kernel, it resets the connection
//                              (resetAndDestroy), in place of any end line.
//                              A destroy() reaches the peer as a FIN, never
//                              a reset (measured).
//   (refused "CODE" MS)        the connection, or with --tls the handshake,
//                              failed, in place of all the lines above; CODE
//                              is EOF for a TLS peer that closed before the
//                              handshake was done
//
// With --half-close it ends its side (a FIN, after TLS's close_notify with
// --tls) once its bytes are handed to the kernel, and goes on reading: over
// TLS too, on Node 20.10.0 and 24.18.0 (measured). Without it, it never
// half-closes.
//
// With --tls SERVERNAME it speaks TLS, with SNI SERVERNAME, a DNS name, never
// an IP address, and judges no certificate: it verifies nothing. With
// --alpn LIST it offers LIST's protocols, separated by commas, each once, in
// LIST's order, by ALPN, and only with --tls. --reset cannot be given with --tls: resetting the TCP
// socket under a client TLS socket reached the server as a FIN (measured).
//
// It exits 0 when it ran, and 2 on a usage error, with a message on stderr.

import { readFileSync, readSync } from 'node:fs';
import net from 'node:net';
import process from 'node:process';
import tls from 'node:tls';

const started = performance.now();
const ms = () => Math.floor(performance.now() - started);

function usage(problem) {
  process.stderr.write(
    `wire-probe: ${problem}\nusage: node tests/wire-probe.mjs [--reset | --half-close] [--tls SERVERNAME [--alpn LIST]] [--split OFFSET:MS] [--deadline MS] HOST PORT HEX IDLE-MS\n`);
  process.exit(2);
}

// code: an error's code, as a word a Scheme string holds unescaped.
const code = (err) => String((err && err.code) || 'UNKNOWN').replace(/[^A-Za-z0-9_]/g, '_');

const positive = /^[1-9][0-9]*$/;

// A DNS name: labels of letters, digits and inner hyphens, joined by dots.
const dnsName = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$/;

// An ALPN list: protocols of printable ASCII but the comma, joined by commas.
const alpnList = /^[\x21-\x2b\x2d-\x7e]+(?:,[\x21-\x2b\x2d-\x7e]+)*$/;

let args = process.argv.slice(2);
let reset = false;
let halfClose = false;
let servername = null;
let alpn = null;
let deadline = 30000;
let split = null;
for (;;) {
  if (args[0] === '--reset' && !reset) {
    reset = true;
    args = args.slice(1);
  } else if (args[0] === '--half-close' && !halfClose) {
    halfClose = true;
    args = args.slice(1);
  } else if (args[0] === '--tls' && servername === null) {
    if (args.length < 2) usage('--tls takes SERVERNAME, a DNS name');
    servername = args[1];
    args = args.slice(2);
  } else if (args[0] === '--alpn' && alpn === null) {
    if (args.length < 2) usage('--alpn takes LIST, protocols separated by commas');
    alpn = args[1];
    args = args.slice(2);
  } else if (args[0] === '--deadline') {
    if (args.length < 2 || !positive.test(args[1])) usage('--deadline takes a positive natural, its milliseconds');
    deadline = Number(args[1]);
    args = args.slice(2);
  } else if (args[0] === '--split' && split === null) {
    const m = args.length < 2 ? null : /^([1-9][0-9]*):([1-9][0-9]*)$/.exec(args[1]);
    if (!m) usage('--split takes OFFSET:MS, two positive naturals');
    split = { offset: Number(m[1]), ms: Number(m[2]) };
    args = args.slice(2);
  } else {
    break;
  }
}
if (reset && halfClose) usage('--reset and --half-close cannot both be given');
if (reset && servername !== null) {
  usage('--reset and --tls cannot both be given: a reset under a TLS socket reaches the server as a FIN');
}
if (alpn !== null && servername === null) usage('--alpn is given only with --tls');
if (servername !== null && net.isIP(servername) !== 0) {
  usage(`--tls takes a DNS name, and ${JSON.stringify(servername)} is an IP address, which SNI cannot carry`);
}
if (servername !== null && !dnsName.test(servername)) {
  usage(`--tls takes a DNS name, and was given ${JSON.stringify(servername)}`);
}
if (alpn !== null && !alpnList.test(alpn)) {
  usage(`--alpn takes protocols separated by commas, and was given ${JSON.stringify(alpn)}`);
}
if (alpn !== null && new Set(alpn.split(',')).size !== alpn.split(',').length) {
  usage(`--alpn names a protocol twice, in ${JSON.stringify(alpn)}`);
}
if (args.length !== 4) usage(`it takes 4 arguments after its options, and was given ${args.length}`);
const [host, portText, hexArg, idleText] = args;
if (host === '') usage('HOST is empty');
if (!/^(0|[1-9][0-9]*)$/.test(portText) || Number(portText) > 65535) {
  usage(`PORT is ${JSON.stringify(portText)}, not a natural up to 65535`);
}
let hex = hexArg;
if (hexArg.startsWith('@')) {
  try {
    hex = readFileSync(hexArg.slice(1), 'latin1');
  } catch (err) {
    usage(`HEX names ${JSON.stringify(hexArg.slice(1))}, which cannot be read: ${code(err)}`);
  }
}
if (!/^([0-9a-f]{2})*$/.test(hex)) usage('HEX is not pairs of lower-case hex digits');
if (split !== null && split.offset >= hex.length / 2) {
  usage(`--split's OFFSET, ${split.offset}, is not fewer than HEX's ${hex.length / 2} bytes`);
}
if (!positive.test(idleText)) usage(`IDLE-MS is ${JSON.stringify(idleText)}, not a positive natural`);
const idle = Number(idleText);

const say = (line) => process.stdout.write(`${line}\n`);

let connected = false;
let done = false;
let offset = 0;
let timer = null;
let splitTimer = null;

// The socket: TCP, or TLS over it, verifying nothing, with SNI SERVERNAME and
// ALPN's protocols when given. Either way half-open, so that its own end does
// not end its reading.
const socket = servername === null
  ? net.connect({ host, port: Number(portText), allowHalfOpen: true })
  : tls.connect({
    host,
    port: Number(portText),
    servername,
    rejectUnauthorized: false,
    ...(alpn === null ? {} : { ALPNProtocols: alpn.split(',') }),
    allowHalfOpen: true,
  });

// finish: prints LINE, the last, and ends the connection: with a reset when
// RESETTING, else with destroy().
function finish(line, resetting) {
  if (done) return;
  done = true;
  clearTimeout(timer);
  clearTimeout(whole);
  clearTimeout(splitTimer);
  say(line);
  if (resetting) socket.resetAndDestroy();
  else socket.destroy();
}

// The whole run's bound, by the clock: it is never rearmed.
const whole = setTimeout(() => {
  if (connected) finish(`(end deadline ${ms()})`, false);
  else finish(`(refused "DEADLINE" ${ms()})`, false);
}, deadline);

function arm() {
  clearTimeout(timer);
  timer = setTimeout(() => finish(`(end timeout ${ms()})`, false), idle);
}

// sent: what to do once the bytes are with the kernel.
function sent() {
  if (reset) finish(`(reset-sent ${ms()})`, true);
  else if (halfClose && !done) socket.end();
}

// after: calls THEN once MS ms have passed by the clock, never sooner: a
// timer can fire early by the loop's cached time, so it is rearmed for what
// is left.
function after(msToWait, then) {
  const start = performance.now();
  const check = () => {
    const left = msToWait - (performance.now() - start);
    if (left > 0) splitTimer = setTimeout(check, Math.ceil(left));
    else then();
  };
  splitTimer = setTimeout(check, msToWait);
}

socket.on(servername === null ? 'connect' : 'secureConnect', () => {
  connected = true;
  say(`(connected ${ms()})`);
  const bytes = Buffer.from(hex, 'hex');
  arm();
  if (bytes.length === 0) sent();
  else if (split === null) socket.write(bytes, (err) => { if (!err) sent(); });
  else {
    socket.write(bytes.subarray(0, split.offset), (err) => {
      if (err) return;
      after(split.ms, () => {
        if (done) return;
        arm();
        socket.write(bytes.subarray(split.offset), (err2) => { if (!err2) sent(); });
      });
    });
  }
});

socket.on('data', (chunk) => {
  if (done) return;
  say(`(data ${offset} ${ms()} "${chunk.toString('hex')}")`);
  offset += chunk.length;
  arm();
});

// heldReset: whether the kernel still holds a reset for the socket, by one
// read(2) of its fd: ECONNRESET. A FIN reads 0 bytes. Over TLS the fd is the
// TCP socket's, under the TLS one.
function heldReset() {
  try {
    readSync(socket._handle.fd, Buffer.alloc(1));
    return false;
  } catch (err) {
    return err.code === 'ECONNRESET';
  }
}

// A TLS peer that closes before the handshake is done is a refusal: there
// was no connection to end.
socket.on('end', () => {
  if (!connected) finish(`(refused "EOF" ${ms()})`, false);
  else if (heldReset()) finish(`(end reset ${ms()})`, false);
  else finish(`(end eof ${ms()})`, false);
});

socket.on('error', (err) => {
  if (!connected) finish(`(refused "${code(err)}" ${ms()})`, false);
  else if (err.code === 'ECONNRESET') finish(`(end reset ${ms()})`, false);
  else finish(`(end error ${ms()} "${code(err)}")`, false);
});
