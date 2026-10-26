#!/bin/sh
# M4 slice 1's measurements in Docker ubuntu:24.04. Run on the host, from the
# repository's root:
#
#   sh .plans/research/m4/slice1/docker.sh CURRENT [SCRIPT]
#
# SCRIPT is run.sh, the default, or options.sh.
#
# CURRENT is the install directory of curl 8.23.0 that
# scripts/ci/build-curl.sh --current made. It also needs spike E1's floor
# build in build/e1/ci/curl-floor. It runs run.sh on four lanes, with Node
# from the Guix store:
#   floor           curl 7.85.0, built from source with OpenSSL
#   ubuntu-openssl  Ubuntu's libcurl4t64 8.5.0
#   ubuntu-gnutls   Ubuntu's libcurl3t64-gnutls 8.5.0
#   current         curl 8.23.0, built from source with OpenSSL
# The container's own lane runs on the host:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m4/slice1/run.sh guix-8.20.0'
set -eu
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo "usage: docker.sh CURRENT [SCRIPT]" >&2; exit 2; }
script=${2:-run.sh}
case $script in run.sh|options.sh) ;; *) echo "docker.sh: SCRIPT is run.sh or options.sh" >&2; exit 2 ;; esac
[ -f .plans/research/m4/slice1/run.sh ] || { echo "docker.sh: run it from the repository's root" >&2; exit 2; }
current=$(cd "$1" && pwd)
[ -f "$current/lib/libcurl.so.4" ] || { echo "docker.sh: no lib/libcurl.so.4 under $current" >&2; exit 1; }
[ -f build/e1/ci/curl-floor/lib/libcurl.so.4 ] || { echo "docker.sh: spike E1's floor build is missing" >&2; exit 1; }
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
node=$(scripts/guix-env sh -c 'command -v node')
case $node in /gnu/store/*) ;; *) echo "docker.sh: node is not in the store: '$node'" >&2; exit 1 ;; esac
root=$PWD
exec docker run --rm -v "$root:/src" -v "$root:$root" -v /gnu/store:/gnu/store:ro \
  -e GUIX_NODE="$node" -e CURRENT="$current" -e SCRIPT="$script" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
cd /src
pkgs=$(grep -v -e "^#" -e "^$" packaging/debian-prereqs.txt | tr "\n" " ")
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends $pkgs >/dev/null 2>&1
dpkg-query -W -f "package \${Package} \${Version}\n" libcurl4t64 libcurl3t64-gnutls libssl3t64 libc6 openssl
arch=$(uname -m)-linux-gnu
export NODE=$GUIX_NODE CC=gcc
CURL_LIB=/src/build/e1/ci/curl-floor/lib/libcurl.so.4 CURL_INCLUDE=/src/build/e1/ci/curl-floor/include \
  sh .plans/research/m4/slice1/$SCRIPT floor
CURL_LIB=/usr/lib/$arch/libcurl.so.4 sh .plans/research/m4/slice1/$SCRIPT ubuntu-openssl
CURL_LIB=/usr/lib/$arch/libcurl-gnutls.so.4 sh .plans/research/m4/slice1/$SCRIPT ubuntu-gnutls
CURL_LIB=$CURRENT/lib/libcurl.so.4 CURL_INCLUDE=$CURRENT/include sh .plans/research/m4/slice1/$SCRIPT current'
