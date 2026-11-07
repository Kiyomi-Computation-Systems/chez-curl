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
node20=/src/build/verify/m3s2/node20/node
current=/src/build/verify/c823/lane1/curl-current
arch=$(uname -m)-linux-gnu
for lane in "$@"; do
  case $lane in
    openssl) lib=/usr/lib/$arch/libcurl.so.4; inc= ; probe_node=$GUIX_NODE ;;
    gnutls) lib=/usr/lib/$arch/libcurl-gnutls.so.4; inc= ; probe_node=$GUIX_NODE ;;
    floor) lib=$ci/curl-floor/lib/libcurl.so.4; inc=$ci/curl-floor/include; probe_node=$node20 ;;
    current) lib=$current/lib/libcurl.so.4; inc=$current/include; probe_node=$GUIX_NODE ;;
    *) echo "lanes-in-docker: no lane $lane" >&2; exit 2 ;;
  esac
  case ${PROBE_NODE:-} in node20) probe_node=$node20 ;; guix) probe_node=$GUIX_NODE ;; esac
  env_line="CHEZ=$chez CHEZ_CURL_LIBCURL=$lib CC=gcc${inc:+ C_INCLUDE_PATH=$inc}"
  case $MODE in
    probe)
      echo "== lane $lane: probe in /w/$TREE, $env_line NODE=$probe_node"
      su "$lane_user" -c "cd /w/$TREE && env $env_line NODE=$probe_node ${SERVER:+SERVER=$SERVER} ${H2_LIMITS:+H2_LIMITS=$H2_LIMITS} sh m8s2/run-probe.sh $lane m8s2/engine-probe.sps $ARGS" 2>&1 || echo "lane $lane: probe exit $?"
      ;;
    cost)
      vg=
      [ -z "$VALGRIND" ] || vg="VALGRIND=/w/logs/$VALGRIND-$lane.vg"
      echo "== lane $lane: cost in /w/$TREE, $env_line NODE=$node20 $vg"
      su "$lane_user" -c "cd /w/$TREE && env $env_line NODE=$node20 $vg sh m8s2/run-probe.sh $lane m8s2/cost.sps $ARGS" 2>&1 || echo "lane $lane: cost exit $?"
      ;;
    test)
      w=/work/$lane
      rm -rf "$w"
      mkdir -p "$w"
      (cd "/w/$TREE" && tar cf - --exclude=./build --exclude=./m8s2 .) | (cd "$w" && tar xf -)
      chown -R "$lane_user" "$w"
      log=/w/logs/test-${TAG:-run}-$lane.log
      suites_line=
      [ -z "$SUITES" ] || suites_line="SUITES='$SUITES'"
      echo "== lane $lane: make test in a copy of /w/$TREE, $env_line NODE=$node20 $suites_line"
      start=$(date +%s)
      if su "$lane_user" -c "cd $w && env $env_line NODE=$node20 make --no-print-directory deps test $suites_line" > "$log" 2>&1; then
        echo "lane $lane: pass ($(( $(date +%s) - start )) s)"
      else
        echo "lane $lane: FAIL ($(( $(date +%s) - start )) s)"
      fi
      grep -E '^test: (pass|FAIL|HUNG|ran)' "$log" | sed "s|^|  [$lane] |" || true
      chown "$HOST_UID:$HOST_GID" "$log"
      ;;
    memory)
      w=/work/$lane
      rm -rf "$w"
      mkdir -p "$w"
      (cd "/w/$TREE" && tar cf - --exclude=./build --exclude=./m8s2 .) | (cd "$w" && tar xf -)
      chown -R "$lane_user" "$w"
      log=/w/logs/memory-${TAG:-run}-$lane.log
      echo "== lane $lane: make test-memory in a copy of /w/$TREE, $env_line NODE=$node20 MEMORY_SUITES='$SUITES'"
      start=$(date +%s)
      # VALGRIND is the Makefile's own variable, the Valgrind to run: the
      # harness's, the cost mode's log name, is unset for it.
      if su "$lane_user" -c "cd $w && env -u VALGRIND -u SUITES -u TAG $env_line NODE=$node20 make --no-print-directory deps test-memory MEMORY_SUITES='$SUITES'" > "$log" 2>&1; then
        echo "lane $lane memory: pass ($(( $(date +%s) - start )) s)"
      else
        echo "lane $lane memory: FAIL ($(( $(date +%s) - start )) s)"
      fi
      grep -E '^test-memory: (pass|FAIL|HUNG|ran)' "$log" | sed "s|^|  [$lane] |" || true
      cp "$w"/build/memory/*.valgrind /w/logs/ 2>/dev/null || true
      chown "$HOST_UID:$HOST_GID" "$log"
      ;;
    *) echo "lanes-in-docker: no mode $MODE" >&2; exit 2 ;;
  esac
done
chown -R "$HOST_UID:$HOST_GID" /w/logs
