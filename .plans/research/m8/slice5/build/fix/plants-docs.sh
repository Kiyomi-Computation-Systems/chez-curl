#!/bin/sh
# Plants for test-docs' two new checks, each a one-line change to a page,
# then tests/test-docs.sps, then the page restored from build/fix-pristine/.
# Run inside the container from the repository's root, after copying the
# pages there on the host:
#   scripts/guix-env sh .plans/research/m8/slice5/build/fix/plants-docs.sh < /dev/null
# Prints, for each plant, the suite's exit status and its FAIL lines.
set -u
out=.plans/research/m8/slice5/build/fix/plants-docs
replace=.plans/research/m8/slice5/review/replace.js
mkdir -p "$out"

# plant NAME FILE OLD NEW: replaces the one occurrence of OLD in FILE.
plant() {
  name=$1 file=$2 old=$3 new=$4
  pristine="build/fix-pristine/$(basename "$file")"
  cp "$pristine" "$file"
  if ! OLD=$old NEW=$new node "$replace" "$file"; then echo "== $name: NOT APPLIED"; return; fi
  if cmp -s "$file" "$pristine"; then echo "== $name: NO CHANGE"; return; fi
  "$CHEZ" --libdirs src:tests:build/scheme-libs --program tests/test-docs.sps >"$out/$name.log" 2>&1 3>&-
  rc=$?
  cp "$pristine" "$file"
  cmp -s "$file" "$pristine" && restored=restored || restored=NOT-RESTORED
  echo "== $name: test-docs exit $rc, $restored"
  grep '^FAIL' "$out/$name.log"
}

"$CHEZ" --libdirs src:tests:build/scheme-libs --program tests/test-docs.sps >"$out/control.log" 2>&1 3>&-
echo "== control: test-docs exit $? ($(grep -c '^FAIL' "$out/control.log") FAIL lines)"

plant p1-page-run-line docs/headers-and-json.md \
  'scheme --libdirs src:build/scheme-libs --program examples/json-api.sps' \
  'scheme --libdirs src --program examples/json-api.sps'
plant p2-index-run-line docs/README.md \
  '`scheme --libdirs src:build/scheme-libs --program examples/json-api.sps URL`' \
  '`scheme --libdirs src --program examples/json-api.sps URL`'
plant p3-quickstart-run-line docs/quickstart.md \
  'scheme --libdirs src --program examples/quick-start.sps http://127.0.0.1:40001' \
  'scheme --libdirs src:build/scheme-libs --program examples/quick-start.sps http://127.0.0.1:40001'
plant p4-page-reason docs/headers-and-json.md '| `framing-header` |' '| `framing-headers` |'
plant p5-errors-reason docs/errors.md '| `body-limit` |' '| `body-limits` |'
plant p6-errors-reasons-cell docs/errors.md '`credentials-bytes`, `credentials-empty`, `credentials-beside-userinfo`' \
  '`credentials-bytes`, `credential-empty`, `credentials-beside-userinfo`'
plant p7-tls-reason docs/tls-and-environment.md '| `below-floor` |' '| `below-the-floor` |'
