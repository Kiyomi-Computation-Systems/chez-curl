# chez-curl harness plan: what we copy from chez-cmark-gfm and chez-libuv

Date: 2026-10-04
Status: accepted. The maintainer approved the improvements in §3, and the choices in
ADR-0014 and ADR-0015, on 2026-10-04.
Sources: chez-cmark-gfm at `e0118a3` and chez-libuv at `d46654c`, both `main`, surveyed
read-only. The container follows cl-commonmark-gfm (ADR-0006).
Decisions: [ADR-0001 to ADR-0015](decisions/). ADR-0014 (the memory gate) and ADR-0015 (the
test harness) come from this plan.
Ledger: [progress.md](progress.md). House rules: [global-constraints.md](global-constraints.md).

The aim is consistency across the family. chez-curl copies a sibling's working harness
wherever one exists, changes only what its decisions require, and fixes the gaps the
survey found. Citations name files, symbols and targets, never line numbers.

## 1. What chez-curl copies

| Piece | From | What changes |
|---|---|---|
| Makefile skeleton: `help`, `check-help`, `.DEFAULT_GOAL := help`, `.PHONY` on one line | chez-libuv `Makefile` | `check-help` checks both directions, and `make test` runs it |
| `make test`: every `tests/test-*.sps` runs, even after a failure; exit codes combined; per-suite `timeout`, with HUNG on exit 124 | chez-libuv `Makefile` (`test`) | `timeout` required via `scripts/require-tools`; `CHEZ ?= scheme` |
| SRFI-64 from `vendor/chez-srfi` at `7879b52`, linked into `build/scheme-libs` by `make deps` | both | `make deps` never fetches (ADR-0015) |
| `Akku.manifest` (development dependency, no scripts), `Akku.lock`, `make check-pins` | both | chez-srfi only (ADR-0015) |
| `make build` as a preflight that prints what loaded | chez-cmark-gfm `tests/preflight.sps` | prints ADR-0002's path, source, version, features and TLS backend, or the reason symbol and its remedy |
| Probes named outside the `test-*` glob; load-time tests in subprocesses; decoy libraries | chez-cmark-gfm `tests/test-library-loading.sps`, chez-libuv `tests/test-shim-loading.sps` | probes print `(reason . symbol)`, and tests assert it |
| Test helpers: `capture-command`; `run-until`, which answers with symbols and caps by iterations; seeded bytes; `describe` | chez-cmark-gfm `tests/cmark-testing.sls`, chez-libuv `tests/uv-testing.sls` | one `tests/curl-testing.sls`. Command arguments are quoted. Adds the Node origin's lifecycle: spawn it, read its JSON line, close its stdin |
| Discovery as a pure function with injected file access, tested on synthetic listings | chez-cmark-gfm `discovery.sls` | ADR-0002's worlds and candidate lists |
| Loading as ordered definitions: the library first, then the version binding, then the version check (itself a definition), then everything else | chez-cmark-gfm `native.sls` | ADR-0003's probes; optional functions bound via `foreign-entry?`, not a catch-all `guard`; `load-failed` keeps the loader's message |
| Conditions: a base type, subtypes and reason symbols | both `conditions.sls` | `&curl-error`, ADR-0002's six reasons, `&curl-wrong-thread` |
| Refusing a non-threaded Chez at expansion; the suite that scans source; the non-threaded check script | chez-libuv `require-threaded.sls`, `test-require-threaded.sps`, `docker/check-nothreads.sh` | scans `(curl …)` and `(http-client …)`; runs as a CI lane, not in Docker (§4) |
| One central owner-thread check | chez-libuv `require-loop-thread` | the engine's owner is fixed when it starts, and never transfers |
| A fence around the one thread-safe call | chez-libuv's fence for `uv-async-send!` | fences enqueue-plus-`curl_multi_wakeup` against engine shutdown |
| Scope records: `alive?`, checked accessors, a `release!` that is safe to repeat, a `dynamic-wind` re-entry check | chez-cmark-gfm `scope.sls` | request groups and response ports (M5, M6) |
| Always-on counters that tests must see move and return to zero | chez-cmark-gfm `native.sls` counters | per engine, in Scheme |
| Memory gate: `test-memory`, `check-memory-gate`, `memory-gate-sabotage.sps` | chez-libuv `Makefile` | ADR-0014 |
| CI: Chez from the release tarball with split cache restore and save; `RUN_MEMORY` gating with a notice; versions recorded; one package list that fails closed | chez-libuv and chez-cmark-gfm `ci.yml` | §4 |
| Mutation logs in the newer format | chez-cmark-gfm `guix-env-mutation-log.md`, chez-libuv `require-threaded-mutation-log.md` | none |
| Spikes: `spike/<topic>/NN-*.sps` beside a `FINDINGS.md` | chez-libuv `spike/threading/` | programs committed (§3) |
| `.plans/traps.md` with one-line rules in AGENTS.md; the CHANGELOG format; the PR template's checklist; the gates in CONTRIBUTING | both | the general traps only (§5) |

The newer mutation-log format has one section per check: Guards, Mutation, Result and Clean
rerun. It records a red run made before the code existed, a baseline with its commit, and
what is "Not covered".

A spike's `FINDINGS.md` holds a toolchain table, a verdict table, each claim's exact command
with its verbatim output, every claim run twice, and a "Deliberately untested" list.

## 2. What chez-curl leaves behind

- **The C shim and everything built around it:** the C flags, the generated `config.sls`,
  the relink guard and stamps, and `prod`/`check-prod` (ADR-0001).
- **chez-cmark-gfm's vendored C library,** its command-line oracle, its differential suites
  and its docs site.
- **The Docker images** (`valgrind.Dockerfile`, `nothreads.Dockerfile`). The Guix container
  is the Linux box (ADR-0006), and the non-threaded check moves to CI.
- **The macOS ASan CI arm.** CI is Linux only; ASan stays a local supplement (ADR-0014).
- **libuv-specific knobs:** `UV_USE_IO_URING`, `test-root`, and the registry's late-install
  dispatcher.

## 3. Improvements over the siblings

Each closes a gap the survey found in a sibling.

1. **Checks behind written rules** (ADR-0015).
   - `check-suites` requires every suite's exit line, and fails a suite that ran no tests.
   - `make test` runs `check-help`; chez-libuv's never did.
   - `check-test-fails` becomes a make target. The siblings had it only as inline CI shell.
   - `timeout` is required.
2. **Reason symbols, not error text.** Refusal probes print `(reason . symbol)` (ADR-0015).
3. **`__collect_safe` attributes are checked.** A pure suite reads `src/` as data. It holds
   each `foreign-procedure` and `foreign-callable` convention against a table that cites
   ADR-0013. Neither sibling checks attributes.
4. **State is per engine.**
   - Tables and counters belong to their engine, not the process. chez-libuv's registry is one
     unsynchronised table shared by every loop.
   - The enqueue-and-wakeup is fenced against engine shutdown.
5. **The floors have one source.** The Chez, libcurl and Node floors live in one file.
   `make check-floors` asserts that the README, the docs, CI and the Scheme version check
   agree with it. chez-libuv states its Chez floor three times and checks none.
6. **CI hardening:**
   - a pinned `ubuntu-24.04` runner;
   - a Chez cache key that covers its configure flags and build steps;
   - `test-memory` that collects every failure (ADR-0014).
7. **Spike and citation hygiene.** Spike programs are committed; chez-cmark-gfm's never were.
   Citations name a file, symbol or target. Both siblings carry stale line-number citations.

## 4. CI

One workflow, Linux only (AGENTS.md), on a pinned `ubuntu-24.04`.

- **The main job, on every push and pull request.**
  - It runs `check-help`, `check-suites`, `check-pins`, `check-seam`, `check-floors`,
    `build` (the preflight), `test` and `check-test-fails`.
  - Chez 10.4.0 is built from the release tarball, and cached.
  - libcurl is the runner's, found by discovery.
  - Node is the runner's: 22, against a floor of 20.
  - Packages come from `packaging/debian-prereqs.txt`.
- **The GnuTLS lane, from M2.** The suite runs again with `CHEZ_CURL_LIBCURL` naming the
  runner's `libcurl-gnutls.so.4`. This gives brief §9 risk 3 its second backend (ADR-0002).
- **The floor lane.** It builds curl 7.85.0 from the release tarball, caches it by version,
  and runs the suite against it through the override. A variant built with
  `--disable-get-easy-options --disable-headers-api` must be refused with `missing-api`
  (ADR-0003).
- **The non-threaded lane.** It builds Chez 10.4.0 with `--nothreads`, under its own cache key.
  The non-threaded check then requires every public library's import to be refused, by name.
- **The memory lane, on `main`, on tags and on request.** It runs `check-memory-gate`, then
  `test-memory` (ADR-0014).
- **Nothing in CI runs the Guix container** (ADR-0006).

## 5. Traps carried into AGENTS.md

These are general traps, copied with their one-line rules. Their incidents go in
`.plans/traps.md`.

- **`guard` returns the body's value when nothing raises, and `0` is truthy.** Assert what
  was raised, with a separate sentinel for "nothing raised".
- **SRFI-64 turns an exception in the actual expression into `#f`.** Never expect `#f` from
  code that can raise.
- **Every suite ends with its own `(exit …)`.** `check-suites` now checks it.
- **Compiled library code evaluates arguments right to left.** No assertion may depend on
  argument order.
- **`foreign-procedure` resolves its entry point when evaluated.**
- **A library body runs only when one of its bindings is referenced.** Load-time tests must
  call into the library.
- **`$CHEZ` must be the real binary,** neither a symlink nor a wrapper. `check-guix` checks it.
- **`timeout` goes outside Valgrind,** never between it and Chez.
- **An assertion passes whenever another rule can produce its expected value.** Assert whole
  outputs, and build test bases from non-default values.
- **Deleting a subsystem disarms its checks.** Ask what would make each surviving check
  fail.

## 6. Order of work: M0's slices

1. **Container and Makefile skeleton** (ADR-0006, with Valgrind).
   - `scripts/guix-env`, `scripts/guix-env-enter`, `scripts/require-tools` and
     `scripts/guix-env-selftest`.
   - `help`, `check-help` and `check-guix`.
   - AGENTS.md's container and traps sections, and `.plans/traps.md`.
2. **Test harness** (ADR-0015).
   - The chez-srfi submodule, `Akku.manifest`, `Akku.lock`, `check-pins` and `deps`.
   - The `test` loop, `check-suites` and `check-test-fails`.
   - `tests/curl-testing.sls` and `packaging/debian-prereqs.txt`.
3. **Loading** (ADR-0001, ADR-0002, ADR-0003).
   - `require-threaded`, the conditions, and pure discovery with its suite.
   - `native.sls`, with the load order, the version check and the probes.
   - `make build` as the preflight, the refusal probes, and `check-seam`.
4. **Constants and layouts** (ADR-0001).
   - `check-constants`, the C program compiled at test time.
   - The `__collect_safe` attribute suite.
   - The floors file and `check-floors`.
5. **Memory gate and CI** (ADR-0014).
   - `test-memory` and `check-memory-gate`.
   - `.github/workflows/ci.yml` with §4's lanes.

The probes run while deciding become tests in slices 3 and 4: varargs setopt, the census of
the options API, world detection, `curl_url`'s verdicts, the header-API probe, and the
loopback-only container (progress.md, PR #1's close-out).
