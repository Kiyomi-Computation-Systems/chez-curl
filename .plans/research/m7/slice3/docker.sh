#!/bin/sh
# M7 slice 3's measurements (2026-11-02) in Docker ubuntu:24.04, on the four
# lanes the Guix container cannot run. Run on the host, from the
# repository's root, after make-prototype.sh:
#   sh .plans/research/m7/slice3/docker.sh LANES [PART...]
# It needs curl 8.23.0's install in build/verify/c823/lane1/curl-current
# (CURRENT overrides it), spike E1's floor curl in build/e1/ci/curl-floor
# and its threaded Chez in build/e1/ci/chez-threads, and Node 20.10.0 in
# build/verify/m3s2/node20. LANES is all, the four lanes, or a comma list of
# floor-7.85.0, ubuntu-openssl-8.5.0, ubuntu-gnutls-8.5.0 and
# current-8.23.0.
#
# The apt packages are fetched once, by a container that does nothing else,
# into build/m7s3/apt (git-ignored; handed back to the caller's uid). The
# lanes then run in one container with --network none: loopback alone,
# which it prints. It installs the packages from that cache, then runs
# run.sh LANE PART... on each lane, in that order, one after another, with
# LOW_PORTS=1: the container is root, so the stand-in also listens on 80,
# 443 and 1080 (item 2 (c)). The repository is mounted read-only, at /src
# and at its own path. VALGRIND, SLOW and BOUND are handed to run.sh. It
# starts two containers, each with --rm, and touches no other.
set -eu
[ "$#" -ge 1 ] || { echo "usage: docker.sh LANES [PART...]" >&2; exit 2; }
[ -f .plans/research/m7/slice3/run.sh ] || { echo "docker.sh: run it from the repository's root" >&2; exit 2; }
[ -d build/m7s3/src ] || { echo "docker.sh: no build/m7s3/src: run make-prototype.sh first" >&2; exit 2; }
current=$(cd "${CURRENT:-build/verify/c823/lane1/curl-current}" && pwd)
lanes=$1
shift
lanes=$(echo "$lanes" | sed 's/\ball\b/floor-7.85.0,ubuntu-openssl-8.5.0,ubuntu-gnutls-8.5.0,current-8.23.0/')
chez=build/e1/ci/chez-threads/lib/csv10.4.0/ta6le/scheme
for f in "$current/lib/libcurl.so.4" build/e1/ci/curl-floor/lib/libcurl.so.4 $chez build/verify/m3s2/node20/node; do
  [ -f "$f" ] || { echo "docker.sh: no $f" >&2; exit 1; }
done
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
root=$PWD
cache=$root/build/m7s3/apt
pkgs="libcurl4t64 libcurl3t64-gnutls ca-certificates openssl valgrind"
if [ ! -f "$cache/fetched" ]; then
  mkdir -p "$cache/archives/partial" "$cache/lists/partial"
  docker run --rm -v "$cache/archives:/var/cache/apt/archives" -v "$cache/lists:/var/lib/apt/lists" \
    -e HOSTID="$(id -u):$(id -g)" -e PKGS="$pkgs" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
rm -f /etc/apt/apt.conf.d/docker-clean
apt-get update -qq >/dev/null
apt-get install -y -qq --download-only --no-install-recommends $PKGS >/dev/null
chown -R "$HOSTID" /var/cache/apt/archives /var/lib/apt/lists'
  touch "$cache/fetched"
fi
exec docker run --rm --network none -v "$root:/src:ro" -v "$root:$root:ro" -v "$cache:/aptcache:ro" \
  -e CURRENT="$current" -e LANES="$lanes" -e BOUND="${BOUND:-900}" -e CHEZ_REAL="/src/$chez" \
  -e VALGRIND="${VALGRIND:-}" -e SLOW="${SLOW:-10}" -e PKGS="$pkgs" \
  ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
echo "network interfaces: $(ls /sys/class/net | tr "\n" " ")"
rm -f /etc/apt/apt.conf.d/docker-clean
cp -R /aptcache/lists/. /var/lib/apt/lists/
cp /aptcache/archives/*.deb /var/cache/apt/archives/
apt-get install -y -qq --no-download --no-install-recommends $PKGS >/dev/null 2>&1
cd /src
grep PRETTY_NAME /etc/os-release
dpkg-query -W -f "package \${Package} \${Version}\n" libcurl4t64 libcurl3t64-gnutls libssl3t64 libgnutls30t64 openssl libnghttp2-14 valgrind
arch=$(uname -m)-linux-gnu
export NODE=/src/build/verify/m3s2/node20/node CHEZ=$CHEZ_REAL LOW_PORTS=1
[ -n "$VALGRIND" ] || unset VALGRIND
runner=.plans/research/m7/slice3/run.sh
for lane in $(echo "$LANES" | tr "," " "); do
  case $lane in
    floor-7.85.0) CURL_LIB=/src/build/e1/ci/curl-floor/lib/libcurl.so.4 sh $runner "$lane" "$@" ;;
    ubuntu-openssl-8.5.0) CURL_LIB=/usr/lib/$arch/libcurl.so.4 sh $runner "$lane" "$@" ;;
    ubuntu-gnutls-8.5.0) CURL_LIB=/usr/lib/$arch/libcurl-gnutls.so.4 sh $runner "$lane" "$@" ;;
    current-8.23.0) CURL_LIB=$CURRENT/lib/libcurl.so.4 sh $runner "$lane" "$@" ;;
    *) echo "docker.sh: no lane $lane"; exit 2 ;;
  esac
done' docker "$@"
