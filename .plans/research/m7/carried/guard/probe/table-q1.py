#!/usr/bin/env python3
"""table-q1.py KIND VARIANT...: the SIGINT (sigint) or timer (timer)
matrix as one row per WHERE and ACTION, one cell per variant: what the caller
received, short, when all four entries agree; else each entry's."""
import re, sys
here = sys.path[0] + '/../results/'
kind = sys.argv[1]
variants = sys.argv[2:]
def short(outcome, returned):
    o = outcome
    if 'the-planted-condition' in o: return 'planted, as raised'
    if 'returned' in o and 'raised' not in o: return 'call resumed, 200' + (' (handler returned)' if returned != '0' else '')
    if 're-entered after its handle was freed' in o: return 're-entry refusal, compounded'
    if 'non-continuable' in o: return 'non-continuable violation (handler returned)'
    if 'compounded carries-the-plant' in o: return 'compounded with &http-exchange'
    if 'non-condition #f' in o: return '#f, as raised'
    return o
cells = {}
for v in variants:
    for line in open(here + f'{kind}-{v}.log'):
        if kind == 'sigint' and line.startswith('(result '):
            m = re.match(r'\(result (\S+) (\S+) (\S+) (\(raised .*?\)\)|\(returned .*?\)) .* (\d+)\)$', line.strip())
        elif kind == 'timer' and line.startswith('(timer '):
            m = re.match(r'\(timer (\S+) (\S+) (\S+) (\(raised .*?\)\)|\(returned .*?\)) .* (\d+) \(\d+ \d+ \d+\)\)$', line.strip())
        else:
            continue
        if not m: print('unparsed', v, line); continue
        e, w, a, o, r = m.groups()
        cells.setdefault((w, a), {}).setdefault(v, {})[e] = short(o, r)
print('| where | action | ' + ' | '.join(variants) + ' |')
print('|---|---|' + '---|' * len(variants))
for (w, a), byv in cells.items():
    row = []
    for v in variants:
        es = byv.get(v, {})
        vals = set(es.values())
        if len(vals) == 1 and len(es) == 4: row.append(vals.pop())
        else: row.append('; '.join(f'{e}: {x}' for e, x in es.items()))
    print(f'| {w} | {a} | ' + ' | '.join(row) + ' |')
