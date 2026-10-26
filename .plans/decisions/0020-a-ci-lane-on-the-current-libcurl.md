# ADR-0020: A CI lane on the current libcurl, built from source

- **Status:** Accepted
- **Date:** 2026-10-26
- **Scope:** CI (`.github/workflows/ci.yml`), `scripts/ci/build-curl.sh`, and the version
  tables a libcurl needs rows in
- **Settles:** which libcurl the lane builds; the maintainer chose on 2026-10-26
- **Related:** [ADR-0003](0003-libcurl-floor-7-85.md), the floor ·
  [ADR-0016](0016-floors-have-one-source.md), the floors' one source ·
  [ADR-0017](0017-drift-guard.md), the drift guard ·
  [ADR-0019](0019-a-stalled-lookup-does-not-stall-the-engine.md), amended 2026-10-25, whose
  review found that no CI lane loads 8.20.0 or later

## Context

CI's lanes load Ubuntu's 8.5.0, with OpenSSL and with GnuTLS, and the floor's 7.85.0, built
from source. Only the Guix container runs 8.20.0, so `CURLMOPT_QUICK_EXIT`, its constant's
check, and every version table's 8.20.0 row run nowhere in CI (ADR-0019, amended 2026-10-25,
after the slice's review). The maintainer asked for a lane that builds a current curl, as the
floor lane builds 7.85.0.

Measured on 2026-10-26, in Docker `ubuntu:24.04` with `packaging/debian-prereqs.txt`
installed, under the floor's Chez:

- **curl's newest release is 8.23.0, of 2026-10-14** (`https://curl.se/info`). The container
  runs 8.20.0. Both release tarballs' detached signatures verify against Daniel Stenberg's
  key, `27EDEAF22F3ABCEB50DB9A125CC908FDB71E12C2`, the key `build-curl.sh` already names:
  8.20.0's `.tar.xz` has sha256 `63fe2dc1…b896`, 8.23.0's `8dadd7d2…e6c5`.
- **curl 8 needs a configure line of its own.** 8.20.0's `./configure` has no `librtmp`,
  `wolfssh`, `hyper` or `msh3` options, which the floor's line names, and under
  `--enable-option-checking=fatal` each stops it. It has two new options that look for a
  library: `libuv`, and Apple's IDN. 8.23.0 drops `smb` and `tls-srp` too, which the line
  does not name.
- **With that line, vanilla 8.20.0 with OpenSSL passed every suite but `test-drift`,** which
  printed the row it needs: 22 of 23. Its other version tables already hold 8.20.0 rows,
  from the container, and its answers agreed with them; `test-transfer-tls` takes it as a
  libcurl that reads neither `SSL_CERT_FILE` nor `SSL_CERT_DIR`, as Guix's patch does.
- **8.23.0 failed four suites, and `test-engine` hung past its 300 s bound.**
  - `test-drift`, `test-url`, `test-transfer` and `test-variadic` have no 8.23.0 row.
  - Five of `test-transfer`'s varying scenarios answer otherwise: a 100 KB and a 1 MB header
    and 100,000 headers are refused with 100, a bad status code is a 200, and conflicting
    `Content-Length` headers are refused with 8.
  - One answer every recorded libcurl shared changed: the error buffer's text for a NUL in a
    header.
  - Two transfers in `test-engine` failed with `CURLE_SEND_ERROR`, "Failed sending data to
    the peer", on caller threads that do not catch it, and the suite hung waiting for them.

## Decision

1. **The lane builds 8.20.0,** vanilla, with OpenSSL: the version the container runs, so the
   current libcurl's every row is one the container already measures, and a build without
   Guix's patches checks them beside the patched one. 8.23.0 is a slice of its own, below.
2. **`build-curl.sh --current` builds it.** The script pins `current_version`, beside the
   floor, with its sha256, and builds it with its own configure line, read against its own
   `./configure --help`. With `--current` it reads no floors file, and no argument or
   environment variable gives the version: the flag chooses between the two pinned builds and
   changes neither. Without it, the floor's build is as it was. The current version is no
   floor, so it is not in `packaging/floors.sexp`, and ADR-0016 does not govern it.
3. **The `current` job runs `make build` and `make test`** against the install, with
   `CHEZ_CURL_LIBCURL` and `C_INCLUDE_PATH` naming it, under the runner's own Node. It fails
   unless `make build` loaded the version the install's own `curl-config` reports, so the
   workflow names no version. Its cache is keyed by `build-curl.sh`, which holds the version,
   and by the package list and the runner image.
4. **`tests/known-libcurls.sexp` gains the build's row,** as `test-drift` printed it.
5. **`test-check-floors` holds `--current`:** it reaches the download of the pinned version
   whatever the floors file holds, or with none; the environment cannot move it; and it takes
   the same usage and prefix rules.

### Rejected

- **8.23.0 now.** It needs rows in five tables, a shared answer moved to version rows, and
  the hang understood before the lane could pass.
- **Both now,** for the same reason, and one more job.
- **The current version in `packaging/floors.sexp`,** or a file of its own with a reader
  script. It is no floor, `check-floors` holds that file to three keys, and the build script,
  which also pins its sum, is one place a change shows.

## Consequences

- **CI shows `CURLMOPT_QUICK_EXIT`,** its constant's check, and the stall checks' 8.20.0
  rows, once CI runs at all: its jobs still stop at the billing limit.
- **Raising the current version is a reviewed change:** a verified sum, a configure line read
  again, and the rows `make test` prints for every version table.
- **Owed, a slice of its own: 8.23.0.** Its rows, the shared answer that moves, and the hang:
  two caller threads in `test-engine` that let a transfer's raise escape, so the suite waits
  for good rather than failing by name. That last is a defect in the suite whatever the
  libcurl, and a check that hangs names no test.
- **The workflow check does not read the current version.** `check-floors` keeps the floors'
  versions out of the workflows; the current lane states none, and nothing passes one to
  `--current`, which takes no value.
