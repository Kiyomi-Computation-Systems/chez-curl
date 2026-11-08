#!/usr/bin/env python3
"""M8 slice 3's tables, from the probe's logs in RESULTS (results/):

    python3 tables.py RESULTS > RESULTS/tables.md

Reads probe-docker-{1,2}.log (lanes floor, openssl, gnutls, current),
probe-guix-8.20.0-{1,2}.log and probe-nomime-{1,2}.log, each line [LANE] TEXT.
A cell is a line starting "cell ", with the "  | " lines after it, the
origin's report or the mime-files stand-in's events. Each table prints a
row per cell and a column per lane, or "all five: X" when every lane's
answer is the same, from run 1; then every cell whose two runs differ once
times, ports, boundaries and boundary-dependent hashes are set aside, with
both answers."""
import collections
import os
import re
import sys

LANES = ['floor', 'openssl', 'gnutls', 'guix-8.20.0', 'current']
NAMES = {'floor': 'F 7.85.0', 'openssl': 'O 8.5.0', 'gnutls': 'G 8.5.0', 'guix-8.20.0': 'X 8.20.0',
         'current': 'C 8.23.0', 'nomime785': '7.85.0 without mime', 'nomime823': '8.23.0 without mime'}
KEY_ENDS = [' asked=', ' outcome=', ' head=', ' held=', ' sunk-before=', ' outcomes=', ' body-bytes=']


def read(path):
    """{lane: [[text, [sub lines], check-ns]]} for every lane in PATH."""
    out = collections.defaultdict(list)
    if not os.path.exists(path):
        return out
    for raw in open(path, errors='replace'):
        raw = raw.rstrip('\n')
        m = re.match(r'^\[([^\]]+)\] (.*)$', raw)
        if not m:
            continue
        lane, text = m.groups()
        if text.startswith('  | '):
            if out[lane]:
                out[lane][-1][1].append(text[4:])
        elif text.startswith('  check-ns'):
            if out[lane]:
                out[lane][-1][2] = text.strip()
        else:
            out[lane].append([text, [], None])
    return out


def key_of(text):
    end = len(text)
    for k in KEY_ENDS:
        i = text.find(k)
        if 0 <= i < end:
            end = i
    return text[:end]


def cells(runlog):
    """{lane: OrderedDict(key -> (text, subs, ns))} of the cell lines."""
    out = {}
    for lane, entries in runlog.items():
        d = collections.OrderedDict()
        for text, subs, ns in entries:
            if text.startswith('cell '):
                k = key_of(text)
                n = 2
                while k in d:
                    k = f'{key_of(text)} #{n}'
                    n += 1
                d[k] = (text, subs, ns)
        out[lane] = d
    return out


def merged(*logs):
    out = collections.defaultdict(list)
    for log in logs:
        for lane, entries in log.items():
            out[lane].extend(entries)
    return out


def norm(s):
    s = re.sub(r' (ms|release-to-end-ms|other-ms)=[0-9.]+', '', s)
    s = re.sub(r'boundary=[^ ;"_\\|]+', 'boundary=B', s)
    s = re.sub(r' sha256=[0-9a-f]{64}', '', s)
    s = re.sub(r'after [0-9]+ milliseconds', 'after N milliseconds', s)
    s = re.sub(r'^ev [0-9]+ t=[0-9.]+ ', '', s)
    s = re.sub(r' conn=[0-9]+', '', s)
    s = re.sub(r' head="[^"]*"', '', s)
    s = re.sub(r' first="[^"]*"', '', s)
    s = re.sub(r' last="[^"]*"', '', s)
    s = re.sub(r' buffered_body_bytes=[0-9]+', '', s)
    s = re.sub(r' gap=[0-9.]+@[0-9]+', '', s)
    if s.startswith('body face=') or ' body face=' in s:
        s = re.sub(r' fnv=[0-9a-f]+', '', s)
    s = re.sub(r' auth=yes.*$', ' auth=yes', s)
    return s


def after(text, name):
    m = re.search(' ' + re.escape(name) + r'=(\S+)', text)
    return m.group(1) if m else None


def outcome_of(text):
    i = text.find(' outcome=')
    if i < 0:
        return None
    rest = text[i + 9:]
    # up to " sizes=" or the end
    for end in (' sizes=', ' stop-returned-ms-after-release='):
        j = rest.find(end)
        if j >= 0:
            rest = rest[:j]
    return rest


def judge_of(text):
    j = text.find(' sizes=')
    if j < 0:
        return ''
    rest = text[j:]
    m = re.match(r' sizes=\(([^)]*)\)', rest)
    tail = rest[m.end():] if m else rest
    tail = re.sub(r' ms=[0-9.]+', '', tail)
    tail = re.sub(r' release-to-end-ms=[0-9.]+', '', tail)
    tail = re.sub(r' other-get=\(status 200 version http/1.1\)', '', tail)
    tail = re.sub(r' other-ms=[0-9.]+', '', tail)
    return tail.strip()


def sizes_of(text):
    m = re.search(r' sizes=\(([^)]*)\)', text)
    return m.group(1) if m else ''


def row(values):
    """One table row's lane cells, collapsed to 'all five: X' when alike."""
    present = [values.get(l) for l in LANES]
    if all(v is not None for v in present) and len(set(present)) == 1:
        return [f'all five: {present[0]}']
    return [f'{NAMES[l].split()[0]}: {values.get(l, "-")}' for l in LANES]


def cell_table(title, caption, c1, pred, show):
    print(f'### {title}\n')
    print(caption + '\n')
    print('| cell | answer, by lane |')
    print('|---|---|')
    keys = []
    for l in LANES:
        for k in c1.get(l, {}):
            if pred(k) and k not in keys:
                keys.append(k)
    for k in keys:
        values = {}
        for l in LANES:
            if k in c1.get(l, {}):
                values[l] = show(c1[l][k])
        cellname = k[len('cell '):]
        print(f'| {md(cellname)} | {"<br>".join(md(v) for v in row(values))} |')
    print()


def md(s):
    return s.replace('|', '\\|')


def report_head(subs):
    for s in subs:
        if s.startswith('parts '):
            return s
    return ''


def part_headers(subs, i):
    for s in subs:
        if s.startswith(f'part {i} '):
            m = re.search(r' headers=(.*?) len=', s)
            d = re.search(r' data=(.*?)( unterminated)?$', s)
            return (m.group(1) if m else '?'), (d.group(1) if d else '?')
    return None, None


def main(results):
    r1 = merged(read(os.path.join(results, 'probe-docker-1.log')), read(os.path.join(results, 'probe-guix-8.20.0-1.log')),
                read(os.path.join(results, 'probe-nomime-1.log')))
    r2 = merged(read(os.path.join(results, 'probe-docker-2.log')), read(os.path.join(results, 'probe-guix-8.20.0-2.log')),
                read(os.path.join(results, 'probe-nomime-2.log')))
    c1, c2 = cells(r1), cells(r2)

    print('# M8 slice 3: the tables\n')
    print('Generated by `tables.py` from `probe-docker-{1,2}.log`, `probe-guix-8.20.0-{1,2}.log` and '
          '`probe-nomime-{1,2}.log`. Each row is run 1; the runs are compared at the end.\n')

    # --- load -----------------------------------------------------------------
    print('## The load\n')
    print('| lane | probe | mime | counts after the load | multipart post | get | bytevector post | curl-request-check of a multipart body |')
    print('|---|---|---|---|---|---|---|---|')
    for l in LANES + ['nomime785', 'nomime823']:
        entries = r1.get(l, [])
        load = next((t for t, s, n in entries if t.startswith('load lane=')), None)
        if not load:
            continue
        probe = re.search(r'probe=(\(\(formadd[^)]*\) \(mime-init[^)]*\)\))', load).group(1)
        mime = after(load, 'mime')
        counts = re.search(r'counts-after-load=(\(.*\))', load).group(1)
        zero = 'all 0' if re.fullmatch(r'\((\([a-z-]+ \. 0\) ?)+\)', counts) else counts
        get = lambda label: next((outcome_of(t) for t, s, n in entries if t.startswith(f'cell load {label} ')), '-')
        print(f'| {NAMES[l]} | `{probe}` | {mime} | {zero} | {md(get("multipart-post"))} | {md(get("get"))} | '
              f'{md(get("bytevector-post"))} | {md(get("curl-request-check"))} |')
    print()

    show = lambda e: f'{outcome_of(e[0])} {judge_of(e[0])}'.strip()
    cell_table('Each part kind, its options, every method, and large bodies',
               'Over HTTP/1.1 (h1), h2c by prior knowledge and h2 over TLS. The outcome, then for each part '
               'asked whether its header lines (meta) and its data arrived as asked: same, default-type when '
               'libcurl added only that Content-Type line, or DIFF.',
               c1, lambda k: k.startswith(('cell kinds ', 'cell methods ', 'cell large ')), show)

    # Content-Type, Expect and the request size the origin saw, for the large cells
    print('### What the origin saw of the large bodies, and the request size\n')
    print('`ct`, `expect` and `cl` as the parts route read them; `bytes` the body; `size` CURLINFO_REQUEST_SIZE; '
          '`size - bytes` the head, when the size counts the body too.\n')
    print('| cell | lane | expect | cl | bytes | size | size - bytes |')
    print('|---|---|---|---|---|---|---|')
    for l in LANES:
        for k, (t, subs, ns) in c1.get(l, {}).items():
            if k.startswith(('cell large ', 'cell kinds string/none', 'cell kinds file/none', 'cell methods post')):
                h = report_head(subs)
                size = sizes_of(t)
                b = after(h, 'bytes')
                diff = (int(size) - int(b)) if size.isdigit() and b and b.isdigit() else '-'
                print(f'| {md(k[5:])} | {NAMES[l]} | {after(h, "expect")} | {after(h, "cl")} | {b} | {size} | {diff} |')
    print()

    cell_table('Default types', 'One part over h1, post. What arrived: the part\'s header lines as the origin split them.',
               c1, lambda k: k.startswith('cell defaults '),
               lambda e: part_headers(e[1], 0)[0] if outcome_of(e[0]).startswith('(status') else outcome_of(e[0]))

    # --- bytes ------------------------------------------------------------------
    def bytes_show(e):
        t, subs, ns = e
        o = outcome_of(t)
        if not o.startswith('(status'):
            return o
        h, d = part_headers(subs, 0)
        count = after(report_head(subs), 'count')
        z = part_headers(subs, 1)[0]
        extra = '' if count == '2' else f' count={count}'
        field = re.search(r'cell bytes (\w+)/', t).group(1)
        return (f'data={d}' if field == 'value' else h) + extra + ('' if z and 'name="z"' in z else ' NEXT-PART-LOST')
    cell_table('Hostile and edge bytes', 'Each value in one field of part 1, a part `z` after it, over h1, '
               '`MIME_OPTIONS` never set. What arrived: part 1\'s header lines, escaped as the origin escapes '
               '(\\xNN, | between lines), or its data for value; the parts\' count when not 2.',
               c1, lambda k: k.startswith('cell bytes '), bytes_show)

    def ctype_show(e):
        t, subs, ns = e
        o = outcome_of(t)
        if not o.startswith('(status'):
            return o
        h = report_head(subs)
        p0 = part_headers(subs, 0)[0]
        return f'ct={after(h, "ct")} count={after(h, "count")} part0={p0}'
    cell_table("A caller's Content-Type", 'Two data parts; the header given, or none (the blank left out). '
               'ct as the origin read it, spaces as _; the parts it found by the first boundary=; part 0\'s lines.',
               c1, lambda k: k.startswith('cell ctype '), ctype_show)

    cell_table('The file check', '`made`: the path given at construction as that kind (the caller\'s stat). '
               '`engine-check`: a regular file at construction and submit, made that kind by the seam\'s gate on '
               'the engine\'s thread just before its check.', c1,
               lambda k: k.startswith(('cell made ', 'cell engine-check ')),
               lambda e: outcome_of(e[0]) + (' ' + judge_of(e[0]) if outcome_of(e[0]).startswith('(status') else ''))

    print('### The engine\'s check, how long it took (ns, the seam\'s clock)\n')
    print('| cell | ' + ' | '.join(NAMES[l] for l in LANES) + ' |')
    print('|---|' + '---|' * len(LANES))
    keys = [k for k in c1.get('guix-8.20.0', {}) if k.startswith('cell engine-check ')]
    for k in keys:
        print(f'| {k[5:]} | ' + ' | '.join((c1.get(l, {}).get(k, (None, None, None))[2] or '-').replace('check-ns ', '')
                                          for l in LANES) + ' |')
    print()

    def after_show(e):
        t = e[0]
        o = outcome_of(t)
        rest = judge_of(t)
        other = after(t, 'other-ms')
        rel = after(t, 'release-to-end-ms')
        h = report_head(e[1])
        body = f' closed={after(h, "closed")} count={after(h, "count")}' if h else ''
        un = ' UNTERMINATED' if any('unterminated' in s for s in e[1]) else ''
        return f'{o}{body}{un} {rest} release-to-end={rel} ms, other GET={other} ms'
    cell_table('After the check: the file changed once the origin holds the head',
               'Three parts, `before`, the file (3,000 bytes at the check) and `after`, or two for grown-last; a '
               "caller's `Expect: 100-continue` and `EXPECT_100_TIMEOUT_MS` 60000, the parts route's hold=1 "
               'holding the 100 until the change was made. Then the outcome; the time from the release to the end '
               '(a GET on the same engine is submitted 200 ms after the release, and its time is the second '
               'number); closed=1 when the closing delimiter came.', c1, lambda k: k.startswith('cell after '),
               after_show)

    # --- stat -------------------------------------------------------------------------
    print("## The caller's stat, inside a critical section\n")
    print('200 calls each; make: `make-curl-request` of one file part; stat: `file-regular?` alone; µs, '
          'median (max).\n')
    print('| path | ' + ' | '.join(NAMES[l] for l in LANES) + ' |')
    print('|---|' + '---|' * len(LANES))
    stat_rows = collections.OrderedDict()
    for l in LANES:
        for t, s, n in r1.get(l, []):
            if t.startswith('stat '):
                k = t.split()[1]
                m = re.search(r'verdict=(\S+) make-us min=\S+ median=(\S+) max=(\S+) stat-us min=\S+ median=(\S+) max=(\S+)', t)
                stat_rows.setdefault(k, {})[l] = f'{m.group(1)}: make {m.group(2)} ({m.group(3)}), stat {m.group(4)} ({m.group(5)})'
    for k, v in stat_rows.items():
        print(f'| {k} | ' + ' | '.join(v.get(l, '-') for l in LANES) + ' |')
    print()

    def cap_show(e):
        t = e[0]
        if ' head=' in t:
            return f'head={after(t, "head")} port={t.split(" port=")[1].split(" outcome=")[0]} outcome={outcome_of(t)}'
        return outcome_of(t)
    cell_table('The header cap beside MIMEPOST', 'Two parts, 70,005 bytes of data; the parts route answers N header '
               'lines in all.', c1, lambda k: k.startswith('cell cap '), cap_show)

    # --- resend ---------------------------------------------------------------------------
    def resend_show(e):
        t, subs, ns = e
        o = outcome_of(t) or ''
        reqs = [s for s in subs if ' req ' in s and ' GET /hello' not in s]
        bodies = [s for s in subs if ' body ' in s]
        sums = [s for s in subs if ' summary ' in s]
        parts = [s for s in subs if ' part ' in s and ' summary ' not in s]
        drops = [s for s in subs if ' drop ' in s or ' refused-body ' in s]
        rsts = [s for s in subs if ' rst ' in s]
        answers = [re.search(r'status=(\d+)', s).group(1) for s in subs if ' answer ' in s and 'GET' not in s and re.search(r'status=(\d+)', s)]
        body_desc = ','.join(f'{after(b, "got")}/{after(b, "declared")}' for b in bodies)
        closed = ','.join(after(s, 'closed') or '?' for s in sums)
        # each attempt's parts, as len:fnv, closed by its summary line
        groups, current = [], []
        for x in subs:
            if ' part ' in x and ' summary ' not in x:
                current.append(f'{after(x, "len")}:{after(x, "fnv")}')
            elif ' summary ' in x:
                groups.append(' '.join(current))
                current = []
        same = 'whole and alike' if groups and len(set(groups)) == 1 and all(c == '1' for c in closed.split(',') if c) else \
            ('no part read' if not groups else 'DIFFER: ' + ' / '.join(groups))
        return (f'{o} requests={len(reqs)} bodies={body_desc or "-"} closed={closed or "-"} '
                f'answers={",".join(answers) or "-"}{" drops=" + str(len(drops)) if drops else ""}'
                f'{" rst=" + str(len(rsts)) if rsts else ""}: {same}')
    cell_table('Resends', 'Against the mime-files stand-in: each request the tag reached (the warm-up GET aside), '
               'each body as got/declared, each multipart body\'s closing delimiter, and each attempt\'s parts '
               'by length and FNV-1a; "whole and alike" when every attempt the server read whole carried the same '
               'parts, each closed.', c1, lambda k: k.startswith('cell resend '), resend_show)

    print('## The holes (item 4)\n')
    for l in LANES:
        for t, s, n in r1.get(l, []):
            if t.startswith('hole ') or t.startswith('cell hole '):
                print(f'- {NAMES[l]}: `{md(norm(t))}`' + (f' — sent: `{md(part_headers(s, 0)[0] or "")}` '
                                                          f'data `{md((part_headers(s, 0)[1] or "")[:24])}...`'
                                                          if s else ''))
    print()

    cell_table('The memory group, natively', 'Each part kind, a failed file check, a cancel and a timeout mid-body.',
               c1, lambda k: k.startswith('cell memory '), lambda e: (outcome_of(e[0]) or e[0].split(' ', 3)[-1]))

    print('## Counts at each run\'s end\n')
    for name, log in (('run 1', r1), ('run 2', r2)):
        for l in LANES + ['nomime785', 'nomime823']:
            ends = [t for t, s, n in log.get(l, []) if t.startswith('end counts=') or t.startswith('load counts-at-end=')]
            exits = [t for t, s, n in log.get(l, []) if t.startswith('program exit=')]
            if ends or exits:
                zero = all(re.fullmatch(r'.*=\((\([a-z-]+ \. 0\) ?)+\)', e) for e in ends)
                print(f'- {name}, {NAMES[l]}: {"all 0" if zero else ends} at every end line ({len(ends)}); '
                      f'{", ".join(exits)}')
    print()

    # --- the racing cell, every run ------------------------------------------------------------
    print('## The reset inside a 4 MiB part, every run\n')
    print('Each lane\'s three cells in each of runs 1 and 2 (`resend reset-in-big-part`, `-2`, `-3`), and the '
          '`race` group\'s ten in each of `races-*-{1,2}.log`: how many resent and answered 200, and how many '
          'failed, by code.\n')
    print('| lane | runs 1 and 2 | the race group, two runs of ten | in all |')
    print('|---|---|---|---|')
    races = merged(read(os.path.join(results, 'races-docker-1.log')), read(os.path.join(results, 'races-docker-2.log')),
                   read(os.path.join(results, 'races-guix-8.20.0-1.log')), read(os.path.join(results, 'races-guix-8.20.0-2.log')))
    def tally(entries, prefix):
        out = collections.Counter()
        for t, sub, n in entries:
            if t.startswith(prefix):
                o = outcome_of(t) or ''
                m = re.match(r'\((status 200|failed \S+ \d+)', o)
                out[m.group(1) if m else o] += 1
        return out
    for l in LANES:
        a = tally(r1.get(l, []) + r2.get(l, []), 'cell resend reset-in-big-part')
        b = tally(races.get(l, []), 'cell race reset-in-big-part')
        c = a + b
        fmt = lambda x: ', '.join(f'{k}: {v}' for k, v in sorted(x.items())) or '-'
        print(f'| {NAMES[l]} | {fmt(a)} | {fmt(b)} | {fmt(c)} |')
    print()
    print('## The FIFO\'s timeout and stop, two runs\n')
    print('| lane | run | timeout-ms 500 | release to end | the stop returned, after the release |')
    print('|---|---|---|---|---|')
    for name, path in (('1', 'races-docker-1.log'), ('2', 'races-docker-2.log'), ('1', 'races-guix-8.20.0-1.log'),
                       ('2', 'races-guix-8.20.0-2.log')):
        log = read(os.path.join(results, path))
        for l in LANES:
            ts = [t for t, sub, n in log.get(l, []) if t.startswith('cell fifo timeout-500')]
            ss = [t for t, sub, n in log.get(l, []) if t.startswith('cell fifo stop')]
            if ts and ss:
                print(f'| {NAMES[l]} | {name} | {md(outcome_of(ts[0]))} | {after(ts[0], "release-to-end-ms")} ms | '
                      f'{after(ss[0], "stop-returned-ms-after-release")} ms, {md(outcome_of(ss[0]))} |')
    print()

    # --- splits -----------------------------------------------------------------------------
    print('## Cells the two runs split\n')
    print('Each cell\'s line and its report or events, run 1 against run 2, once times, ports, boundaries, '
          'boundary-dependent hashes, and the bytes a dropped connection held, are set aside.\n')
    n = 0
    total = 0
    for l in LANES + ['nomime785', 'nomime823']:
        a, b = c1.get(l, {}), c2.get(l, {})
        for k in a:
            total += 1
            if k not in b:
                print(f'- {NAMES[l]} `{md(k)}`: not in run 2')
                n += 1
                continue
            x = [norm(a[k][0])] + [norm(s) for s in a[k][1]]
            y = [norm(b[k][0])] + [norm(s) for s in b[k][1]]
            if x != y:
                n += 1
                print(f'- {NAMES[l]} `{md(k[5:])}`:')
                print(f'  - run 1: `{md(outcome_of(a[k][0]) or a[k][0])}` {md(resend_show(a[k]) if "resend" in k else "")}')
                print(f'  - run 2: `{md(outcome_of(b[k][0]) or b[k][0])}` {md(resend_show(b[k]) if "resend" in k else "")}')
                diff = [(i, p, q) for i, (p, q) in enumerate(zip(x, y)) if p != q][:3]
                for i, p, q in diff:
                    print(f'  - line {i}: `{md(p[:300])}` against `{md(q[:300])}`')
                if len(x) != len(y):
                    print(f'  - lines: {len(x)} against {len(y)}')
    print(f'\n{n} of {total} cells split.\n')


if __name__ == '__main__':
    main(sys.argv[1])
