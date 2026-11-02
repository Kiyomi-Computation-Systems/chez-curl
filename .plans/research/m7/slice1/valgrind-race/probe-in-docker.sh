#!/bin/sh
# Inside Docker ubuntu:24.04: the probe tree, build/m7s1b/probe, on each
# LANE: the probe natively and under the memory gate (Ubuntu's Valgrind),
# PROBE_REPS each, then test-version under the gate RUNS times.
set -eu
export DEBIAN_FRONTEND=noninteractive
pkgs=$(grep -v -e '^#' -e '^$' /src/packaging/debian-prereqs.txt | tr '\n' ' ')
apt-get update -qq >/dev/null
# shellcheck disable=SC2086
apt-get install -y -qq --no-install-recommends $pkgs >/dev/null 2>&1
dpkg-query -W -f 'package ${Package} ${Version}\n' libcurl4t64 libcurl3t64-gnutls valgrind
lane_user=$(getent passwd "$HOST_UID" | cut -d: -f1)
if [ -z "$lane_user" ]; then useradd -m -u "$HOST_UID" lane; lane_user=lane; fi
ci=/src/build/e1/ci
chez=$ci/chez-threads/lib/csv10.4.0/ta6le/scheme
node=/src/build/verify/m3s2/node20/node
current=/src/build/verify/c823/lane1/curl-current
arch=$(uname -m)-linux-gnu
for lane in "$@"; do
  w=/work/$lane
  rm -rf "$w"; mkdir -p "$w"
  (cd /src/build/m7s1b/probe && tar cf - .) | (cd "$w" && tar xf -)
  chown -R "$lane_user" "$w"
  case $lane in
    openssl) env_line="CHEZ_CURL_LIBCURL=/usr/lib/$arch/libcurl.so.4" ;;
    gnutls) env_line="CHEZ_CURL_LIBCURL=/usr/lib/$arch/libcurl-gnutls.so.4" ;;
    floor) env_line="CHEZ_CURL_LIBCURL=$ci/curl-floor/lib/libcurl.so.4 C_INCLUDE_PATH=$ci/curl-floor/include" ;;
    current) env_line="CHEZ_CURL_LIBCURL=$current/lib/libcurl.so.4 C_INCLUDE_PATH=$current/include" ;;
  esac
  envs="CHEZ=$chez NODE=$node CC=gcc PROBE_REPS=${PROBE_REPS:-30} $env_line"
  su "$lane_user" -c "cd $w && env $envs make --no-print-directory deps test SUITES=tests/test-pkprobe.sps" > /tmp/n.log 2>&1 || true
  grep "^(probe" /tmp/n.log | sed "s/^/[$lane native] /"
  su "$lane_user" -c "cd $w && env $envs make --no-print-directory test-memory MEMORY_SUITES=tests/test-pkprobe.sps" > /tmp/m.log 2>&1 || true
  grep "^test-memory: " /tmp/m.log | sed "s/^/[$lane valgrind] /"
  grep "^(probe" $w/build/memory/test-pkprobe.log | sed "s/^/[$lane valgrind] /"
  i=1
  while [ $i -le ${RUNS:-2} ]; do
    su "$lane_user" -c "cd $w && env $envs make --no-print-directory test-memory MEMORY_SUITES=tests/test-version.sps" > /tmp/v.log 2>&1 || true
    echo "[$lane valgrind test-version $i] $(grep '^test-memory: ' /tmp/v.log | tr '\n' ' ') $(grep -h 'test-version: prior\|test-version: together' $w/build/memory/test-version.log | tr '\n' ' ')"
    grep -h "^FAIL" $w/build/memory/test-version.log | sed "s/^/[$lane valgrind test-version $i] /" | cut -c1-200 || true
    i=$((i+1))
  done
done
