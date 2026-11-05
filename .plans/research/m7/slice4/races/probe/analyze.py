#!/usr/bin/env python3
"""analyze.py FILE...: the PROBE and PROBE-UPLOAD lines of race-gate.sh outputs,
or of a suite's own output, tabulated.

For each SIGINT child of test-group: its verdict against the test's expected
value, which thread took the SIGINT (main, the holder, or another), the
times from the child's ready line to the script's sight of it, to the send
and to the arrival, the hold's length, the margin from the arrival to the
hold's end, where the handler ran (frame names) and when, relative to the
hold's end. For test-upload's body-asked rows: the bit, whether and when
libcurl asked, and the head's publication, in ms from the submit.
"""
import re
import sys
from collections import defaultdict, Counter


def tokenize(s):
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c.isspace():
            i += 1
        elif c in '()':
            yield c
            i += 1
        elif c == '"':
            j = i + 1
            buf = []
            while s[j] != '"':
                if s[j] == '\\':
                    j += 1
                    buf.append({'n': '\n', 't': '\t'}.get(s[j], s[j]))
                else:
                    buf.append(s[j])
                j += 1
            yield ('str', ''.join(buf))
            i = j + 1
        elif c == "'":
            yield "'"
            i += 1
        else:
            j = i
            while j < n and not s[j].isspace() and s[j] not in '()':
                j += 1
            yield ('atom', s[i:j])
            i = j


def parse(s):
    toks = list(tokenize(s))
    pos = 0

    def read():
        nonlocal pos
        t = toks[pos]
        pos += 1
        if t == '(':
            out = []
            while toks[pos] != ')':
                out.append(read())
            pos += 1
            return out
        if t == "'":
            return ['quote', read()]
        if isinstance(t, tuple) and t[0] == 'str':
            return t[1]
        a = t[1]
        if a == '#t':
            return True
        if a == '#f':
            return False
        try:
            return int(a)
        except ValueError:
            return a
    out = []
    while pos < len(toks):
        out.append(read())
    return out


def plist(lst):
    return {lst[i]: lst[i + 1] for i in range(0, len(lst) - 1, 2)}


EXPECTED = {
    'lost': ['lost', 'escaped', 'taken', ['answered', 200, 'status 200\n']],
    'submit': ['submit', 'escaped', 'after-release', [0, 0, 0]],
    'raise': ['raise', True, False, 'after-release', [0, 0, 0]],
    'turn-escape': ['turn', 'escaped', 'after-release', [0, 0, 0], 'ended'],
    'turn-raise': ['turn', ['raise', True, False], 'after-release', [0, 0, 0], 'ended'],
    'admissions': ['admissions', [['transfer', 'stopped'], 1], [['engine', 'stopped'], 0]],
    'P1': ['resume', 'P1', ['raised', 'cancelled', 'http-await', 0], 2, 1, 0, 0],
    'P3': ['resume', 'P3', ['raised', 'cancelled', 'http-await', 1], 3, 1, 0, 0],
    'G': ['resume', 'G', ['value', [True, ['cancelled', 'http-await', 0], ['closed', 'go', False]]], 1, 1, 0, 0],
}


def child_key(kept0):
    if not isinstance(kept0, list) or not kept0:
        return '?'
    h = kept0[0]
    if h == 'turn':
        return 'turn-raise' if isinstance(kept0[1], list) else 'turn-escape'
    if h == 'resume':
        return kept0[1]
    return h


def verdict(key, kept0):
    if key == 'sections':
        ok = (isinstance(kept0, list) and len(kept0) == 2 and isinstance(kept0[1], list)
              and kept0[1][:2] == ['raised', 'stopped'] and str(kept0[1][2]).endswith('sections-1&ms=1000')
              and kept0[1][3] == 0)
        return 'ok' if ok else 'WRONG'
    return 'ok' if EXPECTED.get(key) == kept0 else 'WRONG'


def ms(a, b):
    return None if a is None or b is None else round((b - a) / 1e6, 1)


def short_frames(frames):
    keep = [f for f in frames if f not in (False, 'dynamic-wind', 'ksrc', '$expeditor', 'invoke', 'thunk')]
    return '/'.join(keep[:5])


def group_row(tag, d):
    pl = plist(d)
    kept = pl.get('kept', [])
    status = pl.get('status')
    probes = pl.get('probes', [])
    probe = next((p for p in probes if p and p[0] == 'probe'), None)
    script = next((p for p in probes if p and p[0] == 'script'), None)
    kept0 = kept[0] if kept else None
    key = child_key(kept0)
    v = verdict(key, kept0) if status == 0 else f'status {status}'
    row = {'tag': tag, 'child': key, 'verdict': v, 'kept': kept0}
    if not probe:
        row['note'] = 'no probe'
        return row
    _, name, pid, installed, events, sigs, count = probe[:7]
    ev = defaultdict(list)
    for e in events:
        ev[e[0]].append(e)
    t = lambda k: ev[k][0][1] if ev[k] else None
    ready = t('ready')
    hs = ev['hold-start'][0] if ev['hold-start'] else None
    he = ev['hold-end'][0] if ev['hold-end'] else None
    holder_tid = hs[2] if hs else None
    row.update({
        'sigs': count,
        'ready->saw': ms(ready, script[2]) if script else None,
        'ready->sent': ms(ready, script[4]) if script else None,
        'hold': ms(hs[1], he[1]) if hs and he else None,
        'main-at-hold-end': he[2] if he else None,
    })
    if sigs:
        tid, sns, rax, mainsys = sigs[0]
        who = 'main' if tid == pid else ('holder' if tid == holder_tid else 'other')
        row.update({'sig-thread': who, 'ready->sig': ms(ready, sns), 'sig->hold-end': ms(sns, he[1]) if he else None,
                    'rax': rax, 'mainsys': mainsys})
    else:
        row.update({'sig-thread': 'none'})
    hd = ev['handler']
    if hd:
        row['handler'] = short_frames(hd[0][2])
        row['hold-end->handler'] = ms(he[1], hd[0][1]) if he else None
        row['handlers'] = len(hd)
    else:
        row['handler'] = 'never'
    for k in ('go-call', 'go-return', 'await-call', 'await-return', 'parallel-call', 'done-call', 'done-return', 'run-call'):
        if ev[k]:
            row[k] = ms(ready, ev[k][0][1])
    return row


def upload_row(tag, d):
    name = d[0]
    pl = plist(d[1:])
    row = {'tag': tag, 'row': name, 'bit': pl.get('bit')}
    if 'asked' in pl:
        sub = pl.get('submit-at')
        row.update({'asked': pl['asked'], 'submit->ask': ms(sub, pl['asked-at']) if pl['asked-at'] else None,
                    'submit->head': ms(sub, pl['head-at']) if pl.get('head-at') else None,
                    'ask-before-head': (pl['asked-at'] < pl['head-at']) if pl['asked-at'] and pl.get('head-at') else None,
                    'outcome': pl.get('outcome')})
    return row


def main(paths):
    groups, uploads = [], []
    for path in paths:
        for line in open(path, errors='replace'):
            m = re.match(r'^(\[(\S+) (\d+)\] )?(PROBE|PROBE-UPLOAD) (.*)$', line.rstrip('\n'))
            if not m:
                continue
            tree = m.group(2) or '-'
            rnd = m.group(3) or '-'
            tag = f'{path.split("/")[-1]}:{tree}:{rnd}'
            try:
                d = parse(m.group(5))[0]
            except Exception as e:  # noqa
                print(f'unparsed {tag}: {e}', file=sys.stderr)
                continue
            (groups if m.group(4) == 'PROBE' else uploads).append((tree, group_row(tag, d) if m.group(4) == 'PROBE' else upload_row(tag, d)))
    if groups:
        print('== test-group SIGINT children')
        cols = ['tag', 'child', 'verdict', 'sig-thread', 'ready->saw', 'ready->sent', 'ready->sig', 'hold',
                'sig->hold-end', 'rax', 'main-at-hold-end', 'handler', 'hold-end->handler']
        print('\t'.join(cols))
        for tree, r in groups:
            print('\t'.join(str(r.get(c, '')) for c in cols))
        print('== summary by tree and child: runs, verdicts, signal thread, handler place, min margin (ms)')
        agg = defaultdict(list)
        for tree, r in groups:
            agg[(tree, r['child'])].append(r)
        for (tree, child), rs in sorted(agg.items()):
            margins = [r['sig->hold-end'] for r in rs if r.get('sig->hold-end') is not None]
            sends = [r['ready->sent'] for r in rs if r.get('ready->sent') is not None]
            print(tree, child, len(rs), dict(Counter(r['verdict'] for r in rs)),
                  dict(Counter(r.get('sig-thread') for r in rs)), dict(Counter(r.get('handler') for r in rs)),
                  'min-margin', min(margins) if margins else None, 'max-ready->sent', max(sends) if sends else None)
        wrong = [r for _, r in groups if r['verdict'] != 'ok']
        if wrong:
            print('== wrong verdicts, whole')
            for r in wrong:
                print(r)
    if uploads:
        print('== test-upload body-asked rows')
        cols = ['tag', 'row', 'bit', 'asked', 'submit->ask', 'submit->head', 'ask-before-head', 'outcome']
        print('\t'.join(cols))
        for tree, r in uploads:
            if 'asked' in r:
                print('\t'.join(str(r.get(c, '')) for c in cols))
        print('== summary by tree and row: runs, bits, asked, ask-before-head')
        agg = defaultdict(list)
        for tree, r in uploads:
            if 'asked' in r:
                agg[(tree, r['row'])].append(r)
        for (tree, row), rs in sorted(agg.items()):
            print(tree, row, len(rs), 'bit', dict(Counter(r['bit'] for r in rs)), 'asked', dict(Counter(r['asked'] for r in rs)),
                  'ask-before-head', dict(Counter(r['ask-before-head'] for r in rs)))


if __name__ == '__main__':
    main(sys.argv[1:])
