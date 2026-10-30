#!/bin/sh
# M6 slice 1's measurements (2026-10-30) in Docker ubuntu:24.04, on the four
# lanes the container cannot run. Run on the host, from the repository's
# root, after build.sh:
#   sh .plans/research/m6/slice1/docker.sh CURRENT LANES PROGRAM [ARG...]
# CURRENT is the install directory of curl 8.23.0 that
# scripts/ci/build-curl.sh --current made (build/verify/c823/lane1/curl-current);
# it also needs spike E1's floor curl in build/e1/ci/curl-floor, its threaded
# Chez in build/e1/ci/chez-threads, and the floor's Node 20.10.0 in
# build/verify/m3s2/node20. Other Node comes from the Guix store, mounted
# read-only; the repository is mounted read-only too. LANES is all, the four
# native lanes, or a comma list of all, floor-7.85.0, ubuntu-openssl-8.5.0,
# ubuntu-gnutls-8.5.0, current-8.23.0 and ubuntu-openssl-8.5.0-valgrind, the
# last under Ubuntu's Valgrind with the gate's options, as the memory lane
# runs; or vanilla-8.20.0, a diagnostic lane, upstream 8.20.0 built with
# OpenSSL in build/verify/current/curl-8.20.0-install, beside Guix's. It installs packaging/debian-prereqs.txt, then runs run.sh PROGRAM
# ARG... on each lane, in that order; PROGRAM wake runs wake.sh instead.
set -eu
[ "$#" -ge 3 ] || { echo "usage: docker.sh CURRENT LANES PROGRAM [ARG...]" >&2; exit 2; }
[ -f .plans/research/m6/slice1/run.sh ] || { echo "docker.sh: run it from the repository's root" >&2; exit 2; }
current=$(cd "$1" && pwd)
lanes=$2
shift 2
lanes=$(echo "$lanes" | sed 's/\ball\b/floor-7.85.0,ubuntu-openssl-8.5.0,ubuntu-gnutls-8.5.0,current-8.23.0/')
for f in "$current/lib/libcurl.so.4" build/e1/ci/curl-floor/lib/libcurl.so.4 build/e1/ci/chez-threads/bin/scheme \
         build/verify/m3s2/node20/node build/m6s1/patch.sha256; do
  [ -f "$f" ] || { echo "docker.sh: no $f" >&2; exit 1; }
done
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
node=$(scripts/guix-env sh -c 'command -v node' < /dev/null)
case $node in /gnu/store/*) ;; *) echo "docker.sh: node is not in the store: '$node'" >&2; exit 1 ;; esac
root=$PWD
exec docker run --rm -v "$root:/src:ro" -v "$root:$root:ro" -v /gnu/store:/gnu/store:ro \
  -e GUIX_NODE="$node" -e CURRENT="$current" -e LANES="$lanes" -e CHILD_PROXY="${CHILD_PROXY:-}" \
  ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
cd /src
pkgs=$(grep -v -e "^#" -e "^\$" packaging/debian-prereqs.txt | tr "\n" " ")
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends $pkgs >/dev/null 2>&1
dpkg-query -W -f "package \${Package} \${Version}\n" libcurl4t64 libcurl3t64-gnutls valgrind openssl
arch=$(uname -m)-linux-gnu
export NODE=$GUIX_NODE CHEZ=/src/build/e1/ci/chez-threads/bin/scheme
export CC=gcc
runner=.plans/research/m6/slice1/run.sh
[ "$1" = wake ] && { runner=.plans/research/m6/slice1/wake.sh; shift; }
for lane in $(echo "$LANES" | tr "," " "); do
  case $lane in
    floor-7.85.0)
      NODE=/src/build/verify/m3s2/node20/node CURL_LIB=/src/build/e1/ci/curl-floor/lib/libcurl.so.4 \
        sh $runner "$lane" "$@" ;;
    ubuntu-openssl-8.5.0) CURL_LIB=/usr/lib/$arch/libcurl.so.4 sh $runner "$lane" "$@" ;;
    ubuntu-gnutls-8.5.0) CURL_LIB=/usr/lib/$arch/libcurl-gnutls.so.4 sh $runner "$lane" "$@" ;;
    current-8.23.0) CURL_LIB=$CURRENT/lib/libcurl.so.4 sh $runner "$lane" "$@" ;;
    vanilla-8.20.0)
      CURL_LIB=/src/build/verify/current/curl-8.20.0-install/lib/libcurl.so.4 \
        CURL_INCLUDE=/src/build/verify/current/curl-8.20.0-install/include sh $runner "$lane" "$@" ;;
    ubuntu-openssl-8.5.0-valgrind)
      VALGRIND=valgrind CURL_LIB=/usr/lib/$arch/libcurl.so.4 sh $runner "$lane" "$@" ;;
    *) echo "docker.sh: no lane $lane"; exit 2 ;;
  esac
done' docker "$@"
