#!/bin/sh
# The review's mutants, each a copy of the working tree (no build/) with one
# change, under build/m7s2-review/mut/NAME. On the host, from the root:
#   sh build/m7s2-review/make-mutants.sh
set -eu
m=build/m7s2-review/mut
T=src/curl/private/transfer.sls
mk() {
  name=$1 file=$2 old=$3 new=$4
  if [ -n "${ONLY:-}" ] && [ "$ONLY" != "$name" ]; then return 0; fi
  rm -rf "$m/$name"; mkdir -p "$m/$name"
  rsync -a --exclude=/build --exclude=/.git ./ "$m/$name/"
  python3 - "$m/$name/$file" "$old" "$new" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
n = s.count(old)
if n != 1: raise SystemExit(f'{p}: {n} matches')
open(p, 'w').write(s.replace(old, new))
PY
  echo "made $name"
}
# 1. the bytes scan skips each part's first char
mk scan-skips-first $T "                      (let scan ((i 0))
                        (when (< i (string-length text))" "                      (let scan ((i 1))
                        (when (< i (string-length text))"
# 2. the Authorization rule reads the first header alone
mk authorization-first-only $T "(when (exists (lambda (header) (string=? (ascii-folded (car header)) \"authorization\")) headers)" "(when (and (pair? headers) (string=? (ascii-folded (car (car headers))) \"authorization\"))"
# 3. a refusal carries the credentials inside a record, which strings-in never opens
mk refusal-holds-record $T "          (refuse-credentials who scheme 'credentials-beside-authorization))" "          (raise (condition (make-curl-request-error 'credentials scheme 'credentials-beside-authorization)
                            (make-who-condition who)
                            (make-message-condition \"credentials beside an Authorization header\")
                            (make-irritants-condition (list scheme (make-curl-request \"http://x/\" 'credentials credentials))))))"
# 4. the bytes rule refuses a printable char too: " (0x22)
mk bytes-refuses-dquote $T "      (or (< code #x20) (= code #x7F))))" "      (or (< code #x20) (= code #x7F) (= code #x22))))"
