# `test-http-client`'s timings and witnesses (M5 slice 1, 2026-10-27)

Measured by the slice's builder (Opus) in the container on 8.20.0, on the code after the review's
first fix round, in `build/m5s1-builder/kept/`, and copied here with each log's command as it ran
there, on its first line. `run.sh` and `run-mutant.sh` rerun them from that directory; run from
here, change the `build/m5s1-builder/kept/` paths to this one's.

- `timing/`: `timing.sps` makes the suite's three bounded calls, `timeout-ms` 400 against a 3 s
  drip, and its timer escape from an await, then prints each one's milliseconds.
  - `native.log`, 10 runs: the bound calls 405 to 407 ms, and the escape's transfer ended 1 to 2
    ms after it.
  - `valgrind.log`, 3 runs with ADR-0014's flags: 411 to 480 ms, and 6 to 10 ms.
  The suite allows 400 to 800 ms for a bound, and 3 s for an escape's transfer to end.
- `witness/`: the SIGINT child of the suite's critical-section test, run 40 times under 24 busy
  loops, or idle, by `child-loop.sh`.
  - `escape-child-v1.sps`, the first witness, which summed the engine's queued and live counts,
    each read in a hold of its own: `v1-loaded.log` read 1, the one transfer, 35 times, 0 four
    times and 2 once. A token sits in neither while the engine sets it up
    ([engine-window](../engine-window/)), and the engine can move it between the two reads.
  - `escape-child-v2.sps`, the suite's witness, which waits for the holder to let go and then
    for the engine to hold nothing: `v2-loaded.log` and `v2-idle.log` passed 40 of 40, and
    `v2-record-after-section.log`, the drive's record moved after its critical section, failed
    30 of 30, the transfer still live.
- `double-escape/non-critical-wind.log`: the suite on the drive with a plain `dynamic-wind`,
  failing the second-escape sweep at ticks 5 to 9, as the slice's review found
  ([escape](../escape/)). The builder's mutation script that made it is not kept: the mutant is
  one change in `src/http-client/private/drive.sls`, `(dynamic-wind #t` made `(dynamic-wind`, in
  a copy of the tree, then `make test SUITES=tests/test-http-client.sps` there.
- `engine/`, from fix round 2: a call inside a Chez engine whose fuel runs out in its await.
  - `ticks.sps`, `ticks.log`: the ticks a call spends, about 6,700 for its setup and about 100
    for each 10 ms poll of its await, so one fuel of 50,000, the suite's, runs out about 440 ms
    into the await, against a 10 s drip.
  - `slices.sps`, `slices-idle.log`, `slices-loaded.log`: the builder's first try, slices of
    1,000 ticks. Idle, each of 10 runs met an expiry with the transfer live; under 24 busy
    loops none of 10 did, an expiry just after the submit cancelling the token while it was
    still queued. Every run raised `cancelled` once resumed, with one transfer.
  - `suite-with-slices.log`, `repeat.sh`: the suite with those slices failed 2 of 10 runs idle
    and 10 of 10 loaded; with the one fuel of 50,000 the final tree passed 20 of 20, 10 of them
    loaded (the builder's report).
