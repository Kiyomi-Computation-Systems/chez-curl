# ADR-0016: The floors have one source, `packaging/floors.sexp`

- **Status:** Accepted; amended 2026-10-16: CI reads the floors from the file (M0 slice 5); amended 2026-10-26: the current libcurl is no floor
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

## Amendment, 2026-10-16: CI reads the floors from the file (M0 slice 5)

- **CI states no floor.** `scripts/ci/floor.sh NAME` prints one floor from
  `packaging/floors.sexp`. It fails closed unless the file is one list of `(key "version")`
  entries, holding exactly one well-formed entry for NAME.
  - `build-chez.sh PREFIX [--nothreads]` and `build-curl.sh PREFIX [FLAGS...]` take no
    version, and read their floor through it.
  - So does every step that compares a version: the floor lane's check that `make build`
    loaded the floor, and `expect-missing-api.sh`'s version line.
  - The cache keys hash `packaging/floors.sexp` with the build script.
- **Why:** the first design wrote the floors once, as two env lines that every step
  referred to. A review showed that a job-level `env:` redefining `CURL_FLOOR_VERSION` to
  8.1.3 passed `check-floors`. The floor lane would then have built, and checked against, a
  libcurl that is not the floor. A text check cannot see a redefinition. A script that reads
  the file can't be handed one.
- **`make check-floors` holds every file under `.github/workflows/`,** subdirectories
  included. No line may contain either floor's version text, or name `CHEZ_VERSION` or
  `CURL_FLOOR_VERSION`. A missing or empty directory fails, and so does one with no
  `ci.yml`. A linked directory is not followed.
- **The tarball sums.** Each build script pins a sha256 per version, and a floor with no
  pinned sum fails. `test-check-floors` runs both scripts, up to their sum check, on the
  checked-in floors, so raising a floor without pinning its tarball fails `make test`.
- **Changing a floor edits:** the file, the README lines, `verify.sls`'s `libcurl-floor`,
  `require-threaded.sls`'s `minimum`, the literal rows that name the old floor, and the
  tarball's sum in its build script.
- **Not caught:** a step that builds a version without the scripts. A matrix value of
  another version reaches nothing, since the scripts take no version.
- **The Node floor is still unchecked:** nothing in CI uses Node until M1.

## Amendment, 2026-10-26: the current libcurl is no floor

CI gained a lane on the current libcurl, 8.20.0, built from source
([ADR-0020](0020-a-ci-lane-on-the-current-libcurl.md)). That version is pinned in
`scripts/ci/build-curl.sh` itself, as `current_version`, beside its sha256, and built with
`--current`. It is not a floor, so it is not in `packaging/floors.sexp`, and this record's
rules do not hold it: the file keeps its three keys, and `check-floors` the floors' versions
out of the workflows. The workflow states the current version nowhere either. The lane reads
it back from what it built.
