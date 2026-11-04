#!/bin/sh
# standin.mjs's self-test, watched failing (2026-11-02): a copy whose Basic
# decoder splits user and password at the last colon, not the first, must
# fail the vectors with a colon in the password, exit 1; and a copy whose
# planted vector is made true (its expected hex given its last byte back)
# must fail as a planted vector that passed, exit 1. The file as it is must
# pass, exit 0. Run from the repository's root:
#   scripts/guix-env sh .plans/research/m7/slice3/selftest-control.sh < /dev/null
set -u
d=.plans/research/m7/slice3
t=$(mktemp -d "${TMPDIR:-/tmp}/selftestcontrol.XXXXXX") || exit 1
trap 'rm -rf "$t"' EXIT
sed 's/const i = raw.indexOf(0x3a);/const i = raw.lastIndexOf(0x3a);/' $d/standin.mjs > $t/split.mjs
cmp -s $d/standin.mjs $t/split.mjs && { echo "selftest-control: the split mutation did not apply"; exit 1; }
sed "s/const planted = \[\['Basic YWxpY2U6czNjcmV0', '616c6963653a7333637265'/const planted = [['Basic YWxpY2U6czNjcmV0', '616c6963653a733363726574'/" $d/standin.mjs > $t/planted.mjs
cmp -s $d/standin.mjs $t/planted.mjs && { echo "selftest-control: the planted mutation did not apply"; exit 1; }
diff $d/standin.mjs $t/split.mjs
diff $d/standin.mjs $t/planted.mjs
echo "-- as it is:"
"${NODE:-node}" $d/standin.mjs --selftest; echo "exit=$?"
echo "-- split at the last colon:"
"${NODE:-node}" $t/split.mjs --selftest; echo "exit=$?"
echo "-- the planted vector made true:"
"${NODE:-node}" $t/planted.mjs --selftest; echo "exit=$?"
