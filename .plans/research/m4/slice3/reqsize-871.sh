#!/bin/sh
# Whether upstream curl 8.7.1, Apple's version, reports a request size of 0
# for a failed transfer that sent its request, as the Mac's libcurl 8.7.1 did
# in test-request on M4 slice 3's PR, or the request's length, as 7.85.0,
# 8.5.0, 8.20.0 and 8.23.0 do (ADR-0022, amended). Run on the host, from the
# repository's root:
#
#   sh .plans/research/m4/slice3/reqsize-871.sh
#
# In Docker ubuntu:24.04, it fetches curl-8.7.1.tar.xz from curl.se, prints
# its sha256, builds it with OpenSSL and the current lane's library choices
# (scripts/ci/build-curl.sh), and runs M4 slice 1's probe,
# .plans/research/m4/slice1/run.sh, on it, with Node from the Guix store.
# The build lives in the container alone.
set -eu
[ -f .plans/research/m4/slice1/run.sh ] || { echo "reqsize-871.sh: run it from the repository's root" >&2; exit 2; }
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
node=$(scripts/guix-env sh -c 'command -v node' < /dev/null)
case $node in /gnu/store/*) ;; *) echo "reqsize-871.sh: node is not in the store: '$node'" >&2; exit 1 ;; esac
root=$PWD
exec docker run --rm -v "$root:/src" -v /gnu/store:/gnu/store:ro -e GUIX_NODE="$node" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
cd /src
pkgs=$(grep -v -e "^#" -e "^$" packaging/debian-prereqs.txt | tr "\n" " ")
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends $pkgs curl xz-utils make libssl-dev zlib1g-dev libnghttp2-dev pkg-config >/dev/null 2>&1
mkdir -p /build && cd /build
curl -fsSL --retry 3 -o curl-8.7.1.tar.xz https://curl.se/download/curl-8.7.1.tar.xz
echo "sha256 $(sha256sum curl-8.7.1.tar.xz | cut -d" " -f1) curl-8.7.1.tar.xz"
tar xJf curl-8.7.1.tar.xz
cd curl-8.7.1
./configure --prefix=/opt/curl-8.7.1 --disable-static --with-openssl --with-zlib --with-nghttp2 \
  --enable-ipv6 --without-brotli --without-zstd --without-libidn2 --without-libpsl \
  --without-libgsasl --without-gssapi --disable-ldap --disable-ldaps --without-libssh2 \
  --without-libssh > /build/configure.log 2>&1 || { tail -20 /build/configure.log; exit 1; }
make -j"$(nproc)" > /build/make.log 2>&1 || { tail -20 /build/make.log; exit 1; }
make install > /build/install.log 2>&1
echo "curl-config: $(/opt/curl-8.7.1/bin/curl-config --version), features: $(/opt/curl-8.7.1/bin/curl-config --features | tr "\n" " ")"
cd /src
export NODE=$GUIX_NODE CC=gcc
CURL_LIB=/opt/curl-8.7.1/lib/libcurl.so.4 CURL_INCLUDE=/opt/curl-8.7.1/include \
  sh .plans/research/m4/slice1/run.sh upstream-8.7.1'
