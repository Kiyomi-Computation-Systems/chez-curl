#!/bin/sh
# The M8 plan's review (2026-11-06): probe.c on lanes F, O, G and C, and on
# the mime-files probe's two builds without mime, in Docker ubuntu:24.04,
# --network none, --rm, CPUs 0-5. It reuses the mime-files probe's apt cache,
# build/m8/mime-files/apt, and fetches nothing. Run on the host, from the
# repository's root:
#   sh .plans/research/m8/review/formtell/docker.sh > .plans/research/m8/review/formtell/results/docker-N.log 2>&1
set -eu
[ "$#" -eq 0 ] || { echo "usage: docker.sh" >&2; exit 2; }
[ -f .plans/research/m8/review/formtell/run.sh ] || { echo "docker.sh: run it from the repository's root" >&2; exit 2; }
root=$PWD
cache=$root/build/m8/mime-files/apt
[ -f "$cache/fetched" ] || { echo "docker.sh: no apt cache at $cache" >&2; exit 1; }
for f in build/e1/ci/curl-floor/lib/libcurl.so.4 build/verify/c823/lane1/curl-current/lib/libcurl.so.4 \
         build/m8/mime-files/nomime-7.85.0/lib/libcurl.so.4 build/m8/mime-files/nomime-8.23.0/lib/libcurl.so.4; do
  [ -f "$f" ] || { echo "docker.sh: no $f" >&2; exit 1; }
done
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
exec docker run --rm --network none --cpuset-cpus 0-5 -v "$root:$root:ro" -v "$cache:/aptcache:ro" \
  -e ROOT="$root" -e HOSTUID="$(id -u)" -e HOSTGID="$(id -g)" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
echo "network interfaces: $(ls /sys/class/net | tr "\n" " ")"
rm -f /etc/apt/apt.conf.d/docker-clean
cp -R /aptcache/lists/. /var/lib/apt/lists/
cp /aptcache/archives/*.deb /var/cache/apt/archives/
apt-get install -y -qq --no-download --no-install-recommends build-essential libcurl4-openssl-dev libcurl3t64-gnutls >/dev/null 2>&1
dpkg-query -W -f "package \${Package} \${Version}\n" libcurl4t64 libcurl3t64-gnutls gcc || true
cd "$ROOT"
arch=$(uname -m)-linux-gnu
as_user() { setpriv --reuid="$HOSTUID" --regid="$HOSTGID" --clear-groups env HOME=/tmp TMPDIR=/tmp CC=gcc "$@"; }
r=.plans/research/m8/review/formtell/run.sh
as_user CURL_LIB=$ROOT/build/e1/ci/curl-floor/lib/libcurl.so.4 sh $r floor-7.85.0
as_user CURL_LIB=/usr/lib/$arch/libcurl.so.4 sh $r ubuntu-openssl-8.5.0
as_user CURL_LIB=/usr/lib/$arch/libcurl-gnutls.so.4 sh $r ubuntu-gnutls-8.5.0
as_user CURL_LIB=$ROOT/build/verify/c823/lane1/curl-current/lib/libcurl.so.4 sh $r current-8.23.0
as_user CURL_LIB=$ROOT/build/m8/mime-files/nomime-7.85.0/lib/libcurl.so.4 sh $r nomime-7.85.0
as_user CURL_LIB=$ROOT/build/m8/mime-files/nomime-8.23.0/lib/libcurl.so.4 sh $r nomime-8.23.0'
