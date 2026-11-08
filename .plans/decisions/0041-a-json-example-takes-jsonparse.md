# ADR-0041: A JSON example takes jsonparse, one pinned submodule, and headers get a page

- **Status:** Accepted
- **Date:** 2026-11-08
- **Scope:** chez-curl v1, M8 slice 5: docs and one example for headers and a JSON API, before
  the release ([ADR-0038](0038-m8s-scope.md), decision 3: the docs)
- **Settles:** where JSON comes from in chez-curl's docs, how that library arrives, what an
  example may import, and the page. The maintainer chose on 2026-11-08, the recommended option
  each time, from a reading of jsonparse's repository and of the docs as merged.
- **Related:**
  - [ADR-0025](0025-the-high-levels-surface.md), decision 3: no JSON, encoding and decoding stay
    the caller's;
  - [ADR-0015](0015-test-harness-and-scheme-dependencies.md): chez-srfi, a submodule pinned in
    Akku.lock, linked by `make deps`, which never fetches;
  - [ADR-0006](0006-pinned-guix-container.md): the container has no network;
  - [ADR-0038](0038-m8s-scope.md), amended 2026-11-08: an example imports public libraries
    alone.

## Context

On `main` at `9d2f573`:

- **Headers have no section of their own** in the docs: `headers` is one key in the high level's
  list, with one sentence on how a call's replaces a session's, and the low level's reference
  entry lists the header refusals' reasons.
- **No example sends or reads JSON,** and the test origin answers no JSON: `/echo` answers with
  the request as text.
- **jsonparse** (`Kiyomi-Computation-Systems/jsonparse`, BSD-3-Clause, public) is an R6RS JSON
  library at `0.0.0`, unreleased, its M1 closed at `2e3ae12b`. Its `(jsonparse easy)` reads a
  document from a string, bytes or a port and writes one back. Its parser, `(generated
  jsonparse)`, imports byte-machine's runtime, `^0.8.0`, which jsonparse keeps as a pinned
  submodule of its own (`c1f77911`, v0.8.0), beside a chez-srfi at chez-curl's commit. It is on
  no Akku archive. Its CI's floor is Chez 10.4.1 (its `.github/workflows/ci.yml`), and
  byte-machine's README asks for 10.4.1 or newer; chez-curl's floor is 10.4.0.
- **Every example imports** `(rnrs)`, `(curl)`, `(curl unsupported)` and `(http-client)` alone,
  and runs with `--libdirs src`, which `tests/test-examples.sps` holds.

## Decision

1. **A slice before the release,** so 0.1.0's docs hold it: M8 has six slices, the release
   the sixth (the M8 plan, §3.10).
2. **jsonparse is a dependency of one example alone,** `examples/json-api.sps`. No library under
   `src/` imports it, which `check-seam` holds, and `test-examples` runs it, through the
   example; no check keeps another suite from importing it. chez-curl keeps no JSON of its own
   (ADR-0025, decision 3): the example shows a caller doing it.
3. **One submodule, `vendor/jsonparse`, pinned by its gitlink;** byte-machine comes as
   jsonparse's own submodule, pinned by jsonparse's gitlink, so chez-curl runs the pair of
   commits jsonparse's own CI tested, on Chez 10.4.1, and a bump of jsonparse moves both.
   chez-curl runs them on its own floor, 10.4.0, through `test-examples`, in the container and
   on every CI lane. A clone needs `git submodule update --init --recursive` once, on the host.
   - `make deps` links `src/jsonparse`, `src/generated` and byte-machine's `src/byte-machine`
     into `build/scheme-libs`, and fails, naming the host command, when the one library it
     checks in each is missing. It never fetches.
   - `make check-pins` holds each checkout to its gitlink: jsonparse's in this repository,
     byte-machine's in jsonparse's, reading the parent's own toplevel first.
   - Neither is in `Akku.manifest` or `Akku.lock` until jsonparse is on an Akku archive.
4. **An example imports public libraries alone, but `json-api`,** which may also import
   `(jsonparse easy)`, and runs with `--libdirs src:build/scheme-libs`. `test-examples` holds
   both, by example, and runs each example with the library path its own run line names, so
   the line a reader copies is the one that ran.
5. **One page, `docs/headers-and-json.md`, "Headers and JSON":** setting headers on a session
   and a call, what is refused, reading a response's headers, then the JSON API example. The
   test origin's `/json` route stands in for a JSON API that insists on `Accept` and
   `Content-Type`, and `test-origin` holds it.

## Rejected

- **After 0.1.0:** the release's docs would teach no headers and no JSON.
- **Two top-level submodules,** jsonparse and byte-machine each pinned here: a bump of jsonparse
  must move byte-machine by hand, to a pair jsonparse's CI may not have run. Either way a
  recursive checkout clones one library twice: with this one, byte-machine; with the decision,
  chez-srfi, jsonparse's own, at chez-curl's commit.
- **Vendoring jsonparse's sources:** a copy that no pin or check ties to a commit.
- **A Headers section in `docs/high-level.md` and a separate JSON page:** headers are both
  levels', and the example is their use.

## Consequences

- `make test` needs jsonparse checked out: `make deps` refuses without it. CI's checkouts are
  recursive already; the Mac and a fresh clone need the recursive update once. `make build`,
  `check-seam` and a program of `(curl)` alone on `--libdirs src` need none of it.
- jsonparse is tested upstream on Chez 10.4.1, and here on 10.4.0: a bump of jsonparse must pass
  chez-curl's suites on its floor.
- jsonparse's parser is `(generated jsonparse)`, under the top-level name byte-machine gives
  every parser it generates: a program with generated parsers of its own keeps their names
  apart.
- `make dev`'s REPL imports `(jsonparse easy)` too, since its library path holds
  `build/scheme-libs`.
- jsonparse's own manifest says Akku installs every library it finds in a package, and
  jsonparse leaves `vendor/` out by an `.akkuignore`. chez-curl has none, so its package would
  hold chez-srfi's libraries, and now jsonparse's and byte-machine's. Akku and a release
  archive's exclusions are not in M8 (the M8 plan's opening), so this is carried past it.
