#!/usr/bin/env python3
"""delta_table.py LOG...: for a trip-delta sweep's log, each run's delta, verdict,
where the collect request ran (ms after ready, and the bytes allocated since
ready by then), where the handler ran, and the bytes main allocated from
ready to go-call."""
import re, sys
sys.path.insert(0, __import__('os').path.dirname(__file__))
from analyze import parse, plist, child_key, verdict, short_frames
for path in sys.argv[1:]:
    delta = None
    print('==', path)
    for line in open(path, errors='replace'):
        m = re.match(r'^\(sweep \S+ \S+ \d+ delta (\S+)\)', line)
        if m:
            delta = m.group(1); continue
        if not line.startswith('PROBE '):
            continue
        d = parse(line[6:])[0]
        pl = plist(d)
        kept0 = pl['kept'][0] if pl['kept'] else None
        key = child_key(kept0)
        v = verdict(key, kept0)
        probe = next(p for p in pl['probes'] if p[0] == 'probe')
        ev = probe[4]
        def find(tag):
            return next((e for e in ev if e[0] == tag), None)
        ready = find('ready'); gocall = find('go-call') or find('await-call'); creq = find('collect-request'); hd = find('handler'); he = find('hold-end')
        gc = lambda e: e[-1] if e else None
        bytes_of = lambda e: gc(e)[2] if e and isinstance(gc(e), list) and len(gc(e)) > 2 else None
        rb = bytes_of(ready)
        out = [f'delta={delta}', v, str(kept0[1:3]) if kept0 else '-']
        out.append(f"go-call-bytes={bytes_of(gocall)-rb if gocall and rb is not None else None}")
        if creq:
            plus = bytes_of(creq) - rb if rb is not None else None
            out.append(f"creq@{(creq[1]-ready[1])/1e6:.1f}ms bytes+{plus} {'after-hold-end' if he and creq[1] > he[1] else 'in-hold'}")
        else:
            out.append('no-creq')
        out.append('handler=' + (short_frames(hd[2]) if hd else 'never'))
        print('  '.join(out))
