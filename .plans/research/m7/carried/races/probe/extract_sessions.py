#!/usr/bin/env python3
"""extract_sessions.py WHICH LOG...: the events of each refused session
analyze_refuse.py would print a row for, origin's and probe's, in time order,
with t made ms from the session's first event: every one when WHICH is all,
those that lost their RST_STREAM when it is missing, those whose client's end
came before the refused stream's close when it is end-first. A log name may
be LABEL=PATH; each session starts with a line # LABEL KEY ROW."""
import json
import sys
from collections import defaultdict

RST = '00000403000000000100000007'
which = sys.argv[1]
for arg in sys.argv[2:]:
    label, path = arg.split('=', 1) if '=' in arg else (arg, arg)
    by_port = defaultdict(list)
    for line in open(path):
        try:
            e = json.loads(line)
        except ValueError:
            continue
        by_port[e.get('port')].append(e)
    for port, evs in by_port.items():
        evs.sort(key=lambda e: e['t'])
        for r in [e for e in evs if e['w'] == 'origin' and e['ev'] == 'refuse']:
            sess = [e for e in evs if e['w'] == 'origin' and e['ev'] == 'session' and e['t'] <= r['t']]
            t0 = sess[-1]['t'] if sess else r['t']
            later = [e for e in evs if e['w'] == 'origin' and e['ev'] == 'session' and e['t'] > r['t']]
            t1 = later[0]['t'] if later else float('inf')
            conn = [e for e in evs if t0 - 50 <= e['t'] < t1]
            o = {e['ev']: e for e in conn if e['w'] == 'origin'}
            got = ''.join(e['hex'] for e in conn if e['w'] == 'probe' and e['ev'] == 'data')
            missing = RST not in got
            end_first = 'client-end' in o and 'stream-close' in o and o['client-end']['t'] < o['stream-close']['t']
            if which == 'missing' and not missing:
                continue
            if which == 'end-first' and not end_first:
                continue
            start = conn[0]['t']
            print(f"# {label} {r.get('key')} {'MISSING' if missing else 'got'} {'end<close' if end_first else 'close<end'}")
            for e in conn:
                f = {k: v for k, v in e.items() if k not in ('t', 'pid')}
                print(f"{e['t'] - start:9.3f} {json.dumps(f)}")
