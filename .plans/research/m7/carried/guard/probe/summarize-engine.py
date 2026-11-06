#!/usr/bin/env python3
"""summarize-engine.py LOG...: (LOG plain or .gz) an engine sweep's rows (engine ENTRY F TRAIL
OUTCOME) as runs of equal (TRAIL, OUTCOME), per entry, in fuel order; then,
per entry, the count of fuels at each outcome among those whose expiry
landed inside call-state (TRAIL holds enter and not exit)."""
import gzip
import re
import sys
from collections import Counter, OrderedDict

ROW = re.compile(r'\(engine (\S+) (\d+) (\(.*?\)|completed) (.*)\)$')

for path in sys.argv[1:]:
    print('==', path)
    rows = []
    for line in (gzip.open(path, 'rt') if path.endswith('.gz') else open(path)):
        if line.startswith('(engine'):
            m = ROW.match(line.strip())
            if not m:
                print('unparsed:', line.strip())
                continue
            rows.append(m.groups())
    cur = None
    for e, f, t, o in rows:
        key = (e, t, o)
        if cur and cur[0] == key:
            cur[2] = f
        else:
            if cur:
                print(f'  {cur[0][0]} {cur[1]}-{cur[2]} {cur[0][1]} {cur[0][2][:160]}')
            cur = [key, f, f]
    if cur:
        print(f'  {cur[0][0]} {cur[1]}-{cur[2]} {cur[0][1]} {cur[0][2][:160]}')
    inside = OrderedDict()
    for e, f, t, o in rows:
        marks = t.strip('()').split() if t != 'completed' else []
        if 'enter' in marks and 'exit' not in marks:
            where = 'in-parse' if marks[-1] == 'parse' else 'in-checks'
            inside.setdefault(e, Counter())[(where, o[:110])] += 1
    for e, c in inside.items():
        print(f'  inside call-state, {e}:')
        for (where, o), n in sorted(c.items()):
            print(f'    {n:5d} {where} {o}')
