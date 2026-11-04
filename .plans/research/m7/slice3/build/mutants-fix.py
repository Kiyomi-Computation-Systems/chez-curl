#!/usr/bin/env python3
"""build/m7s3b/mutants-fix.py: M7 slice 3's fix round's mutants, each a
(NAME FILE OLD NEW SUITES) row, as mutants.py's. `mutants-fix.py make
NAME...` writes each one's copy under build/m7s3b/mut/NAME (by mutate.py);
`mutants-fix.py list` names them."""
import subprocess, sys
T = 'src/curl/private/transfer.sls'
E = 'src/curl/private/engine.sls'
CO = 'src/curl/private/conditions.sls'
HC = 'src/http-client/private/conditions.sls'
CALL = 'src/http-client/private/call.sls'
X = 'src/http-client/private/exchange.sls'
H = 'src/http-client.sls'
K = 'src/curl/private/constants.sls'
P = 'tests/test-proxy.sps'
TC = 'tests/test-conditions.sps'
THC = 'tests/test-http-client.sps'
TT = 'tests/test-transfer.sps'
TK = 'tests/test-constants.sps'
M = [
 # item 1, decision 11
 ('never-switch', E, "      (when (plan-unmultiplex (curl-token-plan token)) (stop-multiplexing! engine multi))\n", "", [P]),
 ('switch-every', T, "(and proxy-url userinfo (< version-number unshared-tunnel-floor) #t)",
                     "(and (< version-number unshared-tunnel-floor) #t)", [P]),
 ('switch-no-userinfo', T, "(and proxy-url userinfo (< version-number unshared-tunnel-floor) #t)",
                           "(and proxy-url (< version-number unshared-tunnel-floor) #t)", [P]),
 ('switch-all-versions', T, "(and proxy-url userinfo (< version-number unshared-tunnel-floor) #t)",
                            "(and proxy-url userinfo #t)", [P]),
 ('switch-resumes', E, "      (locked (curl-engine-lock engine) (lambda () (engine-multiplexing-set! engine 'switched)))))",
                       "      (locked (curl-engine-lock engine) (lambda () (engine-multiplexing-set! engine 'default)))))", [P]),
 # item 2, a caller's value named by its kind or field
 ('key-low', T, "(refuse-field who 'key (shown-key key) 'unknown-key)", "(refuse-field who 'key key 'unknown-key)", [P]),
 ('key-high', CALL, "(refuse who 'key (shown-key key) 'unknown-key", "(refuse who 'key key 'unknown-key", [P, THC]),
 ('shown-strings', CO, "(if (or (shown-atom? x) (and (list? x) (for-all shown-atom? x)))",
                       "(if (or (string? x) (shown-atom? x) (and (list? x) (for-all shown-atom? x)))", [TC, P]),
 ('shown-lists', CO, "(if (or (shown-atom? x) (and (list? x) (for-all shown-atom? x)))",
                     "(if (or (shown-atom? x) (list? x))", [TC, P]),
 ('shown-key-numbers', CO, "(if (symbol? x) x (list 'kind (kind-of x))))",
                           "(if (or (symbol? x) (number? x)) x (list 'kind (kind-of x))))", [TC, P]),
 ('shown-strings-high', HC, "(if (or (shown-atom? x) (and (list? x) (for-all shown-atom? x)))",
                            "(if (or (string? x) (shown-atom? x) (and (list? x) (for-all shown-atom? x)))", [THC]),
 ('header-value', T, "(refuse-field who 'header-value (car header) problem)",
                     "(refuse-field who 'header-value (cdr header) problem)", [P, TT]),
 ('headers-wrong', T, """  (define (snapshot who headers user-agent)
    (define (wrong message irritant) (assertion-violation who message (shown-value irritant)))""",
                      """  (define (snapshot who headers user-agent)
    (define (wrong message irritant) (assertion-violation who message irritant))""", [P]),
 ('submit-request', T, """      (assertion-violation who "not a request" (shown-value request)))
    (let* ((url (string-copy (curl-request-url request)))""",
                       """      (assertion-violation who "not a request" request))
    (let* ((url (string-copy (curl-request-url request)))""", [P]),
 ('not-a-session', H, '(assertion-violation who "not a session" (shown-value x))', '(assertion-violation who "not a session" x)', [P]),
 ('not-a-token', E, '(assertion-violation who "not a token" (shown-value x))', '(assertion-violation who "not a token" x)', [P]),
 ('hatch-wrong', T, "(cons name (shown-value value))", "(cons name value)", [P]),
 ('body-kind', CALL, "(else (refuse who 'body (shown-value value) 'not-a-body", "(else (refuse who 'body value 'not-a-body", [P]),
 # item 3
 ('next-verify', X, """                         'proxy-ca-file (curl-request-proxy-ca-file last)
                         'proxy-verify (curl-request-proxy-verify last))))""",
                    """                         'proxy-ca-file (curl-request-proxy-ca-file last)
                         )))""", [P]),
 # item 4
 ('no-lane', P, '(define lane (if (and (string? version) (string? backend)) (string-append version "/" backend) version))',
                '(define lane "0.0.0/none")', [P]),
 ('no-version-code', P, "(let ((row (assoc version refused-rows)))", "(let ((row (assoc \"0.0.0\" refused-rows)))", [P]),
 # item 5
 ('https-check-drop', T, """        (check-https-proxy who (and reading (string=? (cadr reading) "https"))
                           (libcurl-info-features (loaded-libcurl)))
""", "", [TT]),
 ('https-always', T, "(not (zero? (bitwise-and features curl-version-https-proxy))))", "#t)", [P]),
 ('https-constant', K, "(define curl-version-https-proxy #x00200000)", "(define curl-version-https-proxy #x00100000)", [TK, P]),
]
byname = {m[0]: m for m in M}
if sys.argv[1] == 'list':
    for m in M: print(m[0], m[1], ' '.join(m[4]))
    sys.exit(0)
for name in sys.argv[2:]:
    n, f, old, new, suites = byname[name]
    d = 'build/m7s3b/mutdefs'
    open(f'{d}/{n}.old', 'w').write(old)
    open(f'{d}/{n}.new', 'w').write(new)
    r = subprocess.run(['python3', 'build/m7s3b/mutate.py', n, f, f'{d}/{n}.old', f'{d}/{n}.new'], capture_output=True, text=True)
    print(n, (r.stdout + r.stderr).strip(), 'suites:', ' '.join(suites))
