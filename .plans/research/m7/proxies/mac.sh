#!/bin/sh
# M7's proxy probe on the maintainer's Mac, against Apple's libcurl 8.7.1 (cc,
# -lcurl, the SDK's headers). Run from the repository's root:
#   NODE="$(asdf which node)" sh .plans/research/m7/proxies/mac.sh
# It runs run.sh twice: with the default TLS backend (Apple's LibreSSL), and
# with CURL_SSL_BACKEND=secure-transport, which run.sh hands every case's
# env -i. Each pass writes its log into results/ and prints where; the
# cases' lookup of nonesuch.invalid is skipped, since on macOS it leaves
# loopback. run.sh's mktemp template is under $TMPDIR. The logs are under
# results/, which the Mac's git ignores: add them with git add -f.
set -u
[ "$(uname -s)" = Darwin ] || { echo "mac.sh: this is for macOS" >&2; exit 2; }
d=.plans/research/m7/proxies
[ -f $d/run.sh ] || { echo "mac.sh: run it from the repository's root" >&2; exit 2; }
NODE=${NODE:-node}
export NODE
"$NODE" --version > /dev/null 2>&1 || { echo "mac.sh: no node at '$NODE'; pass NODE=\"\$(asdf which node)\"" >&2; exit 2; }
mkdir -p $d/results
status=0
for pass in default secure-transport; do
  log=$d/results/mac-8.7.1-$pass.log
  if [ "$pass" = default ]; then
    EXTRA_ENV= sh $d/run.sh mac-$pass > "$log" 2>&1
  else
    EXTRA_ENV=CURL_SSL_BACKEND=secure-transport sh $d/run.sh mac-$pass > "$log" 2>&1
  fi
  s=$?
  [ "$s" -eq 0 ] || status=1
  echo "mac.sh: $pass: run.sh exited $s, $(grep -c ' done code=' "$log") transfers; the log is $(pwd)/$log"
done
echo "mac.sh: add the logs with: git add -f $d/results/mac-8.7.1-*.log"
exit $status
