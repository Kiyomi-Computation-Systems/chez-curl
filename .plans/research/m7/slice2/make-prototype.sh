#!/bin/sh
# M7 slice 2's prototype (2026-11-02): a private copy of src/ in
# build/m7s2/src whose hatch can reach what the auth measurements need (the
# M7 plan, section 5.1). Run on the host, from the repository's root:
#   sh .plans/research/m7/slice2/make-prototype.sh
# It removes build/m7s2/src, copies src/ there, and changes three things in
# (curl private transfer), nothing else:
#   1. owned-option-names leaves out USERNAME and PASSWORD, so the hatch
#      sets them as the credentials field would. HTTPAUTH, XOAUTH2_BEARER,
#      AWS_SIGV4 and every twin measured are the hatch's on main already.
#   2. rounds-option-names is ("PROXYAUTH"), so a streamed response beside
#      the hatch's HTTPAUTH is not refused as stream-with-rounds.
#   3. A byte seam: a string option's value may be a bytevector, sent as
#      those bytes and a NUL, by call-with-foreign-bytes; one holding a 0
#      byte is refused, embedded-nul. A string keeps today's rules: UTF-8
#      by call-with-c-string, and U+0000, CR and LF refused. A UTF-8 string
#      cannot carry a lone byte above 0x7F, and the hatch refuses CR and LF,
#      so the hostile-byte cases need it.
# It writes the diff to prototype.diff beside this script, and fails unless
# the diff changes exactly the lines it means to.
set -eu
d=.plans/research/m7/slice2
[ -f $d/make-prototype.sh ] || { echo "make-prototype.sh: run it from the repository's root" >&2; exit 2; }
out=build/m7s2/src
rm -rf "$out"
mkdir -p build/m7s2
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
change('"TRANSFERTEXT" "USERPWD" "USERNAME" "PASSWORD" "NETRC" "HSTS"',
       '"TRANSFERTEXT" "USERPWD" "NETRC" "HSTS"')
change("""(define rounds-option-names '("HTTPAUTH" "PROXYAUTH"))""",
       """(define rounds-option-names '("PROXYAUTH"))""")
change("""      ((string)
       (unless (string? value) (wrong "the option takes a string"))
       (checked (string-copy value)))""",
       """      ((string)
       (if (bytevector? value)
           (let ((copy (bytevector-copy value)))
             (when (memv 0 (bytevector->u8-list copy)) (refuse-option who name 'embedded-nul))
             copy)
           (begin (unless (string? value) (wrong "the option takes a string"))
                  (checked (string-copy value)))))""")
change("""        ((string) (set-string-option! easy name value buffer))""",
       """        ((string) (if (bytevector? value)
                      (let ((bytes (make-bytevector (+ (bytevector-length value) 1) 0)))
                        (bytevector-copy! value 0 bytes 0 (bytevector-length value))
                        (call-with-foreign-bytes bytes (lambda (address) (set-option! easy name address buffer))))
                      (set-string-option! easy name value buffer)))""")
open(path, 'w', encoding='utf-8').write(text)
PY
diff -u src/curl/private/transfer.sls "$f" > $d/prototype.diff && { echo "make-prototype.sh: no change made" >&2; exit 1; }
removed=$(grep -c '^-[^-]' $d/prototype.diff)
added=$(grep -c '^+[^+]' $d/prototype.diff)
[ "$removed" -eq 5 ] && [ "$added" -eq 13 ] || { echo "make-prototype.sh: $removed lines removed and $added added, not 5 and 13" >&2; exit 1; }
diff -r -q src "$out" | grep -v "transfer.sls differ" && { echo "make-prototype.sh: another file differs" >&2; exit 1; }
echo "make-prototype.sh: $out made; $d/prototype.diff holds the change ($removed lines removed, $added added)"
