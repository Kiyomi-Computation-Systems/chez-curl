// M7 slice 2's stand-in (2026-11-02; the M7 plan, section 5.1): an auth
// origin for measurements through chez-curl's engine. Node 20 or later, ESM,
// the standard library only. Adapted from ../auth/server.mjs: its Digest
// arithmetic, its self-test and its parsers are that file's, unchanged.
//
//   node standin.mjs --selftest
//     checks the Digest arithmetic against RFC 2617's and RFC 7616's worked
//     examples, and that a wrong password, a wrong body hash, the hash
//     function and -sess each change the answer; prints "selftest ok N" and
//     exits 0, or prints each failure and exits 1.
//   node standin.mjs PKI
//     serves with PKI's good.pem and good.key (tests/make-test-pki.sh, whose
//     names are localhost, 127.0.0.1 and ::1); writes one line on stdout,
//     {"http":"P1","httpb":"P2","https":"P3","h2":"P4","ctl":"P5"}, the
//     ports, then serves until stdin ends.
//
// Faces, each on 127.0.0.1 and on ::1 at the same port but ctl:
//   http   HTTP/1.1 from bytes, plaintext; a connection whose first byte is
//          0x16 is TLS instead (ALPN http/1.1 alone), so http:// and https://
//          share one host and port. Logged as face http or http+tls.
//   httpb  HTTP/1.1 from bytes, plaintext: another port.
//   https  HTTP/1.1 from bytes over TLS, ALPN http/1.1 alone.
//   h2     node:http2 over TLS, ALPN h2 alone, header lists to 16 MiB.
//   ctl    plaintext, 127.0.0.1: GET /log?tag=TAG answers TAG's log once
//          every request of it has ended, bounded at 3 s.
// Every face numbers its connections from 1: a plaintext face each TCP
// connection, a TLS face each completed handshake, h2 each session. A
// request's log names its face, that number (conn=K) and its peer's address.
//
// Every request carries tag=TAG in its query; its log lines are kept under
// TAG, its requests numbered #1, #2 ... across faces in arrival order.
//
// Route /auth, and any path below it (/auth/next). Its query:
//   ch=basic|digest|both|both-rev|bearer|none|open
//     the challenge a request without valid credentials gets: a 401 with
//     WWW-Authenticate Basic; Digest; Basic then Digest; Digest then Basic;
//     Bearer; a 401 with no WWW-Authenticate, always; or a 200 always.
//   The account, the bytes a request must carry:
//     uh=HEX, ph=HEX, th=HEX  the user, password and token as hex bytes;
//     u=, p=, tok=            the same as UTF-8 (defaults user, pass, tok123);
//     plen=N, tlen=N          a password, a token, of N bytes, byte i being
//                             a to z, i mod 26.
//   alg=, qop=, userhash=1, fixnonce=N  the Digest challenge, as in
//     ../auth/server.mjs: alg the algorithm token (MD5 by default; none for no
//     parameter), qop auth|auth-int|both|none (auth by default).
//   stale=N  the first N valid requests of the tag are answered 401 again:
//     Digest with a new nonce and stale=true, its nonce retired; Basic and
//     Bearer with the route's challenge.
//   go=URL   a request that would be answered 200 is answered gostatus
//     (302 by default) with Location: URL, as given.
//   size=N   a 200's body is N bytes, byte i = i mod 251 (default "ok\n").
//   slow=MS  a 200's head goes out at once, its body MS ms later.
//   early=1  a request that would not be answered 200 is answered as its
//     head arrives; a body that follows is still read and logged.
//   after=N  as early=1, once N body bytes have arrived.
//   expect=417  a request whose Expect holds 100-continue, in any case, is
//     answered 417 as its head arrives, before anything else is judged;
//     expect=417once, the tag's first such request alone.
// Without expect=417, an Expect: 100-continue request with a body is
// answered 100 Continue on HTTP/1.1 when its head alone would pass, else
// refused at once without one. After a refusal at the head, the next bytes
// decide: a first byte A to Z begins the next request (no body was sent),
// any other is the refused request's body, read and logged. (A body from
// the program is byte i = i mod 251, so it begins with 0x00.)
//
// The log of each request: "req" (face, conn, peer, method, target);
// "names" (every header's name, in order: a header of the client's own
// making shows here); "head" (the raw head after the request line, bytes
// escaped; for h2 each header as "name: value" joined by \r\n); "auth" (each
// Authorization value whole, or "none"); "hdr" (Content-Length,
// Transfer-Encoding, Expect); the verdict ("basic", "bearer", "digest");
// "body" (length, pattern, SHA-256); "answer" (status, when, challenges,
// Location). A value or head over 4096 bytes is logged as its length,
// SHA-256 and first 64 bytes. Last, "rounds": one bracket per request. A
// tag's first 40 requests are logged so; past them, each is counted alone,
// and "rounds" ends with "more=K" and the last request's bracket.
//
// Escaping in every log line: printable ASCII as is, but \ as \\ and " as
// \"; every other byte as \xNN, lower case.
import { createHash, randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import http2 from 'node:http2';
import net from 'node:net';
import tls from 'node:tls';
import { Duplex } from 'node:stream';

const REALM = 'chez-curl-test';
const OPAQUE = 'opq5ccb';
const T0 = performance.now();
const now = () => performance.now();
const ms = (x) => x.toFixed(1);
const sleep = (n) => new Promise((r) => setTimeout(r, n));
const LIMIT = 4096;

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
const sha = (buf) => createHash('sha256').update(buf).digest('hex');
const HASHES = { md5: 'md5', 'sha-256': 'sha256', 'sha-512-256': 'sha512-256' };
// shown: BUF escaped whole, or past LIMIT bytes its length, SHA-256 and head.
const shown = (buf) => (buf.length <= LIMIT ? `"${esc(buf)}"` : `len=${buf.length}:sha=${sha(buf).slice(0, 16)}:head="${esc(buf.subarray(0, 64))}"`);

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
const h1ctx = tls.createSecureContext({ cert, key });
const sockets = new Set();
const sessions = new Set();
const track = (s) => { sockets.add(s); s.on('close', () => sockets.delete(s)); s.on('error', () => {}); };
const conns = { http: 0, httpb: 0, https: 0, h2: 0 };

// tags: TAG -> { lines, inflight, fetched, n, rounds, staleLeft }
const tags = new Map();
const tagOf = (t) => {
  let e = tags.get(t);
  if (!e) { e = { lines: [], inflight: 0, fetched: false, n: 0, rounds: [], staleUsed: 0 }; tags.set(t, e); }
  return e;
};
// nonces: NONCE -> { tag, dead, ncs: Set }
const nonces = new Map();

function parseTarget(target) {
  const q = target.indexOf('?');
  return { path: q < 0 ? target : target.slice(0, q), params: new URLSearchParams(q < 0 ? '' : target.slice(q + 1)) };
}

// begin: a request's head has arrived. hs: [[lowercase name, value as a
// latin1 string, the raw line]] in arrival order; head, the raw head's bytes
// after the request line.
function begin(face, conn, method, target, hs, head) {
  const { path, params } = parseTarget(target);
  const tag = params.get('tag') || '-';
  const r = { face, conn, method, target, path, params, tag, hs, t0: now(), ended: false };
  const e = tagOf(tag);
  r.n = ++e.n;
  e.inflight++;
  r.entry = e;
  const detail = r.n <= 40;
  r.log = detail ? (line) => e.lines.push(line) : () => {};
  r.end = () => { if (!r.ended) { r.ended = true; e.inflight--; } };
  r.round = { n: r.n, face, method, conn: conn.k, scheme: 'none', verdict: '-', status: '-', when: '-', body: '-', auths: 0 };
  if (detail) e.rounds.push(r.round); else { e.more = (e.more || 0) + 1; e.lastRound = r.round; }
  r.body = bodyRec();
  r.log(`req #${r.n} face=${face} conn=${conn.k} peer=${conn.peer} method=${method} target="${esc(L1(target))}" at=${ms(r.t0 - T0)}`);
  r.log(`names #${r.n} ${hs.map(([n]) => esc(L1(n || '(no-colon)'))).join(',') || '-'}`);
  r.log(`head #${r.n} ${shown(head)}`);
  let auths = 0;
  for (const [name, value, raw] of hs) {
    if (name === 'authorization') { auths++; r.log(`auth #${r.n} value=${shown(L1(value))}`); }
    if (['content-length', 'transfer-encoding', 'expect'].includes(name)) r.log(`hdr #${r.n} "${esc(L1(raw))}"`);
  }
  r.round.auths = auths;
  if (!auths) r.log(`auth #${r.n} none`);
  if (!isRoute(path)) r.log(`no-route #${r.n} ${esc(L1(path))}`);
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
const pattern26 = (n) => { const b = Buffer.alloc(n); for (let i = 0; i < n; i++) b[i] = 0x61 + (i % 26); return b; };
function account(r) {
  const P = r.params;
  const hex = (k) => (P.has(k) ? Buffer.from(P.get(k), 'hex') : null);
  return {
    user: hex('uh') ?? Buffer.from(P.get('u') ?? 'user', 'utf8'),
    pass: hex('ph') ?? (P.has('plen') ? pattern26(Number(P.get('plen'))) : Buffer.from(P.get('p') ?? 'pass', 'utf8')),
    tok: hex('th') ?? (P.has('tlen') ? pattern26(Number(P.get('tlen'))) : Buffer.from(P.get('tok') ?? 'tok123', 'utf8')),
  };
}

function verifyDigest(r, value, body) {
  const P = r.params;
  const { user, pass } = account(r);
  const algParam = P.get('alg') || 'MD5';
  const qopParam = P.get('qop') || 'auth';
  const offered = qopParam === 'none' ? [] : qopParam === 'both' ? ['auth', 'auth-int'] : [qopParam];
  const { f, quoted, trailing } = parseParams(value);
  const issues = [];
  const want = algOf(algParam === 'none' ? 'MD5' : algParam) || algOf('MD5');
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
    line: `digest #${r.n} ${issues.length ? `bad(${issues.join(',')})` : 'ok'} alg=${f.algorithm ?? '-'} qop=${f.qop ?? '-'} nc=${f.nc ?? '-'} cnonce=${f.cnonce ? 'yes' : 'no'} userhash=${f.userhash ?? '-'} username=${shown(uname)} uri=${f.uri === r.target ? 'target' : `"${esc(L1(f.uri ?? ''))}"`} alt=${alt} params=${sent}${trailing ? ` trailing="${esc(L1(trailing))}"` : ''}${notes.length ? ` ${notes.join(' ')}` : ''}`,
  };
}

// judge: the request's credentials, its first Authorization. final: the
// judgement whose Digest nc is recorded. Answers { scheme, ok, verdict,
// lines, nonce }.
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
    lines.push(`basic #${r.n} decoded=${shown(dec)} user=${shown(u)} pass=${p === null ? 'none' : shown(p)} canonical=${canon ? 'yes' : 'no'} match=${ok ? 'yes' : 'no'}`);
  } else if (/^bearer$/i.test(scheme)) {
    ok = L1(rest).equals(tok);
    lines.push(`bearer #${r.n} token=${shown(L1(rest))} match=${ok ? 'yes' : 'no'}`);
  } else if (/^digest$/i.test(scheme)) {
    if (!final) {
      const saved = nonces.get(parseParams(rest).f.nonce);
      const ncs = saved ? new Set(saved.ncs) : null;
      const d = verifyDigest(r, rest, body);
      if (saved) saved.ncs = ncs;
      ok = d.ok; nonce = d.nonce; lines.push(d.line);
    } else {
      const d = verifyDigest(r, rest, body);
      ok = d.ok; nonce = d.nonce; lines.push(d.line);
    }
  } else lines.push(`other #${r.n} scheme="${esc(L1(scheme))}" value=${shown(L1(v))}`);
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

// passed: the answer to a request that passes: 200, or the go= redirect.
function passed(r) {
  const go = r.params.get('go');
  if (go) return { status: Number(r.params.get('gostatus') || 302), www: [], extra: [['Location', go]] };
  return { status: 200, www: [], extra: [], size: r.params.has('size') ? Number(r.params.get('size')) : null, slow: Number(r.params.get('slow') || 0) };
}

// decide: the answer to a judged request. final: the answer goes out now,
// so a stale tag spends one of its stale answers.
function decide(r, j, final) {
  const ch = r.params.get('ch');
  if (!isRoute(r.path)) return { status: 404, www: [], extra: [] };
  if (ch === 'open') return passed(r);
  if (ch === 'none') return { status: 401, www: [], extra: [] };
  const accepts = { basic: ['basic'], digest: ['digest'], both: ['basic', 'digest'], 'both-rev': ['basic', 'digest'], bearer: ['bearer'] }[ch] || [];
  if (j.ok && !accepts.includes(j.scheme)) {
    return { status: 401, www: challenges(r, false), extra: [], note: `scheme: valid ${j.scheme} credentials refused, since ch=${ch} offers ${accepts.join(' and ') || 'none'}` };
  }
  if (j.ok) {
    const staleN = Number(r.params.get('stale') || 0);
    if (r.entry.staleUsed < staleN) {
      if (!final) return { status: 401, pending: true, www: [], extra: [] };
      r.entry.staleUsed++;
      if (j.scheme === 'digest') {
        const rec = nonces.get(j.nonce);
        if (rec) rec.dead = true;
        return { status: 401, www: challenges(r, true), extra: [], note: `stale: a valid response answered 401 stale=true (${r.entry.staleUsed} of ${staleN}), its nonce retired` };
      }
      return { status: 401, www: challenges(r, false), extra: [], note: `stale: valid ${j.scheme} credentials answered 401 again (${r.entry.staleUsed} of ${staleN})` };
    }
    return passed(r);
  }
  return { status: 401, www: challenges(r, false), extra: [] };
}

const REASON = { 200: 'OK', 301: 'Moved Permanently', 302: 'Found', 303: 'See Other', 307: 'Temporary Redirect', 401: 'Unauthorized', 404: 'Not Found', 417: 'Expectation Failed' };
const bodyOf = (d) => {
  if (d.status === 200 && d.size != null) { const b = Buffer.alloc(d.size); for (let i = 0; i < d.size; i++) b[i] = i % 251; return b; }
  return L1(d.status === 200 ? 'ok\n' : `status ${d.status}\n`);
};

function logAnswer(r, j, d, when) {
  for (const l of j.lines) r.log(l);
  if (d.note) r.log(`${d.note} #${r.n}`);
  r.log(`answer #${r.n} status=${d.status} ${when} www=[${d.www.map((w) => `"${esc(L1(w))}"`).join(',')}]${d.extra.map(([k, v]) => ` ${k}="${esc(L1(v))}"`).join('')}${d.size != null ? ` size=${d.size}` : ''}${d.slow ? ` slow=${d.slow}` : ''}`);
  r.round.scheme = j.scheme;
  r.round.verdict = j.verdict;
  r.round.status = String(d.status);
  r.round.when = when.startsWith('as') ? 'early' : when.startsWith('once') ? 'mid' : 'after-body';
}

const isRoute = (path) => path === '/auth' || path.startsWith('/auth/');
// refuses417: whether R, whose Expect holds 100-continue, is answered 417.
const refuses417 = (r) => {
  const m = r.params.get('expect');
  if (m === '417') return true;
  if (m === '417once' && !r.entry.refused417) { r.entry.refused417 = true; return true; }
  return false;
};
const expect417 = (r) => ({ status: 417, www: [], extra: [], note: 'expect: Expect 100-continue answered 417 at the head' });
const holdsContinue = (v) => /100-continue/i.test(v || '');

// ---------------------------------------------------------------- HTTP/1.1
function serveH1(sock, face, k, peer) {
  const conn = { sock, face, k, peer, buf: Buffer.alloc(0), req: null, dead: false };
  sock.on('data', (chunk) => { conn.buf = conn.buf.length ? Buffer.concat([conn.buf, chunk]) : chunk; pump(conn); });
  sock.on('error', () => {});
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
  const body = bodyOf(d);
  let head = `HTTP/1.1 ${d.status} ${REASON[d.status] || 'Status'}\r\n`;
  for (const w of d.www) head += `WWW-Authenticate: ${w}\r\n`;
  for (const [k, v] of d.extra) head += `${k}: ${v}\r\n`;
  head += `Content-Length: ${body.length}\r\n\r\n`;
  if (d.slow) {
    conn.sock.write(L1(head));
    setTimeout(() => { if (!conn.sock.destroyed) conn.sock.write(body); }, d.slow);
  } else conn.sock.write(Buffer.concat([L1(head), body]));
}

function pump(conn) {
  for (;;) {
    if (conn.dead) return;
    if (!conn.req) {
      const end = conn.buf.indexOf('\r\n\r\n');
      if (end < 0) return;
      const headBytes = conn.buf.subarray(0, end);
      conn.buf = conn.buf.subarray(end + 4);
      const nl = headBytes.indexOf('\r\n');
      const first = (nl < 0 ? headBytes : headBytes.subarray(0, nl)).toString('latin1');
      const rest = nl < 0 ? Buffer.alloc(0) : headBytes.subarray(nl + 2);
      const [method, target] = first.split(' ');
      const hs = [];
      const h = {};
      for (const l of rest.toString('latin1').split('\r\n')) {
        if (!l.length) continue;
        const i = l.indexOf(':');
        if (i < 0) { hs.push(['', '', l]); continue; }
        const name = l.slice(0, i).trim().toLowerCase();
        const v = l.slice(i + 1).replace(/^[ \t]+/, '');
        hs.push([name, v, l]);
        h[name] = h[name] == null ? v.trim() : `${h[name]},${v.trim()}`;
      }
      const face = conn.face;
      if (face === 'ctl') {
        const { path, params } = parseTarget(target);
        if (path === '/log') answerLog(params).then((b) => { if (!conn.sock.destroyed) conn.sock.write(`HTTP/1.1 200 OK\r\nContent-Length: ${Buffer.byteLength(b, 'latin1')}\r\n\r\n${b}`, 'latin1'); });
        else conn.sock.write('HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n');
        continue;
      }
      const r = begin(face, conn, method, target, hs, rest);
      const q = { r, framing: 'none', need: 0, cstate: 'size', cleft: 0, answered: false, afterRefusal: false };
      if (/chunked/i.test(h['transfer-encoding'] || '')) q.framing = 'chunked';
      else if (h['content-length'] != null) { q.framing = 'length'; q.need = Number(h['content-length']); }
      conn.req = q;
      const hasBody = q.framing === 'chunked' || q.need > 0;
      const expect = holdsContinue(h.expect);
      if (expect && refuses417(r)) {
        logAnswer(r, { scheme: judge(r, Buffer.alloc(0), false).scheme, verdict: '-', lines: [] }, expect417(r), 'as the head arrived');
        writeH1(conn, expect417(r));
        q.answered = true;
        q.afterRefusal = hasBody;
      } else {
        const pre = judge(r, Buffer.alloc(0), false);
        const pd = decide(r, pre, false);
        const pass = pd.status !== 401 && pd.status !== 404;
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
            q.afterRefusal = true;
          }
        }
      }
    }
    const q = conn.req;
    if (q.afterRefusal && q.r.body.bytes === 0) {
      if (conn.buf.length === 0) return;
      const c = conn.buf[0];
      q.afterRefusal = false;
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
  const session = stream.session;
  const conn = { k: session.k, peer: session.peer };
  const hs = [];
  const lines = [];
  for (const [k, v] of Object.entries(headers)) {
    for (const one of Array.isArray(v) ? v : [v]) {
      lines.push(`${k}: ${one}`);
      if (!k.startsWith(':')) hs.push([k, String(one), `${k}: ${one}`]);
    }
  }
  const r = begin('h2', conn, headers[':method'], headers[':path'], hs, L1(lines.join('\r\n')));
  const q = { answered: false };
  const respond = (d) => {
    const body = bodyOf(d);
    const h = { ':status': d.status, 'content-length': String(body.length) };
    if (d.www.length) h['www-authenticate'] = d.www;
    for (const [k, v] of d.extra) h[k.toLowerCase()] = v;
    try {
      stream.respond(h);
      if (d.slow) { stream.write(Buffer.alloc(0)); setTimeout(() => { if (!stream.destroyed) stream.end(body); }, d.slow); } else stream.end(body);
    } catch (e) { r.log(`respond #${r.n} failed: ${esc(L1(String(e.message)))}`); }
  };
  const expect = holdsContinue(headers.expect);
  let answerAt = 0;
  let pre = null;
  if (expect && refuses417(r)) {
    logAnswer(r, { scheme: judge(r, Buffer.alloc(0), false).scheme, verdict: '-', lines: [] }, expect417(r), 'as the headers arrived');
    respond(expect417(r));
    q.answered = true;
  } else {
    pre = judge(r, Buffer.alloc(0), false);
    const pd = decide(r, pre, false);
    const pass = pd.status !== 401 && pd.status !== 404;
    if (r.params.get('early') === '1' && !pass) {
      const d = decide(r, judge(r, Buffer.alloc(0), true), true);
      logAnswer(r, pre, d, 'as the headers arrived');
      respond(d);
      q.answered = true;
    }
    if (r.params.get('after') && !pass) answerAt = Number(r.params.get('after'));
  }
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
  const bracket = (x) => `[#${x.n} ${x.face} ${x.method} conn=${x.conn} auth=${x.scheme}:${x.verdict}${x.auths > 1 ? `:x${x.auths}` : ''} status=${x.status} ${x.when} body=${x.body}]`;
  lines.push(`rounds n=${e.n} ${e.rounds.map((x) => `[#${x.n} ${x.face} ${x.method} conn=${x.conn} auth=${x.scheme}:${x.verdict}${x.auths > 1 ? `:x${x.auths}` : ''} status=${x.status} ${x.when} body=${x.body}]`).join(' ') || '-'}${e.more ? ` more=${e.more} last ${bracket(e.lastRound)}` : ''}`);
  return lines.join('\n') + '\n';
}

// ---------------------------------------------------------------- servers
const peerOf = (s) => `${s.remoteFamily === 'IPv6' ? `[${s.remoteAddress}]` : s.remoteAddress}`;

// duplexOf: SOCK as a stream that yields FIRST, then the rest, for a TLS
// socket made over a connection whose first bytes were already read.
function duplexOf(sock, first) {
  const d = new Duplex({
    read() { sock.resume(); },
    write(chunk, enc, cb) { sock.write(chunk, cb); },
    final(cb) { sock.end(); cb(); },
    destroy(err, cb) { sock.destroy(); cb(err); },
  });
  d.push(first);
  sock.on('data', (c) => { if (!d.push(c)) sock.pause(); });
  sock.on('end', () => d.push(null));
  sock.on('close', () => d.destroy());
  return d;
}

function httpServer() {
  return net.createServer((sock) => {
    track(sock);
    const k = ++conns.http;
    const peer = peerOf(sock);
    sock.once('data', (first) => {
      if (first[0] === 0x16) {
        const t = new tls.TLSSocket(duplexOf(sock, first), { isServer: true, secureContext: h1ctx, ALPNProtocols: ['http/1.1'] });
        t.on('error', () => {});
        serveH1(t, 'http+tls', k, peer);
      } else {
        sock.pause();
        sock.unshift(first);
        serveH1(sock, 'http', k, peer);
        sock.resume();
      }
    });
  });
}
const plainServer = (face) => net.createServer((sock) => { track(sock); serveH1(sock, face, face === 'ctl' ? 0 : ++conns[face], peerOf(sock)); });
function httpsServer() {
  const s = tls.createServer({ cert, key, ALPNProtocols: ['http/1.1'] }, (t) => { track(t); serveH1(t, 'https', ++conns.https, peerOf(t)); });
  s.on('tlsClientError', () => {});
  return s;
}
function h2Server() {
  const s = http2.createSecureServer({ cert, key, ALPNProtocols: ['h2'], allowHTTP1: false, maxSessionMemory: 1000,
    maxHeaderListPairs: 4096, settings: { maxHeaderListSize: 16 * 1024 * 1024 } });
  s.on('connection', (tcp) => track(tcp));
  s.on('tlsClientError', () => {});
  s.on('session', (ss) => { ss.k = ++conns.h2; ss.peer = peerOf(ss.socket); sessions.add(ss); ss.on('close', () => sessions.delete(ss)); ss.on('error', () => {}); });
  s.on('stream', serveH2);
  return s;
}

const listen = (server, port, host) => new Promise((resolve, reject) => {
  server.once('error', reject);
  server.listen(port, host, () => { server.removeListener('error', reject); resolve(server.address().port); });
});
// both: FACTORY's servers on 127.0.0.1 and ::1 at one port, tried until a
// port both families take.
async function both(factory) {
  for (let i = 0; i < 20; i++) {
    const a = factory();
    const port = await listen(a, 0, '127.0.0.1');
    const b = factory();
    try { await listen(b, port, '::1'); return { port, servers: [a, b] }; } catch { a.close(); }
  }
  throw new Error('no port both 127.0.0.1 and ::1 take');
}
const faces = { http: await both(httpServer), httpb: await both(() => plainServer('httpb')), https: await both(httpsServer), h2: await both(h2Server) };
const ctl = plainServer('ctl');
const ctlPort = await listen(ctl, 0, '127.0.0.1');
process.stdout.write(`${JSON.stringify({ http: String(faces.http.port), httpb: String(faces.httpb.port), https: String(faces.https.port), h2: String(faces.h2.port), ctl: String(ctlPort) })}\n`);
process.stdin.on('data', () => {});
process.stdin.on('end', () => {
  for (const [tag, e] of tags) {
    if (e.fetched || tag === '-') continue;
    process.stderr.write(`unfetched tag=${tag} requests ${e.n}\n`);
  }
  for (const s of sessions) s.destroy();
  for (const s of sockets) s.destroy();
  for (const f of Object.values(faces)) for (const s of f.servers) s.close();
  ctl.close();
  process.exit(0);
});
