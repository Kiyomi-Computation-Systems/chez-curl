#!/bin/sh
# verify/memory-race.sh N: test-group and test-upload under the memory gate,
# on Ubuntu's 8.5.0 with OpenSSL, as CI's memory job runs them, in one --rm
# ubuntu:24.04 pinned to two CPUs, as a GitHub runner has two: N rounds, each the
# slice's tree (build/m7s4b/snap-ci) then main's (build/m7s4b/snap-main), a
# fresh copy of each. Prints each run's suite lines and FAIL titles. From
# the repository's root, on the host:
#   sh .plans/research/m7/slice4/verify/memory-race.sh 3 > .plans/research/m7/slice4/verify/results/memory-race.out 2>&1
set -eu
n=${1:-3}
root=$PWD
for d in build/m7s4b/snap-ci build/m7s4b/snap-main build/e1/ci/chez-threads build/verify/m3s2/node20; do
  [ -d "$d" ] || { echo "memory-race.sh: no $d" >&2; exit 2; }
done
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
exec docker run --rm --cpuset-cpus 0-1 -v "$root:/src:ro" -e N="$n" -e HOST_UID="$(id -u)" ubuntu:24.04 sh -c '
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
  for tree in ci main; do
    w=/work/$tree-$i
    mkdir -p "$w"
    (cd /src/build/m7s4b/snap-$tree && tar cf - .) | (cd "$w" && tar xf -)
    chown -R "$lane" "$w"
    start=$(date +%s)
    su "$lane" -c "cd $w && env CHEZ=$chez NODE=$node CC=gcc CHEZ_CURL_LIBCURL=/usr/lib/$arch/libcurl.so.4 make --no-print-directory deps test-memory MEMORY_SUITES=\"tests/test-group.sps tests/test-upload.sps\"" > "$w/memory.out" 2>&1 || true
    echo "=== round $i, tree $tree, $(( $(date +%s) - start )) s"
    grep -E "^test-memory: (pass|FAIL|HUNG|ran)" "$w/memory.out" || echo "(no test-memory lines: tail follows)"
    grep -E "^test-memory" "$w/memory.out" > /dev/null || tail -5 "$w/memory.out"
    cat "$w"/build/memory/*.log 2>/dev/null | grep -E "^FAIL|^  (expected|actual):" | cut -c1-400 || true
    rm -rf "$w"
  done
  i=$((i + 1))
done
echo "memory-race: done"'
