#!/bin/sh
# M7 slice 3's prototype (2026-11-02): a private copy of src/ in
# build/m7s3/src whose request takes a proxy URL, and whose hatch can reach
# what the proxy measurements need (the M7 plan, section 6.1). Run on the
# host, from the repository's root:
#   sh .plans/research/m7/slice3/make-prototype.sh
# It removes build/m7s3/src, copies src/ there, and changes four things in
# (curl private transfer), nothing else:
#   1. The proxy field takes a string beside environment and #f, and a
#      transfer sets PROXY to it verbatim: no NOPROXY, no port added. A case
#      that wants NOPROXY "" sets it by the hatch.
#   2. owned-option-names leaves out NOPROXY and proxy-tls-option-names, so
#      the hatch sets NOPROXY, PROXY_CAINFO, PROXY_CAPATH,
#      PROXY_SSL_VERIFYPEER and PROXY_SSL_VERIFYHOST, as the plan's fields
#      would.
#   3. owned-option-names leaves out FRESH_CONNECT, a streamed body's, so the
#      hatch can set it on a transfer that streams nothing: item 3's
#      FRESH_CONNECT 1 on the second transfer.
#   4. A string option's hatch value may be #f, a clear, set as NULL by
#      set-option!, as tls-settings clears CAPATH: item 5's PROXY_CAPATH
#      cleared, which no string can say. set-option! takes CURLE_NOT_BUILT_IN
#      for a clear, as it does for CAPATH (setopt-accepted?).
# It writes the diff to prototype.diff beside this script, and fails unless
# the diff changes exactly the lines it means to.
set -eu
d=.plans/research/m7/slice3
[ -f $d/make-prototype.sh ] || { echo "make-prototype.sh: run it from the repository's root" >&2; exit 2; }
out=build/m7s3/src
rm -rf build/m7s3/src
mkdir -p build/m7s3
cp -R src "$out"
f=$out/curl/private/transfer.sls
python3 - "$f" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding='utf-8').read()
def change(a, b):
    global text
    assert text.count(a) == 1, ("not unique", a)
    text = text.replace(a, b)
change("""    (unless (or (eq? proxy 'environment) (not proxy))""",
       """    (unless (or (eq? proxy 'environment) (not proxy) (string? proxy))""")
change("""      (set-string-option! easy (field-option 'proxy) "" buffer))""",
       """      (set-string-option! easy (field-option 'proxy) "" buffer))
    (when (string? (plan-proxy plan))
      (set-string-option! easy (field-option 'proxy) (plan-proxy plan) buffer))""")
change("""            (apply append (map cdr request-field-options))""",
       """            (remove "FRESH_CONNECT" (apply append (map cdr request-field-options)))""")
change('''              "NOPROXY" "PRE_PROXY" "PROXYPORT" "PROXYTYPE"''',
       '''              "PRE_PROXY" "PROXYPORT" "PROXYTYPE"''')
change("""              "AWS_SIGV4")
            proxy-tls-option-names))""",
       """              "AWS_SIGV4")))""")
change("""      ((string)
       (unless (string? value) (wrong "the option takes a string"))
       (checked (string-copy value)))""",
       """      ((string)
       (if (not value)
           #f
           (begin (unless (string? value) (wrong "the option takes a string"))
                  (checked (string-copy value)))))""")
change("""        ((string) (set-string-option! easy name value buffer))""",
       """        ((string) (if value (set-string-option! easy name value buffer) (set-option! easy name #f buffer)))""")
open(path, 'w', encoding='utf-8').write(text)
PY
diff -u src/curl/private/transfer.sls "$f" > $d/prototype.diff && { echo "make-prototype.sh: no change made" >&2; exit 1; }
removed=$(grep -c '^-[^-]' $d/prototype.diff)
added=$(grep -c '^+[^+]' $d/prototype.diff)
[ "$removed" -eq 8 ] && [ "$added" -eq 11 ] || { echo "make-prototype.sh: $removed lines removed and $added added, not 8 and 11" >&2; exit 1; }
diff -r -q src "$out" | grep -v "transfer.sls differ" && { echo "make-prototype.sh: another file differs" >&2; exit 1; }
echo "make-prototype.sh: $out made; $d/prototype.diff holds the change ($removed lines removed, $added added)"
