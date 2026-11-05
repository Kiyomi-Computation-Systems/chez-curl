#!/usr/bin/env python3
"""M7 slice 4's race fixes, their mutants: each a copy of the working tree
(every file but build/, .git and .plans) under build/m7s4r/mut/NAME/, with
one mutation, its mutation.diff beside it.

  python3 build/m7s4r/mut.py make [NAME ...]   make the copies
  python3 build/m7s4r/mut.py list               the names, rules and suites

The src/ mutants are M5 slice 4's (build/m5s4/mutate.py), each of a rule a
SIGINT child of test-group guards, matched to today's src exactly once;
the rest plant in the copy's tests or origin what the fixes defend against.
"""
import difflib
import importlib.util
import os
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'build', 'm7s4r', 'mut')
GROUP = 'tests/test-group.sps'
UPLOAD = 'tests/test-upload.sps'
ORIGIN = 'tests/origin.mjs'
TRANSFER = 'src/curl/private/transfer.sls'

spec = importlib.util.spec_from_file_location('m5', os.path.join(ROOT, 'build', 'm5s4', 'mutate.py'))
m5 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m5)
M5 = {name: (rule, suite, edits) for name, rule, suite, edits in m5.MUTANTS}

FROM_M5 = ['r4-guard-outside-section', 'r4-record-outside-section', 'f1-guard-outside-due',
           'turn-no-sections', 'f6-one-section', 'g7-admissions-one-section', 'r5-no-take-out',
           'r7-no-look', 'g1-parallel-no-closed', 'z-parallel-last-unfinished', 'z3-go-closed-after-admit']

MUTANTS = [('baseline', 'control: no mutation', 'test-group test-upload test-origin-tls', [])]
MUTANTS += [(name, 'M5: ' + M5[name][0], 'test-group', M5[name][2]) for name in FROM_M5]
MUTANTS += [
    # a collection planted in every hold: each holder sets the trip to 1 KiB
    # as its hold starts, so the main thread meets one before its call
    # blocks; quiet must fail
    ('plant-trip-in-hold', 'plant: a collection asked for in every hold', 'test-group', [
        (GROUP, """    (define (until-sent)
      (let wait ((n 0))""", """    (define (until-sent)
      (collect-trip-bytes 1024)
      (let wait ((n 0))""")]),
    # the SIGINT sent 3.5 s after ready, past every hold the children had:
    # with until-sent each child must still pass
    ('control-late-sigint', 'control: the SIGINT sent 3.5 s after ready', 'test-group', [
        (GROUP, '   "sleep 0.5\\n"\n   "kill -INT \\"$pid\\"\\n"', '   "sleep 3.5\\n"\n   "kill -INT \\"$pid\\"\\n"')]),
    # the same, with the hold back to a fixed 1 s: the children must fail
    ('plant-late-fixed-hold', 'plant: the SIGINT 3.5 s after ready, each hold 1 s', 'test-group', [
        (GROUP, '   "sleep 0.5\\n"\n   "kill -INT \\"$pid\\"\\n"', '   "sleep 3.5\\n"\n   "kill -INT \\"$pid\\"\\n"'),
        (GROUP, """        (unless (or (and child-sent (file-exists? child-sent)) (>= n 2000))""",
         """        (unless (>= n 100)""")]),
    # the body-asked bit read from the bytes handed, not libcurl's ask
    ('bit-from-handed', "the head's body-asked bit: bytes handed, not libcurl's ask", 'test-upload', [
        (TRANSFER, """(and up (upload-asked up) #t)))""", """(and up (> (upload-handed up) 0))))""")]),
    # the origin answers a held /answer at once
    ('origin-hold-ignored', "the origin: HTTP/2's /answer answers at once, hold or not", 'test-origin-tls test-upload', [
        (ORIGIN, """      if (r.hold === undefined) return h2Text(stream, r.status, `answer ${r.status}\\n`);""",
         """      if (true) return h2Text(stream, r.status, `answer ${r.status}\\n`);""")]),
    # the origin never answers a held /answer
    ('origin-hold-forever', "the origin: HTTP/2's held /answer never answers", 'test-origin-tls test-upload', [
        (ORIGIN, """          if (how === 'released' && !stream.destroyed) h2Text(stream, r.status, `answer ${r.status}\\n`);""",
         """          if (false) h2Text(stream, r.status, `answer ${r.status}\\n`);""")]),
]


def make(name, rule, suite, edits):
    dest = os.path.join(OUT, name)
    os.makedirs(dest, exist_ok=True)
    subprocess.run(['rsync', '-a', '--delete', '--exclude', '/build', '--exclude', '/.git', '--exclude', '/.plans',
                    ROOT + '/', dest + '/'], check=True)
    diffs = []
    for f, old, new in edits:
        path = os.path.join(dest, f)
        text = open(path).read()
        if text.count(old) != 1:
            sys.exit(f'mut.py: {name}: {f}: the old text occurs {text.count(old)} times')
        mutated = text.replace(old, new)
        open(path, 'w').write(mutated)
        diffs.extend(difflib.unified_diff(text.splitlines(True), mutated.splitlines(True), 'a/' + f, 'b/' + f))
    open(os.path.join(dest, 'mutation.diff'), 'w').write(''.join(diffs))
    open(os.path.join(dest, 'suites.txt'), 'w').write(' '.join('tests/' + s + '.sps' for s in suite.split()) + '\n')
    print(f'mut.py: made {name}: {rule}')


if __name__ == '__main__':
    if len(sys.argv) < 2 or sys.argv[1] not in ('make', 'list'):
        sys.exit(__doc__)
    names = sys.argv[2:]
    for name, rule, suite, edits in MUTANTS:
        if names and name not in names:
            continue
        if sys.argv[1] == 'list':
            print(name, '|', rule, '|', suite)
        else:
            make(name, rule, suite, edits)
