#!/bin/sh
# M7's auth probe (2026-11-02) on the maintainer's Mac: Apple's libcurl 8.7.1
# (/usr/lib/libcurl.4.dylib, by cc's -lcurl and the SDK's headers), twice.
# Run from the repository's root:
#   sh .plans/research/m7/auth/mac.sh
# It needs cc (the Xcode command line tools), Node 20 or later (asdf's, by
# `asdf which node`, unless NODE is set) and openssl on PATH
# (tests/make-test-pki.sh; LibreSSL's /usr/bin/openssl serves). Each run's
# log goes to .plans/research/m7/auth/results/mac-8.7.1-N.log, and the script
# prints where; the Mac's git ignores results/ globally, so add them with
# `git add -f`. A run takes about two to four minutes: group E holds some
# HTTP/2 transfers to its 10 s bound.
# run.sh sets CURL_SSL_BACKEND=secure-transport, as make test does, since
# Apple's LibreSSL falls back to the keychain when a CA file fails.
set -u
d=.plans/research/m7/auth
[ -f $d/run.sh ] || { echo "mac.sh: run it from the repository's root" >&2; exit 2; }
[ "$(uname -s)" = Darwin ] || { echo "mac.sh: this is for macOS; Linux lanes run by run.sh and docker.sh" >&2; exit 2; }
if [ -z "${NODE:-}" ]; then
  NODE=$(asdf which node 2>/dev/null) || { echo "mac.sh: no node from asdf; set NODE" >&2; exit 1; }
fi
export NODE
"$NODE" --version > /dev/null 2>&1 || { echo "mac.sh: $NODE does not run" >&2; exit 1; }
# A version manager's shim may write to stderr on every call (AGENTS.md):
# NODE is the real binary, not the shim.
mkdir -p "$d/results"
for n in 1 2; do
  log=$d/results/mac-8.7.1-$n.log
  {
    echo "[mac] sw_vers $(sw_vers -productVersion) $(sw_vers -buildVersion) uname $(uname -srm)"
    echo "[mac] libcurl $(otool -L /usr/lib/libcurl.4.dylib 2>/dev/null | sed -n 2p | tr -s ' \t' ' ')"
    echo "[mac] openssl $(openssl version 2>&1)"
    sh $d/run.sh mac-8.7.1 < /dev/null 2>&1
    echo "[mac] run.sh exit=$?"
  } > "$log"
  echo "mac.sh: run $n's log is $log ($(wc -l < "$log" | tr -d ' ') lines; $(grep -c ' row ' "$log") rows; $(grep -c 'exit=0' "$log") 'exit=0' lines, 9 expected)"
done
