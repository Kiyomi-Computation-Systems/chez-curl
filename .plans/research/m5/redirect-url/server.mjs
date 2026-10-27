// The M5 plan's redirect-URL probe server (2026-10-27). node:net, so each
// head goes out byte for byte, as Node's http would never write it. A request
// for any path whose last segment is NAME, its query ignored, gets case
// NAME's status line and header lines, then Content-Length: 0 and
// Connection: close, and the connection closes. {PORT} in a line is the
// server's own port. An unknown NAME gets 404. Announces its port on stdout;
// exits when stdin ends.
import net from 'node:net';

const long = (n) => '/' + 'a'.repeat(n);
// Each case: [status, ...header lines], each line written in latin1, so a
// \x escape below is one byte on the wire.
const cases = {
  'rel-abs': [302, 'Location: /x/y?z=1'],
  'rel-path': [302, 'Location: d/e'],
  'rel-dots': [302, 'Location: ../../up'],
  'rel-query': [302, 'Location: ?only=1'],
  'rel-frag': [302, 'Location: #only'],
  'netpath': [302, 'Location: //127.0.0.1:{PORT}/np'],
  'other-host': [302, 'Location: http://other.invalid/x'],
  'https': [302, 'Location: https://127.0.0.1:1/s'],
  'no-path': [302, 'Location: http://127.0.0.1:{PORT}'],
  'upper-scheme': [302, 'Location: HTTP://127.0.0.1:{PORT}/UP'],
  'ftp': [302, 'Location: ftp://127.0.0.1/f'],
  'file': [302, 'Location: file:///etc/passwd'],
  'javascript': [302, 'Location: javascript:alert(1)'],
  'unknown-scheme': [302, 'Location: foo://bar/x'],
  'empty': [302, 'Location:'],
  'blank': [302, 'Location:    '],
  'missing': [302],
  'padded': [302, 'Location:    /padded   '],
  'tab': [302, 'Location:\t/tabbed'],
  'space-inside': [302, 'Location: /a b/c d'],
  'utf8': [302, 'Location: /caf\xc3\xa9'],
  'latin1': [302, 'Location: /caf\xe9'],
  'ctl': [302, 'Location: /x\x01y'],
  'del': [302, 'Location: /x\x7fy'],
  'pct': [302, 'Location: /already%20encoded'],
  'bad-pct': [302, 'Location: /bad%zz'],
  'userinfo': [302, 'Location: http://u:p@127.0.0.1:{PORT}/creds'],
  'frag-abs': [302, 'Location: /withfrag#f'],
  'bad-ipv6': [302, 'Location: http://[::1/x'],
  'bad-port': [302, 'Location: http://127.0.0.1:99999/x'],
  'backslash': [302, 'Location: /\\evil.invalid/x'],
  'two': [302, 'Location: /first', 'Location: /second'],
  'lower-name': [302, 'location: /lc'],
  'idn': [302, 'Location: http://caf\xc3\xa9.invalid/'],
  'long-8k': [302, 'Location: ' + long(8000)],
  'long-90k': [302, 'Location: ' + long(90000)],
  'long-110k': [302, 'Location: ' + long(110000)],
  's200': [200, 'Location: /s'],
  's201': [201, 'Location: /s'],
  's299': [299, 'Location: /s'],
  's300': [300, 'Location: /s'],
  's301': [301, 'Location: /s'],
  's303': [303, 'Location: /s'],
  's304': [304, 'Location: /s'],
  's305': [305, 'Location: /s'],
  's306': [306, 'Location: /s'],
  's307': [307, 'Location: /s'],
  's308': [308, 'Location: /s'],
  's309': [309, 'Location: /s'],
  's399': [399, 'Location: /s'],
  's400': [400, 'Location: /s'],
};

const server = net.createServer({ allowHalfOpen: true }, (sock) => {
  let head = Buffer.alloc(0);
  sock.on('error', () => {});
  sock.on('data', (chunk) => {
    head = Buffer.concat([head, chunk]);
    const end = head.indexOf('\r\n\r\n');
    if (end < 0) return;
    sock.removeAllListeners('data');
    const target = head.toString('latin1', 0, head.indexOf('\r\n')).split(' ')[1] || '/';
    const name = target.split('?')[0].split('/').pop();
    const port = String(server.address().port);
    const c = cases[name] || [404];
    const lines = [`HTTP/1.1 ${c[0]} X`, ...c.slice(1).map((l) => l.replaceAll('{PORT}', port)),
                   'Content-Length: 0', 'Connection: close', '', ''];
    sock.end(Buffer.from(lines.join('\r\n'), 'latin1'));
  });
});
server.listen(0, '127.0.0.1', () => process.stdout.write(`${server.address().port}\n`));
process.stdin.on('data', () => {});
process.stdin.on('end', () => { server.close(); process.exit(0); });
