#!/bin/sh
# M7 slice 4's prototype (2026-11-03): a private copy of src/ in
# build/m7s4/src with a cookie jar on the engine's thread, as little as the
# measurement needs (prototype.py says what, file by file). Run on the
# host, from the repository's root:
#   sh .plans/research/m7/slice4/make-prototype.sh            # check
#   sh .plans/research/m7/slice4/make-prototype.sh --record   # first time
# It removes build/m7s4/src, copies src/ there, applies prototype.py, and
# diffs each changed file against src/, in sorted path order, with fixed
# labels, so the diff holds no time. Without --record it fails unless that
# diff is byte for byte prototype.diff, the recorded one, and unless no
# other file differs; --record writes prototype.diff instead.
set -eu
d=.plans/research/m7/slice4
[ -f $d/make-prototype.sh ] || { echo "make-prototype.sh: run it from the repository's root" >&2; exit 2; }
out=build/m7s4/src
rm -rf build/m7s4/src
mkdir -p build/m7s4
cp -R src "$out"
python3 $d/prototype.py "$out"
t=$(mktemp "${TMPDIR:-/tmp}/m7s4diff.XXXXXX")
trap 'rm -f "$t"' EXIT
changed=$(diff -r -q src "$out" | sed -n 's/^Files src\/\(.*\) and .* differ$/\1/p' | LC_ALL=C sort)
others=$(diff -r -q src "$out" | grep -v '^Files src/.* and .* differ$' || true)
[ -z "$others" ] || { echo "make-prototype.sh: more than changed files differ: $others" >&2; exit 1; }
for f in $changed; do
  diff -u --label "a/src/$f" --label "b/src/$f" "src/$f" "$out/$f" >> "$t" || true
done
files=$(echo $changed | wc -w)
removed=$(grep -c '^-[^-]' "$t" || true)
added=$(grep -c '^+[^+]' "$t" || true)
if [ "${1:-}" = --record ]; then
  cp "$t" $d/prototype.diff
  echo "make-prototype.sh: $out made; recorded $d/prototype.diff ($files files, $removed lines removed, $added added)"
  exit 0
fi
cmp -s "$t" $d/prototype.diff || { echo "make-prototype.sh: the diff is not the recorded one:" >&2; diff $d/prototype.diff "$t" >&2 || true; exit 1; }
if command -v sha256sum > /dev/null 2>&1; then sum=$(sha256sum $d/prototype.diff); else sum=$(shasum -a 256 $d/prototype.diff); fi
echo "make-prototype.sh: $out made; its diff is $d/prototype.diff ($files files, $removed lines removed, $added added), sha256 ${sum%% *}"
