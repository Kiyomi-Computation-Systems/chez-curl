#!/usr/bin/env python3
"""Make the research copies of the snapshot, build/carried-guard/snap (29f4b5d).

  python3 make_copies.py VARIANT...

VARIANT is one of:
  today   the snapshot with the seam alone: (curl private gate), called at
          call-state's enter and exit, and at a URL parse's parse and
          parse-end (probe/gate.sls)
  a       today's seam, and call-state's work inside one critical section,
          its guard inside it, every raise answered as data and raised once
          the section has ended (option a)
  b       today's seam, and no guard spanning call-state: each high-level
          refusal raised compounded where it is made, each (curl) call of the
          checks answered as data from a section of its own (option b)
  a-*     option a's mutants, named in MUTANTS below
Each goes to build/carried-guard/VARIANT, replaced whole. Nothing outside
build/carried-guard is written. Every edit must match exactly once, or the
script stops.
"""
import os
import shutil
import subprocess
import sys

ROOT = '/home/kishu/src/chez-curl'
SNAP = ROOT + '/build/carried-guard/snap'
HERE = os.path.dirname(os.path.abspath(__file__))


def edit(path, old, new, count=1):
    with open(path) as f:
        text = f.read()
    n = text.count(old)
    if n != count:
        sys.exit(f'make_copies: {path}: expected {count} match(es), found {n}:\n{old}')
    with open(path, 'w') as f:
        f.write(text.replace(old, new))


def seam(dest):
    shutil.copy(HERE + '/gate.sls', dest + '/src/curl/private/gate.sls')
    url = dest + '/src/curl/private/url.sls'
    edit(url, """          (curl private constants)
          (curl private native))
""", """          (curl private constants)
          (curl private native)
          (curl private gate))
""")
    edit(url, """        (lambda ()
          (set-url-flagged! handle string flags)
          (proc handle))
        (lambda ()
          (set! freed #t)
          (curl-url-cleanup handle)))))
""", """        (lambda ()
          (run-gate! 'parse)
          (call-with-values
            (lambda ()
              (set-url-flagged! handle string flags)
              (proc handle))
            (lambda vs (run-gate! 'parse-end) (apply values vs))))
        (lambda ()
          (set! freed #t)
          (curl-url-cleanup handle)))))
""")
    hc = dest + '/src/http-client.sls'
    edit(hc, """          (http-client private drive))
""", """          (http-client private drive)
          (curl private gate)
          (only (chezscheme) critical-section))
""")


TODAY_STATE = """  (define (call-state session method url plist check? mode who)
    (let* ((start (monotonic-ns))
           (given (if (string? url) (string-copy url) url)))
      (guard (e ((condition? e)
                 (raise (condition e (make-http-exchange method given '() 0)))))
        (check-session who session)
        (let-values (((request redirects allow-downgrade retry producer)
                      (call-request-of who mode session method given plist)))
          (when check? (curl-request-check request))
          (cons (make-exchange method given request (curl-request-timeout-ms request)
                               start redirects allow-downgrade retry)
                producer)))))
"""

TODAY_SEAMED = """  (define (call-state session method url plist check? mode who)
    (let* ((start (monotonic-ns))
           (given (if (string? url) (string-copy url) url)))
      (guard (e ((condition? e)
                 (raise (condition e (make-http-exchange method given '() 0)))))
        (run-gate! 'enter)
        (check-session who session)
        (let-values (((request redirects allow-downgrade retry producer)
                      (call-request-of who mode session method given plist)))
          (when check? (curl-request-check request))
          (run-gate! 'exit)
          (cons (make-exchange method given request (curl-request-timeout-ms request)
                               start redirects allow-downgrade retry)
                producer)))))
"""

# Option a: one critical section; the guard inside it; every raise answered
# as data, (refused X), and raised once the section has ended.
A_STATE = """  (define (call-state session method url plist check? mode who)
    (let* ((start (monotonic-ns))
           (given (if (string? url) (string-copy url) url))
           (made (critical-section
                  (guard (e (#t (list 'refused
                                      (if (condition? e)
                                          (condition e (make-http-exchange method given '() 0))
                                          e))))
                    (run-gate! 'enter)
                    (check-session who session)
                    (let-values (((request redirects allow-downgrade retry producer)
                                  (call-request-of who mode session method given plist)))
                      (when check? (curl-request-check request))
                      (run-gate! 'exit)
                      (list 'made
                            (cons (make-exchange method given request (curl-request-timeout-ms request)
                                                 start redirects allow-downgrade retry)
                                  producer)))))))
      (if (eq? (car made) 'refused)
          (raise (cadr made))
          (cadr made))))
"""

# Option a's mutants: each breaks one rule of the fix.
MUTANTS = {
    # The guard outside the section: a Ctrl-C made pending inside it runs
    # as it ends, still inside the guard.
    'a-guard-outside': """  (define (call-state session method url plist check? mode who)
    (let* ((start (monotonic-ns))
           (given (if (string? url) (string-copy url) url))
           (made (guard (e (#t (list 'refused
                                      (if (condition? e)
                                          (condition e (make-http-exchange method given '() 0))
                                          e))))
                  (critical-section
                    (run-gate! 'enter)
                    (check-session who session)
                    (let-values (((request redirects allow-downgrade retry producer)
                                  (call-request-of who mode session method given plist)))
                      (when check? (curl-request-check request))
                      (run-gate! 'exit)
                      (list 'made
                            (cons (make-exchange method given request (curl-request-timeout-ms request)
                                                 start redirects allow-downgrade retry)
                                  producer)))))))
      (if (eq? (car made) 'refused)
          (raise (cadr made))
          (cadr made))))
""",
    # The refusal raised inside the section, from the guard's clause: the
    # caller's handler then runs with interrupts off.
    'a-raise-inside': """  (define (call-state session method url plist check? mode who)
    (let* ((start (monotonic-ns))
           (given (if (string? url) (string-copy url) url))
           (made (critical-section
                  (guard (e (#t (raise (if (condition? e)
                                           (condition e (make-http-exchange method given '() 0))
                                           e))))
                    (run-gate! 'enter)
                    (check-session who session)
                    (let-values (((request redirects allow-downgrade retry producer)
                                  (call-request-of who mode session method given plist)))
                      (when check? (curl-request-check request))
                      (run-gate! 'exit)
                      (list 'made
                            (cons (make-exchange method given request (curl-request-timeout-ms request)
                                                 start redirects allow-downgrade retry)
                                  producer)))))))
      (if (eq? (car made) 'refused)
          (raise (cadr made))
          (cadr made))))
""",
    # The section around the URL's checks alone, the keys and the body
    # outside it: what a handler raises during the keys' checks is
    # compounded again.
    'a-section-late': None,  # built below from call.sls
    # No compounding: the refusal raised bare.
    'a-no-compound': """  (define (call-state session method url plist check? mode who)
    (let* ((start (monotonic-ns))
           (given (if (string? url) (string-copy url) url))
           (made (critical-section
                  (guard (e (#t (list 'refused e)))
                    (run-gate! 'enter)
                    (check-session who session)
                    (let-values (((request redirects allow-downgrade retry producer)
                                  (call-request-of who mode session method given plist)))
                      (when check? (curl-request-check request))
                      (run-gate! 'exit)
                      (list 'made
                            (cons (make-exchange method given request (curl-request-timeout-ms request)
                                                 start redirects allow-downgrade retry)
                                  producer)))))))
      (if (eq? (car made) 'refused)
          (raise (cadr made))
          (cadr made))))
""",
}

# a-section-late: today's guard and no section around call-state, but the
# section is entered only after the keys, the body, the form, the params and
# the policies are checked: a guard spanning a window with interrupts on.
A_SECTION_LATE_STATE = """  (define (call-state session method url plist check? mode who)
    (let* ((start (monotonic-ns))
           (given (if (string? url) (string-copy url) url))
           (made (guard (e (#t (list 'refused
                                      (if (condition? e)
                                          (condition e (make-http-exchange method given '() 0))
                                          e))))
                    (run-gate! 'enter)
                    (check-session who session)
                    (let-values (((request redirects allow-downgrade retry producer)
                                  (call-request-of who mode session method given plist)))
                      (critical-section
                       (when check? (curl-request-check request))
                       (run-gate! 'exit)
                       (list 'made
                             (cons (make-exchange method given request (curl-request-timeout-ms request)
                                                  start redirects allow-downgrade retry)
                                   producer)))))))
      (if (eq? (car made) 'refused)
          (raise (cadr made))
          (cadr made))))
"""

# Option b: call-state holds no guard. call-request-of takes COMPOUND, which
# compounds a condition with the call's &http-exchange; every high-level
# refusal it makes is raised compounded where it is made; each (curl) call
# runs in answered, a section of its own whose guard answers its raise as
# data, raised compounded once the section has ended.
B_STATE = """  (define (call-state session method url plist check? mode who)
    (let* ((start (monotonic-ns))
           (given (if (string? url) (string-copy url) url))
           (compound (lambda (c)
                       (if (condition? c) (condition c (make-http-exchange method given '() 0)) c))))
      (run-gate! 'enter)
      (unless (http-session? session)
        (raise (compound (condition (make-assertion-violation) (make-who-condition who)
                                    (make-message-condition "not a session")
                                    (make-irritants-condition (list (shown-value session)))))))
      (let-values (((request redirects allow-downgrade retry producer)
                    (call-request-of who mode session method given plist compound)))
        (when check? (answered compound (lambda () (curl-request-check request))))
        (run-gate! 'exit)
        (cons (make-exchange method given request (curl-request-timeout-ms request)
                             start redirects allow-downgrade retry)
              producer))))
"""


def option_b_call(dest):
    call = dest + '/src/http-client/private/call.sls'
    edit(call, """          call-request-of group-keys group-limit)
""", """          call-request-of group-keys group-limit answered)
""")
    # refuse takes an optional COMPOUND.
    edit(call, """  (define (refuse who field value reason message)
    (raise (condition (make-http-request-error field value reason)
                      (make-who-condition who)
                      (make-message-condition message)
                      (make-irritants-condition (list value)))))
""", """  (define (refuse who field value reason message . compound)
    (let ((c (condition (make-http-request-error field value reason)
                        (make-who-condition who)
                        (make-message-condition message)
                        (make-irritants-condition (list value)))))
      (raise (if (pair? compound) ((car compound) c) c))))

  ;; answered : (Condition -> Condition) (-> Any) -> Any
  ;; THUNK's value, run in a critical section of its own whose guard
  ;; answers its raise as data; once the section has ended, the raise
  ;; compounded by COMPOUND. No interrupt handler runs inside the section,
  ;; so the guard reads THUNK's own raises alone.
  (define (answered compound thunk)
    (let ((r (critical-section (guard (e (#t (list 'refused e))) (list 'ok (thunk))))))
      (if (eq? (car r) 'refused)
          (raise (compound (cadr r)))
          (cadr r))))

  ;; no-compound : Condition -> Condition
  (define (no-compound c) c)
""")
    # key-settings: optional COMPOUND.
    edit(call, """  (define (key-settings who keys plist)
    (let loop ((rest plist) (found '()))
      (if (null? rest)
          (reverse found)
          (let ((key (car rest)))
            (unless (memq key keys)
              (refuse who 'key (shown-key key) 'unknown-key "not a key this takes"))
            (when (null? (cdr rest))
              (refuse who 'key key 'missing-value "a key with no value after it"))
            (when (assq key found)
              (refuse who 'key key 'repeated-key "a key given twice"))
""", """  (define (key-settings who keys plist . more)
    (define compound (if (pair? more) (car more) no-compound))
    (let loop ((rest plist) (found '()))
      (if (null? rest)
          (reverse found)
          (let ((key (car rest)))
            (unless (memq key keys)
              (refuse who 'key (shown-key key) 'unknown-key "not a key this takes" compound))
            (when (null? (cdr rest))
              (refuse who 'key key 'missing-value "a key with no value after it" compound))
            (when (assq key found)
              (refuse who 'key key 'repeated-key "a key given twice" compound))
""")
    # string-pairs's guard around length, in a section of its own.
    edit(call, """  (define (string-pairs x)
    (let ((n (guard (e ((assertion-violation? e) #f)) (length x))))
""", """  (define (string-pairs x)
    (let ((n (critical-section (guard (e ((assertion-violation? e) #f)) (length x)))))
""")
    # the policy's checks: optional COMPOUND.
    edit(call, """  (define (checked-redirects who value)
    (unless (or (not value) (and (integer? value) (exact? value) (>= value 0)))
      (refuse who 'redirects (shown-value value) 'not-a-redirect-count
              "redirects is an exact natural, the most redirects a call follows, or #f, none"))
    value)
""", """  (define (checked-redirects who value . compound)
    (unless (or (not value) (and (integer? value) (exact? value) (>= value 0)))
      (apply refuse who 'redirects (shown-value value) 'not-a-redirect-count
              "redirects is an exact natural, the most redirects a call follows, or #f, none" compound))
    value)
""")
    edit(call, """  (define (checked-allow-downgrade who value)
    (unless (boolean? value)
      (refuse who 'allow-downgrade (shown-value value) 'not-a-boolean "allow-downgrade is #t or #f"))
    value)
""", """  (define (checked-allow-downgrade who value . compound)
    (unless (boolean? value)
      (apply refuse who 'allow-downgrade (shown-value value) 'not-a-boolean "allow-downgrade is #t or #f"
             compound))
    value)
""")
    edit(call, """  (define (checked-retry who value)
    (unless (or (not value) (http-retry? value))
      (refuse who 'retry (shown-value value) 'not-a-retry-policy
              "retry is a policy, made by make-http-retry, or #f, none"))
    value)
""", """  (define (checked-retry who value . compound)
    (unless (or (not value) (http-retry? value))
      (apply refuse who 'retry (shown-value value) 'not-a-retry-policy
              "retry is a policy, made by make-http-retry, or #f, none" compound))
    value)
""")
    edit(call, """  (define (policy-of who settings redirects allow-downgrade retry)
    (let* ((r (assq 'redirects settings))
           (a (assq 'allow-downgrade settings))
           (p (assq 'retry settings))
           (redirects (if r (checked-redirects who (cdr r)) redirects))
           (allow-downgrade (if a (checked-allow-downgrade who (cdr a)) allow-downgrade))
           (retry (if p (checked-retry who (cdr p)) retry)))
      (list redirects allow-downgrade retry)))
""", """  (define (policy-of who settings redirects allow-downgrade retry . compound)
    (let* ((r (assq 'redirects settings))
           (a (assq 'allow-downgrade settings))
           (p (assq 'retry settings))
           (redirects (if r (apply checked-redirects who (cdr r) compound) redirects))
           (allow-downgrade (if a (apply checked-allow-downgrade who (cdr a) compound) allow-downgrade))
           (retry (if p (apply checked-retry who (cdr p) compound) retry)))
      (list redirects allow-downgrade retry)))
""")
    edit(call, """  (define (call-body who value)
    (cond ((bytevector? value) (bytevector-copy value))
          ((string? value) (string->utf8 value))
          ((procedure? value) value)
          (else (refuse who 'body (shown-value value) 'not-a-body
                        "a body is a bytevector, a string, sent as UTF-8, or a producer, a procedure of no arguments"))))
""", """  (define (call-body who value compound)
    (cond ((bytevector? value) (bytevector-copy value))
          ((string? value) (string->utf8 value))
          ((procedure? value) value)
          (else (refuse who 'body (shown-value value) 'not-a-body
                        "a body is a bytevector, a string, sent as UTF-8, or a producer, a procedure of no arguments"
                        compound))))
""")
    edit(call, """  (define (call-pairs who field value)
    (or (string-pairs value)
        (refuse who field (shown-value value) 'not-name-value-pairs
                "a list of pairs of a name and a value, both strings")))
""", """  (define (call-pairs who field value compound)
    (or (string-pairs value)
        (refuse who field (shown-value value) 'not-name-value-pairs
                "a list of pairs of a name and a value, both strings" compound)))
""")
    edit(call, """                  (call-request-of 'http-request 'request session method url plist)))
""", """                  (call-request-of 'http-request 'request session method url plist no-compound)))
""")
    edit(call, """  (define (call-request-of who mode session method url plist)
    (let* ((settings (key-settings who (if (eq? mode 'port) port-keys call-keys) plist))
""", """  (define (call-request-of who mode session method url plist compound)
    (let* ((settings (key-settings who (if (eq? mode 'port) port-keys call-keys) plist compound))
""")
    edit(call, """           (body (and body-given (call-body who (cdr body-given))))
           (form (and form-given (call-pairs who 'form (cdr form-given))))
           (params (and params-given (call-pairs who 'params (cdr params-given))))
           (policy (policy-of who settings (http-session-redirects session)
                              (http-session-allow-downgrade session)
                              (http-session-retry session)))
""", """           (body (and body-given (call-body who (cdr body-given) compound)))
           (form (and form-given (call-pairs who 'form (cdr form-given) compound)))
           (params (and params-given (call-pairs who 'params (cdr params-given) compound)))
           (policy (policy-of who settings (http-session-redirects session)
                              (http-session-allow-downgrade session)
                              (http-session-retry session) compound))
""")
    edit(call, """      (when (and body-given form-given)
        (refuse who 'form #f 'body-and-form "a body and a form together"))
      (when (and (memq method '(get head)) (or body-given form-given))
        (refuse who (if body-given 'body 'form) method 'body-not-allowed
                "a body or a form with get or head, which send none"))
      (when (and producer (eq? mode 'group))
        (refuse who 'body producer 'stream-in-group
                "a request group takes no producer: its calls share one thread, which a producer's wait would hold"))
      (when (and buffer-given (not (cdr buffer-given)))
        (assertion-violation who
          "a stream-buffer is a positive exact integer: every response of call-with-response-port streams"
          #f))
""", """      (when (and body-given form-given)
        (refuse who 'form #f 'body-and-form "a body and a form together" compound))
      (when (and (memq method '(get head)) (or body-given form-given))
        (refuse who (if body-given 'body 'form) method 'body-not-allowed
                "a body or a form with get or head, which send none" compound))
      (when (and producer (eq? mode 'group))
        (refuse who 'body producer 'stream-in-group
                "a request group takes no producer: its calls share one thread, which a producer's wait would hold"
                compound))
      (when (and buffer-given (not (cdr buffer-given)))
        (raise (compound (condition (make-assertion-violation) (make-who-condition who)
                                    (make-message-condition
                                     "a stream-buffer is a positive exact integer: every response of call-with-response-port streams")
                                    (make-irritants-condition (list #f))))))
""")
    edit(call, """             (checked (apply make-curl-request check-url 'method method
                             (append (settings->plist own)
                                     (if sent (list 'body sent) '())
                                     (if length-given (list 'body-length body-length) '())
                                     (if stream-buffer (list 'stream-buffer stream-buffer) '()))))
""", """             (checked (answered compound
                       (lambda ()
                         (apply make-curl-request check-url 'method method
                                (append (settings->plist own)
                                        (if sent (list 'body sent) '())
                                        (if length-given (list 'body-length body-length) '())
                                        (if stream-buffer (list 'stream-buffer stream-buffer) '()))))))
""")
    edit(call, """             (target (curl-url-part (if (and params (pair? params))
                                        (curl-url-append-query url (form-encode params))
                                        url)
                                    'url)))
        (values (make-curl-request target
""", """             (query (and params (pair? params) (form-encode params)))
             (target (answered compound
                       (lambda ()
                         (curl-url-part (if query (curl-url-append-query url query) url) 'url)))))
        (values (answered compound (lambda () (make-curl-request target
""")
    edit(call, """                                   'cookie-jar (curl-request-cookie-jar defaults))
                (car policy)
""", """                                   'cookie-jar (curl-request-cookie-jar defaults))))
                (car policy)
""")


def make(variant):
    dest = ROOT + '/build/carried-guard/' + variant
    if os.path.exists(dest):
        shutil.rmtree(dest)
    subprocess.run(['cp', '-a', SNAP, dest], check=True)
    seam(dest)
    hc = dest + '/src/http-client.sls'
    if variant == 'today':
        edit(hc, TODAY_STATE, TODAY_SEAMED)
    elif variant == 'a':
        edit(hc, TODAY_STATE, A_STATE)
    elif variant == 'a-section-late':
        edit(hc, TODAY_STATE, A_SECTION_LATE_STATE)
    elif variant in MUTANTS:
        edit(hc, TODAY_STATE, MUTANTS[variant])
    elif variant == 'b':
        edit(hc, TODAY_STATE, B_STATE)
        option_b_call(dest)
    else:
        sys.exit('make_copies: no variant ' + variant)
    print('copy', dest)


if __name__ == '__main__':
    for v in sys.argv[1:]:
        make(v)
