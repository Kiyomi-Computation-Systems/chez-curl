#!/usr/bin/env python3
"""M8 slice 2's mutants: each a copy of src/ and tests/ with one rule broken,
the suites that must notice, and the tests that must fail.

  mutants.py make [NAME...]   copy and mutate each (all by default) under
                              build/m8s2/mut/NAME; write build/m8s2/mut/jobs
  mutants.py check [NAME...]  read each mutant's logs: killed when every
                              expected test failed, by name, else SURVIVED

The jobs run in the container, two at a time:
  scripts/guix-env sh .plans/research/m8/slice2/build/mut-run.sh < /dev/null
From the repository's root, on the host."""
import os, re, shutil, subprocess, sys

T = 'src/curl/private/transfer.sls'
C = 'src/curl/private/conditions.sls'
O = 'tests/origin.mjs'

HEADERS = ['tests/test-headers.sps']
M = []


def mutant(name, edits, suites, expect):
    M.append(dict(name=name, edits=edits, suites=suites, expect=expect))


# --- control: nothing broken; every suite the mutants run passes ------------------------
mutant('control', [], HEADERS + ['tests/test-unsupported.sps', 'tests/test-origin-tls.sps',
                                 'tests/test-transfer.sps', 'tests/test-conditions.sps'], [])

# --- the cap, off by one each way ----------------------------------------------------------
mutant('lines-cap-1001', [(T, '(define header-line-cap 1000)', '(define header-line-cap 1001)')],
       HEADERS, ['1,000 header lines are taken', 'a 103 head of 500 lines', 'a 100 head of 500 lines',
                 '998 trailers', 'a Digest round', 'a 417 of 500 lines', 'a CONNECT answer of 500 lines'])
mutant('lines-cap-999', [(T, '(define header-line-cap 1000)', '(define header-line-cap 999)')],
       HEADERS, ['1,000 header lines are taken', 'a 103 head of 500 lines', 'a 100 head of 500 lines',
                 '998 trailers', 'a Digest round', 'a 417 of 500 lines', 'a CONNECT answer of 500 lines'])
mutant('bytes-cap-102401', [(T, '(define header-byte-cap 102400)', '(define header-byte-cap 102401)')],
       HEADERS, ['a head of 102,400 bytes', 'one line of 102362', 'one line of 102366'])
mutant('bytes-cap-102399', [(T, '(define header-byte-cap 102400)', '(define header-byte-cap 102399)')],
       HEADERS, ['a head of 102,400 bytes', 'one line of 102362', 'one line of 102366'])

# --- the count per response, not per transfer: each status line starts it again ---------
mutant('count-per-response', [(T, '''            (status (sink-head-start-set! sink #f))
            (else (sink-head-start-set! sink #f)''', '''            (status (sink-head-start-set! sink #f)
                    (sink-header-lines-set! sink 0)
                    (sink-header-bytes-set! sink n))
            (else (sink-head-start-set! sink #f)''')],
       HEADERS, ['a 103 head of 500 lines', 'a 100 head of 500 lines', 'a 103 head of 150 lines',
                 'a Digest round', 'a 417 of 500 lines', 'a CONNECT answer of 500 lines'])

# --- the status line counted as a header line ----------------------------------------------
mutant('status-line-counted', [(T, '''            (status (sink-head-start-set! sink #f))
            (else (sink-head-start-set! sink #f)''', '''            (status (sink-head-start-set! sink #f)
                    (sink-header-lines-set! sink (+ (sink-header-lines sink) 1)))
            (else (sink-head-start-set! sink #f)''')],
       HEADERS, ['1,000 header lines are taken', 'a 103 head of 500 lines', 'a Digest round',
                 'a 417 of 500 lines', 'a CONNECT answer of 500 lines'])

# --- the reason not recorded: the line refused, libcurl's code alone -----------------------
mutant('reason-not-recorded', [(T, '''              ((not (count-header-line! sink data n))
               (record! key 'header-limit #f)
               0)''', '''              ((not (count-header-line! sink data n))
               0)''')],
       HEADERS, ['1,000 header lines are taken', 'a head of 102,400 bytes', 'the high level',
                 'by version, cap-h1', 'by version, cap-h2-head', 'by version, cap-h2-trailer'])

# --- a later call not refused once a reason is recorded ------------------------------------
mutant('later-call-taken', [(T, '''              ((not sink) 0)
              ((sink-recorded sink) 0)
              ((not (count-header-line! sink data n))''', '''              ((not sink) 0)
              ((not (count-header-line! sink data n))''')],
       HEADERS, ['a reason recorded at the head'])

# --- SUPPRESS_CONNECT_HEADERS taken by the hatch ---------------------------------------------
mutant('suppress-taken', [(T, '''              "COOKIE" "COOKIELIST" "COOKIESESSION"
              "SUPPRESS_CONNECT_HEADERS")''', '''              "COOKIE" "COOKIELIST" "COOKIESESSION")''')],
       ['tests/test-unsupported.sps', 'tests/test-transfer.sps'],
       ['each owned option and twin, written out here', 'HEADERFUNCTION and HEADERDATA, the header callable',
        'owned-option-names, written out'])

# --- header-limit of no class: the base type, as callback-raised is --------------------------
mutant('reason-unclassed', [(C, '''    (let ((make (case (if (memq reason '(body-limit header-limit))''',
                              '''    (let ((make (case (if (memq reason '(body-limit))''')],
       HEADERS + ['tests/test-conditions.sps'],
       ['1,000 header lines are taken', 'the class follows the code'])

# --- the origin's send limit left at Node's default --------------------------------------------
mutant('origin-send-limit-default', [(O, '''const H2_SEND_LIMIT = 64 << 20;''', '''const H2_SEND_LIMIT = 65536;''')],
       ['tests/test-origin-tls.sps'] + HEADERS,
       ['h2c GET /head?n=6000', 'h2 GET /head?n=6000', 'h2c GET /head?n=2&tn=6000', 'h2 GET /head?n=2&tn=6000',
        'HTTP/2: a head of 102,400 bytes'])

root = os.getcwd()
base = os.path.join(root, 'build', 'm8s2', 'mut')


def make(names):
    os.makedirs(base, exist_ok=True)
    jobs = []
    for m in M:
        if names and m['name'] not in names:
            continue
        d = os.path.join(base, m['name'])
        if os.path.exists(d):
            shutil.rmtree(d)
        os.makedirs(d)
        for sub in ('src', 'tests'):
            shutil.copytree(os.path.join(root, sub), os.path.join(d, sub), symlinks=True)
        for f, old, new in m['edits']:
            p = os.path.join(d, f)
            text = open(p, encoding='utf-8').read()
            if text.count(old) != 1:
                sys.exit(f"mutants: {m['name']}: {f}: expected one of {old[:60]!r}, found {text.count(old)}")
            open(p, 'w', encoding='utf-8').write(text.replace(old, new))
        for s in m['suites']:
            jobs.append(f"{m['name']} {s}")
        print(f"made {m['name']}: {len(m['edits'])} edit(s), suites {' '.join(m['suites'])}")
    with open(os.path.join(base, 'jobs'), 'w') as f:
        f.write('\n'.join(jobs) + '\n')


def check(names):
    for m in M:
        if names and m['name'] not in names:
            continue
        d = os.path.join(base, m['name'], 'logs')
        fails, exits = [], []
        for s in m['suites']:
            p = os.path.join(d, os.path.basename(s)[:-4] + '.log')
            if not os.path.exists(p):
                exits.append(f'{s}: no log')
                continue
            text = open(p, encoding='latin-1').read()
            fails += [l[5:] for l in text.split('\n') if l.startswith('FAIL ')]
            last = text.strip().split('\n')[-1]
            exits.append(f'{os.path.basename(s)} {last}')
        missed = [e for e in m['expect'] if not any(e in f for f in fails)]
        if m['name'] == 'control':
            verdict = 'clean' if not fails and all(x.endswith('exit 0') for x in exits) else 'NOT CLEAN'
        else:
            verdict = 'killed' if not missed and fails else 'SURVIVED'
        print(f"{m['name']}: {verdict}; {len(fails)} failing test(s); {'; '.join(exits)}"
              + (f"; expected failures missing: {missed}" if missed else ''))
        for f in fails[:12]:
            print(f'    FAIL {f[:160]}')


if __name__ == '__main__':
    if len(sys.argv) < 2 or sys.argv[1] not in ('make', 'check'):
        sys.exit(__doc__)
    (make if sys.argv[1] == 'make' else check)(sys.argv[2:])
