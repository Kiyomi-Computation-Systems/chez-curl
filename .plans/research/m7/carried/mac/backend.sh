#!/bin/sh
# mac/backend.sh: which TLS backend Apple's libcurl puts in use, by
# CURL_SSL_BACKEND: unset, secure-transport, securetransport and openssl.
# For each, the C probe's ssl_version before and after curl_global_init, and
# chez-curl's own record of it; then the value make gives its suites. CHEZ and
# CC name the tools, chez and cc by default. On the Mac, from the
# repository's root:
#   sh .plans/research/m7/carried/mac/backend.sh > .plans/research/m7/carried/mac/mac-8.7.1-backend.log 2>&1
set -u
chez=${CHEZ:-chez}
cc=${CC:-cc}
dir=.plans/research/m7/carried/mac
[ -f "$dir/backend.c" ] || { echo "backend.sh: run it from the repository's root" >&2; exit 2; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/backend.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
echo "uname: $(uname -sm), shell CURL_SSL_BACKEND: ${CURL_SSL_BACKEND-unset}"
"$cc" -o "$tmp/backend" "$dir/backend.c" -lcurl || { echo "backend.sh: the compile failed" >&2; exit 1; }
for value in unset secure-transport securetransport openssl; do
  echo "=== CURL_SSL_BACKEND $value"
  if [ "$value" = unset ]; then
    env -u CURL_SSL_BACKEND "$tmp/backend"; echo "c exit $?"
    env -u CURL_SSL_BACKEND "$chez" --libdirs src --script "$dir/backend.sps"; echo "chez exit $?"
  else
    env CURL_SSL_BACKEND="$value" "$tmp/backend"; echo "c exit $?"
    env CURL_SSL_BACKEND="$value" "$chez" --libdirs src --script "$dir/backend.sps"; echo "chez exit $?"
  fi
done
echo "=== what make gives its suites, the shell's variable unset"
env -u CURL_SSL_BACKEND make -pn test 2>/dev/null | grep -m 2 '^CURL_SSL_BACKEND' || echo "(no CURL_SSL_BACKEND in make's database)"
echo "backend.sh: done"
