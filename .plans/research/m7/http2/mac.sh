#!/bin/sh
# M7's HTTP/2 probe on the Mac (2026-11-02): Apple's libcurl 8.7.1
# (/usr/lib/libcurl.4.dylib, by cc's -lcurl and the SDK's headers), under
# SecureTransport, as make test selects it. Run from the repository's root:
#   sh .plans/research/m7/http2/mac.sh
# It needs nothing but the repository, cc, openssl (LibreSSL's is fine, for
# tests/make-test-pki.sh) and Node 20 or later: NODE, else `asdf which node`
# (the asdf shim writes to stderr on every call), else node on PATH.
#
# It runs run.sh four times, about 40 s each: twice as libcurl comes, and
# twice with PROBE_NO_MULTIPLEX=1, CURLMOPT_PIPELINING 0, which is what
# chez-curl's engine sets on 8.7.0 and 8.7.1 (ADR-0030, amended). Every line
# goes to one log, each run's lines prefixed by its lane: [mac-8.7.1],
# [mac-8.7.1-2], [mac-8.7.1-nomux], [mac-8.7.1-nomux-2]. The log is
# .plans/research/m7/http2/results/mac-8.7.1.log, overwritten if there; it
# prints the path at the end. run.sh makes its temporary directory under
# $TMPDIR and removes it.
set -u
[ "$(uname -s)" = Darwin ] || { echo "mac.sh: this is the Mac's script; Linux lanes run run.sh" >&2; exit 2; }
d=.plans/research/m7/http2
[ -f $d/run.sh ] || { echo "mac.sh: run it from the repository's root" >&2; exit 2; }
if [ -z "${NODE:-}" ]; then
  NODE=$(asdf which node 2>/dev/null) || NODE=
  [ -n "$NODE" ] || NODE=$(command -v node) || NODE=
fi
[ -n "$NODE" ] && [ -x "$NODE" ] || { echo "mac.sh: no node found; set NODE to a Node 20 or later binary" >&2; exit 1; }
export NODE
CC=${CC:-cc}
export CC
unset CURL_LIB CURL_INCLUDE CASES PROBE_NO_MULTIPLEX
mkdir -p "$d/results"
log=$d/results/mac-8.7.1.log
echo "mac.sh: about 3 minutes; writing $log"
{
  echo "mac.sh start $(date -u +%Y-%m-%dT%H:%M:%SZ) macOS $(sw_vers -productVersion 2>/dev/null) $(uname -m) node=$NODE cc=$(command -v "$CC")"
  # /usr/lib/libcurl.4.dylib is in the dyld shared cache, not on disk, from
  # macOS 11; the probe's --version line names the libcurl it loaded.
  /usr/bin/curl --version 2>&1 | sed 's/^/mac.sh system curl: /'
  sh $d/run.sh mac-8.7.1; echo "mac.sh run.sh mac-8.7.1 exit=$?"
  sh $d/run.sh mac-8.7.1-2; echo "mac.sh run.sh mac-8.7.1-2 exit=$?"
  PROBE_NO_MULTIPLEX=1 sh $d/run.sh mac-8.7.1-nomux; echo "mac.sh run.sh mac-8.7.1-nomux exit=$?"
  PROBE_NO_MULTIPLEX=1 sh $d/run.sh mac-8.7.1-nomux-2; echo "mac.sh run.sh mac-8.7.1-nomux-2 exit=$?"
  echo "mac.sh end $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$log" 2>&1
echo "mac.sh: done; the log is $PWD/$log"
echo "mac.sh: $(grep -c ' exit=0$' "$log") lines read exit=0; want 28, 4 runs of run.sh and 24 of the probe"
echo "mac.sh: a global gitignore of results/ needs: git add -f $log"
