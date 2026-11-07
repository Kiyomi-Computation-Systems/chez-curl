#!/usr/bin/env python3
"""M8 slice 2: which of the caps stand-in's three h2 limits the cap's cells need.

    python3 limits.py RESULTS_DIR

Reads limits-{none,send,send+pairs,send+pairs+settings}-guix-8.20.0*.log,
engine-probe.sps run against server-limits.mjs with H2_LIMITS as named (none:
Node's defaults; send: maxSendHeaderBlockLength 64 MiB; pairs:
maxHeaderListPairs 2^20; settings: SETTINGS_MAX_HEADER_LIST_SIZE 64 MiB), and
prints, for each variant, every cell whose outcome, tally or stream differs
from the variant with all three, and the stand-in's h2-close line for it.
"""
import os, re, sys

res = sys.argv[1]
CELL = re.compile(r'^\[([^\]]+)\] cell (\S+) (\S+) face=(\S+) way=(\S+) opts=(\S+) ended=(\S+) outcome=(.*) tally=(.*) stream=(.*) ms=(\S+) cpu_ms=(\S+)$')

def load(name):
    cells, last, closes = {}, None, {}
    for line in open(os.path.join(res, name), encoding='latin-1'):
        m = CELL.match(line.rstrip('\n'))
        if m:
            last = (m.group(2), m.group(3), m.group(4), m.group(5), m.group(6))
            # A later seam adds " after N" to the tally; compare without it.
            cells[last] = (m.group(8), re.sub(r' after \d+\)', ')', m.group(9)), m.group(10))
        elif last and ' h2-close ' in line:
            closes[last] = re.sub(r'.* h2-close ', 'h2-close ', line.strip())
    return cells, closes

full, _ = load('limits-send+pairs+settings-guix-8.20.0.log')
for variant, name in (('none, run 1', 'limits-none-guix-8.20.0-1.log'), ('none, run 2', 'limits-none-guix-8.20.0-2.log'),
                      ('send', 'limits-send-guix-8.20.0.log'), ('send+pairs', 'limits-send+pairs-guix-8.20.0.log')):
    cells, closes = load(name)
    diff = [k for k in cells if k in full and cells[k] != full[k]]
    print(f'== {variant} ({name}): {len(cells)} cells, {len(diff)} differ from send+pairs+settings')
    for k in diff:
        print(f'  {" ".join(k)}\n    {cells[k][0][:150]}\n    {closes.get(k, "")[:200]}')
