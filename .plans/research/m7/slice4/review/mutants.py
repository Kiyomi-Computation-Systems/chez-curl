#!/usr/bin/env python3
"""M7 slice 4's adversarial review: mutants the build's 86 did not make.

  python3 mutants.py make [NAME...]   copies the review tree's src/, tests/,
                                      packaging/ and .plans/decisions/ to
                                      build/m7s4-review/base/mut/NAME and
                                      applies NAME's edit, each old text
                                      required to stand exactly once
  python3 mutants.py list             prints NAME SUITE lines, the jobs

Run from the repository's root on the host. The review tree is
build/m7s4-review/base, an rsync of the working tree (README.md here).
"""
import os, shutil, subprocess, sys

E = 'src/curl/private/engine.sls'
T = 'src/curl/private/transfer.sls'
COOKIES = 'tests/test-cookies.sps'
M = []

def mutant(name, edits, suite, why):
    M.append(dict(name=name, edits=edits, suite=suite, why=why))

# 1. A jar message taken in the failing turn's batch, after the submit whose
#    set-up raised, is never answered: fail-engine! answers the queue alone.
mutant('fail-batch-unanswered',
       [(E, "(answer-jar-messages! engine (append (engine-batch engine) queued) failure)",
         "(answer-jar-messages! engine queued failure)")],
       COOKIES, 'a jar message in the batch of a failing turn: its caller waits for ever')

# 2. A jar message queued with no wakeup: carried out at the poll's end, up to 1 s late.
mutant('jar-no-wakeup',
       [(E, """                   (curl-engine-queue-set! engine
                                           (cons (list 'jar kind jar reply arg) (curl-engine-queue engine)))
                   (curl-multi-wakeup (engine-multi engine))
                   #f)""",
         """                   (curl-engine-queue-set! engine
                                           (cons (list 'jar kind jar reply arg) (curl-engine-queue engine)))
                   #f)""")],
       COOKIES, 'each jar message waits for the poll to time out')

# 3. The control bytes as an enumerated list: the six the suite tries.
mutant('control-enumerated',
       [(T, "((exists (lambda (c) (or (and (< c #x20) (not (= c 9))) (= c #x7F))) codes) 'control-byte)",
         "((exists (lambda (c) (memv c '(0 1 10 13 31 127))) codes) 'control-byte)")],
       COOKIES, 'U+0002 to U+0008, U+000B, U+000C, U+000E to U+001E taken')

# 4. The expiry's digits by char-numeric?, which takes Latin-1's other numerics.
mutant('expiry-char-numeric',
       [(T, "(for-all (lambda (c) (char<=? #\\0 c #\\9)) (string->list s))",
         "(for-all char-numeric? (string->list s))")],
       COOKIES, 'U+00B2 SUPERSCRIPT TWO as an expiry digit')

# 5. A hold let go twice: release! no longer removes the token from the table.
mutant('release-twice',
       [(E, """                            (hashtable-delete! (engine-holds engine) token)
                            (cookie-jar-holders-set! jar (- (cookie-jar-holders jar) 1))""",
         """                            (cookie-jar-holders-set! jar (- (cookie-jar-holders jar) 1))""")],
       COOKIES, "a failure at take-out!'s free step lets the hold go again")

# 6. No by-version row for this lane: every table must fail by name.
mutant('no-8.20.0-rows',
       [(COOKIES, '("8.20.0" . ((\"path-empty\"', '("8.20.0-gone" . ((\"path-empty\"'),
        (COOKIES, '("8.20.0" . (() ("a.localhost', '("8.20.0-gone" . (() ("a.localhost'),
        (COOKIES, '("8.20.0" . (200 200 (a-request a-request)))', '("8.20.0-gone" . (200 200 (a-request a-request)))'),
        (COOKIES, '("8.20.0/psl" .', '("8.20.0-gone/psl" .'),
        (COOKIES, '("8.20.0" . ((((\"a.localhost\\tFALSE\\t/cookies/a/b\\tFALSE', '("8.20.0-gone" . ((((\"a.localhost\\tFALSE\\t/cookies/a/b\\tFALSE')],
       COOKIES, 'each of the five tables fails by name on 8.20.0')

ROOT = os.getcwd()
BASE = os.path.join(ROOT, 'build/m7s4-review/base')
MUT = os.path.join(BASE, 'mut')

def make(names):
    os.makedirs(MUT, exist_ok=True)
    for m in M:
        if names and m['name'] not in names:
            continue
        dest = os.path.join(MUT, m['name'])
        for sub in ['src', 'tests', 'packaging', '.plans/decisions']:
            os.makedirs(os.path.join(dest, os.path.dirname(sub)), exist_ok=True)
            subprocess.run(['rsync', '-a', '--delete', os.path.join(BASE, sub) + '/',
                            os.path.join(dest, sub) + '/'], check=True)
        for path, old, new in m['edits']:
            p = os.path.join(dest, path)
            text = open(p, encoding='utf-8').read()
            n = text.count(old)
            if n != 1:
                sys.exit('%s: %s: the old text stands %d times' % (m['name'], path, n))
            open(p, 'w', encoding='utf-8').write(text.replace(old, new))
        print('made', m['name'])

if __name__ == '__main__':
    if sys.argv[1] == 'make':
        make(sys.argv[2:])
    elif sys.argv[1] == 'list':
        for m in M:
            print(m['name'], m['suite'])
