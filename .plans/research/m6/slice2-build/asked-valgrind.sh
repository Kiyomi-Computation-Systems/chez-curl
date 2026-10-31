#!/bin/sh
# A scratch program under Valgrind on the memory lane's libcurl (Ubuntu's
# 8.5.0, by discovery), in a throwaway ubuntu:24.04, as the host user, from
# the repository's root:
#   sh build/m6s2b/asked2/valgrind.sh SNAP PROGRAM LOG ARG...
# Valgrind's own report goes to LOG.valgrind; the program's output to LOG.
set -eu
snap=$1; prog=$2; log=$3; shift 3
root=$PWD
node=$(scripts/guix-env sh -c 'command -v node' < /dev/null)
exec docker run --rm -v "$root:/src" -v "$root:$root" -v /gnu/store:/gnu/store:ro \
  -e HOST_UID="$(id -u)" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
pkgs=$(grep -v -e "^#" -e "^\$" /src/packaging/debian-prereqs.txt | tr "\n" " ")
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends $pkgs >/dev/null 2>&1
u=$(getent passwd "$HOST_UID" | cut -d: -f1)
if [ -z "$u" ]; then useradd -m -u "$HOST_UID" lane; u=lane; fi
su "$u" -c "cd /src/'"$snap"' && make --no-print-directory deps >/dev/null && env NODE='"$node"' valgrind --command-line-only=yes --log-file=/src/'"$log"'.valgrind /src/build/e1/ci/chez-threads/bin/scheme --libdirs src:tests:build/scheme-libs --program /src/'"$prog"' '"$*"' > /src/'"$log"' 2>&1"
'
