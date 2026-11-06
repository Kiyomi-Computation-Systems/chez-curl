#!/bin/sh
# Inside Docker ubuntu:24.04, from build-lanes.sh: for each LANE, a copy of
# /src/build/carried-guard/build under /work, then make deps and make test
# SUITES, or with MEMORY make test-memory MEMORY_SUITES, ROUNDS times, as
# the host's user. Each log to the build directory of the research.
set -eu
export DEBIAN_FRONTEND=noninteractive
pkgs=$(grep -v -e '^#' -e '^$' /src/packaging/debian-prereqs.txt | tr '\n' ' ')
apt-get update -qq >/dev/null
# shellcheck disable=SC2086
apt-get install -y -qq --no-install-recommends $pkgs >/dev/null 2>&1
dpkg-query -W -f 'package ${Package} ${Version}\n' libcurl4t64 libcurl3t64-gnutls openssl libnghttp2-14 valgrind
echo "cpus: $(nproc)"
lane_user=$(getent passwd "$HOST_UID" | cut -d: -f1)
if [ -z "$lane_user" ]; then useradd -m -u "$HOST_UID" lane; lane_user=lane; fi
ci=/src/build/e1/ci
chez=$ci/chez-threads/lib/csv10.4.0/ta6le/scheme
node=/src/build/verify/m3s2/node20/node
current=/src/build/verify/c823/lane1/curl-current
arch=$(uname -m)-linux-gnu
out=/src/.plans/research/m7/carried/guard/${OUT:-build}
mkdir -p "$out"
for lane in "$@"; do
  mkdir -p /work
  w=$(mktemp -d "/work/$lane.XXXXXX")
  (cd "/src/build/carried-guard/${COPY:-build}" && tar cf - --exclude ./build --exclude ./probe .) | (cd "$w" && tar xf -)
  chown -R "$lane_user" "$w"
  case $lane in
    openssl) env_line="CHEZ_CURL_LIBCURL=/usr/lib/$arch/libcurl.so.4" ;;
    gnutls) env_line="CHEZ_CURL_LIBCURL=/usr/lib/$arch/libcurl-gnutls.so.4" ;;
    floor) env_line="CHEZ_CURL_LIBCURL=$ci/curl-floor/lib/libcurl.so.4 C_INCLUDE_PATH=$ci/curl-floor/include" ;;
    current) env_line="CHEZ_CURL_LIBCURL=$current/lib/libcurl.so.4 C_INCLUDE_PATH=$current/include" ;;
    *) echo "build-lanes-in-docker: no lane $lane" >&2; exit 2 ;;
  esac
  round=1
  while [ "$round" -le "$ROUNDS" ]; do
    if [ -n "$MEMORY" ]; then
      log="$out/lane-$lane-$TAG-$round.log"
      target="deps test-memory MEMORY_SUITES='$SUITES'"
    else
      log="$out/lane-$lane-$TAG.log"
      if [ -n "$SUITES" ]; then target="deps test SUITES='$SUITES'"; else target="deps test"; fi
    fi
    echo "== lane $lane round $round: $env_line make $target"
    start=$(date +%s)
    if su "$lane_user" -c "cd $w && env CHEZ=$chez NODE=$node CC=gcc $env_line make --no-print-directory $target" >"$log" 2>&1; then
      echo "lane $lane round $round: pass ($(( $(date +%s) - start )) s)"
    else
      echo "lane $lane round $round: FAIL ($(( $(date +%s) - start )) s)"
    fi
    grep -E '^test(-memory)?: (pass|FAIL|HUNG|ran)' "$log" | sed "s|^|  [$lane $round] |" || true
    grep -E '^FAIL ' "$log" | cut -c1-300 | sed "s|^|  [$lane $round] |" || true
    if [ -n "$MEMORY" ] && [ -d "$w/build/memory" ]; then
      mkdir -p "$out/memory-$lane-$TAG-$round"
      cp "$w"/build/memory/* "$out/memory-$lane-$TAG-$round/"
    fi
    round=$((round + 1))
  done
done
chown -R "$HOST_UID:$HOST_GID" "$out"
