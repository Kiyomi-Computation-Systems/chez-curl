#!/bin/sh
# M7's proxy probe (2026-11-02) in Docker ubuntu:24.04. Run on the host, from
# the repository's root:
#   sh .plans/research/m7/proxies/docker.sh CURRENT [main|sysstore]
# CURRENT is the install directory of curl 8.23.0 that
# scripts/ci/build-curl.sh --current made (build/verify/c823/lane1/curl-current);
# it also needs spike E1's floor build in build/e1/ci/curl-floor and the
# floor's Node 20.10.0 in build/verify/m3s2/node20. Other Node comes from the
# Guix store, mounted read-only; the repository is mounted read-only too.
#
# The apt packages are fetched once, by a container that does nothing else,
# into build/m7/proxies/apt (git-ignored; handed back to the caller's uid).
# Every case then runs in a container with --network none: loopback alone,
# which it prints (/sys/class/net). It installs the packages from that cache,
# and runs run.sh on the floor (7.85.0, under Node 20.10.0, as the floor lane
# runs), Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, and 8.23.0, each against
# its own headers.
#
# main, the default: every case. sysstore: run.sh with SYSSTORE=1, which
# adds each run's CA to the container's system store, and only the cases
# that read a default CA (I4-a-ca-*, I4-c-ca-*, I4-o-*). CASES, when set,
# replaces either list.
# The container's own lane runs on the host:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m7/proxies/run.sh guix-8.20.0' < /dev/null
set -eu
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo "usage: docker.sh CURRENT [main|sysstore]" >&2; exit 2; }
pass=${2:-main}
case $pass in
  main) sys= cases=${CASES:-} ;;
  sysstore) sys=1 cases=${CASES:-"I4-a-ca-* I4-c-ca-* I4-o-*"} ;;
  *) echo "docker.sh: no pass $pass" >&2; exit 2 ;;
esac
[ -f .plans/research/m7/proxies/run.sh ] || { echo "docker.sh: run it from the repository's root" >&2; exit 2; }
current=$(cd "$1" && pwd)
for f in "$current/lib/libcurl.so.4" "$current/include/curl/curl.h" build/e1/ci/curl-floor/lib/libcurl.so.4 \
         build/e1/ci/curl-floor/include/curl/curl.h build/verify/m3s2/node20/node; do
  [ -f "$f" ] || { echo "docker.sh: no $f" >&2; exit 1; }
done
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
node=$(scripts/guix-env sh -c 'command -v node' < /dev/null)
case $node in /gnu/store/*) ;; *) echo "docker.sh: node is not in the store: '$node'" >&2; exit 1 ;; esac
root=$PWD
cache=$root/build/m7/proxies/apt
pkgs="build-essential libcurl4-openssl-dev libcurl3t64-gnutls ca-certificates openssl"
if [ ! -f "$cache/fetched" ]; then
  mkdir -p "$cache/archives/partial" "$cache/lists/partial"
  docker run --rm -v "$cache/archives:/var/cache/apt/archives" -v "$cache/lists:/var/lib/apt/lists" \
    -e HOSTID="$(id -u):$(id -g)" -e PKGS="$pkgs" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
rm -f /etc/apt/apt.conf.d/docker-clean
apt-get update -qq >/dev/null
apt-get install -y -qq --download-only --no-install-recommends $PKGS >/dev/null
chown -R "$HOSTID" /var/cache/apt/archives /var/lib/apt/lists'
  touch "$cache/fetched"
fi
exec docker run --rm --network none -v "$root:/src:ro" -v "$root:$root:ro" -v /gnu/store:/gnu/store:ro \
  -v "$cache:/aptcache:ro" -e GUIX_NODE="$node" -e CURRENT="$current" -e CASES="$cases" -e SYSSTORE="$sys" \
  -e PKGS="$pkgs" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
echo "network interfaces: $(ls /sys/class/net | tr "\n" " ")"
rm -f /etc/apt/apt.conf.d/docker-clean
cp -R /aptcache/lists/. /var/lib/apt/lists/
cp /aptcache/archives/*.deb /var/cache/apt/archives/
apt-get install -y -qq --no-download --no-install-recommends $PKGS >/dev/null 2>&1
dpkg-query -W -f "package \${Package} \${Version}\n" libcurl4t64 libcurl3t64-gnutls libssl3t64 libgnutls30t64 openssl ca-certificates gcc || true
cd /src
arch=$(uname -m)-linux-gnu
export NODE=$GUIX_NODE CC=gcc
NODE=/src/build/verify/m3s2/node20/node CURL_LIB=/src/build/e1/ci/curl-floor/lib/libcurl.so.4 \
  CURL_INCLUDE=/src/build/e1/ci/curl-floor/include sh .plans/research/m7/proxies/run.sh floor-7.85.0
CURL_LIB=/usr/lib/$arch/libcurl.so.4 sh .plans/research/m7/proxies/run.sh ubuntu-openssl-8.5.0
CURL_LIB=/usr/lib/$arch/libcurl-gnutls.so.4 sh .plans/research/m7/proxies/run.sh ubuntu-gnutls-8.5.0
CURL_LIB=$CURRENT/lib/libcurl.so.4 CURL_INCLUDE=$CURRENT/include sh .plans/research/m7/proxies/run.sh current-8.23.0'
