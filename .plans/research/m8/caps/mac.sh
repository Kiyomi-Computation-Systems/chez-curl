#!/bin/sh
# M8's header-caps probe on the Mac (2026-11-06): Apple's libcurl 8.7.1
# (/usr/lib/libcurl.4.dylib, by cc's -lcurl and the SDK's headers), under
# SecureTransport, as make test selects it. Run from the repository's root:
#   sh .plans/research/m8/caps/mac.sh
# It needs nothing but the repository, cc, openssl (LibreSSL's is fine, for
# tests/make-test-pki.sh) and Node 20 or later: NODE, else `asdf which node`
# (the asdf shim writes to stderr on every call), else node on PATH.
#
# It runs run.sh twice, every case (count, bytes, toward, walk), a few
# minutes each. The probe sets CURLMOPT_PIPELINING 0 on 8.7.0 and 8.7.1, as
# chez-curl's engine does (ADR-0030, amended), and says so on any failure.
# Each run's lines go to a log of their own, prefixed by its lane:
# .plans/research/m8/caps/results/mac-8.7.1-1.log ([mac-8.7.1-1]) and
# mac-8.7.1-2.log ([mac-8.7.1-2]), overwritten if there; it prints the paths
# at the end. run.sh makes its temporary directory under $TMPDIR and removes
# it. Case 5's Valgrind run and case 6 are lane X's alone (Linux).
set -u
[ "$(uname -s)" = Darwin ] || { echo "mac.sh: this is the Mac's script; Linux lanes run run.sh" >&2; exit 2; }
d=.plans/research/m8/caps
[ -f $d/run.sh ] || { echo "mac.sh: run it from the repository's root" >&2; exit 2; }
if [ -z "${NODE:-}" ]; then
  NODE=$(asdf which node 2>/dev/null) || NODE=
  [ -n "$NODE" ] || NODE=$(command -v node) || NODE=
fi
[ -n "$NODE" ] && [ -x "$NODE" ] || { echo "mac.sh: no node found; set NODE to a Node 20 or later binary" >&2; exit 1; }
export NODE
CC=${CC:-cc}
export CC
unset CURL_LIB CURL_INCLUDE CASES PROBE_MODES WALK_NS WALK_ROUNDS PROBE_VALGRIND
mkdir -p "$d/results"
for k in 1 2; do
  log=$d/results/mac-8.7.1-$k.log
  echo "mac.sh: run $k of 2, a few minutes; writing $log"
  {
    echo "mac.sh start $(date -u +%Y-%m-%dT%H:%M:%SZ) macOS $(sw_vers -productVersion 2>/dev/null) $(uname -m) node=$NODE cc=$(command -v "$CC")"
    # /usr/lib/libcurl.4.dylib is in the dyld shared cache, not on disk, from
    # macOS 11; the probe's --version line names the libcurl it loaded.
    /usr/bin/curl --version 2>&1 | sed 's/^/mac.sh system curl: /'
    sh $d/run.sh "mac-8.7.1-$k"; echo "mac.sh run.sh mac-8.7.1-$k exit=$?"
    echo "mac.sh end $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$log" 2>&1
  echo "mac.sh: $(grep -c ' exit=0$' "$log") lines read exit=0 in $log; want 5, run.sh's and its 4 cases'"
done
echo "mac.sh: done; the logs are $PWD/$d/results/mac-8.7.1-1.log and -2.log"
echo "mac.sh: a global gitignore of results/ needs: git add -f $d/results/mac-8.7.1-1.log $d/results/mac-8.7.1-2.log"
