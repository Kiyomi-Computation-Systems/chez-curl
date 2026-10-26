#!/bin/sh
# M3 slice 3's Docker lanes. Run on the host, from the repository's root,
# after `make deps`, and after spike E1's docker.sh has built the floors'
# Chez and libcurl into build/e1/ci:
#
#   sh .plans/research/stall/docker.sh SET...
#
# It starts ubuntu:24.04 with the repository at /src and at its own path,
# and the Guix store read-only for Node, and runs run.sh there on three
# lanes, each under the floor's Chez:
#   floor           curl 7.85.0, built from source with OpenSSL
#   ubuntu-openssl  Ubuntu's libcurl4t64 8.5.0
#   ubuntu-gnutls   Ubuntu's libcurl3t64-gnutls 8.5.0
# The container's own lane runs on the host:
#   scripts/guix-env sh .plans/research/stall/run.sh container SET...
set -eu
[ -f .plans/research/stall/run.sh ] || { echo "docker.sh: run it from the repository's root" >&2; exit 2; }
[ -x build/e1/ci/chez-threads/bin/scheme ] && [ -f build/e1/ci/curl-floor/lib/libcurl.so.4 ] \
  || { echo "docker.sh: spike E1's builds are missing from build/e1/ci: run .plans/research/e1/docker.sh first" >&2; exit 1; }
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
node=$(scripts/guix-env sh -c 'command -v node')
case $node in /gnu/store/*) ;; *) echo "docker.sh: node is not in the store: '$node'" >&2; exit 1 ;; esac
root=$PWD
exec docker run --rm -v "$root:/src" -v "$root:$root" -v /gnu/store:/gnu/store:ro \
  -e GUIX_NODE="$node" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
cd /src
pkgs=$(grep -v -e "^#" -e "^$" packaging/debian-prereqs.txt | tr "\n" " ")
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends $pkgs >/dev/null 2>&1
dpkg-query -W -f "package \${Package} \${Version}\n" libcurl4t64 libcurl3t64-gnutls libc6
ci=/src/build/e1/ci
arch=$(uname -m)-linux-gnu
export CHEZ=$ci/chez-threads/bin/scheme NODE=$GUIX_NODE CC=gcc
for lane in "floor:$ci/curl-floor/lib/libcurl.so.4" \
            "ubuntu-openssl:/usr/lib/$arch/libcurl.so.4" \
            "ubuntu-gnutls:/usr/lib/$arch/libcurl-gnutls.so.4"; do
  CHEZ_CURL_LIBCURL=${lane#*:} sh .plans/research/stall/run.sh "${lane%%:*}" "$@"
done' sh "$@"
