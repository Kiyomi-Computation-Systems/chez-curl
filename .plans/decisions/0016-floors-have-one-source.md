# ADR-0016: The floors have one source, `packaging/floors.sexp`

- **Status:** Accepted
- **Date:** 2026-10-16
- **Scope:** every statement of the Chez, libcurl and Node floors
- **Settles:** the harness plan's §3 item 5
- **Related:** [ADR-0001](0001-bind-libcurl-directly.md) (the Chez floor) ·
  [ADR-0003](0003-libcurl-floor-7-85.md) (the libcurl floor) ·
  [ADR-0005](0005-node-test-origin.md) (the Node floor) ·
  [the harness plan](../2026-10-04-harness-plan.md)

## Context

A floor is written in several places: the code that enforces it, the README that promises
it, and later CI, which builds Chez at the floor and runs a lane against curl at its floor.
chez-libuv states its Chez floor three times and checks none of them. When the places drift
apart, the README promises a version the code refuses, or CI tests a version nobody
supports.

## Decision

1. **`packaging/floors.sexp` holds the floors,** as one datum:
   `((chez "10.4.0") (libcurl "7.85.0") (node "20"))`.
   - The keys are exactly `chez`, `libcurl` and `node`, in that order.
   - `chez` and `libcurl` have three numbers, which is how the code compares them: a list
     of three, and `version_num`. `node` has one or more.
   - Each number is ASCII digits with no leading zero, so text and numbers round-trip.
2. **`make check-floors` holds the prose to it, and `make test` runs it.** README.org's
   `** Requirements` section must hold exactly the three list lines the file calls for, in
   order. Text between them is ignored. A malformed file fails the check, naming the
   problem.
3. **The code is held to it by behaviour, not text.**
   - `test-verify` requires `libcurl-floor` to equal the file's libcurl floor as a
     `version_num`. `check-version` must accept that floor and refuse the version one below
     it.
   - `test-require-threaded` builds rows from the file's Chez floor: the floor loads, and
     a pre-release of it is refused, with a message naming the floor.
   - The suites keep their literal rows too, so changing a floor shows up in their diffs.
4. **`check-test-fails` plants a README that disagrees with the file,** and `make test` must
   fail on it, naming the line.

### Rejected

- **Generating the code's floors from the file.** `require-threaded`'s check runs at
  expansion, and a library contains its own code (AGENTS.md), so it can't read a data file.
  Checking behaviour gets the same guarantee.
- **Reading the floor out of the source as text.** A change to the code's shape would break
  the check without any change to the floor.

## Consequences

- **Changing a floor edits:** the file, the README lines, `verify.sls`'s `libcurl-floor`,
  `require-threaded.sls`'s `minimum`, and the literal rows that name the old floor. Each
  place left behind fails by name.
- **A floor can't be rehearsed upward on the Chez that runs the suites.** Raised past the
  running Chez, the Chez floor makes every library refuse at import.
- **Slice 5 adds CI's workflow to what `check-floors` holds.** `docs/` joins it when it has
  a requirements statement.
- **Not yet checked against the file:**
  - the Node floor, which no code reads until the test origin lands in M1;
  - the floors named in comments;
  - the decoy libcurl's 7.85.0, in `tests/decoy-libcurl.c`.
