#!/usr/bin/env python3
"""M8 slice 2's tables, from the kept logs under results/ (README.md pastes them).

    python3 tables.py RESULTS_DIR > tables.md

Reads probe-docker-{1,2}.log (lanes floor, openssl, gnutls, current) and
probe-guix-8.20.0-{1,2}.log (lane guix-8.20.0), engine-probe.sps's cell and
hatch lines; and cost-*.log, cost.sps's lines. Prints each group's table, the
cells the two runs split, and the cost's medians.
"""
import re, sys, os, statistics
from collections import defaultdict

res = sys.argv[1]
LANES = ['floor', 'openssl', 'gnutls', 'guix-8.20.0', 'current']
NAMES = {'floor': '7.85.0', 'openssl': '8.5.0 OpenSSL', 'gnutls': '8.5.0 GnuTLS', 'guix-8.20.0': '8.20.0', 'current': '8.23.0'}
CELL = re.compile(r'^\[([^\]]+)\] cell (\S+) (\S+) face=(\S+) way=(\S+) opts=(\S+) ended=(\S+) outcome=(.*) tally=(.*) stream=(.*) ms=(\S+) cpu_ms=(\S+)$')
HATCH = re.compile(r'^\[([^\]]+)\] hatch (\S+) (.*) (accepted|\(refused \S+\)|\(assertion .*\))$')

def runs():
    out = {}
    for run in (1, 2):
        for f in (f'probe-docker-{run}.log', f'probe-guix-8.20.0-{run}.log'):
            p = os.path.join(res, f)
            if not os.path.exists(p):
                continue
            for line in open(p, encoding='latin-1'):
                m = CELL.match(line.rstrip('\n'))
                if m:
                    lane, group, label, face, way, opts, ended, outcome, tally, stream, ms, cpu = m.groups()
                    out.setdefault(run, {})[(lane, group, label, face, way, opts)] = dict(
                        ended=ended, outcome=outcome, tally=tally, stream=stream, ms=float(ms), cpu=float(cpu), file=f)
                h = HATCH.match(line.rstrip('\n'))
                if h:
                    out.setdefault(run, {})[(h.group(1), 'hatch', h.group(2), '-', '-', h.group(3))] = dict(answer=h.group(4), file=f)
    return out

def short_outcome(o):
    m = re.match(r'\(status (\d+) version (\S+) headers (\d+)\)', o)
    if m:
        return f'{m.group(1)} ({m.group(3)} headers)'
    m = re.match(r'\(failed (\S+) (\S+) (\S+) "(.*)"\)$', o)
    if m:
        reason, code, cls, err = m.groups()
        return f'{code} {reason}' if reason != 'perform-failed' else code
    return o

def short_tally(t):
    m = re.match(r'\(calls (\d+) lines (\d+) bytes (\d+) heads \((.*)\) after (\d+)\)', t)
    if not m:
        return t
    after = f' +{m.group(5)} refused after' if m.group(5) != '0' else ''
    return f'{m.group(2)}/{m.group(3)} [{m.group(4).replace(" ", ",")}]{after}'

def short_stream(s):
    if s == '-':
        return ''
    m = re.match(r'\(head (none|\d+ \d+) body (\d+) end (eof|\(raised (\S+) (\S+)\))\)', s)
    if not m:
        return s
    head = 'no head' if m.group(1) == 'none' else 'head ' + m.group(1).replace(' ', '/')
    end = 'eof' if m.group(3) == 'eof' else (m.group(5) if m.group(4) == 'perform-failed' else f'{m.group(5)} {m.group(4)}')
    body = f', body {m.group(2)}' if m.group(2) != '0' else ''
    return f'{head}{body}, port {end}'

def key_cells(data, group):
    seen = []
    for k in data:
        if k[1] == group and (k[2], k[3], k[5]) not in seen:
            seen.append((k[2], k[3], k[5]))
    return seen

def grouped(values):
    """VALUES, one per lane in LANES' order (None for none): 'all five: V', or
    each distinct value with the lanes that gave it."""
    have = [(l, v) for l, v in zip(LANES, values) if v is not None]
    distinct = []
    for l, v in have:
        for d in distinct:
            if d[1] == v:
                d[0].append(l); break
        else:
            distinct.append(([l], v))
    if len(distinct) == 1 and len(have) == len(LANES):
        return f'all five: {distinct[0][1]}'
    return '; '.join(f'**{", ".join(NAMES[l] for l in ls)}**: {v}' for ls, v in distinct)

def table(data, group, title, show_tally=True):
    print(f'\n*{title}*\n')
    print('| cell | face | opts | way | answer |')
    print('|---|---|---|---|---|')
    for label, face, opts in key_cells(data, group):
        for way in ('buffered', 'streamed'):
            values = []
            for lane in LANES:
                c = data.get((lane, group, label, face, way, opts))
                if not c:
                    values.append(None)
                    continue
                s = short_outcome(c['outcome'])
                if show_tally:
                    s += f'; {short_tally(c["tally"])}'
                st = short_stream(c['stream'])
                if st:
                    s += f'; {st}'
                values.append(s)
            if any(v is not None for v in values):
                print(f'| {label} | {face} | {"-" if opts == "-" else opts.rstrip(";")} | {way} | {grouped(values)} |')

def splits(all_runs):
    print('\n*Cells the runs split (outcome, tally or stream; times set aside)*\n')
    if 1 not in all_runs or 2 not in all_runs:
        print('(one run only)')
        return
    a, b = all_runs[1], all_runs[2]
    n = 0
    for k in sorted(set(a) | set(b)):
        x, y = a.get(k), b.get(k)
        if x is None or y is None:
            print(f'- {k}: in one run only'); n += 1; continue
        fx = {f: x.get(f) for f in ('outcome', 'tally', 'stream', 'answer')}
        fy = {f: y.get(f) for f in ('outcome', 'tally', 'stream', 'answer')}
        if fx != fy:
            n += 1
            print(f'- `{k}`: run 1 {fx} / run 2 {fy}')
    if n == 0:
        print(f'None: {len(a)} cells and hatch lines in run 1, {len(b)} in run 2, every one alike.')

def hatch(data):
    print('\n*The hatch: each option that can change what the header callable sees, as curl-request-with-options answers it*\n')
    names = [k for k in data if k[1] == 'hatch']
    order = []
    for k in names:
        if (k[2], k[5]) not in order:
            order.append((k[2], k[5]))
    print('| option | value | answer |')
    print('|---|---|---|')
    for name, value in order:
        print(f'| `{name}` | `{value}` | ' + grouped([data.get((l, 'hatch', name, '-', '-', value), {}).get('answer') for l in LANES]) + ' |')

def cost():
    pat = re.compile(r'cost lane=(\S+) kind=(\S+) round=(\d+) ended=#t status=(\d+) headers=(\d+) cpu_ms=(\S+) wall_ms=(\S+) total_us=(\S+)')
    files = sorted(f for f in os.listdir(res) if f.startswith('cost-') and f.endswith('.log'))
    if not files:
        return
    print('\n*The cost, lane F (7.85.0): process CPU and libcurl\'s total per request, min / median / max (samples), each log*\n')
    print('| log | tree | Valgrind | kind | headers | process CPU ms | libcurl total ms | samples |')
    print('|---|---|---|---|---|---|---|---|')
    med = {}
    for f in files:
        tree = 'proto' if '-proto-' in f else 'main' if '-main-' in f else '?'
        vg = 'yes' if '-vg-' in f else 'no'
        run = f.rsplit('-', 1)[1].split('.')[0]
        by = defaultdict(list)
        for line in open(os.path.join(res, f), encoding='latin-1'):
            m = pat.search(line)
            if m and m.group(2) != 'warm':
                by[m.group(2)].append((float(m.group(6)), int(m.group(8)) / 1000.0, int(m.group(5))))
        for kind in ('base', 'final', 'pre'):
            xs = by.get(kind, [])
            if not xs:
                continue
            cpu = sorted(x[0] for x in xs); tot = sorted(x[1] for x in xs)
            med[(vg, tree, run, kind)] = (statistics.median(cpu), statistics.median(tot))
            print(f'| `{f}` | {tree} | {vg} | {kind} | {xs[0][2]} | {cpu[0]:.2f} / {statistics.median(cpu):.2f} / {cpu[-1]:.2f} | '
                  f'{tot[0]:.2f} / {statistics.median(tot):.2f} / {tot[-1]:.2f} | {len(xs)} |')
    calls = {'base': 4, 'final': 1002, 'pre': 1004}
    print('\n*The prototype less main, by the medians above, run by run, and per call of the callable*\n')
    print('| Valgrind | run | kind | calls | process CPU ms | per call, us | libcurl total ms | per call, us |')
    print('|---|---|---|---|---|---|---|---|')
    for vg in ('no', 'yes'):
        for run in ('1', '2'):
            for kind in ('base', 'final', 'pre'):
                a, b = med.get((vg, 'main', run, kind)), med.get((vg, 'proto', run, kind))
                if a and b:
                    dc, dt = b[0] - a[0], b[1] - a[1]
                    print(f'| {vg} | {run} | {kind} | {calls[kind]} | {dc:+.2f} | {dc * 1000 / calls[kind]:+.2f} | {dt:+.2f} | {dt * 1000 / calls[kind]:+.2f} |')

all_runs = runs()
data = all_runs.get(1, {})
table(data, 'edge', 'Edges, run 1: the outcome (a status and its headers, or a code and reason); what the callable counted, lines/bytes [status:lines:bytes per head]; for a stream, what it published')
table(data, 'toward', 'What counts toward the cap across a transfer, run 1')
table(data, 'early', "libcurl's refusals before a line reaches the callable, and their controls, run 1")
table(data, 'suppress', 'SUPPRESS_CONNECT_HEADERS through the proxy, run 1')
table(data, 'options', 'HTTP_TRANSFER_DECODING through the hatch, run 1')
hatch(data)
splits(all_runs)
cost()
