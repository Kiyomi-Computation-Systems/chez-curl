// 8.23.0's Digest header for a UTF-8 user, recomputed apart from
// server.mjs (2026-11-02). Reads case D:utf8:MD5's second Authorization, as
// the server logged it, from each LOG's current-8.23.0 lane, and computes
// the MD5 response from that header's nonce, cnonce, nc, qop and uri, with
// the password p\xc3\xa4ss and two user names: the bytes \xc3\xbcser, and
// the header's own "%C3%BCser". Prints which one gives libcurl's response.
//   node .plans/research/m7/auth/utf8-recompute.mjs LOG...
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

const md5 = (b) => createHash('md5').update(b).digest('hex');
for (const f of process.argv.slice(2)) {
  for (const line of readFileSync(f, 'latin1').split('\n')) {
    if (!line.startsWith('[current-8.23.0] case D:utf8:MD5 raw server: auth #2 value="')) continue;
    const v = line.slice(line.indexOf('value="') + 7).replace(/"$/, '').replace(/\\"/g, '"');
    const p = {};
    for (const m of v.matchAll(/(\w+)=(?:"([^"]*)"|([^,]*))/g)) p[m[1]] = m[2] ?? m[3];
    const resp = (user) => {
      const ha1 = md5(Buffer.concat([user, Buffer.from(':chez-curl-test:'), Buffer.from('päss', 'utf8')]));
      return md5(`${ha1}:${p.nonce}:${p.nc}:${p.cnonce}:${p.qop}:${md5(`GET:${p.uri}`)}`);
    };
    const a = resp(Buffer.from('üser', 'utf8'));
    const b = resp(Buffer.from('%C3%BCser'));
    console.log(`${f}: header username="${p.username}" response=${p.response}; with \\xc3\\xbcser ${a} ${a === p.response ? 'MATCH' : 'no'}; with %C3%BCser ${b} ${b === p.response ? 'MATCH' : 'no'}`);
  }
}
