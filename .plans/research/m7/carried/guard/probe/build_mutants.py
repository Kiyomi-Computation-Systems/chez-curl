#!/usr/bin/env python3
"""build_mutants.py VARIANT...: copies of build/carried-guard/build, the
built change, at build/carried-guard/build-VARIANT, call-state's definition
replaced, its two gate calls kept where the build has them:

  today            the snapshot's guard, with interrupts on, around the
                   checks; no section
  a-guard-outside  the section inside the guard: a Ctrl-C made pending in
                   the section runs as it ends, inside the guard
  a-raise-inside   the refusal raised from the guard's clause, inside the
                   section, where the caller's handler runs with
                   interrupts off
  a-section-late   the section entered only after call-request-of: the
                   keys, the body and the URL checked with interrupts on,
                   inside the guard
  a-no-compound    the refusal raised bare, with no &http-exchange

Each replaced whole; nothing outside build/carried-guard is written.
"""
import os
import shutil
import subprocess
import sys

ROOT = '/home/kishu/src/chez-curl/build/carried-guard'
BUILD = ROOT + '/build'

HEAD = "  (define (call-state session method url plist check? mode who)\n"
TAIL = "  (define (make-http-session . plist)\n"

MADE = """(list 'made
                            (cons (make-exchange method given request (curl-request-timeout-ms request)
                                                 start redirects allow-downgrade retry)
                                  producer))"""

VARIANTS = {
    'today': """  (define (call-state session method url plist check? mode who)
    (let* ((start (monotonic-ns))
           (given (if (string? url) (string-copy url) url)))
      (guard (e ((condition? e)
                 (raise (condition e (make-http-exchange method given '() 0)))))
        (run-checks-gate! 'start)
        (check-session who session)
        (let-values (((request redirects allow-downgrade retry producer)
                      (call-request-of who mode session method given plist)))
          (when check? (curl-request-check request))
          (run-checks-gate! 'end)
          (cons (make-exchange method given request (curl-request-timeout-ms request)
                               start redirects allow-downgrade retry)
                producer)))))

""",
    'a-guard-outside': """  (define (call-state session method url plist check? mode who)
    (let* ((start (monotonic-ns))
           (given (if (string? url) (string-copy url) url))
           (made (guard (e (#t (list 'refused
                                      (if (condition? e)
                                          (condition e (make-http-exchange method given '() 0))
                                          e))))
                  (critical-section
                    (run-checks-gate! 'start)
                    (check-session who session)
                    (let-values (((request redirects allow-downgrade retry producer)
                                  (call-request-of who mode session method given plist)))
                      (when check? (curl-request-check request))
                      (run-checks-gate! 'end)
                      MADE)))))
      (if (eq? (car made) 'refused)
          (raise (cadr made))
          (cadr made))))

""",
    'a-raise-inside': """  (define (call-state session method url plist check? mode who)
    (let* ((start (monotonic-ns))
           (given (if (string? url) (string-copy url) url))
           (made (critical-section
                  (guard (e (#t (raise (if (condition? e)
                                           (condition e (make-http-exchange method given '() 0))
                                           e))))
                    (run-checks-gate! 'start)
                    (check-session who session)
                    (let-values (((request redirects allow-downgrade retry producer)
                                  (call-request-of who mode session method given plist)))
                      (when check? (curl-request-check request))
                      (run-checks-gate! 'end)
                      MADE)))))
      (if (eq? (car made) 'refused)
          (raise (cadr made))
          (cadr made))))

""",
    'a-section-late': """  (define (call-state session method url plist check? mode who)
    (let* ((start (monotonic-ns))
           (given (if (string? url) (string-copy url) url))
           (made (guard (e (#t (list 'refused
                                      (if (condition? e)
                                          (condition e (make-http-exchange method given '() 0))
                                          e))))
                    (run-checks-gate! 'start)
                    (check-session who session)
                    (let-values (((request redirects allow-downgrade retry producer)
                                  (call-request-of who mode session method given plist)))
                      (critical-section
                       (when check? (curl-request-check request))
                       (run-checks-gate! 'end)
                       MADE)))))
      (if (eq? (car made) 'refused)
          (raise (cadr made))
          (cadr made))))

""",
    'a-no-compound': """  (define (call-state session method url plist check? mode who)
    (let* ((start (monotonic-ns))
           (given (if (string? url) (string-copy url) url))
           (made (critical-section
                  (guard (e (#t (list 'refused e)))
                    (run-checks-gate! 'start)
                    (check-session who session)
                    (let-values (((request redirects allow-downgrade retry producer)
                                  (call-request-of who mode session method given plist)))
                      (when check? (curl-request-check request))
                      (run-checks-gate! 'end)
                      MADE)))))
      (if (eq? (car made) 'refused)
          (raise (cadr made))
          (cadr made))))

""",
}


def make(variant):
    dest = ROOT + '/build-' + variant
    if os.path.exists(dest):
        shutil.rmtree(dest)
    subprocess.run(['cp', '-a', BUILD, dest], check=True)
    hc = dest + '/src/http-client.sls'
    with open(hc) as f:
        text = f.read()
    i = text.index(HEAD)
    j = text.index(TAIL)
    assert text.count(HEAD) == 1 and text.count(TAIL) == 1 and i < j
    body = VARIANTS[variant].replace('MADE', MADE)
    with open(hc, 'w') as f:
        f.write(text[:i] + body + text[j:])
    print('copy', dest)


if __name__ == '__main__':
    for v in sys.argv[1:]:
        if v not in VARIANTS:
            sys.exit('build_mutants: no variant ' + v)
        make(v)
