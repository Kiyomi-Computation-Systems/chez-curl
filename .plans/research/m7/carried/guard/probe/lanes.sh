#!/bin/sh
# lanes.sh TAG PROGRAM LANE...: PROGRAM, a probe under probe/, on the Docker
# lanes, as build/m7s4b/lanes.sh runs them (floor 7.85.0, Ubuntu's 8.5.0 with
# OpenSSL and with GnuTLS, 8.23.0), each on a copy of
# build/carried-guard/q2 (the snapshot and these probes), under spike E1's
# threaded Chez and Node 20.10.0, after make deps alone. One --rm
# ubuntu:24.04, pinned to CPUs 10 to 17; nothing else touched. Each lane's
# output goes to results/lane-LANE-TAG.log. UNDER_VALGRIND=1 runs the probe
# under Valgrind's memcheck, its own log discarded, for the memory gate's
# timing; timeout stays outside Valgrind.
set -eu
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=/home/kishu/src/chez-curl
tag=$1; program=$2; shift 2
[ -d "$root/build/carried-guard/q2/src" ] || { echo "lanes: no copy build/carried-guard/q2" >&2; exit 2; }
mkdir -p "$root/build/carried-guard/q2/probe"
cp "$here"/*.sps "$here"/*.mjs "$root/build/carried-guard/q2/probe/"
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
exec docker run --rm --cpuset-cpus 10-17 -v "$root:/src" \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" -e TAG="$tag" -e PROGRAM="$program" -e UNDER_VALGRIND="${UNDER_VALGRIND:-}" -e HELD_REPS="${HELD_REPS:-}" -e HELD_PATHS="${HELD_PATHS:-}" -e HELD_FACES="${HELD_FACES:-}" \
  ubuntu:24.04 sh /src/.plans/research/m7/carried/guard/probe/lanes-in-docker.sh "$@"
