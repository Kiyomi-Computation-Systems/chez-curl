#!/usr/bin/env python3
"""build/m7s3b/audit.py: every raise site in src/ that can carry a value:
assertion-violation, error, the refusal helpers, and raise of a made
condition; each with its file, line and form, cut at 240 chars."""
import re, sys, os
root = sys.argv[1]
heads = ['assertion-violation', 'error', 'refuse-field', 'refuse', 'refuse-proxy', 'refuse-ca-file',
         'refuse-header', 'make-curl-request-error', 'make-http-request-error', 'make-curl-url-error',
         'make-curl-transfer-error', 'make-irritants-condition', 'raise-continuable', 'violation']
def form_at(text, i):
    depth = 0; j = i; instr = False; esc = False
    while j < len(text):
        c = text[j]
        if instr:
            if esc: esc = False
            elif c == '\\': esc = True
            elif c == '"': instr = False
        else:
            if c == '"': instr = True
            elif c == ';':
                while j < len(text) and text[j] != '\n': j += 1
            elif c == '(': depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0: return text[i:j+1]
        j += 1
    return text[i:]
for dirpath, _, files in os.walk(os.path.join(root, 'src')):
    for f in sorted(files):
        if not f.endswith('.sls'): continue
        path = os.path.join(dirpath, f)
        text = open(path).read()
        for m in re.finditer(r'\((' + '|'.join(map(re.escape, heads)) + r')[\s)]', text):
            line_start = text.rfind('\n', 0, m.start()) + 1
            line = text[line_start:text.find('\n', m.start())]
            if line.lstrip().startswith(';'): continue
            if re.match(r'\s*\(define', text[m.start():m.start()+8]): continue
            form = ' '.join(form_at(text, m.start()).split())
            if form.startswith('(define'): continue
            ln = text.count('\n', 0, m.start()) + 1
            print(f"{os.path.relpath(path, root)}:{ln}: {form[:240]}")
