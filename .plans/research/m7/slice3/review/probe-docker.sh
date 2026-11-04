#!/bin/sh
# Runs one Chez program on the four Docker lanes (floor 7.85.0, Ubuntu's
# 8.5.0 with OpenSSL and with GnuTLS, 8.23.0), in one --rm --network none
# ubuntu:24.04, from the apt cache the research fetched into build/m7s3/apt.
#   sh build/m7s3-review/probe-docker.sh PROGRAM [ARG...]
# From the repository's root, on the host. The repository is mounted
# read-only. Each lane's output is prefixed "== LANE".
set -eu
[ "$#" -ge 1 ] || { echo "usage: probe-docker.sh PROGRAM [ARG...]" >&2; exit 2; }
root=$PWD
cache=$root/build/m7s3/apt
[ -f "$cache/fetched" ] || { echo "probe-docker: no apt cache at $cache" >&2; exit 1; }
current=$root/build/verify/c823/lane1/curl-current
chez=build/e1/ci/chez-threads/lib/csv10.4.0/ta6le/scheme
pkgs="libcurl4t64 libcurl3t64-gnutls ca-certificates openssl valgrind"
exec docker run --rm --network none -v "$root:/src:ro" -v "$root:$root:ro" -v "$cache:/aptcache:ro" \
  -e CURRENT="$current" -e CHEZ_REAL="/src/$chez" -e PKGS="$pkgs" -e LANES="${LANES:-floor openssl gnutls current}" \
  ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
rm -f /etc/apt/apt.conf.d/docker-clean
cp -R /aptcache/lists/. /var/lib/apt/lists/
cp /aptcache/archives/*.deb /var/cache/apt/archives/
apt-get install -y -qq --no-download --no-install-recommends $PKGS >/dev/null 2>&1
cd /src/build/m7s3-review/tree
arch=$(uname -m)-linux-gnu
export NODE=/src/build/verify/m3s2/node20/node CHEZ=$CHEZ_REAL
prog=$1; shift
for lane in $LANES; do
  case $lane in
    floor) lib=/src/build/e1/ci/curl-floor/lib/libcurl.so.4 ;;
    openssl) lib=/usr/lib/$arch/libcurl.so.4 ;;
    gnutls) lib=/usr/lib/$arch/libcurl-gnutls.so.4 ;;
    current) lib=$CURRENT/lib/libcurl.so.4 ;;
  esac
  echo "== $lane"
  CHEZ_CURL_LIBCURL=$lib timeout 600 $CHEZ --libdirs src:tests:/src/build/scheme-libs --program "$prog" "$@" 2>&1 || echo "exit $?"
done' docker "$@"
