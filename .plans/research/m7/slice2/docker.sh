#!/bin/sh
# M7 slice 2's measurements (2026-11-02) in Docker ubuntu:24.04, on the four
# lanes the Guix container cannot run: slice 1's docker.sh, its runner
# changed to this directory's run.sh. Run on the host, from the
# repository's root, after make-prototype.sh:
#   sh .plans/research/m7/slice2/docker.sh LANES [PART...]
# It needs curl 8.23.0's install in build/verify/c823/lane1/curl-current
# (CURRENT overrides it), spike E1's floor curl in build/e1/ci/curl-floor
# and its threaded Chez in build/e1/ci/chez-threads, and Node 20.10.0 in
# build/verify/m3s2/node20. The repository is mounted read-only, at /src and
# at its own path. LANES is all, the four lanes, or a comma list of
# floor-7.85.0, ubuntu-openssl-8.5.0, ubuntu-gnutls-8.5.0 and
# current-8.23.0. It installs packaging/debian-prereqs.txt (Valgrind among
# them), then runs run.sh LANE PART... on each lane, in that order, one
# after another. VALGRIND, SLOW, BOUND and PROGRAM are handed to run.sh. It starts
# one container, with --rm, and touches no other.
set -eu
[ "$#" -ge 1 ] || { echo "usage: docker.sh LANES [PART...]" >&2; exit 2; }
[ -f .plans/research/m7/slice2/run.sh ] || { echo "docker.sh: run it from the repository's root" >&2; exit 2; }
[ -d build/m7s2/src ] || { echo "docker.sh: no build/m7s2/src: run make-prototype.sh first" >&2; exit 2; }
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
exec docker run --rm -v "$root:/src:ro" -v "$root:$root:ro" \
  -e CURRENT="$current" -e LANES="$lanes" -e BOUND="${BOUND:-900}" -e CHEZ_REAL="/src/$chez" \
  -e VALGRIND="${VALGRIND:-}" -e SLOW="${SLOW:-10}" -e PROGRAM="${PROGRAM:-auth.sps}" \
  ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
cd /src
pkgs=$(grep -v -e "^#" -e "^\$" packaging/debian-prereqs.txt | tr "\n" " ")
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends $pkgs >/dev/null 2>&1
grep PRETTY_NAME /etc/os-release
dpkg-query -W -f "package \${Package} \${Version}\n" libcurl4t64 libcurl3t64-gnutls openssl libnghttp2-14 valgrind
arch=$(uname -m)-linux-gnu
export NODE=/src/build/verify/m3s2/node20/node CHEZ=$CHEZ_REAL
[ -n "$VALGRIND" ] || unset VALGRIND
runner=.plans/research/m7/slice2/run.sh
for lane in $(echo "$LANES" | tr "," " "); do
  case $lane in
    floor-7.85.0) CURL_LIB=/src/build/e1/ci/curl-floor/lib/libcurl.so.4 sh $runner "$lane" "$@" ;;
    ubuntu-openssl-8.5.0) CURL_LIB=/usr/lib/$arch/libcurl.so.4 sh $runner "$lane" "$@" ;;
    ubuntu-gnutls-8.5.0) CURL_LIB=/usr/lib/$arch/libcurl-gnutls.so.4 sh $runner "$lane" "$@" ;;
    current-8.23.0) CURL_LIB=$CURRENT/lib/libcurl.so.4 sh $runner "$lane" "$@" ;;
    *) echo "docker.sh: no lane $lane"; exit 2 ;;
  esac
done' docker "$@"
