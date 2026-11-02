#!/bin/sh
# standin.mjs's Digest self-test, watched failing (2026-11-02), as
# ../auth/selftest-control.sh watched server.mjs's: a copy whose response
# puts nc before the nonce must fail RFC 2617's and RFC 7616's examples, exit
# 1; the file as it is must pass, exit 0. Run from the repository's root:
#   scripts/guix-env sh .plans/research/m7/slice2/selftest-control.sh < /dev/null
set -u
d=.plans/research/m7/slice2
t=$(mktemp -d "${TMPDIR:-/tmp}/selftestcontrol.XXXXXX") || exit 1
trap 'rm -rf "$t"' EXIT
sed 's/cat(ha1, .:., nonce, .:., nc, .:., cnonce/cat(ha1, ":", nc, ":", nonce, ":", cnonce/' $d/standin.mjs > $t/standin.mjs
cmp -s $d/standin.mjs $t/standin.mjs && { echo "selftest-control: the mutation did not apply"; exit 1; }
diff $d/standin.mjs $t/standin.mjs
echo "-- as it is:"
"${NODE:-node}" $d/standin.mjs --selftest; echo "exit=$?"
echo "-- mutated:"
"${NODE:-node}" $t/standin.mjs --selftest; echo "exit=$?"
