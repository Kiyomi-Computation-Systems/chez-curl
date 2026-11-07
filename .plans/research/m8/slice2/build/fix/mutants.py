#!/usr/bin/env python3
"""M8 slice 2's review fixes' mutants: each a copy of src/ and tests/ with one
rule broken, the suites that must notice, and the tests that must fail; a
mutant marked survives must pass every suite, to show what a check misses.

  fix/mutants.py make [NAME...]   copy and mutate each (all by default) under
                                  build/m8s2/mutfix/NAME; write its jobs file
  fix/mutants.py check [NAME...]  read each mutant's logs: killed when every
                                  expected test failed, by name, else SURVIVED

The jobs run in the container, two at a time, by ../mut-run.sh:
  scripts/guix-env sh .plans/research/m8/slice2/build/mut-run.sh build/m8s2/mutfix/jobs < /dev/null
From the repository's root, on the host. mut-run.sh runs each job in
build/m8s2/mut/NAME, so make links build/m8s2/mut/fix-NAME to each copy and
names the jobs fix-NAME."""
import os, shutil, sys

T = 'src/curl/private/transfer.sls'
O = 'tests/origin.mjs'
R = 'tests/test-origin.sps'

HEADERS = 'tests/test-headers.sps'
ORIGIN = 'tests/test-origin.sps'
TRANSFER = 'tests/test-transfer.sps'
M = []


def mutant(name, edits, suites, expect, survives=False):
    M.append(dict(name=name, edits=edits, suites=suites, expect=expect, survives=survives))


mutant('control', [], [HEADERS, ORIGIN, TRANSFER, 'tests/test-origin-tls.sps'], [])

# --- 1: a status line exempt anywhere in a head, not at its start alone -------------------
mutant('start-dropped', [(T, '(status (and (not empty) start (status-line? data n)))',
                          '(status (and (not empty) (status-line? data n)))')],
       [HEADERS], ['1,000 header lines named HTTP/1.1 x-NNNNNN'])

# --- 2: status-line? back to an HTTP/ prefix -----------------------------------------------
STATUS = '''  (define (status-line? data n)
    (and (>= n 7)
         (let* ((k (min n 9))
                (bytes (make-bytevector k)))
           (copy-foreign->bytevector! data bytes 0 k)
           (let ((digit? (lambda (i) (<= 48 (bytevector-u8-ref bytes i) 57)))
                 (is? (lambda (i b) (= (bytevector-u8-ref bytes i) b))))
             (and (is? 0 72) (is? 1 84) (is? 2 84) (is? 3 80) (is? 4 47) (digit? 5)
                  (or (is? 6 32)
                      (and (= k 9) (is? 6 46) (digit? 7) (is? 8 32))))))))'''
mutant('status-prefix', [(T, STATUS, '''  (define (status-line? data n)
    (and (>= n 5)
         (let ((bytes (make-bytevector 5)))
           (copy-foreign->bytevector! data bytes 0 5)
           (bytevector=? bytes (string->utf8 "HTTP/")))))''')],
       [HEADERS], ["a trailer section's first line named HTTP/x"])
# Each real status line still exempt: HTTP/1.0's, and HTTP/2's short form.
mutant('status-1.1-only', [(T, '(and (= k 9) (is? 6 46) (digit? 7) (is? 8 32))',
                            '(and (= k 9) (is? 6 46) (is? 7 49) (is? 8 32))')],
       [HEADERS], ['HTTP/1.0: a head of 1,000 header lines'])
mutant('status-no-short-form', [(T, '''                  (or (is? 6 32)
                      (and (= k 9)''', '''                  (or #f
                      (and (= k 9)''')],
       [HEADERS], ['HTTP/2: 1,000 header lines are taken'])

# --- 4: the route and this suite's generator one byte short together ------------------------
SHORT = [(O, '''    let left = spec.total - (spec.slen === undefined ? slen : spec.slen) - 2 - (fixed ? headLineBytes(fixed) : 0)
      - (spec.big === undefined ? 0 : spec.big);''', '''    let left = spec.total - (spec.slen === undefined ? slen : spec.slen) - 2 - (fixed ? headLineBytes(fixed) : 0)
      - (spec.big === undefined ? 0 : spec.big) - (spec.total > 100000 ? 1 : 0);'''),
         (R, '(let loop ((left (- total 17 2 19)) (i 1) (lines \'()))',
          '(let loop ((left (- total 17 2 19 (if (> total 100000) 1 0))) (i 1) (lines \'()))')]
mutant('route-short', SHORT, [ORIGIN],
       ['raw /raw/head?total=102400&line=256', 'raw /raw/head?total=102401&line=256'])
# The rows as they were, the generator's length: the same plant passes.
mutant('route-short-old-rows', SHORT + [(R, "         (list total 'same 'eof)", "         (list (string-length want) 'same 'eof)")],
       [ORIGIN], [], survives=True)

# --- 5: the header seams' refusals removed ----------------------------------------------------
mutant('mark-request-unchecked', [(T, '''    (unless (curl-request? request)
      (assertion-violation 'curl-request-with-head-mark "not a request" (shown-value request)))''', '')],
       [TRANSFER], ["the header seams' refusals"])
mutant('mark-line-unchecked', [(T, '''    (unless (chunk-fault? n)
      (assertion-violation 'curl-request-with-head-mark "a head's line is a positive exact integer" n))''', '')],
       [TRANSFER], ["the header seams' refusals"])
mutant('mark-zero-taken', [(T, '''    (and (list? x) (= (length x) 2) (eq? (car x) 'mark) (chunk-fault? (cadr x))))''',
                            '''    (and (list? x) (= (length x) 2) (eq? (car x) 'mark) (integer? (cadr x)) (exact? (cadr x)) (>= (cadr x) 0)))''')],
       [TRANSFER], ["a request's checks refuse a header seam's fault"])
mutant('head-fault-request-unchecked', [(T, '''    (unless (curl-request? request)
      (assertion-violation 'curl-request-with-head-fault "not a request" (shown-value request)))''', '')],
       [TRANSFER], ["the header seams' refusals"])
mutant('head-fault-line-unchecked', [(T, '''    (unless (chunk-fault? n)
      (assertion-violation 'curl-request-with-head-fault "a head's line is a positive exact integer" n))''', '')],
       [TRANSFER], ["the header seams' refusals"])
mutant('head-zero-taken', [(T, '''    (and (list? x) (= (length x) 2) (eq? (car x) 'head) (chunk-fault? (cadr x))))''',
                            '''    (and (list? x) (= (length x) 2) (eq? (car x) 'head) (integer? (cadr x)) (exact? (cadr x)) (>= (cadr x) 0)))''')],
       [TRANSFER], ["a request's checks refuse a header seam's fault"])

root = os.getcwd()
base = os.path.join(root, 'build', 'm8s2', 'mutfix')
links = os.path.join(root, 'build', 'm8s2', 'mut')


def make(names):
    os.makedirs(base, exist_ok=True)
    os.makedirs(links, exist_ok=True)
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
        # test-origin's SIGKILL tests start a child Chez from the copy's
        # root, its library path holding build/scheme-libs.
        os.makedirs(os.path.join(d, 'build'))
        os.symlink(os.path.join(root, 'build', 'scheme-libs'), os.path.join(d, 'build', 'scheme-libs'))
        for f, old, new in m['edits']:
            p = os.path.join(d, f)
            text = open(p, encoding='utf-8').read()
            if text.count(old) != 1:
                sys.exit(f"mutants: {m['name']}: {f}: expected one of {old[:60]!r}, found {text.count(old)}")
            open(p, 'w', encoding='utf-8').write(text.replace(old, new))
        link = os.path.join(links, 'fix-' + m['name'])
        if os.path.islink(link):
            os.unlink(link)
        os.symlink(d, link)
        for s in m['suites']:
            jobs.append(f"fix-{m['name']} {s}")
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
        clean = not fails and all(x.endswith('exit 0') for x in exits)
        if m['name'] == 'control':
            verdict = 'clean' if clean else 'NOT CLEAN'
        elif m['survives']:
            verdict = 'survives, as it should' if clean else 'KILLED, not as expected'
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
