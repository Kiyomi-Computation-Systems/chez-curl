#!/bin/sh
# The wire check, watched failing (2026-11-02): the wire part against a copy
# of standin.mjs that logs each Authorization value one byte short, so
# wire.mjs must print DIFFERS for every value, and exit 1; then the same
# part against standin.mjs as it is, where it must find every value the
# same, and exit 0. Run from the repository's root, in the container, after
# make-prototype.sh:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m7/slice2/wire-control.sh' < /dev/null
set -u
d=.plans/research/m7/slice2
t=$(mktemp -d "${TMPDIR:-/tmp}/wirecontrol.XXXXXX") || exit 1
trap 'rm -rf "$t"' EXIT
sed 's/r.log(`auth #${r.n} value=${shown(L1(value))}`)/r.log(`auth #${r.n} value=${shown(L1(value.slice(1)))}`)/' $d/standin.mjs > $t/standin.mjs
cmp -s $d/standin.mjs $t/standin.mjs && { echo "wire-control: the mutation did not apply"; exit 1; }
diff $d/standin.mjs $t/standin.mjs
echo "-- mutated:"
STANDIN=$t/standin.mjs sh $d/run.sh guix-8.20.0 wire > $t/mutated.log 2>&1
grep "part wire exited" $t/mutated.log
"${NODE:-node}" $d/wire.mjs $t/mutated.log > $t/m.out; echo "wire.mjs exit=$? (1 expected)"
echo "DIFFERS lines $(grep -c DIFFERS $t/m.out), same lines $(grep -c ' same$' $t/m.out)"
tail -1 $t/m.out
echo "-- as it is:"
sh $d/run.sh guix-8.20.0 wire > $t/plain.log 2>&1
grep "part wire exited" $t/plain.log
"${NODE:-node}" $d/wire.mjs $t/plain.log > $t/p.out; echo "wire.mjs exit=$? (0 expected)"
echo "DIFFERS lines $(grep -c DIFFERS $t/p.out), same lines $(grep -c ' same$' $t/p.out)"
tail -1 $t/p.out
