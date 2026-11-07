#!/bin/sh
# M8 slice 2's four Docker lanes (floor 7.85.0, Ubuntu 24.04's 8.5.0 with
# OpenSSL and with GnuTLS, 8.23.0), as .plans/research/m7/slice4/build/lanes.sh
# ran them, under spike E1's threaded Chez 10.4.0, with --network none once
# the packages are cached, as research/m8/caps/docker.sh does. On the host,
# from the repository's root:
#
#   sh .plans/research/m8/slice2/lanes.sh WORK MODE TREE LANE... [-- ARG...]
#
# WORK is this slice's mktemp directory under build/m8s2/, holding the trees
# (main, proto, origin, probe). MODE:
#   probe  sh m8s2/run-probe.sh LANE m8s2/engine-probe.sps ARG... in TREE, read
#          only, Node as the caps probe ran each lane: 20.10.0 on the floor,
#          the Guix store's 24.18.0 elsewhere;
#   cost   sh m8s2/run-probe.sh LANE m8s2/cost.sps ARG... in TREE, Node 20.10.0;
#          VALGRIND, when set to a name, runs it under the memory gate's
#          Valgrind, its log WORK/logs/NAME;
#   test   make deps test in a copy of TREE under /work, as the host's user,
#          with Node 20.10.0, as lanes-in-docker.sh did; SUITES, when set,
#          names the suites. Its log is WORK/logs/test-TAG-LANE.log.
#   memory make deps test-memory MEMORY_SUITES=SUITES in such a copy; its log
#          WORK/logs/memory-TAG-LANE.log.
# SERVER and H2_LIMITS, when set, are handed to run-probe.sh in probe mode;
# PROBE_NODE, node20 or guix, sets every lane's Node there.
# LANE is floor, openssl, gnutls or current. TAG names the logs. CPUS, the
# container's CPUs, 6-17 by default. One --rm ubuntu:24.04 per call,
# nothing else touched.
set -eu
[ -f .plans/research/m8/slice2/lanes-in-docker.sh ] || { echo "lanes.sh: run it from the repository's root" >&2; exit 2; }
work=$1; mode=$2; tree=$3; shift 3
lanes=
while [ "$#" -gt 0 ] && [ "$1" != -- ]; do lanes="$lanes $1"; shift; done
[ "$#" -gt 0 ] && shift
case $work in /*) ;; *) work=$PWD/$work ;; esac
[ -d "$work/$tree" ] || { echo "lanes.sh: no tree $work/$tree" >&2; exit 2; }
cpus=${CPUS:-6-17}
root=$PWD
cache=$root/build/m8s2/apt
pkgs=$(grep -v -e '^#' -e '^$' packaging/debian-prereqs.txt | tr '\n' ' ')
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
if [ ! -f "$cache/fetched" ]; then
  mkdir -p "$cache/archives/partial" "$cache/lists/partial"
  docker run --rm --cpuset-cpus "$cpus" -v "$cache/archives:/var/cache/apt/archives" -v "$cache/lists:/var/lib/apt/lists" \
    -e HOSTID="$(id -u):$(id -g)" -e PKGS="$pkgs" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
rm -f /etc/apt/apt.conf.d/docker-clean
apt-get update -qq >/dev/null
apt-get install -y -qq --download-only --no-install-recommends $PKGS >/dev/null
chown -R "$HOSTID" /var/cache/apt/archives /var/lib/apt/lists'
  touch "$cache/fetched"
fi
node=$(scripts/guix-env sh -c 'command -v node' < /dev/null)
case $node in /gnu/store/*) ;; *) echo "lanes.sh: node is not in the store: '$node'" >&2; exit 1 ;; esac
mkdir -p "$work/logs"
echo "lanes.sh start $(date -u +%Y-%m-%dT%H:%M:%SZ) mode=$mode tree=$tree lanes=$lanes cpuset=$cpus args=$*"
exec docker run --rm --network none --cpuset-cpus "$cpus" -v "$root:/src:ro" -v "$work:/w" -v /gnu/store:/gnu/store:ro \
  -v "$cache:/aptcache:ro" -e GUIX_NODE="$node" -e PKGS="$pkgs" -e MODE="$mode" -e TREE="$tree" \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" -e SUITES="${SUITES:-}" -e TAG="${TAG:-}" -e VALGRIND="${VALGRIND:-}" \
  -e SERVER="${SERVER:-}" -e H2_LIMITS="${H2_LIMITS:-}" -e PROBE_NODE="${PROBE_NODE:-}" \
  -e ARGS="$*" ubuntu:24.04 sh /src/.plans/research/m8/slice2/lanes-in-docker.sh $lanes
