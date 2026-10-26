#!/bin/sh
# The M4 plan review's redirect probe (2026-10-26). Run on the host, from the
# repository root:
#   sh .plans/research/m4/redirect/docker.sh
# Runs run.sh in Docker ubuntu:24.04 on the floor (7.85.0), Ubuntu's 8.5.0
# (OpenSSL) and curl 8.23.0, with Node from the Guix store.
set -eu
node=$(scripts/guix-env sh -c 'command -v node')
case $node in /gnu/store/*) ;; *) echo "node is not in the store: '$node'" >&2; exit 1 ;; esac
root=$PWD
exec docker run --rm --name m4review-redirect -v "$root:/src" -v "$root:$root" -v /gnu/store:/gnu/store:ro \
  -e GUIX_NODE="$node" -e CURRENT="$root/build/verify/c823/lane1/curl-current" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
cd /src
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends build-essential libcurl4-openssl-dev ca-certificates >/dev/null 2>&1
dpkg-query -W -f "package \${Package} \${Version}\n" libcurl4t64
arch=$(uname -m)-linux-gnu
export NODE=$GUIX_NODE CC=gcc
CURL_LIB=/src/build/e1/ci/curl-floor/lib/libcurl.so.4 CURL_INCLUDE=/src/build/e1/ci/curl-floor/include \
  sh .plans/research/m4/redirect/run.sh floor-7.85.0
CURL_LIB=/usr/lib/$arch/libcurl.so.4 sh .plans/research/m4/redirect/run.sh ubuntu-8.5.0
CURL_LIB=$CURRENT/lib/libcurl.so.4 CURL_INCLUDE=$CURRENT/include sh .plans/research/m4/redirect/run.sh current-8.23.0'
