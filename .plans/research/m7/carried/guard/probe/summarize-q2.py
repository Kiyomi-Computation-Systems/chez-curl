#!/usr/bin/env python3
"""summarize-q2.py LOG...: paused-send.sps's rows, one line per libcurl,
face, server and path, its reps joined: each rep's wait, then its after-end
head, then its outcome, as compact text; and paused-send-high.sps's rows,
one line per libcurl, face, server, call and producer, each rep's PROC time
and end."""
import re
import sys


def sexp(text):
    """A tiny s-expression reader: lists, strings, atoms."""
    tokens = re.findall(r'\(|\)|"(?:[^"\\]|\\.)*"|[^\s()]+', text)
    pos = 0

    def read():
        nonlocal pos
        tok = tokens[pos]
        pos += 1
        if tok == '(':
            out = []
            while tokens[pos] != ')':
                out.append(read())
            pos += 1
            return out
        return tok.strip('"')
    return read()


def show(x):
    if isinstance(x, list):
        return '(' + ' '.join(show(y) for y in x) + ')'
    return x


for path in sys.argv[1:]:
    print('==', path)
    low, high = {}, {}
    for line in open(path):
        line = line.strip()
        if line.startswith('(paused '):
            r = sexp(line)
            _, version, face, server, p, rep, asked, wait, after, outcome = r
            low.setdefault((version, face, server, p), []).append((asked, wait, after, outcome))
        elif line.startswith('(high '):
            r = sexp(line)
            _, version, face, server, call, kind, rep, produced, proc, end = r
            high.setdefault((version, face, server, call, kind), []).append((produced, proc, end))
    for key, reps in low.items():
        cells = ['asked ' + show(a) + ' wait ' + show(w) + ' after-end ' + show(e) + ' -> ' + show(o)
                 for a, w, e, o in reps]
        print('  ' + ' '.join(key) + ':')
        for c in cells:
            print('      ' + c)
    for key, reps in high.items():
        cells = ['proc ' + show(p) + ' produced ' + show(d) + ' end ' + show(e) for d, p, e in reps]
        print('  ' + ' '.join(key) + ': ' + ' | '.join(cells))
