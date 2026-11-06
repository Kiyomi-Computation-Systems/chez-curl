#!/bin/sh
# Each suite's time under the memory gate, from CI memory jobs' logs, by
# their timestamps: from a suite's "=== tests/X.sps" line to its
# "test-memory: pass" (or FAIL, HUNG) line. Also each job's setup (its first
# line to the planted defects' step), the planted defects' step, and the
# suites' step. Usage: sh times.sh LOG ...  Prints one table, seconds.
set -eu
[ $# -gt 0 ] || { echo "usage: sh times.sh LOG ..." >&2; exit 2; }
awk '
  function secs(ts,   d, y, m, day, h, mi, s, a, b, jd) {
    # 2026-11-06T20:24:15.2483206Z, to seconds since an epoch of its own:
    # a Julian day number, so a log that crosses midnight or a month adds up.
    y = substr(ts, 1, 4) + 0; m = substr(ts, 6, 2) + 0; day = substr(ts, 9, 2) + 0
    h = substr(ts, 12, 2) + 0; mi = substr(ts, 15, 2) + 0; s = substr(ts, 18) + 0
    a = int((14 - m) / 12); b = y + 4800 - a; m = m + 12 * a - 3
    jd = day + int((153 * m + 2) / 5) + 365 * b + int(b / 4) - int(b / 100) + int(b / 400) - 32045
    return jd * 86400 + h * 3600 + mi * 60 + s
  }
  FNR == 1 { f = FILENAME; sub(/.*\//, "", f); sub(/^memory-/, "", f); sub(/\.log$/, "", f)
    runs[++nruns] = f; sub(/^\357\273\277/, "") ; start[f] = secs($1); cur = "" }
  { t = secs($1) }
  index($0, "##[group]Run make check-memory-gate") { gate[f] = t }
  index($0, "##[group]Run make test-memory") { suites[f] = t }
  $2 == "===" { cur = $3; since = t; next }
  $2 == "test-memory:" && ($3 == "pass" || $3 == "FAIL" || $3 == "HUNG") && $4 == cur {
    name = cur; sub(/^tests\//, "", name); sub(/\.sps$/, "", name)
    if (!(name in known)) { known[name] = 1; order[++nnames] = name }
    took[name, f] = t - since; if ($3 != "pass") verdict[name, f] = $3; cur = "" }
  $2 == "test-memory:" && $3 == "ran" { done[f] = t }
  END {
    printf "%-26s", "suite"; for (i = 1; i <= nruns; i++) printf " %12s", runs[i]; printf " %8s\n", "max"
    for (k = 1; k <= nnames; k++) { n = order[k]; printf "%-26s", n; mx = 0
      for (i = 1; i <= nruns; i++) { r = runs[i]
        if ((n, r) in took) { printf " %12.1f", took[n, r]; if (took[n, r] > mx) mx = took[n, r] }
        else printf " %12s", "-" }
      printf " %8.1f\n", mx; total += mx }
    printf "%-26s", "(sum of suites)"; for (i = 1; i <= nruns; i++) { r = runs[i]; s = 0
      for (k = 1; k <= nnames; k++) s += took[order[k], r]; printf " %12.1f", s }
    printf " %8.1f\n", total
    printf "%-26s", "setup"; for (i = 1; i <= nruns; i++) printf " %12.1f", gate[runs[i]] - start[runs[i]]; print ""
    printf "%-26s", "planted defects"; for (i = 1; i <= nruns; i++) printf " %12.1f", suites[runs[i]] - gate[runs[i]]; print ""
    printf "%-26s", "suites step"; for (i = 1; i <= nruns; i++) printf " %12.1f", done[runs[i]] - suites[runs[i]]; print ""
    printf "%-26s", "first line to last suite"; for (i = 1; i <= nruns; i++) printf " %12.1f", done[runs[i]] - start[runs[i]]; print ""
    for (k = 1; k <= nnames; k++) for (i = 1; i <= nruns; i++) if ((order[k], runs[i]) in verdict)
      printf "note: %s ended %s in %s\n", order[k], verdict[order[k], runs[i]], runs[i]
  }' "$@"
