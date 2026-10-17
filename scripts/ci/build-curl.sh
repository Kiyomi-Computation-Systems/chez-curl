#!/bin/sh
# scripts/ci/build-curl.sh PREFIX [EXTRA-CONFIGURE-FLAGS...]
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
# pinned below before anything is unpacked. Afterwards it asks the installed
# curl-config for the version and the TLS backend, and fails unless they are
# the floor and OpenSSL, and unless the library and the header the lanes name
# are there.
#
# EXTRA-CONFIGURE-FLAGS go to ./configure after --prefix, --with-openssl and
# --disable-static. PREFIX must be an absolute path. Nothing is installed
# outside PREFIX.
#
# Changing the floor is a reviewed change: fetch the release tarball, verify
# its signature, and add its sha256 to tarball_sha256 below. A floor with no
# sha256 here fails.
set -eu

usage() {
  echo "usage: build-curl.sh PREFIX [EXTRA-CONFIGURE-FLAGS...]" >&2
  exit 2
}

[ "$#" -ge 1 ] || usage
prefix=$1
shift 1

case $prefix in
  /?*) ;;
  *) echo "build-curl.sh: PREFIX must be an absolute path, not '$prefix'" >&2; exit 2 ;;
esac

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
version=$(sh "$here/floor.sh" libcurl) || {
  echo "build-curl.sh: no libcurl floor to build" >&2
  exit 1
}

# tarball_sha256 VERSION: the sha256 of curl-VERSION.tar.xz, the release
# tarball, which https://curl.se/download/ and curl's GitHub release serve
# alike. Each sum here was taken from a tarball whose detached signature
# (curl-VERSION.tar.xz.asc) verifies against Daniel Stenberg's release key,
# 27EDEAF22F3ABCEB50DB9A125CC908FDB71E12C2. Fails for a version with no sum.
tarball_sha256() {
  case $1 in
    7.85.0) echo 88b54a6d4b9a48cb4d873c7056dcba997ddd5b7be5a2d537a4acb55c20b04be6 ;;
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

./configure --prefix="$prefix" --with-openssl --disable-static "$@"
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
for needed in "$prefix/lib/libcurl.so.4" "$prefix/include/curl/curl.h"; do
  if [ ! -e "$needed" ]; then
    echo "build-curl.sh: the install holds no $needed" >&2
    exit 1
  fi
done
echo "build-curl.sh: curl $version built into $prefix ($backends)"
