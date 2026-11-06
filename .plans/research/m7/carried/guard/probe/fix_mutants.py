#!/usr/bin/env python3
"""fix_mutants.py NAME...: mutants of the fix round's working tree, each a
copy at build/carried-guard/fixmut-NAME, made by rsync of the tree (no
build/, .git or .plans/research) and one change, each edit matching once:

  step-pre            the steps run with no section and no guard, as before
                      the fix, the step gate's marks kept
  step-guard-outside  the step's guard around its critical section
  step-section-late   the step itself outside the section, the end mark in
  step-raise-inside   the step's raise raised from the guard's clause, in
                      the section
  submit-pre          request-checks' two URL parses as before the fix: the
                      proxy URL's under a guard of &curl-url-error alone,
                      with interrupts on, and the URL's bare
  submit-guard-outside, submit-section-late, submit-raise-inside
                      the submit's in-section, as the step's three
  cap-pre             no cap: neither call-state's check nor checked-input's
  cap-late            call-state's check after call-request-of
  cap-off-by-one      both checks at the cap itself, 8,000,000 refused too
  cap-copying         call-state's check kept, checked-input's removed, so
                      the URL is copied, scanned, encoded and parsed first
  noseam              the review's mut-noseam: call-state's two checks gate
                      calls removed (m4)
  stop-late           test-origin-tls's stopped-probe stops the origin
                      2300 ms after the connect, past the probe's send (m3)
  flip-no-cr          value-fault takes CR as a value's: test-transfer's
                      flip tests, a refusal now yielding, must still fail
  group-step-outside  turn! steps a done token outside a critical section,
                      both ways it does: a group's step rows must fail
  handler-sleep       not a mutant: test-call-checks' child's Ctrl-C handler
                      sleeps 100 ms before it raises, so a group's next hop
                      starts first; its rows must pass both ways
"""
import os
import shutil
import subprocess
import sys

ROOT = '/home/kishu/src/chez-curl'

STEP_FIXED = """  (define (in-step-section thunk)
    (let ((r (critical-section
              (guard (e (#t (list 'raised e)))
                (run-step-gate! 'start)
                (let ((v (thunk)))
                  (run-step-gate! 'end)
                  (list 'value v))))))
      (if (eq? (car r) 'raised)
          (raise (cadr r))
          (cadr r))))"""

SUBMIT_FIXED = """  (define (in-section thunk)
    (let ((r (critical-section
              (guard (e (#t (list 'raised e)))
                (run-parse-gate! 'start)
                (list 'value (thunk))))))
      (if (eq? (car r) 'raised)
          (raise (cadr r))
          (cadr r))))"""

DRIVE = 'src/http-client/private/drive.sls'
TRANSFER = 'src/curl/private/transfer.sls'
HC = 'src/http-client.sls'
URL = 'src/curl/private/url.sls'
TLS = 'tests/test-origin-tls.sps'

CAP_CHECK = """                    (when (and (string? given) (> (string-length given) url-input-cap))
                      (curl-url-part given 'url))
"""

MUTANTS = {
    'step-pre': [(DRIVE, STEP_FIXED, """  (define (in-step-section thunk)
    (run-step-gate! 'start)
    (let ((v (thunk)))
      (run-step-gate! 'end)
      v))""")],
    'step-guard-outside': [(DRIVE, STEP_FIXED, """  (define (in-step-section thunk)
    (let ((r (guard (e (#t (list 'raised e)))
               (critical-section
                (run-step-gate! 'start)
                (let ((v (thunk)))
                  (run-step-gate! 'end)
                  (list 'value v))))))
      (if (eq? (car r) 'raised)
          (raise (cadr r))
          (cadr r))))""")],
    'step-section-late': [(DRIVE, STEP_FIXED, """  (define (in-step-section thunk)
    (let ((r (guard (e (#t (list 'raised e)))
               (run-step-gate! 'start)
               (let ((v (thunk)))
                 (critical-section
                  (run-step-gate! 'end)
                  (list 'value v))))))
      (if (eq? (car r) 'raised)
          (raise (cadr r))
          (cadr r))))""")],
    'step-raise-inside': [(DRIVE, STEP_FIXED, """  (define (in-step-section thunk)
    (let ((r (critical-section
              (guard (e (#t (raise e)))
                (run-step-gate! 'start)
                (let ((v (thunk)))
                  (run-step-gate! 'end)
                  (list 'value v))))))
      (if (eq? (car r) 'raised)
          (raise (cadr r))
          (cadr r))))""")],
    'submit-pre': [
        (TRANSFER, """        (let ((scheme (in-section
                       (lambda ()
                         (call-with-parsed-url url
                           (lambda (handle)
                             (let ((scheme (require-http-scheme handle url)))
                               (when credentials
                                 (check-userinfo who credentials (userinfo-parts handle url)))
                               scheme)))))))""", """        (let ((scheme (call-with-parsed-url url
                        (lambda (handle)
                          (let ((scheme (require-http-scheme handle url)))
                            (when credentials
                              (check-userinfo who credentials (userinfo-parts handle url)))
                            scheme)))))"""),
        (TRANSFER, """    (let ((reading (in-section
                    (lambda ()
                      (guard (e (#t (if (curl-url-error? e) #f (raise e))))
                        (proxy-url-reading proxy))))))""",
         """    (let ((reading (guard (e ((curl-url-error? e) #f)) (proxy-url-reading proxy))))""")],
    'submit-guard-outside': [(TRANSFER, SUBMIT_FIXED, """  (define (in-section thunk)
    (let ((r (guard (e (#t (list 'raised e))) (critical-section (run-parse-gate! 'start) (list 'value (thunk))))))
      (if (eq? (car r) 'raised)
          (raise (cadr r))
          (cadr r))))""")],
    'submit-section-late': [(TRANSFER, SUBMIT_FIXED, """  (define (in-section thunk)
    (let ((r (guard (e (#t (list 'raised e))) (run-parse-gate! 'start) (let ((v (thunk))) (critical-section (list 'value v))))))
      (if (eq? (car r) 'raised)
          (raise (cadr r))
          (cadr r))))""")],
    'submit-raise-inside': [(TRANSFER, SUBMIT_FIXED, """  (define (in-section thunk)
    (let ((r (critical-section (guard (e (#t (raise e))) (run-parse-gate! 'start) (list 'value (thunk))))))
      (if (eq? (car r) 'raised)
          (raise (cadr r))
          (cadr r))))""")],
    'cap-pre': [
        (HC, CAP_CHECK, ""),
        (URL, """    (when (and (string? input) (> (string-length input) url-input-cap))
      (refuse-code input (code-of 'malformed-input)))
    (checked-string who input "a URL"))""", """    (checked-string who input "a URL"))""")],
    'cap-late': [
        (HC, CAP_CHECK, ""),
        (HC, """                      (when check? (curl-request-check request))
                      (run-checks-gate! 'end)""", """                      (when (and (string? given) (> (string-length given) url-input-cap))
                        (curl-url-part given 'url))
                      (when check? (curl-request-check request))
                      (run-checks-gate! 'end)""")],
    'cap-off-by-one': [
        (HC, """(> (string-length given) url-input-cap)""", """(>= (string-length given) url-input-cap)"""),
        (URL, """(> (string-length input) url-input-cap)""", """(>= (string-length input) url-input-cap)""")],
    'cap-copying': [
        (URL, """    (when (and (string? input) (> (string-length input) url-input-cap))
      (refuse-code input (code-of 'malformed-input)))
    (checked-string who input "a URL"))""", """    (checked-string who input "a URL"))""")],
    'noseam': [
        (HC, """                    (run-checks-gate! 'start)
                    (check-session who session)""", """                    #f
                    (check-session who session)"""),
        (HC, """                      (when check? (curl-request-check request))
                      (run-checks-gate! 'end)""", """                      (when check? (curl-request-check request))
                      #f""")],
    'flip-no-cr': [(TRANSFER, """((or (= code 10) (= code 13)) 'line-break)""",
                    """((= code 10) 'line-break)""")],
    'group-step-outside': [
        (DRIVE, """                (critical-section
                 (when (and (hashtable-contains? (group-live group) token) (curl-token-done? token))
                   (step-token! group token))))""", """                (begin
                 (when (and (hashtable-contains? (group-live group) token) (curl-token-done? token))
                   (step-token! group token))))"""),
        (DRIVE, """        (critical-section (step-token! group token)))))""",
         """        (step-token! group token))))""")],
    'handler-sleep': [('tests/test-call-checks.sps', """               (set! handler-marks (reverse marks))
               (if (eq? action 'raise)""", """               (set! handler-marks (reverse marks))
               (sleep (make-time 'time-duration 100000000 0))
               (if (eq? action 'raise)""")],
    'stop-late': [(TLS, """                        (pause-ms 300)
                        (dynamic-wind
                          (lambda () #f)
                          (lambda ()
                            (set! stopped (kill-origin "-STOP"))""", """                        (pause-ms 2300)
                        (dynamic-wind
                          (lambda () #f)
                          (lambda ()
                            (set! stopped (kill-origin "-STOP"))""")],
}


def edit(path, old, new):
    with open(path) as f:
        text = f.read()
    n = text.count(old)
    if n != 1:
        sys.exit(f'fix_mutants: {path}: expected 1 match, found {n}:\n{old[:200]}')
    with open(path, 'w') as f:
        f.write(text.replace(old, new))


def make(name):
    dest = ROOT + '/build/carried-guard/fixmut-' + name
    os.makedirs(dest, exist_ok=True)
    subprocess.run(['rsync', '-a', '--delete', '--exclude', '/build', '--exclude', '/.git',
                    '--exclude', '/.plans/research', '--exclude', '/probe', ROOT + '/', dest + '/'],
                   check=True)
    for rel, old, new in MUTANTS[name]:
        edit(dest + '/' + rel, old, new)
    print('mutant', dest)


if __name__ == '__main__':
    for n in sys.argv[1:]:
        if n not in MUTANTS:
            sys.exit('fix_mutants: no mutant ' + n)
        make(n)
