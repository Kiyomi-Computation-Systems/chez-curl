#!/bin/sh
# server.mjs's Digest self-test, watched failing (2026-11-02): a copy whose
# response puts nc before the nonce must fail RFC 2617's and RFC 7616's
# examples; the file as it is must pass. Run from the repository's root:
#   scripts/guix-env sh .plans/research/m7/auth/selftest-control.sh < /dev/null
set -u
d=.plans/research/m7/auth
t=$(mktemp -d "${TMPDIR:-/tmp}/selftestcontrol.XXXXXX") || exit 1
trap 'rm -rf "$t"' EXIT
sed 's/cat(ha1, .:., nonce, .:., nc, .:., cnonce/cat(ha1, ":", nc, ":", nonce, ":", cnonce/' $d/server.mjs > $t/server.mjs
cmp -s $d/server.mjs $t/server.mjs && { echo "selftest-control: the mutation did not apply"; exit 1; }
diff $d/server.mjs $t/server.mjs
echo "-- as it is:"
"${NODE:-node}" $d/server.mjs --selftest; echo "exit=$?"
echo "-- mutated:"
"${NODE:-node}" $t/server.mjs --selftest; echo "exit=$?"
