#!/bin/bash
# Checks readme-claims.md's claims table, host only, read-only: every test
# citation (Test column) names a line that is a test-equal or test-assert, or a
# table's row; every code citation (Code column) lies inside its file. A bare
# :N is a line of the file named before it in the same cell. Lines that are
# neither are printed, for a reader to judge.
R=/home/kishu/src/chez-curl
F=$R/.plans/research/m8/slice4/readme-claims.md
expand() {  # the short names the table's header defines
  perl -pe 's/(?<![\/\w-])((?:transfer|engine|url|native|conditions|verify|discovery|require-threaded)\.sls)/src\/curl\/private\/$1/g;
            s/(?<![\/\w-])((?:call|exchange|drive)\.sls)/src\/http-client\/private\/$1/g'
}
cites() {
  perl -ne 'my $file; while (/((?:src|tests|packaging|\.plans|\.github)\/[A-Za-z0-9._\/-]+|Makefile)?:(\d+)/g) {
              if ($1) {$file=$1} next unless $file; print "$file $2\n" }'
}
rows=$(grep '^| :[0-9]' $F)
echo "claims rows: $(printf '%s\n' "$rows" | wc -l)"
printf '%s\n' "$rows" | awk -F'|' '{print $5}' | cites | sort -u > /tmp/readme-test-cites.$$
echo "test citations: $(wc -l < /tmp/readme-test-cites.$$)"
echo "# test citations that are no test line or row:"
while read file line; do
  [ -f "$R/$file" ] || { echo "NOFILE $file"; continue; }
  text=$(sed -n "${line}p" "$R/$file")
  case "$text" in *test-equal*|*test-assert*|*'("'*|*'(('*|*'(cons "'*) ;; *) echo "$file:$line: $(printf '%s' "$text" | cut -c1-100)";; esac
done < /tmp/readme-test-cites.$$
printf '%s\n' "$rows" | awk -F'|' '{print $4}' | expand | cites | sort -u > /tmp/readme-code-cites.$$
echo "code citations: $(wc -l < /tmp/readme-code-cites.$$)"
echo "# code citations past their file's end, or to no file:"
while read file line; do
  [ -f "$R/$file" ] || { echo "NOFILE $file"; continue; }
  n=$(wc -l < "$R/$file"); [ "$line" -le "$n" ] || echo "PAST END $file:$line ($n lines)"
done < /tmp/readme-code-cites.$$
rm -f /tmp/readme-test-cites.$$ /tmp/readme-code-cites.$$
echo "ok readme-citations done"
