set -eu
export DEBIAN_FRONTEND=noninteractive
rm -f /etc/apt/apt.conf.d/docker-clean
cp -R /aptcache/lists/. /var/lib/apt/lists/
cp /aptcache/archives/*.deb /var/cache/apt/archives/
apt-get install -y -qq --no-download --no-install-recommends $PKGS >/dev/null 2>&1
mkdir -p /work && (cd /w && tar cf - --exclude=./build .) | (cd /work && tar xf -)
cd /work
ci=/src/build/e1/ci
export CHEZ=$ci/chez-threads/lib/csv10.4.0/ta6le/scheme
export CHEZ_CURL_LIBCURL=$ci/curl-floor/lib/libcurl.so.4
export NODE=/src/build/verify/m3s2/node20/node
export PATH=$(dirname $NODE):$PATH
make deps >/dev/null 2>&1 || true
ls -la /sys/kernel/mm/transparent_hugepage/enabled || true
mkdir -p /tmp/zz
$CHEZ --libdirs src:tests:build/scheme-libs --program tests/zz-review-wire.sps /tmp/zz
