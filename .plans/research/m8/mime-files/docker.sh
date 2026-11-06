#!/bin/sh
# M8's mime-files probe (2026-11-06) in Docker ubuntu:24.04, on lanes F, O,
# G and C. Run on the host, from the repository's root:
#   sh .plans/research/m8/mime-files/docker.sh > .plans/research/m8/mime-files/results/docker-N.log 2>&1
# It needs curl 8.23.0's install in build/verify/c823/lane1/curl-current
# (scripts/ci/build-curl.sh --current), spike E1's floor build in
# build/e1/ci/curl-floor and the floor's Node 20.10.0 in
# build/verify/m3s2/node20. Other Node comes from the Guix store, mounted
# read-only; the repository is mounted read-only too, at its own path.
#
# The apt packages are fetched once, by a container that does nothing else,
# into build/m8/mime-files/apt (git-ignored; handed back to the caller's
# uid), as research/m7/proxies/docker.sh does. Every case then runs in a
# container with --network none, loopback alone, which it prints. Every
# container this script starts is --rm and pinned to CPUs 6-11
# (--cpuset-cpus). The list holds valgrind, for the lifetime cases, and the
# headers and xz that nomime.sh's builds need, so both share one cache.
#
# Each lane's run.sh runs as the caller's uid and gid (setpriv), not as root,
# so that a file made unreadable (C-unreadable-*) is unreadable to libcurl:
# run.sh prints the uid. VALGRIND=valgrind on every lane. CASES and VG_CASES,
# when set, are handed to run.sh. REPEAT=N (default 1) runs the four lanes N
# times over, each pass's lanes labelled LANE-runK (summarize.mjs reads each
# as a run of LANE): the racing cells' extra runs,
#   CASES="..." VG_CASES=none REPEAT=20 sh .plans/research/m8/mime-files/docker.sh > .plans/research/m8/mime-files/results/races-docker.log 2>&1
#
# The container's own lane runs on the host:
#   taskset -c 6-11 scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL VALGRIND=valgrind sh .plans/research/m8/mime-files/run.sh guix-8.20.0' < /dev/null
set -eu
[ "$#" -eq 0 ] || { echo "usage: docker.sh" >&2; exit 2; }
[ -f .plans/research/m8/mime-files/run.sh ] || { echo "docker.sh: run it from the repository's root" >&2; exit 2; }
root=$PWD
current=$root/build/verify/c823/lane1/curl-current
for f in "$current/lib/libcurl.so.4" "$current/include/curl/curl.h" build/e1/ci/curl-floor/lib/libcurl.so.4 \
         build/e1/ci/curl-floor/include/curl/curl.h build/verify/m3s2/node20/node; do
  [ -f "$f" ] || { echo "docker.sh: no $f" >&2; exit 1; }
done
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
node=$(scripts/guix-env sh -c 'command -v node' < /dev/null)
case $node in /gnu/store/*) ;; *) echo "docker.sh: node is not in the store: '$node'" >&2; exit 1 ;; esac
cache=$root/build/m8/mime-files/apt
pkgs="build-essential libcurl4-openssl-dev libcurl3t64-gnutls ca-certificates openssl valgrind libssl-dev zlib1g-dev libnghttp2-dev xz-utils"
if [ ! -f "$cache/fetched" ]; then
  mkdir -p "$cache/archives/partial" "$cache/lists/partial"
  docker run --rm --cpuset-cpus 6-11 -v "$cache/archives:/var/cache/apt/archives" -v "$cache/lists:/var/lib/apt/lists" \
    -e HOSTID="$(id -u):$(id -g)" -e PKGS="$pkgs" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
rm -f /etc/apt/apt.conf.d/docker-clean
apt-get update -qq >/dev/null
apt-get install -y -qq --download-only --no-install-recommends $PKGS >/dev/null
chown -R "$HOSTID" /var/cache/apt/archives /var/lib/apt/lists'
  touch "$cache/fetched"
fi
exec docker run --rm --network none --cpuset-cpus 6-11 -v "$root:$root:ro" -v /gnu/store:/gnu/store:ro \
  -v "$cache:/aptcache:ro" -e GUIX_NODE="$node" -e CURRENT="$current" -e ROOT="$root" -e CASES="${CASES:-}" \
  -e VG_CASES="${VG_CASES:-}" -e REPEAT="${REPEAT:-1}" -e PKGS="$pkgs" -e HOSTUID="$(id -u)" -e HOSTGID="$(id -g)" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
echo "network interfaces: $(ls /sys/class/net | tr "\n" " ")"
rm -f /etc/apt/apt.conf.d/docker-clean
cp -R /aptcache/lists/. /var/lib/apt/lists/
cp /aptcache/archives/*.deb /var/cache/apt/archives/
apt-get install -y -qq --no-download --no-install-recommends $PKGS >/dev/null 2>&1
dpkg-query -W -f "package \${Package} \${Version}\n" libcurl4t64 libcurl3t64-gnutls libssl3t64 libgnutls30t64 libnghttp2-14 valgrind gcc || true
cd "$ROOT"
arch=$(uname -m)-linux-gnu
[ -n "$CASES" ] || unset CASES
[ -n "$VG_CASES" ] || unset VG_CASES
as_user() { setpriv --reuid="$HOSTUID" --regid="$HOSTGID" --clear-groups env HOME=/tmp TMPDIR=/tmp CC=gcc VALGRIND=valgrind "$@"; }
k=1
while [ "$k" -le "$REPEAT" ]; do
  sfx=
  [ "$REPEAT" -gt 1 ] && sfx=-run$k
  as_user NODE=$ROOT/build/verify/m3s2/node20/node CURL_LIB=$ROOT/build/e1/ci/curl-floor/lib/libcurl.so.4 \
    CURL_INCLUDE=$ROOT/build/e1/ci/curl-floor/include sh .plans/research/m8/mime-files/run.sh floor-7.85.0$sfx
  as_user NODE=$GUIX_NODE CURL_LIB=/usr/lib/$arch/libcurl.so.4 sh .plans/research/m8/mime-files/run.sh ubuntu-openssl-8.5.0$sfx
  as_user NODE=$GUIX_NODE CURL_LIB=/usr/lib/$arch/libcurl-gnutls.so.4 sh .plans/research/m8/mime-files/run.sh ubuntu-gnutls-8.5.0$sfx
  as_user NODE=$GUIX_NODE CURL_LIB=$CURRENT/lib/libcurl.so.4 CURL_INCLUDE=$CURRENT/include sh .plans/research/m8/mime-files/run.sh current-8.23.0$sfx
  k=$((k+1))
done'
