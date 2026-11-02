#!/bin/sh
# M7's cookie probe (2026-11-02) on the maintainer's Mac, against Apple's
# libcurl 8.7.1 (/usr/lib/libcurl.4.dylib, by -lcurl and the SDK's headers),
# twice. Run from the repository's root:
#   NODE="$(asdf which node)" sh .plans/research/m7/cookies/mac.sh
# NODE defaults to asdf's node, else the first node on PATH; CC, to cc.
# It writes both runs' output to one log under $TMPDIR, prints the log's
# path, and touches nothing else outside its own mktemp directories.
# The probe's file watch is Linux's alone (an interposer of fopen and open);
# on macOS the evidence that no case touched a file is each case's empty
# working directory, and its stdin, stdout and stderr checks.
set -u
[ "$(uname -s)" = Darwin ] || { echo "mac.sh: this is the Mac's script; Linux lanes run run.sh" >&2; exit 2; }
[ -f .plans/research/m7/cookies/run.sh ] || { echo "mac.sh: run it from the repository's root" >&2; exit 2; }
if [ -z "${NODE:-}" ]; then
  NODE=$(asdf which node 2>/dev/null || command -v node)
fi
[ -n "$NODE" ] && [ -x "$NODE" ] || { echo "mac.sh: no node; set NODE" >&2; exit 2; }
export NODE
CC=${CC:-cc}
export CC
log=$(mktemp "${TMPDIR:-/tmp}/m7-cookies-mac.XXXXXX") || exit 1
{
  echo "mac.sh $(date -u '+%Y-%m-%dT%H:%M:%SZ') libcurl $(ls -l /usr/lib/libcurl.4.dylib 2>&1)"
  echo "mac.sh sw_vers $(sw_vers -productVersion) build $(sw_vers -buildVersion) cc $("$CC" --version 2>&1 | head -1)"
  sh .plans/research/m7/cookies/run.sh mac-8.7.1
  echo "mac.sh run 1 exit=$?"
  sh .plans/research/m7/cookies/run.sh mac-8.7.1-run2
  echo "mac.sh run 2 exit=$?"
} > "$log" 2>&1
echo "mac.sh: the log is $log ($(wc -l < "$log" | tr -d ' ') lines)"
echo "mac.sh: copy it to .plans/research/m7/cookies/results/mac-8.7.1.log (git add -f: results/ is ignored there)"
