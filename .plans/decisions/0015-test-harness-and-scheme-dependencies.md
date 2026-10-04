# ADR-0015: Tests use SRFI-64 from a vendored chez-srfi pinned in Akku.lock, and the suite rules are checks

- **Status:** Accepted
- **Date:** 2026-10-04
- **Scope:** chez-curl's test suites and Scheme dependencies
- **Related:**
  - chez-cmark-gfm and chez-libuv: their `vendor/chez-srfi`, `Akku.manifest`, `Akku.lock` and
    `check-pins`;
  - chez-cmark-gfm ADR-0017 (no Akku scripts);
  - [ADR-0001](0001-bind-libcurl-directly.md) (whether to publish on Akku is open);
  - [ADR-0006](0006-pinned-guix-container.md) (no network in the container);
  - [the harness plan](../2026-10-04-harness-plan.md).

## Context

Both siblings test with SRFI-64 from a chez-srfi git submodule under `vendor/`, at commit
`7879b527f267f067416552fb989135ad1b4ea436`. `make deps` links it into
`build/scheme-libs`. Their `Akku.manifest` declares it as a development dependency
(`"^0.0.0-akku.181.7879b52"`). `Akku.lock` pins the same commit, and `make check-pins`
fails if the two disagree. chez-cmark-gfm's ADR-0017 rules out Akku scripts.

The 2026-10-04 survey found the siblings' suite rules are written down but never checked:

- **Every suite must end with its own `(exit …)`, but nothing checks it.** SRFI-64 sets no
  exit status, so a missing line makes a failing suite pass.
- **A suite that runs zero tests passes.**
- **chez-libuv's per-suite timeout is optional,** applied only when `timeout` is on `PATH`.
- **Load-time tests grep error text.** chez-libuv greps stderr for condition type names, and
  chez-cmark-gfm's grep for `load-failed` also matches its probe's own filename.
- **`make test` does not fail on a failing suite in any check that runs locally.** That check
  exists only as inline CI shell.

## Decision

1. **SRFI-64 comes from a chez-srfi submodule under `vendor/`,** at the siblings' commit
   `7879b52`.
2. **Akku declares and pins it.** `Akku.manifest` declares chez-srfi as a development
   dependency and runs no scripts. `Akku.lock` pins the same commit, and `make check-pins`
   fails when the submodule and `Akku.lock` disagree. Publishing chez-curl on Akku is still
   undecided (ADR-0001).
3. **`make deps` never fetches.** It links the checked-out submodule into
   `build/scheme-libs`. If the submodule is empty, it fails and points at
   `git submodule update --init` on the host. The container has no network (ADR-0006).
4. **The suite rules are checks:**
   - **`make check-suites`** reads every `tests/test-*.sps` as data. It requires each to end
     with the shared exit form, which fails when the runner saw a failure or saw no tests at
     all.
   - **`make test`** runs `check-help` and `check-suites` first. It then runs every suite,
     even after a failure, and fails if any did.
   - **Every suite runs under `timeout`.** `scripts/require-tools` makes `timeout` required.
     Exit status 124 is reported as HUNG, not as a failing assertion.
   - **`make check-test-fails`** plants a failing suite in a copy of the tree. `make test`
     must exit non-zero there and still run the suites after it.
5. **Probes and helpers sit outside the `test-*` glob.** A probe that exercises a refusal
   catches the condition and prints `(reason . symbol)`. Tests assert that symbol and never
   match error text.

### Rejected

- **Deferring Akku until publishing is decided.** The maintainer chose consistency with the
  siblings now.
- **Fetching inside `make deps`.** It cannot work in a network-less container.
- **Leaving the suite rules as prose.** Both siblings did, and each rule was broken.

## Consequences

- **`git submodule update --init` runs on the host,** before the first `make deps`.
- **Bumping chez-srfi takes two edits,** the submodule and `Akku.lock`, and `check-pins`
  holds them together.
- **A suite that forgets its exit line, runs no tests, or hangs fails by name.** None can
  pass silently.
