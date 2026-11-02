#!/bin/sh
# M7 slice 1's prototype (2026-11-02): a private copy of src/ in
# build/m7s1/src whose hatch may set PROXY and NOPROXY, so a named proxy
# can be measured before the proxy field takes a URL (plan, section 4.1).
# HTTPPROXYTUNNEL needs no change: today's hatch takes it. Run on the host,
# from the repository's root:
#   sh .plans/research/m7/slice1/make-prototype.sh
# It removes build/m7s1/src, copies src/ there, and changes one definition,
# owned-option-names in (curl private transfer), to leave out "PROXY" and
# "NOPROXY"; every other owned option stays refused. The field still sets
# PROXY "" for a proxy of #f; the hatch sets its options last, so its PROXY
# replaces that. It writes the diff to prototype.diff beside this script,
# and fails unless the diff is exactly the two lines changed.
set -eu
d=.plans/research/m7/slice1
[ -f $d/make-prototype.sh ] || { echo "make-prototype.sh: run it from the repository's root" >&2; exit 2; }
out=build/m7s1/src
rm -rf "$out"
mkdir -p build/m7s1
cp -R src "$out"
f=$out/curl/private/transfer.sls
python3 - "$f" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding='utf-8').read()
a = "    (append '(\"URL\" \"PROTOCOLS_STR\""
b = "            proxy-tls-option-names))\n"
assert text.count(a) == 1 and text.count(b) == 1, "the patch targets are not unique"
text = text.replace(a, "    (remp (lambda (name) (member name '(\"PROXY\" \"NOPROXY\"))) (append '(\"URL\" \"PROTOCOLS_STR\"")
text = text.replace(b, "            proxy-tls-option-names)))\n")
open(path, 'w', encoding='utf-8').write(text)
PY
diff -u src/curl/private/transfer.sls "$f" > $d/prototype.diff && { echo "make-prototype.sh: no change made" >&2; exit 1; }
changed=$(grep -c '^+[^+]' $d/prototype.diff)
[ "$changed" -eq 2 ] || { echo "make-prototype.sh: $changed lines changed, not 2" >&2; exit 1; }
echo "make-prototype.sh: $out made; $d/prototype.diff holds the change"
