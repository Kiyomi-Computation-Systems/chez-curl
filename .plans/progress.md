# Progress ledger

Where chez-curl stands. Read it with [global-constraints.md](global-constraints.md)
before starting slice work. When a slice merges, update **Now** and add a
close-out under **Close-outs**, newest first.

## Now

- **Milestone:** M0 (brief §8), not started.
- **Next slice:** slice 1 of the [harness plan](2026-10-04-harness-plan.md) (§6). That is
  the development container from [ADR-0006](decisions/0006-pinned-guix-container.md), now
  with Valgrind, and the Makefile skeleton (`help`, `check-help`, `check-guix`). It
  follows `~/src/cl-commonmark-gfm`. AGENTS.md gains its container and traps sections in
  the same slice.
- **Waiting on evidence:** ADR-0013 (`__collect_safe`) stays Proposed until spike E1
  at M3. Until then its rules bind as written.

## Close-outs

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
