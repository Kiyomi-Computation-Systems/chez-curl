#!/bin/sh
# M8 slice 2's review fixes: odd.sh on the four Docker lanes, as
# ../../lanes.sh sets them up: ubuntu:24.04, --network none, the apt cache at
# build/m8s2/apt, spike E1's threaded Chez, Node 20.10.0. From the
# repository's root, on the host:
#   sh .plans/research/m8/slice2/build/fix/odd/lanes.sh TREE
# TREE, a directory under build/m8s2/ holding src/ and odd/, mounted
# read-only. One --rm container, CPUs 6 to 17.
set -eu
tree=$1
case $tree in /*) ;; *) tree=$PWD/$tree ;; esac
[ -f "$tree/odd/odd.sh" ] || { echo "lanes.sh: no $tree/odd/odd.sh" >&2; exit 2; }
cache=$PWD/build/m8s2/apt
[ -f "$cache/fetched" ] || { echo "lanes.sh: no apt cache: run ../../lanes.sh first" >&2; exit 2; }
pkgs=$(grep -v -e '^#' -e '^$' packaging/debian-prereqs.txt | tr '\n' ' ')
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
exec docker run --rm --network none --cpuset-cpus 6-17 -v "$PWD:/src:ro" -v "$tree:/t:ro" -v "$cache:/aptcache:ro" \
  -e PKGS="$pkgs" -e HOST_UID="$(id -u)" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
echo "network interfaces: $(ls /sys/class/net | tr "\n" " ")"
rm -f /etc/apt/apt.conf.d/docker-clean
cp -R /aptcache/lists/. /var/lib/apt/lists/
cp /aptcache/archives/*.deb /var/cache/apt/archives/
apt-get install -y -qq --no-download --no-install-recommends $PKGS >/dev/null 2>&1
dpkg-query -W -f "package \${Package} \${Version}\n" libcurl4t64 libcurl3t64-gnutls
user=$(getent passwd "$HOST_UID" | cut -d: -f1 || true)
if [ -z "$user" ]; then useradd -m -u "$HOST_UID" lane; user=lane; fi
ci=/src/build/e1/ci
arch=$(uname -m)-linux-gnu
for lane in floor openssl gnutls current; do
  case $lane in
    floor) lib=$ci/curl-floor/lib/libcurl.so.4 ;;
    openssl) lib=/usr/lib/$arch/libcurl.so.4 ;;
    gnutls) lib=/usr/lib/$arch/libcurl-gnutls.so.4 ;;
    current) lib=/src/build/verify/c823/lane1/curl-current/lib/libcurl.so.4 ;;
  esac
  su "$user" -c "cd /t && env CHEZ=$ci/chez-threads/lib/csv10.4.0/ta6le/scheme CHEZ_CURL_LIBCURL=$lib NODE=/src/build/verify/m3s2/node20/node sh odd/odd.sh $lane"
done'
