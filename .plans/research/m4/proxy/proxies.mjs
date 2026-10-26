// The M4 plan's proxy measurement: two plain HTTP listeners on 127.0.0.1.
//
//   node proxies.mjs LOG
//
// The origin answers every request 200 "origin". The proxy answers every
// request 299 "proxy", and every CONNECT 403, and appends one line per
// request to LOG: its method and target. It announces one JSON line,
// {"origin":PORT,"proxy":PORT}, and exits 0 when its stdin ends.
import http from 'node:http';
import fs from 'node:fs';

const log = process.argv[2];
if (!log) {
  process.stderr.write('usage: node proxies.mjs LOG\n');
  process.exit(2);
}
const answer = (status, text) => (req, res) => {
  res.writeHead(status, { 'Content-Type': 'text/plain', 'Content-Length': text.length, Connection: 'close' });
  res.end(text);
};
const origin = http.createServer(answer(200, 'origin'));
const proxy = http.createServer((req, res) => {
  fs.appendFileSync(log, `${req.method} ${req.url}\n`);
  answer(299, 'proxy')(req, res);
});
proxy.on('connect', (req, socket) => {
  fs.appendFileSync(log, `CONNECT ${req.url}\n`);
  socket.end('HTTP/1.1 403 Probe\r\nContent-Length: 0\r\n\r\n');
});
const listen = (server) => new Promise((done) => server.listen(0, '127.0.0.1', () => done(server.address().port)));
const ports = { origin: await listen(origin), proxy: await listen(proxy) };
process.stdout.write(`${JSON.stringify(ports)}\n`);
process.stdin.on('data', () => {});
process.stdin.on('end', () => {
  origin.close();
  proxy.close();
  origin.closeAllConnections();
  proxy.closeAllConnections();
  process.exit(0);
});
