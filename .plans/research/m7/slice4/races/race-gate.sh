#!/bin/sh
# races/race-gate.sh N: the suites SUITES names (test-group and test-upload by
# default), under the memory gate (MODE=gate, the default) or natively
# (MODE=native), on Ubuntu's 8.5.0 with OpenSSL, as CI's memory job runs them,
# in one --rm ubuntu:24.04 pinned to the CPUs CPUS names (0-1 by default; a
# GitHub runner has two): N rounds, each tree TREES names in turn (ci main by
# default), each run on a fresh copy of SNAP-TREE (build/m7s4r/snap-TREE-probe
# by default, SNAP the prefix). A copy of verify/memory-race.sh's container, with
# sigprobe.c, at the copy's root, built into /work/sigprobe.so and named by
# SIGPROBE for the instrumented children. Prints each run's suite lines, FAIL
# titles with their values, and every PROBE line; each run's suite logs go to
# OUT/TREE-ROUND/ (build/m7s4r/out/LABEL, LABEL by default MODE). From the
# repository's root, on the host:
#   sh .plans/research/m7/slice4/races/race-gate.sh 10 > .plans/research/m7/slice4/races/results/NAME.out 2>&1
set -eu
n=${1:-3}
root=$PWD
mode=${MODE:-gate}
trees=${TREES:-ci main}
snap=${SNAP:-build/m7s4r/snap-}
suffix=${SNAP_SUFFIX--probe}
cpus=${CPUS:-0-1}
suites=${SUITES:-tests/test-group.sps tests/test-upload.sps}
label=${LABEL:-$mode}
out=build/m7s4r/out/$label
for t in $trees; do
  [ -d "$snap$t$suffix" ] || { echo "race-gate.sh: no $snap$t$suffix" >&2; exit 2; }
done
for d in build/e1/ci/chez-threads build/verify/m3s2/node20; do
  [ -d "$d" ] || { echo "race-gate.sh: no $d" >&2; exit 2; }
done
mkdir -p "$out"
echo "race-gate: mode $mode, trees $trees, snap $snap*$suffix, cpus $cpus, suites $suites, out $out"
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
exec docker run --rm --cpuset-cpus "$cpus" -v "$root:/src:ro" -v "$root/$out:/out" \
  -e N="$n" -e HOST_UID="$(id -u)" -e MODE="$mode" -e TREES="$trees" -e SNAP="$snap" -e SUFFIX="$suffix" \
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
    (cd /src/$SNAP$tree$SUFFIX && tar cf - .) | (cd "$w" && tar xf -)
    if [ -f "$w/sigprobe.c" ]; then gcc -shared -fPIC -O2 -o "$w/sigprobe.so" "$w/sigprobe.c"; fi
    chown -R "$lane" "$w"
    start=$(date +%s)
    if [ "$MODE" = gate ]; then
      goal="deps test-memory MEMORY_SUITES=\"$SUITES\""
    else
      goal="deps test SUITES=\"$SUITES\""
    fi
    su "$lane" -c "cd $w && env ORIGIN_PROBE_LOG=$w/origin-probe.log SIGPROBE=$w/sigprobe.so CHEZ=$chez NODE=$node CC=gcc CHEZ_CURL_LIBCURL=/usr/lib/$arch/libcurl.so.4 make --no-print-directory $goal" > "$w/make.out" 2>&1 || true
    echo "=== round $i, tree $tree, mode $MODE, $(( $(date +%s) - start )) s"
    mkdir -p /out/$tree-$i
    cp "$w/make.out" /out/$tree-$i/
    cp "$w"/build/memory/*.log /out/$tree-$i/ 2>/dev/null || true
    cp "$w"/origin-probe.log /out/$tree-$i/ 2>/dev/null || true
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
