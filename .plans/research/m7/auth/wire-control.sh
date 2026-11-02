#!/bin/sh
# The probe's wire check, watched failing (2026-11-02): group A against a copy
# of server.mjs that logs each Authorization value one byte short, so every
# request that carries one must print "wire #K DIFFERS", and every one that
# carries none "wire #K same (none)". Run from the repository's root, in the
# container:
#   scripts/guix-env sh .plans/research/m7/auth/wire-control.sh < /dev/null
set -u
d=.plans/research/m7/auth
t=$(mktemp -d "${TMPDIR:-/tmp}/wirecontrol.XXXXXX") || exit 1
trap 'rm -rf "$t"' EXIT
sed 's/r.log(`auth #${r.n} value="${esc(L1(value))}"`)/r.log(`auth #${r.n} value="${esc(L1(value.slice(1)))}"`)/' $d/server.mjs > $t/server.mjs
cmp -s $d/server.mjs $t/server.mjs && { echo "wire-control: the mutation did not apply"; exit 1; }
"${CC:-cc}" -o $t/probe $d/probe.c "$CHEZ_CURL_LIBCURL" || exit 1
mkdir $t/pki && sh tests/make-test-pki.sh $t/pki || exit 1
mkfifo $t/in
"${NODE:-node}" $t/server.mjs $t/pki < $t/in > $t/ports 2> $t/err &
pid=$!
exec 3> $t/in
n=0; until [ -s $t/ports ]; do n=$((n+1)); [ $n -le 100 ] || { echo "no ports"; exit 1; }; sleep 0.1; done
set -- $(sed 's/[a-z0-9]*=//g' $t/ports)
$t/probe A "$1" "$2" $t/pki/ca.pem < /dev/null > $t/out
echo "probe exit=$?"
exec 3>&-
wait $pid
grep -E ' wire ' $t/out
echo "wire lines $(grep -c ' wire ' $t/out): DIFFERS $(grep -c 'wire #[0-9]* DIFFERS' $t/out), same (none) $(grep -c 'wire #[0-9]* same (none)' $t/out), same with a value $(grep -c 'wire #[0-9]* same$' $t/out)"
