#!/usr/bin/env python3
# My mutants of M7 slice 4's build (2026-11-04), none among the builder's,
# on the copy in build/m7s4-check/tree (every file but build/, .git and
# .plans, made by rsync before this runs): each changes one place, runs
# test-cookies in the Guix container, keeps its log beside this script's
# results, and restores the file. "control" runs the copy unchanged.
#   python3 .plans/research/m7/slice4/verify/build-mutants.py control M...
import subprocess, sys, pathlib
tree = pathlib.Path('build/m7s4-check/tree')
results = pathlib.Path('.plans/research/m7/slice4/verify/results')
T = 'src/curl/private/transfer.sls'
E = 'src/curl/private/engine.sls'
MUTANTS = {
    # The jar's own handle never attached to the share: a load reaches the
    # handle's own jar, and a read-out reads it.
    'jar-handle-unattached': (T,
        "(define (jar-attach! easy share)\n    (set-option! easy (car (field-options 'cookie-jar)) share #f))",
        "(define (jar-attach! easy share)\n    (if #f #f))"),
    # The expiry's limit itself refused: 9223372036854775807 is the largest
    # a load takes.
    'expiry-limit-strict': (T,
        "(<= (string->number expiry 10) expiry-limit)",
        "(< (string->number expiry 10) expiry-limit)"),
    # A name and value of exactly 4,096 refused.
    'size-refuses-limit': (T,
        "((> (+ (string-length name) (string-length value)) cookie-line-limit) 'size)",
        "((>= (+ (string-length name) (string-length value)) cookie-line-limit) 'size)"),
    # The leading-dot rule read from the field as given, #HttpOnly_ and all.
    'leading-dot-reads-prefix': (T,
        "((not (eq? (char=? (string-ref domain 0) #\\.) (string=? tail \"TRUE\"))) 'leading-dot)",
        "((not (eq? (char=? (string-ref given 0) #\\.) (string=? tail \"TRUE\"))) 'leading-dot)"),
    # After the fix round (2026-11-04): mine, on the prefix rule.
    'host-path-prefix': (T,
        '(and (string=? secure "TRUE") (string=? path "/") (string=? tail "FALSE"))',
        '(and (string=? secure "TRUE") (string-starts? path "/") (string=? tail "FALSE"))'),
    'secure-prefix-reads-tail': (T,
        '((string-starts? folded "__secure-") (not (string=? secure "TRUE")))',
        '((string-starts? folded "__secure-") (not (string=? tail "TRUE")))'),
    # The review's four survivors, as its mutants.py has them, again.
    'fail-batch-unanswered': (E,
        "(answer-jar-messages! engine (append (engine-batch engine) queued) failure)",
        "(answer-jar-messages! engine queued failure)"),
    'control-enumerated': (T,
        "((exists (lambda (c) (or (and (< c #x20) (not (= c 9))) (= c #x7F))) codes) 'control-byte)",
        "((exists (lambda (c) (memv c '(0 1 10 13 31 127))) codes) 'control-byte)"),
    'expiry-char-numeric': (T,
        "(for-all (lambda (c) (char<=? #\\0 c #\\9)) (string->list s))",
        "(for-all char-numeric? (string->list s))"),
    'release-twice': (E,
        """                            (hashtable-delete! (engine-holds engine) token)
                            (cookie-jar-holders-set! jar (- (cookie-jar-holders jar) 1))""",
        """                            (cookie-jar-holders-set! jar (- (cookie-jar-holders jar) 1))"""),
}
def run(name, suites='tests/test-cookies.sps'):
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
    (results / ('build-mutant-%s.log' % name)).write_text(out)
    fails = [l for l in out.splitlines() if l.startswith('FAIL ')]
    summary = [l for l in out.splitlines() if l.startswith('test: ran')]
    print('%s: %d FAIL lines; %s' % (name, len(fails), summary[-1] if summary else 'no summary'))
    for l in fails[:6]:
        print('  ' + l[:220])
for n in sys.argv[1:]:
    run(n)
