# M6 slice 3's build: the evidence its records cite (2026-10-31 to 11-01)

What the slice's build, its two reviews and my checks measured that the records rest on: the plan's
§3.6 rules added by the fix rounds, §6.2 "as built", and ADR-0031's amendments of 2026-10-31 and
2026-11-01. The measurements before the build are [`../slice3/`](../slice3/), and my checks of
them [`../slice3/verify/`](../slice3/verify/). The programs ran from git-ignored scratch under
`build/`, on copies of the tree, so their paths name it; they are kept as they ran.

| File | What it is |
|---|---|
| `review/` | the adversarial review's probes: `probe-escape.sps` with `mut-escape.diff`, a gate in the producer's critical after thunk (case A) and at `curl-token-end-body!`'s section (case B); `probe-put.sps`, a put's escape through the engine's held mutex; `probe-reset.sps` with `probe-reset-server.mjs`, a server that reads 64 KiB of a producer's body, then closes; `mut-hop-redraws.diff`, a hop stepped with a fresh draw; and the review's own escape log |
| `results/probe-escape-rerun.log` | my rerun of case A and B: A came back 983,040 bytes of 1,048,576, first bad offset 196,608, 3 of 3, the call answering normally; B called the producer after its eof, 1 of 3; the controls whole |
| `results/probe-put-{tree,mut-reconcile-off}.log` | my rerun: the tree whole; without the reconcile, 1,114,112 bytes, a 64 KiB piece duplicated at 262,144, 3 of 3 |
| `results/probe-reset-{tree,mut-call-ignored}.log` | my rerun: the tree raised 52 with 1 transfer; the mutant reached a second transfer, stopped only by the drive's own assertion, after its submit |
| `results/mut-redraws-round3.log` | my rerun: the fresh-draw mutant passed test-stream-call, test-retry and test-redirect |
| `results/end-at-length-*` | the builder's evidence that the producer must be asked for its end once its puts reach `body-length`: with the waits at their whole bound, a sized producer was asked 16 times, not 17, and a long one passed as a 200; and the round-3 mutant that waited for room, once natively on raw-tls (ADR-0031, amended) |
| `results/round4-escape-before-fix.log` | round 4's escape child on the code before the fix: A lost 65,536 bytes, B called the producer after its eof, C returned instead of raising |
| `results/mut-{call-ignored,reconcile-off,redraws}-final.{diff,log}` | my mutants of the review's three survivors on round 4's code: each failed the test named for its rule |
| `scoped-review/` | the scoped review's probes: `retain.sps` (`probe-retain.log`, the seam keeping a 64 MiB body, 64.1 MB), `before-escape.sps` with `p-before.diff` (case E, `probe-before.log`, the transfer cancelled 3 of 3), `m-ending-B20.log` (case B's kill a race, 14 of 20), and `engine-expiry.sps` (`probe-engine2.log`) |
| `results/retain-round4-rerun.log`, `results/before-escape-rerun.log` | my reruns of the scoped review's two probes: 64.1 MB retained; case E cancelled the transfer 3 of 3, the controls whole |
| `results/round5-*` | round 5's red and green: the seam's retention (67,041,992 bytes before the fix), case E, case B held deterministic (20 of 20 on the mutant, 20 of 20 clean on the tree), the at-length test (a 28 at 10,007 ms on the mutant), and the escape child's loop, its hang before the plants changed and 600 cases after |
| `results/retain-final.log` | the scoped review's retain probe on the final tree: 0.0 MB retained |
| `results/mut-{seam-unarmed,before-cancel}-final.{diff,log}` | my mutants of round 5's two fixes on the final tree: each failed the test named for its rule |
| `mutants/` | the builder's mutation log, `mutants.md`, and its round 3, 4 and 5 tables |
