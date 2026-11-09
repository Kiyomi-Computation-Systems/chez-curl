#!/usr/bin/env python3
"""The /json route's mutants, each a copy of tests/origin.mjs with one rule
broken, for tests/test-origin.sps to fail on. Run on the host from the
repository's root:

    python3 .plans/research/m8/slice5/build/route-mutants.py

It writes build/mutants/NAME/, each holding tests/ (a copy, its origin.mjs
the mutant), and src and build/scheme-libs as links to the checkout's, so
the suite runs there as it does at the root. Each replacement must match the
pristine file exactly once, or it stops.
"""
import os
import shutil
import sys

ROOT = os.getcwd()
ORIGIN = os.path.join(ROOT, 'tests', 'origin.mjs')
OUT = os.path.join(ROOT, 'build', 'mutants')

ACCEPT = "const acceptsJson = (accept) => accept !== null && accept.split(',').some((range) => mediaType(range) === JSON_TYPE);"
CT_CHECK = "  if (type === null || mediaType(type) !== JSON_TYPE) {\n    return answer(415, { error: 'unsupported-media-type', 'content-type': type });\n  }\n"
ACCEPT_CHECK = "  if (!acceptsJson(accept)) return answer(406, { error: 'not-acceptable', accept });\n"
ANSWER = "  const answer = (status, value) => ({ status, bytes: Buffer.from(JSON.stringify(value), 'utf8') });\n"

MUTANTS = {
    # Accept
    'accept-any': [(ACCEPT, "const acceptsJson = (accept) => accept !== null;")],
    'accept-star': [(ACCEPT, ACCEPT.replace("mediaType(range) === JSON_TYPE)", "mediaType(range) === JSON_TYPE || mediaType(range) === '*/*')"))],
    'accept-case': [(ACCEPT, ACCEPT.replace("mediaType(range) === JSON_TYPE", "range.split(';')[0].replace(/^[ \\t]+|[ \\t]+$/g, '') === JSON_TYPE"))],
    'accept-params': [(ACCEPT, ACCEPT.replace("mediaType(range) === JSON_TYPE", "asciiFolded(range.replace(/^[ \\t]+|[ \\t]+$/g, '')) === JSON_TYPE"))],
    'accept-no-split': [(ACCEPT, ACCEPT.replace("accept.split(',').some(", "[accept].some("))],
    'accept-no-trim': [(ACCEPT, ACCEPT.replace("mediaType(range) === JSON_TYPE", "asciiFolded(range.split(';')[0]) === JSON_TYPE"))],
    'accept-substring': [(ACCEPT, ACCEPT.replace("mediaType(range) === JSON_TYPE", "asciiFolded(range).includes(JSON_TYPE)"))],
    'first-header-only': [("    if (asciiFolded(pairs[i]) === name) values.push(pairs[i + 1]);",
                           "    if (asciiFolded(pairs[i]) === name && values.length === 0) values.push(pairs[i + 1]);")],
    'join-no-space': [("values.join(', ')", "values.join(',')")],
    # the body's methods
    'no-put': [("['POST', 'PUT', 'PATCH'].includes(method)", "['POST', 'PATCH'].includes(method)")],
    'no-patch': [("['POST', 'PUT', 'PATCH'].includes(method)", "['POST', 'PUT'].includes(method)")],
    'delete-body': [("['POST', 'PUT', 'PATCH'].includes(method)", "['POST', 'PUT', 'PATCH', 'DELETE'].includes(method)")],
    # Content-Type
    'no-415': [("  if (type === null || mediaType(type) !== JSON_TYPE) {", "  if (false) {")],
    'ct-params': [("type === null || mediaType(type) !== JSON_TYPE", "type === null || asciiFolded(type.trim()) !== JSON_TYPE")],
    'ct-case': [("type === null || mediaType(type) !== JSON_TYPE", "type === null || type.split(';')[0].trim() !== JSON_TYPE")],
    'ct-prefix': [("type === null || mediaType(type) !== JSON_TYPE", "type === null || !asciiFolded(type).startsWith(JSON_TYPE)")],
    # the body
    'lax-utf8': [("{ fatal: true, ignoreBOM: true }", "{ fatal: false, ignoreBOM: true }")],
    'bom-dropped': [("{ fatal: true, ignoreBOM: true }", "{ fatal: true, ignoreBOM: false }")],
    'no-parse': [("    json = JSON.parse(text);", "    json = text;")],
    # the order of the rules
    'order-ct-before-accept': [
        (ACCEPT_CHECK, "  if (!acceptsJson(accept) && !['POST', 'PUT', 'PATCH'].includes(method)) return answer(406, { error: 'not-acceptable', accept });\n"),
        (CT_CHECK, CT_CHECK + ACCEPT_CHECK)],
    'order-body-before-ct': [
        (CT_CHECK, ""),
        ("  return answer(201, ", CT_CHECK + "  return answer(201, ")],
    # the answer
    'status-200-for-body': [("return answer(201, ", "return answer(200, ")],
    'http-no-content-type': [("send(res, answer.status, ['Content-Type', JSON_TYPE, 'Content-Length'",
                              "send(res, answer.status, ['Content-Length'")],
    'h2-no-content-type': [("['content-type', JSON_TYPE, 'content-length', String(answer.bytes.length)]",
                            "['content-length', String(answer.bytes.length)]")],
    'h2-method-get': [("jsonAnswer(headers[':method'], headers[':path']", "jsonAnswer('GET', headers[':path']")],
    # state: a repeat of a request answered differently
    'repeat-differs': [
        ("const JSON_TYPE = 'application/json';\n", "const JSON_TYPE = 'application/json';\nconst jsonKeys = new Set();\n"),
        (ANSWER,
         "  const key = `${method} ${target} ${fieldValue(pairs, 'content-type')} ${body.toString('latin1')}`;\n"
         "  const again = jsonKeys.has(key);\n"
         "  jsonKeys.add(key);\n"
         "  const answer = (status, value) => ({ status, bytes: Buffer.from(JSON.stringify(again && status === 201 ? { ...value, again } : value), 'utf8') });\n")],
}


def main():
    with open(ORIGIN, encoding='utf-8') as f:
        pristine = f.read()
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    names = sorted(MUTANTS) if len(sys.argv) == 1 else sys.argv[1:]
    for name in names:
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
        os.symlink(os.path.join(ROOT, 'src'), os.path.join(d, 'src'))
        os.makedirs(os.path.join(d, 'build'))
        os.symlink(os.path.join(ROOT, 'build', 'scheme-libs'), os.path.join(d, 'build', 'scheme-libs'))
        print(name)


main()
