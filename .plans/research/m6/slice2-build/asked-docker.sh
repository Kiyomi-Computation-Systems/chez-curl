#!/bin/sh
# A scratch program on one Docker lane, in a throwaway ubuntu:24.04, as the
# host user, from the repository's root:
#   sh build/m6s2b/asked/docker.sh SNAP LIBCURL PROGRAM ARG...
# LIBCURL is a path inside the container, or "main" for discovery.
set -eu
snap=$1; lib=$2; prog=$3; shift 3
root=$PWD
envlib=
[ "$lib" = main ] || envlib="CHEZ_CURL_LIBCURL=$lib"
exec docker run --rm -v "$root:/src" -v "$root:$root" -v /gnu/store:/gnu/store:ro \
  -e HOST_UID="$(id -u)" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
pkgs=$(grep -v -e "^#" -e "^\$" /src/packaging/debian-prereqs.txt | tr "\n" " ")
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends $pkgs >/dev/null 2>&1
u=$(getent passwd "$HOST_UID" | cut -d: -f1)
if [ -z "$u" ]; then useradd -m -u "$HOST_UID" lane; u=lane; fi
su "$u" -c "cd /src/'"$snap"' && make --no-print-directory deps >/dev/null && env NODE=/src/build/verify/m3s2/node20/node '"$envlib"' /src/build/e1/ci/chez-threads/bin/scheme --libdirs src:tests:build/scheme-libs --program /src/'"$prog"' '"$*"'"
'
