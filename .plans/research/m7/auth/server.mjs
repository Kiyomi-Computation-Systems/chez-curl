// M7's auth probe server (2026-11-02; the M7 plan's measurements, area auth:
// Basic, Bearer and Digest). Node 20 or later, ESM, the standard library
// only. Modelled on M6's pause probe server (../../m6/pause/server.mjs).
//
//   node server.mjs --selftest
//     checks this file's Digest arithmetic against RFC 2617's and RFC 7616's
//     worked examples, and that a wrong password, a wrong body hash and a
//     wrong hash function each fail it; prints "selftest ok N" and exits 0,
//     or prints each failure and exits 1.
//   node server.mjs PKI
//     serves, with PKI's good.pem and good.key (tests/make-test-pki.sh);
//     writes one line on stdout, "raw=PORT h2=PORT", then serves until
//     stdin ends.
//
// raw  plaintext HTTP/1.1 on node:net: each head parsed from its bytes, so
//      every header is logged byte for byte; keep-alive.
// h2   node:http2's secure server, ALPN h2 alone.
//
// Every request carries tag=TAG in its query. The server keeps each
// request's log lines under its tag; GET /log?tag=TAG on the raw face answers
// them once every request of that tag has ended (bounded at 3 s), then a
// "rounds" line, one bracket per request, and a "count" line. Tags never
// fetched go to stderr as stdin ends.
//
// Route /auth. Its query:
//   ch=basic|digest|both|both-rev|bearer|none|open|redirect
//     the challenge a request without valid credentials gets: a 401 with
//     WWW-Authenticate Basic; Digest; Basic then Digest (two headers);
//     Digest then Basic; Bearer; a 401 with no WWW-Authenticate, always; a
//     200 always (open); a 301 to /auth?ch=open always (redirect).
//   u=, p=  the account, UTF-8 percent-encoded (default user, pass);
//   tok=    the bearer token (default tok123);
//   alg=    the Digest challenge's algorithm token, as given (default MD5),
//           or none to send no algorithm parameter (MD5 is then meant);
//   qop=    auth|auth-int|both ("auth,auth-int")|none (no qop parameter);
//           default auth;
//   userhash=1  the challenge says userhash=true; the username must then be
//           H(user:realm);
//   stale=1  the first valid Digest response of the tag is answered 401 with
//           a new nonce and stale=true, its nonce retired;
//   fixnonce=N  every Digest challenge of this request carries nonce N, not a
//           fresh one;
//   early=1  a request the server would not answer 200 (a 401, or the
//           redirect's 301) is answered as its head
//           arrives, before any body byte is read. raw: the body that follows,
//           if any, is still read and logged; h2: the stream is answered and
//           ended at once, and DATA that follows is counted.
//   after=N  as early=1, but the answer goes out once N body bytes have
//           arrived (M6's early-3xx server's rule, research/m6/slice3/verify/),
//           and the rest of the body is still read and logged.
// An Expect: 100-continue request on raw is answered 100 Continue when its
// head alone would pass, else refused at once without 100 Continue; then the
// next bytes decide: a first byte A to Z begins the next request (the client
// sent no body), any other is the refused request's body, read and logged.
// (A body from the probe is byte i = i mod 251, so it begins with 0x00.)
//
// A request passes only with valid credentials in a scheme its ch offers:
// basic Basic, digest Digest, both and both-rev either, bearer Bearer.
// Verdicts: Basic, the decoded bytes against u:p; Bearer, the token against
// tok; Digest, every parameter against the challenge (realm, nonce issued and
// not retired, uri = the request target, opaque, algorithm echoed, qop
// offered, nc, cnonce, username or its hash) and the response against this
// server's own arithmetic (RFC 7616 section 3.4.1; HA2 of auth-int over the
// body as received). A wrong response is retried against 48 other
// arithmetics, each hash function, -sess or not, the body or an empty one,
// the qop or none, and the account's user or the header's; the first that
// matches is logged as alt=.
//
// Escaping in every log line: printable ASCII as is, but \ as \\ and " as
// \"; every other byte as \xNN, lower case, the probe's own rule.
import { createHash, randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import http2 from 'node:http2';
import net from 'node:net';

const REALM = 'chez-curl-test';
const OPAQUE = 'opq5ccb';
const T0 = performance.now();
const now = () => performance.now();
const ms = (x) => x.toFixed(1);
const sleep = (n) => new Promise((r) => setTimeout(r, n));

function esc(buf) {
  let s = '';
  for (const c of buf) {
    if (c === 0x5c) s += '\\\\';
    else if (c === 0x22) s += '\\"';
    else if (c < 0x20 || c > 0x7e) s += `\\x${c.toString(16).padStart(2, '0')}`;
    else s += String.fromCharCode(c);
  }
  return s;
}
const L1 = (s) => Buffer.from(s, 'latin1');
const cat = (...parts) => Buffer.concat(parts.map((p) => (Buffer.isBuffer(p) ? p : L1(String(p)))));
const H = (name) => (buf) => createHash(name).update(buf).digest('hex');
const HASHES = { md5: 'md5', 'sha-256': 'sha256', 'sha-512-256': 'sha512-256' };

// algOf('SHA-256-sess') -> { base: 'sha256', sess: true }; null if unknown.
function algOf(name) {
  const l = name.toLowerCase();
  const sess = l.endsWith('-sess');
  const b = sess ? l.slice(0, -5) : l;
  return HASHES[b] ? { base: HASHES[b], sess } : null;
}

// RFC 7616 section 3.4.1, with RFC 2069's form when there is no qop.
function digestResponse(hname, sess, user, realm, pass, nonce, cnonce, nc, qop, method, uri, body) {
  const h = H(hname);
  let ha1 = h(cat(user, ':', realm, ':', pass));
  if (sess) ha1 = h(cat(ha1, ':', nonce, ':', cnonce));
  const ha2 = qop === 'auth-int' ? h(cat(method, ':', uri, ':', h(body))) : h(cat(method, ':', uri));
  return qop ? h(cat(ha1, ':', nonce, ':', nc, ':', cnonce, ':', qop, ':', ha2)) : h(cat(ha1, ':', nonce, ':', ha2));
}

// parseParams: a challenge's or credentials' auth-params, after the scheme.
// Values come back as latin1 strings, so each keeps its bytes.
function parseParams(s) {
  const f = {};
  const quoted = [];
  const re = /\s*([A-Za-z0-9_*-]+)\s*=\s*(?:"((?:[^"\\]|\\.)*)"|([^,]*?))\s*(?:,|$)/gy;
  let m;
  let last = 0;
  while (re.lastIndex < s.length && (m = re.exec(s))) {
    const k = m[1].toLowerCase();
    if (m[2] !== undefined) { f[k] = m[2].replace(/\\(.)/g, '$1'); quoted.push(k); } else f[k] = m[3];
    last = re.lastIndex;
  }
  return { f, quoted, trailing: s.slice(last) };
}

// ---------------------------------------------------------------- selftest
function selftest() {
  const fails = [];
  let n = 0;
  const t = (label, got, want) => { n++; if (got !== want) fails.push(`${label}: got ${got}, want ${want}`); };
  // RFC 2617 section 3.5.
  const r2617 = ['md5', false, L1('Mufasa'), 'testrealm@host.com', L1('Circle Of Life'), 'dcd98b7102dd2f0e8b11d0f600bfb0c093',
    '0a4f113b', '00000001', 'auth', 'GET', '/dir/index.html', Buffer.alloc(0)];
  t('rfc2617 md5 auth', digestResponse(...r2617), '6629fae49393a05397450978507c4ef1');
  // RFC 7616 section 3.9.1, MD5 and SHA-256.
  const r7616 = (h) => [h, false, L1('Mufasa'), 'http-auth@example.org', L1('Circle of Life'),
    '7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v', 'f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ', '00000001', 'auth', 'GET',
    '/dir/index.html', Buffer.alloc(0)];
  t('rfc7616 md5 auth', digestResponse(...r7616('md5')), '8ca523f5e9506fed4657c9700eebdbec');
  t('rfc7616 sha-256 auth', digestResponse(...r7616('sha256')), '753927fa0e85d155564e2e272a28d1802ca10daf4496794697cf8db5856cb6c1');
  // RFC 7616 section 3.9.2's SHA-512-256 example is not used: its published
  // values carry an erratum. SHA-512/256 itself, FIPS 180-4's empty-input
  // digest:
  t('sha512-256 of nothing', H('sha512-256')(Buffer.alloc(0)), 'c672b8d1ef56ed28ab87c3622c5114069bdd3ad7b8f9737498d0c01ecef0967a');
  // Controls: each must differ from the good answer.
  const good = digestResponse(...r7616('sha256'));
  const w1 = [...r7616('sha256')]; w1[4] = L1('Circle of life');
  n++; if (digestResponse(...w1) === good) fails.push('wrong password passed');
  const w2 = [...r7616('sha256')]; w2[8] = 'auth-int'; w2[11] = L1('x');
  const w3 = [...r7616('sha256')]; w3[8] = 'auth-int';
  n++; if (digestResponse(...w2) === digestResponse(...w3)) fails.push('auth-int ignored the body');
  n++; if (digestResponse(...r7616('sha512-256')) === good) fails.push('the hash function made no difference');
  const w4 = [...r7616('sha256')]; w4[1] = true;
  n++; if (digestResponse(...w4) === good) fails.push('-sess made no difference');
  // The parser: quoted-pair, unquoted tokens, a comma inside quotes.
  const p = parseParams('username="a\\"b", qop=auth, nc=00000001, uri="/x?a=1,b=2", algorithm=SHA-256');
  t('parse username', p.f.username, 'a"b');
  t('parse qop', p.f.qop, 'auth');
  t('parse uri', p.f.uri, '/x?a=1,b=2');
  t('parse algorithm', p.f.algorithm, 'SHA-256');
  t('esc', esc(Buffer.from([0x41, 0x5c, 0x22, 0x00, 0xc3, 0xbc, 0x7f])), 'A\\\\\\"\\x00\\xc3\\xbc\\x7f');
  if (fails.length) { for (const f of fails) console.log(`selftest FAIL ${f}`); process.exit(1); }
  console.log(`selftest ok ${n}`);
  process.exit(0);
}
if (process.argv[2] === '--selftest') selftest();

// ---------------------------------------------------------------- state
const pki = process.argv[2];
const cert = readFileSync(`${pki}/good.pem`);
const key = readFileSync(`${pki}/good.key`);
const sockets = new Set();
const sessions = new Set();
const track = (s) => { sockets.add(s); s.on('close', () => sockets.delete(s)); s.on('error', () => {}); };

// tags: TAG -> { lines, inflight, fetched, counts, rounds, staleDone }
const tags = new Map();
const tagOf = (t) => {
  let e = tags.get(t);
  if (!e) { e = { lines: [], inflight: 0, fetched: false, counts: new Map(), rounds: [], staleDone: false }; tags.set(t, e); }
  return e;
};
// nonces: NONCE -> { tag, dead, ncs: Set }
const nonces = new Map();

function parseTarget(target) {
  const q = target.indexOf('?');
  return { path: q < 0 ? target : target.slice(0, q), params: new URLSearchParams(q < 0 ? '' : target.slice(q + 1)) };
}

// begin: a request's head has arrived. hs: [[lowercase name, value as a
// latin1 string, the raw line or null]] in arrival order.
function begin(face, method, target, port, hs) {
  const { path, params } = parseTarget(target);
  const tag = params.get('tag') || '-';
  const r = { face, method, target, path, params, tag, hs, port, t0: now(), ended: false };
  if (path === '/log') { r.log = () => {}; r.end = () => {}; return r; }
  const e = tagOf(tag);
  const fk = `${face}:${path}`;
  r.n = (e.counts.get(fk) || 0) + 1;
  e.counts.set(fk, r.n);
  e.inflight++;
  r.entry = e;
  r.log = (line) => e.lines.push(line);
  r.end = () => { if (!r.ended) { r.ended = true; e.inflight--; } };
  r.round = { n: r.n, face, method, conn: port, scheme: 'none', verdict: '-', status: '-', when: '-', body: '-' };
  e.rounds.push(r.round);
  r.body = bodyRec();
  r.log(`req #${r.n} ${face} ${method} "${esc(L1(target))}" conn=${port} at=${ms(r.t0 - T0)}`);
  const want = ['authorization', 'content-length', 'transfer-encoding', 'expect', 'content-type'];
  let auths = 0;
  for (const [name, value, raw] of hs) {
    if (!want.includes(name)) continue;
    if (name === 'authorization') { auths++; r.log(`auth #${r.n} value="${esc(L1(value))}"`); }
    r.log(`hdr #${r.n} "${esc(L1(raw ?? `${name}: ${value}`))}"`);
  }
  if (!auths) r.log(`auth #${r.n} none`);
  if (path !== '/auth') r.log(`no-route #${r.n} ${esc(L1(path))}`);
  return r;
}

function bodyRec() {
  return {
    bytes: 0, chunks: [], hash: createHash('sha256'), bad: -1,
    add(buf) {
      for (let i = 0; i < buf.length && this.bad < 0; i++) if (buf[i] !== (this.bytes + i) % 251) this.bad = this.bytes + i;
      this.bytes += buf.length;
      this.hash.update(buf);
      this.chunks.push(Buffer.from(buf));
    },
    buf() { return Buffer.concat(this.chunks); },
    summary() {
      if (!this.bytes) return '0';
      return `${this.bytes}:pattern=${this.bad < 0 ? 'ok' : `bad@${this.bad}`}:sha=${this.hash.copy().digest('hex').slice(0, 16)}`;
    },
  };
}

// ---------------------------------------------------------------- verdicts
const account = (r) => ({
  user: Buffer.from(r.params.get('u') ?? 'user', 'utf8'),
  pass: Buffer.from(r.params.get('p') ?? 'pass', 'utf8'),
  tok: r.params.get('tok') ?? 'tok123',
});

function verifyDigest(r, value, body) {
  const P = r.params;
  const { user, pass } = account(r);
  const algParam = P.get('alg') || 'MD5';
  const qopParam = P.get('qop') || 'auth';
  const offered = qopParam === 'none' ? [] : qopParam === 'both' ? ['auth', 'auth-int'] : [qopParam];
  const { f, quoted, trailing } = parseParams(value);
  const issues = [];
  const want = algOf(algParam === 'none' ? 'MD5' : algParam);
  const nrec = nonces.get(f.nonce);
  const notes = [];
  if (!nrec) issues.push('nonce-unknown');
  else {
    if (nrec.dead) issues.push('nonce-retired');
    if (nrec.tag !== r.tag) notes.push(`nonce-from=${nrec.tag}`);
    if (nrec.ncs.has(f.nc)) notes.push('nc-repeat');
    nrec.ncs.add(f.nc);
  }
  if (f.realm !== REALM) issues.push('realm');
  if (f.uri !== r.target) issues.push('uri');
  if (f.opaque !== OPAQUE) issues.push('opaque');
  if (algParam !== 'none' && (f.algorithm || '').toLowerCase() !== algParam.toLowerCase()) issues.push('algorithm-echo');
  const uh = P.get('userhash') === '1';
  const uname = L1(f.username ?? '');
  if (uh) {
    if (f.userhash !== 'true') issues.push('userhash-flag');
    if (f.username !== H(want.base)(cat(user, ':', REALM))) issues.push('username-hash');
  } else {
    if (!uname.equals(user)) issues.push('username');
    if (f.userhash !== undefined) notes.push(`userhash=${f.userhash}`);
  }
  if (f['username*'] !== undefined) notes.push(`username*="${esc(L1(f['username*']))}"`);
  if (offered.length) {
    if (!offered.includes(f.qop)) issues.push('qop');
    if (!/^[0-9a-fA-F]{8}$/.test(f.nc || '')) issues.push('nc');
    if (!f.cnonce) issues.push('cnonce');
  } else if (f.qop) issues.push('qop-unoffered');
  const qop = f.qop;
  const expected = digestResponse(want.base, want.sess, user, REALM, pass, f.nonce || '', f.cnonce || '', f.nc || '', qop,
    r.method, f.uri || '', body);
  const respOk = (f.response || '').toLowerCase() === expected;
  let alt = '-';
  if (!respOk) {
    issues.push('response');
    outer: for (const hb of ['md5', 'sha256', 'sha512-256']) {
      for (const sess of [false, true]) {
        for (const [bn, bb] of [['body', body], ['empty-body', Buffer.alloc(0)]]) {
          for (const [qn, qq] of [['qop', qop], ['no-qop', undefined]]) {
            for (const [un, uu] of [['user', user], ['header-user', uname]]) {
              const x = digestResponse(hb, sess, uu, REALM, pass, f.nonce || '', f.cnonce || '', f.nc || '', qq, r.method, f.uri || '', bb);
              if (x === (f.response || '').toLowerCase()) { alt = `${hb}${sess ? '-sess' : ''},${bn},${qn},${un}`; break outer; }
            }
          }
        }
      }
    }
  }
  const sent = Object.keys(f).map((k) => `${k}${quoted.includes(k) ? '(q)' : ''}`).join(',');
  return {
    ok: issues.length === 0, nonce: f.nonce,
    line: `digest #${r.n} ${issues.length ? `bad(${issues.join(',')})` : 'ok'} alg=${f.algorithm ?? '-'} qop=${f.qop ?? '-'} nc=${f.nc ?? '-'} cnonce=${f.cnonce ? 'yes' : 'no'} userhash=${f.userhash ?? '-'} username="${esc(uname)}" uri=${f.uri === r.target ? 'target' : `"${esc(L1(f.uri ?? ''))}"`} alt=${alt} params=${sent}${trailing ? ` trailing="${esc(L1(trailing))}"` : ''}${notes.length ? ` ${notes.join(' ')}` : ''}`,
  };
}

// judge: the request's credentials. Pure but for verifyDigest's nc record
// when final. Answers { scheme, ok, verdict, lines, nonce }.
function judge(r, body, final) {
  const { user, pass, tok } = account(r);
  const auths = r.hs.filter(([n]) => n === 'authorization').map(([, v]) => v);
  if (!auths.length) return { scheme: 'none', ok: false, verdict: '-', lines: [] };
  const v = auths[0];
  const sp = v.indexOf(' ');
  const scheme = sp < 0 ? v : v.slice(0, sp);
  const rest = sp < 0 ? '' : v.slice(sp + 1);
  const lines = [];
  let ok = false;
  let nonce;
  if (auths.length > 1) lines.push(`auth #${r.n} ${auths.length} Authorization headers; the first is judged`);
  if (/^basic$/i.test(scheme)) {
    const b64 = rest.trim();
    const dec = Buffer.from(b64, 'base64');
    const canon = dec.toString('base64') === b64;
    const i = dec.indexOf(0x3a);
    const u = i < 0 ? dec : dec.subarray(0, i);
    const p = i < 0 ? null : dec.subarray(i + 1);
    ok = dec.equals(cat(user, ':', pass));
    lines.push(`basic #${r.n} decoded="${esc(dec)}" user="${esc(u)}" pass=${p === null ? 'none' : `"${esc(p)}"`} canonical=${canon ? 'yes' : 'no'} match=${ok ? 'yes' : 'no'}`);
  } else if (/^bearer$/i.test(scheme)) {
    ok = rest === tok;
    lines.push(`bearer #${r.n} token="${esc(L1(rest))}" match=${ok ? 'yes' : 'no'}`);
  } else if (/^digest$/i.test(scheme)) {
    if (!final) {
      // A head-time look: verify on a copy of the nonce record, so nc is
      // recorded once, by the final judgement.
      const saved = nonces.get(parseParams(rest).f.nonce);
      const ncs = saved ? new Set(saved.ncs) : null;
      const d = verifyDigest(r, rest, body);
      if (saved) saved.ncs = ncs;
      ok = d.ok; nonce = d.nonce; lines.push(d.line);
    } else {
      const d = verifyDigest(r, rest, body);
      ok = d.ok; nonce = d.nonce; lines.push(d.line);
    }
  } else lines.push(`other #${r.n} scheme="${esc(L1(scheme))}"`);
  return { scheme: scheme.toLowerCase(), ok, verdict: ok ? 'ok' : 'bad', lines, nonce };
}

function digestChallenge(r, stale) {
  const P = r.params;
  const nonce = P.get('fixnonce') || randomBytes(16).toString('hex');
  if (!nonces.has(nonce)) nonces.set(nonce, { tag: r.tag, dead: false, ncs: new Set() });
  const parts = [`realm="${REALM}"`];
  const qop = P.get('qop') || 'auth';
  if (qop === 'both') parts.push('qop="auth,auth-int"');
  else if (qop !== 'none') parts.push(`qop="${qop}"`);
  parts.push(`nonce="${nonce}"`, `opaque="${OPAQUE}"`);
  const alg = P.get('alg') || 'MD5';
  if (alg !== 'none') parts.push(`algorithm=${alg}`);
  if (stale) parts.push('stale=true');
  if (P.get('userhash') === '1') parts.push('userhash=true');
  return `Digest ${parts.join(', ')}`;
}

function challenges(r, stale) {
  const basic = `Basic realm="${REALM}"`;
  switch (r.params.get('ch')) {
    case 'basic': return [basic];
    case 'digest': return [digestChallenge(r, stale)];
    case 'both': return [basic, digestChallenge(r, stale)];
    case 'both-rev': return [digestChallenge(r, stale), basic];
    case 'bearer': return [`Bearer realm="${REALM}"`];
    default: return [];
  }
}

// decide: the answer to a judged request. final: the answer goes out now,
// so a stale=1 tag spends its one stale answer.
function decide(r, j, final) {
  const ch = r.params.get('ch');
  if (r.path !== '/auth') return { status: 404, www: [], extra: [] };
  if (ch === 'open') return { status: 200, www: [], extra: [] };
  if (ch === 'redirect') return { status: 301, www: [], extra: [['Location', `/auth?ch=open&tag=${encodeURIComponent(r.tag)}.next`]] };
  if (ch === 'none') return { status: 401, www: [], extra: [] };
  const accepts = { basic: ['basic'], digest: ['digest'], both: ['basic', 'digest'], 'both-rev': ['basic', 'digest'], bearer: ['bearer'] }[ch] || [];
  if (j.ok && !accepts.includes(j.scheme)) {
    return { status: 401, www: challenges(r, false), extra: [], note: `scheme: valid ${j.scheme} credentials refused, since ch=${ch} offers ${accepts.join(' and ') || 'none'}` };
  }
  if (j.ok) {
    if (r.params.get('stale') === '1' && j.scheme === 'digest' && !r.entry.staleDone) {
      if (!final) return { status: 401, pending: true };
      r.entry.staleDone = true;
      const rec = nonces.get(j.nonce);
      if (rec) rec.dead = true;
      return { status: 401, www: challenges(r, true), extra: [], note: 'stale: a valid response answered 401 stale=true, its nonce retired' };
    }
    return { status: 200, www: [], extra: [] };
  }
  return { status: 401, www: challenges(r, false), extra: [] };
}

const REASON = { 200: 'OK', 301: 'Moved Permanently', 401: 'Unauthorized', 404: 'Not Found' };

function logAnswer(r, j, d, when) {
  for (const l of j.lines) r.log(l);
  if (d.note) r.log(`${d.note} #${r.n}`);
  r.log(`answer #${r.n} status=${d.status} ${when} www=[${d.www.map((w) => `"${esc(L1(w))}"`).join(',')}]${d.extra.map(([k, v]) => ` ${k}="${esc(L1(v))}"`).join('')}`);
  r.round.scheme = j.scheme;
  r.round.verdict = j.verdict;
  r.round.status = String(d.status);
  r.round.when = when.startsWith('as') ? 'early' : when.startsWith('once') ? 'mid' : 'after-body';
}

// ---------------------------------------------------------------- HTTP/1.1
function serveH1(sock) {
  const conn = { sock, buf: Buffer.alloc(0), req: null, dead: false, port: sock.remotePort };
  sock.on('data', (chunk) => { conn.buf = conn.buf.length ? Buffer.concat([conn.buf, chunk]) : chunk; pump(conn); });
  sock.on('close', () => {
    if (conn.req) {
      const q = conn.req;
      q.r.log(`closed #${q.r.n} ${q.answered ? 'after its early answer' : 'before any answer'}: the client closed the connection with ${q.r.body.bytes} body bytes read of ${q.framing === 'length' ? q.need : q.framing}`);
      q.r.round.body = `${q.r.body.summary()}(closed)`;
      q.r.end();
      conn.req = null;
    }
  });
}

function writeH1(conn, d) {
  const body = d.status === 200 ? 'ok\n' : `status ${d.status}\n`;
  let head = `HTTP/1.1 ${d.status} ${REASON[d.status] || 'Status'}\r\n`;
  for (const w of d.www) head += `WWW-Authenticate: ${w}\r\n`;
  for (const [k, v] of d.extra) head += `${k}: ${v}\r\n`;
  head += `Content-Length: ${body.length}\r\n\r\n${body}`;
  conn.sock.write(L1(head));
}

function pump(conn) {
  for (;;) {
    if (conn.dead) return;
    if (!conn.req) {
      const end = conn.buf.indexOf('\r\n\r\n');
      if (end < 0) return;
      const head = conn.buf.toString('latin1', 0, end);
      conn.buf = conn.buf.subarray(end + 4);
      const lines = head.split('\r\n');
      const [method, target] = lines[0].split(' ');
      const hs = [];
      const h = {};
      for (const l of lines.slice(1)) {
        const i = l.indexOf(':');
        if (i < 0) continue;
        const name = l.slice(0, i).trim().toLowerCase();
        const v = l.slice(i + 1).replace(/^[ \t]+/, '');
        hs.push([name, v, l]);
        h[name] = h[name] == null ? v.trim() : `${h[name]},${v.trim()}`;
      }
      const r = begin('raw', method, target, conn.port, hs);
      if (r.path === '/log') { conn.dead = true; answerLog(r.params).then((b) => conn.sock.end(`HTTP/1.1 200 OK\r\nContent-Length: ${Buffer.byteLength(b)}\r\nConnection: close\r\n\r\n${b}`)); return; }
      const q = { r, framing: 'none', need: 0, cstate: 'size', cleft: 0, answered: false, after401: false };
      if (/chunked/i.test(h['transfer-encoding'] || '')) q.framing = 'chunked';
      else if (h['content-length'] != null) { q.framing = 'length'; q.need = Number(h['content-length']); }
      conn.req = q;
      const pre = judge(r, Buffer.alloc(0), false);
      const pd = decide(r, pre, false);
      const pass = pd.status === 200;
      const expect = /100-continue/i.test(h.expect || '');
      const hasBody = q.framing === 'chunked' || q.need > 0;
      if (r.params.get('after') && !pass) q.answerAt = Number(r.params.get('after'));
      if (r.params.get('early') === '1' && !pass) {
        const d = decide(r, judge(r, Buffer.alloc(0), true), true);
        logAnswer(r, pre, d, 'as the head arrived');
        writeH1(conn, d);
        q.answered = true;
      } else if (expect && hasBody) {
        if (pass) { conn.sock.write('HTTP/1.1 100 Continue\r\n\r\n'); r.log(`continue #${r.n} sent 100 Continue for Expect: ${esc(L1(h.expect))}`); }
        else {
          const d = decide(r, judge(r, Buffer.alloc(0), true), true);
          logAnswer(r, pre, d, 'as the head arrived, without 100 Continue');
          writeH1(conn, d);
          q.answered = true;
          q.after401 = true;
        }
      }
    }
    const q = conn.req;
    if (q.after401 && q.r.body.bytes === 0) {
      if (conn.buf.length === 0) return;
      const c = conn.buf[0];
      q.after401 = false;
      if (c >= 0x41 && c <= 0x5a) {
        q.r.log(`after-refusal #${q.r.n}: the next bytes begin a request, so the client sent no body`);
        q.r.round.body = 'none-sent';
        q.r.end();
        conn.req = null;
        continue;
      }
      q.r.log(`after-refusal #${q.r.n}: the client sent the body anyway`);
    }
    const t = now();
    let complete = false;
    const before = q.r.body.bytes;
    if (q.framing === 'none') complete = true;
    else if (q.framing === 'length') {
      const k = Math.min(q.need - q.r.body.bytes, conn.buf.length);
      if (k > 0) { q.r.body.add(conn.buf.subarray(0, k)); conn.buf = conn.buf.subarray(k); }
      complete = q.r.body.bytes >= q.need;
    } else {
      for (;;) {
        if (q.cstate === 'size') {
          const i = conn.buf.indexOf('\r\n');
          if (i < 0) break;
          const n = parseInt(conn.buf.toString('latin1', 0, i).split(';')[0], 16);
          conn.buf = conn.buf.subarray(i + 2);
          if (n === 0) q.cstate = 'trailer'; else { q.cleft = n; q.cstate = 'data'; }
        } else if (q.cstate === 'data') {
          const k = Math.min(q.cleft, conn.buf.length);
          if (k === 0) break;
          q.r.body.add(conn.buf.subarray(0, k));
          conn.buf = conn.buf.subarray(k);
          q.cleft -= k;
          if (q.cleft === 0) q.cstate = 'crlf';
        } else if (q.cstate === 'crlf') {
          if (conn.buf.length < 2) break;
          conn.buf = conn.buf.subarray(2);
          q.cstate = 'size';
        } else {
          const i = conn.buf.indexOf('\r\n');
          if (i < 0) break;
          conn.buf = conn.buf.subarray(i + 2);
          if (i === 0) { complete = true; break; }
        }
      }
    }
    if (q.r.body.bytes > before && !q.firstAt) q.firstAt = t - q.r.t0;
    if (q.answerAt && !q.answered && q.r.body.bytes >= q.answerAt) {
      const d = decide(q.r, judge(q.r, Buffer.alloc(0), true), true);
      logAnswer(q.r, judge(q.r, Buffer.alloc(0), false), d, `once ${q.r.body.bytes} body bytes had arrived`);
      writeH1(conn, d);
      q.answered = true;
    }
    if (!complete) return;
    const r = q.r;
    conn.req = null;
    if (q.answered) {
      r.log(`body #${r.n} after the early answer: ${r.body.summary()}, whole at ${ms(now() - r.t0)}ms`);
      r.round.body = r.body.summary();
      r.end();
      continue;
    }
    const body = r.body.buf();
    if (r.body.bytes) r.log(`body #${r.n} ${r.body.summary()} first_at=${ms(q.firstAt ?? 0)}ms whole_at=${ms(now() - r.t0)}ms`);
    r.round.body = r.body.summary();
    const j = judge(r, body, true);
    const d = decide(r, j, true);
    logAnswer(r, j, d, 'after the body');
    writeH1(conn, d);
    r.end();
  }
}

// ---------------------------------------------------------------- HTTP/2
function serveH2(stream, headers) {
  stream.on('error', () => {});
  const port = stream.session.socket.remotePort;
  const hs = [];
  for (const [k, v] of Object.entries(headers)) {
    if (k.startsWith(':')) continue;
    for (const one of Array.isArray(v) ? v : [v]) hs.push([k, String(one), null]);
  }
  const r = begin('h2', headers[':method'], headers[':path'], port, hs);
  const q = { answered: false };
  const respond = (d) => {
    const body = d.status === 200 ? 'ok\n' : `status ${d.status}\n`;
    const h = { ':status': d.status, 'content-length': String(body.length) };
    if (d.www.length) h['www-authenticate'] = d.www;
    for (const [k, v] of d.extra) h[k.toLowerCase()] = v;
    stream.respond(h);
    stream.end(body);
  };
  if (r.path === '/log') {
    answerLog(r.params).then((b) => { stream.respond({ ':status': 200 }); stream.end(b); });
    return;
  }
  const pre = judge(r, Buffer.alloc(0), false);
  if (r.params.get('early') === '1' && decide(r, pre, false).status !== 200) {
    const d = decide(r, judge(r, Buffer.alloc(0), true), true);
    logAnswer(r, pre, d, 'as the headers arrived');
    respond(d);
    q.answered = true;
  }
  const answerAt = r.params.get('after') && decide(r, pre, false).status !== 200 ? Number(r.params.get('after')) : 0;
  let firstAt = null;
  stream.on('data', (chunk) => {
    if (firstAt === null) firstAt = now() - r.t0;
    r.body.add(chunk);
    if (answerAt && !q.answered && r.body.bytes >= answerAt) {
      const d = decide(r, judge(r, Buffer.alloc(0), true), true);
      logAnswer(r, pre, d, `once ${r.body.bytes} body bytes had arrived`);
      respond(d);
      q.answered = true;
    }
  });
  stream.on('end', () => {
    if (q.answered) {
      r.log(`body #${r.n} after the early answer: ${r.body.summary()}, the client ended its side at ${ms(now() - r.t0)}ms`);
      r.round.body = r.body.summary();
      r.end();
      return;
    }
    if (r.body.bytes) r.log(`body #${r.n} ${r.body.summary()} first_at=${ms(firstAt ?? 0)}ms whole_at=${ms(now() - r.t0)}ms`);
    r.round.body = r.body.summary();
    const j = judge(r, r.body.buf(), true);
    const d = decide(r, j, true);
    logAnswer(r, j, d, 'after the body');
    respond(d);
    r.end();
  });
  stream.on('close', () => {
    if (!r.ended) {
      r.log(`closed #${r.n} ${q.answered ? 'after its early answer' : 'before any answer'}: the stream closed, rst_code=${stream.rstCode}, with ${r.body.bytes} body bytes read, at ${ms(now() - r.t0)}ms`);
      r.round.body = `${r.body.summary()}(closed)`;
      r.end();
    }
  });
}

// ---------------------------------------------------------------- the log
async function answerLog(params) {
  const tag = params.get('tag') || '-';
  const e = tagOf(tag);
  const t = now();
  while (e.inflight > 0 && now() - t < 3000) await sleep(5);
  e.fetched = true;
  const lines = [...e.lines];
  if (e.inflight > 0) lines.push(`log: ${e.inflight} request(s) of this tag still open after 3 s`);
  lines.push(`rounds n=${e.rounds.length} ${e.rounds.map((x) => `[#${x.n} ${x.face} ${x.method} conn=${x.conn} auth=${x.scheme}:${x.verdict} status=${x.status} ${x.when} body=${x.body}]`).join(' ') || '-'}`);
  const cs = [...e.counts].map(([k, v]) => `${k}=${v}`).join(' ');
  lines.push(`count ${cs || 'none'}`);
  return lines.join('\n') + '\n';
}

const raw = net.createServer((tcp) => { track(tcp); serveH1(tcp); });
const h2server = http2.createSecureServer({ cert, key, ALPNProtocols: ['h2'], allowHTTP1: false });
h2server.on('connection', (tcp) => track(tcp));
h2server.on('tlsClientError', () => {});
h2server.on('session', (s) => { sessions.add(s); s.on('close', () => sessions.delete(s)); s.on('error', () => {}); });
h2server.on('stream', serveH2);

const listen = (server) => new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port)));
const ports = [await listen(raw), await listen(h2server)];
process.stdout.write(`raw=${ports[0]} h2=${ports[1]}\n`);
process.stdin.on('data', () => {});
process.stdin.on('end', () => {
  for (const [tag, e] of tags) {
    if (e.fetched || tag === '-') continue;
    const cs = [...e.counts].map(([k, v]) => `${k}=${v}`).join(' ');
    process.stderr.write(`unfetched tag=${tag} count ${cs}\n`);
  }
  for (const s of sessions) s.destroy();
  for (const s of sockets) s.destroy();
  raw.close();
  h2server.close();
  process.exit(0);
});
