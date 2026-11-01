#!/bin/sh
# M6 slice 3's measurements (2026-10-31) in Docker ubuntu:24.04, on the four
# lanes the container cannot run: slice 2's docker.sh, its paths changed,
# and Node 20.10.0 on every lane. Run on the host, from the repository's
# root:
#   sh .plans/research/m6/slice3/docker.sh LANES PROGRAM [ARG...]
# It needs curl 8.23.0's install in build/verify/c823/lane1/curl-current
# (CURRENT overrides it), spike E1's floor curl in build/e1/ci/curl-floor
# and its threaded Chez in build/e1/ci/chez-threads, and Node 20.10.0 in
# build/verify/m3s2/node20. The repository is mounted read-only, at /src and
# at its own path, which build/scheme-libs's links name. LANES is all, the
# four native lanes, or a comma list of floor-7.85.0, ubuntu-openssl-8.5.0,
# ubuntu-gnutls-8.5.0, current-8.23.0 and ubuntu-openssl-8.5.0-valgrind,
# the last under Ubuntu's Valgrind with the gate's options, as the memory
# lane runs. It installs packaging/debian-prereqs.txt, then runs run.sh
# PROGRAM ARG... on each lane, in that order, one after another. It starts
# one container, with --rm, and touches no other.
set -eu
[ "$#" -ge 2 ] || { echo "usage: docker.sh LANES PROGRAM [ARG...]" >&2; exit 2; }
[ -f .plans/research/m6/slice3/run.sh ] || { echo "docker.sh: run it from the repository's root" >&2; exit 2; }
current=$(cd "${CURRENT:-build/verify/c823/lane1/curl-current}" && pwd)
lanes=$1
shift
lanes=$(echo "$lanes" | sed 's/\ball\b/floor-7.85.0,ubuntu-openssl-8.5.0,ubuntu-gnutls-8.5.0,current-8.23.0/')
for f in "$current/lib/libcurl.so.4" build/e1/ci/curl-floor/lib/libcurl.so.4 build/e1/ci/chez-threads/bin/scheme \
         build/verify/m3s2/node20/node; do
  [ -f "$f" ] || { echo "docker.sh: no $f" >&2; exit 1; }
done
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
root=$PWD
exec docker run --rm -v "$root:/src:ro" -v "$root:$root:ro" \
  -e CURRENT="$current" -e LANES="$lanes" -e BOUND="${BOUND:-3600}" \
  ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
cd /src
pkgs=$(grep -v -e "^#" -e "^\$" packaging/debian-prereqs.txt | tr "\n" " ")
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends $pkgs >/dev/null 2>&1
dpkg-query -W -f "package \${Package} \${Version}\n" libcurl4t64 libcurl3t64-gnutls valgrind openssl
arch=$(uname -m)-linux-gnu
export NODE=/src/build/verify/m3s2/node20/node CHEZ=/src/build/e1/ci/chez-threads/bin/scheme
export CC=gcc
runner=.plans/research/m6/slice3/run.sh
for lane in $(echo "$LANES" | tr "," " "); do
  case $lane in
    floor-7.85.0) CURL_LIB=/src/build/e1/ci/curl-floor/lib/libcurl.so.4 sh $runner "$lane" "$@" ;;
    ubuntu-openssl-8.5.0) CURL_LIB=/usr/lib/$arch/libcurl.so.4 sh $runner "$lane" "$@" ;;
    ubuntu-gnutls-8.5.0) CURL_LIB=/usr/lib/$arch/libcurl-gnutls.so.4 sh $runner "$lane" "$@" ;;
    current-8.23.0) CURL_LIB=$CURRENT/lib/libcurl.so.4 sh $runner "$lane" "$@" ;;
    ubuntu-openssl-8.5.0-valgrind)
      VALGRIND=valgrind CURL_LIB=/usr/lib/$arch/libcurl.so.4 sh $runner "$lane" "$@" ;;
    *) echo "docker.sh: no lane $lane"; exit 2 ;;
  esac
done' docker "$@"
