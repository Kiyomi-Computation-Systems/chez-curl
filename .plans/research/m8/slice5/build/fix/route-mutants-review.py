#!/usr/bin/env python3
"""The review's /json route mutants: rules the builder's 26 did not try.
Run on the host, from the repository root (copied from review/route-mutants.py, its OUT moved to build/mutants-fix):

    python3 review-scripts/route-mutants.py

Writes review-mutants/NAME/, each holding tests/ (a copy, its origin.mjs the
mutant) and examples/, src and build/scheme-libs as links to the copy's
own, so test-origin and test-examples run there as at the root. Each
replacement must match the pristine file exactly once, or it stops.
"""
import os
import shutil
import sys

ROOT = os.getcwd()
ORIGIN = os.path.join(ROOT, 'tests', 'origin.mjs')
OUT = os.path.join(ROOT, 'build', 'mutants-fix')

METHOD_200 = "  if (!['POST', 'PUT', 'PATCH'].includes(method)) return answer(200, { method, target, accept });\n"
ANSWER = "  const answer = (status, value) => ({ status, bytes: Buffer.from(JSON.stringify(value), 'utf8') });\n"
ACCEPT = "const acceptsJson = (accept) => accept !== null && accept.split(',').some((range) => mediaType(range) === JSON_TYPE);"

MUTANTS = {
    # 415 for any method that names a Content-Type other than JSON: the
    # route says 415 for a POST, PUT or PATCH alone.
    'r01-ct-any-method': [(METHOD_200,
        "  { const t0 = fieldValue(pairs, 'content-type');\n"
        "    if (t0 !== null && mediaType(t0) !== JSON_TYPE) return answer(415, { error: 'unsupported-media-type', 'content-type': t0 }); }\n"
        + METHOD_200)],
    # The answer's bytes as Latin-1, not UTF-8.
    'r02-answer-latin1': [(ANSWER, ANSWER.replace("'utf8'", "'latin1'"))],
    # A repeat of a GET answered differently: the route keeps nothing.
    'r03-repeat-differs-get': [
        ("const JSON_TYPE = 'application/json';\n", "const JSON_TYPE = 'application/json';\nconst jsonSeen = new Set();\n"),
        (METHOD_200,
         "  if (!['POST', 'PUT', 'PATCH'].includes(method)) {\n"
         "    const key = `${method} ${target} ${accept}`; const again = jsonSeen.has(key); jsonSeen.add(key);\n"
         "    return answer(200, again ? { method, target, accept, again } : { method, target, accept });\n"
         "  }\n")],
    # HEAD refused: the route says 200 for any other method.
    'r04-head-405': [(METHOD_200,
        "  if (method === 'HEAD') return answer(405, { error: 'method' });\n" + METHOD_200)],
    # The 200's target without its query: the route says as received.
    'r05-get-target-no-query': [(METHOD_200, METHOD_200.replace("{ method, target, accept }", "{ method, target: target.split('?')[0], accept }"))],
    # A PUT's body not parsed: the route says 400 for a POST, PUT or PATCH.
    'r06-put-no-parse': [("    json = JSON.parse(text);\n", "    json = method === 'PUT' ? text : JSON.parse(text);\n")],
    # Content-Type's first header alone, not every one joined.
    'r07-ct-first-only': [("  const type = fieldValue(pairs, 'content-type');\n",
        "  const type = (() => { for (let i = 0; i + 1 < pairs.length; i += 2) if (asciiFolded(pairs[i]) === 'content-type') return pairs[i + 1]; return null; })();\n")],
    # Over HTTP/2, :path without its query.
    'r08-h2-path-no-query': [("jsonAnswer(headers[':method'], headers[':path'], rawHeaders, body)",
                              "jsonAnswer(headers[':method'], headers[':path'].split('?')[0], rawHeaders, body)")],
    # q=0 read as refusing JSON: the route says q is ignored.
    'r09-accept-q0': [(ACCEPT, ACCEPT.replace("mediaType(range) === JSON_TYPE)",
                                              "mediaType(range) === JSON_TYPE && !/;\\s*q=0(\\.0*)?\\s*(;|$)/.test(range))"))],
}


def main():
    with open(ORIGIN, encoding='utf-8') as f:
        pristine = f.read()
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    for name in sorted(MUTANTS):
        text = pristine
        for old, new in MUTANTS[name]:
            n = text.count(old)
            if n != 1:
                sys.exit(f'{name}: {n} matches of {old!r}')
            text = text.replace(old, new)
        if text == pristine:
            sys.exit(f'{name}: no change')
        d = os.path.join(OUT, name)
        shutil.copytree(os.path.join(ROOT, 'tests'), os.path.join(d, 'tests'), symlinks=True)
        with open(os.path.join(d, 'tests', 'origin.mjs'), 'w', encoding='utf-8') as f:
            f.write(text)
        for link in ('src', 'examples'):
            os.symlink(os.path.join(ROOT, link), os.path.join(d, link))
        os.makedirs(os.path.join(d, 'build'))
        os.symlink(os.path.join(ROOT, 'build', 'scheme-libs'), os.path.join(d, 'build', 'scheme-libs'))
        print(name)


main()
