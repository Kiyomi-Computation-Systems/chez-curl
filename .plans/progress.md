# Progress ledger

Where chez-curl stands. Read it with [global-constraints.md](global-constraints.md)
before starting slice work. When a slice merges, update **Now** and add a
close-out under **Close-outs**, newest first.

## Now

- **Milestone:** M0 (brief §8), not started.
- **Next slice:** the development container from
  [ADR-0006](decisions/0006-pinned-guix-container.md). That is `scripts/guix-env`,
  `scripts/guix-env-enter`, `scripts/require-tools`, `manifest.scm`, `channels.scm`, and
  a `Makefile` with `help`, `check-help` and `check-guix`, following
  `~/src/cl-commonmark-gfm`. AGENTS.md gains its container section in the same slice.
- **Waiting on evidence:** ADR-0013 (`__collect_safe`) stays Proposed until spike E1
  at M3. Until then its rules bind as written.
- **Loose ends:**
  - The brief's status line still reads "draft — nothing accepted yet". Where the brief
    and an ADR disagree, the ADR is current.
  - AGENTS.md says `CHANGELOG.md`, but the repository has `CHANGELOG.org`.

## Close-outs

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
