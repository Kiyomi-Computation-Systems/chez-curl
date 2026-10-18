// tests/wire-probe.mjs: the byte probe (M1 plan, section 5; ADR-0005,
// amended). It knows no HTTP: it sends the bytes it is given and reports every
// byte it receives, so nothing between the origin and a suite normalises
// framing. Node's standard library only, for Node 20 and later (measured on
// 20.10.0 and 24.18.0).
//
//   node tests/wire-probe.mjs [--reset | --half-close] [--deadline MS] HOST PORT HEX IDLE-MS
//
// It connects to HOST:PORT and sends HEX's bytes once (none for an empty
// HEX). HEX is pairs of lower-case hex digits, or @FILE: a file holding
// them, read whole, for bytes too many for one argument. It ends the
// connection itself when IDLE-MS pass with no data, or when the whole run
// reaches --deadline MS, 30000 when not given: a peer that keeps sending
// cannot keep it waiting. On stdout it prints Scheme data, one datum per
// line; each MS is whole milliseconds since it started:
//
//   (connected MS)
//   (data OFFSET MS "HEX")     one per chunk it reads; OFFSET is the chunk's
//                              first byte's place in the stream. Chunk
//                              boundaries are not part of any contract.
//   (end KIND MS)              KIND is eof; reset; timeout, IDLE-MS passed
//                              with no data; or deadline, the run reached
//                              --deadline. On the last two it destroys the
//                              socket
//   (end error MS "CODE")      any other error, with its code
//   (reset-sent MS)            with --reset: once its bytes are handed to the
//                              kernel, it resets the connection
//                              (resetAndDestroy), in place of any end line.
//                              A destroy() reaches the peer as a FIN, never
//                              a reset (measured).
//   (refused "CODE" MS)        the connection failed, in place of all the
//                              lines above
//
// With --half-close it ends its side (a FIN) once its bytes are handed to the
// kernel, and goes on reading. Without it, it never half-closes.
//
// It exits 0 when it ran, and 2 on a usage error, with a message on stderr.

import { readFileSync } from 'node:fs';
import net from 'node:net';
import process from 'node:process';

const started = performance.now();
const ms = () => Math.floor(performance.now() - started);

function usage(problem) {
  process.stderr.write(
    `wire-probe: ${problem}\nusage: node tests/wire-probe.mjs [--reset | --half-close] [--deadline MS] HOST PORT HEX IDLE-MS\n`);
  process.exit(2);
}

// code: an error's code, as a word a Scheme string holds unescaped.
const code = (err) => String((err && err.code) || 'UNKNOWN').replace(/[^A-Za-z0-9_]/g, '_');

const positive = /^[1-9][0-9]*$/;

let args = process.argv.slice(2);
let reset = false;
let halfClose = false;
let deadline = 30000;
for (;;) {
  if (args[0] === '--reset' && !reset) {
    reset = true;
    args = args.slice(1);
  } else if (args[0] === '--half-close' && !halfClose) {
    halfClose = true;
    args = args.slice(1);
  } else if (args[0] === '--deadline') {
    if (args.length < 2 || !positive.test(args[1])) usage('--deadline takes a positive natural, its milliseconds');
    deadline = Number(args[1]);
    args = args.slice(2);
  } else {
    break;
  }
}
if (reset && halfClose) usage('--reset and --half-close cannot both be given');
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
if (!positive.test(idleText)) usage(`IDLE-MS is ${JSON.stringify(idleText)}, not a positive natural`);
const idle = Number(idleText);

const say = (line) => process.stdout.write(`${line}\n`);

let connected = false;
let done = false;
let offset = 0;
let timer = null;

const socket = net.connect({ host, port: Number(portText), allowHalfOpen: true });

// finish: prints LINE, the last, and ends the connection: with a reset when
// RESETTING, else with destroy().
function finish(line, resetting) {
  if (done) return;
  done = true;
  clearTimeout(timer);
  clearTimeout(whole);
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

socket.on('connect', () => {
  connected = true;
  say(`(connected ${ms()})`);
  const bytes = Buffer.from(hex, 'hex');
  arm();
  if (bytes.length === 0) sent();
  else socket.write(bytes, (err) => { if (!err) sent(); });
});

socket.on('data', (chunk) => {
  if (done) return;
  say(`(data ${offset} ${ms()} "${chunk.toString('hex')}")`);
  offset += chunk.length;
  arm();
});

socket.on('end', () => finish(`(end eof ${ms()})`, false));

socket.on('error', (err) => {
  if (!connected) finish(`(refused "${code(err)}" ${ms()})`, false);
  else if (err.code === 'ECONNRESET') finish(`(end reset ${ms()})`, false);
  else finish(`(end error ${ms()} "${code(err)}")`, false);
});
