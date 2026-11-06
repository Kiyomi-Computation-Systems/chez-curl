#!/bin/sh
# M8's mime-files probe on the Mac (2026-11-06): Apple's libcurl 8.7.1
# (/usr/lib/libcurl.4.dylib, by cc's -lcurl and the SDK's headers), with
# CURL_SSL_BACKEND=secure-transport, as make test selects it (run.sh sets it
# unless it is set; no case here uses TLS). Run from the repository's root:
#   NODE="$(asdf which node)" sh .plans/research/m8/mime-files/mac.sh
# It needs nothing but the repository, cc and Node 20 or later: NODE, else
# `asdf which node` (the asdf shim writes to stderr on every call), else node
# on PATH.
#
# It runs run.sh twice, a minute or so each, every case of probe --list, one
# process each. Not on the Mac: the file watch, which interposes libc's open
# and stdio calls on Linux alone, so no "fs" lines print and table 1 has no
# Mac column; N-proc, which needs /proc, says "skip"; and Valgrind, which
# the Linux lanes run. Every line goes to one log, each run's lines prefixed
# by its lane: [mac-8.7.1-run1] and [mac-8.7.1-run2] (summarize.mjs reads
# both as the lane mac-8.7.1). The log is
# .plans/research/m8/mime-files/results/mac-8.7.1.log, overwritten if there;
# it prints the path at the end. run.sh makes its temporary directory under
# $TMPDIR and removes it.
set -u
[ "$(uname -s)" = Darwin ] || { echo "mac.sh: this is the Mac's script; Linux lanes run run.sh" >&2; exit 2; }
d=.plans/research/m8/mime-files
[ -f $d/run.sh ] || { echo "mac.sh: run it from the repository's root" >&2; exit 2; }
if [ -z "${NODE:-}" ]; then
  NODE=$(asdf which node 2>/dev/null) || NODE=
  [ -n "$NODE" ] || NODE=$(command -v node) || NODE=
fi
[ -n "$NODE" ] && [ -x "$NODE" ] || { echo "mac.sh: no node found; set NODE to a Node 20 or later binary" >&2; exit 1; }
export NODE
CC=${CC:-cc}
export CC
unset CURL_LIB CURL_INCLUDE CASES VG_CASES VALGRIND
mkdir -p "$d/results"
log=$d/results/mac-8.7.1.log
echo "mac.sh: about 3 minutes; writing $log"
{
  echo "mac.sh start $(date -u +%Y-%m-%dT%H:%M:%SZ) macOS $(sw_vers -productVersion 2>/dev/null) $(uname -m) node=$NODE cc=$(command -v "$CC")"
  # /usr/lib/libcurl.4.dylib is in the dyld shared cache, not on disk, from
  # macOS 11; the probe's --version line names the libcurl it loaded.
  /usr/bin/curl --version 2>&1 | sed 's/^/mac.sh system curl: /'
  sh $d/run.sh mac-8.7.1-run1; echo "mac.sh run.sh mac-8.7.1-run1 exit=$?"
  sh $d/run.sh mac-8.7.1-run2; echo "mac.sh run.sh mac-8.7.1-run2 exit=$?"
  echo "mac.sh end $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$log" 2>&1
echo "mac.sh: done; the log is $PWD/$log"
cases=$(grep -c ' probe [A-Z][-A-Za-z0-9]* exit=' "$log")
echo "mac.sh: $(grep -c ' probe [A-Z][-A-Za-z0-9]* exit=0$' "$log") of $cases probe processes exited 0; $(grep -c '^mac.sh run.sh .* exit=0$' "$log") of 2 run.sh runs"
echo "mac.sh: a global gitignore of results/ needs: git add -f $log"
