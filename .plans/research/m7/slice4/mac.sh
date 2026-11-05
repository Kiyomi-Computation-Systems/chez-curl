#!/bin/sh
# M7 slice 4's measurements on the maintainer's Mac, against Apple's libcurl
# 8.7.1, the rows 8.7.1 needs: items 1 (lifetime, abandon-leave,
# abandon-free), 2 (setopt), 4 (load), 5 (readout), 7 (host), 8 (h2) and 12
# (ipv6). Run from the repository's root:
#   NODE="$(asdf which node)" sh .plans/research/m7/slice4/mac.sh
# It makes the prototype (make-prototype.sh, python3), then runs run.sh on
# those parts twice per pass: with the default TLS backend (Apple's
# LibreSSL), and with CURL_SSL_BACKEND=secure-transport, which run.sh hands
# every process's env -i. libcurl is discovered (no CURL_LIB). CHEZ, chez
# by default (Homebrew's); GNU timeout as gtimeout (brew install
# coreutils); OPENSSL, as make test finds it. Each run writes its log into
# results/ and prints where. The logs are under results/, which the Mac's
# git ignores: add them with git add -f. Not run by its author: the Mac is
# the maintainer's.
set -u
[ "$(uname -s)" = Darwin ] || { echo "mac.sh: this is for macOS" >&2; exit 2; }
d=.plans/research/m7/slice4
[ -f $d/run.sh ] || { echo "mac.sh: run it from the repository's root" >&2; exit 2; }
NODE=${NODE:-node}
CHEZ=${CHEZ:-chez}
export NODE CHEZ
"$NODE" --version > /dev/null 2>&1 || { echo "mac.sh: no node at '$NODE'; pass NODE=\"\$(asdf which node)\"" >&2; exit 2; }
sh $d/make-prototype.sh || exit 1
mkdir -p $d/results
parts="lifetime abandon-leave abandon-free setopt load readout host h2 ipv6"
status=0
for pass in default secure-transport; do
  for n in 1 2; do
    log=$d/results/mac-8.7.1-$pass-$n.log
    if [ "$pass" = default ]; then
      # shellcheck disable=SC2086
      EXTRA_ENV= sh $d/run.sh mac-8.7.1-$pass $parts > "$log" 2>&1
    else
      # shellcheck disable=SC2086
      EXTRA_ENV=CURL_SSL_BACKEND=secure-transport sh $d/run.sh mac-8.7.1-$pass $parts > "$log" 2>&1
    fi
    s=$?
    [ "$s" -eq 0 ] || status=1
    echo "mac.sh: $pass run $n: run.sh exited $s, $(grep -c '\] case ' "$log") cases, $(grep -c 'exited 0 after' "$log") of 9 parts exited 0; the log is $(pwd)/$log"
  done
done
echo "mac.sh: add the logs with: git add -f $d/results/mac-8.7.1-*.log"
exit $status
