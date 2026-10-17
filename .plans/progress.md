# Progress ledger

Where chez-curl stands. Read it with [global-constraints.md](global-constraints.md)
before starting slice work. When a slice merges, update **Now** and add a
close-out under **Close-outs**, newest first.

## Now

- **Milestone:** M0 (brief §8), in progress.
- **Done:** slices 1 to 5 of the [harness plan](2026-10-04-harness-plan.md) (§6):
  - slice 1, the container and the Makefile skeleton;
  - slice 2, the test harness
    ([ADR-0015](decisions/0015-test-harness-and-scheme-dependencies.md));
  - slice 3, loading (ADR-0001, ADR-0002, ADR-0003, ADR-0007, all amended), with its
    [mutation log](loading-mutation-log.md);
  - slice 4, constants and layouts (ADR-0001, ADR-0007 and ADR-0013 amended, ADR-0016
    new), with its [mutation log](constants-mutation-log.md);
  - slice 5, the memory gate and CI (ADR-0014 amended), with its
    [mutation log](memory-ci-mutation-log.md).
- **First macOS run,** 2026-10-16, on the maintainer's Mac: Apple silicon (M1, so arm64),
  Homebrew's Chez 10.4.1, Apple's libcurl 8.7.1. `make test` passes all 13 suites, after a
  fix: a bare `mktemp -d` ignored `TMPDIR` there (`traps.md`). So macOS has run on arm64;
  Linux on arm64 and macOS on amd64 have not.
- **CI has never run.** Every job of PR #8 was "not started because recent account payments
  have failed or your spending limit needs to be increased". GitHub parsed the workflow and
  listed all six jobs, so the file is valid. What only CI can show is still unshown: Chez
  built from its tarball on the runner, a real `--nothreads` Chez, the suites under Ubuntu's
  Valgrind 3.22, and the jobs' times.
- **In progress:** slice 6, which closes M0, on `m0/variadic`, with its
  [mutation log](variadic-mutation-log.md):
  - the variadic bindings: `curl_easy_setopt` once per value type, and `curl_easy_getinfo`,
    through `bind-variadic`. `test-variadic` round-trips each value through libcurl with no
    transfer, and `make check-variadic` plants a missing `(__varargs_after 2)`, per binding
    (ADR-0001, amended);
  - `test-collect-safe` closed the routes round the binding macros that two reviews found,
    open since slice 4. Every macro `src/` defines is now a row of `known-macros`
    (ADR-0013, amended), and `check-seam`'s rules (h) and (i) keep every library `src/`
    imports in `src/`, at its name's path (ADR-0007, amended);
  - `make dev` and `make clean`, which the brief's M0 names, held by `check-dev` and
    `check-clean`;
  - the decision-time probes accounted for: which became tests, and `curl_url`'s verdicts
    moved to M2 (the harness plan, §6; ADR-0008, amended).

  Every check passes in the container. **Waiting on the maintainer's M1:** `make test` and
  `make check-variadic` on Apple arm64, the only ABI where a missing annotation fails.
- **Decided for M2,** by the maintainer:
  - one checked wrapper owns every copy between a bytevector and foreign memory;
  - the counters become the leak gate, since Valgrind cannot see Chez's heap (ADR-0001,
    ADR-0014, amended).
- **Settled before slice 5:** the leak in the container. Loading libcurl there loses one
  block in Guix's glibc, and Ubuntu 24.04 loses nothing (`traps.md`). ADR-0014 now allows
  one suppression for it, passed in the container only.
- **Waiting on evidence:** ADR-0013 (`__collect_safe`) stays Proposed until spike E1
  at M3. Until then its rules bind as written.
- **Open for M3:** a first reference to `(curl)` from a second thread, made while the load
  runs, raises `cyclic dependency` (ADR-0002's amendment).

## Close-outs

### 2026-10-17 — M0 slice 5: the memory gate and CI (PR #8, `eda03a2`)

- **Valgrind is the memory gate** (ADR-0014). `make test-memory` runs every suite under
  exactly the gate's command, and a suite passes only on evidence from Valgrind's own log:
  its command, the Chez it read, and no errors. It refuses every `VALGRIND_*` variable and
  both `.valgrindrc` files, and holds each suite's options and suppressions to the gate's.
- **One suppression, in the container only.** Loading libcurl there loses one block in Guix's
  glibc. Ubuntu 24.04 loses nothing, so CI passes no suppression.
- **`make check-memory-gate` must see it fail:** a planted overrun, a planted leak, each
  hidden source of options, a forged log, and a run with no evidence.
- **CI's workflow:** the `main`, `floor`, `floor-disabled-api` (two lanes), `nothreads` and
  `memory` jobs. The gate runs on every pull request, push to `main` and tag, and actions are
  pinned to full SHAs. CI states no floor: its build scripts read `packaging/floors.sexp`
  (ADR-0016, amended), and `check-floors` holds every workflow file to that.
- **`make check-nothreads`** requires every public library to refuse, by name, a Chez built
  without threads. It fails on a threaded Chez by design, so CI runs it on a `--nothreads`
  build.
- **Valgrind cannot see Chez's heap.** An overrun into a bytevector passes, and so does a
  dropped block whose address an ftype pointer held. So `test-collect-safe` now holds every
  binding's types to an allowlist, and refuses a heap crossing without a reviewed mark. For
  M2, the maintainer decided on one checked wrapper for bytevector copies, and the counters
  as the leak gate.
- **Built with subagents,** nine in all, about 3.2M tokens, the most yet.
  - Each of three reviews found a class the last fix had left open: a deny list that
    `VALGRIND_LIB` walked round, passes taken from empty output, a pattern variable spelt
    like an allowed type, and a floor redefined in a job's `env:`.
  - The lesson: brief a check as "passes only on evidence", never as "refuses X".
- **Evidence:** the [mutation log](memory-ci-mutation-log.md), in eight parts. Every check
  has a red run, and every mutation fails its check by name.
- **Carried forward:**
  - CI's first run, once billing allows. Expect it to need fixes.
  - For M2: the checked bytevector wrapper, the counters as the leak gate, and `lock-object`
    for every callable C holds (ADR-0013).
  - Valgrind follows no child process, so the Chez processes `test-library-loading` spawns
    run unchecked.

### 2026-10-16 — M0 slice 4: constants and layouts, the convention suite and the floors (PR #7, `ba42f70`)

- **Checks constants and struct layouts against libcurl's own headers.** `test-constants`
  generates one C program from `constants.sls`'s exports and `layouts.sls`'s
  `define-ftype`s. It checks each constant's value, and each field's offset, size and kind.
  A C name follows from its Scheme name. The headers must be no newer than the library
  `(curl)` loads.
- **The structs live in `(curl private layouts)`,** held to struct `define-ftype` forms
  alone.
- **Checks every binding's conventions.** `test-collect-safe` holds every
  `foreign-procedure` and `foreign-callable` to a table, each row quoting the record
  sentence behind it. `curl_easy_perform` and `curl_multi_poll` already have
  `__collect_safe` rows (ADR-0013).
- **The floors have one source,** `packaging/floors.sexp` (ADR-0016). `make check-floors`
  holds the README to it, and the suites hold the code to it by behaviour.
- **`check-seam` rules (f) and (g)** keep `define-ftype` in layouts and stop any library
  re-exporting a Chez name. A function ftype would bind C that no other check sees.
- **The first macOS run,** on the maintainer's M1, passes all 13 suites. Two fixes got it
  there. A bare `mktemp -d` ignored `TMPDIR` on macOS, and Homebrew installs Chez as
  `chez`.
- **Built with subagents,** eight in all, about 2.1M tokens: the builders on Opus, Opus and
  Sonnet, two reviews on Opus, and two fix rounds.
  - The first review found that function ftypes could bind C unseen, and that nothing tied
    the headers to the library. Fields of the wrong kind passed, a test asserted message
    text, and a constant's C name was free text.
  - The review of the fixes walked round the `define-ftype` rule three ways: re-export, a
    macro argument, and an exported macro. That was a flaw in the fix brief, which named too
    narrow a class.
- **Evidence:** the [mutation log](constants-mutation-log.md), in six parts. Every check has
  a red run, and every mutation fails its check by name.
- **Carried forward:**
  - CI's floor lane must point both `C_INCLUDE_PATH` and `CHEZ_CURL_LIBCURL` at curl
    7.85.0, and CI's workflow joins what `check-floors` holds.
  - Known limits: the kind check can't tell a pointer from an aggregate of the same size,
    a name built at expansion is out of the convention suite's reach, and rule (g) sees
    bindings only.
  - Linux on arm64 and macOS on amd64 have not run.

### 2026-10-16 — M0 slice 3: loading libcurl, `(curl)` and the seam check (PR #6, `bfc3aa6`)

- **Loads libcurl as ADR-0002 says.** Discovery is a pure function of the environment: the
  override, or one candidate list per world. `native.sls` then loads once, reads
  `curl_version_info` first, checks the floor and SSL, calls `curl_global_init` once,
  binds every entry point after `foreign-entry?` finds it, and runs the two API probes.
- **Refusals stick.** Each is one of six reason symbols and carries the library's report
  once its version is read. `(curl private load-state)` records the first failure and raises
  it again at every later reference, so libcurl is never loaded twice.
- **`(curl)` reports what it loaded:** the path, its source, the version, the features and
  the TLS backend. `make build` is the preflight that prints it.
- **Refuses an unusable Chez by name:** one older than 10.4.0, a 10.4.0 pre-release, or one
  without threads, at expansion.
- **`check-seam` guards ADR-0007's boundary with allowlists,** and `make test` runs it.
  Every `src/` library is in one of the two families, and file endings Chez would load but
  the check can't read are refused by name.
- **Tests without the real thing:** decoy libcurls compiled at test time, a C oracle that
  reads the same library through `dlopen`, and an in-process suite for `native.sls`.
- **Built with subagents,** eight in all, about 2.8M tokens: the pure core and the native
  layer on Opus, `check-seam` on Sonnet in its own worktree, two reviews on Opus and three
  fix rounds.
  - The first review found a flaw in the brief itself: its import-order rule contradicted
    ADR-0007. It also found refusals that didn't stick, and tests that would fail on CI.
  - The second review found fixes that blocked only the reviewer's examples, a cleanup that
    could remove the wrong directory, and rules tested only in scratch.
- **Evidence:** the [mutation log](loading-mutation-log.md), in six parts. Every check has a
  red run, and every mutation fails its check by name.
- **Carried forward:**
  - Loading GnuTLS's libcurl leaks a block in p11-kit, which fails ADR-0014's gate. Decide
    before slice 5.
  - At M3, a first reference to `(curl)` from a second thread, while the load runs, raises
    `cyclic dependency`.
  - CI must run `make build`, which `make test` doesn't. The disabled-API lane should run the
    preflight and expect `missing-api`, rather than the full suite.
  - Nothing has run on macOS or arm64 yet.

### 2026-10-04 — M0 slice 2: the test harness (PR #5, `9bacc6d`)

- **Pinned SRFI-64.** `vendor/chez-srfi` is a submodule at `7879b52`, recorded in
  `Akku.lock`. `make deps` links it and never fetches. `make check-pins` holds the lock, the
  gitlink and the checkout equal, on the host.
- **Built the test loop.** `make test` runs every suite under GNU `timeout` (or `gtimeout`),
  names each as pass, FAIL or HUNG, and fails if any failed or hung, or if none exists.
- **Turned the suite rules into checks.**
  - `check-suites` requires the shared exit form last, and allows only `(exit 1)` before it.
  - `check-test-fails` plants eight bad cases, and `make test` must fail on each, by name.
- **Shared helpers** live in `tests/curl-testing.sls`. The exit verdict is 0 or 1, never a
  count, because exit statuses wrap at 256.
- **Took git out of the container again.** In a git worktree, the container's git could read
  nothing, so `make test` and `make check-guix` failed there. A `no-git` self-test assertion
  keeps it out (ADR-0006 amended).
- **Built with subagents.** Sonnet did the pins, Opus the harness core and an adversarial
  review, and Sonnet the review's fixes. The review found the worktree failure, a flaw in
  the brief itself.
- **Evidence:** the [mutation log](test-harness-mutation-log.md). Each check has a red run,
  and each mutation fails its check by name. The rewritten `check-suites` got fresh mutants
  after the fixes.
- **Carried forward:**
  - `capture-command` shares one counter across threads and writes predictable `/tmp`
    names. Fix it before the first threaded suite (M3).
  - `check-suites` refuses a suite that starts with a `#!` line.
  - The Node origin's helpers wait for the slice that adds `tests/origin.mjs`.

### 2026-10-04 — M0 slice 1: the pinned container and the Makefile skeleton (PR #4, `e8a2f63`)

- **Built ADR-0006's container, with Valgrind.** `scripts/guix-env` runs the pinned
  toolchain with no network. `make check-guix` tests the launcher on the host (60 checks),
  then checks the container from inside. A cached start takes about 1.5 s.
- **Checked the help.** `check-help` holds `make help`'s own listing equal to `.PHONY`,
  both ways.
- **Measured, and amended ADR-0006:**
  - the pinned toolchain has no `cc`, so the container exports `CC`;
  - `--emulate-fhs` does not let Guix's Chez load a library by bare name;
  - `LD_LIBRARY_PATH` does, so the self-test asserts that such a load fails.
- **Evidence:** the [mutation log](guix-env-mutation-log.md) records 50 mutations, each
  failing its check by name. The red run caught a launcher test that passed for the wrong
  reason.
- **Carried forward:** `GOAL`'s `MAKECMDGOALS` branch stays unexercised until a target
  reaches `require-tools` through a prerequisite, which is slice 2's `test`.

### 2026-10-04 — living brief, harness plan, memory and test records (PR #3, `ea56eb4`)

- **The brief is a living document,** accepted for M0. It cites the records and defers to
  them where they disagree.
- **Recorded how M0 checks itself:**
  - ADR-0014: Valgrind on Linux is the memory gate, and it must be seen to fail.
  - ADR-0015: SRFI-64 comes from a vendored chez-srfi pinned in `Akku.lock`, and the suite
    rules are checks.
- **Planned the harness.** The harness plan covers what M0 copies from chez-cmark-gfm and
  chez-libuv, seven improvements on them, CI's lanes, and five slices.
- **Corrected two records:**
  - ADR-0006 gained Valgrind. It had been lost by copying cl-commonmark-gfm's container
    rather than chez-cmark-gfm's.
  - ADR-0013's E5 figures are chez-http-server's, measured on macOS only.
- **Renamed** `CHANGELOG.org` to `CHANGELOG.md`.
- **Carried forward:** close-outs written after a merge still land one PR late, as this
  one does.

### 2026-10-04 — ledger, constraints and the engine records (PR #2, `9077e28`)

- **Moved the ledger to `.plans/`.** AGENTS.md names this file as the ledger and
  `global-constraints.md` as the hard rules every task brief must follow. `/.superpowers/`
  is git-ignored plugin scratch.
- **Recorded the brief's engine rules.** ADR-0012 (accepted): one engine thread owns every
  transfer handle. ADR-0013 (proposed until spike E1): blocking calls are `__collect_safe`,
  and so is every callback they can invoke.
- **Carried forward:** close-outs written after a merge land one PR late, as this one did.

### 2026-10-04 — open decisions settled (PR #1, `407a8c5`)

- **Settled:** D1 to D11, as ADR-0001 to ADR-0011. That is the brief's D1 to D5, plus
  D6 to D11 raised while checking the brief against this host.
- **What changed the brief:**
  - Chez 10's `(__varargs_after n)` removed the C shim (ADR-0001).
  - Guix Chez cannot load the host's libcurl, so discovery reads which world it runs in
    (ADR-0002).
  - The floor moved to 7.85.0 for `CURLOPT_PROTOCOLS_STR` (ADR-0003).
  - A container without `--network` keeps tests on loopback (ADR-0006).
- **Carried forward:** the probes run while deciding are M0's first tests in waiting:
  - varargs setopt;
  - the census of the options API;
  - world detection via `/proc/self/maps`;
  - `curl_url`'s verdicts;
  - the header-API probe;
  - the loopback-only container.

  They lived in session scratch and need writing as real tests.
