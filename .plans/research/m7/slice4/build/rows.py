#!/usr/bin/env python3
"""build/m7s4b/rows.py LOG...: each 'test-cookies: TAG on KEY measured VALUE'
line of each LOG; per TAG and KEY, whether every log that measured it agrees,
and the row text (KEY . VALUE)."""
import sys, re, collections
pat = re.compile(r'^test-cookies: (\S+) on (".*?") measured (.*)$')
found = collections.defaultdict(lambda: collections.defaultdict(list))
for path in sys.argv[1:]:
    for line in open(path, encoding='latin-1'):
        m = pat.match(line.rstrip('\n'))
        if m:
            found[m.group(1)][m.group(2)].append((path, m.group(3)))
for tag in found:
    print(f';; == {tag}')
    for key, seen in found[tag].items():
        values = set(v for _, v in seen)
        print(f';; {key}: {len(seen)} runs, {"agree" if len(values)==1 else "SPLIT"}: ' + ', '.join(p.split('/')[-1] for p,_ in seen))
        for v in values:
            print(f'    ({key} . {v})')
