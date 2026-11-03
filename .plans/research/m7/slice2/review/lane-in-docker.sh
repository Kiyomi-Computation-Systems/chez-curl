#!/bin/sh
set -eu
export DEBIAN_FRONTEND=noninteractive
pkgs=$(grep -v -e '^#' -e '^$' /src/packaging/debian-prereqs.txt | tr '\n' ' ')
apt-get update -qq >/dev/null
# shellcheck disable=SC2086
apt-get install -y -qq --no-install-recommends $pkgs >/dev/null 2>&1
lane_user=$(getent passwd "$HOST_UID" | cut -d: -f1)
if [ -z "$lane_user" ]; then useradd -m -u "$HOST_UID" lane; lane_user=lane; fi
ci=/src/build/e1/ci
chez=$ci/chez-threads/lib/csv10.4.0/ta6le/scheme
node=/src/build/verify/m3s2/node20/node
current=/src/build/verify/c823/lane1/curl-current
arch=$(uname -m)-linux-gnu
w=/work/tree
mkdir -p "$w"
(cd "/src/$TREE" && tar cf - --exclude=./build .) | (cd "$w" && tar xf -)
mkdir -p "$w/build"
[ -d /src/build/m7s2-review ] && cp -r /src/build/m7s2-review "$w/build/"
chown -R "$lane_user" "$w"
case $LANE in
  openssl) env_line="CHEZ_CURL_LIBCURL=/usr/lib/$arch/libcurl.so.4" ;;
  gnutls) env_line="CHEZ_CURL_LIBCURL=/usr/lib/$arch/libcurl-gnutls.so.4" ;;
  floor) env_line="CHEZ_CURL_LIBCURL=$ci/curl-floor/lib/libcurl.so.4 C_INCLUDE_PATH=$ci/curl-floor/include" ;;
  current) env_line="CHEZ_CURL_LIBCURL=$current/lib/libcurl.so.4 C_INCLUDE_PATH=$current/include" ;;
  *) echo "no lane $LANE" >&2; exit 2 ;;
esac
su "$lane_user" -c "cd $w && env CHEZ=$chez NODE=$node CC=gcc $env_line sh -c 'make --no-print-directory deps >/dev/null && $COMMAND'"
