#!/bin/sh
# Inside Docker ubuntu:24.04, from lanes2.sh, COPY the copy: for each LANE, a copy of
# /src/build/carried-guard/q2 under /work, make deps, then probe/PROGRAM, as
# the host's user; its output to the results directory, lane-LANE-TAG.log.
set -eu
export DEBIAN_FRONTEND=noninteractive
pkgs=$(grep -v -e '^#' -e '^$' /src/packaging/debian-prereqs.txt | tr '\n' ' ')
apt-get update -qq >/dev/null
# shellcheck disable=SC2086
apt-get install -y -qq --no-install-recommends $pkgs >/dev/null 2>&1
dpkg-query -W -f 'package ${Package} ${Version}\n' libcurl4t64 libcurl3t64-gnutls openssl libnghttp2-14
lane_user=$(getent passwd "$HOST_UID" | cut -d: -f1)
if [ -z "$lane_user" ]; then useradd -m -u "$HOST_UID" lane; lane_user=lane; fi
ci=/src/build/e1/ci
chez=$ci/chez-threads/lib/csv10.4.0/ta6le/scheme
node=/src/build/verify/m3s2/node20/node
current=/src/build/verify/c823/lane1/curl-current
arch=$(uname -m)-linux-gnu
out=/src/.plans/research/m7/carried/guard/results
vg=
if [ -n "${UNDER_VALGRIND:-}" ]; then vg="valgrind -q --tool=memcheck --error-exitcode=0 --log-file=/dev/null"; fi
for lane in "$@"; do
  mkdir -p /work
  w=$(mktemp -d "/work/$lane.XXXXXX")
  (cd "/src/build/carried-guard/$COPY" && tar cf - --exclude ./build .) | (cd "$w" && tar xf -)
  chown -R "$lane_user" "$w"
  case $lane in
    openssl) env_line="CHEZ_CURL_LIBCURL=/usr/lib/$arch/libcurl.so.4" ;;
    gnutls) env_line="CHEZ_CURL_LIBCURL=/usr/lib/$arch/libcurl-gnutls.so.4" ;;
    floor) env_line="CHEZ_CURL_LIBCURL=$ci/curl-floor/lib/libcurl.so.4 C_INCLUDE_PATH=$ci/curl-floor/include" ;;
    current) env_line="CHEZ_CURL_LIBCURL=$current/lib/libcurl.so.4 C_INCLUDE_PATH=$current/include" ;;
    *) echo "lanes-in-docker: no lane $lane" >&2; exit 2 ;;
  esac
  log="$out/lane-$lane-$TAG.log"
  echo "== lane $lane: $env_line probe/$PROGRAM"
  start=$(date +%s)
  if su "$lane_user" -c "cd $w && env CHEZ=$chez NODE=$node CC=gcc $env_line make --no-print-directory deps >/dev/null && env CHEZ=$chez NODE=$node HELD_REPS=${HELD_REPS:-} HELD_PATHS='${HELD_PATHS:-}' HELD_FACES='${HELD_FACES:-}' $env_line timeout 3600 $vg $chez --libdirs src:tests:build/scheme-libs --program probe/$PROGRAM" >"$log" 2>&1; then
    echo "lane $lane: exit 0 ($(( $(date +%s) - start )) s)"
  else
    echo "lane $lane: FAIL ($(( $(date +%s) - start )) s)"
  fi
done
chown -R "$HOST_UID:$HOST_GID" "$out"
