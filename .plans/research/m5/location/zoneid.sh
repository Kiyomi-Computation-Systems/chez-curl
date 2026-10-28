#!/bin/sh
# The review's zone ID question (2026-10-28): zoneid.sps on one libcurl, or in
# Docker on four. Run from the repository's root. In the container:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m5/location/zoneid.sh guix-8.20.0' < /dev/null
# In Docker ubuntu:24.04, on 7.85.0, Ubuntu's 8.5.0 with OpenSSL and with
# GnuTLS, and 8.23.0, CURRENT as docker.sh takes it:
#   sh .plans/research/m5/location/zoneid.sh docker CURRENT
# On the Mac: CHEZ=chez sh .plans/research/m5/location/zoneid.sh mac
set -u
d=.plans/research/m5/location
[ -f $d/zoneid.sps ] || { echo "zoneid.sh: run it from the repository's root" >&2; exit 2; }
if [ "${1:-}" = docker ]; then
  current=$(cd "$2" && pwd)
  root=$PWD
  exec docker run --rm -v "$root:/src" -v "$root:$root" -e CURRENT="$current" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
cd /src
pkgs=$(grep -v -e "^#" -e "^\$" packaging/debian-prereqs.txt | tr "\n" " ")
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends $pkgs >/dev/null 2>&1
arch=$(uname -m)-linux-gnu
export CHEZ=/src/build/e1/ci/chez-threads/bin/scheme
for pair in floor-7.85.0:/src/build/e1/ci/curl-floor/lib/libcurl.so.4 \
            ubuntu-openssl-8.5.0:/usr/lib/$arch/libcurl.so.4 \
            ubuntu-gnutls-8.5.0:/usr/lib/$arch/libcurl-gnutls.so.4 \
            current-8.23.0:$CURRENT/lib/libcurl.so.4; do
  CURL_LIB=${pair#*:} sh .plans/research/m5/location/zoneid.sh ${pair%%:*}
done'
fi
lane=$1
if [ -n "${CURL_LIB:-}" ]; then
  CHEZ_CURL_LIBCURL=$CURL_LIB "${CHEZ:-scheme}" --libdirs src --program $d/zoneid.sps < /dev/null 2>&1 | sed "s/^/[$lane] /"
else
  "${CHEZ:-scheme}" --libdirs src --program $d/zoneid.sps < /dev/null 2>&1 | sed "s/^/[$lane] /"
fi
