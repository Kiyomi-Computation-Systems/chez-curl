#!/bin/sh
# Spike E1, inside Docker ubuntu:24.04, from docker.sh. Not for the host.
#
#   in-docker.sh [SET...]
#
# SET is one of run.sh's sets; with none, collect, wake, deliver, lookup,
# interrupt, load-race and collect-once.
#
# 1. Installs packaging/debian-prereqs.txt, as each CI lane does, and
#    netcat-openbsd, and prints the versions of the libcurls and their TLS
#    libraries.
# 2. Builds the floors' Chez and libcurl into /src/build/e1/ci through
#    scripts/ci/build-chez.sh and build-curl.sh, unless they are there.
# 3. Points /etc/resolv.conf at 127.0.0.1, where nc reads every query and
#    answers none, and shows that a lookup now stalls.
# 4. Runs run.sh on each lane with the sets, and the guix-store lane with
#    lookup when it is among them, then gives build/e1 back to the host's
#    user.
set -eu
sets=${*:-collect wake deliver lookup interrupt load-race collect-once}
export DEBIAN_FRONTEND=noninteractive
cd /src
pkgs=$(grep -v -e '^#' -e '^$' packaging/debian-prereqs.txt | tr '\n' ' ')
[ -n "$pkgs" ] || { echo "in-docker.sh: no packages" >&2; exit 1; }
apt-get update -qq >/dev/null
# shellcheck disable=SC2086
apt-get install -y -qq --no-install-recommends $pkgs netcat-openbsd >/dev/null 2>&1

dpkg-query -W -f 'package ${Package} ${Version}\n' libcurl4t64 libcurl3t64-gnutls libssl3t64 libgnutls30t64

ci=/src/build/e1/ci
mkdir -p "$ci"
if [ ! -x "$ci/chez-threads/bin/scheme" ]; then
  sh scripts/ci/build-chez.sh "$ci/chez-threads" >"$ci/build-chez.log" 2>&1 \
    || { tail -30 "$ci/build-chez.log"; exit 1; }
fi
if [ ! -f "$ci/curl-floor/lib/libcurl.so.4" ]; then
  sh scripts/ci/build-curl.sh "$ci/curl-floor" >"$ci/build-curl.log" 2>&1 \
    || { tail -30 "$ci/build-curl.log"; exit 1; }
fi

echo "nameserver 127.0.0.1" >/etc/resolv.conf
nc -lku 127.0.0.1 53 >/dev/null 2>&1 &
sleep 1
t0=$(date +%s%N)
getent hosts slow-name.example.com && found=yes || found=no
t1=$(date +%s%N)
echo "stall check: getent hosts slow-name.example.com found $found after $(( (t1 - t0) / 1000000 )) ms"

e1=.plans/research/e1
arch=$(uname -m)-linux-gnu
export NODE="$GUIX_NODE"
export CHEZ="$ci/chez-threads/bin/scheme"
for lane in "floor:$ci/curl-floor/lib/libcurl.so.4" \
            "ubuntu-openssl:/usr/lib/$arch/libcurl.so.4" \
            "ubuntu-gnutls:/usr/lib/$arch/libcurl-gnutls.so.4"; do
  # shellcheck disable=SC2086
  CHEZ_CURL_LIBCURL=${lane#*:} sh "$e1/run.sh" "${lane%%:*}" $sets
done
case " $sets " in
  *" lookup "*) CHEZ="$GUIX_CHEZ" CHEZ_CURL_LIBCURL="$GUIX_LIBCURL" sh "$e1/run.sh" guix-store lookup ;;
esac
chown -R "$HOST_UID:$HOST_GID" /src/build/e1
