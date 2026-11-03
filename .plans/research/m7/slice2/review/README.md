# M7 slice 2's review probes (2026-11-02)

The slice's adversarial review (Opus, read-only) wrote these in `build/m7s2-review/`, where
they ran; `results/` holds its logs. To rerun one, copy them back there first, from the
repository's root: `mkdir -p build/m7s2-review && cp .plans/research/m7/slice2/review/*.s* build/m7s2-review/`,
then the command in each file's header.

- **`leak.sps`, `leak2.sh` and `leak2.sps`:** a request with credentials, then `(write request)`,
  `(write token)`, and `display-condition` of each assertion that hands the token over as its
  irritant. Before the fix each printed the password, and `leak2` another live request's Bearer
  token through the engine's table ([`results/leak.log`](results/leak.log),
  [`results/leak2.log`](results/leak2.log)). I reran `leak.sps` on Guix's 8.20.0 before the fix
  round, every line `YES` ([`results/leak-rerun-before-fix.log`](results/leak-rerun-before-fix.log)),
  and after it, every line `no`, the token printing as `#<curl-token>`
  ([`results/leak-rerun-after-fix.log`](results/leak-rerun-after-fix.log)).
- **`make-mutants.sh` and `run-mutants.sh`:** the review's four mutants, `scan-skips-first`,
  `authorization-first-only`, `refusal-holds-record` and `bytes-refuses-dquote`, each passing
  test-auth on the build ([`results/mutants-run.out`](results/mutants-run.out) and the
  `mutant-*` logs); I reran the first two, and each passed test-auth again
  (`mutant-*.mine.log`). The fix round remade all four on its tree, and each failed.
- **`inject.sps`:** under `scan-skips-first`, `(bearer "\nX-Inj: 1")` wrote a header of its own
  ([`results/inject.log`](results/inject.log)).
- **`record-irritant.sps`, `reflect.sps` and `printer.ss`:** a secret inside a record that the
  suite's `leaked` could not see; `record-rtd` reading and changing a request's private copy
  before the records were opaque; an opaque record printing as its type alone.
- **`probe.sps`:** Digest beside a `put` and over h2c by prior knowledge, on Guix's 8.20.0 and
  the floor's 7.85.0 ([`results/probe-guix.log`](results/probe-guix.log),
  [`results/probe-floor.log`](results/probe-floor.log)): a `put` with a body goes twice to a
  server that never challenges, as a `post` does.
- **`hl-userinfo.sps`:** the high level's URL reading treats empty userinfo as the low level
  does, on both lanes.
