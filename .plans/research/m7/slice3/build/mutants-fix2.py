#!/usr/bin/env python3
"""build/m7s3b/mutants-fix2.py: M7 slice 3's second fix round's mutants,
as mutants.py's rows. `mutants-fix2.py make NAME...`; `... list`."""
import subprocess, sys
T = 'src/curl/private/transfer.sls'
U = 'src/curl/private/url.sls'
CO = 'src/curl/private/conditions.sls'
HC = 'src/http-client/private/conditions.sls'
L = 'src/curl/private/libcurl-info.sls'
X = 'src/http-client/private/exchange.sls'
PR = 'tests/test-printed.sps'
M = [
 ('unwrapped-status', T, """  (define curl-response-status
    (checked-accessor 'curl-response-status curl-response? "a response" unchecked-curl-response-status))""",
                         """  (define curl-response-status unchecked-curl-response-status)""", [PR]),
 ('unwrapped-exchange-url', HC, """  (define http-exchange-url
    (checked-accessor 'http-exchange-url http-exchange? "a &http-exchange" unchecked-http-exchange-url))""",
                               """  (define http-exchange-url unchecked-http-exchange-url)""", [PR]),
 ('unwrapped-info-host', L, """  (define libcurl-info-host (checked 'libcurl-info-host unchecked-libcurl-info-host)))""",
                            """  (define libcurl-info-host unchecked-libcurl-info-host))""", [PR]),
 ('accessor-prints', CO, """        (assertion-violation who (string-append "not " what) (shown-value x)))
      (accessor x)))""", """        (assertion-violation who (string-append "not " what) x))
      (accessor x)))""", [PR]),
 ('info-shown-strings', L, """          ((string? x) '(kind string))""", """          ((string? x) x)""", [PR]),
 ('url-names-input', U, """                      (make-irritants-condition (list (if (pair? field) (car field) 'url))))))""",
                        """                      (make-irritants-condition (list input)))))""", [PR]),
 ('url-field-reference', U, """    (cond ((string=? what "a reference") 'reference)""", """    (cond ((string=? what "a reference") 'url)""", [PR]),
 ('row-dropped', PR, """    (curl-head-status 1 (assertion curl-head-status ((kind string))))\n""", "", [PR]),
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
