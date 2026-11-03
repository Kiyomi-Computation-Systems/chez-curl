#!/bin/sh
# The review's Docker lane runner: one --rm ubuntu:24.04, nothing else
# touched. On the host, from the repository's root:
#   sh build/m7s2-review/lane.sh LANE TREE 'COMMAND'
# LANE floor, openssl, gnutls or current; TREE a tree under the repository
# (its src/ and tests/ are used); COMMAND run in a copy of TREE with CHEZ,
# NODE, CC and the lane's CHEZ_CURL_LIBCURL (and C_INCLUDE_PATH) set.
set -eu
root=$PWD
exec docker run --rm -v "$root:/src" -v "$root:$root" \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" -e LANE="$1" -e TREE="$2" -e COMMAND="$3" \
  ubuntu:24.04 sh /src/build/m7s2-review/lane-in-docker.sh
