#!/usr/bin/env python3
"""M8 slice 3's make test logs, read: every suite that failed, and each of its
failing tests, classed.

    python3 maketest.py LOG...

A failing test is classed `kind` when its actual value is its expected one
with " (mime . 0)" added after each counts list's share entry, the ninth
counter kind the prototype adds and the suites' written-out lists lack (for a
value SRFI-64 printed cut, at about 3,000 chars, the cut prefixes agree);
every other failing test is printed with its expected and actual values, cut.
check-seam's own verdict, which lanes-in-docker.sh logs before make test, is
printed first."""
import re
import sys


def suites(path):
    out = []
    cur = None
    lines = open(path, errors='replace').read().split('\n')
    i = 0
    seam = [l for l in lines if l.startswith('check-seam')]
    while i < len(lines):
        l = lines[i]
        if l.startswith('=== tests/'):
            cur = {'suite': l[4:], 'fails': [], 'verdict': None}
            out.append(cur)
        elif l.startswith('FAIL ') and cur is not None:
            name = l[5:]
            exp = act = None
            j = i + 1
            while j < len(lines) and j < i + 4:
                if lines[j].startswith('  expected: '):
                    exp = lines[j][12:]
                elif lines[j].startswith('  actual:   '):
                    act = lines[j][12:]
                j += 1
            cur['fails'].append((name, exp, act))
        elif l.startswith('test: ') and cur is not None and cur['suite'] in l:
            cur['verdict'] = l
        i += 1
    return seam, out


def kind_only(exp, act):
    # SRFI-64's printing cuts a long value at about 3,000 chars, with "...":
    # then the shorter of the two, the kind taken out, is a prefix of the
    # other, a cut entry's tail aside
    if exp is None or act is None:
        return False
    a = act.replace(' (mime . 0)', '')
    if a == exp:
        return True
    if not (exp.endswith('...') or act.endswith('...')):
        return False
    e = exp[:-3] if exp.endswith('...') else exp
    a = a[:-3] if act.endswith('...') else a
    n = min(len(e), len(a)) - 16
    return n > 1000 and e[:n] == a[:n]


def main(paths):
    for path in paths:
        seam, out = suites(path)
        print(f'## {path}\n')
        for s in seam:
            print(f'- {s}')
        failed = [s for s in out if s['verdict'] and ' FAIL ' in s['verdict'] or (s['verdict'] and ' HUNG ' in s['verdict'])]
        print(f'- suites: {len(out)}, failed or hung: {len(failed)}\n')
        for s in failed:
            kinds = [f for f in s['fails'] if kind_only(f[1], f[2])]
            other = [f for f in s['fails'] if not kind_only(f[1], f[2])]
            print(f'### {s["suite"]}: {s["verdict"][6:]}; {len(s["fails"])} failing, {len(kinds)} by the kind alone\n')
            for name, exp, act in other:
                print(f'- {name[:400]}')
                if exp is not None or act is not None:
                    print(f'  - expected: `{(exp or "")[:600]}`')
                    print(f'  - actual:   `{(act or "")[:600]}`')
            print()


if __name__ == '__main__':
    main(sys.argv[1:])
