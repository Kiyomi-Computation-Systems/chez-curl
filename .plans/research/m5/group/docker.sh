#!/bin/sh
# M5 slice 4's group measurement (2026-10-28) in Docker ubuntu:24.04. Run on the
# host, from the repository's root:
#   sh .plans/research/m5/group/docker.sh CURRENT RUNS
# CURRENT is the install directory of curl 8.23.0 that
# scripts/ci/build-curl.sh --current made; it also needs spike E1's floor
# curl in build/e1/ci/curl-floor and its threaded Chez in
# build/e1/ci/chez-threads. Node comes from the Guix store, mounted
# read-only, and the floor's Node 20.10.0 from build/verify/m3s2/node20.
# Runs run.sh on the floor (7.85.0, under Node 20.10.0, as the floor lane
# runs), Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, and 8.23.0; then
# 8.5.0 with OpenSSL under Ubuntu's Valgrind, as the memory lane runs. The
# container's own lanes run on the host (run.sh says how).
set -eu
[ "$#" -eq 2 ] || { echo "usage: docker.sh CURRENT RUNS" >&2; exit 2; }
[ -f .plans/research/m5/group/run.sh ] || { echo "docker.sh: run it from the repository's root" >&2; exit 2; }
current=$(cd "$1" && pwd)
for f in "$current/lib/libcurl.so.4" build/e1/ci/curl-floor/lib/libcurl.so.4 build/e1/ci/chez-threads/bin/scheme build/verify/m3s2/node20/node; do
  [ -f "$f" ] || { echo "docker.sh: no $f" >&2; exit 1; }
done
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
node=$(scripts/guix-env sh -c 'command -v node' < /dev/null)
case $node in /gnu/store/*) ;; *) echo "docker.sh: node is not in the store: '$node'" >&2; exit 1 ;; esac
root=$PWD
exec docker run --rm -v "$root:/src" -v "$root:$root" -v /gnu/store:/gnu/store:ro \
  -e GUIX_NODE="$node" -e CURRENT="$current" -e RUNS="$2" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
cd /src
pkgs=$(grep -v -e "^#" -e "^\$" packaging/debian-prereqs.txt | tr "\n" " ")
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends $pkgs >/dev/null 2>&1
dpkg-query -W -f "package \${Package} \${Version}\n" libcurl4t64 libcurl3t64-gnutls valgrind
arch=$(uname -m)-linux-gnu
export NODE=$GUIX_NODE CHEZ=/src/build/e1/ci/chez-threads/bin/scheme
NODE=/src/build/verify/m3s2/node20/node CURL_LIB=/src/build/e1/ci/curl-floor/lib/libcurl.so.4 \
  sh .plans/research/m5/group/run.sh floor-7.85.0 "$RUNS"
CURL_LIB=/usr/lib/$arch/libcurl.so.4 sh .plans/research/m5/group/run.sh ubuntu-openssl-8.5.0 "$RUNS"
CURL_LIB=/usr/lib/$arch/libcurl-gnutls.so.4 sh .plans/research/m5/group/run.sh ubuntu-gnutls-8.5.0 "$RUNS"
CURL_LIB=$CURRENT/lib/libcurl.so.4 sh .plans/research/m5/group/run.sh current-8.23.0 "$RUNS"
VALGRIND=valgrind CURL_LIB=/usr/lib/$arch/libcurl.so.4 sh .plans/research/m5/group/run.sh ubuntu-openssl-8.5.0-valgrind "$RUNS"'
