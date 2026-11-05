#!/bin/sh
# M7 slice 4's review: each probe of PROBES on each LANE, in one --rm
# ubuntu:24.04, as the build's lanes.sh runs its lanes (floor 7.85.0,
# Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, 8.23.0), on a snapshot of the
# review tree, build/m7s4-review/snap. On the host, from the repository's
# root:
#
#   PROBES='probes/probe-load.sps probes/probe-engine.sps' \
#     sh .plans/research/m7/slice4/review/probe-lanes.sh LANE...
#
# Logs under build/m7s4-review/lanes/. Nothing else touched.
set -eu
[ -d build/m7s4-review/base ] || { echo "probe-lanes.sh: run it from the repository's root" >&2; exit 2; }
rsync -a --delete --exclude /build --exclude /mut --exclude /logs build/m7s4-review/base/ build/m7s4-review/snap/
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
root=$PWD
exec docker run --rm -v "$root:/src" -v "$root:$root" \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" -e PROBES="$PROBES" \
  -e SNAP=/src/build/m7s4-review/snap \
  ubuntu:24.04 sh /src/.plans/research/m7/slice4/review/probe-lanes-in-docker.sh "$@"
