#!/bin/sh
# M5 slice 3's retry measurement (2026-10-28) in Docker ubuntu:24.04. Run on the
# host, from the repository's root:
#   sh .plans/research/m5/retry/docker.sh CURRENT
# CURRENT is the install directory of curl 8.23.0 that
# scripts/ci/build-curl.sh --current made; it also needs spike E1's floor
# curl in build/e1/ci/curl-floor and its threaded Chez in
# build/e1/ci/chez-threads. Node comes from the Guix store, mounted
# read-only. Runs run.sh on the floor (7.85.0), Ubuntu's 8.5.0 with OpenSSL
# and with GnuTLS, and 8.23.0. The container's own lane runs on the host:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m5/retry/run.sh guix-8.20.0' < /dev/null
set -eu
[ "$#" -eq 1 ] || { echo "usage: docker.sh CURRENT" >&2; exit 2; }
[ -f .plans/research/m5/retry/run.sh ] || { echo "docker.sh: run it from the repository's root" >&2; exit 2; }
current=$(cd "$1" && pwd)
for f in "$current/lib/libcurl.so.4" build/e1/ci/curl-floor/lib/libcurl.so.4 build/e1/ci/chez-threads/bin/scheme; do
  [ -f "$f" ] || { echo "docker.sh: no $f" >&2; exit 1; }
done
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
node=$(scripts/guix-env sh -c 'command -v node' < /dev/null)
case $node in /gnu/store/*) ;; *) echo "docker.sh: node is not in the store: '$node'" >&2; exit 1 ;; esac
root=$PWD
exec docker run --rm -v "$root:/src" -v "$root:$root" -v /gnu/store:/gnu/store:ro \
  -e GUIX_NODE="$node" -e CURRENT="$current" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
cd /src
pkgs=$(grep -v -e "^#" -e "^\$" packaging/debian-prereqs.txt | tr "\n" " ")
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends $pkgs >/dev/null 2>&1
dpkg-query -W -f "package \${Package} \${Version}\n" libcurl4t64 libcurl3t64-gnutls
arch=$(uname -m)-linux-gnu
export NODE=$GUIX_NODE CC=gcc CHEZ=/src/build/e1/ci/chez-threads/bin/scheme
CURL_LIB=/src/build/e1/ci/curl-floor/lib/libcurl.so.4 CURL_INCLUDE=/src/build/e1/ci/curl-floor/include \
  sh .plans/research/m5/retry/run.sh floor-7.85.0
CURL_LIB=/usr/lib/$arch/libcurl.so.4 sh .plans/research/m5/retry/run.sh ubuntu-openssl-8.5.0
CURL_LIB=/usr/lib/$arch/libcurl-gnutls.so.4 sh .plans/research/m5/retry/run.sh ubuntu-gnutls-8.5.0
CURL_LIB=$CURRENT/lib/libcurl.so.4 CURL_INCLUDE=$CURRENT/include sh .plans/research/m5/retry/run.sh current-8.23.0'
