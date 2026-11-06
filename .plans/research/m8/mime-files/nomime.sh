#!/bin/sh
# M8's mime-files probe, case 8 (2026-11-06): a libcurl configured without
# mime. Run on the host, from the repository's root, after docker.sh has
# fetched the apt cache once:
#   sh .plans/research/m8/mime-files/nomime.sh > .plans/research/m8/mime-files/results/nomime-N.log 2>&1
#
# It builds, once each, curl 7.85.0 (the floor) and 8.23.0 (the C lane's
# version) with scripts/ci/build-curl.sh, unchanged, and its one extra
# ./configure flag, --disable-mime, into build/m8/mime-files/nomime-VERSION:
#   build-curl.sh        PREFIX --disable-mime   (7.85.0, from floors.sexp)
#   build-curl.sh --current PREFIX --disable-mime (8.23.0)
# in Docker ubuntu:24.04 with --network none, pinned to CPUs 6-11. The
# script fetches its tarball with curl; here a stand-in curl, written into
# the container's own /tmp and first on PATH, copies the tarball of that name
# from build/verify/current (mounted read-only), and build-curl.sh checks it
# against the sha256 it pins, as it checks a download. Each build's whole
# output goes to build/m8/mime-files/nomime-build-VERSION.log, which the
# host copies into results/ once the container ends.
#
# Then, for each build: its curl-config answers, the configure lines that
# name mime and the form API, the curl_mime_ and curl_formadd symbols its
# libcurl.so.4 defines (nm -D), and run.sh on it, as the caller's uid, with
# CASES "D-calls R-when", against its own headers.
set -eu
[ "$#" -eq 0 ] || { echo "usage: nomime.sh" >&2; exit 2; }
[ -f .plans/research/m8/mime-files/run.sh ] || { echo "nomime.sh: run it from the repository's root" >&2; exit 2; }
root=$PWD
out=$root/build/m8/mime-files
cache=$out/apt
[ -f "$cache/fetched" ] || { echo "nomime.sh: no apt cache; run docker.sh first" >&2; exit 1; }
for f in build/verify/current/curl-7.85.0.tar.xz build/verify/current/curl-8.23.0.tar.xz; do
  [ -f "$f" ] || { echo "nomime.sh: no $f" >&2; exit 1; }
done
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
node=$(scripts/guix-env sh -c 'command -v node' < /dev/null)
case $node in /gnu/store/*) ;; *) echo "nomime.sh: node is not in the store: '$node'" >&2; exit 1 ;; esac
pkgs="build-essential libcurl4-openssl-dev libcurl3t64-gnutls ca-certificates openssl valgrind libssl-dev zlib1g-dev libnghttp2-dev xz-utils"
docker run --rm --network none --cpuset-cpus 6-11 -v "$root:$root:ro" -v "$out:$out" -v /gnu/store:/gnu/store:ro \
  -v "$cache:/aptcache:ro" -v "$root/build/verify/current:/tarballs:ro" -e GUIX_NODE="$node" -e ROOT="$root" -e OUT="$out" \
  -e PKGS="$pkgs" -e HOSTUID="$(id -u)" -e HOSTGID="$(id -g)" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
echo "network interfaces: $(ls /sys/class/net | tr "\n" " ")"
rm -f /etc/apt/apt.conf.d/docker-clean
cp -R /aptcache/lists/. /var/lib/apt/lists/
cp /aptcache/archives/*.deb /var/cache/apt/archives/
apt-get install -y -qq --no-download --no-install-recommends $PKGS >/dev/null 2>&1
dpkg-query -W -f "package \${Package} \${Version}\n" libssl-dev zlib1g-dev libnghttp2-dev gcc || true
mkdir -p /tmp/shim
cat > /tmp/shim/curl <<"EOF"
#!/bin/sh
# A stand-in for curl, as build-curl.sh calls it: curl -fsSL --retry 3 -o FILE URL.
out= url=
while [ "$#" -gt 0 ]; do
  case $1 in
    -o) out=$2; shift 2 ;;
    --retry) shift 2 ;;
    -*) shift ;;
    *) url=$1; shift ;;
  esac
done
name=${url##*/}
echo "curl stand-in: $url -> /tarballs/$name -> $out" >&2
exec cp "/tarballs/$name" "$out"
EOF
chmod +x /tmp/shim/curl
cd "$ROOT"
for spec in floor:7.85.0 current:8.23.0; do
  kind=${spec%%:*} v=${spec#*:}
  prefix=$OUT/nomime-$v
  flag=
  [ "$kind" = current ] && flag=--current
  if [ ! -f "$prefix/lib/libcurl.so.4" ]; then
    echo "build $v: scripts/ci/build-curl.sh $flag $prefix --disable-mime"
    if PATH=/tmp/shim:$PATH sh scripts/ci/build-curl.sh $flag "$prefix" --disable-mime > "$OUT/nomime-build-$v.log" 2>&1; then
      echo "build $v: exit 0"
    else
      echo "build $v: exit $? (tail follows)"; tail -30 "$OUT/nomime-build-$v.log"
    fi
  else
    echo "build $v: already built in $prefix"
  fi
  [ -f "$prefix/lib/libcurl.so.4" ] || continue
  echo "build $v: curl-config --version: $($prefix/bin/curl-config --version)"
  echo "build $v: curl-config --features: $($prefix/bin/curl-config --features | tr "\n" " ")"
  echo "build $v: curl-config --protocols: $($prefix/bin/curl-config --protocols | tr "\n" " ")"
  echo "build $v: curl-config --configure: $($prefix/bin/curl-config --configure)"
  echo "build $v: nm -D defined curl_mime_/curl_form symbols: $(nm -D --defined-only "$prefix/lib/libcurl.so.4" | awk "{print \$3}" | grep -E "^curl_(mime_|form)" | sort | tr "\n" " ")"
done
chown -R "$HOSTUID:$HOSTGID" "$OUT"/nomime-* 2>/dev/null || true
as_user() { setpriv --reuid="$HOSTUID" --regid="$HOSTGID" --clear-groups env HOME=/tmp TMPDIR=/tmp CC=gcc "$@"; }
for v in 7.85.0 8.23.0; do
  prefix=$OUT/nomime-$v
  [ -f "$prefix/lib/libcurl.so.4" ] || { echo "nomime-$v: no build, no run"; continue; }
  as_user NODE=$GUIX_NODE CASES="D-calls R-when" CURL_LIB=$prefix/lib/libcurl.so.4 CURL_INCLUDE=$prefix/include \
    sh .plans/research/m8/mime-files/run.sh nomime-$v
done'
for v in 7.85.0 8.23.0; do
  if [ -f "$out/nomime-build-$v.log" ]; then
    cp "$out/nomime-build-$v.log" .plans/research/m8/mime-files/results/nomime-build-$v.log
    echo "nomime.sh: kept the build's output as .plans/research/m8/mime-files/results/nomime-build-$v.log"
  fi
done
