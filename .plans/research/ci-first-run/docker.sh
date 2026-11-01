#!/bin/sh
# The CI-fix PR's stand-ins for CI's lanes (2026-11-01), in Docker
# ubuntu:24.04, the runner's image. Run on the host, from the repository's
# root:
#   sh build/cifix/docker.sh LANE TAG COMMAND...
# LANE: floor (curl 7.85.0 and its headers), current (curl 8.23.0 and its
# headers), main (Ubuntu's libcurl4t64, by discovery) or gnutls. NODE_BIN
# picks the Node: node22 (22.23.4, libuv 1.51.0, the runner's own; the
# default) or node20 (20.10.0, libuv 1.46.0). COMMAND runs as a user of the
# host's uid in a copy of the tree under /work, with CHEZ, NODE,
# CHEZ_CURL_LIBCURL and C_INCLUDE_PATH set for the lane; its output goes to
# build/cifix/out/TAG.log. MUT_FILE and MUT_SED, when set, run sed -i
# MUT_SED on that file of the copy first, and refuse a sed that changes
# nothing. One container, with --rm; no other is touched.
set -eu
[ "$#" -ge 3 ] || { echo "usage: docker.sh LANE TAG COMMAND..." >&2; exit 2; }
lane=$1 tag=$2
shift 2
root=$PWD
[ -f "$root/build/cifix/docker.sh" ] || { echo "docker.sh: run it from the repository's root" >&2; exit 2; }
case ${NODE_BIN:-node22} in
  node22) node=/src/build/cifix/node-v22.23.4-linux-x64/bin/node ;;
  node20) node=/src/build/verify/m3s2/node20/node ;;
  *) echo "docker.sh: no NODE_BIN ${NODE_BIN}" >&2; exit 2 ;;
esac
exec docker run --rm -v "$root:/src:ro" -v "$root/build/cifix/out:/out" \
  -e LANE="$lane" -e TAG="$tag" -e NODEP="$node" -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  -e MUT_FILE="${MUT_FILE:-}" -e MUT_SED="${MUT_SED:-}" \
  ${DOCKER_ARGS:-} ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
pkgs=$(grep -v -e "^#" -e "^\$" /src/packaging/debian-prereqs.txt | tr "\n" " ")
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends $pkgs >/dev/null 2>&1
user=$(getent passwd "$HOST_UID" | cut -d: -f1)
if [ -z "$user" ]; then useradd -m -u "$HOST_UID" lane; user=lane; fi
arch=$(uname -m)-linux-gnu
ci=/src/build/e1/ci
cur=/src/build/verify/c823/lane1/curl-current
case $LANE in
  floor) envs="CHEZ_CURL_LIBCURL=$ci/curl-floor/lib/libcurl.so.4 C_INCLUDE_PATH=$ci/curl-floor/include" ;;
  current) envs="CHEZ_CURL_LIBCURL=$cur/lib/libcurl.so.4 C_INCLUDE_PATH=$cur/include" ;;
  main) envs= ;;
  gnutls) envs="CHEZ_CURL_LIBCURL=/usr/lib/$arch/libcurl-gnutls.so.4" ;;
  *) echo "docker.sh: no lane $LANE"; exit 2 ;;
esac
w=/work/tree
mkdir -p $w
(cd /src && tar cf - --exclude=./.git --exclude=./build --exclude=./.claude .) | (cd $w && tar xf -)
mkdir -p $w/build/cifix && cp -r /src/build/cifix/*.sps $w/build/cifix/ 2>/dev/null || true
if [ -n "$MUT_FILE" ]; then
  cp $w/$MUT_FILE /work/mut.orig
  sed -i "$MUT_SED" $w/$MUT_FILE
  if cmp -s /work/mut.orig $w/$MUT_FILE; then echo "docker.sh: the mutant changed nothing" > /out/$TAG.log; exit 1; fi
fi
chown -R "$user" /work
sysctl net.ipv4.tcp_rmem net.ipv4.tcp_wmem net.core.rmem_max net.core.wmem_max net.core.rmem_default net.core.wmem_default net.ipv4.tcp_moderate_rcvbuf > /out/$TAG.log 2>&1 || true
echo "lane $LANE node $($NODEP --version) envs $envs" >> /out/$TAG.log
[ -n "$MUT_FILE" ] && { echo "mutant: $MUT_FILE: $MUT_SED"; diff /work/mut.orig $w/$MUT_FILE || true; } >> /out/$TAG.log
su "$user" -c "cd $w && export CHEZ=$ci/chez-threads/bin/scheme NODE=$NODEP CC=gcc $envs && $*" >> /out/$TAG.log 2>&1 && echo "exit 0" >> /out/$TAG.log || echo "exit $?" >> /out/$TAG.log
chown "$HOST_UID:$HOST_GID" /out/$TAG.log
' docker "$@"
