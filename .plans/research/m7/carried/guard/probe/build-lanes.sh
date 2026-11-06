#!/bin/sh
# build-lanes.sh TAG CPUS LANE...: make deps and make test, SUITES only, on
# the Docker lanes, as build/m7s4b/lanes.sh runs them (floor 7.85.0,
# Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, 8.23.0), each on a copy of
# build/carried-guard/build, under spike E1's threaded Chez, with Node
# 20.10.0; COPY names another copy under build/carried-guard, OUT another
# directory of the research's for the logs. One --rm ubuntu:24.04 pinned
# to CPUS. SUITES, as
# make takes it; MEMORY=1 runs make test-memory with MEMORY_SUITES=SUITES
# instead, ROUNDS times (1 by default). Logs to
# .plans/research/m7/carried/guard/build/lane-LANE-TAG[-ROUND].log.
set -eu
root=/home/kishu/src/chez-curl
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
tag=$1; cpus=$2; shift 2
copy=${COPY:-build}
[ -d "$root/build/carried-guard/$copy/src" ] || { echo "build-lanes: no copy build/carried-guard/$copy" >&2; exit 2; }
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
exec docker run --rm --cpuset-cpus "$cpus" -v "$root:/src" \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" -e TAG="$tag" -e SUITES="${SUITES:-}" \
  -e MEMORY="${MEMORY:-}" -e ROUNDS="${ROUNDS:-1}" -e COPY="$copy" -e OUT="${OUT:-build}" \
  ubuntu:24.04 sh /src/.plans/research/m7/carried/guard/probe/build-lanes-in-docker.sh "$@"
