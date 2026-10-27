#!/bin/sh
# M4 slice 4's measurements in Docker ubuntu:24.04. Run on the host, from the
# repository's root:
#
#   [PLAIN_ONLY=1] sh .plans/research/m4/slice4/docker.sh CURRENT [SET...]
#
# CURRENT is the install directory of curl 8.23.0 that
# scripts/ci/build-curl.sh --current made. It also needs spike E1's floor
# build in build/e1/ci/curl-floor and its threaded Chez in
# build/e1/ci/chez-threads, for the chez set. The store is mounted read-only,
# for Node. It runs run.sh on four lanes, each plainly and then, unless
# PLAIN_ONLY is set, under Ubuntu's Valgrind with the memory gate's options:
#   floor            curl 7.85.0, built from source with OpenSSL
#   ubuntu-openssl   Ubuntu's libcurl4t64 8.5.0
#   ubuntu-gnutls    Ubuntu's libcurl3t64-gnutls 8.5.0
#   current          curl 8.23.0, built from source with OpenSSL
# The container's own lane runs on the host:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m4/slice4/run.sh guix-8.20.0'
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL VALGRIND=valgrind sh .plans/research/m4/slice4/run.sh guix-8.20.0-valgrind'
set -eu
[ "$#" -ge 1 ] || { echo "usage: docker.sh CURRENT [SET...]" >&2; exit 2; }
[ -f .plans/research/m4/slice4/run.sh ] || { echo "docker.sh: run it from the repository's root" >&2; exit 2; }
current=$(cd "$1" && pwd)
shift
for lib in "$current/lib/libcurl.so.4" build/e1/ci/curl-floor/lib/libcurl.so.4; do
  [ -f "$lib" ] || { echo "docker.sh: no $lib" >&2; exit 1; }
done
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
node=$(scripts/guix-env sh -c 'command -v node' < /dev/null)
case $node in /gnu/store/*) ;; *) echo "docker.sh: node is not in the store: '$node'" >&2; exit 1 ;; esac
root=$PWD
exec docker run --rm -v "$root:/src" -v "$root:$root" -v /gnu/store:/gnu/store:ro \
  -e GUIX_NODE="$node" -e CURRENT="$current" -e PLAIN_ONLY="${PLAIN_ONLY:-}" \
  ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
cd /src
pkgs=$(grep -v -e "^#" -e "^$" packaging/debian-prereqs.txt | tr "\n" " ")
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends $pkgs >/dev/null 2>&1
dpkg-query -W -f "package \${Package} \${Version}\n" libcurl4t64 libcurl3t64-gnutls libgnutls30t64 libssl3t64 libc6 valgrind
arch=$(uname -m)-linux-gnu
export NODE=$GUIX_NODE CC=gcc CHEZ=/src/build/e1/ci/chez-threads/bin/scheme
for vg in "" ${PLAIN_ONLY:+no-}valgrind; do
  [ "$vg" != no-valgrind ] || continue
  sfx=${vg:+-valgrind}
  VALGRIND=$vg CURL_LIB=/src/build/e1/ci/curl-floor/lib/libcurl.so.4 CURL_INCLUDE=/src/build/e1/ci/curl-floor/include \
    sh .plans/research/m4/slice4/run.sh floor$sfx "$@"
  VALGRIND=$vg CURL_LIB=/usr/lib/$arch/libcurl.so.4 sh .plans/research/m4/slice4/run.sh ubuntu-openssl$sfx "$@"
  VALGRIND=$vg CURL_LIB=/usr/lib/$arch/libcurl-gnutls.so.4 sh .plans/research/m4/slice4/run.sh ubuntu-gnutls$sfx "$@"
  VALGRIND=$vg CURL_LIB=$CURRENT/lib/libcurl.so.4 CURL_INCLUDE=$CURRENT/include \
    sh .plans/research/m4/slice4/run.sh current$sfx "$@"
done' sh "$@"
