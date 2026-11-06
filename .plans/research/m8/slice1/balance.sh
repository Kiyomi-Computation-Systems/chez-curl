#!/bin/sh
# Splits the suites into two shards by their times under the memory gate,
# from times.sh's table: each suite, slowest first by its slowest run, goes
# to the shard with less time so far (longest processing time first). Then
# prints each shard, in the suites' sorted order, and its time in each run.
# Usage: sh times.sh LOG ... | sh balance.sh
set -eu
awk '
  NR == 1 { nruns = NF - 2; for (i = 1; i <= nruns; i++) run[i] = $(i + 1); next }
  $1 ~ /^\(/ || $1 == "setup" || $1 == "planted" || $1 == "suites" || $1 == "first" || $1 == "note:" { next }
  { n++; name[n] = $1; mx[n] = $NF; for (i = 1; i <= nruns; i++) t[n, i] = $(i + 1) }
  END {
    for (i = 1; i <= n; i++) idx[i] = i
    for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++)
      if (mx[idx[j]] > mx[idx[i]] || (mx[idx[j]] == mx[idx[i]] && name[idx[j]] < name[idx[i]])) {
        x = idx[i]; idx[i] = idx[j]; idx[j] = x }
    for (k = 1; k <= n; k++) { i = idx[k]; s = (load[1] <= load[2]) ? 1 : 2; shard[i] = s; load[s] += mx[i] }
    for (s = 1; s <= 2; s++) {
      printf "shard %d:", s; c = 0
      for (i = 1; i <= n; i++) if (shard[i] == s) { printf " %s", name[i]; c++ }
      printf "\n  %d suites; seconds, by run:", c
      for (r = 1; r <= nruns; r++) { sum = 0; for (i = 1; i <= n; i++) if (shard[i] == s) sum += t[i, r]
        printf " %s %.1f", run[r], sum }
      printf "; by each suite'"'"'s slowest: %.1f\n", load[s] }
  }'
