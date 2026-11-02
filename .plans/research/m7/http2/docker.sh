#!/bin/sh
# M7's HTTP/2 probe (2026-11-02) in Docker ubuntu:24.04, as M6's pause probe
# ran there. Run on the host, from the repository's root:
#   sh .plans/research/m7/http2/docker.sh
# It needs curl 8.23.0's install in build/verify/c823/lane1/curl-current
# (scripts/ci/build-curl.sh --current), spike E1's floor build in
# build/e1/ci/curl-floor and the floor's Node 20.10.0 in
# build/verify/m3s2/node20. Other Node comes from the Guix store, mounted
# read-only; the repository is mounted read-only too. Runs run.sh on the
# floor (7.85.0, under Node 20.10.0, as the floor lane runs), Ubuntu's 8.5.0
# with OpenSSL and with GnuTLS, and 8.23.0, each against its own headers.
# CASES and PROBE_NO_MULTIPLEX, when set, are handed to run.sh.
# The container's own lane runs on the host:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m7/http2/run.sh guix-8.20.0' < /dev/null
set -eu
[ "$#" -eq 0 ] || { echo "usage: docker.sh" >&2; exit 2; }
[ -f .plans/research/m7/http2/run.sh ] || { echo "docker.sh: run it from the repository's root" >&2; exit 2; }
current=build/verify/c823/lane1/curl-current
for f in "$current/lib/libcurl.so.4" "$current/include/curl/curl.h" build/e1/ci/curl-floor/lib/libcurl.so.4 \
         build/e1/ci/curl-floor/include/curl/curl.h build/verify/m3s2/node20/node; do
  [ -f "$f" ] || { echo "docker.sh: no $f" >&2; exit 1; }
done
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
node=$(scripts/guix-env sh -c 'command -v node' < /dev/null)
case $node in /gnu/store/*) ;; *) echo "docker.sh: node is not in the store: '$node'" >&2; exit 1 ;; esac
exec docker run --rm -v "$PWD:/src:ro" -v /gnu/store:/gnu/store:ro \
  -e GUIX_NODE="$node" -e CURRENT="/src/$current" -e CASES="${CASES:-}" \
  -e PROBE_NO_MULTIPLEX="${PROBE_NO_MULTIPLEX:-}" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
cd /src
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends build-essential libcurl4-openssl-dev libcurl3t64-gnutls ca-certificates openssl >/dev/null 2>&1
dpkg-query -W -f "package \${Package} \${Version}\n" libcurl4t64 libcurl3t64-gnutls libcurl4-openssl-dev libnghttp2-14 openssl gcc
arch=$(uname -m)-linux-gnu
export NODE=$GUIX_NODE CC=gcc
[ -n "$CASES" ] || unset CASES
NODE=/src/build/verify/m3s2/node20/node CURL_LIB=/src/build/e1/ci/curl-floor/lib/libcurl.so.4 \
  CURL_INCLUDE=/src/build/e1/ci/curl-floor/include sh .plans/research/m7/http2/run.sh floor-7.85.0
CURL_LIB=/usr/lib/$arch/libcurl.so.4 sh .plans/research/m7/http2/run.sh ubuntu-openssl-8.5.0
CURL_LIB=/usr/lib/$arch/libcurl-gnutls.so.4 sh .plans/research/m7/http2/run.sh ubuntu-gnutls-8.5.0
CURL_LIB=$CURRENT/lib/libcurl.so.4 CURL_INCLUDE=$CURRENT/include sh .plans/research/m7/http2/run.sh current-8.23.0'
