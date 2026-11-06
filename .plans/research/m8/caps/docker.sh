#!/bin/sh
# M8's header-caps probe (2026-11-06) in Docker ubuntu:24.04: lanes F, O, G
# and C. Run on the host, from the repository's root:
#   sh .plans/research/m8/caps/docker.sh > .plans/research/m8/caps/results/docker-N.log 2>&1
# It needs curl 8.23.0's install in build/verify/c823/lane1/curl-current
# (scripts/ci/build-curl.sh --current), spike E1's floor build in
# build/e1/ci/curl-floor and the floor's Node 20.10.0 in
# build/verify/m3s2/node20. Other Node comes from the Guix store, mounted
# read-only; the repository is mounted read-only too.
#
# The apt packages are fetched once, by a container that does nothing else,
# into build/m8/caps/apt (git-ignored; handed back to the caller's uid), as
# M7's proxy probe did. Every case then runs in one container with
# --network none, loopback alone, which it prints (/sys/class/net), and
# --cpuset-cpus 12-17 (CPUS), the probe's share of the host. It installs the
# packages from that cache, and runs run.sh on the floor (7.85.0, under Node
# 20.10.0, as the floor lane runs), Ubuntu's 8.5.0 with OpenSSL and with
# GnuTLS (against libcurl4-openssl-dev's headers), and 8.23.0, each against
# its own headers. CASES and PROBE_MODES, when set, are handed to run.sh.
# The container's own lane runs on the host:
#   taskset -c 12-17 scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m8/caps/run.sh guix-8.20.0' < /dev/null
set -eu
[ "$#" -eq 0 ] || { echo "usage: docker.sh" >&2; exit 2; }
[ -f .plans/research/m8/caps/run.sh ] || { echo "docker.sh: run it from the repository's root" >&2; exit 2; }
cpus=${CPUS:-12-17}
current=build/verify/c823/lane1/curl-current
for f in "$current/lib/libcurl.so.4" "$current/include/curl/curl.h" build/e1/ci/curl-floor/lib/libcurl.so.4 \
         build/e1/ci/curl-floor/include/curl/curl.h build/verify/m3s2/node20/node; do
  [ -f "$f" ] || { echo "docker.sh: no $f" >&2; exit 1; }
done
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
node=$(scripts/guix-env sh -c 'command -v node' < /dev/null)
case $node in /gnu/store/*) ;; *) echo "docker.sh: node is not in the store: '$node'" >&2; exit 1 ;; esac
root=$PWD
cache=$root/build/m8/caps/apt
pkgs="build-essential libcurl4-openssl-dev libcurl3t64-gnutls ca-certificates openssl"
if [ ! -f "$cache/fetched" ]; then
  mkdir -p "$cache/archives/partial" "$cache/lists/partial"
  docker run --rm --cpuset-cpus "$cpus" -v "$cache/archives:/var/cache/apt/archives" -v "$cache/lists:/var/lib/apt/lists" \
    -e HOSTID="$(id -u):$(id -g)" -e PKGS="$pkgs" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
rm -f /etc/apt/apt.conf.d/docker-clean
apt-get update -qq >/dev/null
apt-get install -y -qq --download-only --no-install-recommends $PKGS >/dev/null
chown -R "$HOSTID" /var/cache/apt/archives /var/lib/apt/lists'
  touch "$cache/fetched"
fi
echo "docker.sh start $(date -u +%Y-%m-%dT%H:%M:%SZ) cpuset=$cpus"
exec docker run --rm --network none --cpuset-cpus "$cpus" -v "$root:/src:ro" -v /gnu/store:/gnu/store:ro \
  -v "$cache:/aptcache:ro" -e GUIX_NODE="$node" -e CURRENT="/src/$current" -e CASES="${CASES:-}" \
  -e PROBE_MODES="${PROBE_MODES:-}" -e PKGS="$pkgs" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
echo "network interfaces: $(ls /sys/class/net | tr "\n" " ")"
rm -f /etc/apt/apt.conf.d/docker-clean
cp -R /aptcache/lists/. /var/lib/apt/lists/
cp /aptcache/archives/*.deb /var/cache/apt/archives/
apt-get install -y -qq --no-download --no-install-recommends $PKGS >/dev/null 2>&1
dpkg-query -W -f "package \${Package} \${Version}\n" libcurl4t64 libcurl3t64-gnutls libnghttp2-14 libssl3t64 libgnutls30t64 gcc || true
cd /src
arch=$(uname -m)-linux-gnu
export NODE=$GUIX_NODE CC=gcc
[ -n "$CASES" ] || unset CASES
[ -n "$PROBE_MODES" ] || unset PROBE_MODES
NODE=/src/build/verify/m3s2/node20/node CURL_LIB=/src/build/e1/ci/curl-floor/lib/libcurl.so.4 \
  CURL_INCLUDE=/src/build/e1/ci/curl-floor/include sh .plans/research/m8/caps/run.sh floor-7.85.0
CURL_LIB=/usr/lib/$arch/libcurl.so.4 sh .plans/research/m8/caps/run.sh ubuntu-openssl-8.5.0
CURL_LIB=/usr/lib/$arch/libcurl-gnutls.so.4 sh .plans/research/m8/caps/run.sh ubuntu-gnutls-8.5.0
CURL_LIB=$CURRENT/lib/libcurl.so.4 CURL_INCLUDE=$CURRENT/include sh .plans/research/m8/caps/run.sh current-8.23.0
echo "docker.sh end $(date -u +%Y-%m-%dT%H:%M:%SZ)"'
