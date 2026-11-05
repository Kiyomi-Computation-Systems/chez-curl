#!/bin/sh
# M7 slice 4's checks on the instrument, each watched failing (2026-11-03).
# Run from the repository's root, in the Guix container, after
# make-prototype.sh:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL CHEZ=$CHEZ sh .plans/research/m7/slice4/controls.sh' < /dev/null
#
#   1. The stand-in's report of the Cookie headers: its self-test writes
#      Cookie headers of every byte class and reads the report back; a copy
#      whose report drops each header's last byte must fail it, exit 1; the
#      file as it is must pass, exit 0.
#   2. The read-out walk against libcurl's own file: the walk part on a
#      copy of the prototype whose walk of struct curl_slist stops before
#      the last element must print DIFFERS for the scratch handle and for
#      the jar; on the prototype as it is, same.
#   3. Item 1's lifetime: item 1 (c) on a copy of the prototype whose close
#      frees the share at once, whatever holds it, must show
#      curl_share_cleanup refused, CURLSHE_IN_USE (2), while transfers hold
#      it; on the prototype as it is, the share is freed once, answering 0,
#      when the last holder lets go.
# Every line it prints begins with the check's number.
set -u
d=.plans/research/m7/slice4
[ -f $d/controls.sh ] || { echo "controls.sh: run it from the repository's root" >&2; exit 2; }
[ -d build/m7s4/src ] || { echo "controls.sh: no build/m7s4/src: run make-prototype.sh on the host first" >&2; exit 2; }
t=$(mktemp -d "${TMPDIR:-/tmp}/m7s4controls.XXXXXX") || exit 1
trap 'rm -rf "$t"' EXIT

# 1. the report
sed 's/lines.push(`cookie "${esc(whole)}"`)/lines.push(`cookie "${esc(whole.subarray(0, whole.length - 1))}"`)/' $d/standin.mjs > $t/standin-drop.mjs
cmp -s $d/standin.mjs $t/standin-drop.mjs && { echo "1 the drop mutation did not apply"; exit 1; }
diff $d/standin.mjs $t/standin-drop.mjs | sed 's/^/1 diff: /'
echo "1 -- the stand-in as it is:"
"${NODE:-node}" $d/standin.mjs --selftest 2>&1 | sed 's/^/1 /'; echo "1 exit=$(  "${NODE:-node}" $d/standin.mjs --selftest > /dev/null 2>&1; echo $?) (0 expected)"
echo "1 -- the copy that drops a byte:"
"${NODE:-node}" $t/standin-drop.mjs --selftest 2>&1 | sed 's/^/1 /'; echo "1 exit=$(  "${NODE:-node}" $t/standin-drop.mjs --selftest > /dev/null 2>&1; echo $?) (1 expected)"

# 2. the walk
cp -R build/m7s4/src $t/walk-src
f=$t/walk-src/curl/private/native.sls
sed 's/(if (eqv? node 0)/(if (or (eqv? node 0) (eqv? (ftype-ref curl-slist (next) (make-ftype-pointer curl-slist node)) 0))/' build/m7s4/src/curl/private/native.sls > $f
cmp -s build/m7s4/src/curl/private/native.sls $f && { echo "2 the walk mutation did not apply"; exit 1; }
diff build/m7s4/src/curl/private/native.sls $f | sed 's/^/2 diff: /'
echo "2 -- the walk that skips the last element:"
PROTO=$t/walk-src sh $d/run.sh guix-8.20.0 walk 2>&1 | grep -E 'walk-check|exited' | sed 's/^/2 /'
echo "2 -- the walk as it is:"
sh $d/run.sh guix-8.20.0 walk 2>&1 | grep -E 'walk-check|exited' | sed 's/^/2 /'

# 3. the lifetime
cp -R build/m7s4/src $t/life-src
f=$t/life-src/curl/private/engine.sls
sed 's/(when (= (locked lock (lambda () (cookie-jar-holders jar))) 0)/(when #t/' build/m7s4/src/curl/private/engine.sls > $f
cmp -s build/m7s4/src/curl/private/engine.sls $f && { echo "3 the lifetime mutation did not apply"; exit 1; }
diff build/m7s4/src/curl/private/engine.sls $f | sed 's/^/3 diff: /'
echo "3 -- the close that frees the share at once:"
PROTO=$t/life-src sh $d/run.sh guix-8.20.0 lifetime-plant 2>&1 | grep -E 'close =>|after t|jar j |counts|exited|raised' | sed 's/^/3 /'
echo "3 -- the close as it is:"
sh $d/run.sh guix-8.20.0 lifetime-plant 2>&1 | grep -E 'close =>|after t|jar j |counts|exited|raised' | sed 's/^/3 /'
