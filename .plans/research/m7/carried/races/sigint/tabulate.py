#!/usr/bin/env python3
"""tabulate.py LOG...: the child-loop runs, by child and plant: each run's
verdict as its suite reads it, and whether a collection ran in the hold
(the probe's HELD and HANDLER differ, or the handler never ran).

  hc-escape: the suite passes on (escape escaped after-release cancelled)
  hc-raise:  on (raise #t #f after-release cancelled)
  mailbox:   on (escape lost #f #t (response 200))
  engine:    on (interrupt H A (response 200)), 450 <= H <= 1000, A > 1500
"""
import re
import sys
from collections import Counter, defaultdict

tally = defaultdict(Counter)
for path in sys.argv[1:]:
    head = None
    for line in open(path):
        line = line.rstrip('\n')
        m = re.match(r'^== (\S+) (.*?) (\S+=\S+)$', line)
        if m:
            head = (m.group(1), m.group(2), m.group(3))
            continue
        if not line.startswith('(') or head is None:
            continue
        prog, args, plant = head
        name = prog.replace('.sps', '') + ('' if not args.split()[1:] else '-' + args.split()[1])
        verdict = 'FAIL'
        if prog == 'hc-escape.sps' and '(escape escaped after-release cancelled)' in line:
            verdict = 'pass'
        elif prog == 'hc-raise.sps' and '(raise #t #f after-release cancelled)' in line:
            verdict = 'pass'
        elif prog == 'mailbox-escape.sps' and '(escape lost #f #t (response 200))' in line:
            verdict = 'pass'
        elif prog == 'engine-interrupt.sps':
            m = re.search(r'\(interrupt (\d+) (\d+) \(response 200\)\)', line)
            if m and 450 <= int(m.group(1)) <= 1000 and int(m.group(2)) > 1500:
                verdict = 'pass'
        cls = re.search(r'\((escape|raise|interrupt) ([^()]*?)\s*(\(|\) \(probe)', line)
        what = cls.group(2).strip() if cls else '?'
        p = re.search(r"\(probe \S+ (\S+) (\S+) (\S+)", line)
        stalled = '?'
        if p:
            held, handler = p.group(1), p.group(2)
            stalled = 'quiet' if held == handler else f'collected({held},{handler})'
        if prog == 'engine-interrupt.sps':
            stalled = 'n/a'
        tally[(name, plant)][(verdict, what, stalled if prog != 'engine-interrupt.sps' else 'n/a')] += 1
for (name, plant), c in sorted(tally.items()):
    total = sum(c.values())
    fails = sum(v for k, v in c.items() if k[0] == 'FAIL')
    print(f'{name:28} {plant:22} runs {total:2}  suite-fails {fails:2}  ' +
          '; '.join(f'{v}x {k[0]} [{k[1]}] {k[2]}' for k, v in sorted(c.items(), key=str)))
