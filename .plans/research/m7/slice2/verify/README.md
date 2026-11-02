# M7 slice 2's measurement and build, checked (2026-11-02)

My checks of the measuring agent's hand-back, and of a trap the builder reported.

- **The measurement, rerun on Guix's 8.20.0:** `run.sh guix-8.20.0`, every part, into
  [`results/rerun-guix-8.20.0.log`](results/rerun-guix-8.20.0.log): 997 transfers, as the
  agent's run 1 has. `tables.mjs`, given run 1 and my rerun as its two runs, marked no cell
  split. With one status changed in a copy of my log, `schemes20`'s 200 to 500, it marked that
  cell ([`results/compare-planted.md`](results/compare-planted.md)), so the comparison can fire.
- **The `MAXREDIRS` addition, rerun on Guix's 8.20.0:**
  [`results/rerun-maxredirs-guix-8.20.0.log`](results/rerun-maxredirs-guix-8.20.0.log): its ten
  outcomes, timings aside, are the agent's run 1's line for line.
- **libcurl resends after a 417 only on a connection it keeps:** both 7.85.0's and 8.20.0's
  `lib/http.c` resend inside the transfer only when `!conn->bits.close`. [`c417.sh`](c417.sh)
  runs curl's own tool, Guix's 8.20.0, with a caller's `Expect: 100-continue` against
  [`c417-server.mjs`](c417-server.mjs), which answers 417 to every such request, keeping the
  connection or closing it with `Connection: close`
  ([`results/c417-guix-8.20.0.log`](results/c417-guix-8.20.0.log)): kept, 51 requests and exit
  47, the tool's own `--max-redirs` of 50; closed, one request, ending 417. Rerun in the Guix
  container, from the repository's root: `scripts/guix-env sh .plans/research/m7/slice2/verify/c417.sh < /dev/null`.
- **The changed suites on the four Docker lanes,** on a copy of the tree, with
  `build/m7s2b/lanes.sh`: 13 of 13 on the floor 7.85.0 and both 8.5.0 lanes. On 8.23.0,
  test-mailbox failed one test, an interrupt handler's planted escape as a take's critical
  section ends: the child returned before the signal came, `escape returned` where `escape lost`
  was planted, and its `kill` found no process
  ([`results/lanes-current-changed-suites.log`](results/lanes-current-changed-suites.log)).
  The slice changes nothing that test reads, and the slice's review was running on the host.
  test-mailbox alone then passed three times of three there
  ([`results/lanes-current-mailbox-reruns.log`](results/lanes-current-mailbox-reruns.log)).
- **The build, on the final tree before the review's fix round:** `make test` in the container,
  37 of 37 ([`results/make-test-guix-8.20.0.log`](results/make-test-guix-8.20.0.log)), and the
  lanes above, whose `test-auth` lines print, on each lane, what `curl_url` reports for the
  empty-userinfo URLs and what the field then does (`empty-userinfo on`), the table ADR-0036's
  amendment gives.
- **After the review's fix round,** on the final tree: `make test` in the container, 37 of 37
  ([`results/make-test-guix-8.20.0-after-fix.log`](results/make-test-guix-8.20.0-after-fix.log));
  test-auth under the memory gate there
  ([`results/memory-test-auth-guix-8.20.0-after-fix.log`](results/memory-test-auth-guix-8.20.0-after-fix.log));
  the 13 changed suites on the four Docker lanes, 13 of 13 each (`results/lanes-*-after-fix.log`).
  Three mutants of mine each failed test-auth by the tests named for them
  (`results/mutant-*-after-fix.log`): the token's record not opaque, the credentials scan from
  index 1, and the `Authorization` rule reading the first header alone.
