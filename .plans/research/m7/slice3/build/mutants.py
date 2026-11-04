#!/usr/bin/env python3
"""build/m7s3b/mutants.py: M7 slice 3's mutants, each a (NAME FILE OLD NEW
SUITES) row. `mutants.py make NAME...` writes each one's copy under
build/m7s3b/mut/NAME (by mutate.py); `mutants.py list` names them."""
import os, subprocess, sys
T='src/curl/private/transfer.sls'
U='src/curl/private/url.sls'
P='tests/test-proxy.sps'
M = [
 ('flag', U, "(call-with-flagged-url 'proxy-url-reading input curlu-non-support-scheme",
             "(call-with-flagged-url 'proxy-url-reading input 0", [P]),
 ('scan-first', T, """                      (let scan ((i 0))
                        (when (< i (bytevector-length bytes))
                          (let ((b (bytevector-u8-ref bytes i)))""",
                   """                      (let scan ((i 1))
                        (when (< i (bytevector-length bytes))
                          (let ((b (bytevector-u8-ref bytes i)))""", [P]),
 ('scan-last', T, """                      (let scan ((i 0))
                        (when (< i (bytevector-length bytes))
                          (let ((b (bytevector-u8-ref bytes i)))""",
                  """                      (let scan ((i 0))
                        (when (< i (- (bytevector-length bytes) 1))
                          (let ((b (bytevector-u8-ref bytes i)))""", [P]),
 ('colon', T, "(and (= b #x3A) (eq? (car part) 'user))", "(and (= b #x3A) (eq? (car part) 'nobody))", [P]),
 ('utf8', T, "(unless (utf-8-bytes? bytes)", "(unless (or #t (utf-8-bytes? bytes))", [P]),
 ('empty', T, "(refuse-proxy who '(proxy user) 'credentials-empty))))", "(if #f #f))))", [P]),
 ('malformed', T, """                 (and high low
                      (loop (+ i 3) (cons (u8-list->bytevector (list (+ (* high 16) low))) chunks)))))""",
                  """                 (if (and high low)
                     (loop (+ i 3) (cons (u8-list->bytevector (list (+ (* high 16) low))) chunks))
                     (loop (+ i 1) (cons (string->utf8 "%") chunks)))))""", [P]),
 ('scheme', T, """        (unless (member scheme '("http" "https"))
          (refuse-proxy who 'proxy 'proxy-scheme))""", "", [P]),
 ('query', T, """                     (or (not query) (string=? query ""))""", """                     #t""", [P]),
 ('path', T, """        (unless (and (or (not path) (string=? path "/"))""", """        (unless (and #t""", [P]),
 ('pa-case', T, """(when (string=? (ascii-folded (car header)) "proxy-authorization")""",
                """(when (string=? (car header) "Proxy-Authorization")""", [P, 'tests/test-redirect.sps']),
 ('pa-drop', T, """                    (when (string=? (ascii-folded (car header)) "proxy-authorization")
                      (refuse-field who 'header-name (car header) 'proxy-authorization-header))
""", "", [P, 'tests/test-redirect.sps']),
 ('tls-without', T, """        (check-proxy-tls who (and reading (string=? (cadr reading) "https")) proxy-ca-file
                         proxy-verify)""", "", [P]),
 ('pk-proxy', T, "          (check-prior-knowledge-proxy who version reading)\n", "", [P]),
 ('noproxy', T, """(append (list (cons (car names) proxy) (cons (cadr names) "")""",
                """(append (list (cons (car names) proxy)""", [P]),
 ('port', U, "(when (and (not port) default)", "(when (and (not port) default #f)", [P]),
 ('connect-code', T, "(and (integer? code) (positive? code) (not (<= 200 code 299)) code))",
                     "(and (integer? code) (positive? code) (not (<= 200 code 299)) #f))", [P]),
 ('retry-rule', 'src/http-client/private/exchange.sls', """         (let ((status (curl-transfer-error-connect-code c)))""",
                """         (let ((status #f))""", [P, 'tests/test-retry.sps']),
 ('call-drop', 'src/http-client/private/call.sls', """                                                        ((hit 'proxy) #f)
""", "", [P]),
 ('next-request', 'src/http-client/private/exchange.sls', """                         'proxy-ca-file (curl-request-proxy-ca-file last)
""", "", [P]),
 ('copy-proxy', T, "(proxy (if (string? proxy) (string-copy proxy) proxy)))", "(proxy proxy))", [P]),
 ('copy-ca', T, "credentials (path-copy who 'proxy-ca-file proxy-ca-file) proxy-verify",
                "credentials (begin (path-copy who 'proxy-ca-file proxy-ca-file) proxy-ca-file) proxy-verify", [P]),
 ('value-url', T, """        (when (or (and user (not user-bytes)) (and password (not password-bytes)))
          (refuse-proxy who 'proxy 'proxy-url))""", """        (when (or (and user (not user-bytes)) (and password (not password-bytes)))
          (refuse-proxy who proxy 'proxy-url))""", [P]),
 ('env-proxy-ca', T, "        (check-ca-environment who 'proxy-ca-file proxy-ca-file proxy-verify)\n", "", [P]),
 ('constant', 'src/curl/private/constants.sls', "(define curlinfo-http-connectcode 2097174)",
              "(define curlinfo-http-connectcode 2097175)", ['tests/test-constants.sps']),
 ('verify-values', T, """                           (cons (car verify-names) (if verify 1 0))
                           (cons (cadr verify-names) (if verify 2 0)))""", """                           (cons (car verify-names) (if verify 1 0))
                           (cons (cadr verify-names) (if verify 1 0)))""", [P]),
 ('floor', T, "(define unshared-tunnel-floor #x081300)", "(define unshared-tunnel-floor #x081500)", [P]),
 ('order-user', T, "                (list (cons 'user user) (cons 'password password)))",
                   "                (list (cons 'password password) (cons 'user user)))", [P]),
 ('origin-decode', 'tests/origin.mjs', "const shown = basic === null ? `other:${escaped(latin1(values[0]))}` : `basic:${escaped(basic)}`;",
                   "const shown = `other:${escaped(latin1(values[0]))}`;", ['tests/test-origin.sps', P]),
 ('origin-keep', 'tests/origin.mjs', "  client.write(`HTTP/1.1 ${status} ${REASONS[status]}\\r\\n${challenge}Content-Length: ${body.length}\\r\\n\\r\\n${body}`);",
                 "  client.end(`HTTP/1.1 ${status} ${REASONS[status]}\\r\\n${challenge}Content-Length: ${body.length}\\r\\n\\r\\n${body}`);", ['tests/test-origin.sps']),
 ('origin-inner', 'tests/origin.mjs', "  if (tunnel && !tunnel.far.destroyed) {", "  if (false) {", ['tests/test-origin.sps', P]),
 ('rounds-follow', T, "      (when (and stream-buffer follow)", "      (when (and stream-buffer #f)", ['tests/test-stream.sps']),
 ('cookie-drop', 'src/http-client/private/exchange.sls', """            '("Authorization" "Cookie")))""", """            '("Authorization")))""", ['tests/test-redirect.sps']),
 ('last-arg-irritant', 'src/http-client.sls', """                             "the last argument is a procedure, of the session" 'proc))""",
                       """                             "the last argument is a procedure, of the session" proc))""", [P]),
 # the Docker lanes'
 ('stall-gnutls', T, """      ("8.5.0" "GnuTLS" (#f http/1.1 http/2))))""", """      ("8.5.1" "GnuTLS" (#f http/1.1 http/2))))""", [P]),
 ('stall-floor', T, """    '(("7.85.0" #f (#f http/2))""", """    '(("7.85.1" #f (#f http/2))""", [P]),
 ('stall-backend', T, """                        (or (not (cadr row)) (not (string? backend))
                            (string-prefix? (cadr row) backend))""", """                        #t""", [P]),
 ('fresh', T, """    (when (or (and (plan-upload plan) fresh) (assoc "FRESH_CONNECT" (plan-tunnel plan)))""",
              """    (when (and (plan-upload plan) fresh)""", [P]),
 ('forbid', T, """    (when (assoc "FORBID_REUSE" (plan-tunnel plan))""", """    (when (and #f (assoc "FORBID_REUSE" (plan-tunnel plan)))""", [P]),
 ('forbid-all', T, "(and reading #t) (and reading (caddr reading))", "(and reading #t) (and reading #t)", [P]),
 ('tls-in-tls-submit', T, "          (check-tls-in-tls who scheme reading version)\n",
                          "          (when (eq? who 'curl-request-check) (check-tls-in-tls who scheme reading version))\n", [P]),
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
