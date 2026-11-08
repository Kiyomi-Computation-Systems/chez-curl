#!/usr/bin/env python3
"""M8 slice 3's mutants, each watched failing. On the host, from the
repository's root:

    python3 .plans/research/m8/slice3/build/mutants.py OUT [NAME ...]

For each mutant (all, or the NAMEs given): copies the working tree, less
build/ and .git, to build/m8s3/mut/NAME, applies the mutant's exact text
replacements (each old text must stand there exactly once), runs `make deps`
and then each listed suite in the Guix container, under timeout, and writes
the suite's FAIL lines and exit status. A mutant is caught when at least one
listed suite exits non-zero, and every suite named as the catcher names a
FAIL line or dies. OUT is the log file. CPUs 12 to 17 alone, by taskset.
The control, the tree unchanged, runs every suite once first, and must
pass."""
import os, shutil, subprocess, sys, time

ROOT = os.getcwd()
MUT = os.path.join(ROOT, 'build', 'm8s3', 'mut')
T = 'src/curl/private/transfer.sls'
N = 'src/curl/private/native.sls'
E = 'src/curl/private/engine.sls'
C = 'src/http-client/private/call.sls'
D = 'tests/decoy-libcurl.c'
O = 'tests/origin.mjs'
X = 'src/http-client/private/exchange.sls'

MUTANTS = [
    ('probe-7-as-yes', [(N, "(and (eqv? (cdr (assq 'formadd mime-probe)) curl-formadd-ok)",
                         "(and (memv (cdr (assq 'formadd mime-probe)) (list curl-formadd-ok curl-formadd-disabled))")],
     ['tests/test-library-loading.sps']),
    ('probe-null-as-yes', [(N, "(eq? (cdr (assq 'mime-init mime-probe)) 'made)))",
                            "(memq (cdr (assq 'mime-init mime-probe)) '(made null))))")],
     ['tests/test-library-loading.sps']),
    ('probe-other-as-yes', [(N, "(and (eqv? (cdr (assq 'formadd mime-probe)) curl-formadd-ok)",
                             "(and (not (eqv? (cdr (assq 'formadd mime-probe)) curl-formadd-disabled))")],
     ['tests/test-library-loading.sps']),
    ('byte-low-edge-down', [(T, "(if (or (control-char? c) (and quoted (char=? c #\\\")))",
                             "(if (or (< (char->integer c) #x1F) (= (char->integer c) #x7F) (and quoted (char=? c #\\\")))")],
     ['tests/test-multipart.sps']),
    ('byte-low-edge-up', [(T, "(if (or (control-char? c) (and quoted (char=? c #\\\")))",
                           "(if (or (< (char->integer c) #x21) (= (char->integer c) #x7F) (and quoted (char=? c #\\\")))")],
     ['tests/test-multipart.sps']),
    ('byte-del-edge-down', [(T, "(if (or (control-char? c) (and quoted (char=? c #\\\")))",
                             "(if (or (< (char->integer c) #x20) (= (char->integer c) #x7E) (and quoted (char=? c #\\\")))")],
     ['tests/test-multipart.sps']),
    ('byte-del-edge-up', [(T, "(if (or (control-char? c) (and quoted (char=? c #\\\")))",
                           "(if (or (< (char->integer c) #x20) (>= (char->integer c) #x7F) (and quoted (char=? c #\\\")))")],
     ['tests/test-multipart.sps']),
    ('quote-let-in', [(T, "(if (or (control-char? c) (and quoted (char=? c #\\\")))",
                       "(if (or (control-char? c) (and quoted #f))")],
     ['tests/test-multipart.sps']),
    ('content-type-blank-kept', [(T, "(append (if (or (multipart? body) (named? \"Content-Type\")) '() '(\"Content-Type:\"))",
                                  "(append (if (named? \"Content-Type\") '() '(\"Content-Type:\"))")],
     ['tests/test-request.sps', 'tests/test-multipart.sps']),
    ('mimepost-not-last', [(T, """          (append (case method
                    ((head) (list (cons (car method-names) 1)))""",
                            """          (append (if (multipart? body) (list (cons (list-ref body-names 9) 'mime)) '())
                  (case method
                    ((head) (list (cons (car method-names) 1)))"""),
                           (T, "((multipart? body) (list (cons (list-ref body-names 9) 'mime)))",
                            "((multipart? body) '())")],
     ['tests/test-request.sps']),
    ('mime-freed-before-cleanup', [(T, """    (critical-section
     (let ((easy (live-transfer-easy live)))
       (when easy
         (curl-easy-cleanup easy)
         (live-transfer-easy-set! live #f))))
    (critical-section
     (let ((mime (live-transfer-mime live)))
       (when mime
         (curl-mime-free mime)
         (live-transfer-mime-set! live #f))))""",
                                    """    (critical-section
     (let ((mime (live-transfer-mime live)))
       (when mime
         (curl-mime-free mime)
         (live-transfer-mime-set! live #f))))
    (critical-section
     (let ((easy (live-transfer-easy live)))
       (when easy
         (curl-easy-cleanup easy)
         (live-transfer-easy-set! live #f))))""")],
     ['tests/test-transfer.sps', 'tests/test-multipart.sps']),
    ('engine-check-skipped', [(E, "                            (check-plan-files! (curl-token-plan token))\n", "")],
     ['tests/test-multipart.sps']),
    ('resolved-at-submit', [(T, "(body (if (and parts (not kept)) (multipart-paths-checked who parts #t) body)))",
                             "(body (if (and parts (not kept)) (begin (multipart-paths-checked who parts #t) parts) body)))"),
                            (T, "(multipart-paths-checked who (multipart-copy who body) #f))))))",
                             "(multipart-paths-checked who (multipart-copy who body) #t))))))")],
     ['tests/test-multipart.sps']),
    ('accessor-uncopied', [(T, "(if (multipart? body) (multipart-answer body) body)))))", "body))))")],
     ['tests/test-multipart.sps']),
    ('relative-refusal-removed', [(T, "(multipart-paths-checked who (multipart-copy who body) #f))))))",
                                   "(multipart-paths-checked who (multipart-copy who body) #t))))))")],
     ['tests/test-multipart.sps']),
    ('data-copied-when-made', [(T, "              (cond ((or (string? given-source) (bytevector? given-source)) given-source)",
                                "              (cond ((string? given-source) (string-copy given-source)) ((bytevector? given-source) (bytevector-copy given-source))")],
     ['tests/test-multipart.sps']),
    ('high-level-copies-at-each-submit', [(C, "(multipart-data-copied (curl-request-body checked))",
                                           "(curl-request-body checked)")],
     ['tests/test-multipart.sps']),
    ('session-content-type-kept', [(C, """                            (multipart-given
                             (filter (lambda (header) (not (ascii-ci=? (car header) "Content-Type")))
                                     (car merged)))
""", "")],
     ['tests/test-multipart.sps']),
    ('multipart-beside-form', [(C, "(when (and multipart-given (or body-given form-given))",
                                "(when (and multipart-given body-given)")],
     ['tests/test-multipart.sps']),
    ('decoy-switch-unread', [(D, "#if defined(DECOY_FORMADD_DISABLED)", "#if defined(DECOY_FORMADD_DISABLED_UNREAD)")],
     ['tests/test-library-loading.sps']),
    ('abandoned-mime-freed', [(T, """     (live-transfer-easy-set! live #f)
     (live-transfer-mime-set! live #f)))""", """     (live-transfer-easy-set! live #f)
     (let ((mime (live-transfer-mime live))) (when mime (curl-mime-free mime)))
     (live-transfer-mime-set! live #f)))""")],
     ['tests/test-multipart.sps']),
    ('mime-free-unowned', [(N, "    (check-owner 'curl-mime-free mime 'mime)\n", "")],
     ['tests/test-native.sps']),
    ('submit-stat-skipped', [(T, "                        (unless (file-regular? path)\n                          (refuse-part who i 'path 'part-file))\n",
                              "                        (unless (or (not resolve) (file-regular? path))\n                          (refuse-part who i 'path 'part-file))\n")],
     ['tests/test-multipart.sps']),
    ('submit-content-type-unchecked', [(T, "                            (check-multipart-content-type who (car fields))\n", "")],
     ['tests/test-multipart.sps']),
    ('unsupported-unchecked', [(T, "                            (check-multipart-supported who)\n", "")],
     ['tests/test-library-loading.sps']),
    ('mime-options-unowned', [(T, "\"HTTPPOST\" \"MIME_OPTIONS\" \"INFILESIZE\"", "\"HTTPPOST\" \"INFILESIZE\"")],
     ['tests/test-unsupported.sps', 'tests/test-transfer.sps']),
    ('filedata-as-mime-failed', [(T, "(fail (if (eq? (car answer) 'filedata) 'part-file 'mime-failed)",
                                  "(fail 'mime-failed")],
     ['tests/test-multipart.sps']),
    ('origin-bar-unescaped', [(O, "else if (b >= 0x20 && b < 0x7f && b !== 0x7c) text += String.fromCharCode(b);",
                               "else if (b >= 0x20 && b < 0x7f) text += String.fromCharCode(b);")],
     ['tests/test-origin.sps', 'tests/test-origin-tls.sps']),
    ('origin-hold-ignored', [(O, "    if (r.kind !== 'parts' || r.hold === undefined) {", "    if (true) {")],
     ['tests/test-origin.sps']),
    ('origin-fail-ignored', [(O, "  return r.fail !== undefined && n <= r.fail ? 503 : 200;", "  return 200;")],
     ['tests/test-origin.sps', 'tests/test-origin-tls.sps']),
    # The fix round's (the slice's review, and the coordinator's checks).
    ('engine-open-removed', [(T, """                        (unless (and (file-regular? path)
                                     (guard (e ((i/o-error? e) #f))
                                       (close-port (open-file-input-port path))
                                       #t))""", """                        (unless (file-regular? path)""")],
     ['tests/test-multipart.sps']),
    ('stat-guard-returned', [(T, "                        (unless (file-regular? path)\n                          (refuse-part who i 'path 'part-file))\n",
                              "                        (unless (guard (e (#t #f)) (file-regular? path))\n                          (refuse-part who i 'path 'part-file))\n")],
     ['tests/test-multipart.sps']),
    ('step-ignores-code', [(N, "(define (step label code rest) (if (eqv? code curle-ok) (rest) (cons label code)))",
                            "(define (step label code rest) (rest))")],
     ['tests/test-native.sps', 'tests/test-multipart.sps']),
    ('default-filename-whole-path', [(T, "(let ((default (path-last path)))", "(let ((default path))")],
     ['tests/test-multipart.sps']),
    ('c1-controls-refused', [(T, "(if (or (control-char? c) (and quoted (char=? c #\\\")))",
                              "(if (or (control-char? c) (<= #x80 (char->integer c) #x9F) (and quoted (char=? c #\\\")))")],
     ['tests/test-multipart.sps']),
    ('astral-refused', [(T, "(if (or (control-char? c) (and quoted (char=? c #\\\")))",
                         "(if (or (control-char? c) (> (char->integer c) #xFFFF) (and quoted (char=? c #\\\")))")],
     ['tests/test-multipart.sps']),
    ('origin-epilogue-miscounted', [(O, "          epilogue = body.length - (after + 2);", "          epilogue = body.length - (after + 1);")],
     ['tests/test-multipart.sps']),
    ('origin-preamble-miscounted', [(O, "      preamble = at;", "      preamble = at + 1;")],
     ['tests/test-multipart.sps']),
    ('table-row-dropped', [('tests/test-native.sps', """
        (list 'curl-mime-free 'curl-mime-free (lambda () (curl-mime-free mime)))))""", "))")],
     ['tests/test-native.sps']),
    # Item 4, the url key (ADR-0023, after slice 3's review).
    ('next-request-back-to-make', [(X, """      (apply curl-request-with last
             'url url
             'method (if dropped 'get method)
             'headers headers
             (append (if dropped '(body #f body-length #f) '())
                     (if across '(credentials #f) '())))))""", """      (make-curl-request url
                         'method (if dropped 'get method)
                         'headers headers
                         'body (if dropped #f (curl-request-body last))
                         'body-length (if dropped #f (curl-request-body-length last))
                         'stream-buffer (curl-request-stream-buffer last)
                         'user-agent (curl-request-user-agent last)
                         'timeout-ms (curl-request-timeout-ms last)
                         'connect-timeout-ms (curl-request-connect-timeout-ms last)
                         'body-limit (curl-request-body-limit last)
                         'ca-file (curl-request-ca-file last)
                         'verify (curl-request-verify last)
                         'proxy (curl-request-proxy last)
                         'http-version (curl-request-http-version last)
                         'credentials (if across #f (curl-request-credentials last))
                         'proxy-ca-file (curl-request-proxy-ca-file last)
                         'proxy-verify (curl-request-proxy-verify last)
                         'cookie-jar (curl-request-cookie-jar last))))""")],
     ['tests/test-multipart.sps']),
    ('url-key-ignored', [(T, "                    (if url (cdr url) (curl-request-url request)) (curl-request-fault request)",
                          "                    (curl-request-url request) (curl-request-fault request)")],
     ['tests/test-multipart.sps']),
    ('kept-body-restatted', [(T, """                           (let ((own (unchecked-curl-request-body request)))
                             (if (multipart? own) (make-kept-body own) own))))""",
                              """                           (curl-request-body request)))""")],
     ['tests/test-multipart.sps']),
]

SUITE_TIMEOUT = 900


def log(out, text):
    out.write(text + '\n')
    out.flush()
    print(text, flush=True)


def copy_tree(name):
    dest = os.path.join(MUT, name)
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    os.makedirs(dest)
    subprocess.run(['rsync', '-a', '--exclude', '/build', '--exclude', '/.git', ROOT + '/', dest + '/'], check=True)
    return dest


def apply(dest, edits):
    for path, old, new in edits:
        p = os.path.join(dest, path)
        s = open(p).read()
        n = s.count(old)
        if n != 1:
            return 'the old text stands %d times in %s: %r' % (n, path, old[:80])
        open(p, 'w').write(s.replace(old, new))
    return None


def run_suites(dest, suites):
    rel = os.path.relpath(dest, ROOT)
    script = ('(cd %s && make --no-print-directory deps >/dev/null 2>&1 && for t in %s; do '
              'echo "=== $t"; timeout --foreground %d "$CHEZ" --libdirs src:tests:build/scheme-libs --program "$t"; '
              'echo "exit=$t $?"; done)') % (rel, ' '.join(suites), SUITE_TIMEOUT)
    r = subprocess.run(['taskset', '-c', '12-17', 'scripts/guix-env', 'sh', '-c', script],
                       stdin=subprocess.DEVNULL, capture_output=True, text=True)
    return r.stdout + r.stderr


def verdicts(text, suites):
    found = {}
    current = None
    for line in text.split('\n'):
        if line.startswith('=== '):
            current = line[4:]
            found[current] = {'fails': [], 'exit': None}
        elif line.startswith('exit=') and current:
            found[current]['exit'] = int(line.rsplit(' ', 1)[1])
        elif line.startswith('FAIL ') and current:
            found[current]['fails'].append(line[5:])
    return found


def main():
    out_path = sys.argv[1]
    names = sys.argv[2:]
    chosen = [m for m in MUTANTS if not names or m[0] in names]
    os.makedirs(MUT, exist_ok=True)
    with open(out_path, 'a') as out:
        log(out, 'mutants start %s, %d chosen' % (time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), len(chosen)))
        if not names:
            suites = sorted({s for m in chosen for s in m[2]})
            dest = copy_tree('control')
            text = run_suites(dest, suites)
            v = verdicts(text, suites)
            ok = all(v.get(s, {}).get('exit') == 0 for s in suites)
            log(out, 'control: %s %s' % ('passes' if ok else 'FAILS', ' '.join('%s=%s' % (s, v.get(s, {}).get('exit')) for s in suites)))
            if not ok:
                log(out, text)
                sys.exit(1)
        caught = 0
        for name, edits, suites in chosen:
            dest = copy_tree(name)
            problem = apply(dest, edits)
            if problem:
                log(out, 'mutant %s: NOT APPLIED: %s' % (name, problem))
                continue
            start = time.time()
            text = run_suites(dest, suites)
            v = verdicts(text, suites)
            failing = [s for s in suites if v.get(s, {}).get('exit') not in (0, None)]
            log(out, 'mutant %s: %s in %.0f s' % (name, 'CAUGHT' if failing else 'SURVIVED', time.time() - start))
            for s in suites:
                info = v.get(s, {'fails': [], 'exit': None})
                log(out, '  %s exit=%s' % (s, info['exit']))
                for f in info['fails'][:6]:
                    log(out, '    FAIL ' + f[:300])
                if len(info['fails']) > 6:
                    log(out, '    ... and %d more' % (len(info['fails']) - 6))
            if failing:
                caught += 1
                shutil.rmtree(dest)
            else:
                log(out, text[-3000:])
        log(out, 'mutants done: %d of %d caught' % (caught, len(chosen)))


main()
