#!/usr/bin/env python3
"""analyze_refuse.py LOG...: each /refuse stream the instrumented origin
refused (gen_refuse_probe.py), joined by the client's port to its session's
events and to the probe that sent it, one row per refusal:

  LOG key face at  rst=got|MISSING  order  sockw-at-client-end  probe-bytes  end

order is how the origin's events fell: refused<close<end, when the stream's
close (its RST_STREAM serialized) came before the client's end was read,
refused<end<close when the end came first. sockw is the cleartext the
session had handed its socket when the client's end was read: for h2 18 is
the SETTINGS and the ACK alone, 31 those and the RST_STREAM. Then a tally by
face, at, rst and order. A log name may be LABEL=PATH.
"""
import json
import sys
from collections import Counter, defaultdict

RST = '00000403000000000100000007'
tally = Counter()
rows = []
for arg in sys.argv[1:]:
    label, path = arg.split('=', 1) if '=' in arg else (arg, arg)
    by_port = defaultdict(list)
    for line in open(path):
        line = line.strip()
        if not line:
            continue
        try:
            e = json.loads(line)
        except ValueError:
            continue
        by_port[e.get('port')].append(e)
    for port, evs in by_port.items():
        evs.sort(key=lambda e: e['t'])
        refuses = [e for e in evs if e['w'] == 'origin' and e['ev'] == 'refuse']
        if not refuses:
            continue
        # A port can be reused by a later connection: keep the events from
        # the last session event before the refusal to the next session event.
        for r in refuses:
            sess = [e for e in evs if e['w'] == 'origin' and e['ev'] == 'session' and e['t'] <= r['t']]
            t0 = sess[-1]['t'] if sess else 0
            later = [e for e in evs if e['w'] == 'origin' and e['ev'] == 'session' and e['t'] > r['t']]
            t1 = later[0]['t'] if later else float('inf')
            conn = [e for e in evs if t0 - 50 <= e['t'] < t1]
            o = {e['ev']: e for e in conn if e['w'] == 'origin'}
            probe = [e for e in conn if e['w'] == 'probe']
            got = ''.join(e['hex'] for e in probe if e['ev'] == 'data')
            end = next((e['line'] for e in probe if e['ev'] == 'end'), None)
            close_t = o.get('stream-close', {}).get('t')
            end_t = o.get('client-end', {}).get('t')
            if close_t is None:
                order = 'no-close'
            elif end_t is None:
                order = 'no-client-end'
            elif close_t < end_t:
                order = 'refused<close<end'
            else:
                order = 'refused<end<close'
            sockw = o.get('client-end', {}).get('sockw')
            rst = 'got' if RST in got else 'MISSING'
            face, at = r['face'], r['at']
            rows.append((label, r.get('key'), face, at, rst, order, sockw, len(got) // 2, end))
            tally[(face, at, rst, order)] += 1
for row in rows:
    print('ROW', *row)
for k in sorted(tally, key=str):
    print('TALLY', *k, tally[k])
