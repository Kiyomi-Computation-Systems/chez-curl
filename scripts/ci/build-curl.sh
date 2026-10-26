#!/bin/sh
# scripts/ci/build-curl.sh [--current] PREFIX [EXTRA-CONFIGURE-FLAGS...]
#
# Builds curl at its floor, libcurl with OpenSSL, from its release tarball and
# installs it into PREFIX, for the floor lanes of .github/workflows/ci.yml
# (ADR-0003): the suite runs against PREFIX/lib/libcurl.so.4 with the headers
# in PREFIX/include, and the variants built with --disable-get-easy-options
# alone and with --disable-headers-api alone must each be refused as
# missing-api, one lane each (scripts/ci/expect-missing-api.sh). It takes no
# version: the floor is the one packaging/floors.sexp holds (ADR-0016), read by
# scripts/ci/floor.sh, which fails closed on a file that does not give exactly
# one well-formed libcurl version. Nothing a workflow says, an env key or a
# matrix value, can change it. The tarball is checked against the sha256
# pinned below before anything is unpacked.
#
# With --current, it builds the current libcurl instead, for the current lane
# (ADR-0020): current_version below, the one version this script pins beside
# the floor, which is no floor and so not in packaging/floors.sexp. It reads
# no floors file then, and still no argument or environment variable gives
# the version: --current chooses between the two pinned builds, and changes
# neither. Its configure flags are its own list, read against its own
# ./configure --help: curl 8 dropped options the floor's list names, and
# --enable-option-checking=fatal stops at each.
#
# The libcurl it builds does not depend on what libraries the machine has
# installed (ADR-0017). One thing ./configure still finds for itself: the
# default CA bundle and CA path, which change no feature bit but matter to
# TLS. ./configure turns on every optional library it finds, so a build that left
# it to look would answer a different curl_version_info on a machine with
# libbrotli-dev than on one without, and tests/test-drift.sps compares that
# answer with a row of tests/known-libcurls.sexp. So every optional library
# is named. OpenSSL, zlib and nghttp2 are on, and their -dev packages are in
# packaging/debian-prereqs.txt. Every other library ./configure finds, or can
# be told of, is off. RTSP stays on: tests/test-variadic.sps needs it.
#
# Three checks hold that:
#   - --enable-option-checking=fatal stops ./configure at a flag it does not
#     know, here or in EXTRA-CONFIGURE-FLAGS. It only warns otherwise, and a
#     misspelt --without-... would leave the library to be found.
#   - --with-zlib and --with-nghttp2, given bare, only look: a machine
#     without the library builds without it and says nothing. So the
#     install's curl-config --features must list libz and HTTP2, and IPv6,
#     which --enable-ipv6 sets rather than leaving to a run-time probe.
#   - It must list none of what is off: brotli, zstd, IDN, PSL, GSS-API,
#     Kerberos, SPNEGO, GSASL and HTTP3 among its features, and LDAP, LDAPS,
#     RTMP, SCP and SFTP among its protocols, which the features word the
#     drift guard compares does not show.
# Afterwards it also asks curl-config for the version and the TLS backend, and
# fails unless they are the version it built, the floor or the current one,
# and OpenSSL, and unless the library and the header the lanes name are
# there.
#
# EXTRA-CONFIGURE-FLAGS go to ./configure after --prefix and the flags above,
# so they win. PREFIX must be an absolute path. Nothing is installed outside
# PREFIX.
#
# Changing the floor, or the current version, is a reviewed change: fetch the
# release tarball, verify its signature, and add its sha256 to tarball_sha256
# below. A version with no sha256 here fails. A new version also needs its
# ./configure --help read again, for each optional library it lists, and its
# rows in every suite's version tables, which make test prints.
set -eu

usage() {
  echo "usage: build-curl.sh [--current] PREFIX [EXTRA-CONFIGURE-FLAGS...]" >&2
  exit 2
}

# current_version: the current libcurl, built with --current (ADR-0020,
# amended 2026-10-26): curl's newest release when it was pinned, on
# 2026-10-26, so that CI runs every suite against it. Raising it is a reviewed change: a verified sum below, this
# line read again against its ./configure --help, and the rows make test
# prints for every version table.
current_version=8.23.0

current=no
if [ "${1-}" = --current ]; then
  current=yes
  shift 1
fi
[ "$#" -ge 1 ] || usage
prefix=$1
shift 1

case $prefix in
  /?*) ;;
  *) echo "build-curl.sh: PREFIX must be an absolute path, not '$prefix'" >&2; exit 2 ;;
esac

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
if [ "$current" = yes ]; then
  version=$current_version
else
  version=$(sh "$here/floor.sh" libcurl) || {
    echo "build-curl.sh: no libcurl floor to build" >&2
    exit 1
  }
fi

# tarball_sha256 VERSION: the sha256 of curl-VERSION.tar.xz, the release
# tarball, which https://curl.se/download/ and curl's GitHub release serve
# alike. Each sum here was taken from a tarball whose detached signature
# (curl-VERSION.tar.xz.asc) verifies against Daniel Stenberg's release key,
# 27EDEAF22F3ABCEB50DB9A125CC908FDB71E12C2. Fails for a version with no sum.
tarball_sha256() {
  case $1 in
    7.85.0) echo 88b54a6d4b9a48cb4d873c7056dcba997ddd5b7be5a2d537a4acb55c20b04be6 ;;
    8.23.0) echo 8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5 ;;
    *) return 1 ;;
  esac
}

sum=$(tarball_sha256 "$version") || {
  echo "build-curl.sh: no sha256 is pinned for curl $version: fetch its release tarball, check it, and add the sum to tarball_sha256 in this script" >&2
  exit 1
}

# sha256_of FILE: the sha256 of FILE. sha256sum on Linux, shasum elsewhere.
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

work=$(mktemp -d "${TMPDIR:-/tmp}/build-curl.XXXXXX")
trap 'rm -rf "$work"' EXIT

tarball=$work/curl-$version.tar.xz
curl -fsSL --retry 3 -o "$tarball" "https://curl.se/download/curl-$version.tar.xz"

got=$(sha256_of "$tarball")
if [ "$got" != "$sum" ]; then
  echo "build-curl.sh: curl-$version.tar.xz has sha256 $got, but this script pins $sum" >&2
  exit 1
fi

tar xJf "$tarball" -C "$work"
cd "$work/curl-$version"

# The flags. $flags is split into words on purpose: none holds a space.
flags="--enable-option-checking=fatal --disable-static"
# On: the TLS backend, and the two libraries HTTP and its compression need.
flags="$flags --with-openssl --with-zlib --with-nghttp2"
# On: IPv6. Left to itself, ./configure decides it by trying an AF_INET6
# socket while it runs, so a build host with IPv6 sockets off would answer
# another features word.
flags="$flags --enable-ipv6"
# Off: libraries ./configure finds by itself. Each one found changes
# curl_version_info's features word (brotli, zstd, libidn2, libpsl, libgsasl)
# or its protocols (LDAP, LDAPS, librtmp, libssh2, libssh, wolfssh).
flags="$flags --without-brotli --without-zstd --without-libidn2 --without-libpsl"
flags="$flags --without-libgsasl --without-gssapi --disable-ldap --disable-ldaps"
flags="$flags --without-libssh2 --without-libssh"
if [ "$current" = yes ]; then
  # The current version's own: curl 8 has no librtmp, wolfssh, hyper or msh3
  # options, which the floor's list names, and two of its own that look for
  # a library: libuv, and Apple's IDN, macOS's alone. The HTTP/3 stacks and
  # c-ares are off, as at the floor. Read against 8.20.0's ./configure
  # --help (ADR-0020), and again against 8.23.0's: its new options,
  # apple-fast-udp, gssapi-apple, httpsig and proxy-http3, are experimental
  # features off unless asked, and look for no library (ADR-0020, amended
  # 2026-10-26).
  flags="$flags --without-libuv --without-apple-idn"
  flags="$flags --disable-ares --without-quiche --without-ngtcp2 --without-nghttp3"
else
  flags="$flags --without-librtmp --without-wolfssh"
  # Off: the ones 7.85.0's ./configure uses only when asked (--without-gssapi
  # is above): c-ares, hyper and the HTTP/3 stacks. Named anyway, so that a
  # later floor that looks for one stays off.
  flags="$flags --disable-ares --without-hyper --without-quiche --without-msh3"
  flags="$flags --without-ngtcp2 --without-nghttp3"
fi

# shellcheck disable=SC2086
./configure --prefix="$prefix" $flags "$@"
jobs=$(nproc 2>/dev/null || echo 2)
make -j"$jobs"
make install

# Ask what was built.
config=$prefix/bin/curl-config
reported=$("$config" --version)
if [ "$reported" != "libcurl $version" ]; then
  echo "build-curl.sh: $config --version says '$reported', but this is curl $version" >&2
  exit 1
fi
backends=$("$config" --ssl-backends)
case $backends in
  *OpenSSL*) ;;
  *)
    echo "build-curl.sh: $config --ssl-backends says '$backends', but this build needs OpenSSL" >&2
    exit 1
    ;;
esac
# What the install holds, one word per line: features, then protocols.
words=$("$config" --features; "$config" --protocols)
for needed in libz HTTP2 IPv6; do
  if ! printf '%s\n' "$words" | grep -qxF "$needed"; then
    echo "build-curl.sh: $config does not list $needed, which this build needs (is its -dev package installed? see packaging/debian-prereqs.txt)" >&2
    exit 1
  fi
done
for unwanted in brotli zstd IDN PSL GSS-API Kerberos SPNEGO GSASL HTTP3 \
                LDAP LDAPS RTMP SCP SFTP; do
  if printf '%s\n' "$words" | grep -qxF "$unwanted"; then
    echo "build-curl.sh: $config lists $unwanted, which this build turns off" >&2
    exit 1
  fi
done
for needed in "$prefix/lib/libcurl.so.4" "$prefix/include/curl/curl.h"; do
  if [ ! -e "$needed" ]; then
    echo "build-curl.sh: the install holds no $needed" >&2
    exit 1
  fi
done
echo "build-curl.sh: curl $version built into $prefix ($backends)"
