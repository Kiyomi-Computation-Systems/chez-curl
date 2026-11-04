#!/usr/bin/env python3
# My mutants of M7 slice 3's second fix round (2026-11-03), on the copy in
# build/m7s3-check/tree: each puts one public accessor back to its raw Chez
# accessor, runs test-printed in the Guix container, and restores the file.
import subprocess, sys, pathlib
tree = pathlib.Path('build/m7s3-check/tree')
MUTANTS = {
    'raw-history': ('src/http-client/private/exchange.sls',
                    "(checked-accessor 'http-response-history http-response? \"a response\" unchecked-http-response-history)",
                    "unchecked-http-response-history"),
    'raw-connect-code': ('src/curl/private/conditions.sls',
                         "(checked-accessor 'curl-transfer-error-connect-code curl-transfer-error? \"a &curl-transfer-error\" unchecked-curl-transfer-error-connect-code)",
                         "unchecked-curl-transfer-error-connect-code"),
}
def run(name, suites='tests/test-printed.sps'):
    out_name = 'control' if name == 'control' else name
    if name != 'control':
        path, old, new = MUTANTS[name]
        f = tree / path
        text = f.read_text()
        assert text.count(old) == 1, (name, text.count(old))
        f.write_text(text.replace(old, new))
    try:
        out = subprocess.run(['scripts/guix-env', 'sh', '-c', "make test SUITES='%s'" % suites], cwd=tree,
                             stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True).stdout
    finally:
        if name != 'control':
            f.write_text(text)
    pathlib.Path('build/m7s3-check/mutant2-%s.log' % out_name).write_text(out)
    fails = [l for l in out.splitlines() if l.startswith('FAIL ')]
    summary = [l for l in out.splitlines() if l.startswith('test: ran')]
    print('%s: %d FAIL lines; %s' % (name, len(fails), summary[-1] if summary else 'no summary'))
    for l in fails[:4]:
        print('  ' + l[:200])
for n in sys.argv[1:]:
    run(n)
