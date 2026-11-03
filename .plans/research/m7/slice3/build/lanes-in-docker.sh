#!/bin/sh
# Inside Docker ubuntu:24.04, from build/m7s3b/lanes.sh: make deps and make test for
# each LANE on a copy of SNAP under /work, as the host's user, logs under
# /src/build/m7s3b/lanes/.
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
out=/src/build/m7s3b/lanes
mkdir -p "$out"
for lane in "$@"; do
  w=/work/$lane
  rm -rf "$w"
  mkdir -p "$w"
  (cd "$SNAP" && tar cf - .) | (cd "$w" && tar xf -)
  chown -R "$lane_user" "$w"
  case $lane in
    openssl) env_line="CHEZ_CURL_LIBCURL=/usr/lib/$arch/libcurl.so.4" ;;
    gnutls) env_line="CHEZ_CURL_LIBCURL=/usr/lib/$arch/libcurl-gnutls.so.4" ;;
    floor) env_line="CHEZ_CURL_LIBCURL=$ci/curl-floor/lib/libcurl.so.4 C_INCLUDE_PATH=$ci/curl-floor/include" ;;
    current) env_line="CHEZ_CURL_LIBCURL=$current/lib/libcurl.so.4 C_INCLUDE_PATH=$current/include" ;;
    *) echo "lanes-in-docker: no lane $lane" >&2; exit 2 ;;
  esac
  log="$out/lane-$lane${TAG:+-$TAG}.log"
  suites_line=
  [ -z "${SUITES:-}" ] || suites_line="SUITES='$SUITES'"
  echo "== lane $lane: $env_line make test $suites_line"
  start=$(date +%s)
  # shellcheck disable=SC2086
  if su "$lane_user" -c "cd $w && env CHEZ=$chez NODE=$node CC=gcc $env_line make --no-print-directory deps test $suites_line" >"$log" 2>&1; then
    echo "lane $lane: pass ($(( $(date +%s) - start )) s)"
  else
    echo "lane $lane: FAIL ($(( $(date +%s) - start )) s)"
  fi
  grep -E '^test: (pass|FAIL|HUNG|ran)' "$log" | sed "s|^|  [$lane] |" || true
  grep -E '^test-proxy: |^FAIL ' "$log" | cut -c1-600 | sed "s|^|  [$lane] |" || true
  if [ -n "${MEMORY_SUITES:-}" ]; then
    mlog="$out/lane-$lane-memory${TAG:+-$TAG}.log"
    echo "== lane $lane: $env_line make test-memory MEMORY_SUITES='$MEMORY_SUITES'"
    if su "$lane_user" -c "cd $w && env CHEZ=$chez NODE=$node CC=gcc $env_line make --no-print-directory test-memory MEMORY_SUITES='$MEMORY_SUITES'" >"$mlog" 2>&1; then
      echo "lane $lane memory: pass"
    else
      echo "lane $lane memory: FAIL"
    fi
    grep -E '^test-memory: (pass|FAIL|HUNG|ran)' "$mlog" | sed "s|^|  [$lane memory] |" || true
    cat $w/build/memory/*.log | grep -E '^test-proxy: |^FAIL' | sed "s|^|  [$lane memory] |" || true
  fi
done
chown -R "$HOST_UID:$HOST_GID" "$out"
