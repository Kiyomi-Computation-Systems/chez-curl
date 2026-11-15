#!/bin/sh
# live-check.sh REF: fetches every page site/pages.sls names, and the
# stylesheet, from the live docs site; requires each to answer 200, and
# every link out to the repository to name blob/REF/, none another ref.
# Prints one line per page and a summary; exits 1 on any failure.
set -u
ref=$1
base=https://kiyomi-computation-systems.github.io/chez-curl/
blob=https://github.com/Kiyomi-Computation-Systems/chez-curl/blob/
tmp=$(mktemp -d "${TMPDIR:-/tmp}/live-check.XXXXXX")
fail=0
pages=$(grep -o '("[A-Za-z-]*\.md"' site/pages.sls | sed 's/^("//; s/\.md"$//; s/^README$/index/')
n=0
for p in $pages style; do
  case $p in style) f=style.css ;; *) f=$p.html ;; esac
  code=$(curl -s -o "$tmp/$f" -w '%{http_code}' "$base$f")
  n=$((n + 1))
  if [ "$code" = 200 ]; then
    refs=$(grep -o "href=\"$blob[^/\"]*/" "$tmp/$f" | sed "s#href=\"$blob##; s#/\$##" | sort | uniq -c | tr -s ' ' | tr '\n' ';')
    echo "200 $f ${refs:-no repository links}"
    if grep -o "href=\"$blob[^/\"]*/" "$tmp/$f" | grep -v -F "href=\"$blob$ref/" | grep -q .; then
      echo "  FAILED: $f links a ref other than $ref"; fail=1
    fi
  else
    echo "$code $f"; fail=1
  fi
done
total=$(cat "$tmp"/*.html | grep -o "href=\"$blob[^/\"]*/" | wc -l)
pinned=$(cat "$tmp"/*.html | grep -o "href=\"$blob$ref/" | wc -l)
echo "live-check: $n files fetched; $pinned of $total repository links name blob/$ref/"
rm -rf "$tmp"
[ "$fail" -eq 0 ] && [ "$total" -gt 0 ] && [ "$pinned" -eq "$total" ]
