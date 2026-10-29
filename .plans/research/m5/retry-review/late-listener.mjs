// Listens on 127.0.0.1:PORT after DELAY ms; logs each connection's bytes; never answers.
import net from 'node:net';
const [port, delay] = process.argv.slice(2).map(Number);
const sockets = [];
setTimeout(() => {
  const server = net.createServer((s) => {
    sockets.push(s);
    let got = '';
    s.on('data', (d) => { got += d.toString('latin1'); });
    s.on('close', () => { console.log(JSON.stringify({ received: got })); });
  });
  server.listen(port, '127.0.0.1', () => console.log(JSON.stringify({ listening: port, at: delay })));
}, delay);
