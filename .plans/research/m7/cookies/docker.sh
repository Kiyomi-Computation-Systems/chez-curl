#!/bin/sh
# M7's cookie probe (2026-11-02) in Docker ubuntu:24.04. Run on the host,
# from the repository's root:
#   sh .plans/research/m7/cookies/docker.sh CURRENT
# CURRENT is the install directory of curl 8.23.0 that
# scripts/ci/build-curl.sh --current made
# (build/verify/c823/lane1/curl-current); it also needs spike E1's floor
# build in build/e1/ci/curl-floor and the floor's Node 20.10.0 in
# build/verify/m3s2/node20. Other Node comes from the Guix store, mounted
# read-only; the repository is mounted read-only too. Runs run.sh on the
# floor (7.85.0, under Node 20.10.0, as the floor lane runs), Ubuntu's 8.5.0
# with OpenSSL and with GnuTLS (the GnuTLS one against libcurl4-openssl-dev's
# headers, 8.5.0's too, as CI's GnuTLS lane builds), and 8.23.0, each
# against its own headers. CASES, when set, is handed to run.sh. Once apt
# is done, /etc/resolv.conf names a server that is not there (127.0.0.9).
# The container's own lane runs on the host:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m7/cookies/run.sh guix-8.20.0' < /dev/null
set -eu
[ "$#" -eq 1 ] || { echo "usage: docker.sh CURRENT" >&2; exit 2; }
[ -f .plans/research/m7/cookies/run.sh ] || { echo "docker.sh: run it from the repository's root" >&2; exit 2; }
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
  -e GUIX_NODE="$node" -e CURRENT="$current" -e CASES="${CASES:-}" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
cd /src
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends build-essential libcurl4-openssl-dev libcurl3t64-gnutls >/dev/null 2>&1
dpkg-query -W -f "package \${Package} \${Version}\n" libcurl4t64 libcurl3t64-gnutls libcurl4-openssl-dev libpsl5t64 gcc || true
echo "lo addresses: $(cat /proc/net/if_inet6 2>/dev/null | wc -l) IPv6, disable_ipv6=$(cat /proc/sys/net/ipv6/conf/lo/disable_ipv6 2>/dev/null || echo none)"
# With the packages in, the system resolver loses its DNS server, so that a
# name it still resolves comes from /etc/hosts alone, and X-resolve can show
# libcurl answering *.localhost itself.
echo "nameserver 127.0.0.9" > /etc/resolv.conf
echo "resolv.conf: $(cat /etc/resolv.conf)"
echo "hosts: $(grep -v "^#" /etc/hosts | tr -s " \t" " " | tr "\n" ";")"
arch=$(uname -m)-linux-gnu
export NODE=$GUIX_NODE CC=gcc
[ -n "$CASES" ] || unset CASES
NODE=/src/build/verify/m3s2/node20/node CURL_LIB=/src/build/e1/ci/curl-floor/lib/libcurl.so.4 \
  CURL_INCLUDE=/src/build/e1/ci/curl-floor/include sh .plans/research/m7/cookies/run.sh floor-7.85.0
CURL_LIB=/usr/lib/$arch/libcurl.so.4 sh .plans/research/m7/cookies/run.sh ubuntu-openssl-8.5.0
CURL_LIB=/usr/lib/$arch/libcurl-gnutls.so.4 sh .plans/research/m7/cookies/run.sh ubuntu-gnutls-8.5.0
CURL_LIB=$CURRENT/lib/libcurl.so.4 CURL_INCLUDE=$CURRENT/include sh .plans/research/m7/cookies/run.sh current-8.23.0'
