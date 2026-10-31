# M6 slice 2's build: the evidence its records cite (2026-10-30 to 31)

What the slice's build, its review and my checks measured that the records rest on: the traps,
ADR-0030's amendments of 2026-10-31 and the plan's §5.2 "as built". The measurements before the
build are [`../slice2/`](../slice2/). The programs ran from git-ignored scratch under `build/`,
on copies of the tree, so their paths name it; they are kept as they ran.

| File | What it is |
|---|---|
| `control.sps`, `control-docker.sh` | the builder's pacing-off control on the floor lane, 7.85.0: a 2 s pause of an HTTP/2 upload, 10 runs a setting |
| `results/spin-control-floor-4k-sent.log` | that control, 4,096 bytes sent first: with pacing off, 8 runs of 10 spun, about 2,000 ms of CPU |
| `results/spin-control-floor-nothing-sent.log` | the same, nothing sent first, from an earlier `control.sps` not kept: 0 of 10 spun |
| `asked.sps`, `asked-docker.sh` | the builder's measurement of `curl-head-body-asked?` before its rows were written, 5 runs a case |
| `results/body-asked-{guix,floor,main,gnutls,current}.log` | that measurement on the five Linux lanes: one answer on each, `#t` for every streamed body libcurl asked for, `#f` for a whole body, none, and a length of 0 |
| `results/full-buffer-repro-guix-8.20.0.log` | my rerun of the builder's first full-buffer test, from its tree `runs/base3-1`: a put timed out on a full buffer, then a later one was taken, `(2031616 2097152)` |
| `results/mutant-reason-ignores-refusal.diff` and `-{guix-8.20.0,floor-7.85.0,main-8.5.0}.log` | my mutant that leaves a put's refusal to the read callable alone: the transfer ended 200, 1,000 bytes handed, on all three |
| `review/once.sps` | the review's probe: two puts inside one pause, the engine held |
| `review/results/once-{base,flag-ignored}.log` | 1 resume on the base, 2 on the mutant that ignores the resume flag |
| `review/results/mut-no-row.{diff,log}` | the review's mutant that deletes 8.20.0's rows: test-upload and test-stream passed on 8.20.0, 52 and 74 tests |
| `review/results/mut-flag-ignored.{diff,log}` | the mutant behind `once-flag-ignored.log`: test-upload passed, 52 of 52 |
| `review/answer.sps`, `review/results/answer-guix.log` | the review's probe of the answer table, 10 runs a cell |
| `review/results/base.log` | the review's base run of the suites it read |
| `asked-early.sps` | round 3's measurement: a streamed post against `/raw/arm`, whose answer the origin writes as it accepts the connection, 5 runs of {200, 413} × {sized, chunked} a lane |
| `results/body-asked-early-{floor,main,gnutls,guix,current}.log` | unheld: the bit `#t` in 100 runs of 100, the answer landing after libcurl's request and its first ask |
| `results/body-asked-held-probe.diff`, `results/body-asked-held-{floor,main,gnutls,guix,current}.log` | a scratch copy whose prerequest callable sleeps 200 ms first: `#f`, never asked, 20 of 20 on 7.85.0 and both 8.5.0 builds; `#t` on 8.20.0 and 8.23.0, which ask with the head |
| `results/body-asked-held-mutant.diff`, `results/body-asked-held-mutant-floor.log` | the scoped review's mutant on that copy, the bit as "streams, length not 0": `#t` 20 of 20 on 7.85.0, `ever-asked=#f` |
| `asked-valgrind.sh`, `results/body-asked-{held,unheld}-valgrind-8.5.0.log` | round 4's runs under the memory gate's Valgrind on 8.5.0: held, `#f` 20 of 20; unheld too, `#f` 20 of 20, never asked: the answer won the race there |
| `results/body-asked-hold-zero-ms-floor.log` | round 4's mutant whose hold sleeps 0 ms, on 7.85.0: the answer came first in 1 case of 4 |

