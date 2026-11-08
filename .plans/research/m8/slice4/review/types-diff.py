#!/usr/bin/env python3
# Compares each NAME : TYPE line of docs/reference.md's text blocks with the
# signature comment in src/ (the current tree), whitespace-normalized.
import re, glob
ref = open("/home/kishu/src/chez-curl/docs/reference.md").read()
types = {}
inblock = False
for line in ref.split("\n"):
    if line.startswith("```"):
        inblock = (line.strip() == "```text") if not inblock else False
        continue
    if inblock:
        m = re.match(r"^(\S+) : (.*)$", line)
        if m: types[m.group(1)] = m.group(2).strip()
src = ""
for f in glob.glob("/home/kishu/src/chez-curl/src/**/*.sls", recursive=True):
    src += open(f).read() + "\n"
# signature comments: ";; NAME : TYPE" possibly continued on following ';;   ' lines starting with '->' or with deeper indent
sigs = {}
lines = src.split("\n")
for i, l in enumerate(lines):
    m = re.match(r"^\s*;;\s+(\S+) : (.*)$", l)
    if m:
        name, t = m.group(1), m.group(2).strip()
        j = i + 1
        while j < len(lines) and re.match(r"^\s*;;\s{3,}(->|\[|\(|[A-Z])", lines[j]) and " : " not in lines[j]:
            t += " " + lines[j].strip().lstrip(";").strip(); j += 1
        sigs.setdefault(name, []).append(re.sub(r"\s+", " ", t))
for name, t in sorted(types.items()):
    t2 = re.sub(r"\s+", " ", t)
    cands = sigs.get(name, [])
    if not cands:
        print("NO-SIG ", name, ":", t2); continue
    if t2 not in cands:
        print("DIFFERS", name)
        print("   ref:", t2)
        for c in cands: print("   src:", c)
