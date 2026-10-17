#!/bin/sh
# scripts/ci/build-chez.sh PREFIX [--nothreads]
#
# Builds Chez Scheme at its floor from the release tarball and installs it into
# PREFIX, for .github/workflows/ci.yml (ADR-0001: apt's Chez is 9.5.8, below
# the floor, so CI builds the floor itself). It takes no version: the floor is
# the one packaging/floors.sexp holds (ADR-0016), read by scripts/ci/floor.sh,
# which fails closed on a file that does not give exactly one well-formed Chez
# version. Nothing a workflow says, an env key or a matrix value, can change
# it. The tarball is checked against the sha256 pinned below before anything is
# unpacked. Threaded by default, as chez-curl needs; --nothreads builds the
# Chez the non-threaded lane imports the libraries on. Afterwards it asks the
# installed scheme for its version and (threaded?), and fails unless they are
# the floor and what was asked for: a build that came out other than it was
# configured is no build.
#
# PREFIX must be an absolute path. Run it once for a PREFIX: it installs over
# what is there. Nothing is installed outside PREFIX.
#
# Changing the floor is a reviewed change: fetch the release tarball, compare
# its sha256 with the digest the GitHub releases API lists for the asset, and
# add it to tarball_sha256 below. A floor with no sha256 here fails.
set -eu

usage() {
  echo "usage: build-chez.sh PREFIX [--nothreads]" >&2
  exit 2
}

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
prefix=$1
threads=--threads
want=yes
if [ "$#" -eq 2 ]; then
  [ "$2" = "--nothreads" ] || usage
  threads=--nothreads
  want=no
fi

case $prefix in
  /?*) ;;
  *) echo "build-chez.sh: PREFIX must be an absolute path, not '$prefix'" >&2; exit 2 ;;
esac

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
version=$(sh "$here/floor.sh" chez) || {
  echo "build-chez.sh: no Chez floor to build" >&2
  exit 1
}

# tarball_sha256 VERSION: the sha256 of csvVERSION.tar.gz, the release
# tarball. Chez publishes no checksum file; each sum here is that of the
# downloaded release asset, and equals the digest the GitHub releases API lists
# for the asset. Fails for a version with no sum.
tarball_sha256() {
  case $1 in
    10.4.0) echo 54d0d19e4cd51878f88fb4b7ddb44079be6ca12bcf14163f8ea53cbcb4633385 ;;
    *) return 1 ;;
  esac
}

sum=$(tarball_sha256 "$version") || {
  echo "build-chez.sh: no sha256 is pinned for Chez $version: fetch its release tarball, check it, and add the sum to tarball_sha256 in this script" >&2
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

work=$(mktemp -d "${TMPDIR:-/tmp}/build-chez.XXXXXX")
trap 'rm -rf "$work"' EXIT

tarball=$work/csv$version.tar.gz
curl -fsSL --retry 3 -o "$tarball" \
  "https://github.com/cisco/ChezScheme/releases/download/v$version/csv$version.tar.gz"

got=$(sha256_of "$tarball")
if [ "$got" != "$sum" ]; then
  echo "build-chez.sh: csv$version.tar.gz has sha256 $got, but this script pins $sum" >&2
  exit 1
fi

tar xzf "$tarball" -C "$work"
cd "$work/csv$version"

# --disable-x11 --disable-curses: the expeditor, Chez's line editor, then needs
# no X11 or curses headers, and chez-curl only ever runs Chez with --program
# (packaging/debian-prereqs.txt). The make is serial: a parallel make races the
# bootstrap.
./configure "$threads" --disable-x11 --disable-curses --installprefix="$prefix"
make
make install

# Ask what was built. scheme-version-number answers three values, major, minor
# and patch; a threaded build answers #t to (threaded?).
probe=$work/probe.ss
cat >"$probe" <<'EOF'
(let-values (((major minor patch) (scheme-version-number)))
  (display (list major minor patch (if (threaded?) 'yes 'no))))
EOF
asked=$("$prefix/bin/scheme" --script "$probe")
expected="($(printf '%s' "$version" | tr . ' ') $want)"
if [ "$asked" != "$expected" ]; then
  echo "build-chez.sh: the installed $prefix/bin/scheme answers $asked, but (scheme-version-number) and (threaded?) should answer $expected" >&2
  exit 1
fi
echo "build-chez.sh: Chez $version built $threads into $prefix: $asked"
