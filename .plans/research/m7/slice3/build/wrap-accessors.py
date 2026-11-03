#!/usr/bin/env python3
"""build/m7s3b/wrap-accessors.py: renames each listed record or condition
accessor to unchecked-NAME in its type's definition, and defines NAME after
the definition as checked-accessor's wrapper of it."""
import re, sys
ROOT = '/home/kishu/src/chez-curl/'

def block_end(s, i):
    depth = 0; j = i; instr = False; esc = False
    while j < len(s):
        c = s[j]
        if instr:
            if esc: esc = False
            elif c == '\\': esc = True
            elif c == '"': instr = False
        else:
            if c == '"': instr = True
            elif c == ';':
                while s[j] != '\n': j += 1
            elif c == '(': depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0: return j + 1
        j += 1
    raise SystemExit('unbalanced')

def wrap(path, head, pred, what, names, comment):
    p = ROOT + path
    s = open(p).read()
    i = s.find(head)
    assert i >= 0 and s.count(head) == 1, (path, head)
    j = block_end(s, i)
    block = s[i:j]
    for n in names:
        new, k = re.subn(r'(\s)' + re.escape(n) + r'\)', r'\1unchecked-' + n + ')', block)
        assert k == 1, (path, n, k)
        block = new
    defs = '\n\n' + comment + '\n' + '\n'.join(
        f"  (define {n}\n    (checked-accessor '{n} {pred} \"{what}\" unchecked-{n}))" for n in names)
    s = s[:i] + block + defs + s[j:]
    open(p, 'w').write(s)
    print(path, head, len(names))

COMMENT = """  ;; Each accessor checks its argument first: anything else is an assertion
  ;; violation from the accessor, naming it by its kind, shown-value's,
  ;; never printed, as Chez's own check printed it (ADR-0036, amended
  ;; 2026-11-03)."""

CO = 'src/curl/private/conditions.sls'
wrap(CO, '(define-condition-type &curl-library-unavailable', 'curl-library-unavailable?', 'a &curl-library-unavailable',
     ['curl-library-unavailable-reason', 'curl-library-unavailable-path', 'curl-library-unavailable-source',
      'curl-library-unavailable-detail', 'curl-library-unavailable-candidates', 'curl-library-unavailable-library'], COMMENT)
wrap(CO, '(define-condition-type &curl-wrong-thread', 'curl-wrong-thread?', 'a &curl-wrong-thread',
     ['curl-wrong-thread-who', 'curl-wrong-thread-expected', 'curl-wrong-thread-actual'], COMMENT)
wrap(CO, '(define-condition-type &curl-embedded-nul', 'curl-embedded-nul?', 'a &curl-embedded-nul',
     ['curl-embedded-nul-string'], COMMENT)
wrap(CO, '(define-condition-type &curl-url-error', 'curl-url-error?', 'a &curl-url-error',
     ['curl-url-error-input', 'curl-url-error-reason', 'curl-url-error-code', 'curl-url-error-message'], COMMENT)
wrap(CO, '(define-condition-type &curl-request-error', 'curl-request-error?', 'a &curl-request-error',
     ['curl-request-error-field', 'curl-request-error-value', 'curl-request-error-reason'], COMMENT)
wrap(CO, '(define-condition-type &curl-transfer-error', 'curl-transfer-error?', 'a &curl-transfer-error',
     ['curl-transfer-error-reason', 'curl-transfer-error-code', 'curl-transfer-error-option',
      'curl-transfer-error-strerror', 'curl-transfer-error-error-buffer', 'curl-transfer-error-recorded',
      'curl-transfer-error-request-size', 'curl-transfer-error-connect-code'], COMMENT)
wrap(CO, '(define-condition-type &curl-engine-error', 'curl-engine-error?', 'a &curl-engine-error',
     ['curl-engine-error-reason', 'curl-engine-error-condition'], COMMENT)

HC = 'src/http-client/private/conditions.sls'
wrap(HC, '(define-condition-type &http-request-error', 'http-request-error?', 'a &http-request-error',
     ['http-request-error-field', 'http-request-error-value', 'http-request-error-reason'], COMMENT)
wrap(HC, '(define-condition-type &http-redirect-error', 'http-redirect-error?', 'a &http-redirect-error',
     ['http-redirect-error-reason', 'http-redirect-error-response', 'http-redirect-error-location'], COMMENT)
wrap(HC, '(define-condition-type &http-timeout', 'http-timeout?', 'a &http-timeout',
     ['http-timeout-timeout-ms'], COMMENT)
wrap(HC, '(define-condition-type &http-group-error', 'http-group-error?', 'a &http-group-error',
     ['http-group-error-reason'], COMMENT)
wrap(HC, '(define-condition-type &http-exchange', 'http-exchange?', 'a &http-exchange',
     ['http-exchange-method', 'http-exchange-url', 'http-exchange-history', 'http-exchange-transfers'], COMMENT)

T = 'src/curl/private/transfer.sls'
wrap(T, '(define-record-type (curl-request new-curl-request curl-request?)', 'curl-request?', 'a request',
     ['curl-request-url', 'curl-request-method', 'curl-request-headers', 'curl-request-body',
      'curl-request-user-agent', 'curl-request-timeout-ms', 'curl-request-connect-timeout-ms',
      'curl-request-body-limit', 'curl-request-ca-file', 'curl-request-verify', 'curl-request-stream-buffer',
      'curl-request-body-length', 'curl-request-http-version', 'curl-request-proxy-verify'], COMMENT)
wrap(T, '(define-record-type (curl-response make-curl-response curl-response?)', 'curl-response?', 'a response',
     ['curl-response-status', 'curl-response-http-version', 'curl-response-effective-url',
      'curl-response-headers', 'curl-response-body', 'curl-response-timings'], COMMENT)
wrap(T, '(define-record-type (curl-head make-curl-head curl-head?)', 'curl-head?', 'a head',
     ['curl-head-status', 'curl-head-http-version', 'curl-head-headers', 'curl-head-body-asked?'], COMMENT)

X = 'src/http-client/private/exchange.sls'
wrap(X, '(define-record-type (http-response make-http-response http-response?)', 'http-response?', 'a response',
     ['http-response-status', 'http-response-http-version', 'http-response-url', 'http-response-headers',
      'http-response-body', 'http-response-timings', 'http-response-history'], COMMENT)
