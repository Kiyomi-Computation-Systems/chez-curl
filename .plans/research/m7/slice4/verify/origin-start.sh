#!/bin/sh
# verify/origin-start.sh ORIGIN N [PKI]: how long ORIGIN takes from its start
# to its announcement line, N times, in ms, with the run's PKI when PKI is
# given (a directory made by tests/make-test-pki.sh). From the repository's
# root, in the Guix container:
#   scripts/guix-env sh .plans/research/m7/slice4/verify/origin-start.sh tests/origin.mjs 5 < /dev/null
set -u
origin=$1
n=$2
pki=${3:-}
i=0
while [ "$i" -lt "$n" ]; do
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/ostart.XXXXXX") || exit 1
  mkfifo "$tmp/in"
  start=$(date +%s%N)
  if [ -n "$pki" ]; then node "$origin" --pki "$pki" < "$tmp/in" > "$tmp/out" 2> "$tmp/err" &
  else node "$origin" < "$tmp/in" > "$tmp/out" 2> "$tmp/err" &
  fi
  pid=$!
  exec 3> "$tmp/in"
  until [ -s "$tmp/out" ]; do :; done
  end=$(date +%s%N)
  exec 3>&-
  wait "$pid"
  echo "start $((i + 1)): $(( (end - start) / 1000000 )) ms, $(head -c 60 "$tmp/out")"
  rm -rf "$tmp"
  i=$((i + 1))
done
