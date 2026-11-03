#!/usr/bin/env python3
# My mutants of M7 slice 3's build (2026-11-03), on the copy in
# build/m7s3-check/tree: each replaces one string that must occur once,
# runs the named suites in the Guix container, and restores the file.
#   python3 build/m7s3-check/mutants.py NAME...    (from the repository's root)
import subprocess, sys, pathlib

tree = pathlib.Path('build/m7s3-check/tree')
T = 'src/curl/private/transfer.sls'
X = 'src/http-client/private/exchange.sls'
MUTANTS = {
    'noproxy-gone': (T, '(append (list (cons (car names) proxy) (cons (cadr names) "")',
                     '(append (list (cons (car names) proxy)', ['tests/test-proxy.sps']),
    'password-unscanned': (T, "(list (cons 'user user) (cons 'password password)))",
                           "(list (cons 'user user)))", ['tests/test-proxy.sps']),
    'connect-code-ignored': (X, '(let ((status (curl-transfer-error-connect-code c)))',
                             '(let ((status #f))', ['tests/test-proxy.sps', 'tests/test-retry.sps']),
    'scheme-refusal-holds-url': (T, "(refuse-proxy who 'proxy 'proxy-scheme)",
                                 "(refuse-proxy who proxy 'proxy-scheme)", ['tests/test-proxy.sps']),
}

def run(name):
    path, old, new, suites = MUTANTS[name]
    f = tree / path
    text = f.read_text()
    assert text.count(old) == 1, (name, text.count(old))
    f.write_text(text.replace(old, new))
    try:
        cmd = "make test SUITES='%s'" % ' '.join(suites)
        out = subprocess.run(['scripts/guix-env', 'sh', '-c', cmd], cwd=tree, stdin=subprocess.DEVNULL,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True).stdout
    finally:
        f.write_text(text)
    log = pathlib.Path('build/m7s3-check/mutant-%s.log' % name)
    log.write_text(out)
    fails = [l for l in out.splitlines() if l.startswith('FAIL ')]
    summary = [l for l in out.splitlines() if l.startswith('test: ran')]
    print('mutant %s: %d FAIL lines; %s' % (name, len(fails), summary[-1] if summary else 'no summary'))
    for l in fails[:6]:
        print('  ' + l[:220])

for n in sys.argv[1:]:
    run(n)
