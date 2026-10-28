#!/bin/sh
# Runs lanes-in-docker.sh in a throwaway ubuntu:24.04, on the host, from the
# repository's root:
#
#   sh build/m5s1/lanes.sh LANE...
#
# The repository is mounted at /src and at its own path, which make deps's
# links name, and the Guix store read-only, for Node.
set -eu
[ -f build/m5s1/lanes-in-docker.sh ] || { echo "lanes.sh: run it from the repository's root" >&2; exit 2; }
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
node=$(scripts/guix-env sh -c 'command -v node')
case $node in /gnu/store/*) ;; *) echo "lanes.sh: node is not in the store: '$node'" >&2; exit 1 ;; esac
root=$PWD
exec docker run --rm -v "$root:/src" -v "$root:$root" -v /gnu/store:/gnu/store:ro \
  -e GUIX_NODE="$node" -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" -e SUITES="${SUITES:-}" \
  ubuntu:24.04 sh /src/build/m5s1/lanes-in-docker.sh "$@"
