#!/usr/bin/env python3
"""M8 slice 2's README.md: readme-src.md with each @@NAME@@ replaced by the
section of tables.py's output whose title starts as SECTIONS says, and
@@maketest@@ by maketest.md.

    python3 assemble.py RESULTS_DIR > README.md
"""
import os, subprocess, sys

here = os.path.dirname(os.path.abspath(__file__))
res = sys.argv[1]
out = subprocess.run([sys.executable, os.path.join(here, 'tables.py'), res], check=True,
                     capture_output=True, text=True).stdout
# Split at each italic title line.
sections, cur = [], None
for line in out.split('\n'):
    if line.startswith('*') and line.endswith('*') and not line.startswith('**'):
        cur = [line]; sections.append(cur)
    elif cur is not None:
        cur.append(line)
def find(prefix):
    hits = ['\n'.join(s).strip() for s in sections if s[0].startswith('*' + prefix)]
    if not hits:
        sys.exit(f'assemble: no section {prefix!r}')
    return '\n\n'.join(hits)
SECTIONS = {'edge': 'Edges', 'toward': 'What counts', 'early': "libcurl's refusals", 'suppress': 'SUPPRESS',
            'options': 'HTTP_TRANSFER', 'hatch': 'The hatch', 'splits': 'Cells the runs', 'cost': 'The '}
text = open(os.path.join(here, 'readme-src.md'), encoding='utf-8').read()
for name, prefix in SECTIONS.items():
    if name == 'cost':
        body = find('The cost') + '\n\n' + find('The prototype less main')
    else:
        body = find(prefix)
    text = text.replace(f'@@{name}@@', body)
text = text.replace('@@maketest@@', open(os.path.join(here, 'maketest.md'), encoding='utf-8').read().strip())
if '@@' in text:
    sys.exit('assemble: a placeholder is left')
sys.stdout.write(text)
