#!/bin/sh
# The control on the floor lane, curl 7.85.0, in a throwaway ubuntu:24.04,
# from the repository's root on the host:  sh build/m6s2b/control/docker.sh SNAP RUNS
# SNAP is a tree copy under build/m6s2b/runs/; its build/scheme-libs is made here.
set -eu
snap=$1
runs=$2
root=$PWD
exec docker run --rm -v "$root:/src" -v "$root:$root" -v /gnu/store:/gnu/store:ro \
  -e HOST_UID="$(id -u)" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
pkgs=$(grep -v -e "^#" -e "^\$" /src/packaging/debian-prereqs.txt | tr "\n" " ")
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends $pkgs >/dev/null 2>&1
u=$(getent passwd "$HOST_UID" | cut -d: -f1)
if [ -z "$u" ]; then useradd -m -u "$HOST_UID" lane; u=lane; fi
su "$u" -c "cd /src/'"$snap"' && make --no-print-directory deps && NODE=/src/build/verify/m3s2/node20/node CHEZ_CURL_LIBCURL=/src/build/e1/ci/curl-floor/lib/libcurl.so.4 /src/build/e1/ci/chez-threads/bin/scheme --libdirs src:tests:build/scheme-libs --program /src/build/m6s2b/control/control.sps '"$runs"'"
'
