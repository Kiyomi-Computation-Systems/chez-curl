// M7's proxy probe: which username bytes libcurl hashed into a Digest
// Proxy-Authorization it sent, read from run.sh's logs alone.
//   node digest-check.mjs LOG...
// For every Digest Proxy-Authorization a proxy logged (a "server: req" line),
// it recomputes the MD5 response, qop=auth, from the header's own realm,
// nonce, nc, cnonce, qop and uri and the request's method, with HA1 over
// each candidate username: the header's bytes as sent, and those bytes
// percent-decoded; and the password server.mjs keeps for the decoded name.
// One line per header: the lane, the case, the username as sent, and which
// candidate reproduces the response ("neither" when none does, as for a
// wrong password).
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

const USERS = [
  [Buffer.from('alice'), Buffer.from('s3cret')],
  [Buffer.from('al@ice'), Buffer.from('p:ss%w')],
  [Buffer.from('élève', 'utf8'), Buffer.from('päss', 'utf8')],
];
const passOf = (u) => { for (const [k, p] of USERS) if (k.equals(u)) return p; return null; };
const md5 = (...parts) => createHash('md5').update(Buffer.concat(parts.map((p) => (Buffer.isBuffer(p) ? p : Buffer.from(p, 'latin1'))))).digest('hex');
// unesc: server.mjs's escapes back to bytes.
const unesc = (s) => Buffer.from(s.replace(/\\x([0-9a-f]{2})|\\r|\\n|\\\\|\\"/g, (m, h) => (h ? String.fromCharCode(parseInt(h, 16)) : m === '\\r' ? '\r' : m === '\\n' ? '\n' : m[1])), 'latin1');
const pctDecode = (b) => Buffer.from(b.toString('latin1').replace(/%([0-9A-Fa-f]{2})/g, (m, h) => String.fromCharCode(parseInt(h, 16))), 'latin1');
const esc = (b) => [...b].map((c) => (c < 0x20 || c > 0x7e || c === 0x22 || c === 0x5c ? `\\x${c.toString(16).padStart(2, '0')}` : String.fromCharCode(c))).join('');

let n = 0;
for (const file of process.argv.slice(2)) {
  for (const line of readFileSync(file, 'latin1').split('\n')) {
    const m = /^\[([^\]]+)\] case (\S+) server: req \S+ #\d+ "(.*)"$/.exec(line);
    if (!m) continue;
    const head = unesc(m[3]).toString('latin1');
    const pa = head.split('\r\n').find((l) => /^proxy-authorization:\s*digest /i.test(l));
    if (!pa) continue;
    const method = head.split(' ')[0];
    const d = {};
    for (const x of pa.replace(/^[^:]*:\s*digest\s+/i, '').matchAll(/([a-z*]+)=("((?:[^"\\]|\\.)*)"|[^,\s]*)/gi)) d[x[1].toLowerCase()] = x[3] !== undefined ? x[3] : x[2];
    const sent = Buffer.from(d.username || '', 'latin1');
    const decoded = pctDecode(sent);
    const pass = passOf(decoded) || passOf(sent);
    const ha2 = md5(`${method}:${d.uri}`);
    const resp = (user) => md5(`${md5(user, ':', d.realm, ':', pass)}:${d.nonce}:${d.nc}:${d.cnonce}:${d.qop}:${ha2}`);
    let by = 'neither';
    if (pass && resp(sent) === d.response) by = 'the bytes as sent';
    else if (pass && !decoded.equals(sent) && resp(decoded) === d.response) by = 'the percent-decoded bytes';
    n++;
    console.log(`${file.split('/').pop()} [${m[1]}] ${m[2]} ${method} username="${esc(sent)}" decoded="${esc(decoded)}" password-known=${!!pass} response-reproduced-by: ${by}`);
  }
}
console.log(`-- ${n} Digest header(s) checked`);
