#!/bin/sh
# M4 slice 2's measurements in Docker ubuntu:24.04, with Ubuntu's libcurl
# 8.5.0 and Valgrind 3.22, CI's memory gate. Run on the host, from the
# repository's root, once make deps has run:
#
#   sh .plans/research/m4/slice2/docker.sh [SET...]
#
# It needs spike E1's threaded Chez in build/e1/ci/chez-threads, and runs
# run.sh as the lane ubuntu-8.5.0, with Node from the Guix store. The
# container's own lane runs on the host:
#   scripts/guix-env sh .plans/research/m4/slice2/run.sh guix-8.20.0
set -eu
[ -f .plans/research/m4/slice2/run.sh ] || { echo "docker.sh: run it from the repository's root" >&2; exit 2; }
[ -x build/e1/ci/chez-threads/bin/scheme ] || { echo "docker.sh: spike E1's Chez is missing" >&2; exit 1; }
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
node=$(scripts/guix-env sh -c 'command -v node')
case $node in /gnu/store/*) ;; *) echo "docker.sh: node is not in the store: '$node'" >&2; exit 1 ;; esac
root=$PWD
exec docker run --rm -v "$root:/src" -v "$root:$root" -v /gnu/store:/gnu/store:ro \
  -e GUIX_NODE="$node" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
cd /src
pkgs=$(grep -v -e "^#" -e "^$" packaging/debian-prereqs.txt | tr "\n" " ")
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends $pkgs >/dev/null 2>&1
dpkg-query -W -f "package \${Package} \${Version}\n" libcurl4t64 libc6 valgrind
export NODE=$GUIX_NODE CHEZ=/src/build/e1/ci/chez-threads/bin/scheme CC=gcc
sh .plans/research/m4/slice2/run.sh ubuntu-8.5.0 "$@"' sh "$@"
