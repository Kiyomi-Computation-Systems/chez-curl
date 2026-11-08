#!/usr/bin/env python3
# Makes one copy of the tree's docs, examples, src and tests per plant under
# build/m8s4-review/plants/NAME, and applies the plant: (file, old, new),
# old required to occur exactly once. "control" plants nothing.
import os, shutil, subprocess, sys
ROOT = "/home/kishu/src/chez-curl"
OUT = ROOT + "/build/m8s4-review/plants"
COPY = ["README.org", "LICENSE", "docs", "examples", "src", "tests"]
PLANTS = {
  "control": [],
  "dk-adr-killed": [("docs/cookies.md", "Nothing keeps cookies unless you ask:", "Nothing keeps cookies unless you ask (ADR-0035):")],
  "rk-entry-dropped-killed": [("docs/reference.md", "### `curl-token-wait`\n", "### `curl-token-wait-x`\n")],
  "ek-expected-byte-killed": [("examples/expected/quick-start.out", "status 200", "status 201")],
  # test-docs
  "d1-output-block": [("docs/errors.md", "(timeout 200 #t)\n(too-large", "(timeout 300 #t)\n(too-large")],
  "d2-fragment-wrong-name": [("docs/low-level.md", "(curl-url-append-query \"https://example.com/s?q=1\" \"page=2\")", "(curl-url-add-query \"https://example.com/s?q=1\" \"page=2\")")],
  "d3-fragment-wrong-answer": [("docs/low-level.md", "'port)      ; 8443", "'port)      ; 80")],
  "d4-anchor-gone": [("docs/libcurl-versions.md", "## Multipart\n", "## Multipart bodies\n")],
  "d5-prose-no-such-export": [("docs/low-level.md", "- **`curl-token-await`** waits", "- **`curl-token-awaits`** waits")],
  "d6-slice-and-adr-history": [("docs/cookies.md", "Nothing keeps cookies unless you ask:", "Nothing keeps cookies unless you ask (ADR 0035, M7 slice 4, decided 2026-11-04; CI's memory job measured it):")],
  "d7-readme-drops-a-page": [("README.org", "- [[file:docs/hatch.md][The hatch]]: =(curl unsupported)=.\n", "")],
  "d8-index-example-table-wrong": [("docs/README.md", "| [`errors.sps`](../examples/errors.sps) |", "| [`errors.sps`](../examples/group.sps) |")],
  # test-reference
  "r1-type-wrong": [("docs/reference.md", "curl-token-wait : Token Natural -> Boolean", "curl-token-wait : Token -> Response")],
  "r2-key-row-dropped": [("docs/reference.md", "| `cookie-jar` | `(U Jar #f)`, the jar whose cookies it sends and keeps | `#f` |\n", "")],
  "r3-raises-nothing": [("docs/reference.md", "Ends every transfer the engine holds as stopped, frees all it holds, and\nreturns once its thread has ended. A second stop returns at once. Raises an\nassertion violation for anything but an engine, or inside a critical\nsection.", "Ends every transfer the engine holds as stopped, frees all it holds, and\nreturns once its thread has ended. A second stop returns at once. Raises\nnothing.")],
  "r4-wrong-page": [("docs/reference.md", "  closed one.\n\nSee [The low level](low-level.md).", "  closed one.\n\nSee [Cookies](cookies.md).")],
  # test-examples
  "e1-head-comment-wrong": [("examples/quick-start.sps", ";;;   scheme --libdirs src --program examples/quick-start.sps URL", ";;;   scheme --program examples/quick-start.sps")],
}
def run(name, edits):
    d = os.path.join(OUT, name)
    if os.path.exists(d):
        shutil.rmtree(d)
    os.makedirs(d)
    for c in COPY:
        s = os.path.join(ROOT, c)
        if os.path.isdir(s):
            shutil.copytree(s, os.path.join(d, c), symlinks=True)
        else:
            shutil.copy2(s, os.path.join(d, c))
    for (f, old, new) in edits:
        p = os.path.join(d, f)
        t = open(p, encoding="utf-8").read()
        n = t.count(old)
        if n != 1:
            sys.exit(f"{name}: {f}: the old text occurs {n} times")
        open(p, "w", encoding="utf-8").write(t.replace(old, new))
    print(name, "made")
only = sys.argv[1:]
for name, edits in PLANTS.items():
    if not only or name in only:
        run(name, edits)
