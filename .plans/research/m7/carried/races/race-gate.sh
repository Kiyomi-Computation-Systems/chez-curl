#!/bin/sh
# build/carried-races/race-gate.sh N: a copy of .plans/research/m7/slice4/races/race-gate.sh
# for the carried races. The suites SUITES names (tests/test-origin-tls.sps by
# default), under the memory gate (MODE=gate, the default) or natively
# (MODE=native), on Ubuntu's 8.5.0 with OpenSSL, as CI's memory job runs them, in
# one --rm ubuntu:24.04 pinned to the CPUs CPUS names (within 0-9; a GitHub
# runner has two): N rounds, each tree TREES names in turn (main by default),
# each run on a fresh copy of build/carried-races/snap-TREE. With RACE=1 (the
# default) the instrumented origin and probe log to RACE_LOG, and the mailbox
# child to MAILBOX_PROBE_LOG, copied out as race.log and window.log. Each run's suite logs go to build/carried-races/out/LABEL/TREE-ROUND/.
# Prints each run's suite lines and FAIL titles with their values. From the
# repository's root, on the host:
#   CPUS=0,1 LABEL=NAME sh build/carried-races/race-gate.sh 10 > build/carried-races/out/NAME.out 2>&1
set -eu
n=${1:-3}
root=$PWD
mode=${MODE:-gate}
trees=${TREES:-main}
cpus=${CPUS:-0,1}
suites=${SUITES:-tests/test-origin-tls.sps}
label=${LABEL:-$mode}
race=${RACE:-1}
out=build/carried-races/out/$label
case $cpus in
  *1[0-9]*) echo "race-gate.sh: CPUS $cpus is outside 0-9" >&2; exit 2 ;;
esac
for t in $trees; do
  [ -d "build/carried-races/snap-$t" ] || { echo "race-gate.sh: no build/carried-races/snap-$t" >&2; exit 2; }
done
for d in build/e1/ci/chez-threads build/verify/m3s2/node20; do
  [ -d "$d" ] || { echo "race-gate.sh: no $d" >&2; exit 2; }
done
mkdir -p "$out"
echo "race-gate: mode $mode, trees $trees, cpus $cpus, suites $suites, race $race, out $out"
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
exec docker run --rm --cpuset-cpus "$cpus" -v "$root:/src:ro" -v "$root/$out:/out" \
  -e N="$n" -e HOST_UID="$(id -u)" -e MODE="$mode" -e TREES="$trees" -e RACE="$race" \
  -e SUITES="$suites" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
pkgs=$(grep -v -e "^#" -e "^$" /src/packaging/debian-prereqs.txt | tr "\n" " ")
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends $pkgs >/dev/null 2>&1
dpkg-query -W -f "package \${Package} \${Version}\n" libcurl4t64 valgrind
echo "cpus: $(nproc)"
lane=$(getent passwd "$HOST_UID" | cut -d: -f1)
if [ -z "$lane" ]; then useradd -m -u "$HOST_UID" lane; lane=lane; fi
chez=/src/build/e1/ci/chez-threads/lib/csv10.4.0/ta6le/scheme
node=/src/build/verify/m3s2/node20/node
arch=$(uname -m)-linux-gnu
i=1
while [ "$i" -le "$N" ]; do
  for tree in $TREES; do
    w=/work/run
    rm -rf /work/run
    mkdir -p "$w"
    (cd /src/build/carried-races/snap-$tree && tar cf - .) | (cd "$w" && tar xf -)
    chown -R "$lane" "$w"
    start=$(date +%s)
    if [ "$MODE" = gate ]; then
      goal="deps test-memory MEMORY_SUITES=\"$SUITES\""
    else
      goal="deps test SUITES=\"$SUITES\""
    fi
    racelog=
    [ "$RACE" = 1 ] && racelog="RACE_LOG=$w/race.log MAILBOX_PROBE_LOG=$w/window.log"
    su "$lane" -c "cd $w && env $racelog CHEZ=$chez NODE=$node CC=gcc CHEZ_CURL_LIBCURL=/usr/lib/$arch/libcurl.so.4 make --no-print-directory $goal" > "$w/make.out" 2>&1 || true
    echo "=== round $i, tree $tree, mode $MODE, $(( $(date +%s) - start )) s"
    mkdir -p /out/$tree-$i
    cp "$w/make.out" /out/$tree-$i/
    cp "$w"/build/memory/*.log /out/$tree-$i/ 2>/dev/null || true
    cp "$w"/build/memory/*.valgrind /out/$tree-$i/ 2>/dev/null || true
    cp "$w"/race.log /out/$tree-$i/ 2>/dev/null || true
    cp "$w"/window.log /out/$tree-$i/ 2>/dev/null || true
    chown -R "$HOST_UID" /out/$tree-$i
    if [ "$MODE" = gate ]; then
      grep -E "^test-memory: (pass|FAIL|HUNG|ran)" "$w/make.out" || { echo "(no test-memory lines: tail follows)"; tail -5 "$w/make.out"; }
      logs=$(ls "$w"/build/memory/*.log 2>/dev/null || true)
    else
      grep -E "^test: (pass|FAIL|HUNG|ran)" "$w/make.out" || { echo "(no test lines: tail follows)"; tail -5 "$w/make.out"; }
      logs=$w/make.out
    fi
    for f in $logs; do
      grep -E "^FAIL|^  (expected|actual):" "$f" | cut -c1-600 || true
      grep -E "^PROBE" "$f" | sed "s/^/[$tree $i] /" || true
    done
  done
  i=$((i + 1))
done
echo "race-gate: done"'
