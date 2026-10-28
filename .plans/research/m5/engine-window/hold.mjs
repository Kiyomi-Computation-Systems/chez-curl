// Accepts every connection and never answers; prints its port; exits when stdin ends.
import net from 'node:net';
const socks = new Set();
const s = net.createServer((c) => { socks.add(c); c.on('error', () => {}); c.on('close', () => socks.delete(c)); });
s.listen(0, '127.0.0.1', () => process.stdout.write(`${s.address().port}\n`));
process.stdin.on('data', () => {});
process.stdin.on('end', () => process.exit(0));
