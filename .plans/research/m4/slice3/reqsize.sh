#!/bin/sh
# Whether upstream curl VERSION reports a request size of 0 for a transfer
# that sent its request, as the Mac's libcurl 8.7.1 did in test-request on
# M4 slice 3's PR, or the request's length, as 7.85.0, 8.5.0, 8.6.0, 8.20.0
# and 8.23.0 do (ADR-0022, amended 2026-10-27). Run on the host, from the
# repository's root:
#
#   sh .plans/research/m4/slice3/reqsize.sh VERSION
#
# In Docker ubuntu:24.04, it fetches curl-VERSION.tar.xz from curl.se, prints
# its sha256, builds its library and headers alone with OpenSSL and the
# current lane's library choices (scripts/ci/build-curl.sh), and runs M4 slice 1's probe,
# .plans/research/m4/slice1/run.sh, on it, with Node from the Guix store.
# The build lives in the container alone.
set -eu
[ "$#" -eq 1 ] || { echo "usage: reqsize.sh VERSION" >&2; exit 2; }
case $1 in [0-9]*.[0-9]*.[0-9]*) ;; *) echo "reqsize.sh: VERSION is like 8.7.1" >&2; exit 2 ;; esac
[ -f .plans/research/m4/slice1/run.sh ] || { echo "reqsize.sh: run it from the repository's root" >&2; exit 2; }
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
node=$(scripts/guix-env sh -c 'command -v node' < /dev/null)
case $node in /gnu/store/*) ;; *) echo "reqsize.sh: node is not in the store: '$node'" >&2; exit 1 ;; esac
root=$PWD
exec docker run --rm -v "$root:/src" -v /gnu/store:/gnu/store:ro -e GUIX_NODE="$node" -e V="$1" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
cd /src
pkgs=$(grep -v -e "^#" -e "^$" packaging/debian-prereqs.txt | tr "\n" " ")
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends $pkgs curl xz-utils make libssl-dev zlib1g-dev libnghttp2-dev pkg-config >/dev/null 2>&1
mkdir -p /build && cd /build
curl -fsSL --retry 3 -o curl-$V.tar.xz https://curl.se/download/curl-$V.tar.xz
echo "sha256 $(sha256sum curl-$V.tar.xz | cut -d" " -f1) curl-$V.tar.xz"
tar xJf curl-$V.tar.xz
cd curl-$V
./configure --prefix=/opt/curl-$V --disable-static --with-openssl --with-zlib --with-nghttp2 \
  --enable-ipv6 --without-brotli --without-zstd --without-libidn2 --without-libpsl \
  --without-libgsasl --without-gssapi --disable-ldap --disable-ldaps --without-libssh2 \
  --without-libssh > /build/configure.log 2>&1 || { tail -20 /build/configure.log; exit 1; }
# The library and its headers alone: the man pages of 8.7.0 fail to build here.
make -j"$(nproc)" -C lib > /build/make.log 2>&1 || { tail -20 /build/make.log; exit 1; }
make -C lib install > /build/install.log 2>&1
make -C include install >> /build/install.log 2>&1
cd /src
export NODE=$GUIX_NODE CC=gcc
CURL_LIB=/opt/curl-$V/lib/libcurl.so.4 CURL_INCLUDE=/opt/curl-$V/include \
  sh .plans/research/m4/slice1/run.sh upstream-$V'
