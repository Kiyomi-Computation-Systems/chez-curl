#!/bin/sh
# Inside Docker ubuntu:24.04, --network none, from lanes.sh: the packages
# installed from the cache, then MODE for each LANE given (lanes.sh's header).
set -eu
export DEBIAN_FRONTEND=noninteractive
echo "network interfaces: $(ls /sys/class/net | tr '\n' ' ')"
rm -f /etc/apt/apt.conf.d/docker-clean
cp -R /aptcache/lists/. /var/lib/apt/lists/
cp /aptcache/archives/*.deb /var/cache/apt/archives/
# shellcheck disable=SC2086
apt-get install -y -qq --no-download --no-install-recommends $PKGS >/dev/null 2>&1
dpkg-query -W -f 'package ${Package} ${Version}\n' libcurl4t64 libcurl3t64-gnutls libnghttp2-14 libssl3t64 libgnutls30t64 openssl valgrind || true
lane_user=$(getent passwd "$HOST_UID" | cut -d: -f1 || true)
if [ -z "$lane_user" ]; then useradd -m -u "$HOST_UID" lane; lane_user=lane; fi
ci=/src/build/e1/ci
chez=$ci/chez-threads/lib/csv10.4.0/ta6le/scheme
node20=${NODE_FOR_TEST:-/src/build/verify/m3s2/node20/node}
current=/src/build/verify/c823/lane1/curl-current
nomime=/src/build/m8/mime-files
arch=$(uname -m)-linux-gnu
for lane in "$@"; do
  nofiles=${NOFILES:-}
  case $lane in
    openssl) lib=/usr/lib/$arch/libcurl.so.4; inc= ; probe_node=$GUIX_NODE ;;
    gnutls) lib=/usr/lib/$arch/libcurl-gnutls.so.4; inc= ; probe_node=$GUIX_NODE ;;
    floor) lib=$ci/curl-floor/lib/libcurl.so.4; inc=$ci/curl-floor/include; probe_node=$node20 ;;
    current) lib=$current/lib/libcurl.so.4; inc=$current/include; probe_node=$GUIX_NODE ;;
    nomime785) lib=$nomime/nomime-7.85.0/lib/libcurl.so.4; inc=$nomime/nomime-7.85.0/include; probe_node=$GUIX_NODE; nofiles=1 ;;
    nomime823) lib=$nomime/nomime-8.23.0/lib/libcurl.so.4; inc=$nomime/nomime-8.23.0/include; probe_node=$GUIX_NODE; nofiles=1 ;;
    *) echo "lanes-in-docker: no lane $lane" >&2; exit 2 ;;
  esac
  case ${PROBE_NODE:-} in node20) probe_node=$node20 ;; guix) probe_node=$GUIX_NODE ;; esac
  env_line="CHEZ=$chez CHEZ_CURL_LIBCURL=$lib CC=gcc${inc:+ C_INCLUDE_PATH=$inc}"
  case $MODE in
    probe)
      vg=
      [ -z "$VALGRIND" ] || vg="VALGRIND=/w/logs/$VALGRIND-$lane.vg"
      echo "== lane $lane: probe in /w/$TREE, $env_line NODE=$probe_node ${nofiles:+NOFILES=1} $vg"
      su "$lane_user" -c "cd /w/$TREE && env $env_line NODE=$probe_node ${nofiles:+NOFILES=1} $vg sh m8s3/run-probe.sh $lane $ARGS" 2>&1 || echo "lane $lane: probe exit $?"
      ;;
    test)
      w=/work/$lane
      rm -rf "$w"
      mkdir -p "$w"
      (cd "/w/$TREE" && tar cf - --exclude=./build --exclude=./m8s3 .) | (cd "$w" && tar xf -)
      chown -R "$lane_user" "$w"
      log=/w/logs/test-${TAG:-run}-$lane.log
      suites_line=
      [ -z "$SUITES" ] || suites_line="SUITES='$SUITES'"
      echo "== lane $lane: make test in a copy of /w/$TREE, $env_line NODE=$node20 $suites_line"
      start=$(date +%s)
      # check-seam alone first, its verdict logged: the prototype imports
      # current-directory, which its allowlist lacks, and make test would
      # otherwise run no suite; then make test with check-seam taken as made
      su "$lane_user" -c "cd $w && env $env_line make --no-print-directory deps check-seam; echo check-seam-exit=\$?" > "$log" 2>&1 || true
      if su "$lane_user" -c "cd $w && env $env_line NODE=$node20 make --no-print-directory -o check-seam deps test $suites_line" >> "$log" 2>&1; then
        echo "lane $lane: pass ($(( $(date +%s) - start )) s)"
      else
        echo "lane $lane: FAIL ($(( $(date +%s) - start )) s)"
      fi
      grep -E '^test: (pass|FAIL|HUNG|ran)' "$log" | sed "s|^|  [$lane] |" || true
      chown "$HOST_UID:$HOST_GID" "$log"
      ;;
    *) echo "lanes-in-docker: no mode $MODE" >&2; exit 2 ;;
  esac
done
chown -R "$HOST_UID:$HOST_GID" /w/logs
