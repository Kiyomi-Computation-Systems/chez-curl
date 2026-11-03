#!/bin/sh
# M7 slice 3's build: the four Docker lanes, as .plans/research/m7/slice2/
# runs them (floor 7.85.0, Ubuntu's 8.5.0 with OpenSSL and with GnuTLS,
# 8.23.0), each running make test on a copy of SNAP, under spike E1's
# threaded Chez, with Node 20.10.0. On the host, from the repository's root:
#
#   sh build/m7s3b/lanes.sh LANE...
#
# LANE is floor, openssl, gnutls or current. SUITES, when set, names the
# suites make test runs; MEMORY_SUITES, when set, those make test-memory
# runs after. SNAP is the tree to copy, build/m7s3b/snap by default. TAG is
# added to each log's name. One --rm ubuntu:24.04, nothing else touched.
set -eu
[ -f build/m7s3b/lanes-in-docker.sh ] || { echo "lanes.sh: run it from the repository's root" >&2; exit 2; }
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
root=$PWD
exec docker run --rm -v "$root:/src" -v "$root:$root" \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" -e SUITES="${SUITES:-}" -e MEMORY_SUITES="${MEMORY_SUITES:-}" \
  -e SNAP="${SNAP:-/src/build/m7s3b/snap}" -e TAG="${TAG:-}" \
  ubuntu:24.04 sh /src/build/m7s3b/lanes-in-docker.sh "$@"
