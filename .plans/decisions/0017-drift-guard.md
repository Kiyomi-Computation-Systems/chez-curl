# ADR-0017: The drift guard fails on any libcurl it has no row for

- **Status:** Accepted
- **Date:** 2026-10-18
- **Scope:** brief §7's drift guard, and every environment that runs `make test`
- **Settles:** what the drift guard compares, and what it does with a libcurl nobody
  recorded. The maintainer chose on 2026-10-18.
- **Related:** [ADR-0002](0002-runtime-libcurl-discovery.md), whose report it reads ·
  [ADR-0006](0006-pinned-guix-container.md), whose pin fixes the container's libcurl ·
  [the M1 plan](../2026-10-18-m1-plan.md) §9

## Context

Brief §7 asks for "a drift guard on the linked libcurl: version, feature bits and TLS backend
asserted, so an OS or package update that swaps the library or its backend fails a test
instead of a user". ADR-0002 already reports what was loaded. Nothing compares that report
with anything.

Four environments run the suites:

- the pinned Guix container (libcurl 8.20.0, GnuTLS/3.8.13);
- CI's runner, with Ubuntu 24.04's `libcurl4t64`;
- CI's floor lane, with 7.85.0 built from source;
- the maintainer's Mac, with Apple's libcurl, which changes with macOS updates.

The Mac is where drift is likeliest, and it is the environment nothing else watches.

## Decision

1. **The rows live in `tests/known-libcurls.sexp`.** Each row records one libcurl the
   suites have run against: a label, `where`, and five fields from `curl_version_info`.
   - `version`
   - `version-num`
   - `features`, the whole word
   - `ssl-version`, the whole string, so a backend's version counts too
   - `host`
2. **`test-drift` passes only when the loaded libcurl's five fields equal exactly one row's.**
   The path and its source are not compared: discovery checks those, and the container's
   profile path changes with every manifest change.
3. **A libcurl with no row fails,** wherever it runs. The failure prints the loaded
   library's row, ready to add. Adding or changing a row is a reviewed change.
4. **The file is held to its shape.** A malformed file, a duplicate row, or a row with a
   field missing or extra fails by name.
5. **The floor lane's libcurl is built the same everywhere.** `scripts/ci/build-curl.sh`
   names every optional library explicitly, enabled or disabled, so its feature word does
   not depend on what the build machine has installed.

### Rejected

- **Warn and pass on an unknown libcurl.** A new environment would never be blocked. But
  the Mac would stay unguarded until someone recorded its row, and nothing would make them.
- **Rows keyed by an environment name** that `scripts/guix-env` and CI set. An unset name
  would mean no check, which is the Mac's case again.
- **Comparing with the C oracle.** That checks that chez-curl reads its library correctly,
  which `test-native` already does. It cannot see the library change.

## Consequences

- **Bumping the Guix pin updates the container's row** in the same change. A row that no
  longer matches is how the bump shows what it changed.
- **The Mac fails `make test` until its row is recorded,** from its first run after this
  lands. That run belongs with the Mac's other pending one (ADR-0001's arm64 gate).
- **A contributor on another system sees `make test` fail** with their libcurl's row and the
  file to add it to. For a project whose suites are its own contract, that is the intent.
- **CI's rows are measured in Docker,** because CI has never run. Its first run either
  confirms them or fails, naming the row it found.

## Measured in the building (M1 slice 1, 2026-10-18)

- **The three rows,** each read by `tests/libcurl-oracle.c`:

  | Where | version | version-num | features | ssl-version | host |
  |---|---|---|---|---|---|
  | the Guix container | 8.20.0 | 529408 | 1430210445 | GnuTLS/3.8.13 | x86_64-unknown-linux-gnu |
  | Ubuntu 24.04, `libcurl4t64 8.5.0-2ubuntu10.16` | 8.5.0 | 525568 | 1438599069 | OpenSSL/3.0.13 | x86_64-pc-linux-gnu |
  | the 7.85.0 floor, `build-curl.sh` on Ubuntu 24.04 | 7.85.0 | 480512 | 1361691293 | OpenSSL/3.0.13 | x86_64-pc-linux-gnu |

  The Ubuntu row was measured twice, by the builder and in a separate check, with the same
  result.
- **The old floor build drifted with the machine.** In Docker `ubuntu:24.04` it gave
  features 1361625749 with only the prereqs installed. With ten more `-dev` packages it gave
  1975043741, adding brotli, zstd, IDN, PSL, GSASL and zlib, and LDAP, LDAPS and RTMP to its
  protocols. With only the prereqs, it also had no zlib and no HTTP/2, because
  `libcurl4-openssl-dev` only suggests their headers (`apt-cache depends`, noble). With the
  explicit flags, both machines give the same five fields and protocols.
- **What holds the floor build to its flags:**
  - `--enable-option-checking=fatal`. Otherwise `./configure` only warns about an option
    it doesn't know: a misspelt `--without-brotlii` built and did nothing.
  - **A check after the build.** `--with-zlib` and `--with-nghttp2` given bare only look,
    and a machine without the headers builds without them, silently. So `build-curl.sh`
    requires `curl-config --features` to list `libz`, `HTTP2` and `IPv6`, and to list
    nothing that is off.
  - **A protocols check too.** LDAP, RTMP and SSH show only among the protocols, never in
    the features word the guard compares, so `build-curl.sh` checks `--protocols` as well.
  - **`--enable-ipv6`.** Without it, `./configure` decides IPv6 by trying a socket while it
    runs.
- **`nm -D` cannot show a disabled API.** curl compiles stubs for an API configured out.
  Both `curl_easy_option_by_name` and `curl_easy_header` were present in every variant. The
  evidence is the load's refusal instead: in Docker, `expect-missing-api.sh` refused each
  variant as `missing-api`, naming its entry point.
- **Evidence:** the drift guard's part of the [M1 mutation log](../instrument-mutation-log.md).
  Every rule has a red run, and every mutation fails its test by name.
