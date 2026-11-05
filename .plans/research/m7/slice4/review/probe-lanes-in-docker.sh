#!/bin/sh
# Inside Docker ubuntu:24.04, from probe-lanes.sh: for each LANE, a copy of
# SNAP under /work, make deps, then each probe of PROBES, as the host's
# user, its log build/m7s4-review/lanes/LANE-PROBE.log. The lanes' paths and
# packages are the build's lanes-in-docker.sh's.
set -eu
export DEBIAN_FRONTEND=noninteractive
pkgs=$(grep -v -e '^#' -e '^$' /src/packaging/debian-prereqs.txt | tr '\n' ' ')
apt-get update -qq >/dev/null
# shellcheck disable=SC2086
apt-get install -y -qq --no-install-recommends $pkgs >/dev/null 2>&1
dpkg-query -W -f 'package ${Package} ${Version}\n' libcurl4t64 libcurl3t64-gnutls
lane_user=$(getent passwd "$HOST_UID" | cut -d: -f1)
if [ -z "$lane_user" ]; then useradd -m -u "$HOST_UID" lane; lane_user=lane; fi
ci=/src/build/e1/ci
chez=$ci/chez-threads/lib/csv10.4.0/ta6le/scheme
node=/src/build/verify/m3s2/node20/node
current=/src/build/verify/c823/lane1/curl-current
arch=$(uname -m)-linux-gnu
out=/src/build/m7s4-review/lanes
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
    floor) env_line="CHEZ_CURL_LIBCURL=$ci/curl-floor/lib/libcurl.so.4" ;;
    current) env_line="CHEZ_CURL_LIBCURL=$current/lib/libcurl.so.4" ;;
    *) echo "probe-lanes-in-docker: no lane $lane" >&2; exit 2 ;;
  esac
  su "$lane_user" -c "cd $w && env CHEZ=$chez make --no-print-directory deps" >/dev/null 2>&1
  for probe in $PROBES; do
    log="$out/$lane-$(basename "$probe" .sps).log"
    su "$lane_user" -c "cd $w && env CHEZ=$chez NODE=$node $env_line timeout 300 $chez --libdirs src:tests:build/scheme-libs --program $probe" >"$log" 2>&1 || echo "exit $?" >> "$log"
    sed "s|^|  [$lane] |" "$log" | cut -c1-400
  done
done
chown -R "$HOST_UID:$HOST_GID" "$out"
