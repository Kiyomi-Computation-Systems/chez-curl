#!/bin/sh
# verify/cap-docker.sh SCRIPT: runs verify/cap.sh or verify/cap-url.sh on the
# Docker lanes, in one --rm ubuntu:24.04 container that installs gcc and
# libcurl's headers from Ubuntu's archive (it needs the network). From the
# repository's root, on the host:
#   sh .plans/research/m7/slice4/verify/cap-docker.sh cap.sh > .plans/research/m7/slice4/verify/results/cap-c-docker.log 2>&1
#   sh .plans/research/m7/slice4/verify/cap-docker.sh cap-url.sh > .plans/research/m7/slice4/verify/results/cap-url-docker.log 2>&1
# cap.sh ran on all four lanes; cap-url.sh on 7.85.0, 8.5.0 with OpenSSL and
# 8.23.0 (LANES, default all four).
set -eu
script=$1
root=$PWD
cur=$(cd build/verify/c823/lane1/curl-current && pwd)
exec docker run --rm -v "$root:$root:ro" -w "$root" -e CUR="$cur" -e SCRIPT="$script" \
  -e LANES="${LANES:-floor-7.85.0 ubuntu-openssl-8.5.0 ubuntu-gnutls-8.5.0 current-8.23.0}" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null && apt-get install -y -qq --no-install-recommends gcc libc6-dev libcurl4-openssl-dev libcurl3t64-gnutls >/dev/null 2>&1
dpkg-query -W -f "package \${Package} \${Version}\n" libcurl4t64 libcurl3t64-gnutls
export TMPDIR=/tmp NODE=build/verify/m3s2/node20/node
arch=$(uname -m)-linux-gnu
v=.plans/research/m7/slice4/verify
for lane in $LANES; do
  case $lane in
    floor-7.85.0) CURL_LIB=build/e1/ci/curl-floor/lib/libcurl.so.4 CURL_INC=build/e1/ci/curl-floor/include sh $v/$SCRIPT $lane ;;
    ubuntu-openssl-8.5.0) CURL_LIB=/usr/lib/$arch/libcurl.so.4 sh $v/$SCRIPT $lane ;;
    ubuntu-gnutls-8.5.0) CURL_LIB=/usr/lib/$arch/libcurl-gnutls.so.4 sh $v/$SCRIPT $lane ;;
    current-8.23.0) CURL_LIB=$CUR/lib/libcurl.so.4 CURL_INC=$CUR/include sh $v/$SCRIPT $lane ;;
  esac
done'
