// replace.js FILE: replaces the first occurrence of $OLD with $NEW in FILE,
// bytes kept (read and written as Latin-1); exits 3 when OLD is not there
// exactly once.
const fs = require('fs');
const file = process.argv[2];
const s = fs.readFileSync(file, 'latin1');
const o = Buffer.from(process.env.OLD, 'utf8').toString('latin1');
const n = Buffer.from(process.env.NEW, 'utf8').toString('latin1');
const i = s.indexOf(o);
if (i < 0 || s.indexOf(o, i + 1) >= 0) process.exit(3);
fs.writeFileSync(file, s.slice(0, i) + n + s.slice(i + o.length), 'latin1');
