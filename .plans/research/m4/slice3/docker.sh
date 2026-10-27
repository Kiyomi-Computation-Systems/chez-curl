#!/bin/sh
# M4 slice 3's measurements in Docker ubuntu:24.04. Run on the host, from the
# repository's root:
#
#   sh .plans/research/m4/slice3/docker.sh CURRENT GUIX-8.20.0 GUIX-8.6.0 [SET...]
#
# CURRENT is the install directory of curl 8.23.0 that
# scripts/ci/build-curl.sh --current made; GUIX-8.20.0 and GUIX-8.6.0 are
# store directories of Guix's curl. It also needs spike E1's floor build in
# build/e1/ci/curl-floor and its threaded Chez in build/e1/ci/chez-threads.
# The store is mounted read-only, for Node and for Guix's libcurls, which
# load from it with their closures beside Ubuntu's libc. It runs run.sh on
# six lanes, and the maps set under spike E1's Chez on each:
#   floor            curl 7.85.0, built from source with OpenSSL
#   ubuntu-openssl   Ubuntu's libcurl4t64 8.5.0
#   ubuntu-gnutls    Ubuntu's libcurl3t64-gnutls 8.5.0
#   current          curl 8.23.0, built from source with OpenSSL
#   guix-8.20.0-fhs  Guix's 8.20.0, loaded outside Guix
#   guix-8.6.0-fhs   Guix's 8.6.0, loaded outside Guix
# The container's own lane runs on the host:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m4/slice3/run.sh guix-8.20.0 when pkcs11 proxy maps'
set -eu
[ "$#" -ge 3 ] || { echo "usage: docker.sh CURRENT GUIX-8.20.0 GUIX-8.6.0 [SET...]" >&2; exit 2; }
[ -f .plans/research/m4/slice3/run.sh ] || { echo "docker.sh: run it from the repository's root" >&2; exit 2; }
current=$(cd "$1" && pwd)
guix820=$2 guix86=$3
shift 3
for lib in "$current/lib/libcurl.so.4" "$guix820/lib/libcurl.so.4" "$guix86/lib/libcurl.so.4" \
           build/e1/ci/curl-floor/lib/libcurl.so.4; do
  [ -f "$lib" ] || { echo "docker.sh: no $lib" >&2; exit 1; }
done
[ -x build/e1/ci/chez-threads/bin/scheme ] || { echo "docker.sh: spike E1's Chez is missing" >&2; exit 1; }
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
node=$(scripts/guix-env sh -c 'command -v node' < /dev/null)
case $node in /gnu/store/*) ;; *) echo "docker.sh: node is not in the store: '$node'" >&2; exit 1 ;; esac
root=$PWD
exec docker run --rm -v "$root:/src" -v "$root:$root" -v /gnu/store:/gnu/store:ro \
  -e GUIX_NODE="$node" -e CURRENT="$current" -e GUIX820="$guix820" -e GUIX86="$guix86" \
  ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
cd /src
pkgs=$(grep -v -e "^#" -e "^$" packaging/debian-prereqs.txt | tr "\n" " ")
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends $pkgs >/dev/null 2>&1
dpkg-query -W -f "package \${Package} \${Version}\n" libcurl4t64 libcurl3t64-gnutls libgnutls30t64 libssl3t64 libc6
arch=$(uname -m)-linux-gnu
export NODE=$GUIX_NODE CC=gcc CHEZ=/src/build/e1/ci/chez-threads/bin/scheme
[ "$#" -ge 1 ] || set -- when pkcs11 proxy maps
CURL_LIB=/src/build/e1/ci/curl-floor/lib/libcurl.so.4 CURL_INCLUDE=/src/build/e1/ci/curl-floor/include \
  sh .plans/research/m4/slice3/run.sh floor "$@"
CURL_LIB=/usr/lib/$arch/libcurl.so.4 sh .plans/research/m4/slice3/run.sh ubuntu-openssl "$@"
CURL_LIB=/usr/lib/$arch/libcurl-gnutls.so.4 sh .plans/research/m4/slice3/run.sh ubuntu-gnutls "$@"
CURL_LIB=$CURRENT/lib/libcurl.so.4 CURL_INCLUDE=$CURRENT/include sh .plans/research/m4/slice3/run.sh current "$@"
CURL_LIB=$GUIX820/lib/libcurl.so.4 sh .plans/research/m4/slice3/run.sh guix-8.20.0-fhs "$@"
CURL_LIB=$GUIX86/lib/libcurl.so.4 sh .plans/research/m4/slice3/run.sh guix-8.6.0-fhs "$@"' sh "$@"
