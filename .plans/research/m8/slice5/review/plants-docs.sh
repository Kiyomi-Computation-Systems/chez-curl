#!/bin/sh
# Page plants: each a one-line change to docs/headers-and-json.md (or
# docs/README.md), then tests/test-docs.sps, then the page restored from
# review-scripts/pristine/. Run inside the container from the copy's root:
#   scripts/guix-env sh review-scripts/plants-docs.sh < /dev/null
# Prints, for each plant, the suite's exit status and its FAIL lines.
set -u
out=review-out/plants-docs
mkdir -p "$out"
page=docs/headers-and-json.md
index=docs/README.md

# plant NAME FILE OLD NEW: replaces the one line holding OLD's text.
plant() {
  name=$1 file=$2 old=$3 new=$4
  cp "review-scripts/pristine/$(basename "$file")" "$file"
  if ! OLD=$old NEW=$new node review-scripts/replace.js "$file"; then echo "== $name: NOT APPLIED"; return; fi
  if cmp -s "$file" "review-scripts/pristine/$(basename "$file")"; then echo "== $name: NO CHANGE"; return; fi
  "$CHEZ" --libdirs src:tests:build/scheme-libs --program tests/test-docs.sps >"$out/$name.log" 2>&1 3>&-
  rc=$?
  echo "== $name: test-docs exit $rc"
  grep '^FAIL' "$out/$name.log" | head -5
  cp "review-scripts/pristine/$(basename "$file")" "$file"
}

"$CHEZ" --libdirs src:tests:build/scheme-libs --program tests/test-docs.sps >"$out/control.log" 2>&1 3>&-
echo "== control: test-docs exit $? ($(grep -c '^FAIL' "$out/control.log") FAIL lines)"

plant d01-wrong-reason "$page" '| `framing-header` |' '| `framing-headers` |'
plant d02-wrong-merge-order "$page" "Z case. The session's others go first, in their order, then the call's." "Z case. The call's go first, then the session's others, in their order."
plant d03-wrong-output-line "$page" '(37 "Ada" "C")' '(38 "Ada" "C")'
plant d04-link-no-file "$page" '[stream](streams.md)' '[stream](stream.md)'
plant d05-link-wrong-page "$page" '[Auth and proxies](auth-and-proxies.md)' '[Auth and proxies](cookies.md)'
plant d06-link-wrong-anchor "$page" '(high-level.md#timeouts-and-limits)' '(high-level.md#timeouts-and-limit)'
plant d07-wrong-run-line "$page" 'scheme --libdirs src:build/scheme-libs --program examples/json-api.sps' 'scheme --libdirs src --program examples/json-api.sps'
plant d08-wrong-field "$page" '`header-name`,
`header-value` or `user-agent`' '`header-name`,
`header-values` or `user-agent`'
plant d09-wrong-export "$page" '`http-response-header RESPONSE NAME`' '`http-response-head RESPONSE NAME`'
plant d10-wrong-cap "$page" 'at 1,000 lines or 102,400' 'at 2,000 lines or 102,400'
plant d11-wrong-json-reason "$page" '`invalid-utf8` or `unexpected-eof`' '`invalid-utf8` or `unexpected-end`'
plant d12-wrong-fragment "$page" '(make-transcoder (latin-1-codec))' '(make-transcoder (utf-8-codec))'
plant d13-no-recursive "$page" 'git submodule update --init --recursive' 'git submodule update --init'
plant d14-index-run-line "$index" 'runs with `--libdirs src:build/scheme-libs`' 'runs with `--libdirs src`'
plant d15-wrong-repo "$page" 'github.com/Kiyomi-Computation-Systems/jsonparse' 'github.com/someone-else/jsonparse'
plant d16-wrong-reason-row "$page" '| `line-break` | a value holding CR or LF' '| `line-break` | a value holding a tab'
plant d17-wrong-refusal-key "$page" '`credentials` an `Authorization`' '`credentials` a `Cookie`'
plant d18-wrong-ua-rule "$page" "and a call's
  \`user-agent\` drops a session's \`User-Agent\` header." "and a call's
  \`user-agent\` keeps a session's \`User-Agent\` header."
plant d19-wrong-example-output-claim "$page" 'The last line above is `/status/200`'"'"'s' 'The last line above is `/status/404`'"'"'s'
plant d20-wrong-api-name-prose "$page" '`json->bytevector` writes' '`json->string` writes'
