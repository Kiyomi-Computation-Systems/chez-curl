#!/bin/sh
# M5 slice 1's stand-ins for CI's lanes, inside Docker ubuntu:24.04, from
# lanes.sh on the host. Not for the host.
#
#   lanes-in-docker.sh LANE...
#
# LANE is main (Ubuntu's libcurl4t64, found by discovery), gnutls
# (libcurl-gnutls.so.4), floor (curl 7.85.0 and its headers, Node 20.10.0)
# or memory (make check-memory-gate and make test-memory, Ubuntu's Valgrind).
# Each runs on a copy of the tree, without .git and build, under the floor's
# Chez from spike E1's build, so nothing here writes the host's build/.
set -eu
export DEBIAN_FRONTEND=noninteractive
pkgs=$(grep -v -e '^#' -e '^$' /src/packaging/debian-prereqs.txt | tr '\n' ' ')
apt-get update -qq >/dev/null
# shellcheck disable=SC2086
apt-get install -y -qq --no-install-recommends $pkgs >/dev/null 2>&1
lane_user=$(getent passwd "$HOST_UID" | cut -d: -f1)
if [ -z "$lane_user" ]; then useradd -m -u "$HOST_UID" lane; lane_user=lane; fi
ci=/src/build/e1/ci
arch=$(uname -m)-linux-gnu
for lane in "$@"; do
  w=/work/$lane
  rm -rf "$w"
  mkdir -p "$w"
  (cd /src/build/m5s1/snap && tar cf - .) | (cd "$w" && tar xf -)
  mkdir -p "$w/vendor"
  cp -r /src/build/m5s1/snap/vendor/. "$w/vendor/"
  chown -R "$lane_user" "$w"
  case $lane in
    main) env_line="NODE=$GUIX_NODE" ; target="build test check-variadic" ;;
    gnutls) env_line="NODE=$GUIX_NODE CHEZ_CURL_LIBCURL=/usr/lib/$arch/libcurl-gnutls.so.4" ; target="test" ;;
    floor) env_line="NODE=/src/build/verify/m3s2/node20/node CHEZ_CURL_LIBCURL=$ci/curl-floor/lib/libcurl.so.4 C_INCLUDE_PATH=$ci/curl-floor/include" ; target="build test" ;;
    memory) env_line="NODE=$GUIX_NODE" ; target="check-memory-gate test-memory" ;;
    current) env_line="NODE=$GUIX_NODE CHEZ_CURL_LIBCURL=/src/build/verify/c823/lane1/curl-current/lib/libcurl.so.4 C_INCLUDE_PATH=/src/build/verify/c823/lane1/curl-current/include" ; target="build test" ;;
    *) echo "lanes-in-docker: no lane $lane" >&2; exit 2 ;;
  esac
  echo "== lane $lane: $env_line make $target"
  start=$(date +%s)
  # shellcheck disable=SC2086
  suites_line=
  [ -z "${SUITES:-}" ] || suites_line="SUITES='$SUITES'"
  if su "$lane_user" -c "cd $w && env CHEZ=$ci/chez-threads/bin/scheme $env_line make --no-print-directory deps $target $suites_line" >"/src/build/m5s1/lane-$lane.log" 2>&1; then
    echo "lane $lane: pass ($(( $(date +%s) - start )) s)"
  else
    echo "lane $lane: FAIL, exit $? ($(( $(date +%s) - start )) s)"
  fi
  grep -E '^test: (pass|FAIL|HUNG|ran)|^test-memory: (pass|FAIL|HUNG|ran)|^check-memory-gate|  version:' "/src/build/m5s1/lane-$lane.log" | sed "s|^|  [$lane] |" || true
done
chown "$HOST_UID:$HOST_GID" /src/build/m5s1/lane-*.log
