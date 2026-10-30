#!/bin/sh
# M6's pause probe (2026-10-29) in Docker ubuntu:24.04. Run on the host, from
# the repository's root:
#   sh .plans/research/m6/pause/docker.sh CURRENT
# CURRENT is the install directory of curl 8.23.0 that
# scripts/ci/build-curl.sh --current made; it also needs spike E1's floor
# build in build/e1/ci/curl-floor and the floor's Node 20.10.0 in
# build/verify/m3s2/node20. Other Node comes from the Guix store, mounted
# read-only; the repository is mounted read-only too. Runs run.sh on the
# floor (7.85.0, under Node 20.10.0, as the floor lane runs), Ubuntu's 8.5.0
# with OpenSSL and with GnuTLS, and 8.23.0, each against its own headers.
# CASES, when set, is handed to run.sh, and so is PAUSE_NO_MULTIPLEX
# (probe.c's opt-in switch, added for M6 slice 1), empty when unset.
# The container's own lane runs on the host:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m6/pause/run.sh guix-8.20.0' < /dev/null
set -eu
[ "$#" -eq 1 ] || { echo "usage: docker.sh CURRENT" >&2; exit 2; }
[ -f .plans/research/m6/pause/run.sh ] || { echo "docker.sh: run it from the repository's root" >&2; exit 2; }
current=$(cd "$1" && pwd)
for f in "$current/lib/libcurl.so.4" "$current/include/curl/curl.h" build/e1/ci/curl-floor/lib/libcurl.so.4 \
         build/e1/ci/curl-floor/include/curl/curl.h build/verify/m3s2/node20/node; do
  [ -f "$f" ] || { echo "docker.sh: no $f" >&2; exit 1; }
done
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
node=$(scripts/guix-env sh -c 'command -v node' < /dev/null)
case $node in /gnu/store/*) ;; *) echo "docker.sh: node is not in the store: '$node'" >&2; exit 1 ;; esac
root=$PWD
exec docker run --rm -v "$root:/src:ro" -v "$root:$root:ro" -v /gnu/store:/gnu/store:ro \
  -e GUIX_NODE="$node" -e CURRENT="$current" -e CASES="${CASES:-}" \
  -e PAUSE_NO_MULTIPLEX="${PAUSE_NO_MULTIPLEX:-}" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
cd /src
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends build-essential libcurl4-openssl-dev libcurl3t64-gnutls ca-certificates openssl >/dev/null 2>&1
dpkg-query -W -f "package \${Package} \${Version}\n" libcurl4t64 libcurl3t64-gnutls libnghttp2-14 openssl gcc
arch=$(uname -m)-linux-gnu
export NODE=$GUIX_NODE CC=gcc
NODE=/src/build/verify/m3s2/node20/node CURL_LIB=/src/build/e1/ci/curl-floor/lib/libcurl.so.4 \
  CURL_INCLUDE=/src/build/e1/ci/curl-floor/include sh .plans/research/m6/pause/run.sh floor-7.85.0
CURL_LIB=/usr/lib/$arch/libcurl.so.4 sh .plans/research/m6/pause/run.sh ubuntu-openssl-8.5.0
CURL_LIB=/usr/lib/$arch/libcurl-gnutls.so.4 sh .plans/research/m6/pause/run.sh ubuntu-gnutls-8.5.0
CURL_LIB=$CURRENT/lib/libcurl.so.4 CURL_INCLUDE=$CURRENT/include sh .plans/research/m6/pause/run.sh current-8.23.0'
